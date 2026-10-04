--[[
Lexicard: hold a word in KOReader, get an AI-written Anki card.
Every module is required here, at load time, because KOReader puts this
plugin's folder on package.path only while it loads the plugin.
]]
local DataStorage = require("datastorage")
local NetworkMgr = require("ui/network/manager")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local T = require("ffi/util").template
local _ = require("gettext")

local Anki = require("lexicard_anki")
local Background = require("lexicard_background")
local Config = require("lexicard_config")
local Context = require("lexicard_context")
local Gemini = require("lexicard_gemini")
local Http = require("lexicard_http")
local Media = require("lexicard_media")
local Note = require("lexicard_note")
local Outbox = require("lexicard_outbox")
local Picture = require("lexicard_picture")
local Pipeline = require("lexicard_pipeline")
local UI = require("lexicard_ui")

local BUSY = _("Gemini is busy or out of free quota. Try again in a minute.")
local GEMINI_ERRORS = {
    auth = _("Gemini rejected the API key. Check GEMINI_API_KEY in lexicard.koplugin/.env."),
    quota = BUSY,
    busy = BUSY,
    network = _("Couldn't reach Gemini. Check the Wi-Fi connection."),
    tls = _("Secure connection failed. Is the Kindle's date and time correct?"),
    invalid = _("Gemini returned an unusable card. Please try again."),
}
local NOT_A_WORD = {
    proper_noun = _("“%1” looks like a name. No card created."),
    not_english = _("“%1” doesn't look like English. No card created."),
    unclear = _("Couldn't make sense of “%1”. No card created."),
}
local WAITING = _("Saved on Kindle. It will be sent when Anki is reachable (%1 waiting).")

local Lexicard = WidgetContainer:extend{
    name = "lexicard",
    is_doc_only = true,
}

Lexicard.VERSION = "0.3.0"

function Lexicard:init()
    self.cfg, self.cfg_found = Config.load(self.path .. "/.env")
    self.outbox = Outbox.open(DataStorage:getSettingsDir() .. "/lexicard_outbox.json")
    self.interactive = {}
    self.ipa_path = self.path .. "/data/cmudict-ipa.tsv"
    self.ui.menu:registerToMainMenu(self)
    local dictionary = self.ui.dictionary
    if dictionary and type(dictionary.addToDictButtons) == "function" then
        dictionary:addToDictButtons{
            id = "lexicard",
            text = _("Lexicard"),
            menu_text = _("Lexicard: make an Anki card"),
            show_func = function(popup) return not popup.is_wiki and not popup:isDocless() end,
            callback = function(popup) self:handleDictButton(popup) end,
        }
    else
        logger.warn("Lexicard: ReaderDictionary:addToDictButtons is missing; is KOReader too old?")
    end
end

function Lexicard:handleDictButton(popup)
    local input = Context.from_popup(self.ui, popup)
    popup:onClose()
    if input.word == "" then return end
    local missing = Config.missing(self.cfg)
    if #missing > 0 then
        UI.info(T(_("Lexicard needs %1 in lexicard.koplugin/.env."), table.concat(missing, ", ")))
        return
    end
    NetworkMgr:runWhenOnline(function() self:generate(input) end)
end

function Lexicard:generate(input)
    local cfg = self.cfg
    Trapper:wrap(function()
        local completed, result = Trapper:dismissableRunInSubprocess(function()
            return Gemini.generate(cfg, input, Http.transport(cfg.tls_verify))
        end, _("Lexicard: writing card…"))
        if not completed then return end
        if type(result) ~= "table" then
            logger.warn("Lexicard: Gemini subprocess returned", result)
            UI.info(_("Lexicard: something went wrong. See crash.log."))
            return
        end
        if not result.ok then
            logger.warn("Lexicard: Gemini failed", result.kind, result.model, result.message)
            if result.kind == "not_a_word" then
                UI.info(T(NOT_A_WORD[result.status] or NOT_A_WORD.unclear, input.word))
            else
                UI.info(GEMINI_ERRORS[result.kind] or T(_("Gemini error: %1"), tostring(result.message)))
            end
            return
        end
        local card = Pipeline.finish(result.card, input, self.ipa_path)
        logger.info("Lexicard: card for", card.headword, "from", result.model)
        UI.preview(Note.preview_text(card, input, cfg.anki_deck, Config.pictures_enabled(cfg)),
            function() self:generate(input) end,
            function() self:save(card, input, false) end)
    end)
