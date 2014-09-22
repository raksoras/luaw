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

int new_user_timer(lua_State* l_thread) {
    luaw_timer_t* timer = lua_newuserdata(l_thread, sizeof(luaw_timer_t));
    if (timer == NULL) {
        raise_lua_error(l_thread, "Could not allocate memory for user timer");
    }

    timer->handle = (uv_timer_t*)malloc(sizeof(uv_timer_t));
    if (timer->handle == NULL) {
        free(timer);
        return raise_lua_error(l_thread, "Could not allocate memory for user timer");
    }
    timer->handle->data = timer;

    clear_user_timer(timer);
    luaL_setmetatable(l_thread, LUA_USER_TIMER_META_TABLE);
    uv_timer_init(uv_default_loop(), timer->handle);

    return 1;
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
Success:  status(true), nil = timer:start(timeout)
Failure:  status(false), error message = timer:start(timeout)
*/
static int start_user_timer(lua_State* l_thread) {
    LUA_GET_TIMER_OR_ERROR(l_thread, 1, timer);

    if (timer->state != INIT) {
        /* Timer is already started by another lua thread */
        return error_to_lua(l_thread, "Timer already in use by another thread");
    }

    int timeout = lua_tointeger(l_thread, 2);
    if (timeout <= 0) {
        return error_to_lua(l_thread, "Invalid timeout value %d specified", timeout);
    }

    int rc = uv_timer_start(timer->handle, on_user_timer_timeout, timeout, 0);
    if (rc) {
        return error_to_lua(l_thread, "Error starting timer: %s", uv_strerror(rc));
    }

    timer->state = TICKING;
    lua_pushboolean(l_thread, 1);
    return 1;
}


/* lua call spec: status, timer_elapsed = timer:wait(tid)
Success, timer elapsed:  status = true, timer_elapsed = true
Success, timer not elapsed:  status = true, timer_elapsed = false
Failure:  status = false, error message
*/
int wait_user_timer(lua_State* l_thread) {
    LUA_GET_TIMER_OR_ERROR(l_thread, 1, timer);

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
static int stop_user_timer(lua_State* l_thread) {
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
        uv_timer_stop(timer->handle);
    }
    return 0;
}

void close_timer(luaw_timer_t* timer) {
    if (timer == NULL) return;

    close_if_active((uv_handle_t*)timer->handle, (uv_close_cb)free);
    timer->handle = NULL;

    /* unblock waiting thread */
    if (timer->lua_tid) {
        lua_rawgeti(l_global, LUA_REGISTRYINDEX, resume_thread_fn_ref);
        lua_pushinteger(l_global, timer->lua_tid);
        timer->lua_tid = 0;
        lua_pushboolean(l_global, 0);                           //status
        lua_pushstring(l_global, uv_strerror(UV_ECANCELED));    //error message
        resume_lua_thread(l_global, 3, 2, 0);
    }
}

LUA_OBJ_METHOD static int timer_gc(lua_State *L) {
    luaw_timer_t* timer = LUA_GET_TIMER(L, 1);
    step
    close_timer(timer);
    step
    return 0;
}

static const struct luaL_Reg luaw_user_timer_methods[] = {
	{"start", start_user_timer},
	{"stop", stop_user_timer},
	{"wait", wait_user_timer},
	{"__gc", timer_gc},
	{NULL, NULL}  /* sentinel */
};


void luaw_init_timer_lib (lua_State *L) {
	make_metatable(L, LUA_USER_TIMER_META_TABLE, luaw_user_timer_methods);
}
