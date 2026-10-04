--[[
The Gemini prompt: system instruction with reference lists and five worked
examples, the tagged user message, and the JSON schema of the reply.
]]
local Json = require("lexicard_json")
local Traps = require("lexicard_traps")

local Prompt = {}

Prompt.SCHEMA_JSON = [=[{
  "type": "object",
  "properties": {
    "status": {"type": "string", "enum": ["ok", "proper_noun", "not_english", "unclear"]},
    "expression_in_text": {"type": "string", "description": "The whole unit the held word belongs to, copied exactly from the sentence (\"gave it up\")"},
    "headword": {"type": "string", "description": "Dictionary form of that unit (\"give up\", \"seek\")"},
    "pos": {"type": "string", "enum": ["noun", "verb", "adjective", "adverb", "phrasal verb", "idiom", "preposition", "conjunction", "other"]},
    "sense": {"type": "string", "description": "At most 12 plain words: the meaning in THIS sentence"},
    "ipa": {"type": "string", "description": "General American IPA of the headword (not the inflected word), word by word, between slashes"},
    "pattern": {"type": "string", "description": "How it is used, with sb/sth (\"give sth up\", \"depend on sth\"); \"\" if nothing to add"},
    "register": {"type": "string", "enum": ["neutral", "informal", "formal", "literary", "slang", "old-fashioned", "offensive"]},
    "definition": {"type": "string", "description": "At most 15 common words, dictionary style (\"to ...\" for verbs), never the headword or its family"},
    "spanish": {"type": "array", "items": {"type": "string"}, "maxItems": 3, "description": "1-3 Mexican Spanish equivalents with the same meaning and register"},
    "trap": {"type": "string", "enum": ["none", "false_friend", "preposition", "calque", "confusable", "register"]},
    "warning": {"type": "string", "description": "In Spanish, written \"✗ ... → ✓ ...\", only when trap is not none; otherwise \"\""},
    "sound": {"type": "string", "enum": ["none", "v_b", "short_i", "vowels", "schwa", "s_cluster", "ed_ending", "z_sound", "th", "j_y", "sh_ch", "h_sound", "final_cluster", "stress", "silent_letter"]},
    "pron_tip": {"type": "string", "description": "In Spanish, at most 15 words, about sounds, quoting the /ipa/ segment, only when sound is not none; otherwise \"\""},
    "example": {"type": "string", "description": "At most 12 everyday words, built differently from the book's sentence, the expression in <b></b>"},
    "collocations": {"type": "array", "items": {"type": "string"}, "maxItems": 3, "description": "Frequent word partners for this meaning; [] if unsure"}
  },
  "required": ["status", "expression_in_text", "headword", "pos", "sense", "ipa", "pattern", "register", "definition", "spanish", "trap", "warning", "sound", "pron_tip", "example", "collocations"]
}]=]

