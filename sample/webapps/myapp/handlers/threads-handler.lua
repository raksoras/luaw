local scheduler = require("luaw_scheduler")
local timer_lib = require('luaw_timer')

local function timerFn(id, delay)
    print(id.."# sleeping  for "..delay.." seconds")
    local timer = timer_lib.newTimer()
    timer:sleep(delay)
    print(id.."# woke up after "..delay.." seconds")
    return(id.."# done")
end

webapp:registerResource {
    method = 'GET',
    path = '/threads',

    handler = function(httpConn)
        local t1 = scheduler.startNewThread(timerFn, 1, 2000)
        local t2 = scheduler.startNewThread(timerFn, 2, 5000)
        local t3 = scheduler.startNewThread(timerFn, 3, 7000)

        print(t1:join())
        print(t3:join())
        print(t2:join())
        print("Handler resumed")
        
        httpConn:appendBody('OK')
    end
}