local http_lib = require("luaw_lib")
local tests = require("unit_testing")

local CRLF = '\r\n'

local mock_conn = {
    startReading = function() return true end
}

local function getBody(req) 
    if req.bodyChunks then
        return table.concat(req.bodyChunks)
    end
end


local function buildHeadersAndBody(input, mesg)
	if input.headers then
		for k,v in pairs(input.headers) do
			mesg = mesg .. k .. ': ' .. v .. CRLF
		end
	end
	mesg = mesg .. CRLF
	if input.body then
		mesg = mesg .. input.body .. CRLF
	end
	mesg = mesg .. CRLF
	return mesg
end

local function buildHttpRequestBody(input)
	local mesg = input.method .. ' '.. input.url .. " HTTP/" .. input.major_version .. '.' .. input.minor_version .. CRLF
	return buildHeadersAndBody(input, mesg)
end

local function buildHttpResponseBody(input)
	local mesg = "HTTP/" .. input.major_version .. '.' .. input.minor_version .. ' ' .. input.status .. ' ' .. input.status_message .. CRLF
	return buildHeadersAndBody(input, mesg)
end

local function assertHeadersAndBodyAreEqual(original, parsed)
--	tests.printTable(parsed)
--	tests.printTable(original)
	tests.assertEqual(original.major_version, parsed.major_version)
	tests.assertEqual(original.minor_version, parsed.minor_version)
	if (original.headers) then
		for k,v in pairs(original.headers) do
			tests.assertEqual(original.headers[k], parsed.headers[k])
		end
	end
	if original.body then
 		tests.assertEqual(original.body, getBody(parsed))
	else 
		tests.assertNil(parsed.body)
	end
end

local function assertRequestsAreEqual(original, parsed)
	tests.assertEqual(original.method, parsed.method)
	tests.assertEqual(original.url, parsed.url)
	assertHeadersAndBodyAreEqual(original, parsed)
end

local function assertResponsesAreEqual(original, parsed)
	tests.assertEqual(original.status, parsed.status)
	assertHeadersAndBodyAreEqual(original, parsed)
end

local function testParsedHttpReq(body, input)
	local parser = http_lib.newHttpRequestParser()
	local req = http_lib.newServerHttpRequest(mock_conn)
	parser:parseHttpString(req, body)
	assertRequestsAreEqual(input, req)
	return req;
end

local function testHttpReqRoundTrip(input)
	local body = buildHttpRequestBody(input)
	return testParsedHttpReq(body, input)
end

local function testParsedHttpResp(body, input)
	local parser = http_lib:newHttpResponseParser()
	local resp = http_lib:newServerHttpResponse(mock_conn)
	parser:parseHttpString(resp, body)
	assertResponsesAreEqual(input, resp)
	return resp;
end

local function testHttpRespRoundTrip(input)
	local body = buildHttpResponseBody(input)
	return testParsedHttpResp(body, input)
end

local urlParts = { "schema", "host", "port", "path", "queryString", "fragment", "userinfo" }

local function assertParsedURL(expected, actual)
	for i,k in ipairs(urlParts) do
		expectedVal = expected[k];
		if expectedVal then
			tests.assertEqual(expectedVal, actual[k])
		else
			tests.assertNil(actual[k])
		end
	end
end

-- Requests

tests.testSimpleHttpReq = function() 
	testHttpReqRoundTrip {
		method = 'POST',
		url = '/test',
		major_version = 1,
		minor_version = 1,
		headers = {
			["Content-Length"] = "5",
			["Content-Type"] = "text/plain"
		},
		body = 'Hello'
	}
end

tests.testHttpReq1 = function() 
	testHttpReqRoundTrip {
		method = 'GET',
		url = '/test',
		major_version = 1,
		minor_version = 1,
		headers = {
			["User-Agent"] = "curl/7.18.0 (i486-pc-linux-gnu) libcurl/7.18.0 OpenSSL/0.9.8g zlib/1.2.3.3 libidn/1.1",
			Host = "0.0.0.0=5000",
			Accept = "*/*"
		}
	}
