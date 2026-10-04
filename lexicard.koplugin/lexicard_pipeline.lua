--[[
Everything that runs after Gemini and before the preview.
]]
local Ipa = require("lexicard_ipa")

local Pipeline = {}

function Pipeline.finish(card, input, ipa_path)
    card.ipa = Ipa.for_headword(ipa_path, card.headword, card.ipa) or card.ipa
    return card
end

return Pipeline
