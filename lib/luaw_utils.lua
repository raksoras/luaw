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

local luaw_util_lib = {}

local function tprint(tbl, indent, tab)
  for k, v in pairs(tbl) do
    if type(v) == "table" then
		print(string.rep(tab, indent) .. tostring(k) .. ": {")
		tprint(v, indent+1, tab)
		print(string.rep(tab, indent) .. "}")
    else
		print(string.rep(tab, indent) .. tostring(k) .. ": " .. tostring(v))
    end
  end
end

-- Print contents of `tbl`, with indentation.
-- `indent` sets the initial level of indentation.
luaw_util_lib.debugDump = function(tbl, indent, tab)
    indent = indent or 0
    tab = tab or "  "
  	print(string.rep(tab, indent) .. "{")
	tprint(tbl, indent+1, tab)
	print(string.rep(tab, indent) .. "}")
end

luaw_util_lib.steplight = function(mesg)
    local tid = tostring(Luaw.scheduler.tid())
    print("Thread-"..tid.."> "..tostring(mesg))
end

luaw_util_lib.step = function(mesg, level)
    local tid = tostring(Luaw.scheduler.tid())

    local lvl = level or 2
    if (lvl < 0) then lvl = lvl * -1 end

    local dc = debug.getinfo(lvl, "nSl")

    local str = ""
    if type(mesg) == 'table' then
        for k,v in pairs(mesg) do
            str = str..", "..tostring(k).."="..tostring(v)
        end
    else
        str = tostring(mesg)
    end

    print('Thread '..tid..'> line# '..tostring(dc.linedefined)..' in function '..tostring(dc.name)..' in file '..tostring(dc.source)..': '..str)

    if ((level)and(level < 0)) then
        print(debug.traceback())
    end
end

luaw_util_lib.run = function(codeblock)
    if (codeblock) then
        local try = codeblock.try
        if (try) then
            local catch = codeblock.catch
            local finally = codeblock.finally

            local status, err = pcall(try, codeblock)
            if ((not status)and(catch)) then
                status, err = pcall(catch, codeblock, err)
            end

            if (finally) then
                finally(codeblock)
            end

            if (not status) then
                error(err)
            end
        end
    end
end

luaw_util_lib.clearArrayPart = function(t)
    local len = #t
    for i=1,len do
        t[i] = nil
    end
end

luaw_util_lib.splitter = function(splitCh)
    local separator = string.byte(splitCh, 1, 1)
    local byte = string.byte

    return function (str, pos)
        pos = pos + 1
        local start = pos
        local len = #str
        while pos <= len do
            local ch = byte(str, pos, pos)
            if (ch == separator) then
                if (pos > start) then
                    return pos, string.sub(str, start, pos-1)
                end
                start = pos + 1
            end
            pos = pos + 1
        end
        if (pos > start) then return pos, string.sub(str, start, pos) end
    end
end

luaw_util_lib.nilFn = function()
    return nil
end

luaw_util_lib.formattedLine = function(str, lineSize, paddingCh, beginCh, endCh)
    lineSize = lineSize or 0
    paddingCh = paddingCh or ''
    beginCh = beginCh or ''
    endCh = endCh or ''
    paddingWidth = (lineSize - #str -2)/2
    local padding = ''
    if paddingWidth > 0 then
        padding = string.rep(paddingCh, paddingWidth)
    end
    print(string.format("%s %s %s %s %s", beginCh, padding, str, padding, endCh))
end

return luaw_util_lib
