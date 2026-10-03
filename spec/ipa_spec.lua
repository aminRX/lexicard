local Ipa = require("lexicard_ipa")

local function write(lines)
    local path = os.tmpname()
    local f = assert(io.open(path, "w"))
    f:write(table.concat(lines, "\n"), "\n")
    f:close()
    return path
end

local SMALL = { "bank\tbæŋk", "give\tɡɪv", "read\trɛd|rid", "up\tʌp" }

describe("Ipa.lookup", function()
    it("finds words in a small sorted file", function()
        local path = write(SMALL)
        assert_same(Ipa.lookup(path, "give"), { "ɡɪv" })
        assert_same(Ipa.lookup(path, "read"), { "rɛd", "rid" })
        assert_eq(Ipa.lookup(path, "zebra"), nil)
        assert_eq(Ipa.lookup(path, "aardvark"), nil)
        os.remove(path)
    end)
    it("finds every probed word in a large file", function()
        local lines = {}
        for i = 1, 20000 do lines[i] = ("w%05d\tipa%d"):format(i, i) end
        local path = write(lines)
        for _, i in ipairs({ 1, 2, 777, 10000, 19999, 20000 }) do
            assert_same(Ipa.lookup(path, ("w%05d"):format(i)), { "ipa" .. i })
        end
        assert_eq(Ipa.lookup(path, "w20001"), nil)
        os.remove(path)
    end)
    it("returns nil when the file is missing", function()
        assert_eq(Ipa.lookup("/nonexistent/cmudict-ipa.tsv", "give"), nil)
    end)
end)

describe("Ipa.for_headword", function()
    it("joins unambiguous words and refuses ambiguous or unknown ones", function()
        local path = write(SMALL)
        assert_eq(Ipa.for_headword(path, "give up"), "/ɡɪv ʌp/")
        assert_eq(Ipa.for_headword(path, "Bank"), "/bæŋk/")
        assert_eq(Ipa.for_headword(path, "read"), nil)
        assert_eq(Ipa.for_headword(path, "give in"), nil)
        os.remove(path)
    end)
end)
