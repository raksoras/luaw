--[[
Copyright (c) 2015 raksoras

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]

local constants = require('luaw_constants')
local luaw_tcp_lib = require('luaw_tcp')

local TS_BLOCKED_EVENT = constants.TS_BLOCKED_EVENT
local TS_RUNNABLE = constants.TS_RUNNABLE

local CONN_BUFFER_SIZE = constants.CONN_BUFFER_SIZE

local EOF = constants.EOF
local CRLF = constants.CRLF

local MULTIPART_BEGIN = constants.MULTIPART_BEGIN
local PART_BEGIN = constants.PART_BEGIN
local PART_DATA = constants.PART_DATA
local PART_END = constants.PART_END
local MULTIPART_END = constants.MULTIPART_END

local http_status_codes = {
    [100] = "Continue",
    [101] = "Switching Protocols",
    [200] = "OK",
    [201] = "Created",
    [202] = "Accepted",
    [203] = "Non-Authoritative Information",
    [204] = "No Content",
    [205] = "Reset Content",
    [206] = "Partial Content",
    [300] = "Multiple Choices",
    [301] = "Moved Permanently",
    [302] = "Found",
    [303] = "See Other",
    [304] = "Not Modified",
    [305] = "Use Proxy",
    [307] = "Temporary Redirect",
    [400] = "Bad Request",
    [401] = "Unauthorized",
    [402] = "Payment Required",
    [403] = "Forbidden",
    [404] = "Not Found",
    [405] = "Method Not Allowed",
    [406] = "Not Acceptable",
    [407] = "Proxy Authentication Required",
    [408] = "Request Timeout",
    [409] = "Conflict",
    [410] = "Gone",
    [411] = "Length Required",
    [412] = "Precondition Failed",
    [413] = "Request Entity Too Large",
    [414] = "Request-URI Too Long",
    [416] = "Requested Range Not Satisfiable",
    [417] = "Expectation Failed",
    [500] = "Internal Server Error",
    [501] = "Not Implemented",
    [502] = "Bad Gateway",
    [503] = "Service Unavailable",
    [504] = "Gateway Timeout",
    [505] = "HTTP Version Not Supported"
}

setmetatable(http_status_codes, {
    __index = function(status)
        return "User Defined Status"
    end
})

-- write buffer implementation

local function clearArrayPart(t)
    local len = #t
    for i=1,len do
        t[i] = nil
    end
end

local function reset(buffer)
    clearArrayPart(buffer)
    buffer.len = 0
end

local function concat(buffer)
    return table.concat(buffer)
end

local function append(buffer, str)
    local len = buffer.len
    if (str) then
        table.insert(buffer, str)
        len = len + #str
        buffer.len = len
    end
    return len
end

local function newBuffer()
    return {
        len = 0,
        reset = reset,
        concat = concat,
        append = append
    }
end


function luaw_http_lib.storeHttpParam(params, name , value)
	oldValue = params[name]
    if (oldValue) then
		-- handle multi-valued param names
        if (type(oldValue) == 'table') then
        	table.insert(oldValue, value)
        else
        	-- single param value already stored against the same param name
			-- convert it to table and store multiple values in it
			params[name] = {oldValue, value}
		end
	else
		params[name] = value
	end
end

local parserMT = getmetatable(luaw_http_lib.newHttpRequestParser())

--[[ HTTP parser we use can invoke callback for the same HTTP field (status, URL, header
name/value etc.) multiple times, each time passing only few characters for the current
ongoing field. This can happen because we are reading HTTP request or response body in
multiple chuncks - either of a fixed byte buffer size of by new lines. For this reason we
"accumulate" http header name and value in a hidden request table fields (_acc_header_name_
/_acc_header_value_) and then store full header value against full header name when the
parser issues callback for a next HTTP field. Other fields like URL, status etc. are
accumulated by concatenating them "in place".
]]


local function accumulateChunkedValue(req, name, chunk)
	local accValue = rawget(req, name)
	if accValue then
		rawset(req, name, accValue .. chunk)
	else
		rawset(req, name, chunk)
	end
end

local function addHeader(req, hName, hValue)
	if (hName and hValue) then
		local headers = req.headers
		local currValues = headers[hName]

        if currValues then
            -- handle multi-valued headers
            if (type(currValues) == 'table') then
                table.insert(currValues, hValue)
            else
                -- single string header value already stored against the same header name
                -- convert it to table and store multiple values in it
                headers[hName] = {currValues, hValue}
            end
        else
            headers[hName] = hValue
        end
        return true
	end
	return false
end

local function handleAccHttpHeader(req)
	local hName = rawget(req, '_acc_header_name_')
	local hValue = rawget(req, '_acc_header_value_')
	local added = addHeader(req, hName, hValue)
	if (added) then
        rawset(req, '_acc_header_name_', nil)
        rawset(req, '_acc_header_value_', nil)
	end
end

local function handleKeepAlive(req, keepAlive)
    if not keepAlive then
        req.headers['Connection'] = 'close'
        req.EOF = true
    end
end

local function onNone(req, cbType)
end

local function onMesgBegin(req, cbtype, remaining)
    req:reset()
end

local function onStatus(req, cbtype, remaining ,status)
	accumulateChunkedValue(req, 'statusMesg', status)
end

local function onURL(req, cbtype, remaining, url)
	accumulateChunkedValue(req, 'url', url)
end

local function onHeaderName(req, cbtype, remaining, hName)
	handleAccHttpHeader(req)
    accumulateChunkedValue(req, '_acc_header_name_', hName)
end

local function onHeaderValue(req, cbtype, remaining, hValue)
	if not hValue then hValue = '' end -- empty header value
	accumulateChunkedValue(req, '_acc_header_value_', hValue)
end

local function onHeadersComplete(req, cbtype, remaining, keepAlive, httpMajor, httpMinor, method, status)
	handleAccHttpHeader(req)
	handleKeepAlive(req, keepAlive)
	req.major_version = httpMajor
	req.minor_version = httpMinor
    req.method = method
    req.status = status

    -- parse URL
    local url = req.url
    local parsedURL
    if url then
        local method = req.method
        parsedURL = luaw_http_lib.parseURL(url, ((method) and (string.upper(method) == "CONNECT")))
    else
        parsedURL = {}
    end
    req.parsedURL = parsedURL

    -- GET query params
    local params = {}
    local queryString = parsedURL.queryString
    if queryString then
        assert(luaw_http_lib:urlDecode(queryString, params))
    end
    req.params = params

    req.luaw_headers_done = true
end

local function onBody(req, cbtype, remaining, chunk)
    req.bodyParts:append(chunk)
end

local function onMesgComplete(req, cbtype, remaining, keepAlive)
	-- for the rare boundary case of chunked transfer encoding, where headers may continue
	-- after the last body chunk
	handleAccHttpHeader(req)
	handleKeepAlive(req, keepAlive)
	local luaw_parser = req.luaw_parser
    if (luaw_parser) then
        luaw_parser:initHttpParser()
    end

    -- store body
    local bodyParts = req.bodyParts
    req.body = bodyParts:concat()
    bodyParts:reset()

    -- POST form params
    local params = req.params
    local contentType = req.headers['Content-Type']
    if ((contentType) and (contentType:lower() == 'application/x-www-form-urlencoded')) then
        assert(luaw_http_lib:urlDecode(req.body, params))
    end

    req.luaw_mesg_done = true
end

-- Order is important and must match C enum http_parser_cb_type
local http_callbacks_lua = {
    onNone,
    onMesgBegin,
    onStatus,
    onURL,
    onHeaderName,
    onHeaderValue,
    onHeadersComplete,
    onBody,
    onMesgComplete
}

local function parseHttpFragment(req, conn, parser, content, offset)
    -- matched against most number of return results possible. Actual variable names
    -- are meaningless without the context of correct callback, misleading even!
    local cbtype, offset, keepAlive, httpMajor, httpMinor, method, status = parser:parseHttp(content, offset)
    if (not cbtype) then
        conn:close()
        return error(offset) -- offset carries error message in this case
    end

    local callback = http_callbacks_lua[cbtype]
    if (not callback) then
        conn:close()
        return error("Invalid HTTP parser callback# "..tostring(cbtype).." requested")
    end

    callback(req, cbtype, remaining, keepAlive, httpMajor, httpMinor, method, status)
    return  cbtype, offset
end

local function hasContent(content, offset)
    return (content)and(offset)and(offset < #content)
end

local function readAndParse(req)
    local conn = req.luaw_conn
    local parser = req.luaw_parser
    local content = req.luaw_read_content
    local offset = req.luaw_read_offset
    local httpcb, status

    if (not hasContent(content, offset)) then
        -- read new content from socket
        status, content = conn:read(req.readTimeout)
        if (not status) then
            if (content == 'EOF') then
                req:addHeader('Connection', 'close')
                req.luaw_read_content = nil
                req.luaw_read_offset = nil
                req.luaw_headers_done = true
                req.luaw_mesg_done = true
                req.EOF = true
                return
            else
                return error(content)
            end
        end
        offset = 0 -- offset is for C, therefore zero based
    end

    httpcb, offset = parseHttpFragment(req, conn, parser, content, offset)

    if (hasContent(content,offset)) then
        -- store back remaining content in request object for next HTTP request parsing
        req.luaw_read_content = content
        req.luaw_read_offset = offset
    else
        req.luaw_read_content = nil
        req.luaw_read_offset = nil
    end
end

local function consumeTill(input, search, offset)
    local start, stop = string.find(input, search, offset, true)
    if (start and stop) then
        return stop+1, string.sub(input, offset, start-1)
    end
end

local function getMultipartBoundary(req)
    local header = req.headers['Content-Type']
    if (header) then
        local offset, contentType = consumeTill(header, ";", 1)
        if (contentType == "multipart/form-data") then
            local boundary
            offset, boundary = consumeTill(header, "=", offset)
            if ((boundary)and(string.find(boundary, "boundary", 1, true))) then
                return '--'..string.sub(header, offset)
            end
        end
    end
end

local function isMultipart(req)
    if (req.luaw_multipart_boundary) then
        return true
    end

    local boundary = getMultipartBoundary(req)
    if (boundary) then
        req.luaw_multipart_boundary = boundary
        req.luaw_multipart_end = boundary .. '--'
        return true
    end
end

local function isLuaPackMesg(req)
    local contentType = req.headers['Content-Type']
    if ('application/luapack' == contentType) then
        return true
    end
end

local function readFull(req)
    -- first parse till headers are done
    while (not req.luaw_headers_done) do
        req:readAndParse()
    end

    if ((isMultipart(req))or(isLuaPackMesg(req))) then
        -- multipart (file upload) HTTP requests and LuaPack requests are forced to be streaming to conserve memory
        return
    end

    while (not req.luaw_mesg_done) do
        req:readAndParse()
    end
end

local function consumeBodyChunkParsed(req)
    local bodyChunk = req.body
    if (bodyChunk) then
        req.body = nil
    else
        local bodyParts = req.bodyParts
        if (bodyParts.len > 0) then
            bodyChunk = bodyParts:concat()
            bodyParts:reset()
        end
    end
    return bodyChunk
end

local function bufferedConsume(req, search, content, offset)
    assert(search, "search pattern cannot be nil")

    while (true) do
        if ((content)and(#content > offset)) then
            local matchPos, matchStr  = consumeTill(content, search, offset)
            if (matchPos) then
                -- found match
                if (matchPos < #content) then
                    -- there is content remaining
                    return matchStr, content, matchPos
                end
                -- content fully consumed
                return matchStr, nil, nil
            end

            if (offset > 1) then
                content = string.sub(content, offset)
                offset = 1
            end
        end

        -- match not found, read more
        req:readAndParse()
        if (req.luaw_mesg_done) then
            error("premature HTTP message end")
        end

        local readStr = req:consumeBodyChunkParsed()
        if (readStr) then
            if (content) then
                content = content..readStr
            else
                content = readStr
                offset = 1
            end
        end
    end
end

local function saveState(req, content, offset)
    req.luaw_multipart_content = content
    req.luaw_multipart_offset = offset
end

function fetchNextPart(req, state)
    local content = req.luaw_multipart_content
    local offset = req.luaw_multipart_offset or 1
    local boundary = req.luaw_multipart_boundary
    local matchStr

    if (state == MULTIPART_BEGIN) then
        -- read beginning boundary
        matchedStr, content, offset = bufferedConsume(req, CRLF, content, offset)
        assert(matchedStr == boundary, "Missing multi-part boundary at the beginning of the part")
        state = PART_END
    end

    if (state == PART_END) then
        -- read "Content-Disposition" line
        matchedStr, content, offset = bufferedConsume(req, ": ", content, offset)
        assert(matchedStr == 'Content-Disposition',"Missing 'Content-Disposition' header")

        matchedStr, content, offset = bufferedConsume(req, "; ", content, offset)
        assert(string.find(matchedStr, 'form-data', 1, true), "Wrong Content-Disposition")

        matchedStr, content, offset = bufferedConsume(req, '"', content, offset)
        assert(string.find(matchedStr, "name", 1, true), "form field name missing")

        local fieldName
        fieldName, content, offset = bufferedConsume(req, '"', content, offset)
        assert(#fieldName > 0, "form field name missing")

        matchedStr, content, offset = bufferedConsume(req, CRLF, content, offset)
        local _, filenamePos = string.find(matchedStr, 'filename="', 1, true)
        local fileName
        if (filenamePos) then
            fileName = string.sub(matchedStr, filenamePos+1, #matchedStr-1)
        end

        local contentType
        if (fileName) then
            -- read "Content-Type" line
            matchedStr, content, offset = bufferedConsume(req, ": ", content, offset)
            assert(matchedStr == 'Content-Type', "Missing 'Content-Type' header")

            contentType, content, offset = bufferedConsume(req, CRLF, content, offset)
            assert(#contentType, "Content-Type value missing")
        end

        -- read next blank line
        matchedStr, content, offset = bufferedConsume(req, CRLF, content, offset)
        assert(#matchedStr == 0, "Missing line separating content headers and actual content")

        saveState(req, content, offset)
        return PART_BEGIN, fieldName, fileName, contentType
    end

    while ((state == PART_BEGIN)or(state == PART_DATA)) do
        local matchedStr, content, offset = bufferedConsume(req, CRLF, content, offset)
        if (matchedStr) then
            if (matchedStr == boundary) then
                saveState(req, content, offset)
                return PART_END
            end

            local lastBoundary = req.luaw_multipart_end
            if (matchedStr == lastBoundary) then
                saveState(req, content, offset)
                return MULTIPART_END
            end

            saveState(req, content, offset)
            return PART_DATA, matchedStr
        else
            local content = req.luaw_multipart_content
            local offset = req.luaw_consumed_till or 0

            if ((content)and(#content-offset) > #boundary+3) then
                saveState(req, nil, 1)
                return PART_DATA, content
            end
        end
    end
end

local function multiPartIterator(req)
    if (isMultipart(req)) then
        return fetchNextPart, req, MULTIPART_BEGIN
    end
end

local function shouldCloseConnection(req)
    if req and req.EOF then
        return true
    end
end

local function  toURLSafeChar(ch)
    if (ch == " ") then return "+" end
    return string.format("%%%02X", string.byte(ch))
end

local function urlEncode(str)
    str = string.gsub(str, "([^a-zA-Z0-9%.%*%-_])", toURLSafeChar)
    return str
end

local function urlEncodeParams(params)
    if params then
        local encodedParams = {}
        local contentLength = 0

        for key, val in pairs(params) do
            local ueKey = urlEncode(key)
            table.insert(encodedParams, ueKey)
            contentLength = contentLength + #ueKey

            table.insert(encodedParams, "=")
            contentLength = contentLength + 1

            local ueVal = urlEncode(val)
            table.insert(encodedParams, ueVal)
            contentLength = contentLength + #ueVal

            table.insert(encodedParams, "&")
            contentLength = contentLength + 1
        end

        if (#encodedParams > 0) then
            table.remove(encodedParams) -- remove the last extra "&"
            contentLength = contentLength - 1
            return encodedParams, contentLength
        end
    end

    return nil, 0
end

function buildURL(req)
    if (req.method == 'GET') then
        local encodedParams = urlEncodeParams(req.params)
        if encodedParams then
            table.insert(encodedParams, 1, "?")
            table.insert(encodedParams, 1, req.url)
            return table.concat(encodedParams)
        end
    end
    return req.url
end

local function setStatus(resp, status)
    resp.status = status
    resp.statusMesg = http_status_codes[status]
end

local function getStatus(resp)
    return resp.status
end

local function getBody(resp)
    return resp.body
end

local function firstResponseLine(resp)
    local line = {"HTTP/", resp.major_version, ".", resp.minor_version,
        " ", resp.status, " ", resp.statusMesg, CRLF}
    return table.concat(line)
end

local function firstRequestLine(req)
    local line = {req.method, " ", req:buildURL(), " HTTP/", req.major_version,
         ".", req.minor_version, CRLF}
    return table.concat(line)
end

local function sendBuffer(buffer, conn, writeTimeout, isChunked)
	local chunk = table.concat(buffer)
	buffer:reset()
    if (isChunked) then
        chunk = string.format("%x\r\n", #chunk)..chunk..CRLF
    end
    conn:write(chunk, writeTimeout)
end

local function bufferHeader(buffer, name, value)
    buffer:append(tostring(name))
    buffer:append(": ")
    buffer:append(tostring(value))
    buffer:append(CRLF)
end

local function bufferHeaders(headers, buffer)
    if (headers) then
        for name,value in pairs(headers) do
            if (type(value) == 'table') then
                for i,v in ipairs(value) do
                    bufferHeader(buffer, name, v)
                end
            else
                bufferHeader(buffer, name, value)
            end
            headers[name] = nil
        end
    end
    buffer:append(CRLF)
end

local function startStreaming(resp)
    resp.luaw_is_chunked = true
    resp:addHeader('Transfer-Encoding', 'chunked')

    local headers = resp.headers
    local conn = resp.luaw_conn
    local writeTimeout = resp.writeTimeout

    -- use separate buffer from "bodyParts" to serialize headers
    local headersBuffer = newBuffer()
    headersBuffer:append(resp:firstLine())
    bufferHeaders(headers, headersBuffer)

    -- flush up to HTTP headers end without chunked encoding before actual body starts
    sendBuffer(headersBuffer, conn, writeTimeout, false)
end

local function appendBody(resp, bodyPart)
    if not bodyPart then
        return
    end

    local bodyBuffer = resp.bodyParts
    local len = bodyBuffer:append(bodyPart)

    if ((resp.luaw_is_chunked)and(len >= CONN_BUFFER_SIZE)) then
        local conn = resp.luaw_conn
        local writeTimeout = resp.writeTimeout
        sendBuffer(bodyBuffer, conn, writeTimeout, true)
    end
end

local function writeFullBody(resp)
    local conn = resp.luaw_conn
    local writeTimeout = resp.writeTimeout
    local bodyBuffer = resp.bodyParts

    if (resp.method == 'POST') then
        local encodedParams, contentLength = urlEncodeParams(resp.params)
        if encodedParams then
            resp:addHeader('Content-Type', 'application/x-www-form-urlencoded')
            bodyBuffer:append(encodedParams)
        end
    end

    resp:addHeader('Content-Length', bodyBuffer.len)

    -- first write up to HTTP headers end
    local headersBuffer = newBuffer()
    headersBuffer:append(resp:firstLine())
    bufferHeaders(resp.headers, headersBuffer)
    sendBuffer(headersBuffer, conn, writeTimeout, false)

    -- now write body
    sendBuffer(bodyBuffer, conn, writeTimeout, false)
end

local function endStreaming(resp)
    local conn = resp.luaw_conn
    local writeTimeout = resp.writeTimeout
    local bodyBuffer = resp.bodyParts

    -- flush whatever is remaining in write buffer
    sendBuffer(bodyBuffer, conn, writeTimeout, true)

    -- add last chunk encoding trailer
    conn:write("0\r\n\r\n", writeTimeout)
end

local function flush(resp)
    if resp.luaw_is_chunked then
        endStreaming(resp)
    else
        writeFullBody(resp)
    end
end

local function close(req)
    local conn = req.luaw_conn;
    if conn then
        conn:close()
        req.luaw_conn = nil
    end
end

local function reset(req)
    req.headers = {}
    req["_acc_header_name_"] = nil
    req["_acc_header_value_"] = nil
    req.url = nil
    req.bodyParts:reset()
    req.body = nil
    req.luaw_mesg_done = nil
    req.luaw_headers_done = nil
    req.params = nil
    req.parsedURL = nil
    req.status = nil
    req.statusMesg = nil
end

luaw_http_lib.newServerHttpRequest = function(conn)
	local req = {
	    luaw_mesg_type = 'sreq',
	    luaw_conn = conn,
	    headers = {},
		bodyParts = newBuffer(),
	    luaw_parser = luaw_http_lib:newHttpRequestParser(),
	    addHeader = addHeader,
	    shouldCloseConnection = shouldCloseConnection,
	    isComplete = isComplete,
	    readAndParse = readAndParse,
	    readFull = readFull,
	    isMultipart = isMultipart,
	    multiPartIterator = multiPartIterator,
	    getBody = getBody,
	    reset = reset,
	    consumeBodyChunkParsed = consumeBodyChunkParsed,
	    close = close
	}
    return req;
end

luaw_http_lib.newServerHttpResponse = function(conn)
    local resp = {
        luaw_mesg_type = 'sresp',
        luaw_conn = conn,
        major_version = 1,
        minor_version = 1,
        contentLength = 0,
        headers = {},
        bodyParts = newBuffer(),
        addHeader = addHeader,
        shouldCloseConnection = shouldCloseConnection,
        setStatus = setStatus,
        firstLine = firstResponseLine,
        startStreaming = startStreaming,
        appendBody = appendBody,
        flush = flush,
        reset = reset,
        close = close
    }
    return resp;
end

local function newClientHttpResponse(conn)
	local resp = {
	    luaw_mesg_type = 'cresp',
	    luaw_conn = conn,
	    headers = {},
		bodyParts = newBuffer(),
	    luaw_parser = luaw_http_lib:newHttpResponseParser(),
	    addHeader = addHeader,
	    shouldCloseConnection = shouldCloseConnection,
	    readAndParse = readAndParse,
	    getBody = getBody,
	    getStatus = getStatus,
	    readFull = readFull,
	    consumeBodyChunkParsed = consumeBodyChunkParsed,
	    reset = reset,
	    close = close
	}
	return resp;
end

local function connect(req)
    local conn = assert(luaw_tcp_lib.connect(req.hostIP, req.hostName, req.port, req.connectTimeout))
    return conn
end

local function connectReq(req)
    conn = connect(req)
    conn:startReading()
    req.luaw_conn = conn
    local resp = newClientHttpResponse(conn)
    resp.readTimeout = req.readTimeout
    resp.writeTimeout = req.writeTimeout
    return resp
end

local function execute(req)
    local resp = req:connect()
    req:flush()
    resp:readFull()
    if resp:shouldCloseConnection() then
        resp:close()
    end
    return resp
end


luaw_http_lib.newClientHttpRequest = function()
    local req = {
        luaw_mesg_type = 'creq',
        port = 80,
        major_version = 1,
        minor_version = 1,
        method = 'GET',
        contentLength = 0,
        headers = {},
		bodyParts = newBuffer(),
        addHeader = addHeader,
        connect = connectReq,
        execute = execute,
        shouldCloseConnection = shouldCloseConnection,
        buildURL = buildURL,
        firstLine = firstRequestLine,
        startStreaming = startStreaming,
        appendBody = appendBody,
        flush = flush,
        reset = reset,
        close = close
    }
	return req;
end


return luaw_http_lib
