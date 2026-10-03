local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local UI = {}

function UI.info(text, timeout)
    UIManager:show(InfoMessage:new{ text = text, timeout = timeout })
end

function UI.confirm(text, ok_text, ok_callback)
    UIManager:show(ConfirmBox:new{ text = text, ok_text = ok_text, ok_callback = ok_callback })
end

function UI.preview(text, on_regenerate, on_save)
    local viewer
    viewer = TextViewer:new{
        title = _("Lexicard"),
        text = text,
        text_type = "lookup",
        buttons_table = {
            {
                { text = _("Cancel"), callback = function() UIManager:close(viewer) end },
                { text = _("Regenerate"), callback = function() UIManager:close(viewer); on_regenerate() end },
                { text = _("Save"), callback = function() UIManager:close(viewer); on_save() end },
            },
        },
    }
    UIManager:show(viewer)
end

return UI
