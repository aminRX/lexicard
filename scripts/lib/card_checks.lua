-- Automatic quality checks on a finished card, used by the prompt evaluation.
local Text = require("lexicard_text")

local Checks = {}

local function norm(s)
    local out = Text.fold(Text.strip_tags(s or "")):gsub("^the ", ""):gsub("^an? ", "")
    return out
end

local function as_list(v)
    if type(v) == "table" then return v end
    return { v }
end

function Checks.run(case, result, fields)
    local out = {}
    local function add(name, ok, detail)
        out[#out + 1] = { name = name, ok = ok and true or false, detail = detail and tostring(detail) or "" }
    end
    local expect = case.expect or {}
    if expect.status and expect.status ~= "ok" then
        add("status", result.kind == "not_a_word" and result.status == expect.status, result.status or result.kind)
        return out
    end
    add("ok", result.ok == true, result.ok and "" or result.kind)
    if not result.ok or not fields then return out end

    if expect.headword then
        local got, hit = norm(fields.Headword), false
        for _, h in ipairs(as_list(expect.headword)) do
            if norm(h) == got then hit = true end
        end
        add("headword", hit, got)
    end
    local definition = Text.strip_tags(fields.Definition)
    add("definition_no_headword", not Text.mentions(definition, fields.Headword), definition)
    add("definition_short", #Text.words(definition) <= 15, #Text.words(definition) .. " words")
    local example = Text.strip_tags(fields.Example)
    add("example_short", #Text.words(example) <= 15, #Text.words(example) .. " words")
    if (case.sentence or "") ~= "" then
        local overlap = Text.overlap(example, Text.strip_marks(case.sentence))
        add("example_new", overlap <= 0.5, ("overlap %.2f"):format(overlap))
    end
    local spanish = {}
    for item in (fields.Spanish or ""):gmatch("[^/]+") do spanish[#spanish + 1] = Text.fold(item) end
    local dupes = false
    for i = 1, #spanish do
        for j = i + 1, #spanish do
            local a, b = spanish[i], spanish[j]
            if a == b or a:sub(1, #b + 1) == b .. " " or b:sub(1, #a + 1) == a .. " " then dupes = true end
        end
    end
    add("spanish_clean", not dupes and #spanish > 0, fields.Spanish)
    if expect.trap and expect.trap ~= "any" then
        local has = Text.strip_tags(fields.Warning or "") ~= ""
        add("warning_" .. expect.trap, (expect.trap == "none") == (not has), fields.Warning)
    end
    local tip = Text.fold(fields.PronTip or "")
    add("pron_tip_no_spelling", not (tip:find("doble", 1, true) or tip:find("letra", 1, true)), fields.PronTip)
    local ipa = (fields.IPA or ""):gsub("/", "")
    local n_ipa = 0
    for _ in ipa:gmatch("%S+") do n_ipa = n_ipa + 1 end
    add("ipa_words", ipa == "" or n_ipa == #Text.words(fields.Headword), fields.IPA)
    add("cloze_blank", (fields.Cloze or ""):find("_", 1, true) ~= nil, fields.Cloze)
    return out
end

return Checks
