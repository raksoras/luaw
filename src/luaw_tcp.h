#ifndef LUAW_TCP_H

#define LUAW_TCP_H

#define LUA_CONNECTION_META_TABLE "_luaw_connection_MT_"
#define LUA_USER_TIMER_META_TABLE "_luaw_user_timer_MT_"

typedef enum {
	OPEN = 0,
	CLOSING,
	CLOSED
}
handle_state;


struct luaw_connection_ref;

/* client connection's state: socket connection, coroutines servicing the connection
 and read/write buffers for the connection */
typedef struct {
    uv_tcp_t handle;                    /* connected socket */
    size_t buff_size;                   /* allocation size of read/write buffers */

    /* reader section */
    int lua_reader_tid;                 /* id of a lua thread reading from this connection */
    int read_status;                    /* libuv status of the last read operation */
    bool read_eof;                      /* is EOF reached in read stream */
    uv_buf_t read_buffer;               /* buffer to read into */
    size_t parse_len;                   /* length of buffer parsed so far - HTTP pipelining */
    uv_timer_t read_timer;              /* for read timeout */

    /* writer section */    
    int lua_writer_tid;                 /* id of a lua thread writing on this connection */
    int write_status;                   /* libuv status of the last write operation */
    uv_buf_t write_buffer;              /* buffer to write from */
    uv_write_t write_req;               /* write request */
    uv_timer_t write_timer;             /* for write/connect timeout */
    
    /* resource cleanup management state*/
    handle_state state;                 /* is uv_close() called on handles */
    bool lua_gc_done;                   /* whether the full user data pointing to this conn 
                                          in lua VM is garbage collected */
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
    connection_t* conn;
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
} timer_t;

typedef struct luaw_timer_ref {
    timer_t* timer;
} luaw_timer_ref_t;


#define CHUNK_HEADER_LEN 6 //4 hex digits for chunk sizes up to 64K + 2 for \r\n
#define MAX_CONNECTION_BUFF_SIZE 65536  //16^4
#define TO_CONNECTION(handle)   (connection_t*)handle->data
#define TO_TIMER(handle)        (timer_t*)handle->data
#define LUA_SERVER_META_TABLE "_luaw_server_MT_"

#define FN_REFS(L, scd_stk_id, fname, refvar)    \
    lua_pushstring(L, fname);                   \
    lua_rawget(L, scd_stk_id);                  \
    assert(lua_isfunction(L, -1));              \
    refvar = luaL_ref(L, LUA_REGISTRYINDEX);    

#define ASSERT_INIT_DONES(L, var) if (var == 0) return luaL_error(L, #var " not initialized")

#define PARSE_START(conn)  (void *)(conn->read_buffer.base + conn->parse_len)
#define PARSE_LEN(conn)  (conn->read_buffer.len - conn->parse_len)

#define REMAINING_WRITE_BUFF_CAPACITY(connection, trailer_len) ((connection->buff_size) - (connection->write_buffer.len) - (trailer_len))
#define WRITE_BUFF_APPEND_DEST(connection) ((connection->write_buffer.base)+(connection->write_buffer.len))


/* TCP lib methods to be exported */
extern int luaw_new_connection_ref(lua_State* L);
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