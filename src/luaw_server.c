#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <errno.h>
#include <unistd.h>

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#include "uv.h"
#include "luaw_common.h"
#include "luaw_tcp.h"
#include "luaw_server.h"

static char* server_ip = "0.0.0.0";
static int server_port = 80;
int buff_size = 2048;

static uv_tcp_t server;
static uv_loop_t* event_loop;

lua_State* l_global = NULL;  //main global Lua state that spawns all other coroutines

static int service_http_fn_ref;
static int start_thread_fn_ref;
int resume_thread_fn_ref;
static int run_ready_threads_fn_ref;

#define LUA_LOAD_FILE_BUFF_SIZE 1024

typedef struct {
    FILE *file;                             /* file being read */
    char buff[LUA_LOAD_FILE_BUFF_SIZE];     /* area for reading file */
    int luaw_init_appended;                  /* is last line for luaw_init appended */
} lua_load_buffer_t;


static const char* lua_file_reader(lua_State* L, void* data, size_t* size) {
    lua_load_buffer_t *lb = (lua_load_buffer_t*)data;

    if (lb->luaw_init_appended) return NULL;

    if (feof(lb->file)) {
        const char* init_str = "\ninit = require(\"luaw_init\")\n";
        strcpy(lb->buff, init_str);
        *size = strlen(lb->buff);
        lb->luaw_init_appended = 1;
        return lb->buff;
    }

    *size = fread(lb->buff, 1, sizeof(lb->buff), lb->file);  /* read block */
    return lb->buff;
}


void init_luaw_server(lua_State* L) {
    lua_getglobal(L, "request_handler");
    if (lua_isfunction(L, -1)) {
        service_http_fn_ref = luaL_ref(L, LUA_REGISTRYINDEX);
    } else {
        fprintf(stderr, "Main HTTP request handler function (request_handler) not set\n");
        exit(EXIT_FAILURE);
    }

    lua_getglobal(L, "scheduler");
    if (lua_istable(L, -1)) {
        lua_getfield(L, -1, "resumeThreadId");
        if (lua_isfunction(L, -1)) {
            resume_thread_fn_ref = luaL_ref(L, LUA_REGISTRYINDEX);
        } else {
            fprintf(stderr, "resumeThreadId function not found in luaw scheduler\n");
            exit(EXIT_FAILURE);
        }

        lua_getfield(L, -1, "startSystemThread");
        if (lua_isfunction(L, -1)) {
            start_thread_fn_ref = luaL_ref(L, LUA_REGISTRYINDEX);
        } else {
            fprintf(stderr, "startSystemThread function not found in luaw scheduler\n");
            exit(EXIT_FAILURE);
        }

        lua_getfield(L, -1, "runReadyThreads");
        if (lua_isfunction(L, -1)) {
            run_ready_threads_fn_ref = luaL_ref(L, LUA_REGISTRYINDEX);
        } else {
            fprintf(stderr, "runReadyThreads function not found in luaw scheduler\n");
            exit(EXIT_FAILURE);
        }
    } else {
        fprintf(stderr, "luaw scheduler not initialized\n");
        exit(EXIT_FAILURE);
    }

    lua_getglobal(L, "server_config");
    if (lua_istable(L, -1)) {
        lua_getfield(L, -1, "server_ip");
        if (lua_isstring(L, -1)) {
            server_ip = (char *)lua_tostring(L, -1);
            lua_pop(L, 1);
        }

        lua_getfield(L, -1, "server_port");
        if (lua_isnumber(L, -1)) {
            server_port = lua_tointeger(L, -1);
            lua_pop(L, 1);
        }

        lua_getfield(L, -1, "connection_buffer_size");
        if (lua_isnumber(L, -1)) {
            buff_size = lua_tointeger(L, -1);
            lua_pop(L, 1);
        }

        lua_pop(L, 1);
    }

    event_loop = uv_default_loop();
}

