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
    "register": {"type": "string", "enum": ["neutral", "informal", "formal", "literary", "slang", "old-fashioned", "offensive"]},
    "definition": {"type": "string", "description": "At most 15 common words, dictionary style (\"to ...\" for verbs), never the headword or its family"},
    "spanish": {"type": "array", "items": {"type": "string"}, "maxItems": 3, "description": "1-3 Mexican Spanish equivalents with the same meaning and register"},
    "trap": {"type": "string", "enum": ["none", "false_friend", "preposition", "calque", "confusable", "register"]},
    "warning": {"type": "string", "description": "In Spanish, written \"✗ ... → ✓ ...\", only when trap is not none; otherwise \"\""},
    "usage": {"type": "array", "minItems": 1, "maxItems": 3, "description": "2-3 common ways to build sentences with it, from everyday life", "items": {"type": "object", "properties": {"pattern": {"type": "string", "description": "Short reusable frame (\"give up + something\", \"give up + -ing\")"}, "example": {"type": "string", "description": "At most 12 everyday words, the expression in <b></b>, never the book's scene"}}, "required": ["pattern", "example"]}},
    "picture_format": {"type": "string", "enum": ["object", "action", "before_after", "contrast", "manner"]},
    "picture_scene": {"type": "string", "description": "At most 70 words: exactly what to draw so the meaning is obvious, panel by panel"},
    "picture_caption": {"type": "string", "description": "At most 10 everyday words that the picture shows, the word in <b></b>"}
  },
  "required": ["status", "expression_in_text", "headword", "pos", "sense", "ipa", "register", "definition", "spanish", "trap", "warning", "usage", "picture_format", "picture_scene", "picture_caption"]
}]=]

