local http_lib = require("luaw_lib")
local tests = require("unit_testing")

tests.testSingleParam1 = function() 
	params = http_lib:urlDecode("name1=value1", {})
	tests.assertEqual(params['name1'], 'value1')
end

tests.testSingleParam2 = function() 
	params = http_lib:urlDecode("n=v", {})
	tests.assertEqual(params['n'], 'v')
end

tests.testSingleParam3 = function() 
	params = http_lib:urlDecode("n=value1", {})
	tests.assertEqual(params['n'], 'value1')
end

tests.testSingleParam4 = function() 
	params = http_lib:urlDecode("name1=v", {})
	tests.assertEqual(params['name1'], 'v')
end

tests.testTwoParam1 = function() 
	params = http_lib:urlDecode("name1=value1&name2=value2", {})
	tests.assertEqual(params['name1'], 'value1')
	tests.assertEqual(params['name2'], 'value2')
end

tests.testTwoParam2 = function() 
	params = http_lib:urlDecode("n=value1&name2=value2", {})
	tests.assertEqual(params['n'], 'value1')
	tests.assertEqual(params['name2'], 'value2')
end

tests.testTwoParam3 = function() 
	params = http_lib:urlDecode("name1=v&name2=value2", {})
	tests.assertEqual(params['name1'], 'v')
	tests.assertEqual(params['name2'], 'value2')
end

tests.testTwoParam4 = function() 
	params = http_lib:urlDecode("name1=value1&n=value2", {})
	tests.assertEqual(params['name1'], 'value1')
	tests.assertEqual(params['n'], 'value2')
end

tests.testTwoParam5 = function() 
	params = http_lib:urlDecode("name1=value1&name2=v", {})
	tests.assertEqual(params['name1'], 'value1')
	tests.assertEqual(params['name2'], 'v')
end

tests.testTwoParam6 = function() 
	params = http_lib:urlDecode("n=v&name2=value2", {})
	tests.assertEqual(params['n'], 'v')
	tests.assertEqual(params['name2'], 'value2')
end

tests.testTwoParam7 = function() 
	params = http_lib:urlDecode("name1=value1&n=v", {})
	tests.assertEqual(params['name1'], 'value1')
	tests.assertEqual(params['n'], 'v')
end

tests.testTwoParam8 = function() 
	params = http_lib:urlDecode("n=value1&name2=v", {})
	tests.assertEqual(params['n'], 'value1')
	tests.assertEqual(params['name2'], 'v')
end

tests.testTwoParam9 = function() 
	params = http_lib:urlDecode("name1=v&n=value2", {})
	tests.assertEqual(params['name1'], 'v')
	tests.assertEqual(params['n'], 'value2')
end

tests.testTwoParam10 = function() 
	params = http_lib:urlDecode("name1=value1&name2=value2&", {})
	tests.assertEqual(params['name1'], 'value1')
	tests.assertEqual(params['name2'], 'value2')
end

tests.testTwoParam11 = function() 
	params = http_lib:urlDecode("n=value1&name2=value2&", {})
	tests.assertEqual(params['n'], 'value1')
	tests.assertEqual(params['name2'], 'value2')
end

tests.testTwoParam12 = function() 
	params = http_lib:urlDecode("name1=v&name2=value2&", {})
	tests.assertEqual(params['name1'], 'v')
	tests.assertEqual(params['name2'], 'value2')
end

tests.testTwoParam13 = function() 
	params = http_lib:urlDecode("name1=value1&n=value2&", {})
	tests.assertEqual(params['name1'], 'value1')
	tests.assertEqual(params['n'], 'value2')
end

tests.testTwoParam14 = function() 
	params = http_lib:urlDecode("name1=value1&name2=v&", {})
	tests.assertEqual(params['name1'], 'value1')
	tests.assertEqual(params['name2'], 'v')
end

tests.testTwoParam15 = function() 
	params = http_lib:urlDecode("n=v&name2=value2&", {})
	tests.assertEqual(params['n'], 'v')
	tests.assertEqual(params['name2'], 'value2')
end

tests.testTwoParam16 = function() 
	params = http_lib:urlDecode("name1=value1&n=v&", {})
	tests.assertEqual(params['name1'], 'value1')
	tests.assertEqual(params['n'], 'v')
end

tests.testTwoParam17 = function() 
	params = http_lib:urlDecode("n=value1&name2=v&", {})
	tests.assertEqual(params['n'], 'value1')
	tests.assertEqual(params['name2'], 'v')
end

tests.testTwoParam18 = function() 
	params = http_lib:urlDecode("name1=v&n=value2&", {})
	tests.assertEqual(params['name1'], 'v')
	tests.assertEqual(params['n'], 'value2')
end

tests.testParamNameOnly1 = function() 
	params = http_lib:urlDecode("name", {})
end

tests.testParamNameOnly2 = function() 
	params = http_lib:urlDecode("n", {})
end

tests.testParamNameOnly3 = function() 
	params = http_lib:urlDecode("name=", {})
end

tests.testParamNameOnly4 = function() 
	params = http_lib:urlDecode("n=", {})
end

tests.testSingleHexParam1 = function() 
	params = http_lib:urlDecode("name%201=value%2F1", {})
	tests.assertEqual(params['name 1'], 'value/1')
end

tests.testSingleHexParam2 = function() 
	params = http_lib:urlDecode("n%20=v%2F", {})
	tests.assertEqual(params['n '], 'v/')
end

tests.testSingleHexParam3 = function() 
	params = http_lib:urlDecode("n%26=value1", {})
	tests.assertEqual(params['n&'], 'value1')
end

