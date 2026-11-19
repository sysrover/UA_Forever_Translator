local _, ns = ...
local M = {}; ns.Composer = M
local C = ns.Compat
local allowed = {SAY=true,YELL=true,WHISPER=true,PARTY=true,RAID=true,RAID_WARNING=true,GUILD=true,OFFICER=true,INSTANCE_CHAT=true,CHANNEL=true}
local destinationTypes = {say = "SAY", yell = "YELL"}

local function openChatContext(edit)
    if C.read(edit, "IsVisible") ~= true then return nil end
    return C.context(edit)
end

local function defaultChatContext()
    local choose = ChatFrameUtil and ChatFrameUtil.ChooseBoxForSend
    if type(choose) ~= "function" then return nil end
    local ok, edit = pcall(choose)
    if ok then return C.context(edit) end
end

local function groupChatType()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid(LE_PARTY_CATEGORY_HOME) then return "RAID" end
    if IsInGroup(LE_PARTY_CATEGORY_HOME) then return "PARTY" end
end

local function canUseCurrentChannel(context)
    return allowed[context.chatType]
        and (context.chatType ~= "WHISPER" or (context.target and context.target ~= ""))
        and (context.chatType ~= "CHANNEL" or context.channel ~= nil)
end

function M.translate(text)
    M.invalidateDraft()
    local result = ns.Translator.translate(text, "uk-en")
    if not result then return nil, "unsupported" end
    if result.reason == "byte-limit" then return nil, "sourceTooLong" end
    M.source, M.result = text, result
    return result
end
function M.invalidateDraft()
    M.result, M.source = nil, nil
end
function M.clear()
    M.invalidateDraft()
end
function M.insert(text, source, clickedChat, destination)
    if C.combat() then return false, "combat" end
    if not C.public(text, source) then return false, "unsupported" end
    if not M.result or source ~= M.source then return false, "staleDraft" end
    if type(text) ~= "string" or text == "" then return false, "unsupported" end
    if text:find("[\r\n]") or text:match("^%s*/") then return false, "singleLine" end
    local chatType = destinationTypes[destination]
    if destination == "group" then
        chatType = groupChatType()
        if not chatType then return false, "noGroup" end
    end
    local active = C.activeEdit()
    local current
    if active then
        current = openChatContext(active)
    else
        current = clickedChat or defaultChatContext()
    end
    if clickedChat and not C.sameContext(clickedChat, current) then return false, "writeFailed" end
    local preserveChannel = active or clickedChat
    if not current or (not chatType and preserveChannel and not canUseCurrentChannel(current)) then return false, "noChat" end
    if current.text:match("^%s*/") then return false, "chatCommand" end
    local fits, reason = C.withinLimit(current.edit, text)
    if not fits then return false, reason end
    if C.read(current.edit, "IsForbidden") ~= false then return false, "writeFailed" end
    local edit = current.edit
    local previousType
    local ok = pcall(function()
        if C.combat() then error("combat") end
        local live = C.activeEdit()
        if not active then
            if live or not C.sameContext(current, C.context(edit)) then error("context-changed") end
            local activate = ChatFrameUtil and ChatFrameUtil.ActivateChat or ChatEdit_ActivateChat
            if type(activate) ~= "function" then error("activation-unavailable") end
            activate(edit)
        else
            if not C.sameContext(current, openChatContext(live)) then error("context-changed") end
            edit:SetFocus()
        end
        local focused = openChatContext(C.activeEdit())
        if C.combat() or not focused or focused.edit ~= edit or focused.text ~= current.text then error("context-changed") end
        if C.read(edit, "IsForbidden") ~= false then error("forbidden") end
        if chatType then
            if destination == "group" and groupChatType() ~= chatType then error("group-changed") end
            -- Use the same channel and header operations as the native chat menu.
            previousType = focused.chatType
            edit:SetChatType(chatType)
            edit:UpdateHeader()
            focused.chatType, focused.target, focused.channel = chatType, nil, nil
            if C.combat() or not C.sameContext(focused, openChatContext(C.activeEdit())) then error("context-changed") end
        elseif (preserveChannel and not C.sameContext(current, focused)) or not canUseCurrentChannel(focused) then
            error("context-changed")
        end
        edit:SetText(text)
        if C.read(edit, "GetText") ~= text then
            edit:SetText(current.text)
            error("native-capacity-changed")
        end
    end)
    if not ok then
        if previousType and not C.combat() and C.activeEdit() == edit and C.read(edit, "IsForbidden") == false then
            pcall(function()
                edit:SetChatType(previousType)
                edit:UpdateHeader()
            end)
        end
        return false, "writeFailed"
    end
    return true
end
