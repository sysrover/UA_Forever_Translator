local _, ns = ...
local G = {}; ns.Engine.Grammar = G
local moneyForms = {
    g = {"золоту монету", "золоті монети", "золотих монет", "золотої монети"},
    s = {"срібну монету", "срібні монети", "срібних монет", "срібної монети"},
    c = {"мідну монету", "мідні монети", "мідних монет", "мідної монети"},
}

local function renderMoney(slot)
    local amount, forms = slot.amount, moneyForms[slot.unit]
    if not amount or not forms then return slot.raw end
    local numeric = tonumber((amount:gsub(",", ".")))
    if not numeric then return slot.raw end
    local last, pair = numeric % 10, numeric % 100
    local form = 3
    if numeric % 1 ~= 0 then form = 4
    elseif last == 1 and pair ~= 11 then form = 1
    elseif last >= 2 and last <= 4 and (pair < 12 or pair > 14) then form = 2 end
    return amount .. " " .. forms[form]
end

function G.numberForm(number)
    local n = tonumber(number)
    if not n then return "genitivePlural" end
    local last, pair = n % 10, n % 100
    if last == 1 and pair ~= 11 then return "genitiveSingular" end
    if last >= 2 and last <= 4 and (pair < 12 or pair > 14) then return "genitivePlural" end
    return "genitivePlural"
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
            if form == "counted" then form = G.numberForm(slots.count and slots.count.raw or "1") end
            if form == "genitiveSingular" and slot.plural then form = "genitivePlural" end
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
        return form == "money" and renderMoney(slot) or slot.raw
    end)
    if failed then return nil end
    return output
end