end

tests.testHttpReq2 = function() 
	testHttpReqRoundTrip {
		method = 'GET',
		url = '/favicon.ico',
		major_version = 1,
		minor_version = 1,
		headers = {
			Host = "0.0.0.0=5000",
			["User-Agent"] = "Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.9) Gecko/2008061015 Firefox/3.0",
			Accept = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
			["Accept-Language"] = "en-us,en;q=0.5",
			[ "Accept-Encoding"] = "gzip,deflate",
			["Accept-Charset"] = "ISO-8859-1,utf-8;q=0.7,*;q=0.7",
			["Keep-Alive"] = "300",
			Connection = "keep-alive"
		}
	}
end

tests.testHttpReq3 = function() 
	testHttpReqRoundTrip {
		method = 'GET',
		url = '/dumbduck',
		major_version = 1,
		minor_version = 1,
		headers = {
			aaaaaaaaaaaaa = "++++++++++"
		}
	}
end

tests.testHttpReq4 = function() 
	local req = testHttpReqRoundTrip {
		method = 'GET',
		url = 'http://luaw.com:8080/forums/1/topics/2375?page=1#posts-17408',
		major_version = 1,
		minor_version = 1,
	}
	local parsed_url = req:getParsedURL()

	assertParsedURL({fragment = "posts-17408",
  		queryString = "page=1",
  		port  = "8080",
  		schema = "http",
  		path = "/forums/1/topics/2375",
  		host = "luaw.com"}, parsed_url)
	
	parsed_url.test_memoization = "testx"
	local parsed_url2 = req:getParsedURL()
	tests.assertEqual("testx", parsed_url2.test_memoization)
end

tests.testHttpReq5 = function() 
	testHttpReqRoundTrip {
		method = 'GET',
		url = '/get_no_headers_no_body/world',
		major_version = 1,
		minor_version = 1,
	}
end

tests.testHttpReq6 = function() 
	testHttpReqRoundTrip {
		method = 'GET',
		url = '/get_one_headers_no_body/world',
		major_version = 1,
		minor_version = 1,
		headers = {
			Accept = "*/*",
		}
	}
end

tests.testHttpReq7 = function() 
	testHttpReqRoundTrip {
		method = 'GET',
		url = '/get_funky_content_length_body_hello',
		major_version = 1,
		minor_version = 0,
		headers = {
			["conTENT-Length"] = "5",
		},
		body = 'HELLO'
	}
end

tests.testHttpReq8 = function() 
	local req = testHttpReqRoundTrip {
		method = 'POST',
		url = '/post_identity_body_world?q=search#hey',
		major_version = 1,
		minor_version = 1,
		headers = {
			["Accept"] = "*/*",
			["Transfer-Encoding"] = "identity",
			["Content-Length"] ="5"
		},
		body = 'World'
	}
	
	local parsed_url = req:getParsedURL()
	assertParsedURL({fragment = "hey",
	queryString = "q=search",
	path = "/post_identity_body_world"}, parsed_url)

end

tests.testHttpReq9 = function() 
	local input =  {
		method = 'POST',
		url = '/post_chunked_all_your_base',
		major_version = 1,
		minor_version = 1,
		headers = {
			["Transfer-Encoding"] = "chunked",
		},
		body = "all your base are belong to us"
	}
	
	local body = "POST /post_chunked_all_your_base HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n1e\r\nall your base are belong to us\r\n0\r\n\r\n"
	testParsedHttpReq(body, input)
end

tests.testHttpReq10 = function() 
	local input =  {
		method = 'POST',
		url = '/two_chunks_mult_zero_end',
		major_version = 1,
		minor_version = 1,
		headers = {
			["Transfer-Encoding"] = "chunked",
		},
		body = "hello world"
	}
	
	local body = "POST /two_chunks_mult_zero_end HTTP/1.1\r\n" ..
         "Transfer-Encoding: chunked\r\n" ..
         "\r\n" ..
         "5\r\nhello\r\n"..
         "6\r\n world\r\n"..
         "000\r\n"..
         "\r\n"
	testParsedHttpReq(body, input)
