Luaw = require("luaw_lib")
logging = require("luaw_logging")
scheduler = require("luaw_scheduler")
webapp = require("luaw_webapp")

-- Init deployed webapps
if ((webapp_config)and(webapp_config.webapps_dir)) then
    local webapps = webapp.findFiles(webapp_config.webapps_dir, ".-%-webapp%.cfg", {})
    if webapps then
        for i, webAppCfgFile in ipairs(webapps) do
            Luaw.formattedLine('Starting webapp '..i..'# '..webAppCfgFile, 80, '-', '\n')
            dofile(webAppCfgFile) -- defines global variable webapp
            local app = webapp.loadWebApp()
            webapp.startWebApp(app)
            Luaw.formattedLine('Webapp '..i..'# '..webAppCfgFile..' started', 80, '-', '\n')
            webapp = nil  -- reset global variable
        end
    end
end




function request_handler(conn)
    local req = Luaw.newServerHttpRequest(conn)
    local resp = Luaw.newServerHttpResponse(conn)

    while (true) do
        local body = req:readFull()
        local url = req:getParsedURL()

        if ((url)and(url.path)) then
            local proxyReq = Luaw.newClientHttpRequest()
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
        end

        if (req:shouldCloseConnection() or resp:shouldCloseConnection()) then break end

        req:reset()
        resp:reset()
    end

    req:close()
    resp:close()
end

print("Whoa, I got run!")