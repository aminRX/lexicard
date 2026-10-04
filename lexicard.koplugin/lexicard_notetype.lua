--[[
The "Lexicard" Anki note type: two cards per note (Recognize, Produce).
New fields are appended at the end so old note types can be migrated in place.
]]
local NoteType = {}

NoteType.VERSION_MARK = "lexicard-notetype v2"

NoteType.FIELDS = { "Headword", "POS", "Pattern", "IPA", "Spanish", "Definition", "Context", "Example",
                    "Cloze", "Collocations", "Warning", "PronTip", "Book", "CEFR",
                    "Register", "ContextOpen", "Audio" }

local META = [=[<div class="lx-meta">{{#IPA}}<span>{{IPA}}</span>{{/IPA}}{{#POS}}<span>{{POS}}</span>{{/POS}}{{#Pattern}}<span>{{Pattern}}</span>{{/Pattern}}{{#Register}}<span>{{Register}}</span>{{/Register}}</div>]=]

NoteType.TEMPLATES = {
    {
        Name = "Recognize",
        Front = [=[<div class="lx">
<div class="lx-headword">{{Headword}}</div>
<div class="lx-audio">{{Audio}}</div>
{{#Context}}{{#ContextOpen}}<div class="lx-context">{{Context}}</div>{{/ContextOpen}}{{^ContextOpen}}<div class="lx-hint">{{hint:Context}}</div>{{/ContextOpen}}{{/Context}}
</div>]=],
        Back = [=[{{FrontSide}}
<hr id="answer">
<div class="lx">
<div class="lx-spanish">{{Spanish}}</div>
<div class="lx-definition">{{Definition}}</div>
]=] .. META .. [=[

{{#Warning}}<div class="lx-warning">⚠️ {{Warning}}</div>{{/Warning}}
{{#PronTip}}<div class="lx-small">🗣 {{PronTip}}</div>{{/PronTip}}
{{#Context}}{{^ContextOpen}}<div class="lx-context">{{Context}}</div>{{/ContextOpen}}{{/Context}}
{{#Book}}<div class="lx-book">{{Book}}</div>{{/Book}}
</div>]=],
    },
    {
        Name = "Produce",
        Front = [=[<div class="lx">
<div class="lx-prompt">Say it in English</div>
<div class="lx-spanish">{{Spanish}}</div>
<div class="lx-definition">{{Definition}}</div>
<div class="lx-meta"><span>{{POS}}</span>{{#Register}}<span>{{Register}}</span>{{/Register}}</div>
{{#Cloze}}<div class="lx-example">{{Cloze}}</div>{{/Cloze}}
</div>]=],
        Back = [=[{{FrontSide}}
<hr id="answer">
<div class="lx">
<div class="lx-headword">{{Headword}}</div>
<div class="lx-audio">{{Audio}}</div>
<div class="lx-meta">{{#IPA}}<span>{{IPA}}</span>{{/IPA}}{{#Pattern}}<span>{{Pattern}}</span>{{/Pattern}}</div>
<div class="lx-example">{{Example}}</div>
{{#Collocations}}<div class="lx-small">{{Collocations}}</div>{{/Collocations}}
{{#Warning}}<div class="lx-warning">⚠️ {{Warning}}</div>{{/Warning}}
{{#PronTip}}<div class="lx-small">🗣 {{PronTip}}</div>{{/PronTip}}
</div>]=],
    },
}

NoteType.CSS = "/* " .. NoteType.VERSION_MARK .. " */\n" .. [=[.card {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  font-size: 20px;
  line-height: 1.45;
  text-align: center;
  color: #1d1d1f;
  background-color: #fafafa;
}
.lx { max-width: 34em; margin: 0 auto; padding: 0 12px; }
.lx-headword { font-size: 1.6em; font-weight: 700; margin: 0.3em 0; }
.lx-context { font-family: Georgia, "Times New Roman", serif; font-size: 1.05em; margin: 0.6em 0; }
.lx-context b, .lx-example b { color: #b3261e; }
.lx-hint { margin: 0.6em 0; font-size: 0.85em; }
.lx-hint a { color: #8e8e93; }
.lx-meta { color: #6e6e73; font-size: 0.85em; margin: 0.2em 0; }
.lx-meta span + span::before { content: " · "; }
.lx-spanish { font-size: 1.2em; font-weight: 600; margin-top: 0.6em; }
.lx-definition { margin: 0.3em 0 0.6em; }
.lx-example { font-style: italic; margin: 0.5em 0; }
.lx-small { color: #6e6e73; font-size: 0.85em; margin: 0.3em 0; }
.lx-warning { background-color: #fff4d6; border-radius: 8px; padding: 0.4em 0.6em; margin: 0.6em 0; font-size: 0.9em; }
.lx-book { color: #8e8e93; font-size: 0.75em; margin-top: 1em; }
.lx-prompt { color: #6e6e73; font-size: 0.75em; text-transform: uppercase; letter-spacing: 0.06em; }
.nightMode.card, .night_mode.card, .nightMode .card, .night_mode .card { color: #f2f2f7; background-color: #1c1c1e; }
.nightMode .lx-warning, .night_mode .lx-warning { background-color: #3a2f12; }
.nightMode .lx-context b, .night_mode .lx-context b, .nightMode .lx-example b, .night_mode .lx-example b { color: #ff8a80; }
.nightMode .lx-meta, .night_mode .lx-meta, .nightMode .lx-small, .night_mode .lx-small { color: #aeaeb2; }]=]

function NoteType.create_model_params(name)
    return {
        modelName = name,
        inOrderFields = NoteType.FIELDS,
        css = NoteType.CSS,
        isCloze = false,
        cardTemplates = NoteType.TEMPLATES,
    }
end

function NoteType.update_templates_params(name)
    local templates = {}
    for _, t in ipairs(NoteType.TEMPLATES) do
        templates[t.Name] = { Front = t.Front, Back = t.Back }
    end
    return { model = { name = name, templates = templates } }
end

function NoteType.update_styling_params(name)
    return { model = { name = name, css = NoteType.CSS } }
end

return NoteType
