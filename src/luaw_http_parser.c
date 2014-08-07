#include <stdlib.h>
#include <string.h>
#include <assert.h>

#include <lua.h>
#include <lauxlib.h>

#include "luaw_common.h"
#include "luaw_http_parser.h"
#include "luaw_tcp.h"

typedef enum {
	PARSE_HTTP_PARSER_IDX = 1,
	PARSE_HTTP_REQ_IDX,
	PARSE_HTTP_BUFF_IDX,
	PARSE_HTTP_LENGTH_IDX,
	PARSE_HTTP_CONN_IDX
} 
parse_http_lua_stack_index;

static int lua_http_callback(const char* cb_name, const http_parser *parser, const char* start, const size_t len) {
	lua_State *L = (lua_State *)parser->data;

	luaL_checkudata(L, PARSE_HTTP_PARSER_IDX, LUA_HTTP_PARSER_META_TABLE);
	lua_getfield(L, PARSE_HTTP_PARSER_IDX, cb_name);
	if (lua_isfunction(L, -1) != 1) {
		return raise_lua_error(L, "500 Missing lua http callback %s", cb_name);
	}
	
	/* Lua HTTP callback signature: lua_callback_fn(req, [parsed HTTP field string]) */
	lua_pushvalue(L, PARSE_HTTP_REQ_IDX);
	if (start != NULL) {
		lua_pushlstring(L, start, len);
	}
	else {
		if ((strcmp(cb_name, "onHeadersComplete")&&(strcmp(cb_name, "onMesgComplete")))) {
		    return raise_lua_error(L, "500 Empty parsed http field passed to callback %s", cb_name);
		}
		lua_pushboolean(L, http_should_keep_alive(parser));
	}	

    lua_call(L, 2, 0);
	return 0;
}

HTTP_PARSER_CALLBACK static int http_parser_on_message_begin(http_parser *parser) {
	return 0;
}

HTTP_PARSER_CALLBACK static int http_parser_on_url(http_parser *parser, const char* start, size_t len) {
	return lua_http_callback("onURL", parser, start, len);
}

HTTP_PARSER_CALLBACK static int http_parser_on_status(http_parser *parser, const char* start, size_t len) {
	return lua_http_callback("onStatus", parser, start, len);
}

HTTP_PARSER_CALLBACK static int http_parser_on_header_name(http_parser *parser, const char* start, size_t len) {
	return lua_http_callback("onHeaderName", parser, start, len);
}

HTTP_PARSER_CALLBACK static int http_parser_on_header_value(http_parser *parser, const char* start, size_t len) {
	return lua_http_callback("onHeaderValue", parser, start, len);
}

HTTP_PARSER_CALLBACK static int http_parser_on_headers_complete(http_parser *parser) {
	lua_State *L = (lua_State *)parser->data;

	if (!lua_istable(L, PARSE_HTTP_REQ_IDX)) {
		return raise_lua_error(L, "500 Missing lua http request table");
	}
	
	lua_pushinteger(L, parser->http_major);
	lua_setfield(L, PARSE_HTTP_REQ_IDX, "major_version");

	lua_pushinteger(L, parser->http_minor);
	lua_setfield(L, PARSE_HTTP_REQ_IDX, "minor_version");

	if (parser->type == HTTP_REQUEST) {
		lua_pushstring(L, http_methods[parser->method]);
		lua_setfield(L, PARSE_HTTP_REQ_IDX, "method");
	}

	if (parser->type == HTTP_RESPONSE) {
		lua_pushinteger(L, parser->status_code);
		lua_setfield(L, PARSE_HTTP_REQ_IDX, "status");
	}

	if (parser->http_errno != 0) {
		lua_pushinteger(L, parser->http_errno);
		lua_setfield(L, PARSE_HTTP_REQ_IDX, "errno");
	}
	
	lua_http_callback("onHeadersComplete", parser, NULL, 0);
	return 0;
}

HTTP_PARSER_CALLBACK static int http_parser_on_body(http_parser *parser, const char* start, size_t len) {
	return lua_http_callback("onBody", parser, start, len);
}