end

tests.testHttpReq10 = function() 
	local input =  {
		method = 'POST',
		url = '/chunked_w_trailing_headers',
		major_version = 1,
		minor_version = 1,
		headers = {
			Vary = "*",
		    ["Content-Type"] = "text/plain",
		    ["Transfer-Encoding"] = "chunked"
		},
		body = "hello world"
	}
	
	local body = "POST /chunked_w_trailing_headers HTTP/1.1\r\n"..
         "Transfer-Encoding: chunked\r\n"..
         "\r\n"..
         "5\r\nhello\r\n"..
         "6\r\n world\r\n"..
         "0\r\n"..
         "Vary: *\r\n"..
         "Content-Type: text/plain\r\n"..
         "\r\n"
	testParsedHttpReq(body, input)
end

tests.testHttpReq11 = function() 
	local input =  {
		method = 'POST',
		url = '/chunked_w_rubbish_after_length',
		major_version = 1,
		minor_version = 1,
		headers = {
			["Transfer-Encoding"] = "chunked"
		},
		body = "hello world"
	}
	
	local body = "POST /chunked_w_rubbish_after_length HTTP/1.1\r\n"..
         "Transfer-Encoding: chunked\r\n"..
         "\r\n"..
         "5; ihatew3;wtf=aretheseparametersfor\r\nhello\r\n"..
         "6; blahblah; blah\r\n world\r\n"..
         "0\r\n"..
         "\r\n"
	testParsedHttpReq(body, input)
end

tests.testHttpReq12 = function() 
	local req = testHttpReqRoundTrip {
		method = "GET",
	    url = "https://luna.com:473/foo/t.html?qstring#frag",
		major_version = 1,
		minor_version = 1,	    
	    headers = {
    	    Host = "localhost:8000",
        	["User-Agent"] = "ApacheBench/2.3",
        	["Content-Length"] = "5",
	        Accept = "*/*",
    	},
    	body = "body\n"
    }
    
    local parsed_url = req:getParsedURL()
	assertParsedURL({fragment = "frag",
	queryString = "qstring",
	port  = "473",
	schema = "https",
	path = "/foo/t.html",
	host = "luna.com"}, parsed_url)

end

tests.testHttpReq13 = function() 
	testHttpReqRoundTrip {
		method = "GET",
	    url = "/",
		major_version = 1,
		minor_version = 1,	    
	    headers = {
    	    Host = "foo:80",
        	["Content-Length"] = "12",
	        Accept = "*/*",
    	},
    	body = "chunk1chunk2"
    }
end

tests.testHttpReq14 = function() 
	testHttpReqRoundTrip {
		method = "GET",
	    url = "/",
		major_version = 1,
		minor_version = 1,	    
	    headers = {
    	    Host = "localhost",
        	["User-Agent"] = "httperf/0.9.0"

    	}
    }
end

tests.testHttpReq15 = function() 
	testHttpReqRoundTrip {
		method = "GET",
    	url = "/",
		major_version = 1,
		minor_version = 1,	    
	    headers = {
    	    ["User-Agent"] = "Mozilla/5.0 (X11; U;Linux i686; en-US; rv:1.9.0.15)Gecko/2009102815 Ubuntu/9.04 (jaunty)Firefox/3.0.15",
        	Accept = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
	        ["Accept-Language"] = "en-gb,en;q=0.5",
    	    ["Accept-Encoding"] = "gzip,deflate",
        	["Accept-Charset"] = "ISO-8859-1,utf-8;q=0.7,*;q=0.7",
	        ["Keep-Alive"] = "300",
    	    Connection = "keep-alive",
    	}  
	}
end

