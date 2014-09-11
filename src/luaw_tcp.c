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

static int buff_size = 2048;        // default
static lua_State* l_global = NULL;  // main global Lua state that spawns all other coroutines
static char* server_ip;
static int server_port;

static struct addrinfo *log_server_addr = NULL;
static int log_sock_fd = -1;

static char hostname[512] = {'\0'};

static int service_http_fn_ref;
static int start_thread_fn_ref;
static int resume_thread_fn_ref;

static void close_if_active(uv_handle_t* handle, uv_close_cb close_cb) {
    if (handle && uv_is_active(handle)) {
        uv_close(handle, close_cb);
    }
    handle->data = NULL;
}

static void close_if_open(uv_handle_t* handle, uv_close_cb close_cb) {
    if (handle && !uv_is_closing(handle)) {
        uv_close(handle, close_cb);
    }
    handle->data = NULL;
}

static void clear_user_timer(luaw_timer_t* timer) {
    timer->state = INIT;
    timer->lua_tid = 0;
}

int new_user_timer(lua_State* l_thread) {
    luaw_timer_ref_t* ref = lua_newuserdata(l_thread, sizeof(luaw_timer_ref_t));
    if (ref == NULL) {
        raise_lua_error(l_thread, "Could not allocate memory for user timer lua reference");
    }

    luaw_timer_t *timer = (luaw_timer_t *)malloc(sizeof(luaw_timer_t));
    ref->timer = timer;
    if (timer == NULL) {
        return raise_lua_error(l_thread, "Could not allocate memory for user timer");
    }

    luaL_setmetatable(l_thread, LUA_USER_TIMER_META_TABLE);
    uv_timer_init(uv_default_loop(), &timer->handle);
    timer->handle.data = timer;
    clear_user_timer(timer);
    return 1;
}

static luaw_timer_t* get_timer(lua_State *l_thread, int timer_idx) {
    luaw_timer_ref_t* ref = luaL_checkudata(l_thread, timer_idx, LUA_USER_TIMER_META_TABLE);
    if ((ref == NULL)||(ref->timer == NULL)){
        raise_lua_error(l_thread, "Timer missing."); //never returns, longjmp
    }
    return ref->timer;
}

static void resume_lua_thread(lua_State* L, int nargs, int nresults, int errHandler) {
    int tid = lua_tointeger(L, (0 - nargs));
    debug_i(tid)
    if (tid) {
        int rc = lua_pcall(L, nargs, nresults, errHandler);
        debug_i(rc)
        if (rc != 0) {
            fprintf(stderr, "******** Error resuming Lua thread# %d: %s (%d) *********\n", tid, lua_tostring(L, -1), rc);
        }
    }
    step
}

/* lua call spec: status, timer_elapsed = timer:wait(tid)
Success, timer elapsed:  status = true, timer_elapsed = true
Success, timer not elapsed:  status = true, timer_elapsed = false
Failure:  status = false, error message
*/
LIBUV_CALLBACK static void on_user_timer_timeout(uv_timer_t* handle) {
    luaw_timer_t* timer = (luaw_timer_t*)handle->data;

    if(timer->lua_tid) {
//         lua_settop(l_global, 0);
        lua_rawgeti(l_global, LUA_REGISTRYINDEX, resume_thread_fn_ref);
        lua_pushinteger(l_global, timer->lua_tid);
        clear_user_timer(timer);

        /* Lua call spec: status, time_elapsed/error message = timer:wait() */
//        if (status) {
//            lua_pushboolean(l_global, 0);
//            lua_pushstring(l_global, uv_strerror(status));
//        } else {
            lua_pushboolean(l_global, 1);
            lua_pushboolean(l_global, 1);
//        }
        resume_lua_thread(l_global, 3, 2, 0);
    } else {
        timer->state = ELAPSED;
    }
}

