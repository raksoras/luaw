local constMT = {
    __newindex = function(table, key, value)
        error("constant "..table.name.." cannot be changed")
    end,

    __tostring = function(table)
        return table.name
    end,

    __concat = function(op1, op2)
        return tostring(op1)..tostring(op2)
    end,

    __metatable = "Luaw constant"
}

local function luaw_constant(value)
    local c = {name = value}
    setmetatable(c, constMT)
    return c
end

return {
    -- scheduler constants
    TS_RUNNABLE = luaw_constant("RUNNABLE"),
    TS_DONE = luaw_constant("DONE"),
    TS_BLOCKED_EVENT = luaw_constant("BLOCKED_ON_EVENT"),
    TS_BLOCKED_THREAD = luaw_constant("BLOCKED_ON_THREAD"),
    END_OF_CALL = luaw_constant("END_OF_CALL"),
    END_OF_THREAD = luaw_constant("END_OF_THREAD"),

    -- TCP constants
    DEFAULT_CONNECT_TIMEOUT = luaw_server_config.connect_timeout or 8000,
    DEFAULT_READ_TIMEOUT = luaw_server_config.read_timeout or 3000,
    DEFAULT_WRITE_TIMEOUT = luaw_server_config.write_timeout or 3000,
    CONN_BUFFER_SIZE = luaw_server_config.connection_buffer_size or 4096,

    -- HTTP parser constants
    EOF = 0,
    CRLF = '\r\n',
    MULTIPART_BEGIN = luaw_constant("MULTIPART_BEGIN"),
    PART_BEGIN = luaw_constant("PART_BEGIN"),
    PART_DATA = luaw_constant("PART_DATA"),
    PART_END = luaw_constant("PART_END"),
    MULTIPART_END = luaw_constant("MULTIPART_END")

}