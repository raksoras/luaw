#include "http_parser.h"
#include "uv.h"

#ifndef LUAW_HTTP_PARSER_H
#define LUAW_HTTP_PARSER_H

#define LUA_HTTP_PARSER_META_TABLE "__luaw_HTTP_parser_MT__"

typedef enum {
	starting_name = 0,
	in_name,
	starting_value,
	in_value
}
decoder_state;

typedef enum {
    http_cb_none = 1,  //Used to denote invocations of http_parser_execute() that don't cause callback
    http_cb_on_message_begin,
    http_cb_on_status,
    http_cb_on_url,
    http_cb_on_header_field,
    http_cb_on_header_value,
    http_cb_on_headers_complete,
    http_cb_on_body,
    http_cb_on_mesg_complete
} http_parser_cb_type;

/* imported from http_parser.h */
static const char *http_methods[] =
  {
#define XX(num, name, string) #string,
  HTTP_METHOD_MAP(XX)
#undef XX
  };

#define PARSE_START(conn)  (void *)(conn->read_buffer + conn->parse_len)
#define PARSE_LEN(conn)  (conn->read_len - conn->parse_len)

typedef struct {
    http_parser parser;
    http_parser_cb_type http_cb;
    char* start;
    size_t len;
}
luaw_http_parser_t;

/* HTTP lib methods to be exported */

extern int luaw_url_decode(lua_State *L);
extern int luaw_new_http_request_parser(lua_State *L);
extern int luaw_new_http_response_parser(lua_State *L);
extern int luaw_parse_url(lua_State *L);
extern int luaw_to_http_error(lua_State *L);
extern void luaw_init_http_lib(lua_State *L);

#endif
