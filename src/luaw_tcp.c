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

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
//#include <assert.h>

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <errno.h>
#include <unistd.h>

#include <lua.h>
#include <lauxlib.h>

#include "uv.h"
#include "luaw_common.h"
#include "luaw_buffer.h"
//#include "http_parser.h"
//#include "luaw_http_parser.h"
#include "luaw_tcp.h"
//#include "lfs.h"



connection_t* new_connection(lua_State* L) {
    connection_t* conn = (connection_t*)calloc(1, sizeof(connection_t));
    if (conn == NULL) {
        raise_lua_error(L, "Could not allocate memory for client connection");
        return NULL;
    }

    connection_t** lua_ref = lua_newuserdata(L, sizeof(connection_t*));
    if (lua_ref == NULL) {
        free(conn);
        raise_lua_error(L, "Could not allocate memory for client connection Lua reference");
        return NULL;
    }

    /* link C side connection reference and Lua's full userdata that represents it to each other */
    luaL_setmetatable(L, LUA_CONNECTION_META_TABLE);
    *lua_ref = conn;
    INCR_REF_COUNT(conn)
    conn->lua_ref = lua_ref;

    /* init libuv artifacts */
    uv_tcp_init(uv_default_loop(), &conn->handle);
    conn->handle.data = conn;
    INCR_REF_COUNT(conn)

    uv_timer_init(uv_default_loop(), &conn->read_timer);
    conn->read_timer.data = conn;
    INCR_REF_COUNT(conn)
    conn->lua_reader_tid = 0;

    uv_timer_init(uv_default_loop(), &conn->write_timer);
    conn->write_timer.data = conn;
	INCR_REF_COUNT(conn)
    conn->lua_writer_tid = 0;

    return conn;
}

LUA_LIB_METHOD static int new_connection_lua(lua_State* L) {
    new_connection(L);
    return 1;
}

static void free_timer(uv_handle_t* handle) {
    connection_t* conn = GET_CONN_OR_RETURN(handle);
    handle->data = NULL;
    GC_REF(conn)
}

static void free_tcp_handle(uv_handle_t* handle) {
    connection_t* conn = GET_CONN_OR_RETURN(handle);
    handle->data = NULL;
    GC_REF(conn)
}

void close_connection(connection_t* conn, const int status) {
    /* conn->lua_ref == NULL also acts as a flag to mark that this conn has been closed */
    if ((conn == NULL)||(conn->lua_ref == NULL)) return;

    *(conn->lua_ref) = NULL;  //delink from Lua's userdata
    conn->lua_ref = NULL;
    DECR_REF_COUNT(conn);

    uv_timer_stop(&conn->read_timer);
    close_if_active((uv_handle_t*)&conn->read_timer, (uv_close_cb)free_timer);

    uv_timer_stop(&conn->write_timer);
    close_if_active((uv_handle_t*)&conn->write_timer, (uv_close_cb)free_timer);

    close_if_active((uv_handle_t*)&conn->handle, (uv_close_cb)free_tcp_handle);

    /* unblock reader thread */
    if (conn->lua_reader_tid) {
        lua_rawgeti(l_global, LUA_REGISTRYINDEX, resume_thread_fn_ref);
        lua_pushinteger(l_global, conn->lua_reader_tid);
        if ((status == 0)||(status == UV_EOF)) {
            lua_pushboolean(l_global, 0);
            lua_pushliteral(l_global, "EOF");
        } else {
            /* error */
            lua_pushboolean(l_global, 0);
            lua_pushstring(l_global, uv_strerror(status));
        }

        conn->lua_reader_tid = 0;
        resume_lua_thread(l_global, 3, 2, 0);
    }

    /* unblock writer thread */
    if (conn->lua_writer_tid) {
        lua_rawgeti(l_global, LUA_REGISTRYINDEX, resume_thread_fn_ref);
        lua_pushinteger(l_global, conn->lua_writer_tid);
        if ((status == 0)||(status == UV_EOF)) {
            lua_pushboolean(l_global, 1);
            lua_pushinteger(l_global, 0);
        } else {
            /* error */
            lua_pushboolean(l_global, 0);
            lua_pushstring(l_global, uv_strerror(status));
        }

        conn->lua_writer_tid = 0;
        resume_lua_thread(l_global, 3, 2, 0);
    }
}

LIBUV_CALLBACK static void on_conn_timeout(uv_timer_t* timer) {
    /* Either connect,read or write timed out, close the connection */
    connection_t* conn = GET_CONN_OR_RETURN(timer);
    close_connection(conn, UV_ECANCELED);
}

