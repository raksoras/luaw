#ifndef LUAW_TCP_H

#define LUAW_TCP_H

#define LUA_CONNECTION_META_TABLE "_luaw_connection_MT_"
#define LUA_USER_TIMER_META_TABLE "_luaw_user_timer_MT_"
#define LUA_SERVER_META_TABLE "_luaw_server_MT_"

/* client connection's state: socket connection, coroutines servicing the connection
 and read/write buffers for the connection */
typedef struct {
    uv_tcp_t* handle;           /* connected socket */
    bool is_closed;             /* connection state */

    /* read section */
    int lua_reader_tid;         /* ID of the reading coroutine */
    uv_buf_t read_buffer;       /* buffer to read into */
    size_t parse_len;           /* length of buffer parsed so far - HTTP pipelining */
    uv_timer_t* read_timer;     /* for read timeout */

    /* write section */
    int lua_writer_tid;         /* ID of the writing coroutine */
    uv_buf_t write_buffer;      /* buffer to write from */
    uv_timer_t* write_timer;    /* for write/connect timeout */
    uv_write_t* write_req;      /* write request */
} connection_t;

/* struct used to map connection_t to full user data in Lua. We need full user data for
    A) to be able to use metatable to provide methods like connection:read() etc.
    B) to free connection_t resources reliably even when some buggy code forgets to do the
       cleanup by having Lua's gc call cleanup (i.e. __gc) as last defense.
  However, we can't used connection_t itself as a full userdata because it will be free'd by
  Lua as soon as the last reference to it goes away when really the correct way and place
  to free it is in on_close callback called by libuv after uv_close() closes the connection
*/
typedef struct luaw_connection_ref {
    connection_t* conn_c_ref;
} luaw_connection_ref_t;

typedef struct {
    uv_tcp_t server;
    uv_loop_t* event_loop;
} luaw_server_t;

typedef enum {
	INIT = 0,
	TICKING,
	ELAPSED
}
timer_state;

typedef struct {
    uv_timer_t handle;
    timer_state state;
    int lua_tid;            /* id of a lua thread waiting on this timer */
} luaw_timer_t;

typedef struct luaw_timer_ref {
    luaw_timer_t* timer;
} luaw_timer_ref_t;


#define CHUNK_HEADER_LEN 6 //4 hex digits for chunk sizes up to 64K + 2 for \r\n

#define MAX_CONNECTION_BUFF_SIZE 65536  //16^4

#define TO_CONN(h) (connection_t*)h->data

#define GET_CONN_OR_RETURN(h)   \
    (connection_t*)h->data;     \
    if(!h->data) return

#define LUA_GET_CONN(L, i) luaL_checkudata(L, i, LUA_CONNECTION_META_TABLE)

#define LUA_GET_CONN_OR_ERROR(L, i, c)                                         \
    connection_t* c = luaL_checkudata(L, i, LUA_CONNECTION_META_TABLE);   \
    if (!c) return error_to_lua(L, "Connection missing");                   \
    if (!c->handle) return error_to_lua(L, "Connection closed");

#define TO_TIMER(h) (luaw_timer_t*)h->data

#define REMAINING_WRITE_BUFF_CAPACITY(connection, trailer_len) (buff_size - (connection->write_buffer.len) - (trailer_len))

#define WRITE_BUFF_APPEND_DEST(connection) ((connection->write_buffer.base)+(connection->write_buffer.len))

#define CLEANUP_ON_FAIL_MALLOC(ptr, type, label)    \
    ptr = (type##*)malloc(sizeof(type));            \
    if(ptr == NULL) goto label;

#define CLEANUP_ON_FAIL_CALLOC(ptr, size, label)    \
    ptr = (char*)calloc(1, size);                   \
    if(ptr == NULL) goto label;

#define GET_TID(h)  ((h && h->data) ? (*((int*)h->data)) : 0)

/* TCP lib methods to be exported */
extern int new_connection_lua(lua_State* L);
extern int luaw_new_server(lua_State* L);
extern void luaw_init_tcp_lib (lua_State *L);
extern int client_connect(lua_State* l_thread);
extern int dns_resolve(lua_State* l_thread);
extern int new_user_timer(lua_State* l_thread);
extern int connect_to_syslog(lua_State *L);
extern int send_to_syslog(lua_State *L);
extern int get_hostname_lua(lua_State *L);
extern void clear_read_buffer(connection_t* conn);

#endif
