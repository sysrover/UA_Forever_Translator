local _, ns = ...
local DB = {}; ns.Database = DB
local C = ns.Compat
DB.events = {
    whisper = {"CHAT_MSG_WHISPER"},
    party = {"CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER"},
    raid = {"CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING"},
    guild = {"CHAT_MSG_GUILD", "CHAT_MSG_OFFICER"},
    say = {"CHAT_MSG_SAY", "CHAT_MSG_YELL"},
    channel = {"CHAT_MSG_CHANNEL"},
}
DB.eventGroups = {}
for group, events in pairs(DB.events) do
    for _, event in ipairs(events) do DB.eventGroups[event] = group end
end
local function validColor(r, g, b)
    return C.public(r, g, b) and type(r) == "number" and r >= 0 and r <= 1
        and type(g) == "number" and g >= 0 and g <= 1
        and type(b) == "number" and b >= 0 and b <= 1
end

function DB.load()
    local old = type(UA_Forever_TranslatorDB) == "table" and UA_Forever_TranslatorDB or {}
    -- The account-wide database holds settings. The optional journal is per character.
    local channels = type(old.channels) == "table" and old.channels or {}
    local clean = { schema = 1, enabled = old.enabled ~= false, own = old.own == true,
        showInUA = old.showInUA ~= false, showInMain = old.showInMain == true,
        logTranslations = old.logTranslations == true, neuralIncoming = old.neuralIncoming == true, channels = {} }
    local color = old.translationColor
    if type(color) == "table" and validColor(color.r, color.g, color.b) then
        clean.translationColor = {r=color.r, g=color.g, b=color.b}
    end
    for group in pairs(DB.events) do
        local value = channels[group]
        if type(value) ~= "boolean" then value = group ~= "say" and group ~= "channel" end
        clean.channels[group] = value
    end
    UA_Forever_TranslatorDB = clean
    DB.settings = clean
end

function DB.setTranslationColor(r, g, b)
    if r == nil and g == nil and b == nil then DB.settings.translationColor = nil
    elseif validColor(r, g, b) then DB.settings.translationColor = {r=r, g=g, b=b}
    else return end
    if ns.UI.Settings then ns.UI.Settings.refreshVisible() end
end

function DB.setNeuralIncoming(enabled)
    if enabled and not (ns.Data.translationStudent and ns.Engine.NeuralRuntime) then return false end
    DB.settings.neuralIncoming = enabled == true
    return true
end

function DB.changed()
    if ns.Incoming then ns.Incoming.configure() end
    if ns.UI.Settings then ns.UI.Settings.refreshVisible() end
end
