local module = {total_run = 0, total_failed = 0}

function module.assertTrue(expr)
	if not expr then
		error("Assert true failed!", 2)
	end
end

function module.assertFalse(expr)
	if expr then
		error("Assert false failed!", 2)
	end
end

function module.assertNotNil(expr)
	if not expr then
		error("Assert not nil failed!", 2)
	end
end

function module.assertNil(expr)
	if expr then
		error("Assert nil failed!", 2)
	end
end

function module.assertEqual(actual, expected)
	if (actual ~= expected) then
		error(string.format("Assert equal failed! Actual: [%s], Expected: [%s]", actual, expected), 2)
	end
end

function module.assertNotEqual(actual, expected)
	if (actual == expected) then
		error(string.format("Assert not equal failed! Actual: [%s], Expected: [%s]", actual, expected), 2)
	end
end

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
function module.printTable (tbl, indent, tab)
    indent = indent or 0
    tab = tab or "  "
  	print(string.rep(tab, indent) .. "{")
	tprint(tbl, indent+1, tab)
	print(string.rep(tab, indent) .. "}")
end

function module:runTests()
	number_run = 0
	number_failed = 0
	
	for name, func in pairs(self) do
		if (string.find(name, "test") == 1) then
			result, mesg = pcall(func)
			number_run = number_run + 1
			if (string.find(name, "testError") == 1) then
				-- negative test
				if not result then
					print(string.format("    %-40s [OK]", name));
				else
					number_failed = number_failed + 1
					print(string.format("    %-30s [FAILED! Expected to throw error]", name));
				end
			else
				if result then
					print(string.format("    %-40s [OK]", name));
				else
					number_failed = number_failed + 1
					print(string.format("    %-30s [FAILED! %s]", name, mesg));
				end
			end
			self[name] = nil
		end
	end
	
	self.total_run = self.total_run + number_run
	self.total_failed = self.total_failed + number_failed
	
	local info = debug.getinfo(2, "S")
	print('----------------------------------------------------------------------------')
	print(string.format("%s:  Total# %d, Failed# %d", info.source, number_run, number_failed));
	print('----------------------------------------------------------------------------')
end

function printOverallSummary() 
	print('\n*****************************************************************************')
	print(string.format("Overall Summary:  Total# %d, Failed# %d", module.total_run, module.total_failed));
	print('*****************************************************************************\n')

end

return module;