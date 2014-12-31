#12. Luaw Timers

Luaw supports user defined timers. Here is an example:

```lua
local timer = Luaw.newTimer()
timer:start(1000)
doSomeStuff()
print("waiting till it's time...")
timer:wait()
print('done waiting!')
-- call timer: delete() to free timer resources immediately. If not delete() is not called
-- timer resources hang around till Lua's VM garbage collects them
timer:delete()
```

1. You create a new timer using Luaw.newTimer()
2. You start it with some timeout - specified in milliseconds using timer:start(timeout)
3.  and finally you wait on it using timer:wait()

That's basically it!

There is one more call - `timer:sleep(timeout)` - that combines `timer:start()` and `timer:wait()` in a single function call. The example above can be rewritten as follows provided we did not have to call doSomeStuff() in between:

```lua
local timer = Luaw.newTimer()
timer:sleep(1000)
print('done waiting!')
```

Luaw timers are fully hooked into Luaw's async machinert. Just like any other async call - HTTP client's execute(), for example - timer:wait() or timer:sleep() suspend current Luaw thread till the time is up.