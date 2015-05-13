registerHandler {
    method = 'GET',
    path = 'helloworld',

    handler = function(req, resp, pathParams)
        return "Hello World!"
    end
}

