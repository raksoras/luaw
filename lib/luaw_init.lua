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

luaw_utils = require("luaw_utils")
luaw_logging = require("luaw_logging")
luaw_lpack = require("luapack")
luaw_scheduler = require("luaw_scheduler")
luaw_tcp = require("luaw_tcp")
luaw_timer = require("luaw_timer")
luaw_http = require("luaw_http")
luaw_webapp = require("luaw_webapp")

local function chronometer(step)
    local timer = luaw_timer.newTimer()
    while (true) do
        timer:sleep(step)
        luaw_scheduler.updateCurrentTime(os.time())
    end
end

luaw_scheduler.updateCurrentTime(os.time())
luaw_scheduler.startNewThread(chronometer, 200)

luaw_webapp.init()