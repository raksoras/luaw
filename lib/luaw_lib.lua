local lfs = require('lfs')
local testing = require('unit_testing')

local luaw_open_lib, err = package.loadlib('/Users/saroskar/luaw/lib_luaw.so', 'luaw_open_lib')
if not luaw_open_lib then
	error(err)
end
local luaw_lib = assert(luaw_open_lib(), "Could not open luaw_lib")

-- Thread states
luaw_lib.TS_RUNNABLE = {"RUNNABLE"}
luaw_lib.TS_DONE = {"DONE"}
luaw_lib.TS_BLOCKED_EVENT = {"BLOCKED_ON_EVENT"}
luaw_lib.TS_BLOCKED_THREAD = {"BLOCKED_ON_THREAD"}

local TS_BLOCKED_EVENT = luaw_lib.TS_BLOCKED_EVENT
local TS_RUNNABLE = luaw_lib.TS_RUNNABLE

local DEFAULT_CONNECT_TIMEOUT = 8000
local DEFAULT_READ_TIMEOUT = 5000
local DEFAULT_WRITE_TIMEOUT = 5000

EOF = 0
CRLF = '\r\n'

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
    __index = function(statusCode)
        return "User Defined Status"
    end
})


function luaw_lib.storeHttpParam(params, name , value)
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

local parserMT = getmetatable(luaw_lib.newHttpRequestParser())

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
    end
end

parserMT.onHeaderName = function(req, hName)
	handleAccHttpHeader(req)
    accumulateChunkedValue(req, '_acc_header_name_', hName)
end

parserMT.onHeaderValue = function(req, hValue)
	if not hValue then hValue = '' end -- empty header value
	accumulateChunkedValue(req, '_acc_header_value_', hValue)
end

parserMT.onHeadersComplete = function(req, keepAlive)
	handleAccHttpHeader(req)
	handleKeepAlive(req, keepAlive)
	req.luaw_headers_done = true
end

parserMT.onURL = function(req, url)
	accumulateChunkedValue(req, 'url', url)
end

parserMT.onStatus =  function(req, status)
	accumulateChunkedValue(req, 'statusMesg', status)
end

parserMT.onBody = function(req, chunk)
    local bodyChunks = rawget(req, 'bodyChunks')
    if not bodyChunks then
        bodyChunks = luaw_lib.createDict(4, 0)
        req.bodyChunks = bodyChunks
    end 
    table.insert(bodyChunks, chunk)
end

parserMT.onMesgComplete = function(req, keepAlive)
	-- for the rare boundary case of chunked transfer encoding, where headers may continue
	-- after the last body chunk 
	handleAccHttpHeader(req)
	handleKeepAlive(req, keepAlive)
	req.luaw_mesg_done = true
	req.luaw_headers_done = true
end


local function shouldCloseConnection(req)
    if req and req.headers then
        local val = req.headers['Connection']
        if ((val)and(val:lower() == 'close')) then
            return true
        end
    end
end

local function readAndParse(req)
    local status, mesg = assert(req.luaw_conn:read(req.readTimeout))
    assert(req.luaw_parser:parseHttpBuffer(req, req.luaw_conn))

    if mesg == 'EOF' then 
        req.luaw_headers_done = true
        req.luaw_mesg_done = true 
        req:addHeader('Connection', 'close')
    end
    return req.luaw_headers_done, req.luaw_mesg_done
end

local function isComplete(req)
    return rawget(req, 'luaw_mesg_done')
end

local function headersDone(req)
    return rawget(req, 'luaw_headers_done')
end

local function parseParams(req)
    local params = rawget(req, 'params')
    if params then return params end
    
    if not params then
        params = luaw_lib.createDict(0, 16)
    end
    
    -- POST form params
    local contentType = req.headers['Content-Type']
    if ((contentType) and (contentType:lower() == 'application/x-www-form-urlencoded')) then
        local status, errMesg = luaw_lib:urlDecode(req.body, params)
    end
    
    -- GET query params
    local queryString = req:getParsedURL().queryString
    if queryString then
        luaw_lib:urlDecode(queryString, params)
    end

    req.params = params
    return params
