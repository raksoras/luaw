local writeToResp = 'resp:appendBody'

--
-- Runtime stack emulation for variable scope checks
--
local stack = {
	frames = {{}}
}

function stack:peek()
	local size = #self.frames
	return self.frames[size]
end

function stack:pushFrame()
	local newFrame = {}
	local topFrame = self:peek()
	mt = {__index = topFrame}
	setmetatable(newFrame, mt)
	table.insert(self.frames, newFrame)
end

function stack:popFrame()
	local size = #self.frames
	if (size > 1) then
		return table.remove(stack.frames)
	end
	return nil;
end

 function stack:defineVar(var)
	local topFrame = stack:peek()
	topFrame[var.varName] = var
end


function stack:findVar(varName)
	local topFrame = stack:peek()
	return topFrame[varName]
end

--
-- Variables handling
--

local function tostr(table)
	local str = '{nodeType = '..(table.nodeType or 'nil')
	local vName = rawget(table, 'varName')
	if (vName) then
		str = str .. ', varName = ' .. vName
	end
	str = str .. '}'
	return str
end

local function noop()
    return false
end

local function displayVar(self, buff)
    buff:newline()
    buff:append(writeToResp, '(', self.varName, ')')
	return false
end


local function display(self)
	assert(self, 'display() called on nil reference')
	assert((rawget(self, 'nodeType') == 'VARIABLE'), 'display() called on object which is not a variable')
	local varName = rawget(self, 'varName')
	assert(varName, "display() called on undefined variable")

	return {
		nodeType = 'DISPLAY_VAR',
		varName = varName,
		dataType = dataType,
		codeBegin = displayVar,
		codeEnd = noop
	}
end

local function getNestedProp(var, propName)
	var.varName = var.varName .. '.' .. propName
	return var
end

local VarMT = {
	__index = getNestedProp,
	__tostring = tostr
}


local RootVarMT = {
	__index = function(table, key)
		local var = {
			nodeType = table.nodeType,
			schema = rawget(table, 'schema'),
			varName = table.varName,
			display = display
		}
		setmetatable(var, VarMT)
		return var[key]
	end,

	__tostring = tostr
}

local function defineRootVar(lval)
	local rootVar = {nodeType = 'VARIABLE', varName = lval}
	setmetatable(rootVar, RootVarMT)
	_G[lval] = rootVar
	stack:defineVar(rootVar)
	return rootVar
end

local function undefineBlkVars()
	local stackFrame = stack:popFrame()
	for vName, v in pairs(stackFrame) do
		if (vName) then
			_G[vName] = nil
		end
		-- check if another variable with the same name exists in a enclosing
		-- (higher) scope and bring it back ('uncover') if it does
		local oldVar = stack:findVar(vName)
		if (oldVar) then
			_G[vName] = oldVar
		end
	end
end

local function getVarName(v)
	if((not v)or(type(v) ~= 'table')or(not rawget(v, 'varName'))) then
		error('Invalid variable reference of type"'..type(v)..'": '..tostring(v))
	end
	return rawget(v, 'varName')
end

local function assertValidVar(v)
	if (not v) then
		error('nil supplied where variable reference was expected')
	end
	if (type(v) ~= 'table') then
		error('Invalid variable "'..tostring(v)..'" supplied. Type: '..type(v))
	end
	if (rawget(v, 'nodeType') ~= 'VARIABLE') then
		error('Invalid variable of type "'..type(v)..'" specified: '..tostring(v))
	end
	return v
end

local function assertValidVarName(vName, vDefault)
	local name = (vName or vDefault)
	if (not name) then
		error('Nil supplied where variable name was expected')
	end
	if (type(name) ~= 'string') then
		error('Invalid variable name specified. Expected string, got '..type(name))
	end
	return name
end


--
-- Flow control statements definitions
--

local function codeBlkEnd(self, buff)
    buff:decreaseIndent()
    buff:newline()
    buff:append('end')
    return true
end

local function presentBlkBegin(self, buff)
	buff:newline()
	buff:append('if (', self.ctrlVarName, ') then')
	buff:increaseIndent()
	return true
end

function present(v)
	v = assertValidVar(v)

	return function(nested)
		return {
			nodeType = 'CODE_BLK_PRESENT',
			children = nested,
			ctrlVarName = getVarName(v),
			codeBegin = presentBlkBegin,
			codeEnd = codeBlkEnd
		}
	end
end

local function absentBlkBegin(self, buff)
	buff:newline()
	buff:append('if (not ', self.ctrlVarName, ') then')
	buff:increaseIndent()
	return true
