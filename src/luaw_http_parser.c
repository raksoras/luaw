#include <stdlib.h>
#include <string.h>
#include <assert.h>

#include <lua.h>
#include <lauxlib.h>

#include "uv.h"
#include "luaw_common.h"
#include "luaw_http_parser.h"
#include "luaw_tcp.h"

typedef enum {
	PARSE_HTTP_PARSER_IDX = 1,
	PARSE_HTTP_BUFF_IDX,
	PARSE_HTTP_REQ_IDX,
	PARSE_HTTP_LENGTH_IDX,
	PARSE_HTTP_CONN_IDX
}
parse_http_lua_stack_index;

static int decode_hex_str(const char* str, int len) {
	char *read_ptr = (char *)str;
	char *write_ptr = (char *)str;
	int hex_ch;
	char ch;

	while (len) {
		ch = *read_ptr;
		if ((ch == '%')&&(len > 2)) {
			sscanf((read_ptr+1),"%2x", &hex_ch);
			ch = (char)hex_ch;
			read_ptr += 3; len -= 3;
		}
		else {
			read_ptr++;	len--;
		}

		*write_ptr = ch;
		write_ptr++;
	}
	return ((const unsigned char*)write_ptr - (const unsigned char*)str);
}

static int handle_name_value_pair(lua_State* L, const char* name, int name_len, bool hex_name, const char* value, int value_len, bool hex_value) {
	if ((name != NULL)&&(name_len > 0)&&(value != NULL)&&(value_len > 0)) {
		if (hex_name) {
			name_len = decode_hex_str(name, name_len);
		}
		if (hex_value) {
			value_len = decode_hex_str(value, value_len);
		}

		lua_getfield(L, 1, "storeHttpParam");
		if (lua_isfunction(L, -1) != 1) {
			raise_lua_error(L, "500 Missing lua function storeHttpParam()");
        }
		lua_pushvalue(L, 3);
		lua_pushlstring(L, name, name_len);
		lua_pushlstring(L, value, value_len) ;
		lua_call(L, 3, 0);
	}
	else if((name_len == 0)&&(value_len > 0)) {
	    error_to_lua(L, "400 Bad URL encoding: empty parameter name, non empty parameter value: %s ", value);
	    return false;
	}
	return true; //param name without value is ok, e.g. &foo=
}

/* Lua call spec:
 success: params table, nil = http_lib:url_decode(url encoded string, params)
 success: status(false), error message = http_lib:url_decode(url encoded string, params)
*/
LUA_LIB_METHOD int luaw_url_decode(lua_State *L) {
	if (!lua_istable(L, 1)) {
		return raise_lua_error(L, "500 Lua HTTP lib table is missing");
	}
	size_t length = 0;
	const char* data = lua_tolstring(L, 2, &length);
	char *read_ptr = (char *)data;
	char *name = NULL;
	char *value = NULL;
	bool hex_name = false, hex_value = false;
	int name_len = 0, value_len = 0;
	decoder_state ds = starting_name;

	while (length--) {
		char ch = *read_ptr;

		switch(ds) {
			case starting_name:
                if (!handle_name_value_pair(L, name, name_len, hex_name, value, value_len, hex_value)) return 2; //err_code, err_mesg
				name_len = 0;
				hex_name = false;
				value_len = 0;
				hex_value = false;

				switch(ch) {
					case '&':
					case '=':
                	    return error_to_lua(L, "400 Bad URL encoding: Error while expecting start of param name at: %s\n", read_ptr);
					case '%':
						hex_name = true;
				}
				ds = in_name;
				name = read_ptr;
				name_len = 1;
				break;

			case in_name:
				switch(ch) {
					case '&':
			    	    return error_to_lua(L, "400 Bad URL encoding: Error while parsing param name at: %s\n", read_ptr);
					case '=':
						ds = starting_value;
						break;
					case '%':
						hex_name = true;
					default:
						name_len++;
				}
				break;

			case starting_value:
				switch(ch) {
					case '&':
					case '=':
			    	    return error_to_lua(L, "400 Bad URL encoding: Error while expecting start of param value at: %s\n", read_ptr);
					case '%':
						hex_value = true;
				}
				ds = in_value;
				value = read_ptr;
				value_len = 1;
				break;

			case in_value:
				switch(ch) {
					case '&':
						ds = starting_name;
						break;
					case '=':
			    	    return error_to_lua(L, "400 Bad URL encoding: Error while parsing param value at: %s\n", read_ptr);
					case '%':
						hex_value = true;
					default:
						value_len++;
				}
				break;

		}
		if (ch == '+') *read_ptr =' ';
		read_ptr++;
	}
    return handle_name_value_pair(L, name, name_len, hex_name, value, value_len, hex_value) ? 1 : 2;
}

