#11. User Threads

Luaw allows developer to spawn user threads to execute multiple tasks in parallel. Luaw user threads are implemented using Lua's coroutines and hence are very lightweight compared to real OS threads. In addition to this Luaw also pools and reuses Lua coroutines underlying user threads to make spawning user threads even cheaper. As a result you should be able to spawn thousands of them without having to worry about using up all your system resources.

Here is a small example of user threads' usage. It uses async HTTP client introduced in last chapter to do two HTTP calls in parallel using user threads, waits till both of them return and then processes both the responses received. It is an example of common scatter/gather pattern frequently encountered in service oriented architecture and illustrates how Luaw's user threads nicely complement Luaw's async HTTP client's functionality

```lua
local function parallelHttpRequest(host, url)
    local clientReq = Luaw.newClientHttpRequest()
    clientReq.hostName = host
    clientReq.method = 'GET'
    clientReq.url = url
    clientReq:addHeader("Host", host)
    local clientResp = clientReq:execute()
    return clientResp
end

local scheduler = Luaw.scheduler
-- do two HTTP request in parallel
local threadCtx1 = scheduler.startUserThread(parallelHttpRequest, "www.google.com", "/")
local threadCtx2 = scheduler.startUserThread(parallelHttpRequest, "www.facebook.com", "/")

-- wait on both threads to be donw
scheduler.join(threadCtx1, threadCtx2)

-- Retrieve the responses received
local clientResp1 = threadCtx1.result
local clientResp2 = threadCtx2.result
```

1. You use Luaw.scheduler.startUserThread(function, ...) to start a new user thread. First argument to this method must be a "thread function" that is to be run by the thread being spawn. This function argument may be followed by variable number of arguments which are passed to the thread function as its argument. In case of the example above our thread function is "parallelHttpRequest" which takes two arguments - a hostname and a URL. These two arguments are passed in Luaw.scheduler.startUserThread() after the thread function in the same order. Luaw.scheduler.startUserThread() re-uses internally pooled coroutine - if one is available - to run the thread function provided so this call is really cheap.

2. Luaw.scheduler.startUserThread() returns a thread context which you can pass to scheduler.join() to wait on the thread to complete. scheduler.join() accepts variable number of thread contexts so you can wait on more than one thread in a single call. scheduler.join() doesn't return till all the threads represented by thread contexts passed into it have finished executing.

3. Value returned by the thread function ("parallelHttpRequest" in our case) can be retrieved as threadCtx.result. Thread function should return only single value (Lua allows functions to return multiple values). If there is a need to return multiple values from the thread function, the function can stuff them all inside a single Lua table with different keys (i.e. property names) and return the Lua table instead.

4. Finally, in all other aspects user threads are semantically similar to system threads spawned by Luaw server itself to server incoming HTTP requests. That is, they can use async calls like HTTP client's execute or Timer methods (explained in the next chapter) and Luaw will automatically suspend them when they are waiting for the async calls to return. They are fully hooked into Luaw's internal async callback mechanism.
