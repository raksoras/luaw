local luaw_lib = require("luaw_lib")
local template_lang = require('luaw_template_lang')

local writeBuffMT = {}
writeBuffMT.__index = writeBuffMT

writeBuffMT.append = function(buff, ...)
    local size = buff.size
    for i, v in ipairs({...}) do
        size = size + 1
        buff[size] = v
    end
    buff.size = size
    return buff
end

writeBuffMT.toString = function(buff)
    if (buff.size > 0) then
        return table.concat(buff, '', 1, buff.size)
    end
end

writeBuffMT.clear = function(buff)
    buff.size = 0
    return buff
end

writeBuffMT.increaseIndent = function(buff)
    buff.indent = buff.indent + 1
    return buff
end

writeBuffMT.decreaseIndent = function(buff)
    local indent = buff.indent
    if (indent > 0) then
        buff.indent = indent - 1
    end
    return buff
end

writeBuffMT.newline = function(buff)
    buff:append("\n")
    for i = 1, buff.indent do
        buff:append('    ')
    end
    return buff
end

local function newWriteBuffer(capacity)
    local buff = luaw_lib.createDict(capacity or 32, 0)
    buff.size = 0
    buff.indent = 0
    setmetatable(buff, writeBuffMT)
    return buff
end

-- Used in generating error message in case of template compilation errors
local lastSrcLine = ''

local function outputSource(buff, debug)
    local src = buff:toString()
    lastSrcLine = src 
    if debug then io.write(src) end
    coroutine.yield(src)
    buff:clear()
end

local function codeGen(node, buff, debug)
	local nType = type(node)
	if (nType == 'string') then
	    buff:newline()
	    buff:append(template_lang.writeToResp, '([[', node, ']])')
        outputSource(buff, debug)
	elseif (nType == 'table') then
		if (rawget(node, 'nodeType')) then
			local visitChildren = node:codeBegin(buff)
            outputSource(buff, debug)			
			
			if (visitChildren) then
				local children = rawget(node, 'children')
				if (children) then
					for _,child in ipairs(children) do
						codeGen(child, buff, debug)
					end
				end
			end
			
			local hasContent = node:codeEnd(buff)
			if hasContent then 
			    outputSource(buff, debug)
			end
		else
			for _, child in ipairs(node) do
				codeGen(child, buff, debug)
			end
		end
	else
		error('Invalid node found in AST tree. Type: '..nType)
	end
end

local function generateSource(template, buff, debug)
    coroutine:yield() -- capture variables and yield
    buff:append("return function (req, resp, pathParams, model)")
    outputSource(buff, debug)
    buff:increaseIndent()
	codeGen(template, buff, debug)
	buff:decreaseIndent()
	buff:append('\nend\n')
	outputSource(buff, debug)
end

local function compileFile(inputFile)
	-- reset per page globals
	processModel = nil
	template = nil
	debug_template = nil
	
	-- compile file
    dofile(inputFile)
	assert(template, 'Missing template, define it as template = HTML{...}')
	
	local processModelFn = processModel

    local srcGen = coroutine.wrap(generateSource)
    -- first call just serves to capture the variables template and debug in coroutine
    srcGen(template, newWriteBuffer(), debug_template)
    
    if (debug_template) then
        luaw_lib.formattedLine('Begin '..inputFile, 80, '-', '\n', '\n')
    end

    local templateFn, errMesg = load(srcGen, inputFile)
    
    if (debug_template) then
        luaw_lib.formattedLine('End '..inputFile, 80, '-', '\n', '\n')
    end
    
    if not templateFn then
        error(errMesg..": => "..tostring(lastSrcLine))
    end
    
    local compiledTemplate = templateFn()
    if processModelFn then
        return function(req, resp, pathParams, model)
            model = processModelFn(req, pathParams, model)
            compiledTemplate(req, resp, pathParams, model)
        end
    else
        return compiledTemplate
    end
end

return {
	compileFile = compileFile,
}