HTTP_PARSER_CALLBACK static int http_parser_on_message_complete(http_parser *parser) {
    /* pause http parser to correctly handle HTTP 1.1 pipelining */
    http_parser_pause(parser, 1);
    return lua_http_callback("onMesgComplete", parser, NULL, 0);
}

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
	char *name, *value;
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

static int new_http_parser(lua_State *L, enum http_parser_type parser_type) {
	http_parser* parser = lua_newuserdata(L, sizeof(http_parser));
	if (parser == NULL) {
		return raise_lua_error(L, "500 Failed to allocate memory for new http_parser.");
	}	
	luaL_setmetatable(L, LUA_HTTP_PARSER_META_TABLE);
	http_parser_init(parser, parser_type);
	return 1;
}

LUA_LIB_METHOD int luaw_new_http_request_parser(lua_State* L) {
    return new_http_parser(L, HTTP_REQUEST);
}

LUA_LIB_METHOD int luaw_new_http_response_parser(lua_State* L) {
    return new_http_parser(L, HTTP_RESPONSE);
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

static int parse_http_buffer(lua_State *L) {
    lua_settop(L, 3);
	http_parser* parser = luaL_checkudata(L, 1, LUA_HTTP_PARSER_META_TABLE);
	parser->data = L;

	const luaw_connection_ref_t* conn_ref = luaL_checkudata(L, 3, LUA_CONNECTION_META_TABLE);
	connection_t* conn = conn_ref->conn;
	char* buff = PARSE_START(conn);
	const size_t len = PARSE_LEN(conn);

	const int nparsed = http_parser_execute(parser, &parser_settings, buff, len);
	const int remaining = len - nparsed;
	
	if (remaining == 0) {
	    /* normal case, buffer fully parsed */
	    clear_read_buffer(conn);
        lua_pushboolean(L, 1);
        return 1;
	} 
    
    if ((remaining > 0)&&(parser->http_errno == HPE_PAUSED)) {
        /* pipelined HTTP request, "forward" buffer to the end of last parsed request */
        conn->parse_len += nparsed;
        http_parser_pause(parser, 0); 
        lua_pushboolean(L, 1);
        return 1;
    } 
    
    /* error while parsing */
    lua_pushboolean(L, 0);
    lua_pushfstring(L, "400 Error parsing HTTP fragment: %s\n total=%d, parsed=%d\n", buff, len, nparsed);
    return 2;
}

LUA_OBJ_METHOD static int parse_http_string(lua_State *L) {
	size_t len = 0;
	const char* str = luaL_checklstring(L, PARSE_HTTP_BUFF_IDX, &len);
    
    lua_settop(L, 3);
	http_parser* parser = luaL_checkudata(L, PARSE_HTTP_PARSER_IDX, LUA_HTTP_PARSER_META_TABLE);
	parser->data = L;
	const int nparsed = http_parser_execute(parser, &parser_settings, str, len);
	
    if (nparsed != len) {
        if (parser->http_errno != HPE_OK) {
            /* error while parsing */
            lua_pushboolean(L, 0);
            lua_pushfstring(L, "400 Error parsing HTTP fragment: %s\n total=%d, parsed=%d\n", str, len, nparsed);
            return 2;
        }
        /* pipelined HTTP request */
    }
    
    if (parser->http_errno == HPE_PAUSED) {
        http_parser_pause(parser, 0); 
    } 

    lua_pushboolean(L, 1);
    lua_pushnil(L);
    return 2;
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
	{"parseHttpString", parse_http_string},
	{"onHeaderName", luaw_fn_place_holder},
	{"onHeaderValue", luaw_fn_place_holder},
	{"onHeadersComplete", luaw_fn_place_holder},
	{"onURL", luaw_fn_place_holder},
	{"onStatus", luaw_fn_place_holder},
	{"onBody", luaw_fn_place_holder},
	{"onMesgComplete", luaw_fn_place_holder},
	{NULL, NULL}  /* sentinel */
};

void luaw_init_http_lib (lua_State *L) {
    make_metatable(L, LUA_HTTP_PARSER_META_TABLE, http_parser_methods);
}