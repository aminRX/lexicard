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
-- (ɹ/r, ɚ ɝ ɜ/ər, ɡ/g), so variants compare by sound.
function Ipa.normalize(ipa)
    return (ipa:gsub("/", ""):gsub("ˈ", ""):gsub("ˌ", ""):gsub("ː", ""):gsub("%.", "")
        :gsub("ɹ", "r"):gsub("ɚ", "ər"):gsub("ɝ", "ər"):gsub("ɜr", "ər"):gsub("ɜ", "ər"):gsub("ɡ", "g"))
end

-- Pronunciations for each word of the headword, or nil if a word is missing.
-- When a word has several, `hint` (Gemini's IPA) picks the closest; without a hint an ambiguous word gives nil.
function Ipa.headword_parts(path, headword, hint)
    local words = {}
    for word in (headword or ""):lower():gmatch("%S+") do words[#words + 1] = word end
    if #words == 0 then return nil end
    local guess = Ipa.normalize(hint or "")
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
                local d = Ipa.distance(Ipa.normalize(variant), target)
                if not best or d < best then best, choice = d, variant end
            end
        end
        parts[#parts + 1] = choice
    end
    return parts
end

-- "/ipa ipa/" for the headword from the dictionary, or nil.
function Ipa.for_headword(path, headword, hint)
    local parts = Ipa.headword_parts(path, headword, hint)
    if not parts then return nil end
    return "/" .. table.concat(parts, " ") .. "/"
end

-- Phrasal verbs: secondary stress on the verb, primary on the particle (/ˌɡɪv ˈʌp/).
function Ipa.phrasal_stress(parts)
    local out = {}
    for i, p in ipairs(parts) do out[i] = p end
    if #out < 2 then return out end
    if out[1]:find("ˈ", 1, true) then
        out[1] = out[1]:gsub("ˈ", "ˌ")
    elseif not out[1]:find("ˌ", 1, true) then
        out[1] = "ˌ" .. out[1]
    end
    if not out[2]:find("ˈ", 1, true) then out[2] = "ˈ" .. out[2] end
    return out
end

local IPA_CHARS = {}
for ch in ("abdefhijklmnoprstuvwzæɑɒɔəɛɪʊʌθðʃʒŋɡɾʔˈˌʧʤ /"):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    IPA_CHARS[ch] = true
end

-- Oxford American style: no length or syllable marks, ər for ɚ/ɝ/ɜ, r for ɹ, ˈ for an apostrophe.
function Ipa.style(ipa)
    local s = (ipa or ""):gsub("ː", ""):gsub("%.", ""):gsub("'", "ˈ"):gsub("ɹ", "r")
    s = s:gsub("ɚ", "ər"):gsub("ɝ", "ər"):gsub("ɜr", "ər"):gsub("ɜ", "ər"):gsub("g", "ɡ")
    return s
end

-- The model's IPA if it is plausible for the headword (valid symbols, one transcription per word).
function Ipa.check_model(ipa, headword)
    local body = Ipa.style(ipa):gsub("^%s*/", ""):gsub("/%s*$", "")
    if body == "" then return nil end
    for ch in body:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        if not IPA_CHARS[ch] then return nil end
    end
    local n_ipa, n_words = 0, 0
    for _ in body:gmatch("%S+") do n_ipa = n_ipa + 1 end
    for _ in (headword or ""):gmatch("%S+") do n_words = n_words + 1 end
    if n_ipa ~= n_words then return nil end
    return "/" .. body .. "/"
end

-- Final IPA for a card: dictionary first, else the model's if plausible, else "".
function Ipa.for_card(path, card)
    local parts = Ipa.headword_parts(path, card.headword, card.ipa)
    if parts then
        if card.pos == "phrasal verb" then parts = Ipa.phrasal_stress(parts) end
        return "/" .. table.concat(parts, " ") .. "/"
    end
    return Ipa.check_model(card.ipa, card.headword) or ""
end

return Ipa
