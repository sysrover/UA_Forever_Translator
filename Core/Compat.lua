local _, ns = ...
local C = {}; ns.Compat = C
C.targetBuild = "1.60.1.70959"
function C.secret(value)
    if type(issecretvalue) ~= "function" then return false end
    local ok, secret = pcall(issecretvalue, value)
    return not ok or secret
end
function C.public(...)
    for i = 1, select("#", ...) do
        if C.secret(select(i, ...)) then return false end
    end
    return true
end
function C.read(object, method, ...)
    local args, count = {...}, select("#", ...)
    local ok, value = pcall(function()
        local fn = object and object[method]
        if type(fn) == "function" then return fn(object, unpack(args, 1, count)) end
    end)
    if not ok or C.secret(value) then return nil end
    return value
end
function C.combat()
    if type(InCombatLockdown) ~= "function" then return false end
    local ok, value = pcall(InCombatLockdown)
    return not ok or C.secret(value) or value == true
end
function C.frame(kind, parent, template)
    return CreateFrame(kind, nil, parent, template)
end
function C.activeEdit()
    local fn = ChatFrameUtil and ChatFrameUtil.GetActiveWindow or ChatEdit_GetActiveWindow
    if type(fn) ~= "function" then return nil end
    local ok, edit = pcall(fn)
    if ok and not C.secret(edit) then return edit end
end
function C.context(edit)
    if not edit or C.secret(edit) then return nil end
    local chatType = C.read(edit, "GetAttribute", "chatType")
    local target = C.read(edit, "GetAttribute", "tellTarget")
    local channel = C.read(edit, "GetAttribute", "channelTarget")
    local text = C.read(edit, "GetText")
    if chatType ~= "WHISPER" then target = nil end
    if chatType ~= "CHANNEL" then channel = nil end
    if type(chatType) ~= "string" or type(text) ~= "string"
        or (target ~= nil and type(target) ~= "string")
        or (channel ~= nil and type(channel) ~= "number" and type(channel) ~= "string") then return nil end
    return { edit = edit, chatType = chatType, target = target, channel = channel, text = text }
end
function C.sameContext(a, b)
    return a and b and a.edit == b.edit and a.chatType == b.chatType
        and a.target == b.target and a.channel == b.channel and a.text == b.text
end
local capacityField
function C.withinLimit(edit, text)
    local bytes = C.read(edit, "GetMaxBytes")
    local letters = C.read(edit, "GetMaxLetters")
    local visible = C.read(edit, "GetVisibleTextByteLimit")
    local invisible = C.read(edit, "IsCountInvisibleLetters")
    if type(bytes) ~= "number" or type(letters) ~= "number" or type(visible) ~= "number"
        or type(invisible) ~= "boolean" or bytes <= 0 then return false, "limitUnknown" end
    if #text > bytes then return false, "tooLong" end
    -- Exact-build native fields have separate total/visible/invisible byte
    -- limits (1280/255/1023). Let an owned hidden field apply the actual byte
    -- policy before touching the player's draft; never approximate link labels.
    local ok, accepted = pcall(function()
        if not capacityField then
            capacityField = C.frame("EditBox", UIParent)
            capacityField:SetFontObject(ChatFontNormal)
            capacityField:SetAutoFocus(false); capacityField:Hide()
        end
        capacityField:SetMaxBytes(bytes); capacityField:SetMaxLetters(letters)
        capacityField:SetVisibleTextByteLimit(visible); capacityField:SetCountInvisibleLetters(invisible)
        capacityField:SetText(text)
        local stored = capacityField:GetText()
        local equal = not C.secret(stored) and stored == text
        capacityField:SetText("")
        return equal
    end)
    if not ok then return false, "limitUnknown" end
    if accepted then return true end
    return false, "tooLong"
end
function C.font(region)
    -- Native Cyrillic font identity is present in the client listfile. Actual
    -- Ukrainian glyph rendering remains part of the manual compatibility matrix.
    if region and region.SetFont then pcall(region.SetFont, region, "Fonts\\FRIZQT___CYR.TTF", 13, "") end
end
function C.print(text)
    if DEFAULT_CHAT_FRAME and type(text) == "string" then
        DEFAULT_CHAT_FRAME:AddMessage("|cff69c9ffUAFT|r " .. text)
    end
end
