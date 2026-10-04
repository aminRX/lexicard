--[[
Everything that runs after Gemini and before the preview:
the IPA from the dictionary first, then the repairs.
]]
local Ipa = require("lexicard_ipa")
local Repair = require("lexicard_repair")

local Pipeline = {}

function Pipeline.finish(card, input, ipa_path)
    card.surface = input.word
    card.ipa = Ipa.for_card(ipa_path, card)
    return Repair.apply(card)
end

return Pipeline
