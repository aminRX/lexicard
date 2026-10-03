-- Converts CMUdict to lexicard.koplugin/data/cmudict-ipa.tsv ("word<TAB>ipa1|ipa2", byte-sorted).
-- Usage: luajit scripts/build-ipa-dict.lua build/cmudict.dict lexicard.koplugin/data/cmudict-ipa.tsv
package.path = "tools/?.lua;" .. package.path
local Arpabet = require("arpabet")

local input, output = arg[1], arg[2]
assert(input and output, "usage: luajit scripts/build-ipa-dict.lua INPUT OUTPUT")

local entries, order, skipped = {}, {}, 0
for line in io.lines(input) do
    line = line:gsub("%s*#.*$", "")
    local word, phones = line:match("^(%S+)%s+(.+)$")
    if word then
        word = word:gsub("%(%d+%)$", ""):lower()
        local ipa = Arpabet.to_ipa(phones)
        if ipa then
            if not entries[word] then
                entries[word] = {}
                order[#order + 1] = word
            end
            local seen = false
            for _, v in ipairs(entries[word]) do
                if v == ipa then seen = true end
            end
            if not seen then table.insert(entries[word], ipa) end
        else
            skipped = skipped + 1
        end
    end
end
table.sort(order)

local f = assert(io.open(output, "w"))
for _, word in ipairs(order) do
    f:write(word, "\t", table.concat(entries[word], "|"), "\n")
end
f:close()
print(("wrote %d words to %s (%d entries skipped)"):format(#order, output, skipped))
