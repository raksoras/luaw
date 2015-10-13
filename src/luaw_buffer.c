#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include <lua.h>
#include <lauxlib.h>

#include "uv.h"
#include "luaw_common.h"
#include "luaw_buffer.h"

LUA_LIB_METHOD int new_buffer(lua_State* l_thread) {
    int buff_cap = lua_tointeger(l_thread, 1);
    if (buff_cap <= 0) {
        return raise_lua_error(l_thread, "Invalid buffer size");
    }
        
    char* b = (char*) calloc(1, buff_cap);
    if (b == NULL) {
        return raise_lua_error(l_thread, "Could not allocate memory for buffer");
    }

    buff_t* buff = lua_newuserdata(l_thread, sizeof(buff_t));
    if (buff == NULL) {
        free(b);
        return raise_lua_error(l_thread, "Could not allocate memory for buffer Lua reference");
    }

    buff->cap = buff_cap;
    buff->end = 0;
    buff->pos = 0;
    buff->buffer = b;
    luaL_setmetatable(l_thread, LUA_BUFFER_META_TABLE);
    return 1;
}

LUA_OBJ_METHOD int free_buffer(lua_State* l_thread) {
    buff_t* buff = luaL_checkudata(l_thread, 1, LUA_BUFFER_META_TABLE);
    if ((buff != NULL)&&(buff->buffer != NULL)) {
        free(buff->buffer);
        buff->buffer = NULL;
    }
    return 0;
}

LUA_OBJ_METHOD int buffer_capacity(lua_State *l_thread) {
    LUA_GET_BUFF_OR_ERROR(l_thread, 1, buff);
    lua_pushinteger(l_thread, buff->cap);
    return 1;
}

LUA_OBJ_METHOD int buffer_position(lua_State *l_thread) {
    LUA_GET_BUFF_OR_ERROR(l_thread, 1, buff);
    lua_pushinteger(l_thread, buff->pos);
    return 1;
}

LUA_OBJ_METHOD int buffer_length(lua_State *l_thread) {
    LUA_GET_BUFF_OR_ERROR(l_thread, 1, buff);
    lua_pushinteger(l_thread, buff->end);
    return 1;
}

LUA_OBJ_METHOD int buffer_tostring(lua_State *l_thread) {
    LUA_GET_BUFF_OR_ERROR(l_thread, 1, buff);

    int argc = lua_gettop(l_thread);
    int start = (argc > 1) ? lua_tointeger(l_thread, 2) : 0;
    int end   = (argc > 2) ? lua_tointeger(l_thread, 3) : buff->end;
    char* buffer = buff->buffer;
    
    if ((buffer == NULL)||(start >= end)||(end > buff->cap)) {
      lua_pushnil(l_thread);
    } else {
      lua_pushlstring(l_thread, (buffer+start), (end-start));
    }
    return 1;
}

LUA_OBJ_METHOD int buffer_clear(lua_State *l_thread) {
    LUA_GET_BUFF_OR_ERROR(l_thread, 1, buff);
    buff->end = 0;
    buff->pos = 0;
    return 0;
}

LUA_OBJ_METHOD int buffer_reset(lua_State *l_thread) {
    LUA_GET_BUFF_OR_ERROR(l_thread, 1, buff);
    lua_pushlstring(l_thread, buff->buffer, buff->end);
    buff->end = 0;  
    buff->pos = 0;
    return 1;
}

int remaining_content_len(buff_t* buff) {
    if (buff != NULL) {
        int len = buff->end - buff->pos;
        if (len > 0) {
            return len;
        }
    }
    return 0;
}

LUA_OBJ_METHOD int buffer_remaining_content_len(lua_State *l_thread) {
    LUA_GET_BUFF_OR_ERROR(l_thread, 1, buff);
    int len = remaining_content_len(buff);
    lua_pushinteger(l_thread, len);
    return 1;
}

LUA_OBJ_METHOD int buffer_remaining_content(lua_State *l_thread) {
    LUA_GET_BUFF_OR_ERROR(l_thread, 1, buff);
    int len = remaining_content_len(buff);
    char* start = buffer_read_start_pos(buff);
    lua_pushlstring(l_thread, start, len);
    return 1;
}

int remaining_capacity(buff_t* buff) {
    if (buff != NULL) {
        int cap_remain = buff->cap - buff->end;
        if (cap_remain > 0) {
            return cap_remain;
        }
    }
    return 0;
}

LUA_OBJ_METHOD int buffer_remaining_capacity(lua_State *l_thread) {
    LUA_GET_BUFF_OR_ERROR(l_thread, 1, buff);
    int reamining_cap = remaining_capacity(buff);
    lua_pushinteger(l_thread, reamining_cap);
    return 1;
}

char* buffer_read_start_pos(buff_t* buff) {
    if (buff != NULL) {
        int pos = buff->pos;
        if ((pos < buff->end)&&(pos < buff->cap)) {
            return buff->buffer + pos;
        }
    }
    return NULL;
}

char* buffer_fill_start_pos(buff_t* buff) {
    if (buff != NULL) {
        if (buff->end < buff->cap) {
            return buff->buffer + buff->end;
        }
    }
    return NULL;
}

/*
* status = buff:append(str)
*/
LUA_OBJ_METHOD int append(lua_State *l_thread) {
    LUA_GET_BUFF_OR_ERROR(l_thread, 1, buff);
    
    size_t len;
    const char* str = lua_tolstring(l_thread, 2, &len);
    if (len <= 0) {
        lua_pushboolean(l_thread, 1);
        return 1;
    }

    int remaining_cap = remaining_capacity(buff);
    if (len <= remaining_cap) {
        char* dest = buffer_fill_start_pos(buff);
        if (dest != NULL) {
            memcpy(dest, str, len);
            buff->end += len;
            lua_pushboolean(l_thread, 1);
            return 1;
        }
    }
    
    lua_pushboolean(l_thread, 0);
    return 1;
}

LUA_OBJ_METHOD int resize(lua_State *l_thread) {
    LUA_GET_BUFF_OR_ERROR(l_thread, 1, buff);
    
    int newsize = lua_tointeger(l_thread, 2);
    if (newsize <= 0) {
        return raise_lua_error(l_thread, "Invalid new size");
    }
    
    buff->buffer = realloc(buff->buffer, newsize);
    if (buff->buffer == NULL) {
        return raise_lua_error(l_thread, "Could not resize write buffer");
    }
    
    buff->cap = newsize;
    return 0;
}

