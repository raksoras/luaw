local scheduler = require("luaw_scheduler")
local timer_lib = require('luaw_timer')

local function timerFn(id, delay)
    print(id.."# sleeping  for "..delay.." seconds")
    local timer = timer_lib.newTimer()
    timer:sleep(delay)
    print(id.."# woke up after "..delay.." seconds")
    return(id.."# done")
end

registerHandler {
    method = 'GET',
    path = '/threads',

    handler = function(req, resp)
        local t1 = scheduler.startUserThread(timerFn, 1, 2000)
        local t2 = scheduler.startUserThread(timerFn, 2, 5000)
        local t3 = scheduler.startUserThread(timerFn, 3, 7000)

        print(t1:join())
        print(t3:join())
        print(t2:join())
        print("Handler resumed")
        
        resp:appendBody('OK')
    end
}
