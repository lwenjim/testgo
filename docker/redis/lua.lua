#!/usr/local/bin/lua

local array = { "a", "" }
for index, value in pairs(array) do
    print(index, value)
end
local table = {}
table["abc"] = 123
table["aaa"] = 456
for index, value in pairs(table) do
    print(index, value)
end