-- Runs eval/cases.lua through each model, scores the cards and writes eval/out/ (git-ignored).
-- Usage: EVAL_LABEL=v0.1 [EVAL_THINKING=low] [EVAL_DELAY=13] luajit scripts/eval-prompt.lua [model ...]
package.path = "lexicard.koplugin/?.lua;spec/support/?.lua;scripts/lib/?.lua;" .. package.path
local Checks = require("card_checks")
local Config = require("lexicard_config")
local Curl = require("curl_transport")
local Gemini = require("lexicard_gemini")
local Json = require("lexicard_json")
local Note = require("lexicard_note")
local Pipeline = require("lexicard_pipeline")

local label = os.getenv("EVAL_LABEL") or "run"
local thinking = os.getenv("EVAL_THINKING")
local delay = tonumber(os.getenv("EVAL_DELAY") or "0")
local base = Config.load(".env")
local models = {}
for i = 1, #arg do models[i] = arg[i] end
if #models == 0 then models = { base.gemini_model } end
local cases = dofile("eval/cases.lua")

os.execute("mkdir -p eval/out")
local out = assert(io.open("eval/out/report-" .. label .. ".md", "w"))
local summary = { label = label, runs = {} }
for _, model in ipairs(models) do
    local cfg = {}
    for k, v in pairs(base) do cfg[k] = v end
    cfg.gemini_model, cfg.gemini_fallback_model = model, ""
    if thinking then cfg.gemini_thinking = thinking end
    local passed, total, seconds, per_check = 0, 0, 0, {}
    out:write("# ", model, " (", label, ")\n\n")
    for _, case in ipairs(cases) do
        local input = { word = case.word, sentence = case.sentence, book_title = "Eval", book_author = "" }
        local started = os.time()
        local result = Gemini.generate(cfg, input, Curl.transport)
        seconds = seconds + (os.time() - started)
        local fields
        out:write("## ", case.name, "\n\n")
        if result.ok then
            local card = Pipeline.finish(result.card, input, "lexicard.koplugin/data/cmudict-ipa.tsv")
            fields = Note.fields(card, input)
            out:write("```\n", Note.preview_text(card, input, cfg.anki_deck), "\n```\n\n")
        else
            out:write("FAILED: ", tostring(result.kind), " ", tostring(result.status or result.message), "\n\n")
        end
        local failed = {}
        for _, check in ipairs(Checks.run(case, result, fields)) do
            total = total + 1
            per_check[check.name] = per_check[check.name] or { passed = 0, total = 0 }
            per_check[check.name].total = per_check[check.name].total + 1
            if check.ok then
                passed = passed + 1
                per_check[check.name].passed = per_check[check.name].passed + 1
            else
                failed[#failed + 1] = check.name .. " (" .. check.detail .. ")"
            end
        end
        out:write(#failed == 0 and "All checks passed.\n\n" or ("Failed: " .. table.concat(failed, "; ") .. "\n\n"))
        print(("%s · %s: %s"):format(model, case.name, #failed == 0 and "ok" or table.concat(failed, ", ")))
        if delay > 0 then os.execute("sleep " .. delay) end
    end
    print(("== %s (%s): %d/%d checks passed, %d s total"):format(model, label, passed, total, seconds))
    summary.runs[#summary.runs + 1] = { model = model, passed = passed, total = total, seconds = seconds, per_check = per_check }
end
out:close()
local f = assert(io.open("eval/out/summary-" .. label .. ".json", "w"))
f:write(Json.encode(summary))
f:close()
print("Report: eval/out/report-" .. label .. ".md")
