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

local luaw_lib = require("luaw_lib")
local ds_lib = require('luaw_data_structs_lib')
local logging = require('luaw_logging')

-- Constants
local TS_RUNNABLE = Luaw.TS_RUNNABLE
local TS_DONE = Luaw.TS_DONE
local TS_BLOCKED_EVENT = Luaw.TS_BLOCKED_EVENT
local TS_BLOCKED_THREAD = Luaw.TS_BLOCKED_THREAD

local END_OF_CALL = {"END_OF_CALL"}
local END_OF_THREAD = {"END_OF_THREAD"}

local UPDATE_TIME_COUNTER_LIMIT = 10

-- Scheduler object
local scheduler = {}

-- scheduler state
local threadRegistry = ds_lib.newRegistry(luaw_server_config.thread_pool_size or 1024)
local threadPool = ds_lib.newRingBuffer(luaw_server_config.thread_pool_size or 1024)
local timesReuseThread = luaw_server_config.thread_reuse_limit or 1024
local runQueueLen = 0
local runQueueHead = nil
local runQueueTail = nil
local currentRunningThreadCtx = nil
local updateTimeCyclingCounter = 0
local currentTime


scheduler.updateCurrentTime = function ()
    updateTimeCyclingCounter = updateTimeCyclingCounter + 1
    if (updateTimeCyclingCounter >= UPDATE_TIME_COUNTER_LIMIT) then
        currentTime = os.time()
        logging.updateCurrentTime(currentTime)
        updateTimeCyclingCounter = 0
    end
end

scheduler.time = function()
    return currentTime
end

-- returns current running thread's id
scheduler.tid = function()
    if currentRunningThreadCtx then
        return currentRunningThreadCtx.tid
    end
    return nil
end

local function threadRunLoop(fn, arg1, arg2, arg3, arg4)
    local i = 0
    while i <= timesReuseThread do
        fn, arg1, arg2, arg3, arg4 = coroutine.yield(END_OF_CALL, fn(arg1, arg2, arg3, arg4))
        i = i+1
    end
    return END_OF_THREAD, fn(arg1, arg2, arg3, arg4)
end

local function userThreadRunner(userThreadFn, ...)
    -- We have captured user thread function along with its arguments on a coroutine stack.
    -- Yield now so that scheduler can add this thread in run queue for "bottom half"
    -- processing later and original calling thread can resume.
    coroutine.yield(TS_RUNNABLE)
    -- At this point we have been resumed by thread scheduler during the "bottom half" run
    -- queue processing bu the scheduler so run the actual user thread function.
    return userThreadFn(...)
end

local function addToRunQueue(threadCtx)
    if not runQueueTail then
        runQueueHead = threadCtx
        runQueueTail = threadCtx
    else
        runQueueTail.nextThread = threadCtx
        runQueueTail = threadCtx
    end
    runQueueLen = runQueueLen + 1
    threadCtx.state = TS_RUNNABLE
end

local function newThread()
    local t = threadPool:take()
    if not t then
        t = coroutine.create(threadRunLoop)
    end

    local threadCtx = { thread = t, requestCtx = {} }
    -- anchor thread in registry to prevent GC
    local ref = threadRegistry:ref(threadCtx)
    threadCtx.tid = ref
    return threadCtx
end

local function unblockJoinedThreadIfAny(threadCtx, status, retVal)
    local joinedTC = threadCtx.joinedBy
    if joinedTC then
        local count = joinedTC.joinCount
        count = count -1
        joinedTC.joinCount = count
        if (count <= 0) then
            addToRunQueue(joinedTC)
        end
    end
end

local function afterResume(threadCtx, state, retVal)
    threadCtx.state, threadCtx.result = state, retVal
    currentRunningThreadCtx = nil
    if (state == TS_DONE) then
        return true, retVal
    end
    return false, retVal
end

