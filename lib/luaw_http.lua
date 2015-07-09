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
local luaw_util_lib = require('luaw_utils')

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

local function clear(wbuffer)
    clearArrayPart(wbuffer)
    wbuffer.len = 0
end

local function concat(wbuffer)
    return table.concat(wbuffer)
end

local function append(wbuffer, str)
    local len = wbuffer.len
    if (str) then
        table.insert(wbuffer, str)
        len = len + #str
        wbuffer.len = len
    end
    return len
end

local function newWriteBuffer()
    return {
        len = 0,
        clear = clear,
        concat = concat,
        append = append
    }
end


--local parserMT = getmetatable(luaw_http_lib.newHttpRequestParser())

-- Must match C enum http_parser_cb_type
local HTTP_NONE = 1
local HTTP_MESG_BEGIN = 2
local HTTP_STATUS = 3
local HTTP_URL = 4
local HTTP_HEADER_NAME = 5
local HTTP_HEADER_VALUE = 6
local HTTP_HEADERS_DONE = 7
local HTTP_BODY = 8
local HTTP_MESG_DONE = 9


local function addNVPair(dict, name, value)
    local currValue = dict[name]
    if currValue then
        -- handle multi-valued headers
        if (type(currValue) == 'table') then
            table.insert(currValue, value)
        else
            dict[name] = {currValue, value}
        end
    else
        dict[name] = value
    end
end

local function addHeader(req, headerName, headerValue)
    addNVPair(req.headers, headerName, headerValue)
end


local function urlDecode(str)
  return (str:gsub('+', ' '):gsub("%%(%x%x)", function(xx) return string.char(tonumber(xx, 16)) end))
end

function parseUrlParams(self, str, params)
    params = params or {}
    if (str) then
        for pair in str:gmatch"[^&]+" do
            local key, val = pair:match"([^=]+)=(.*)"
            if (key and val) then 
                addNVPair(params, urlDecode(key), urlDecode(val))
            else
                error("wrong encoding")
            end
        end    
    end
  return params
end

luaw_http_lib.parseUrlParams = parseUrlParams

local function parseURL(req, url)
    local parsedURL
    local params
    
    if url then
        local method = req.method
        parsedURL = luaw_http_lib.parseURL(url, ((method) and (string.upper(method) == "CONNECT")))        
        local queryString = parsedURL.queryString
        if queryString then
            params = parseUrlParams(queryString)
        end
    end
    
    req.parsedURL = parsedURL or {}
    req.params = params or {}
end

local function parseBody(req, bodyParts)
    -- store body
    local body = table.concat(bodyParts)
    req.body = body

    -- POST form params
    local contentType = req.headers['Content-Type']
    if ((contentType) and (contentType:lower() == 'application/x-www-form-urlencoded')) then
        assert(parseUrlParams(body, req.params))
    end
    
    return body
end

local function handleKeepAlive(parser, req)
    if (not parser:shouldKeepAlive()) then
        req.headers['Connection'] = 'close'
        req.EOF = true
    end
end    

local function safeAppend(v1, v2)
    if (v1) then
        if (v2) then
            return v1..v2
        end
        return v1
    end
    return v2
end

-- returns token, remaining
local function nextToken(input, searchstr)
    if (input) then
        local start, stop = input:find(searchstr, 1, true)
        if (start and stop) then
            return input:sub(1, start-1), input:sub(stop+1)
        end
    end
    return nil, input
end

local function getMultipartBoundary(req)
    local header = req.headers['Content-Type']
    if (header) then
        local boundary = string.match(header, 'multipart/form%-data; boundary=(.*)')
        if (boundary) then
            return '--'..boundary
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

local function streamBody(req, streamParse)
    return streamParse or isLuaPackMesg(req) or isMultipart(req)
end

