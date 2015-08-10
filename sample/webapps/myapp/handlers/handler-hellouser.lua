registerHandler {
    method = 'GET',
    path = '/user/:username/#count',

	handler = function(req, resp)
		resp:appendBody("Hello "..req.pathParams.username.."! You are user number "..req.pathParams.count.." to visit this site.")
	end
}