end

-- Save keeps the card text in the outbox at once, then sends it in the background.
function Lexicard:save(card, input, allow_duplicate)
    local cfg = self.cfg
    local item = self.outbox:add(Note.build(card, input, cfg, allow_duplicate), nil, Media.request(card, cfg))
    self.interactive[item.id] = true
    if NetworkMgr:isConnected() then
        UI.info(T(_("Saving “%1”… you can keep reading."), card.headword), 2)
        self:sendWaiting(false)
    else
        UI.info(T(WAITING, self.outbox:count()))
    end
end

-- Sends the outbox in a background subprocess. Audio and pictures are made there, in memory.
-- Cards saved while a batch is running go in the next batch.
function Lexicard:sendWaiting(silent)
    if self.outbox:count() == 0 then return end
    if self.sending then
        self.send_again = true
        return
    end
    self.sending = true
    local cfg = self.cfg
    local items = {}
    for i, item in ipairs(self.outbox.items) do items[i] = item end
    Background.run(function()
        local transport = Http.transport(cfg.tls_verify)
        return Anki.deliver_many(transport, cfg, items, function(item)
            return Media.attach(cfg, transport, item.note, item.media)
        end)
    end, function(report)
        self.sending = false
        self:afterSend(items, report, silent)
        if self.send_again then
            self.send_again = false
            self:sendWaiting(true)
        end
    end)
end

function Lexicard:askDuplicate(item)
    local headword = type(item.note.fields) == "table" and item.note.fields.Headword or "?"
    UI.confirm(T(_("“%1” is already in your deck. Add anyway?"), headword), _("Add anyway"), function()
        local note = item.note
        note.options = note.options or {}
        note.options.allowDuplicate = true
        local again = self.outbox:add(note, nil, item.media)
        self.interactive[again.id] = true
        self:sendWaiting(false)
    end)
end

