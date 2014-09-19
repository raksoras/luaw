local webapp = require("luaw_webapp")

webapp.GET 'hello/:name' {
	function(req, resp, pathParams)
	    return 200, "Hello "..pathParams.name.."!"
	end
}
