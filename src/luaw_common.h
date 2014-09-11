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

extern int luaw_fn_place_holder(lua_State *L);
extern int error_to_lua(lua_State* L, const char* fmt, ...);
extern int raise_lua_error (lua_State *L, const char *fmt, ...);
extern void make_metatable(lua_State *L, const char* mt_name, const luaL_Reg* mt_funcs);

#endif