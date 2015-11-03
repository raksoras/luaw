local utils_lib = require('luaw_utils')
local http_lib = require('luaw_http')
local lpack = require('luapack')

webapp:registerResource {
    method = 'GET',
    path = 'readlpack',

    handler = function(httpConn)
        local backendReq = http_lib.newClientHttpRequest()
        backendReq.hostName = 'localhost'
        backendReq.port = 7001
        backendReq.url = '/myapp/genlpack'
        backendReq.method = 'GET'
        backendReq.headers = { Host = 'localhost' }
        local backendResp = backendReq:execute()
        local lpackReader = lpack.newLPackReqReader(backendResp)
        local mesg = lpackReader:read()

        print('\n================================\n')
        utils_lib.debugDump(backendResp.headers)
        print('\n================================\n')
        utils_lib.debugDump(mesg)
        print('\n================================\n')
        resp:appendBody("OK")
    end
}
