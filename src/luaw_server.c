/*
* Copyright (c) 2015 raksoras
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in all
* copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
* SOFTWARE.
*/

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
#include "luaw_logging.h"
#include "luaw_buffer.h"
#include "luaw_tcp.h"
#include "lfs.h"

static uv_loop_t* event_loop;
static uv_signal_t shutdown_signal;
static int run_ready_threads_fn_ref = -1;

static void handle_shutdown_req(uv_signal_t* handle, int signum) {
    if (signum == SIGHUP) {
        fprintf(stderr, "shutdown request received\n");
        uv_signal_stop(handle);
        uv_stop(event_loop);
    }
}

int register_function(lua_State* L, const char* fn_name) {
    lua_getfield(L, -1, fn_name);
    if (!lua_isfunction(L, -1)) {
        fprintf(stderr, "%s function not found in luaw scheduler\n", fn_name);
        exit(EXIT_FAILURE);
    }
    return luaL_ref(L, LUA_REGISTRYINDEX);
}

void init_luaw_server(lua_State* L) {
    lua_getglobal(L, "luaw_scheduler");
    if (!lua_istable(L, -1)) {
        fprintf(stderr, "Luaw scheduler not initialized\n");
        exit(EXIT_FAILURE);
    }

    resume_thread_fn_ref = register_function(L, "resumeThreadId");
    start_req_thread_fn_ref = register_function(L, "startRequestThread");
    run_ready_threads_fn_ref = register_function(L, "runReadyThreads");
    lua_pop(L, 1);
    
    event_loop = uv_default_loop();
    uv_signal_init(event_loop, &shutdown_signal);
    uv_signal_start(&shutdown_signal, handle_shutdown_req, SIGHUP);    
}

static void run_user_threads() {
    /* do the bottom half processing, run ready user threads that are waiting */
    lua_rawgeti(l_global, LUA_REGISTRYINDEX, run_ready_threads_fn_ref);
    int status = lua_pcall(l_global, 0, 1, 0);
    if (status != LUA_OK) {
        fprintf(stderr,"Error running user threads for bottom half processing: %s\n", lua_tostring(l_global, -1));
        uv_stop(event_loop);
    }
    lua_settop(l_global, 0);
}

static void close_walk_cb(uv_handle_t* handle, void* arg) {
	if (!uv_is_closing(handle)) {
		uv_close(handle, NULL);
	}
}

static int server_loop(lua_State *L) {
    int status = 1;
    while (status) {
        status = uv_run(event_loop, UV_RUN_ONCE);
        run_user_threads();
    }
    
    /* clean up resources used by the event loop and Lua */
    uv_walk(event_loop, close_walk_cb, NULL);
    uv_run(event_loop, UV_RUN_ONCE);
    uv_loop_delete(event_loop);
    close_listeners();
    lua_close(L);
	close_syslog();

    return status;
}

static void run_lua_file(const char* filename) {
    int status = luaL_dofile(l_global, filename);
    if (status != LUA_OK) {
        fprintf(stderr, "Error while running script: %s\n", filename);
        fprintf(stderr, "%s\n", lua_tostring(l_global, -1));
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
		fprintf(stderr, "Usage: %s <luaw config scripts>\n", argv[0]);
		exit(EXIT_FAILURE);
	}

    l_global = luaL_newstate();
	if (!l_global) {
		fprintf(stderr, "Could not create new Lua state\n");
		exit(EXIT_FAILURE);
	}

    lua_gc(l_global, LUA_GCSTOP, 0);  /* stop collector during initialization */
    luaL_openlibs(l_global);  /* open libraries */
    luaw_init_libs(l_global);
    luaopen_lfs(l_global);
    lua_gc(l_global, LUA_GCRESTART, 0);
    set_lua_path(l_global);
    
    /* run lua on startup scripts passed on the command line */
    for (int i = 1; i < argc; i++) {
        fprintf(stderr, "## Running %s \n", argv[i]);
        run_lua_file(argv[i]);
    }

    init_luaw_server(l_global);
    int status = start_listeners();
    if (status) {
        fprintf(stderr, "Error while starting listeners: %s\n", uv_strerror(status));
        exit(status);
    }
    
    status = server_loop(l_global);
    exit(status);
}
