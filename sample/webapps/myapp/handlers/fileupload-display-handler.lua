webapp:registerResource {
    method = 'GET',
    path = 'showform',

	handler = function(httpConn)
	    resp:appendBody [[
            <!DOCTYPE html>
            <html lang="en">
                <head>
                    <meta charset="utf-8"/>
                    <title>upload</title>
                </head>
                <body>
                    <form action="/myapp/filesupload" method="post" enctype="multipart/form-data">
                        <p><input type="text" name="text1" value="text default">
                        <p><input type="text" name="text2" value="ABCD">
                        <p><input type="file" name="file1">
                        <p><input type="file" name="file2">
                        <p><button type="submit">Submit</button>
                    </form>
                </body>
            </html>
        ]]
	end
}
