-- Stand-ins for the KOReader modules main.lua uses. Stubs are created once
-- (modules keep references to them); Fake.reset() clears the state between tests.
local Fake = { shown = {}, connected = true, settings_dir = nil, transport = nil }

local function widget(kind)
    return { new = function(_, args) args.kind = kind; return args end }
end

package.loaded["gettext"] = function(s) return s end
package.loaded["logger"] = { info = function() end, warn = function() end, dbg = function() end, err = function() end }
package.loaded["ffi/util"] = {
    template = function(s, ...)
        local args = { ... }
        return (s:gsub("%%(%d)", function(i) return tostring(args[tonumber(i)]) end))
    end,
}
package.loaded["datastorage"] = { getSettingsDir = function() return Fake.settings_dir end }
package.loaded["ui/uimanager"] = {
    show = function(_, w) Fake.shown[#Fake.shown + 1] = w end,
    close = function(_, w) w.closed = true end,
    scheduleIn = function(_, _, fn) fn() end,
}
package.loaded["ui/trapper"] = {
    wrap = function(_, fn) fn() end,
    dismissableRunInSubprocess = function(_, task) return true, task() end,
}
package.loaded["ui/network/manager"] = {
    isConnected = function() return Fake.connected end,
    runWhenOnline = function(_, fn) fn() end,
    runWhenConnected = function(_, fn) fn() end,
}
package.loaded["ui/widget/infomessage"] = widget("info")
package.loaded["ui/widget/confirmbox"] = widget("confirm")
package.loaded["ui/widget/textviewer"] = widget("viewer")
package.loaded["ui/widget/container/widgetcontainer"] = {
    extend = function(_, class)
        class.__index = class
        class.new = function(cls, o)
            o = setmetatable(o or {}, cls)
            if o.init then o:init() end
            return o
        end
        return class
    end,
}
package.loaded["lexicard_http"] = {
    transport = function() return function(request) return Fake.transport(request) end end,
}

function Fake.reset(opts)
    Fake.shown = {}
    Fake.connected = opts.connected ~= false
    Fake.settings_dir = opts.settings_dir
    Fake.transport = opts.transport
end

function Fake.last(kind)
    for i = #Fake.shown, 1, -1 do
        if Fake.shown[i].kind == kind then return Fake.shown[i] end
    end
end

function Fake.press(viewer, label)
    for _, row in ipairs(viewer.buttons_table) do
        for _, button in ipairs(row) do
            if button.text == label then return button.callback() end
        end
    end
    error("no button " .. label)
end

function Fake.ui()
    local ui = {}
    ui.menu = { registerToMainMenu = function(_, plugin) ui.menu_plugin = plugin end }
    ui.dictionary = { addToDictButtons = function(_, spec) ui.dict_spec = spec end }
    ui.highlight = {
        selected_text = { text = "gave" },
        getSelectedWordContext = function() return "she finally ", " it up." end,
    }
    ui.doc_props = { display_title = "Example Book", authors = "Ann Author" }
    return ui
end

function Fake.popup(word)
    return {
        word = word,
        is_wiki = false,
        isDocless = function() return false end,
        onClose = function(self) self.closed = true end,
    }
end

return Fake
