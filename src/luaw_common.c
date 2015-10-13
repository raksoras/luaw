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
#include <unistd.h>

#include <lua.h>
#include <lauxlib.h>

#include "uv.h"
#include "luaw_common.h"
#include "luaw_logging.h"
#include "luaw_buffer.h"
#include "luaw_tcp.h"
#include "luaw_http_parser.h"
#include "luaw_timer.h"
#include "lua_lpack.h"

/* globals */
lua_State* l_global = NULL;  //main global Lua state that spawns all other coroutines
int start_req_thread_fn_ref = -1; //Start new request thread function
int resume_thread_fn_ref = -1;    //Resume thread lua function


void resume_lua_thread(lua_State* L, int nargs, int nresults, int errHandler) {
    int rc = lua_pcall(L, nargs, nresults, errHandler);
    if (rc != 0) {
        fprintf(stderr, "******** Error resuming Lua thread: %s (%d) *********\n", lua_tostring(L, -1), rc);
    }
}

/* sets up error code and error message on the Lua stack to be returned by the original C
   function called from Lua. */
int error_to_lua(lua_State* L, const char* fmt, ...) {
    lua_settop(L, 0); //remove success status and params table from stack
    lua_pushboolean(L, 0);  //set status to false in case of error
    va_list argp;
    va_start(argp, fmt);
    lua_pushvfstring(L, fmt, argp);
    va_end(argp);
    return 2; //two values status and err_mesg pushed onto stack.
}

int raise_lua_error (lua_State *L, const char *fmt, ...) {
    va_list argp;
    va_start(argp, fmt);
    lua_pushvfstring(L, fmt, argp);
    va_end(argp);
    return lua_error(L);
}

void close_if_active(uv_handle_t* handle, uv_close_cb close_cb) {
    if ((handle != NULL)&&(!uv_is_closing(handle))) {
        uv_close(handle, close_cb);
    }
}

/* Minimal LuaJIT compatibility layer adopted from https://github.com/keplerproject/lua-compat-5.2 */
#if !defined(LUA_VERSION_NUM) || LUA_VERSION_NUM == 501

void luaL_setfuncs (lua_State *L, const luaL_Reg *l, int nup) {
  luaL_checkstack(L, nup+1, "too many upvalues");
  for (; l->name != NULL; l++) {  /* fill the table with given functions */
    int i;
    lua_pushstring(L, l->name);
    for (i = 0; i < nup; i++)  /* copy upvalues to the top */
      lua_pushvalue(L, -(nup + 1));
    lua_pushcclosure(L, l->func, nup);  /* closure with those upvalues */
    lua_settable(L, -(nup + 3)); /* table must be below the upvalues, the name and the closure */
  }
  lua_pop(L, nup);  /* remove upvalues */
}

void luaL_setmetatable (lua_State *L, const char *tname) {
  luaL_checkstack(L, 1, "not enough stack slots");
  luaL_getmetatable(L, tname);
  lua_setmetatable(L, -2);
}

#endif

void make_metatable(lua_State *L, const char* mt_name, const luaL_Reg* mt_funcs) {
	luaL_newmetatable(L, mt_name);
	luaL_setfuncs(L, mt_funcs, 0);
	/* client metatable.__index = client metatable */
	lua_pushstring(L, "__index");
	lua_pushvalue(L,-2);
	lua_rawset(L, -3);
}

LUA_LIB_METHOD void luaw_init_libs (lua_State *L) {
    luaw_init_logging_lib(L);
    luaw_init_tcp_lib(L);
    luaw_init_http_lib(L);
    luaw_init_timer_lib(L);
    luaw_init_lpack_lib(L);
}

/*********************************************************************
* This file contains parts of Lua 5.2's source code:
*
* Copyright (C) 1994-2013 Lua.org, PUC-Rio.
*
* Permission is hereby granted, free of charge, to any person obtaining
* a copy of this software and associated documentation files (the
* "Software"), to deal in the Software without restriction, including
* without limitation the rights to use, copy, modify, merge, publish,
* distribute, sublicense, and/or sell copies of the Software, and to
* permit persons to whom the Software is furnished to do so, subject to
* the following conditions:
*
* The above copyright notice and this permission notice shall be
* included in all copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*********************************************************************/
