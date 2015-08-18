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
    local status, mesg = rawRead(self.luaw_raw_conn, buff, scheduler.tid(), readTimeout)
    if (status) then
        -- wait for libuv on_read callback
        status, mesg = coroutine.yield(TS_BLOCKED_EVENT)
    end
    return status, mesg
end

function close_connection(conn)
    local rawConn = conn.luaw_raw_conn
    if (rawConn) then
        rawClose(rawConn)
        conn.luaw_raw_conn = nil
    end
end

local connMT = {
    startReading = function(self)
        local status, mesg = rawStartReading(self.luaw_raw_conn)
        assert(status, mesg)
    end,
    
    read = asyncRead,

    readMinLength = function(self, buff, readTimeout, minReadLen)
        if (buff:capacity() < minReadLen) then
            return false, "Buffer capacity is less than minimum read length requested"
        end

        local status, mesg = true
        while ((buff:length() < minReadLen)and(status)) do
            status, mesg = asyncRead(self, buff, readTimeout)
        end
        return status, mesg
    end,

    write = function(self, wbuffers, writeTimeout)
        local status, nwritten = rawWrite(self.luaw_raw_conn, scheduler.tid(), #wbuffers, wbuffers, writeTimeout  or DEFAULT_WRITE_TIMEOUT)
        if ((status)and(nwritten > 0)) then
            -- there is something to write, yield for libuv callback
            status, nwritten = coroutine.yield(TS_BLOCKED_EVENT)
        end
        assert(status, nwritten)
        return nwritten
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

local function connect(hostIP, hostName, port, connectTimeout)
    assert((hostName or hostIP), "Either hostName or hostIP must be specified in request")
    local threadId = scheduler.tid()
    if not hostIP then
        local status, mesg = resolveDNS(hostName, threadId)
        assert(status, mesg)
        status, mesg = coroutine.yield(TS_BLOCKED_EVENT)
        assert(status, mesg)
        hostIP = mesg
    end

    local connectTimeout = connectTimeout or DEFAULT_CONNECT_TIMEOUT
    local rawConn, mesg = rawConnect(hostIP, port, threadId, connectTimeout)
    -- initial connect_req succeeded, block for libuv callback
    assert(coroutine.yield(TS_BLOCKED_EVENT))
    
    local conn = wrapConnection(rawConn)
    return conn, mesg
end
luaw_tcp_lib.connect = connect

return luaw_tcp_lib
