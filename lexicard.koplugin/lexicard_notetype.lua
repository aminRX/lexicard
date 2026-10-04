--[[
The "Lexicard" Anki note type: one English card per note (template "Recognize").
Note types from older versions keep their extra fields: Lexicard never deletes fields or cards.
]]
local NoteType = {}

NoteType.VERSION_MARK = "lexicard-notetype v3"

NoteType.FIELDS = { "Headword", "IPA", "POS", "Register", "Spanish", "Definition", "Usage", "Image", "Caption",
                    "Audio", "Warning", "Context", "Book" }

NoteType.TEMPLATES = {
    {
        Name = "Recognize",
        Front = [=[<div class="lx">
<div class="lx-headword">{{Headword}}</div>
<div class="lx-meta">{{#IPA}}<span>{{IPA}}</span>{{/IPA}}{{#POS}}<span>{{POS}}</span>{{/POS}}{{#Register}}<span>{{Register}}</span>{{/Register}}</div>
<div class="lx-audio">{{Audio}}</div>
</div>]=],
        Back = [=[{{FrontSide}}
<hr id="answer">
<div class="lx">
{{#Image}}<div class="lx-image">{{Image}}</div>{{/Image}}
{{#Caption}}<div class="lx-caption">{{Caption}}</div>{{/Caption}}
<div class="lx-spanish">{{Spanish}}</div>
<div class="lx-definition">{{Definition}}</div>
{{#Usage}}<div class="lx-usage"><div class="lx-label">How to use it</div>{{Usage}}</div>{{/Usage}}
{{#Warning}}<div class="lx-warning">⚠️ {{Warning}}</div>{{/Warning}}
{{#Context}}<div class="lx-from"><span class="lx-label">From your book</span><br>“{{Context}}”{{#Book}} <span class="lx-book">· {{Book}}</span>{{/Book}}</div>{{/Context}}
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
.lx-headword { font-size: 1.7em; font-weight: 700; margin: 0.3em 0 0.1em; }
.lx-meta { color: #6e6e73; font-size: 0.85em; margin: 0.2em 0; }
.lx-meta span + span::before { content: " · "; }
.lx-image img { display: block; max-width: 100%; max-height: 45vh; margin: 0.3em auto 0.2em; border-radius: 14px; }
.lx-caption { font-family: Georgia, "Times New Roman", serif; font-style: italic; color: #3a3a3c; margin: 0.2em 0 0.6em; }
.lx-spanish { font-size: 1.3em; font-weight: 700; margin-top: 0.4em; }
.lx-definition { margin: 0.2em 0 0.8em; }
.lx-usage { text-align: left; background-color: #f2f2f7; border-radius: 12px; padding: 0.6em 0.8em; margin: 0.6em 0; }
.lx-label { color: #8e8e93; font-size: 0.7em; font-weight: 700; text-transform: uppercase; letter-spacing: 0.06em; }
.lx-use { margin: 0.35em 0; }
.lx-pattern { font-weight: 700; margin-right: 0.3em; }
.lx-ex { font-style: italic; }
.lx-caption b, .lx-ex b, .lx-from b { color: #b3261e; }
.lx-warning { background-color: #fff4d6; border-radius: 8px; padding: 0.4em 0.6em; margin: 0.6em 0; font-size: 0.9em; }
.lx-from { color: #6e6e73; font-size: 0.8em; margin-top: 1em; }
.lx-book { color: #8e8e93; }
.nightMode.card, .night_mode.card, .nightMode .card, .night_mode .card { color: #f2f2f7; background-color: #1c1c1e; }
.nightMode .lx-usage, .night_mode .lx-usage { background-color: #2c2c2e; }
.nightMode .lx-warning, .night_mode .lx-warning { background-color: #3a2f12; }
.nightMode .lx-caption, .night_mode .lx-caption { color: #d1d1d6; }
.nightMode .lx-caption b, .night_mode .lx-caption b, .nightMode .lx-ex b, .night_mode .lx-ex b, .nightMode .lx-from b, .night_mode .lx-from b { color: #ff8a80; }
.nightMode .lx-meta, .night_mode .lx-meta, .nightMode .lx-from, .night_mode .lx-from { color: #aeaeb2; }]=]

-- The front of an older reverse card ("Produce"), wrapped so that it renders empty, and so
-- no card is made, for notes that leave Cloze empty (all v3 notes). nil if already wrapped.
function NoteType.retire_produce(front)
    if front:sub(1, 10) == "{{#Cloze}}" then return nil end
    return "{{#Cloze}}" .. front .. "{{/Cloze}}"
end

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