end

function absent(v)
	v = assertValidVar(v)

	return function(nested)
		return {
			nodeType = 'CODE_BLK_ABSENT',
			children = nested,
			ctrlVarName = getVarName(v),
			codeBegin = absentBlkBegin,
			codeEnd = codeBlkEnd
		}
	end
end

local function getOperandStr(op)
	local opType = type(op)

	if (opType == 'table') then
		local nodeType = op.nodeType
		if (nodeType == 'VARIABLE') then
			local vName = rawget(op, 'varName')
			assert(vName, "undefined variable referred")
			return vName
		end
	end

	if(opType == 'string') then
		return "'"..op.."'"
	end

	if ((opType == 'number')or(opType == 'boolean')) then
		return tostring(op)
	end

	assert('Invalid operand of type "'..opType..'"')
end

local function equalBlkBegin(self, buff)
    buff:newline()
    buff:append('if (', self.leftVarName, ' == ', self.rightVarName, ') then')
    buff:increaseIndent()
    return true
end

local function notEqualBlkBegin(self, buff)
    buff:newline()
	buff:append('if (', self.leftVarName, ' ~= ', self.rightVarName, ') then')
	buff:increaseIndent()
	return true
end

local function matchBlk(v1, v2, blkType, codeBlkBegin)
	local leftV = getOperandStr(v1)
	local rightV = getOperandStr(v2)

	return function(nested)
		return {
			nodeType = blkType,
			children = nested,
			leftVarName = leftV,
			rightVarName = rightV,
			codeBegin = codeBlkBegin,
			codeEnd = codeBlkEnd
		}
	end
end

function equal(v1, v2)
	return matchBlk(v1, v2, 'CODE_BLK_EQUAL', equalBlkBegin)
end

function notequal(v1, v2)
	return matchBlk(v1, v2, 'CODE_BLK_NOT_EQUAL', notEqualBlkBegin)
end

local function forKeyValBlkBegin(self, buff)
    buff:newline()
	buff:append('for ', self.keyVarName, ', ', self.valVarName,' in pairs(', self.ctrlVarName, ') do')
	buff:increaseIndent()
	return true
end

local function forIdxValBlkBegin(self, buff)
    buff:newline()
	buff:append('for ', self.keyVarName, ', ', self.valVarName,' in ipairs(', self.ctrlVarName, ') do')
	buff:increaseIndent()
	return true
end

local function forLoop(list, keyVarName, valVarName, forBlkType, codeBlkBegin)
	stack:pushFrame()
	list = assertValidVar(list)

	local kName = assertValidVarName(keyVarName)
	defineRootVar(kName)

	local vName = assertValidVarName(valVarName)
	defineRootVar(vName, list)

	return function(nested)
		undefineBlkVars()
		return {
			nodeType = forBlkType,
			children = nested,
			ctrlVarName = getVarName(list),
			keyVarName = kName,
			valVarName = vName,
			codeBegin = codeBlkBegin,
			codeEnd = codeBlkEnd
		}
	end
end

function foreach(list, keyVarName, valVarName)
	return forLoop(list, (indexVarName or 'key'), (valVarName or 'val'), 'CODE_BLK_FOR_KEY_VAL', forKeyValBlkBegin)
end

function foreachi(list, indexVarName, valVarName)
	return forLoop(list, (indexVarName or 'idx'), (valVarName or 'val'), 'CODE_BLK_FOR_INDEX_VAL', forIdxValBlkBegin)
end

local function loopBlkBegin(self, buff)
    buff:newline()
	buff:append('for ', self.loopVarName, '=', self.start,', ', self.stop, ', ', self.step, ' do')
	buff:increaseIndent()
	return true    
end

local function handleLoopNumOrVar(v)
	if (type(v) == 'number') then
			return tostring(v)
	else
		assertValidVar(v)
		return getVarName(v)
	end
end

function loop(start, stop, step, loopVarName)
	stack:pushFrame()
	local lvName = assertValidVarName(loopVarName, 'index')
	defineRootVar(lvName)

	return function(nested)
		undefineBlkVars()
		return {
			nodeType = 'CODE_BLK_LOOP',
			children = nested,
			start = handleLoopNumOrVar(start),
			stop = handleLoopNumOrVar(stop),
			step = handleLoopNumOrVar(step),
			loopVarName = lvName,
			codeBegin = loopBlkBegin,
			codeEnd = codeBlkEnd
		}
	end
end

--
-- HTML tag definitions
--