tests.testSingleHexParam4 = function() 
	params = http_lib:urlDecode("name1=v%26", {})
	tests.assertEqual(params['name1'], 'v&')
end

tests.testTwoHexParam1 = function() 
	params = http_lib:urlDecode("name%201=value%2F1&na%20me2=va%2Flue2", {})
	tests.assertEqual(params['name 1'], 'value/1')
	tests.assertEqual(params['na me2'], 'va/lue2')
end

tests.testTwoHexParam2 = function() 
	params = http_lib:urlDecode("n=value1&%2Fname2=value2%26", {})
	tests.assertEqual(params['n'], 'value1')
	tests.assertEqual(params['/name2'], 'value2&')
end

tests.testTwoHexParam3 = function() 
	params = http_lib:urlDecode("name1=%26v&%2Fname2=value2", {})
	tests.assertEqual(params['name1'], '&v')
	tests.assertEqual(params['/name2'], 'value2')
end

tests.testTwoHexParam4 = function() 
	params = http_lib:urlDecode("%26name1=value1%2F&n=value2", {})
	tests.assertEqual(params['&name1'], 'value1/')
	tests.assertEqual(params['n'], 'value2')
end

tests.testTwoHexParam5 = function() 
	params = http_lib:urlDecode("name1=value1&%26name2=v%2F", {})
	tests.assertEqual(params['name1'], 'value1')
	tests.assertEqual(params['&name2'], 'v/')
end

tests.testTwoHexParam6 = function() 
	params = http_lib:urlDecode("n=v%26&%2Fname2=value2", {})
	tests.assertEqual(params['n'], 'v&')
	tests.assertEqual(params['/name2'], 'value2')
end

tests.testTwoHexParam7 = function() 
	params = http_lib:urlDecode("%26name1=value1&n=v%2F", {})
	tests.assertEqual(params['&name1'], 'value1')
	tests.assertEqual(params['n'], 'v/')
end

tests.testTwoHexParam8 = function() 
	params = http_lib:urlDecode("n%26=%2Fvalue1&name2=v", {})
	tests.assertEqual(params['n&'], '/value1')
	tests.assertEqual(params['name2'], 'v')
end

tests.testTwoHexParam9 = function() 
	params = http_lib:urlDecode("name1=v&n%26=%2Fvalue2", {})
	tests.assertEqual(params['name1'], 'v')
	tests.assertEqual(params['n&'], '/value2')
end

tests.testTwoHexParam10 = function() 
	params = http_lib:urlDecode("na%20me%1=val%2Fue%1&name%2=value%2", {})
	tests.assertEqual(params['na me%1'], 'val/ue%1')
	tests.assertEqual(params['name%2'], 'value%2')
end

tests.testTwoHexParam11 = function() 
	params = http_lib:urlDecode("name%201=value%2F1&na%20me2=va%2Flue2&", {})
	tests.assertEqual(params['name 1'], 'value/1')
	tests.assertEqual(params['na me2'], 'va/lue2')
end

tests.testTwoHexParam12 = function() 
	params = http_lib:urlDecode("n=value1&%2Fname2=value2%26&", {})
	tests.assertEqual(params['n'], 'value1')
	tests.assertEqual(params['/name2'], 'value2&')
end

tests.testTwoHexParam13 = function() 
	params = http_lib:urlDecode("name1=%26v&%2Fname2=value2&", {})
	tests.assertEqual(params['name1'], '&v')
	tests.assertEqual(params['/name2'], 'value2')
end

tests.testTwoHexParam14 = function() 
	params = http_lib:urlDecode("%26name1=value1%2F&n=value2&", {})
	tests.assertEqual(params['&name1'], 'value1/')
	tests.assertEqual(params['n'], 'value2')
end

tests.testTwoHexParam15 = function() 
	params = http_lib:urlDecode("name1=value1&%26name2=v%2F&", {})
	tests.assertEqual(params['name1'], 'value1')
	tests.assertEqual(params['&name2'], 'v/')
end

tests.testTwoHexParam16 = function() 
	params = http_lib:urlDecode("n=v%26&%2Fname2=value2&", {})
	tests.assertEqual(params['n'], 'v&')
	tests.assertEqual(params['/name2'], 'value2')
end

tests.testTwoHexParam17 = function() 
	params = http_lib:urlDecode("%26name1=value1&n=v%2F&", {})
	tests.assertEqual(params['&name1'], 'value1')
	tests.assertEqual(params['n'], 'v/')
end

tests.testTwoHexParam18 = function() 
	params = http_lib:urlDecode("n%26=%2Fvalue1&name2=v&", {})
	tests.assertEqual(params['n&'], '/value1')
	tests.assertEqual(params['name2'], 'v')
end

tests.testTwoHexParam19 = function() 
	params = http_lib:urlDecode("name1=v&n%26=%2Fvalue2&", {})
	tests.assertEqual(params['name1'], 'v')
	tests.assertEqual(params['n&'], '/value2')
end

tests.testTwoHexParam20 = function() 
	params = http_lib:urlDecode("na%20me%1=val%2Fue%1&name%2=value%2&", {})
	tests.assertEqual(params['na me%1'], 'val/ue%1')
	tests.assertEqual(params['name%2'], 'value%2')
end

tests.testErrorEncoding1 = function() 
	params = assert(http_lib:urlDecode("name1&value1"), "wrong encoding", {})
end

tests.testErrorEncoding2 = function() 
	params = assert(http_lib:urlDecode("n&v"), "wrong encoding", {})
end

tests.testErrorEncoding3 = function() 
	params = assert(http_lib:urlDecode("=value1"), "wrong encoding", {})
end

tests:runTests()
