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

-- Thread states
Luaw.TS_RUNNABLE = {"RUNNABLE"}
Luaw.TS_DONE = {"DONE"}
Luaw.TS_BLOCKED_EVENT = {"BLOCKED_ON_EVENT"}
Luaw.TS_BLOCKED_THREAD = {"BLOCKED_ON_THREAD"}

local TS_BLOCKED_EVENT = Luaw.TS_BLOCKED_EVENT
local TS_RUNNABLE = Luaw.TS_RUNNABLE

local DEFAULT_CONNECT_TIMEOUT = luaw_server_config.connect_timeout or 8000
local DEFAULT_READ_TIMEOUT = luaw_server_config.read_timeout or 3000
local DEFAULT_WRITE_TIMEOUT = luaw_server_config.write_timeout or 3000
local CONN_BUFFER_SIZE = luaw_server_config.connection_buffer_size or 4096

EOF = 0
CRLF = '\r\n'

local function tprint(tbl, indent, tab)
  for k, v in pairs(tbl) do
    if type(v) == "table" then
		print(string.rep(tab, indent) .. tostring(k) .. ": {")
		tprint(v, indent+1, tab)
		print(string.rep(tab, indent) .. "}")
    else
		print(string.rep(tab, indent) .. tostring(k) .. ": " .. tostring(v))
    end
  end
end

-- Print contents of `tbl`, with indentation.
-- `indent` sets the initial level of indentation.
function debugDump (tbl, indent, tab)
    indent = indent or 0
    tab = tab or "  "
  	print(string.rep(tab, indent) .. "{")
	tprint(tbl, indent+1, tab)
	print(string.rep(tab, indent) .. "}")
end

function steplight(mesg)
    local tid = tostring(Luaw.scheduler.tid())
    print("Thread-"..tid.."> "..tostring(mesg))
end

function step(mesg, level)
    local tid = tostring(Luaw.scheduler.tid())

    local lvl = level or 2
    if (lvl < 0) then lvl = lvl * -1 end

    local dc = debug.getinfo(lvl, "nSl")

    local str = ""
    if type(mesg) == 'table' then
        for k,v in pairs(mesg) do
            str = str..", "..tostring(k).."="..tostring(v)
        end
    else
        str = tostring(mesg)
    end

    print('Thread '..tid..'> line# '..tostring(dc.linedefined)..' in function '..tostring(dc.name)..' in file '..tostring(dc.source)..': '..str)

    if ((level)and(level < 0)) then
        print(debug.traceback())
    end
end

function Luaw.run(codeblock)
    if (codeblock) then
        local try = codeblock.try
        if (try) then
            local catch = codeblock.catch
            local finally = codeblock.finally

            local status, err = pcall(try, codeblock)
            if ((not status)and(catch)) then
                status, err = pcall(catch, codeblock, err)
            end

            if (finally) then
                finally(codeblock)
            end

            if (not status) then
                error(err)
            end
        end
    end
end


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


function Luaw.storeHttpParam(params, name , value)
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

local parserMT = getmetatable(Luaw.newHttpRequestParser())

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
	req.luaw_headers_done = true
	req.major_version = httpMajor
	req.minor_version = httpMinor
    req.method = method
    req.status = status
end

local function onBody(req, cbtype, remaining, chunk)
    local bodyParts = rawget(req, 'bodyParts')
    table.insert(bodyParts, chunk)
end

local function onMesgComplete(req, cbtype, remaining, keepAlive)
	-- for the rare boundary case of chunked transfer encoding, where headers may continue
	-- after the last body chunk
	handleAccHttpHeader(req)
	handleKeepAlive(req, keepAlive)
	req.luaw_mesg_done = true
	req.luaw_headers_done = true
	local luaw_parser = req.luaw_parser
    if (luaw_parser) then
        luaw_parser:initHttpParser()
    end
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

local function parseHttpBuffer(req, conn)
    local parser = req.luaw_parser
    while true do
        -- matched against most number of return results possible. Actual variable names
        -- are meaningless without the context of correct callback, misleading even!
        local cbtype, remaining, keepAlive, httpMajor, httpMinor, method, status = parser:parseHttpBuffer(conn)
        if (not cbtype) then
            conn:close()
            error(remaining) -- remaining carries error message in this case
        end

        local callback = http_callbacks_lua[cbtype]
        if (not callback) then
            conn:close()
            error("Invalid HTTP parser callback# "..tostring(cbtype).." requested")
        end
        callback(req, cbtype, remaining, keepAlive, httpMajor, httpMinor, method, status)
        if (remaining == 0) then break end
    end
