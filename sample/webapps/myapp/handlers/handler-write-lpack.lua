local utils_lib = require('luaw_utils')
local http_lib = require('luaw_http')
local lpack = require('luapack')

local big_str = "abcdefghijklmnopqrstuvwxyz0123456789"
while (#big_str < 4096) do
    big_str = big_str ..'-'..big_str
end

local mesg = {
    name = "Homer Simpson",
    gender = "M",
    uint8 = 255,
    uint16 = 256,
    uint32 = 4294967295,
    int8_neg = -128,
    int8 = 127,
    int16_neg = -1000,
    int16 = 20000,
    int32 = 32456,
    int64= 17179869184,
    int64_neg= -17179869184,
    float = 0.0012,
    float_neg = - 112.8,
    double = 8589934592.13,
    double_neg = -8589934592.28,
    str = "ABCD",
    bigstr = big_str,
    positive = true,
    negative = false,
    kids = {
        {
            name = "Lisa",
            gender = "F",
            uint8 = 255,
            uint16 = 256,
            uint32 = 4294967295,
            int8_neg = -128,
            int8 = 127,
            int16_neg = -1000,
            int16 = 20000,
            int32 = 32456,
            int64= 17179869184,
            int64_neg= -17179869184,
            float = 0.0012,
            float_neg = - 112.8,
            double = 8589934592.13,
            double_neg = -8589934592.28,
            str = "ABCD",
            bigstr = big_str,
            positive = true,
            negative = false
        },
        {
            name = "Bart",
            gender = "M",
            uint8 = 255,
            uint16 = 256,
            uint32 = 4294967295,
            int8_neg = -128,
            int8 = 127,
            int16_neg = -1000,
            int16 = 20000,
            int32 = 32456,
            int64= 17179869184,
            int64_neg= -17179869184,
            float = 0.0012,
            float_neg = - 112.8,
            double = 8589934592.13,
            double_neg = -8589934592.28,
            str = "ABCD",
            bigstr = big_str,
            positive = true,
            negative = false
        },
        {
            name = "Maggy",
            gender = "?"
        }
    }
}

local dict = {
    "name",
    "gender",
    "uint8",
    "uint16",
    "uint32",
    "int8_neg",
    "int8",
    "int16_neg",
    "int16",
    "int32",
    "int64",
    "int64_neg",
    "float",
    "float_neg",
    "double",
    "double_neg",
    "str",
    "bigstr",
    "positive",
    "negative",
    big_str
}

registerHandler {
    method = 'GET',
    path = 'genlpack',

    handler = function(httpConn)
        httpConn:setStatus(200)
        local lpackWriter = lpack.newLPackRespWriter(httpConn)
        if (httpConn.params['dict'] == 'true') then
            lpackWriter:useDictionary(dict)
        end
        lpackWriter:write(mesg)
    end
}
