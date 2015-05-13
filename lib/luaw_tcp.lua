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

local DEFAULT_CONNECT_TIMEOUT = constants.DEFAULT_CONNECT_TIMEOUT
local DEFAULT_READ_TIMEOUT = constants.DEFAULT_READ_TIMEOUT
local DEFAULT_WRITE_TIMEOUT = constants.DEFAULT_WRITE_TIMEOUT
local CONN_BUFFER_SIZE = constants.CONN_BUFFER_SIZE

local conn = luaw_tcp_lib.newConnection();
local connMT = getmetatable(conn)
conn:close()
local startReadingInternal = connMT.startReading
local readInternal = connMT.read
local writeInternal = connMT.write

connMT.startReading = function(self)
    local status, mesg = startReadingInternal(self)
    assert(status, mesg)
end

connMT.read = function(self, readTimeout)
    local status, str = readInternal(self, scheduler.tid(), readTimeout or DEFAULT_READ_TIMEOUT)
    if ((status)and(not str)) then
        -- nothing in buffer, wait for libuv on_read callback
        status, str = coroutine.yield(TS_BLOCKED_EVENT)
    end
    return status, str
end

connMT.write = function(self, str, writeTimeout)
    local status, nwritten = writeInternal(self, scheduler.tid(), str, writeTimeout  or DEFAULT_WRITE_TIMEOUT)
    if ((status)and(nwritten > 0)) then
        -- there is something to write, yield for libuv callback
        status, nwritten = coroutine.yield(TS_BLOCKED_EVENT)
    end
    assert(status, nwritten)
    return nwritten
end

local connectInternal = luaw_tcp_lib.connect

local function connect(hostIP, hostName, port, connectTimeout)
    assert((hostName or hostIP), "Either hostName or hostIP must be specified in request")
    local threadId = scheduler.tid()
    if not hostIP then
        local status, mesg = luaw_tcp_lib.resolveDNS(hostName, threadId)
        assert(status, mesg)
        status, mesg = coroutine.yield(TS_BLOCKED_EVENT)
        assert(status, mesg)
        hostIP = mesg
    end

    local connectTimeout = connectTimeout or DEFAULT_CONNECT_TIMEOUT
    local conn, mesg = connectInternal(hostIP, port, threadId, connectTimeout)

    -- initial connect_req succeeded, block for libuv callback
    assert(coroutine.yield(TS_BLOCKED_EVENT))
    return conn, mesg
end

luaw_tcp_lib.connect = connect

return luaw_tcp_lib