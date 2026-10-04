-- One-time upgrade of an existing Lexicard deck to v0.3. Run on the Mac with Anki open.
--  1. Updates the note type (fields, templates, CSS).
--  2. Removes the old Spanish→English card type ("Produce"), which deletes those cards.
--  3. Rebuilds each note that has no picture: usage, caption, definition, Spanish, warning,
--     plus a picture (and audio if it had none).
-- Usage: luajit scripts/upgrade-v0.3.lua [--dry-run] [--keep-produce]
package.path = "lexicard.koplugin/?.lua;spec/support/?.lua;scripts/lib/?.lua;" .. package.path
local Anki = require("lexicard_anki")
local Config = require("lexicard_config")
local Curl = require("curl_transport")
local Gemini = require("lexicard_gemini")
local Media = require("lexicard_media")
local Note = require("lexicard_note")
local Pipeline = require("lexicard_pipeline")
local Text = require("lexicard_text")

local dry, keep_produce = false, false
for _, a in ipairs(arg) do
    if a == "--dry-run" then dry = true elseif a == "--keep-produce" then keep_produce = true end
end

local cfg = Config.load(".env")
local url = assert(cfg.ankiconnect_urls[1], "ANKICONNECT_URLS missing in .env")
local function call(action, params)
    local kind, result = Anki.call(Curl.transport, url, cfg, action, params, 60)
    if kind ~= "ok" then error(action .. ": " .. tostring(result)) end
    return result
end
local function unescape(s)
    return (s:gsub("&quot;", '"'):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&"))
end

if not dry then
    local kind, message = Anki.ensure_setup(Curl.transport, url, cfg)
    if kind ~= "ok" then error("note type update: " .. tostring(message)) end
end

local templates = call("modelTemplates", { modelName = cfg.anki_note_type })
if templates.Produce and not keep_produce then
    print("Removing the Spanish→English card type (Produce) and its cards…")
    if not dry then call("modelTemplateRemove", { modelName = cfg.anki_note_type, templateName = "Produce" }) end
end

local notes = call("notesInfo", { notes = call("findNotes", { query = ('"note:%s"'):format(cfg.anki_note_type) }) })
for _, n in ipairs(notes) do
    local f = n.fields
    local function value(name) return f[name] and f[name].value or "" end
    local headword = unescape(value("Headword"))
    if value("Image") ~= "" then
        print("skip (already has a picture): " .. headword)
    else
        local context = value("Context")
        local word = unescape(Text.strip_tags(context:match("<b>(.-)</b>") or headword))
        local sentence = unescape(Text.strip_tags((context:gsub("<b>(.-)</b>", "⟦%1⟧"))))
        local book = unescape(value("Book"))
        local title, author = book:match("^(.-) — (.+)$")
        local input = { word = word, sentence = sentence, book_title = title or book, book_author = author or "" }
        local result = Gemini.generate(cfg, input, Curl.transport)
        if not result.ok then
            print(("FAILED %s: %s %s"):format(headword, tostring(result.kind), tostring(result.message or result.status)))
        else
            local card = Pipeline.finish(result.card, input, "lexicard.koplugin/data/cmudict-ipa.tsv")
            local fresh = Note.fields(card, input)
            local request = Media.request(card, cfg)
            if value("Audio") ~= "" then request.audio_text = "" end
            local media, info = Media.attach(cfg, Curl.transport, {}, request)
            local update = { id = n.noteId, audio = media.audio, picture = media.picture, fields = {
                IPA = fresh.IPA, POS = fresh.POS, Register = fresh.Register, Spanish = fresh.Spanish,
                Definition = fresh.Definition, Usage = fresh.Usage, Caption = fresh.Caption, Warning = fresh.Warning,
            } }
            print(("%s: %d patterns · picture %s%s"):format(headword, #card.usage, tostring(info.picture),
                dry and " (dry run)" or ""))
            if not dry then call("updateNoteFields", { note = update }) end
        end
        os.execute("sleep 5") -- Gemini free tier: stay under the per-minute limit
    end
end
print("Done. Now do ONE full sync: on the Mac press Sync → Upload to AnkiWeb; on the iPhone choose Download from AnkiWeb.")
