--[[
CMUdict ARPAbet → General American IPA (build time only).
Stress marks go before the stressed syllable's onset (maximal-onset rule).
One-syllable words get no stress mark.
]]
local Arpabet = {}

local VOWELS = { AA = "ɑ", AE = "æ", AO = "ɔ", AW = "aʊ", AY = "aɪ", EH = "ɛ", EY = "eɪ", IH = "ɪ", IY = "i",
                 OW = "oʊ", OY = "ɔɪ", UH = "ʊ", UW = "u" }
local CONSONANTS = { B = "b", CH = "tʃ", D = "d", DH = "ð", F = "f", G = "ɡ", HH = "h", JH = "dʒ", K = "k",
                     L = "l", M = "m", N = "n", NG = "ŋ", P = "p", R = "r", S = "s", SH = "ʃ", T = "t",
                     TH = "θ", V = "v", W = "w", Y = "j", Z = "z", ZH = "ʒ" }

local ONSETS = {}
for _, cluster in ipairs({
    "P R", "P L", "B R", "B L", "T R", "D R", "K R", "K L", "G R", "G L", "F R", "F L", "TH R", "SH R",
    "S P", "S T", "S K", "S M", "S N", "S L", "S W", "S F", "T W", "D W", "K W", "G W", "TH W",
    "P Y", "B Y", "F Y", "V Y", "K Y", "G Y", "M Y", "HH Y",
    "S P R", "S P L", "S T R", "S K R", "S K W", "S K Y", "S P Y",
}) do ONSETS[cluster] = true end

local function symbol(unit)
    if unit.vowel then
        if unit.base == "AH" then return unit.stress == 0 and "ə" or "ʌ" end
        if unit.base == "ER" then return unit.stress == 0 and "ɚ" or "ɝ" end
        return VOWELS[unit.base]
    end
    return CONSONANTS[unit.base]
end

local function is_onset(units, first, last)
    local names = {}
    for i = first, last do names[#names + 1] = units[i].base end
    if #names == 1 then return names[1] ~= "NG" end
    return ONSETS[table.concat(names, " ")] == true
end

function Arpabet.to_ipa(arpabet)
    local units = {}
    for phone in arpabet:gmatch("%S+") do
        local base, stress = phone:match("^(%u+)([012])$")
        local unit = base and { vowel = true, base = base, stress = tonumber(stress) }
            or { vowel = false, base = phone }
        if not symbol(unit) then return nil end
        units[#units + 1] = unit
    end
    if #units == 0 then return nil end
    local vowels = {}
    for i, unit in ipairs(units) do
        if unit.vowel then vowels[#vowels + 1] = i end
    end
    local marks = {}
    if #vowels > 1 then
        for n, vi in ipairs(vowels) do
            local stress = units[vi].stress
            if stress == 1 or stress == 2 then
                local start = vi
                if n == 1 then
                    start = 1
                else
                    for s = vowels[n - 1] + 1, vi - 1 do
                        if is_onset(units, s, vi - 1) then
                            start = s
                            break
                        end
                    end
                end
                marks[start] = stress == 1 and "ˈ" or "ˌ"
            end
        end
    end
    local out = {}
    for i, unit in ipairs(units) do
        if marks[i] then out[#out + 1] = marks[i] end
        out[#out + 1] = symbol(unit)
    end
    return table.concat(out)
end

return Arpabet
