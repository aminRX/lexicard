local Audio = require("lexicard_audio")
local Config = require("lexicard_config")
local Json = require("lexicard_json")

local card = { headword = "give up", usage = { { pattern = "x", example = "I <b>gave up</b> coffee." } } }

local function reply(mime, data)
    return Json.encode({ candidates = { { content = { parts = { { inlineData = { mimeType = mime, data = data } } } } } } })
end

describe("Audio", function()
    it("chooses what to read", function()
        assert_eq(Audio.text_for(card, "word"), "give up")
        assert_eq(Audio.text_for(card, "word+example"), "give up. I gave up coffee.")
        assert_eq(Audio.text_for(card, "off"), nil)
    end)
    it("asks the TTS model for the text in the configured voice", function()
        local cfg = Config.from_values({ GEMINI_API_KEY = "k" })
        local seen
        local data = Audio.generate(cfg, "give up", function(request)
            seen = request
            return 200, reply("audio/wav", "UklGRg==")
        end)
        assert_eq(data, "UklGRg==")
        assert_match(seen.url, "gemini%-3%.8%-flash%-lite%-tts:generateContent$")
        local body = Json.decode(seen.body)
        assert_eq(body.contents[1].parts[1].text, "give up")
        assert_eq(body.generationConfig.speechConfig.voiceConfig.prebuiltVoiceConfig.voiceName, "Kore")
    end)
    it("returns nil on errors, raw PCM, or no text", function()
        local cfg = Config.from_values({ GEMINI_API_KEY = "k" })
        assert_eq(Audio.generate(cfg, "x", function() return 500, "{}" end), nil)
        assert_eq(Audio.generate(cfg, "x", function() return 200, reply("audio/L16;rate=24000", "AAAA") end), nil)
        assert_eq(Audio.generate(cfg, "", function() error("no call") end), nil)
        assert_eq(Audio.generate(cfg, nil, function() error("no call") end), nil)
    end)
end)
