local Json = require("lexicard_json")
local Gemini = require("lexicard_gemini")
local Config = require("lexicard_config")

local cfg = Config.from_values({ GEMINI_API_KEY = "test-key" })
local input = { word = "gave", sentence = "she finally ⟦gave⟧ it up.", book_title = "", book_author = "" }

local GOOD = {
    status = "ok", surface = "gave", expression_in_text = "gave it up", headword = "give up",
    pos = "phrasal verb", pattern = "give sth up", register = "neutral", cefr = "B1",
    definition = "to stop doing something", spanish = { "dejar", "abandonar" },
    context = "she finally <b>gave it up</b>.", example = "He <b>gave up</b> smoking.",
    collocations = { "give up hope" }, warning = "", pron_tip = "", ipa = "/ɡɪv ʌp/",
}

local function reply(card)
    return Json.encode({ candidates = { { content = { parts = { { text = Json.encode(card) } } } } } })
end

local function fake(responses)
    local calls = {}
    local transport = function(request)
        calls[#calls + 1] = request
        local r = table.remove(responses, 1)
        return r[1], r[2]
    end
    return transport, calls
end

local function copy(t)
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    return c
end

describe("Gemini.generate", function()
    it("returns a normalized card from the primary model", function()
        local transport, calls = fake({ { 200, reply(GOOD) } })
        local result = Gemini.generate(cfg, input, transport)
        assert_eq(result.ok, true)
        assert_eq(result.model, "gemini-3.5-flash-lite")
        assert_eq(result.card.headword, "give up")
        assert_same(result.card.spanish, { "dejar", "abandonar" })
        assert_eq(#calls, 1)
        assert_match(calls[1].url, "models/gemini%-3%.5%-flash%-lite:generateContent$")
        assert_eq(calls[1].headers["x-goog-api-key"], "test-key")
        assert_eq(calls[1].method, "POST")
    end)
    it("falls back to the second model when the first is busy", function()
        local transport, calls = fake({ { 503, '{"error":{"message":"high demand"}}' }, { 200, reply(GOOD) } })
        local result = Gemini.generate(cfg, input, transport)
        assert_eq(result.ok, true)
        assert_eq(result.model, "gemini-3.6-flash")
        assert_eq(Json.decode(calls[2].body).generationConfig.thinkingConfig.thinkingLevel, "low")
    end)
    it("falls back when the first reply is unusable", function()
        local transport = fake({ { 200, reply({ status = "ok" }) }, { 200, reply(GOOD) } })
        assert_eq(Gemini.generate(cfg, input, transport).ok, true)
    end)
    it("does not retry a rejected API key", function()
        local transport, calls = fake({ { 403, '{"error":{"message":"API key not valid"}}' } })
        local result = Gemini.generate(cfg, input, transport)
        assert_eq(result.kind, "auth")
        assert_eq(result.message, "API key not valid")
        assert_eq(#calls, 1)
    end)
    it("reports names without retrying", function()
        local transport, calls = fake({ { 200, reply({ status = "proper_noun" }) } })
        local result = Gemini.generate(cfg, input, transport)
        assert_eq(result.kind, "not_a_word")
        assert_eq(result.status, "proper_noun")
        assert_eq(#calls, 1)
    end)
    it("reports the last error when both models fail", function()
        local transport = fake({ { nil, "timeout" }, { 429, '{"error":{"message":"quota"}}' } })
        local result = Gemini.generate(cfg, input, transport)
        assert_eq(result.ok, false)
        assert_eq(result.kind, "quota")
    end)
    it("classifies certificate failures as tls and does not retry", function()
        local transport, calls = fake({ { nil, "certificate verify failed" } })
        assert_eq(Gemini.generate(cfg, input, transport).kind, "tls")
        assert_eq(#calls, 1)
    end)
end)

describe("Gemini.normalize", function()
    it("trims strings, caps lists and adds IPA slashes", function()
        local raw = copy(GOOD)
        raw.headword = "  give up "
        raw.ipa = "ɡɪv ʌp"
        raw.spanish = { "a", "b", "c", "d", 5 }
        local card = Gemini.normalize(raw)
        assert_eq(card.headword, "give up")
        assert_eq(card.ipa, "/ɡɪv ʌp/")
        assert_same(card.spanish, { "a", "b", "c" })
    end)
    it("rejects cards without Spanish equivalents", function()
        local raw = copy(GOOD)
        raw.spanish = {}
        local card, reason = Gemini.normalize(raw)
        assert_eq(card, nil)
        assert_eq(reason, "missing spanish")
    end)
    it("turns JSON nulls into empty strings", function()
        local raw = copy(GOOD)
        raw.warning = Json.null
        assert_eq(Gemini.normalize(raw).warning, "")
    end)
end)

describe("Gemini.reply_text", function()
    it("ignores thought parts", function()
        local data = { candidates = { { content = { parts = { { text = "thinking...", thought = true }, { text = '{"a":1}' } } } } } }
        assert_eq(Gemini.reply_text(data), '{"a":1}')
    end)
    it("explains blocked prompts", function()
        local text, why = Gemini.reply_text({ promptFeedback = { blockReason = "SAFETY" } })
        assert_eq(text, nil)
        assert_eq(why, "blocked: SAFETY")
    end)
end)
