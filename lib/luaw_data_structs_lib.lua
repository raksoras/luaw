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

local module = {}

--
-- Registry
---

-- reg[0] stores head of the free list
local function ref(reg, obj)
    if not obj then return -1 end

    local ref = reg[0];
    if ref then
        reg[0] = reg[ref]
    else
        ref = #reg + 1
    end

    reg[ref] = obj
    reg.size = reg.size + 1
    return ref
end

local function unref(reg, ref)
    if ref >= 0 then
        reg[ref] = reg[0]
        reg[0] = ref
        reg.size = reg.size -1
    end
end

function module.newRegistry(size)
    local reg = {}
    reg.ref = ref;
    reg.unref = unref;
    reg.size = 0
    return reg;
end

--
-- Ring buffers
--

local function offer(rb, obj)
    local size = rb.size
    local filled = rb.filled
    local writer = rb.writer

    if (filled < size) then
        rb[writer] = obj
        rb.filled = filled + 1
        if (writer == size) then
            rb.writer = 1
        else
            rb.writer = writer + 1
        end
        return true;
    end
    return false;
end

local function offerWithWait(rb, obj)
    local added = offer(rb, obj)
    while not added do
        coroutine.yield()
        added = offer(rb, obj)
    end
    return added
end

local function take(rb)
    local size = rb.size
    local filled = rb.filled
    local reader = rb.reader
    local obj = nil

    if (filled > 0) then
        obj = rb[reader];
        rb[reader] = nil;
        rb.filled = filled - 1
        if (reader == size) then
            rb.reader = 1
        else
            rb.reader = reader + 1
        end
    end
    return obj
end

local function takeWithWait(rb)
    local obj = take(rb)
    while not obj do
        coroutine.yield()
        obj = take(rb)
    end
    return obj
end

local function offerWithOverwrite(rb, obj)
    local added = offer(rb, obj)
    if added then return true end

    -- overwrite oldest item
    local overwrittenObj = take(rb)
    offer(rb, obj)
    return false, overwrittenObj
end


function module.newRingBuffer(size)
    local rb = {}
    rb.reader = 1
    rb.writer = 1
    rb.filled = 0
    rb.size = size
    rb.offer = offer
    rb.take = take
    return rb
end

function module.newOverwrittingRingBuffer(size)
    local rb = {}
    rb.reader = 1
    rb.writer = 1
    rb.filled = 0
    rb.size = size
    rb.offer = offerWithOverwrite
    rb.take = take
    return rb
end

function module.newBlockingRingBuffer(size)
    local rb = {}
    rb.reader = 1
    rb.writer = 1
    rb.filled = 0
    rb.size = size
    rb.offer = offerWithWait
    rb.take = takeWithWait
    return rb
end

return module