local function parseHttpRequest(req, streamParse)    
    local conn = req.luaw_conn
    local parser = req.luaw_parser    
    local headers = req.headers
    local buffer = req.rbuffer
    
    local statusMesg, url, headerName, headerValue, bodyParts 
    
    while (not req.END) do        
        
        if (buffer:remainingLength() <= 0) then
            -- read new content from the request socket 
            buffer:clear()
            local status, err = conn:read(buffer, req.readTimeout)
            
            if (not status) then
                if (err == 'EOF') then
                    headers['Connection'] = 'close'
                    req.END = true
                    req.EOF = true
                    return
                else
                    return error(err)
                end
            end
        end
        
        -- parse content present in read buffer
        local cbtype = parser:parseHttp(buffer)
        
        if (cbtype == HTTP_MESG_BEGIN) then
            req:reset()
            headers = req.headers
            
        elseif (cbtype == HTTP_STATUS) then
            statusMesg = safeAppend(statusMesg, parser:getParsedChunk())
            
        elseif (cbtype == HTTP_URL) then
            url = safeAppend(url, parser:getParsedChunk())
        
        elseif (cbtype == HTTP_HEADER_NAME) then
            if (headerName and headerValue) then
                addNVPair(headers, headerName, headerValue)
                headerName = nil
            end
            headerValue = nil
            headerName = safeAppend(headerName, parser:getParsedChunk())
            
        elseif (cbtype == HTTP_HEADER_VALUE) then
            headerValue = safeAppend(headerValue, parser:getParsedChunk())
        
        elseif (cbtype == HTTP_HEADERS_DONE) then
            if (headerName and headerValue) then
                addNVPair(headers, headerName, headerValue)
            end
            headerName = nil
            headerValue = nil
            
            handleKeepAlive(parser, req)
            req.major_version = parser:getHttpMajorVersion()
            req.minor_version = parser:getHttpMinorVersion()
            if (req.luaw_mesg_type == 'sreq') then
                req.method = parser:getReqMethod()
                parseURL(req, url)
            else
                req.status = parser:getRespStatus()
                req.statusMesg = statusMesg
            end
                       
            if (streamBody(req, streamParse)) then
                return
            end
        
        elseif (cbtype == HTTP_BODY) then
            if (streamBody(req, streamParse)) then
                return parser:getParsedChunk()
            end
            bodyParts = bodyParts or {}
            table.insert(bodyParts, parser:getParsedChunk())
        
        elseif (cbtype == HTTP_MESG_DONE) then
            -- for the rare boundary case of chunked transfer encoding, 
            -- where headers may continue after the last body chunk
            if (headerName and headerValue) then
                addNVPair(headers, headerName, headerValue)
            end
            headerName = nil
            headerValue = nil
            
            local body
            if (bodyParts) then
                body = parseBody(req, bodyParts)
            end
            req.END = true
            handleKeepAlive(parser, req)
            -- reset parser for next request in case this connection is a persistent/pipelined HTTP connection
            parser:initHttpParser()    
            
            return body
    
        elseif  (cbtype == HTTP_NONE) then
            -- ignore
        
        else
            conn:close()
            return error("Invalid HTTP parser callback# "..tostring(cbtype).." requested. Error: "..remaining)
        end
    end 
    return req.body
end

local function patternRead(content, searchstr, req)
    local buff = content
    while ((not req.END) and
           ((not content)or(not content:find(searchstr, 1, true)))) do
        content = parseHttpRequest(req, true)
        buff = safeAppend(buff, content)
    end
    return buff
end

