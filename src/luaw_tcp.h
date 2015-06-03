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
#define LUA_BUFFER_META_TABLE "_luaw_buff_MT_"
#define CONN_BUFFER_SIZE 4096

typedef struct buff_s buff_t;

struct buff_s {
    int offset;                     /* position upto which content is consumed from buffer */
    int end;                        /* end of content available in buffer */
    char buff[CONN_BUFFER_SIZE];    /* buffer to read into */
};

typedef struct connection_s connection_t;

/* client connection's state: socket connection, coroutines servicing the connection
 and read/write buffers for the connection */
struct connection_s {
    uv_tcp_t handle;                /* connected socket */

    /* read section */
    int lua_reader_tid;             /* ID of the reading coroutine */
    uv_timer_t read_timer;          /* for read timeout */

    /* write section */
    int lua_writer_tid;             /* ID of the writing coroutine */
    uv_timer_t write_timer;         /* for write/connect timeout */
    uv_write_t write_req;           /* write request */

    /* memory management */
    int ref_count;                  /* reference count */
    connection_t** lua_ref;         /* back reference to Lua's full userdata pointing to this conn */

    /* read buffer */
    buff_t read_buffer;             /* buffer to read into */
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
extern connection_t* new_connection(lua_State* L);
extern void close_connection(connection_t* conn, const int status);
extern int remaining_read_len(connection_t* conn);
extern char* remaining_read_start(connection_t* conn);
extern void luaw_init_tcp_lib (lua_State *L);

#endif
