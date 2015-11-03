local function append(buffer, str)
    if (str) then
        table.insert(buffer, str)
        table.insert(buffer, ", ")
    end
end


webapp:registerResource {
  method = 'POST',
  path = 'filesupload',

	handler = function(httpConn)
	    if (httpConn:isMultipartRequest()) then
            local token, fieldName, fileName, contentType
            local buffer = {}
            for token, fieldName, fileName, contentType in httpConn:multiPartIterator() do
                append(buffer, tostring(token))
                append(buffer, fieldName)
                append(buffer, fileName)
                append(buffer, contentType)
                table.insert(buffer,"\n")
            end
            httpConn:appendBody(table.concat(buffer))
	    else
            httpConn:appendBody("Not a multi-part file upload")
        end
	end
}