/* create a new lua coroutine to service this conn, anchor it in "all active coroutines"
*  global table to prevent it from being garbage collected and start the coroutine
*/
LIBUV_CALLBACK static void on_server_connect(uv_stream_t* server, int status) {
    if (status) {
        raise_lua_error(l_global, "500 Error in on_server_connect callback: %s\n", uv_strerror(status));
        return;
    }

    lua_rawgeti(l_global, LUA_REGISTRYINDEX, start_thread_fn_ref);
    assert(lua_isfunction(l_global, -1));

    lua_rawgeti(l_global, LUA_REGISTRYINDEX, service_http_fn_ref);
    assert(lua_isfunction(l_global, -1));

    connection_t * conn = new_connection(l_global);

    status = uv_tcp_init(server->loop, conn->handle);
    if (status) {
        close_connection(conn, status, false, false);
        fprintf(stderr, "Could not initialize memory for a new connection\n");
        return;
    }

    status = uv_accept(server, (uv_stream_t*) conn->handle);
    if (status) {
        close_connection(conn, status, false, false);
        fprintf(stderr, "500 Error accepting incoming conn: %s\n", uv_strerror(status));
        return;
    }

    status = lua_pcall(l_global, 2, 2, 0);
    if (status) {
        fprintf(stderr, "******** Error starting new client connect thread: %s (%d) *********\n", lua_tostring(l_global, -1), status);
    }
}

void start_server(lua_State *L) {
    fprintf(stderr, "starting server...\n");

    struct sockaddr_in addr;
    int err_code = uv_ip4_addr(server_ip, server_port, &addr);
    if (err_code) {
        fprintf(stderr, "Error initializing socket address: %s\n", uv_strerror(err_code));
        exit(EXIT_FAILURE);
    }

    uv_tcp_init(event_loop, &server);

    err_code = uv_tcp_bind(&server, (const struct sockaddr*) &addr, 0);
    if (err_code) {
        fprintf(stderr, "Error binding to port %d : %s\n", server_port, uv_strerror(err_code));
        exit(EXIT_FAILURE);
    }

    err_code = uv_listen((uv_stream_t*)&server, 128, on_server_connect);
    if (err_code) {
        fprintf(stderr, "Error listening on port %d : %s\n", server_port, uv_strerror(err_code));
        exit(EXIT_FAILURE);
    }
}

static int event_loop_once() {
    int status = uv_run(event_loop, UV_RUN_ONCE);
    return status;
}

static int event_loop_no_block() {
    int status = uv_run(event_loop, UV_RUN_NOWAIT);
    return status;
}

static int server_loop(lua_State *L) {
    int status = 0;
    while (true) {
        lua_settop(L, 0);

        status = event_loop_once();
        if (status == 0) {
            fprintf(stderr,"Error while running event loop: %s\n", uv_strerror(status));
            exit(EXIT_FAILURE);
        }

        /* do the bottom half processing, run ready threads that are waiting */
        lua_rawgeti(L, LUA_REGISTRYINDEX, run_ready_threads_fn_ref);
        status = lua_pcall(L, 0, 1, 0);
        if (status != LUA_OK) {
            fprintf(stderr,"Error while running ready threads for bottom half processing: %s\n", lua_tostring(L, -1));
            exit(EXIT_FAILURE);
        }
    }
    return status;
}

static void stop_server(lua_State *L) {
    fprintf(stderr, "stopping server...\n");
    uv_stop(event_loop);
    lua_close(L);
}


int main (int argc, char* argv[]) {
	if (argc < 2) {
		fprintf(stderr, "Usage: %s <luaw config file >\n", argv[0]);
		exit(EXIT_FAILURE);
	}

    l_global = luaL_newstate();
	if (!l_global) {
		fprintf(stderr, "Could not create new Lua state\n");
		exit(EXIT_FAILURE);
	}

	luaL_checkversion(l_global);
    lua_gc(l_global, LUA_GCSTOP, 0);  /* stop collector during initialization */
    luaL_openlibs(l_global);  /* open libraries */
    luaw_open_lib(l_global);
    lua_gc(l_global, LUA_GCRESTART, 0);

    lua_load_buffer_t lb;
    lb.luaw_init_appended = 0;
    lb.file = fopen(argv[1], "r");
    if (lb.file == NULL) {
        fprintf(stderr, "Could not open configuration file %s for reading\n", argv[1]);
        exit(EXIT_FAILURE);
    }

    int status = lua_load(l_global, lua_file_reader, &lb, argv[1], "t");
    if (status != LUA_OK) {
        fprintf(stderr, "Error while loading file: %s\n", argv[1]);
        fprintf(stderr, "%s\n", lua_tostring(l_global, -1));
        exit(EXIT_FAILURE);
    }

    status = lua_pcall(l_global, 0, 0, 0);
    if (status != LUA_OK) {
        fprintf(stderr, "Error while executing file: %s\n", argv[1]);
        fprintf(stderr, "%s\n", lua_tostring(l_global, -1));
        exit(EXIT_FAILURE);
    }

    init_luaw_server(l_global);
    start_server(l_global);
    server_loop(l_global);
    stop_server(l_global);
}