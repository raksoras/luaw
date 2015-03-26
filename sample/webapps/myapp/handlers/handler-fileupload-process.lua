local function append(buffer, str)
    if (str) then
        table.insert(buffer, str)
        table.insert(buffer, ", ")
    end
end


registerHandler {
    method = 'POST',
    path = 'filesupload',

	handler = function(req, resp, pathParams)
	    if (req:isMultipart()) then
            local token, fieldName, fileName, contentType
            local buffer = {}
            for token, fieldName, fileName, contentType in req:multiPartIterator() do
                append(buffer, token)
                append(buffer, fieldName)
                append(buffer, fileName)
                append(buffer, contentType)
                table.insert(buffer,"\n")
            end
            return table.concat(buffer)
	    end
	    return "Not a multi-part file upload"
	end
}
