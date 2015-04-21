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
#include <assert.h>
#include <unistd.h>

#include <lua.h>
#include <lauxlib.h>

#include "uv.h"
#include "luaw_common.h"
#include "luaw_logging.h"

static logfile_sate log_state = LOG_NOT_OPEN;
static uv_file logfile;
static struct addrinfo *log_server_addr = NULL;
static int log_sock_fd = -1;


LUA_LIB_METHOD static int get_logging_state(lua_State* l_thread) {
    lua_pushinteger(l_thread, log_state);
    return 1;
}

LIBUV_CALLBACK static void on_log_open(uv_fs_t* req) {
    logfile = req->result;
    log_state = LOG_IS_OPEN;
    uv_fs_req_cleanup(req);
    free(req);
}

LUA_LIB_METHOD static int open_log_file(lua_State* l_thread) {
    if (log_state == LOG_NOT_OPEN) {
        const char* filename = lua_tostring(l_thread, 1);
        if (filename) {
            uv_fs_t* open_req = (uv_fs_t*)malloc(sizeof(uv_fs_t));
            if (open_req) {
                uv_loop_t* loop = uv_default_loop();
                int rc = uv_fs_open(loop, open_req, filename, O_WRONLY|O_CREAT|O_TRUNC, S_IRUSR|S_IWUSR|S_IRGRP, on_log_open);
                if (rc == 0) {
                    log_state = OPENING_LOG;
                }
            }
        }
    }
    return 0;
}

LIBUV_CALLBACK static void on_log_close(uv_fs_t* req) {
    uv_fs_req_cleanup(req);
    free(req);
}

LIBUV_CALLBACK static void close_log(uv_fs_t* req) {
    uv_file f = *((int*)req->data);
    uv_fs_req_cleanup(req);
    uv_fs_close(uv_default_loop(), req, f, on_log_close);
}

LIBUV_CALLBACK static void on_log_write(uv_fs_t* req) {
    if (req->result >= 0) {
        uv_fs_req_cleanup(req);
        free(req);
    } else { /* error */
        log_state = LOG_NOT_OPEN;
        close_log(req);
    }
}

LUA_LIB_METHOD static int write_log(lua_State* l_thread) {
    if (log_state == LOG_IS_OPEN) {
        size_t len = 0;
        const char* str = lua_tolstring(l_thread, 1, &len);

        if ((str != NULL)||(len > 0)) {
            char* log_mesg = malloc(len * sizeof(char));
            if (log_mesg != NULL) {
                memcpy(log_mesg, str, len);
                uv_fs_t* write_req = (uv_fs_t*)malloc(sizeof(uv_fs_t));

                if (write_req) {
                    write_req->data = &logfile;
                    uv_buf_t buff = uv_buf_init(log_mesg, len);
                    uv_loop_t* loop = uv_default_loop();

                    int rotate_log = lua_toboolean(l_thread, 2);
                    if (rotate_log == 0) {
                        int rc = uv_fs_write(loop, write_req, logfile, &buff, 1, -1, on_log_write);
                        if (rc != 0) {
                            log_state = LOG_NOT_OPEN;
                            close_log(write_req);
                        }
                    } else {
                        log_state = LOG_NOT_OPEN;
                        uv_fs_write(loop, write_req, logfile, &buff, 1, -1, close_log);
                    }
                } else {
                    free(log_mesg);
                }
            }
        }
    }

    lua_pushinteger(l_thread, log_state);
    return 1;
}

void close_syslog() {
	uv_freeaddrinfo(log_server_addr);
}

LUA_LIB_METHOD static int connect_to_syslog(lua_State *L) {
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

LUA_LIB_METHOD static int send_to_syslog(lua_State *L) {
    if (log_sock_fd > 0) {
        size_t len = 0;
        const char* mesg = lua_tolstring(L, 1, &len);
        if ((mesg)&&(len > 0)) {
            sendto(log_sock_fd, mesg, len, MSG_DONTWAIT,log_server_addr->ai_addr, log_server_addr->ai_addrlen);
        }
    }
    return 0;
}



static const struct luaL_Reg luaw_logging_lib[] = {
	{"logState", get_logging_state},
	{"openLog", open_log_file},
	{"writeLog", write_log},
    {"syslogConnect", connect_to_syslog},
	{"syslogSend", send_to_syslog},
    {NULL, NULL}  /* sentinel */
};

int luaw_init_logging_lib (lua_State *L) {
    luaL_newlib(L, luaw_logging_lib);
    lua_setglobal(L, "luaw_logging_lib");
	return 1;
}
