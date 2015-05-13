registerHandler {
    method = 'GET',
    path = 'address/:city/#zip',

    handler = function(req, resp, pathParams)
        address = {
            city = pathParams.city,
            zip = pathParams.zip
        }
        return '/views/view-address.lua', address
    end
}
