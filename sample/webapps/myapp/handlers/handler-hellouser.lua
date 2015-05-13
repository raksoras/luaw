registerHandler {
    method = 'GET',
    path = '/user/:username/#count',

	handler = function(req, resp, pathParams)
		return "Hello "..pathParams.username.."! You are user number "..pathParams.count.." to visit this site."
	end
}

