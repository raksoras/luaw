#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <errno.h>
#include <unistd.h>

#include <lua.h>
#include <lauxlib.h>

#include "uv.h"
#include "luaw_common.h"
#include "http_parser.h"
#include "luaw_http_parser.h"
#include "luaw_tcp.h"
#include "lfs.h"

void clear_read_buffer(connection_t* conn) {
    if (conn) {
        conn->read_len = 0L;
        conn->parse_len = 0L;
    }
}

static void clear_write_buffer(connection_t* conn) {
    if (conn) conn->write_len = 0;
}

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
    clear_read_buffer(conn);
    conn->lua_reader_tid = 0;

    uv_timer_init(uv_default_loop(), &conn->write_timer);
    conn->write_timer.data = conn;
	INCR_REF_COUNT(conn)
    clear_write_buffer(conn);
    conn->lua_writer_tid = 0;

    return conn;
}

LUA_LIB_METHOD int new_connection_lua(lua_State* L) {
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
            lua_pushboolean(l_global, 1);
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

LUA_OBJ_METHOD static int reset_read_buffer(lua_State* l_thread) {
    LUA_GET_CONN_OR_ERROR(l_thread, 1, conn);
    clear_read_buffer(conn);
    return 0;
}

LUA_OBJ_METHOD static int reset_write_buffer(lua_State* l_thread) {
    LUA_GET_CONN_OR_ERROR(l_thread, 1, conn);
    clear_write_buffer(conn);
    return 0;
}

LUA_OBJ_METHOD static int close_connection_lua(lua_State* l_thread) {
    LUA_GET_CONN_OR_RETURN(l_thread, 1, conn);
    close_connection(conn, UV_ECANCELED);
    return 0;
}

LUA_OBJ_METHOD static int connection_gc(lua_State *L) {
    LUA_GET_CONN_OR_RETURN(L, 1, conn);
    /* if we reached here, there is a connection that has not been closed */
    fprintf(stderr, "Luaw salvaging possible resource leak, connection not properly closed\n");
    close_connection(conn, UV_ECANCELED);
    return 0;
}

/* reuse the buffer attached with this conn to minimize memory allocation. Each on_read()
*  resets the buffer to empty after sending all the bytes read to the coroutine servicing this
*  conn. If we get called before on_read() has had chance to empty the buffer, we return
*  0 which means on_read() will be called with nread=UV_ENOBUFS next which we must handle.
*/
LIBUV_CALLBACK static void on_alloc(uv_handle_t* handle, size_t suggested_size, uv_buf_t* buf) {
    buf->base = NULL;
    buf->len = 0;

    connection_t* conn = GET_CONN_OR_RETURN(handle);
    if(conn->read_buffer) {
        size_t free_space = CONN_BUFFER_SIZE - conn->read_len;
        if (free_space > 0) {
            buf->base = conn->read_buffer + conn->read_len;
            buf->len = free_space;
        }
    }
}

LIBUV_API static void on_read(uv_stream_t* stream, ssize_t nread, const uv_buf_t* buf) {
    connection_t* conn = GET_CONN_OR_RETURN(stream);
    stop_timer(&conn->read_timer); //clear read timeout if any

    if ((nread == 0)||(nread == UV_ENOBUFS)) {
        /* either no data was read or no buffer was available to read the data. Anyway there
           is nothing to do so no need to wake conn coroutine. Let this callback pass through
           as  NOOP */
        return;
    }

    if (nread > 0) {
        /* success: send read bytes to coroutine if one is waiting */
        lua_rawgeti(l_global, LUA_REGISTRYINDEX, resume_thread_fn_ref);
        lua_pushinteger(l_global, conn->lua_reader_tid);
        conn->lua_reader_tid = 0;
        lua_pushboolean(l_global, 1);

        conn->read_len += nread;
        size_t len = PARSE_LEN(conn);
        if (len == 0) {
            lua_pushliteral(l_global, "WAIT");
        } else {
            lua_pushliteral(l_global, "OK");
        }
        resume_lua_thread(l_global, 3, 2, 0);
        return;
    }

    /* either EOF or read error, in either case close connection */
    close_connection(conn, nread);
}

/* lua call spec:
Success:  status(true), nil = conn:start_reading()
Failure:  status(false), error message = conn:start_reading()
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

/* lua call spec: status, message = conn:readInternal(tid, readTimeout)
Success, no EOF: status = true, mesg = "OK"
Success, EOF: status = true, mesg = "EOF"
Success, no data available: status = true, mesg = "WAIT"
Failure: status = false, mesg = error message
*/
LUA_OBJ_METHOD static int read_check(lua_State* l_thread) {
    LUA_GET_CONN_OR_ERROR(l_thread, 1, conn);

    if (!uv_is_active((uv_handle_t*)&conn->handle)) {
       return error_to_lua(l_thread, "read() called on conn that is not registered to receive read events");
    }

    const size_t len = PARSE_LEN(conn);
    if (len == 0) {
        /* empty buffer, record reader tid and block (yield) in lua */
        int lua_reader_tid = lua_tointeger(l_thread, 2);
        if (lua_reader_tid == 0) {
            return error_to_lua(l_thread, "read() specified invalid thread id");
        }

        conn->lua_reader_tid = lua_reader_tid;
        int readTimeout = lua_tointeger(l_thread, 3);
        start_timer(&conn->read_timer, readTimeout);

        lua_pushboolean(l_thread, 1);
        lua_pushliteral(l_thread, "WAIT");
        return 2;
    }

    /* data available in buffer */
    lua_pushboolean(l_thread, 1);
    lua_pushliteral(l_thread, "OK");
    return 2;
}

static int get_write_buffer_len(lua_State* l_thread) {
    LUA_GET_CONN_OR_ERROR(l_thread, 1, conn);
    lua_pushinteger(l_thread, conn->write_len);
    return 1;
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
            lua_pushinteger(l_global,  conn->write_len);
            clear_write_buffer(conn);
            resume_lua_thread(l_global, 3, 2, 0);
        }
        /* Unlike libuv handles, libuv requests do not support uv_close(). Therefore we increment
        reference count every time request starts and decrement it as soon as it completes */
        GC_REF(conn)
    }
}

