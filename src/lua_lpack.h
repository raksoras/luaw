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
    HUGE_STRING,
    DICT_URL,
    BIG_DICT_URL
}
type_tag;

extern void luaw_init_lpack_lib (lua_State *L);
extern int new_lpack_parser(lua_State* L);
