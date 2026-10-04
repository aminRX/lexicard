-- Automatic quality checks on a finished card, used by the prompt evaluation.
local Text = require("lexicard_text")

local Checks = {}

local function norm(s)
    local out = Text.fold(Text.strip_tags(s or "")):gsub("^the ", ""):gsub("^an? ", "")
    return out
end

local function as_list(v)
    if type(v) == "table" then return v end
    return { v }
end

-- Capitalized words of the book sentence, except its first word and "I": likely names.
local function book_names(sentence)
    local names, first = {}, true
    for word in Text.strip_marks(sentence or ""):gmatch("[%a']+") do
        if not first and word:match("^%u") and word ~= "I" then names[word:lower()] = true end
        first = false
    end
    return names
end

local function mentions_any(text, names)
    for _, w in ipairs(Text.words(text)) do
        if names[w] then return true end
    end
    return false
end

function Checks.run(case, result)
    local out = {}
    local function add(name, ok, detail)
        out[#out + 1] = { name = name, ok = ok and true or false, detail = detail and tostring(detail) or "" }
    end
    local expect = case.expect or {}
    if expect.status and expect.status ~= "ok" then
        add("status", result.kind == "not_a_word" and result.status == expect.status, result.status or result.kind)
        return out
    end
    add("ok", result.ok == true, result.ok and "" or result.kind)
    local card = result.card
    if not result.ok or not card then return out end

    if expect.headword then
        local got, hit = norm(card.headword), false
        for _, h in ipairs(as_list(expect.headword)) do
            if norm(h) == got then hit = true end
        end
        add("headword", hit, got)
    end
    add("definition_no_headword", not Text.mentions(card.definition, card.headword), card.definition)
    add("definition_short", #Text.words(card.definition) <= 15, #Text.words(card.definition) .. " words")
    add("usage_count", #card.usage >= 2 and #card.usage <= 3, #card.usage .. " patterns")
    local long, plain_example, worst = nil, nil, 0
    local sentence = Text.strip_marks(case.sentence or "")
    for _, item in ipairs(card.usage) do
        if #Text.words(item.example) > 12 then long = item.example end
        if not item.example:find("<b>", 1, true) then plain_example = item.example end
        if sentence ~= "" then worst = math.max(worst, Text.overlap(item.example, sentence)) end
    end
    add("usage_short", long == nil, long)
    add("usage_bold", plain_example == nil, plain_example)
    if sentence ~= "" then add("example_new", worst <= 0.5, ("overlap %.2f"):format(worst)) end
    local names = book_names(case.sentence)
    local leaked = false
    for _, item in ipairs(card.usage) do leaked = leaked or mentions_any(item.example, names) end
    leaked = leaked or mentions_any(card.picture_scene or "", names) or mentions_any(card.picture_caption or "", names)
    add("no_book_names", not leaked)
    local spanish = {}
    for _, item in ipairs(card.spanish or {}) do spanish[#spanish + 1] = Text.fold(item) end
    local dupes = false
    for i = 1, #spanish do
        for j = i + 1, #spanish do
            local a, b = spanish[i], spanish[j]
            if a == b or a:sub(1, #b + 1) == b .. " " or b:sub(1, #a + 1) == a .. " " then dupes = true end
        end
    end
    add("spanish_clean", not dupes and #spanish > 0, table.concat(card.spanish or {}, " / "))
    if expect.trap and expect.trap ~= "any" then
        local has = (card.warning or "") ~= ""
        add("warning_" .. expect.trap, (expect.trap == "none") == (not has), card.warning)
    end
    local ipa = (card.ipa or ""):gsub("/", "")
    local n_ipa = 0
    for _ in ipa:gmatch("%S+") do n_ipa = n_ipa + 1 end
    add("ipa_words", ipa == "" or n_ipa == #Text.words(card.headword), card.ipa)
    local scene_words = #Text.words(card.picture_scene or "")
    add("picture_scene", scene_words > 0 and scene_words <= 70, scene_words .. " words")
    local caption = card.picture_caption or ""
    add("caption_short", #Text.words(caption) <= 10 and caption:find("<b>", 1, true) ~= nil, caption)
    return out
end

return Checks
