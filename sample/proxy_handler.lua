local http_lib = require('luaw_http')
--[[
    Luaw allows you to replace it's default MVC/REST request handler with your own custom HTTP
request handler implementation. To override the default HTTP request handler just set Luaw object's
request_handler property to your custom Lua function. This function is passed in a low level connection
object for each incoming request instead of the normal request and response objects passed to REST handler.
The function is called on its own separate Luaw coroutine for each HTTP request so you don't have to worry
about multithreaded access to shared state inside the function.
]]

http_lib.request_handler =  function(conn)
    conn:startReading()

    -- loop to support HTTP 1.1 persistent (keep-alive) connections
    while true do
        local req = http_lib.newServerHttpRequest(conn)
        local resp = http_lib.newServerHttpResponse(conn)

        -- read and parse full request
        req:read()
        if (req.EOF) then
            conn:close()
            return "connection reset by peer"
        end

        local reqHeaders = req.headers
        local beHost =  reqHeaders['backend-host']
        local beURL = reqHeaders['backend-url']

        if (beHost and beURL) then
           local backendReq = http_lib.newClientHttpRequest()
           backendReq.hostName = beHost
           backendReq.url = beURL
           backendReq.method = 'GET'
           backendReq.headers = { Host = beHost }

           local status, backendResp = pcall(backendReq.execute, backendReq)
           if (status) then
               resp:setStatus(backendResp.status)
               resp:appendBody(backendResp.body)
               local beHeaders = backendResp.headers
               for k,v in pairs(beHeaders) do
                   if ((k ~= 'Transfer-Encoding')and(k ~= 'Content-Length')) then
                       resp:addHeader(k,v)
                   end
               end
               backendResp:close()
            else
               resp:setStatus(500)
               resp:appendBody("connection to backend server failed")
           end
        else
            resp:setStatus(400)
            resp:appendBody("Request must contain headers backend-host and backend-url\n")
        end

        local status, mesg = pcall(resp.flush, resp)
        if (not status) then
            conn:close()
            return error(mesg)
        end

        if (req:shouldCloseConnection() or resp:shouldCloseConnection()) then
            conn:close()
            return "connection reset by peer"
        end
    end
end
