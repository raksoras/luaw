GET '/user/:username/#count' {
	function(req, resp, pathParams)
		return "Hello "..pathParams.username.."! You are user number "..pathParams.count.." to visit this site."
	end
}

