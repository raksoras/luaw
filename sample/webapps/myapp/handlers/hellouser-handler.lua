webapp:registerResource {
    method = 'GET',
    path = '/user/:username/#count',

	handler = function(httpConn)
		httpConn:appendBody("Hello "..httpConn.pathParams.username.."! You are user number "..httpConn.pathParams.count.." to visit this site.")
	end
}

