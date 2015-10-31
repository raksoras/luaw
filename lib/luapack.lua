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

local luaw_constants = require("luaw_constants")

local lpackMT = getmetatable(luaw_lpack_lib.newLPackParser())

lpackMT.INT_RANGES = {
    lpackMT.UINT_8,
    lpackMT.UINT_16,
    lpackMT.UINT_32,
    lpackMT.INT_8,
    lpackMT.INT_16,
    lpackMT.INT_32,
    lpackMT.INT_64,
    lpackMT.FLOAT,
    lpackMT.DOUBLE
}

lpackMT.FLOAT_RANGES = {
    lpackMT.FLOAT,
    lpackMT.DOUBLE
}

lpackMT.STRING_RANGES = {
    lpackMT.STRING,
    lpackMT.BIG_STRING,
    lpackMT.HUGE_STRING
}

lpackMT.DICT_ENTRY_RANGES = {
    lpackMT.DICT_ENTRY,
    lpackMT.BIG_DICT_ENTRY
}

local function findMinRange(num, ranges)
    for i, range in ipairs(ranges) do
        if ((num >= range[4])and(num <= range[5])) then
            return range
        end
    end
    error("Number "..num.." outside supported max range")
end

-- read functions

local function readNextBuffer(lpack)
    if not lpack.EOF then
        local newBuffer = lpack:readFn()
        if not newBuffer then
            lpack.EOF = true
        else
            local buffer = lpack.buffer
            local offset = lpack.offset
            if ((buffer)and(#buffer > offset)) then
                lpack.buffer = string.sub(buffer, offset)..newBuffer
            else
                lpack.buffer = newBuffer
            end
            lpack.offset = 0
        end
    end
end

local function done(lpack)
    return ((lpack.EOF)and(lpack.offset >= #lpack.buffer))
end

local function readNumber(lpack, numType)
    while (not lpack:done()) do
        local offset = lpack.offset
        local readLen, value = lpack.read_number(numType, lpack.buffer, offset)
        if (readLen < 0) then
            error("Error while reading number at byte# "..tostring(offset).." in buffer: "..tostring(lpack.buffer))
        end
        if (readLen > 0) then
            lpack.offset = offset + readLen
            return value
        end
        readNextBuffer(lpack);
    end
end

local function readMarker(lpack)
    return readNumber(lpack, lpack.TYPE_MARKER[2])
end

local function readString(lpack, desiredLen)
    local accm
    while ((desiredLen > 0)and(not lpack:done())) do
        local offset = lpack.offset
        local buffer = lpack.buffer
        local readLen, value = lpack.read_string(desiredLen, buffer, offset)
        if (readLen > 0) then
            lpack.offset = offset + readLen
            desiredLen = desiredLen - readLen

            if (desiredLen == 0) then
                if accm then
                    table.insert(accm, value)
                    return table.concat(accm)
                end
                return value
            end

            if not accm then accm = {} end
            table.insert(accm, value)
        end
        readNextBuffer(lpack);
    end
end

local function deserialize(lpack, container, isMap)
    local key, val, len, t
    local isKey = true
    local dictionary = lpack.dictionary

    while not lpack:done() do
        t = readMarker(lpack)

        if t == lpack.NIL[2] then
            val = nil

        elseif t == lpack.BOOL_TRUE[2] then
            val = true

        elseif t == lpack.BOOL_FALSE[2] then
            val = false

        elseif t == lpack.STRING[2] then
            len = readNumber(lpack, lpack.UINT_8[2])
            val = readString(lpack, len)

        elseif t == lpack.BIG_STRING[2] then
            len = readNumber(lpack, lpack.UINT_16[2])
            val = readString(lpack, len)

        elseif t == lpack.HUGE_STRING[2] then
            len = readNumber(lpack, lpack.UINT_32[2])
            val = readString(lpack, len)

        elseif t == lpack.MAP_START[2] then
            val = deserialize(lpack, luaw_lpack_lib.createDict(0, 16), true)

        elseif t == lpack.ARRAY_START[2] then
            val = deserialize(lpack, luaw_lpack_lib.createDict(16, 0), false)

        elseif t == lpack.RECORD_END[2] then
            if ((isMap)and(not isKey)) then
                error("Unbalanced table, key without corresponding value found")
            end
            return container

        elseif t == lpack.DICT_ENTRY[2] then
            local dw = readNumber(lpack, lpack.UINT_8[2])
            assert(dictionary, "Missing dictionary")
            val = assert(dictionary[dw], "Entry missing in dictionary: "..dw)

        elseif t == lpack.BIG_DICT_ENTRY[2] then
            local dw = readNumber(lpack, lpack.UINT_16[2])
            assert(dictionary, "Missing dictionary")
            val = assert(dictionary[dw], "Entry missing in dictionary")

        elseif t == lpack.DICT_START[2] then
            dictionary = deserialize(lpack, luaw_lpack_lib.createDict(64, 0), false)
            lpack.dictionary = dictionary
            debugDump(dictionary)

        else
            -- everything else is a number
            val = readNumber(lpack, t)
        end

        if container then
            if isMap then
                if isKey then
                    key = val
                    isKey = false
                else
                    container[key] = val
                    isKey = true
                end
            else
                -- is array
                table.insert(container, val)
            end
        else
            if (t ~= lpack.DICT_START[2]) then
                -- single, standalone value
                return val
            end
        end
    end

    return val
end

local function read(lpack)
    readNextBuffer(lpack)
    val = deserialize(lpack, nil, false)
    return val
end

local function newLPackReader()
    local lpackReader = luaw_lpack_lib.newLPackParser();
    lpackReader.EOF = false
    lpackReader.buffer = ''
    lpackReader.offset = 0
    lpackReader.done = done
    lpackReader.read = read
    return lpackReader
end

local function newLPackStringReader(str)
    assert(str, "String cannot be null")
    local lpackReader = newLPackReader()
    local eof = false
    lpackReader.readFn = function()
        if (not eof) then
            eof = true
            return str
        end
    end
    return lpackReader
end

local function newLPackFileReader(file)
    assert(file, "File cannot be null")
    local lpackReader = newLPackReader()
    lpackReader.readFn = function()
        return file:read(1024)
    end
    return lpackReader
end

local function newLPackReqReader(req)
    assert(req, "Request cannot be null")
    local lpackReader = newLPackReader()
    lpackReader.readFn = function()
        if ((not req.EOF)and(not req.luaw_mesg_done)) then
            req:readAndParse()
            local str =  req:consumeBodyChunkParsed()
            if (not str) then
                debugDump(req)
            end
            return str
        end
    end
    return lpackReader
end

-- Write functions

local function flush(lpack)
    local writeQ = lpack.writeQ
    local count = #writeQ
    if count then
        local str = lpack.serialize_write_Q(writeQ, lpack.writeQsize)
        if str then
            lpack:writeFn(str)
            lpack.writeQsize = 0
            for i=1,count do
                writeQ[i] = nil
            end
        end
    end
end

local function qstore(lpack, val, size)
    if not val then
        error("nil string passed to write(), use writeNil() instead")
    end

    local writeQ = lpack.writeQ
    table.insert(writeQ, val);
    lpack.writeQsize = lpack.writeQsize + size;

    if (lpack.writeQsize >= lpack.flushLimit) then
        flush(lpack)
    end
end

local function writeMarker(lpack, marker)
    if ((marker[2] < lpack.TYPE_MARKER[2])or(marker[2] > lpack.HUGE_STRING[2])) then
        error("Invalid marker "..marker.." specified")
    end
    qstore(lpack, marker[2], 1)
end

local function startMap(lpack)
    writeMarker(lpack, lpack.MAP_START)
end

local function startArray(lpack)
    writeMarker(lpack, lpack.ARRAY_START)
end

local function startDict(lpack)
    writeMarker(lpack, lpack.DICT_START)
end

local function endCollection(lpack)
    writeMarker(lpack, lpack.RECORD_END)
end

local function writeBoolean(lpack, value)
    if (value) then
        writeMarker(lpack, lpack.BOOL_TRUE)
    else
        writeMarker(lpack, lpack.BOOL_FALSE)
    end
end

local function writeNil(lpack)
    writeMarker(lpack, lpack.NIL)
end

local function writeNumber(lpack, num)
    local range

    if (num % 1 == 0) then
        -- integer
        range = findMinRange(num, lpack.INT_RANGES)
    else
        -- float
        range = findMinRange(num, lpack.FLOAT_RANGES)
    end
    qstore(lpack, range[2], 1);
    qstore(lpack, num, range[3]);
end

local function writeString(lpack, str)
    local dw, len, range
    local dict = lpack.dictionary
    if dict then
        dw = dict[str]
    end

    if dw then
        range = findMinRange(dw, lpack.DICT_ENTRY_RANGES)
        str = dw
        len = range[3]
    else
        len = #str
        range = findMinRange(len, lpack.STRING_RANGES)
    end

    qstore(lpack, range[2], 1) -- marker
    qstore(lpack, str, len) -- actual string value/dictionary entry
end

local function serialize(lpack, val)
    local t = type(val)

    if t == 'nil' then
        writeNil(lpack)
        return;
    end

    if t == 'boolean' then
        writeBoolean(lpack, val)
        return
    end

    if t == 'number' then
        writeNumber(lpack, val)
        return
    end

    if t == 'string' then
        writeString(lpack, val)
        return
    end

    if t == 'table' then
        if (#val > 0) then
            writeMarker(lpack, lpack.ARRAY_START)
            for i, v in ipairs(val) do
                serialize(lpack, v)
            end
            endCollection(lpack)
        else
            writeMarker(lpack, lpack.MAP_START)
            for k, v in pairs(val) do
                serialize(lpack, k)
                serialize(lpack, v)
            end
            endCollection(lpack)
        end
    end
end

local function write(lpack, val)
    serialize(lpack, val)
    flush(lpack)
end

local function setDictionaryForWrite(lpack, dict)
    assert((type(dict) == 'table'), "Please provide valid dictionary table")
    local dictionary = luaw_lpack_lib.createDict(#dict, 0)
    writeMarker(lpack, lpack.DICT_START)
    for i, dw in ipairs(dict) do
        writeString(lpack, dw)
        dictionary[dw] = i
    end
    writeMarker(lpack, lpack.RECORD_END)
    lpack.dictionary = dictionary
end

local function newLPackWriter(limit)
    local lpackWriter = luaw_lpack_lib.newLPackParser()
    lpackWriter.writeQ = {}
    lpackWriter.writeQsize = 0
    lpackWriter.flushLimit = limit or luaw_constants.CONN_BUFFER_SIZE
    lpackWriter.useDictionary = setDictionaryForWrite
    lpackWriter.write = write
    return lpackWriter
end

local function newLPackFileWriter(file, limit)
    assert(file, "File can not be nil")
    local lpackWriter = newLPackWriter(limit)
    lpackWriter.writeFn = function(lpack, str)
        file:write(str)
    end
    return lpackWriter
end

local function newLPackBufferWriter(buff, limit)
    assert(buff, "buffer can not be nil")
    local lpackWriter = newLPackWriter(limit)
    lpackWriter.writeFn = function(lpack, str)
        table.insert(buff, str)
    end
    return lpackWriter
end

local function newLPackRespWriter(resp, limit)
    assert(resp, "response can not be nil")
    local lpackWriter = newLPackWriter(limit)
    resp.headers['Content-Type'] = 'application/luapack'
    resp:startStreaming()
    lpackWriter.writeFn = function(lpack, str)
        resp:appendBody(str)
    end
    return lpackWriter
end

luaw_lpack_lib.newLPackFileReader = newLPackFileReader
luaw_lpack_lib.newLPackStringReader = newLPackStringReader
luaw_lpack_lib.newLPackReqReader = newLPackReqReader
luaw_lpack_lib.newLPackFileWriter = newLPackFileWriter
luaw_lpack_lib.newLPackBufferWriter = newLPackBufferWriter
luaw_lpack_lib.newLPackRespWriter = newLPackRespWriter

return luaw_lpack_lib


