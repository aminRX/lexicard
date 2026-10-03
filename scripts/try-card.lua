-- Make one card from the Mac.
-- Usage: luajit scripts/try-card.lua WORD "SENTENCE with ⟦WORD⟧" ["Title — Author"] [--send] [--deck NAME]
package.path = "lexicard.koplugin/?.lua;spec/support/?.lua;scripts/lib/?.lua;" .. package.path
local Anki = require("lexicard_anki")
local Config = require("lexicard_config")
local Curl = require("curl_transport")
local Gemini = require("lexicard_gemini")
local Ipa = require("lexicard_ipa")
local Note = require("lexicard_note")

local positional, send, deck = {}, false, nil
local i = 1
while i <= #arg do
    if arg[i] == "--send" then
        send = true
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
    io.stderr:write('usage: luajit scripts/try-card.lua WORD "SENTENCE with ⟦WORD⟧" ["Title — Author"] [--send] [--deck NAME]\n')
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
local card = result.card
card.ipa = Ipa.for_headword("lexicard.koplugin/data/cmudict-ipa.tsv", card.headword) or card.ipa
print("model: " .. result.model)
print(Note.preview_text(card, input, cfg.anki_deck))
if send then
    local outcome = Anki.deliver(Curl.transport, cfg, Note.build(card, input, cfg, false))
    print("anki: " .. outcome.kind .. (outcome.message and (" — " .. outcome.message) or ""))
    if outcome.kind ~= "ok" then os.exit(1) end
end
