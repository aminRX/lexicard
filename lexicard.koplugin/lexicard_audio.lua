--[[
Card audio from Gemini text-to-speech. Returns the WAV as base64, which AnkiConnect
stores as media (the Kindle never decodes or stores it). Any failure returns nil: the
card is then saved without audio.
]]
local Json = require("lexicard_json")
local Text = require("lexicard_text")

local Audio = {}

Audio.BASE_URL = "https://generativelanguage.googleapis.com/v1beta/models/"

function Audio.text_for(card, mode)
    if mode == "off" then return nil end
    local text = card.headword
    local first = card.usage and card.usage[1]
    if mode == "word+example" and first and (first.example or "") ~= "" then
        text = text .. ". " .. Text.strip_tags(first.example)
    end
    return text
end

function Audio.request_body(text, voice)
    return '{"contents":[{"parts":[{"text":' .. Json.quote(text) .. '}]}],'
        .. '"generationConfig":{"responseModalities":["AUDIO"],'
        .. '"speechConfig":{"voiceConfig":{"prebuiltVoiceConfig":{"voiceName":' .. Json.quote(voice) .. '}}}}}'
end

-- Base64 WAV of the text, or nil plus a reason.
function Audio.generate(cfg, text, transport)
    if not text or text == "" then return nil, "no audio" end
    local code, body = transport({
        method = "POST",
        url = Audio.BASE_URL .. cfg.tts_model .. ":generateContent",
        headers = { ["Content-Type"] = "application/json", ["x-goog-api-key"] = cfg.gemini_api_key },
        body = Audio.request_body(text, cfg.tts_voice),
        block_timeout = 10,
        total_timeout = 15,
    })
    if type(code) ~= "number" then return nil, "network error" end
    if code == 429 then return nil, "daily voice limit reached" end
    if code ~= 200 then return nil, "voice error (HTTP " .. code .. ")" end
    local data = Json.decode(body)
    local candidate = type(data) == "table" and type(data.candidates) == "table" and data.candidates[1]
    local parts = type(candidate) == "table" and type(candidate.content) == "table" and candidate.content.parts
    if type(parts) ~= "table" then return nil, "no audio in reply" end
    for _, part in ipairs(parts) do
        local inline = type(part) == "table" and part.inlineData
        if type(inline) == "table" and type(inline.data) == "string" then
            if tostring(inline.mimeType):find("wav", 1, true) then return inline.data end
            return nil, "unsupported audio format " .. tostring(inline.mimeType)
        end
    end
    return nil, "no audio in reply"
end

return Audio
