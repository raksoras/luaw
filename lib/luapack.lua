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
local testing = require("unit_testing")

local lpackMT = getmetatable(luaw_lib.newLPackParser())

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

lpackMT.DICT_URL_RANGES = {
    lpackMT.DICT_URL,
    lpackMT.BIG_DICT_URL
}

local lpackArrayMT = {}

local function newArray(size)
    local arr = luaw_lib.createDict(size, 0)
    setmetatable(arr, lpackArrayMT)
    return arr
end

local function findMinRange(num, ranges)
    for i, range in ipairs(ranges) do
        if ((num >= range[4])and(num <= range[5])) then
            return range
        end
    end
    error("Number "..num.." outside supported max range")
end

local function setDictionaryForRead(lpack, dict)
    local dictIndex = luaw_lib.createDict(#dict, 0)
    for i,w in pairs(dict) do
        dictIndex[i] = w
    end
    lpack.dictionary = dictIndex
end

-- read functions

local function readNextBuffer(lpack, desiredLen)
    if lpack.EOF then
        -- readNextBuffer is called after reaching EOF once
        lpack.finished = true
    else
        if desiredLen < 1024 then desiredLen = 1024 end
        local newBuffer = lpack:reader(desiredLen)
        if not newBuffer then
            lpack.EOF = true
        else
            local buffer = lpack.buffer
            local offset = lpack.offset
            if ((buffer)and(#buffer > offset)) then
                lpack.buffer = buffer.sub(offset)..newBuffer
            else
                lpack.buffer = newBuffer
            end
            lpack.offset = 0
        end
    end
end

local function readNumber(lpack, numType)
    while (not lpack.finished) do
        local offset = lpack.offset
        local readLen, value, desiredLen = lpack.read_number(numType, lpack.buffer, offset)
        if (readLen < 0) then
            error("Error while reading number at byte# "..tostring(offset).." in buffer: "..tostring(lpack.buffer))
        end
        if (readLen > 0) then
            lpack.offset = offset + readLen
            return value
        end
        readNextBuffer(lpack, desiredLen);
    end
end

local function readMarker(lpack)
    return readNumber(lpack, lpack.TYPE_MARKER[2])
end

local function readString(lpack, desiredLen)
    local accm
    while ((desiredLen > 0)and(not lpack.finished)) do
        local offset = lpack.offset
        local buffer = lpack.buffer
        local readLen, value = lpack.read_string(desiredLen, lpack.buffer, offset)

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

        readNextBuffer(lpack, desiredLen);
    end
end

local function deserialize(lpack, container, isMap)
    local key, val, len
    local isKey = true
    local dictionary = lpack.dictionary

    while not lpack.finished do
        local t = readMarker(lpack)

        if t == lpack.MAP_START[2] then
            val = deserialize(lpack, luaw_lib.createDict(0, 16), true)
            goto processing
        end

        if t == lpack.ARRAY_START[2] then
            val = deserialize(lpack, newArray(16), false)
            goto processing
        end

        if t == lpack.DICT_START[2] then
            dictionary = deserialize(lpack, newArray(64), false)
            lpack:useDictionary(dictionary)
            goto last --continue
        end

        if t == lpack.RECORD_END[2] then
            if ((isMap)and(not isKey)) then
                error("Unbalanced table, key without corresponding value found")
            end
            return container
        end

        if t == lpack.DICT_URL[2] then
            --TODO
        end

        if t == lpack.BIG_DICT_URL[2] then
            --TODO
        end

        if t == lpack.NIL[2] then
            val = nil
            goto processing
        end

        if t == lpack.BOOL_TRUE[2] then
            val = true
            goto processing
        end

        if t == lpack.BOOL_FALSE[2] then
            val = false
            goto processing
        end

        if t == lpack.STRING[2] then
            len = readNumber(lpack, lpack.UINT_8[2])
            val = readString(lpack, len)
            goto processing
        end

        if t == lpack.BIG_STRING[2] then
            len = readNumber(lpack, lpack.UINT_16[2])
            val = readString(lpack, len)
            goto processing
        end

        if t == lpack.HUGE_STRING[2] then
            len = readNumber(lpack, lpack.UINT_32[2])
            val = readString(lpack, len)
            goto processing
        end

        if t == lpack.DICT_ENTRY[2] then
            local dw = readNumber(lpack, lpack.UINT_8[2])
            assert(dictionary, "Missing dictionary")
            val = assert(dictionary[dw], "Entry missing in dictionary: "..dw)
            goto processing
        end

        if t == lpack.BIG_DICT_ENTRY[2] then
            local dw = readNumber(lpack, lpack.UINT_16[2])
            assert(dictionary, "Missing dictionary")
            val = assert(dictionary[dw], "Entry missing in dictionary")
            goto processing
        end

        -- everything else is a number
        val = readNumber(lpack, t)

        ::processing::

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
            -- single, standalone value
            return val
        end

        ::last::
    end

    return val
end

local function read(lpack)
    readNextBuffer(lpack, 1024)
    val = deserialize(lpack, nil, false)
    return val
end

local function close(lpack)
    lpack:reader(0, "close")
end

local function fileReader(fileName)
    assert(fileName, "File name can not be nil")
    local f = io.open(fileName, "rb")
    if not f then
        error("Could not open file "..fileName.." for reading")
    end

    return function(lpack, desiredLen, cmd)
        if (not cmd) then
            return f:read(desiredLen)
        end
        if (cmd == "close") then
            f:close()
            f = nil
        end
    end
end

local function stringReader(str)
    assert(str, "String to read from can not be null")
    return function(lpack, desiredLen)
        local temp = str
        str = nil
        return temp
    end
end

local function newLPackReader(reader)
    if (type(reader) ~= 'function') then
        error("Please provide valid function (reader) to read next buffer")
    end

    local lpackReader = luaw_lib.newLPackParser();
    lpackReader.EOF = false
    lpackReader.buffer = ""
    lpackReader.offset = 0
    lpackReader.reader = reader
    lpackReader.read = read
    lpackReader.close = close
    lpackReader.useDictionary = setDictionaryForRead
    return lpackReader
end


-- Write functions

local function setDictionaryForWrite(lpack, dict)
    local dictIndex = luaw_lib.createDict(#dict, 0)
    for i,w in pairs(dict) do
        dictIndex[w] = i
    end
    lpack.dictionary = dictIndex
end

local function flush(lpack)
    local writeQ = lpack.writeQ
    local count = #writeQ
    if count then
        local str = lpack.serialize_write_Q(writeQ, lpack.writeQsize)
        if str then
            lpack:writer(str)
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
    local accSize = lpack.writeQsize + size;

    if (accSize >= lpack.flushLimit) then
        flush(lpack)
    else
        lpack.writeQsize = accSize
    end
end

local function writeMarker(lpack, marker)
    if ((marker[2] < lpack.TYPE_MARKER[2])or(marker[2] > lpack.BIG_DICT_URL[2])) then
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
    writeMarker(lpack, lpack.RECORD_END, 1)
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

local function writeDictionary(lpack, dict)
    assert((type(dict) == 'table'), "Please provide valid dictionary table")
    local dictionary = luaw_lib.createDict(#dict, 0)
    writeMarker(lpack, lpack.DICT_START)
    for i, dw in ipairs(dict) do
        writeString(lpack, dw)
        dictionary[dw] = i
    end
    writeMarker(lpack, lpack.RECORD_END)
    lpack.dictionary = dictionary
end

local function writeDictionaryURL(lpack, url)
    assert((type(dictURL) == 'string'), "Please provide valid dictionary URL")
    local len = #url
    local range = findMinRange(len, lpack.DICT_URL_RANGES)
    qstore(lpack, range[2], 1) -- marker
    qstore(lpack, url, len) -- actual URL value
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
        if (getmetatable(val) == lpackArrayMT) then
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

local function close(lpack)
    return lpack:writer(nil, "close")
end

local function newLPackWriter(writer)
    if (type(writer) ~= 'function') then
        error("Please provide valid function (writer) to write accumulated buffer")
    end

    local lpackWriter = luaw_lib.newLPackParser()
    lpackWriter.writeQ = {}
    lpackWriter.writeQsize = 0
    lpackWriter.flushLimit = 2048
    lpackWriter.newArray = newArray
    lpackWriter.writeDictionaryURL = writeDictionaryURL
    lpackWriter.writer= writer
    lpackWriter.write = write
    lpackWriter.close = close
    lpackWriter.useDictionary = setDictionaryForWrite
    lpackWriter.writeDictionary = writeDictionary
    return lpackWriter
end

local function fileWriter(fileName)
    assert(fileName, "File name can not be nil")
    local f = io.open(fileName, "wb")
    if not f then
        error("Could not open file "..fileName.." for writing")
    end

    return function(lpack, str, cmd)
        if (not cmd) then
            return f:write(str)
        end
        if (cmd == "close") then
            f:close()
            f = nil
        end
    end
end

local function stringWriter()
    local buff = {}
    local val

    return function(lpack, str, cmd)
        if (not cmd) then
            return table.insert(buff, str)
        end
        if (cmd == "close") then
            if (not val) then
                val = table.concat(buff)
            end
            return val
        end
    end
end

return {
    newLPackReader = newLPackReader,
    newLPackWriter = newLPackWriter,
    fileReader = fileReader,
    stringReader = stringReader,
    fileWriter = fileWriter,
    stringWriter = stringWriter
}