tests.testHttpReq16 = function() 
	local input =  {
		method = 'GET',
		url = '/',
		major_version = 1,
		minor_version = 1,
		headers = {
			["Transfer-Encoding"] = "chunked"
		},
		body = "This is the data in the first chunkX and this is the second one"
	}
	
	local parser = http_lib:newHttpRequestParser()
	local req = http_lib.newServerHttpRequest(mock_conn)
	parser:parseHttpString(req, "GET / HTTP/1.1\r\n")
    parser:parseHttpString(req, "Transfer-Encoding: chunked\r\n")
    parser:parseHttpString(req, "\r\n")
    parser:parseHttpString(req, "23\r\n")
    parser:parseHttpString(req, "This is the data in the first chunk\r\n")
    parser:parseHttpString(req, "1C\r\n")
    parser:parseHttpString(req, "X and this is the second one\r\n")
    parser:parseHttpString(req, "0\r\n\r\n")

	assertRequestsAreEqual(input, req)
end

tests.testHttpReq17 = function() 
	local input =  {
		method = 'GET',
		url = '/foo/t.html?qstring#frag',
		major_version = 1,
		minor_version = 1,
		headers = {
			 Host = "localhost:8000",
            ["User-Agent"] = "ApacheBench/2.3",
            Accept = "*/*",
            ["Content-Length"] = "5"
		},
		body = "body\n"
	}
	
	local parser = http_lib.newHttpRequestParser()
	local req = http_lib.newServerHttpRequest(mock_conn)
	parser:parseHttpString(req, "GET /")
	parser:parseHttpString(req, "foo/t")
	parser:parseHttpString(req, ".html?") 
	parser:parseHttpString(req, "qst")
	parser:parseHttpString(req, "ring") 
	parser:parseHttpString(req, "#fr") 
	parser:parseHttpString(req, "ag ")
	parser:parseHttpString(req, "HTTP/1.1\r\n")
    parser:parseHttpString(req,"Ho")
    parser:parseHttpString(req, "st: loca")
    parser:parseHttpString(req, "lhos")
    parser:parseHttpString(req, "t:8000\r\nUser-Agent: ApacheBench/2.3\r\n")
    parser:parseHttpString(req, "Con")
    parser:parseHttpString(req, "tent-L")
    parser:parseHttpString(req, "ength")
    parser:parseHttpString(req, ": 5\r\n")
    parser:parseHttpString(req, "Accept: */*\r\n\r")
    parser:parseHttpString(req, "\nbody\n")

    assertRequestsAreEqual(input, req)
    
	local parsed_url = req:getParsedURL()
	assertParsedURL({fragment = "frag",
	queryString = "qstring",
	path = "/foo/t.html"}, parsed_url)

end

tests.testHttpReq18 = function() 
	local input =  {
		method = 'GET',
		url = '/',
		major_version = 1,
		minor_version = 1,
		headers = {
			 Host = "foo:80",
            ["Content-Length"] = "12"
		},
		body = "chunk1chunk2"
	}
	
	local parser = http_lib.newHttpRequestParser()
	local req = http_lib.newServerHttpRequest(mock_conn)
	parser:parseHttpString(req, "GET / HTTP/1.1\r\n")
	parser:parseHttpString(req, "Host: foo:80\r\n")
	parser:parseHttpString(req, "Content-Length: 12\r\n") 
	parser:parseHttpString(req, "\r\n")
	parser:parseHttpString(req, "chunk1") 
	parser:parseHttpString(req, "chunk2") 

    assertRequestsAreEqual(input, req)
end

tests.testHttpReq19 = function() 
	local input =  {
		method = 'GET',
		url = '/',
		major_version = 1,
		minor_version = 1,
		headers = {
			 Host = "localhost",
            ["User-Agent"] = "httperf/0.9.0"
		}
	}
	
	local parser = http_lib.newHttpRequestParser()
	local req = http_lib.newServerHttpRequest(mock_conn)
	parser:parseHttpString(req, "GET / HTTP/1.1\r\n")
	parser:parseHttpString(req, "Host: localhost\r\n")
	parser:parseHttpString(req, "User-Agent: httperf/0.9.0\r\n\r\n")

    assertRequestsAreEqual(input, req)
