local Checks = require("card_checks")

local function names_failed(list)
    local failed = {}
    for _, c in ipairs(list) do
        if not c.ok then failed[#failed + 1] = c.name end
    end
    return failed
end

local GOOD_FIELDS = {
    Headword = "call off", Definition = "to decide that a planned event will not happen",
    Example = "They <b>called off</b> the game because of rain.", Spanish = "cancelar / suspender",
    Warning = "", PronTip = "", IPA = "/ˌkɔl ˈɔf/", Cloze = "They c____ ____ the game because of rain.",
}

describe("Checks.run", function()
    it("passes a good card", function()
        local case = { word = "called", sentence = "We ⟦called⟧ the meeting off and went home.",
                       expect = { headword = "call off", trap = "none" } }
        assert_same(names_failed(Checks.run(case, { ok = true }, GOOD_FIELDS)), {})
    end)
    it("flags the headword in the definition, a copied example and duplicate Spanish", function()
        local fields = {}
        for k, v in pairs(GOOD_FIELDS) do fields[k] = v end
        fields.Definition = "to call something off"
        fields.Example = "We <b>called</b> the meeting off and went home."
        fields.Spanish = "renuente / renuente a"
        local case = { word = "called", sentence = "We ⟦called⟧ the meeting off and went home.", expect = {} }
        assert_same(names_failed(Checks.run(case, { ok = true }, fields)),
            { "definition_no_headword", "example_new", "spanish_clean" })
    end)
    it("expects a warning for a false friend and none otherwise", function()
        local case = { word = "realized", sentence = "", expect = { trap = "false_friend" } }
        assert_same(names_failed(Checks.run(case, { ok = true }, GOOD_FIELDS)), { "warning_false_friend" })
    end)
    it("checks the status of names", function()
        local case = { word = "Vin", sentence = "", expect = { status = "proper_noun" } }
        assert_same(names_failed(Checks.run(case, { ok = false, kind = "not_a_word", status = "proper_noun" })), {})
    end)
    it("flags spelling talk and IPA that doesn't match the words", function()
        local fields = {}
        for k, v in pairs(GOOD_FIELDS) do fields[k] = v end
        fields.PronTip = "Cuidado con la doble t."
        fields.IPA = "/opak/"
        local case = { word = "called", sentence = "", expect = {} }
        assert_same(names_failed(Checks.run(case, { ok = true }, fields)), { "pron_tip_no_spelling", "ipa_words" })
    end)
end)
