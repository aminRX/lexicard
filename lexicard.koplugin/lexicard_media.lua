--[[
Audio and picture for a note, made when the note is sent and kept only in memory.
At Save, Media.request() records what to make: a few short strings the outbox can keep.
Media.attach() makes them and returns a copy of the note with the media attached. That
copy goes to AnkiConnect and is never written to the Kindle.
]]
local Audio = require("lexicard_audio")
local Config = require("lexicard_config")
local Note = require("lexicard_note")
local Picture = require("lexicard_picture")

local Media = {}

function Media.request(card, cfg)
    return {
        slug = Note.slug(card.headword),
        audio_text = Audio.text_for(card, cfg.audio) or "",
        picture_prompt = Picture.prompt(card) or "",
    }
end

-- note, info. info.audio and info.picture are "ok", "none" (nothing to make, or turned off)
-- or why it failed.
function Media.attach(cfg, transport, note, request, now)
    local out = {}
    for k, v in pairs(note) do out[k] = v end
    local info = { audio = "none", picture = "none" }
    if type(request) ~= "table" then return out, info end
    now = now or os.time()
    local slug = (request.slug or "") ~= "" and request.slug or "word"
    if (request.audio_text or "") ~= "" then
        local audio, why = Audio.generate(cfg, request.audio_text, transport)
        if audio then
            out.audio = { { data = audio, filename = ("lexicard-%s-%d.wav"):format(slug, now), fields = { "Audio" } } }
            info.audio = "ok"
        else
            info.audio = why
        end
    end
    if (request.picture_prompt or "") ~= "" and Config.pictures_enabled(cfg) then
        local picture, why = Picture.draw(cfg, request.picture_prompt, transport)
        if picture then
            out.picture = { { data = picture, filename = ("lexicard-%s-%d.jpg"):format(slug, now), fields = { "Image" } } }
            info.picture = "ok"
        else
            info.picture = why
        end
    end
    return out, info
end

return Media