/* lua call spec:
Success:  status(true), nil = timer:start(timeout)
Failure:  status(false), error message = timer:start(timeout)
*/
static int start_user_timer(lua_State* l_thread) {
    luaw_timer_t* timer = get_timer(l_thread, 1);

    if (timer->state != INIT) {
        /* Timer is already started by another lua thread */
        return error_to_lua(l_thread, "Could not start timer, timer state: %d", timer->state);
    }

    int timeout = lua_tointeger(l_thread, 2);
    if (timeout <= 0) {
        return error_to_lua(l_thread, "Invalid timeout value %d specified", timeout);
    }

    int rc = uv_timer_start(&timer->handle, on_user_timer_timeout, timeout, 0);
    if (rc) {
        return error_to_lua(l_thread, "Error starting timer: %s", uv_strerror(rc));
    }

    timer->state = TICKING;
    lua_pushboolean(l_thread, 1);
    return 1;
}

/* lua call spec: status, timer_elapsed = timer:wait(tid)
Success, timer elapsed:  status = true, timer_elapsed = true
Success, timer not elapsed:  status = true, timer_elapsed = false
Failure:  status = false, error message
*/
int wait_user_timer(lua_State* l_thread) {
    luaw_timer_t* timer = get_timer(l_thread, 1);

    if (timer->state == ELAPSED) {
        clear_user_timer(timer);
        lua_pushboolean(l_thread, 1);
        lua_pushboolean(l_thread, 1);
    } else {
        if (timer->state != TICKING) {
            return error_to_lua(l_thread, "Attempt to wait on timer that is not started, timer state: %d", timer->state);
        }
        if (timer->lua_tid) {
            return error_to_lua(l_thread, "Timer already is in use by thread %d", timer->lua_tid);
        }
        int tid = lua_tointeger(l_thread, 2);
        if (tid <= 0) {
            return error_to_lua(l_thread, "Invalid thread id %d specified", tid);
        }

        timer->lua_tid = tid;
        lua_pushboolean(l_thread, 1);
        lua_pushboolean(l_thread, 0);
    }

    return 2;
}

/* lua call spec: timer:stop() */
static int stop_user_timer(lua_State* l_thread) {
    luaw_timer_t* timer = get_timer(l_thread, 1);
    if (timer->state == TICKING) {
        uv_timer_stop(&timer->handle);
        clear_user_timer(timer);
    }
    return 0;
}

LIBUV_CALLBACK static void on_user_timer_close(uv_handle_t* handle) {
    if (handle) {
        luaw_timer_t* timer = TO_TIMER(handle);
        if (timer) {
            if (timer->lua_tid) {
                /* unblock waiting thread */
//                 lua_settop(l_global, 0);
                lua_rawgeti(l_global, LUA_REGISTRYINDEX, resume_thread_fn_ref);
                lua_pushinteger(l_global, timer->lua_tid);
                lua_pushboolean(l_global, 0);
                lua_pushstring(l_global, uv_strerror(UV_ECANCELED));
                resume_lua_thread(l_global, 3, 2, 0);
            }
            free(timer);
        } else {
            free(handle);
        }
    }
}

LUA_OBJ_METHOD static int timer_ref_gc(lua_State *L) {
    luaw_timer_ref_t* ref= (luaw_timer_ref_t*) luaL_testudata(L, 1, LUA_USER_TIMER_META_TABLE);
    if (ref && ref->timer) {
        luaw_timer_t* timer = ref->timer;
        ref->timer = NULL;       //don't free it twice!
        uv_close((uv_handle_t*)&timer->handle, on_user_timer_close);
    }
    return 0;
}

/* TCP Connection methods */

void clear_read_buffer(connection_t* conn) {
    if (conn) {
        conn->read_buffer.len = 0;
        conn->parse_len = 0;
    }
}

static void clear_write_buffer(connection_t* conn) {
    if (conn) conn->write_buffer.len = 0;
}

