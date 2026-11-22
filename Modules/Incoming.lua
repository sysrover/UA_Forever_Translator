local _, ns = ...
local I = {}; ns.Incoming = I
local C, DB, Log = ns.Compat, ns.Database, ns.ChatLog
local listener, ready, triedToOpen, wasShowingUA
local registered = {}
local sliceMilliseconds, queueCapacity = 4, 64
local pending, first, count = {}, 1, 0
local active, scheduled, deadline
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

local function destinations(group)
    local settings = DB.settings
    if settings and settings.enabled and settings.channels[group] then
        return settings.showInUA and ns.UI.ChatTab.current(), mainDestination(settings)
    end
end

local function display(frame, message, r, g, b, id)
    if r then frame:AddMessage(message, r, g, b, id)
    else frame:AddMessage(message) end
end

local function playerLink(author, chatType, channelIndex, line)
    local caption = "[" .. plain(author) .. "]"
    if author == "" or author:find("[|:%c]") then return caption end
    if type(GetPlayerLink) == "function" then
        local chatGroup, chatTarget
        if ChatFrameUtil and type(ChatFrameUtil.GetChatCategory) == "function" then
            local ok, category = pcall(ChatFrameUtil.GetChatCategory, chatType)
            if ok and not C.secret(category) and type(category) == "string" then
                chatGroup = category
                if type(FCFManager_GetChatTarget) == "function" then
                    local found, target = pcall(FCFManager_GetChatTarget, category, author, channelIndex)
                    if found and not C.secret(target) then chatTarget = target end
                end
            end
        end
        local ok, link = pcall(GetPlayerLink, author, caption, line, chatGroup, chatTarget)
        if ok and not C.secret(link) and type(link) == "string" and link ~= "" then return link end
    end
    return "|Hplayer:" .. author .. "|h" .. caption .. "|h"
end

local function lineAllowed(line)
    if type(line) == "number" and line > 0 and C_ChatInfo and C_ChatInfo.IsChatLineCensored then
        local ok, censored = pcall(C_ChatInfo.IsChatLineCensored, line)
        return ok and not C.secret(censored) and not censored
    end
    return true
end

local function present(job, result, originalOnly, delayed)
    if not originalOnly and (not result or result.mode == "unchanged") then return end
    local group, context = job.group, job.context
    local tab, main = destinations(group)
    if not tab and (originalOnly or not main) then return end
    local event, author, line = context.event, context.author, context.line
    local channel, channelIndex = job.channel, job.channelIndex
    if delayed and (not C.public(job.text, author, channel, channelIndex, line)
        or not lineAllowed(line)) then return end
    local sourceName = ns.L.chatSources[group]
    local source = sourceName and "[" .. sourceName .. "]" or ""
    local chatType = event:sub(10)
    local infoType = chatType
    if group == "channel" then
        if type(channel) == "string" and channel ~= "" then source = "[" .. plain(channel) .. "]" end
        if type(channelIndex) == "number" and channelIndex > 0 and channelIndex % 1 == 0 then
            infoType = chatType .. channelIndex
            source = "|Hchannel:channel:" .. channelIndex .. "|h" .. source .. "|h"
        end
    end
    local info = ChatTypeInfo and ChatTypeInfo[infoType]
    local player = playerLink(author, chatType, channelIndex, line)
    local message = (source ~= "" and source .. " " or "") .. player .. ": "
        .. (originalOnly and job.text or result.text)
    local r, g, b, id
    local color = not originalOnly and DB.settings.translationColor
    if color then r, g, b = color.r, color.g, color.b
    elseif info and C.public(info.r, info.g, info.b, info.id) then r, g, b, id = info.r, info.g, info.b, info.id end
    local logTranslation = not originalOnly and DB.settings.logTranslations
    if tab then display(tab, message, r, g, b, id) end
    if not originalOnly and main and main ~= tab then display(main, message, r, g, b, id) end
    if logTranslation then
        Log.record(event, job.text, result, "en-uk", job.translationMs, job.maxSliceMs, Log.duration(job.neuralQueuedAt))
    end
end

local function checkpoint()
    if debugprofilestop() >= deadline then coroutine.yield() end
end

local function removeFirst()
    local job = pending[first]
    pending[first], active = nil, nil
    first, count = first % queueCapacity + 1, count - 1
    return job
end

local function reportError(message)
    local handler = type(geterrorhandler) == "function" and geterrorhandler()
    if type(handler) == "function" then pcall(handler, message) end
end

local function presentDelayed(job, result, originalOnly)
    local ok, message = pcall(present, job, result, originalOnly, true)
    if not ok then reportError(message) end
end

local schedule
local function drain()
    scheduled, deadline = nil, debugprofilestop() + sliceMilliseconds
    while count > 0 and debugprofilestop() < deadline do
        local job = pending[first]
        local tab, main = destinations(job.group)
        local neural = DB.settings.neuralIncoming
        local starting = not active or job.neural ~= neural
        if not (tab or main) or starting and not lineAllowed(job.context.line) then
            removeFirst()
        else
            if starting then
                job.neural = neural
                active = coroutine.create(function()
                    return ns.Translator.translate(job.text, "en-uk", job.context, checkpoint)
                end)
            end
            -- Measure each resume once. Waiting for the next frame belongs to neither duration.
            local startedAt = job.translationMs and Log.now()
            local ok, result = coroutine.resume(active)
            local sliceMs = Log.duration(startedAt)
            if sliceMs then
                job.translationMs = job.translationMs + sliceMs
                job.maxSliceMs = math.max(job.maxSliceMs, sliceMs)
            else
                job.translationMs, job.maxSliceMs = nil, nil
            end
            if ok and coroutine.status(active) ~= "dead" then break end
            removeFirst()
            if ok then presentDelayed(job, result)
            else reportError(result) end
        end
    end
    if count > 0 then schedule() end
end

schedule = function()
    if scheduled then return end
    scheduled = true
    C_Timer.After(0, drain)
end

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
    if DB.settings.neuralIncoming and DB.settings.logTranslations then job.neuralQueuedAt = Log.now() end
    if not C_Timer or type(C_Timer.After) ~= "function" or type(debugprofilestop) ~= "function" then
        local startedAt = Log.now()
        local result = ns.Translator.translate(text, "en-uk", job.context)
        job.translationMs = Log.duration(startedAt)
        job.maxSliceMs = job.translationMs
        present(job, result)
        return
    end
    local overflow
    -- Keep the original visible in the UA tab if the translation queue fills.
    if count == queueCapacity then overflow = removeFirst() end
    pending[(first + count - 1) % queueCapacity + 1] = job
    count = count + 1
    schedule()
    if overflow then presentDelayed(overflow, nil, true) end
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
    if not settings.enabled and count > 0 then pending, first, count, active = {}, 1, 0, nil end
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
