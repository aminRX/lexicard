--[[
JSON adapter. KOReader ships rapidjson; the Mac tests use dkjson.
`quote` builds JSON string literals ourselves so the request body can keep
the schema's key order.
]]
local Json = {}

local ok, rapidjson = pcall(require, "rapidjson")

if ok then
    Json.encode = function(value) return rapidjson.encode(value) end
    Json.decode = function(text)
        local done, value, err = pcall(rapidjson.decode, text)
        if not done then return nil, tostring(value) end
        if value == nil then return nil, err or "invalid JSON" end
        return value
    end
    Json.array = function(t) return rapidjson.array and rapidjson.array(t or {}) or (t or {}) end
    Json.null = rapidjson.null
else
    local dkjson = require("dkjson")
    Json.encode = function(value) return dkjson.encode(value) end
    Json.decode = function(text)
        local value, _, err = dkjson.decode(text, 1, dkjson.null)
        if err then return nil, err end
        return value
    end
    Json.array = function(t) return setmetatable(t or {}, { __jsontype = "array" }) end
    Json.null = dkjson.null
end

function Json.is_null(value)
    return value == nil or value == Json.null
end

local ESCAPES = {
    ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
    ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
}

function Json.quote(s)
    return '"' .. s:gsub('[%c"\\]', function(c)
        return ESCAPES[c] or string.format("\\u%04x", c:byte())
    end) .. '"'
end

return Json
