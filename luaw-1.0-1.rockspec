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
		lib_luaw = {
			sources = {"src/luaw_tcp.c", "src/luaw_http_parser.c", "src/http_parser.c", "src/luaw_common.c", "src/lua_lpack.c"},
			libraries = {"uv"},
			incdirs = {"$(LIBUV_INCDIR)"},
			libdirs = {"$(LIBUV_LIBDIR)"}
		}
	}
}
