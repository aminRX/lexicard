local Fake = require("fake_koreader")
local Json = require("lexicard_json")

local CARD = {
    status = "ok", expression_in_text = "gave it up", headword = "give up", pos = "phrasal verb",
    sense = "stopped", ipa = "/ˌɡɪv ˈʌp/", pattern = "give sth up", register = "neutral",
    definition = "to stop doing something", spanish = { "dejar" }, trap = "none", warning = "",
    sound = "none", pron_tip = "", example = "He <b>gave up</b> coffee.", collocations = {},
}

local function transport_for(state)
    return function(request)
        if request.url:find("%-tts:generateContent") then
            if state.tts_down then return 500, "{}" end
            return 200, Json.encode({ candidates = { { content = { parts = {
                { inlineData = { mimeType = "audio/wav", data = "UklGRg==" } } } } } } })
        end
        if request.url:find("generativelanguage", 1, true) then
            local text = Json.encode(state.card or CARD)
            return 200, Json.encode({ candidates = { { content = { parts = { { text = text } } } } } })
        end
        if state.anki_down then return nil, "connection refused" end
        local req = Json.decode(request.body)
        state.actions[#state.actions + 1] = req.action
        if req.action == "addNote" then
            if state.duplicate and not req.params.note.options.allowDuplicate then
                return 200, Json.encode({ result = Json.null, error = "cannot create note because it is a duplicate" })
            end
            state.notes[#state.notes + 1] = req.params.note
        end
        local NoteType = require("lexicard_notetype")
        local results = { version = 6, deckNames = { "Reading vocabulary" }, modelNames = { "Lexicard" }, addNote = 1,
                          modelFieldNames = NoteType.FIELDS, modelStyling = { css = NoteType.CSS } }
        return 200, Json.encode({ result = results[req.action] or Json.null, error = Json.null })
    end
end

local Lexicard = dofile("lexicard.koplugin/main.lua")

local function setup(state, opts)
    opts = opts or {}
    state.actions, state.notes = {}, {}
    local dir = os.tmpname()
    os.remove(dir)
    os.execute("mkdir -p '" .. dir .. "'")
    local f = assert(io.open(dir .. "/.env", "w"))
    f:write(opts.env or "GEMINI_API_KEY=test-key\nANKICONNECT_URLS=http://mac:8765\n")
    f:close()
    Fake.reset({ settings_dir = dir, transport = transport_for(state), connected = opts.connected })
    local ui = Fake.ui()
    local plugin = Lexicard:new{ ui = ui, path = dir }
    return plugin, ui
end

local function hold_and_save(ui, word)
    ui.dict_spec.callback(Fake.popup(word or "gave"))
    Fake.press(Fake.last("viewer"), "Save")
end

describe("Lexicard plugin (fake KOReader)", function()
    it("registers a dictionary button and a menu", function()
        local plugin, ui = setup({})
        assert_eq(ui.dict_spec.id, "lexicard")
        assert_eq(ui.menu_plugin, plugin)
    end)
    it("hold → preview → save adds the note and syncs", function()
        local state = {}
        local _, ui = setup(state)
        local popup = Fake.popup("gave")
        ui.dict_spec.callback(popup)
        assert_true(popup.closed)
        assert_match(Fake.last("viewer").text, "give up")
        Fake.press(Fake.last("viewer"), "Save")
        assert_eq(#state.notes, 1)
        assert_eq(state.notes[1].deckName, "Reading vocabulary")
        assert_eq(state.notes[1].fields.Headword, "give up")
        assert_eq(state.notes[1].fields.Book, "Example Book — Ann Author")
        assert_eq(state.notes[1].fields.Context, "she finally <b>gave it up</b>.")
        assert_eq(state.notes[1].audio[1].data, "UklGRg==")
        assert_eq(state.actions[#state.actions], "sync")
        assert_match(Fake.last("info").text, "Added to Reading vocabulary")
    end)
    it("saves without audio when the voice fails", function()
        local state = { tts_down = true }
        local _, ui = setup(state)
        hold_and_save(ui)
        assert_eq(#state.notes, 1)
        assert_eq(state.notes[1].audio, nil)
    end)
    it("keeps the card on the Kindle when Anki is unreachable", function()
        local plugin, ui = setup({ anki_down = true })
        hold_and_save(ui)
        assert_eq(plugin.outbox:count(), 1)
        assert_match(Fake.last("info").text, "1 waiting")
    end)
    it("keeps the card when Wi-Fi dropped before saving", function()
        local state = {}
        local plugin, ui = setup(state, { connected = false })
        hold_and_save(ui)
        assert_eq(plugin.outbox:count(), 1)
        assert_eq(#state.notes, 0)
    end)
    it("sends waiting cards from the menu", function()
        local state = { anki_down = true }
        local plugin, ui = setup(state)
        hold_and_save(ui)
        state.anki_down = false
        local menu = {}
        plugin:addToMainMenu(menu)
        local send = menu.lexicard.sub_item_table[1]
        assert_eq(send.text_func(), "Send waiting cards (1)")
        send.callback()
        assert_eq(plugin.outbox:count(), 0)
        assert_eq(#state.notes, 1)
        assert_match(Fake.last("info").text, "Sent 1")
    end)
    it("asks before adding a duplicate", function()
        local state = { duplicate = true }
        local _, ui = setup(state)
        hold_and_save(ui)
        assert_eq(#state.notes, 0)
        Fake.last("confirm").ok_callback()
        assert_eq(#state.notes, 1)
        assert_eq(state.notes[1].options.allowDuplicate, true)
    end)
    it("explains when the word is a name", function()
        local state = { card = { status = "proper_noun" } }
        local _, ui = setup(state)
        ui.dict_spec.callback(Fake.popup("Vin"))
        assert_match(Fake.last("info").text, "looks like a name")
        assert_eq(Fake.last("viewer"), nil)
    end)
    it("asks for the API key when .env lacks it", function()
        local _, ui = setup({}, { env = "ANKICONNECT_URLS=http://mac:8765\n" })
        ui.dict_spec.callback(Fake.popup("gave"))
        assert_match(Fake.last("info").text, "GEMINI_API_KEY")
    end)
end)
