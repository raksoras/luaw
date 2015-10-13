--[[
Copyright (c) 2015 raksoras

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]

local constants = require('luaw_constants')
local scheduler = require('luaw_scheduler')

-- Global reference for luaw_server.c to get hold of at init time
luaw_scheduler = scheduler

local TS_BLOCKED_EVENT = constants.TS_BLOCKED_EVENT
local DEFAULT_CONNECT_TIMEOUT = constants.DEFAULT_CONNECT_TIMEOUT
local DEFAULT_READ_TIMEOUT = constants.DEFAULT_READ_TIMEOUT
local DEFAULT_WRITE_TIMEOUT = constants.DEFAULT_WRITE_TIMEOUT
local CONN_BUFFER_SIZE = constants.CONN_BUFFER_SIZE

local rawStartReading = luaw_tcp_lib.startReading
local rawRead = luaw_tcp_lib.read
local rawWrite = luaw_tcp_lib.write
local rawClose = luaw_tcp_lib.close
local resolveDNS = luaw_tcp_lib.resolveDNS
local rawConnect = luaw_tcp_lib.connect


function asyncRead(self, buff, readTimeout)
    readTimeout = readTimeout or DEFAULT_READ_TIMEOUT
    assert(rawRead(self.luaw_raw_conn, buff, scheduler.tid(), readTimeout))  
    -- initial call succeeded, wait for libuv callback
    assert(coroutine.yield(TS_BLOCKED_EVENT))
end

local connMT = {
    startReading = function(self)
        assert(rawStartReading(self.luaw_raw_conn))
    end,
    
    read = asyncRead,

    readMinLength = function(self, buff, readTimeout, minReadLen)
        if (buff:capacity() < minReadLen) then
            error("Buffer capacity is less than minimum read length requested")
        end

        while (buff:length() < minReadLen) do
            assert(asyncRead(self, buff, readTimeout))
        end
    end,

    write = function(self, wbuffers, writeTimeout)
        writeTimeout = writeTimeout  or DEFAULT_WRITE_TIMEOUT
        local sc, nwritten = rawWrite(self.luaw_raw_conn, scheduler.tid(), #wbuffers, wbuffers, writeTimeout)
        assert(sc, nwritten)
        if (nwritten > 0 ) then
            -- there is something to write, yield for libuv callback
            local s, m = coroutine.yield(TS_BLOCKED_EVENT)
        end
    end,

    close = function(self)
        local rawConn = self.luaw_raw_conn
        if (rawConn) then
            rawClose(rawConn)
            self.luaw_raw_conn = nil
        end
    end,

    __gc = function(self)
        local rawConn = self.luaw_raw_conn
        if (rawConn) then
            print("Luaw cleaned up unclosed connection")
            rawClose(rawConn)
            self.luaw_raw_conn = nil
        end
    end
}

connMT.__index = connMT

function wrapConnection(rawConn)
    local conn = { luaw_raw_conn = rawConn }
    setmetatable(conn, connMT)
    return conn
end
luaw_tcp_lib.wrapConnection = wrapConnection

luaw_tcp_lib.connectByIP = function(hostIP, port, connectTimeout)
    assert(hostIP, "IP must be specified in request")
    
    local threadId = scheduler.tid()
    connectTimeout = connectTimeout or DEFAULT_CONNECT_TIMEOUT
    local rawConn, mesg = rawConnect(hostIP, port, threadId, connectTimeout)
    assert(rawConn, mesg)
    
    -- initial connect_req succeeded, block for libuv callback
    assert(coroutine.yield(TS_BLOCKED_EVENT))
    return wrapConnection(rawConn)
end

luaw_tcp_lib.connectByHostName = function(hostName, port, connectTimeout)
    assert(hostName, "hostName must be specified in request")
    
    local threadId = scheduler.tid()    
    assert(resolveDNS(hostName, threadId))
    
    local status, hostIP = coroutine.yield(TS_BLOCKED_EVENT)
    assert(status, hostIP)
    
    connectTimeout = connectTimeout or DEFAULT_CONNECT_TIMEOUT
    local rawConn, mesg = rawConnect(hostIP, port, threadId, connectTimeout)
    assert(rawConn, mesg)

    -- initial connect_req succeeded, block for libuv callback
    assert(coroutine.yield(TS_BLOCKED_EVENT))
    return wrapConnection(rawConn)
end

return luaw_tcp_lib
