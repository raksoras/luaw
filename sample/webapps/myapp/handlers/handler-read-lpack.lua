registerHandler {
    method = 'GET',
    path = 'readlpack',

	handler = function(req, resp, pathParams)
        local backendReq = Luaw.newClientHttpRequest()
        backendReq.hostName = 'localhost'
        backendReq.port = 7001
        backendReq.url = '/myapp/genlpack'
        backendReq.method = 'GET'
        backendReq.headers = { Host = 'localhost' }
        local backendResp = backendReq:execute()
        local lpackReader = Luaw.lpack.newLPackReqReader(backendResp)
        local mesg = lpackReader:read()

        print('\n================================\n')
        debugDump(backendResp.headers)
        print('\n================================\n')
        debugDump(mesg)
        print('\n================================\n')
        return "OK"
	end
}
