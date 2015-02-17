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

#ifndef LUAW_TCP_H

#define LUAW_TCP_H

#define LUA_CONNECTION_META_TABLE "_luaw_connection_MT_"
#define CONN_BUFFER_SIZE 4096

typedef struct connection_s connection_t;

/* client connection's state: socket connection, coroutines servicing the connection
 and read/write buffers for the connection */
struct connection_s {
    uv_tcp_t handle;                        /* connected socket */

    /* read section */
    int lua_reader_tid;                     /* ID of the reading coroutine */
    char read_buffer[CONN_BUFFER_SIZE];     /* buffer to read into */
	size_t read_len;			            /* read length */
    size_t parse_len;                       /* length of buffer parsed so far - HTTP pipelining */
    uv_timer_t read_timer;                  /* for read timeout */

    /* write section */
    int lua_writer_tid;                     /* ID of the writing coroutine */
    char write_buffer[CONN_BUFFER_SIZE];    /* buffer to write from */
	size_t write_len;			            /* write length */
	char chunk_header[16];		            /* buffer to write HTTP 1.1 chunk header */
    uv_timer_t write_timer;                 /* for write/connect timeout */
    uv_write_t write_req;                   /* write request */

    /* memory management */
    int ref_count;                          /* reference count */
    connection_t** lua_ref;                 /* back reference to Lua's full userdata pointing to this conn */
};

#define MAX_CONNECTION_BUFF_SIZE 65536  //16^4

#define TO_CONN(h) (connection_t*)h->data

#define GET_CONN_OR_RETURN(h)   \
    (connection_t*)h->data;     \
    if(!h->data) return

#define LUA_GET_CONN_OR_RETURN(L, i, c)                                     \
    connection_t** cr = luaL_checkudata(L, i, LUA_CONNECTION_META_TABLE);   \
    if (cr == NULL) return 0;                                               \
    connection_t* c = *cr;                                                  \
    if (c == NULL) return 0;

#define LUA_GET_CONN_OR_ERROR(L, i, c)                                      \
    connection_t** cr = luaL_checkudata(L, i, LUA_CONNECTION_META_TABLE);   \
    if (cr == NULL) return error_to_lua(L, "Connection missing");           \
    connection_t* c = *cr;                                                  \
    if (c == NULL) return error_to_lua(L, "Connection closed");

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
