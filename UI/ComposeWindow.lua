local _, ns = ...
local U = {}; ns.UI.ComposeWindow = U
local C, L = ns.Compat, ns.L
local function label(parent, text, x, y, width)
    local f = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    C.font(f); f:SetPoint("TOPLEFT", x, y); f:SetWidth(width); f:SetJustifyH("LEFT"); f:SetText(text)
    return f
end
local function button(parent, text, anchor, x, width, callback)
    local b = C.frame("Button", parent, "UIPanelButtonTemplate")
    b:SetPoint(anchor, x, 12); b:SetSize(width, 26); b:SetText(text)
    if b.GetFontString then C.font(b:GetFontString()) end
    b:SetScript("OnClick", callback); return b
end
local function edit(parent, y)
    local field = C.frame("EditBox", parent, "InputBoxTemplate")
    field:SetPoint("TOPLEFT", 20, y)
    field:SetPoint("TOPRIGHT", -16, y)
    field:SetHeight(20)
    field:SetAutoFocus(false)
    field:SetTextInsets(4, 4, 0, 0)
    field:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    C.font(field)
    return field
end
local function clearPreview()
    ns.Composer.invalidateDraft()
    U.draft:SetText("")
    U.draftLabel:SetText(L.draft)
end
local function preview()
    local original = C.read(U.source, "GetText")
    local result, reason = ns.Composer.translate(original)
    if not result then
        clearPreview()
        C.print(L[reason])
        return
    end
    U.draft:SetText(result.text)
    if C.read(U.draft, "GetText") ~= result.text then
        clearPreview()
        C.print(L.previewFailed)
        return
    end
    local caption = (result.mode == "partial" or result.mode == "unchanged") and L[result.mode] or L.draft
    U.draftLabel:SetText(caption)
    U.source:ClearFocus()
    U.draft:ClearFocus()
    ns.ChatLog.record("COMPOSER_PREVIEW", original, result, "uk-en")
end
function U.create()
    if U.frame then return end
    local f = C.frame("Frame", UIParent, "BackdropTemplate")
    f:Hide()
    f:SetSize(360, 184); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true); f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if not C.combat() then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",tile=true,tileSize=32,edgeSize=24,insets={left=5,right=5,top=5,bottom=5}})
    label(f, L.compose, 16, -14, 300)
    local close = C.frame("Button", f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    label(f, L.original, 16, -38, 328)
    U.source = edit(f, -53)
    U.draftLabel = label(f, L.draft, 16, -79, 328)
    U.draft = edit(f, -94)
    local destination = "current"
    local checkboxes = {}
    for index, mode in ipairs({"say", "group", "yell", "current"}) do
        local check = C.frame("CheckButton", f, "UICheckButtonTemplate")
        check:SetSize(20, 20)
        check:SetPoint("TOPLEFT", 16 + (index - 1) * 85, -119)
        check:SetHitRectInsets(0, -60, 0, 0)
        check.Text:SetText(L.chatDestinations[mode])
        check:SetChecked(mode == destination)
        checkboxes[mode] = check
        check:SetScript("OnClick", function()
            destination = mode
            for key, option in pairs(checkboxes) do option:SetChecked(key == destination) end
        end)
    end
    button(f, L.translate, "BOTTOMLEFT", 16, 130, preview)
    local clickedChat
    local insert = button(f, L.insert, "BOTTOMRIGHT", -16, 150, function()
        local context = clickedChat
        clickedChat = nil
        local ok, reason = ns.Composer.insert(C.read(U.draft, "GetText"), C.read(U.source, "GetText"), context, destination)
        if not ok then C.print(L[reason]) end
    end)
    insert:RegisterForClicks("LeftButtonDown")
    local function clearClickedChat() clickedChat = nil end
    insert:HookScript("OnLeave", clearClickedChat)
    insert:HookScript("OnMouseUp", clearClickedChat)
    local focusLostEvent = "ChatFrame.OnEditBoxFocusLost"
    f:SetScript("OnShow", function()
        EventRegistry:RegisterCallback(focusLostEvent, function(_, editBox)
            -- Blizzard emits this before closing an empty chat line on blur.
            if C.combat() or C.read(insert, "IsMouseOver") ~= true or not IsMouseButtonDown("LeftButton")
                or not C.public(editBox) or editBox ~= C.activeEdit() then return end
            local context = C.context(editBox)
            if context and context.text == "" then clickedChat = context end
        end, f)
    end)
    U.source:SetScript("OnTextChanged", function(_, user)
        if user and ns.Composer.result then clearPreview() end
    end)
    f:SetScript("OnHide", function()
        EventRegistry:UnregisterCallback(focusLostEvent, f)
        clearClickedChat()
        U.source:SetText("")
        clearPreview()
    end)
    U.frame = f
end
function U.open(text)
    if C.combat() then C.print(L.combat); return end
    U.create(); U.frame:Show()
    if text then
        U.source:SetText(text)
        if C.read(U.source, "GetText") ~= text then
            clearPreview()
            C.print(L.previewFailed)
            return
        end
        preview()
    end
end
