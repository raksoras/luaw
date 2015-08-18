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


local timerMT = getmetatable(luaw_timer_lib.newTimer())
local waitInternal = timerMT.wait

timerMT.wait = function(timer)
    local status, elapsed = waitInternal(timer, scheduler.tid())
    if ((status) and (not elapsed)) then
        -- timer not yet elapsed, wait for libuv on_timeout callback
        status, elapsed = coroutine.yield(TS_BLOCKED_EVENT)
    end
    return status, elapsed
end

timerMT.sleep = function(timer, timeout)
    assert(timer:start(timeout))
    timer:wait()
end

local function chronometer(step)
    local timer = luaw_timer_lib.newTimer()
    while (true) do
        timer:sleep(step)
        scheduler.updateCurrentTime(os.time())
    end
end
scheduler.updateCurrentTime(os.time())
scheduler.startNewThread(chronometer, 200)

return luaw_timer_lib
