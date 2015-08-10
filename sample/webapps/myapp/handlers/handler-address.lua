registerHandler {
    method = 'GET',
    path = 'address/:city/#zip',

    handler = function(req, resp)
        address = {
            city = req.pathParams.city,
            zip = req.pathParams.zip
        }
        resp:renderView('/views/view-address.lua', address)
    end
}