static int start_timer(uv_timer_t* timer, int timeout) {
    if ((timeout > 0)&&(!uv_is_active((uv_handle_t*) timer))) {
        return uv_timer_start(timer, on_conn_timeout, timeout, 0);
    }
    return 0;
}

static void stop_timer(uv_timer_t* timer) {
    if (uv_is_active((uv_handle_t*) timer)) {
        uv_timer_stop(timer);
    }
}

LUA_OBJ_METHOD static int close_connection_lua(lua_State* l_thread) {
    LUA_GET_CONN_OR_RETURN(l_thread, 1, conn);

    /* being called from lua, no reason to resume thread */
    conn->lua_reader_tid = 0;
    conn->lua_writer_tid = 0;
    close_connection(conn, UV_EOF);
    return 0;
}

LUA_OBJ_METHOD static int connection_gc(lua_State *L) {
    LUA_GET_CONN_OR_RETURN(L, 1, conn);

    /* if we reached here, there is a connection that has not been closed */
    fprintf(stderr, "Luaw closed unclosed connection\n");

    /* being called from lua, no reason to resume thread */
    conn->lua_reader_tid = 0;
    conn->lua_writer_tid = 0;
    close_connection(conn, UV_ECANCELED);
    return 0;
}

LIBUV_CALLBACK static void on_alloc(uv_handle_t* handle, size_t suggested_size, uv_buf_t* buf) {
    buf->base = NULL;
    buf->len = 0;
    connection_t* conn = GET_CONN_OR_RETURN(handle);
    
    size_t free_space = buffer_remaining_capacity(conn->read_buffer);
    if (free_space > 0) {
        buf->base = buffer_fill_start_pos(conn->read_buffer);
        buf->len = free_space;
    }
}

/*
* Returns,
* Success: status=true, length of content available to read (could be zero)
* Failure: status=false, error message
*/
LIBUV_API static void on_read(uv_stream_t* stream, ssize_t nread, const uv_buf_t* buf) {
    connection_t* conn = GET_CONN_OR_RETURN(stream);
    stop_timer(&conn->read_timer); //clear read timeout if any
    
    if (nread == UV_ENOBUFS) {
        /* No buffer was available to read the data. Let this callback pass through as NOOP */
        return;
    }

    if (nread < 0) {
        /* either EOF or read error, in either case close connection */
        close_connection(conn, nread);
    }
    
    buff_t* read_buffer = conn->read_buffer;
    if ((nread > 0)&&(read_buffer != NULL)&&(conn->lua_reader_tid != 0)) {
        /* new additional data available for read */
        int read_len = read_buffer->end + nread;
        if (read_len > read_buffer->cap) {
            /* should never happen, on_alloc returns read buffer within limit */
            close_connection(conn, UV_EAI_OVERFLOW);
        }
        read_buffer->end = read_len;

        /* wake up read coroutine */
        lua_rawgeti(l_global, LUA_REGISTRYINDEX, resume_thread_fn_ref);
        lua_pushinteger(l_global, conn->lua_reader_tid);
        lua_pushboolean(l_global, 1);
        lua_pushinteger(l_global, read_len);
        conn->lua_reader_tid = 0;
        conn->read_buffer = NULL;
        resume_lua_thread(l_global, 3, 2, 0);
    }
}

/* Returns,
* Success:  status(true), nil = conn:start_reading()
* Failure:  status(false), error message = conn:start_reading()
*/
LUA_OBJ_METHOD static int start_reading(lua_State *l_thread) {
    LUA_GET_CONN_OR_ERROR(l_thread, 1, conn);

    conn->lua_reader_tid = 0;
    int err_code = uv_read_start((uv_stream_t*)&conn->handle, on_alloc, on_read);
    if (err_code) {
        lua_pushboolean(l_thread, 0);
        lua_pushstring(l_thread,  uv_strerror(err_code));
        close_connection(conn, err_code);
        return 2;
    }

    lua_pushboolean(l_thread, 1);
    return 1;
}