/* lua call spec: conn:write(tid, writeTimeout, isChunked)
Success: status(true), nwritten
Failure: status(false), error message
*/
LUA_OBJ_METHOD static int write_buffer(lua_State* l_thread) {
    LUA_GET_CONN_OR_ERROR(l_thread, 1, conn);
    conn->lua_writer_tid = 0;

    if (conn->write_len > 0) {
        /* non empty write buffer. Send write request, record writer tid and block in lua */
        int lua_writer_tid = lua_tointeger(l_thread, 2);
        if (lua_writer_tid == 0) {
            return error_to_lua(l_thread, "500 write() specified invalid thread id");
        }

        int writeTimeout = lua_tointeger(l_thread, 3);
        int isChunked = lua_toboolean(l_thread, 4);
        int err_code = 0;

        if (isChunked)  {
            uv_buf_t buffs[3];
            buffs[0].base = conn->chunk_header;
            buffs[0].len = sprintf(conn->chunk_header, "%zx\r\n", conn->write_len);
            buffs[1].base = conn->write_buffer;
            buffs[1].len = conn->write_len;
            buffs[2].base = "\r\n";
            buffs[2].len = 2;
            err_code = uv_write(&conn->write_req, (uv_stream_t*)&conn->handle, buffs, 3, on_write);
        } else {
            uv_buf_t buff;
            buff.base = conn->write_buffer;
            buff.len = conn->write_len;
            err_code = uv_write(&conn->write_req, (uv_stream_t*)&conn->handle, &buff, 1, on_write);
        }

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
    lua_pushinteger(l_thread, conn->write_len);
    return 2;
}

/* Fill conn's write buffer with the input string passed. Multiple consecutive fill_buffer()
* calls append passed in strings inside conn's write buffer. If the buffer is too full to
* copy input string in its entirety, it copies whatever fraction of the input it can and
* returns the remaining part that could not be fit inside the buffer.
*
* Lua call spec:
* Success: remaining buffer capacity, part of the string that could not fit = conn:appendBuffer("...")
*          - when input fits in the buffer completely second return value is nil
* Failure: status(false), error message = conn:appendBuffer()
*/
LUA_OBJ_METHOD static int append_buffer(lua_State* l_thread) {
    LUA_GET_CONN_OR_ERROR(l_thread, 1, conn);

    size_t input_len = 0;
    const char* input = lua_tolstring(l_thread, 2, &input_len);

    size_t buff_cap = CONN_BUFFER_SIZE - conn->write_len;
    if (input == NULL) {
        lua_pushinteger(l_thread, buff_cap);
        lua_pushnil(l_thread);
        return 2;
    }

    size_t fit_len = (input_len <= buff_cap) ? input_len : buff_cap;
    size_t remaining_input_len = input_len - fit_len;

    char* dest = conn->write_buffer + conn->write_len;
    memcpy(dest, input, fit_len);
    conn->write_len += fit_len;

    lua_pushinteger(l_thread, (CONN_BUFFER_SIZE - conn->write_len));
    if (remaining_input_len > 0) {
        lua_pushlstring(l_thread, (input + fit_len), remaining_input_len);
    } else {
        lua_pushnil(l_thread);
    }
    return 2;
}

LIBUV_CALLBACK static void on_client_connect(uv_connect_t* connect_req, int status) {
    connection_t* conn = GET_CONN_OR_RETURN(connect_req);

    stop_timer(&conn->write_timer); //clear connect timeout if any
    free(connect_req);

    lua_rawgeti(l_global, LUA_REGISTRYINDEX, resume_thread_fn_ref);
    lua_pushinteger(l_global, conn->lua_writer_tid);

    if (status) {
        conn->lua_writer_tid = 0;
        close_connection(conn, status);
        lua_pushboolean(l_global, 0);
        lua_pushstring(l_global, uv_strerror(status));
    } else {
        lua_pushboolean(l_global, 1); //status to be returned
        lua_pushnil(l_global);
    }

    clear_write_buffer(conn);
    resume_lua_thread(l_global, 3, 2, 0);
}

/* lua call spec: luaw_lib.connect(ip4_addr, port, tid, connectTimeout)
Success: conn
Failure: false, error message
*/
LUA_LIB_METHOD int client_connect(lua_State* l_thread) {
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

LUA_LIB_METHOD int dns_resolve(lua_State* l_thread) {
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
	{"writeBufferLength", get_write_buffer_len},
	{"clearReadBuffer", reset_read_buffer},
	{"clearWriteBuffer", reset_write_buffer},
	{"appendBuffer", append_buffer},
	{"write", write_buffer},
	{"close", close_connection_lua},
	{"__gc", connection_gc},
	{NULL, NULL}  /* sentinel */
};

void luaw_init_tcp_lib (lua_State *L) {
	make_metatable(L, LUA_CONNECTION_META_TABLE, luaw_connection_methods);
}

