local _, ns = ...
-- Indexed numeric spans for EN-to-UK chat inference.
local M = {}; ns.Engine.NeuralNumbers = M
local slots, classes = {}, {}
for i = 1, 4 do slots[i] = string.char(238, 132, 127 + i) end
for i = 1, 3 do classes[i] = string.char(238, 132, 131 + i) end
M.slots, M.classes = slots, classes

local function isDigit(ch) return ch:match("^[0-9]$") ~= nil end
local function embedded(text, neighbor, outside)
    if neighbor < 1 or neighbor > #text then return false end
    local ch = text:sub(neighbor, neighbor)
    return ch:match("[A-Za-z_+%-]") ~= nil
        or (ch:match("[.,:/]") ~= nil and outside >= 1 and isDigit(text:sub(outside, outside)))
end

local weaponNouns = {weapon=true, axe=true, mace=true, sword=true, hammer=true, staff=true, polearm=true}

local function handedSuffix(text, first, last)
    local suffix = text:match("^%-?([A-Za-z]+)%f[^%w_]", last)
    if not suffix then return end
    local key = suffix:lower()
    local hyphen = text:sub(last, last) == "-"
    local finish = last + #suffix + (hyphen and 1 or 0)
    if key == "handed" then return finish, "-handed" end
    if key ~= "hand" and (key ~= "h" or hyphen) then return end
    local nextWord = text:match("^%s+([A-Za-z]+)", finish)
    if nextWord then
        local noun = nextWord:lower():gsub("s$", "")
        if weaponNouns[noun] then return finish, "-handed" end
    end
    -- Enchanting lists can omit the weapon noun after a signed stat.
    if key == "h" and not nextWord and text:sub(1, first - 1):match("%+%d+%s*[A-Za-z]+%s*$") then
        return finish, "-handed weapon"
    end
end

local function numericExpression(text, first, last)
    local before = text:sub(first - 1, first - 1)
    local signed = first > 1 and (before == "+" or before == "-")
    local amount = text:sub(first, last - 1)
    -- A separate chat quantity can put the multiplication marker on either side.
    if first > 1 and before == "x" and not embedded(text, first - 2, first - 3)
        and not embedded(text, last, last + 1) then
        return {first=first-1,last=last,value=amount}
    end
    local start = signed and first - 1 or first
    if embedded(text, start - 1, start - 2) then return end
    if not signed then
        if text:match("^x%f[^%w_]", last) and not embedded(text, last + 1, last + 2) then
            return {first=first,last=last+1,value=amount}
        end
        if amount == "1" or amount == "2" then
            local finish, suffix = handedSuffix(text, first, last)
            if finish then return {first=first,last=finish,value=amount,suffix=suffix} end
        end
    end
    local separator, endAmount = text:match("^([vV:.,/-])(%d+)", last)
    if not separator then
        separator, endAmount = text:match("^(–)(%d+)", last)
    end
    if separator then
        last = last + #separator + #endAmount
        if embedded(text, last, last + 1) or text:match("^–%d", last) then return end
        -- A range uses the last number for agreement.
        amount = (separator == "-" or separator == "–") and endAmount or ""
    elseif not signed or (not text:match("^[A-Za-z]", last) and embedded(text, last, last + 1)) then
        return
    end
    return {first=start,last=last,value=text:sub(start,last-1),amount=amount}
end

