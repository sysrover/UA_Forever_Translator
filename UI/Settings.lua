local _, ns = ...
local S = {}; ns.UI.Settings = S
local C, L, DB = ns.Compat, ns.L, ns.Database

local function pickTranslationColor()
    if C.combat() then C.print(L.combat); return end
    local picker = ColorPickerFrame
    if not picker or type(picker.SetupColorPickerAndShow) ~= "function" or type(picker.GetColorRGB) ~= "function" then
        C.print(L.colorPickerUnavailable)
        return
    end
    local previous = DB.settings.translationColor
    local r, g, b = 1, 1, 1
    if previous then r, g, b = previous.r, previous.g, previous.b end
    picker:SetupColorPickerAndShow({
        r=r, g=g, b=b, hasOpacity=false,
        swatchFunc=function()
            local red, green, blue = picker:GetColorRGB()
            if not C.public(red, green, blue) then return end
            if not previous and red == r and green == g and blue == b then DB.setTranslationColor()
            else DB.setTranslationColor(red, green, blue) end
        end,
        cancelFunc=function()
            if previous then DB.setTranslationColor(previous.r, previous.g, previous.b)
            else DB.setTranslationColor() end
        end,
    })
end

local function refresh(page)
    if not page.controls or not DB.settings or not page:IsVisible() then return end
    for _, entry in ipairs(page.controls) do
        local checked = entry.getter()
        if (entry.control:GetChecked() == true) ~= checked then
            entry.control:SetChecked(checked)
        end
    end
    local color = DB.settings.translationColor
    if color then page.colorSwatch:SetColorTexture(color.r, color.g, color.b)
    else page.colorSwatch:SetColorTexture(1, 1, 1) end
    page.colorReset:SetEnabled(color ~= nil)
end

local function populate(page)
    if page.controls then return end
    page.controls = {}
    local title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    C.font(title)
    title:SetPoint("TOPLEFT", 22, -22)
    title:SetText(L.configTitle)

    local y = -58
    local function addCheck(text, getter, setter)
        local control = C.frame("CheckButton", page, "UICheckButtonTemplate")
        control:SetPoint("TOPLEFT", 20, y)
        control:SetSize(26, 26)
        local label = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        C.font(label)
        label:SetPoint("LEFT", control, "RIGHT", 5, 0)
        label:SetWidth(460)
        label:SetJustifyH("LEFT")
        label:SetText(text)
        control:SetScript("OnClick", function(self)
            setter(self:GetChecked() == true)
            DB.changed()
        end)
        page.controls[#page.controls + 1] = {control = control, getter = getter}
        y = y - 30
    end
    addCheck(L.enabledLabel, function() return DB.settings.enabled end, function(v) DB.settings.enabled = v end)
    addCheck(L.showInUA, function() return DB.settings.showInUA end, function(v) DB.settings.showInUA = v end)
    addCheck(L.showInMain, function() return DB.settings.showInMain end, function(v) DB.settings.showInMain = v end)
    addCheck(L.own, function() return DB.settings.own end, function(v) DB.settings.own = v end)
    addCheck(L.logTranslations, function() return DB.settings.logTranslations end,
        function(v) DB.settings.logTranslations = v end)
    for _, id in ipairs({"whisper", "party", "raid", "guild", "say", "channel"}) do
        local group = id
        addCheck(L.channels[group], function() return DB.settings.channels[group] end,
            function(v) DB.settings.channels[group] = v end)
    end

    local colorButton = C.frame("Button", page, "UIPanelButtonTemplate")
    colorButton:SetPoint("TOPLEFT", 20, y)
    colorButton:SetSize(164, 24)
    colorButton:SetText(L.translationColor)
    C.font(colorButton:GetFontString())
    colorButton:SetScript("OnClick", pickTranslationColor)

    local swatch = page:CreateTexture(nil, "ARTWORK")
    swatch:SetSize(18, 18)
    swatch:SetPoint("LEFT", colorButton, "RIGHT", 8, 0)
    page.colorSwatch = swatch

    local reset = C.frame("Button", page, "UIPanelButtonTemplate")
    reset:SetPoint("LEFT", swatch, "RIGHT", 12, 0)
    reset:SetSize(145, 24)
    reset:SetText(L.channelColor)
    C.font(reset:GetFontString())
    reset:SetScript("OnClick", function() DB.setTranslationColor() end)
    page.colorReset = reset

    y = y - 36
    local note = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    C.font(note)
    note:SetPoint("TOPLEFT", 25, y - 5)
    note:SetWidth(485)
    note:SetJustifyH("LEFT")
    note:SetText(L.translationDestination)
end

local function show(page)
    populate(page)
    refresh(page)
end

function S.refreshVisible()
    if S.page then refresh(S.page) end
    if S.fallback then refresh(S.fallback) end
end

function S.register()
    if S.categoryID then return true end
    local api = _G.Settings
    if not api or type(api.RegisterCanvasLayoutCategory) ~= "function"
        or type(api.RegisterAddOnCategory) ~= "function" then return false end

    if not S.page then
        local page = C.frame("Frame")
        page:Hide()
        page:SetScript("OnShow", show)
        page.OnRefresh = show
        S.page = page
    end
    if not S.category then
        local ok, category = pcall(api.RegisterCanvasLayoutCategory, S.page, L.title)
        if not ok or C.secret(category) or not category then return false end
        S.category = category
    end
    local id = C.read(S.category, "GetID")
    if type(id) ~= "number" or not pcall(api.RegisterAddOnCategory, S.category) then return false end
    S.categoryID = id
    return true
end

function S.open()
    if C.combat() then C.print(L.combat); return end
    if S.register() and type(_G.Settings.OpenToCategory) == "function"
        and pcall(_G.Settings.OpenToCategory, S.categoryID) then
        if S.fallback then S.fallback:Hide() end
        return
    end

    if not S.fallback then
        local page = C.frame("Frame", UIParent, "BackdropTemplate")
        page:Hide()
        page:SetSize(540, 510)
        page:SetPoint("CENTER")
        page:SetFrameStrata("DIALOG")
        page:EnableMouse(true)
        page:SetClampedToScreen(true)
        page:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 24,
            insets = {left = 5, right = 5, top = 5, bottom = 5},
        })
        local close = C.frame("Button", page, "UIPanelButtonTemplate")
        close:SetPoint("BOTTOMRIGHT", -20, 17)
        close:SetSize(110, 25)
        close:SetText(L.close)
        C.font(close:GetFontString())
        close:SetScript("OnClick", function() page:Hide() end)
        page:SetScript("OnShow", show)
        S.fallback = page
    end
    S.fallback:Show()
end
