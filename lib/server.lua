local luaw_lib = require("luaw_lib")
local logging = require("luaw_logging")
local server = require("luaw_server")
local webapp = require("luaw_webapp")

local function proxyHTTPStreaming(conn)
    local req = luaw_lib.newServerHttpRequest(conn)
    local resp = luaw_lib.newServerHttpResponse(conn)

    while (true) do
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
                print("PARSE_HEADERS {\n")
                headersDone, mesgDone, body = proxyResp:readStreaming()
            end
            print("}\n")

            resp:setStatus(proxyResp.status)
            local headers = proxyResp.headers
            for k,v in pairs(headers) do
                if (k ~= 'Transfer-Encoding') then
                    resp:addHeader(k,v)
                end
            end

            print("START_STREAMING{\n")
            resp:startStreaming()
            print("}\n")

            while true do
                print("WRITE_BODY{\n")
                if body then
                    resp:appendBody(body)
                end
                if mesgDone then break end
                print("}\n\nPARSE_BODY{\n")
                headersDone,  mesgDone, body = proxyResp:readStreaming()
                print("}\n\n")
            end

            resp:flush()
            proxyResp:close()
        end

        if (req:shouldCloseConnection() or resp:shouldCloseConnection()) then break end

--        req:reset()
--        resp:reset()
    end

--    req:close()
--    resp:close()
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
while status do
    print("------------------<poll>------------------------")
    status = blockingPoll()
    -- bottom half processing of the runnable user threads
    local runnableCount = runQueueSize()
    for i=1, runnableCount do
        local tid = runNextFromRunQueue()
    end
end

print("Stoping server...")
server.stop();
print("Server stopped")
