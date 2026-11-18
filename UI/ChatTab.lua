local _, ns = ...
local T = {}; ns.UI.ChatTab = T
local C, L = ns.Compat, ns.L
local window, hooksInstalled

local systemMessages = {
    BN_CONNECTED = true, BN_DISCONNECTED = true,
    CHAT_SERVER_DISCONNECTED = true, CHAT_SERVER_RECONNECTED = true,
    CHAT_REGIONAL_STATUS_CHANGED = true, CHAT_REGIONAL_SEND_FAILED = true,
    NOTIFY_CHAT_SUPPRESSED = true,
}

local function hideNativeMessages(_, event)
    -- The native frame still handles configuration, layout and reports.
    return systemMessages[event] or event:sub(1, 9) == "CHAT_MSG_"
end

function T.current()
    return window
end

local function detach(frame)
    if not window or frame ~= window then return end
    if frame.customEventHandler == hideNativeMessages then frame.customEventHandler = nil end
    window, UA_Forever_TranslatorTabID = nil, nil
    if ns.Incoming then ns.Incoming.configure() end
end

local function installHooks()
    if hooksInstalled then return end
    hooksecurefunc("FCF_Close", function(frame, fallback)
        detach(fallback or frame or FCF_GetCurrentChatFrame())
    end)
    hooksecurefunc("FCF_SetWindowName", function(frame)
        if frame == window and (C.secret(frame.name) or frame.name ~= L.tabName) then detach(frame) end
    end)
    hooksInstalled = true
end

local function hasSavedSubscriptions(getter, id)
    if type(getter) ~= "function" then return nil end
    local ok, first = pcall(getter, id)
    if not ok or C.secret(first) then return nil end
    return first ~= nil and first ~= ""
end

local function reusableWindow(id)
    if C.secret(id) or type(id) ~= "number" or id < 1 or id > Constants.ChatFrameConstants.MaxChatWindows or id % 1 ~= 0
        or FCF_IsChatWindowIndexReserved(id) then return nil end
    local frame = FCF_GetChatFrameByID(id)
    if not frame or C.secret(frame.name) or frame.customEventHandler or frame == DEFAULT_CHAT_FRAME then return nil end
    local active = FCF_IsChatWindowIndexActive(id)
    local name = frame.name
    -- Docked tabs can still be hidden while WoW is restoring chat windows.
    if type(GetChatWindowInfo) == "function" then
        local ok, savedName, _, _, _, _, _, shown, _, docked = pcall(GetChatWindowInfo, id)
        if ok and C.public(savedName, shown, docked) and type(savedName) == "string" and savedName ~= "" then
            name = savedName
            active = active or shown == true or docked == true or (type(docked) == "number" and docked > 0)
        end
    end
    if not active or name ~= L.tabName then return nil end
    local groups = hasSavedSubscriptions(GetChatWindowMessages, id)
    local channels = hasSavedSubscriptions(GetChatWindowChannels, id)
    if groups == nil then groups = type(frame.messageTypeList) ~= "table" or next(frame.messageTypeList) ~= nil end
    if channels == nil then channels = type(frame.channelList) ~= "table" or next(frame.channelList) ~= nil end
    if not groups and not channels then return frame end
end

local function restoreWindow()
    local saved = UA_Forever_TranslatorTabID
    local frame = reusableWindow(saved)
    if frame then return frame, saved end
    for id = 1, Constants.ChatFrameConstants.MaxChatWindows do
        frame = reusableWindow(id)
        if frame then return frame, id end
    end
end

local function show(frame)
    if frame.isDocked then
        FCF_SelectDockFrame(frame)
    elseif frame.minimized then
        FCF_MaximizeFrame(frame)
    else
        FCF_FadeInChatFrame(frame)
    end
end

function T.open(selectWindow)
    if C.combat() then return nil, "tabCombat" end
    if window then
        if selectWindow then show(window) end
        return window
    end
    if type(FCF_OpenNewWindow) ~= "function" or type(FCF_IsChatWindowIndexReserved) ~= "function"
        or type(FCF_SelectDockFrame) ~= "function" or type(FCF_GetChatFrameByID) ~= "function"
        or type(FCF_Close) ~= "function" or type(FCF_SetWindowName) ~= "function"
        or type(FCF_IsChatWindowIndexActive) ~= "function" or type(hooksecurefunc) ~= "function"
        or type(FCFDock_GetSelectedWindow) ~= "function" or not GENERAL_CHAT_DOCK
        or not (ChatFrameUtil and ChatFrameUtil.GetLastActiveWindow and ChatFrameUtil.SetLastActiveWindow)
        or not (Constants and Constants.ChatFrameConstants) then
        return nil, "tabUnavailable"
    end
    installHooks()

    local frame, id = restoreWindow()
    if not frame then
        UA_Forever_TranslatorTabID = nil
        local previous = FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK) or DEFAULT_CHAT_FRAME
        local editBox = ChatFrameUtil.GetLastActiveWindow()
        -- true requests a docked window with no default message groups.
        local ok
        ok, frame, id = pcall(FCF_OpenNewWindow, L.tabName, true)
        if not ok then return nil, "tabUnavailable" end
        if not frame then return nil, "tabFull" end
        if type(id) ~= "number" then id = C.read(frame, "GetID") end
        if not selectWindow and previous then FCF_SelectDockFrame(previous) end
        if not C.secret(editBox) then ChatFrameUtil.SetLastActiveWindow(editBox) end
    elseif selectWindow then
        show(frame)
    end

    frame.customEventHandler = hideNativeMessages
    window, UA_Forever_TranslatorTabID = frame, id
    return window
end
