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
    local strlen = #str
    
    if (count > 0) then
        buff = buffers[count]
    else
        buff = luaw_tcp_lib.newBuffer(math.max(CONN_BUFFER_SIZE, strlen+1))
        count = 1
        buffers[count] = buff
    end

    local added = buff:append(str)    
    if (not added) then
        buff = luaw_tcp_lib.newBuffer(math.max(CONN_BUFFER_SIZE, strlen+1))
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

local function lastBuffer(buffers)
    local count = #buffers
    return buffers[count], count
end

local function addCapacity(buffers)
    local count = #buffers
    local newbuff = luaw_tcp_lib.newBuffer(CONN_BUFFER_SIZE)
    count = count + 1
    buffers[count] = newbuff
    return newbuff, count
end

local function concat(buffers, startIdx, startPos, endIdx, endPos)
    local temp = {}
    startIdx = startIdx or 1
    startPos = startPos or 0
    endIdx = endIdx or #buffers
    local k=1
    for i=startIdx,endIdx do
        local buff = buffers[i]
        local pos = 0
        if (i == startIdx) then pos = startPos end

        if ((i ~= endIdx)or(not endPos)) then
            temp[k] = buff:tostring(pos)
        else
            temp[k] = buff:tostring(pos,endPos)
        end
        k = k+1
    end
    return table.concat(temp)
end

local function add(buffers, buffersToAdd)
    local count = #buffers + 1
    for i, buff in ipairs(buffersToAdd) do
        buffers[count] = buff
        count = count + 1
    end
end

local function newBufferChain()
    local bufferChain = {
        clear = clear,
        free = free,
        append = append,
        lastBuffer = lastBuffer,
        addCapacity = addCapacity,
        concat = concat,
        add = add,
        length = length
    }
    -- initialize with addition of first buffer to the chain
    bufferChain:addCapacity()
    return bufferChain
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

local function addHeader(httpConn, headerName, headerValue)
    addNVPair(httpConn.luaw_wheaders, headerName, headerValue)
end

local function urlDecode(str)
    return (str:gsub('+', ' '):gsub("%%(%x%x)", function(xx) return string.char(tonumber(xx, 16)) end))
end

function parseUrlParams(str, params)
    if (str) then
        params = params or {}
        if (str) then
            for pair in str:gmatch"[^&]+" do
                local key, val = pair:match"([^=]+)=(.*)"
                if (key and val) then 
                    addNVPair(params, urlDecode(key), urlDecode(val))
                end
            end    
        end
    end
    return params
end

luaw_http_lib.parseUrlParams = parseUrlParams

local function parseURL(httpConn, url)
    local parsedURL
    local params

    if url then
        httpConn.URL = url
        local method = httpConn.method
        parsedURL = luaw_http_lib.parseURL(url, ((method) and (string.upper(method) == "CONNECT")))        
        local queryString = parsedURL.queryString
        if queryString then
            params = parseUrlParams(queryString)
        end
    end

    httpConn.parsedURL = parsedURL
    httpConn.luaw_params = params
end

local function parseBody(httpConn)
    -- store body
    local body = httpConn.luaw_rbody

    -- POST form params
    local contentType = httpConn.luaw_rheaders['Content-Type']
    if ((contentType) and (contentType:lower() == 'application/x-www-form-urlencoded')) then
        httpConn.luaw_params = parseUrlParams(body, httpConn.luaw_params)
    end

    return body
end

local function handleKeepAlive(parser, httpConn)
    if (not parser:shouldKeepAlive()) then
        httpConn.luaw_wheaders['Connection'] = 'close'
        httpConn.luaw_close_conn = true
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

local function getMultipartBoundary(httpConn)
    local header = httpConn.luaw_rheaders['Content-Type']
    if (header) then
        local boundary = string.match(header, 'multipart/form%-data; boundary=(.*)')
        if (boundary) then
            return '--'..boundary
        end
    end
end

local function isMultipartRequest(httpConn)
    if (httpConn.luaw_multipart_boundary) then
        return true
    end

    local boundary = getMultipartBoundary(httpConn)
    if (boundary) then
        httpConn.luaw_multipart_boundary = boundary
        httpConn.luaw_multipart_end = boundary .. '--'
        return true
    end
