--[[
Gemini client: tries the primary model, then the fallback, and returns a plain
table (strings, numbers, booleans and string lists only) so it can cross the
KOReader subprocess boundary.
]]
local Json = require("lexicard_json")
local Prompt = require("lexicard_prompt")
local Text = require("lexicard_text")

local Gemini = {}

Gemini.BASE_URL = "https://generativelanguage.googleapis.com/v1beta/models/"

local TEXT_FIELDS = { "expression_in_text", "headword", "pos", "sense", "ipa", "pattern", "register",
                      "definition", "trap", "warning", "sound", "pron_tip", "example" }
local REQUIRED = { "headword", "definition", "example" }
local STATUS_KINDS = { [408] = "busy", [429] = "quota", [500] = "busy", [502] = "busy", [503] = "busy", [504] = "busy" }

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Card table from the model's JSON object, or nil plus a reason.
function Gemini.normalize(raw)
    if type(raw) ~= "table" then return nil, "reply is not a JSON object" end
    local card = { status = type(raw.status) == "string" and raw.status or "" }
    for _, key in ipairs(TEXT_FIELDS) do
        card[key] = type(raw[key]) == "string" and trim(raw[key]) or ""
    end
    local function list(key, max)
        local out = {}
        if type(raw[key]) == "table" then
            for _, item in ipairs(raw[key]) do
                if type(item) == "string" and trim(item) ~= "" and #out < max then out[#out + 1] = trim(item) end
            end
        end
        return out
    end
    card.spanish = list("spanish", 3)
    card.collocations = list("collocations", 3)
    if card.trap == "" then card.trap = "none" end
    if card.sound == "" then card.sound = "none" end
    if card.status ~= "ok" then return card end
    for _, key in ipairs(REQUIRED) do
        if card[key] == "" then return nil, "missing " .. key end
    end
    if #card.spanish == 0 then return nil, "missing spanish" end
    return card
end

-- A reason to ask the other model, or nil.
function Gemini.quality_problem(card, input)
    if Text.mentions(card.definition, card.headword) then return "definition uses the headword" end
    local sentence = Text.strip_marks(input.sentence or "")
    if sentence ~= "" and Text.overlap(card.example, sentence) > 0.5 then return "example copies the book" end
    return nil
end

-- The model's text from a generateContent reply, or nil plus a reason.
function Gemini.reply_text(data)
    local candidates = type(data) == "table" and data.candidates
    local candidate = type(candidates) == "table" and candidates[1]
    if type(candidate) ~= "table" then
        local feedback = type(data) == "table" and data.promptFeedback
        local block = type(feedback) == "table" and feedback.blockReason
        return nil, block and ("blocked: " .. tostring(block)) or "no candidates"
    end
    local parts = type(candidate.content) == "table" and candidate.content.parts
    local texts = {}
    if type(parts) == "table" then
        for _, part in ipairs(parts) do
            if type(part) == "table" and part.thought ~= true and type(part.text) == "string" then
                texts[#texts + 1] = part.text
            end
        end
    end
    if #texts == 0 then return nil, "empty reply (" .. tostring(candidate.finishReason) .. ")" end
    return table.concat(texts)
end

local function api_message(body)
    local data = Json.decode(body or "")
    if type(data) == "table" and type(data.error) == "table" and type(data.error.message) == "string" then
        return data.error.message
    end
    return tostring(body or ""):sub(1, 200)
end

-- One HTTP outcome → result table. `retry` says whether the fallback model is worth trying.
function Gemini.interpret(code, body)
    if type(code) ~= "number" then
        local err = tostring(body)
        local kind = err:lower():find("certificate", 1, true) and "tls" or "network"
        return { ok = false, retry = kind == "network", kind = kind, message = err }
    end
    if code == 401 or code == 403 then
        return { ok = false, retry = false, kind = "auth", message = api_message(body) }
    end
    if code ~= 200 then
        return { ok = false, retry = true, kind = STATUS_KINDS[code] or "http", code = code, message = api_message(body) }
    end
    local text, why = Gemini.reply_text(Json.decode(body))
    if not text then return { ok = false, retry = true, kind = "invalid", message = why } end
    local card, reason = Gemini.normalize(Json.decode(text))
    if not card then return { ok = false, retry = true, kind = "invalid", message = reason } end
    if card.status ~= "ok" then
        return { ok = false, retry = false, kind = "not_a_word", status = card.status }
    end
    return { ok = true, card = card }
end

function Gemini.generate(cfg, input, transport)
    local attempts = {
        { model = cfg.gemini_model, thinking = (cfg.gemini_thinking or "") ~= "" and cfg.gemini_thinking or nil },
        { model = cfg.gemini_fallback_model, thinking = "low" },
    }
    local result, first_ok
    for _, attempt in ipairs(attempts) do
        if attempt.model and attempt.model ~= "" then
            local code, body = transport({
                method = "POST",
                url = Gemini.BASE_URL .. attempt.model .. ":generateContent",
                headers = { ["Content-Type"] = "application/json", ["x-goog-api-key"] = cfg.gemini_api_key },
                body = Prompt.build_body(cfg, input, attempt.thinking),
                block_timeout = 10,
                total_timeout = 30,
            })
            result = Gemini.interpret(code, body)
            result.model = attempt.model
            if result.ok then
                result.problem = Gemini.quality_problem(result.card, input)
                if not result.problem then return result end
                first_ok = first_ok or result
            elseif not result.retry then
                return first_ok or result
            end
        end
    end
    return first_ok or result or { ok = false, kind = "http", message = "no Gemini model configured" }
end

-- Cheap reachability and key check: fetches the primary model's description.
function Gemini.check(cfg, transport)
    local code, body = transport({
        method = "GET",
        url = Gemini.BASE_URL .. cfg.gemini_model,
        headers = { ["x-goog-api-key"] = cfg.gemini_api_key },
        block_timeout = 10,
        total_timeout = 15,
    })
    if code == 200 then return { ok = true } end
    return Gemini.interpret(code, body)
end

return Gemini
