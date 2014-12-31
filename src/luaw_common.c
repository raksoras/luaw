#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <unistd.h>

#include <lua.h>
#include <lauxlib.h>

#include "uv.h"
#include "luaw_common.h"
#include "luaw_tcp.h"
#include "luaw_http_parser.h"
#include "luaw_timer.h"
#include "lua_lpack.h"

/* globals */
lua_State* l_global = NULL; //main global Lua state that spawns all other coroutines
int resume_thread_fn_ref;   //Resume thread lua function


static logfile_sate log_state = LOG_NOT_OPEN;
static uv_file logfile;
static struct addrinfo *log_server_addr = NULL;
static int log_sock_fd = -1;
static char hostname[512] = {'\0'};


void resume_lua_thread(lua_State* L, int nargs, int nresults, int errHandler) {
    int tid = lua_tointeger(L, (0 - nargs));
    if (tid) {
        int rc = lua_pcall(L, nargs, nresults, errHandler);
        if (rc != 0) {
            fprintf(stderr, "******** Error resuming Lua thread# %d: %s (%d) *********\n", tid, lua_tostring(L, -1), rc);
        }
    }
}

LUA_LIB_METHOD static int create_dict(lua_State* L) {
    int narr = luaL_checkint(L, 1);
    int nrec = luaL_checkint(L, 2);
    lua_createtable(L, narr, nrec);
    return 1;
}

LUA_LIB_METHOD static int to_hex(lua_State* L) {
    int num = luaL_checkinteger(L, -1);
    if (num > 65536) {
        raise_lua_error(L, "toHex called with input %d, which is larger than acceptable limit", num);
    }

    char hex[5];
    sprintf(hex, "%x", num);
    lua_pushstring(L, hex);
    return 1;
}

/* sets up error code and error message on the Lua stack to be returned by the original C
   function called from Lua. */
int error_to_lua(lua_State* L, const char* fmt, ...) {
    lua_settop(L, 0); //remove success status and params table from stack
    lua_pushboolean(L, 0);  //set status to false in case of error
    va_list argp;
    va_start(argp, fmt);
    lua_pushvfstring(L, fmt, argp);
    va_end(argp);
    return 2; //two values status and err_mesg pushed onto stack.
}

int raise_lua_error (lua_State *L, const char *fmt, ...) {
    va_list argp;
    va_start(argp, fmt);
    lua_pushvfstring(L, fmt, argp);
    va_end(argp);
    return lua_error(L);
}

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

void close_if_active(uv_handle_t* handle, uv_close_cb close_cb) {
    if ((handle != NULL)&&(!uv_is_closing(handle))) {
        uv_close(handle, close_cb);
    }
}

void make_metatable(lua_State *L, const char* mt_name, const luaL_Reg* mt_funcs) {
	luaL_newmetatable(L, mt_name);
	luaL_setfuncs(L, mt_funcs, 0);
	/* client metatable.__index = client metatable */
	lua_pushstring(L, "__index");
	lua_pushvalue(L,-2);
	lua_rawset(L, -3);
}

static const struct luaL_Reg luaw_lib[] = {
    {"createDict", create_dict},
    {"toHex", to_hex},
	{"urlDecode", luaw_url_decode},
	{"newHttpRequestParser", luaw_new_http_request_parser},
	{"newHttpResponseParser", luaw_new_http_response_parser},
	{"parseURL", luaw_parse_url},
	{"toHttpError", luaw_to_http_error},
	{"newConnection", new_connection_lua},
	{"connect", client_connect},
	{"resolveDNS", dns_resolve},
	{"newTimer", new_user_timer},
	{"logState", get_logging_state},
	{"openLog", open_log_file},
	{"writeLog", write_log},
    {"syslogConnect", connect_to_syslog},
	{"syslogSend", send_to_syslog},
	{"hostname", get_hostname_lua},
	{"newLPackParser", new_lpack_parser},
    {NULL, NULL}  /* sentinel */
};

LUA_LIB_METHOD int luaw_open_lib (lua_State *L) {
    luaw_init_http_lib(L);
    luaw_init_tcp_lib(L);
    luaw_init_timer_lib(L);
    luaw_init_lpack_lib(L);
    luaL_newlib(L, luaw_lib);
    lua_setglobal(L, "Luaw");
	return 1;
}
