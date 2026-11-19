local _, ns = ...
local A = {}
ns.Engine.ClauseAnalysis = A
local P, L = ns.Engine.Phrases, ns.Engine.Lexicon

local function lexemeFrame(entry)
    return entry.lexeme.frame or {}
end

local function controlledStart(document, first, limit, frame)
    local english = document.direction == "en-uk"
    local case = english and "accusative" or frame.controlCase
    local actor, index = P.pronoun(document, first, limit, case, true)
    if not actor then actor, index = P.noun(document, first, limit, case) end
    if not actor or (actor.pronoun and actor.pronoun.id == "it")
        or not (actor.pronoun or actor.animacy == "animate") then return nil end
    if english and frame.controlTo and P.key(document, index, limit) == "to" then index = index + 1 end
    local negative = P.key(document, index, limit) == (english and "not" or "не")
    if negative then index = index + 1 end
    if index <= limit then return actor, index, negative end
end

local function personalSubject(id)
    for _, pronoun in ipairs(ns.Linguistics.grammar.pronouns) do
        if pronoun.id == id then
            return {pronoun=pronoun, person=pronoun.person, number=pronoun.number, gender=pronoun.gender}
        end
    end
end

local copula = {am="present", is="present", are="present", was="past", were="past",
    ["є"]="present", ["був"]="past", ["була"]="past", ["було"]="past", ["були"]="past"}
local negativeCopula = {["isn't"]="is", ["aren't"]="are", ["wasn't"]="was", ["weren't"]="were"}
local have = {have=true, has=true, had=true}
local contracted = {
    idk={"i","do","know",true},
    ["i'm"]={"i","am"}, ["you're"]={"you","are"}, youre={"you","are"}, ["we're"]={"we","are"}, ["they're"]={"they","are"},
    ["i've"]={"i","have"}, ["you've"]={"you","have"}, ["we've"]={"we","have"}, ["they've"]={"they","have"},
    ["i'll"]={"i","will"}, ["you'll"]={"you","will"}, ["he'll"]={"he","will"}, ["she'll"]={"she","will"},
    ["it'll"]={"it","will"}, ["we'll"]={"we","will"}, ["they'll"]={"they","will"},
}
contracted.im = contracted["i'm"]
local auxiliary = {
    can={modal="can"}, cannot={modal="can", negative=true}, ["can't"]={modal="can", negative=true},
    could={modal="could"}, ["couldn't"]={modal="could", negative=true},
    might={modal="might"},
    must={modal="must"}, should={modal="should"}, ["shouldn't"]={modal="should", negative=true},
    will={tense="future", ellipsis=true}, ["won't"]={tense="future", negative=true, ellipsis=true},
    gonna={tense="future"},
    do_={tense="present", support=true}, does={tense="present", support=true}, did={tense="past", support=true},
    ["don't"]={tense="present", negative=true, support=true}, ["doesn't"]={tense="present", negative=true, support=true},
    ["didn't"]={tense="past", negative=true, support=true},
    ["можу"]={modal="can", person=1, number="singular"}, ["можеш"]={modal="can", person=2, number="singular"},
    ["може"]={modal="can", person=3, number="singular"}, ["можемо"]={modal="can", person=1, number="plural"},
    ["можете"]={modal="can", person=2, number="plural"}, ["можуть"]={modal="can", person=3, number="plural"},
    ["міг"]={modal="could", number="singular", gender="masculine"},
    ["могла"]={modal="could", number="singular", gender="feminine"},
    ["могло"]={modal="could", number="singular", gender="neuter"},
    ["могли"]={modal="could", number="plural"},
    ["буду"]={tense="future", ellipsis=true, person=1, number="singular"},
    ["будеш"]={tense="future", ellipsis=true, person=2, number="singular"},
    ["буде"]={tense="future", ellipsis=true, person=3, number="singular"},
    ["будемо"]={tense="future", ellipsis=true, person=1, number="plural"},
    ["будете"]={tense="future", ellipsis=true, person=2, number="plural"},
    ["будуть"]={tense="future", ellipsis=true, person=3, number="plural"},
}
auxiliary["do"] = auxiliary.do_
local permission = {modal="may"}
auxiliary.dont, auxiliary.doesnt, auxiliary.didnt = auxiliary["don't"], auxiliary["doesn't"], auxiliary["didn't"]

local function craftingObject(document, first, limit)
    local token = document.tokens[first]
    if first <= limit and token.linkKind == "item" then return true end
    local noun = P.noun(document, first, limit, "accusative")
    return noun and noun.term and noun.term.category == "goods"
end

local function verb(document, index, limit, subject, base, imperative, sense, aspect, headword, previous)
    if index > limit then return nil end
    local english = document.direction == "en-uk"
    local after = index + 1
    if english and not headword then
        local phrase, finish = L.phraseAt(document, index, limit, "verb")
        if phrase then headword, after = phrase, finish end
    end
    local selected = L.choose(document, headword or index, "verb", nil, sense, function(candidate)
        local f = candidate.form
        local frame = lexemeFrame(candidate)
        if frame.requiresSharedSubject and not (previous and previous.subject) then return false end
        local context = frame.coordinatedAfter
        if context and not (previous and previous.verb and context[previous.verb.lexeme.en]) then return false end
        if frame.requiresDestination then
            local destination = P.noun(document, after, limit, "accusative", true)
            if not destination or not destination.term or destination.term.category ~= "places" then return false end
        end
        if english and frame.requiredControl then
            local actor, at = controlledStart(document, after, limit, frame)
            if not actor then return false end
            local phrase = L.phraseAt(document, at, limit, "verb")
            if not L.choose(document, phrase or at, "verb", {mood="base"}) then return false end
        end
        if aspect == "resultative" then
            return f.verbalForm == "participle" and f.tense == "past" and lexemeFrame(candidate).resultative
        end
        if aspect == "passive" then return f.verbalForm == "participle" and f.tense == "past" and frame.passiveUk end
        if aspect then return f.verbalForm == "participle" and f.tense == aspect end
        if f.verbalForm then return false end
        if english then
            if base or imperative then return f.mood == "base" end
            if f.mood == "base" then
                return frame.invariantPresent or not subject or subject.person ~= 3 or subject.number == "plural"
            end
            if subject and f.person then
                return f.person == subject.person and (not f.number or f.number == subject.number)
            end
            return f.tense ~= nil
        end
        if lexemeFrame(candidate).contact then
            local addressee, after = P.noun(document, index + 1, limit, "dative")
            if not addressee or P.noun(document, after, limit, "accusative") then return false end
        end
        if base then return f.mood == "infinitive" end
        if imperative then return f.mood == "imperative" end
        if f.mood == "infinitive" or f.mood == "imperative" then return false end
        return f.tense ~= nil and (not subject
            or (not f.person or f.person == subject.person)
                and (not f.number or f.number == subject.number)
                and (not f.gender or not subject.gender or f.gender == subject.gender))
    end)
    if selected then return selected, after end
end

local function adverbAt(document, first, limit, context)
    local rows, last = L.functional(document, "adverbs", first, limit)
    if not rows or last > limit then return nil end
    local adverb = ns.Linguistics.grammar.adverbs[rows[1]]
    if not adverb.context or adverb.context == context then return adverb, last + 1 end
end

local function levelQuestion(document, first, limit, english)
    local head = P.key(document, first, limit)
    local noun = P.key(document, first + 1, limit)
    local requester, marker, placeAt
    if english then
        if (head ~= "what" and head ~= "which") or (noun ~= "level" and noun ~= "lvl") then return nil end
        local helper = P.key(document, first + 2, limit)
        if helper ~= "do" and helper ~= "does" then return nil end
        requester, marker = P.pronoun(document, first + 3, limit, "nominative", true)
        if not requester or requester.pronoun.id == "someone"
            or (helper == "does") ~= (requester.person == 3 and requester.number == "singular")
            or P.key(document, marker, limit) ~= "need" or P.key(document, marker + 1, limit) ~= "for" then return nil end
        placeAt = marker + 2
    else
        if head ~= "який" or noun ~= "рівень" then return nil end
        requester, marker = P.pronoun(document, first + 2, limit, "dative", true)
        if not requester or requester.pronoun.id == "someone" or P.key(document, marker, limit) ~= "потрібен"
            or P.key(document, marker + 1, limit) ~= "для" then return nil end
        placeAt = marker + 2
    end
    local place, finish = P.noun(document, placeAt, limit, "genitive", true)
    if place and place.term and place.term.category == "places" then
        return {kind="levelQuestion", requester=requester, place=place, question=true}, finish
    end
end