static connection_t* new_connection(lua_State* L) {
step
    connection_t* conn = lua_newuserdata(L, sizeof(connection_t));
    if (conn == NULL) goto free_conn;
    luaL_setmetatable(L, LUA_CONNECTION_META_TABLE);
step
    conn->handle = (uv_tcp_t*)malloc(sizeof(uv_tcp_t));
    if (!conn->handle) goto free_conn;

    conn->read_buffer.base = (char*)calloc(1, buff_size);
    if (!conn->read_buffer.base) goto free_handle;
step
    conn->read_timer = (uv_timer_t*)malloc(sizeof(uv_timer_t));
    if (!conn->read_timer) goto free_read_buff;
step
    conn->write_buffer.base = (char*)calloc(1, buff_size);
    if (!conn->write_buffer.base) goto free_read_timer;
step
    conn->write_timer = (uv_timer_t*)malloc(sizeof(uv_timer_t));
    if (!conn->write_timer) goto free_write_buff;
step
    conn->write_req = (uv_write_t*)malloc(sizeof(uv_write_t));
    if (!conn->write_req) goto free_write_timer;
step
    /* All allocations successfully done */
    conn->handle->data = conn;
    step
    uv_timer_init(uv_default_loop(), conn->read_timer);step
    conn->read_timer->data = conn;step
    uv_timer_init(uv_default_loop(), conn->write_timer);step
    conn->write_timer->data = conn;step
    conn->write_req->data = conn;step
    clear_read_buffer(conn);step
    clear_write_buffer(conn);step
    conn->lua_reader_tid = 0;
    conn->lua_writer_tid = 0;
step
    return conn;

    /* Error case */
    free_write_timer:   free(conn->write_timer);
    free_write_buff:    free(conn->write_buffer.base);
    free_read_timer:    free(conn->read_timer);
    free_read_buff:     free(conn->read_buffer.base);
    free_handle:        free(conn->handle);
    free_conn:          raise_lua_error(L, "Could not allocate memory for client connection");
step
    return NULL;
}

LUA_LIB_METHOD int new_connection_lua(lua_State* L) {
    new_connection(L);
    return 1;
}

static void send_read_data_to_lua(int tid, int status, size_t len, bool eof);
static void send_write_results_to_lua(int tid, int status, size_t len);

static inline void close_connection(connection_t* conn, int status, bool eof, bool warn_if_not_closed) {
step
    if ((conn == NULL)||(conn->handle == NULL)) return;
    if (warn_if_not_closed) fprintf(stderr, "Possible resource leak, connection not properly closed\n");

    if (conn->read_buffer.base) free(conn->read_buffer.base);
    conn->read_buffer.base = NULL;

    if (conn->write_buffer.base) free(conn->write_buffer.base);
    conn->write_buffer.base = NULL;

    close_if_active((uv_handle_t*)conn->read_timer, (uv_close_cb)free);
    close_if_active((uv_handle_t*)conn->write_timer, (uv_close_cb)free);
    close_if_active((uv_handle_t*)conn->handle, (uv_close_cb)free);
    conn->handle = NULL;

    if (conn->write_req->data)
        conn->write_req->data = NULL;
    else
        free(conn->write_req);

    /* unblock reader thread */
    if (conn->lua_reader_tid) {
        send_read_data_to_lua(conn->lua_reader_tid, status, 0, eof);
        step
        conn->lua_reader_tid = 0;
    }

    /* unblock writer thread */
    if (conn->lua_writer_tid) {
        send_write_results_to_lua(conn->lua_writer_tid, status, 0);
        conn->lua_writer_tid = 0;
    }
}

LIBUV_CALLBACK static void on_conn_timeout(uv_timer_t* timer) {
    /* Either connect,read or write timed out, close the connection */
    connection_t* conn = GET_CONN_OR_RETURN(timer);
    close_connection(conn, UV_ECANCELED, false, false);
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
step
    connection_t* conn = LUA_GET_CONN(l_thread, 1);
    close_connection(conn, UV_ECANCELED, false, false);
    return 0;
}