static int new_lhttp_parser(lua_State *L, enum http_parser_type parser_type) {
	luaw_http_parser_t* lhttp_parser = lua_newuserdata(L, sizeof(luaw_http_parser_t));
	if (lhttp_parser == NULL) {
		return raise_lua_error(L, "500 Failed to allocate memory for new http_parser.");
	}
	luaL_setmetatable(L, LUA_HTTP_PARSER_META_TABLE);
	http_parser_init(&lhttp_parser->parser, parser_type);
	lhttp_parser->parser.data = lhttp_parser;
	return 1;
}

LUA_LIB_METHOD int luaw_new_http_request_parser(lua_State* L) {
    return new_lhttp_parser(L, HTTP_REQUEST);
}

LUA_LIB_METHOD int luaw_new_http_response_parser(lua_State* L) {
    return new_lhttp_parser(L, HTTP_RESPONSE);
}

LUA_LIB_METHOD int luaw_init_http_parser(lua_State* L) {
	luaw_http_parser_t* lhttp_parser = luaL_checkudata(L, 1, LUA_HTTP_PARSER_META_TABLE);
	http_parser* parser = &lhttp_parser->parser;
	http_parser_init(parser, parser->type);
    return 0;
}

static int handle_http_callback(http_parser *parser, http_parser_cb_type cb, const char* start, size_t len) {
    luaw_http_parser_t* lhttp_parser = (luaw_http_parser_t*) parser->data;
    lhttp_parser->http_cb = cb;
    lhttp_parser->start = (char*)start;
    lhttp_parser->len = len;
    http_parser_pause(parser, 1);
    return 0;
}

HTTP_PARSER_CALLBACK static int http_parser_on_message_begin(http_parser *parser) {
	return handle_http_callback(parser, http_cb_on_message_begin, NULL, 0);
}

HTTP_PARSER_CALLBACK static int http_parser_on_url(http_parser *parser, const char* start, size_t len) {
	return handle_http_callback(parser, http_cb_on_url, start, len);
}

HTTP_PARSER_CALLBACK static int http_parser_on_status(http_parser *parser, const char* start, size_t len) {
	return handle_http_callback(parser, http_cb_on_status, start, len);
}

HTTP_PARSER_CALLBACK static int http_parser_on_header_name(http_parser *parser, const char* start, size_t len) {
	return handle_http_callback(parser, http_cb_on_header_field, start, len);
}

HTTP_PARSER_CALLBACK static int http_parser_on_header_value(http_parser *parser, const char* start, size_t len) {
	return handle_http_callback(parser, http_cb_on_header_value, start, len);
}

HTTP_PARSER_CALLBACK static int http_parser_on_headers_complete(http_parser *parser) {
    return handle_http_callback(parser, http_cb_on_headers_complete, NULL, 0);
}

HTTP_PARSER_CALLBACK static int http_parser_on_body(http_parser *parser, const char* start, size_t len) {
	return handle_http_callback(parser, http_cb_on_body, start, len);
}

HTTP_PARSER_CALLBACK static int http_parser_on_message_complete(http_parser *parser) {
    return handle_http_callback(parser, http_cb_on_mesg_complete, NULL, 0);
}

static const http_parser_settings parser_settings = {
	.on_message_begin = http_parser_on_message_begin,
	.on_status = http_parser_on_status,
	.on_url = http_parser_on_url,
	.on_header_field = http_parser_on_header_name,
	.on_header_value = http_parser_on_header_value,
	.on_headers_complete = http_parser_on_headers_complete,
	.on_body = http_parser_on_body,
	.on_message_complete = http_parser_on_message_complete
};

