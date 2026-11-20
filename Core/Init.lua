local name, ns = ...
local frame = ns.Compat.frame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LOGOUT")
local loaded, enteredWorld
frame:SetScript("OnEvent", function(_, event, addon)
    if event == "ADDON_LOADED" and ns.Compat.public(addon) then
        if addon == name and not loaded then
            loaded = true
            ns.Database.load(); ns.Commands.register()
            local models = ns.UDPipeModels
            if models then
                ns.Engine.UDPipe.prepare(models.en)
                ns.Engine.UDPipe.prepare(models.uk)
            end
            if enteredWorld then ns.Incoming.start() end
            ns.UI.Settings.register()
        elseif loaded and addon == "Blizzard_ChatFrameBase" then
            ns.Commands.register()
            if enteredWorld then ns.Incoming.start() end
        elseif loaded and (addon == "Blizzard_Settings_Shared" or addon == "Blizzard_Settings") then
            ns.UI.Settings.register()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        enteredWorld = true
        frame:UnregisterEvent(event)
        if loaded then ns.Incoming.start() end
    elseif event == "PLAYER_LOGOUT" then
        ns.Translator.clearCache(); ns.Composer.clear()
    end
end)
