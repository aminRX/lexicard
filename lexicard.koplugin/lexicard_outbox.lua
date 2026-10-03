--[[
Notes waiting for Anki, saved as a JSON array. Writes go to a temporary file
that is then renamed, so a crash or flat battery can't leave half a file.
]]
local Json = require("lexicard_json")

local Outbox = {}
Outbox.__index = Outbox

-- Items from a file; nil if the file doesn't exist, false if it is corrupt.
local function read_items(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    local data = Json.decode(text)
    if type(data) ~= "table" then return false end
    local items = {}
    for _, item in ipairs(data) do
        if type(item) == "table" and type(item.id) == "string" and type(item.note) == "table" then
            items[#items + 1] = item
        end
    end
    return items
end

function Outbox.open(path)
    local self = setmetatable({ path = path, items = {} }, Outbox)
    local from_tmp = read_items(path .. ".tmp")
    if from_tmp then
        self.items = from_tmp
        os.rename(path .. ".tmp", path)
        return self
    end
    local items = read_items(path)
    if items == false then
        os.rename(path, path .. ".corrupt")
    elseif items then
        self.items = items
    end
    return self
end

function Outbox:save()
    local tmp = self.path .. ".tmp"
    local f = assert(io.open(tmp, "w"))
    f:write(Json.encode(Json.array(self.items)))
    f:close()
    assert(os.rename(tmp, self.path))
end

local counter = 0

function Outbox:add(note, now)
    counter = counter + 1
    now = now or os.time()
    local item = {
        id = ("%d-%d-%d"):format(now, counter, math.random(1000000)),
        created_at = now,
        note = note,
        attempts = 0,
        last_error = "",
    }
    self.items[#self.items + 1] = item
    self:save()
    return item
end

function Outbox:count()
    return #self.items
end

-- Applies delivery outcomes ({id, kind, message}) and returns a summary.
function Outbox:apply(outcomes)
    local by_id = {}
    for _, o in ipairs(outcomes or {}) do
        if o.id then by_id[o.id] = o end
    end
    local summary = { sent = 0, duplicates = {}, failed = 0, remaining = 0 }
    local keep = {}
    for _, item in ipairs(self.items) do
        local o = by_id[item.id]
        if o and o.kind == "ok" then
            summary.sent = summary.sent + 1
        elseif o and o.kind == "duplicate" then
            local fields = type(item.note.fields) == "table" and item.note.fields or {}
            summary.duplicates[#summary.duplicates + 1] = fields.Headword or "?"
        else
            if o and o.kind ~= "unreachable" then
                item.attempts = (item.attempts or 0) + 1
                item.last_error = o.message or o.kind
                summary.failed = summary.failed + 1
            end
            keep[#keep + 1] = item
        end
    end
    self.items = keep
    summary.remaining = #keep
    self:save()
    return summary
end

function Outbox.summary_text(summary)
    local parts = {}
    if summary.sent > 0 then parts[#parts + 1] = ("Sent %d"):format(summary.sent) end
    if #summary.duplicates > 0 then
        parts[#parts + 1] = ("%d already in deck (%s)"):format(#summary.duplicates, table.concat(summary.duplicates, ", "))
    end
    if summary.failed > 0 then parts[#parts + 1] = ("%d failed"):format(summary.failed) end
    if summary.remaining > 0 then parts[#parts + 1] = ("%d still waiting"):format(summary.remaining) end
    return table.concat(parts, " · ")
end

return Outbox
