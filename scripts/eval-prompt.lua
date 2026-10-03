-- Runs eval/cases.lua through each model and writes eval/out/report.md (git-ignored).
-- Usage: luajit scripts/eval-prompt.lua [model ...]
package.path = "lexicard.koplugin/?.lua;spec/support/?.lua;scripts/lib/?.lua;" .. package.path
local Config = require("lexicard_config")
local Curl = require("curl_transport")
local Gemini = require("lexicard_gemini")
local Note = require("lexicard_note")

local base = Config.load(".env")
local models = {}
for i = 1, #arg do models[i] = arg[i] end
if #models == 0 then models = { base.gemini_model, base.gemini_fallback_model } end
local cases = dofile("eval/cases.lua")

os.execute("mkdir -p eval/out")
local out = assert(io.open("eval/out/report.md", "w"))
for _, model in ipairs(models) do
    local cfg = {}
    for k, v in pairs(base) do cfg[k] = v end
    cfg.gemini_model, cfg.gemini_fallback_model = model, ""
    out:write("# ", model, "\n\n")
    for _, case in ipairs(cases) do
        local input = { word = case.word, sentence = case.sentence, book_title = "Eval", book_author = "" }
        local started = os.time()
        local result = Gemini.generate(cfg, input, Curl.transport)
        local seconds = os.time() - started
        out:write("## ", case.name, " (", seconds, " s)\n\n")
        if result.ok then
            out:write("```\n", Note.preview_text(result.card, input, cfg.anki_deck), "\n```\n\n")
        else
            out:write("FAILED: ", tostring(result.kind), " ", tostring(result.status or result.message), "\n\n")
        end
        print(("%s · %s: %s (%d s)"):format(model, case.name, result.ok and "ok" or tostring(result.kind), seconds))
    end
end
out:close()
print("Report: eval/out/report.md")
