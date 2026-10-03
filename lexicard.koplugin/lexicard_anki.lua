--[[
AnkiConnect client (API version 6). Every public function returns plain
tables so it can run inside a KOReader subprocess.
Kinds: "ok", "duplicate", "unreachable", "error".
]]
local Json = require("lexicard_json")
local NoteType = require("lexicard_notetype")

local Anki = {}

function Anki.request_body(action, params, api_key)
    local req = { action = action, version = 6 }
    if params ~= nil then req.params = params end
    if api_key and api_key ~= "" then req.key = api_key end
    return Json.encode(req)
end

function Anki.classify(code, body)
    if type(code) ~= "number" then return "unreachable", tostring(body) end
    if code ~= 200 then return "error", "HTTP " .. code end
    local data = Json.decode(body or "")
    if type(data) ~= "table" then return "error", "invalid reply from AnkiConnect" end
    if type(data.error) == "string" and data.error ~= "" then
        if data.error:lower():find("duplicate", 1, true) then return "duplicate", data.error end
        return "error", data.error
    end
    return "ok", data.result
end

function Anki.call(transport, url, cfg, action, params, timeout)
    local code, body = transport({
        method = "POST",
        url = url,
        headers = { ["Content-Type"] = "application/json" },
        body = Anki.request_body(action, params, cfg.ankiconnect_api_key),
        block_timeout = timeout or 5,
        total_timeout = timeout or 15,
    })
    return Anki.classify(code, body)
end

local function contains(list, value)
    if type(list) ~= "table" then return false end
    for _, item in ipairs(list) do
        if item == value then return true end
    end
    return false
end

-- The first URL whose AnkiConnect answers, or nil, kind, message.
function Anki.find_url(transport, cfg)
    local kind, message = "unreachable", "no AnkiConnect URL configured"
    for _, url in ipairs(cfg.ankiconnect_urls) do
        local k, result = Anki.call(transport, url, cfg, "version", nil, 3)
        if k == "ok" then return url end
        kind, message = k, tostring(result)
        if k == "error" then return nil, kind, message end
    end
    return nil, kind, message
end

-- Creates the deck and the note type if they are missing.
function Anki.ensure_setup(transport, url, cfg)
    local kind, decks = Anki.call(transport, url, cfg, "deckNames")
    if kind ~= "ok" then return kind, decks end
    if not contains(decks, cfg.anki_deck) then
        local k, m = Anki.call(transport, url, cfg, "createDeck", { deck = cfg.anki_deck })
        if k ~= "ok" then return k, m end
    end
    local models
    kind, models = Anki.call(transport, url, cfg, "modelNames")
    if kind ~= "ok" then return kind, models end
    if not contains(models, cfg.anki_note_type) then
        local k, m = Anki.call(transport, url, cfg, "createModel", NoteType.create_model_params(cfg.anki_note_type))
        if k ~= "ok" then return k, m end
    end
    return "ok"
end

local function connect(transport, cfg)
    local url, kind, message = Anki.find_url(transport, cfg)
    if not url then return nil, { kind = kind, message = message } end
    local k, m = Anki.ensure_setup(transport, url, cfg)
    if k ~= "ok" then return nil, { kind = k, message = tostring(m) } end
    return url
end

-- Sends one note, then syncs. Returns {kind, message}.
function Anki.deliver(transport, cfg, note)
    local url, failure = connect(transport, cfg)
    if not url then return failure end
    local kind, message = Anki.call(transport, url, cfg, "addNote", { note = note })
    if kind ~= "ok" then return { kind = kind, message = tostring(message) } end
    Anki.call(transport, url, cfg, "sync", nil, 30)
    return { kind = "ok" }
end

-- Sends queued items ({id, note}) oldest first, stopping at the first unreachable.
-- Returns {outcomes = {{id, kind, message}}, setup_error = {kind, message} or nil}.
function Anki.deliver_many(transport, cfg, items)
    local url, failure = connect(transport, cfg)
    if not url then return { outcomes = {}, setup_error = failure } end
    local outcomes, sent = {}, 0
    for _, item in ipairs(items) do
        local kind, message = Anki.call(transport, url, cfg, "addNote", { note = item.note })
        outcomes[#outcomes + 1] = { id = item.id, kind = kind, message = kind ~= "ok" and tostring(message) or nil }
        if kind == "ok" then sent = sent + 1 end
        if kind == "unreachable" then break end
    end
    if sent > 0 then Anki.call(transport, url, cfg, "sync", nil, 30) end
    return { outcomes = outcomes }
end

function Anki.update_note_type(transport, cfg)
    local url, failure = connect(transport, cfg)
    if not url then return failure end
    local kind, message = Anki.call(transport, url, cfg, "updateModelTemplates",
        NoteType.update_templates_params(cfg.anki_note_type))
    if kind ~= "ok" then return { kind = kind, message = tostring(message) } end
    kind, message = Anki.call(transport, url, cfg, "updateModelStyling",
        NoteType.update_styling_params(cfg.anki_note_type))
    if kind ~= "ok" then return { kind = kind, message = tostring(message) } end
    return { kind = "ok" }
end

function Anki.check(transport, cfg)
    local results = {}
    for _, url in ipairs(cfg.ankiconnect_urls) do
        local kind, result = Anki.call(transport, url, cfg, "version", nil, 3)
        results[#results + 1] = {
            url = url,
            kind = kind,
            message = kind == "ok" and ("AnkiConnect v" .. tostring(result)) or tostring(result),
        }
    end
    return results
end

return Anki
