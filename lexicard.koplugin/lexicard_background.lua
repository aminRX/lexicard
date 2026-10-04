--[[
Runs a task in a KOReader subprocess without blocking the reader. on_done(result) runs on
the main process when the task ends (nil if it crashed). The result must be plain data:
strings, numbers, booleans and tables of those.
]]
local buffer = require("string.buffer")
local ffiutil = require("ffi/util")
local UIManager = require("ui/uimanager")
local logger = require("logger")

local Background = {}

local POLL_SECONDS = 1

local function collect_later(pid)
    local function collect()
        if not ffiutil.isSubProcessDone(pid) then UIManager:scheduleIn(POLL_SECONDS, collect) end
    end
    UIManager:scheduleIn(POLL_SECONDS, collect)
end

function Background.run(task, on_done)
    local pid, fd = ffiutil.runInSubProcess(function(_, child_fd)
        local ok, encoded = pcall(function() return buffer.encode(table.pack(task())) end)
        if not ok then logger.warn("Lexicard: background task failed:", encoded) end
        ffiutil.writeToFD(child_fd, ok and encoded or "", true)
    end, true)
    if not pid then
        on_done(nil)
        return
    end
    local function poll()
        local done = ffiutil.isSubProcessDone(pid)
        if not done and ffiutil.getNonBlockingReadSize(fd) == 0 then
            UIManager:scheduleIn(POLL_SECONDS, poll)
            return
        end
        local output = ffiutil.readAllFromFD(fd)
        if not done then collect_later(pid) end
        local ok, packed = pcall(buffer.decode, output or "")
        on_done(ok and type(packed) == "table" and packed[1] or nil)
    end
    UIManager:scheduleIn(POLL_SECONDS, poll)
end

return Background
