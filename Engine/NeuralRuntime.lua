-- EN → UK student inference shared by the addon and the offline evaluator.
local _, ns = ...
local Numbers = ns.Engine.NeuralNumbers
local beForms = ns.Engine.Normalize.englishCopulas

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
        if neuralSense == "finder" then return exact or surface == "lfg" and ns.Engine.ChatRouting.finderReference(tokens, first) end
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
local inference = ns.Engine.NeuralInference
local UNK, BOS, EOS = inference.UNK, inference.BOS, inference.EOS
local M = {
    tokenize=inference.tokenize, encode=inference.encode, decode=inference.decode,
    candidates=inference.candidates, score=inference.score,
}
ns.Engine.NeuralRuntime = M

function M.prepare(data, checkpoint)
    local model = inference.prepare(data, checkpoint)
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
    model.numberSlots, model.numberSlotOrder, model.numericPieces = data.numberSlots, numberSlotOrder, numericPieces
    model.termSlots, model.itemSlots, model.moneySlots = data.termSlots, data.itemSlots, data.moneySlots
    return model
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

local function translatePlain(model, text, checkpoint, fullVocabulary, requireComplete, opener, terms, prices, trace)
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
    local normalized = inference.normalizeInput(sourceText)
    local key = decodedKey(model, normalized, fullVocabulary, values, terms)
    local numberOrder = requireComplete and values and #values > 1 and model.numberSlotOrder
    if numberOrder then key = key .. ":ordered" end
    local cache = model.decodedCache
    local cached = cache and cache.outputs[key]
    if cached then
        if trace then trace("decoded-cache-hit", cached.failure) end
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
    if trace then trace("encode", #source) end
    local encoded, state = M.encode(model, source, checkpoint)
    local target, previous = {}, BOS
    local nextNumber, repeated = 1, 1
    for _ = 1, model.maxPieces do
        local features
        features, state = M.decode(model, previous, encoded, state, checkpoint)
        local best = inference.bestTarget(model, features, choices, checkpoint, M.score)
        if trace then trace("decode", best) end
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
    rememberDecoded(cache, key, nil, #choices, "target-length")
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

function M.withProtected(text, split, translate, requireComplete, traceOffsets)
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
            local result, status, candidates
            if traceOffsets then result, status, candidates = translate(body, segment.first, #leading)
            else result, status, candidates = translate(body, segment.first) end
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

local function translateWithPrices(model, text, checkpoint, fullVocabulary, requireComplete, opener, terms, trace)
    local prices = model.moneySlots and Numbers.prices(terms and terms.input or text, opener)
    if prices then
        local result, mode, count = translatePlain(model, text, checkpoint, fullVocabulary,
            requireComplete, opener, terms, prices, trace)
        if result then
            local digits = result:gmatch("%d+")
            local same = true
            for original in text:gmatch("%d+") do
                if digits() ~= original then same = false; break end
            end
            if same and not digits() then return result, mode, count end
        end
    end
    return translatePlain(model, text, checkpoint, fullVocabulary, requireComplete, opener, terms, nil, trace)
end

function M.translate(model, text, checkpoint, fullVocabulary, split, context, requireComplete, trace)
    local function infer(fragment, opener, record)
        if not model.termSlots then
            return translateWithPrices(model, fragment, checkpoint, fullVocabulary, requireComplete, nil, nil, record)
        end
        local masked, terms, corrected = Glossary.mask(ns, fragment, opener, model.itemSlots)
        local function constrained()
            terms.input = masked
            local candidate, mode, count = translateWithPrices(model, fragment, checkpoint, fullVocabulary,
                requireComplete, opener, terms, record)
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
            checkpoint, fullVocabulary, requireComplete, opener, nil, record)
        if terms and not preferConstrained and (not ordinary or not Glossary.target(ns, ordinary, terms)) then
            local candidate, mode, count = constrained()
            if candidate then return candidate, mode, count end
        end
        if ordinary and requiredTerms and not Glossary.target(ns, ordinary, requiredTerms) then
            return nil, "term-slots"
        end
        return ordinary, ordinaryMode, ordinaryCount
    end
    local function translate(fragment, opener, first)
        local record
        if trace then
            first = first or 1
            record = function(kind, detail) trace(kind, first, first + #fragment - 1, nil, detail) end
        end
        local output, mode, count = infer(fragment, opener, record)
        local expanded = modelSource(fragment)
        if expanded ~= fragment and not hasVisibleNegation(output) then
            local alternative, retryMode, retryCount = infer(expanded, opener, record)
            if hasVisibleNegation(alternative) then return alternative, retryMode, retryCount end
        end
        return output, mode, count
    end
    if not split then return translate(text, context) end
    return M.withProtected(text, split, function(fragment, first, leading)
        return translate(fragment, (not first or first == 1) and context or nil, first and first + (leading or 0))
    end, requireComplete, trace)
end

return M
