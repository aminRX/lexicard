local Arpabet = require("arpabet")

describe("Arpabet.to_ipa", function()
    local cases = {
        { "G IH1 V", "ɡɪv" },
        { "R IH0 L AH1 K T AH0 N T", "rɪˈlʌktənt" },
        { "R UW1 TH L AH0 S N AH0 S", "ˈruθləsnəs" },
        { "AH0 B AW1 T", "əˈbaʊt" },
        { "AH2 N D ER0 S T AE1 N D", "ˌʌndɚˈstænd" },
        { "EH1 K S T R AH0", "ˈɛkstrə" },
        { "EH0 M P L OY1", "ɛmˈplɔɪ" },
        { "AE1 K CH UW0 AH0 L IY0", "ˈæktʃuəli" },
        { "F R AY1 T AH0 N D", "ˈfraɪtənd" },
        { "B ER1 D", "bɝd" },
    }
    for _, case in ipairs(cases) do
        it(case[1] .. " → " .. case[2], function()
            assert_eq(Arpabet.to_ipa(case[1]), case[2])
        end)
    end
    it("returns nil for unknown symbols", function()
        assert_eq(Arpabet.to_ipa("XX1"), nil)
    end)
end)
