local _, ns = ...
local A = {}
ns.Engine.ClauseAnalysis = A
local P, L = ns.Engine.Phrases, ns.Engine.Lexicon

local function lexemeFrame(entry)
    return entry.lexeme.frame or {}
end

local copula = {am="present", is="present", are="present", was="past", were="past",
    ["є"]="present", ["був"]="past", ["була"]="past", ["було"]="past", ["були"]="past"}
local negativeCopula = {["isn't"]="is", ["aren't"]="are", ["wasn't"]="was", ["weren't"]="were"}
local have = {have=true, has=true, had=true}
local contracted = {
    ["i'm"]={"i","am"}, ["you're"]={"you","are"}, ["we're"]={"we","are"}, ["they're"]={"they","are"},
    ["i've"]={"i","have"}, ["you've"]={"you","have"}, ["we've"]={"we","have"}, ["they've"]={"they","have"},
    ["i'll"]={"i","will"}, ["you'll"]={"you","will"}, ["he'll"]={"he","will"}, ["she'll"]={"she","will"},
    ["it'll"]={"it","will"}, ["we'll"]={"we","will"}, ["they'll"]={"they","will"},
}
local auxiliary = {
    can={modal="can"}, cannot={modal="can", negative=true}, ["can't"]={modal="can", negative=true},
    could={modal="could"}, ["couldn't"]={modal="could", negative=true},
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

local function verb(document, index, limit, subject, base, imperative, sense, aspect, headword)
    if index > limit then return nil end
    local english = document.direction == "en-uk"
    local after = index + 1
    if english and not headword and P.key(document, after, limit) == "off" then
        local key = P.key(document, index, limit)
        if key == "set" or key == "sets" or key == "setting" then
            headword, after = key .. " off", after + 1
        end
    end
    local selected = L.choose(document, headword or index, "verb", nil, sense, function(candidate)
        local f = candidate.form
        if aspect then return f.verbalForm == "participle" and f.tense == aspect end
        if f.verbalForm then return false end
        if english then
            if base or imperative then return f.mood == "base" end
            if f.mood == "base" then
                return not subject or subject.person ~= 3 or subject.number == "plural"
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

local function adverbAt(document, first, limit)
    local rows, last = L.functional(document, "adverbs", first, limit)
    if not rows or last > limit then return nil end
    local adverb = ns.Linguistics.grammar.adverbs[rows[1]]
    if not adverb.context then return adverb, last + 1 end
end

local function boundary(document, index, limit)
    local key = P.key(document, index, limit)
    return index > limit or key == "," or key == ";" or L.functional(document, "connectors", index, limit)
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
local function complements(document, tree, index, limit, depth)
    depth = depth or 0
    local frame = lexemeFrame(tree.verb)
    local english = document.direction == "en-uk"
    local preposition
    if not english and frame.objectPreposition and P.key(document, index, limit) == frame.objectPreposition then
        preposition = true
        index = index + 1
    end
    local objectCase = english and "accusative" or frame.objectCase or "accusative"
    if frame.content and depth < 3 then
        local marker = english and "that" or "що"
        local start = index
        if not english and P.key(document, start, limit) == "," then start = start + 1 end
        if P.key(document, start, limit) == marker then
            local embedded, finish = simple(document, start + 1, limit, nil, depth + 1)
            if embedded and embedded.subject and not embedded.imperative and not embedded.question then
                tree.content = {embedded}
                index = finish
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
    if frame.recipientCase then
        recipient, after = P.noun(document, index, limit, english and "accusative" or frame.recipientCase)
        if recipient then
            local object, last = P.coordinated(document, after, limit, objectCase)
            if object then tree.recipient, tree.object, index = recipient, object, last end
        end
    end
    if not tree.object and not frame.motion and (english or not frame.objectPreposition or preposition) then
        local object, nextIndex = P.coordinated(document, index, limit, objectCase)
        if object then tree.object, index = object, nextIndex
        elseif preposition then return nil end
    end
    if not tree.object and frame.infinitive and depth < 3 then
        local marker = P.key(document, index, limit)
        if not english or marker == "to" then
            local verbIndex = english and index + 1 or index
            local embedded, after = verb(document, verbIndex, limit, nil, true)
            if embedded then
                tree.infinitive = {verb=embedded, tense="infinitive"}
                local finish = complements(document, tree.infinitive, after, limit, depth + 1)
                if not finish then return nil end
                index = finish
            end
        end
    end
    for _ = 1, 3 do
        if depth < 3 and not tree.purpose then
            local start, negative = purposeStart(document, index, limit, frame.motion or frame.contact)
            if start and not negative then
                local activity, finish = smallActivity(document, start, limit)
                if activity then tree.purpose = activity; return finish end
            end
            if start then
                local predicateVerb, after = verb(document, start, limit, nil, true)
                if predicateVerb then
                    local purpose = {verb=predicateVerb, tense="infinitive", negative=negative, purposeClause=true}
                    local finish = complements(document, purpose, after, limit, depth + 1)
                    if finish then tree.purpose = purpose; return finish end
                end
            end
        end
        if boundary(document, index, limit) then break end
        local pp, last = P.preposition(document, index, limit, frame.motion)
        if pp then
            local entry = pp.object.entry
            if english and tree.object and not tree.purpose and pp.rule.id == "for" and entry
                and frame.goalObjects and frame.goalObjects[entry.lexeme.en] then
                tree.purpose = {object=pp.object}
            else
                tree.prepositions = tree.prepositions or {}
                tree.prepositions[#tree.prepositions + 1] = pp
            end
            index = last
        else
            local adverb, endAt = adverbAt(document, index, limit)
            if not adverb then break end
            tree.adverbs = tree.adverbs or {}
            tree.adverbs[#tree.adverbs + 1] = adverb
            index = endAt
        end
    end
    return index
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

local function predicate(document, tree, index, limit)
    local pp, finish = P.preposition(document, index, limit)
    if pp then tree.prepositions = {pp}; return finish end
    if index > limit then return tree.where and index end
    if tree.where then return nil end
    local modifier = P.key(document, index, limit)
    local intensity
    if modifier == "more" or modifier == "більш" or modifier == "very" or modifier == "дуже" then
        intensity = (modifier == "more" or modifier == "більш") and "more" or "very"
        index = index + 1
    end
    local adjective = index <= limit and L.choose(document, index, "adj")
    local object, nextIndex = P.noun(document, index, limit, "nominative")
    if object and (not intensity or not adjective) then tree.predicate = object; return nextIndex end
    if adjective then tree.adjective = {entry=adjective, intensity=intensity}; return index + 1 end
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

simple = function(document, first, limit, previous, depth)
    local english = document.direction == "en-uk"
    local key = P.key(document, first, limit)
    local special, after = duration(document, first, limit)
    if special then return special, after end
    special, after = wish(document, first, limit)
    if special then return special, after end
    local tree, index = {kind="clause"}, first
    if key == "where" or key == "де" then
        tree.where, tree.question, index = true, true, index + 1
    elseif key == "why" or key == "чому" then
        tree.why, tree.question, index = true, true, index + 1
    elseif key == "чи" and not english then
        tree.question, index = true, index + 1
    end
    local head = P.key(document, index, limit)
    local aux
    if english then aux = auxiliary[head] end
    local invertedCopula = negativeCopula[head] or head
    local inverted = english and (aux or copula[invertedCopula])
    if inverted then
        tree.question = true
        if not aux then
            tree.copula, tree.tense, tree.negative = true, copula[invertedCopula], negativeCopula[head] ~= nil
        end
        index = index + 1
    end
    local subject, nextIndex
    local contraction = english and not inverted and contracted[head]
    if contraction then
        for _, pronoun in ipairs(ns.Linguistics.grammar.pronouns) do
            if pronoun.id == contraction[1] then
                subject = {pronoun=pronoun, person=pronoun.person, number=pronoun.number, gender=pronoun.gender}
                nextIndex = index + 1
                break
            end
        end
    else
        subject, nextIndex = P.coordinated(document, index, limit, "nominative")
    end
    if subject then tree.subject, index = subject, nextIndex end
    local current = contraction and contraction[2] or P.key(document, index, limit)
    local contractedNegative = negativeCopula[current]
    if contractedNegative then current = contractedNegative end
    -- Auxiliary selection is licensed by a participle. A possessive "have"
    -- and an ordinary copula continue through the existing paths.
    if english and subject and (have[current] or copula[current]) then
        local nextVerb = contraction and index or index + 1
        local aspect = have[current] and "past" or "present"
        local negative = P.key(document, nextVerb, limit) == "not"
        if negative then nextVerb = nextVerb + 1 end
        local adverb, afterAdverb = adverbAt(document, nextVerb, limit)
        if adverb then nextVerb = afterAdverb end
        local candidate, afterVerb = verb(document, nextVerb, limit, subject, false, false, nil, aspect)
        if candidate then
            tree.verb, tree.negative = candidate, negative or contractedNegative ~= nil
            tree.tense = have[current] and "past" or copula[current]
            tree.aspect = have[current] and "perfect" or "continuous"
            if adverb then tree.leadingAdverb = adverb end
            local finish = complements(document, tree, afterVerb, limit, depth)
            if finish then return tree, finish end
            return nil
        end
    end
    if not inverted then
        if copula[current] then
            tree.copula, tree.tense, tree.negative = true, copula[current], contractedNegative ~= nil
            if not contraction then index = index + 1 end
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
        tree.tense, tree.modal, tree.negative = aux.tense, aux.modal, tree.negative or aux.negative
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
    if tree.copula then
        if not subject then return nil end
        tree.copula, tree.tense = true, tree.tense or "present"
        if english and P.key(document, index, limit) == "off" and P.key(document, index + 1, limit) == "to" then
            local departure, after = verb(document, index, limit, subject, true, nil, nil, nil, "set off")
            if departure then
                local move = {kind="clause", subject=subject, verb=departure, tense=tree.tense,
                    negative=tree.negative, question=tree.question}
                local finish = complements(document, move, after, limit, depth)
                if finish and move.purpose then return move, finish end
            end
        end
        local finish = predicate(document, tree, index, limit)
        if finish then return tree, finish end
        return nil
    end
    local inheritedSubject = not subject and previous and previous.subject
    local inheritedImperative = not subject and previous and previous.imperative
    tree.imperative = (not subject and not inheritedSubject and not aux and english) or inheritedImperative
    if inverted and not subject then return nil end
    local afterVerb
    tree.verb, afterVerb = verb(document, index, limit, subject or inheritedSubject, aux ~= nil, tree.imperative)
    if not tree.verb and not subject and not english and not aux then
        tree.verb, afterVerb = verb(document, index, limit, nil, false, true)
        tree.imperative = tree.verb ~= nil
    end
    if not tree.verb and not english and subject and not aux then
        local finish = predicate(document, tree, index, limit)
        if finish then tree.copula, tree.tense = true, "present"; return tree, finish end
    end
    if not tree.verb and english and subject and not aux and not tree.question then
        local imperative, after = verb(document, first, limit, nil, false, true)
        if imperative then
            local command = {kind="clause", verb=imperative, imperative=true}
            local finish = complements(document, command, after, limit, depth)
            if finish then return command, finish end
        end
    end
    if not tree.verb then return nil end
    tree.subject = subject or inheritedSubject
    tree.inherited = inheritedSubject ~= nil and inheritedSubject ~= false
    tree.tense = tree.tense or tree.verb.form.tense or "present"
    local finish = complements(document, tree, afterVerb, limit, depth)
    if finish then return tree, finish end
end

local function explicitTime(tree)
    if tree.leadingAdverb and tree.leadingAdverb.time then return tree.leadingAdverb.time end
    if tree.adverbs then
        for _, adverb in ipairs(tree.adverbs) do
            if adverb.time then return adverb.time end
        end
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

function A.parse(document, first, limit)
    local trees, joins = {}, {}
    local prefix, prefixEnd = L.functional(document, "connectors", first, limit)
    if prefix then
        prefix = ns.Linguistics.grammar.connectors[prefix[1]]
        if prefix.id ~= "because" and prefix.id ~= "if" and prefix.id ~= "when" then prefix = nil end
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
        if not tree and not prefix and #trees == 0 then
            local noun, ending = P.noun(document, index, limit, "nominative")
            if noun then
                local pp, finish = P.preposition(document, ending, limit)
                if pp or ((noun.adjectives or noun.possessor or noun.nominalObject) and ending > limit) then
                    tree, after = {kind="nounPhrase", subject=noun, prepositions=pp and {pp}}, finish or ending
                end
            else
                local pp, finish = P.preposition(document, index, limit)
                if pp and finish > limit then tree, after = {kind="nounPhrase", prepositions={pp}}, finish end
            end
        end
        if not tree or after <= index then break end
        trees[#trees + 1] = tree
        index = after
        if index > limit then break end
        local comma = P.key(document, index, limit) == ","
        local found, last = L.functional(document, "connectors", index + (comma and 1 or 0), limit)
        if found and last < limit then
            joins[#joins + 1] = {rule=ns.Linguistics.grammar.connectors[found[1]], comma=comma}
            index = last + 1
        elseif prefix and #trees == 1 and comma and index < limit then
            joins[#joins + 1] = {comma=true}
            index = index + 1
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

function A.hasClauseCue(document)
    local tokens = document.tokens
    if #tokens < 2 then return false end
    if document.direction == "en-uk" and tokens[1].key == "any" then return true end
    for index = 1, #tokens - 1 do
        local key = tokens[index].key
        if contracted[key] or (index > 1 and (auxiliary[key] or copula[key] or negativeCopula[key])) then
            return true
        end
    end
    local key = tokens[#tokens].key
    return auxiliary[key] ~= nil or negativeCopula[key] ~= nil
end
