#4. Your First Luaw Webapp - "Hello world!"

Now that we are familiar with Luaw's directory layout and configuration, we are ready to write our first webapp - "Hello world" but of course.

Luaw comes equipped with [Ruby's Sinatra](http://www.sinatrarb.com/) like web framework that allows mapping URLs to request handlers (routes in Sinatra's terminology). It has full support for REST path and query parameters.

##Writing Luaw Request Handler

1. Switch to directory `luaw_root_dir/webapps` that was created in chapter "Getting started" and create a directory called `myapp` under it. This is our first webapp.

		cd luaw_root_dir/webapps
		mkdir myapp
		cd myapp

2. create a filed called web.lua in `luaw_root_dir/webapps/myapp` and put following content in it
```lua
luaw_webapp = {
		resourcePattern = "handler%-.*%.lua",
}
```
This is a bare minimum webapp configuration that basically tells Luaw to load any file matching Lua regex pattern "handler%-.*%.lua" as a URL (or in REST terminology Resource) handler.

3. Now we will write our first resource handler. create a directory `handlers` under `luaw_root_dir/webapps/myapp` and create a file named `handler-helloworld.lua` under it. The choice of the directory name "handlers" is purely arbitrary. All that matters is that handler's file name matches the pattern `handler%-.*%.lua` that we have specified in web.lua. Luaw will traverse all folders under `luaw_root_dir/webapps/myapp` looking for handler files to load that match the pattern. This means we could have placed handler-helloworld.lua directly under luaw_root_dir/webapps/myapp and it would have still worked. It's probably a better practice to put them in their own directory like "handlers" from the point of view of clean code organization though.
Next put following code in "handler-helloworld.lua":
```lua
    GET 'helloworld' {
        function(req, resp, pathParams)
            return "Hello World!"
        end
    }
```

	In the code above GET identifies the HTTP method this handler will service. Other methods available are POST, PUT, DELETE, HEAD, OPTIONS, TRACE and CONNECT corresponding to respective HTTP methods. There is also a catch-all, uber method called  SERVICE that you can use in case you want to handle any HTTP request irrespective of its method.
the string 'helloworld' specifies the URL path this handler will match. It is analogus to Sinatra's route. It means this handler will be invoked for all GET methods made on `/myapp/helloworld` URL.

	Finally, the function in the above example is the actual code run whenever `/myapp/helloworld` is requested. The function is passed incoming HTTP request, HTTP response to write to and any REST path parameters defined on the resources. We will see how to used all three of these objects in subsequent chapters. For now, we just want to follow the age old rite of passage and say "Hello World!" to the browser. Simply returning the string "Hello World!" from our function is sufficient to achieve this. Later we will see more sophisticated ways of forming and returning response using response object and Luaw template views.

4. Now we are ready to start the server. To do this switch to `luaw_root_dir` and run Luaw server like this:
		cd luaw_root_dir
		./bin/luaw_server ./conf/server.cfg

	First argument to the luaw_server is always the server configuration file. If you have followed all the steps so far correctly, you should see following output in your console window:

```
******************** Starting webapp myapp *******************************
	.Loading resource ./webapps/myapp/handlers/handler-helloworld.lua
	#Loaded total 1 resources

	#Compiled total 0 views
 *********************** Webapp myapp started ****************************
starting server on port 7001 ...
```

Now point your browser to http://localhost:7001/myapp/helloworld and greet the brave new world!

Congratulations, you have successfully written your first Luaw webapp!