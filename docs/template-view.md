#6. Luaw Template Views

Luaw comes equipped with a Luaw template views for generating server-side dynamic content. Luaw template views serve the same need as served by solutions like JSP, ASP and PHP.

In reality, a Luaw template view is a normal, plain Lua code with little bit of syntactical sugar added for generating HTML/XHTML/XML markup. This allows developer to use full power of Lua - including if-then-else conditional checks, for/while loops, local variables and functions etc. - within the template view while still using concise, readable notation for generating markup in output. Of course this power can be abused by writing complex logic - which should belong to a well defined, separate business logic tier - inside a template view but we trust that you will do no such thing :) Remember with great power comes great responsibility!

Without further ado, here is a sample Luaw template view file - view-address.lua:
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

Each Luaw template view has access to following implicitly defined variables: `req`, `resp`,
`pathParams` and `model` passed from resource handler that invoked the view

It also defines three syntax sugar extentions to generate markeup `BEGIN`, `TEXT` and `END`.

1. You use `BEGIN tag_name` to open any HTML or XML tag of type tag_name
2. If the tag has any attributes you follow the `BEGIN tag_name`  with set of attributes defined like this `{name1=value1, name2=value2 ...}`
3. You close opne tag with `END tag_name`
4. If you want to emit any content in the body of the response you are generating you can use `TEXT()` to do so. `TEXT()` can take multiple, variable number of arguments of different types. It will include them in the output response in the same order by calling tostring() on each of the arguments. Consequtive arguments are separated by a single space in the response. As a special case if you want to emit a literal string ('Hello world!' for example) you can do so without using parenthesis like this: `TEXT 'Hello world!'`. There is nothing special about this syntax. Lua as a language offers this convenient notation for calling any Lua function with a single, literal string argument.

That's it! You can mix your normal Lua code - if/else, loops etc. - along with the markup to be  genertated easily. Take a look at the check for zipcode in the sample code above to see an example of this.

In the next chapter we will see how to use Luaw template views with resource handlers.

**_NOTE:_**

You can write resusable templates to generate markup that is common across many pages - web site header and footer, for example - by writing Lua functions that generate this common markup and then simply invoking these where you want to include the markup. This is very similar to JSP tag libraries or other server side include technologies. The only tricky part is making syntax sugar extentions like `BEGIN`, `TEXT` and `END` available to normal Lua functions outside Lua template views. This is actually very easy. Behind the scene these three extentions are really closures bound to current request/response scope. This means you can pass them to any normal Lua functions - even functions defined in separate .lua files that themselves are not Lua template views - like this:

```lua
-- Reusable markup generating function AKA tag library
function generateHeader(model, BEGIN, TEXT, END)
	BEGIN 'div' {class='header')
    	--- generate HTML here using BEGIN, TEXT and END
    END 'div'
end
```

```lua
-- Using common markup generating function from Luaw template view
local ssi = require("common_markup.lua")

-- Just call function to include the markup at write place
ssi.generateHeader(model, BEGIN, TEXT, END)

BEGIN 'div' {class="body"}
	--- generate page specific page markup here
END 'div'

ssi.generateFooter(model, BEGIN, TEXT, END)
```