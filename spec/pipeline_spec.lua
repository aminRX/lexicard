local Pipeline = require("lexicard_pipeline")

local function write(lines)
    local path = os.tmpname()
    local f = assert(io.open(path, "w"))
    f:write(table.concat(lines, "\n"), "\n")
    f:close()
    return path
end

describe("Pipeline.finish", function()
    it("sets the IPA from the dictionary, then repairs warnings and tips", function()
        local path = write({ "actually\tˈæktʃuəli" })
        local card = Pipeline.finish({
            headword = "actually", pos = "adverb", ipa = "/ˈæk.tʃu.əl.i/", register = "neutral",
            spanish = { "actualmente", "en realidad" }, trap = "none", warning = "", sound = "stress",
            pron_tip = "Cuidado con la doble l.",
        }, { word = "actually", sentence = "" }, path)
        os.remove(path)
        assert_eq(card.ipa, "/ˈæktʃuəli/")
        assert_eq(card.surface, "actually")
        assert_eq(card.warning, "Falso amigo: ✗ «actualmente» → ✓ «en realidad»")
        assert_eq(card.pron_tip, "")
        assert_same(card.spanish, { "en realidad" })
    end)
end)
