#ifndef LUAW_COMMON_H

#define LUAW_COMMON_H

typedef enum {
	false = 0,
	true
}
bool;

typedef enum {
    LOG_NOT_OPEN = 0,
    OPENING_LOG,
    LOG_IS_OPEN,
} logfile_sate;

/* marker macros for documenting code */
#define LIBUV_CALLBACK
#define LIBUV_API
#define LUA_OBJ_METHOD
#define LUA_LIB_METHOD
#define HTTP_PARSER_CALLBACK

#define step  fprintf(stderr, "At line# %d function(%s) in file %s\n", __LINE__, __FUNCTION__, __FILE__);
#define debug_i(s) fprintf(stderr, #s "= %d at line# %d function(%s) in file %s\n", s, __LINE__, __FUNCTION__, __FILE__);
#define debug_l(s) fprintf(stderr, #s "= %ld at line# %d function(%s) in file %s\n", s, __LINE__, __FUNCTION__, __FILE__);
#define debug_s(s) fprintf(stderr, #s "= %s at line# %d function(%s) in file %s\n", s, __LINE__, __FUNCTION__, __FILE__);
#define debug_p(s) fprintf(stderr, #s "= %p at line# %d function(%s) in file %s\n", s, __LINE__, __FUNCTION__, __FILE__);

/* global state */
extern lua_State* l_global;
extern lua_State* l_global ;
extern int buff_size;
extern int resume_thread_fn_ref;

extern int error_to_lua(lua_State* L, const char* fmt, ...);
extern int raise_lua_error (lua_State *L, const char *fmt, ...);
extern void make_metatable(lua_State *L, const char* mt_name, const luaL_Reg* mt_funcs);
extern int luaw_open_lib (lua_State *L);
extern void close_if_active(uv_handle_t* handle, uv_close_cb close_cb);
extern void resume_lua_thread(lua_State* L, int nargs, int nresults, int errHandler);

#endif