--[[
Checks and repairs a card after Gemini, before the preview (pure).
]]
local Text = require("lexicard_text")
local Traps = require("lexicard_traps")

local Repair = {}

local INFLECTIONS = { "", "s", "es", "d", "ed", "ing", "ly" }

local function is_english_form(token, base)
    for _, suffix in ipairs(INFLECTIONS) do
        if token == base .. suffix then return true end
    end
    return false
end

-- True if the warning names a Spanish word that looks like the headword.
function Repair.names_lookalike(warning, headword)
    for _, token in ipairs(Text.words(warning)) do
        for _, base in ipairs(Text.content_words(headword)) do
            if #token >= 3 and not is_english_form(token, base) and Text.looks_alike(token, base) then
                return true
            end
        end
    end
    return false
end

-- Returns the warning to keep and its trap type.
function Repair.warning(card)
    local trap, warning = card.trap or "none", card.warning or ""
    local keep = false
    if warning ~= "" then
        if trap == "false_friend" then
            keep = Repair.names_lookalike(warning, card.headword)
        elseif trap == "preposition" then
            for _, w in ipairs(Text.words(warning)) do
                if Traps.PREPOSITIONS[w] then keep = true end
            end
        elseif trap == "register" then
            keep = (card.register or "") ~= "" and card.register ~= "neutral"
        elseif trap == "calque" or trap == "confusable" then
            keep = true
        end
    end
    if keep then return warning, trap end
    local fallback = Traps.false_friend_warning(card.headword)
    if fallback then return fallback, "false_friend" end
    fallback = Traps.confusable_warning(card.headword)
    if fallback then return fallback, "confusable" end
    return "", "none"
end

function Repair.spanish(card)
    local ff = Traps.false_friend(card.headword)
    local head = Text.fold(card.headword)
    local kept, folded_kept = {}, {}
    for _, item in ipairs(card.spanish or {}) do
        local f = Text.fold(item)
        local drop = f == "" or f == head or (ff ~= nil and f == Text.fold(ff.lookalike))
        if not drop and card.register ~= "slang" then
            for _, w in ipairs(Text.words(f)) do
                if Traps.VULGAR[w] then drop = true end
            end
        end
        if not drop then
            for _, k in ipairs(folded_kept) do
                if f == k or f:sub(1, #k + 1) == k .. " " or k:sub(1, #f + 1) == f .. " " then drop = true end
            end
        end
        if not drop then
            kept[#kept + 1] = item
            folded_kept[#folded_kept + 1] = f
        end
    end
    if #kept == 0 and card.spanish and card.spanish[1] then kept[1] = card.spanish[1] end
    return kept
end

function Repair.apply(card)
    card.warning, card.trap = Repair.warning(card)
    card.spanish = Repair.spanish(card)
    return card
end

return Repair