local SYSTEM_TEMPLATE = [=[
You write one Anki vocabulary card for an adult native speaker of %NATIVE% (level %LEVEL%) who is learning English by reading novels on a Kindle. They held one word; in the sentence it is marked like ⟦this⟧.

1. Card the whole unit the held word belongs to (a phrasal verb, even when split like "gave it up"; an idiom; a fixed phrase; a compound) in its dictionary form.
2. Describe only the meaning used in this sentence; write `sense` first, in plain words.
3. Write for this learner: simple, common English in the definition and the example; natural Spanish that someone from Mexico would say, with the same meaning and register.
4. Flag only real traps for Spanish speakers, using the lists below. When you are not sure, use "none" and "".
5. Keep every field within the limits in the schema descriptions.
6. If the held word is a name, isn't English or can't be read, set status to proper_noun, not_english or unclear, use "" or [] for the text fields, pos "other", register "neutral", trap "none" and sound "none".

%LISTS%

<example>
<book>Example Book — Example Author</book>
<sentence>She tried the violin for years, but last winter she finally ⟦gave⟧ it up.</sentence>
<word>gave</word>
{"status":"ok","expression_in_text":"gave it up","headword":"give up","pos":"phrasal verb","sense":"stopped doing an activity she did regularly","ipa":"/ˌɡɪv ˈʌp/","pattern":"give sth up","register":"neutral","definition":"to stop doing something that you did regularly","spanish":["dejar","abandonar"],"trap":"none","warning":"","sound":"none","pron_tip":"","example":"I <b>gave up</b> coffee a month ago.","collocations":["give up smoking","give up hope"]}
</example>

<example>
<book>Example Book — Example Author</book>
<sentence>For many years the old monk ⟦sought⟧ the truth in silence.</sentence>
<word>sought</word>
{"status":"ok","expression_in_text":"sought","headword":"seek","pos":"verb","sense":"looked for something important for a long time","ipa":"/sik/","pattern":"seek sth","register":"formal","definition":"to try to find or get something","spanish":["buscar"],"trap":"none","warning":"","sound":"none","pron_tip":"","example":"Many people <b>seek</b> advice from friends.","collocations":["seek help","seek advice"]}
</example>

<example>
<book>Example Book — Example Author</book>
<sentence>He looked calm, but he was ⟦actually⟧ terrified of the dark.</sentence>
<word>actually</word>
{"status":"ok","expression_in_text":"actually","headword":"actually","pos":"adverb","sense":"in reality, although it seemed different","ipa":"/ˈæktʃuəli/","pattern":"","register":"neutral","definition":"used to say what is really true, often something surprising","spanish":["en realidad","de hecho"],"trap":"false_friend","warning":"Falso amigo: ✗ «actualmente» → ✓ «en realidad»","sound":"none","pron_tip":"","example":"I thought it was hard, but it was <b>actually</b> easy.","collocations":[]}
</example>

<example>
<book>Example Book — Example Author</book>
<sentence>Our plans for the trip ⟦depend⟧ on how much money we save.</sentence>
<word>depend</word>
{"status":"ok","expression_in_text":"depend on","headword":"depend on","pos":"verb","sense":"are decided by something else","ipa":"/dɪˈpɛnd ɑn/","pattern":"depend on sth","register":"neutral","definition":"to change according to something else","spanish":["depender de"],"trap":"preposition","warning":"✗ depend of → ✓ depend on","sound":"none","pron_tip":"","example":"The price <b>depends on</b> the size.","collocations":["it depends"]}
</example>

<example>
<book>Example Book — Example Author</book>
<sentence>I stayed home because I felt a bit ⟦under⟧ the weather.</sentence>
<word>under</word>
{"status":"ok","expression_in_text":"under the weather","headword":"under the weather","pos":"idiom","sense":"slightly sick","ipa":"/ˈʌndər ðə ˈwɛðər/","pattern":"feel under the weather","register":"informal","definition":"slightly ill","spanish":["un poco enfermo","indispuesto"],"trap":"none","warning":"","sound":"th","pron_tip":"Pon la lengua entre los dientes para /ð/; no es /d/.","example":"Sorry, I'm a little <b>under the weather</b> today.","collocations":["feel under the weather"]}
</example>

Reply with the JSON object only.]=]

function Prompt.system_instruction(cfg)
    return (SYSTEM_TEMPLATE:gsub("%%(%u+)%%", {
        NATIVE = cfg.native_language, LEVEL = cfg.level, LISTS = Traps.prompt_lists(),
    }))
end

function Prompt.user_message(input)
    local book = input.book_title or ""
    if (input.book_author or "") ~= "" then book = book .. " — " .. input.book_author end
    return "<book>" .. book .. "</book>\n"
        .. "<sentence>" .. (input.sentence or "") .. "</sentence>\n"
        .. "<word>" .. (input.word or "") .. "</word>"
end

-- The generateContent body. `thinking_level` is set for the fallback model, or by GEMINI_THINKING.
function Prompt.build_body(cfg, input, thinking_level)
    local generation = '"responseMimeType":"application/json","responseJsonSchema":' .. Prompt.SCHEMA_JSON
    if thinking_level then
        generation = generation .. ',"thinkingConfig":{"thinkingLevel":' .. Json.quote(thinking_level) .. "}"
    end
    return '{"systemInstruction":{"parts":[{"text":' .. Json.quote(Prompt.system_instruction(cfg)) .. "}]},"
        .. '"contents":[{"role":"user","parts":[{"text":' .. Json.quote(Prompt.user_message(input)) .. "}]}],"
        .. '"generationConfig":{' .. generation .. "}}"
end

return Prompt
