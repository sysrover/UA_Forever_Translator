local _, ns = ...
local S = {}; ns.UI.Settings = S
local C, L, DB = ns.Compat, ns.L, ns.Database
function S.open()
    if C.combat() then C.print(L.combat); return end
    if not S.frame then
        local f = C.frame("Frame", UIParent, "BackdropTemplate")
        f:SetSize(540, 430); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG"); f:EnableMouse(true)
        f:SetClampedToScreen(true)
        f:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",tile=true,tileSize=32,edgeSize=24,insets={left=5,right=5,top=5,bottom=5}})
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        C.font(title); title:SetPoint("TOPLEFT", 22, -22); title:SetText(L.configTitle)
        S.controls = {}
        local y = -58
        local function check(key, text, getter, setter)
            local control = C.frame("CheckButton", f, "UICheckButtonTemplate")
            control:SetPoint("TOPLEFT", 20, y); control:SetSize(26, 26)
            local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            C.font(label); label:SetPoint("LEFT", control, "RIGHT", 5, 0); label:SetWidth(460); label:SetJustifyH("LEFT"); label:SetText(text)
            control:SetScript("OnClick", function(self) setter(self:GetChecked() == true); DB.changed() end)
            S.controls[#S.controls + 1] = {control = control, getter = getter}
            y = y - 30
        end
        check("enabled", L.enabledLabel, function() return DB.settings.enabled end, function(v) DB.settings.enabled = v end)
        check("own", L.own, function() return DB.settings.own end, function(v) DB.settings.own = v end)
        check("annotation", L.annotation, function() return DB.settings.display == "annotation" end,
            function(v) DB.settings.display = v and "annotation" or "line" end)
        for _, id in ipairs({"whisper","party","raid","guild","say","channel"}) do
            local group = id
            check(group, L.channels[group], function() return DB.settings.channels[group] end,
                function(v) DB.settings.channels[group] = v end)
        end
        local note = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        C.font(note); note:SetPoint("TOPLEFT", 25, y - 5); note:SetWidth(485); note:SetJustifyH("LEFT"); note:SetText(L.originalPreserved)
        local close = C.frame("Button", f, "UIPanelButtonTemplate")
        close:SetPoint("BOTTOMRIGHT", -20, 17); close:SetSize(110, 25); close:SetText(L.close)
        C.font(close:GetFontString()); close:SetScript("OnClick", function() f:Hide() end)
        S.frame = f
    end
    for _, entry in ipairs(S.controls) do entry.control:SetChecked(entry.getter()) end
    S.frame:Show()
end
