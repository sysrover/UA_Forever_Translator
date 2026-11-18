local _, ns = ...
local N = {}; ns.Engine.Normalize = N
local upper = {"А","Б","В","Г","Ґ","Д","Е","Є","Ж","З","И","І","Ї","Й","К","Л","М","Н","О","П","Р","С","Т","У","Ф","Х","Ц","Ч","Ш","Щ","Ь","Ю","Я"}
local lower = {"а","б","в","г","ґ","д","е","є","ж","з","и","і","ї","й","к","л","м","н","о","п","р","с","т","у","ф","х","ц","ч","ш","щ","ь","ю","я"}
local case, uppercase = {}, {}
for i, value in ipairs(upper) do
    case[value], uppercase[lower[i]] = lower[i], value
end
for byte = 65, 90 do
    local capital, small = string.char(byte), string.char(byte + 32)
    case[capital], uppercase[small] = small, capital
end
local unicodeSpaces = { ["\194\160"] = true, ["\226\128\175"] = true, ["\227\128\128"] = true }
for byte = 128, 138 do unicodeSpaces["\226\128" .. string.char(byte)] = true end
function N.isUnicodeSpace(char)
    return unicodeSpaces[char] == true
end
local function normalizeSpaces(text)
    if text:find("[\194\226\227]") then
        text = text:gsub("\194\160", " "):gsub("\226\128[\128-\138\175]", " "):gsub("\227\128\128", " ")
    end
    return text
end
function N.word(text)
    text = text:gsub("’", "'"):gsub("ʼ", "'"):gsub("‘", "'")
    -- string.lower is locale-sensitive and may change individual UTF-8 bytes.
    return (text:gsub("[A-Z]", case):gsub("[\192-\223][\128-\191]", case))
end
function N.upperStart(text)
    local first = text:match("^[a-z]") or text:match("^[\192-\223][\128-\191]")
    local capital = first and uppercase[first]
    return capital and capital .. text:sub(#first + 1) or text
end
function N.key(text)
    return (N.word(normalizeSpaces(text)):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
        :gsub("%s*[.!?]+$", ""))
end