end

local function readFull(req)
    -- loop and block till the body is completely parsed
    local headersDone = false
    local mesgDone = false
    while (not mesgDone) do
        headersDone, mesgDone = req:readAndParse()
    end
 
    local bodyChunks = rawget(req, 'bodyChunks')
    local body = ""
    if (bodyChunks) then
        if (#bodyChunks > 0) then
            body = table.concat(bodyChunks)
        end
        req.bodyChunks = nil
    end

    req.body = body    
    parseParams(req)    
    return body
end

local function getParsedURL(req)
    local parsedURL = rawget(req, 'parsedURL')
    if parsedURL then return parsedURL end
    local url = req.url

    if url then
        local method = req.method
        parsedURL = luaw_lib.parseURL(url, ((method) and (string.upper(method) == "CONNECT")))
    else
        parsedURL = {}
    end
    req.parsedURL = parsedURL
    return parsedURL
end

local function clearArrayPart(t)
    local len = #t
    for i=1,len do
        table.remove(t)
    end
end

local function readStreaming(req)
    if not rawget(req, 'luaw_mesg_done') then
        local headersDone, mesgDone = req:readAndParse()
        local bodyChunks = rawget(req, 'bodyChunks')
        local body = nil
        if ((bodyChunks)and(#bodyChunks > 0)) then
            body = table.concat(bodyChunks)
            clearArrayPart(bodyChunks)
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
        local encodedParams = luaw_lib.createDict(16, 0)
        for key, val in pairs(params) do
            table.insert(encodedParams, urlEncode(key))
            table.insert(encodedParams, "=")
            table.insert(encodedParams, urlEncode(val))
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

local function setStatus(resp, statusCode)
    resp.statusCode = statusCode
    resp.statusMesg = http_status_codes[statusCode]
end

local function firstResponseLine(resp)
    local line = {"HTTP/", resp.major_version, ".", resp.minor_version, 
        " ", resp.statusCode, " ", resp.statusMesg, CRLF}
    return table.concat(line)
end

local function firstRequestLine(req)
    local line = {req.method, " ", req:buildURL(), " HTTP/", req.major_version,
         ".", req.minor_version, CRLF}
    return table.concat(line)
end

local function fillHTTPBuffer(conn, str, isChunked)
    if ((isChunked) and (conn:bufferLength() == 0)) then
        -- reserve space at the beginning of the buffer for chunk length header
        assert(conn:appendBuffer('0000\r\n', isChunked))
    end
    return assert(conn:appendBuffer(str, isChunked))
end

local function writeHTTPBuffer(conn, isChunked, writeTimeout)
    if (isChunked) then
        assert(conn:addChunkEnvelope())
    end
    return assert(conn:write(writeTimeout))
end

local function bufferAndWrite(conn, str, isChunked, writeTimeout)
    local remainingCapacity, remainingStr = fillHTTPBuffer(conn, str, isChunked)
    while remainingStr do
        -- buffer full with input string remaining. Send buffer over wire to make space.
        assert(writeHTTPBuffer(conn, isChunked, writeTimeout))
        remainingCapacity, remainingStr =  fillHTTPBuffer(conn, remainingStr, isChunked)
    end
end

local function startStreaming(resp)
    resp.luaw_is_chunked = true
    resp:addHeader('Transfer-Encoding', 'chunked')
    
    local conn = resp.luaw_conn
    bufferAndWrite(conn, resp:firstLine(), resp.writeTimeout)
    
    local headers = resp.headers
    for name,value in pairs(headers) do
        bufferAndWrite(conn, tostring(name) .. ": " .. tostring(value) .. CRLF, resp.writeTimeout)
        headers[name] = nil
    end
    bufferAndWrite(conn, CRLF, resp.writeTimeout)
    assert(conn:write(resp.writeTimeout)) -- flush stream before actual chunked encoding starts

    local bodyChunks = rawget(resp, "bodyChunks")
    if ((bodyChunks)and(#bodyChunks > 0)) then
        bufferAndWrite(conn, table.concat(bodyChunks), true, resp.writeTimeout)
        resp.bodyChunks = nil
    end
end

local function appendBody(resp, bodyPart)
    if not bodyPart then return end
    
    if resp.luaw_is_chunked then
        -- send connection's buffer full of chunk as they fill
        bufferAndWrite(resp.luaw_conn, tostring(bodyPart), true, resp.writeTimeout)        
    else 
        -- buffer complete body in memory in order to calculate Content-Length
        local bodyChunks = rawget(resp, "bodyChunks")
        if not bodyChunks then
            bodyChunks = luaw_lib.createDict(4, 0)
            resp.bodyChunks = bodyChunks
        end
        table.insert(bodyChunks, bodyPart)
    end
end

local function writeFullBody(resp)
    if (resp.method == 'POST') then
        local encodedParams = urlEncodeParams(resp.params)
        if encodedParams then
            resp:addHeader('Content-Type', 'application/x-www-form-urlencoded')
            resp.bodyChunks = encodedParams
        end
    end

    local bodyChunks = rawget(resp, "bodyChunks")
    local body
    if (bodyChunks) then
        if (#bodyChunks > 0) then
            table.insert(bodyChunks, CRLF)
            body = table.concat(bodyChunks)
            resp:addHeader('Content-Length', #body)
        end
        resp.bodyChunks = nil
    end

    local conn = resp.luaw_conn
    bufferAndWrite(conn, resp:firstLine(), resp.writeTimeout)

    for name,value in pairs(resp.headers) do
        bufferAndWrite(conn, tostring(name) .. ": " .. tostring(value) .. CRLF, resp.writeTimeout)
    end
    bufferAndWrite(conn, CRLF, resp.writeTimeout)

    if ((body)and(#body > 0)) then
        bufferAndWrite(conn, body, resp.writeTimeout)
    end

    -- flush whatever is remaining in buffer
    assert(conn:write(resp.writeTimeout))
end


local function endStreaming(resp)
    local conn = resp.luaw_conn;
    assert(conn:addChunkEnvelope())
    bufferAndWrite(conn, "0" .. CRLF .. CRLF, resp.writeTimeout)        
    -- flush whatever is remaining in buffer
    assert(conn:write(resp.writeTimeout))
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

local connMT = getmetatable(luaw_lib.newConnection())
local readInternal = connMT.read
local writeInternal = connMT.write

connMT.read = function(self, readTimeout)
    readTimeout = readTimeout or DEFAULT_READ_TIMEOUT
    local status, mesg = readInternal(self, tid(), readTimeout)
    if ((status)and(mesg == 'WAIT')) then 
        -- nothing in buffer, wait for libuv on_read callback
        status, mesg = coroutine.yield(TS_BLOCKED_EVENT)
    end
    return status, mesg
end

connMT.write = function(self, writeTimeout)
    writeTimeout = writeTimeout or DEFAULT_WRITE_TIMEOUT
    local status, nwritten = writeInternal(self, tid(), writeTimeout)

    if ((status)and(nwritten > 0)) then
        -- there is something to write, yield for libuv callback
        status, nwritten = coroutine.yield(TS_BLOCKED_EVENT)  
    end
    return status, nwritten
end

luaw_lib.newServerHttpRequest = function(conn)
	local req = {
	    luaw_conn = conn,
        headers = luaw_lib.createDict(0, 16),
	    luaw_parser = luaw_lib:newHttpRequestParser(),
	    addHeader = addHeader,
	    shouldCloseConnection = shouldCloseConnection,
	    readAndParse = readAndParse,
	    isComplete = isComplete,
	    headersDone = headersDone,
	    getParsedURL = getParsedURL,
	    readFull = readFull,
	    readStreaming = readStreaming,
	    close = close
	}
    assert(conn:startReading())
	return req;
end

luaw_lib.newServerHttpResponse = function(conn)
    local resp = {
        luaw_conn = conn,
        major_version = 1,
        minor_version = 1,
        headers = luaw_lib.createDict(0, 16),
        addHeader = addHeader,
        shouldCloseConnection = shouldCloseConnection,
        setStatus = setStatus,
        firstLine = firstResponseLine,
        startStreaming = startStreaming,
        appendBody = appendBody,
        flush = flush,
        close = close 
    }
	return resp;
end

local function newClientHttpResponse(conn)
	local resp = {
	    luaw_conn = conn,
        headers = luaw_lib.createDict(0, 16),
	    luaw_parser = luaw_lib:newHttpResponseParser(),
	    addHeader = addHeader,
	    shouldCloseConnection = shouldCloseConnection,
	    readAndParse = readAndParse,
	    isComplete = isComplete,
	    headersDone = headersDone,
	    readFull = readFull,
	    readStreaming = readStreaming,
	    close = close
	}
    assert(conn:startReading())
	return resp;
end

local connectInternal = luaw_lib.connect

local function connect(req)
    local hostName, hostIP = req.hostName, req.hostIP
    assert((hostIP or hostName), "Either hostName or hostIP must be specified in request")
    
    local status = nil
    local threadId = tid()
    
    if not hostIP then
        status, hostIP = luaw_lib.resolveDNS(hostName, threadId)
        if status then
            -- initial resolveDNS succeeded, block for libuv callback
            status, hostIP = coroutine.yield(TS_BLOCKED_EVENT)
        end
        if not status then
            return status, hostIP
        end
    end

    local conn = nil    
    local connectTimeout = req.connectTimeout or DEFAULT_CONNECT_TIMEOUT

    status, conn = connectInternal(hostIP, req.port, threadId, connectTimeout)
    if status then 
        -- initial connect_req succeeded, block for libuv callback
        status, conn = coroutine.yield(TS_BLOCKED_EVENT)
    end
    return status, conn
end

local function connectReq(req)
    status, conn = assert(connect(req))
    req.luaw_conn = conn
    local resp = newClientHttpResponse(conn)
    resp.readTimeout = req.readTimeout
    resp.writeTimeout = req.writeTimeout
    return resp
end

local function execute(req)
    resp = req:connect()
    req:flush()
    resp:readFull()
    if resp:shouldCloseConnection() then
        resp:close()
    end
    return resp
end

luaw_lib.newClientHttpRequest = function()
    local req = {
        port = 80,
        major_version = 1,
        minor_version = 1,
        method = 'GET',
        headers = luaw_lib.createDict(0, 16),
        addHeader = addHeader,
        connect = connectReq,
        execute = execute,
        shouldCloseConnection = shouldCloseConnection,
        buildURL = buildURL,
        firstLine = firstRequestLine,
        startStreaming = startStreaming,
        appendBody = appendBody,
        flush = flush,
        close = close 
    }
	return req;
end


-- Timer functions
local timerMT = getmetatable(luaw_lib.newTimer())
local waitInternal = timerMT.wait

timerMT.wait = function(timer)
    local status, elapsed = waitInternal(timer, tid())
    if ((status) and (not elapsed)) then 
        -- timer not yet elapsed, wait for libuv on_read callback
        status, elapsed = coroutine.yield(TS_BLOCKED_EVENT)
    end
    return status, elapsed
end

timerMT.sleep = function(timer, timeout)
    assert(timer:start(timeout))
    timer:wait()
end

luaw_lib.splitter = function(splitCh)
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

luaw_lib.nilFn = function()
    return nil 
end

luaw_lib.formattedLine = function(str, lineSize, paddingCh, beginCh, endCh)
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

return luaw_lib