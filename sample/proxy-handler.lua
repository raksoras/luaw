Luaw.request_handler = function(conn)
    assert(conn:startReading())

    -- loop to support HTTP 1.1 persistent (keep-alive) connections
    while true do
	    conn:startReading()
		local resp = Luaw.newServerHttpResponse(conn)
        local req = Luaw.newServerHttpRequest(conn)

        -- read and parse full request
print("\n\nbefore readfull")
        req:readFull() -- read and parse full request
print("after readFull")
    	local backendHost = req.headers['backend-host']
    	local backendURL = req.headers['backend-url']

    	if ((backendHost)and(backendURL)) then
       		 --[[ Create a new Luaw HTTP client request ]]
        	local backendReq = Luaw.newClientHttpRequest()
        	backendReq.hostName = backendHost
        	backendReq.url = backendURL
        	backendReq.method = 'GET'
        	backendReq.headers = { Host = backendHost }
print("before execute")
			local backendResp = backendReq:execute()
print("after execute")

        	--[[Send the HTTP status returned by the backend server back to the client, along with other response headers.]]
        	resp:setStatus(backendResp.status)
        	local backendHeaders = backendResp.headers
        	for k,v in pairs(backendHeaders) do
           		if ((k ~= 'Transfer-Encoding')and(k ~= 'Content-Length')) then
                	resp:addHeader(k,v)
            	end
        	end
print("#body="..#backendResp.body)
			resp:appendBody(backendResp.body)
   	 		backendResp:close()
    	else
        	resp:setStatus(400)
        	resp:appendBody("Headers backend-host and backend-url must be present")
    	end

print("before flush")
		resp:flush()
print("after flush")
       	if (req:shouldCloseConnection() or resp:shouldCloseConnection()) then
           	resp:close()
			req:close()
       		break
       	end
	end
print("Closed connection!!!!")
end
