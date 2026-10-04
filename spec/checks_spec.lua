local Checks = require("card_checks")

local function names_failed(list)
    local failed = {}
    for _, c in ipairs(list) do
        if not c.ok then failed[#failed + 1] = c.name end
    end
    return failed
end

local function good_card()
    return {
        headword = "call off", definition = "to decide that a planned event will not happen",
        spanish = { "cancelar", "suspender" }, warning = "", ipa = "/ˌkɔl ˈɔf/",
        usage = { { pattern = "call off + something", example = "They <b>called off</b> the game." },
                  { pattern = "call something off", example = "We <b>called</b> the party <b>off</b>." } },
        picture_format = "before_after", picture_scene = "Two panels: a sunny football game, then rain and an empty field.",
        picture_caption = "They <b>called off</b> the game.",
    }
end

describe("Checks.run", function()
    it("passes a good card", function()
        local case = { word = "called", sentence = "We ⟦called⟧ the meeting off and went home.",
                       expect = { headword = "call off", trap = "none" } }
        assert_same(names_failed(Checks.run(case, { ok = true, card = good_card() })), {})
    end)
    it("flags copied examples, few patterns, book names and long captions", function()
        local card = good_card()
        card.usage = { { pattern = "x", example = "Vin <b>called</b> the meeting off at home." } }
        card.picture_caption = "One two three four five six seven eight nine ten eleven <b>x</b>"
        card.picture_scene = "Vin in a dark alley."
        local case = { word = "called", sentence = "Then Vin ⟦called⟧ the meeting off at home.", expect = {} }
        assert_same(names_failed(Checks.run(case, { ok = true, card = card })),
            { "usage_count", "example_new", "no_book_names", "caption_short" })
    end)
    it("expects a warning for a false friend and none otherwise", function()
        local case = { word = "realized", sentence = "", expect = { trap = "false_friend" } }
        assert_same(names_failed(Checks.run(case, { ok = true, card = good_card() })), { "warning_false_friend" })
    end)
    it("checks the status of names", function()
        local case = { word = "Vin", sentence = "", expect = { status = "proper_noun" } }
        assert_same(names_failed(Checks.run(case, { ok = false, kind = "not_a_word", status = "proper_noun" })), {})
    end)
end)
