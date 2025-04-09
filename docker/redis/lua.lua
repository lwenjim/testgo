#!/usr/local/bin/lua

local array = { "a", "", "abc", ""}
for index, value in ipairs(array) do
    if (value ~= "") then
        print(value)
    end
end