local function lengthRead(content, len, req)
    local buff = content
    while ((not req.END) and
           ((not buff)or(#buff < len))) do
        content = parseHttpRequest(req, true)
        buff = safeAppend(buff, content)
    end
    return buff
end

function fetchNextPart(req, state)
    local boundary = req.luaw_multipart_boundary
    local content = req.luaw_multipart_content
    local line
    
    if (state == MULTIPART_BEGIN) then
        -- read beginning boundary
        content = patternRead(content, CRLF, req)
        line, content = nextToken(content, CRLF)
        assert(line == boundary, "Missing multi-part boundary at the beginning of the part")
        state = PART_END
    end

    if (state == PART_END) then
        local fieldName, fileName, contentType
        
        -- read "Content-Disposition" line
        content = patternRead(content, CRLF, req)
        line, content = nextToken(content, CRLF)
        assert(line, "Missing Content-Disposition")
        
        fieldName, fileName = string.match(line, 'Content%-Disposition: form%-data; name="(.-)"; filename="(.-)"')
        if (not fieldName) then
            fieldName = string.match(line, 'Content%-Disposition: form%-data; name="(.-)"')
        end
        assert(fieldName, "form field name missing")
        
        if (fileName) then
            -- read "Content-Type" line
            content = patternRead(content, CRLF, req)
            line, content = nextToken(content, CRLF)
            assert(line, "Missing Content-Type")    
            
            contentType = string.match(line, 'Content%-Type: (.*)')
            assert(contentType, "Missing Content-Type value")
        end

        -- read next blank line
        content = patternRead(content, CRLF, req)
        line, content = nextToken(content, CRLF)

        -- save remaining content before returning from iterator
        req.luaw_multipart_content = content 
        return PART_BEGIN, fieldName, fileName, contentType
    end

    if ((state == PART_BEGIN)or(state == PART_DATA)) then   
        local endBoundary = req.luaw_multipart_end
        
        -- double the size of max possible boundary length: endBoundary + CRLF
        content = lengthRead(content, 2*(#endBoundary + 2), req)        
        if ((not content)and(req.END)) then
            return MULTIPART_END
        end

        line, content = nextToken(content, CRLF)
        
        if (not line) then
            req.luaw_multipart_content = nil
            return PART_DATA, content
        end
    
        if (line == boundary) then
            req.luaw_multipart_content = content
            return PART_END
        end
        
        if (line == endBoundary) then
            req.luaw_multipart_content = nil
            return MULTIPART_END
        end
                
        req.luaw_multipart_content = content
        return PART_DATA, line
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
        local len = 0

        for key, val in pairs(params) do
            local ueKey = urlEncode(key)
            table.insert(encodedParams, ueKey)
            table.insert(encodedParams, "=")
            local ueVal = urlEncode(val)
            table.insert(encodedParams, ueVal)
            table.insert(encodedParams, "&")
            len = len + #ueKey + #ueVal + 2 -- +2 for '&' and '='
        end

        if (#encodedParams > 0) then
            table.remove(encodedParams) -- remove the last extra "&"
            len = len - 1
            return encodedParams, len
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

local function sendBuffer(wbuffer, conn, writeTimeout, isChunked)
	local chunk = table.concat(wbuffer)
	wbuffer:clear()
    if (isChunked) then
        chunk = string.format("%x\r\n", #chunk)..chunk..CRLF
    end
    conn:write(chunk, writeTimeout)
end

local function bufferHeader(wbuffer, name, value)
    wbuffer:append(tostring(name))
    wbuffer:append(": ")
    wbuffer:append(tostring(value))
    wbuffer:append(CRLF)
end

local function bufferHeaders(headers, wbuffer)
    if (headers) then
        for name,value in pairs(headers) do
            if (type(value) == 'table') then
                for i,v in ipairs(value) do
                    bufferHeader(wbuffer, name, v)
                end
            else
                bufferHeader(wbuffer, name, value)
            end
            headers[name] = nil
        end
    end
    wbuffer:append(CRLF)
end

local function startStreaming(resp)
    resp.luaw_is_chunked = true
    resp:addHeader('Transfer-Encoding', 'chunked')

    local headers = resp.headers
    local conn = resp.luaw_conn
    local writeTimeout = resp.writeTimeout

    -- use separate buffer from "bodyBuffer" to serialize headers
    local headersBuffer = newWriteBuffer()
    headersBuffer:append(resp:firstLine())
    bufferHeaders(headers, headersBuffer)

    -- flush up to HTTP headers end without chunked encoding before actual body starts
    sendBuffer(headersBuffer, conn, writeTimeout, false)
end

local function appendBody(resp, bodyPart)
    if not bodyPart then
        return
    end

    local bodyBuffer = resp.bodyBuffer
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
    local bodyBuffer = resp.bodyBuffer

    if (resp.method == 'POST') then
        local encodedParams, contentLength = urlEncodeParams(resp.params)
        if encodedParams then
            resp:addHeader('Content-Type', 'application/x-www-form-urlencoded')
            bodyBuffer:append(encodedParams)
        end
    end

    resp:addHeader('Content-Length', bodyBuffer.len)

    -- first write up to HTTP headers end
    local headersBuffer = newWriteBuffer()
    headersBuffer:append(resp:firstLine())
    bufferHeaders(resp.headers, headersBuffer)
    sendBuffer(headersBuffer, conn, writeTimeout, false)

    -- now write body
    sendBuffer(bodyBuffer, conn, writeTimeout, false)
end

local function endStreaming(resp)
    local conn = resp.luaw_conn
    local writeTimeout = resp.writeTimeout
    local bodyBuffer = resp.bodyBuffer

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
    local buffer = req.rbuffer
    if buffer then
        buffer:free()
        req.buffer = nil
    end
end

local function reset(req)
    req.headers = {}
    req.url = nil
    local bodyBuffer = req.bodyBuffer
    if (bodyBuffer) then
        bodyBuffer:clear()
    end
    req.body = nil
    req.END = nil
    req.params = nil
    req.parsedURL = nil
    req.status = nil
    req.statusMesg = nil
end

luaw_http_lib.newServerHttpRequest = function(conn)
	return {
	    luaw_mesg_type = 'sreq',
	    luaw_conn = conn,
	    headers = {},
	    luaw_parser = luaw_http_lib:newHttpRequestParser(),
        rbuffer = luaw_tcp_lib.newBuffer(CONN_BUFFER_SIZE),
	    addHeader = addHeader,
	    shouldCloseConnection = shouldCloseConnection,
	    isComplete = isComplete,
	    read = parseHttpRequest,
	    isMultipart = isMultipart,
	    multiPartIterator = multiPartIterator,
	    reset = reset,
	    consumeBodyChunkParsed = consumeBodyChunkParsed,
	    close = close
	}
end

luaw_http_lib.newServerHttpResponse = function(conn)
    return {
        luaw_mesg_type = 'sresp',
        luaw_conn = conn,
        major_version = 1,
        minor_version = 1,
        headers = {},
        bodyBuffer = newWriteBuffer(),
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
end

local function newClientHttpResponse(conn)
	return {
	    luaw_mesg_type = 'cresp',
	    luaw_conn = conn,
	    headers = {},
	    luaw_parser = luaw_http_lib:newHttpResponseParser(),
        rbuffer = luaw_tcp_lib.newBuffer(CONN_BUFFER_SIZE),
	    addHeader = addHeader,
	    shouldCloseConnection = shouldCloseConnection,
	    read = parseHttpRequest,
	    consumeBodyChunkParsed = consumeBodyChunkParsed,
	    reset = reset,
	    close = close
	}
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
    resp:read()
    if resp:shouldCloseConnection() then
        resp:close()
    end
    return resp
end

luaw_http_lib.newClientHttpRequest = function()
    return {
        luaw_mesg_type = 'creq',
        port = 80,
        major_version = 1,
        minor_version = 1,
        method = 'GET',
        headers = {},
		bodyBuffer = newWriteBuffer(),
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
end

return luaw_http_lib
