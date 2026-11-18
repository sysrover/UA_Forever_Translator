local _, ns = ...
local M = {}; ns.Engine.Markup = M
local function endOfWord(text, first, mention)
    local boundary = mention and "[%s\194\226\227|]" or "[%s\194\226\227]"
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

function M.isLink(text)
    local first, last = 1, #text
    if text:match("^|c%x%x%x%x%x%x%x%x") and text:sub(-2) == "|r" then
        first, last = 11, last - 2
    end
    if text:sub(first, first + 1) ~= "|H" then return false end
    local label = findTag(text, "|h", first + 2)
    if not label or label <= first + 2 then return false end
    local close = findTag(text, "|h", label + 2)
    return close ~= nil and close + 1 == last
end
function M.split(text)
    local segments, plain, i, length = {}, 1, 1, #text
    local function protect(last)
        if plain < i then segments[#segments + 1] = { first = plain, last = i - 1 } end
        segments[#segments + 1] = { first = i, last = last, protected = true }
        i, plain = last + 1, last + 1
    end
    while i <= length do
        local head = text:sub(i, i + 1)
        local last
        if head == "|H" then
            local firstClose = findTag(text, "|h", i + 2)
            last = firstClose and findTag(text, "|h", firstClose + 2)
            last = last and last + 1 or length
        elseif head == "|c" and text:sub(i + 2, i + 9):match("^%x%x%x%x%x%x%x%x$") then
            last = findTag(text, "|r", i + 10)
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
        end
        if last then protect(last) else i = i + 1 end
    end
    if plain <= length then segments[#segments + 1] = { first = plain, last = length } end
    return segments
end
