--[[
Card pictures from Cloudflare Workers AI (FLUX.2 [klein]). The picture comes back as a
base64 JPEG that goes straight to AnkiConnect: it lives only in memory and is never
written to the Kindle. Failures return nil plus a short reason; the card is then sent
without a picture.
]]
local Config = require("lexicard_config")
local Json = require("lexicard_json")

local Picture = {}

Picture.BASE_URL = "https://api.cloudflare.com/client/v4/"
Picture.STYLE = "Simple, friendly flat illustration in a picture-dictionary style, clean outlines, soft colors, "
    .. "plain light background, no text, no letters, no numbers."
Picture.WIDTH, Picture.HEIGHT = 1024, 768

local REASONS = {
    [401] = "check the Cloudflare token",
    [403] = "check the Cloudflare token",
    [429] = "daily picture limit reached",
}

-- The text prompt for a card, or nil when the card has no picture design.
function Picture.prompt(card)
    local scene = card.picture_scene or ""
    if scene == "" then return nil end
    return scene .. " " .. Picture.STYLE
end

-- multipart/form-data body from {{name, value}, ...}; returns body, content type.
function Picture.multipart(fields, boundary)
    local parts = {}
    for _, field in ipairs(fields) do
        parts[#parts + 1] = "--" .. boundary .. "\r\nContent-Disposition: form-data; name=\"" .. field[1]
            .. "\"\r\n\r\n" .. field[2] .. "\r\n"
    end
    parts[#parts + 1] = "--" .. boundary .. "--\r\n"
    return table.concat(parts), "multipart/form-data; boundary=" .. boundary
end

-- Base64 JPEG for the prompt, or nil plus a reason.
function Picture.draw(cfg, prompt, transport)
    if not prompt or prompt == "" then return nil, "nothing to draw" end
    local boundary = ("lexicard%d%06d"):format(os.time(), math.random(0, 999999))
    local body, content_type = Picture.multipart({
        { "prompt", prompt }, { "width", tostring(Picture.WIDTH) }, { "height", tostring(Picture.HEIGHT) },
    }, boundary)
    local code, reply = transport({
        method = "POST",
        url = Picture.BASE_URL .. "accounts/" .. cfg.cloudflare_account_id .. "/ai/run/" .. cfg.image_model,
        headers = { ["Content-Type"] = content_type, Authorization = "Bearer " .. cfg.cloudflare_api_token },
        body = body,
        block_timeout = 45,
        total_timeout = 60,
    })
    if type(code) ~= "number" then return nil, "network error" end
    if code ~= 200 then return nil, REASONS[code] or ("Cloudflare HTTP " .. code) end
    local data = Json.decode(reply or "")
    local result = type(data) == "table" and data.result
    local image = type(result) == "table" and result.image
    if type(image) ~= "string" or image == "" then return nil, "no picture in reply" end
    return image
end

-- Free token check: {ok = true} or {ok = false, message}.
function Picture.check(cfg, transport)
    if not Config.pictures_enabled(cfg) then
        return { ok = false, message = "off (no CLOUDFLARE_ACCOUNT_ID / CLOUDFLARE_API_TOKEN in .env)" }
    end
    local code, reply = transport({
        method = "GET",
        url = Picture.BASE_URL .. "user/tokens/verify",
        headers = { Authorization = "Bearer " .. cfg.cloudflare_api_token },
        block_timeout = 10,
        total_timeout = 15,
    })
    local data = Json.decode(reply or "")
    if code == 200 and type(data) == "table" and data.success == true then return { ok = true } end
    return { ok = false, message = type(code) == "number" and ("HTTP " .. code) or tostring(reply) }
end

return Picture
