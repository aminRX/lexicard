--[[
Looks words up in data/cmudict-ipa.tsv ("word<TAB>ipa1|ipa2", sorted by byte)
with a binary search, so the 3.5 MB file is never loaded into memory.
]]
local Text = require("lexicard_text")

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

-- Edit distance between two UTF-8 strings, counted in characters.
Ipa.distance = Text.distance

-- Drops slashes, stress and length marks and unifies spellings of the same sound
-- (ɹ/r, ɚ/ər, ɝ/ɜr, ɡ/g), so variants compare by sound.
local function normalize(ipa)
    return (ipa:gsub("/", ""):gsub("ˈ", ""):gsub("ˌ", ""):gsub("ː", ""):gsub("%.", "")
        :gsub("ɹ", "r"):gsub("ɚ", "ər"):gsub("ɝ", "ɜr"):gsub("ɡ", "g"))
end

--[[
"/ipa ipa/" for the headword from the dictionary, or nil if a word is missing.
When a word has several pronunciations, `hint` (Gemini's IPA) picks the closest;
without a hint an ambiguous word gives nil.
]]
function Ipa.for_headword(path, headword, hint)
    local words = {}
    for word in (headword or ""):lower():gmatch("%S+") do words[#words + 1] = word end
    if #words == 0 then return nil end
    local guess = normalize(hint or "")
    local guess_parts = {}
    for part in guess:gmatch("%S+") do guess_parts[#guess_parts + 1] = part end
    local parts = {}
    for i, word in ipairs(words) do
        local variants = Ipa.lookup(path, word)
        if not variants then return nil end
        local choice = variants[1]
        if #variants > 1 then
            if guess == "" then return nil end
            local target = #guess_parts == #words and guess_parts[i] or guess
            local best
            for _, variant in ipairs(variants) do
                local d = Ipa.distance(normalize(variant), target)
                if not best or d < best then best, choice = d, variant end
            end
        end
        parts[#parts + 1] = choice
    end
    return "/" .. table.concat(parts, " ") .. "/"
end

return Ipa
