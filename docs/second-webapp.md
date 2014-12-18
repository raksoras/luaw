#5. Your Second Luaw webapp - "Hello `username`!"

Luaw handlers can accept and process HTTP request parameters (query parameters as well as form parameters) using the request object that is passed to the resource handler function. These parameters are available as `req.params`. For example to access HTTP parameter 'username' - either passed as a query parameter like `?username=raksoras` or POSTed as a form field - you can do either `req.params.username` or `req.params['username']`

Luaw also supports mapping parts of URL paths to REST path parameters. We will use this method to receive username. Let's say we want to use URL format '/user/raksoras' where raksoras is the input user name. To do this create a new handler named "handler-hellouser.lua" under `luaw_root_dir/webapps/myapp/handlers` that we created in previous chapter and put following code in it:
```lua
GET '/user/:username' {
	function(req, resp, pathParams)
		return "Hello "..pathParams.username.."!"
	end
}
```
Here colon in `:username` in the URL path `user/:username` identifies it as a REST path parameter. Luaw will parse it from the URL path at runtime and will make it available on the third paramter - pathParams - passed to the handler function. Inside the function you may refer to it as either `pathParams.username` or `pathParams['username']`

Now restart your Luaw server and then point your browser to http://localhost:7001/myapp/user/your_name and Luaw should greet you this time in a more personal manner!

In fact, the preceding ":" identifies the path parameter as a string path parameter. You can use preceding "#" to identify a path parameter as a numerical path parameter instead and Luaw will automatically parse it as a number. For example, you can change the handler-hellouser.lua code as follows,

```lua
GET '/user/:username/#count' {
	function(req, resp, pathParams)
		return "Hello "..pathParams.username.."! You are user number "..pathParams.count.." to visit this site."
	end
}
```

and then point your browser to "http://localhost:7001/myapp/user/raksoras/9" to get
```
Hello raksoras! You are user number 9 to visit this site.
```
in your browser window.