end

--local function isLuaPackMesg(req)
--    local contentType = req.headers['Content-Type']
--    if ('application/luapack' == contentType) then
--        return true
--    end
--end

local function readNextChunkIfNeeded(httpConn)
    local buffers = httpConn.luaw_rbuffers
    local currentReadBuff, currentReadBuffIdx = lastBuffer(buffers)
    
    if (currentReadBuff:remainingLength() > 0) then
        -- unparsed content available, no need to read
        return currentReadBuff, currentReadBuffIdx
    end
    
    -- read new content from the request socket 
    if (currentReadBuff:remainingCapacity() <= 0) then
        currentReadBuff, currentReadBuffIdx = addCapacity(buffers)
    end

    httpConn:read(currentReadBuff, httpConn.readTimeout)   
    return currentReadBuff, currentReadBuffIdx
end

local function readHttpHeaders(httpConn)    
    local parser = httpConn.luaw_parser    
    local headers = httpConn.luaw_rheaders
    local statusMesg, url, headerName, headerValue

    while (not httpConn.luaw_END) do  
        local currentReadBuff, currentReadBuffIdx = readNextChunkIfNeeded(httpConn)
        if (not currentReadBuff) then break end
        
        -- parse content present in read buffer
        local cbtype, errmesg = parser:parseHttp(currentReadBuff)

        if (cbtype == HTTP_STATUS) then
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
            httpConn.luaw_end_headers_idx = currentReadBuffIdx
            httpConn.luaw_end_headers_pos = currentReadBuff:position()
            
            if (headerName and headerValue) then
                addNVPair(headers, headerName, headerValue)
            end

            handleKeepAlive(parser, httpConn)
            httpConn.major_version = parser:getHttpMajorVersion()
            httpConn.minor_version = parser:getHttpMinorVersion()
            local httpMethod = parser:getReqMethod()
            if (httpMethod) then
                httpConn.method = httpMethod
                parseURL(httpConn, url)
            else
                httpConn.status = parser:getRespStatus()
                httpConn.statusMesg = statusMesg
            end
            break

        elseif  ((cbtype == HTTP_MESG_BEGIN)or(cbtype == HTTP_NONE)) then
            -- ignore

        else
            httpConn:close()
            return error("Invalid HTTP parser callback# "..tostring(cbtype).." requested. Error: "..tostring(errmesg))
        end
    end 
end

local function readHttpBody(httpConn, streamParse)    
    local parser = httpConn.luaw_parser
    
    while (not httpConn.luaw_END) do  
        local currentReadBuff, currentReadBuffIdx = readNextChunkIfNeeded(httpConn)
        if (not currentReadBuff) then break end
        
        -- parse content present in read buffer
        local cbtype, errmesg = parser:parseHttp(currentReadBuff)

        if (cbtype == HTTP_BODY) then
            if (streamParse) then
                local chunk = parser:getParsedChunk()
                -- streaming request body to caller, reuse same buffer instead of allocating a new one
                currentReadBuff:clear()
                return chunk
            end

        elseif (cbtype == HTTP_MESG_DONE) then
            httpConn.luaw_END = true
            httpConn.luaw_end_body_idx = currentReadBuffIdx
            httpConn.luaw_end_body_pos = currentReadBuff:position()
            handleKeepAlive(parser, httpConn)
            -- reset parser for next request in case this connection is a persistent/pipelined HTTP connection
            parser:initHttpParser()
            break

        elseif  (cbtype == HTTP_NONE) then
            -- ignore

        else
            httpConn:close()
            return error("Invalid HTTP parser callback# "..tostring(cbtype).." requested. Error: "..tostring(errmesg))
        end
    end 
    return httpConn.luaw_body
end

local function patternRead(content, searchstr, httpConn)
    local buff = content
    while ((not httpConn.luaw_END) and
        ((not content)or(not content:find(searchstr, 1, true)))) do
        content = readHttpBody(httpConn, true)
        buff = safeAppend(buff, content)
    end
    return buff
end

