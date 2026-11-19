local _, ns = ...
local M = {}; ns.Composer = M
local C = ns.Compat
local allowed = {SAY=true,YELL=true,WHISPER=true,PARTY=true,RAID=true,RAID_WARNING=true,GUILD=true,OFFICER=true,INSTANCE_CHAT=true,CHANNEL=true}

local function openChatContext(edit)
    if C.read(edit, "IsVisible") ~= true then return nil end
    return C.context(edit)
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
function M.insert(text, source, clickedChat)
    if C.combat() then return false, "combat" end
    if not C.public(text, source) then return false, "unsupported" end
    if not M.result or source ~= M.source then return false, "staleDraft" end
    if type(text) ~= "string" or text == "" then return false, "unsupported" end
    if text:find("[\r\n]") or text:match("^%s*/") then return false, "singleLine" end
    local active = C.activeEdit()
    local reopen = clickedChat and not active
    local current = reopen and clickedChat or openChatContext(active)
    if clickedChat and not C.sameContext(clickedChat, current) then return false, "writeFailed" end
    if not current or not allowed[current.chatType]
        or (current.chatType == "WHISPER" and (not current.target or current.target == ""))
        or (current.chatType == "CHANNEL" and current.channel == nil) then return false, "noChat" end
    if current.text:match("^%s*/") then return false, "chatCommand" end
    local fits, reason = C.withinLimit(current.edit, text)
    if not fits then return false, reason end
    if C.read(current.edit, "IsForbidden") ~= false then return false, "writeFailed" end
    local ok = pcall(function()
        if C.combat() then error("combat") end
        local live = C.activeEdit()
        if reopen then
            if live or not C.sameContext(current, C.context(current.edit)) then error("context-changed") end
            local activate = ChatFrameUtil and ChatFrameUtil.ActivateChat or ChatEdit_ActivateChat
            if type(activate) ~= "function" then error("activation-unavailable") end
            activate(current.edit)
        else
            if not C.sameContext(current, openChatContext(live)) then error("context-changed") end
            current.edit:SetFocus()
        end
        -- Native focus handlers can change the active field or destination.
        if C.combat() or not C.sameContext(current, openChatContext(C.activeEdit())) then error("context-changed") end
        if C.read(current.edit, "IsForbidden") ~= false then error("forbidden") end
        current.edit:SetText(text)
        if C.read(current.edit, "GetText") ~= text then
            current.edit:SetText(current.text)
            error("native-capacity-changed")
        end
    end)
    if not ok then return false, "writeFailed" end
    return true
end
