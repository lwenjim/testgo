local data = {}
local myData = redis.call("keys", "*")

for i, v in pairs(myData) do
    local t = redis.call("type", v)["ok"]
    if (t == "string") then
        data[v] = redis.call("get", v)
    elseif (t == "hash") then
        local d = redis.call("hgetall", v)
        for i, v in pairs(d) do
            data[i] = v
        end
    else
    end
end
return data
