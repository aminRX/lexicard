--[[
Lexicard configuration: KEY=value lines in the plugin's .env file, plus defaults.
]]
local Config = {}

Config.DEFAULTS = {
    GEMINI_MODEL = "gemini-3.5-flash-lite",
    GEMINI_FALLBACK_MODEL = "gemini-3.6-flash",
    ANKI_DECK = "Reading vocabulary",
    ANKI_NOTE_TYPE = "Lexicard",
    LEARNER_NATIVE_LANGUAGE = "Spanish (Mexico)",
    LEARNER_LEVEL = "B1-B2",
    TLS_VERIFY = "true",
    AUDIO = "word",
    TTS_MODEL = "gemini-3.8-flash-lite-tts",
    TTS_VOICE = "Kore",
}

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function Config.parse(text)
    local values = {}
    for raw in (text .. "\n"):gmatch("(.-)\r?\n") do
        local line = trim(raw)
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local key, value = line:match("^([%w_]+)%s*=%s*(.*)$")
            if key then
                local quote = value:sub(1, 1)
                if (quote == '"' or quote == "'") and #value >= 2 and value:sub(-1) == quote then
                    value = value:sub(2, -2)
                else
                    value = trim((value:gsub("%s+#.*$", "")))
                end
                values[key] = value
            end
        end
    end
    return values
end

local function split_urls(s)
    local urls = {}
    for url in (s or ""):gmatch("[^,%s]+") do urls[#urls + 1] = url end
    return urls
end

local AUDIO_MODES = { word = true, ["word+example"] = true, off = true }

function Config.from_values(values)
    local v = {}
    for key, default in pairs(Config.DEFAULTS) do v[key] = default end
    for key, value in pairs(values) do
        if value ~= "" then v[key] = value end
    end
    return {
        gemini_api_key = v.GEMINI_API_KEY or "",
        gemini_model = v.GEMINI_MODEL,
        gemini_fallback_model = v.GEMINI_FALLBACK_MODEL,
        ankiconnect_urls = split_urls(v.ANKICONNECT_URLS),
        ankiconnect_api_key = v.ANKICONNECT_API_KEY or "",
        anki_deck = v.ANKI_DECK,
        anki_note_type = v.ANKI_NOTE_TYPE,
        native_language = v.LEARNER_NATIVE_LANGUAGE,
        level = v.LEARNER_LEVEL,
        tls_verify = v.TLS_VERIFY:lower() ~= "false",
        gemini_thinking = v.GEMINI_THINKING or "",
        audio = AUDIO_MODES[v.AUDIO:lower()] and v.AUDIO:lower() or "word",
        tts_model = v.TTS_MODEL,
        tts_voice = v.TTS_VOICE,
    }
end

-- Returns the config and whether the file existed.
function Config.load(path)
    local f = io.open(path, "r")
    if not f then return Config.from_values({}), false end
    local text = f:read("*a")
    f:close()
    return Config.from_values(Config.parse(text)), true
end

function Config.missing(cfg)
    local missing = {}
    if cfg.gemini_api_key == "" then missing[#missing + 1] = "GEMINI_API_KEY" end
    if #cfg.ankiconnect_urls == 0 then missing[#missing + 1] = "ANKICONNECT_URLS" end
    return missing
end

return Config