end

tests.testHttpReq20 = function() 
	local input =  {
		method = 'GET',
		url = '/',
		major_version = 1,
		minor_version = 1,
		headers = {
			 Host = "two.local:8000",
            ["User-Agent"] = "Mozilla/5.0 (X11; U;Linux i686; en-US; rv:1.9.0.15)Gecko/2009102815 Ubuntu/9.04 (jaunty)Firefox/3.0.15",
            Accept = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            ["Accept-Language"] = "en-gb,en;q=0.5",
            ["Accept-Encoding"] = "gzip,deflate",
            ["Accept-Charset"] = "ISO-8859-1,utf-8;q=0.7,*;q=0.7",
            ["Keep-Alive"] = "300",
            Connection = "keep-alive"
		}
	}
	
	local parser = http_lib.newHttpRequestParser()
	local req = http_lib.newServerHttpRequest(mock_conn)
	
	parser:parseHttpString(req, "GET / HTTP/1.1\r\n")
	parser:parseHttpString(req, "Host: two.local:8000\r\n")
	parser:parseHttpString(req, "User-Agent: Mozilla/5.0 (X11; U;")
	parser:parseHttpString(req, "Linux i686; en-US; rv:1.9.0.15)")
	parser:parseHttpString(req, "Gecko/2009102815 Ubuntu/9.04 (jaunty)")
	parser:parseHttpString(req, "Firefox/3.0.15\r\n")
	parser:parseHttpString(req, "Accept: text/html,application/xhtml+xml,application/xml;")
	parser:parseHttpString(req, "q=0.9,*/*;q=0.8\r\n")
	parser:parseHttpString(req, "Accept-Language:en-gb,en;q=0.5\r\n")
	parser:parseHttpString(req, "Accept-Encoding: gzip,deflate\r\n")
	parser:parseHttpString(req, "Accept-Charset:ISO-8859-1,utf-8;q=0.7,*;q=0.7\r\n")
	parser:parseHttpString(req, "Keep-Alive: 300\r\n")
	parser:parseHttpString(req, "Connection:keep-alive\r\n\r\n")
	
    assertRequestsAreEqual(input, req)    
end
-- Responses

tests.testSimpleHttpResp = function() 
	testHttpRespRoundTrip {
		status = 200,
		status_message = 'OK',
		major_version = 1,
		minor_version = 1,
		headers = {
			["Content-Length"] = "5",
			["Content-Type"] = "text/plain"
		},
		body = 'Hello'
	}
end

tests.testHttpResp1 = function() 
	testHttpRespRoundTrip {
		status = 301,
		status_message = 'Moved Permanently',
		major_version = 1,
		minor_version = 1,
		headers = {
			Location = "http://www.google.com/",
    		["Content-Type"] = "text/html; charset=UTF-8",
    		Date = "Sun, 26 Apr 2009 11:11:49 GMT",
    		Expires = "Tue, 26 May 2009 11:11:49 GMT",
    		["Cache-Control"] = "public, max-age=2592000",
    		Server = "gws",
		    ["Content-Length"] = "219"
		},
		body = "<HTML><HEAD><meta http-equiv=\"content-type\" content=\"text/html;charset=utf-8\">\n"..
         "<TITLE>301 Moved</TITLE></HEAD><BODY>\n"..
         "<H1>301 Moved</H1>\n"..
         "The document has moved\n"..
         "<A HREF=\"http://www.google.com/\">here</A>.\r\n"..
         "</BODY></HTML>\r\n"
	}
end

