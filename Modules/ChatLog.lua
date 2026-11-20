local _, ns = ...
local Log = {}; ns.ChatLog = Log
local legacyCapacity = 500 -- Used only to migrate the schema-1 ring.
local journal

local function openJournal()
    local saved = UA_Forever_TranslatorLog
    if type(saved) == "table" and type(saved.entries) == "table" then
        if saved.schema == 2 then
            saved.nextIndex = #saved.entries + 1
            return saved
        elseif saved.schema == 1 then
            local entries, length, first = {}, #saved.entries, 1
            local nextIndex = saved.nextIndex
            if length == legacyCapacity and type(nextIndex) == "number" and nextIndex % 1 == 0
                and nextIndex >= 1 and nextIndex <= legacyCapacity then first = nextIndex end
            for offset = 0, length - 1 do
                local index = (first + offset - 1) % legacyCapacity + 1
                local entry = saved.entries[index]
                if type(entry) == "table" then
                    entry.direction = entry.direction or "en-uk"
                    entries[#entries + 1] = entry
                end
            end
            saved = {schema=2, entries=entries, nextIndex=#entries + 1}
            UA_Forever_TranslatorLog = saved
            return saved
        end
    end

    saved = { schema = 2, nextIndex = 1, entries = {} }
    UA_Forever_TranslatorLog = saved
    return saved
end

function Log.now()
    if type(GetTimePreciseSec) == "function" then return GetTimePreciseSec() * 1000 end
    if type(debugprofilestop) == "function" then return debugprofilestop() end
end

function Log.duration(startedAt)
    if not startedAt then return end
    local finishedAt = Log.now()
    if finishedAt and finishedAt >= startedAt then return finishedAt - startedAt end
end

local function validDuration(value)
    if ns.Compat.public(value) and type(value) == "number" and value >= 0 and value < math.huge then return value end
end

function Log.record(event, original, result, direction, translationMs, elapsedMs)
    local settings = ns.Database.settings
    if not settings or not settings.logTranslations then return end
    if not ns.Compat.public(event, original, result, direction) or type(result) ~= "table" then return end
    local translation, mode = result.text, result.mode
    if not ns.Compat.public(event, original, translation, mode) then return end
    direction = direction or "en-uk"
    if direction ~= "en-uk" and direction ~= "uk-en" then return end
    if type(event) ~= "string" or type(original) ~= "string" or type(translation) ~= "string" then return end
    if mode ~= "exact" and mode ~= "template" and mode ~= "partial" then return end
    if not journal then journal = openJournal() end

    local index = journal.nextIndex
    journal.entries[index] = {
        event = event,
        original = original,
        translation = translation,
        mode = mode,
        direction = direction,
        translationMs = validDuration(translationMs),
        elapsedMs = validDuration(elapsedMs),
    }
    journal.nextIndex = index + 1
end
