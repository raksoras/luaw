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

#define Q(x) #x
#define QUOTE(x) Q(x)

#define INCR_REF_COUNT(s) if (s != NULL) s->ref_count++;

#define DECR_REF_COUNT(s) if (s != NULL) s->ref_count--;

#define GC_REF(s)                           \
    if (s != NULL) {                        \
        s->ref_count--;                     \
        if (s->ref_count <= 0) {debug_i(s->ref_count); free(s);}     \
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
extern int luaw_open_lib (lua_State *L);
extern void close_if_active(uv_handle_t* handle, uv_close_cb close_cb);
extern void resume_lua_thread(lua_State* L, int nargs, int nresults, int errHandler);
extern void close_syslog();

#endif
