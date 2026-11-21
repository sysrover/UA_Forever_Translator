local _, ns = ...
local T = {}; ns.Engine.Tokenizer = T
local normalize = ns.Engine.Normalize
local punctuation = {
    ["—"]=true, ["–"]=true, ["…"]=true, ["«"]=true, ["»"]=true, ["→"]=true, ["›"]=true,
    ["“"]=true, ["”"]=true, ["„"]=true, ["‐"]=true, ["‑"]=true,
    ["\226\128\141"]=true, ["\239\184\143"]=true,
}
local apostrophes = { ["’"]=true, ["‘"]=true, ["ʼ"]=true }
local function readUnit(text, index, limit)
    local byte = text:byte(index)
    if byte < 128 then
        if byte == 32 or (byte >= 9 and byte <= 13) then return index, "space" end
        if byte == 39 then return index, "apostrophe" end
        if byte == 95 or (byte >= 48 and byte <= 57) or (byte >= 65 and byte <= 90)
            or (byte >= 97 and byte <= 122) then return index, "word" end
        return index, "symbol"
    end
    local length
    if byte >= 194 and byte <= 223 then length = 2
    elseif byte >= 224 and byte <= 239 then length = 3
    elseif byte >= 240 and byte <= 244 then length = 4
    else return index, "symbol" end
    local last = index + length - 1
    if last > limit then return index, "symbol" end
    for pos = index + 1, last do
        local continuation = text:byte(pos)
        if continuation < 128 or continuation > 191 then return index, "symbol" end
    end
    if length == 4 then return last, "symbol" end
    local char = text:sub(index, last)
    if normalize.isUnicodeSpace(char) then return last, "space" end
    if apostrophes[char] then return last, "apostrophe" end
    if punctuation[char] then return last, "symbol" end
    -- The commonly used BMP pictographs span U+2600 through U+27BF.
    if byte == 226 then
        local second = text:byte(index + 1)
        if second >= 152 and second <= 158 then return last, "symbol" end
    end
    return last, "word"
end
local function spacedContraction(text, first, apostropheEnd, spaceEnd, limit, spellings)
    local start = spaceEnd + 1
    local ending, kind
    while start <= limit do
        ending, kind = readUnit(text, start, limit)
        if kind ~= "space" then break end
        start = ending + 1
    end
    if kind ~= "word" or ending ~= start then return end
    while ending < limit do
        local nextEnd, nextKind = readUnit(text, ending + 1, limit)
        if nextKind == "apostrophe" then return end
        if nextKind ~= "word" then break end
        if nextEnd - start > 1 then return end
        ending = nextEnd
    end
    local modelForm = text:sub(first, apostropheEnd) .. text:sub(start, ending)
    local key = normalize.word(modelForm)
    if spellings[key] then return ending, key, modelForm end
end

function T.scan(text, englishContractions)
    local tokens = {}
    for _, segment in ipairs(ns.Engine.Markup.split(text)) do
        if segment.protected then
            tokens[#tokens + 1] = { first = segment.first, last = segment.last, key = "<protected>", protected = true,
                linkKind = ns.Engine.Markup.linkKind(text:sub(segment.first, segment.last)),
                questReference = segment.questReference }
            if #tokens > ns.Limits.tokens then return nil end
        else
            local i = segment.first
            while i <= segment.last do
                local last, kind = readUnit(text, i, segment.last)
                if kind == "space" then i = last + 1
                else
                    local first, key, modelForm = i
                    if kind == "word" then
                        while last < segment.last do
                            local nextLast, nextKind = readUnit(text, last + 1, segment.last)
                            if nextKind == "apostrophe" and nextLast < segment.last then
                                local apostropheEnd = nextLast
                                nextLast, nextKind = readUnit(text, nextLast + 1, segment.last)
                                if nextKind == "space" and englishContractions then
                                    local ending
                                    ending, key, modelForm = spacedContraction(text, first, apostropheEnd,
                                        nextLast, segment.last, englishContractions)
                                    if ending then last = ending end
                                    break
                                end
                            end
                            if nextKind ~= "word" then break end
                            last = nextLast
                        end
                    end
                    key = key or normalize.word(text:sub(first, last))
                    local count, suffix = key:match("^lf(%d+)(m?)$")
                    if count and #count <= 3 then
                        tokens[#tokens + 1] = {first = first, last = first + 1, key = "lf"}
                        tokens[#tokens + 1] = {first = first + 2, last = last - #suffix, key = count}
                        if suffix == "m" then tokens[#tokens + 1] = {first = last, last = last, key = suffix} end
                    else
                        tokens[#tokens + 1] = {first = first, last = last, key = key, modelForm = modelForm}
                    end
                    i = last + 1
                end
                if #tokens > ns.Limits.tokens then return nil end
            end
        end
    end
    return tokens
end
