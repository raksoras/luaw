local http_lib = require('luaw_http')
local tcp_lib = require("luaw_tcp")
local scheduler = require("luaw_scheduler")
--[[
    Luaw allows you to replace it's default MVC/REST request handler with your own custom HTTP
request handler implementation. To override the default HTTP request handler just set Luaw object's
request_handler property to your custom Lua function. This function is passed in a low level connection
object for each incoming request instead of the normal request and response objects passed to REST handler.
The function is called on its own separate Luaw coroutine for each HTTP request so you don't have to worry
about multithreaded access to shared state inside the function.
]]

local function request_handler(conn)
    -- read client request
    conn:readComplete()
    
    local reqHeaders = conn.requestHeaders
    local beHost =  reqHeaders['backend-host']
    local beURL = reqHeaders['backend-url']

    if (beHost and beURL) then
        -- proxy client request to backend server
        local backendConn = assert(http_lib.connectByHostName(beHost, 80))
        backendConn.url = beURL
        backendConn.method = 'GET'
        backendConn.requestHeaders['Host'] = beHost
        backendConn:GET()

        -- proxy backend server's response back to the client
        conn:setStatus(backendConn.status)
        conn:appendBody(backendConn:getBody())
        local beHeaders = backendConn.responseHeaders
        for k,v in pairs(beHeaders) do
            if ((k ~= 'Transfer-Encoding')and(k ~= 'Content-Length')) then
                conn:addHeader(k,v)
            end
        end
        backendConn:close()
    else
        conn:setStatus(400)
        conn:appendBody("Request must contain headers backend-host and backend-url\n")
    end

    conn:flush()

    if (conn:shouldCloseConnection()) then
        conn:close()
        error("Connection reset by peer")
    end
    
    --free bufffers
    conn:free()
end

function proxy(rawConn)
    tcp_lib.startReading(rawConn)
    -- loop to support HTTP 1.1 persistent (keep-alive) connections
    while true do    
        local conn = tcp_lib.wrapConnection(rawConn)
        http_lib.addHttpServerMethods(conn)
        local status, mesg = pcall(request_handler, conn)
        if (not status) then
            conn:close()
            error(mesg)
        end    
    end
end
