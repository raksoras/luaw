#ifndef LUAW_TIMER_H

#define LUAW_TIMER_H

#define LUA_USER_TIMER_META_TABLE "_luaw_user_timer_MT_"

typedef enum {
	INIT = 0,
	TICKING,
	ELAPSED
}
timer_state;

typedef struct luaw_timer_s luaw_timer_t;

struct luaw_timer_s {
    uv_timer_t handle;              /* timer handler */
    timer_state state;              /* timer state */
    int lua_tid;                    /* id of a lua thread waiting on this timer */

    /* memory management */
    int ref_count;                  /* reference count */
    luaw_timer_t** lua_ref;         /* back reference to Lua's full userdata pointing to this conn */
};


#define TO_TIMER(h) (luaw_timer_t*)h->data

#define GET_TIMER_OR_RETURN(h)  \
    (luaw_timer_t*)h->data;     \
    if(!h->data) return

#define LUA_GET_TIMER_OR_RETURN(L, i, t)                                    \
    luaw_timer_t** tr = luaL_checkudata(L, i, LUA_USER_TIMER_META_TABLE);   \
    if (tr == NULL) return 0;                                               \
    luaw_timer_t* t = *tr;                                                  \
    if (t == NULL) return 0;

#define LUA_GET_TIMER_OR_ERROR(L, i, t)                                     \
    luaw_timer_t** tr = luaL_checkudata(L, i, LUA_USER_TIMER_META_TABLE);   \
    if (tr == NULL) return error_to_lua(L, "Timer missing");                \
    luaw_timer_t* t = *tr;                                                  \
    if (t == NULL) return error_to_lua(L, "Timer closed");


extern void luaw_init_timer_lib(lua_State *L);

#endif