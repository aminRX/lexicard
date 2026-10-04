--[[
Turns a finished card into a text-only AnkiConnect note, and into preview text.
Model text is escaped; only balanced <b></b> survives in Context, Usage and Caption.
The book sentence comes from KOReader, not from the model. Audio and pictures are
attached when the note is sent (lexicard_media).
]]
local Text = require("lexicard_text")

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

function Note.register(card)
    local register = card.register or ""
    if register == "neutral" then return "" end
    return register
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
    return tags
end

-- The book sentence with the expression in bold, everything else escaped.
function Note.context_html(sentence, expression, word)
    if (sentence or "") == "" then return "" end
    local marker = sentence:find("⟦", 1, true)
    local plain = Text.strip_marks(sentence)
    local lower = plain:lower()
    local i, j
    if (expression or "") ~= "" then
        i, j = lower:find(expression:lower(), math.max(1, (marker or 1) - 40), true)
        if not i then i, j = lower:find(expression:lower(), 1, true) end
    end
    if not i and marker then i, j = marker, marker + #(word or "") - 1 end
    if not i then return escape_html(plain) end
    return escape_html(plain:sub(1, i - 1)) .. "<b>" .. escape_html(plain:sub(i, j)) .. "</b>"
        .. escape_html(plain:sub(j + 1))
end

local function bold_expression(text, card, input)
    return Note.keep_bold(Note.ensure_bold(text, { card.expression_in_text, card.headword, input.word }))
end

-- One line per usage pattern: '<div class="lx-use"><span class="lx-pattern">…</span> <span class="lx-ex">…</span></div>'.
function Note.usage_html(card, input)
    local lines = {}
    for _, item in ipairs(card.usage or {}) do
        local pattern = escape_html(item.pattern or "")
        lines[#lines + 1] = '<div class="lx-use">'
            .. (pattern ~= "" and ('<span class="lx-pattern">' .. pattern .. "</span> ") or "")
            .. '<span class="lx-ex">' .. bold_expression(item.example, card, input) .. "</span></div>"
    end
    return table.concat(lines, "\n")
end

function Note.fields(card, input)
    local caption = card.picture_caption or ""
    return {
        Headword = escape_html(card.headword),
        IPA = escape_html(card.ipa or ""),
        POS = escape_html(card.pos),
        Register = escape_html(Note.register(card)),
        Spanish = escape_html(table.concat(card.spanish, " / ")),
        Definition = escape_html(card.definition),
        Usage = Note.usage_html(card, input),
        Image = "",
        Caption = caption ~= "" and bold_expression(caption, card, input) or "",
        Audio = "",
        Warning = escape_html(card.warning or ""),
        Context = Note.context_html(input.sentence, card.expression_in_text, input.word),
        Book = escape_html(Note.book_label(input)),
    }
end

-- The note without media: audio and picture are added when it is sent (lexicard_media).
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
    return Text.strip_marks(Text.strip_tags(s))
end

local FORMAT_LABEL = { before_after = " (before → after)", contrast = " (contrast)" }

function Note.preview_text(card, input, deck, with_picture)
    local lines = {}
    local function add(s) lines[#lines + 1] = s end
    add(card.headword .. "   " .. (card.ipa or ""))
    local meta = { card.pos }
    if Note.register(card) ~= "" then meta[#meta + 1] = Note.register(card) end
    add(table.concat(meta, " · "))
    add("")
    add(table.concat(card.spanish, " / "))
    add(card.definition)
    if #(card.usage or {}) > 0 then
        add("")
        add("How to use it:")
        for _, item in ipairs(card.usage) do
            add("• " .. ((item.pattern or "") ~= "" and (item.pattern .. " — ") or "") .. plain(item.example))
        end
    end
    if (card.warning or "") ~= "" then
        add("")
        add("⚠ " .. card.warning)
    end
    add("")
    if with_picture and (card.picture_scene or "") ~= "" then
        add("Picture" .. (FORMAT_LABEL[card.picture_format] or "") .. ": " .. card.picture_scene)
    end
    if (card.picture_caption or "") ~= "" then add("Caption: " .. plain(card.picture_caption)) end
    if (input.sentence or "") ~= "" then add("Book: " .. plain(input.sentence)) end
    add("")
    add(("Saves 1 card to “%s”."):format(deck))
    return table.concat(lines, "\n")
end

return Note
