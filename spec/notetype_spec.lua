local NoteType = require("lexicard_notetype")
local Note = require("lexicard_note")
local Config = require("lexicard_config")

describe("NoteType", function()
    it("declares exactly the fields Note.build fills, Headword first", function()
        local empty = { status = "ok", expression_in_text = "", headword = "x", pos = "", sense = "", pattern = "",
            register = "", definition = "", spanish = {}, trap = "none", warning = "", sound = "none", pron_tip = "",
            example = "", collocations = {}, ipa = "" }
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
    it("only references declared fields in templates", function()
        local known = { FrontSide = true }
        for _, name in ipairs(NoteType.FIELDS) do known[name] = true end
        for _, template in ipairs(NoteType.TEMPLATES) do
            for _, side in ipairs({ template.Front, template.Back }) do
                for ref in side:gmatch("{{(.-)}}") do
                    local name = ref:gsub("^[#/^]", ""):gsub("^.*:", "")
                    assert_true(known[name], "unknown field in template: " .. ref)
                end
            end
        end
    end)
    it("marks the CSS with the template version", function()
        assert_true(NoteType.CSS:find(NoteType.VERSION_MARK, 1, true) ~= nil)
    end)
    it("builds AnkiConnect parameters", function()
        local params = NoteType.create_model_params("Lexicard")
        assert_eq(params.modelName, "Lexicard")
        assert_eq(params.isCloze, false)
        assert_eq(params.css, NoteType.CSS)
        assert_same(params.inOrderFields, NoteType.FIELDS)
        assert_eq(params.cardTemplates[1].Name, "Recognize")
        assert_eq(params.cardTemplates[2].Name, "Produce")
        local update = NoteType.update_templates_params("Lexicard")
        assert_eq(update.model.name, "Lexicard")
        assert_eq(update.model.templates.Produce.Back, NoteType.TEMPLATES[2].Back)
        assert_eq(NoteType.update_styling_params("Lexicard").model.css, NoteType.CSS)
    end)
end)
