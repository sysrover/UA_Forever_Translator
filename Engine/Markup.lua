local _, ns = ...
local M = {}; ns.Engine.Markup = M
local function endOfWord(text, first, stopAtPipe)
    local boundary = stopAtPipe and "[%s\194\226\227|]" or "[%s\194\226\227]"
    local cursor = first
    while true do
        local index = text:find(boundary, cursor)
        if not index then return #text end
        local byte = text:byte(index)
        if byte < 128 then return index - 1 end
        local width = byte == 194 and 2 or 3
        if ns.Engine.Normalize.isUnicodeSpace(text:sub(index, index + width - 1)) then return index - 1 end
        cursor = index + 1
    end
end

local addressStartsAfter = {}
for char in (" \t\n\v\f\r\"'(<=[,;"):gmatch(".") do
    addressStartsAfter[char:byte()] = true
end
local function bareAddressEnd(text, first)
    if first > 1 then
        local previous = text:byte(first - 1)
        if not addressStartsAfter[previous] then
            if previous < 128 then return nil end
            local unicodeSpace = ns.Engine.Normalize.isUnicodeSpace
            if not (unicodeSpace(text:sub(first - 2, first - 1))
                or first > 3 and unicodeSpace(text:sub(first - 3, first - 1))) then return nil end
        end
    end
    local _, slash, host = text:find("^([A-Za-z0-9][A-Za-z0-9.%-]*)/", first)
    if not host or not host:match("%.[A-Za-z][A-Za-z]+$") or host:find("..", 1, true)
        or host:find(".-", 1, true) or host:find("-.", 1, true) then return nil end
    -- Stop at WoW tags so the following link still has its own protected span.
    return endOfWord(text, slash + 1, true)
end
local function findTag(text, tag, first)
    local i = first
    while i < #text do
        local pipe = text:find("|", i, true)
        if not pipe then return nil end
        local pair = text:sub(pipe, pipe + 1)
        if pair == "||" then i = pipe + 2
        elseif pair == tag then return pipe
        else i = pipe + 1 end
    end
end

local function colorEnd(text, first)
    if text:sub(first, first + 1) ~= "|c" then return nil end
    if text:sub(first + 2, first + 9):match("^%x%x%x%x%x%x%x%x$") then return first + 9 end
    local nameEnd = text:find(":", first + 3, true)
    if nameEnd and nameEnd <= first + 35 and text:sub(first + 2, nameEnd - 1):match("^n[A-Z][A-Za-z0-9_]*$") then
        return nameEnd
    end
end

local function linkBounds(text)
    local first, last = 1, #text
    local color = colorEnd(text, first)
    if color and text:sub(-2) == "|r" then first, last = color + 1, last - 2 end
    if text:sub(first, first + 1) ~= "|H" then return nil end
    local label = findTag(text, "|h", first + 2)
    if not label or label <= first + 2 then return nil end
    local close = findTag(text, "|h", label + 2)
    if close and close + 1 == last then return first + 2, label - 1, label + 2, close - 1 end
end
function M.linkKind(text)
    local first, last = linkBounds(text)
    if first then return text:sub(first, last):match("^([%w_]+):") end
end
function M.itemId(text)
    local first, last = linkBounds(text)
    if not first then return nil end
    local payload = text:sub(first, last)
    return payload:match("^item:(%d+):") or payload:match("^item:(%d+)$")
end
function M.isLink(text, kind)
    local actual = M.linkKind(text)
    return actual ~= nil and (kind == nil or kind == actual)
end

function M.bracketLabel(text)
    local _, _, first, last = linkBounds(text)
    if not first then
        local color = colorEnd(text, 1)
        if not color or text:sub(-2) ~= "|r" then return nil end
        first, last = color + 1, #text - 2
    end
    return text:sub(first, last):match("^%[([^%[%]|%c]+)%]$")
end

local function angleEnd(text, first, heading)
    local name = heading and text:match("^<[ \t]*()", first) or first + 1
    if not text:sub(name, name):match("[%a\128-\255]") then return end
    local last = text:find(">", first + 1, true)
    if last and last - first <= 64 and not text:sub(first + 1, last - 1):find("[<>|\r\n]") then return last end
end

local guildLanguages = {
    EN=true, UK=true, UA=true, RU=true, DE=true, FR=true, ES=true, IT=true, PT=true, PL=true,
    CS=true, SK=true, HU=true, RO=true, TR=true, BG=true, SV=true, NO=true, ZH=true, KO=true, JA=true,
}

local function guildLanguageBounds(text)
    local first = text:match("^%s*()%[")
    if not first then return end
    local codes, after = text:match("^%[([A-Z/ ]+)%]()", first)
    if not codes then return end
    local guild = text:match("^%s*()<", after)
    if not guild or not angleEnd(text, guild, true) then return end

    local cursor = 1
    while cursor do
        local code, nextAt = codes:match("^ *([A-Z][A-Z]) *()", cursor)
        if not guildLanguages[code] then return end
        if nextAt > #codes then return first, after - 1, guild end
        cursor = codes:match("^/()", nextAt)
    end
end

function M.split(text)
    local segments, plain, i, length = {}, 1, 1, #text
    local languageFirst, languageLast, guild = guildLanguageBounds(text)
    local heading = guild or text:match("^%s*()<")
    local hasBareAddress = text:find("/", 1, true) and text:find("%.[A-Za-z][A-Za-z]+/")
    local function protect(last, questReference)
        if plain < i then segments[#segments + 1] = { first = plain, last = i - 1 } end
        segments[#segments + 1] = { first = i, last = last, protected = true, questReference = questReference }
        i, plain = last + 1, last + 1
    end
    while i <= length do
        local head = text:sub(i, i + 1)
        local last
        local questReference
        if i == languageFirst then
            last = languageLast
        elseif head == "|H" then
            local firstClose = findTag(text, "|h", i + 2)
            last = firstClose and findTag(text, "|h", firstClose + 2)
            last = last and last + 1 or length
        elseif head == "|c" and colorEnd(text, i) then
            last = findTag(text, "|r", colorEnd(text, i) + 1)
            last = last and last + 1 or length
        elseif head == "|T" or head == "|A" or head == "|K" then
            local close = head == "|T" and "|t" or (head == "|A" and "|a" or "|k")
            last = findTag(text, close, i + 2)
            last = last and last + 1 or length
        elseif head == "||" or head == "|r" or head == "|n" then last = i + 1
        elseif text:sub(i, i) == "|" then last = length
        elseif text:sub(i, i + 6):lower() == "http://"
            or text:sub(i, i + 7):lower() == "https://"
            or text:sub(i, i + 3):lower() == "www." then
            last = endOfWord(text, i, false)
        elseif text:sub(i, i) == "@" and text:sub(i + 1, i + 1):match("[%w_\128-\255]") then
            -- A name can contain a token that also looks like a join word.
            last = endOfWord(text, i + 1, true)
        elseif text:sub(i, i) == "{" then
            local close = text:find("}", i + 1, true)
            if close then last = close end
        elseif head == "[[" then
            local reference = text:sub(i, i + 255):match("^%[%[%d%d?%d?%] +[^%[%]|%c]+ %(%d+%)%]")
            if reference then last, questReference = i + #reference - 1, true end
        elseif text:sub(i, i) == "<" then
            last = angleEnd(text, i, i == heading)
        elseif hasBareAddress then
            last = bareAddressEnd(text, i)
        end
        if last then protect(last, questReference) else i = i + 1 end
    end
    if plain <= length then segments[#segments + 1] = { first = plain, last = length } end
    return segments
end
