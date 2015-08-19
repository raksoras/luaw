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
local scheduler = require("luaw_scheduler")

local TS_BLOCKED_EVENT = constants.TS_BLOCKED_EVENT

local rawNewTimer = luaw_timer_lib.newTimer
local rawStart = luaw_timer_lib.start
local rawStop = luaw_timer_lib.stop
local rawWait = luaw_timer_lib.wait
local rawDelete = luaw_timer_lib.delete

local start = function(self, timeout)
    return rawStart(self.luaw_raw_timer, timeout)
end

local wait = function(self)
    local status, elapsed = rawWait(self.luaw_raw_timer, scheduler.tid())
    if ((status) and (not elapsed)) then
        -- timer not yet elapsed, wait for libuv on_timeout callback
        status, elapsed = coroutine.yield(TS_BLOCKED_EVENT)
    end
    return status, elapsed
end

local delete = function(self)
    local rawTimer = self.luaw_raw_timer
    if (rawTimer) then
        rawDelete(rawTimer)
        self.luaw_raw_timer = nil
    end
end

local timerMT = {
    start = start,
    wait = wait,

    sleep = function(self, timeout)
        assert(start(self, timeout))
        wait(self)
    end,
    
    delete = delete,
    __gc = delete
}

timerMT.__index = timerMT

luaw_timer_lib.newTimer = function()
    local rawTimer = rawNewTimer();
    local timer = { luaw_raw_timer = rawTimer }
    setmetatable(timer, timerMT)
    return timer
end

-- for efficient current time caching
local tick = 200

local chronos = luaw_timer_lib.newTimer()
chronos:start(tick)

local function chronometer()
    while (true) do
        chronos:wait()
        scheduler.updateCurrentTime(os.time())
        chronos:start(tick)
    end
end

scheduler.updateCurrentTime(os.time())
scheduler.startNewThread(chronometer)

return luaw_timer_lib
