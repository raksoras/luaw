registerHandler {
    method = 'GET',
    path = 'helloworld',

    handler = function(req, resp)
        resp:appendBody("Hello World!\n")
    end
}

