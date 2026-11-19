local _, ns = ...
local M = {}; ns.Composer = M
local C = ns.Compat
local allowed = {SAY=true,YELL=true,WHISPER=true,PARTY=true,RAID=true,RAID_WARNING=true,GUILD=true,OFFICER=true,INSTANCE_CHAT=true,CHANNEL=true}

local function openChatContext()
    local edit = C.activeEdit()
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
function M.insert(text, source)
    if C.combat() then return false, "combat" end
    if not C.public(text, source) then return false, "unsupported" end
    if not M.result or source ~= M.source then return false, "staleDraft" end
    if type(text) ~= "string" or text == "" then return false, "unsupported" end
    if text:find("[\r\n]") or text:match("^%s*/") then return false, "singleLine" end
    local current = openChatContext()
    if not current or not allowed[current.chatType]
        or (current.chatType == "WHISPER" and (not current.target or current.target == ""))
        or (current.chatType == "CHANNEL" and current.channel == nil) then return false, "noChat" end
    if current.text:match("^%s*/") then return false, "chatCommand" end
    local fits, reason = C.withinLimit(current.edit, text)
    if not fits then return false, reason end
    if C.read(current.edit, "IsForbidden") ~= false then return false, "writeFailed" end
    local ok = pcall(function()
        if C.combat() or not C.sameContext(current, openChatContext()) then error("context-changed") end
        current.edit:SetFocus()
        -- Native focus handlers can change the active field or destination.
        if C.combat() or not C.sameContext(current, openChatContext()) then error("context-changed") end
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
