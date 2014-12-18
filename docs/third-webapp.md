#7. Your third webapp - with Luaw template view

In this chapter we will put together all the pieces we have learned about so far - resource handler reading REST path parameters + Luaw template view - to build a toy but nevertheless complete MVC solution with Luaw.

##Luaw template view
Create a new directory `views` under `luaw_root_dir/webapps/myapp` and add a file named "view-address.lua" to the `views` directory, containing following piece of Luaw template view code from the last chapter:

```lua
BEGIN 'html'
    BEGIN 'head'
        BEGIN 'title'
            TEXT 'Address'
        END 'title'
    END 'head'
    BEGIN 'body'
        BEGIN 'div' {class='address'}
            BEGIN 'h1'
                TEXT(model.title)
            END 'h1'
            BEGIN 'table' {border="1", margin="1px"}
                BEGIN 'tr'
                    BEGIN 'td' {style="padding: 3px 3px 3px 3px"}
                        TEXT 'City'
                    END 'td'
                    BEGIN 'td' {style="padding: 3px 3px 3px 3px"}
                        TEXT(model.city)
                    END 'td'
                END 'tr'
                if (model.zip == 94086) then
                    BEGIN 'tr'
                        BEGIN 'td' {style="padding: 3px 3px 3px 3px"}
                            TEXT 'County'
                        END 'td'
                        BEGIN 'td' {style="padding: 3px 3px 3px 3px"}
                            TEXT 'Santa Clara'
                        END 'td'
                    END 'tr'
                end
                BEGIN 'tr'
                    BEGIN 'td' {style="padding: 3px 3px 3px 3px"}
                        TEXT 'Zip'
                    END 'td'
                    BEGIN 'td' {style="padding: 3px 3px 3px 3px"}
                        TEXT(model.zip)
                    END 'td'
                END 'tr'
            END 'table'
        END 'div'
    END 'body'
END 'html'
```

##REST resource handler
Add a file `handler-address.lua` to `luaw_root_dir/webapps/myapp/handlers` containing following code:
```lua
    GET 'address/:city/#zip' {
        function(req, resp, pathParams)
            address = {
                city = pathParams.city,
                zip = pathParams.zip
            }
            return '/views/view-address.lua', address
        end
    }
```

This resource handler handles GET request made to URL path "address/_city_/_zip_" with two path parameters - "city" defined as string parameter (denoted by preceding ':') and "zip" defined as numeric (denoted by preceding '#')

Most interesting line in the handler above is the following return statement from the function handler:

		return '/views/view-address.lua', address

So far we have been returning a single string from resource handler function (return "Hello World", for example) which Luaw took as a whole response body. This is a second, alternative form. In this form we return two values from the handler function - Lua as a language allows returning multiple values from a function which is very handy - a string and any other value. Whenever this form is used Luaw automatically interpretes first string returned as a relative path to a Luaw template view and the second value to be a "model" that is to be passed to the "view" defined by the Luaw template view. The Luaw template view path is always relative to the application root (`luaw_root_dir/webapps/myapp` in case of our example here) and always starts with a "/". The second value returned - the "model" - can be of any type - number, string, boolean or a Lua table. Our example resource handler above reads values for city and zip code from its REST path parameters and puts them in a single Lua table which it then returns as a model. Our Luaw template view in the step 1 above - view-address.lua - gets access to this model passed from the resource handler using variable `model`

##Modified web.lua
Modify *<luaw_root_dir>*/webapps/myapp/web.lua to include the "viewPattern" element that defines a view pattern so Luaw can load any Luaw template view definitions found under "myapp" directory

    luaw_webapp = {
        resourcePattern = "handler%-.*%.lua",
        viewPattern = "view%-.*%.lua",
    }

##Test your work
Finally, restart your luaw server by running

    cd luaw_root_dir
    ./bin/luaw_server ./conf/server.cfg

You should see console output similar to this:

```
********************* Starting webapp myapp ****************************
  .Loading resource ./webapps/myapp/handlers/handler-address.lua
  .Loading resource ./webapps/myapp/handlers/handler-hellouser.lua
  .Loading resource ./webapps/myapp/handlers/handler-helloworld.lua
  #Loaded total 3 resources

  .Loading view /views/view-address.lua
  #Compiled total 1 views
 *********** ********* Webapp myapp started ****************************
```

Note the "loading view" part.

Now point your browser to http://127.0.0.1:7001/myapp/address/Sunnyvale/94085 and see the output in your browser.

To verify that the Lua conditional logic embedded in view-address.lua is working properly, point your browser to http://127.0.0.1:7001/myapp/address/Sunnyvale/94086 and see the output. It should include one additional row for the county now.
