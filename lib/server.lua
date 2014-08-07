local luaw_lib = require("luaw_lib")
local logging = require("luaw_logging")
local server = require("luaw_server")
local webapp = require("luaw_webapp")

local config = server.loadConfiguration(...)
config.request_handler = webapp.serviceHTTP

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
