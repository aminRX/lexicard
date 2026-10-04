local NoteType = require("lexicard_notetype")
local Note = require("lexicard_note")
local Config = require("lexicard_config")

describe("NoteType", function()
    it("declares exactly the fields Note.build fills, Headword first", function()
        local empty = { status = "ok", expression_in_text = "", headword = "x", pos = "", sense = "", register = "",
            definition = "", spanish = {}, trap = "none", warning = "", usage = {}, ipa = "",
            picture_format = "object", picture_scene = "", picture_caption = "" }
        local note = Note.build(empty, { book_title = "", book_author = "" }, Config.from_values({}))
        local filled = {}
        for name in pairs(note.fields) do filled[#filled + 1] = name end
        table.sort(filled)
        local declared = {}
        for i, name in ipairs(NoteType.FIELDS) do declared[i] = name end
        table.sort(declared)
        assert_same(filled, declared)
        assert_eq(NoteType.FIELDS[1], "Headword")
    end)
    it("has one English card that only references declared fields", function()
        assert_eq(#NoteType.TEMPLATES, 1)
        assert_eq(NoteType.TEMPLATES[1].Name, "Recognize")
        local known = { FrontSide = true }
        for _, name in ipairs(NoteType.FIELDS) do known[name] = true end
        for _, side in ipairs({ NoteType.TEMPLATES[1].Front, NoteType.TEMPLATES[1].Back }) do
            for ref in side:gmatch("{{(.-)}}") do
                local name = ref:gsub("^[#/^]", ""):gsub("^.*:", "")
                assert_true(known[name], "unknown field in template: " .. ref)
            end
        end
        assert_true(not NoteType.TEMPLATES[1].Front:find("{{Spanish}}", 1, true), "Spanish must stay on the back")
        assert_true(NoteType.TEMPLATES[1].Back:find("{{Image}}", 1, true) ~= nil)
    end)
    it("marks the CSS with the template version", function()
        assert_true(NoteType.CSS:find(NoteType.VERSION_MARK, 1, true) ~= nil)
        assert_eq(NoteType.VERSION_MARK, "lexicard-notetype v3")
    end)
    it("builds AnkiConnect parameters", function()
        local params = NoteType.create_model_params("Lexicard")
        assert_eq(params.modelName, "Lexicard")
        assert_eq(params.isCloze, false)
        assert_same(params.inOrderFields, NoteType.FIELDS)
        assert_eq(#params.cardTemplates, 1)
        local update = NoteType.update_templates_params("Lexicard")
        assert_eq(update.model.templates.Recognize.Back, NoteType.TEMPLATES[1].Back)
        assert_eq(NoteType.update_styling_params("Lexicard").model.css, NoteType.CSS)
    end)
    it("retires an old reverse card so new notes don't get it", function()
        assert_eq(NoteType.retire_produce("<div>{{Spanish}}</div>"), "{{#Cloze}}<div>{{Spanish}}</div>{{/Cloze}}")
        assert_eq(NoteType.retire_produce("{{#Cloze}}x{{/Cloze}}"), nil)
    end)
end)