local englishQuestions = {
    who={kind="person"}, whom={kind="person", role="object"}, ["who's"]={kind="person", role="subject", copula="is"},
    what={kind="thing"}, ["what's"]={kind="thing", copula="is"}, how={kind="manner", role="manner"},
}
local ukrainianQuestions = {
    ["хто"]={kind="person", role="subject"}, ["кого"]={kind="person", role="object", case="accusative"},
    ["кому"]={kind="person", role="object", case="dative"}, ["ким"]={kind="person", role="object", case="instrumental"},
    ["що"]={kind="thing"}, ["чого"]={kind="thing", role="object", case="genitive"},
    ["чим"]={kind="thing", role="object", case="instrumental"}, ["як"]={kind="manner", role="manner"},
    ["який"]={kind="thing", role="predicate", definite=true, gender="masculine"},
    ["яка"]={kind="thing", role="predicate", definite=true, gender="feminine"},
    ["яке"]={kind="thing", role="predicate", definite=true, gender="neuter"},
    ["які"]={kind="thing", role="predicate", definite=true, gender="plural"},
    ["скільки"]={kind="quantity"},
}

local function requirementTail(document, first, limit)
    local head = P.key(document, first, limit)
    if document.direction == "en-uk" then
        if (head == "does" or head == "did") and P.key(document, first + 1, limit) == "it"
            and P.key(document, first + 2, limit) == "take" then return first + 3, head == "did" end
    elseif head == "знадобилося" or head == "потрібно" then
        return first + 1, head == "знадобилося"
    end
end

local function quantifiedNoun(document, first, limit, mode)
    local english = document.direction == "en-uk"
    local noun, after
    local event = ns.Engine.Morphology.select(document, first, "countedEvents", limit, not english and "genitive" or nil)
    if event and requirementTail(document, event.last + 1, limit) then
        local features = event.features
        noun, after = {term=event.term, person=3, number=features.number,
            gender=features.gender, sourceCase=features.case}, event.last + 1
    else
        noun, after = P.noun(document, first, limit, english and "nominative" or "genitive", false, false)
    end
    if not noun or noun.raw or noun.pronoun or noun.article or (not english and noun.sourceCase ~= "genitive") then return nil end
    local plural = noun.number == "plural"
    local mass = noun.term and noun.term.features and noun.term.features.mass or noun.entry and noun.entry.head.mass
    if (mode == "many" and not plural) or (mode == "much" and (plural or not mass)) or (not mode and not plural and not mass) then
        return nil
    end
    return noun, after
end

local function interrogativeAt(document, first, limit, indirect)
    local english = document.direction == "en-uk"
    local questions = english and englishQuestions or ukrainianQuestions
    local spec = questions[P.key(document, first, limit)]
    if not spec then return nil end
    local index, role = first + 1, spec.role
    local head = P.key(document, index, limit)
    local kind, quantified = spec.kind
    if kind == "manner" and ((english and head == "long") or (not english and head == "довго")) then
        kind, index, head = "duration", index + 1, P.key(document, index + 1, limit)
    elseif kind == "quantity" and not english and head == "часу" then
        kind, role, index, head = "duration", "manner", index + 1, P.key(document, index + 1, limit)
    end
    if kind == "quantity" or (kind == "manner" and english and (head == "many" or head == "much")) then
        local mode = english and head or nil
        quantified, index = quantifiedNoun(document, index + (mode and 1 or 0), limit, mode)
        if not quantified then return nil end
        kind, role, head = "quantity", nil, P.key(document, index, limit)
    end
    local another = not quantified and kind ~= "manner" and (head == "else" or head == "ще")
    if another then index, head = index + 1, P.key(document, index + 1, limit) end
    if not english and not role and head == "таке" then role, index = "predicate", index + 1 end
    if not english and not role and head == "саме" then role, index = "object", index + 1 end
    if indirect and kind == "person" and (P.key(document, first, limit) == "who" or P.key(document, first, limit) == "хто") then
        local subject, after = P.pronoun(document, index, limit, "nominative")
        if subject and ((english and copula[P.key(document, after, limit)]) or (not english and after > limit)) then
            role = "predicate"
        end
    end
    if not role then
        local copular = english and (spec.copula or negativeCopula[head] or copula[head] and head)
        local aux = english and auxiliary[head]
        if aux or copular or not english or indirect then
            local skipAux = (aux or copular) and not spec.copula
            local subject, after = P.coordinated(document, index + (skipAux and 1 or 0), limit, "nominative")
            if subject then
                local nextKey = P.key(document, after, limit)
                if nextKey == "not" or nextKey == "не" then after = after + 1 end
                local _, adverbEnd = adverbAt(document, after, limit)
                local atVerb = adverbEnd or after
                local aspect = copular and "present" or nil
                if verb(document, atVerb, limit, subject, aux and true or false, false, nil, aspect)
                    or not english and auxiliary[P.key(document, atVerb, limit)] then
                    role = "object"
                elseif copular and spec.kind == "thing" and after > limit then
                    role = "predicate"
                end
            end
        end
    end
    return {kind=kind, noun=quantified, role=role or "subject", case=spec.case, another=another, copula=spec.copula,
        definite=spec.definite, gender=spec.gender}, index
end

local function explicitTime(tree)
    if tree.leadingAdverb and tree.leadingAdverb.time then return tree.leadingAdverb.time end
    if tree.adverbs then
        for _, adverb in ipairs(tree.adverbs) do
            if adverb.time then return adverb.time end
        end
    end
    if tree.controlled then return explicitTime(tree.controlled.action) end
end

local function clauseConnector(document, index, limit)
    local choices, last = L.functional(document, "connectors", index, limit)
    local rule = choices and ns.Linguistics.grammar.connectors[choices[1]]
    if not rule then return nil end
    if rule.alsoPreposition ~= P.key(document, index, limit) then return rule, last end
    local subject, after = P.noun(document, last + 1, limit, "nominative")
    if not subject then return nil end
    local _, afterAdverb = adverbAt(document, after, limit)
    after = afterAdverb or after
    local predicate = P.key(document, after, limit)
    if copula[predicate] or auxiliary[predicate] or negativeCopula[predicate]
        or verb(document, after, limit, subject, false) then return rule, last end
end

local function boundary(document, index, limit)
    local key = P.key(document, index, limit)
    return index > limit or key == "," or key == ";" or clauseConnector(document, index, limit)
end

local function purposeStart(document, index, limit, bare)
    local key = P.key(document, index, limit)
    if document.direction == "en-uk" then
        if key == "in" and P.key(document, index + 1, limit) == "order" then
            index = index + 2
        elseif not bare then return end
        local negative = P.key(document, index, limit) == "not"
        if negative then index = index + 1 end
        if P.key(document, index, limit) == "to" then return index + 1, negative end
    else
        if key == "," then index = index + 1; key = P.key(document, index, limit) end
        if key == "щоб" or key == "аби" then
            local negative = P.key(document, index + 1, limit) == "не"
            return index + (negative and 2 or 1), negative
        end
    end
end

local function smallActivity(document, index, limit)
    if document.direction == "en-uk" then
        if P.key(document, index, limit) ~= "do" then return end
        local amount = P.key(document, index + 1, limit)
        if amount == "some" then index = index + 2
        elseif amount == "a" and P.key(document, index + 2, limit) == "bit"
            and P.key(document, index + 3, limit) == "of" then index = index + 4
        else return end
    elseif P.key(document, index, limit) == "трохи" then index = index + 1
    else return end
    local entries, last = L.functional(document, "activities", index, limit)
    if entries and #entries == 1 then
        return {kind="activity", activity=ns.Linguistics.grammar.activities[entries[1]]}, last + 1
    end
end

local simple
local function coordinatedObject(document, first, limit, case, locationOnly, enumeration)
    local startsPredicate
    if document.direction == "en-uk" then
        startsPredicate = function(index)
            local candidate, after = verb(document, index, limit, nil, true)
            if not candidate or after > limit then return false end
            local object = P.noun(document, after, limit, "accusative")
            if object and (object.article or object.pronoun or object.possessor or object.quantity) then return true end
            return P.preposition(document, after, limit, lexemeFrame(candidate).motion) ~= nil
        end
    end
    return P.coordinated(document, first, limit, case, startsPredicate, locationOnly, enumeration)
end