end


local function readAndParse(req)
    if (not req.luaw_mesg_done) then
   		local conn = req.luaw_conn
    	local mesg = conn:read(req.readTimeout)

    	if mesg == 'EOF' then
        	req.luaw_headers_done = true
        	req.luaw_mesg_done = true
        	req.EOF = true
        	req:addHeader('Connection', 'close')
    	else
        	parseHttpBuffer(req, conn)
    	end
	end
    return req.luaw_headers_done, req.luaw_mesg_done
end

local function shouldCloseConnection(req)
    if req and req.EOF then
        return true
    end
end

local function parseParams(req)
    if (req.luaw_mesg_type == 'sreq') then
        local params = rawget(req, 'params')
        if params then return params end

        if not params then
            params = {}
        end

        -- POST form params
        local contentType = req.headers['Content-Type']
        if ((contentType) and (contentType:lower() == 'application/x-www-form-urlencoded')) then
            local status, errMesg = Luaw:urlDecode(req.body, params)
        end

        -- GET query params
        local url = req:getParsedURL()
        if url then
            local queryString = url.queryString
            if queryString then
                Luaw:urlDecode(queryString, params)
            end
        end

        req.params = params
        return params
    end
end

local function clearArrayPart(t)
    local len = #t
    for i=1,len do
        t[i] = nil
    end
end

