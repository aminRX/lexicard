local Media = require("lexicard_media")
local Config = require("lexicard_config")
local Json = require("lexicard_json")

local on = Config.from_values({ GEMINI_API_KEY = "k", CLOUDFLARE_ACCOUNT_ID = "acc", CLOUDFLARE_API_TOKEN = "tok" })
local card = { headword = "give up", usage = { { pattern = "x", example = "I <b>gave up</b> it." } },
               picture_scene = "Two panels." }

local function transport(state)
    return function(request)
        if request.url:find("cloudflare", 1, true) then
            if state.picture_down then return 429, "{}" end
            return 200, Json.encode({ result = { image = "/9j/PIC" } })
        end
        return 200, Json.encode({ candidates = { { content = { parts = {
            { inlineData = { mimeType = "audio/wav", data = "UklGRg==" } } } } } } })
    end
end

describe("Media", function()
    it("records what to make, as short strings", function()
        local request = Media.request(card, on)
        assert_eq(request.slug, "give_up")
        assert_eq(request.audio_text, "give up")
        assert_match(request.picture_prompt, "^Two panels%. Simple, friendly")
    end)
    it("attaches audio and picture to a copy of the note", function()
        local note = { fields = { Headword = "give up" } }
        local out, info = Media.attach(on, transport({}), note, Media.request(card, on), 1000)
        assert_eq(out.audio[1].data, "UklGRg==")
        assert_eq(out.audio[1].filename, "lexicard-give_up-1000.wav")
        assert_same(out.audio[1].fields, { "Audio" })
        assert_eq(out.picture[1].data, "/9j/PIC")
        assert_eq(out.picture[1].filename, "lexicard-give_up-1000.jpg")
        assert_same(out.picture[1].fields, { "Image" })
        assert_eq(info.picture, "ok")
        assert_eq(note.audio, nil)
        assert_eq(note.picture, nil)
    end)
    it("says why the audio is missing", function()
        local quota = function(request)
            if request.url:find("cloudflare", 1, true) then return 200, Json.encode({ result = { image = "/9j/PIC" } }) end
            return 429, "{}"
        end
        local out, info = Media.attach(on, quota, { fields = {} }, Media.request(card, on))
        assert_eq(out.audio, nil)
        assert_eq(info.audio, "daily voice limit reached")
        assert_eq(info.picture, "ok")
    end)
    it("sends without a picture when Cloudflare fails or pictures are off", function()
        local note = { fields = {} }
        local out, info = Media.attach(on, transport({ picture_down = true }), note, Media.request(card, on))
        assert_eq(out.picture, nil)
        assert_eq(info.picture, "daily picture limit reached")
        local off = Config.from_values({ GEMINI_API_KEY = "k" })
        out, info = Media.attach(off, transport({}), note, Media.request(card, off))
        assert_eq(out.picture, nil)
        assert_eq(info.picture, "none")
        out, info = Media.attach(on, transport({}), note, nil)
        assert_eq(out.audio, nil)
        assert_eq(info.picture, "none")
    end)
end)