local complements
local function nominalInfinitive(document, noun, first, limit, depth)
    local head = noun.members and noun.members[#noun.members] or noun
    local frame = head.entry and head.entry.lexeme.frame
    if document.direction ~= "en-uk" or depth >= 3 or not frame or not frame.nominalInfinitive
        or P.key(document, first, limit) ~= "to" then return nil end
    local entry, after = verb(document, first + 1, limit, nil, true)
    if not entry then return nil end
    local action = {verb=entry, tense="infinitive"}
    local finish = complements(document, action, after, limit, depth + 1)
    if finish then return action, finish end
end

local function purposeSeries(document, purpose, index, limit, depth)
    for _ = 1, 3 do
        local comma = P.key(document, index, limit) == ","
        local start = index + (comma and 1 or 0)
        local selected, last = L.functional(document, "connectors", start, limit)
        local join = selected and ns.Linguistics.grammar.connectors[selected[1]]
        if join and (join.id == "and" or join.id == "or") then start = last + 1
        elseif comma and not join then join = nil
        else break end
        local adverb, afterAdverb = adverbAt(document, start, limit)
        local entry, following = verb(document, afterAdverb or start, limit, nil, true)
        if not entry then break end
        local action = {verb=entry, tense="infinitive", leadingAdverb=adverb, purposeClause=true}
        local finish = complements(document, action, following, limit, depth)
        if not finish then break end
        purpose.series = purpose.series or {}
        purpose.series[#purpose.series + 1] = {action=action, join=join}
        index = finish
    end
    return index
end

complements = function(document, tree, index, limit, depth)
    depth = depth or 0
    local frame = lexemeFrame(tree.verb)
    local english = document.direction == "en-uk"
    if english and tree.wh and tree.wh.kind == "duration" and tree.verb.lexeme.en == "take" then return nil end
    local objectPreposition = english and frame.enObjectPreposition or not english and frame.objectPreposition
    local questionObject = tree.wh and tree.wh.role == "object"
    local gap = tree.objectGap
    if gap then
        if not frame.objectCase or objectPreposition or frame.intransitive or frame.motion or frame.separation then return nil end
        tree.relativeCase = frame.objectCase
    end
    local occupiedObject = questionObject or gap
    if questionObject then
        local expected = frame.objectCase
        local observed = tree.wh.case
        local animateGenitive = tree.wh.kind == "person" and observed == "accusative" and expected == "genitive"
        if not expected or objectPreposition or frame.motion or frame.intransitive
            or (observed and observed ~= expected and not animateGenitive)
            or (expected == "dative" and tree.wh.kind == "thing")
            or (tree.wh.kind == "quantity" and expected ~= "accusative" and expected ~= "genitive") then return nil end
        tree.wh.case = expected
    end
    local preposition
    if objectPreposition and P.key(document, index, limit) == objectPreposition then
        preposition = true
        index = index + 1
    end
    local objectCase = english and "accusative" or frame.objectCase or "accusative"
    local priceAdverb
    if frame.priceAdverb and not occupiedObject then
        local adverb, after = adverbAt(document, index, limit, "price")
        local ambiguous = english and after == index + 1 and P.key(document, index, limit) == "free"
        if adverb and adverb.context == "price" and (not ambiguous or craftingObject(document, after, limit)) then
            priceAdverb, index = adverb, after
        end
    end
    if not occupiedObject and frame.controlCase and depth < 3 then
        local actor, start, negative = controlledStart(document, index, limit, frame)
        if actor then
            local entry, after = verb(document, start, limit, nil, true)
            if entry and entry.lexeme.en ~= "be" then
                if frame.permission and entry.lexeme.en == "know" then return nil end
                local action = {verb=entry, tense="infinitive", negative=negative, purposeClause=not negative}
                local finish = complements(document, action, after, limit, depth + 1)
                if finish then tree.controlled, index = {actor=actor, action=action}, finish end
            end
        end
    end
    if frame.requiredControl and not tree.controlled then return nil end
    if frame.content and not occupiedObject and depth < 3 then
        local marker = english and "that" or "що"
        local start = index
        if not english and P.key(document, start, limit) == "," then start = start + 1 end
        local linker = P.key(document, start, limit)
        local following = P.key(document, start + 1, limit)
        local indirect = linker == "where" or linker == "де" or linker == "why" or linker == "чому"
            or (english and englishQuestions[linker])
            or (not english and ukrainianQuestions[linker]
                and (linker ~= "що" or following == "саме" or following == "ще" or following == "таке"))
        if linker == marker or indirect then
            local embedded, finish = simple(document, indirect and start or start + 1, limit, nil, depth + 1, indirect)
            if embedded and embedded.subject and not embedded.imperative and not embedded.question then
                tree.content = {embedded}
                index = finish
                if indirect then return index end
                for _ = 1, 2 do
                    local nextMarker = index
                    if P.key(document, nextMarker, limit) == "," then nextMarker = nextMarker + 1 end
                    local join = P.key(document, nextMarker, limit)
                    local andJoin = join == "and" or join == "і" or join == "й" or join == "та"
                    if not andJoin or P.key(document, nextMarker + 1, limit) ~= marker then break end
                    embedded, finish = simple(document, nextMarker + 2, limit, nil, depth + 1)
                    if not embedded or not embedded.subject or embedded.imperative or embedded.question then break end
                    tree.content[#tree.content + 1] = embedded
                    index = finish
                end
                return index
            end
        end
    end
    local recipient, after
    if frame.recipientCase and not occupiedObject and not tree.controlled then
        recipient, after = P.noun(document, index, limit, english and "accusative" or frame.recipientCase)
        if recipient then
            local object, last = coordinatedObject(document, after, limit, objectCase)
            if object then tree.recipient, tree.object, index = recipient, object, last end
        end
    end
    if not occupiedObject and not tree.controlled and not tree.object and not frame.motion and not frame.intransitive
        and (not objectPreposition or preposition) then
        local object, nextIndex
        if frame.separation then object, nextIndex = P.noun(document, index, limit, objectCase, false, nil, true)
        else object, nextIndex = coordinatedObject(document, index, limit, objectCase, frame.destinationObject, frame.enumeratesObject) end
        if object then
            local objectFrame = object.entry and object.entry.lexeme.frame
            local quantity = tonumber(object.quantity)
            if english and tree.verb.lexeme.en == "open" and objectFrame and objectFrame.skillThreshold
                and object.number == "singular" and quantity and quantity >= 25 and quantity <= 999 then
                object.skillRequirement, object.quantity = object.quantity, nil
            end
            tree.object, index = object, nextIndex
        elseif preposition then return nil end
    end
    if frame.separation and tree.object and P.key(document, index, limit) == (english and "of" or "від") then
        tree.separation, after = P.noun(document, index + 1, limit, "genitive")
        if not tree.separation then return nil end
        index = after
    end
    if priceAdverb then
        if not tree.object then return nil end
        tree.adverbs = {priceAdverb}
    end
    if not occupiedObject and not tree.controlled and not tree.object and frame.infinitive and depth < 3 then
        local marker = P.key(document, index, limit)
        if not english or marker == "to" or frame.bareInfinitive then
            local verbIndex = english and marker == "to" and index + 1 or index
            local embedded, after = verb(document, verbIndex, limit, nil, true)
            if embedded then
                tree.infinitive = {verb=embedded, tense="infinitive"}
                local finish = complements(document, tree.infinitive, after, limit, depth + 1)
                if not finish then return nil end
                index = finish
            elseif english and frame.omittedInfinitive and marker == "to" and index == limit then
                index = index + 1
            end
        end
    end
    for _ = 1, 3 do
        if depth < 3 and not tree.purpose then
            local start, negative = purposeStart(document, index, limit, frame.motion or frame.contact or frame.barePurpose)
            if start and not negative then
                local activity, finish = smallActivity(document, start, limit)
                if activity then tree.purpose = activity; return finish end
            end
            if start then
                local predicateVerb, after = verb(document, start, limit, nil, true)
                if predicateVerb then
                    local purpose = {verb=predicateVerb, tense="infinitive", negative=negative, purposeClause=true}
                    local finish = complements(document, purpose, after, limit, depth + 1)
                    if finish then tree.purpose = purpose; return purposeSeries(document, purpose, finish, limit, depth + 1) end
                end
            end
        end
        if boundary(document, index, limit) then break end
        local pp, last = P.preposition(document, index, limit, frame.motion, frame.displacesObject and tree.object ~= nil)
        if pp then
            local entry = pp.object.entry
            local action, finish = nominalInfinitive(document, pp.object, last, limit, depth)
            if action then pp.infinitive, last = action, finish end
            if english and tree.object and not tree.purpose and pp.rule.id == "for" and entry
                and frame.goalObjects and frame.goalObjects[entry.lexeme.en] then
                tree.purpose = {object=pp.object}
            else
                tree.prepositions = tree.prepositions or {}
                tree.prepositions[#tree.prepositions + 1] = pp
            end
            index = last
        else
            local adverb, endAt = adverbAt(document, index, limit, frame.priceAdverb and "price" or nil)
            if not adverb then break end
            tree.adverbs = tree.adverbs or {}
            tree.adverbs[#tree.adverbs + 1] = adverb
            index = endAt
        end
    end
    return index
end

local durationAuxiliaries = {["do"]="present", does="present", did="past", will="future"}
local requiredTime = {["потрібно"]="present", ["знадобилося"]="past", ["знадобиться"]="future"}
local nominalTime = {
    ["займає"]={tense="present"}, ["займають"]={tense="present", plural=true},
    ["займе"]={tense="future"}, ["займуть"]={tense="future", plural=true},
    ["зайняв"]={tense="past", gender="masculine"}, ["зайняла"]={tense="past", gender="feminine"},
    ["зайняло"]={tense="past", gender="neuter"}, ["зайняли"]={tense="past", plural=true},
}

local function durationAction(document, index, limit, subject)
    local english = document.direction == "en-uk"
    local head = P.key(document, index, limit)
    if english and head == "level" then
        local skill, after = subject, index + 1
        if not skill then skill, after = P.noun(document, index + 1, limit, "accusative") end
        if skill and skill.term and skill.term.category == "professions" then
            return {kind="skillLevel", skill=skill}, after
        end
        if not skill then return nil end
    elseif not english and head == "підвищити" and P.key(document, index + 1, limit) == "рівень" then
        local skill, after = P.noun(document, index + 2, limit, "genitive")
        if skill and skill.term and skill.term.category == "professions" and skill.sourceCase == "genitive" then
            return {kind="skillLevel", skill=skill}, after
        end
    end
    if subject then return nil end
    local entry, after = verb(document, index, limit, nil, true)
    if not entry then return nil end
    local action = {verb=entry, tense="infinitive", purposeClause=true}
    local finish = complements(document, action, after, limit)
    if finish then return action, finish end
end

local function durationQuery(document, first, limit, english)
    local opening, second = P.key(document, first, limit), P.key(document, first + 1, limit)
    local index = first + 2
    local subject, tense, recipient
    if english then
        if opening ~= "how" or second ~= "long" then return nil end
        local aux = P.key(document, index, limit)
        tense = durationAuxiliaries[aux]
        if not tense then return nil end
        if P.key(document, index + 1, limit) == "it" then index = index + 2
        else
            subject, index = P.noun(document, index + 1, limit, "nominative")
            if not subject then return nil end
        end
        local thirdSingular = not subject or (subject.person == 3 and subject.number == "singular")
        if (aux == "do" and thirdSingular) or (aux == "does" and not thirdSingular) then return nil end
        if P.key(document, index, limit) ~= "take" then return nil end
        index = index + 1
        if P.key(document, index, limit) ~= "to" then
            local person, after = P.noun(document, index, limit, "accusative", false, false, true)
            if person and (person.pronoun or person.animacy == "animate") then recipient, index = person, after end
        end
        if subject and not recipient and (subject.pronoun or subject.animacy == "animate") then
            recipient, subject = subject, nil
        end
        if P.key(document, index, limit) == "to" then
            local action, finish = durationAction(document, index + 1, limit, subject)
            if action then return {kind="duration", question=true, tense=tense, action=action, recipient=recipient}, finish end
            return nil
        end
    else
        if opening ~= "скільки" or second ~= "часу" then return nil end
        local marker = P.key(document, index, limit)
        if not (requiredTime[marker] or nominalTime[marker]) then
            local person, after = P.noun(document, index, limit, "dative", false, false, true)
            if person and (person.pronoun or person.animacy == "animate") and requiredTime[P.key(document, after, limit)] then
                recipient, index, marker = person, after, P.key(document, after, limit)
            end
        end
        tense = requiredTime[marker]
        if tense then
            index = index + 1
            local goal = index + (P.key(document, index, limit) == "," and 1 or 0)
            if P.key(document, goal, limit) == "щоб" then
                local action, finish = durationAction(document, goal + 1, limit)
                if action then return {kind="duration", question=true, tense=tense, action=action, recipient=recipient}, finish end
                return nil
            end
        else
            local form = nominalTime[marker]
            if form then subject, index = P.noun(document, index + 1, limit, "nominative")
            else
                subject, index = P.noun(document, index, limit, "nominative")
                if not subject then return nil end
                form = nominalTime[P.key(document, index, limit)]
                index = index + 1
            end
            if not form or not subject or subject.person ~= 3 or (subject.number == "plural") ~= (form.plural == true)
                or (form.gender and subject.gender ~= form.gender) then return nil end
            tense = form.tense
        end
    end
    if subject and recipient then return nil end
    return {kind="duration", question=true, tense=tense, action=subject and {noun=subject}, recipient=recipient}, index
end

local function duration(document, first, limit)
    local english = document.direction == "en-uk"
    local index = first
    local key = P.key(document, index, limit)
    if english and key == "it" then index = index + 1 end
    local action, durationVerb, quantity, after
    if english then
        durationVerb, after = verb(document, index, limit, nil, false, false, "duration")
        if not durationVerb then return nil end
        quantity, after = P.quantity(document, after, limit)
        if not quantity or P.key(document, after, limit) ~= "to" then return nil end
        index = after + 1
        local embedded, embeddedEnd = verb(document, index, limit, nil, true)
        if not embedded then return nil end
        action = {verb=embedded, tense="infinitive"}
        index = complements(document, action, embeddedEnd, limit)
        if not index then return nil end
    else
        local subject
        subject, index = P.noun(document, index, limit, "nominative")
        if not subject or not subject.entry then return nil end
        durationVerb, after = verb(document, index, limit, subject, false, false, "duration")
        if not durationVerb then return nil end
        quantity, index = P.quantity(document, after, limit)
        if not quantity then return nil end
        action = {noun=subject}
    end
    return {kind="duration", verb=durationVerb, quantity=quantity, action=action,
        tense=durationVerb.form.tense or "present"}, index
end

local function predicate(document, tree, index, limit, depth)
    local pp, finish = P.preposition(document, index, limit)
    if pp then tree.prepositions = {pp}; return finish end
    if index > limit then return (tree.where or tree.wh and tree.wh.kind == "manner") and index end
    if tree.where then return nil end
    local modifier = P.key(document, index, limit)
    local number = P.key(document, index + 1, limit)
    if document.direction == "en-uk" and modifier == "real" and tree.subject and tree.subject.term
        and tree.subject.term.category == "places" then
        tree.exists = true
        return index + 1
    end
    local adverb, after = adverbAt(document, index, limit)
    if adverb and adverb.location then tree.adverbs = {adverb}; return after end
    if document.direction == "en-uk" and modifier == "open" and number == "for"
        and P.key(document, index + 2, limit) == "business" then
        tree.openForBusiness = true
        return index + 3
    end
    if document.direction == "en-uk" and (modifier == "level" or modifier == "lvl")
        and number and number:match("^%d%d?%d?$") then
        tree.level = number
        return index + 2
    end
    local intensity
    if modifier == "more" or modifier == "більш" or modifier == "very" or modifier == "дуже" or modifier == "so"
        or modifier == "too" and document.direction == "en-uk" or modifier == "надто" then
        intensity = (modifier == "more" or modifier == "більш") and "more" or modifier == "so" and "so"
            or (modifier == "too" or modifier == "надто") and "too" or "very"
        index = index + 1
    end
    local adjective = index <= limit and L.choose(document, index, "adj", nil, nil, function(candidate)
        return not candidate.lexeme.frame or not candidate.lexeme.frame.profileOnly
    end)
    local object, nextIndex
    if adjective and (intensity or adjective.lexeme.frame and adjective.lexeme.frame.ukExperiencer) then
        object = nil
    else
        object, nextIndex = P.coordinated(document, index, limit, "nominative")
    end
    if object and (not intensity or not adjective) then tree.predicate = object; return nextIndex end
    if adjective then
        tree.adjective = {entry=adjective, intensity=intensity}
        local frame = adjective.lexeme.frame
        if document.direction == "en-uk" and frame and frame.ukContentLemma and depth and depth < 3
            and tree.tense == "present" and not tree.negative then
            local start = index + (P.key(document, index + 1, limit) == "that" and 2 or 1)
            if P.pronoun(document, start, limit, "nominative") then
                local embedded, finish = simple(document, start, limit, nil, depth + 1)
                if embedded and embedded.subject and not embedded.imperative and not embedded.question then
                    tree.adjectiveContent = embedded
                    return finish
                end
            end
        end
        local following, afterAdjective = P.preposition(document, index + 1, limit)
        if following then tree.prepositions = {following}; return afterAdjective end
        return index + 1
    end
end

local function wish(document, first, limit)
    local english = document.direction == "en-uk"
    local key = P.key(document, first, limit)
    local nextIndex = first + 1
    local tree = {kind="wish"}
    local requiresRecipient
    if english then
        if key == "good" and P.key(document, nextIndex, limit) == "luck" then
            nextIndex = nextIndex + 1
        elseif key ~= "goodluck" and key ~= "gl" then return end
        local separator = P.key(document, nextIndex, limit)
        requiresRecipient = separator == "to"
        if separator == "to" or separator == "," then nextIndex = nextIndex + 1 end
    elseif (key == "усім" or key == "всім") and P.key(document, nextIndex, limit) == "удачі" then
        tree.everyone, nextIndex = true, nextIndex + 1
    elseif key ~= "удачі" and key ~= "щасти" then return end
    if not tree.everyone then
        local recipient = P.key(document, nextIndex, limit)
        local everyone = english and (recipient == "all" or recipient == "everyone" or recipient == "everybody")
            or not english and (recipient == "усім" or recipient == "всім")
        if everyone then
            tree.everyone, nextIndex = true, nextIndex + 1
        else
            local pronoun, after = P.noun(document, nextIndex, limit, "dative")
            if pronoun and pronoun.pronoun then tree.recipient, nextIndex = pronoun, after end
        end
    end
    if requiresRecipient and not (tree.everyone or tree.recipient) then return end
    local target, after = P.preposition(document, nextIndex, limit)
    if target and target.rule.id == "with" then
        tree.prepositions, nextIndex = {target}, after
    end
    if tree.everyone or tree.recipient or tree.prepositions then return tree, nextIndex end
end

local function existentialQuestion(document, first, limit, depth)
    if depth >= 3 then return end
    local english = document.direction == "en-uk"
    local key, index, copulaNumber = P.key(document, first, limit), first
    local nearby
    if english then
        if key == "any" and document.tokens[limit + 1] and document.tokens[limit + 1].key == "?" then
            index = index + 1
        elseif (key == "anyone" or key == "anybody") and P.key(document, index + 1, limit) == "who" then
            nearby = true
        elseif (key == "is" or key == "are") and P.key(document, index + 1, limit) == "there" then
            copulaNumber, index = key == "is" and "singular" or "plural", index + 2
            if P.key(document, index, limit) == "any" then index = index + 1 end
        else return end
    elseif key == "чи" and P.key(document, index + 1, limit) == "є" then
        index = index + 2
        if P.key(document, index, limit) == "тут" then nearby, index = true, index + 1 end
    else return end
    local subject, after = P.noun(document, index, limit, "nominative")
    if not subject or (copulaNumber and subject.number ~= copulaNumber) then return end
    local here = P.key(document, after, limit)
    if here == "around" or here == "here" or here == "тут" then nearby, after = true, after + 1 end
    local tree = {kind="existential", subject=subject, question=true, nearby=nearby}
    if after > limit then return tree, after end
    local comma = P.key(document, after, limit) == ","
    if comma then after = after + 1 end
    local marker = P.key(document, after, limit)
    local explicit = marker == "who" or marker == "that" or marker == "which" or marker == "хто" or marker == "що"
        or marker == "який" or marker == "яка" or marker == "яке" or marker == "які"
    if explicit or (english and key == "any" and not comma) then
        local relative, finish = simple(document, after + (explicit and 1 or 0), limit, {subject=subject}, depth + 1, true)
        if relative and relative.inherited and not relative.question then
            tree.relative, tree.relativeMarker = relative, explicit and marker or nil
            return tree, finish
        end
    end
end

local needAgreement = {["потрібен"]="masculine", ["потрібна"]="feminine", ["потрібне"]="neuter", ["потрібні"]="plural"}

local function priceQuestion(document, first, limit, english)
    local opening = P.key(document, first, limit)
    local item, index, plural
    if english then
        if opening ~= "how" or P.key(document, first + 1, limit) ~= "much" then return nil end
        local auxiliary = P.key(document, first + 2, limit)
        if auxiliary == "do" or auxiliary == "are" then plural = true
        elseif auxiliary == "does" or auxiliary == "is" then plural = false
        else return nil end
        item, index = P.noun(document, first + 3, limit, "nominative")
        if not item then return nil end
        if auxiliary == "do" or auxiliary == "does" then
            if P.key(document, index, limit) ~= "cost" then return nil end
            index = index + 1
        else
            if P.key(document, index, limit) ~= "going" or P.key(document, index + 1, limit) ~= "for" then return nil end
            index = index + 2
        end
    else
        if opening ~= "скільки" then return nil end
        local predicate = P.key(document, first + 1, limit)
        if predicate == "коштує" or predicate == "коштують" then
            item, index = P.noun(document, first + 2, limit, "nominative")
        else
            item, index = P.noun(document, first + 1, limit, "nominative")
            if not item then return nil end
            predicate = P.key(document, index, limit)
            index = index + 1
        end
        if predicate ~= "коштує" and predicate ~= "коштують" then return nil end
        plural = predicate == "коштують"
    end
    if not item or (item.number == "plural") ~= plural then return nil end
    local adverb, after = adverbAt(document, index, limit)
    return {kind="priceQuestion", subject=item, question=true, adverb=adverb}, after or index
end

local function politeRequest(document, first, limit, english)
    local last = limit
    if english then
        if P.key(document, last, limit) ~= "please" then return nil end
        last = last - 1
    else
        if P.key(document, last - 1, limit) ~= "будь" or P.key(document, last, limit) ~= "ласка" then return nil end
        last = last - 2
        if P.key(document, first, last) == "можна" then first = first + 1 end
    end
    if P.key(document, last, limit) == "," then last = last - 1 end
    if last < first then return nil end
    local opening = P.key(document, first, last)
    local some = english and opening == "some" or not english and (opening == "кілька" or opening == "трохи")
    local object, after = P.coordinated(document, first + (some and 1 or 0), last,
        not english and some and "genitive" or "accusative")
    if not object or after <= last then return nil end
    local question = document.tokens[limit + 1] and document.tokens[limit + 1].key == "?"
    return {kind="politeRequest", object=object, some=some, question=question}, limit + 1
end

simple = function(document, first, limit, previous, depth, indirect, objectGap)
    local english = document.direction == "en-uk"
    local key = P.key(document, first, limit)
    if english and (key == "hello" or key == "hellooo" or key == "hi" or key == "hey") then
        local start = first + (P.key(document, first + 1, limit) == "," and 2 or 1)
        local addressee, finish = P.noun(document, start, limit, "nominative")
        if addressee and finish > limit then return {kind="greeting", recipient=addressee}, finish end
    end
    if english and key == "all" and P.key(document, first + 1, limit) == "hail"
        and P.key(document, first + 2, limit) == "to" then
        local recipient, after = P.noun(document, first + 3, limit, "accusative")
        if recipient then return {kind="salute", recipient=recipient}, after end
    end
    if depth < 3 then
        local initial, after = adverbAt(document, first, limit)
        if initial and initial.sentenceInitial then
            local tree, finish = simple(document, after, limit, previous, depth + 1, indirect)
            if tree and not tree.sentenceAdverb then tree.sentenceAdverb = initial; return tree, finish end
        end
    end
    if english and key == "no" then
        local object, after = P.noun(document, first + 1, limit, "nominative")
        local requirement = after and P.key(document, after, limit)
        if object and (requirement == "needed" or requirement == "required") then
            local tree = {kind="notRequired", object=object}
            local rest = after + 1
            if P.key(document, rest, limit) == "," then rest = rest + 1 end
            local limiter = P.key(document, rest, limit)
            if limiter == "just" or limiter == "only" then
                local qualification, ending = P.coordinated(document, rest + 1, limit, "accusative")
                if qualification then
                    local action, finish = nominalInfinitive(document, qualification, ending, limit, depth)
                    tree.qualification, tree.qualificationAction = qualification, action
                    return tree, finish or ending
                end
            end
            return tree, after + 1
        end
    end
    if english and key == "looking" and P.key(document, first + 1, limit) == "to"
        and document.tokens[limit + 1] and document.tokens[limit + 1].key == "?" then
        local subject = personalSubject("you")
        local want = verb(document, first, limit, subject, true, nil, nil, nil, "want")
        if want then
            local tree = {kind="clause", verb=want, subject=subject, tense="present", question=true}
            local finish = complements(document, tree, first + 1, limit, depth)
            if finish and tree.infinitive then return tree, finish end
        end
    end
    if not english and key == "можливо" and P.key(document, first + 1, limit) == "," and depth < 3 then
        local start = first + 2
        local tree, finish = simple(document, start, limit, previous, depth + 1, indirect)
        if not tree and P.key(document, start, limit) == "це" then
            local subject = personalSubject("it")
            local negative = P.key(document, start + 1, limit) == "не"
            tree = {kind="clause", subject=subject, copula=true, tense="present", negative=negative}
            finish = predicate(document, tree, start + (negative and 2 or 1), limit)
            if not tree.predicate then return nil end
        end
        if tree and finish and tree.kind == "clause" and tree.tense == "present" and tree.subject
            and not tree.modal and not tree.imperative and not tree.where and not tree.why and not tree.aspect then
            tree.modal = "might"
            return tree, finish
        end
        return nil
    end
    if english and key == "got" and document.tokens[limit + 1] and document.tokens[limit + 1].key == "?" then
        local object, finish = P.coordinated(document, first + 1, limit, "accusative")
        if object and finish > limit then
            local subject = personalSubject("you")
            local haveVerb = verb(document, first, limit, subject, true, nil, nil, nil, "have")
            if haveVerb then
                return {kind="clause", subject=subject, verb=haveVerb, object=object, tense="present", question=true}, finish
            end
        end
    end
    local special, after = duration(document, first, limit)
    if special then return special, after end
    if not indirect then
        special, after = levelQuestion(document, first, limit, english)
        if special then return special, after end
        special, after = durationQuery(document, first, limit, english)
        if special then return special, after end
        special, after = priceQuestion(document, first, limit, english)
        if special then return special, after end
    end
    special, after = wish(document, first, limit)
    if special then return special, after end
    special, after = politeRequest(document, first, limit, english)
    if special then return special, after end
    if not indirect then
        special, after = existentialQuestion(document, first, limit, depth)
        if special then return special, after end
    end
    if not english and needAgreement[key] then
        local object, finish = P.coordinated(document, first + 1, limit, "nominative")
        local agreement = object and (object.number == "plural" and "plural" or object.gender)
        if agreement == needAgreement[key] then return {kind="need", object=object}, finish end
    end
    local tree, index = {kind="clause", objectGap=objectGap}, first
    local wh, afterQuestion = interrogativeAt(document, first, limit, indirect)
    if wh and wh.noun and not indirect then
        local finish, past = requirementTail(document, afterQuestion, limit)
        if finish and boundary(document, finish, limit) then
            return {kind="requiredQuantity", wh=wh, question=true, tense=past and "past" or "present"}, finish
        end
    end
    if wh then
        tree.wh, tree.question, index = wh, not indirect, afterQuestion
    elseif key == "where" or key == "де" then
        tree.where, tree.question, index = true, not indirect, index + 1
    elseif key == "why" or key == "чому" then
        tree.why, tree.question, index = true, not indirect, index + 1
    elseif key == "чи" and not english then
        tree.question, index = true, index + 1
    end
    local headIndex = index
    local head = P.key(document, index, limit)
    if english and index == first then
        local commandStart
        if head == "don't" or head == "dont" then commandStart = index + 1
        elseif head == "do" and P.key(document, index + 1, limit) == "not" then commandStart = index + 2 end
        if commandStart then
            local command, afterVerb = verb(document, commandStart, limit, nil, true, true)
            if command and not lexemeFrame(command).impersonalNeed then
                tree.verb, tree.imperative, tree.negative, tree.tense = command, true, true, "present"
                local finish = complements(document, tree, afterVerb, limit, depth)
                if finish then return tree, finish end
                return nil
            end
        end
    end
    local aux
    if english then
        aux = auxiliary[head]
        if head == "may" and index == first and document.tokens[limit + 1]
            and document.tokens[limit + 1].key == "?" then aux = permission end
    end
    local questionSubject = wh and wh.role == "subject"
    local syntheticCopula = wh and wh.copula
    local invertedCopula = syntheticCopula or negativeCopula[head] or head
    local relativeSubject = indirect and previous and previous.subject
    local continuedAux = english and previous and previous.subject and aux
        and verb(document, index + 1, limit, previous.subject, true, nil, nil, nil, nil, previous)
    local inverted = english and not questionSubject and not relativeSubject and not continuedAux
        and (aux or copula[invertedCopula])
    if inverted then
        tree.question = true
        if not aux then
            tree.copula, tree.tense, tree.negative = true, copula[invertedCopula], negativeCopula[head] ~= nil
        end
        if not syntheticCopula then index = index + 1 end
    end
    local subject, nextIndex
    local contraction = english and not inverted and contracted[head]
    if questionSubject then
        subject = english and wh.noun or {person=3, number="singular", gender=wh.kind == "person" and "masculine" or "neuter"}
        nextIndex = index
    elseif contraction then
        subject, nextIndex = personalSubject(contraction[1]), index + 1
    elseif not relativeSubject and not continuedAux then
        subject, nextIndex = P.coordinated(document, index, limit, "nominative")
    end
    if inverted and not subject and aux and (aux.modal == "can" or aux.tense == "future")
        and not aux.negative and not wh and headIndex == first
        and not previous and not indirect and not (document.tokens[limit + 1] and document.tokens[limit + 1].key == "?") then
        subject, nextIndex = personalSubject("i"), index
        tree.implicitSubject, tree.question, inverted = true, nil, nil
    end
    if subject then tree.subject, index = subject, nextIndex end
    if english and subject and subject.number == "plural" and not inverted and not wh
        and P.key(document, index, limit) == "welcome" and index == limit then
        return {kind="welcomeGroup", subject=subject}, index + 1
    end
    local current = syntheticCopula or contraction and contraction[2] or P.key(document, index, limit)
    local contractedNegative = negativeCopula[current]
    if contractedNegative then current = contractedNegative end
    if english and subject and not inverted and not contraction and not indirect
        and document.tokens[limit + 1] and document.tokens[limit + 1].key == "?" then
        local ongoing, afterVerb = verb(document, index, limit, subject, false, false, nil, "present")
        if ongoing then
            tree.verb, tree.tense, tree.aspect, tree.question = ongoing, "present", "continuous", true
            local finish = complements(document, tree, afterVerb, limit, depth)
            if finish then return tree, finish end
            return nil
        end
    end
    -- Auxiliary selection is licensed by a participle. A possessive "have"
    -- and an ordinary copula continue through the existing paths.
    local aspectAux = inverted and tree.copula and invertedCopula or not inverted and current
    if english and subject and (have[aspectAux] or copula[aspectAux]) then
        local nextVerb = (inverted or contraction or syntheticCopula) and index or index + 1
        local aspect = have[aspectAux] and "past" or "present"
        local negative = P.key(document, nextVerb, limit) == "not"
        if negative then nextVerb = nextVerb + 1 end
        local adverb, afterAdverb = adverbAt(document, nextVerb, limit)
        if adverb then nextVerb = afterAdverb end
        local candidate, afterVerb = verb(document, nextVerb, limit, subject, false, false, nil, aspect)
        local resultative, passive
        if not candidate and copula[aspectAux] then
            candidate, afterVerb = verb(document, nextVerb, limit, subject, false, false, nil, "resultative")
            resultative = candidate ~= nil
            if not candidate then
                candidate, afterVerb = verb(document, nextVerb, limit, subject, false, false, nil, "passive")
                passive = candidate ~= nil
            end
        end
        if candidate and (not inverted or wh or candidate.lexeme.frame) then
            tree.copula, tree.verb = nil, candidate
            tree.negative = tree.negative or negative or contractedNegative ~= nil
            tree.tense = (have[aspectAux] or resultative) and "past" or copula[aspectAux]
            tree.aspect = passive and "passive" or resultative and "resultative" or have[aspectAux] and "perfect" or "continuous"
            if adverb then tree.leadingAdverb = adverb end
            local finish = complements(document, tree, afterVerb, limit, depth)
            if finish then return tree, finish end
            return nil
        end
    end
    if not inverted then
        if copula[current] then
            tree.copula, tree.tense, tree.negative = true, copula[current], contractedNegative ~= nil
            if not contraction and not syntheticCopula then index = index + 1 end
        elseif auxiliary[current] then
            aux = auxiliary[current]
            if not contraction then index = index + 1 end
        end
    end
    local negative = P.key(document, index, limit)
    if negative == "not" or negative == "не" then
        tree.negative, index = true, index + 1
    end
    if not english and not aux and auxiliary[P.key(document, index, limit)] then
        aux, index = auxiliary[P.key(document, index, limit)], index + 1
    end
    if aux then
        tree.tense, tree.modal, tree.negative = aux.tense, aux.modal,
            tree.negative or aux.negative or (contraction and contraction[4])
        tree.inferred = aux.person and {person=aux.person, number=aux.number} or nil
        local auxiliarySubject = subject or (previous and previous.subject)
        if auxiliarySubject then
            if (aux.person and aux.person ~= auxiliarySubject.person)
                or (aux.number and aux.number ~= auxiliarySubject.number)
                or (aux.gender and auxiliarySubject.gender and aux.gender ~= auxiliarySubject.gender) then return nil end
        elseif not english and aux.modal == "could" then
            return nil
        end
        if aux.ellipsis and index > limit and (subject or tree.inferred) then
            tree.elliptic = true
            return tree, index
        end
    end
    if not english and wh and wh.role == "predicate" then tree.copula = true end
    if english and tree.modal == "might" then
        if tree.where or tree.why or wh then return nil end
        if P.key(document, index, limit) == "be" then
            tree.copula, index = true, index + 1
        end
    elseif not english and subject and P.key(document, index, limit) == "—" then
        tree.copula, index = true, index + 1
    end
    if tree.copula then
        if not subject and relativeSubject then
            subject, tree.subject, tree.inherited = relativeSubject, relativeSubject, true
        end
        if not subject then return nil end
        tree.copula, tree.tense = true, tree.tense or "present"
        if wh and wh.role == "predicate" then
            local gender = subject.number == "plural" and "plural" or subject.gender
            wh.definite = wh.definite or subject.article == "definite" or subject.possessor ~= nil or subject.demonstrative ~= nil
            if tree.tense == "present" and not tree.negative and index > limit
                and (not wh.definite or gender and (not wh.gender or wh.gender == gender)) then return tree, index end
            return nil
        end
        if wh and wh.role == "object" then return nil end
        if english and P.key(document, index, limit) == "off" and P.key(document, index + 1, limit) == "to" then
            local departure, after = verb(document, index, limit, subject, true, nil, nil, nil, "set off")
            if departure then
                local move = {kind="clause", subject=subject, verb=departure, tense=tree.tense,
                    negative=tree.negative, question=tree.question}
                local finish = complements(document, move, after, limit, depth)
                if finish and move.purpose then return move, finish end
            end
        end
        local finish = predicate(document, tree, index, limit, depth)
        if finish then return tree, finish end
        return nil
    end
    local inheritedSubject = not subject and previous and previous.subject
    local inheritedImperative = not subject and previous and previous.imperative
    local sharedModal = inheritedSubject and not aux and previous.modal or nil
    tree.imperative = (not subject and not inheritedSubject and not aux and english) or inheritedImperative
    if inverted and not subject then return nil end
    local afterVerb
    local contractedPredicate = contraction and contraction[3]
    if (subject or inheritedSubject) and not contractedPredicate then
        local adverb, following = adverbAt(document, index, limit)
        if adverb then tree.leadingAdverb, index = adverb, following end
    end
    tree.verb, afterVerb = verb(document, contractedPredicate and headIndex or index, limit,
        subject or inheritedSubject, aux ~= nil or sharedModal ~= nil, tree.imperative, nil, nil,
        contractedPredicate, inheritedSubject and previous)
    if not tree.verb and not subject and not english and not aux then
        tree.verb, afterVerb = verb(document, index, limit, nil, false, true)
        tree.imperative = tree.verb ~= nil
    end
    if not tree.verb and not english and subject and not aux then
        local finish = predicate(document, tree, index, limit)
        if finish then tree.copula, tree.tense = true, "present"; return tree, finish end
    end
    if not tree.verb and english and subject and not (subject.pronoun or subject.genitive or subject.destination)
        and not aux and not tree.question then
        local imperative, after = verb(document, first, limit, nil, false, true, nil, nil, nil, previous)
        if imperative then
            tree, subject, afterVerb = {kind="clause", verb=imperative, imperative=true}, nil, after
            if previous and previous.subject and previous.modal then
                inheritedSubject, sharedModal, tree.imperative = previous.subject, previous.modal, nil
            end
        end
    end
    if not tree.verb and tree.imperative and english and not subject and not aux then
        local past = L.choose(document, index, "verb", {tense="past"}, nil, function(candidate)
            return not candidate.form.verbalForm and not candidate.form.mood
        end)
        if past then
            tree.verb, tree.imperative, tree.ellipticSubject, afterVerb = past, nil, true, index + 1
        end
    end
    if not tree.verb then return nil end
    if english and tree.imperative and not tree.negative and lexemeFrame(tree.verb).impersonalNeed then
        local object, finish = P.coordinated(document, afterVerb, limit, "accusative")
        if object then return {kind="need", object=object}, finish end
        return nil
    end
    tree.subject = subject or inheritedSubject
    tree.inherited = inheritedSubject ~= nil and inheritedSubject ~= false
    tree.modal, tree.sharedModal = tree.modal or sharedModal, sharedModal ~= nil
    tree.tense = tree.tense or tree.verb.form.tense or "present"
    local finish = complements(document, tree, afterVerb, limit, depth)
    if finish then
        if english and not aux and not tree.imperative and tree.verb.form.mood == "base"
            and lexemeFrame(tree.verb).unmarkedPast and explicitTime(tree) == "past" then
            tree.tense = "past"
        end
        return tree, finish
    end
end

local function chooseModalSense(tree, pastContext)
    local time = explicitTime(tree)
    local past = time == "past" or (time ~= "nonpast" and (pastContext or tree.tense == "past"))
    if tree.modal == "could" and tree.verb and lexemeFrame(tree.verb).possibleOutcome
        and tree.subject and not past and not tree.question and not tree.negative then
        tree.modalSense = "possibility"
    end
    if tree.content then
        for _, embedded in ipairs(tree.content) do chooseModalSense(embedded, past) end
    end
end

local relativePrepositions = {about="про кого", ["with"]="з ким", ["for"]="для кого", ["from"]="від кого"}
local function relativeApposition(document, tree, first, limit)
    local antecedent = tree.predicate
    if document.direction ~= "en-uk" or not tree.copula or not antecedent or antecedent.animacy ~= "animate"
        or P.key(document, first, limit) ~= "," or P.key(document, first + 1, limit) ~= "the"
        or P.key(document, first + 2, limit) ~= "one" then return nil end
    local start = first + 3
    local marker = P.key(document, start, limit)
    if marker == "who" or marker == "whom" then start = start + 1 end
    local relative, after = simple(document, start, limit, nil, 1)
    if not relative or not relative.subject or not relative.verb or relative.question or relative.imperative
        or after ~= limit then return nil end
    local linker = relativePrepositions[P.key(document, after, limit)]
    if not linker then return nil end
    return {clause=relative, linker=linker}, after + 1
end

local function profile(document, first, limit)
    if document.direction ~= "en-uk" then return nil end
    local modifiers, index = {}, first
    for _ = 1, 6 do
        if P.key(document, index + 1, limit) ~= "," then break end
        local entry = L.choose(document, index, "adj")
        if not entry then break end
        modifiers[#modifiers + 1], index = {entry=entry}, index + 2
    end
    if #modifiers < 2 then return nil end
    local head, after = P.noun(document, index, limit, "nominative")
    if not head or not head.adjectives or head.pronoun or head.raw or not (head.gender or head.number == "plural") then return nil end
    local place, finish = P.preposition(document, after, limit)
    return {kind="profile", subject=head, modifiers=modifiers, prepositions=place and {place}}, finish or after
end

-- A relative clause fills either the subject slot or the direct object
-- slot of its own predicate. It then reduces together with its antecedent.
function A.relative(document, noun, first, limit)
    local comma = P.key(document, first, limit) == ","
    local markerIndex = first + (comma and 1 or 0)
    local marker = P.key(document, markerIndex, limit)
    if not P.relativeMarkers[document.direction][marker] or markerIndex >= limit
        or document.relativeBudget == 0 or document.relativeDepth >= 3 then return end
    local english = document.direction == "en-uk"
    local person = P.relativeAnimate(noun)
    if english and ((marker == "who" or marker == "whom") and not person or marker == "which" and person) then return end

    local subjectReading = english and marker ~= "whom" or marker == P.relativePronoun(noun, "nominative")
    local oldDepth = document.relativeDepth
    document.relativeDepth = oldDepth + 1
    local selected, ending, role
    local start = markerIndex + 1
    if subjectReading then
        document.relativeBudget = document.relativeBudget - 1
        -- The inherited subject carries agreement only. Keeping the whole
        -- antecedent here would create a cycle in the syntax tree.
        local subject = {person=3, number=noun.number, gender=noun.gender, animacy=noun.animacy}
        local tree, after = simple(document, start, limit, {subject=subject}, oldDepth + 1, true)
        if tree and tree.inherited and tree.kind == "clause" and not tree.question and not tree.imperative then
            selected, ending, role = tree, after, "nominative"
        end
    end
    if document.relativeBudget > 0 then
        document.relativeBudget = document.relativeBudget - 1
        local tree, after = simple(document, start, limit, nil, oldDepth + 1, true, true)
        local case = tree and tree.relativeCase
        if case and tree.subject and not tree.question and not tree.imperative
            and (english or marker == P.relativePronoun(noun, case)) then
            if selected then selected = nil
            else selected, ending, role = tree, after, case end
        end
    end
    document.relativeDepth = oldDepth
    if not selected then return nil end
    if P.key(document, ending, limit) == "," and ending < limit
        and not L.functional(document, "connectors", ending + 1, limit) then
        ending = ending + 1
    end
    return {clause=selected, case=role, nonrestrictive=english and comma}, ending
end

local function parse(document, first, limit)
    local trees, joins = {}, {}
    local prefix, prefixEnd = clauseConnector(document, first, limit)
    if prefix then
        if prefix.id ~= "because" and prefix.id ~= "if" and prefix.id ~= "when"
            and prefix.id ~= "so" and prefix.id ~= "in-case" and prefix.id ~= "while" then prefix = nil end
        if prefix and prefix.id == "if" and P.raw(document, first, first) == "IF"
            and copula[P.key(document, prefixEnd + 1, limit)] then prefix = nil end
    end
    local index = prefix and prefixEnd + 1 or first
    for _ = 1, 4 do
        local precedingJoin = joins[#joins]
        local previous
        if precedingJoin and precedingJoin.rule
            and (precedingJoin.rule.id == "and" or precedingJoin.rule.id == "or" or precedingJoin.rule.id == "then") then
            previous = trees[#trees]
        end
        local tree, after = simple(document, index, limit, previous, 0)
        if precedingJoin and precedingJoin.sentence and not (tree and tree.subject and tree.verb and not tree.question) then
            return nil
        end
        if not tree and not prefix and #trees == 0 then
            tree, after = profile(document, index, limit)
        end
        if not tree and not prefix and #trees == 0 then
            local phrase, ending = adverbAt(document, index, limit)
            if phrase and phrase.standalone then
                local comma = P.key(document, ending, limit) == ","
                local pp, finish = P.preposition(document, ending + (comma and 1 or 0), limit)
                if ending > limit or pp and finish > limit then
                    tree, after = {kind="adverbPhrase", expression=phrase, prepositions=pp and {pp}, comma=comma}, finish or ending
                end
            end
        end
        if not tree and not prefix and #trees == 0 then
            local listing, ending = P.coordinated(document, index, limit, "nominative", nil, nil, true)
            if listing and listing.members and ending > limit then
                tree, after = {kind="nounPhrase", subject=listing}, ending
            end
        end
        if not tree and not prefix and #trees == 0 then
            local noun, ending = P.noun(document, index, limit, "nominative")
            if noun then
                if document.direction == "en-uk" and ending <= limit then
                    local modifier, following = verb(document, ending, limit, noun, false, false, nil, "present")
                    if modifier and lexemeFrame(modifier).description then
                        local action = {kind="clause", subject=noun, inherited=true, tense="present", verb=modifier}
                        local finish = complements(document, action, following, limit)
                        if finish and action.object then tree, after = {kind="description", subject=noun, action=action}, finish end
                    end
                end
                if not tree then
                    local pp, finish = P.preposition(document, ending, limit)
                    if pp or ((noun.adjectives or noun.possessor or noun.nominalObject or noun.genitive or noun.destination)
                        and ending > limit) then
                        tree, after = {kind="nounPhrase", subject=noun, prepositions=pp and {pp}}, finish or ending
                    end
                end
            else
                local pp, finish = P.preposition(document, index, limit)
                if pp and finish > limit then tree, after = {kind="nounPhrase", prepositions={pp}}, finish end
            end
        end
        if not tree or after <= index then break end
        local relative, relativeEnd = relativeApposition(document, tree, after, limit)
        if relative then tree.relativeApposition, after = relative, relativeEnd end
        if tree.kind == "clause" and P.key(document, after, limit) == "," then
            local addressee, finish = P.noun(document, after + 1, limit, "vocative")
            if addressee and addressee.term and addressee.term.category == "addresses" and finish > limit then
                tree.addressee, after = addressee, finish
            end
        end
        if tree.imperative and tree.object and after <= limit then
            local boundaryToken, precedingToken = document.tokens[after], document.tokens[after - 1]
            local comma = boundaryToken.key == ","
            if comma or boundaryToken.first - precedingToken.last > 2 then
                local tail, finish = P.noun(document, after + (comma and 1 or 0), limit, "nominative")
                if tail and finish > limit and tail.term and tail.term.features and tail.term.features.apposition then
                    tree.apposition, after = tail, finish
                end
            end
        end
        trees[#trees + 1] = tree
        index = after
        if index > limit then break end
        local token = document.tokens[index]
        local comma = token.key == ","
        local dash = token.key == "—" or token.key == "–"
            or token.key == "-" and token.first > document.tokens[index - 1].last + 1
                and index < limit and document.tokens[index + 1].first > token.last + 1
        local found, last = clauseConnector(document, index + ((comma or dash) and 1 or 0), limit)
        if found and last < limit then
            joins[#joins + 1] = {rule=found, comma=comma, dash=dash}
            index = last + 1
        elseif prefix and #trees == 1 and comma and index < limit then
            joins[#joins + 1] = {comma=true}
            index = index + 1
        elseif tree.kind == "salute" and comma and index < limit then
            joins[#joins + 1] = {sentence=true, punctuation="!"}
            index = index + 1
        elseif tree.imperative and document.direction == "en-uk"
            and P.pronoun(document, index + (comma and 1 or 0), limit, "nominative", true) then
            joins[#joins + 1] = {sentence=true}
            if comma then index = index + 1 end
        else break end
    end
    if #trees == 0 or #joins >= #trees or index <= limit then return nil end
    if document.direction == "en-uk" then
        local pastContext = false
        for _, tree in ipairs(trees) do
            if tree.tense == "past" or explicitTime(tree) == "past" then pastContext = true; break end
        end
        for _, tree in ipairs(trees) do chooseModalSense(tree, pastContext) end
    end
    return {trees=trees, joins=joins, prefix=prefix}
end

local function parseWithRelatives(document, first, limit)
    local parsed = parse(document, first, limit)
    if parsed then return parsed end
    local markers = P.relativeMarkers[document.direction]
    for index = first + 1, limit - 1 do
        local token = document.tokens[index]
        if not token.protected and markers[token.key] then
            document.relativeBudget, document.relativeDepth = 16, 0
            parsed = parse(document, first, limit)
            document.relativeBudget, document.relativeDepth = nil, nil
            return parsed
        end
    end
end



local temporalRules = {
    {en={"before"}, uk={"перш ніж"}, temporal=true},
    {en={"after"}, uk={"після того як"}, temporal=true},
    {en={"until"}, uk={"доки"}, temporal=true},
    {en={"once"}, uk={"щойно"}, temporal=true},
}

local function temporalMarker(document, first, limit)
    local source = document.direction == "en-uk" and "en" or "uk"
    for _, rule in ipairs(temporalRules) do
        local index = first
        for word in rule[source][1]:gmatch("%S+") do
            if P.key(document, index, limit) ~= word then index = nil; break end
            index = index + 1
        end
        if index and index <= limit then return rule, index - 1 end
    end
end

local function finiteClause(parsed, dependent)
    if not parsed or parsed.prefix then return false end
    local tree = parsed.trees[1]
    return tree.kind == "clause" and (tree.verb or tree.copula) and (not dependent or not tree.imperative)
end

local function confirmedAttachment(arcs, offset, start, finish, subordinateFirst, subordinateLast, mainFirst, mainLast)
    for marker = start, finish do
        local arc = arcs[marker - offset]
        if arc and arc.relation == "mark" and arc.head > 0 then
            local dependent = arc.head + offset
            local predicate = arcs[arc.head]
            local parent = predicate.head + offset
            if dependent >= subordinateFirst and dependent <= subordinateLast
                and predicate.relation:match("^advcl") and predicate.head > 0
                and parent >= mainFirst and parent <= mainLast then return true end
        end
    end
    return false
end

local function joined(left, right, junction, prefix)
    local subordinate = prefix and left or right
    for _, tree in ipairs(subordinate.trees) do tree.temporalDependent = true end
    local trees, joins = {}, {}
    for _, tree in ipairs(left.trees) do trees[#trees + 1] = tree end
    for _, tree in ipairs(right.trees) do trees[#trees + 1] = tree end
    for _, join in ipairs(left.joins) do joins[#joins + 1] = join end
    joins[#joins + 1] = junction
    for _, join in ipairs(right.joins) do joins[#joins + 1] = join end
    return {trees=trees, joins=joins, prefix=prefix, dependency=true}
end

local function temporalAttachment(document, first, limit)
    local parser = ns.Engine.UDPipe
    if not parser or not ns.UDPipeModels or document.udpipeUsed or limit - first >= 32 then return nil end
    local attempts = 0
    for marker = first, limit - 1 do
        local rule, markerEnd = temporalMarker(document, marker, limit)
        if rule then
            local subordinateFirst = markerEnd + 1
            if marker == first then
                for separator = subordinateFirst + 1, limit - 1 do
                    if P.key(document, separator, limit) == "," then
                        attempts = attempts + 1
                        if attempts > 4 then return nil end
                        local dependent = parseWithRelatives(document, subordinateFirst, separator - 1)
                        local main = finiteClause(dependent, true) and parseWithRelatives(document, separator + 1, limit)
                        if finiteClause(main) then
                            document.udpipeUsed = true
                            local arcs = parser.analyzeDocument(document, first, limit, marker, markerEnd)
                            if arcs and confirmedAttachment(arcs, first - 1, marker, markerEnd,
                                subordinateFirst, separator - 1, separator + 1, limit) then
                                return joined(dependent, main, {comma=true}, rule)
                            end
                            return nil
                        end
                    end
                end
            else
                attempts = attempts + 1
                if attempts > 4 then return nil end
                local comma = P.key(document, marker - 1, limit) == ","
                local mainEnd = marker - (comma and 2 or 1)
                if mainEnd >= first then
                    local main = parseWithRelatives(document, first, mainEnd)
                    local dependent = finiteClause(main) and parseWithRelatives(document, subordinateFirst, limit)
                    if finiteClause(dependent, true) then
                        document.udpipeUsed = true
                        local arcs = parser.analyzeDocument(document, first, limit, marker, markerEnd)
                        if arcs and confirmedAttachment(arcs, first - 1, marker, markerEnd,
                            subordinateFirst, limit, first, mainEnd) then
                            return joined(main, dependent, {rule=rule})
                        end
                        return nil
                    end
                end
            end
        end
    end
end

function A.parse(document, first, limit)
    return parseWithRelatives(document, first, limit) or temporalAttachment(document, first, limit)
end
