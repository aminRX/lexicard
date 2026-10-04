local Note = require("lexicard_note")
local Config = require("lexicard_config")

local cfg = Config.from_values({})
local input = { word = "gave", sentence = "In the end she finally ⟦gave⟧ it up.", book_title = "The Little Prince",
                book_author = "Antoine de Saint-Exupéry" }

local function card(over)
    local c = {
        status = "ok", surface = "gave", expression_in_text = "gave it up", headword = "give up",
        pos = "phrasal verb", sense = "stopped", ipa = "/ˌɡɪv ˈʌp/", register = "neutral",
        definition = "to stop doing something", spanish = { "dejar", "abandonar" }, trap = "none", warning = "",
        usage = { { pattern = "give up + something", example = "I <b>gave up</b> coffee." },
                  { pattern = "give up + -ing", example = "She gave up smoking." } },
        picture_format = "before_after", picture_scene = "Two panels: coffee, then water.",
        picture_caption = "He <b>gave up</b> coffee.",
    }
    for k, v in pairs(over or {}) do c[k] = v end
    return c
end

describe("Note.keep_bold", function()
    it("keeps <b> and escapes everything else", function()
        assert_eq(Note.keep_bold('a <b>b</b> <i>c</i> & "d"'), 'a <b>b</b> &lt;i&gt;c&lt;/i&gt; &amp; &quot;d&quot;')
    end)
    it("drops unbalanced bold tags", function()
        assert_eq(Note.keep_bold("a <b>b"), "a b")
    end)
end)

describe("Note.ensure_bold", function()
    it("bolds the first matching candidate when the model forgot", function()
        assert_eq(Note.ensure_bold("He gave up smoking.", { "gave it up", "give up", "gave" }), "He <b>gave</b> up smoking.")
    end)
    it("leaves already bolded text alone", function()
        assert_eq(Note.ensure_bold("He <B>gave up</B>.", { "gave" }), "He <B>gave up</B>.")
    end)
end)

describe("Note.register, tags and slugs", function()
    it("shows only a non-neutral register", function()
        assert_eq(Note.register(card()), "")
        assert_eq(Note.register(card({ register = "informal" })), "informal")
    end)
    it("makes Anki-safe tags", function()
        assert_same(Note.tags(card(), input), { "lexicard", "book::the_little_prince" })
    end)
    it("never splits a UTF-8 character when truncating", function()
        assert_eq(Note.utf8_truncate("abcé", 4), "abc")
        assert_eq(Note.utf8_truncate("abcé", 5), "abcé")
    end)
    it("limits slugs to 40 bytes", function()
        assert_true(#Note.slug(("very long title "):rep(10)) <= 40)
    end)
end)

describe("Note.usage_html", function()
    it("writes one line per pattern, escaped, with the expression in bold", function()
        assert_eq(Note.usage_html(card({ usage = { { pattern = "a < b", example = "She gave up smoking." } } }), input),
            '<div class="lx-use"><span class="lx-pattern">a &lt; b</span> <span class="lx-ex">She <b>gave</b> up smoking.</span></div>')
    end)
end)

describe("Note.build", function()
    it("maps the card to the v3 fields, text only", function()
        local note = Note.build(card({ warning = 'Ojo: <no> "dar arriba"' }), input, cfg, false)
        assert_eq(note.deckName, "Reading vocabulary")
        assert_eq(note.modelName, "Lexicard")
        assert_eq(note.fields.Headword, "give up")
        assert_eq(note.fields.Spanish, "dejar / abandonar")
        assert_match(note.fields.Usage, 'I <b>gave up</b> coffee%.')
        assert_match(note.fields.Usage, 'She <b>gave</b> up smoking%.')
        assert_eq(note.fields.Caption, "He <b>gave up</b> coffee.")
        assert_eq(note.fields.Image, "")
        assert_eq(note.fields.Audio, "")
        assert_eq(note.fields.Warning, "Ojo: &lt;no&gt; &quot;dar arriba&quot;")
        assert_eq(note.fields.Book, "The Little Prince — Antoine de Saint-Exupéry")
        assert_eq(note.fields.Context, "In the end she finally <b>gave it up</b>.")
        assert_eq(note.fields.Register, "")
        assert_eq(note.audio, nil)
        assert_eq(note.picture, nil)
        assert_eq(note.options.allowDuplicate, false)
        assert_eq(note.options.duplicateScope, "deck")
        assert_eq(note.options.duplicateScopeOptions.deckName, "Reading vocabulary")
    end)
    it("bolds the held word when the expression isn't found", function()
        local note = Note.build(card({ expression_in_text = "", pos = "verb" }), input, cfg)
        assert_eq(note.fields.Context, "In the end she finally <b>gave</b> it up.")
    end)
    it("allows duplicates on request", function()
        assert_eq(Note.build(card(), input, cfg, true).options.allowDuplicate, true)
    end)
end)

describe("Note.preview_text", function()
    it("shows the card as plain text", function()
        local text = Note.preview_text(card({ warning = "Ojo" }), input, "Reading vocabulary", true)
        assert_match(text, "^give up   /ˌɡɪv ˈʌp/\n")
        assert_match(text, "dejar / abandonar")
        assert_match(text, "How to use it:\n• give up %+ something — I gave up coffee%.")
        assert_match(text, "⚠ Ojo")
        assert_match(text, "Picture %(before → after%): Two panels")
        assert_match(text, "Caption: He gave up coffee%.")
        assert_match(text, "Book: In the end she finally gave it up%.")
        assert_match(text, "Saves 1 card to “Reading vocabulary”%.")
    end)
    it("leaves out the picture when pictures are off", function()
        local text = Note.preview_text(card(), input, "Reading vocabulary", false)
        assert_true(not text:find("Picture", 1, true))
    end)
end)