/* Lua call spec:
* All failures:
*       false, error message = parseHttpBuffer(conn)
*
* Successes:
*
*   http_parser_on_headers_complete:
*       http_cb_type, buffer remaining, http_should_keep_alive, major_version, minor_version, http method, http status code = parseHttpBuffer(conn)
*
*   http_parser_on_message_complete:
*       http_cb_type, buffer remaining, http_should_keep_alive = parseHttpBuffer(conn)
*
*   All other callbacks:
*       http_cb_type, buffer remaining, parsed value = parseHttpBuffer(conn)
*
*/
static int parse_http_buffer(lua_State *L) {
    lua_settop(L, 2);
	luaw_http_parser_t* lhttp_parser = luaL_checkudata(L, 1, LUA_HTTP_PARSER_META_TABLE);
	http_parser* parser = &lhttp_parser->parser;
	connection_t* conn = luaL_checkudata(L, 2, LUA_CONNECTION_META_TABLE);

	char* buff = PARSE_START(conn);
	const size_t len = PARSE_LEN(conn);

	const int nparsed = http_parser_execute(parser, &parser_settings, buff, len);
	const int remaining = len - nparsed;

    if ((remaining > 0)&&(parser->http_errno != HPE_PAUSED)) {
        lua_pushboolean(L, 0);
        lua_pushfstring(L, "400 Error parsing HTTP fragment: errorCode=%d, total=%d, parsed=%d, content=%s\n", parser->http_errno, len, nparsed, buff);
        return 2;
    }

    lua_pushinteger(L, lhttp_parser->http_cb);
    lua_pushinteger(L, remaining);
    int nresults = 3;
    switch(lhttp_parser->http_cb) {

        case http_cb_on_headers_complete:
            lua_pushboolean(L, http_should_keep_alive(parser));
	        lua_pushinteger(L, parser->http_major);
        	lua_pushinteger(L, parser->http_minor);
            if (parser->type == HTTP_REQUEST) {
                lua_pushstring(L, http_methods[parser->method]);
            } else {
                lua_pushnil(L);
            }
            if (parser->type == HTTP_RESPONSE) {
                lua_pushinteger(L, parser->status_code);
            } else {
                lua_pushnil(L);
            }
            nresults = 7;
            break;

        case http_cb_on_mesg_complete:
            lua_pushboolean(L, http_should_keep_alive(parser));
            break;

        default:
            lua_pushlstring(L, lhttp_parser->start, lhttp_parser->len);
    }

	if (remaining == 0) {
	    /* buffer fully parsed */
	    clear_read_buffer(conn);
	} else {
        /* "forward" buffer to the end of last parsed request and un-pause the parser */
        conn->parse_len += nparsed;
    }
    http_parser_pause(parser, 0);

    return nresults;
}


const char* url_field_names[] = { "schema", "host", "port", "path", "queryString", "fragment", "userInfo" };

static void push_url_part(lua_State *L, const char* buff, struct http_parser_url* parsed_url, enum http_parser_url_fields url_field) {
	if ((parsed_url->field_set) & (1 << url_field)) {
		lua_pushlstring(L, (buff + parsed_url->field_data[url_field].off), parsed_url->field_data[url_field].len);
		lua_setfield(L, -2, url_field_names[url_field]);
	}
}

/* Lua call spec:
* Success: url parts table = http_lib.parseURL(url_string, is_connect)
* Failure: nil = http_lib.parseURL(url_string, is_connect)
*/
LUA_LIB_METHOD int luaw_parse_url(lua_State *L) {
	size_t len = 0;
	const char* buff = luaL_checklstring(L, 1, &len);
	int is_connect = lua_toboolean(L, 2);

	struct http_parser_url* parsed_url = (struct http_parser_url*) malloc(sizeof(struct http_parser_url));
	if (parsed_url == NULL) {
		return raise_lua_error(L, "500 Could not allocate memory for URL struct");
	}

	int result = http_parser_parse_url(buff, len, is_connect, parsed_url);
	if (result) {
	    lua_pushnil(L);
	    return 1;
	}

	lua_createtable(L, 0 , 7);
	push_url_part(L, buff, parsed_url, UF_SCHEMA);
	push_url_part(L, buff, parsed_url, UF_HOST);
	push_url_part(L, buff, parsed_url, UF_PORT);
	push_url_part(L, buff, parsed_url, UF_PATH);
	push_url_part(L, buff, parsed_url, UF_QUERY);
	push_url_part(L, buff, parsed_url, UF_FRAGMENT);
	push_url_part(L, buff, parsed_url, UF_USERINFO);

	free(parsed_url);
	return 1;
}

LUA_LIB_METHOD int luaw_to_http_error(lua_State *L) {
    const char* err = luaL_checkstring(L, -1);
    char* err_mesg;
    int err_code = strtol(err, &err_mesg, 10);
    lua_pushinteger(L, err_code);
    lua_pushstring(L, err_mesg);
    return 2;
}


static const struct luaL_Reg http_parser_methods[] = {
	{"parseHttpBuffer", parse_http_buffer},
	{"initHttpParser", luaw_init_http_parser},
	{NULL, NULL}  /* sentinel */
};

void luaw_init_http_lib (lua_State *L) {
    make_metatable(L, LUA_HTTP_PARSER_META_TABLE, http_parser_methods);
}