LUA_OBJ_METHOD static int connection_gc(lua_State *L) {
step
//     LUA_GET_CONN_OR_ERROR(L, 1, conn);
//     close_connection(conn, UV_ECANCELED, false, true);
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
    if(conn->read_buffer.base) {
        size_t free_space = buff_size - conn->read_buffer.len;
        if (free_space > 0) {
            buf->base = conn->read_buffer.base + conn->read_buffer.len;
            buf->len = free_space;
        }
    }
}

static void setup_read_return_values(lua_State* L, int status, size_t len, bool eof) {
debug_i(status)
debug_l(len)
    if (status) {
        /* error */
        lua_pushboolean(L, 0);
        lua_pushstring(L, uv_strerror(status));
        return;
    }

    /* Success cases */
    lua_pushboolean(L, 1);
    if (eof) {
        lua_pushliteral(L, "EOF");
        return;
    }

    if (len == 0) {
        lua_pushliteral(L, "WAIT");
        return;
    }
    lua_pushliteral(L, "OK");
step
}

static void send_read_data_to_lua(int tid, int status, size_t len, bool eof) {
debug_i(tid)
    if (tid) {
        lua_rawgeti(l_global, LUA_REGISTRYINDEX, resume_thread_fn_ref);
        lua_pushinteger(l_global, tid);
        setup_read_return_values(l_global, status, len, eof);
        resume_lua_thread(l_global, 3, 2, 0);
    }
}

LIBUV_API static void on_read(uv_stream_t* stream, ssize_t nread, const uv_buf_t* buf) {
debug_l(nread)
    connection_t* conn = GET_CONN_OR_RETURN(stream);
    int tid = conn->lua_reader_tid;
    conn->lua_reader_tid = 0;
    stop_timer(conn->read_timer); //clear read timeout if any
step
    if ((nread == 0)||(nread == UV_ENOBUFS)) {
    step
        /* either no data was read or no buffer was available to read the data. Anyway there
           is nothing to do so no need to wake conn coroutine. Let this callback pass through
           as  NOOP */
        return;
    }

    if (nread > 0) {
    step
        /* success: send read bytes to coroutine if one is waiting */
        conn->read_buffer.len += nread;
        send_read_data_to_lua(tid, 0 , PARSE_LEN(conn), false);
        step
        return;
    }

    if (nread == UV_EOF) {
    step
        /* socket conn closed, send EOF to lua coroutine to complete HTTP parsing */
        send_read_data_to_lua(tid, 0, 0, true);
        close_connection(conn, UV_ECANCELED, true, false);
        return;
    }

    /* nread < 0 i.e. error status */
    step
    send_read_data_to_lua(tid, nread , 0, false);
    close_connection(conn, nread, false, false);
step
}

