--[[
Small text helpers shared by the checks and repairs (pure).
]]
local Text = {}

local ACCENTS = {
    ["á"] = "a", ["é"] = "e", ["í"] = "i", ["ó"] = "o", ["ú"] = "u", ["ü"] = "u", ["ñ"] = "n",
    ["Á"] = "a", ["É"] = "e", ["Í"] = "i", ["Ó"] = "o", ["Ú"] = "u", ["Ü"] = "u", ["Ñ"] = "n",
}

function Text.strip_tags(s)
    return ((s or ""):gsub("<[^>]*>", ""))
end

function Text.strip_marks(s)
    return ((s or ""):gsub("⟦", ""):gsub("⟧", ""))
end

-- Lowercase, Spanish accents removed, trimmed.
function Text.fold(s)
    local out = (s or ""):gsub("\195[\128-\191]", function(ch) return ACCENTS[ch] or ch end)
    return (out:lower():gsub("^%s+", ""):gsub("%s+$", ""))
end

function Text.words(s)
    local list = {}
    for w in Text.fold(Text.strip_tags(Text.strip_marks(s))):gmatch("[%w']+") do list[#list + 1] = w end
    return list
end

local STOP = {}
for w in ([[a an the to of in on at for with by from up down out off over away back about into onto
    and or but is are was were be been it its this that these those i you he she we they me him her us them
    my your his our their sth sb someone something somebody one]]):gmatch("%S+") do
    STOP[w] = true
end

function Text.content_words(s)
    local list = {}
    for _, w in ipairs(Text.words(s)) do
        if not STOP[w] then list[#list + 1] = w end
    end
    return list
end

local SUFFIXES = { "", "s", "es", "ed", "d", "ing", "er", "ers", "ly", "ness", "ment", "ful", "less" }

-- True if `word` looks like a form of `base` ("reluctantly" of "reluctant", "running" of "run").
function Text.same_family(word, base)
    if #base >= 5 then
        local stem = base:sub(1, math.max(4, #base - 3))
        return #word >= #base - 2 and word:sub(1, #stem) == stem
    end
    for _, suffix in ipairs(SUFFIXES) do
        if word == base .. suffix then return true end
    end
    local doubled = base .. base:sub(-1)
    return word == doubled .. "ing" or word == doubled .. "ed" or word == doubled .. "er"
end

-- True if `text` uses a word from the family of any content word of `headword`.
function Text.mentions(text, headword)
    local bases = Text.content_words(headword)
    for _, w in ipairs(Text.words(text)) do
        for _, base in ipairs(bases) do
            if Text.same_family(w, base) then return true end
        end
    end
    return false
end

-- Share of a's content words that also appear in b (0..1). Words of `ignore` (the headword,
-- in any regular form) don't count, so only the rest of a sentence can copy the book.
function Text.overlap(a, b, ignore)
    local skip = Text.content_words(ignore or "")
    local wa, seen = {}, {}
    for _, w in ipairs(Text.content_words(a)) do
        local keep = true
        for _, base in ipairs(skip) do
            if Text.same_family(w, base) then keep = false end
        end
        if keep then wa[#wa + 1] = w end
    end
    if #wa == 0 then return 0 end
    for _, w in ipairs(Text.content_words(b)) do seen[w] = true end
    local shared = 0
    for _, w in ipairs(wa) do
        if seen[w] then shared = shared + 1 end
    end
    return shared / #wa
end

local function chars(s)
    local list = {}
    for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do list[#list + 1] = ch end
    return list
end

-- Edit distance between two UTF-8 strings, counted in characters.
function Text.distance(a, b)
    local x, y = chars(a), chars(b)
    local prev = {}
    for j = 0, #y do prev[j] = j end
    for i = 1, #x do
        local cur = { [0] = i }
        for j = 1, #y do
            local cost = x[i] == y[j] and 0 or 1
            cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
        end
        prev = cur
    end
    return prev[#y]
end

-- English spelling nudged toward Spanish so cognates line up (sympathetic → simpatetic).
local function hispanize(s)
    s = Text.fold(s):gsub("ph", "f"):gsub("th", "t"):gsub("y", "i"):gsub("ck", "c")
    return (s:gsub("(%a)%1", "%1"))
end

local function prefix_len(a, b)
    local n = 0
    for i = 1, math.min(#a, #b) do
        if a:sub(i, i) ~= b:sub(i, i) then break end
        n = i
    end
    return n
end

-- True if a Spanish word looks like an English one (a possible false friend).
function Text.looks_alike(spanish, english)
    local a, b = hispanize(spanish), hispanize(english)
    if prefix_len(a, b) >= 4 then return true end
    return 1 - Text.distance(a, b) / math.max(#a, #b, 1) >= 0.6
end

return Text
