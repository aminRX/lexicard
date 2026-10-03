local Context = require("lexicard_context")

describe("Context.cut_sentence", function()
    it("keeps only the sentence around the word", function()
        local s = Context.cut_sentence("He was tired. She tried the violin for years, but last winter she finally ",
            "gave", " it up. Then she moved on.")
        assert_eq(s, "She tried the violin for years, but last winter she finally ⟦gave⟧ it up.")
    end)
    it("handles curly quotes and apostrophes", function()
        local s = Context.cut_sentence("Silence. ‘Of course you don’t feel pain,’ the doctor said as she ",
            "busied", " herself with the needle. Next.")
        assert_eq(s, "‘Of course you don’t feel pain,’ the doctor said as she ⟦busied⟧ herself with the needle.")
    end)
    it("starts after a closing quote that ends a sentence", function()
        assert_eq(Context.cut_sentence('He said, "Stop." Then she ', "laughed", "."), "Then she ⟦laughed⟧.")
    end)
    it("treats an ellipsis as a sentence end", function()
        assert_eq(Context.cut_sentence("Wait… I ", "know", " this."), "I ⟦know⟧ this.")
    end)
    it("stops at paragraph breaks", function()
        assert_eq(Context.cut_sentence("Chapter 1\nIt was ", "cold", ".\nNext paragraph"), "It was ⟦cold⟧.")
    end)
    it("keeps the word when there is no context", function()
        assert_eq(Context.cut_sentence("", "Hello", ""), "⟦Hello⟧")
    end)
    it("limits each side to max_side_words", function()
        local s = Context.cut_sentence("one two three four five ", "six", " seven eight nine ten", 2)
        assert_eq(s, "… four five ⟦six⟧ seven eight …")
    end)
end)

describe("Context.clean_word", function()
    it("strips spaces, punctuation and curly quotes around the word", function()
        assert_eq(Context.clean_word("  “Hello,” "), "Hello")
        assert_eq(Context.clean_word("gave."), "gave")
    end)
    it("keeps inner apostrophes", function()
        assert_eq(Context.clean_word("don't"), "don't")
    end)
end)

describe("Context.from_popup", function()
    it("collects word, sentence and book from KOReader objects", function()
        local ui = {
            highlight = {
                selected_text = { text = "gave" },
                getSelectedWordContext = function(self, n) return "she finally ", " it up." end,
            },
            doc_props = { display_title = "Example Book", authors = "Ann Author\nBo Writer" },
        }
        assert_same(Context.from_popup(ui, { word = "gave" }), {
            word = "gave", sentence = "she finally ⟦gave⟧ it up.",
            book_title = "Example Book", book_author = "Ann Author, Bo Writer",
        })
    end)
    it("works without highlight or book data", function()
        assert_same(Context.from_popup({}, { word = "bank" }),
            { word = "bank", sentence = "", book_title = "", book_author = "" })
    end)
end)
