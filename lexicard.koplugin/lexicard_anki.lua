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
        return Anki.call(transport, url, cfg, "createModel", NoteType.create_model_params(cfg.anki_note_type))
    end
    return Anki.migrate(transport, url, cfg)
end

-- Templates and CSS. An older reverse card ("Produce") stays for old notes but is no
-- longer made for new ones (see NoteType.retire_produce).
function Anki.push_note_type(transport, url, cfg)
    local name = cfg.anki_note_type
    local params = NoteType.update_templates_params(name)
    local kind, templates = Anki.call(transport, url, cfg, "modelTemplates", { modelName = name })
    if kind ~= "ok" then return kind, templates end
    local produce = type(templates) == "table" and templates.Produce
    if type(produce) == "table" and type(produce.Front) == "string" then
        local front = NoteType.retire_produce(produce.Front)
        if front then params.model.templates.Produce = { Front = front } end
    end
    kind, templates = Anki.call(transport, url, cfg, "updateModelTemplates", params)
    if kind ~= "ok" then return kind, templates end
    return Anki.call(transport, url, cfg, "updateModelStyling", NoteType.update_styling_params(name))
end

-- Brings an existing note type up to date: adds missing fields, and pushes templates
-- and CSS when fields were added or the CSS lacks the current version mark.
function Anki.migrate(transport, url, cfg)
    local name = cfg.anki_note_type
    local kind, fields = Anki.call(transport, url, cfg, "modelFieldNames", { modelName = name })
    if kind ~= "ok" then return kind, fields end
    local changed = false
    for _, field in ipairs(NoteType.FIELDS) do
        if not contains(fields, field) then
            local k, m = Anki.call(transport, url, cfg, "modelFieldAdd", { modelName = name, fieldName = field })
            if k ~= "ok" then return k, m end
            changed = true
        end
    end
    local styling
    kind, styling = Anki.call(transport, url, cfg, "modelStyling", { modelName = name })
    if kind ~= "ok" then return kind, styling end
    local css = type(styling) == "table" and tostring(styling.css or "") or ""
    if changed or not css:find(NoteType.VERSION_MARK, 1, true) then
        local k, m = Anki.push_note_type(transport, url, cfg)
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

-- Sends queued items ({id, note, media}) oldest first, stopping at the first unreachable.
-- prepare(item), called only once Anki answered, returns the note to send (with media) and
-- an info table copied into the outcome.
-- Returns {outcomes = {{id, kind, message, info}}, setup_error = {kind, message} or nil, sync_error = string or nil}.
function Anki.deliver_many(transport, cfg, items, prepare)
    local url, failure = connect(transport, cfg)
    if not url then return { outcomes = {}, setup_error = failure } end
    local outcomes, sent = {}, 0
    for _, item in ipairs(items) do
        local note, info = item.note, nil
        if prepare then note, info = prepare(item) end
        local kind, message = Anki.call(transport, url, cfg, "addNote", { note = note }, 30)
        outcomes[#outcomes + 1] = { id = item.id, kind = kind, message = kind ~= "ok" and tostring(message) or nil, info = info }
        if kind == "ok" then sent = sent + 1 end
        if kind == "unreachable" then break end
    end
    local report = { outcomes = outcomes }
    if sent > 0 then
        local sync_kind, sync_message = Anki.call(transport, url, cfg, "sync", nil, 30)
        if sync_kind ~= "ok" then report.sync_error = tostring(sync_message) end
    end
    return report
end

-- One note (scripts): {kind, message, sync_error}.
function Anki.deliver(transport, cfg, note)
    local report = Anki.deliver_many(transport, cfg, { { id = "1", note = note } })
    if report.setup_error then return report.setup_error end
    local outcome = report.outcomes[1]
    return { kind = outcome.kind, message = outcome.message, sync_error = report.sync_error }
end

function Anki.update_note_type(transport, cfg)
    local url, failure = connect(transport, cfg)
    if not url then return failure end
    local kind, message = Anki.push_note_type(transport, url, cfg)
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