function M.ranges(text, prices)
    local spans, covered = {}, 0
    for first, last in text:gmatch("()[0-9]+()") do
        if first >= covered then
            local span = prices and prices[first]
            if not span then
                if embedded(text, first - 1, first - 2) or embedded(text, last, last + 1)
                    or text:match("^–%d", last) then
                    span = numericExpression(text, first, last)
                    if not span then return nil, "unsupported-number" end
                else
                    span = {first=first,last=last,value=text:sub(first,last-1)}
                end
            end
            if #spans == #slots then return nil, "number-limit" end
            spans[#spans + 1], covered = span, span.last
        end
    end
    return spans
end

local function digitClass(value)
    local last, tens = value:sub(-1), value:sub(-2, -2)
    if tens ~= "1" then
        if last == "1" then return 1 end
        if last == "2" or last == "3" or last == "4" then return 2 end
    end
    return 3
end

local function hasMarker(text)
    return text:find("\238\132[\128-\135]") ~= nil
end
M.hasMarker = hasMarker

local function render(text, ranges, replacement)
    local out, cursor = {}, 1
    for i, span in ipairs(ranges) do
        out[#out + 1] = text:sub(cursor, span.first - 1)
        out[#out + 1] = replacement(i, span.value, span)
        cursor = span.last
    end
    out[#out + 1] = text:sub(cursor)
    return table.concat(out)
end

local priceMarker = "\238\132\179"
local priceCue = {buy=true, sell=true, buying=true, selling=true, pay=true, paid=true, charge=true,
    cost=true, costs=true, tip=true, tips=true, price=true, wtb=true, wts=true, mats=true, gold=true,
    silver=true, copper=true, cheap=true, cheaper=true, enchant=true, enchanting=true, discount=true}

local priceSuffix = {['for']=true, ['if']=true, ['or']=true, ['and']=true, ['then']=true, but=true,
    at=true, each=true, per=true, total=true, tip=true, tips=true, before=true, after=true,
    from=true, later=true, instead=true, today=true, yesterday=true, only=true, near=true, ['in']=true}

function M.prices(text, opener)
    if not text:match("%d%s*[GSCgsc]%f[^%w_]") then return nil end
    local e = ns.Engine
    local tokens = e.Tokenizer.scan(text)
    if not tokens then return nil end
    local context = priceCue[opener]
    if not context then
        for _, token in ipairs(tokens) do
            if not token.protected and priceCue[token.key] then context = true; break end
        end
    end
    if not context then return nil end
    local ranges, document = nil, {text=text,tokens=tokens}
    for i, token in ipairs(tokens) do
        if not token.protected and token.key:match("^%d") then
            local value, ending = e.Grammar.moneyAt(document,i,#tokens)
            local following = ending and tokens[ending]
            local terminal = not following or following.protected or following.key:match("^%p$") or priceSuffix[following.key]
            if value and terminal and value.sourceRaw:match("^%d+%s*[GSCgsc]$") and #value.amount <= 8 then
                ranges = ranges or {}
                ranges[token.first] = {first=token.first,last=tokens[ending-1].last+1,value=value.amount,
                    price=e.Grammar.moneyText(value),unit=value.unit,sourceRaw=value.sourceRaw}
            end
        end
    end
    return ranges
end

function M.mask(text, prices)
    if hasMarker(text) or text:find(priceMarker, 1, true) then return nil, "source-marker" end
    if not text:find("[0-9]") then return text end
    local spans, reason = M.ranges(text, prices)
    if not spans then return nil, reason end
    local values = {}
    local masked = render(text, spans, function(i, value, span)
        values[i] = span.price or value
        return slots[i] .. classes[digitClass(span.amount or value)] .. (span.price and priceMarker or span.suffix or "")
    end)
    return masked, values
end

function M.target(text, values)
    if hasMarker(text) then return nil end
    local spans, covered = {}, 0
    for first, last in text:gmatch("()[0-9]+()") do
        if first >= covered then
            local value = values[#spans + 1]
            if not value then return nil end
            local start = first - value:find("%d") + 1
            local finish = start + #value
            if start < 1 or start < covered or finish < last or text:sub(start, finish - 1) ~= value then return nil end
            if value:find(" ", 1, true) then
                local following = text:sub(finish, finish + 1)
                if following:match("^[A-Za-z_]") or following:match("^[\208\209][\128-\191]") then return nil end
            end
            spans[#spans + 1], covered = {first=start,last=finish}, finish
        end
    end
    if #spans ~= #values then return nil end
    return render(text, spans, function(i) return slots[i] end)
end

function M.restore(text, values)
    if text:find("[0-9]") then return nil, "generated-number" end
    local cursor = 1
    for i, value in ipairs(values) do
        local first, last = text:find(slots[i], cursor, true)
        if not first then return nil, "number-slot-count" end
        if value:match("^[+-]") and text:sub(first - 1, first - 1):match("^[+-]$") then
            return nil, "number-sign"
        end
        text = text:sub(1, first - 1) .. value .. text:sub(last + 1)
        cursor = first + #value
    end
    if hasMarker(text) then return nil, "unexpected-number-slot" end
    return text
end
