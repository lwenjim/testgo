-- -@class Redis
-- -@field call fun(command: string, ...): any
-- -@field pcall fun(command: string, ...): any, any
-- -@field log fun(level: string, message: string)
-- -@field sha1hex fun(input: string): string

-- -@type Redis
-- redis = {}

-- 现在可以正常使用 redis.call()，并享受代码补全
-- local value = redis.call("GET", "mykey")

-- return ARGS[1]

local redis = require "resty.redis"
local red = redis:new()
red:connect("127.0.0.1", 6379)
local res = red:get("mykey")
error(res)
