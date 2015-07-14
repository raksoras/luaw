#ifndef LUAW_BUFFER_H

#define LUAW_BUFFER_H

#define LUA_BUFFER_META_TABLE "_luaw_buff_MT_"

typedef struct buff_s buff_t;

struct buff_s {
    int cap;            /* buffer capacity */
    int end;            /* end of content available in buffer */
    int pos;            /* position upto which content is consumed from buffer */
    char* buffer;       /* buffer */
};

#define LUA_GET_BUFF_OR_ERROR(L, i, b)                                      \
    buff_t** br = luaL_checkudata(L, i, LUA_BUFFER_META_TABLE);             \
    if (br == NULL) return raise_lua_error(L, "Missing Buffer");            \
    buff_t* b = *br;                                                        \
    if (b == NULL) return raise_lua_error(L, "Missing buffer");


extern int new_buffer(lua_State* l_thread);
extern int free_buffer(lua_State* l_thread);
extern int buffer_capacity(lua_State *l_thread);
extern int buffer_length(lua_State *l_thread);
extern int buffer_tostring(lua_State *l_thread);
extern int buffer_clear(lua_State *l_thread);
extern int buffer_reset(lua_State *l_thread);
extern int remaining_content_len(buff_t* buff);
extern int buffer_remaining_content(lua_State *l_thread);
extern int buffer_remaining_content_len(lua_State *l_thread);
extern int buffer_remaining_capacity(buff_t* buff);
extern char* buffer_read_start_pos(buff_t* buff);
extern char* buffer_fill_start_pos(buff_t* buff);
extern int append(lua_State *l_thread);
extern int resize(lua_State *l_thread);

#endif
