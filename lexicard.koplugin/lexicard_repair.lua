--[[
Checks and repairs a card after Gemini, before the preview (pure).
Run it after the IPA is final: the pronunciation-tip check compares against it.
]]
local Ipa = require("lexicard_ipa")
local Text = require("lexicard_text")
local Traps = require("lexicard_traps")

local Repair = {}

local INFLECTIONS = { "", "s", "es", "d", "ed", "ing", "ly" }
local SPELLING = { "letra", "doble", "se escribe", "escrit", "ortograf" }

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

function Repair.pron_tip(card)
    local sound, tip = card.sound or "none", card.pron_tip or ""
    if sound == "none" or sound == "" or tip == "" then return "" end
    local folded = Text.fold(tip)
    for _, cue in ipairs(SPELLING) do
        if folded:find(cue, 1, true) then return "" end
    end
    if sound == "ed_ending" then
        local surface, head = Text.fold(card.surface or ""), Text.fold(card.headword or "")
        if surface:sub(-2) ~= "ed" and head:sub(-2) ~= "ed" then return "" end
    end
    local ipa = Ipa.normalize(card.ipa or ""):gsub("%s", "")
    local found = false
    for segment in tip:gmatch("/([^/]+)/") do
        local seg = Ipa.normalize(segment):gsub("%s", "")
        if seg ~= "" and ipa:find(seg, 1, true) then found = true end
    end
    if not found then return "" end
    return tip
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
    card.pron_tip = Repair.pron_tip(card)
    card.spanish = Repair.spanish(card)
    return card
end

return Repair
