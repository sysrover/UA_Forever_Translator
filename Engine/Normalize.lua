local _, ns = ...
local N = {}; ns.Engine.Normalize = N
N.englishCopulas = {is=true, are=true, was=true, were=true, be=true}
-- Chat spellings provide an auxiliary reading alongside the original word.
N.englishNegativeAliases = {
    dont="don't", doesnt="doesn't", didnt="didn't",
    cant="can't", couldnt="couldn't", shouldnt="shouldn't", wouldnt="wouldn't", wont="won't",
    isnt="isn't", arent="aren't", wasnt="wasn't", werent="weren't",
    havent="haven't", hasnt="hasn't", hadnt="hadn't", shouldntve="shouldn't've",
}
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
local function questionMarks(terminal)
    if terminal and terminal:find("?", 1, true) then
        return terminal:match("^%?+$") and "?" or terminal
    end
end

function N.questionEnd(text)
    return questionMarks(normalizeSpaces(text):match("([.!?]+)%s*$"))
end

function N.tokenQuestion(text, tokens, first, last)
    local ending = tokens[last]
    if not ending or last < first or not ending.key:match("^[.!?]$") then return end
    local start, question = last, ending.key == "?"
    while start > first do
        local previous = tokens[start - 1]
        if previous.last + 1 ~= tokens[start].first or not previous.key:match("^[.!?]$") then break end
        question = question or previous.key == "?"
        start = start - 1
    end
    if question then return questionMarks(text:sub(tokens[start].first, ending.last)) end
end

function N.endAsQuestion(text, terminal)
    local body = text:gsub("%s+$", ""):gsub("…$", ""):gsub("[.!?]+$", "")
    return body .. terminal
end

function N.key(text)
    return (N.word(normalizeSpaces(text)):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
        :gsub("%s*[.!?]+$", ""))
end
