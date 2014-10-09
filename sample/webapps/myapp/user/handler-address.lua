action:GET 'address/#block/:street/:city/:state/#zip' {
	function(req, resp, pathParams)
	    address = {
	        block = pathParams.block,
	        street = pathParams.street,
	        city = pathParams.city,
	        state = pathParams.state,
	        zip = pathParams.zip
	    }
	    return '/user/address-view.lua', address
	end
}