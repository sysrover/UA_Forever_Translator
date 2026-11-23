local _, ns = ...
local Commands = {}; ns.Commands = Commands
local function occupied()
    if type(hash_SlashCmdList) == "table" and hash_SlashCmdList["/UAFT"] then return true end
    if type(IsSecureCmd) == "function" then
        local ok, result = pcall(IsSecureCmd, "/uaft")
        if not ok or ns.Compat.secret(result) or result then return true end
    end
    -- Bounded to registered slash handlers, once on initialization. No _G scan.
    for key in pairs(SlashCmdList) do
        local index = 1
        while index <= 32 do
            local spelling = _G["SLASH_" .. key .. index]
            if type(spelling) ~= "string" then break end
            if spelling:lower() == "/uaft" then return true end
            index = index + 1
        end
    end
    return false
end
function Commands.dispatch(message)
    if ns.Compat.secret(message) or type(message) ~= "string" then return end
    local command, rest = message:match("^%s*(%S*)%s*(.-)%s*$")
    command = command:lower()
    if command == "" then ns.UI.ComposeWindow.open()
    elseif command == "en" then ns.UI.ComposeWindow.open(rest)
    elseif command == "config" then ns.UI.Settings.open()
    elseif command == "tab" then ns.Incoming.openTab()
    elseif command == "neural" then
        local enabled = rest:lower()
        if enabled == "on" or enabled == "off" then
            local available = ns.Database.setNeuralIncoming(enabled == "on")
            if available then ns.Database.changed() end
            ns.Compat.print(ns.L[not available and "neuralUnavailable"
                or enabled == "on" and "neuralEnabled" or "neuralDisabled"])
        else
            ns.Compat.print(ns.L[ns.Database.settings.neuralIncoming and "neuralEnabled" or "neuralDisabled"])
        end
    elseif command == "on" or command == "off" then
        ns.Database.settings.enabled = command == "on"; ns.Database.changed()
        ns.Compat.print(ns.L[command == "on" and "enabled" or "disabled"])
    elseif command == "lookup" then
        local term = ns.Engine.Dictionary.lookup(rest, "en-uk") or ns.Engine.Dictionary.lookup(rest, "uk-en")
        if term then ns.Compat.print(term.en .. " — " .. term.uk) else ns.Compat.print(ns.L.notFound) end
    else ns.Compat.print(ns.L.help) end
end
function Commands.register()
    if Commands.registered then return true end
    if type(SlashCmdList) ~= "table" or occupied() then ns.Compat.print(ns.L.commandConflict); return false end
    SLASH_UAFOREVERTRANSLATOR1 = "/uaft"
    SlashCmdList.UAFOREVERTRANSLATOR = Commands.dispatch
    Commands.registered = true
    return true
end
