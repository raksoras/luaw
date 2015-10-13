registerHandler {
    method = 'GET',
    path = 'helloworld',

    handler = function(httpConn)
        httpConn:appendBody("Hello World from ")
        httpConn:appendBody(httpConn:getBody())
        httpConn:appendBody("\n")
    end
}

