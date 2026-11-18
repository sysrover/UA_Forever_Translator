local name, ns = ...
local frame = ns.Compat.frame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGOUT")
local loaded = false
frame:SetScript("OnEvent", function(_, event, addon)
    if event == "ADDON_LOADED" and ns.Compat.public(addon) then
        if addon == name and not loaded then
            loaded = true
            ns.Database.load(); ns.Commands.register()
            if not ns.Incoming.configure() then ns.Compat.print(ns.L.unavailable) end
            ns.UI.Settings.register()
        elseif loaded and addon == "Blizzard_ChatFrameBase" then
            ns.Commands.register(); ns.Incoming.configure()
        elseif loaded and (addon == "Blizzard_Settings_Shared" or addon == "Blizzard_Settings") then
            ns.UI.Settings.register()
        end
    elseif event == "PLAYER_LOGOUT" then
        ns.Translator.clearCache(); ns.Composer.clear()
    end
end)
