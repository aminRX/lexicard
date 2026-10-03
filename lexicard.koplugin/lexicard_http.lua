--[[
HTTP(S) transport for KOReader; runs inside a Trapper subprocess.
transport(request) -> status_code, body | nil, error
HTTPS certificates are checked against KOReader's bundled CA file.
]]
local http = require("socket.http")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")

local Http = {}

Http.CA_FILE = "data/ca-bundle.crt" -- relative to KOReader's install folder (its working directory)

local function file_exists(path)
    local f = io.open(path, "r")
    if f then f:close() end
    return f ~= nil
end

function Http.transport(verify_tls)
    return function(request)
        local sink, headers = {}, {}
        for k, v in pairs(request.headers or {}) do headers[k] = v end
        local source
        if request.body then
            headers["Content-Length"] = tostring(#request.body)
            source = ltn12.source.string(request.body)
        end
        local req = {
            url = request.url,
            method = request.method or "GET",
            headers = headers,
            source = source,
            sink = socketutil.table_sink(sink),
        }
        if verify_tls and request.url:match("^https://") then
            if not file_exists(Http.CA_FILE) then
                return nil, "certificate bundle not found: " .. Http.CA_FILE
            end
            req.verify = "peer"
            req.cafile = Http.CA_FILE
        end
        socketutil:set_timeout(request.block_timeout or 10, request.total_timeout or 30)
        local ok, code = pcall(function() return socket.skip(1, http.request(req)) end)
        socketutil:reset_timeout()
        if not ok or type(code) ~= "number" then return nil, tostring(code) end
        return code, table.concat(sink)
    end
end

return Http
