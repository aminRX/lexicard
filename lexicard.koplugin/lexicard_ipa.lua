--[[
Looks words up in data/cmudict-ipa.tsv ("word<TAB>ipa1|ipa2", sorted by byte)
with a binary search, so the 3.5 MB file is never loaded into memory.
]]
local Ipa = {}

function Ipa.lookup(path, word)
    local f = io.open(path, "rb")
    if not f then return nil end
    local lo, hi = 0, f:seek("end")
    while hi - lo > 4096 do
        local mid = math.floor((lo + hi) / 2)
        f:seek("set", mid)
        f:read("*l")
        local line = f:read("*l")
        local key = line and line:match("^([^\t]*)")
        if not key or key >= word then hi = mid else lo = mid end
    end
    f:seek("set", lo)
    if lo > 0 then f:read("*l") end
    local found
    for line in f:lines() do
        local key, value = line:match("^([^\t]*)\t(.*)$")
        if key == word then
            found = {}
            for variant in value:gmatch("[^|]+") do found[#found + 1] = variant end
            break
        end
        if key and key > word then break end
    end
    f:close()
    return found
end

-- "/ipa ipa/" when every word of the headword has exactly one pronunciation, else nil.
function Ipa.for_headword(path, headword)
    local parts = {}
    for word in (headword or ""):lower():gmatch("%S+") do
        local variants = Ipa.lookup(path, word)
        if not variants or #variants ~= 1 then return nil end
        parts[#parts + 1] = variants[1]
    end
    if #parts == 0 then return nil end
    return "/" .. table.concat(parts, " ") .. "/"
end

return Ipa
