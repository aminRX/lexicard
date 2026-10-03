--[[
Turns a validated card into an AnkiConnect note, and into preview text.
Model text is escaped; only balanced <b></b> survives in Context and Example.
]]
local Note = {}

local function escape_html(s)
    return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end
Note.escape_html = escape_html

local function count(s, pattern)
    local n = 0
    for _ in s:gmatch(pattern) do n = n + 1 end
    return n
end

function Note.keep_bold(s)
    s = s:gsub("[\1\2]", "")
    s = s:gsub("<%s*[bB]%s*>", "\1"):gsub("<%s*/%s*[bB]%s*>", "\2")
    if count(s, "\1") ~= count(s, "\2") then s = s:gsub("[\1\2]", "") end
    s = escape_html(s)
    return (s:gsub("\1", "<b>"):gsub("\2", "</b>"))
end

-- Bolds the first candidate phrase found in text, unless text already has bold.
function Note.ensure_bold(text, candidates)
    local lower = text:lower()
    if lower:find("<b>", 1, true) then return text end
    for _, phrase in ipairs(candidates) do
        if phrase and phrase ~= "" then
            local i, j = lower:find(phrase:lower(), 1, true)
            if i then return text:sub(1, i - 1) .. "<b>" .. text:sub(i, j) .. "</b>" .. text:sub(j + 1) end
        end
    end
    return text
end

function Note.cloze(example_html)
    local cloze, n = example_html:gsub("<b>.-</b>", "_____", 1)
    if n == 0 then return "" end
    return cloze
end

function Note.pattern(card)
    local pattern = card.pattern or ""
    if pattern:lower() == (card.headword or ""):lower() then pattern = "" end
    local register = card.register or ""
    if register ~= "" and register ~= "neutral" then
        pattern = pattern ~= "" and (pattern .. " · " .. register) or register
    end
    return pattern
end

function Note.book_label(input)
    local title, author = input.book_title or "", input.book_author or ""
    if title ~= "" and author ~= "" then return title .. " — " .. author end
    return title
end

-- Cuts s to at most n bytes without splitting a UTF-8 character.
function Note.utf8_truncate(s, n)
    if #s <= n then return s end
    s = s:sub(1, n)
    local i = #s
    while i > 0 and s:byte(i) >= 0x80 and s:byte(i) < 0xC0 do i = i - 1 end
    if i > 0 and s:byte(i) >= 0xC0 then
        local lead = s:byte(i)
        local need = lead >= 0xF0 and 4 or (lead >= 0xE0 and 3 or 2)
        if #s - i + 1 < need then s = s:sub(1, i - 1) end
    end
    return s
end

function Note.slug(title)
    local slug = (title or ""):lower():gsub("[%s%p]+", "_"):gsub("^_+", ""):gsub("_+$", "")
    slug = Note.utf8_truncate(slug, 40):gsub("_+$", "")
    return slug
end

function Note.tags(card, input)
    local tags = { "lexicard" }
    local slug = Note.slug(input.book_title)
    if slug ~= "" then tags[#tags + 1] = "book::" .. slug end
    if (card.cefr or "") ~= "" then tags[#tags + 1] = "cefr::" .. card.cefr end
    return tags
end

local function strip_marks(s)
    return (s:gsub("⟦", ""):gsub("⟧", ""))
end

function Note.fields(card, input)
    local example = Note.keep_bold(Note.ensure_bold(card.example,
        { card.expression_in_text, card.headword, card.surface }))
    return {
        Headword = escape_html(card.headword),
        POS = escape_html(card.pos),
        Pattern = escape_html(Note.pattern(card)),
        IPA = escape_html(card.ipa),
        Spanish = escape_html(table.concat(card.spanish, " / ")),
        Definition = escape_html(card.definition),
        Context = Note.keep_bold(strip_marks(card.context)),
        Example = example,
        Cloze = Note.cloze(example),
        Collocations = escape_html(table.concat(card.collocations, " · ")),
        Warning = escape_html(card.warning),
        PronTip = escape_html(card.pron_tip),
        Book = escape_html(Note.book_label(input)),
        CEFR = escape_html(card.cefr),
    }
end

function Note.build(card, input, cfg, allow_duplicate)
    return {
        deckName = cfg.anki_deck,
        modelName = cfg.anki_note_type,
        fields = Note.fields(card, input),
        tags = Note.tags(card, input),
        options = {
            allowDuplicate = allow_duplicate == true,
            duplicateScope = "deck",
            duplicateScopeOptions = { deckName = cfg.anki_deck, checkChildren = false, checkAllModels = false },
        },
    }
end

local function plain(s)
    return strip_marks((s:gsub("</?[bB]>", "")))
end

function Note.preview_text(card, input, deck)
    local lines = {}
    local function add(s) lines[#lines + 1] = s end
    add(card.headword .. "   " .. card.ipa)
    local meta = { card.pos }
    local pattern = Note.pattern(card)
    if pattern ~= "" then meta[#meta + 1] = pattern end
    if card.cefr ~= "" then meta[#meta + 1] = card.cefr end
    add(table.concat(meta, " · "))
    add("")
    add(table.concat(card.spanish, " / "))
    add(card.definition)
    if card.warning ~= "" then
        add("")
        add("⚠ " .. card.warning)
    end
    add("")
    add("Example: " .. plain(card.example))
    if card.context ~= "" then add("Book: " .. plain(card.context)) end
    if #card.collocations > 0 then add("Collocations: " .. table.concat(card.collocations, " · ")) end
    if card.pron_tip ~= "" then add("Pronunciation: " .. card.pron_tip) end
    add("")
    add(("Saves 2 cards to “%s”."):format(deck))
    return table.concat(lines, "\n")
end

return Note
