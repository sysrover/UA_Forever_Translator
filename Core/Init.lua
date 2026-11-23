local name, ns = ...
local frame = ns.Compat.frame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LOGOUT")
local loaded, enteredWorld

local function prepareParsers()
    local models = ns.UDPipeModels
    if not models then return end
    local prepare = ns.Engine.UDPipe.prepare
    if not C_Timer or type(C_Timer.After) ~= "function" or type(debugprofilestop) ~= "function" then
        prepare(models.en)
        prepare(models.uk)
        return
    end

    local deadline
    local function checkpoint()
        if debugprofilestop() >= deadline then coroutine.yield() end
    end
    local warmup = coroutine.create(function()
        prepare(models.en, checkpoint)
        prepare(models.uk, checkpoint)
    end)
    local function resumeWarmup()
        if not ns.Incoming.hasPendingWork() then
            deadline = debugprofilestop() + 3
            local ok, reason = coroutine.resume(warmup)
            if not ok then error(reason) end
        end
        if coroutine.status(warmup) ~= "dead" then C_Timer.After(0, resumeWarmup) end
    end
    C_Timer.After(0, resumeWarmup)
end
frame:SetScript("OnEvent", function(_, event, addon)
    if event == "ADDON_LOADED" and ns.Compat.public(addon) then
        if addon == name and not loaded then
            loaded = true
            ns.Database.load(); ns.Commands.register()
            prepareParsers()
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
