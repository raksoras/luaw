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
    
    buff_t* buff = (buff_t*)calloc(1, (sizeof(buff_t) + buff_cap));
    if (buff == NULL) {
        return raise_lua_error(l_thread, "Could not allocate memory for buffer");
    }
    buff->cap = buff_cap;

    buff_t** lua_ref = lua_newuserdata(l_thread, sizeof(buff_t*));
    if (lua_ref == NULL) {
        free(buff);
        return raise_lua_error(l_thread, "Could not allocate memory for buffer Lua reference");
    }

    *lua_ref = buff;
    luaL_setmetatable(l_thread, LUA_BUFFER_META_TABLE);
    return 1;
}

LUA_OBJ_METHOD int free_buffer(lua_State* l_thread) {
    buff_t** lua_ref = luaL_checkudata(l_thread, 1, LUA_BUFFER_META_TABLE);
    if (lua_ref != NULL) {
        buff_t* buff = *lua_ref;
        if (buff != NULL) {
            free(buff);
            *lua_ref = NULL;
        }
    }
    return 0;
}

LUA_OBJ_METHOD int buffer_capacity(lua_State *l_thread) {
    LUA_GET_BUFF_OR_ERROR(l_thread, 1, buff);
    lua_pushinteger(l_thread, buff->cap);
    return 1;
}

LUA_OBJ_METHOD int buffer_length(lua_State *l_thread) {
    LUA_GET_BUFF_OR_ERROR(l_thread, 1, buff);
    lua_pushinteger(l_thread, buff->end);
    return 1;
}

LUA_OBJ_METHOD int buffer_tostring(lua_State *l_thread) {
    LUA_GET_BUFF_OR_ERROR(l_thread, 1, buff);
    lua_pushlstring(l_thread, buff->buffer, buff->end);
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


int buffer_remaining_capacity(buff_t* buff) {
    if (buff != NULL) {
        int cap_remain = buff->cap - buff->end;
        if (cap_remain > 0) {
            return cap_remain;
        }
    }
    return 0;
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
