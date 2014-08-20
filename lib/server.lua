local luaw_lib = require("luaw_lib")
local logging = require("luaw_logging")
local server = require("luaw_server")
local webapp = require("luaw_webapp")

local function proxyHTTPStreaming(conn)
    while true do
        local req = luaw_lib.newServerHttpRequest(conn)    
        local body = req:readFull()
        local url = req:getParsedURL()

        if ((url)and(url.path)) then
            local proxyReq = luaw_lib.newClientHttpRequest()
            proxyReq.hostName = "hacksubscriber.us-east-1.dyntest.netflix.net"
            proxyReq.method = 'GET'
            proxyReq.url = url.path
            proxyReq.port = 7001
            proxyReq.headers = { Host = "hacksubscriber.us-east-1.dyntest.netflix.net" }

            local proxyResp = proxyReq:connect()
            proxyReq:flush()

            local headersDone, mesgDone, body = false, false, nil
            while not headersDone do
                headersDone, mesgDone, body = proxyResp:readStreaming()
            end
            
            local resp = luaw_lib.newServerHttpResponse(conn)
            resp:setStatus(proxyResp.status)
            local headers = proxyResp.headers
            for k,v in pairs(headers) do
                if (k ~= 'Transfer-Encoding') then
                    resp:addHeader(k,v)
                end
            end
            
            resp:startStreaming()
            
            while true do
                if body then 
                    resp:appendBody(body) 
                end
                if mesgDone then break end
                headersDone,  mesgDone, body = proxyResp:readStreaming()
            end

            resp:flush()
            proxyResp:close()
            
            if (req:shouldCloseConnection() or resp:shouldCloseConnection()) then
                resp:close()
                break
            end
        end
    end
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
