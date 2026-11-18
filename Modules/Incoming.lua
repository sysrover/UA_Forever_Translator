local _, ns = ...
local I = {}; ns.Incoming = I
local C, DB = ns.Compat, ns.Database
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
function I.filter(frame, event, text, author, ...)
    -- Guard the complete event before types, equality, concatenation, cache keys
    -- or forwarding a replacement list. Native processing owns secret messages.
    if not C.public(event, text, author, ...) then return nil end
    if type(text) ~= "string" or type(author) ~= "string" then return nil end
    local settings = DB.settings
    local group = DB.eventGroups[event]
    if not settings or not settings.enabled or not group or not settings.channels[group] then return nil end
    if #text > ns.Limits.messageBytes or text:find(ns.L.translationLabel, 1, true)
        or text:find(ns.L.partialLabel, 1, true) then return nil end
    -- Message arg11 = lineID, arg12 = senderGUID in exact-build ChatFrameUtil.
    local language, target, line, sender = select(1, ...), select(3, ...), select(9, ...), select(10, ...)
    if not settings.own and ownMessage(author, sender) then return nil end
    local result = ns.Translator.translate(text, "en-uk", {
        event=event, line=line, author=author, sender=sender, language=language, target=target })
    if not result or result.mode == "unchanged" then return nil end
    local label = result.mode == "partial" and ns.L.partialLabel or ns.L.translationLabel
    local divider = settings.display == "annotation" and "  — " or "\n"
    -- One native row keeps sender, links, all tail arguments and each frame's
    -- visibility rules. No AddMessage side effect inside a multiply-called filter.
    return false, text .. divider .. label .. result.text, author, ...
end
function I.configure()
    local settings = DB.settings
    if not settings then return end
    local wantedCount, registeredCount = 0, 0
    for event, group in pairs(DB.eventGroups) do
        local wanted = settings.enabled and settings.channels[group]
        if wanted then wantedCount = wantedCount + 1 end
        if wanted and not registered[event] then registered[event] = C.addFilter(event, I.filter)
        elseif not wanted and registered[event] then
            C.removeFilter(event, I.filter); registered[event] = nil
        end
        if registered[event] then registeredCount = registeredCount + 1 end
    end
    return wantedCount == 0 or registeredCount > 0
end
