local luaw_lib = require("luaw_lib")
local logging = require("luaw_logging")
local server = require("luaw_server")
local webapp = require("luaw_webapp")

local function proxyHTTPStreaming(conn)
    local req = luaw_lib.newServerHttpRequest(conn)
    local resp = luaw_lib.newServerHttpResponse(conn)

    while (true) do
print(11)
        local body = req:readFull()
        local url = req:getParsedURL()

        if ((url)and(url.path)) then
            local proxyReq = luaw_lib.newClientHttpRequest()
--            proxyReq.hostName = "hacksubscriber.us-east-1.dyntest.netflix.net"
            proxyReq.hostName = "www.ebay.com"
            proxyReq.method = 'GET'
            proxyReq.url = url.path
--            proxyReq.port = 7001
            proxyReq.headers = { Host = "www.ebay.com" }

            local proxyResp = proxyReq:connect()
            proxyReq:flush()

            local headersDone, mesgDone, body = false, false, nil
            while not headersDone do
                headersDone, mesgDone, body = proxyResp:readStreaming()
            end

print("headers end "..tostring(mesgDone))
            resp:setStatus(proxyResp.status)
            local headers = proxyResp.headers
            for k,v in pairs(headers) do
                if (k ~= 'Transfer-Encoding') then
                    resp:addHeader(k,v)
                end
            end
print(39)
            resp:startStreaming()
print(41)
            while true do
                if body then
                    resp:appendBody(body)
                end
print(46)
                if mesgDone then break end
print("read body")
                headersDone,  mesgDone, body = proxyResp:readStreaming()
            end
print("req/resp end")
            resp:flush()
            proxyResp:close()
        end
print("conn end")
        if (req:shouldCloseConnection() or resp:shouldCloseConnection()) then break end

        req:reset()
        resp:reset()
    end

    req:close()
    resp:close()
end

local config = server.loadConfiguration(...)
config.request_handler = proxyHTTPStreaming

print("Starting server...")

logging.init(config)
local server = server.init(config)
webapp.init(config)
server.start()

print("Server started")

local blockingPoll = server.blockingPoll
local runQueueSize = server.runQueueSize
local runNextFromRunQueue = server.runNextFromRunQueue

local status = true
local i = 1
while status do
    print("------------------ Poll# "..i.." ------------------------")
    status = blockingPoll()
    -- bottom half processing of the runnable user threads
    local runnableCount = runQueueSize()
    for i=1, runnableCount do
        local tid = runNextFromRunQueue()
    end
    i = i + 1
end

print("Stoping server...")
server.stop();
print("Server stopped")
