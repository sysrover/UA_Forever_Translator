local _, ns = ...
local G = {}; ns.Engine.Grammar = G
local moneyForms = {
    g = {"золоту монету", "золоті монети", "золотих монет", "золотої монети", "золота монета"},
    s = {"срібну монету", "срібні монети", "срібних монет", "срібної монети", "срібна монета"},
    c = {"мідну монету", "мідні монети", "мідних монет", "мідної монети", "мідна монета"},
}
local currency = {}
for name, unit in pairs({gold="g", silver="s", copper="c"}) do
    currency[name], currency[name .. "s"] = unit, unit
    currency[name .. " coin"], currency[name .. " coins"] = unit, unit
    for _, form in ipairs(moneyForms[unit]) do currency[form] = unit end
end

function G.moneyAt(document, first, limit)
    local tokens = document.tokens
    local opening = tokens[first]
    if first > limit or not opening or opening.protected or not opening.key:match("^%d") then return nil end
    for last = math.min(limit, first + 4), first, -1 do
        local raw = document.text:sub(opening.first, tokens[last].last)
        local normalized = ns.Engine.Normalize.word(raw)
        local amount, unit = normalized:match("^(%d+[%.,]?%d*)%s*([gsc])$")
        if not amount then
            local number, name = ns.Engine.Normalize.key(raw):match("^(%d+[%.,]?%d*)%s+(.+)$")
            if number and currency[name] then amount, unit = number, currency[name] end
        end
        if amount then return {raw=amount .. unit, sourceRaw=raw, amount=amount, unit=unit}, last + 1 end
    end
end

local denominations = {g=3, s=2, c=1}
local coinJoins = {["and"]=true, ["і"]=true, ["й"]=true, ["та"]=true, [","]=true}

