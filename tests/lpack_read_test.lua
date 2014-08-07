local luaw_lib = require("luaw_lib")
local lpack = require("luapack")
local testing = require("unit_testing")

local lpackReader = lpack.newLPackReader(lpack.fileReader("./out.bin"))
--lpackReader:useDictionary(dict)
local value = lpackReader:read()

testing.printTable(value, 0, "    ")