/* lua call spec:
Success:  status(true), nil = conn:start_reading()
Failure:  status(false), error message = conn:start_reading()
*/
LUA_OBJ_METHOD static int start_reading(lua_State *l_thread) {
    LUA_GET_CONN_OR_ERROR(l_thread, 1, conn);

    int err_code = uv_read_start((uv_stream_t*)conn->handle, on_alloc, on_read);
    if (err_code) {
        lua_pushboolean(l_thread, 0);
        lua_pushstring(l_thread,  uv_strerror(err_code));
        close_connection(conn, err_code, false, false);
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
step
    LUA_GET_CONN_OR_ERROR(l_thread, 1, conn);

    if (!uv_is_active((uv_handle_t*)conn->handle)) {
       return error_to_lua(l_thread, "read() called on conn that is not registered to receive read events");
    }

    size_t len = PARSE_LEN(conn);
    setup_read_return_values(l_thread, 0, len, false);
    if (len == 0) {
        /* empty buffer, record reader tid and block (yield) in lua */
        int lua_reader_tid = lua_tointeger(l_thread, 2);
        if (lua_reader_tid == 0) {
            return error_to_lua(l_thread, "read() specified invalid thread id");
        }

        conn->lua_reader_tid = lua_reader_tid;
        int readTimeout = lua_tointeger(l_thread, 3);
        start_timer(conn->read_timer, readTimeout);
    }
    step
    return 2;
}

static void send_write_results_to_lua(int writer_tid, int write_status, size_t len) {
    if (writer_tid) {
        lua_rawgeti(l_global, LUA_REGISTRYINDEX, resume_thread_fn_ref);
        lua_pushinteger(l_global, writer_tid);

        if (write_status) {
            lua_pushboolean(l_global, 0);
            lua_pushstring(l_global, uv_strerror(write_status));
        } else {
            lua_pushboolean(l_global, 1);
            lua_pushinteger(l_global, len);
        }

        resume_lua_thread(l_global, 3, 2, 0);
    }
}

static int get_write_buffer_len(lua_State* l_thread) {
    LUA_GET_CONN_OR_ERROR(l_thread, 1, conn);
    lua_pushinteger(l_thread, conn->write_buffer.len);
    return 1;
}

LIBUV_API static void on_write(uv_write_t* req, int status) {
step
    connection_t* conn = TO_CONN(req);
    if(conn) {
        int tid = conn->lua_writer_tid;
        conn->lua_writer_tid = 0;
        stop_timer(conn->write_timer); //clear write timeout if any
        send_write_results_to_lua(tid, status, conn->write_buffer.len);
        clear_write_buffer(conn);
        if (status) close_connection(conn, status, false, false);
    } else {
        free(req);
    }
step
}

/* HTTP chunk in chunked transfer encoding:
*       chunk size in hex\r\n
*       actual chunk body\r\n
*/
static int add_http_chunk_envelope(lua_State* l_thread) {
step
    LUA_GET_CONN_OR_ERROR(l_thread, 1, conn)
    char* base = conn->write_buffer.base;
    const size_t len = conn->write_buffer.len;

    if (len <= CHUNK_HEADER_LEN) {
        return error_to_lua(l_thread, "500 Not enough space in buffer to add chunk header");
    }
    if ((buff_size - len) < 2) {
        return error_to_lua(l_thread, "500 Not enough space in buffer to add chunk trailer");
    }

    /* prefix chunk length in hex */
    sprintf(base, "%04zx", (len - CHUNK_HEADER_LEN));
    base[4] = '\r';
    base[5] = '\n';

    /*  suffix chunk with "\r\n" */
    base[len] = '\r';
    base[len+1] = '\n';
    conn->write_buffer.len = len + 2; //accounting for added \r\n

    lua_pushboolean(l_thread, 1);
    return 1;
}

/* lua call spec: conn:write(tid, writeTimeout)
Success: status(true), nwritten
Failure: status(false), error message
*/
LUA_OBJ_METHOD static int write_buffer(lua_State* l_thread) {
step
    LUA_GET_CONN_OR_ERROR(l_thread, 1, conn);
    conn->lua_writer_tid = 0;

    if (conn->write_buffer.len > 0) {
        /* non empty write buffer. Send write request, record writer tid and block in lua */
        int lua_writer_tid = lua_tointeger(l_thread, 2);
        if (lua_writer_tid == 0) {
            return error_to_lua(l_thread, "500 write() specified invalid thread id");
        }

        int writeTimeout = lua_tointeger(l_thread, 3);
        int err_code = uv_write(conn->write_req, (uv_stream_t*)conn->handle, &conn->write_buffer, 1, on_write);
        if (err_code) {
            close_connection(conn, err_code, false, false);
            lua_pushboolean(l_thread, 0);
            lua_pushstring(l_thread,  uv_strerror(err_code));
            return 2;
        }

        conn->lua_writer_tid = lua_writer_tid;
        start_timer(conn->write_timer, writeTimeout);
    }

    lua_pushboolean(l_thread, 1);
    lua_pushinteger(l_thread, conn->write_buffer.len);
step
    return 2;
}

/* Fill conn's write buffer with the input string passed. Multiple consecutive fill_buffer()
* calls append passed in strings inside conn's write buffer. If the buffer is too full to
* copy input string in its entirety, it copies whatever fraction of the input it can and
* returns the remaining part that could not be fit inside the buffer.
*
* Lua call spec:
* Success: remaining buffer capacity, part of the string that could not fit = conn:appendBuffer("...", is_chunked)
*          - when input fits in the buffer completely second return value is nil
* Failure: status(false), error message = conn:appendBuffer()
*/
LUA_OBJ_METHOD static int append_buffer(lua_State* l_thread) {
step
    LUA_GET_CONN_OR_ERROR(l_thread, 1, conn);

    size_t input_len = 0;
    const char* input = lua_tolstring(l_thread, 2, &input_len);
    int is_chunked = lua_toboolean(l_thread, 3);
    int trailer_len = (is_chunked) ? 2 : 0;

    size_t buff_cap = REMAINING_WRITE_BUFF_CAPACITY(conn, trailer_len);
    if (input == NULL) {
        lua_pushinteger(l_thread, buff_cap);
        lua_pushnil(l_thread);
        return 2;
    }

    size_t fit_len = (input_len <= buff_cap) ? input_len : buff_cap;
    size_t remaining_input_len = input_len - fit_len;

    char* dest = WRITE_BUFF_APPEND_DEST(conn);
    memcpy(dest, input, fit_len);
    conn->write_buffer.len += fit_len;

    lua_pushinteger(l_thread, REMAINING_WRITE_BUFF_CAPACITY(conn, trailer_len));
    if (remaining_input_len > 0) {
        lua_pushlstring(l_thread, (input + fit_len), remaining_input_len);
    } else {
        lua_pushnil(l_thread);
    }
    return 2;
}

LIBUV_CALLBACK static void on_client_connect(uv_connect_t* connect_req, int status) {
    connection_t* conn = GET_CONN_OR_RETURN(connect_req);

    stop_timer(conn->write_timer); //clear connect timeout if any
    free(connect_req);

    lua_rawgeti(l_global, LUA_REGISTRYINDEX, resume_thread_fn_ref);
    lua_pushinteger(l_global, conn->lua_writer_tid);

    if (status) {
        conn->lua_writer_tid = 0;
        close_connection(conn, status, false, false);
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

    int status = uv_tcp_init(uv_default_loop(), conn->handle);
    if (status) {
        free(connect_req);
        close_connection(conn, status, false, false);
        return error_to_lua(l_thread, "Could not initialize memory for connection");
    }

    status = uv_tcp_connect(connect_req, conn->handle, (const struct sockaddr*) &addr, on_client_connect);
    if (status) {
        free(connect_req);
        close_connection(conn, status, false, false);
        return error_to_lua(l_thread, "tcp connect failed: %s", uv_strerror(status));
    }

    conn->lua_writer_tid = tid;
    start_timer(conn->write_timer, connectTimeout);
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

/* create a new lua coroutine to service this conn, anchor it in "all active coroutines"
*  global table to prevent it from being garbage collected and start the coroutine
*/
LIBUV_CALLBACK static void on_server_connect(uv_stream_t* server, int status) {
    if (status) {
        raise_lua_error(l_global, "500 Error in on_server_connect callback: %s\n", uv_strerror(status));
        return;
    }

    lua_rawgeti(l_global, LUA_REGISTRYINDEX, start_thread_fn_ref);
    assert(lua_isfunction(l_global, -1));

    lua_rawgeti(l_global, LUA_REGISTRYINDEX, service_http_fn_ref);
    assert(lua_isfunction(l_global, -1));

    connection_t * conn = new_connection(l_global);

    status = uv_tcp_init(server->loop, conn->handle);
    if (status) {
        close_connection(conn, status, false, false);
        fprintf(stderr, "Could not initialize memory for a new connection\n");
        return;
    }

    status = uv_accept(server, (uv_stream_t*) conn->handle);
    if (status) {
        close_connection(conn, status, false, false);
        fprintf(stderr, "500 Error accepting incoming conn: %s\n", uv_strerror(status));
        return;
    }

    status = lua_pcall(l_global, 2, 2, 0);
    if (status) {
        fprintf(stderr, "******** Error starting new client connect thread: %s (%d) *********\n", lua_tostring(l_global, -1), status);
    }
}

/* Lua call spec:
* server = new_server(start_thread_fn, resume_thread_fn,
    {server_ip, server_port, connection_buffer_size, request_handler})
*/
LUA_LIB_METHOD int luaw_new_server(lua_State *L) {
    lua_pushvalue(L, 1);
    start_thread_fn_ref = luaL_ref(L, LUA_REGISTRYINDEX);

    lua_pushvalue(L, 2);
    resume_thread_fn_ref = luaL_ref(L, LUA_REGISTRYINDEX);

    lua_getfield(L, 3, "server_ip");
    server_ip = (char *)lua_tostring(L, -1);
    lua_pop(L, 1);

    lua_getfield(L, 3, "server_port");
    server_port = lua_tointeger(L, -1);
    lua_pop(L, 1);

    lua_getfield(L, 3, "connection_buffer_size");
    buff_size = lua_tointeger(L, -1);
    lua_pop(L, 1);

    lua_getfield(L, 3, "request_handler");
    service_http_fn_ref = luaL_ref(L, LUA_REGISTRYINDEX);

    luaw_server_t* luaw_server = lua_newuserdata(L, sizeof(luaw_server_t));
    if (luaw_server == NULL) {
        return raise_lua_error(L, "Could not allocate memory for Luaw server\n");
    }
    luaL_setmetatable(L, LUA_SERVER_META_TABLE);
    luaw_server->event_loop = uv_default_loop();

    return 1;
}

LUA_LIB_METHOD int connect_to_syslog(lua_State *L) {
    int rc = -1;
    int flags = 1;
    const char* log_server_ip = lua_tostring(L, 1);
    const char* log_server_port = lua_tostring(L, 2);

    if (log_server_ip && log_server_port) {
        struct addrinfo hints;

        memset(&hints, 0, sizeof(struct addrinfo));
        hints.ai_family = AF_INET;
        hints.ai_socktype = SOCK_DGRAM;
        hints.ai_flags = 0;
        hints.ai_protocol = 0;

        rc = getaddrinfo(log_server_ip, log_server_port, &hints, &log_server_addr);
        if (rc != 0) {
            fprintf(stderr,"failed to get address for sys log server :%s\n",gai_strerror(rc));
        } else {
            rc = socket(log_server_addr->ai_family, log_server_addr->ai_socktype, log_server_addr->ai_protocol);
            if (rc < 0) {
                fprintf(stderr, "could not connect to sys log server\n");
            } else {
                log_sock_fd = rc;
                #if defined(O_NONBLOCK)
                    if (-1 == (flags = fcntl(log_sock_fd, F_GETFL, 0))) flags = 0;
                    rc = fcntl(log_sock_fd, F_SETFL, flags | O_NONBLOCK);
                #else
                    rc = ioctl(log_sock_fd, FIONBIO, &flags);
                #endif
                if (rc < 0) {
                    fprintf(stderr, "Error putting syslog connection in non blocking mode\n");
                }
            }
        }
    }

    lua_pushboolean(L, (rc < 0) ? 0 : 1);
    return 1;
}

LUA_LIB_METHOD int send_to_syslog(lua_State *L) {
    if (log_sock_fd > 0) {
        size_t len = 0;
        const char* mesg = lua_tolstring(L, 1, &len);
        if ((mesg)&&(len > 0)) {
            sendto(log_sock_fd, mesg, len, MSG_DONTWAIT,log_server_addr->ai_addr, log_server_addr->ai_addrlen);
        }
    }
    return 0;
}

static const char* get_hostname() {
    if (hostname[0] == '\0') {
        int rc = gethostname(hostname, 511);
        if (rc < 0) {
            strcpy(hostname, "localhost");
        }
    }
    return hostname;
}

LUA_LIB_METHOD int get_hostname_lua(lua_State *L) {
    lua_pushstring(L, get_hostname());
    return 1;
}

LUA_OBJ_METHOD static int start_server(lua_State *L) {
    luaw_server_t* luaw_server = luaL_checkudata(L, 1, LUA_SERVER_META_TABLE);

    struct sockaddr_in addr;
    int err_code = uv_ip4_addr(server_ip, server_port, &addr);
    if (err_code) {
        return luaL_error(L, "Error initializing socket address: %s\n", uv_strerror(err_code));
    }

    uv_tcp_init(luaw_server->event_loop, &luaw_server->server);

    err_code = uv_tcp_bind(&luaw_server->server, (const struct sockaddr*) &addr, 0);
    if (err_code) {
        return luaL_error(L, "Error binding to port %d : %s\n", server_port, uv_strerror(err_code));
    }

    err_code = uv_listen((uv_stream_t*)&luaw_server->server, 128, on_server_connect);
    if (err_code) {
        return luaL_error(L, "Error listening on port %d : %s\n", server_port, uv_strerror(err_code));
    }

    return 1;
}

LUA_OBJ_METHOD static int run_loop_once(lua_State *L) {
    l_global = L;
    luaw_server_t* luaw_server = luaL_checkudata(l_global, 1, LUA_SERVER_META_TABLE);
    int status = uv_run(luaw_server->event_loop, UV_RUN_ONCE);
    lua_pushboolean(L, status);
    return 1;
}

LUA_OBJ_METHOD static int run_loop_no_block(lua_State *L) {
    l_global = L;
    luaw_server_t* luaw_server = luaL_checkudata(l_global, 1, LUA_SERVER_META_TABLE);
    int status = uv_run(luaw_server->event_loop, UV_RUN_NOWAIT);
    lua_pushboolean(L, status);
    return 1;
}

LUA_OBJ_METHOD static int stop_server(lua_State *L) {
    l_global = L;
    luaw_server_t* luaw_server = luaL_checkudata(l_global, 1, LUA_SERVER_META_TABLE);
    if (luaw_server->event_loop) {
        uv_stop(luaw_server->event_loop);
    }
    return 0;
}

static const struct luaL_Reg luaw_connection_methods[] = {
	{"startReading", start_reading},
	{"read", read_check},
	{"writeBufferLength", get_write_buffer_len},
	{"clearReadBuffer", reset_read_buffer},
    {"clearWriteBuffer", reset_write_buffer},
	{"appendBuffer", append_buffer},
	{"addChunkEnvelope", add_http_chunk_envelope},
	{"write", write_buffer},
	{"close", close_connection_lua},
	{"newServerHttpRequest", luaw_fn_place_holder},
	{"newServerHttpResponse", luaw_fn_place_holder},
	{"newClientHttpRequest", luaw_fn_place_holder},
	{"__gc", connection_gc},
    {NULL, NULL}  /* sentinel */
};

static const struct luaL_Reg luaw_server_methods[] = {
    {"start", start_server},
	{"blockingPoll", run_loop_once},
    {"nonBlockingPoll", run_loop_no_block},
    {"stop", stop_server},
	{NULL, NULL}  /* sentinel */
};

static const struct luaL_Reg luaw_user_timer_methods[] = {
	{"start", start_user_timer},
	{"stop", stop_user_timer},
	{"wait", wait_user_timer},
	{"sleep", luaw_fn_place_holder},
	{"__gc", timer_ref_gc},
	{NULL, NULL}  /* sentinel */
};


void luaw_init_tcp_lib (lua_State *L) {
	make_metatable(L, LUA_CONNECTION_META_TABLE, luaw_connection_methods);
	make_metatable(L, LUA_SERVER_META_TABLE, luaw_server_methods);
	make_metatable(L, LUA_USER_TIMER_META_TABLE, luaw_user_timer_methods);
}

