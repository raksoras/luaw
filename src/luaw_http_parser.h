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

/* imported from http_parser.h */
static const char *http_methods[] =
  {
#define XX(num, name, string) #string,
  HTTP_METHOD_MAP(XX)
#undef XX
  };

/* HTTP lib methods to be exported */

extern int luaw_url_decode(lua_State *L);
extern int luaw_new_http_request_parser(lua_State *L);
extern int luaw_new_http_response_parser(lua_State *L);
extern int luaw_parse_url(lua_State *L);
extern int luaw_to_http_error(lua_State *L);
extern void luaw_init_http_lib(lua_State *L);

#endif
