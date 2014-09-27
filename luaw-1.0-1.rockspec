package = "luaw"
version = "1.0-1"
source = {
	url = " "
}
description = {
	summary = "Lua Webserver",
	license = "MIT"
}
dependencies = {
	"lua ~> 5.2"
}
external_dependencies = {
	LIBUV = {
		header = "uv.h"
	}
}
build = {
	type = "builtin",
	modules = {
		luaw_lib = "lib/luaw_lib.lua",
		luaw_logging = "lib/luaw_logging.lua",
		luaw_data_structs_lib = "lib/luaw_data_structs_lib.lua",
		luaw_server = "lib/luaw_server.lua",
		luapack = "lib/luapack.lua",
		luaw_template_compiler = "lib/luaw_template_compiler.lua",
		luaw_template_lang = "lib/luaw_template_lang.lua",
		luaw_webapp = "lib/luaw_webapp.lua",
		luaw_server = {
			sources = {"src/luaw_tcp.c", "src/luaw_server.c", "src/luaw_http_parser.c", "src/http_parser.c", "src/luaw_timer.c", "src/luaw_common.c", "src/lua_lpack.c"},
			libraries = {"uv"},
			incdirs = {"$(LIBUV_INCDIR)"},
			libdirs = {"$(LIBUV_LIBDIR)"}
		}
	}
}
