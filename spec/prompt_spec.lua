local Json = require("lexicard_json")
local Prompt = require("lexicard_prompt")
local Config = require("lexicard_config")

local cfg = Config.from_values({ GEMINI_API_KEY = "k" })
local input = { word = "gave", sentence = "she finally ⟦gave⟧ it up.", book_title = "Example Book", book_author = "Ann Author" }
local ORDER = { "status", "surface", "expression_in_text", "headword", "pos", "pattern", "register", "cefr",
                "definition", "spanish", "context", "example", "collocations", "warning", "pron_tip", "ipa" }

describe("Prompt", function()
    it("fills the learner profile into the system instruction", function()
        local text = Prompt.system_instruction(cfg)
        assert_match(text, "Spanish %(Mexico%)")
        assert_match(text, "B1%-B2")
        assert_true(not text:find("%NATIVE%", 1, true))
    end)
    it("tags the inputs", function()
        assert_eq(Prompt.user_message(input),
            "<book>Example Book — Ann Author</book>\n<sentence>she finally ⟦gave⟧ it up.</sentence>\n<word>gave</word>")
    end)
    it("has a valid schema whose keys follow the reasoning order", function()
        local schema = Json.decode(Prompt.SCHEMA_JSON)
        assert_eq(schema.type, "object")
        assert_same(schema.required, ORDER)
        local last = 0
        for _, key in ipairs(ORDER) do
            assert_true(schema.properties[key] ~= nil, "missing property " .. key)
            local pos = Prompt.SCHEMA_JSON:find('"' .. key .. '"%s*:%s*{')
            assert_true(pos and pos > last, "key out of order: " .. key)
            last = pos
        end
    end)
    it("builds a request body Gemini accepts", function()
        local body = Json.decode(Prompt.build_body(cfg, input))
        assert_eq(body.contents[1].role, "user")
        assert_eq(body.contents[1].parts[1].text, Prompt.user_message(input))
        assert_eq(body.systemInstruction.parts[1].text, Prompt.system_instruction(cfg))
        assert_eq(body.generationConfig.responseMimeType, "application/json")
        assert_eq(body.generationConfig.responseJsonSchema.type, "object")
        assert_eq(body.generationConfig.thinkingConfig, nil)
    end)
    it("adds a thinking level when asked", function()
        local body = Json.decode(Prompt.build_body(cfg, input, "low"))
        assert_eq(body.generationConfig.thinkingConfig.thinkingLevel, "low")
    end)
    it("only uses example JSON that matches the schema keys", function()
        local text = Prompt.system_instruction(cfg)
        local count = 0
        for line in text:gmatch("[^\n]+") do
            if line:sub(1, 1) == "{" then
                local example = assert(Json.decode(line), "example is not valid JSON")
                for _, key in ipairs(ORDER) do assert_true(example[key] ~= nil, "example lacks " .. key) end
                count = count + 1
            end
        end
        assert_eq(count, 3)
    end)
end)
