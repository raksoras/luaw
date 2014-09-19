#ifndef LUAW_SERVER_H

#define LUAW_SERVER_H


// extern char* server_ip;
// extern int server_port;
extern int buff_size;

// extern uv_tcp_t server;
// extern uv_loop_t* event_loop;

extern lua_State* l_global;

// extern int service_http_fn_ref;
// extern int start_thread_fn_ref;
extern int resume_thread_fn_ref;

#endif