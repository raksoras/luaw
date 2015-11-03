#!./bin/luaw

local tcp_lib = require("luaw_tcp")
local webContainer = require("luaw_webcontainer")

local myApp = webContainer.loadWebApp("./webapps")
tcp_lib.listen("0.0.0.0", 7002, myApp.httpHandler())

dofile('proxy_handler.lua')
tcp_lib.listen("0.0.0.0", 7001, proxy)
