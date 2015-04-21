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

#ifndef LUAW_COMMON_H

#define LUAW_COMMON_H

typedef enum {
	false = 0,
	true
}
bool;

/* marker macros for documenting code */
#define LIBUV_CALLBACK
#define LIBUV_API
#define LUA_OBJ_METHOD
#define LUA_LIB_METHOD
#define HTTP_PARSER_CALLBACK

#define Q(x) #x
#define QUOTE(x) Q(x)

#define INCR_REF_COUNT(s) if (s != NULL) s->ref_count++;

#define DECR_REF_COUNT(s) if (s != NULL) s->ref_count--;

#define GC_REF(s)                           \
    if (s != NULL) {                        \
        s->ref_count--;                     \
        if (s->ref_count <= 0) free(s);     \
    }


#define step  fprintf(stdout, "At line# %d function(%s) in file %s\n", __LINE__, __FUNCTION__, __FILE__);
#define debug_i(s) fprintf(stdout, #s "= %d at line# %d function(%s) in file %s\n", s, __LINE__, __FUNCTION__, __FILE__);
#define debug_l(s) fprintf(stdout, #s "= %ld at line# %d function(%s) in file %s\n", s, __LINE__, __FUNCTION__, __FILE__);
#define debug_s(s) fprintf(stdout, #s "= %s at line# %d function(%s) in file %s\n", s, __LINE__, __FUNCTION__, __FILE__);
#define debug_sl(s, l) fprintf(stdout, #s "= %.*s at line# %d function(%s) in file %s\n", l, s, __LINE__, __FUNCTION__, __FILE__);
#define debug_p(s) fprintf(stdout, #s "= %p at line# %d function(%s) in file %s\n", s, __LINE__, __FUNCTION__, __FILE__);
#define debug_break(s) fprintf(stdout, "%s\n", s);

/* global state */
extern lua_State* l_global;
extern int resume_thread_fn_ref;

extern int error_to_lua(lua_State* L, const char* fmt, ...);
extern int raise_lua_error (lua_State *L, const char *fmt, ...);
extern void make_metatable(lua_State *L, const char* mt_name, const luaL_Reg* mt_funcs);
extern void luaw_init_libs(lua_State *L);
extern void close_if_active(uv_handle_t* handle, uv_close_cb close_cb);
extern void resume_lua_thread(lua_State* L, int nargs, int nresults, int errHandler);



/* Minimal LuaJIT compatibility layer adopted from https://github.com/keplerproject/lua-compat-5.2 */

#if defined(LUA_VERSION_NUM) && LUA_VERSION_NUM == 501
/* Lua 5.1 */

/* PUC-Rio Lua uses lconfig_h as include guard for luaconf.h,
 * LuaJIT uses luaconf_h. If you use PUC-Rio's include files
 * but LuaJIT's library, you will need to define the macro
 * COMPAT52_IS_LUAJIT yourself! */
#if !defined(COMPAT52_IS_LUAJIT) && defined(luaconf_h)
#define COMPAT52_IS_LUAJIT
#endif

/* LuaJIT doesn't define these unofficial macros ... */
#if !defined(LUAI_INT32)
#include <limits.h>
#if INT_MAX-20 < 32760
#define LUAI_INT32  long
#define LUAI_UINT32 unsigned long
#elif INT_MAX > 2147483640L
#define LUAI_INT32  int
#define LUAI_UINT32 unsigned int
#else
#error "could not detect suitable lua_Unsigned datatype"
#endif
#endif

#define lua_rawlen(L, i) lua_objlen(L, i)

#endif /* Lua 5.1 */

#if !defined(LUA_VERSION_NUM) || LUA_VERSION_NUM == 501
/* Lua 5.0 *or* 5.1 */

#define LUA_OK 0

#define lua_pushglobaltable(L) \
  lua_pushvalue(L, LUA_GLOBALSINDEX)

#define luaL_newlib(L, l) \
  (lua_newtable((L)),luaL_setfuncs((L), (l), 0))

void luaL_checkversion (lua_State *L);

#endif /* Lua 5.0 *or* 5.1 */

void luaL_setfuncs (lua_State *L, const luaL_Reg *l, int nup);
void luaL_setmetatable (lua_State *L, const char *tname);


#endif