function G.packedMoney(token)
    if not token or token.protected or not token.key:match("^%d+[gsc]%d") then return end
    local parts, cursor, previous = {}, 1, 4
    while cursor <= #token.key do
        local amount, unit, after = token.key:sub(cursor):match("^(%d+)([gsc])()")
        if not amount or denominations[unit] >= previous then return end
        parts[#parts + 1] = {raw=amount .. unit, amount=amount, unit=unit}
        cursor, previous = cursor + after - 1, denominations[unit]
    end
    return parts
end

function G.offerPriceAt(document, first, limit)
    if first > limit then return end
    local tokens = document.tokens
    local parts = G.packedMoney(tokens[first])
    local after = first + 1
    if not parts then
        local part
        part, after = G.moneyAt(document, first, limit)
        if not part then return end
        parts = {part}
    end
    while after <= limit and #parts < 3 do
        local token = tokens[after]
        local following = not token.protected and coinJoins[token.key] and after + 1 or after
        local part, ending = G.moneyAt(document, following, limit)
        if not part or denominations[part.unit] >= denominations[parts[#parts].unit] then break end
        parts[#parts + 1], after = part, ending
    end
    return parts, after
end

local priceBases = {
    each="unit", ["per item"]="unit", ["a piece"]="unit", ["за штуку"]="unit", ["за одиницю"]="unit",
    ["a bottle"]="bottle", ["per bottle"]="bottle", ["за пляшку"]="bottle",
    ["per enchant"]="enchant", ["per enchantment"]="enchant", ["за зачарування"]="enchant",
    total="total", ["in total"]="total", ["загалом"]="total", ["усього"]="total", ["всього"]="total",
}

function G.priceBasisAt(document, first, limit)
    if first > limit then return nil, first end
    local tokens = document.tokens
    local head = tokens[first].key
    if head == "each" and first < limit and ns.Linguistics and tokens[first + 1].key:match("^%a+$") then
        local grammar = ns.Linguistics.grammar
        if grammar.index.en.calendarDays[tokens[first + 1].key] then return nil, first end
        local rows, last = ns.Engine.Lexicon.functional(document, "adverbs", first, limit)
        if last and last > first then
            for _, row in ipairs(rows) do
                if grammar.adverbs[row].recurring then return nil, first end
            end
        end
    end
    if priceBases[head] then return priceBases[head], first + 1 end
    if first < limit then
        local basis = priceBases[head .. " " .. tokens[first + 1].key]
        if basis then return basis, first + 2 end
    end
    return nil, first
end

function G.priceBasisText(basis, english)
    if basis == "bottle" then return english and "a bottle" or "за пляшку" end
    if basis == "enchant" then return english and "per enchant" or "за зачарування" end
    if basis == "total" then return english and "total" or "загалом" end
    return english and "each" or "за штуку"
end

function G.moneyText(slot, nominative)
    local amount, forms = slot.amount, moneyForms[slot.unit]
    if not amount or not forms then return slot.raw end
    local numeric = tonumber((amount:gsub(",", ".")))
    if not numeric then return slot.raw end
    local last, pair = numeric % 10, numeric % 100
    local form = 3
    if numeric % 1 ~= 0 then form = 4
    elseif last == 1 and pair ~= 11 then form = nominative and 5 or 1
    elseif last >= 2 and last <= 4 and (pair < 12 or pair > 14) then form = 2 end
    return amount .. " " .. forms[form]
end

function G.offerPriceText(parts, english)
    local values = {}
    for i, part in ipairs(parts) do values[i] = english and part.raw or G.moneyText(part) end
    if english then return table.concat(values, " ") end
    if #values < 2 then return values[1] end
    return table.concat(values, ", ", 1, #values - 1) .. " і " .. values[#values]
end

function G.numberForm(number)
    local n = tonumber(number)
    if not n then return "genitivePlural" end
    local last, pair = n % 10, n % 100
    if last == 1 and pair ~= 11 then return "genitiveSingular" end
    if last >= 2 and last <= 4 and (pair < 12 or pair > 14) then return "genitivePlural" end
    return "genitivePlural"
end
function G.roleQuantity(slot, term, accusative)
    if not slot.spelled then return slot.raw end
    local number, features = tonumber(slot.raw), term.features or {}
    local gender, animacy = features.gender or "masculine", features.animacy
    if number == 1 then
        return ns.Engine.Phrases.one(gender, accusative and "accusative" or "nominative", animacy)
    end
    local grammar = ns.Linguistics.grammar
    local forms = grammar.cardinalUk
    if accusative and animacy == "animate" and number >= 2 and number <= 4 then
        forms = grammar.cardinalUkByCase.genitive
    elseif number == 2 then
        return gender == "feminine" and "дві" or "два"
    end
    for word, cardinal in pairs(forms) do
        if cardinal == number then return word end
    end
    return slot.raw
end

function G.render(template, slots, direction)
    local failed = false
    local output = template:gsub("{([%w_]+):?([%w_]*)}", function(name, form)
        local slot = slots[name]
        if not slot then failed = true; return "" end
        if slot.term then
            if direction == "uk-en" then
                if form == "address" then return slot.term.englishAddress or slot.term.en end
                if form == "activity" then return slot.term.englishActivity or slot.term.en end
                local count = slots.count and tonumber(slots.count.raw)
                if (slot.plural or (count and count > 1)) and slot.term.englishPlural then return slot.term.englishPlural end
                if slot.term.englishObject then
                    if form == "object" then return slot.term.englishObject end
                    if form == "negativeObject" then return (slot.term.englishObject:gsub("^some ", "")) end
                end
                return slot.term.en
            end
            if form == "destination" then
                local genitive = slot.term.forms and slot.term.forms.genitiveSingular
                return genitive and " до " .. genitive or " — " .. slot.term.uk
            end
            if form == "activity" then form = "accusative" end
            if form == "serviceObject" then
                return slot.term.forms and slot.term.forms.accusative or slot.term.uk
            end
            if form == "object" or form == "negativeObject" then
                form = slot.partitive and "genitiveSingular" or slot.plural and "accusativePlural" or "accusative"
            end
            if form == "countedObject" then
                local count = slots.count and tonumber(slots.count.raw)
                if not count then failed = true; return "" end
                local last, pair = count % 10, count % 100
                if last == 1 and pair ~= 11 then form = "accusative"
                elseif last >= 2 and last <= 4 and (pair < 12 or pair > 14) then
                    form = slot.term.forms.countTwoToFour and "countTwoToFour" or "accusativePlural"
                else form = "genitivePlural" end
            end
            if form == "counted" then form = G.numberForm(slots.count and slots.count.raw or "1")
            elseif form == "genitiveSingular" and slot.plural then form = "genitivePlural" end
            if form ~= "" and form ~= "canonical" then
                local value = slot.term.renderForms and slot.term.renderForms[form]
                    or slot.term.forms and slot.term.forms[form]
                if form == "locative" and not (slot.term.renderForms and slot.term.renderForms.locative) then
                    local term = slot.term
                    local number = term.features and term.features.number or term.morphology and term.morphology.number
                    if slot.plural then number = "plural" end
                    value = ns.Engine.Lexicon.curatedForm(term, "locative", number or "singular") or value
                end
                if not value then failed = true; return "" end
                return value
            end
            return slot.term.uk
        end
        if form == "roleQuantity" then return G.roleQuantity(slot, slots.role.term, true) end
        if form == "offerPrice" then return G.offerPriceText(slot.parts, direction == "uk-en") end
        if form == "money" or form == "moneyNominative" then return G.moneyText(slot, form == "moneyNominative") end
        return slot.raw
    end)
    if failed then return nil end
    return output
end