local function lengthRead(content, len, httpConn)
    local buff = content
    while ((not httpConn.luaw_END) and
        ((not buff)or(#buff < len))) do
        content = readHttpBody(httpConn, true)
        buff = safeAppend(buff, content)
    end
    return buff
end

function fetchNextPart(httpConn, state)
    local boundary = httpConn.luaw_multipart_boundary
    local content = httpConn.luaw_multipart_content
    local line

    if (state == MULTIPART_BEGIN) then
        -- read beginning boundary
        content = patternRead(content, CRLF, httpConn)
        line, content = nextToken(content, CRLF)
        assert(line == boundary, "Missing multi-part boundary at the beginning of the part")
        state = PART_END
    end

    if (state == PART_END) then
        local fieldName, fileName, contentType

        -- read "Content-Disposition" line
        content = patternRead(content, CRLF, httpConn)
        line, content = nextToken(content, CRLF)
        assert(line, "Missing Content-Disposition")

        fieldName, fileName = string.match(line, 'Content%-Disposition: form%-data; name="(.-)"; filename="(.-)"')
        if (not fieldName) then
            fieldName = string.match(line, 'Content%-Disposition: form%-data; name="(.-)"')
        end
        assert(fieldName, "form field name missing")

        if (fileName) then
            -- read "Content-Type" line
            content = patternRead(content, CRLF, httpConn)
            line, content = nextToken(content, CRLF)
            assert(line, "Missing Content-Type")    

            contentType = string.match(line, 'Content%-Type: (.*)')
            assert(contentType, "Missing Content-Type value")
        end

        -- read next blank line
        content = patternRead(content, CRLF, httpConn)
        line, content = nextToken(content, CRLF)

        -- save remaining content before returning from iterator
        httpConn.luaw_multipart_content = content 
        return PART_BEGIN, fieldName, fileName, contentType
    end

    if ((state == PART_BEGIN)or(state == PART_DATA)) then   
        local endBoundary = httpConn.luaw_multipart_end

        -- double the size of max possible boundary length: endBoundary + CRLF
        content = lengthRead(content, 2*(#endBoundary + 2), httpConn)        
        if ((not content)and(httpConn.luaw_END)) then
            return MULTIPART_END
        end

        line, content = nextToken(content, CRLF)

        if (not line) then
            httpConn.luaw_multipart_content = nil
            return PART_DATA, content
        end

        if (line == boundary) then
            httpConn.luaw_multipart_content = content
            return PART_END
        end

        if (line == endBoundary) then
            httpConn.luaw_multipart_content = nil
            return MULTIPART_END
        end

        httpConn.luaw_multipart_content = content
        return PART_DATA, line
    end
end

local function multiPartIterator(httpConn)
    if (isMultipart(httpConn)) then
        return fetchNextPart, httpConn, MULTIPART_BEGIN
    end
end

local function shouldCloseConnection(httpConn)
    return (httpConn and httpConn.luaw_close_conn)
end

local function eof(httpConn)
    return (httpConn and httpConn.luaw_EOF)
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

function buildURL(httpConn)
    if (httpConn.method == 'GET') then
        local encodedParams = urlEncodeParams(httpConn.params)
        if encodedParams then
            table.insert(encodedParams, 1, "?")
            table.insert(encodedParams, 1, httpConn.url)
            return table.concat(encodedParams)
        end
    end
    return httpConn.url
end

local function setStatus(httpConn, status)
    httpConn.status = status
    httpConn.statusMesg = http_status_codes[status]
end

local function firstResponseLine(httpConn)
    if (not httpConn.status) then
        httpConn:setStatus(200)
    end
    local line = {"HTTP/", httpConn.major_version or 1, ".", httpConn.minor_version or 1,
        " ", httpConn.status, " ", httpConn.statusMesg, CRLF}
    return table.concat(line)
end

local function firstRequestLine(httpConn)
    local line = {httpConn.method, " ", httpConn:buildURL(), " HTTP/", httpConn.major_version or 1,
        ".", httpConn.minor_version or 1, CRLF}
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

local function startStreaming(httpConn)
    httpConn.luaw_is_chunked = true
    httpConn:addHeader('Transfer-Encoding', 'chunked')

    local headersBuffer = newBufferChain()
    headersBuffer:append(httpConn:firstLine())
    bufferHeaders(httpConn.responseHeaders, headersBuffer)

    -- flush up to HTTP headers end without chunked encoding before actual body starts
    httpConn:write(headersBuffer, httpConn.writeTimeout)
    headersBuffer:free()

    -- now setup wbuffers to store chunk header, actual chunk and chunk trailer in that order
    local wbuffers = httpConn.luaw_wbuffers
    wbuffers:clear()
    wbuffers[1] = wbuffers[1] or luaw_tcp_lib.newBuffer(8) -- chunk header
    wbuffers[2] = wbuffers[2] or luaw_tcp_lib.newBuffer(CONN_BUFFER_SIZE) -- actual chunk
    wbuffers[3] = wbuffers[3] or luaw_tcp_lib.newBuffer(8) -- chunk trailer
end

local function sendChunk(httpConn, wbuffers)
    local chunkHeaderBuffer, chunkBuffer, chunkTrailerBuffer = wbuffers[1], wbuffers[2], wbuffers[3]    

    chunkHeaderBuffer:clear()
    chunkHeaderBuffer:append(string.format("%x\r\n", chunkBuffer:length())) 
    chunkTrailerBuffer:clear()
    chunkTrailerBuffer:append(CRLF)
    httpConn:write(wbuffers, httpConn.writeTimeout) 
    wbuffers:clear()
end

local function appendChunk(httpConn, bodyPart)
    local wbuffers = httpConn.luaw_wbuffers
    local chunkBuffer = wbuffers[2]

    local status = chunkBuffer:append(bodyPart)
    if (not status) then
        -- chunk full, send to client
        sendChunk(httpConn, wbuffers)

        -- retry original bodyPart
        status = chunkBuffer:append(bodyPart)
        if (not status) then
            --buffer completely empty, still too small. resize.
            chunkBuffer:resize(#bodyPart+1)
            chunkBuffer:append(bodyPart)
        end
    end
end    

local function appendBody(httpConn, bodyPart)
    if not bodyPart then
        return
    end
    if (httpConn.luaw_is_chunked) then
        appendChunk(httpConn, bodyPart)
    else
        httpConn.luaw_wbuffers:append(bodyPart)
    end
end

local function writeFullBody(httpConn)
    local writeTimeout = httpConn.writeTimeout
    local wbuffers = httpConn.luaw_wbuffers

    if (httpConn.method == 'POST') then
        local encodedParams = urlEncodeParams(httpConn.params)
        if encodedParams then
            httpConn:addHeader('Content-Type', 'application/x-www-form-urlencoded')
            wbuffers:append(table.concat(encodedParams))
        end
    end

    httpConn:addHeader('Content-Length', wbuffers:length())

    -- first write up to HTTP headers end
    local headersBuffer = newBufferChain()
    headersBuffer:append(httpConn:firstLine())
    bufferHeaders(httpConn.luaw_wheaders, headersBuffer)
    httpConn:write(headersBuffer, writeTimeout)
    headersBuffer:free()

    -- now write body
    httpConn:write(wbuffers, httpConn.writeTimeout)
    wbuffers:clear()
end

local function endStreaming(httpConn)
    local wbuffers = httpConn.luaw_wbuffers
    local chunkBuffer = wbuffers[2]    
    if (chunkBuffer:length() > 0) then
        sendChunk(httpConn, wbuffers)
    end    
    sendChunk(httpConn, wbuffers)
end

local function flush(httpConn)
    if httpConn.luaw_is_chunked then
        endStreaming(httpConn)
    else
        writeFullBody(httpConn)
    end
end

local function freeBuffers(httpConn)
    local rbuffers = httpConn.luaw_rbuffers
    if (rbuffers) then
        rbuffers:free()
    end    
    local wbuffers = httpConn.luaw_wbuffers
    if (wbuffers) then
        wbuffers:free()
    end
    -- set luaw_raw_conn to nil so that __gc does not close it
    httpConn.luaw_raw_conn = nil
end

local function close(httpConn)
    freeBuffers(httpConn)
    luaw_tcp_lib.close(httpConn.luaw_raw_conn)
end

local function readComplete(httpConn)
    readHttpHeaders(httpConn)
    readHttpBody(httpConn)
end

local function getBody(httpConn)
    local body = httpConn.luaw_rbody
    if (not body) then
        readHttpBody(httpConn)
        body =  concat(httpConn.luaw_rbuffers, httpConn.luaw_end_headers_idx, httpConn.luaw_end_headers_pos, httpConn.luaw_end_body_idx, httpConn.luaw_end_body_pos)
        httpConn.luaw_rbody = body
        
        local contentType = httpConn.luaw_rheaders['Content-Type']
        if ((contentType) and (contentType:lower() == 'application/x-www-form-urlencoded')) then
            httpConn.luaw_params = parseUrlParams(body, httpConn.luaw_params)
        end
    end
    return body
end

local function getParams(httpConn)
    getBody(httpConn)
    return httpConn.luaw_params
end

local function execute(httpConn, method)
    httpConn.method = method
    flush(httpConn)
    httpConn:startReading()
    readHttpHeaders(httpConn)
end

local function HEAD(httpConn)
    execute(httpConn, 'HEAD')
end

local function GET(httpConn)
    execute(httpConn, 'GET')
end

local function POST(httpConn)
    execute(httpConn, 'POST')
end

local function PUT(httpConn)
    execute(httpConn, 'PUT')
end

local function DELETE(httpConn)
    execute(httpConn, 'DELETE')
end

local function OPTIONS(httpConn)
    execute(httpConn, 'OPTIONS')
end

local function TRACE(httpConn)
    execute(httpConn, 'TRACE')
end

local function CONNECT(httpConn)
    execute(httpConn, 'CONNECT')
end

local function addHttpConnectionMethods(conn)
    conn.luaw_rheaders = {}
    conn.luaw_wheaders = {}   
    conn.luaw_rbuffers = newBufferChain()
    conn.luaw_wbuffers = newBufferChain()
    conn.addHeader = addHeader
    conn.shouldCloseConnection = shouldCloseConnection
    conn.eof = eof
    conn.readHeaders = readHttpHeaders
    conn.readBody = readHttpBody
    conn.getBody = getBody
    conn.readComplete = readComplete
    conn.getParams = getParams
    conn.setStatus = setStatus
    conn.startStreaming = startStreaming
    conn.appendBody = appendBody    
    conn.flush = flush
    conn.free = freeBuffers
    conn.close = close
end

local function addHttpServerMethods(conn)
    addHttpConnectionMethods(conn)
    conn.luaw_parser = luaw_http_lib:newHttpRequestParser()
    conn.isMultipartRequest = isMultipartRequest
    conn.multiPartIterator = multiPartIterator
    conn.firstLine = firstResponseLine
    conn.requestHeaders = conn.luaw_rheaders
    conn.responseHeaders = conn.luaw_wheaders
    conn.requestBody = conn.luaw_rbody
    conn.requestBuffers = conn.luaw_rbuffers
    conn.responseBuffers = conn.luaw_wbuffers
end
luaw_http_lib.addHttpServerMethods = addHttpServerMethods

local function addHttpClientMethods(conn)
    addHttpConnectionMethods(conn)
    conn.luaw_parser = luaw_http_lib:newHttpResponseParser()
    conn.firstLine = firstRequestLine
    conn.requestHeaders = conn.luaw_wheaders
    conn.responseHeaders = conn.luaw_rheaders
    conn.responseBody = conn.luaw_rbody
    conn.requestBuffers = conn.luaw_wbuffers
    conn.responseBuffers = conn.luaw_rbuffers
    conn.buildURL = buildURL
    conn.HEAD = HEAD
    conn.GET = GET
    conn.POST = POST
    conn.PUT = PUT
    conn.DELETE = DELETE
    conn.OPTIONS = OPTIONS
    conn.TRACE = TRACE
    conn.CONNECT = CONNECT
end
luaw_http_lib.addHttpClientMethods = addHttpClientMethods

luaw_http_lib.httpConnectByIP = function(ip, port, connectTimeout)
    local conn, mesg = luaw_tcp_lib.connectByIP(ip, port or 80, connectTimeout)
    if (not conn) then return conn, mesg end
    addHttpClientMethods(conn)
    return conn
end

luaw_http_lib.connectByHostName = function(hostName, port, connectTimeout)
    local conn, mesg = luaw_tcp_lib.connectByHostName(hostName, port or 80, connectTimeout)
    if (not conn) then return conn, mesg end
    addHttpClientMethods(conn)
    return conn
end

return luaw_http_lib
