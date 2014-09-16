local luaw_lib = require("luaw_lib")
local ds_lib = require('luaw_data_structs_lib')
local logging = require('luaw_logging')

-- Constants
local TS_RUNNABLE = luaw_lib.TS_RUNNABLE
local TS_DONE = luaw_lib.TS_DONE
local TS_BLOCKED_EVENT = luaw_lib.TS_BLOCKED_EVENT
local TS_BLOCKED_THREAD = luaw_lib.TS_BLOCKED_THREAD

local END_OF_CALL = {"END_OF_CALL"}
local END_OF_THREAD = {"END_OF_THREAD"}

-- Exception to no global rule to allow easy access to current thread's id using
-- global tid() call anywhere in the code
tid = nil

local function threadRunLoop(fn, arg1, arg2, arg3, arg4)
    local i = 0
    while i ~= timesReuseThread do
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

local function init(config)
    assert(type(config) == 'table', "Invalid configuration specified")
    assert(type(config.server_ip) == 'string', "Invalid host address supplied. Either use host IP or 0.0.0.0")
    assert(type(config.server_port) == 'number', "Invalid server port specified")
    assert(type(config.connection_buffer_size) == 'number', "Invalid connection buffer size specified")
    assert(config.connection_buffer_size > 8, "Connection buffer size must be more than 8")
    assert(config.connection_buffer_size <= 65536, "Connection buffer size may not be more than 65536")
    assert(type(config.request_handler) == 'function', "Invalid start new thread function specified")
    assert(type(config.connect_timeout) == 'number', "Invalid connect timeout specified")
    assert(type(config.read_timeout) == 'number', "Invalid read timeout specified")
    assert(type(config.write_timeout) == 'number', "Invalid write timeout specified")
    assert(type(config.thread_reuse_limit) == 'number', "Invalid thread reuse limit specified")
    assert(type(config.thread_pool_size) == 'number', "Invalid server thread pool size specified")

    DEFAULT_CONNECT_TIMEOUT = config.connect_timeout
    DEFAULT_READ_TIMEOUT = config.read_timeout
    DEFAULT_WRITE_TIMEOUT = config.write_timeout


    -- scheduler state

    local threadRegistry = ds_lib.newRegistry(config.thread_pool_size)
    local threadPool = ds_lib.newRingBuffer(config.thread_pool_size)
    local runQueueLen = 0
    local runQueueHead
    local runQueueTail
    local currentRunningThreadCtx
    local currentTime

    -- scheduler methods

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

        context = threadCtx.requestCtx  -- TLS, per thread context
        local status, state, retVal = coroutine.resume(t, ...)
        context = nil -- reset TLS context

        if not status then
            -- thread ran into error
            print("Error: "..tostring(state))
			print(debug.traceback())
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

    local function resumeThreadId(tid, ...)
        local threadCtx = threadRegistry[tid]
        if not threadCtx then error("Invalid thread Id "..tostring(tid)) end
        return resumeThread(threadCtx, ...)
    end

    local function startSystemThread(serviceFn, conn, ...)
        local threadCtx = newThread()
        threadCtx.state = TS_RUNNABLE
        local isDone = resumeThread(threadCtx, serviceFn, conn, ...)
        return isDone, threadCtx.tid
    end

    tid = function ()
        if currentRunningThreadCtx then
            return currentRunningThreadCtx.tid
        end
        return nil
    end

    -- server object

    local server = luaw_lib.newServer(startSystemThread, resumeThreadId, config)
    local serverObj = {}


    -- server obj methods

    serverObj.runQueueNotEmpty = function()
        if runQueueHead then return true end
        return false
    end

    serverObj.runQueueSize = function()
        return runQueueLen
    end

    serverObj.runNextFromRunQueue = function()
        local threadCtx = runQueueHead
        if threadCtx then
            runQueueHead = threadCtx.nextThread
            if not runQueueHead then runQueueTail = nil end
            threadCtx.nextThread = nil
            runQueueLen = runQueueLen -1
            if (runQueueLen < 0) then runQueueLen = 0 end

            if (threadCtx.state == TS_DONE) then
                -- This can happen when thread is added to the run queue but is woken up by libuv
                -- event and then runs to completion before the run queue scheduler gets chance
                -- to resume it
                return
            end
            return resumeThread(threadCtx)
        end
    end

    serverObj.join = function(...)
        local joinedThreads = table.pack(...)
        local numOfThreads = #joinedThreads
        local joiningTC = currentRunningThreadCtx
        local count = 0

        for i=1, numOfThreads do
            local joinedTC = joinedThreads[i]
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

    serverObj.startUserThread = function(userThreadFn, ...)
        local backgroundThreadCtx = newThread()
        coroutine.resume(backgroundThreadCtx.thread, userThreadRunner, userThreadFn, ...)
        addToRunQueue(backgroundThreadCtx)
        return backgroundThreadCtx;
    end

    serverObj.start = function()
        server:start()
    end

    serverObj.nonBlockingPoll = function ()
        currentTime = os.time()
        logging.updateCurrentTime(currentTime)
        return pcall(server.nonBlockingPoll, server)
    end

    serverObj.blockingPoll = function ()
        currentTime = os.time()
        logging.updateCurrentTime(currentTime)
        return pcall(server.blockingPoll, server)
    end

    serverObj.stop = function()
        server:stop()
    end

    serverObj.time = function()
        return currentTime
    end

    return serverObj
end

local default_config = {
    server_ip = "0.0.0.0",
    server_port = 80,
    thread_pool_size = 1024,
    thread_reuse_limit = 256,
    connection_buffer_size = 1024,
    connect_timeout = 8000,
    read_timeout = 3000,
    write_timeout = 3000,

    log_file_basename = "luaw-log",
    log_file_size_limit = 1024 * 1024 * 10, --10MB
    log_file_count_limit = 99,
    log_lines_buffer_count = 100,
    log_filename_timestamp_format = '%Y%m%d-%H%M%S',
    log_line_timestamp_format = "%x %X",
    syslog_facility = logging.SYSLOG_FACILITY_LOCAL7,
    syslog_tag = 'luaw',
}


default_config.__index = default_config

local luaw_serverConfig = nil;

local function configuration(config)
    setmetatable(config, default_config)
    luaw_serverConfig = config
end

local function loadConfiguration(configFile)
    dofile(configFile)
    local config = luaw_serverConfig
    luaw_serverConfig = nil
    return config
end

return {
    configuration = configuration,
    loadConfiguration = loadConfiguration,
    init = init
}
