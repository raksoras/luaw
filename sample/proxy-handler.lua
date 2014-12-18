Luaw.request_handler = function(conn)
    local req = Luaw.newServerHttpRequest(conn)
    local resp = Luaw.newServerHttpResponse(conn)

    local headersDone, mesgDone = false, false
    while (not headersDone) do
        headersDone, mesgDone = req:readAndParse()
    end

    local proxyHost = req.headers['proxy-host']
    local proxyURL = req.headers['proxy-url']

    if ((proxyHost)and(proxyURL)) then
        --[[ Create a new Luaw async HTTP client request ]]
        local proxyReq = Luaw.newClientHttpRequest()
        proxyReq.hostName = proxyHost
        proxyReq.url = proxyURL
        proxyReq.method = 'GET'
        proxyReq.headers = { Host = proxyHost }

        local proxyResp = proxyReq:connect()
        proxyReq:flush()

        local proxyHeadersDone, proxyMesgDone, prxoyBody = false, false, nil
        while not proxyHeadersDone do
            proxyHeadersDone, proxyMesgDone, prxoyBody = proxyResp:readStreaming()
        end

        --[[Send the HTTP status returned by the backend server back to the client, along with other response headers.]]
        resp:setStatus(proxyResp.status)
        local proxyHeaders = proxyResp.headers
        for k,v in pairs(proxyHeaders) do
            if (k ~= 'Transfer-Encoding') then
                resp:addHeader(k,v)
            end
        end

        resp:startStreaming()


        while true do
            if prxoyBody then
                resp:appendBody(prxoyBody)
            end
            if proxyMesgDone then
                break
            end
            proxyHeadersDone, proxyMesgDone, prxoyBody = proxyResp:readStreaming()
        end

    else
        resp:setStatus(400)
        resp:appendBody("Headers proxy-host and proxy-url must be present")
    end

    resp:flush()
    proxyResp:close()
    req:close()
    resp:close()
end
