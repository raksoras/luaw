GET 'address/:city/#zip' {
    function(req, resp, pathParams)
        address = {
            city = pathParams.city,
            zip = pathParams.zip
        }
        return '/views/view-address.lua', address
    end
}
