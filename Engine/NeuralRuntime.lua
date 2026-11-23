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

return M
end)()

local beForms = {is=true, are=true, was=true, were=true, be=true}
local finderAction = {open=true, use=true, check=true, enable=true, disable=true}
local function finderReference(tokens, first)
    local before, after = tokens[first - 1], tokens[first + 1]
    return before and (beForms[before.key] or finderAction[before.key])
        or after and beForms[after.key]
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
local roleplayCue = keys("rp roleplay roleplaying ooc emote channel chat whisper speak talk")
local chatHeads = keys("chat chats")
local chatScopes = keys("general trade guild zone chat party raid")
local roleplayTail = keys("here now today tonight again too please only")
local roleplayOuterPreposition = keys("з із зі в у")

G.sourceMarkers, G.targetMarkers = {}, {}
for i = 1,3 do G.sourceMarkers[i] = char(7+i) end
for i = 1,6 do G.sourceMarkers[3+i] = char(10+i) end
for i = 1,3 do G.sourceMarkers[9+i] = char(47+i) end
for i = 1,3 do
    G.targetMarkers[i] = {}
    for f = 1,#names do G.targetMarkers[i][f] = char(17+(i-1)*#names+f) end
end

local function roleplayMode(tokens, first, last)
    local following = tokens[last + 1]
    if following and not (roleplayTail[following.key] or following.key:match("^%p$")) then return false end
    local preceding = tokens[first - 1]
    if preceding and (preceding.key == "from" or preceding.key == "with") then return false end
    for i = first - 1, math.max(1, first - 10), -1 do
        local token = tokens[i]
        if token.protected or token.key:match("^[.!?]$") then break end
        if roleplayCue[token.key] then return true end
    end
    return false
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
        local features = entry.features
        if not ((exact or plural) and features and not (features.verbatim or features.apposition)) then return false end
        if span.last == first then
            if features.englishDefinite and (prev == "a" or prev == "an") then return false end
            local properSpelling = first > 1 and raw == entry.en or prev == "the"
                or first == 1 and features.englishDefinite
            if not (features.proper and properSpelling and raw:match("^[A-Z]")) then return false end
        end
        -- Outside one sentence, the model can lose the surrounding context when a new term is masked.
        local sentenceBoundary = ns.Engine.Parser.sentenceBoundary
        for i = 1, #tokens - 1 do
            if sentenceBoundary(text, tokens, i) then return false end
        end
        return true
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
        if neuralSense == "layeredChat" then
            local head = tokens[first - 2]
            local modifier = tokens[first - 3]
            return exact and beForms[prev] and head and not head.protected and (chatHeads[head.key]
                or (head.key == "channel" or head.key == "channels") and modifier and chatScopes[modifier.key])
        end
        if neuralSense == "roleplayMode" then return exact and roleplayMode(tokens, first, span.last) end
        if neuralSense == "discourseMode" then return exact end
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
    ["inv"]={id="action.invite",category="actions",uk="запросити",canonicalSource="invite"},
    ["rez"]={id="action.resurrect",category="actions",uk="воскресити",canonicalSource="resurrect"},
    ["res"]={id="action.resurrect",category="actions",uk="воскресити",canonicalSource="resurrect"},
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
                result={id=entry.id,term=entry,last=last,manual=true,correctedSource=entry.canonicalSource}
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
    local corrected = ns.Engine.Morphology.classSpelling(tokens[first].key)
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
            local term = best.term
            local category = categories[term.category]
            if category == 9 or (term.category == "game" and term.englishPlural
                and not (term.features and term.features.neuralSense)) then
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
                local sense = term.features and term.features.neuralSense
                slots[slot] = {id=best.id, forms=f, raw=surface,
                    roleplayMode=sense == "roleplayMode",
                    keepInFallback=sense == "venue",
                    preferConstrained=category == 9 or best.term.category == "game"
                        or sense == "roleplayMode" or sense == "discourseMode" or sense == "layeredChat"
                        or best.manual and best.correctedSource ~= nil}
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
    local used, changes = {}, {}
    for first, key, after in text:gmatch("()(\238\132[\146-\175])()") do
        local idx = key:byte(3)-146
        local slot, form = math.floor(idx/#names)+1,idx%#names+1
        local entry = mapping[slot]
        local value = entry and entry.forms[form]
        if not value or used[slot] then return nil end
        used[slot]=true
        if entry.roleplayMode then
            -- This invariable adverbial already includes its Ukrainian preposition.
            local start, word = text:sub(1, first - 1):match("()([^%s]+)%s+$")
            if word and roleplayOuterPreposition[ns.Engine.Normalize.word(word)] then first = start end
        end
        changes[#changes+1] = {first=first,last=after-1,value=value}
    end
    if #changes ~= #mapping then return nil end
    text = edits(text, changes)
    if text:find("\238\132[\136-\178]") then return nil end
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

-- Matrix weights are signed; linked vocabulary IDs use unsigned bytes.
local signedBytes, unsignedBytes = {}, {}
for value = 0, 255 do
    unsignedBytes[value] = value
    signedBytes[value] = value < 128 and value or value - 256
end

local function decodeBytes(packed, bytes)
    bytes = bytes or unsignedBytes
    local row, index = {}, 1
    for start = 1, #packed, 5 do
        local a, b, c, d, e = packed:byte(start, start + 4)
        local value = (((digit[a] * 85 + digit[b]) * 85 + digit[c]) * 85 + digit[d]) * 85 + digit[e]
        row[index] = bytes[floor(value / 16777216)]
        row[index + 1] = bytes[floor(value / 65536) % 256]
        row[index + 2] = bytes[floor(value / 256) % 256]
        row[index + 3] = bytes[value % 256]
        index = index + 4
    end
    return row
end

local function rowAt(matrix, index)
    local row = matrix.rows[index]
    if not row then
        row = decodeBytes(matrix.packed[index], signedBytes)
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
    local numericPieces, numberSlotOrder
    if data.numberSlots then
        numericPieces = {}
        if #data.numberSlots == #Numbers.slots then
            numberSlotOrder = {}
            for slot, id in ipairs(data.numberSlots) do
                if data.targetPieces[id] ~= Numbers.slots[slot] then
                    numberSlotOrder = nil
                    break
                end
                numberSlotOrder[id] = slot
            end
        end
        for id, piece in ipairs(data.targetPieces) do
            if piece:find('[0-9]') then numericPieces[id] = true end
            -- A marker embedded in another piece or split across pieces needs the full restore check.
            if numberSlotOrder and not numberSlotOrder[id] and (piece:find("\238\132[\128-\131]")
                or piece:sub(-1) == "\238" or piece:sub(-2) == "\238\132") then
                numberSlotOrder = nil
            end
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
        numberSlots=data.numberSlots, numberSlotOrder=numberSlotOrder, numericPieces=numericPieces,
        termSlots=data.termSlots, itemSlots=data.itemSlots, moneySlots=data.moneySlots,
        maxPieces=data.transformer and math.min(128, #data.transformer.sourcePos.packed,
            #data.transformer.targetPos.packed) or MAX_PIECES,
        source=matrix(data.source), target=matrix(data.target), encoder=data.encoder and network(data.encoder),
        transformer=data.transformer and transformerNetwork(data.transformer, matrix),
        decoder=data.decoder and network(data.decoder), combine=data.combine and matrix(data.combine), combineBias=data.combineBias,
        outputBias=data.outputBias}
end

local function normalizeInput(text)
    text = text:gsub("’", "'"):gsub("‘", "'"):gsub("ʼ", "'"):gsub("[A-Z]", string.lower)
    return (text:gsub("^ +", ""):gsub(" +$", ""):gsub(" +", " "))
end

function M.tokenize(model, text, checkpoint, normalized)
    text = normalized or normalizeInput(text)
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

local decodedCacheLimit = 64

local function restoreDecoded(output, values, terms, opener, count)
    if output == nil then return nil, "target-length", count end
    if output == "" then return nil, "empty" end
    if values then
        local reason
        output, reason = Numbers.restore(output, values)
        if not output then return nil, reason, count end
    end
    if terms then
        output = Glossary.restore(ns, output, terms, opener)
        if not output then return nil, "term-slots", count end
    end
    return output, "complete", count
end

local function decodedKey(model, source, fullVocabulary, values, terms)
    local key = (fullVocabulary and "full:" or "short:") .. model.maxPieces .. ":" .. #source .. ":" .. source
    if values then key = key .. "!" .. #values end
    if terms then
        for slot, term in ipairs(terms) do
            local forms = {}
            for form in pairs(term.forms) do forms[#forms + 1] = model.termSlots[slot][form] end
            table.sort(forms)
            key = key .. "/" .. table.concat(forms, ",")
        end
    end
    return key
end

local function rememberDecoded(cache, key, output, count, failure)
    if cache.outputs[key] then return end
    local index = cache.next
    local evicted = cache.keys[index]
    if evicted then cache.outputs[evicted] = nil end
    cache.keys[index] = key
    cache.outputs[key] = {output=output, count=count, failure=failure}
    cache.next = index == decodedCacheLimit and 1 or index + 1
end

local bestTarget

local function hasSourceRepetition(text)
    for bytes = 1, 4 do
        if text:find("(" .. string.rep("[a-z]", bytes) .. ")%1%1") then return true end
    end
    local previous, repeated = nil, 0
    for word in text:gmatch("[a-z]+") do
        repeated = word == previous and repeated + 1 or 1
        if repeated == 3 then return true end
        previous = word
    end
    return false
end

local function translatePlain(model, text, checkpoint, fullVocabulary, requireComplete, opener, terms, prices)
    local sourceText, values = text, nil
    if terms then sourceText = terms.input end
    if model.numberSlots then
        local masked, mapping = Numbers.mask(sourceText, prices)
        if not masked then return nil, mapping end
        sourceText, values = masked, mapping
    elseif sourceText:find("[0-9]") then
        return nil, "number-slots-unavailable"
    end
    -- A cache hit can skip tokenization and restore the current message's numbers and terms.
    local normalized = normalizeInput(sourceText)
    local key = decodedKey(model, normalized, fullVocabulary, values, terms)
    local numberOrder = requireComplete and values and #values > 1 and model.numberSlotOrder
    if numberOrder then key = key .. ":ordered" end
    local cache = model.decodedCache
    local cached = cache and cache.outputs[key]
    if cached then
        if cached.failure then return nil, cached.failure, cached.count end
        return restoreDecoded(cached.output, values, terms, opener, cached.count)
    end
    local source = M.tokenize(model, sourceText, checkpoint, normalized)
    if #source < 2 or #source > model.maxPieces then return nil, "source-length" end
    for _, id in ipairs(source) do
        if id == UNK then return nil, "source-vocabulary" end
    end
    if not cache then
        cache = model.decodedCache or {outputs={}, keys={}, next=1}
        model.decodedCache = cache
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
    local nextNumber, repeated = 1, 1
    for _ = 1, model.maxPieces do
        local features
        features, state = M.decode(model, previous, encoded, state, checkpoint)
        local best = bestTarget(model, features, choices, checkpoint)
        if best == EOS then
            local output = table.concat(target):gsub("▁", " "):gsub("^ +", "")
            rememberDecoded(cache, key, output, #choices)
            return restoreDecoded(output, values, terms, opener, #choices)
        end
        local number = numberOrder and numberOrder[best]
        if number then
            if number ~= nextNumber then
                rememberDecoded(cache, key, nil, #choices, "number-slot-count")
                return nil, "number-slot-count", #choices
            end
            nextNumber = nextNumber + 1
        end
        local group = pending and pending[best]
        if group then
            for i=#choices,1,-1 do
                if group[choices[i]] then table.remove(choices,i) end
            end
        end
        local piece = model.targetPieces[best]
        repeated = best == previous and repeated + 1 or 1
        -- Identical Cyrillic pieces inside one word can trap an autoregressive decode.
        if repeated == 5 and #piece >= 4 and not piece:find("[^\208\209\128-\191]")
            and not hasSourceRepetition(normalized) then
            rememberDecoded(cache, key, nil, #choices, "target-repetition")
            return nil, "target-repetition", #choices
        end
        target[#target + 1], previous = piece, best
    end
    -- A decode that exhausts its limit also depends only on the masked input and candidates.
    rememberDecoded(cache, key, nil, #choices)
    return nil, "target-length", #choices
end

function M.hasVisibleCyrillic(text, split)
    for _, segment in ipairs(split(text)) do
        if not segment.protected and text:sub(segment.first, segment.last):find("[\208\209][\128-\191]") then
            return true
        end
    end
    return false
end

function M.withProtected(text, split, translate, requireComplete)
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
                if requireComplete then return nil, "partial", largest, calls end
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

local function translateWithPrices(model, text, checkpoint, fullVocabulary, requireComplete, opener, terms)
    local prices = model.moneySlots and Numbers.prices(terms and terms.input or text, opener)
    if prices then
        local result, mode, count = translatePlain(model, text, checkpoint, fullVocabulary,
            requireComplete, opener, terms, prices)
        if result then
            local digits = result:gmatch("%d+")
            local same = true
            for original in text:gmatch("%d+") do
                if digits() ~= original then same = false; break end
            end
            if same and not digits() then return result, mode, count end
        end
    end
    return translatePlain(model, text, checkpoint, fullVocabulary, requireComplete, opener, terms)
end

function M.translate(model, text, checkpoint, fullVocabulary, split, context, requireComplete)
    local function infer(fragment, opener)
        if not model.termSlots then
            return translateWithPrices(model, fragment, checkpoint, fullVocabulary, requireComplete)
        end
        local masked, terms, corrected = Glossary.mask(ns, fragment, opener, model.itemSlots)
        local function constrained()
            terms.input = masked
            local candidate, mode, count = translateWithPrices(model, fragment, checkpoint, fullVocabulary,
                requireComplete, opener, terms)
            if candidate and Glossary.target(ns, candidate, terms) then return candidate, mode, count end
        end
        local preferConstrained, requiredTerms
        for _, term in ipairs(terms or {}) do
            preferConstrained = preferConstrained or term.preferConstrained
            if term.keepInFallback then
                requiredTerms = requiredTerms or {}
                requiredTerms[#requiredTerms + 1] = term
            end
        end
        if preferConstrained then
            local candidate, mode, count = constrained()
            if candidate then return candidate, mode, count end
        end
        local ordinary, ordinaryMode, ordinaryCount = translateWithPrices(model, corrected or fragment,
            checkpoint, fullVocabulary, requireComplete, opener)
        if terms and not preferConstrained and (not ordinary or not Glossary.target(ns, ordinary, terms)) then
            local candidate, mode, count = constrained()
            if candidate then return candidate, mode, count end
        end
        if ordinary and requiredTerms and not Glossary.target(ns, ordinary, requiredTerms) then
            return nil, "term-slots"
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
    end, requireComplete)
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

local function independentChat(text, tokens, ranges, engine)
    if #ranges < 2 or #ranges > 6 or #tokens < 12 then return false end
    local parser = engine.Parser
    local twoSentences = #ranges == 2
    local minimumWords = twoSentences and 4 or 2
    local total, strongBoundary = 0, false
    for i, range in ipairs(ranges) do
        local first, last = range[1], range[2]
        local initial = tokens[first]
        if i > 1 and (clauseDependent[initial.key] or twoSentences and conditionalContinuation[initial.key]
            or not parser.startsWithCapital(text, initial)) then return false end
        if i < #ranges then
            local stop = tokens[last]
            if stop.key ~= "." and stop.key ~= "!" and stop.key ~= "?" then return false end
            local previousIndex = last - 1
            -- Adjacent question and exclamation marks can emphasize a single sentence ending.
            if stop.key ~= "." then
                strongBoundary = true
                while previousIndex >= first and tokens[previousIndex].key:match("^[!?]$")
                    and tokens[previousIndex].last + 1 == tokens[previousIndex + 1].first do
                    previousIndex = previousIndex - 1
                end
            end
            if previousIndex < first then return false end
            local previous = tokens[previousIndex]
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
        if count < minimumWords and not (i == 1 and count == 1
            and engine.ClauseAnalysis.guildHeadingWord(text, tokens, first, last)) then return false end
        if hasNumbers then
            local source = text:sub(tokens[first].first, tokens[last].last)
            if not Numbers.ranges(source, Numbers.prices(source)) then return false end
        end
        total = total + count
    end
    return total >= 21 or strongBoundary and total >= 10
end

local enchantmentOpenings = {free=true, selling=true, offering=true, last=true}
local clauseJoin = {["and"]=true, ["or"]=true, but=true}

local function enchantmentAdvertisement(engine, text, tokens, checkpoint)
    if not enchantmentOpenings[tokens[1].key]
        or not (text:find("..", 1, true) or text:find("…", 1, true)) then return end
    local parser = engine.Parser
    local ranges, first, i = {}, 1, 1
    while i < #tokens do
        local ending = parser.ellipsisEnd(tokens, i, #tokens)
        if not ending and tokens[i].key == "." and tokens[i + 1].key == "."
            and tokens[i].last + 1 == tokens[i + 1].first then ending = i + 1 end
        if ending then
            while ending < #tokens and tokens[ending + 1].key == "."
                and tokens[ending].last + 1 == tokens[ending + 1].first do
                ending = ending + 1
            end
            if ending == #tokens then break end
            local initial = tokens[ending + 1]
            if i <= first or #ranges == 5 or clauseJoin[initial.key] or clauseDependent[initial.key]
                or conditionalContinuation[initial.key] or not parser.startsWithCapital(text, initial) then return end
            ranges[#ranges + 1] = {first, i - 1}
            first, i = ending + 1, ending
        end
        i = i + 1
    end
    if #ranges == 0 then return end
    local document = engine.Morphology.analyze(text, tokens, "en-uk")
    document.checkpoint = checkpoint
    local output, tree = engine.Syntax.translateRange(document, 1, ranges[1][2])
    if not (output and tree.kind == "enhancement" and tree.features.offer == "enchanting"
        and tree.slots.count and tree.slots.stat) then return end
    ranges[#ranges + 1] = {first, #tokens}
    return ranges, document, output
end

local function contactCommand(tokens, first)
    local head, command = tokens[first], tokens[first + 1]
    return head.key == "whisper" or head.key == "/" and command
        and (command.key == "w" or command.key == "whisper") and command.first == head.last + 1
end

local dependentContactOpening = {when=true, once=true, because=true, although=true, whereas=true, provided=true}

local function contactBoundary(tokens, first)
    local stop, previous = tokens[first - 1], tokens[first - 2]
    if previous and contactCommand(tokens, first) and stop.key:match("^[.!?]$")
        and not previous.key:match("^[.!?]$") and previous.key ~= "…"
        and not (stop.key == "." and periodAbbreviation[previous.key]) then
        return first, first - 1
    end
    -- A conditional or temporal opening may need the contact command as its main clause.
    local opening = first
    while opening < #tokens and tokens[opening].protected do opening = opening + 1 end
    local key = tokens[opening].key
    if conditionalContinuation[key] or dependentContactOpening[key] then return end
    for i = #tokens - 1, math.max(first + 1, 2), -1 do
        local separator, before, after = tokens[i], tokens[i - 1], tokens[i + 1]
        if (separator.key == "—" or separator.key == "–" or separator.key == "-")
            and before.last + 1 < separator.first and separator.last + 1 < after.first
            and contactCommand(tokens, i + 1) then return i + 1, i - 1 end
    end
end

local function trailingContact(engine, text, tokens, first, grammarClause, checkpoint)
    local head = tokens[first]

    -- A protected heading can travel with the prefix; keep inline links and chat formatting in their existing route.
    local visible
    for _, token in ipairs(tokens) do
        if token.protected then
            if visible then return end
        else visible = true end
    end

    local tail = text:sub(head.first, tokens[#tokens].last)
    local words = engine.Tokenizer.scan(tail, engine.ClauseAnalysis.englishContractions)
    if not words then return end
    local document = engine.Morphology.analyze(tail, words, "en-uk")
    if document.truncated or document.ambiguities then return end
    document.checkpoint = checkpoint
    local translated, clause = grammarClause(document, 1, #words)
    -- A translated restriction can remain in the grammar fallback without splitting an unverified body.
    if clause and clause.imperative and not (clause.question or clause.unknownSpans or clause.attachedRestriction) then
        return translated
    end
end

function M.routeChat(ns, text, translate, checkpoint, tokens, facts, grammarClause, skipContact, requireComplete)
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
    local calls, rules = 0, 0
    if not (routed or known or skipContact) and grammarClause then
        local contact, prefixEnd = contactBoundary(tokens, first)
        local tail = contact and trailingContact(engine, text, tokens, contact, grammarClause, checkpoint)
        if tail then
            facts = facts or engine.Acceptance.measure(text, tokens, direction)
            if not engine.Acceptance.reject(facts, contact, #tokens, tail) then
                local boundary = tokens[prefixEnd].last
                local prefix = text:sub(1, boundary)
                local body, mode, attempts, bodyRules = M.routeChat(ns, prefix, translate, checkpoint,
                    nil, nil, grammarClause, true, requireComplete)
                if body and mode == "complete" and M.hasVisibleCyrillic(body, engine.Markup.split) then
                    if prefixEnd < contact - 1 and not tokens[prefixEnd].key:match("^[.!?]$") then
                        body = body:gsub("%.$", "")
                    end
                    local output = body .. text:sub(boundary + 1, tokens[contact].first - 1)
                        .. tail .. text:sub(tokens[#tokens].last + 1)
                    if not engine.Acceptance.reject(facts, 1, #tokens, output) then
                        return output, mode, attempts, bodyRules + 1
                    end
                end
                calls = attempts
            end
        end
    end
    local advertisement, document, firstOffer
    if not (routed or known) then
        advertisement, document, firstOffer = enchantmentAdvertisement(engine, text, tokens, checkpoint)
        if advertisement then ranges = advertisement end
    end
    local independent = advertisement ~= nil or not (routed or known) and independentChat(text, tokens, ranges, engine)
    if not (routed or known or independent) then
        local result, mode = translate(text)
        return result, mode, calls + 1, 0
    end

    document = document or engine.Morphology.analyze(text, tokens, direction)
    document.checkpoint = checkpoint
    facts = facts or engine.Acceptance.measure(text, tokens, direction)
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
            if advertisement then parsed = start == 1 and firstOffer or rule(start, finish) end
            if not parsed and grammarClause and not document.truncated and not document.ambiguities then
                parsed, clause = grammarClause(document, start, finish)
            end
            if parsed and not (clause and clause.unknownSpans) and not engine.Acceptance.reject(facts, start, finish, parsed) then
                value, mode, rules = parsed, "complete", rules + 1
            else
                value, mode = neural(start, finish)
            end
        else
            value, mode = neural(start, finish)
        end
        local join = text:sub(cursor, tokens[start].first - 1)
        if cursor > 1 then
            if advertisement then join = join:match("^%s*(.-)%s*$") .. " "
            elseif independent and join == "" then join = " " end
        end
        pieces[#pieces + 1] = join
        pieces[#pieces + 1] = advertisement and finish < #tokens and value:gsub("[.!]+$", "") or value
        cursor = tokens[finish].last + 1
        complete = complete and mode == "complete"
        if independent and not complete then
            local result, status = translate(text)
            return result, status, calls + 1, rules
        end
        if requireComplete and not complete then return nil, "partial", calls, rules end
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
    local last = width - width % 16
    for j = 1, last, 16 do
        total = total + values[j] * vector[j] + values[j + 1] * vector[j + 1]
            + values[j + 2] * vector[j + 2] + values[j + 3] * vector[j + 3]
            + values[j + 4] * vector[j + 4] + values[j + 5] * vector[j + 5]
            + values[j + 6] * vector[j + 6] + values[j + 7] * vector[j + 7]
            + values[j + 8] * vector[j + 8] + values[j + 9] * vector[j + 9]
            + values[j + 10] * vector[j + 10] + values[j + 11] * vector[j + 11]
            + values[j + 12] * vector[j + 12] + values[j + 13] * vector[j + 13]
            + values[j + 14] * vector[j + 14] + values[j + 15] * vector[j + 15]
    end
    for j = last + 1, width do total = total + values[j] * vector[j] end
    return total * scale
end

-- Reuse each input block while preserving the addition order within each dot product.
local function projectFour(matrix, first, second, third, fourth, vector, width)
    local firstRow, firstScale = rowAt(matrix, first)
    local secondRow, secondScale = rowAt(matrix, second)
    local thirdRow, thirdScale = rowAt(matrix, third)
    local fourthRow, fourthScale = rowAt(matrix, fourth)
    local firstSum, secondSum, thirdSum, fourthSum = 0, 0, 0, 0
    -- Constant indexes avoid loop arithmetic at the deployed model width.
    -- Keep the additions in the same order as the general path.
    if width == 128 then
        do
            local x0, x1, x2, x3 = vector[1], vector[2], vector[3], vector[4]
            local x4, x5, x6, x7 = vector[5], vector[6], vector[7], vector[8]
            firstSum = firstSum + firstRow[1] * x0 + firstRow[2] * x1 + firstRow[3] * x2 + firstRow[4] * x3
                + firstRow[5] * x4 + firstRow[6] * x5 + firstRow[7] * x6 + firstRow[8] * x7
            secondSum = secondSum + secondRow[1] * x0 + secondRow[2] * x1 + secondRow[3] * x2 + secondRow[4] * x3
                + secondRow[5] * x4 + secondRow[6] * x5 + secondRow[7] * x6 + secondRow[8] * x7
            thirdSum = thirdSum + thirdRow[1] * x0 + thirdRow[2] * x1 + thirdRow[3] * x2 + thirdRow[4] * x3
                + thirdRow[5] * x4 + thirdRow[6] * x5 + thirdRow[7] * x6 + thirdRow[8] * x7
            fourthSum = fourthSum + fourthRow[1] * x0 + fourthRow[2] * x1 + fourthRow[3] * x2 + fourthRow[4] * x3
                + fourthRow[5] * x4 + fourthRow[6] * x5 + fourthRow[7] * x6 + fourthRow[8] * x7
        end
        do
            local x0, x1, x2, x3 = vector[9], vector[10], vector[11], vector[12]
            local x4, x5, x6, x7 = vector[13], vector[14], vector[15], vector[16]
            firstSum = firstSum + firstRow[9] * x0 + firstRow[10] * x1 + firstRow[11] * x2 + firstRow[12] * x3
                + firstRow[13] * x4 + firstRow[14] * x5 + firstRow[15] * x6 + firstRow[16] * x7
            secondSum = secondSum + secondRow[9] * x0 + secondRow[10] * x1 + secondRow[11] * x2 + secondRow[12] * x3
                + secondRow[13] * x4 + secondRow[14] * x5 + secondRow[15] * x6 + secondRow[16] * x7
            thirdSum = thirdSum + thirdRow[9] * x0 + thirdRow[10] * x1 + thirdRow[11] * x2 + thirdRow[12] * x3
                + thirdRow[13] * x4 + thirdRow[14] * x5 + thirdRow[15] * x6 + thirdRow[16] * x7
            fourthSum = fourthSum + fourthRow[9] * x0 + fourthRow[10] * x1 + fourthRow[11] * x2 + fourthRow[12] * x3
                + fourthRow[13] * x4 + fourthRow[14] * x5 + fourthRow[15] * x6 + fourthRow[16] * x7
        end
        do
            local x0, x1, x2, x3 = vector[17], vector[18], vector[19], vector[20]
            local x4, x5, x6, x7 = vector[21], vector[22], vector[23], vector[24]
            firstSum = firstSum + firstRow[17] * x0 + firstRow[18] * x1 + firstRow[19] * x2 + firstRow[20] * x3
                + firstRow[21] * x4 + firstRow[22] * x5 + firstRow[23] * x6 + firstRow[24] * x7
            secondSum = secondSum + secondRow[17] * x0 + secondRow[18] * x1 + secondRow[19] * x2 + secondRow[20] * x3
                + secondRow[21] * x4 + secondRow[22] * x5 + secondRow[23] * x6 + secondRow[24] * x7
            thirdSum = thirdSum + thirdRow[17] * x0 + thirdRow[18] * x1 + thirdRow[19] * x2 + thirdRow[20] * x3
                + thirdRow[21] * x4 + thirdRow[22] * x5 + thirdRow[23] * x6 + thirdRow[24] * x7
            fourthSum = fourthSum + fourthRow[17] * x0 + fourthRow[18] * x1 + fourthRow[19] * x2 + fourthRow[20] * x3
                + fourthRow[21] * x4 + fourthRow[22] * x5 + fourthRow[23] * x6 + fourthRow[24] * x7
        end
        do
            local x0, x1, x2, x3 = vector[25], vector[26], vector[27], vector[28]
            local x4, x5, x6, x7 = vector[29], vector[30], vector[31], vector[32]
            firstSum = firstSum + firstRow[25] * x0 + firstRow[26] * x1 + firstRow[27] * x2 + firstRow[28] * x3
                + firstRow[29] * x4 + firstRow[30] * x5 + firstRow[31] * x6 + firstRow[32] * x7
            secondSum = secondSum + secondRow[25] * x0 + secondRow[26] * x1 + secondRow[27] * x2 + secondRow[28] * x3
                + secondRow[29] * x4 + secondRow[30] * x5 + secondRow[31] * x6 + secondRow[32] * x7
            thirdSum = thirdSum + thirdRow[25] * x0 + thirdRow[26] * x1 + thirdRow[27] * x2 + thirdRow[28] * x3
                + thirdRow[29] * x4 + thirdRow[30] * x5 + thirdRow[31] * x6 + thirdRow[32] * x7
            fourthSum = fourthSum + fourthRow[25] * x0 + fourthRow[26] * x1 + fourthRow[27] * x2 + fourthRow[28] * x3
                + fourthRow[29] * x4 + fourthRow[30] * x5 + fourthRow[31] * x6 + fourthRow[32] * x7
        end
        do
            local x0, x1, x2, x3 = vector[33], vector[34], vector[35], vector[36]
            local x4, x5, x6, x7 = vector[37], vector[38], vector[39], vector[40]
            firstSum = firstSum + firstRow[33] * x0 + firstRow[34] * x1 + firstRow[35] * x2 + firstRow[36] * x3
                + firstRow[37] * x4 + firstRow[38] * x5 + firstRow[39] * x6 + firstRow[40] * x7
            secondSum = secondSum + secondRow[33] * x0 + secondRow[34] * x1 + secondRow[35] * x2 + secondRow[36] * x3
                + secondRow[37] * x4 + secondRow[38] * x5 + secondRow[39] * x6 + secondRow[40] * x7
            thirdSum = thirdSum + thirdRow[33] * x0 + thirdRow[34] * x1 + thirdRow[35] * x2 + thirdRow[36] * x3
                + thirdRow[37] * x4 + thirdRow[38] * x5 + thirdRow[39] * x6 + thirdRow[40] * x7
            fourthSum = fourthSum + fourthRow[33] * x0 + fourthRow[34] * x1 + fourthRow[35] * x2 + fourthRow[36] * x3
                + fourthRow[37] * x4 + fourthRow[38] * x5 + fourthRow[39] * x6 + fourthRow[40] * x7
        end
        do
            local x0, x1, x2, x3 = vector[41], vector[42], vector[43], vector[44]
            local x4, x5, x6, x7 = vector[45], vector[46], vector[47], vector[48]
            firstSum = firstSum + firstRow[41] * x0 + firstRow[42] * x1 + firstRow[43] * x2 + firstRow[44] * x3
                + firstRow[45] * x4 + firstRow[46] * x5 + firstRow[47] * x6 + firstRow[48] * x7
            secondSum = secondSum + secondRow[41] * x0 + secondRow[42] * x1 + secondRow[43] * x2 + secondRow[44] * x3
                + secondRow[45] * x4 + secondRow[46] * x5 + secondRow[47] * x6 + secondRow[48] * x7
            thirdSum = thirdSum + thirdRow[41] * x0 + thirdRow[42] * x1 + thirdRow[43] * x2 + thirdRow[44] * x3
                + thirdRow[45] * x4 + thirdRow[46] * x5 + thirdRow[47] * x6 + thirdRow[48] * x7
            fourthSum = fourthSum + fourthRow[41] * x0 + fourthRow[42] * x1 + fourthRow[43] * x2 + fourthRow[44] * x3
                + fourthRow[45] * x4 + fourthRow[46] * x5 + fourthRow[47] * x6 + fourthRow[48] * x7
        end
        do
            local x0, x1, x2, x3 = vector[49], vector[50], vector[51], vector[52]
            local x4, x5, x6, x7 = vector[53], vector[54], vector[55], vector[56]
            firstSum = firstSum + firstRow[49] * x0 + firstRow[50] * x1 + firstRow[51] * x2 + firstRow[52] * x3
                + firstRow[53] * x4 + firstRow[54] * x5 + firstRow[55] * x6 + firstRow[56] * x7
            secondSum = secondSum + secondRow[49] * x0 + secondRow[50] * x1 + secondRow[51] * x2 + secondRow[52] * x3
                + secondRow[53] * x4 + secondRow[54] * x5 + secondRow[55] * x6 + secondRow[56] * x7
            thirdSum = thirdSum + thirdRow[49] * x0 + thirdRow[50] * x1 + thirdRow[51] * x2 + thirdRow[52] * x3
                + thirdRow[53] * x4 + thirdRow[54] * x5 + thirdRow[55] * x6 + thirdRow[56] * x7
            fourthSum = fourthSum + fourthRow[49] * x0 + fourthRow[50] * x1 + fourthRow[51] * x2 + fourthRow[52] * x3
                + fourthRow[53] * x4 + fourthRow[54] * x5 + fourthRow[55] * x6 + fourthRow[56] * x7
        end
        do
            local x0, x1, x2, x3 = vector[57], vector[58], vector[59], vector[60]
            local x4, x5, x6, x7 = vector[61], vector[62], vector[63], vector[64]
            firstSum = firstSum + firstRow[57] * x0 + firstRow[58] * x1 + firstRow[59] * x2 + firstRow[60] * x3
                + firstRow[61] * x4 + firstRow[62] * x5 + firstRow[63] * x6 + firstRow[64] * x7
            secondSum = secondSum + secondRow[57] * x0 + secondRow[58] * x1 + secondRow[59] * x2 + secondRow[60] * x3
                + secondRow[61] * x4 + secondRow[62] * x5 + secondRow[63] * x6 + secondRow[64] * x7
            thirdSum = thirdSum + thirdRow[57] * x0 + thirdRow[58] * x1 + thirdRow[59] * x2 + thirdRow[60] * x3
                + thirdRow[61] * x4 + thirdRow[62] * x5 + thirdRow[63] * x6 + thirdRow[64] * x7
            fourthSum = fourthSum + fourthRow[57] * x0 + fourthRow[58] * x1 + fourthRow[59] * x2 + fourthRow[60] * x3
                + fourthRow[61] * x4 + fourthRow[62] * x5 + fourthRow[63] * x6 + fourthRow[64] * x7
        end
        do
            local x0, x1, x2, x3 = vector[65], vector[66], vector[67], vector[68]
            local x4, x5, x6, x7 = vector[69], vector[70], vector[71], vector[72]
            firstSum = firstSum + firstRow[65] * x0 + firstRow[66] * x1 + firstRow[67] * x2 + firstRow[68] * x3
                + firstRow[69] * x4 + firstRow[70] * x5 + firstRow[71] * x6 + firstRow[72] * x7
            secondSum = secondSum + secondRow[65] * x0 + secondRow[66] * x1 + secondRow[67] * x2 + secondRow[68] * x3
                + secondRow[69] * x4 + secondRow[70] * x5 + secondRow[71] * x6 + secondRow[72] * x7
            thirdSum = thirdSum + thirdRow[65] * x0 + thirdRow[66] * x1 + thirdRow[67] * x2 + thirdRow[68] * x3
                + thirdRow[69] * x4 + thirdRow[70] * x5 + thirdRow[71] * x6 + thirdRow[72] * x7
            fourthSum = fourthSum + fourthRow[65] * x0 + fourthRow[66] * x1 + fourthRow[67] * x2 + fourthRow[68] * x3
                + fourthRow[69] * x4 + fourthRow[70] * x5 + fourthRow[71] * x6 + fourthRow[72] * x7
        end
        do
            local x0, x1, x2, x3 = vector[73], vector[74], vector[75], vector[76]
            local x4, x5, x6, x7 = vector[77], vector[78], vector[79], vector[80]
            firstSum = firstSum + firstRow[73] * x0 + firstRow[74] * x1 + firstRow[75] * x2 + firstRow[76] * x3
                + firstRow[77] * x4 + firstRow[78] * x5 + firstRow[79] * x6 + firstRow[80] * x7
            secondSum = secondSum + secondRow[73] * x0 + secondRow[74] * x1 + secondRow[75] * x2 + secondRow[76] * x3
                + secondRow[77] * x4 + secondRow[78] * x5 + secondRow[79] * x6 + secondRow[80] * x7
            thirdSum = thirdSum + thirdRow[73] * x0 + thirdRow[74] * x1 + thirdRow[75] * x2 + thirdRow[76] * x3
                + thirdRow[77] * x4 + thirdRow[78] * x5 + thirdRow[79] * x6 + thirdRow[80] * x7
            fourthSum = fourthSum + fourthRow[73] * x0 + fourthRow[74] * x1 + fourthRow[75] * x2 + fourthRow[76] * x3
                + fourthRow[77] * x4 + fourthRow[78] * x5 + fourthRow[79] * x6 + fourthRow[80] * x7
        end
        do
            local x0, x1, x2, x3 = vector[81], vector[82], vector[83], vector[84]
            local x4, x5, x6, x7 = vector[85], vector[86], vector[87], vector[88]
            firstSum = firstSum + firstRow[81] * x0 + firstRow[82] * x1 + firstRow[83] * x2 + firstRow[84] * x3
                + firstRow[85] * x4 + firstRow[86] * x5 + firstRow[87] * x6 + firstRow[88] * x7
            secondSum = secondSum + secondRow[81] * x0 + secondRow[82] * x1 + secondRow[83] * x2 + secondRow[84] * x3
                + secondRow[85] * x4 + secondRow[86] * x5 + secondRow[87] * x6 + secondRow[88] * x7
            thirdSum = thirdSum + thirdRow[81] * x0 + thirdRow[82] * x1 + thirdRow[83] * x2 + thirdRow[84] * x3
                + thirdRow[85] * x4 + thirdRow[86] * x5 + thirdRow[87] * x6 + thirdRow[88] * x7
            fourthSum = fourthSum + fourthRow[81] * x0 + fourthRow[82] * x1 + fourthRow[83] * x2 + fourthRow[84] * x3
                + fourthRow[85] * x4 + fourthRow[86] * x5 + fourthRow[87] * x6 + fourthRow[88] * x7
        end
        do
            local x0, x1, x2, x3 = vector[89], vector[90], vector[91], vector[92]
            local x4, x5, x6, x7 = vector[93], vector[94], vector[95], vector[96]
            firstSum = firstSum + firstRow[89] * x0 + firstRow[90] * x1 + firstRow[91] * x2 + firstRow[92] * x3
                + firstRow[93] * x4 + firstRow[94] * x5 + firstRow[95] * x6 + firstRow[96] * x7
            secondSum = secondSum + secondRow[89] * x0 + secondRow[90] * x1 + secondRow[91] * x2 + secondRow[92] * x3
                + secondRow[93] * x4 + secondRow[94] * x5 + secondRow[95] * x6 + secondRow[96] * x7
            thirdSum = thirdSum + thirdRow[89] * x0 + thirdRow[90] * x1 + thirdRow[91] * x2 + thirdRow[92] * x3
                + thirdRow[93] * x4 + thirdRow[94] * x5 + thirdRow[95] * x6 + thirdRow[96] * x7
            fourthSum = fourthSum + fourthRow[89] * x0 + fourthRow[90] * x1 + fourthRow[91] * x2 + fourthRow[92] * x3
                + fourthRow[93] * x4 + fourthRow[94] * x5 + fourthRow[95] * x6 + fourthRow[96] * x7
        end
        do
            local x0, x1, x2, x3 = vector[97], vector[98], vector[99], vector[100]
            local x4, x5, x6, x7 = vector[101], vector[102], vector[103], vector[104]
            firstSum = firstSum + firstRow[97] * x0 + firstRow[98] * x1 + firstRow[99] * x2 + firstRow[100] * x3
                + firstRow[101] * x4 + firstRow[102] * x5 + firstRow[103] * x6 + firstRow[104] * x7
            secondSum = secondSum + secondRow[97] * x0 + secondRow[98] * x1 + secondRow[99] * x2 + secondRow[100] * x3
                + secondRow[101] * x4 + secondRow[102] * x5 + secondRow[103] * x6 + secondRow[104] * x7
            thirdSum = thirdSum + thirdRow[97] * x0 + thirdRow[98] * x1 + thirdRow[99] * x2 + thirdRow[100] * x3
                + thirdRow[101] * x4 + thirdRow[102] * x5 + thirdRow[103] * x6 + thirdRow[104] * x7
            fourthSum = fourthSum + fourthRow[97] * x0 + fourthRow[98] * x1 + fourthRow[99] * x2 + fourthRow[100] * x3
                + fourthRow[101] * x4 + fourthRow[102] * x5 + fourthRow[103] * x6 + fourthRow[104] * x7
        end
        do
            local x0, x1, x2, x3 = vector[105], vector[106], vector[107], vector[108]
            local x4, x5, x6, x7 = vector[109], vector[110], vector[111], vector[112]
            firstSum = firstSum + firstRow[105] * x0 + firstRow[106] * x1 + firstRow[107] * x2 + firstRow[108] * x3
                + firstRow[109] * x4 + firstRow[110] * x5 + firstRow[111] * x6 + firstRow[112] * x7
            secondSum = secondSum + secondRow[105] * x0 + secondRow[106] * x1 + secondRow[107] * x2 + secondRow[108] * x3
                + secondRow[109] * x4 + secondRow[110] * x5 + secondRow[111] * x6 + secondRow[112] * x7
            thirdSum = thirdSum + thirdRow[105] * x0 + thirdRow[106] * x1 + thirdRow[107] * x2 + thirdRow[108] * x3
                + thirdRow[109] * x4 + thirdRow[110] * x5 + thirdRow[111] * x6 + thirdRow[112] * x7
            fourthSum = fourthSum + fourthRow[105] * x0 + fourthRow[106] * x1 + fourthRow[107] * x2 + fourthRow[108] * x3
                + fourthRow[109] * x4 + fourthRow[110] * x5 + fourthRow[111] * x6 + fourthRow[112] * x7
        end
        do
            local x0, x1, x2, x3 = vector[113], vector[114], vector[115], vector[116]
            local x4, x5, x6, x7 = vector[117], vector[118], vector[119], vector[120]
            firstSum = firstSum + firstRow[113] * x0 + firstRow[114] * x1 + firstRow[115] * x2 + firstRow[116] * x3
                + firstRow[117] * x4 + firstRow[118] * x5 + firstRow[119] * x6 + firstRow[120] * x7
            secondSum = secondSum + secondRow[113] * x0 + secondRow[114] * x1 + secondRow[115] * x2 + secondRow[116] * x3
                + secondRow[117] * x4 + secondRow[118] * x5 + secondRow[119] * x6 + secondRow[120] * x7
            thirdSum = thirdSum + thirdRow[113] * x0 + thirdRow[114] * x1 + thirdRow[115] * x2 + thirdRow[116] * x3
                + thirdRow[117] * x4 + thirdRow[118] * x5 + thirdRow[119] * x6 + thirdRow[120] * x7
            fourthSum = fourthSum + fourthRow[113] * x0 + fourthRow[114] * x1 + fourthRow[115] * x2 + fourthRow[116] * x3
                + fourthRow[117] * x4 + fourthRow[118] * x5 + fourthRow[119] * x6 + fourthRow[120] * x7
        end
        do
            local x0, x1, x2, x3 = vector[121], vector[122], vector[123], vector[124]
            local x4, x5, x6, x7 = vector[125], vector[126], vector[127], vector[128]
            firstSum = firstSum + firstRow[121] * x0 + firstRow[122] * x1 + firstRow[123] * x2 + firstRow[124] * x3
                + firstRow[125] * x4 + firstRow[126] * x5 + firstRow[127] * x6 + firstRow[128] * x7
            secondSum = secondSum + secondRow[121] * x0 + secondRow[122] * x1 + secondRow[123] * x2 + secondRow[124] * x3
                + secondRow[125] * x4 + secondRow[126] * x5 + secondRow[127] * x6 + secondRow[128] * x7
            thirdSum = thirdSum + thirdRow[121] * x0 + thirdRow[122] * x1 + thirdRow[123] * x2 + thirdRow[124] * x3
                + thirdRow[125] * x4 + thirdRow[126] * x5 + thirdRow[127] * x6 + thirdRow[128] * x7
            fourthSum = fourthSum + fourthRow[121] * x0 + fourthRow[122] * x1 + fourthRow[123] * x2 + fourthRow[124] * x3
                + fourthRow[125] * x4 + fourthRow[126] * x5 + fourthRow[127] * x6 + fourthRow[128] * x7
        end
        return firstSum * firstScale, secondSum * secondScale, thirdSum * thirdScale, fourthSum * fourthScale
    end
    for j = 1, width, 8 do
        local j1, j2, j3, j4 = j + 1, j + 2, j + 3, j + 4
        local j5, j6, j7 = j + 5, j + 6, j + 7
        local x0, x1, x2, x3 = vector[j], vector[j1], vector[j2], vector[j3]
        local x4, x5, x6, x7 = vector[j4], vector[j5], vector[j6], vector[j7]
        firstSum = firstSum + firstRow[j] * x0 + firstRow[j1] * x1 + firstRow[j2] * x2 + firstRow[j3] * x3
            + firstRow[j4] * x4 + firstRow[j5] * x5 + firstRow[j6] * x6 + firstRow[j7] * x7
        secondSum = secondSum + secondRow[j] * x0 + secondRow[j1] * x1 + secondRow[j2] * x2 + secondRow[j3] * x3
            + secondRow[j4] * x4 + secondRow[j5] * x5 + secondRow[j6] * x6 + secondRow[j7] * x7
        thirdSum = thirdSum + thirdRow[j] * x0 + thirdRow[j1] * x1 + thirdRow[j2] * x2 + thirdRow[j3] * x3
            + thirdRow[j4] * x4 + thirdRow[j5] * x5 + thirdRow[j6] * x6 + thirdRow[j7] * x7
        fourthSum = fourthSum + fourthRow[j] * x0 + fourthRow[j1] * x1 + fourthRow[j2] * x2 + fourthRow[j3] * x3
            + fourthRow[j4] * x4 + fourthRow[j5] * x5 + fourthRow[j6] * x6 + fourthRow[j7] * x7
    end
    return firstSum * firstScale, secondSum * secondScale, thirdSum * thirdScale, fourthSum * fourthScale
end

local function linearSlice(matrix, vector, first, count, checkpoint, result)
    local width = #vector
    result = result or {}
    local grouped = width % 8 == 0 and count - count % 4 or 0
    for i = 1, grouped, 4 do
        local row = first + i - 1
        result[i], result[i + 1], result[i + 2], result[i + 3] =
            projectFour(matrix, row, row + 1, row + 2, row + 3, vector, width)
        if checkpoint and i % 8 == 5 then checkpoint() end
    end
    for i = grouped + 1, count do
        result[i] = projectTransformer(matrix, first + i - 1, vector, width)
        if checkpoint and i % 8 == 0 then checkpoint() end
    end
    return result
end

local function normalize(vector, parameters, out)
    local width, total = #vector, 0
    for i = 1,width do total = total + vector[i] end
    local mean, variance = total / width, 0
    for i = 1,width do
        local delta = vector[i] - mean
        variance = variance + delta * delta
    end
    local inv = 1 / math.sqrt(variance / width + .00001)
    out = out or {}
    local scale, bias = parameters[1], parameters[2]
    for i = 1,width do out[i] = (vector[i] - mean) * inv * scale[i] + bias[i] end
    return out
end

local function keyValue(attention, vector, width, checkpoint)
    local matrix = attention.qkv
    return linearSlice(matrix, vector, width + 1, width, checkpoint),
        linearSlice(matrix, vector, 2 * width + 1, width, checkpoint)
end

local function queryKeyValue(attention, vector, width, checkpoint, queries)
    local matrix = attention.qkv
    return linearSlice(matrix, vector, 1, width, checkpoint, queries),
        linearSlice(matrix, vector, width + 1, width, checkpoint),
        linearSlice(matrix, vector, 2 * width + 1, width, checkpoint)
end

local function addAttention(vector, attention, query, keys, values, heads, checkpoint, scratch)
    local width, context, weights = #query, scratch.context, scratch.weights
    local span = width / heads
    local inverse = 1 / math.sqrt(span)
    for head = 1,heads do
        local first, last = (head - 1) * span + 1, head * span
        local peak = -math.huge
        for i, key in ipairs(keys) do
            local value = 0
            for j = first,last do value = value + key[j] * query[j] end
            value = value * inverse
            weights[i] = value
            if value > peak then peak = value end
        end
        local total = 0
        for i = 1, #keys do
            weights[i] = exp(weights[i] - peak)
            total = total + weights[i]
        end
        for j = first,last do context[j] = 0 end
        for i, value in ipairs(values) do
            local weight = weights[i] / total
            for j = first,last do context[j] = context[j] + value[j] * weight end
        end
        if checkpoint then checkpoint() end
    end
    local grouped = width % 8 == 0 and width - width % 4 or 0
    for i = 1, grouped, 4 do
        local a, b, c, d = projectFour(attention.output, i, i + 1, i + 2, i + 3, context, width)
        vector[i], vector[i + 1] = vector[i] + a, vector[i + 1] + b
        vector[i + 2], vector[i + 3] = vector[i + 2] + c, vector[i + 3] + d
        if checkpoint and i % 8 == 5 then checkpoint() end
    end
    for i = grouped + 1, width do
        vector[i] = vector[i] + projectTransformer(attention.output, i, context, width)
        if checkpoint and i % 8 == 0 then checkpoint() end
    end
end

local function feedForward(layer, vector, width, checkpoint, scratch)
    local input = normalize(vector, layer.feedNorm, scratch.normalized)
    local hidden = linearSlice(layer.feedIn, input, 1, width * 2, checkpoint, scratch.hidden)
    -- Pack active values into the already visited part of hidden.
    local indexes = scratch.indexes
    local count = 0
    for j = 1,#hidden do
        local value = hidden[j]
        if value > 0 then
            count = count + 1
            indexes[count], hidden[count] = j, value
        end
    end
    local last = count - count % 4
    -- Share the active indexes and values across two output rows.
    local paired = width - width % 2
    for i = 1, paired, 2 do
        local leftRow, leftScale = rowAt(layer.feedOut, i)
        local rightRow, rightScale = rowAt(layer.feedOut, i + 1)
        local left, right = 0, 0
        for j = 1, last, 4 do
            local a, b, c, d = indexes[j], indexes[j + 1], indexes[j + 2], indexes[j + 3]
            local x, y, z, w = hidden[j], hidden[j + 1], hidden[j + 2], hidden[j + 3]
            left = left + leftRow[a] * x + leftRow[b] * y + leftRow[c] * z + leftRow[d] * w
            right = right + rightRow[a] * x + rightRow[b] * y + rightRow[c] * z + rightRow[d] * w
        end
        for j = last + 1, count do
            local k, value = indexes[j], hidden[j]
            left, right = left + leftRow[k] * value, right + rightRow[k] * value
        end
        vector[i], vector[i + 1] = vector[i] + left * leftScale, vector[i + 1] + right * rightScale
        if checkpoint and i % 8 == 7 then checkpoint() end
    end
    if paired < width then
        local row, scale = rowAt(layer.feedOut, width)
        local total = 0
        for j = 1, count do total = total + row[indexes[j]] * hidden[j] end
        vector[width] = vector[width] + total * scale
    end
end

local function positionalEmbedding(tokens, id, positions, position, width)
    local token, tokenScale = rowAt(tokens, id)
    local offset, offsetScale = rowAt(positions, position)
    local result = {}
    for i = 1, width do result[i] = token[i] * tokenScale + offset[i] * offsetScale end
    return result
end

local function transformerEncode(model, tokens, checkpoint)
    local network, width = model.transformer, model.width
    local encoded = {}
    local scratch = {normalized={}, query={}, context={}, weights={}, hidden={}, indexes={}}
    for i, id in ipairs(tokens) do
        encoded[i] = positionalEmbedding(model.source, id, network.sourcePos, i, width)
    end
    for _, layer in ipairs(network.encoder) do
        local queries, keys, values = {}, {}, {}
        for i, vector in ipairs(encoded) do
            local input = normalize(vector, layer.selfNorm, scratch.normalized)
            queries[i], keys[i], values[i] = queryKeyValue(layer.attention, input, width, checkpoint)
        end
        for i, vector in ipairs(encoded) do
            addAttention(vector, layer.attention, queries[i], keys, values, network.heads, checkpoint, scratch)
            feedForward(layer, vector, width, checkpoint, scratch)
        end
    end
    for i, vector in ipairs(encoded) do encoded[i] = normalize(vector, network.sourceNorm) end
    return encoded, {position=0, cache={}, scratch=scratch}
end

local function transformerDecode(model, previous, encoded, state, checkpoint)
    local network, width = model.transformer, model.width
    local position, scratch = state.position + 1, state.scratch
    local vector = positionalEmbedding(model.target, previous, network.targetPos, position, width)
    for i, layer in ipairs(network.decoder) do
        local cache = state.cache[i]
        if not cache then
            cache = {keys={}, values={}, crossKeys={}, crossValues={}}
            for j, row in ipairs(encoded) do
                cache.crossKeys[j], cache.crossValues[j] = keyValue(layer.crossAttention, row, width, checkpoint)
            end
            state.cache[i] = cache
        end
        local input = normalize(vector, layer.selfNorm, scratch.normalized)
        local query
        query, cache.keys[position], cache.values[position] =
            queryKeyValue(layer.attention, input, width, checkpoint, scratch.query)
        addAttention(vector, layer.attention, query, cache.keys, cache.values, network.heads, checkpoint, scratch)
        input = normalize(vector, layer.crossNorm, scratch.normalized)
        query = linearSlice(layer.crossAttention.qkv, input, 1, width, checkpoint, scratch.query)
        addAttention(vector, layer.crossAttention, query, cache.crossKeys, cache.crossValues,
            network.heads, checkpoint, scratch)
        feedForward(layer, vector, width, checkpoint, scratch)
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

local nativeScore = M.score
bestTarget = function(model, features, choices, checkpoint)
    local best, highest = EOS, -math.huge
    if model.transformer and M.score == nativeScore and model.width % 8 == 0 then
        local count, bias, width = #choices, model.outputBias, model.width
        local grouped = count - count % 4
        for index = 1, grouped, 4 do
            local first, second = choices[index], choices[index + 1]
            local third, fourth = choices[index + 2], choices[index + 3]
            local a, b, c, d = projectFour(model.target, first, second, third, fourth, features, width)
            a, b, c, d = a + bias[first], b + bias[second], c + bias[third], d + bias[fourth]
            if a > highest then best, highest = first, a end
            if b > highest then best, highest = second, b end
            if c > highest then best, highest = third, c end
            if d > highest then best, highest = fourth, d end
            if checkpoint and index % 32 == 29 then checkpoint() end
        end
        for index = grouped + 1, count do
            local candidate = choices[index]
            local score = nativeScore(model, features, candidate)
            if score > highest then best, highest = candidate, score end
        end
        return best
    end
    for index, id in ipairs(choices) do
        local score = M.score(model, features, id)
        if score > highest then best, highest = id, score end
        if checkpoint and index % 32 == 0 then checkpoint() end
    end
    return best
end

return M
