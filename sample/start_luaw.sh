#!./bin/luaw

--[[
luaw_server_config = {
    connect_timeout = 4000,
    read_timeout = 8000,
    write_timeout = 8000
}

luaw_log_config = {
    syslog_server = "127.0.0.1",
    syslog_port = 514,
}
]]

luaw_webapp_config = {
    base_dir = "./webapps"
}

local tcp_lib = require("luaw_tcp")
local webapp = require("luaw_webapp")
webapp.init()


dofile('proxy_handler.lua')
tcp_lib.listen("0.0.0.0", 7001, proxy)

-- test proxy_handler.lua
--[[
loadWebapp is a separate function that returns webApp object with webApp:route() method
 local myapp = webApp.load {
  root = "./webapps",
  resourcePattern = "handler%-.*%.lua",
  viewPattern = "view%-.*%.lua",
 }
 ]]
-- test ALL handlers