tests.testHttpResp2 = function() 
	local input = {
		status = 200,
		status_message = 'OK',
		major_version = 1,
		minor_version = 1,
		headers = {
			Date = "Wed, 02 Feb 2011 00:50:50 GMT",
    		["Content-Length"] = "10",
    		Connection = "close"
		},
		body = "0123456789"
	}
	
	local parser = http_lib.newHttpResponseParser()
	local resp = http_lib.newServerHttpResponse()	
	parser:parseHttpString(resp, "HTTP/1.1 100 Please continue mate.\r\n\r\n")
	parser:parseHttpString(resp, "HTTP/1.1 200 OK\r\n")
	parser:parseHttpString(resp, "Date: Wed, 02 Feb 2011 00:50:50 GMT\r\n")
	parser:parseHttpString(resp, "Content-Length: 10\r\n")
	parser:parseHttpString(resp, "Connection: close\r\n\r\n")
	parser:parseHttpString(resp, "0123456789")
--	tests.printTable(resp)
    assertResponsesAreEqual(input, resp)    

end

tests.testHttpResp3 = function() 
	local input = {
		status = 200,
		status_message = 'OK',
		major_version = 1,
		minor_version = 1,
		headers = {
			Date = "Wed, 02 Feb 2011 00:50:50 GMT",
    		Connection = "close"
		},
		body = "0123456789"
	}
	
	local parser = http_lib:newHttpResponseParser()
	local resp = http_lib:newServerHttpResponse()	
	parser:parseHttpString(resp, "HTTP/1.1 200 OK\r\n")
	parser:parseHttpString(resp, "Date: Wed, 02 Feb 2011 00:50:50 GMT\r\n")
	parser:parseHttpString(resp, "Connection: close\r\n\r\n")
	parser:parseHttpString(resp, "0123456789")
	
    assertResponsesAreEqual(input, resp)    

end

tests.testHttpResp4 = function() 
	local input = {
		status = 200,
		status_message = 'OK',
		major_version = 1,
		minor_version = 1,
		headers = {
			Date = "Wed, 02 Feb 2011 00:50:50 GMT",
    		["Content-Length"] = "10",
    		Connection = "close"
		},
		body = "0123456789"
	}
	
	local parser = http_lib:newHttpResponseParser()
	local resp = http_lib:newServerHttpResponse()	
	parser:parseHttpString(resp, "HTTP/1.1 10")
	parser:parseHttpString(resp, "0 Please continue mate.")
	parser:parseHttpString(resp, "\r\n\r\n")
	parser:parseHttpString(resp, "HT")
	parser:parseHttpString(resp, "TP/1.1 20")
	parser:parseHttpString(resp, "0 OK\r\n")
	parser:parseHttpString(resp, "Date:")
	parser:parseHttpString(resp, " Wed, 02 Feb 2011")
	parser:parseHttpString(resp, " 00:50:50 GMT\r\nContent-Le")
	parser:parseHttpString(resp, "ngth: 10\r\n")
	parser:parseHttpString(resp, "Connection: close\r\n\r\n01234")
	parser:parseHttpString(resp, "56789")
	
    assertResponsesAreEqual(input, resp)    

end

tests.testHttpResp5 = function() 
	local input = {
		status = 200,
		status_message = 'OK',
		major_version = 1,
		minor_version = 1,
		headers = {
			Date = "Wed, 02 Feb 2011 00:50:50 GMT",
    		Connection = "close"
		},
		body = "0123456789"
	}
	
	local parser = http_lib:newHttpResponseParser()
    local resp = http_lib:newServerHttpResponse()	
	parser:parseHttpString(resp, "HTTP/1.1 2")
	parser:parseHttpString(resp, "00 OK\r\n")
	parser:parseHttpString(resp, "Date: Wed, 02 Feb 2011 00:50:50 GMT\r\nCon")
	parser:parseHttpString(resp, "nection: clo")
	parser:parseHttpString(resp, "se\r\n\r\n01234")
	parser:parseHttpString(resp, "5")
	parser:parseHttpString(resp, "6")
	parser:parseHttpString(resp, "7")
	parser:parseHttpString(resp, "89")
    assertResponsesAreEqual(input, resp)    

end

tests:runTests()
--tests.testHttpReq17()
