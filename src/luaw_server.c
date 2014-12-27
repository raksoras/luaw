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
#include "lfs.h"

static char* server_ip = "0.0.0.0";
static int server_port = 80;
static uv_tcp_t server;
static uv_loop_t* event_loop;
static uv_signal_t shutdown_signal;
static int is_live = 1;

static int service_http_fn_ref;
static int start_thread_fn_ref;
static int run_ready_threads_fn_ref;

#define LUA_LOAD_FILE_BUFF_SIZE 1024

typedef struct {
    FILE *file;                             /* file being read */
    char buff[LUA_LOAD_FILE_BUFF_SIZE];     /* area for reading file */
    char* epilogue;
} lua_load_buffer_t;


static const char* lua_file_reader(lua_State* L, void* data, size_t* size) {
    lua_load_buffer_t *lb = (lua_load_buffer_t*)data;

    if (lb->file == NULL) return NULL;

    if (feof(lb->file)) {
        fclose(lb->file);
        lb->file = NULL;
        *size = (lb->epilogue != NULL) ? strlen(lb->epilogue) : 0;
        return lb->epilogue;
    }

    *size = fread(lb->buff, 1, sizeof(lb->buff), lb->file);  /* read block */
    return lb->buff;
}

static void handle_shutdown_req(uv_signal_t* handle, int signum) {
    if (signum == SIGHUP) {
        fprintf(stderr, "shutdown request received\n");
        is_live = 0;
        uv_signal_stop(handle);
    }
}


void init_luaw_server(lua_State* L) {
    lua_getglobal(L, "Luaw");
    if (!lua_istable(L, -1)) {
        fprintf(stderr, "Luaw library not initialized\n");
        exit(EXIT_FAILURE);
    }

    lua_getfield(L, -1, "request_handler");
    if (!lua_isfunction(L, -1)) {
        fprintf(stderr, "Main HTTP request handler function (Luaw.request_handler) not set\n");
        exit(EXIT_FAILURE);
    }
    service_http_fn_ref = luaL_ref(L, LUA_REGISTRYINDEX);

    lua_getfield(L, -1, "scheduler");
    if (!lua_istable(L, -1)) {
        fprintf(stderr, "luaw scheduler not initialized\n");
        exit(EXIT_FAILURE);
    }

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

    lua_getglobal(L, "luaw_server_config");
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
    status = uv_accept(server, (uv_stream_t*) conn->handle);
    if (status) {
        close_connection(conn, status);
        fprintf(stderr, "500 Error accepting incoming conn: %s\n", uv_strerror(status));
        return;
    }

    status = lua_pcall(l_global, 2, 2, 0);
    if (status) {
        fprintf(stderr, "******** Error starting new client connect thread: %s (%d) *********\n", lua_tostring(l_global, -1), status);
    }
}

void start_server(lua_State *L) {
    fprintf(stderr, "starting server on port %d ...\n", server_port);

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

    uv_signal_init(event_loop, &shutdown_signal);
    uv_signal_start(&shutdown_signal, handle_shutdown_req, SIGHUP);
}

static int event_loop_once() {
    int status = uv_run(event_loop, UV_RUN_ONCE);
    return status;
}

static int server_loop(lua_State *L) {
    int status = 0;
    while (is_live) {
        lua_settop(L, 0);

        status = event_loop_once();
        if (status == 0) {
            fprintf(stderr,"Error while running event loop: %s\n", uv_strerror(status));
            return EXIT_FAILURE;
        }

        /* do the bottom half processing, run ready threads that are waiting */
        lua_rawgeti(L, LUA_REGISTRYINDEX, run_ready_threads_fn_ref);
        status = lua_pcall(L, 0, 1, 0);
        if (status != LUA_OK) {
            fprintf(stderr,"Error while running ready threads for bottom half processing: %s\n", lua_tostring(L, -1));
            return EXIT_FAILURE;
        }
    }
    return EXIT_SUCCESS;
}

static void close_walk_cb(uv_handle_t* handle, void* arg) {
	if (!uv_is_closing(handle)) {
		uv_close(handle, NULL);
	}
}

static void close_loop(uv_loop_t* loop) {
	uv_walk(loop, close_walk_cb, NULL);
	uv_run(loop, UV_RUN_DEFAULT);
}

static void stop_server(lua_State *L) {
    fprintf(stderr, "stopping server...\n");
    uv_close((uv_handle_t *)&server, NULL);
	close_loop(event_loop);
    uv_stop(event_loop);
    uv_loop_delete(event_loop); 
    lua_close(L);
	close_syslog();
}

static void run_lua_file(const char* filename, char* epilogue) {
    lua_load_buffer_t lb;

    lb.file = fopen(filename, "r");
    if (lb.file == NULL) {
        fprintf(stderr, "Could not open file %s for reading\n", filename);
        exit(EXIT_FAILURE);
    }
    lb.epilogue = epilogue;

    int status = lua_load(l_global, lua_file_reader, &lb, filename, "t");
    if (status != LUA_OK) {
        fprintf(stderr, "Error while loading file: %s\n", filename);
        fprintf(stderr, "%s\n", lua_tostring(l_global, -1));
        exit(EXIT_FAILURE);
    }

    status = lua_pcall(l_global, 0, 0, 0);
    if (status != LUA_OK) {
        fprintf(stderr, "Error while executing file: %s\n", filename);
        fprintf(stderr, "%s\n", lua_tostring(l_global, -1));
        fprintf(stderr, "\n\t* Try running luaw_server from directory that contains \"bin\" directory containing the binary \"luaw_server\"\n");
        fprintf(stderr, "\t* For example: ./bin/luaw_server <server_config_file>\n\n");
        exit(EXIT_FAILURE);
    }
}

static void set_lua_path(lua_State* L) {
    lua_getglobal( L, "package" );
    lua_pushliteral(L, "?;?.lua;./bin/?;./bin/?.lua;./lib/?;./lib/?.lua");
    lua_setfield( L, -2, "path" );
    lua_pop(L, 1);
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
    luaopen_lfs(l_global);
    lua_gc(l_global, LUA_GCRESTART, 0);

    /* load config file, mandatory */
    set_lua_path(l_global);
    run_lua_file(argv[1], "\ninit = require(\"luaw_init\")\n");

    /* run other lua on startup script passed on the command line, if any */
    int i = 2;
    for (; i < argc; i++) {
        fprintf(stderr, "## Running %s \n", argv[i]);
        run_lua_file(argv[i], NULL);
    }

    init_luaw_server(l_global);
    start_server(l_global);
    int status = server_loop(l_global);
    stop_server(l_global);

    exit(status);
}