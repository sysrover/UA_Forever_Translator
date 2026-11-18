local _, ns = ...
local Log = {}; ns.ChatLog = Log
local maxEntries = 500
local journal

local function openJournal()
    local saved = UA_Forever_TranslatorLog
    if type(saved) == "table" and saved.schema == 1 and type(saved.entries) == "table" then
        local nextIndex = saved.nextIndex
        if type(nextIndex) == "number" and nextIndex >= 1 and nextIndex <= maxEntries and nextIndex % 1 == 0 then
            return saved
        end
    end

    saved = { schema = 1, nextIndex = 1, entries = {} }
    UA_Forever_TranslatorLog = saved
    return saved
end

function Log.record(event, original, result)
    local settings = ns.Database.settings
    if not settings or not settings.logTranslations then return end
    local translation, mode = result.text, result.mode
    if not ns.Compat.public(event, original, translation, mode) then return end
    if not journal then journal = openJournal() end

    local index = journal.nextIndex
    journal.entries[index] = {
        event = event,
        original = original,
        translation = translation,
        mode = mode,
    }
    journal.nextIndex = index % maxEntries + 1
end