LUA_OBJ_METHOD static int read_check(lua_State* l_thread) {
    LUA_GET_CONN_OR_ERROR(l_thread, 1, conn);
    if (!uv_is_active((uv_handle_t*)&conn->handle)) {
        close_connection(conn, UV_EAI_BADFLAGS);
        return error_to_lua(l_thread, "read() called on conn that is not registered to receive read events");
    }

    LUA_GET_BUFF_OR_ERROR(l_thread, 2, read_buffer);    
    if (read_buffer->end >= read_buffer->cap) {
        close_connection(conn, UV_EAI_OVERFLOW);
        return error_to_lua(l_thread, "buffer passed to read() is already full");
    }
    
    int lua_reader_tid = lua_tointeger(l_thread, 3);
    if (lua_reader_tid == 0) {
        close_connection(conn, UV_EINVAL);
        return error_to_lua(l_thread, "Invalid coroutine id");
    }

    int readTimeout = lua_tointeger(l_thread, 4);
    conn->read_buffer = read_buffer;
    conn->lua_reader_tid = lua_reader_tid;
    start_timer(&conn->read_timer, readTimeout);
    
    lua_pushboolean(l_thread, 1);
    lua_pushinteger(l_thread, read_buffer->end);
    return 2;
}

LIBUV_API static void on_write(uv_write_t* req, int status) {
    connection_t* conn = TO_CONN(req);
    if(conn) {
        req->data = NULL;
        if (status) {
            close_connection(conn, status);
        } else {
            stop_timer(&conn->write_timer); //clear write timeout if any
            lua_rawgeti(l_global, LUA_REGISTRYINDEX, resume_thread_fn_ref);
            lua_pushinteger(l_global, conn->lua_writer_tid);
            conn->lua_writer_tid = 0;
            lua_pushboolean(l_global, 1);
            lua_pushinteger(l_global, 1);
            resume_lua_thread(l_global, 3, 2, 0);
        }
        /* Unlike libuv handles, libuv requests do not support uv_close(). Therefore we increment
        reference count every time request starts and decrement it as soon as it completes */
        GC_REF(conn)
    }
}

/* lua call spec: conn:write(tid, str, writeTimeout)
Success: status(true), nwritten
Failure: status(false), error message
*/
LUA_OBJ_METHOD static int write_buffer(lua_State* l_thread) {
    LUA_GET_CONN_OR_ERROR(l_thread, 1, conn);

    int lua_writer_tid = lua_tointeger(l_thread, 2);
    if (lua_writer_tid == 0) {
        return error_to_lua(l_thread, "write() specified invalid thread id");
    }

    size_t len = 0;
    const char* buff = lua_tolstring(l_thread, 3, &len);

    if (len > 0) {
        /* non empty write buffer. Send write request, record writer tid and block in lua */
        int writeTimeout = lua_tointeger(l_thread, 4);

        uv_buf_t write_buff;
        write_buff.base = (char*) buff;
        write_buff.len = len;

        int err_code = uv_write(&conn->write_req, (uv_stream_t*)&conn->handle, &write_buff, 1, on_write);
        if (err_code) {
            close_connection(conn, err_code);
            lua_pushboolean(l_thread, 0);
            lua_pushstring(l_thread,  uv_strerror(err_code));
            return 2;
        }

        conn->write_req.data = conn;
        INCR_REF_COUNT(conn)
        conn->lua_writer_tid = lua_writer_tid;
        start_timer(&conn->write_timer, writeTimeout);
    }

    lua_pushboolean(l_thread, 1);
    lua_pushinteger(l_thread, len);
    return 2;
}

LIBUV_CALLBACK static void on_client_connect(uv_connect_t* connect_req, int status) {
    connection_t* conn = GET_CONN_OR_RETURN(connect_req);

    stop_timer(&conn->write_timer); //clear connect timeout if any
    free(connect_req);

    lua_rawgeti(l_global, LUA_REGISTRYINDEX, resume_thread_fn_ref);
    lua_pushinteger(l_global, conn->lua_writer_tid);

    if (status) {
        close_connection(conn, status);
        lua_pushboolean(l_global, 0);
        lua_pushstring(l_global, uv_strerror(status));
    } else {
        lua_pushboolean(l_global, 1); //status to be returned
        lua_pushnil(l_global);
    }

    resume_lua_thread(l_global, 3, 2, 0);
}

/* lua call spec: luaw_lib.connect(ip4_addr, port, tid, connectTimeout)
Success: conn
Failure: false, error message
*/
LUA_LIB_METHOD static int client_connect(lua_State* l_thread) {
    const char* ip4 = luaL_checkstring(l_thread, 1);

    int port = lua_tointeger(l_thread, 2);
    if (port == 0) {
        return error_to_lua(l_thread, "Invalid port specified in client_connect");
    }

    int tid = lua_tointeger(l_thread, 3);
    if (tid == 0) {
        return error_to_lua(l_thread, "Invalid thread id specified in client_connect");
    }

    int connectTimeout = lua_tointeger(l_thread, 4);

    struct sockaddr_in addr;
    if(uv_ip4_addr(ip4, port, &addr)) {
        return error_to_lua(l_thread, "Invalid ip address %s and port %d combination specified in client_connect", ip4, port);
    }

    connection_t* conn = new_connection(l_thread);

    uv_connect_t* connect_req = (uv_connect_t*)malloc(sizeof(uv_connect_t));
    if (connect_req == NULL) {
        close_connection(conn, UV_ENOMEM);
        return error_to_lua(l_thread, "Could not allocate memory for connect request");
    }
    connect_req->data = conn;

    int status = uv_tcp_connect(connect_req, &conn->handle, (const struct sockaddr*) &addr, on_client_connect);
    if (status) {
        free(connect_req);
        close_connection(conn, status);
        return error_to_lua(l_thread, "tcp connect failed: %s", uv_strerror(status));
    }

    conn->lua_writer_tid = tid;
    start_timer(&conn->write_timer, connectTimeout);
    return 1;
}

