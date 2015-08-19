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

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <errno.h>
#include <unistd.h>

#include <lua.h>
#include <lauxlib.h>

#include "uv.h"
#include "luaw_common.h"
#include "luaw_timer.h"


static void clear_user_timer(luaw_timer_t* timer) {
    timer->state = INIT;
    timer->lua_tid = 0;
}

static luaw_timer_t* new_user_timer() {
    luaw_timer_t* timer = (luaw_timer_t*)calloc(1, sizeof(luaw_timer_t));
    if (timer == NULL) {
        return NULL;
    }

    /* To account for reference from Lua to this timer, decreased in close_timer_lua() */
    INCR_REF_COUNT(timer)

    /* init libuv artifacts */
    uv_timer_init(uv_default_loop(), &timer->handle);
    timer->handle.data = timer;
    INCR_REF_COUNT(timer)
    clear_user_timer(timer);

    return timer;
}

LUA_LIB_METHOD static int new_timer_lua(lua_State* L) {
    luaw_timer_t* timer = new_user_timer();
    if (timer == NULL) {
        return raise_lua_error(L, "Could not allocate memory for user timer");
    }
    lua_pushlightuserdata(L, timer);
    return 1;
}


static void free_user_timer(uv_handle_t* handle) {
    luaw_timer_t* timer = GET_TIMER_OR_RETURN(handle);
    handle->data = NULL;
    GC_REF(timer)
}

static void close_timer(luaw_timer_t* timer) {
    if ((timer == NULL)||(timer->mark_closed)) return;
    timer->mark_closed = true;

    /* unblock waiting thread */
    if (timer->lua_tid) {
        lua_rawgeti(l_global, LUA_REGISTRYINDEX, resume_thread_fn_ref);
        lua_pushinteger(l_global, timer->lua_tid);
        lua_pushboolean(l_global, 0);                           //status
        lua_pushstring(l_global, uv_strerror(UV_ECANCELED));    //error message
        timer->lua_tid = 0;
        resume_lua_thread(l_global, 3, 2, 0);
    }

    close_if_active((uv_handle_t*)&timer->handle, free_user_timer);
}

LUA_LIB_METHOD static int close_timer_lua(lua_State* l_thread) {
    LUA_GET_TIMER_OR_RETURN(l_thread, 1, timer);
    GC_REF(timer)    //decrement Lua's reference
    close_timer(timer);
    return 0;
}


/* lua call spec: status, timer_elapsed = timer:wait(tid)
Success, timer elapsed:  status = true, timer_elapsed = true
Success, timer not elapsed:  status = true, timer_elapsed = false
Failure:  status = false, error message
*/
LIBUV_CALLBACK static void on_user_timer_timeout(uv_timer_t* handle) {
    luaw_timer_t* timer = GET_TIMER_OR_RETURN(handle);
    if(timer->lua_tid) {
        lua_rawgeti(l_global, LUA_REGISTRYINDEX, resume_thread_fn_ref);
        lua_pushinteger(l_global, timer->lua_tid);
        clear_user_timer(timer);
        lua_pushboolean(l_global, 1);   //status
        lua_pushboolean(l_global, 1);    //elapsed
        resume_lua_thread(l_global, 3, 2, 0);
    } else {
        timer->state = ELAPSED;
    }
}

/* lua call spec:
Success:  status(true), nil = start(timer, timeout)
Failure:  status(false), error message = start(timer, timeout)
*/
LUA_LIB_METHOD static int start_user_timer(lua_State* l_thread) {
    LUA_GET_TIMER_OR_ERROR(l_thread, 1, timer);
    if (timer->mark_closed) {
        return raise_lua_error(l_thread, "start() called on an already closed timer.");
    }

    if (timer->state != INIT) {
        /* Timer is already started by another lua thread */
        return error_to_lua(l_thread, "Timer already in use by another thread");
    }

    int timeout = lua_tointeger(l_thread, 2);
    if (timeout <= 0) {
        return error_to_lua(l_thread, "Invalid timeout value %d specified", timeout);
    }

    int rc = uv_timer_start(&timer->handle, on_user_timer_timeout, timeout, 0);
    if (rc) {
        close_timer(timer);
        return error_to_lua(l_thread, "Error starting timer: %s", uv_strerror(rc));
    }

    timer->state = TICKING;
    lua_pushboolean(l_thread, 1);
    return 1;
}


/* lua call spec: status, timer_elapsed = wait(timer, tid)
Success, timer elapsed:  status = true, timer_elapsed = true
Success, timer not elapsed:  status = true, timer_elapsed = false
Failure:  status = false, error message
*/
LUA_LIB_METHOD static int wait_user_timer(lua_State* l_thread) {
    LUA_GET_TIMER_OR_ERROR(l_thread, 1, timer);
    if (timer->mark_closed) {
        return raise_lua_error(l_thread, "wait() called on an already closed timer.");
    }

    if (timer->state == ELAPSED) {
        clear_user_timer(timer);
        lua_pushboolean(l_thread, 1);   //status
        lua_pushboolean(l_thread, 1);   //elasped
    } else {
        if (timer->state != TICKING) {
            return error_to_lua(l_thread, "Attempt to wait on timer that is not started, timer state: %d", timer->state);
        }
        if (timer->lua_tid) {
            return error_to_lua(l_thread, "Timer already is in use by thread %d", timer->lua_tid);
        }
        int tid = lua_tointeger(l_thread, 2);
        if (tid <= 0) {
            return error_to_lua(l_thread, "Invalid thread id %d specified", tid);
        }
        timer->lua_tid = tid;
        lua_pushboolean(l_thread, 1);
        lua_pushboolean(l_thread, 0);
    }
    return 2;
}

/* lua call spec: timer:stop() */
LUA_LIB_METHOD static int stop_user_timer(lua_State* l_thread) {
    LUA_GET_TIMER_OR_ERROR(l_thread, 1, timer);
    if (timer->state == TICKING) {
        if (timer->lua_tid) {
            lua_rawgeti(l_thread, LUA_REGISTRYINDEX, resume_thread_fn_ref);
            lua_pushinteger(l_thread, timer->lua_tid);
            lua_pushboolean(l_thread, 0);                           //status
            lua_pushstring(l_thread, uv_strerror(UV_ECANCELED));    //error message
            resume_lua_thread(l_thread, 3, 2, 0);
        }
        clear_user_timer(timer);
        uv_timer_stop(&timer->handle);
    }
    return 0;
}


static const struct luaL_Reg luaw_timer_lib[] = {
	{"newTimer", new_timer_lua},
	{"start", start_user_timer},
	{"stop", stop_user_timer},
	{"wait", wait_user_timer},
	{"delete", close_timer_lua},
    {NULL, NULL}  /* sentinel */
};


void luaw_init_timer_lib (lua_State *L) {
    luaL_newlib(L, luaw_timer_lib);
    lua_setglobal(L, "luaw_timer_lib");
}
