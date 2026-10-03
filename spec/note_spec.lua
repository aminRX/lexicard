local Note = require("lexicard_note")
local Config = require("lexicard_config")

local cfg = Config.from_values({})
local input = { word = "gave", sentence = "", book_title = "The Little Prince", book_author = "Antoine de Saint-Exupéry" }

local function card(over)
    local c = {
        status = "ok", surface = "gave", expression_in_text = "gave it up", headword = "give up",
        pos = "phrasal verb", pattern = "give sth up", register = "neutral", cefr = "B1",
        definition = "to stop doing something", spanish = { "dejar", "abandonar" },
        context = "she finally <b>gave it up</b>.", example = "He <b>gave up</b> smoking.",
        collocations = { "give up hope", "give up smoking" }, warning = "", pron_tip = "", ipa = "/ɡɪv ʌp/",
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

describe("Note.ensure_bold and Note.cloze", function()
    it("bolds the first matching candidate when the model forgot", function()
        assert_eq(Note.ensure_bold("He gave up smoking.", { "gave it up", "give up", "gave" }), "He <b>gave</b> up smoking.")
    end)
    it("leaves already bolded text alone", function()
        assert_eq(Note.ensure_bold("He <B>gave up</B>.", { "gave" }), "He <B>gave up</B>.")
    end)
    it("blanks the bold span", function()
        assert_eq(Note.cloze("He <b>gave up</b> smoking."), "He _____ smoking.")
        assert_eq(Note.cloze("No bold here."), "")
    end)
end)

describe("Note.pattern", function()
    it("hides a pattern that only repeats the headword", function()
        assert_eq(Note.pattern(card({ pattern = "Give Up" })), "")
    end)
    it("appends a non-neutral register", function()
        assert_eq(Note.pattern(card({ register = "informal" })), "give sth up · informal")
        assert_eq(Note.pattern(card({ pattern = "give up", register = "slang" })), "slang")
    end)
end)

describe("Note.tags and slugs", function()
    it("makes Anki-safe tags", function()
        assert_same(Note.tags(card(), input), { "lexicard", "book::the_little_prince", "cefr::B1" })
    end)
    it("never splits a UTF-8 character when truncating", function()
        assert_eq(Note.utf8_truncate("abcé", 4), "abc")
        assert_eq(Note.utf8_truncate("abcé", 5), "abcé")
    end)
    it("limits slugs to 40 bytes", function()
        assert_true(#Note.slug(("very long title "):rep(10)) <= 40)
    end)
end)

describe("Note.build", function()
    it("maps the card to Lexicard fields and options", function()
        local note = Note.build(card({ warning = 'Ojo: <no> "dar arriba"' }), input, cfg, false)
        assert_eq(note.deckName, "Reading vocabulary")
        assert_eq(note.modelName, "Lexicard")
        assert_eq(note.fields.Headword, "give up")
        assert_eq(note.fields.Spanish, "dejar / abandonar")
        assert_eq(note.fields.Example, "He <b>gave up</b> smoking.")
        assert_eq(note.fields.Cloze, "He _____ smoking.")
        assert_eq(note.fields.Collocations, "give up hope · give up smoking")
        assert_eq(note.fields.Warning, "Ojo: &lt;no&gt; &quot;dar arriba&quot;")
        assert_eq(note.fields.Book, "The Little Prince — Antoine de Saint-Exupéry")
        assert_eq(note.fields.Pattern, "give sth up")
        assert_eq(note.options.allowDuplicate, false)
        assert_eq(note.options.duplicateScope, "deck")
        assert_eq(note.options.duplicateScopeOptions.deckName, "Reading vocabulary")
    end)
    it("removes stray markers from the context", function()
        assert_eq(Note.build(card({ context = "she ⟦gave⟧ it up" }), input, cfg).fields.Context, "she gave it up")
    end)
    it("allows duplicates on request", function()
        assert_eq(Note.build(card(), input, cfg, true).options.allowDuplicate, true)
    end)
end)

describe("Note.preview_text", function()
    it("shows the important parts as plain text", function()
        local text = Note.preview_text(card({ warning = "Ojo" }), input, "Reading vocabulary")
        assert_match(text, "^give up   /ɡɪv ʌp/\n")
        assert_match(text, "phrasal verb · give sth up · B1")
        assert_match(text, "dejar / abandonar")
        assert_match(text, "⚠ Ojo")
        assert_match(text, "Example: He gave up smoking%.")
        assert_match(text, "Saves 2 cards to “Reading vocabulary”%.")
    end)
end)