local function resumeThread(threadCtx, ...)
    currentRunningThreadCtx = threadCtx
    local t = threadCtx.thread
    local tid = threadCtx.tid

    scheduler.updateCurrentTime()

    context = threadCtx.requestCtx  -- TLS, per thread context
    local status, state, retVal = coroutine.resume(t, ...)
    context = nil -- reset TLS context

    if not status then
        -- thread ran into error
        print("Error: "..tostring(state))
        state = END_OF_THREAD
        -- thread has blown its stack so let it get garbage collected
        t = nil
    end

    if ((state == END_OF_THREAD)or(state == END_OF_CALL)) then
        threadRegistry:unref(tid)
        threadCtx.thread = nil
        threadCtx.requestCtx = nil
        if ((state == END_OF_CALL) and (t)) then
            -- thread is still alive, return it to free pool if possible
            threadPool:offer(t)
        end
        unblockJoinedThreadIfAny(threadCtx, status, retVal)
        return afterResume(threadCtx, TS_DONE, retVal)
    end

    if ((state == TS_BLOCKED_EVENT)or(state == TS_BLOCKED_THREAD)) then
        -- thread will later be resumed by libuv call back
        return afterResume(threadCtx, state, retVal)
    end

    -- Thread yielded, but is still runnable. Add it back to the run queue
    addToRunQueue(threadCtx)
    return afterResume(threadCtx, TS_RUNNABLE, retVal)
end

function resumeThreadId(tid, ...)
    local threadCtx = threadRegistry[tid]
    if not threadCtx then error("Invalid thread Id "..tostring(tid)) end
    return resumeThread(threadCtx, ...)
end

scheduler.resumeThreadId = resumeThreadId

function startSystemThread(serviceFn, conn, ...)
    local threadCtx = newThread()
    threadCtx.state = TS_RUNNABLE
    local isDone = resumeThread(threadCtx, serviceFn, conn, ...)
    return isDone, threadCtx.tid
end

scheduler.startSystemThread = startSystemThread

-- Scheduler object methods

scheduler.startUserThread = function(userThreadFn, ...)
    local backgroundThreadCtx = newThread()
    coroutine.resume(backgroundThreadCtx.thread, userThreadRunner, userThreadFn, ...)
    addToRunQueue(backgroundThreadCtx)
    return backgroundThreadCtx;
end

scheduler.join = function(...)
    local joiningTC = currentRunningThreadCtx
    if (joininTC) then
        local joinedThreads = table.pack(...)
        local numOfThreads = #joinedThreads

        local count = 0

        for i, joinedTC in ipairs(joinedThreads) do
            if ((joinedTC)and(joinedTC.state)and(joinedTC.state ~= TS_DONE)) then
                count = count + 1
                joinedTC.joinedBy = joiningTC
            end
        end

        joiningTC.joinCount = count
        while (joiningTC.joinCount > 0) do
            coroutine.yield(TS_BLOCKED_THREAD)
        end
    end
end

scheduler.runQueueSize = function()
    return runQueueLen
end

local runNextFromRunQueue = function()
    local threadCtx = runQueueHead
    if threadCtx then
        runQueueHead = threadCtx.nextThread
        if not runQueueHead then
            runQueueTail = nil
        end

        threadCtx.nextThread = nil

        runQueueLen = runQueueLen -1
        if (runQueueLen < 0) then
            runQueueLen = 0
        end

        if (threadCtx.state == TS_DONE) then
            -- This can happen when thread is added to the run queue but is woken up by libuv
            -- event and then runs to completion before the run queue scheduler gets chance
            -- to resume it
            return
        end

        return resumeThread(threadCtx)
    end
end

scheduler.runReadyThreads = function(limit)
    local runnableCount = runQueueLen
    if ((limit)and(limit < runnableCount)) then
        runnableCount = limit
    end

    for i=1, runnableCount do
        runNextFromRunQueue()
        end

    -- about to block on libuv event loop, next resumeThread should update current time
    -- as it may have spent significant time blocked on a event loop.
    updateTimeCyclingCounter = UPDATE_TIME_COUNTER_LIMIT

    return runnableCount
end

scheduler.updateCurrentTime()

return scheduler
