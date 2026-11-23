local _, ns = ...
local I = {}; ns.Incoming = I
local C, DB, Log = ns.Compat, ns.Database, ns.ChatLog
local listener, ready, triedToOpen, wasShowingUA
local registered = {}
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

local function destinations(group)
    local settings = DB.settings
    if settings and settings.enabled and settings.channels[group] then
        return settings.showInUA and ns.UI.ChatTab.current(), mainDestination(settings)
    end
end

local function lineAllowed(line)
    if type(line) == "number" and line > 0 and C_ChatInfo and C_ChatInfo.IsChatLineCensored then
        local ok, censored = pcall(C_ChatInfo.IsChatLineCensored, line)
        return ok and not C.secret(censored) and not censored
    end
    return true
end

local function eligible(job)
    local tab, main = destinations(job.group)
    local context = job.context
    return (tab or main) and C.public(job.text, context.author, job.channel, job.channelIndex, context.line)
        and lineAllowed(context.line)
end

local function present(job, result, originalOnly, delayed)
    local tab, main = destinations(job.group)
    if not tab and (originalOnly or not main) then return "cancelled" end
    if delayed then
        local context = job.context
        if not C.public(job.text, context.author, job.channel, job.channelIndex, context.line)
            or not lineAllowed(context.line) then return "cancelled" end
    end
    if not originalOnly and (not result or result.mode == "unchanged") then return "unchanged" end
    ns.ChatPresentation.show(job, result, originalOnly, tab, main)
    return "completed"
end

local function reportError(message)
    local handler = type(geterrorhandler) == "function" and geterrorhandler()
    if type(handler) == "function" then pcall(handler, message) end
end

local function modelPolicy()
    return DB.settings.neuralIncoming and "allowed" or "disabled"
end

local function translate(job, checkpoint, model)
    return ns.Translator.translate(job.text, "en-uk", job.context, checkpoint, {model=model})
end

local queue = ns.IncomingQueue.new({
    clock=function() return debugprofilestop() end,
    schedule=function(callback) C_Timer.After(0, callback) end,
    now=Log.now, duration=Log.duration,
    eligible=eligible, present=present, reportError=reportError, model=modelPolicy, translate=translate,
})
I.hasPendingWork = queue.hasPending

local function addTranslation(event, group, text, author, ...)
    if not C.public(text, author, ...) then return end
    if type(text) ~= "string" or type(author) ~= "string" or #text > ns.Limits.messageBytes then return end
    local language, channel, target, flags = ...
    local channelIndex = select(6, ...)
    local line, sender = select(9, ...)
    -- Match the client's cinematic, GM whisper and censored-line guards.
    if select(14, ...) or (group == "whisper" and flags == "GM") or not lineAllowed(line) then return end
    if not DB.settings.own and ownMessage(author, sender) then return end
    local job = {text=text, group=group, channel=channel, channelIndex=channelIndex,
        translationMs=0, maxSliceMs=0,
        context={event=event, line=line, author=author, sender=sender, language=language, target=target}}
    if DB.settings.logTranslations then job.queuedAt = Log.now() end
    if not C_Timer or type(C_Timer.After) ~= "function" or type(debugprofilestop) ~= "function" then
        local startedAt = Log.now()
        local result = translate(job, nil, DB.settings.neuralIncoming and "budget-unavailable" or "disabled")
        job.translationMs = Log.duration(startedAt)
        job.maxSliceMs = job.translationMs
        present(job, result)
        return
    end
    queue.push(job)
end

local function onEvent(_, event, ...)
    if C.secret(event) then return end
    if event == "PLAYER_REGEN_ENABLED" then
        listener:UnregisterEvent(event)
        I.configure()
        return
    end
    local group = DB.eventGroups[event]
    if not group then return end
    local tab, main = destinations(group)
    if tab or main then addTranslation(event, group, ...) end
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
    if not settings.enabled then queue.cancel() end
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