local function htmlTagOpen(self, buff)
    buff:newline()
    buff:append(writeToResp, '("<', self.tagName)
    
	if (self.hasAttrs) then
		-- Keep start tag open, we will write attributes on separate lines, 
		-- one attribute per line in attribute handler
		buff:append('")')
	else
		buff:append('>\\n")')
	end
	
	return true
end

local function htmlTagClose(self, buff)
    buff:newline()
    buff:append(writeToResp, '("</', self.tagName, '>\\n")')
    return true
end

local function defineTag(name)
	_G[name]= function(nested)
		local i = 0
		if (nested and type(nested) == 'table') then
			for _, v in pairs(nested) do
				if (type(v) == 'table') then
					if (rawget(v, 'nodeType') == 'HTML_TAG_ATTRS') then
						assert((i == 0),'attrs{} must be the first nested tag inside any HTML tag and cannot be nested or repeated more than once')
						i = i+1
					end
				end
			end
		end

		return {
			nodeType = 'HTML_TAG',
			tagName = name,
			hasAttrs = (i == 1),
			children = nested,
			codeBegin = htmlTagOpen,
			codeEnd = htmlTagClose
		}
	end
end


local htmlTags = {'Name', 'A', 'ABBR', 'ACRONYM', 'ADDRESS', 'APPLET', 'AREA',
'B', 'BASE', 'BASEFONT', 'BDO', 'BIG', 'BLOCKQUOTE', 'BODY', 'BR', 'BUTTON',
'CAPTION', 'CENTER', 'CITE', 'CODE', 'COL', 'COLGROUP',
'DD', 'DEL', 'DFN', 'DIR', 'DIV', 'DL', 'DT',
'EM',
'FIELDSET', 'FONT', 'FORM', 'FRAME', 'FRAMESET',
'H1', 'H2', 'H3', 'H4', 'H5', 'H6', 'HEAD', 'HR', 'HTML',
'I', 'IFRAME', 'IMG', 'INPUT', 'INS', 'ISINDEX',
'KBD',
'LABEL', 'LAYER', 'LEGEND', 'LI', 'LINK',
'MAP', 'MENU', 'META', 'NOBR', 'NOFRAMES', 'NOSCRIPT',
'OBJECT', 'OL', 'OPTGROUP', 'OPTION',
'P', 'PARAM', 'PRE',
'Q',
'S', 'SAMP', 'SCRIPT', 'SELECT', 'SMALL', 'SPAN', 'STRIKE', 'STRONG', 'STYLE', 'SUB', 'SUP',
'TABLE', 'TBODY', 'TD', 'TEXTAREA', 'TFOOT', 'TH', 'THEAD', 'TITLE', 'TR', 'TT',
'U', 'UL',
'VAR'}

local function defineTags(tags)
	for index, tag in ipairs(tags) do
		defineTag(tag);
	end
end

defineTags(htmlTags)

local function stringStartsWith(str, start)
	return (string.sub(str,1,string.len(start)) == start)
end

local function insideAttrCodeGen(key, val, buff)
	local vtype = type(val)

	if ((vtype == 'string')or(vtype == 'number')or(vtype == 'boolean')) then
		buff:newline()
		buff:append(writeToResp, '(" ', key, "='", val, "'\")")
	elseif (vtype == 'table') then
		local nodeType = rawget(val, 'nodeType')
        if (nodeType == 'VARIABLE') then
            buff:newline()
            buff:append(writeToResp, '(" ', key, '=\'")')
            buff:newline()
            buff:append(writeToResp, '(', getVarName(val), ')')
            buff:newline()
            buff:append(writeToResp, '("\'")')
        else
            error('Invalid node used inside attrs{} tag. Type: '..tostring(nodeType))
        end
	else
		error('Invalid node used inside attrs{} tag. Type: '..tostring(vtype))
	end
end


local function tagAttrOpen(self, buff)
	if (self.children) then
		for k, v in pairs(self.children) do
			insideAttrCodeGen(k, v ,buff)
		end
	end
	return false
end

local function tagAttrClose(self, buff)
    buff:newline()
    buff:append(writeToResp, '(">\\n")')
    return true
end

function attrs(nested)
	return {
		nodeType = 'HTML_TAG_ATTRS',
		children = nested,
		codeBegin = tagAttrOpen,
		codeEnd = tagAttrClose
	}
end

--
-- Define per page global "model"
--
defineRootVar('model')

--
-- Export
--
return {
    writeToResp = writeToResp,
	getVarName = getVarName
}
