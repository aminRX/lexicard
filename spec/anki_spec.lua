local Json = require("lexicard_json")
local Anki = require("lexicard_anki")
local Config = require("lexicard_config")
local NoteType = require("lexicard_notetype")

local cfg = Config.from_values({ ANKICONNECT_URLS = "http://mac:8765", ANKICONNECT_API_KEY = "secret" })

-- Fake AnkiConnect: handlers[action](params) returns result, error.
local function fake_anki(handlers, opts)
    opts = opts or {}
    local calls = {}
    local transport = function(request)
        if opts.unreachable then return nil, "connection refused" end
        local req = Json.decode(request.body)
        calls[#calls + 1] = req
        local handler = handlers[req.action]
        if not handler then return 200, Json.encode({ result = Json.null, error = "unsupported action" }) end
        local result, err = handler(req.params)
        return 200, Json.encode({ result = result == nil and Json.null or result, error = err or Json.null })
    end
    return transport, calls
end

local function actions(calls)
    local list = {}
    for i, c in ipairs(calls) do list[i] = c.action end
    return list
end

local function happy(over)
    local h = {
        version = function() return 6 end,
        deckNames = function() return { "Default", "Reading vocabulary" } end,
        modelNames = function() return { "Basic", "Lexicard" } end,
        addNote = function() return 1791059962744 end,
        sync = function() return nil end,
        modelFieldNames = function() return NoteType.FIELDS end,
        modelStyling = function() return { css = NoteType.CSS } end,
    }
    for k, v in pairs(over or {}) do h[k] = v end
    return h
end

describe("Anki.request_body", function()
    it("wraps actions in the version 6 envelope with the API key", function()
        assert_same(Json.decode(Anki.request_body("deckNames", nil, "secret")),
            { action = "deckNames", version = 6, key = "secret" })
    end)
    it("omits an empty key", function()
        assert_eq(Json.decode(Anki.request_body("version", nil, "")).key, nil)
    end)
end)

describe("Anki.classify", function()
    it("separates ok, duplicates, errors and unreachable hosts", function()
        assert_eq((Anki.classify(nil, "timeout")), "unreachable")
        assert_eq((Anki.classify(200, '{"result":null,"error":"cannot create note because it is a duplicate"}')), "duplicate")
        assert_eq((Anki.classify(200, '{"result":null,"error":"valid api key must be provided"}')), "error")
        assert_eq((Anki.classify(500, "")), "error")
        local kind, result = Anki.classify(200, '{"result":6,"error":null}')
        assert_eq(kind, "ok")
        assert_eq(result, 6)
    end)
end)

describe("Anki.deliver", function()
    it("adds the note and syncs", function()
        local transport, calls = fake_anki(happy())
        assert_eq(Anki.deliver(transport, cfg, { fields = { Headword = "give up" } }).kind, "ok")
        assert_same(actions(calls), { "version", "deckNames", "modelNames", "modelFieldNames", "modelStyling", "addNote", "sync" })
        assert_eq(calls[1].key, "secret")
    end)
    it("creates the deck and note type when missing", function()
        local transport, calls = fake_anki(happy({
            deckNames = function() return { "Default" } end,
            modelNames = function() return { "Basic" } end,
            createDeck = function() return 1 end,
            createModel = function(params)
                assert_eq(params.modelName, "Lexicard")
                return { id = 1 }
            end,
        }))
        assert_eq(Anki.deliver(transport, cfg, {}).kind, "ok")
        assert_same(actions(calls), { "version", "deckNames", "createDeck", "modelNames", "createModel", "addNote", "sync" })
    end)
    it("reports duplicates without syncing", function()
        local transport, calls = fake_anki(happy({
            addNote = function() return nil, "cannot create note because it is a duplicate" end,
        }))
        assert_eq(Anki.deliver(transport, cfg, {}).kind, "duplicate")
        assert_eq(actions(calls)[#calls], "addNote")
    end)
    it("migrates an old note type: adds fields, then pushes templates and CSS", function()
        local old = { "Headword", "POS", "Pattern", "IPA", "Spanish", "Definition", "Context", "Example", "Cloze",
                      "Collocations", "Warning", "PronTip", "Book", "CEFR" }
        local added = {}
        local transport, calls = fake_anki(happy({
            modelFieldNames = function() return old end,
            modelFieldAdd = function(params) added[#added + 1] = params.fieldName return nil end,
            modelStyling = function() return { css = ".card {}" } end,
            updateModelTemplates = function() return nil end,
            updateModelStyling = function() return nil end,
        }))
        assert_eq(Anki.deliver(transport, cfg, {}).kind, "ok")
        assert_same(added, { "Register", "ContextOpen", "Audio" })
        local list = actions(calls)
        assert_eq(list[#list - 3], "updateModelTemplates")
        assert_eq(list[#list - 2], "updateModelStyling")
    end)
    it("reports unreachable when no URL answers", function()
        local transport = fake_anki(happy(), { unreachable = true })
        assert_eq(Anki.deliver(transport, cfg, {}).kind, "unreachable")
    end)
    it("reports a wrong API key as an error, not as unreachable", function()
        local transport = fake_anki({ version = function() return nil, "valid api key must be provided" end })
        local outcome = Anki.deliver(transport, cfg, {})
        assert_eq(outcome.kind, "error")
        assert_match(outcome.message, "api key")
    end)
end)

describe("Anki.deliver_many", function()
    it("sends in order, reports each item and syncs once", function()
        local transport, calls = fake_anki(happy({
            addNote = function(params)
                if params.note.fields.Headword == "bank" then return nil, "cannot create note because it is a duplicate" end
                return 1
            end,
        }))
        local report = Anki.deliver_many(transport, cfg, {
            { id = "a", note = { fields = { Headword = "give up" } } },
            { id = "b", note = { fields = { Headword = "bank" } } },
        })
        assert_eq(report.setup_error, nil)
        assert_same(report.outcomes, {
            { id = "a", kind = "ok" },
            { id = "b", kind = "duplicate", message = "cannot create note because it is a duplicate" },
        })
        assert_eq(actions(calls)[#calls], "sync")
    end)
    it("returns a setup error when Anki is unreachable", function()
        local report = Anki.deliver_many(fake_anki(happy(), { unreachable = true }), cfg, { { id = "a", note = {} } })
        assert_eq(report.setup_error.kind, "unreachable")
        assert_same(report.outcomes, {})
    end)
end)

describe("Anki.update_note_type and Anki.check", function()
    it("pushes templates and styling", function()
        local transport, calls = fake_anki(happy({
            updateModelTemplates = function(params)
                assert_eq(params.model.name, "Lexicard")
                return nil
            end,
            updateModelStyling = function() return nil end,
        }))
        assert_eq(Anki.update_note_type(transport, cfg).kind, "ok")
        assert_same(actions(calls), { "version", "deckNames", "modelNames", "modelFieldNames", "modelStyling", "updateModelTemplates", "updateModelStyling" })
    end)
    it("checks every URL", function()
        local results = Anki.check(fake_anki(happy()), cfg)
        assert_same(results, { { url = "http://mac:8765", kind = "ok", message = "AnkiConnect v6" } })
    end)
end)
