local _, ns = ...
local U = {}; ns.UI.ComposeWindow = U
local C, L = ns.Compat, ns.L
local composeFont
local function label(parent, text, x, y, width)
    local f = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    C.font(f); f:SetPoint("TOPLEFT", x, y); f:SetWidth(width); f:SetJustifyH("LEFT"); f:SetText(text)
    return f
end
local function button(parent, text, x, y, width, callback)
    local b = C.frame("Button", parent, "UIPanelButtonTemplate")
    b:SetPoint("BOTTOMLEFT", x, y); b:SetSize(width, 26); b:SetText(text)
    if b.GetFontString then C.font(b:GetFontString()) end
    b:SetScript("OnClick", callback); return b
end
local function edit(parent, y)
    local field = C.frame("Frame", parent, "ScrollingEditBoxTemplate")
    field:SetPoint("TOPLEFT", 20, y)
    field:SetSize(564, 92)
    field:SetTextInsets(2, 4, 2, 2)
    if not composeFont then
        composeFont = CreateFont("UAForeverTranslatorComposeFont")
        composeFont:CopyFontObject(GameFontHighlight)
        C.font(composeFont)
    end
    -- EventEditBox:ApplyText restores its configured font on every write.
    field:GetEditBox().fontName = composeFont
    field:SetFontObject(composeFont)

    local bar = C.frame("EventFrame", parent, "MinimalScrollBar")
    bar:SetPoint("TOPLEFT", field, "TOPRIGHT", 6, 0)
    bar:SetPoint("BOTTOMLEFT", field, "BOTTOMRIGHT", 6, 0)
    ScrollUtil.InitScrollBar(field:GetScrollBox(), bar)
    return field
end
local function status(key)
    U.status:SetText(L[key] or L.unsupported)
end
local function clearPreview(reason)
    ns.Composer.invalidateDraft()
    U.draft:SetText("")
    U.consent:SetChecked(false)
    status(reason)
end
local function preview()
    local original = C.read(U.source, "GetText")
    local result, reason = ns.Composer.translate(original)
    if not result then
        clearPreview(reason)
        return
    end
    U.draft:SetText(result.text)
    if C.read(U.draft, "GetText") ~= result.text then
        clearPreview("previewFailed")
        return
    end
    U.consent:SetChecked(false)
    status(result.mode)
    ns.ChatLog.record("COMPOSER_PREVIEW", original, result, "uk-en")
end
function U.create()
    if U.frame then return end
    local f = C.frame("Frame", UIParent, "BackdropTemplate")
    f:SetSize(628, 530); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true); f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if not C.combat() then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",tile=true,tileSize=32,edgeSize=24,insets={left=5,right=5,top=5,bottom=5}})
    label(f, L.compose, 20, -20, 580)
    label(f, L.original, 20, -52, 580); U.source = edit(f, -78)
    label(f, L.draft, 20, -184, 580); U.draft = edit(f, -210)
    U.status = label(f, L.unchanged, 20, -314, 585); U.status:SetHeight(45); U.status:SetJustifyV("TOP")
    U.target = label(f, "", 20, -366, 580); U.target:SetHeight(42); U.target:SetJustifyV("TOP")
    U.consent = C.frame("CheckButton", f, "UICheckButtonTemplate")
    U.consent:SetPoint("TOPLEFT", 16, -412); U.consent:SetSize(26, 26)
    local consentText = label(f, L.partialConsent, 46, -416, 548); consentText:SetHeight(40)
    button(f, L.translate, 20, 52, 130, preview)
    button(f, L.capture, 160, 52, 235, function()
        local ok, reason = ns.Composer.capture()
        if not ok then status(reason) end
        U.updateTarget()
    end)
    button(f, L.insert, 405, 52, 195, function()
        local ok, reason = ns.Composer.insert(C.read(U.draft, "GetText"), U.consent:GetChecked(), C.read(U.source, "GetText"))
        status(reason)
        if ok then U.source:ClearFocus(); U.draft:ClearFocus() end
    end)
    button(f, L.close, 490, 15, 110, function() f:Hide() end)
    U.source:RegisterCallback("OnTextChanged", function(_, _, user)
        if not user then return end
        ns.Composer.invalidateDraft()
        U.consent:SetChecked(false)
        status("staleDraft")
    end, U)
    U.draft:RegisterCallback("OnTextChanged", function(_, _, user)
        if not user then return end
        U.consent:SetChecked(false)
        status(ns.Composer.result and "edited" or "staleDraft")
    end, U)
    f:SetScript("OnHide", function()
        ns.Composer.clear(); U.source:SetText(""); U.draft:SetText(""); U.consent:SetChecked(false)
    end)
    U.frame = f
end
function U.updateTarget()
    local target = ns.Composer.context
    U.target:SetText(L.target .. (target and (target.chatType .. (target.target and (" → " .. target.target) or "")
        .. (target.channel and (" #" .. target.channel) or "")) or L.noTarget))
end
function U.open(text)
    if C.combat() then C.print(L.combat); return end
    local context = C.context(C.selectedEdit())
    U.create(); U.frame:Show()
    ns.Composer.context = nil
    -- A slash handler runs before the native command clears its input. That
    -- transient command text must not become the selected draft snapshot.
    if context and not context.text:match("^%s*/") then ns.Composer.capture() end
    U.updateTarget()
    if text then
        U.source:SetText(text)
        if C.read(U.source, "GetText") ~= text then
            clearPreview("previewFailed")
            return
        end
        preview()
    end
end
