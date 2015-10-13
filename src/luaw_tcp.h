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

typedef struct tcp_listener_s tcp_listener_t;

struct tcp_listener_s {
    uv_tcp_t listen_sock;
    int port;
    int handler_fn_ref;
    tcp_listener_t* next;
};

typedef struct connection_s connection_t;

/* client connection's state: socket connection, coroutines servicing the connection
 and read/write buffers for the connection */
struct connection_s {
    uv_tcp_t handle;                /* connected socket */

    /* read section */
    int lua_reader_tid;             /* ID of the reading coroutine */
    uv_timer_t read_timer;          /* for read timeout */
    buff_t* read_buffer;            

    /* write section */
    int lua_writer_tid;             /* ID of the writing coroutine */
    uv_timer_t write_timer;         /* for write/connect timeout */
    uv_write_t write_req;           

    /* memory management */
    bool mark_closed;              
    int ref_count;                  
};

#define TO_CONN(h) (connection_t*)h->data

#define GET_CONN_OR_RETURN(h)   \
    (connection_t*)h->data;     \
    if(!h->data) return

#define LUA_GET_CONN_OR_RETURN(L, i, c)         \
    connection_t* c = lua_touserdata(L, i);     \
    if (c == NULL) return 0;

#define LUA_GET_CONN_OR_ERROR(L, i, c)                              \
    connection_t* c = lua_touserdata(L, i);                         \
    if (c == NULL) return error_to_lua(L, "Connection missing");    \

#define TO_TIMER(h) (luaw_timer_t*)h->data



/* TCP lib methods to be exported */
extern connection_t* new_connection();
extern void close_connection(connection_t* conn, const int status);
extern int start_listeners();
extern void close_listeners();
extern void luaw_init_tcp_lib (lua_State *L);

#endif
