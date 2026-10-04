-- Make one card from the Mac.
-- Usage: luajit scripts/try-card.lua WORD "SENTENCE with ⟦WORD⟧" ["Title — Author"] [--image] [--send] [--deck NAME]
--   --image  also draws the picture and saves it on the Mac in eval/out/pictures/ (git-ignored)
--   --send   adds the note (with audio and picture) to Anki
package.path = "lexicard.koplugin/?.lua;spec/support/?.lua;scripts/lib/?.lua;" .. package.path
local Anki = require("lexicard_anki")
local Config = require("lexicard_config")
local Curl = require("curl_transport")
local Gemini = require("lexicard_gemini")
local Media = require("lexicard_media")
local Note = require("lexicard_note")
local Pipeline = require("lexicard_pipeline")

local positional, send, image, deck = {}, false, false, nil
local i = 1
while i <= #arg do
    if arg[i] == "--send" then
        send = true
    elseif arg[i] == "--image" then
        image = true
    elseif arg[i] == "--deck" then
        deck = arg[i + 1]
        i = i + 1
    else
        positional[#positional + 1] = arg[i]
    end
    i = i + 1
end

local word, sentence, book = positional[1], positional[2] or "", positional[3] or ""
if not word then
    io.stderr:write('usage: luajit scripts/try-card.lua WORD "SENTENCE with ⟦WORD⟧" ["Title — Author"] [--image] [--send] [--deck NAME]\n')
    os.exit(2)
end

local cfg = Config.load(".env")
if deck then cfg.anki_deck = deck end
local title, author = book:match("^(.-)%s+—%s+(.+)$")
local input = { word = word, sentence = sentence, book_title = title or book, book_author = author or "" }

local result = Gemini.generate(cfg, input, Curl.transport)
if not result.ok then
    print("FAILED", result.kind, result.model, result.message or result.status)
    os.exit(1)
end
local card = Pipeline.finish(result.card, input, "lexicard.koplugin/data/cmudict-ipa.tsv")
print("model: " .. result.model)
print(Note.preview_text(card, input, cfg.anki_deck, Config.pictures_enabled(cfg)))
if not (image or send) then return end

local note, info = Media.attach(cfg, Curl.transport, Note.build(card, input, cfg, false), Media.request(card, cfg))
print("audio: " .. (note.audio and "yes" or "none") .. " · picture: " .. tostring(info.picture))
if image and note.picture then
    os.execute("mkdir -p eval/out/pictures")
    local b64 = os.tmpname()
    local f = assert(io.open(b64, "w"))
    f:write(note.picture[1].data)
    f:close()
    local path = "eval/out/pictures/" .. note.picture[1].filename
    os.execute(("base64 -D -i '%s' -o '%s'"):format(b64, path))
    os.remove(b64)
    print("picture saved: " .. path)
end
if send then
    local outcome = Anki.deliver(Curl.transport, cfg, note)
    print("anki: " .. outcome.kind .. (outcome.message and (" — " .. outcome.message) or "")
        .. (outcome.sync_error and (" (sync: " .. outcome.sync_error .. ")") or ""))
    if outcome.kind ~= "ok" then os.exit(1) end
end
