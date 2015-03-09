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
extern void luaw_init_http_lib(lua_State *L);

#endif
