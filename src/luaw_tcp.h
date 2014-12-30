#ifndef LUAW_TCP_H

#define LUAW_TCP_H

#define LUA_CONNECTION_META_TABLE "_luaw_connection_MT_"

/* client connection's state: socket connection, coroutines servicing the connection
 and read/write buffers for the connection */
typedef struct {
    uv_tcp_t* handle;           /* connected socket */

    /* read section */
    int lua_reader_tid;         /* ID of the reading coroutine */
    char* read_buffer;       	/* buffer to read into */
	size_t read_len;			/* read length */
    size_t parse_len;           /* length of buffer parsed so far - HTTP pipelining */
    uv_timer_t* read_timer;     /* for read timeout */

    /* write section */
    int lua_writer_tid;         /* ID of the writing coroutine */
    char* write_buffer;      	/* buffer to write from */
	size_t write_len;			/* write length */
	char chunk_header[16];		/* buffer to write HTTP 1.1 chunk header */
    uv_timer_t* write_timer;    /* for write/connect timeout */
    uv_write_t* write_req;      /* write request */
} connection_t;

#define CHUNK_HEADER_LEN 6 //4 hex digits for chunk sizes up to 64K + 2 for \r\n

#define MAX_CONNECTION_BUFF_SIZE 65536  //16^4

#define TO_CONN(h) (connection_t*)h->data

#define GET_CONN_OR_RETURN(h)   \
    (connection_t*)h->data;     \
    if(!h->data) return

#define LUA_GET_CONN(L, i) luaL_checkudata(L, i, LUA_CONNECTION_META_TABLE)

#define LUA_GET_CONN_OR_ERROR(L, i, c)                                      \
    connection_t* c = luaL_checkudata(L, i, LUA_CONNECTION_META_TABLE);     \
    if (!c) return error_to_lua(L, "Connection missing");                   \
    if (!c->handle) return error_to_lua(L, "Connection closed");

#define TO_TIMER(h) (luaw_timer_t*)h->data


/* TCP lib methods to be exported */
extern int new_connection_lua(lua_State* L);
extern connection_t* new_connection(lua_State* L);
extern void close_connection(connection_t* conn, const int status);
extern void luaw_init_tcp_lib (lua_State *L);
extern int client_connect(lua_State* l_thread);
extern int dns_resolve(lua_State* l_thread);
extern int new_user_timer(lua_State* l_thread);
extern int connect_to_syslog(lua_State *L);
extern int send_to_syslog(lua_State *L);
extern int get_hostname_lua(lua_State *L);
extern void clear_read_buffer(connection_t* conn);

#endif
