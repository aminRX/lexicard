local Json = require("lexicard_json")
local Gemini = require("lexicard_gemini")
local Config = require("lexicard_config")

local cfg = Config.from_values({ GEMINI_API_KEY = "test-key" })
local input = { word = "gave", sentence = "she finally ⟦gave⟧ it up.", book_title = "", book_author = "" }

local GOOD = {
    status = "ok", expression_in_text = "gave it up", headword = "give up", pos = "phrasal verb",
    sense = "stopped doing it", ipa = "/ˌɡɪv ˈʌp/", register = "neutral",
    definition = "to stop doing something", spanish = { "dejar", "abandonar" }, trap = "none", warning = "",
    usage = { { pattern = "give up + something", example = "He <b>gave up</b> coffee." } },
    picture_format = "before_after", picture_scene = "Two panels.", picture_caption = "He <b>gave up</b> coffee.",
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
    it("retries with the fallback when the definition uses the headword", function()
        local bad = copy(GOOD)
        bad.definition = "to give something up"
        local transport, calls = fake({ { 200, reply(bad) }, { 200, reply(GOOD) } })
        local result = Gemini.generate(cfg, input, transport)
        assert_eq(result.model, "gemini-3.6-flash")
        assert_eq(result.card.definition, "to stop doing something")
        assert_eq(#calls, 2)
    end)
    it("keeps the first card when the fallback fails", function()
        local bad = copy(GOOD)
        bad.usage = { { pattern = "", example = "she finally <b>gave it up</b>." } }
        local transport = fake({ { 200, reply(bad) }, { 503, "{}" } })
        local result = Gemini.generate(cfg, input, transport)
        assert_eq(result.ok, true)
        assert_eq(result.model, "gemini-3.5-flash-lite")
        assert_eq(result.problem, "example copies the book")
    end)
    it("sends the configured thinking level to the main model", function()
        local thinking_cfg = Config.from_values({ GEMINI_API_KEY = "k", GEMINI_THINKING = "low" })
        local transport, calls = fake({ { 200, reply(GOOD) } })
        Gemini.generate(thinking_cfg, input, transport)
        assert_eq(Json.decode(calls[1].body).generationConfig.thinkingConfig.thinkingLevel, "low")
    end)
    it("classifies certificate failures as tls and does not retry", function()
        local transport, calls = fake({ { nil, "certificate verify failed" } })
        assert_eq(Gemini.generate(cfg, input, transport).kind, "tls")
        assert_eq(#calls, 1)
    end)
end)

describe("Gemini.normalize", function()
    it("trims strings and caps lists", function()
        local raw = copy(GOOD)
        raw.headword = "  give up "
        raw.spanish = { "a", "b", "c", "d", 5 }
        local card = Gemini.normalize(raw)
        assert_eq(card.headword, "give up")
        assert_same(card.spanish, { "a", "b", "c" })
        assert_eq(card.trap, "none")
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
    it("keeps up to three usage items with an example", function()
        local raw = copy(GOOD)
        raw.usage = { { pattern = " p ", example = " a " }, { pattern = "x" }, "junk",
                      { example = "b" }, { example = "c" }, { example = "d" } }
        local card = Gemini.normalize(raw)
        assert_same(card.usage, { { pattern = "p", example = "a" }, { pattern = "", example = "b" },
                                  { pattern = "", example = "c" } })
    end)
    it("rejects a card without usage and fixes an unknown picture format", function()
        local raw = copy(GOOD)
        raw.usage = {}
        local card, reason = Gemini.normalize(raw)
        assert_eq(card, nil)
        assert_eq(reason, "missing usage")
        raw = copy(GOOD)
        raw.picture_format = "comic"
        assert_eq(Gemini.normalize(raw).picture_format, "object")
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
