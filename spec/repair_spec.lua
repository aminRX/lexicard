local Repair = require("lexicard_repair")

local function card(over)
    local c = { headword = "word", surface = "word", pos = "noun", register = "neutral", ipa = "",
                spanish = { "palabra" }, trap = "none", warning = "", sound = "none", pron_tip = "" }
    for k, v in pairs(over or {}) do c[k] = v end
    return c
end

describe("Repair.warning", function()
    it("keeps a false-friend warning that names the look-alike", function()
        local w, trap = Repair.warning(card({ headword = "realize", trap = "false_friend",
            warning = "Falso amigo: ✗ «realizar» → ✓ «darse cuenta»" }))
        assert_eq(w, "Falso amigo: ✗ «realizar» → ✓ «darse cuenta»")
        assert_eq(trap, "false_friend")
    end)
    it("drops a 'false friend' that is really an English comparison", function()
        local w, trap = Repair.warning(card({ headword = "reluctant", trap = "false_friend",
            warning = "No lo confundas con «reticent»." }))
        assert_eq(w, "")
        assert_eq(trap, "none")
    end)
    it("drops warnings when trap is none and fills known false friends", function()
        assert_eq((Repair.warning(card({ headword = "walk", warning = "Cuidado." }))), "")
        assert_eq((Repair.warning(card({ headword = "actually" }))), "Falso amigo: ✗ «actualmente» → ✓ «en realidad»")
    end)
    it("checks preposition and register warnings", function()
        assert_eq((Repair.warning(card({ headword = "depend on", trap = "preposition", warning = "✗ depend of → ✓ depend on" }))),
            "✗ depend of → ✓ depend on")
        assert_eq((Repair.warning(card({ headword = "rely", trap = "preposition", warning = "Úsalo bien." }))), "")
        assert_eq((Repair.warning(card({ headword = "gloaming", trap = "register", warning = "Muy literario." }))), "")
        assert_eq((Repair.warning(card({ headword = "gloaming", trap = "register", register = "literary",
            warning = "Muy literario." }))), "Muy literario.")
    end)
end)

describe("Repair.pron_tip", function()
    it("keeps a tip that quotes a sound from the IPA", function()
        assert_eq(Repair.pron_tip(card({ headword = "leisurely", ipa = "/ˈlizərli/", sound = "vowels",
            pron_tip = "La primera sílaba es /li/, como «li»." })), "La primera sílaba es /li/, como «li».")
    end)
    it("drops invented or spelling tips", function()
        assert_eq(Repair.pron_tip(card({ ipa = "/ˈlizərli/", sound = "vowels", pron_tip = "Suena como «lé»." })), "")
        assert_eq(Repair.pron_tip(card({ ipa = "/rɪˈlʌktənt/", sound = "stress", pron_tip = "Cuidado con la doble t: /lʌk/." })), "")
        assert_eq(Repair.pron_tip(card({ ipa = "/rʌn/", sound = "none", pron_tip = "Es /rʌn/." })), "")
        assert_eq(Repair.pron_tip(card({ headword = "run", surface = "ran", ipa = "/rʌn/", sound = "ed_ending",
            pron_tip = "La -ed es /d/." })), "")
    end)
end)

describe("Repair.spanish", function()
    it("removes duplicates, look-alikes and vulgar words", function()
        assert_same(Repair.spanish(card({ headword = "reluctant", spanish = { "renuente", "renuente a", "reacio" } })),
            { "renuente", "reacio" })
        assert_same(Repair.spanish(card({ headword = "actually", spanish = { "actualmente", "en realidad" } })),
            { "en realidad" })
        assert_same(Repair.spanish(card({ headword = "lit", spanish = { "chingón", "buenísimo" } })), { "buenísimo" })
        assert_same(Repair.spanish(card({ headword = "lit", register = "slang", spanish = { "chingón" } })), { "chingón" })
    end)
    it("never leaves the card without Spanish", function()
        assert_same(Repair.spanish(card({ headword = "actually", spanish = { "actualmente" } })), { "actualmente" })
    end)
end)

describe("Repair.warning confusables", function()
    it("fills a missing warning for a known confusable pair", function()
        local w, trap = Repair.warning(card({ headword = "borrow" }))
        assert_eq(w, "En español ambos son «prestar»: borrow = pedir prestado; lend = prestar a alguien")
        assert_eq(trap, "confusable")
    end)
end)