local SYSTEM_TEMPLATE = [=[
You write one Anki vocabulary card for an adult native speaker of %NATIVE% (level %LEVEL%) who is learning English by reading novels on a Kindle. They held one word; in the sentence it is marked like ⟦this⟧.

1. Card the whole unit the held word belongs to (a phrasal verb, even when split like "gave it up"; an idiom; a fixed phrase; a compound) in its dictionary form.
2. Use the sentence only to choose the meaning; write `sense` first, in plain words. Everything else on the card is about everyday life, not the book.
3. Write for this learner: simple, common English in the definition and the examples; natural Spanish that someone from Mexico would say, with the same meaning and register.
4. `usage`: 2-3 common ways to build sentences with it. Each pattern is a short reusable frame ("give up + something", "give up + -ing", "a ___ of"). Each example sounds natural, follows its pattern exactly, is about everyday life (home, work, food, friends, shopping, travel, health), uses common verbs, has the expression in <b></b>, and never reuses the book's sentence, scene, objects or names.
5. The picture must teach the word like a picture dictionary: someone who sees only the picture should guess the meaning. Choose `picture_format`:
   - object: a concrete thing, big and centered, alone or in its most typical use;
   - action: the most typical moment of the action, with exaggerated body language and motion lines;
   - before_after: stopping, starting or changing (give up, quit, melt): two panels, left before, right after, same person and place;
   - contrast: a quality, feeling, adjective or abstract noun: two panels, left the opposite, right the word;
   - manner: a way of moving or doing (drift, leisurely, rush): make speed, direction or control obvious with dotted paths, motion lines or faces.
   `picture_scene` says exactly what to draw, panel by panel, in an everyday modern setting, never the book's world or characters, with one exaggerated idea. Visual symbols are fine (arrows, motion lines, dotted paths, a big X, check marks, hearts, sweat drops); never letters, words or numbers, and nothing with writing on it. Keep it family-friendly: for violent or sensitive words, use a mild, symbolic scene. `picture_caption` is the everyday sentence the picture shows.
6. Flag only real traps for Spanish speakers, using the lists below. When you are not sure, use "none" and "".
7. Keep every field within the limits in the schema descriptions.
8. If the held word is a name, isn't English or can't be read, set status to proper_noun, not_english or unclear, use "" or [] for the text fields, pos "other", register "neutral", trap "none" and picture_format "object".

%LISTS%

<example>
<book>Example Book — Example Author</book>
<sentence>She tried the violin for years, but last winter she finally ⟦gave⟧ it up.</sentence>
<word>gave</word>
{"status":"ok","expression_in_text":"gave it up","headword":"give up","pos":"phrasal verb","sense":"stopped doing an activity she did regularly","ipa":"/ˌɡɪv ˈʌp/","register":"neutral","definition":"to stop doing something that you did regularly","spanish":["dejar","abandonar"],"trap":"none","warning":"","usage":[{"pattern":"give up + something","example":"I <b>gave up</b> coffee a month ago."},{"pattern":"give up + -ing","example":"My dad <b>gave up</b> smoking last year."}],"picture_format":"before_after","picture_scene":"Two panels. Left: a tired man at a kitchen table drinking from a big cup of coffee, five empty cups around him. Right: the same man smiling, pushing the cup away with one hand, a glass of water in front of him.","picture_caption":"He <b>gave up</b> coffee."}
</example>

<example>
<book>Example Book — Example Author</book>
<sentence>For many years the old monk ⟦sought⟧ the truth in silence.</sentence>
<word>sought</word>
{"status":"ok","expression_in_text":"sought","headword":"seek","pos":"verb","sense":"looked for something important for a long time","ipa":"/sik/","register":"formal","definition":"to try to find or get something","spanish":["buscar"],"trap":"none","warning":"","usage":[{"pattern":"seek + something","example":"You should <b>seek</b> help from a doctor."},{"pattern":"seek advice from + someone","example":"Many people <b>seek</b> advice from friends."}],"picture_format":"action","picture_scene":"A worried young man at a café table asking two friendly friends for help; they lean in and point helpfully, and a small glowing light bulb floats above his head.","picture_caption":"He <b>seeks</b> advice from his friends."}
</example>

<example>
<book>Example Book — Example Author</book>
<sentence>He looked calm, but he was ⟦actually⟧ terrified of the dark.</sentence>
<word>actually</word>
{"status":"ok","expression_in_text":"actually","headword":"actually","pos":"adverb","sense":"in reality, although it seemed different","ipa":"/ˈæktʃuəli/","register":"neutral","definition":"used to say what is really true, often something surprising","spanish":["en realidad","de hecho"],"trap":"false_friend","warning":"Falso amigo: ✗ «actualmente» → ✓ «en realidad»","usage":[{"pattern":"be + actually + adjective","example":"The test was <b>actually</b> easy."},{"pattern":"actually + verb","example":"I <b>actually</b> like cold pizza."}],"picture_format":"contrast","picture_scene":"Two panels. Left: a boy staring at a plate of green vegetables with a disgusted face. Right: the same boy tasting them, eyes wide with surprise, smiling, small hearts around his head.","picture_caption":"The vegetables were <b>actually</b> delicious."}
</example>

<example>
<book>Example Book — Example Author</book>
<sentence>Our plans for the trip ⟦depend⟧ on how much money we save.</sentence>
<word>depend</word>
{"status":"ok","expression_in_text":"depend on","headword":"depend on","pos":"verb","sense":"are decided by something else","ipa":"/dɪˈpɛnd ɑn/","register":"neutral","definition":"to change according to something else","spanish":["depender de"],"trap":"preposition","warning":"✗ depend of → ✓ depend on","usage":[{"pattern":"depend on + something","example":"The price <b>depends on</b> the size."},{"pattern":"it depends on + something","example":"Our picnic <b>depends on</b> the weather."}],"picture_format":"contrast","picture_scene":"Two panels with the same family at a park gate holding a picnic basket. Left: sunny sky, everyone smiling and walking in. Right: dark rain clouds, everyone sad and turning back home.","picture_caption":"Our picnic <b>depends on</b> the weather."}
</example>

<example>
<book>Example Book — Example Author</book>
<sentence>I stayed home because I felt a bit ⟦under⟧ the weather.</sentence>
<word>under</word>
{"status":"ok","expression_in_text":"under the weather","headword":"under the weather","pos":"idiom","sense":"slightly sick","ipa":"/ˈʌndər ðə ˈwɛðər/","register":"informal","definition":"slightly ill","spanish":["un poco enfermo","indispuesto"],"trap":"none","warning":"","usage":[{"pattern":"feel under the weather","example":"I feel <b>under the weather</b>, so I'm staying in bed."},{"pattern":"be under the weather","example":"Sorry, I'm <b>under the weather</b> this week."}],"picture_format":"contrast","picture_scene":"Two panels. Left: a woman jogging happily in a sunny park. Right: the same woman on a sofa wrapped in a blanket, pale and tired, holding a cup of tea, a tissue box beside her.","picture_caption":"She feels a bit <b>under the weather</b>."}
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
