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

#define LUA_LPACK_META_TABLE "_luaw_lpack_MT_"

static const int32_t _i = 1;

#define is_bigendian() ((*(char *)&_i) == 0)

typedef enum {
    /* meta type for all marker tags, should never itself occur in read stream */
    TYPE_MARKER = 0,

    /* single byte marker tags */
    MAP_START,
    ARRAY_START,
    DICT_START,
    RECORD_END,

    /* single byte value markers */
    NIL,
    BOOL_TRUE,
    BOOL_FALSE,

    /* fix width types */
    UINT_8,
    DICT_ENTRY,
    UINT_16,
    BIG_DICT_ENTRY,
    UINT_32,
    INT_8,
    INT_16,
    INT_32,
    INT_64,
    FLOAT,
    DOUBLE,

    /* variable length types */
    STRING,
    BIG_STRING,
    HUGE_STRING
}
type_tag;

extern void luaw_init_lpack_lib (lua_State *L);
extern int new_lpack_parser(lua_State* L);
