local _, ns = ...
local I = {}; ns.Incoming = I
local C, DB = ns.Compat, ns.Database
local listener, ready, triedToOpen, wasShowingUA
local registered = {}
local function plain(value)
    return (value:gsub("|", "||"))
end
local function ownMessage(author, sender)
    local ok, guid = pcall(UnitGUID, "player")
    if ok and not C.secret(guid) and type(guid) == "string" and sender == guid then return true end
    -- GUID is authoritative; do not confuse equal base names across realms.
    if type(sender) == "string" and sender ~= "" then return false end
    if type(UnitFullName) == "function" then
        local success, name, realm = pcall(UnitFullName, "player")
        if success and C.public(name, realm) and type(name) == "string" then
            if author == name then return true end
            if type(realm) == "string" and realm ~= "" and author == name .. "-" .. realm then return true end
        end
    end
    return false
end
local function mainDestination(settings)
    local frame = settings.showInMain and DEFAULT_CHAT_FRAME
    if frame and type(frame.AddMessage) == "function" then return frame end
end

local function display(frame, message, r, g, b, id)
    if r then frame:AddMessage(message, r, g, b, id)
    else frame:AddMessage(message) end
end

local function addTranslation(tab, main, event, group, text, author, ...)
    if not C.public(text, author, ...) then return end
    if type(text) ~= "string" or type(author) ~= "string" then return end
    if #text > ns.Limits.messageBytes then return end
    local language, channel, target, flags = ...
    local channelIndex = select(6, ...)
    local line, sender = select(9, ...)
    -- Match the client's cinematic, GM whisper and censored-line guards.
    if select(14, ...) or (group == "whisper" and flags == "GM") then return end
    if type(line) == "number" and line > 0 and C_ChatInfo and C_ChatInfo.IsChatLineCensored then
        local ok, censored = pcall(C_ChatInfo.IsChatLineCensored, line)
        if not ok or C.secret(censored) or censored then return end
    end
    if not DB.settings.own and ownMessage(author, sender) then return end
    local result = ns.Translator.translate(text, "en-uk", {
        event=event, line=line, author=author, sender=sender, language=language, target=target })
    if not result or result.mode == "unchanged" then return end

    local label = result.mode == "partial" and ns.L.partialLabel or ns.L.translationLabel
    local source = ns.L.chatSources[group]
    local chatType = event:sub(10)
    if group == "channel" then
        if type(channel) == "string" and channel ~= "" then source = plain(channel) end
        if type(channelIndex) == "number" and channelIndex > 0 then chatType = chatType .. channelIndex end
    end
    local info = ChatTypeInfo and ChatTypeInfo[chatType]
    local message = label .. "[" .. source .. "] [" .. plain(author) .. "]: " .. result.text
    local r, g, b, id
    local color = DB.settings.translationColor
    if color then r, g, b = color.r, color.g, color.b
    elseif info and C.public(info.r, info.g, info.b, info.id) then r, g, b, id = info.r, info.g, info.b, info.id end
    if tab then display(tab, message, r, g, b, id) end
    if main and main ~= tab then display(main, message, r, g, b, id) end
    if DB.settings.logTranslations then
        ns.ChatLog.record(event, text, result, "en-uk")
    end
end

local function onEvent(_, event, ...)
    if C.secret(event) then return end
    if event == "PLAYER_REGEN_ENABLED" then
        listener:UnregisterEvent(event)
        I.configure()
        return
    end
    local settings = DB.settings
    local group = DB.eventGroups[event]
    if settings and settings.enabled and group and settings.channels[group] then
        local tab = settings.showInUA and ns.UI.ChatTab.current()
        local main = mainDestination(settings)
        if tab or main then addTranslation(tab, main, event, group, ...) end
    end
end

local function eventFrame()
    if not listener then
        listener = C.frame("Frame")
        listener:SetScript("OnEvent", onEvent)
    end
    return listener
end

function I.configure()
    if not ready or not DB.settings then return end
    local settings = DB.settings
    if settings.showInUA and not wasShowingUA then triedToOpen = nil end
    wasShowingUA = settings.showInUA
    local tab = settings.showInUA and ns.UI.ChatTab.current()
    if settings.showInUA and not tab and settings.enabled and not triedToOpen then
        if C.combat() then
            eventFrame():RegisterEvent("PLAYER_REGEN_ENABLED")
        else
            local reason
            tab, reason = ns.UI.ChatTab.open(false)
            triedToOpen = reason ~= "tabUnavailable"
        end
    end
    local destination = tab or mainDestination(settings)
    for event, group in pairs(DB.eventGroups) do
        local wanted = destination and settings.enabled and settings.channels[group]
        if wanted and not registered[event] then
            eventFrame():RegisterEvent(event)
            registered[event] = true
        elseif not wanted and registered[event] then
            listener:UnregisterEvent(event)
            registered[event] = nil
        end
    end
end

function I.start()
    ready = true
    I.configure()
end

function I.openTab()
    local tab, reason = ns.UI.ChatTab.open(true)
    if not tab then C.print(ns.L[reason]); return end
    triedToOpen = true
    I.configure()
end
