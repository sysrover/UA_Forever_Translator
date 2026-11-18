local _, ns = ...
local M = {}; ns.Composer = M
local C = ns.Compat
function M.capture()
    M.context = nil
    local context = C.context(C.selectedEdit())
    if not context then return false, "noChat" end
    local allowed = {SAY=true,YELL=true,WHISPER=true,PARTY=true,RAID=true,RAID_WARNING=true,GUILD=true,OFFICER=true,INSTANCE_CHAT=true,CHANNEL=true}
    if not allowed[context.chatType] or (context.chatType == "WHISPER" and (not context.target or context.target == ""))
        or (context.chatType == "CHANNEL" and context.channel == nil) then return false, "noChat" end
    M.context = context
    return true
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
    M.context = nil
    M.invalidateDraft()
end
function M.insert(text, consent, source)
    if C.combat() then return false, "combat" end
    if not C.public(text, source) or type(text) ~= "string" or text == "" then return false, "unsupported" end
    if text:find("[\r\n]") or text:match("^%s*/") then return false, "singleLine" end
    if not M.result or source ~= M.source then return false, "staleDraft" end
    if (M.result.mode == "partial" or M.result.mode == "unchanged") and not consent then return false, "confirmPartial" end
    local current = C.context(C.selectedEdit())
    if not C.sameContext(M.context, current) then return false, "targetChanged" end
    local allowed, reason = C.withinLimit(current.edit, text)
    if not allowed then return false, reason end
    local forbidden = C.read(current.edit, "IsForbidden")
    if forbidden ~= false then return false, "writeFailed" end
    local ok = pcall(function()
        -- Re-read immediately before mutation. Never redirect or reactivate a
        -- different field, and never truncate UTF-8 or invoke a send API.
        if C.combat() or not C.sameContext(current, C.context(C.selectedEdit())) then error("context-changed") end
        local activate = ChatFrameUtil and ChatFrameUtil.ActivateChat or ChatEdit_ActivateChat
        if type(activate) ~= "function" then error("activation-unavailable") end
        activate(current.edit)
        -- OnShow may reset a hidden native field to its sticky chat type.
        -- Do not insert if activation changed the selected destination.
        if C.combat() or not C.sameContext(current, C.context(C.activeEdit())) then error("context-changed") end
        if C.read(current.edit, "IsForbidden") ~= false then error("forbidden") end
        current.edit:SetText(text)
        if C.read(current.edit, "GetText") ~= text then
            current.edit:SetText(current.text)
            error("native-capacity-changed")
        end
        current.edit:SetFocus()
    end)
    if not ok then return false, "writeFailed" end
    M.context = C.context(current.edit)
    return true, "inserted"
end