LIBUV_CALLBACK static void on_resolved(uv_getaddrinfo_t *resolver, int status, struct addrinfo *res) {
    int lua_tid = *((int *)resolver->data);
    free(resolver->data);
    free(resolver);

    char ip_str[17] = {'\0'};
    if ((status == 0)&&(res != NULL)) {
        struct sockaddr_in addr = *(struct sockaddr_in*) res->ai_addr;
        status = uv_ip4_name(&addr, (char*)ip_str, sizeof(ip_str));
        uv_freeaddrinfo(res);
    }

    lua_rawgeti(l_global, LUA_REGISTRYINDEX, resume_thread_fn_ref);
    lua_pushinteger(l_global, lua_tid);

    if ((status)||(res == NULL)) {
        lua_pushboolean(l_global, 0);
        lua_pushfstring(l_global, "DNS resolution failed: %s", uv_strerror(status));
    } else {
        lua_pushboolean(l_global, 1);       //status to be returned
        lua_pushstring(l_global, ip_str);   //IP address string
    }
    resume_lua_thread(l_global, 3, 2, 0);
}

LUA_LIB_METHOD static int dns_resolve(lua_State* l_thread) {
    const char* hostname = luaL_checkstring(l_thread, 1);

    int lua_tid = lua_tointeger(l_thread, 2);
    if (lua_tid == 0) {
        return error_to_lua(l_thread, "Invalid thread id specified in dns_resolve");
    }

    struct addrinfo hints;
    hints.ai_family = PF_INET;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_protocol = IPPROTO_TCP;
    hints.ai_flags = 0;

    uv_getaddrinfo_t* resolver = (uv_getaddrinfo_t*)malloc(sizeof(uv_getaddrinfo_t));
    if (resolver == NULL) {
        return error_to_lua(l_thread, "Could not allocate memory for DNS resolver");
    }

    int* tid = (int*)malloc(sizeof(int));
    if (tid == NULL) {
        free(resolver);
        return error_to_lua(l_thread, "Could not allocate memory thread id");
    }
    *tid = lua_tid;
    resolver->data = tid;

    int status = uv_getaddrinfo(uv_default_loop(), resolver, on_resolved, hostname,  NULL, &hints);
    if (status) {
        free(resolver);
        free(tid);
        return error_to_lua(l_thread, "DNS resolve failed: %s", uv_strerror(status));
    }

    //success
    lua_pushboolean(l_thread, 1);
    return 1;
}


static const struct luaL_Reg luaw_connection_methods[] = {
    {"startReading", start_reading},    
    {"read", read_check},
    {"write", write_buffer},
    {"close", close_connection_lua},
    {"__gc", connection_gc},
    {NULL, NULL}  /* sentinel */
};

static const struct luaL_Reg luaw_buffer_methods[] = {
    {"free", free_buffer},    
    {"capacity", buffer_capacity},
    {"length", buffer_length},
    {"remainingLength", buffer_remaining_content_len},
    {"tostring", buffer_tostring},
    {"clear", buffer_clear},
    {"reset", buffer_reset},
    {"__gc", free_buffer},
    {NULL, NULL}  /* sentinel */
};

static const struct luaL_Reg luaw_tcp_lib[] = {
    {"newConnection", new_connection_lua},
    {"newBuffer", new_buffer},
    {"connect", client_connect},
    {"resolveDNS", dns_resolve},
    {NULL, NULL}  /* sentinel */
};


void luaw_init_tcp_lib (lua_State *L) {
    make_metatable(L, LUA_CONNECTION_META_TABLE, luaw_connection_methods);
    make_metatable(L, LUA_BUFFER_META_TABLE, luaw_buffer_methods);
    luaL_newlib(L, luaw_tcp_lib);
    lua_setglobal(L, "luaw_tcp_lib");
}
