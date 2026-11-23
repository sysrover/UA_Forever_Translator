-- EN → UK student inference shared by the addon and the offline evaluator.
local _, ns = ...
local Numbers = (function()
-- Indexed numeric spans for EN-to-UK chat inference.
local M = {}
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
    if not text:match("%d%s*[gsc]%f[^%w_]") then return nil end
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
            if value and terminal and value.sourceRaw:match("^%d+%s*[gsc]$") and #value.amount <= 8 then
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

return M
end)()

local finderCopula = {is=true, are=true, was=true, were=true, be=true}
local finderAction = {open=true, use=true, check=true, enable=true, disable=true}
local function finderReference(tokens, first)
    local before, after = tokens[first - 1], tokens[first + 1]
    return before and (finderCopula[before.key] or finderAction[before.key])
        or after and finderCopula[after.key]
end

local Glossary = (function()
-- Experimental typed dictionary slots for incoming WoW chat.
local G = {}
local char = function(offset) return string.char(238,132,128 + offset) end
-- The existing place marker represents a named noun phrase. Characters and
-- exact quest titles use the same marker without changing the model format.
local categories = {classes=1, roles=2, professions=3, places=4, characters=4, quests=4, game=4,
    slang=5, specializations=6, abilities=7, actions=8, goods=9, equipment=9}
local names = {"canonical","genitiveSingular","accusative","nominativePlural","genitivePlural",
    "accusativePlural","locative","instrumental","dativeSingular","dativePlural"}
local function keys(words)
    local out = {}
    for word in words:gmatch("%S+") do out[word] = true end
    return out
end
local recruitment = keys("lf lfg lfm lfw wtb wts wtt need seeking looking")
local nouns = keys("a an the any another our your my their his her need for with and one two more")
local placeCue = keys("in at from into to near outside inside around through")
local venueCue = keys("in at from near outside inside beside by than")
local groupQuestion = keys("any anyone anybody who")
local ambiguousRole = keys("heal heals tank dps damage")
local itemVerb = keys("make craft buy sell trade need use equip wear bring give offer gave disenchant enchant have got")
local professionDeterminers = keys("a an the any another our your my their his her")

G.sourceMarkers, G.targetMarkers = {}, {}
for i = 1,3 do G.sourceMarkers[i] = char(7+i) end
for i = 1,6 do G.sourceMarkers[3+i] = char(10+i) end
for i = 1,3 do G.sourceMarkers[9+i] = char(47+i) end
for i = 1,3 do
    G.targetMarkers[i] = {}
    for f = 1,#names do G.targetMarkers[i][f] = char(17+(i-1)*#names+f) end
end

local function senseAllowed(n, text, tokens, first, span, groupChat, opener)
    local entry = span.term
    local category, raw = entry.category,text:sub(tokens[first].first,tokens[span.last].last)
    local surface = n.key(raw)
    local exact = surface == n.key(entry.en or "")
    local plural = entry.englishPlural and surface == n.key(entry.englishPlural)
    local practitioner = entry.englishPractitioner and surface == n.key(entry.englishPractitioner)
    local prev = tokens[first-1] and tokens[first-1].key or ""
    local nominal = groupChat or nouns[prev] or prev:match("^[0-9]+$")
    if entry.features and entry.features.professionPractitioner then
        local head = tokens[1].key
        local preceding = tokens[first-2] and tokens[first-2].key
        return exact and (professionDeterminers[prev] or (prev == "for" and preceding == "looking")
            or (first == 1 and opener == "lf") or (first == 2 and head == "lf"))
    end
    local neuralSense = entry.features and entry.features.neuralSense
    if entry.englishLookupOnly or (entry.features and entry.features.caseSensitiveEnglish and raw ~= entry.en
        and neuralSense ~= "identifier") then
        return false
    end
    if category == "goods" or category == "equipment" then
        -- Only complete, approved names enter a slot. Digit-bearing aliases can also be durations.
        if not (exact or plural) or surface:find("[0-9]") then return false end
        if category == "goods" and span.last > first then return true end
        local before = tokens[first-2] and tokens[first-2].key or ""
        local nextWord = tokens[span.last+1] and tokens[span.last+1].key or ""
        local action = itemVerb[prev] or itemVerb[before] and professionDeterminers[prev]
        if category == "equipment" and span.last == first then
            return action and (entry.id ~= "equipment.chest" or prev == "enchant" or before == "enchant")
        end
        return action or (groupChat and (nextWord == "for" or nextWord == "with"))
    elseif category == "game" then
        if neuralSense == "identifier" then return exact end
        if neuralSense == "finder" then return exact or surface == "lfg" and finderReference(tokens, first) end
        if neuralSense == "venue" then
            local before = tokens[first-2] and tokens[first-2].key
            return exact or venueCue[prev] or prev == "the" and venueCue[before]
                or prev == "to" and before == "next" or prev == "only" and raw:match("^[A-Z][A-Z]+$") ~= nil
        end
        return false
    elseif category == "characters" then
        return exact and entry.features and entry.features.proper and not entry.features.verbatim
            and (span.last > first or raw == entry.en)
    elseif category == "quests" then
        return exact and span.last > first
    elseif category == "roles" and ambiguousRole[surface] then
        return nominal
    elseif category == "places" then
        if entry.features and entry.features.contextAliasSense == "roleAvailability" then
            for _, alias in ipairs(entry.contextAliases and entry.contextAliases.en or {}) do
                if surface == n.key(alias) then
                    local initial, promptIndex = tokens[1].key, 1
                    if initial == "is" or initial == "are" then
                        promptIndex = tokens[2] and tokens[2].key == "there" and 3 or 2
                    end
                    local prompt = tokens[promptIndex]
                    return groupChat or prev == "for" and (
                        prompt and groupQuestion[prompt.key] and first <= promptIndex + 3
                        or first == 3 and ambiguousRole[initial])
                end
            end
        end
        if exact or (surface:find(" ", 1, true) and span.last > first) then return true end
        if surface == "if" then return raw == "IF" and placeCue[prev] end
        return groupChat or (placeCue[prev] and #surface >= 4 and surface ~= "stocks")
    elseif category == "slang" then
        return exact and raw == entry.en and raw:match("^[A-Z][A-Z][A-Z]+$") ~= nil
    elseif category == "abilities" then
        return exact and (surface:find(" ",1,true) or (raw == entry.en and
            (prev == "cast" or prev == "learn" or prev == "use")))
    elseif category == "classes" or category == "professions" or category == "specializations" then
        return exact or plural or practitioner
    end
    return exact or plural
end

local function forms(engine,name,span)
    local entry = span.term
    if span.manual then
        if entry.object then return {[1]=entry.uk,[2]=entry.object,[3]=entry.object} end
        return {[1]=entry.uk}
    end
    local en = engine.Normalize.key(name)
    local practitioner = entry.englishPractitioner and en == engine.Normalize.key(entry.englishPractitioner)
    local resolved = {}
    for i, tag in ipairs(names) do
        local value
        if practitioner then
            local sense = entry.renderForms
            if sense then
                if i == 1 then value = sense.practitionerNominative
                elseif i == 2 or i == 3 then value = sense.practitioner end
            end
        elseif entry.category == "slang" or entry.category == "quests" then
            if i == 1 then value = engine.Morphology.generate(entry,"en-uk","canonical") or entry.uk end
        else
            local form = tag
            if tag == "locative" and entry.features and entry.features.neuralSense == "venue"
                and en ~= engine.Normalize.key(entry.en) then
                form = "locativeSingular"
            end
            value = engine.Morphology.generate(entry,"en-uk",form)
            if not value and i == 1 then value = entry.uk end
        end
        if value and (entry.category == "roles" or entry.category == "classes" or entry.category == "professions") then
            value = engine.Normalize.word(value)
        end
        if value and value ~= "" then resolved[i] = value end
    end
    return resolved
end

local function edits(text, changes)
    local out, cursor = {}, 1
    for _, change in ipairs(changes) do
        out[#out+1] = text:sub(cursor,change.first-1)
        out[#out+1] = change.value
        cursor = change.last+1
    end
    out[#out+1] = text:sub(cursor)
    return table.concat(out)
end


local classTypoIndices = setmetatable({},{__mode="k"})
local recruitingPeople = keys("lf lfg lfm seeking need")
local roleFollowing = keys("to for with in at from and please pst who that")
local actionCues = keys("to can could might should must would will please"
    .. " gotta gonna")
local actionPronouns = keys("i we you u they he she someone anybody anyone somebody")
local actionObjects = keys("me him her it them us this that now please again")
local abilityCues = keys("learn learned learning use cast get unlock teach got trained"
    .. " teaching ability talent starter spell skill")
local abilityPossessors = keys("my your our their his her")
local qualifier = keys("a an any another one two more")
local lexemes = {
    ["lockpick"]={id="action.lockpick",category="actions",uk="зламати замок",objectIncluded=true},
    ["pick a lock"]={id="action.lockpick",category="actions",uk="зламати замок"},
    ["pick the lock"]={id="action.lockpick",category="actions",uk="зламати замок"},
    ["pick locks"]={id="action.pick_locks",category="actions",uk="зламувати замки"},
    ["disenchant"]={id="action.disenchant",category="actions",uk="розпилити"},
    ["dispel"]={id="action.dispel",category="actions",uk="розвіяти"},
    ["resurrect"]={id="action.resurrect",category="actions",uk="воскресити"},
    ["rez"]={id="action.resurrect",category="actions",uk="воскресити"},
    ["res"]={id="action.resurrect",category="actions",uk="воскресити"},
    ["interrupt"]={id="action.interrupt",category="actions",uk="перервати"},
    ["taunt"]={id="action.taunt",category="actions",uk="спровокувати"},
    ["summon"]={id="action.summon",category="actions",uk="викликати"},
    ["dual wield"]={id="ability.dual_wield",category="abilities",uk="бій двома зброями"},
    ["lockpicking"]={id="ability.lockpicking",category="abilities",uk="зламування замків"},
    ["blacksmith"]={id="profession.blacksmithing.practitioner",category="professions",uk="коваль",object="коваля"},
    ["bs"]={id="profession.blacksmithing.practitioner",category="professions",uk="коваль",object="коваля"},
}
G.lexemes = lexemes
local function recruitPosition(tokens, first, opener)
    local start
    if recruitingPeople[opener] then start=1
    elseif recruitingPeople[tokens[1].key] then start=2
    elseif tokens[1].key=="looking" and tokens[2] and tokens[2].key=="for" then start=3 end
    if not start or first<start or first-start>2 then return false end
    for i=start,first-1 do
        local token=tokens[i].key
        if not qualifier[token] and not token:match("^[0-9]+$") then return false end
    end
    return true
end

local actionTails=keys("for after before now please again then if when")

local function curatedLexeme(tokens, first, opener)
    if tokens[first].protected then return nil end
    local previous=tokens[first-1] and tokens[first-1].key or ""
    local earlier=tokens[first-2] and tokens[first-2].key or ""
    local phrase, result = "", nil
    for last=first,math.min(#tokens,first+2) do
        if tokens[last].protected then break end
        phrase=phrase..(last==first and "" or " ")..tokens[last].key
        local entry=lexemes[phrase]
        if entry then
            local nextWord=tokens[last+1] and tokens[last+1].key or ""
            local modal=actionCues[previous] or (actionCues[earlier] and actionPronouns[previous])
            local allowed
            if entry.category=="actions" then
                allowed=modal or (first==1 and actionObjects[nextWord])
                if entry.objectIncluded and (nextWord:match("^[a-z]+$") and not
                    actionTails[nextWord] or
                    (tokens[last+1] and tokens[last+1].protected)) then allowed=false end
            elseif entry.category=="abilities" then
                allowed=abilityCues[previous] or abilityCues[earlier] or abilityPossessors[previous]
                    or nextWord=="skill" or nextWord=="ability"
            elseif entry.category=="professions" then
                allowed=recruitPosition(tokens,first,opener) or (phrase=="blacksmith" and nouns[previous] and
                    (nextWord=="to" or nextWord=="who" or nextWord=="with"))
            end
            if allowed then
                result={id=entry.id,term=entry,last=last,manual=true}
            end
        end
    end
    return result
end

local function classTypo(ns,tokens,first,opener)
    local following = tokens[first+1] and tokens[first+1].key
    local actorQuestion = first == 2 and tokens[1].key == "any" and following == "who"
    if not (actorQuestion or recruitPosition(tokens,first,opener)) or
        (following and not roleFollowing[following] and not following:match("^[!?.]$")) then
        return nil
    end
    local registry = ns.Data.terms
    local index = classTypoIndices[registry]
    if not index then
        index = {}
        for _, entry in pairs(registry) do
            local canonical = entry.category == "classes" and entry.status == "approved"
                and ns.Engine.Normalize.key(entry.en)
            if canonical and canonical:match("^[a-z][a-z][a-z][a-z]+$") then
                for i = 1,#canonical-1 do
                    if canonical:sub(i,i) ~= canonical:sub(i+1,i+1) then
                        local spelling = canonical:sub(1,i-1)..canonical:sub(i+1,i+1)
                            ..canonical:sub(i,i)..canonical:sub(i+2)
                        local current = index[spelling]
                        if current ~= nil and current ~= entry then index[spelling] = false
                        else index[spelling] = entry end
                    end
                end
            end
        end
        classTypoIndices[registry] = index
    end
    local corrected = index[tokens[first].key]
    if corrected then return {term=corrected,id=corrected.id,last=first,correctedSource=corrected.en} end
end

function G.mask(ns,text,opener,itemSlots)
    if text:find("\238\132[\136-\178]") then return text end
    local e = ns.Engine
    local tokens = e.Tokenizer.scan(text,e.ClauseAnalysis.englishContractions)
    if not tokens or #tokens == 0 then return text end
    if itemSlots and ns.Linguistics then
        local cardinal = ns.Linguistics.grammar.cardinalEn
        for _, token in ipairs(tokens) do
            if cardinal[token.key] then itemSlots = false; break end
        end
    end
    local doc = e.Morphology.analyze(text,tokens,"en-uk")
    local groupChat = recruitment[opener] or recruitment[tokens[1].key]
        or (tokens[1].key == "looking" and tokens[2] and tokens[2].key == "for")
    local slots, changes, first = {}, {}, 1
    local corrections
    while first <= #tokens do
        local best, ambiguous
        if not doc.limited[first] then
            for _, span in ipairs(doc.spans[first] or {}) do
                local entry = span.term
                if entry and categories[entry.category] and entry.status == "approved"
                    and (categories[entry.category] ~= 9 or itemSlots)
                    and senseAllowed(e.Normalize,text,tokens,first,span,groupChat,opener) then
                    if not best or span.last > best.last then
                        best, ambiguous = span, false
                    elseif span.last == best.last and span.id ~= best.id then
                        ambiguous = true
                    end
                end
            end
        end
        local fixed=curatedLexeme(tokens,first,opener)
        if fixed and (not best or fixed.last>best.last) then best, ambiguous=fixed, false end
        if not best and not ambiguous and not tokens[first].protected then best=classTypo(ns,tokens,first,opener) end
        if best and not ambiguous then
            local start, finish = tokens[first].first,tokens[best.last].last
            local surface = text:sub(start,finish)
            if best.correctedSource then
                corrections = corrections or {}
                corrections[#corrections+1] = {first=start,last=finish,value=best.correctedSource}
            end
            local f = forms(e,surface,best)
            local category = categories[best.term.category]
            if category == 9 then
                local term = best.term
                local lexicalPlural = term.features and term.features.number == "plural"
                local inflectedPlural = term.englishPlural and e.Normalize.key(surface) == e.Normalize.key(term.englishPlural)
                    and e.Normalize.key(surface) ~= e.Normalize.key(term.en)
                if inflectedPlural and not lexicalPlural then
                    f[1], f[2], f[3], f[7], f[8], f[9] = nil, nil, nil, nil, nil, nil
                elseif not lexicalPlural then
                    f[4], f[5], f[6], f[10] = nil, nil, nil, nil
                end
            end
            if opener == "lf" and recruitPosition(tokens,first,opener) and
                (best.term.category == "classes" or best.term.category == "roles" or best.term.category == "professions") then
                local choice = best.features and best.features.number == "plural" and f[6] and 6 or (f[3] and 3)
                if choice then f = {[choice]=f[choice]} end
            end
            local slot = #slots + 1
            if next(f) then
                if slot > #G.targetMarkers then return text,nil,corrections and edits(text,corrections) end
                slots[slot] = {id=best.id, forms=f, raw=surface,
                    preferConstrained=category == 9 or best.term.category == "game"}
                changes[slot] = {first=start,last=finish,value=G.sourceMarkers[slot]..G.sourceMarkers[3+category]}
            end
            first = best.last+1
        else
            first = first+1
        end
    end
    if #slots == 0 then return text end
    return edits(text,changes),slots,corrections and edits(text,corrections)
end

function G.target(ns,text,mapping)
    local n = ns.Engine.Normalize
    local target = ns.Engine.Tokenizer.scan(text)
    if not target then return nil end
    local occupied, changes = {}, {}
    for i, slot in ipairs(mapping) do
        local variants = {}
        for form = 1,#names do
            local label = slot.forms[form]
            if label then variants[form] = ns.Engine.Tokenizer.scan(label) end
        end
        local answer
        for index, head in ipairs(target) do
            if not occupied[index] and not head.protected then
                for form = 1,#names do
                    local tokens = variants[form]
                    local fits = tokens and #tokens > 0 and index+#tokens-1 <= #target
                    if fits then
                        for j, token in ipairs(tokens) do
                            local placed = index+j-1
                            if occupied[placed] or target[placed].protected or target[placed].key ~= token.key then
                                fits = false
                                break
                            end
                        end
                    end
                    if fits and (not answer or #tokens > answer.length) then
                        answer = {offset=index,length=#tokens,form=form}
                    end
                end
            end
        end
        if not answer then return nil end
        local first,last = answer.offset,answer.offset+answer.length-1
        for j=first,last do occupied[j]=true end
        changes[#changes+1] = {first=target[first].first,last=target[last].last,
            value=G.targetMarkers[i][answer.form]}
    end
    table.sort(changes,function(a,b) return a.first < b.first end)
    return edits(text,changes)
end

function G.restore(ns,text,mapping,opener)
    local used, invalid = {}, false
    text = text:gsub("\238\132[\146-\175]",function(key)
        local idx = key:byte(3)-146
        local slot, form = math.floor(idx/#names)+1,idx%#names+1
        local value = mapping[slot] and mapping[slot].forms[form]
        if not value or used[slot] then invalid = true; return key end
        used[slot]=true
        return value
    end)
    if invalid or text:find("\238\132[\136-\178]") then return nil end
    for i=1,#mapping do if not used[i] then return nil end end
    return opener and text or ns.Engine.Normalize.upperStart(text)
end

return G
end)()
local M = {}
if ns then ns.Engine.NeuralRuntime = M end
local UNK, BOS, EOS, PAD = 1, 2, 3, 4
local MAX_PIECES = 48
local alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz!#$%&()*+-;<=>?@^_"
    .. string.char(96) .. "{|}~"
local digit = {}
for i = 1, #alphabet do digit[alphabet:byte(i)] = i - 1 end
local floor, exp = math.floor, math.exp

local function decodeBytes(packed)
    local row = {}
    for start = 1, #packed, 5 do
        local a, b, c, d, e = packed:byte(start, start + 4)
        local value = (((digit[a] * 85 + digit[b]) * 85 + digit[c]) * 85 + digit[d]) * 85 + digit[e]
        row[#row + 1] = floor(value / 16777216)
        row[#row + 1] = floor(value / 65536) % 256
        row[#row + 1] = floor(value / 256) % 256
        row[#row + 1] = value % 256
    end
    return row
end

local function rowAt(matrix, index)
    local row = matrix.rows[index]
    if not row then
        row = decodeBytes(matrix.packed[index])
        for i, value in ipairs(row) do
            if value >= 128 then row[i] = value - 256 end
        end
        matrix.rows[index] = row
    end
    return row, matrix.scales[index]
end

local function embedding(matrix, index, width)
    local row, scale = rowAt(matrix, index)
    local values = {}
    for i = 1, width do values[i] = row[i] * scale end
    return values
end

local function project(matrix, index, values, width)
    local row, scale = rowAt(matrix, index)
    local total = 0
    for i = 1, width do total = total + row[i] * values[i] end
    return total * scale
end

local function sigmoid(value)
    return 1 / (1 + exp(-value))
end

local function tanh(value)
    local decay = exp(-2 * math.abs(value))
    local positive = (1 - decay) / (1 + decay)
    return value < 0 and -positive or positive
end

local function gru(network, input, state, width, checkpoint)
    local nextState = {}
    local inputWidth = #input
    for i = 1, width do
        local reset = sigmoid(project(network.input, i, input, inputWidth) + network.inputBias[i]
            + project(network.state, i, state, width) + network.stateBias[i])
        local updateIndex = width + i
        local update = sigmoid(project(network.input, updateIndex, input, inputWidth) + network.inputBias[updateIndex]
            + project(network.state, updateIndex, state, width) + network.stateBias[updateIndex])
        local cellIndex = 2 * width + i
        local cell = tanh(project(network.input, cellIndex, input, inputWidth) + network.inputBias[cellIndex]
            + reset * (project(network.state, cellIndex, state, width) + network.stateBias[cellIndex]))
        nextState[i] = (1 - update) * cell + update * state[i]
        if checkpoint and i % 8 == 0 then checkpoint() end
    end
    return nextState
end


local function transformerNetwork(values, matrix)
    local function attention(weights)
        return {qkv=matrix(weights.qkv), output=matrix(weights.output)}
    end
    local function blocks(rows)
        local result = {}
        for i, row in ipairs(rows) do
            result[i] = {
                selfNorm=row.selfNorm, attention=attention(row.attention), feedNorm=row.feedNorm,
                feedIn=matrix(row.feedIn), feedOut=matrix(row.feedOut),
                crossNorm=row.crossNorm, crossAttention=row.crossAttention and attention(row.crossAttention)
            }
        end
        return result
    end
    return {heads=values.heads, sourcePos=matrix(values.sourcePos), targetPos=matrix(values.targetPos),
        sourceNorm=values.sourceNorm, targetNorm=values.targetNorm,
        encoder=blocks(values.encoder), decoder=blocks(values.decoder)}
end

function M.prepare(data, checkpoint)
    assert(data.format == 1 or data.format == 2 or data.format == 3, "Unsupported translation student format")
    local function matrix(values)
        return {packed=values.packed, scales=values.scales, rows={}}
    end
    local function network(values)
        return {input=matrix(values.input), state=matrix(values.state), inputBias=values.inputBias,
            stateBias=values.stateBias}
    end
    local pieces, maximumBytes = {}, 0
    for id = PAD + 1, #data.sourcePieces do
        local piece = data.sourcePieces[id]
        pieces[piece] = {id=id, score=data.sourceScores[id]}
        maximumBytes = math.max(maximumBytes, #piece)
        if checkpoint and id % 128 == 0 then checkpoint() end
    end
    local reserved, allCandidates = {}, {EOS}
    local numericPieces
    if data.numberSlots then
        numericPieces = {}
        for id, piece in ipairs(data.targetPieces) do
            if piece:find('[0-9]') then numericPieces[id] = true end
        end
    end
    for _, id in ipairs(data.targetSlots or {}) do reserved[id] = true end
    for id = PAD + 1, #data.targetPieces do
        if not reserved[id] then allCandidates[#allCandidates + 1] = id end
        if checkpoint and id % 128 == 0 then checkpoint() end
    end
    return {width=data.width, pieces=pieces, maximumBytes=maximumBytes, unknownScore=data.unknownScore,
        targetPieces=data.targetPieces, fallback=data.fallback, linked=data.linked, linkedCache={},
        allCandidates=allCandidates, reserved=reserved, inputAttention=data.format == 2,
        numberSlots=data.numberSlots, numericPieces=numericPieces, termSlots=data.termSlots, itemSlots=data.itemSlots, moneySlots=data.moneySlots,
        maxPieces=data.transformer and math.min(128, #data.transformer.sourcePos.packed,
            #data.transformer.targetPos.packed) or MAX_PIECES,
        source=matrix(data.source), target=matrix(data.target), encoder=data.encoder and network(data.encoder),
        transformer=data.transformer and transformerNetwork(data.transformer, matrix),
        decoder=data.decoder and network(data.decoder), combine=data.combine and matrix(data.combine), combineBias=data.combineBias,
        outputBias=data.outputBias}
end

function M.tokenize(model, text, checkpoint)
    text = text:gsub("’", "'"):gsub("‘", "'"):gsub("ʼ", "'"):gsub("[A-Z]", string.lower)
    text = text:gsub("^ +", ""):gsub(" +$", ""):gsub(" +", " ")
    if text == "" then return {EOS} end
    text = "▁" .. text:gsub(" ", "▁")
    local positions = {}
    for start in text:gmatch("()[^\128-\191][\128-\191]*") do positions[#positions + 1] = start end
    positions[#positions + 1] = #text + 1
    local scores, back, ids = {[1]=0}, {}, {}
    for first = 1, #positions - 1 do
        local score, foundSingle = scores[first], false
        if score then
            for last = first + 1, #positions do
                local firstByte, nextByte = positions[first], positions[last]
                if nextByte - firstByte > model.maximumBytes then break end
                local piece = model.pieces[text:sub(firstByte, nextByte - 1)]
                if piece then
                    if last == first + 1 then foundSingle = true end
                    local total = score + piece.score
                    if not scores[last] or total > scores[last] then
                        scores[last], back[last], ids[last] = total, first, piece.id
                    end
                end
            end
            if not foundSingle then
                local last, total = first + 1, score + model.unknownScore
                if not scores[last] or total > scores[last] then
                    scores[last], back[last], ids[last] = total, first, UNK
                end
            end
        end
        if checkpoint and first % 24 == 0 then checkpoint() end
    end
    local reversed, index = {}, #positions
    while back[index] do
        local id = ids[index]
        if id ~= UNK or reversed[#reversed] ~= UNK then reversed[#reversed + 1] = id end
        index = back[index]
    end
    local tokens = {}
    for i = #reversed, 1, -1 do tokens[#tokens + 1] = reversed[i] end
    tokens[#tokens + 1] = EOS
    return tokens
end

function M.encode(model, tokens, checkpoint)
    local width, state, encoded = model.width, {}, {}
    for i = 1, width do state[i] = 0 end
    for i, id in ipairs(tokens) do
        state = gru(model.encoder, embedding(model.source, id, width), state, width, checkpoint)
        encoded[i] = state
    end
    return encoded, state
end

local function sourceContext(query, encoded, width)
    local attention, maximum = {}, -math.huge
    local divisor = math.sqrt(width)
    for i, row in ipairs(encoded) do
        local total = 0
        for j = 1, width do total = total + row[j] * query[j] end
        attention[i] = total / divisor
        maximum = math.max(maximum, attention[i])
    end
    local sum = 0
    for i, value in ipairs(attention) do
        attention[i] = exp(value - maximum)
        sum = sum + attention[i]
    end
    local context = {}
    for j = 1, width do context[j] = 0 end
    for i, row in ipairs(encoded) do
        local weight = attention[i] / sum
        for j = 1, width do context[j] = context[j] + row[j] * weight end
    end
    return context
end

function M.decode(model, previous, encoded, state, checkpoint)
    local width = model.width
    local input = embedding(model.target, previous, width)
    if model.inputAttention then
        local context = sourceContext(input, encoded, width)
        for i = 1, width do input[width + i] = context[i] end
    end
    state = gru(model.decoder, input, state, width, checkpoint)
    local context, combined = sourceContext(state, encoded, width), {}
    for i = 1, width do combined[i], combined[width + i] = state[i], context[i] end
    local features = {}
    for j = 1, width do
        features[j] = tanh(project(model.combine, j, combined, width * 2) + model.combineBias[j])
        if checkpoint and j % 8 == 0 then checkpoint() end
    end
    return features, state
end

function M.candidates(model, source)
    local found, candidates = {}, {}
    local function add(group)
        for _, id in ipairs(group) do
            if not found[id] and not model.reserved[id] then found[id], candidates[#candidates + 1] = true, id end
        end
    end
    add(model.fallback)
    for _, piece in ipairs(source) do
        local linked = model.linkedCache[piece]
        if not linked and model.linked[piece] then
            linked = {}
            local bytes = decodeBytes(model.linked[piece])
            for i = 1, #bytes, 2 do
                local id = bytes[i] + 256 * bytes[i + 1]
                if id ~= 0 then linked[#linked + 1] = id end
            end
            model.linkedCache[piece] = linked
        end
        if linked then add(linked) end
    end
    table.sort(candidates)
    return candidates
end

function M.score(model, features, id)
    return project(model.target, id, features, model.width) + model.outputBias[id]
end

local negativeAuxiliaries = {
    ["don't"]="do", ["doesn't"]="does", ["didn't"]="did",
    ["can't"]="can", ["couldn't"]="could", ["won't"]="will",
    ["shouldn't"]="should", ["wouldn't"]="would",
}
local negativeSubjects = {i=true, we=true, you=true, he=true, she=true, it=true, they=true, u=true}

local function modelSource(text)
    local engine = ns.Engine
    local aliases = engine.Normalize.englishNegativeAliases
    local hasAlias
    for word in text:gmatch("%f[%a]([A-Za-z]+[nN][tT])%f[^%w_]") do
        if negativeAuxiliaries[aliases[word:lower()]] then hasAlias = true; break end
    end
    if not hasAlias then return text end
    local tokens = engine.Tokenizer.scan(text)
    if not tokens then return text end
    local changes, cursor, document = nil, 1, nil
    for i, token in ipairs(tokens) do
        local auxiliary = not token.protected and negativeAuxiliaries[aliases[token.key]]
        local nextToken = auxiliary and tokens[i + 1]
        if nextToken and not nextToken.protected then
            local ambiguous = token.key == "cant" or token.key == "wont"
            local previous = tokens[i - 1]
            local spelling = text:sub(token.first, token.last)
            local possibleName = previous and not previous.key:match("^[.!?]$") and spelling:match("^[A-Z][a-z]+$")
            if not possibleName and (not ambiguous or previous and negativeSubjects[previous.key]) then
                document = document or {tokens=tokens, direction="en-uk"}
                for _, entry in ipairs(engine.Lexicon.at(document, i + 1)) do
                    if entry.lexeme.pos == "verb" and entry.lexeme.en == nextToken.key then
                        changes = changes or {}
                        changes[#changes + 1] = text:sub(cursor, token.first - 1)
                        changes[#changes + 1] = auxiliary .. " not"
                        cursor = token.last + 1
                        break
                    end
                end
            end
        end
    end
    if not changes then return text end
    changes[#changes + 1] = text:sub(cursor)
    return table.concat(changes)
end

local outputNegatives = {
    ["не"]=true, ["ні"]=true, ["ані"]=true, ["ніколи"]=true, ["ніхто"]=true, ["ніщо"]=true,
    ["нічого"]=true, ["нема"]=true, ["немає"]=true, ["неможливо"]=true, ["заборонено"]=true,
}
local function hasVisibleNegation(text)
    if not text then return false end
    for _, token in ipairs(ns.Engine.Tokenizer.scan(text) or {}) do
        if not token.protected and outputNegatives[token.key] then return true end
    end
    return false
end

-- Training can select the original fragment or the expanded retry input.
function M.prepareTrainingFragment(source, target, opener, expanded, glossary)
    if expanded then source = modelSource(source) end
    local digits = target:gmatch("%d+")
    for number in source:gmatch("%d+") do
        if digits() ~= number then return nil, "different-numbers" end
    end
    if digits() then return nil, "different-numbers" end

    if glossary then
        local masked, terms = Glossary.mask(ns, source, opener, glossary == "items")
        if not terms then return nil, "no-glossary-slots" end
        local reference = Glossary.target(ns, target, terms)
        if not reference then return nil, "reference-glossary-slots" end
        source, target = masked, reference
    end

    local prices = Numbers.prices(source, opener)
    if prices then
        local masked, values = Numbers.mask(source, prices)
        local reference = masked and values and Numbers.target(target, values)
        if reference then return masked, reference, "currency" end
    end
    local masked, values = Numbers.mask(source)
    if not masked then return nil, values end
    if not values then return source, target, "plain" end
    local reference = Numbers.target(target, values)
    if reference then return masked, reference, "slots" end
    return nil, "reference-slots"
end

local function translatePlain(model, text, checkpoint, fullVocabulary, opener, terms, prices)
    local sourceText, values = text, nil
    if terms then sourceText = terms.input end
    if model.numberSlots then
        local masked, mapping = Numbers.mask(sourceText, prices)
        if not masked then return nil, mapping end
        sourceText, values = masked, mapping
    elseif sourceText:find("[0-9]") then
        return nil, "number-slots-unavailable"
    end
    local source = M.tokenize(model, sourceText, checkpoint)
    if #source < 2 or #source > model.maxPieces then return nil, "source-length" end
    for _, id in ipairs(source) do
        if id == UNK then return nil, "source-vocabulary" end
    end
    local choices = fullVocabulary and model.allCandidates or M.candidates(model, source)
    local pending
    if values or terms then
        local filtered = {}
        for _, id in ipairs(choices) do
            if not values or not model.numericPieces[id] then filtered[#filtered + 1] = id end
        end
        pending = {}
        for i = 1, values and #values or 0 do
            local id = model.numberSlots[i]
            filtered[#filtered+1], pending[id] = id, {[id]=true}
        end
        for i, entry in ipairs(terms or {}) do
            local group = {}
            for form in pairs(entry.forms) do
                local id = model.termSlots[i][form]
                group[id] = true
                filtered[#filtered+1], pending[id] = id, group
            end
        end
        table.sort(filtered)
        choices = filtered
    end
    local encoded, state = M.encode(model, source, checkpoint)
    local target, previous = {}, BOS
    for _ = 1, model.maxPieces do
        local features
        features, state = M.decode(model, previous, encoded, state, checkpoint)
        local best, highest = EOS, -math.huge
        for index, id in ipairs(choices) do
            local score = M.score(model, features, id)
            if score > highest then best, highest = id, score end
            if checkpoint and index % 32 == 0 then checkpoint() end
        end
        if best == EOS then
            local output = table.concat(target):gsub("▁", " "):gsub("^ +", "")
            if output == "" then return nil, "empty" end
            if values then
                local reason
                output, reason = Numbers.restore(output, values)
                if not output then return nil, reason, #choices end
            end
            if terms then
                output = Glossary.restore(ns, output, terms, opener)
                if not output then return nil, "term-slots", #choices end
            end
            return output, "complete", #choices
        end
        local group = pending and pending[best]
        if group then
            for i=#choices,1,-1 do
                if group[choices[i]] then table.remove(choices,i) end
            end
        end
        target[#target + 1], previous = model.targetPieces[best], best
    end
    return nil, "target-length", #choices
end

function M.withProtected(text, split, translate)
    local segments = split(text)
    if #segments == 0 or (#segments == 1 and not segments[1].protected) then
        return translate(text)
    end
    local pieces, protected, calls, largest = {}, {}, 0, 0
    local changed, incomplete = false, false
    for _, segment in ipairs(segments) do
        local original = text:sub(segment.first, segment.last)
        local value = original
        if segment.protected then
            protected[#protected + 1] = original
        elseif original:find("[A-Za-z]") then
            local leading, body, trailing = original:match("^(%s*)(.-)(%s*)$")
            local result, _, candidates = translate(body, segment.first)
            calls = calls + 1
            largest = math.max(largest, candidates or 0)
            if result then
                value = leading .. result:gsub("%s+$", "") .. trailing
                changed = changed or value ~= original
            else
                incomplete = true
            end
        end
        pieces[#pieces + 1] = value
    end
    if not changed then return text, "unchanged", largest, calls end
    local output, index = table.concat(pieces), 0
    for _, segment in ipairs(split(output)) do
        if segment.protected then
            index = index + 1
            if protected[index] ~= output:sub(segment.first, segment.last) then
                return text, "protected-output", largest, calls
            end
        end
    end
    if index ~= #protected then return text, "protected-output", largest, calls end
    return output, incomplete and "partial" or "complete", largest, calls
end

local function translateWithPrices(model, text, checkpoint, fullVocabulary, opener, terms)
    local prices = model.moneySlots and Numbers.prices(terms and terms.input or text, opener)
    if prices then
        local result, mode, count = translatePlain(model, text, checkpoint, fullVocabulary, opener, terms, prices)
        if result then
            local digits = result:gmatch("%d+")
            local same = true
            for original in text:gmatch("%d+") do
                if digits() ~= original then same = false; break end
            end
            if same and not digits() then return result, mode, count end
        end
    end
    return translatePlain(model, text, checkpoint, fullVocabulary, opener, terms)
end

function M.translate(model, text, checkpoint, fullVocabulary, split, context)
    local function infer(fragment, opener)
        if not model.termSlots then return translateWithPrices(model, fragment, checkpoint, fullVocabulary) end
        local masked, terms, corrected = Glossary.mask(ns, fragment, opener, model.itemSlots)
        local function constrained()
            terms.input = masked
            local candidate, mode, count = translateWithPrices(model, fragment, checkpoint, fullVocabulary, opener, terms)
            if candidate and Glossary.target(ns, candidate, terms) then return candidate, mode, count end
        end
        local preferConstrained
        for _, term in ipairs(terms or {}) do
            if term.preferConstrained then preferConstrained = true; break end
        end
        if preferConstrained then
            local candidate, mode, count = constrained()
            if candidate then return candidate, mode, count end
        end
        local ordinary, ordinaryMode, ordinaryCount = translateWithPrices(model, corrected or fragment,
            checkpoint, fullVocabulary, opener)
        if terms and not preferConstrained and (not ordinary or not Glossary.target(ns, ordinary, terms)) then
            local candidate, mode, count = constrained()
            if candidate then return candidate, mode, count end
        end
        return ordinary, ordinaryMode, ordinaryCount
    end
    local function translate(fragment, opener)
        local output, mode, count = infer(fragment, opener)
        local expanded = modelSource(fragment)
        if expanded ~= fragment and not hasVisibleNegation(output) then
            local alternative, retryMode, retryCount = infer(expanded, opener)
            if hasVisibleNegation(alternative) then return alternative, retryMode, retryCount end
        end
        return output, mode, count
    end
    if not split then return translate(text, context) end
    return M.withProtected(text, split, function(fragment, first)
        return translate(fragment, (not first or first == 1) and context or nil)
    end)
end

local chatOpeners = {lf=true, lfg=true, lfm=true, wts=true, wtb=true, wtt=true, lfw=true,
    afk=true, brb=true, oom=true, pst=true}
local tradeLinkOpeners = {lfw=true, wts=true, wtb=true, wtt=true}
function M.chatOpener(tokens, first)
    local head, nextWord = tokens[first], tokens[first + 1]
    if head and head.linkKind == "trade" and nextWord and tradeLinkOpeners[nextWord.key] then
        first = first + 1
        head, nextWord = nextWord, tokens[first + 1]
    end
    if head and not head.protected and chatOpeners[head.key]
        and (head.key ~= "lfg" or not finderReference(tokens, first))
        and not (nextWord and (nextWord.key == "means" or nextWord.key == "stands")) then
        return first
    end
end
local separators = {[","]=true, [";"]=true, ["—"]=true, ["–"]=true}

local clauseDependent = {he=true, she=true, they=true, it=true, this=true, that=true,
    these=true, those=true, because=true, whereas=true, although=true, which=true}
local conditionalContinuation = {unless=true, ["if"]=true, ["while"]=true, since=true}
local periodAbbreviation = {dr=true, mr=true, mrs=true, ms=true, st=true, vs=true, lvl=true, etc=true,
    no=true, approx=true, prof=true, sr=true, jr=true, inc=true}

local function independentChat(text, tokens, ranges, parser)
    if #ranges < 2 or #ranges > 6 or #tokens < 23 then return false end
    local twoSentences = #ranges == 2
    local minimumWords = twoSentences and 4 or 2
    local total = 0
    for i, range in ipairs(ranges) do
        local first, last = range[1], range[2]
        local initial = tokens[first]
        if i > 1 and (clauseDependent[initial.key] or twoSentences and conditionalContinuation[initial.key]
            or not parser.startsWithCapital(text, initial)) then return false end
        if i < #ranges then
            local stop, previous = tokens[last], tokens[last - 1]
            if not previous or stop.key ~= "." and stop.key ~= "!" and stop.key ~= "?" then return false end
            if previous.key:match("^[.?!]$") or previous.key == "…" or periodAbbreviation[previous.key]
                or stop.key == "." and #previous.key < 2 then return false end
        end
        local count, hasNumbers = 0, false
        for j = first, last do
            local token = tokens[j]
            if not token.protected then
                if token.key == "/" or token.key == "…" then return false end
                hasNumbers = hasNumbers or token.key:find("[0-9]") ~= nil
                if token.key:find("[A-Za-z]") then count = count + 1 end
            end
        end
        if count < minimumWords then return false end
        if hasNumbers then
            local source = text:sub(tokens[first].first, tokens[last].last)
            if not Numbers.ranges(source, Numbers.prices(source)) then return false end
        end
        total = total + count
    end
    return total >= 21
end

function M.routeChat(ns, text, translate, checkpoint, tokens, facts, grammarClause)
    local engine, direction = ns.Engine, "en-uk"
    tokens = tokens or engine.Tokenizer.scan(text, engine.ClauseAnalysis.englishContractions)
    if not tokens or #tokens == 0 then
        local result, mode = translate(text)
        return result, mode, 1, 0
    end
    local ranges, first, routed = {}, 1, false
    for i = 1, #tokens - 1 do
        if engine.Parser.sentenceBoundary(text, tokens, i) then
            local known = M.chatOpener(tokens, first)
            ranges[#ranges + 1], first = {first, i, known}, i + 1
            routed = routed or known
        end
    end
    local known = M.chatOpener(tokens, first)
    ranges[#ranges + 1] = {first, #tokens, known}
    local independent = not (routed or known) and independentChat(text, tokens, ranges, engine.Parser)
    if not (routed or known or independent) then
        local result, mode = translate(text)
        return result, mode, 1, 0
    end

    local document = engine.Morphology.analyze(text, tokens, direction)
    document.checkpoint = checkpoint
    facts = facts or engine.Acceptance.measure(text, tokens, direction)
    local calls, rules = 0, 0
    local tradeOpeners = ns.Linguistics and ns.Linguistics.grammar.tradeOpeners
    local function raw(start, finish)
        return text:sub(tokens[start].first, tokens[finish].last)
    end
    local function rule(start, finish)
        local exact = ns.Data.exact[direction][engine.Normalize.key(raw(start, finish))]
        local value = exact and exact.text or engine.Syntax.translateRange(document, start, finish)
            or engine.Parser.translate(text, tokens, direction, start, finish)
        if not value and grammarClause and tradeOpeners and tradeOpeners[tokens[start].key]
            and not document.truncated and not document.ambiguities then
            local translated, clause = grammarClause(document, start, finish)
            if translated and not clause.unknownSpans then value = translated end
        end
        if value and not engine.Acceptance.reject(facts, start, finish, value) then return value end
    end
    local function neural(start, finish, context)
        calls = calls + 1
        local value, mode = translate(raw(start, finish),context)
        if value and not engine.Acceptance.reject(facts, start, finish, value) then return value, mode end
        return raw(start, finish), "partial"
    end
    local function mixed(start, finish)
        local whole = rule(start, finish)
        if whole then rules = rules + 1; return whole, "complete" end
        local head, number, suffix = tokens[start], tokens[start + 1], tokens[start + 2]
        local recruiting = head.key == "lf" or head.key == "lfm"
        for i = start + 1, math.min(finish - 1, start + 16) do
            if not tokens[i].protected and separators[tokens[i].key] then
                -- A role requirement still depends on the recruitment before the separator.
                if recruiting and engine.Syntax.recruitRoleRequestEnd(tokens, i + 1, finish) then break end
                local prefix = rule(start, i - 1)
                if prefix then
                    local tail, mode = neural(i + 1, finish, head.key)
                    local join = text:sub(tokens[i - 1].last + 1, tokens[i + 1].first - 1)
                    rules = rules + 1
                    return prefix:gsub("[.!?]+$", "") .. join .. tail, mode
                end
            end
        end
        local stop, prefix = start, nil
        if head.key == "lf" and number and suffix and start + 2 <= finish and number.key:match("^%d+$")
            and suffix.key == "m" and head.last + 1 == number.first and number.last + 1 == suffix.first then
            stop = start + 2
            prefix = rule(start, stop)
        end
        if not prefix then
            local entry = engine.Dictionary.literal(document, start, nil, start)
            prefix = entry and (entry.text or entry.uk)
            stop = start
        end
        if not prefix then return neural(start, finish) end
        rules = rules + 1
        if stop == finish then return prefix, "complete" end
        local following = tokens[stop + 1]
        local join = text:sub(tokens[stop].last + 1, following.first - 1)
        prefix = prefix:gsub("[.!?]+$", "")
        if following.key:match("^[.!?]$") then
            local punctuation = raw(stop + 1, finish)
            if punctuation:match("^[.!?]+$") then return prefix .. join .. punctuation, "complete" end
        end
        local tail, mode = neural(stop + 1, finish, tokens[start].key)
        if join == "" and (following.protected or not following.key:match("^%p$")) then join = " " end
        return prefix .. join .. tail, mode
    end

    local pieces, cursor, complete = {}, 1, true
    for _, range in ipairs(ranges) do
        local start, finish, opener = unpack(range)
        local value, mode
        if opener then
            value, mode = mixed(opener, finish)
            if opener > start then
                value = text:sub(tokens[start].first, tokens[opener].first - 1) .. value
            end
        elseif independent then
            local parsed, clause
            if grammarClause and not document.truncated and not document.ambiguities then
                parsed, clause = grammarClause(document, start, finish)
            end
            if parsed and not clause.unknownSpans and not engine.Acceptance.reject(facts, start, finish, parsed) then
                value, mode, rules = parsed, "complete", rules + 1
            else
                value, mode = neural(start, finish)
            end
        else
            value, mode = neural(start, finish)
        end
        local join = text:sub(cursor, tokens[start].first - 1)
        if independent and cursor > 1 and join == "" then join = " " end
        pieces[#pieces + 1] = join
        pieces[#pieces + 1] = value
        cursor = tokens[finish].last + 1
        complete = complete and mode == "complete"
        if independent and not complete then
            local result, status = translate(text)
            return result, status, calls + 1, rules
        end
    end
    pieces[#pieces + 1] = text:sub(cursor)
    local output = table.concat(pieces)
    if engine.Acceptance.reject(facts, 1, #tokens, output) then
        if independent then
            local result, status = translate(text)
            return result, status, calls + 1, rules
        end
        return text, "unchanged", calls, rules
    end
    return output, complete and "complete" or "partial", calls, rules
end


local function projectTransformer(matrix, index, vector, width)
    local values, scale = rowAt(matrix, index)
    local total = 0
    for j = 1,width,8 do
        total = total + values[j] * vector[j] + values[j + 1] * vector[j + 1]
            + values[j + 2] * vector[j + 2] + values[j + 3] * vector[j + 3]
            + values[j + 4] * vector[j + 4] + values[j + 5] * vector[j + 5]
            + values[j + 6] * vector[j + 6] + values[j + 7] * vector[j + 7]
    end
    return total * scale
end

local function linearSlice(matrix, vector, first, count, checkpoint)
    local result, width = {}, #vector
    for i = 1,count do
        result[i] = projectTransformer(matrix, first + i - 1, vector, width)
        if checkpoint and i % 8 == 0 then checkpoint() end
    end
    return result
end

local function sumInto(target, increment)
    for i = 1,#increment do target[i] = target[i] + increment[i] end
end

local function normalize(vector, parameters)
    local width, total = #vector, 0
    for i = 1,width do total = total + vector[i] end
    local mean, variance = total / width, 0
    for i = 1,width do
        local delta = vector[i] - mean
        variance = variance + delta * delta
    end
    local inv = 1 / math.sqrt(variance / width + .00001)
    local out, scale, bias = {}, parameters[1], parameters[2]
    for i = 1,width do out[i] = (vector[i] - mean) * inv * scale[i] + bias[i] end
    return out
end

local function keyValue(attention, vector, width, checkpoint)
    local keys, values, matrix = {}, {}, attention.qkv
    for i = 1,width do
        local keyRow, keyScale = rowAt(matrix, width + i)
        local valueRow, valueScale = rowAt(matrix, 2 * width + i)
        local keySum, valueSum = 0, 0
        for j = 1,#vector,8 do
            local x1, x2, x3, x4 = vector[j], vector[j + 1], vector[j + 2], vector[j + 3]
            local x5, x6, x7, x8 = vector[j + 4], vector[j + 5], vector[j + 6], vector[j + 7]
            keySum = keySum + keyRow[j] * x1 + keyRow[j + 1] * x2
                + keyRow[j + 2] * x3 + keyRow[j + 3] * x4 + keyRow[j + 4] * x5
                + keyRow[j + 5] * x6 + keyRow[j + 6] * x7 + keyRow[j + 7] * x8
            valueSum = valueSum + valueRow[j] * x1 + valueRow[j + 1] * x2
                + valueRow[j + 2] * x3 + valueRow[j + 3] * x4 + valueRow[j + 4] * x5
                + valueRow[j + 5] * x6 + valueRow[j + 6] * x7 + valueRow[j + 7] * x8
        end
        keys[i], values[i] = keySum * keyScale, valueSum * valueScale
        if checkpoint and i % 4 == 0 then checkpoint() end
    end
    return keys, values
end

local function mixedAttention(attention, query, keys, values, heads, checkpoint)
    local width, context = #query, {}
    local span = width / heads
    local inverse = 1 / math.sqrt(span)
    for head = 1,heads do
        local first, last = (head - 1) * span + 1, head * span
        local peak, weights = -math.huge, {}
        for i, key in ipairs(keys) do
            local value = 0
            for j = first,last do value = value + key[j] * query[j] end
            value = value * inverse
            weights[i] = value
            if value > peak then peak = value end
        end
        local total = 0
        for i, value in ipairs(weights) do
            weights[i] = exp(value - peak)
            total = total + weights[i]
        end
        for j = first,last do context[j] = 0 end
        for i, value in ipairs(values) do
            local weight = weights[i] / total
            for j = first,last do context[j] = context[j] + value[j] * weight end
        end
        if checkpoint then checkpoint() end
    end
    return linearSlice(attention.output, context, 1, width, checkpoint)
end

local function feedForward(layer, vector, width, checkpoint)
    local hidden = linearSlice(layer.feedIn, normalize(vector, layer.feedNorm), 1, width * 2, checkpoint)
    local indexes, activation = {}, {}
    local count = 0
    for j = 1,#hidden do
        if hidden[j] > 0 then
            count = count + 1
            indexes[count], activation[count] = j, hidden[j]
        end
    end
    for i = 1,width do
        local row, scale = rowAt(layer.feedOut, i)
        local total = 0
        for j = 1,count do total = total + row[indexes[j]] * activation[j] end
        vector[i] = vector[i] + total * scale
        if checkpoint and i % 8 == 0 then checkpoint() end
    end
end

local function transformerEncode(model, tokens, checkpoint)
    local network, width = model.transformer, model.width
    local encoded = {}
    for i, id in ipairs(tokens) do
        encoded[i] = embedding(model.source, id, width)
        sumInto(encoded[i], embedding(network.sourcePos, i, width))
    end
    for _, layer in ipairs(network.encoder) do
        local queries, keys, values = {}, {}, {}
        for i, vector in ipairs(encoded) do
            local input = normalize(vector, layer.selfNorm)
            queries[i] = linearSlice(layer.attention.qkv, input, 1, width, checkpoint)
            keys[i], values[i] = keyValue(layer.attention, input, width, checkpoint)
        end
        for i, vector in ipairs(encoded) do
            sumInto(vector, mixedAttention(layer.attention, queries[i], keys, values, network.heads, checkpoint))
            feedForward(layer, vector, width, checkpoint)
        end
    end
    for i, vector in ipairs(encoded) do encoded[i] = normalize(vector, network.sourceNorm) end
    return encoded, {position=0, cache={}}
end

local function transformerDecode(model, previous, encoded, state, checkpoint)
    local network, width = model.transformer, model.width
    local position = state.position + 1
    local vector = embedding(model.target, previous, width)
    sumInto(vector, embedding(network.targetPos, position, width))
    for i, layer in ipairs(network.decoder) do
        local cache = state.cache[i]
        if not cache then
            cache = {keys={}, values={}, crossKeys={}, crossValues={}}
            for j, row in ipairs(encoded) do
                cache.crossKeys[j], cache.crossValues[j] = keyValue(layer.crossAttention, row, width, checkpoint)
            end
            state.cache[i] = cache
        end
        local input = normalize(vector, layer.selfNorm)
        local query = linearSlice(layer.attention.qkv, input, 1, width, checkpoint)
        cache.keys[position], cache.values[position] = keyValue(layer.attention, input, width, checkpoint)
        sumInto(vector, mixedAttention(layer.attention, query, cache.keys, cache.values, network.heads, checkpoint))
        input = normalize(vector, layer.crossNorm)
        query = linearSlice(layer.crossAttention.qkv, input, 1, width, checkpoint)
        sumInto(vector, mixedAttention(layer.crossAttention, query, cache.crossKeys, cache.crossValues,
            network.heads, checkpoint))
        feedForward(layer, vector, width, checkpoint)
    end
    state.position = position
    return normalize(vector, network.targetNorm), state
end

local gruEncode, gruDecode, gruScore = M.encode, M.decode, M.score
function M.score(model, vector, index)
    if model.transformer then return projectTransformer(model.target, index, vector, model.width) + model.outputBias[index] end
    return gruScore(model, vector, index)
end
function M.encode(model, tokens, checkpoint)
    if model.transformer then return transformerEncode(model, tokens, checkpoint) end
    return gruEncode(model, tokens, checkpoint)
end
function M.decode(model, previous, encoded, state, checkpoint)
    if model.transformer then return transformerDecode(model, previous, encoded, state, checkpoint) end
    return gruDecode(model, previous, encoded, state, checkpoint)
end

return M
