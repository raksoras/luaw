gcc -v -o server -L/usr/local/lib -luv -llua src/luaw_tcp.o src/luaw_server.o src/luaw_http_parser.o src/http_parser.o src/luaw_common.o src/lua_lpack.o src/luaw_timer.o

