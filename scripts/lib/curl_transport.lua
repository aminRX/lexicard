-- HTTP transport for Mac scripts, using curl. Same contract as lexicard_http.
-- Headers and body go through temporary files so keys never appear in `ps`.
local Curl = {}

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

function Curl.transport(request)
    local header_file, body_file, out_file = os.tmpname(), os.tmpname(), os.tmpname()
    local hf = assert(io.open(header_file, "w"))
    for k, v in pairs(request.headers or {}) do hf:write(k, ": ", v, "\n") end
    hf:close()
    local cmd = { "curl", "-s", "-X", request.method or "GET", "-H", "@" .. header_file,
                  "--max-time", tostring(request.total_timeout or 30), "-o", out_file, "-w", "%{http_code}" }
    if request.body then
        local bf = assert(io.open(body_file, "w"))
        bf:write(request.body)
        bf:close()
        cmd[#cmd + 1] = "--data-binary"
        cmd[#cmd + 1] = "@" .. body_file
    end
    cmd[#cmd + 1] = request.url
    local quoted = {}
    for i, part in ipairs(cmd) do quoted[i] = shell_quote(part) end
    local pipe = io.popen(table.concat(quoted, " "))
    local status = pipe:read("*a")
    pipe:close()
    local of = io.open(out_file, "r")
    local body = of and of:read("*a") or ""
    if of then of:close() end
    os.remove(header_file)
    os.remove(body_file)
    os.remove(out_file)
    local code = tonumber(status)
    if not code or code == 0 then return nil, "curl failed (HTTP " .. tostring(status) .. ")" end
    return code, body
end

return Curl
