#ifndef LUAW_TIMER_H

#define LUAW_TIMER_H

#define LUA_USER_TIMER_META_TABLE "_luaw_user_timer_MT_"

typedef enum {
	INIT = 0,
	TICKING,
	ELAPSED
}
timer_state;

typedef struct {
    uv_timer_t* handle;
    timer_state state;
    int lua_tid;            /* id of a lua thread waiting on this timer */
} luaw_timer_t;


#define TO_TIMER(h) (luaw_timer_t*)h->data

#define GET_TIMER_OR_RETURN(h)   \
    (luaw_timer_t*)h->data;     \
    if(!h->data) return

#define LUA_GET_TIMER(L, i) luaL_checkudata(L, i, LUA_USER_TIMER_META_TABLE)

#define LUA_GET_TIMER_OR_ERROR(L, i, t)                                 \
    luaw_timer_t* t = luaL_checkudata(L, i, LUA_USER_TIMER_META_TABLE); \
    if (!t) return error_to_lua(L, "Timer missing");                    \
    if (!t->handle) return error_to_lua(L, "Timer closed");

extern void luaw_init_timer_lib(lua_State *L);

#endif