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
local Audio = require("lexicard_audio")
local Config = require("lexicard_config")
local Context = require("lexicard_context")
local Gemini = require("lexicard_gemini")
local Http = require("lexicard_http")
local Note = require("lexicard_note")
local Outbox = require("lexicard_outbox")
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
local UNREACHABLE = _("Anki isn't reachable. Is Anki open on the computer?")

local Lexicard = WidgetContainer:extend{
    name = "lexicard",
    is_doc_only = true,
}

Lexicard.VERSION = "0.2.0"

function Lexicard:init()
    self.cfg, self.cfg_found = Config.load(self.path .. "/.env")
    self.outbox = Outbox.open(DataStorage:getSettingsDir() .. "/lexicard_outbox.json")
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
        UI.preview(Note.preview_text(card, input, cfg.anki_deck),
            function() self:generate(input) end,
            function() self:save(card, input, false) end)
    end)
end

function Lexicard:keepOnKindle(note)
    self.outbox:add(note)
    UI.info(T(WAITING, self.outbox:count()))
end

function Lexicard:save(card, input, allow_duplicate)
    local cfg = self.cfg
    if not NetworkMgr:isConnected() then
        self:keepOnKindle(Note.build(card, input, cfg, allow_duplicate))
        return
    end
    Trapper:wrap(function()
        local completed, report = Trapper:dismissableRunInSubprocess(function()
            local transport = Http.transport(cfg.tls_verify)
            local audio = Audio.generate(cfg, card, transport)
            local note = Note.build(card, input, cfg, allow_duplicate, audio)
            return { note = note, outcome = Anki.deliver(transport, cfg, note) }
        end, _("Lexicard: sending to Anki…"))
        local note = type(report) == "table" and report.note or Note.build(card, input, cfg, allow_duplicate)
        local outcome = type(report) == "table" and report.outcome or nil
        if not completed or type(outcome) ~= "table" then
            self:keepOnKindle(note)
        elseif outcome.kind == "ok" then
            if outcome.sync_error then
                logger.warn("Lexicard: AnkiConnect sync failed", outcome.sync_error)
                UI.info(T(_("Added to %1 ✓\nBut Anki couldn't sync to AnkiWeb: open Anki on the computer and press Sync (it may ask for a full sync)."), cfg.anki_deck))
            else
                UI.info(T(_("Added to %1 ✓"), cfg.anki_deck), 2)
            end
            if self.outbox:count() > 0 then self:flushOutbox(true) end
        elseif outcome.kind == "duplicate" then
            UI.confirm(_("Already in your deck. Add anyway?"), _("Add anyway"), function()
                self:save(card, input, true)
            end)
        elseif outcome.kind == "unreachable" then
            self:keepOnKindle(note)
        else
            logger.warn("Lexicard: AnkiConnect error", outcome.message)
            self.outbox:add(note)
            UI.info(T(_("Anki said: %1\nThe card is saved on the Kindle."), tostring(outcome.message)))
        end
    end)
end

function Lexicard:flushOutbox(silent)
    if self.flushing or self.outbox:count() == 0 then return end
    local cfg = self.cfg
    local items = self.outbox.items
    self.flushing = true
    Trapper:wrap(function()
        local completed, report = Trapper:dismissableRunInSubprocess(function()
            return Anki.deliver_many(Http.transport(cfg.tls_verify), cfg, items)
        end, (not silent) and _("Lexicard: sending waiting cards…") or nil)
        self.flushing = false
        if not completed or type(report) ~= "table" then return end
        if report.setup_error then
            if not silent then
                local message = report.setup_error.kind == "unreachable" and UNREACHABLE
                    or T(_("Couldn't send waiting cards: %1"), tostring(report.setup_error.message))
                UI.info(message)
            end
            return
        end
        local summary = self.outbox:apply(report.outcomes)
        if not silent or summary.sent > 0 or #summary.duplicates > 0 then
            UI.info("Lexicard: " .. Outbox.summary_text(summary), 3)
        end
    end)
end

function Lexicard:onNetworkConnected()
    if self.outbox:count() > 0 then
        UIManager:scheduleIn(3, function() self:flushOutbox(true) end)
    end
end

function Lexicard:testConnections()
    local cfg = self.cfg
    Trapper:wrap(function()
        local completed, report = Trapper:dismissableRunInSubprocess(function()
            local transport = Http.transport(cfg.tls_verify)
            return { gemini = Gemini.check(cfg, transport), anki = Anki.check(transport, cfg) }
        end, _("Lexicard: testing connections…"))
        if not completed or type(report) ~= "table" then return end
        local lines = {}
        local g = report.gemini
        lines[#lines + 1] = "Gemini (" .. cfg.gemini_model .. "): "
            .. (g.ok and "OK" or (tostring(g.kind) .. " — " .. tostring(g.message)))
        for _i, a in ipairs(report.anki) do
            lines[#lines + 1] = "Anki " .. a.url .. ": " .. (a.kind == "ok" and a.message or (a.kind .. " — " .. a.message))
        end
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
    return T(_("Lexicard %1\n\nDeck: %2\nNote type: %3\nModels: %4, then %5\nAnkiConnect URLs: %6\nWaiting cards: %7\nSettings: %8"),
        Lexicard.VERSION, cfg.anki_deck, cfg.anki_note_type, cfg.gemini_model, cfg.gemini_fallback_model,
        #cfg.ankiconnect_urls, self.outbox:count(), self.cfg_found and (self.path .. "/.env") or _("missing .env"))
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
                    NetworkMgr:runWhenConnected(function() self:flushOutbox(false) end)
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
