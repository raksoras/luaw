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
    bool mark_closed;              
    int ref_count;                  
};


#define TO_TIMER(h) (luaw_timer_t*)h->data

#define GET_TIMER_OR_RETURN(h)  \
    (luaw_timer_t*)h->data;     \
    if(!h->data) return

#define LUA_GET_TIMER_OR_RETURN(L, i, t)        \
    luaw_timer_t* t = lua_touserdata(L, i);     \
    if (t == NULL) return 0;

#define LUA_GET_CONN_OR_ERROR(L, i, c)                              \
    connection_t* c = lua_touserdata(L, i);                         \
    if (c == NULL) return error_to_lua(L, "Connection missing");    \


#define LUA_GET_TIMER_OR_ERROR(L, i, t)                         \
    luaw_timer_t* t = lua_touserdata(L, i);                     \
    if (t == NULL) return error_to_lua(L, "Timer missing");


extern void luaw_init_timer_lib(lua_State *L);

#endif