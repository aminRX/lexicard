--[[
Builds Gemini's input from what KOReader knows about a held word.
cut_sentence and clean_word are pure; from_popup only reads KOReader tables.
]]
local Context = {}

local ENDERS = { ".", "!", "?", "\226\128\166" }                    -- . ! ? …
local CLOSERS = { '"', "'", ")", "\226\128\157", "\226\128\153" }  -- " ' ) ” ’
local QUOTES = { "\226\128\156", "\226\128\157", "\226\128\152", "\226\128\153" } -- “ ” ‘ ’

local function token_at(s, i, tokens)
    for _, token in ipairs(tokens) do
        if s:sub(i, i + #token - 1) == token then return #token end
    end
end

-- Index just past the first sentence end at or after `from` (ender plus closing quotes), or nil.
local function sentence_end(s, from)
    local i = from
    while i <= #s do
        local n = token_at(s, i, ENDERS)
        if n then
            local j = i + n
            while true do
                local c = token_at(s, j, CLOSERS)
                if not c then break end
                j = j + c
            end
            if j > #s or s:sub(j, j):match("%s") then return j end
            i = j
        else
            i = i + 1
        end
    end
end

local function last_sentence_start(s)
    local start, i = 1, 1
    while true do
        local j = sentence_end(s, i)
        if not j then break end
        start, i = j, j
        if j > #s then break end
    end
    return start
end

local function words(s)
    local list = {}
    for w in s:gmatch("%S+") do list[#list + 1] = w end
    return list
end

-- The held word inside its sentence, marked ⟦like this⟧.
function Context.cut_sentence(prev, word, nxt, max_side_words)
    max_side_words = max_side_words or 30
    prev = (prev or ""):match("([^\n]*)$")
    nxt = (nxt or ""):match("^([^\n]*)")
    prev = prev:sub(last_sentence_start(prev))
    local stop = sentence_end(nxt, 1)
    if stop then nxt = nxt:sub(1, stop - 1) end
    prev = prev:gsub("%s+", " ")
    nxt = nxt:gsub("%s+", " ")
    local before = words(prev)
    if #before > max_side_words then
        prev = "… " .. table.concat(before, " ", #before - max_side_words + 1) .. (prev:match("%s$") and " " or "")
    end
    local after = words(nxt)
    if #after > max_side_words then
        nxt = (nxt:match("^%s") and " " or "") .. table.concat(after, " ", 1, max_side_words) .. " …"
    end
    return prev:gsub("^%s+", "") .. "⟦" .. word .. "⟧" .. nxt:gsub("%s+$", "")
end

function Context.clean_word(word)
    local s = (word or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local changed = true
    while changed and s ~= "" do
        changed = false
        local stripped = s:gsub("^%p+", ""):gsub("%p+$", "")
        if stripped ~= s then s, changed = stripped, true end
        for _, q in ipairs(QUOTES) do
            if s:sub(1, #q) == q then s, changed = s:sub(#q + 1), true end
            if #s >= #q and s:sub(-#q) == q then s, changed = s:sub(1, -#q - 1), true end
        end
    end
    return s
end

-- Reads everything Gemini needs. Call it before closing the dictionary popup.
function Context.from_popup(ui, popup)
    local word = Context.clean_word(popup.word or popup.lookupword or "")
    local prev, nxt
    local highlight = ui.highlight
    if highlight and highlight.selected_text and highlight.getSelectedWordContext then
        local ok, p, n = pcall(highlight.getSelectedWordContext, highlight, 40)
        if ok then prev, nxt = p, n end
    end
    local sentence = ""
    if (prev and prev ~= "") or (nxt and nxt ~= "") then
        sentence = Context.cut_sentence(prev, word, nxt)
    end
    local props = ui.doc_props or {}
    local authors = (props.authors or ""):gsub("\n", ", ")
    return {
        word = word,
        sentence = sentence,
        book_title = props.display_title or props.title or "",
        book_author = authors,
    }
end

return Context
