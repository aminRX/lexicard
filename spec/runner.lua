-- Minimal test runner for Lexicard. No dependencies: run `luajit spec/runner.lua [filter]` from the repo root.
package.path = "lexicard.koplugin/?.lua;spec/support/?.lua;tools/?.lua;scripts/lib/?.lua;" .. package.path

local tests, names, hooks = {}, {}, {}

local function fmt(v)
    if type(v) == "string" then return string.format("%q", v) end
    if type(v) ~= "table" then return tostring(v) end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. fmt(v[k]) end
    return "{" .. table.concat(parts, ", ") .. "}"
end

local function deep_equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do
        if not deep_equal(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

function describe(name, fn)
    names[#names + 1] = name
    local hook_count = #hooks
    fn()
    for i = #hooks, hook_count + 1, -1 do hooks[i] = nil end
    names[#names] = nil
end

function before_each(fn)
    hooks[#hooks + 1] = fn
end

function it(name, fn)
    local copy = {}
    for i, h in ipairs(hooks) do copy[i] = h end
    tests[#tests + 1] = { name = table.concat(names, " > ") .. " > " .. name, fn = fn, hooks = copy }
end

function assert_eq(actual, expected, msg)
    if actual ~= expected then
        error((msg and (msg .. ": ") or "") .. "expected " .. fmt(expected) .. ", got " .. fmt(actual), 2)
    end
end

function assert_same(actual, expected, msg)
    if not deep_equal(actual, expected) then
        error((msg and (msg .. ": ") or "") .. "expected " .. fmt(expected) .. ", got " .. fmt(actual), 2)
    end
end

function assert_true(value, msg)
    if not value then error(msg or "expected a truthy value", 2) end
end

function assert_match(text, pattern, msg)
    if type(text) ~= "string" or not text:find(pattern) then
        error((msg and (msg .. ": ") or "") .. fmt(text) .. " does not match " .. fmt(pattern), 2)
    end
end

local filter = arg[1]
local listing = io.popen("ls spec/*_spec.lua")
for file in listing:lines() do
    if not filter or file:find(filter, 1, true) then dofile(file) end
end
listing:close()

local failures = {}
for _, t in ipairs(tests) do
    local ok, err = pcall(function()
        for _, h in ipairs(t.hooks) do h() end
        t.fn()
    end)
    io.write(ok and "." or "F")
    if not ok then failures[#failures + 1] = { name = t.name, err = err } end
end
print()
for _, f in ipairs(failures) do
    print("FAIL: " .. f.name .. "\n      " .. tostring(f.err))
end
print(("%d tests, %d failed"):format(#tests, #failures))
os.exit(#failures == 0 and 0 or 1)
