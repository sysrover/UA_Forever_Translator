local _, ns = ...
local DB = {}; ns.Database = DB
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
function DB.load()
    local old = type(UA_Forever_TranslatorDB) == "table" and UA_Forever_TranslatorDB or {}
    -- The account-wide database holds settings. The optional journal is per character.
    local channels = type(old.channels) == "table" and old.channels or {}
    local clean = { schema = 1, enabled = old.enabled ~= false, own = old.own == true,
        logTranslations = old.logTranslations == true, channels = {} }
    for group in pairs(DB.events) do
        local value = channels[group]
        if type(value) ~= "boolean" then value = group ~= "say" and group ~= "channel" end
        clean.channels[group] = value
    end
    UA_Forever_TranslatorDB = clean
    DB.settings, DB.revision = clean, 1
end
function DB.changed()
    DB.revision = DB.revision + 1
    if ns.Translator then ns.Translator.clearCache() end
    if ns.Incoming then ns.Incoming.configure() end
    if ns.UI.Settings then ns.UI.Settings.refreshVisible() end
end