local function readFull(req)
    -- loop and block till the body is completely parsed
    local headersDone, mesgDone = false, false
    while (not mesgDone) do
        headersDone, mesgDone = req:readAndParse()
    end

    local body = nil
    local bodyParts = rawget(req, 'bodyParts')
    if ((bodyParts)and(#bodyParts > 0)) then
        body = table.concat(bodyParts)
        clearArrayPart(bodyParts)
    end

    req.body = body
    parseParams(req)

    return req.EOF
end

local function getParsedURL(req)
    local parsedURL = rawget(req, 'parsedURL')
    if parsedURL then return parsedURL end
    local url = req.url

    if url then
        local method = req.method
        parsedURL = Luaw.parseURL(url, ((method) and (string.upper(method) == "CONNECT")))
    else
        parsedURL = {}
    end
    req.parsedURL = parsedURL
    return parsedURL
end

local function readStreaming(req)
    if not rawget(req, 'luaw_mesg_done') then
        local headersDone, mesgDone = req:readAndParse()

        local body = nil
        local bodyParts = rawget(req, 'bodyParts')
        if ((bodyParts)and(#bodyParts > 0)) then
            body = table.concat(bodyParts)
            clearArrayPart(bodyParts)
        end
        return headersDone, mesgDone, body
    end

    return true, true, nil
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

local function bufferAndWrite(str, conn, writeTimeout, isChunked, flush)
    local remainingSpace, remainingStr = 0, nil
    while (str) do
        if (str ~= '') then
            remainingSpace, remainingStr = conn:appendBuffer(str)
        end
        if (remainingStr or flush) then
            -- either buffer is full or flush requested
            conn:write(writeTimeout, isChunked)
        end
        str = remainingStr
    end
end

local function flushBuffer(conn, writeTimeout, isChunked)
    bufferAndWrite('', conn, writeTimeout, isChunked, true)
end

local function writeHeader(conn, writeTimeout, name, value)
    bufferAndWrite(tostring(name), conn, writeTimeout, false, false)
    bufferAndWrite(": ", conn, writeTimeout, false, false)
    bufferAndWrite(tostring(value), conn, writeTimeout, false, false)
    bufferAndWrite(CRLF, conn, writeTimeout, false, false)
end

local function writeHeaders(resp, conn, writeTimeout)
    local headers = resp.headers
    if (headers) then
        for name,value in pairs(headers) do
            if (type(value) == 'table') then
                for i,v in ipairs(value) do
                    writeHeader(conn, writeTimeout, name, v)
                end
            else
                writeHeader(conn, writeTimeout, name, value)
            end
            headers[name] = nil
        end
    end
    bufferAndWrite(CRLF, conn, writeTimeout, false, false)
end

local function startStreaming(resp)
    resp.luaw_is_chunked = true
    resp:addHeader('Transfer-Encoding', 'chunked')

    local conn = resp.luaw_conn
    local writeTimeout = resp.writeTimeout

    bufferAndWrite(resp:firstLine(), conn, writeTimeout, false, false)
    writeHeaders(resp, conn, writeTimeout)
    flushBuffer(conn, writeTimeout, false) -- flush stream before actual chunked encoding starts

    local bodyParts = rawget(resp, "bodyParts")
    if (bodyParts) then
        for i, bodyPart in ipairs(bodyParts) do
            bufferAndWrite(bodyPart, conn, writeTimeout, true, false)
        end
    end
end

local function appendBody(resp, bodyPart)
    if not bodyPart then return end

    if resp.luaw_is_chunked then
        -- send connection's buffer full of chunk as they fill
        local conn = resp.luaw_conn
        local writeTimeout = resp.writeTimeout
        bufferAndWrite(tostring(bodyPart), conn, writeTimeout, true, false)
    else
        -- buffer complete body in memory in order to calculate Content-Length
        local bodyParts = rawget(resp, "bodyParts")
        table.insert(bodyParts, bodyPart)
        resp.contentLength = resp.contentLength + #bodyPart
    end
end

local function writeFullBody(resp)
    local conn = resp.luaw_conn
    local writeTimeout = resp.writeTimeout

    if (resp.method == 'POST') then
        local encodedParams, contentLength = urlEncodeParams(resp.params)
        if encodedParams then
            resp:addHeader('Content-Type', 'application/x-www-form-urlencoded')
            resp.bodyParts = encodedParams
            resp.contentLength = contentLength
        end
    end

    --appendBody(resp, CRLF)
    resp:addHeader('Content-Length', resp.contentLength)

    bufferAndWrite(resp:firstLine(), conn, writeTimeout, false, false)
    writeHeaders(resp, conn, writeTimeout)

    local bodyParts = rawget(resp, "bodyParts")
    if (bodyParts) then
        for i, bodyPart in ipairs(bodyParts) do
            bufferAndWrite(bodyPart, conn, writeTimeout, false, false)
        end
    end

    -- flush whatever is remaining in buffer
    flushBuffer(conn, writeTimeout, false)
end

local function endStreaming(resp)
    local conn = resp.luaw_conn
    local writeTimeout = resp.writeTimeout

    -- flush whatever is remaining in write buffer
    flushBuffer(conn, writeTimeout, true)

    -- add chunk encoding trailer
    bufferAndWrite("0\r\n\r\n", conn, writeTimeout, false, false)
    flushBuffer(conn, writeTimeout, false)
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

local conn = Luaw.newConnection();
local connMT = getmetatable(conn)
conn:close()
local startReadingInternal = connMT.startReading
local readInternal = connMT.read
local writeInternal = connMT.write

connMT.startReading = function(self)
    local status, mesg = startReadingInternal(self)
    assert(status, mesg)
end

connMT.read = function(self, readTimeout)
    local status, mesg = readInternal(self, Luaw.scheduler.tid(), readTimeout or DEFAULT_READ_TIMEOUT)
    if ((status)and(mesg == 'WAIT')) then
        -- nothing in buffer, wait for libuv on_read callback
        status, mesg = coroutine.yield(TS_BLOCKED_EVENT)
    end
    assert(status, mesg)
    return mesg
end

connMT.write = function(self, writeTimeout, isChunked)
    local status, nwritten = writeInternal(self, Luaw.scheduler.tid(), writeTimeout  or DEFAULT_WRITE_TIMEOUT, isChunked)
    if ((status)and(nwritten > 0)) then
        -- there is something to write, yield for libuv callback
        status, nwritten = coroutine.yield(TS_BLOCKED_EVENT)
    end
    assert(status, nwritten)
    return nwritten
end

local function reset(req)
    req.headers = {}
    req["_acc_header_name_"] = nil
    req["_acc_header_value_"] = nil
    req.url = nil
    req.bodyParts = {}
    req.body = nil
    req.luaw_mesg_done = nil
    req.luaw_headers_done = nil
    req.params = nil
    req.parsedURL = nil
    req.status = nil
    req.statusMesg = nil
end

Luaw.newServerHttpRequest = function(conn)
	local req = {
	    luaw_mesg_type = 'sreq',
	    luaw_conn = conn,
	    headers = {},
		bodyParts = {},
	    luaw_parser = Luaw:newHttpRequestParser(),
	    addHeader = addHeader,
	    shouldCloseConnection = shouldCloseConnection,
	    readAndParse = readAndParse,
	    isComplete = isComplete,
	    headersDone = headersDone,
	    getParsedURL = getParsedURL,
	    readFull = readFull,
	    readStreaming = readStreaming,
	    getBody = getBody,
	    reset = reset,
	    close = close
	}
    return req;
end

Luaw.newServerHttpResponse = function(conn)
    local resp = {
        luaw_mesg_type = 'sresp',
        luaw_conn = conn,
        major_version = 1,
        minor_version = 1,
        contentLength = 0,
        headers = {},
        bodyParts = {},
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
		bodyParts = {},
	    luaw_parser = Luaw:newHttpResponseParser(),
	    addHeader = addHeader,
	    shouldCloseConnection = shouldCloseConnection,
	    readAndParse = readAndParse,
	    isComplete = isComplete,
	    headersDone = headersDone,
	    getBody = getBody,
	    getStatus = getStatus,
	    readFull = readFull,
	    readStreaming = readStreaming,
	    reset = reset,
	    close = close
	}
	return resp;
end

local connectInternal = Luaw.connect

local function connect(req)
    local hostName, hostIP = req.hostName, req.hostIP
    assert((hostName or hostIP), "Either hostName or hostIP must be specified in request")
    local threadId = Luaw.scheduler.tid()
    if not hostIP then
        local status, mesg = Luaw.resolveDNS(hostName, threadId)
        assert(status, mesg)
        status, mesg = coroutine.yield(TS_BLOCKED_EVENT)
        assert(status, mesg)
        hostIP = mesg
    end

    local connectTimeout = req.connectTimeout or DEFAULT_CONNECT_TIMEOUT
    local conn = assert(connectInternal(hostIP, req.port, threadId, connectTimeout))

    -- initial connect_req succeeded, block for libuv callback
    assert(coroutine.yield(TS_BLOCKED_EVENT))
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

local function execute(req)
    local resp = req:connect()
    req:flush()
    resp:readFull()
    if resp:shouldCloseConnection() then
        resp:close()
    end
    return resp
end

Luaw.newClientHttpRequest = function()
    local req = {
        luaw_mesg_type = 'creq',
        port = 80,
        major_version = 1,
        minor_version = 1,
        method = 'GET',
        contentLength = 0,
        headers = {},
		bodyParts = {},
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


-- Timer functions
local timerMT = getmetatable(Luaw.newTimer())
local waitInternal = timerMT.wait

timerMT.wait = function(timer)
    local status, elapsed = waitInternal(timer, Luaw.scheduler.tid())
    if ((status) and (not elapsed)) then
        -- timer not yet elapsed, wait for libuv on_timeout callback
        status, elapsed = coroutine.yield(TS_BLOCKED_EVENT)
    end
    return status, elapsed
end

timerMT.sleep = function(timer, timeout)
    assert(timer:start(timeout))
    timer:wait()
end

Luaw.splitter = function(splitCh)
    local separator = string.byte(splitCh, 1, 1)
    local byte = string.byte

    return function (str, pos)
        pos = pos + 1
        local start = pos
        local len = #str
        while pos <= len do
            local ch = byte(str, pos, pos)
            if (ch == separator) then
                if (pos > start) then
                    return pos, string.sub(str, start, pos-1)
                end
                start = pos + 1
            end
            pos = pos + 1
        end
        if (pos > start) then return pos, string.sub(str, start, pos) end
    end
end

Luaw.nilFn = function()
    return nil
end

Luaw.formattedLine = function(str, lineSize, paddingCh, beginCh, endCh)
    lineSize = lineSize or 0
    paddingCh = paddingCh or ''
    beginCh = beginCh or ''
    endCh = endCh or ''
    paddingWidth = (lineSize - #str -2)/2
    local padding = ''
    if paddingWidth > 0 then
        padding = string.rep(paddingCh, paddingWidth)
    end
    print(string.format("%s %s %s %s %s", beginCh, padding, str, padding, endCh))
end

return Luaw