function Lexicard:afterSend(items, report, silent)
    local cfg = self.cfg
    local mine = false
    for _, item in ipairs(items) do
        if self.interactive[item.id] then mine = true end
    end
    local loud = mine or not silent
    if type(report) ~= "table" or report.setup_error then
        local failure = type(report) == "table" and report.setup_error or nil
        if failure and failure.kind ~= "unreachable" then
            logger.warn("Lexicard: AnkiConnect setup failed", failure.message)
            if loud then UI.info(T(_("Anki said: %1\nThe card is saved on the Kindle."), tostring(failure.message))) end
        elseif loud then
            UI.info(T(WAITING, self.outbox:count()))
        end
        return
    end
    local by_id = {}
    for _, item in ipairs(items) do by_id[item.id] = item end
    local no_picture, other_duplicates = nil, {}
    for _, o in ipairs(report.outcomes) do
        local item = by_id[o.id]
        if o.kind == "ok" and type(o.info) == "table" and o.info.picture ~= "ok" and o.info.picture ~= "none" then
            no_picture = no_picture or o.info.picture
        end
        if o.kind == "duplicate" and item then
            if self.interactive[o.id] then
                self:askDuplicate(item)
            else
                local fields = type(item.note.fields) == "table" and item.note.fields or {}
                other_duplicates[#other_duplicates + 1] = fields.Headword or "?"
            end
        end
        self.interactive[o.id] = nil
    end
    local summary = self.outbox:apply(report.outcomes)
    local lines = {}
    if summary.sent == 1 then
        lines[#lines + 1] = T(_("Added “%1” to %2 ✓"), summary.sent_words[1], cfg.anki_deck)
    elseif summary.sent > 1 then
        lines[#lines + 1] = T(_("Added %1 cards to %2 ✓"), summary.sent, cfg.anki_deck)
    end
    if no_picture then lines[#lines + 1] = T(_("No picture: %1."), no_picture) end
    if report.sync_error then
        logger.warn("Lexicard: AnkiConnect sync failed", report.sync_error)
        lines[#lines + 1] = _("But Anki couldn't sync to AnkiWeb: open Anki on the computer and press Sync (it may ask for a full sync).")
    end
    if #other_duplicates > 0 then
        lines[#lines + 1] = T(_("Already in your deck: %1"), table.concat(other_duplicates, ", "))
    end
    if summary.failed > 0 then
        logger.warn("Lexicard: AnkiConnect error", summary.last_error)
        lines[#lines + 1] = T(_("Anki said: %1\nThe card is saved on the Kindle."), tostring(summary.last_error))
    elseif summary.remaining > 0 and loud then
        lines[#lines + 1] = T(WAITING, summary.remaining)
    end
    if #lines > 0 and (loud or summary.sent > 0) then
        UI.info(table.concat(lines, "\n"), (summary.failed == 0 and not report.sync_error and not no_picture) and 3 or nil)
    end
end

function Lexicard:onNetworkConnected()
    if self.outbox:count() > 0 then
        UIManager:scheduleIn(3, function() self:sendWaiting(true) end)
    end
end

function Lexicard:testConnections()
    local cfg = self.cfg
    Trapper:wrap(function()
        local completed, report = Trapper:dismissableRunInSubprocess(function()
            local transport = Http.transport(cfg.tls_verify)
            return { gemini = Gemini.check(cfg, transport), anki = Anki.check(transport, cfg),
                     picture = Picture.check(cfg, transport) }
        end, _("Lexicard: testing connections…"))
        if not completed or type(report) ~= "table" then return end
        local lines = {}
        local g = report.gemini
        lines[#lines + 1] = "Gemini (" .. cfg.gemini_model .. "): "
            .. (g.ok and "OK" or (tostring(g.kind) .. " — " .. tostring(g.message)))
        for _i, a in ipairs(report.anki) do
            lines[#lines + 1] = "Anki " .. a.url .. ": " .. (a.kind == "ok" and a.message or (a.kind .. " — " .. a.message))
        end
        local p = report.picture
        lines[#lines + 1] = "Pictures (Cloudflare): " .. (p.ok and "OK" or tostring(p.message))
        UI.info(table.concat(lines, "\n"))
    end)
end

function Lexicard:updateNoteType()
    local cfg = self.cfg
    Trapper:wrap(function()
        local completed, outcome = Trapper:dismissableRunInSubprocess(function()
            return Anki.update_note_type(Http.transport(cfg.tls_verify), cfg)
        end, _("Lexicard: updating note type…"))
        if not completed or type(outcome) ~= "table" then return end
        if outcome.kind == "ok" then
            UI.info(T(_("Note type “%1” updated in Anki."), cfg.anki_note_type))
        else
            UI.info(T(_("Couldn't update the note type: %1"), tostring(outcome.message)))
        end
    end)
end

function Lexicard:aboutText()
    local cfg = self.cfg
    return T(_("Lexicard %1\n\nDeck: %2\nNote type: %3\nModels: %4, then %5\nAnkiConnect URLs: %6\nWaiting cards: %7\nPictures: %9\nSettings: %8"),
        Lexicard.VERSION, cfg.anki_deck, cfg.anki_note_type, cfg.gemini_model, cfg.gemini_fallback_model,
        #cfg.ankiconnect_urls, self.outbox:count(), self.cfg_found and (self.path .. "/.env") or _("missing .env"),
        Config.pictures_enabled(cfg) and _("on") or _("off"))
end

function Lexicard:addToMainMenu(menu_items)
    menu_items.lexicard = {
        text = _("Lexicard"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text_func = function() return T(_("Send waiting cards (%1)"), self.outbox:count()) end,
                enabled_func = function() return self.outbox:count() > 0 end,
                callback = function()
                    NetworkMgr:runWhenConnected(function() self:sendWaiting(false) end)
                end,
            },
            {
                text = _("Test connections"),
                callback = function()
                    NetworkMgr:runWhenOnline(function() self:testConnections() end)
                end,
            },
            {
                text = _("Update note type in Anki"),
                callback = function()
                    NetworkMgr:runWhenConnected(function() self:updateNoteType() end)
                end,
            },
            {
                text = _("About Lexicard"),
                keep_menu_open = true,
                callback = function() UI.info(self:aboutText()) end,
            },
        },
    }
end

return Lexicard
