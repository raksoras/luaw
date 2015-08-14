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
local luaw_util_lib = require('luaw_utils')
local luaw_tcp_lib = require('luaw_tcp')


local TS_BLOCKED_EVENT = constants.TS_BLOCKED_EVENT
local TS_RUNNABLE = constants.TS_RUNNABLE

local CONN_BUFFER_SIZE = constants.CONN_BUFFER_SIZE

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

-- write buffer chain implementation

local function clear(buffers)
    local count = #buffers
    for i=1,count do
        local buff = buffers[i]
        buff:clear()
    end
end

local function free(buffers)
    local count = #buffers
    for i=1,count do
        local buff = buffers[i]
        buff:free()
        buffers[i] = nil
    end
end

local function append(buffers, str)
    local buff 
    local count = #buffers
    if (count > 0) then
        buff = buffers[count]
    else
        buff = luaw_tcp_lib.newBuffer(math.max(CONN_BUFFER_SIZE, #str+1))
        count = 1
        buffers[count] = buff
    end

    local added = buff:append(str)    
    if (not added) then
        buff = luaw_tcp_lib.newBuffer(math.max(CONN_BUFFER_SIZE, #str+1))
        buffers[count+1] = buff
        buff:append(str)
    end
end

local function length(buffers)
    local count = #buffers
    local len = 0
    for i=1,count do
        local buff = buffers[i]
        len = len + buff:length()
    end
    return len
end

local function newBufferChain()
    return {
        clear = clear,
        free = free,
        append = append,
        length = length
    }
end


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
    if ((not str)or(#str == 0)) then
        return nil
    end

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
        req.URL = url
        local method = req.method
        parsedURL = luaw_http_lib.parseURL(url, ((method) and (string.upper(method) == "CONNECT")))        
        local queryString = parsedURL.queryString
        if queryString then
            params = parseUrlParams(queryString)
        end
    end

    req.parsedURL = parsedURL
    req.luaw_params = params
end

local function parseBody(req, bodyParts)
    -- store body
    local body = table.concat(bodyParts)
    req.luaw_body = body

    -- POST form params
    local contentType = req.headers['Content-Type']
    if ((contentType) and (contentType:lower() == 'application/x-www-form-urlencoded')) then
        req.luaw_params = assert(parseUrlParams(body, req.luaw_params))
    end

    return body
end

local function handleKeepAlive(parser, req)
    if (not parser:shouldKeepAlive()) then
        req.headers['Connection'] = 'close'
        req.luaw_EOF = true
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

--local function isLuaPackMesg(req)
--    local contentType = req.headers['Content-Type']
--    if ('application/luapack' == contentType) then
--        return true
--    end
--end

local function readHttpHeaders(req)    
    local conn = req.luaw_conn
    local parser = req.luaw_parser    
    local headers = req.headers
    local buffer = req.luaw_rbuffer
    local statusMesg, url, headerName, headerValue

    while (not req.luaw_END) do        
        if (buffer:remainingLength() <= 0) then
            -- read new content from the request socket 
            buffer:clear()
            local status, err = conn:read(buffer, req.readTimeout)

            if (not status) then
                if (err == 'EOF') then
                    headers['Connection'] = 'close'
                    req.luaw_END = true
                    req.luaw_EOF = true
                    break
                else
                    return error(err)
                end
            end
        end

        -- parse content present in read buffer
        local cbtype, errmesg = parser:parseHttp(buffer)

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

            break

        elseif  (cbtype == HTTP_NONE) then
            -- ignore

        else
            conn:close()
            return error("Invalid HTTP parser callback# "..tostring(cbtype).." requested. Error: "..tostring(errmesg))
        end
    end 
end

local function readHttpBody(req, streamParse)    
    local conn = req.luaw_conn
    local parser = req.luaw_parser    
    local buffer = req.luaw_rbuffer
    local bodyParts 

    while (not req.luaw_END) do        
        if (buffer:remainingLength() <= 0) then
            -- read new content from the request socket 
            buffer:clear()
            local status, err = conn:read(buffer, req.readTimeout)

            if (not status) then
                if (err == 'EOF') then
                    headers['Connection'] = 'close'
                    req.luaw_END = true
                    req.luaw_EOF = true
                    return
                else
                    return error(err)
                end
            end
        end

        -- parse content present in read buffer
        local cbtype, errmesg = parser:parseHttp(buffer)

        if (cbtype == HTTP_BODY) then
            if (streamParse) then
                return parser:getParsedChunk()
            end
            bodyParts = bodyParts or {}
            table.insert(bodyParts, parser:getParsedChunk())

        elseif (cbtype == HTTP_MESG_DONE) then
            if (bodyParts) then
                body = parseBody(req, bodyParts)
            end
            req.luaw_END = true
            handleKeepAlive(parser, req)
            -- reset parser for next request in case this connection is a persistent/pipelined HTTP connection
            parser:initHttpParser()
            break

        elseif  (cbtype == HTTP_NONE) then
            -- ignore

        else
            conn:close()
            return error("Invalid HTTP parser callback# "..tostring(cbtype).." requested. Error: "..tostring(errmesg))
        end
    end 
    return req.luaw_body
end

local function patternRead(content, searchstr, req)
    local buff = content
    while ((not req.luaw_END) and
        ((not content)or(not content:find(searchstr, 1, true)))) do
        content = readHttpBody(req, true)
        buff = safeAppend(buff, content)
    end
    return buff
end

local function lengthRead(content, len, req)
    local buff = content
    while ((not req.luaw_END) and
        ((not buff)or(#buff < len))) do
        content = readHttpBody(req, true)
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
        if ((not content)and(req.luaw_END)) then
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
    if req and req.luaw_EOF then
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

        for key, val in pairs(params) do
            local ueKey = urlEncode(key)
            table.insert(encodedParams, ueKey)
            table.insert(encodedParams, "=")
            local ueVal = urlEncode(val)
            table.insert(encodedParams, ueVal)
            table.insert(encodedParams, "&")
        end

        if (#encodedParams > 0) then
            table.remove(encodedParams) -- remove the last extra "&"
            return encodedParams
        end
    end

    return nil
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
    if (not resp.status) then
        resp:setStatus(200)
    end
    local line = {"HTTP/", resp.major_version or 1, ".", resp.minor_version or 1,
        " ", resp.status, " ", resp.statusMesg, CRLF}
    return table.concat(line)
end

local function firstRequestLine(req)
    local line = {req.method, " ", req:buildURL(), " HTTP/", req.major_version or 1,
        ".", req.minor_version or 1, CRLF}
    return table.concat(line)
end

local function bufferHeader(buffers, name, value)
    buffers:append(tostring(name))
    buffers:append(": ")
    buffers:append(tostring(value))
    buffers:append(CRLF)
end

local function bufferHeaders(headers, buffers)
    if (headers) then
        for name,value in pairs(headers) do
            if (type(value) == 'table') then
                for i,v in ipairs(value) do
                    bufferHeader(buffers, name, v)
                end
            else
                bufferHeader(buffers, name, value)
            end
            headers[name] = nil
        end
    end
    buffers:append(CRLF)
end

local function startStreaming(resp)
    resp.luaw_is_chunked = true
    resp:addHeader('Transfer-Encoding', 'chunked')

    local headersBuffer = newBufferChain()
    headersBuffer:append(resp:firstLine())
    bufferHeaders(resp.headers, headersBuffer)

    -- flush up to HTTP headers end without chunked encoding before actual body starts
    local conn = resp.luaw_conn
    conn:write(headersBuffer, resp.writeTimeout)
    headersBuffer:free()

    -- now setup wbuffers to store chunk header, actual chunk and chunk trailer in that order
    local wbuffers = resp.luaw_wbuffers
    wbuffers:clear()
    wbuffers[1] = wbuffers[1] or luaw_tcp_lib.newBuffer(8) -- chunk header
    wbuffers[2] = wbuffers[2] or luaw_tcp_lib.newBuffer(CONN_BUFFER_SIZE) -- actual chunk
    wbuffers[3] = wbuffers[3] or luaw_tcp_lib.newBuffer(8) -- chunk trailer
end

local function sendChunk(resp, wbuffers)
    local chunkHeaderBuffer, chunkBuffer, chunkTrailerBuffer = wbuffers[1], wbuffers[2], wbuffers[3]    
    local conn = resp.luaw_conn

    chunkHeaderBuffer:clear()
    chunkHeaderBuffer:append(string.format("%x\r\n", chunkBuffer:length())) 
    chunkTrailerBuffer:clear()
    chunkTrailerBuffer:append(CRLF)
    conn:write(wbuffers, resp.writeTimeout) 
    wbuffers:clear()
end

local function appendChunk(resp, bodyPart)
    local wbuffers = resp.luaw_wbuffers
    local chunkBuffer = wbuffers[2]

    local status = chunkBuffer:append(bodyPart)
    if (not status) then
        -- chunk full, send to client
        sendChunk(resp, wbuffers)

        -- retry original bodyPart
        status = chunkBuffer:append(bodyPart)
        if (not status) then
            --buffer completely empty, still too small. resize.
            chunkBuffer:resize(#bodyPart+1)
            chunkBuffer:append(bodyPart)
        end
    end
end    

local function appendBody(resp, bodyPart)
    if not bodyPart then
        return
    end
    if (resp.luaw_is_chunked) then
        appendChunk(resp, bodyPart)
    else
        resp.luaw_wbuffers:append(bodyPart)
    end
end

local function writeFullBody(resp)
    local conn = resp.luaw_conn
    local writeTimeout = resp.writeTimeout
    local wbuffers = resp.luaw_wbuffers

    if (resp.method == 'POST') then
        local encodedParams = urlEncodeParams(resp.params)
        if encodedParams then
            resp:addHeader('Content-Type', 'application/x-www-form-urlencoded')
            wbuffers:append(table.concat(encodedParams))
        end
    end

    resp:addHeader('Content-Length', wbuffers:length())

    -- first write up to HTTP headers end
    local headersBuffer = newBufferChain()
    headersBuffer:append(resp:firstLine())
    bufferHeaders(resp.headers, headersBuffer)
    conn:write(headersBuffer, writeTimeout)
    headersBuffer:free()

    -- now write body
    conn:write(wbuffers, resp.writeTimeout)
    wbuffers:clear()
end

local function endStreaming(resp)
    local wbuffers = resp.luaw_wbuffers
    local chunkBuffer = wbuffers[2]    
    if (chunkBuffer:length() > 0) then
        sendChunk(resp, wbuffers)
    end    
    sendChunk(resp, wbuffers)
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
    local buffer = req.luaw_rbuffer
    if buffer then
        buffer:free()
        req.buffer = nil
    end
    local wbuffers = req.luaw_wbuffers
    if (wbuffers) then
        wbuffers:free()
    end    
end

local function getBody(req)
    readHttpBody(req)
    return req.luaw_body
end

local function getParams(req)
    readHttpBody(req)
    return req.luaw_params
end

local function reset(httpMesg)
    httpMesg.headers = {}
    httpMesg.status = nil
    httpMesg.statusMesg = nil
    httpMesg.URL = nil
    httpMesg.luaw_END = nil
    httpMesg.luaw_EOF = nil
    httpMesg.luaw_body = nil
    httpMesg.luaw_params = nil
    httpMesg.luaw_parsedURL = nil
    httpMesg.luaw_is_chunked = nil
    httpMesg.major_version = nil
    httpMesg.minor_version = nil
    httpMesg.luaw_multipart_boundary = nil
    httpMesg.luaw_multipart_end = nil
    local wbuffers = httpMesg.luaw_wbuffers
    if (wbuffers) then
        wbuffers:clear()
    end
end

luaw_http_lib.newServerHttpRequest = function(conn)
    return {
        luaw_mesg_type = 'sreq',
        luaw_conn = conn,
        headers = {},
        luaw_parser = luaw_http_lib:newHttpRequestParser(),
        luaw_rbuffer = luaw_tcp_lib.newBuffer(CONN_BUFFER_SIZE),
        addHeader = addHeader,
        shouldCloseConnection = shouldCloseConnection,
        readHeaders = readHttpHeaders,
        readBody = readHttpBody;
        getBody = getBody,
        getParams = getParams,
        isMultipart = isMultipart,
        multiPartIterator = multiPartIterator,
        reset = reset,
        close = close
    }
end

luaw_http_lib.newServerHttpResponse = function(conn)
    return {
        luaw_mesg_type = 'sresp',
        luaw_conn = conn,
        headers = {},
        luaw_wbuffers = newBufferChain(),
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
        luaw_rbuffer = luaw_tcp_lib.newBuffer(CONN_BUFFER_SIZE),
        addHeader = addHeader,
        shouldCloseConnection = shouldCloseConnection,
        readHeaders = readHttpHeaders,
        readBody = readHttpBody;
        getBody = getBody,
        getParams = getParams,
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
        luaw_wbuffers = newBufferChain(),
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
