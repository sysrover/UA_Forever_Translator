local _, ns = ...
local A = {}
ns.Engine.ClauseAnalysis = A
local P, L = ns.Engine.Phrases, ns.Engine.Lexicon
local spatialAdjuncts = {["in"]=true, on=true, near=true, ["on-layer"]=true,
    ["at-landmark"]=true, ["at-near-landmark"]=true}

local function lexemeFrame(entry)
    return entry.lexeme.frame or {}
end

local function personNoun(noun)
    local pronoun = noun and noun.pronoun
    return noun and (P.relativeAnimate(noun) or pronoun and not (pronoun.inanimate or pronoun.id == "it"))
end

local function deicticSubject(noun)
    local id = noun and noun.pronoun and noun.pronoun.id
    return id == "it" or id == "this" or id == "that"
end

local function controlledStart(document, first, limit, frame)
    local english = document.direction == "en-uk"
    local case = english and "accusative" or frame.controlCase
    local actor, index = P.pronoun(document, first, limit, case, true)
    if not actor then actor, index = P.noun(document, first, limit, case) end
    if not actor or (actor.pronoun and (actor.pronoun.id == "it" or actor.pronoun.inanimate))
        or not (actor.pronoun or actor.animacy == "animate") then return nil end
    local negative = P.key(document, index, limit) == (english and "not" or "не")
    if negative then index = index + 1 end
    if english and frame.controlTo then
        if P.key(document, index, limit) == "to" then index = index + 1
        elseif not frame.bareInfinitive then return nil end
        if not negative and P.key(document, index, limit) == "not" then
            negative, index = true, index + 1
        end
    end
    if index <= limit then return actor, index, negative end
end

local function personalSubject(id)
    for _, pronoun in ipairs(ns.Linguistics.grammar.pronouns) do
        if pronoun.id == id then
            return {pronoun=pronoun, person=pronoun.person, number=pronoun.number, gender=pronoun.gender}
        end
    end
end

local possessivePronouns = {my="i", your="you", his="he", her="she", our="we", their="they"}

local copula = {am="present", is="present", are="present", was="past", were="past",
    ["є"]="present", ["був"]="past", ["була"]="past", ["було"]="past", ["були"]="past"}
local negativeCopula = {["isn't"]="is", ["aren't"]="are", ["wasn't"]="was", ["weren't"]="were"}
local have = {have=true, has=true, had=true}
local negativePerfect = {["haven't"]="have", ["hasn't"]="has", ["hadn't"]="had"}
local contracted = {
    idk={"i","do","know",true},
    ["i'm"]={"i","am"}, ["you're"]={"you","are"}, youre={"you","are"}, ["we're"]={"we","are"}, ["they're"]={"they","are"},
    ["he's"]={"he","is"}, ["she's"]={"she","is"}, ["it's"]={"it","is"}, ["that's"]={"that","is"},
    ["i've"]={"i","have"}, ["you've"]={"you","have"}, ["we've"]={"we","have"}, ["they've"]={"they","have"},
    ["i'll"]={"i","will"}, ["you'll"]={"you","will"}, ["he'll"]={"he","will"}, ["she'll"]={"she","will"},
    ["it'll"]={"it","will"}, ["we'll"]={"we","will"}, ["they'll"]={"they","will"},
}
contracted.im = contracted["i'm"]
contracted.il = contracted["i'll"]
contracted.thats = contracted["that's"]
local indefiniteContractions = {
    ["someone's"]="someone", ["somebody's"]="someone", ["anyone's"]="someone", ["anybody's"]="someone",
    ["everyone's"]="everyone", ["everybody's"]="everyone",
}
local auxiliary = {
    can={modal="can"}, cannot={modal="can", negative=true}, ["can't"]={modal="can", negative=true},
    could={modal="could"}, ["couldn't"]={modal="could", negative=true},
    might={modal="might"},
    must={modal="must"}, should={modal="should"}, ["shouldn't"]={modal="should", negative=true},
    would={ability="conditional"}, ["wouldn't"]={ability="conditional", negative=true},
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

local function abilityReading(document, index, requested)
    return L.choose(document, index, "verb", requested, nil, function(candidate)
        local form = candidate.form
        return candidate.lexeme.uk == "змогти" and candidate.lexeme.en == "be able to"
            and not form.verbalForm and not form.mood
            and (form.tense == "past" or form.tense == "future")
    end)
end

local function inflectedAbility(document, index, limit)
    local particle = P.key(document, index, limit)
    local preposed = particle == "б" or particle == "би"
    if preposed then index = index + 1 end
    local negative = preposed and P.key(document, index, limit) == "не"
    if negative then index = index + 1 end
    local entry = abilityReading(document, index)
    if not entry then return end
    local form, after = entry.form, index + 1
    if preposed and form.tense ~= "past" then return end
    particle = P.key(document, after, limit)
    local postposed = form.tense == "past" and (particle == "б" or particle == "би")
    local conditional, gender = preposed or postposed, form.gender
    if preposed and postposed then return end
    if postposed then after = after + 1 end
    if form.tense == "past" and gender == "masculine" and P.key(document, after, limit) == "/" then
        local feminine = abilityReading(document, after + 1, {tense="past", number="singular", gender="feminine"})
        local alternativeParticle = P.key(document, after + 2, limit)
        local alternativePostposed = alternativeParticle == "б" or alternativeParticle == "би"
        if feminine and postposed == alternativePostposed then
            gender, after = nil, after + (alternativePostposed and 3 or 2)
        end
    end
    if after <= limit then
        return {ability=conditional and "conditional" or form.tense, modal="can", tense=form.tense,
            person=form.person, number=form.number, gender=gender, negative=negative}, after
    end
end

local function abilityComplementStart(document, index, limit, finiteCopula)
    local at = finiteCopula and index or index + 1
    if (finiteCopula or P.key(document, index, limit) == "be")
        and P.key(document, at, limit) == "able" and P.key(document, at + 1, limit) == "to" then
        return at + 2
    end
end

local function craftingObject(document, first, limit)
    local token = document.tokens[first]
    if first <= limit and token.linkKind == "item" then return true end
    local noun = P.noun(document, first, limit, "accusative")
    return noun and noun.term and noun.term.category == "goods"
end

local function afterObjectMarker(document, index, limit, marker)
    local nextIndex = index
    for word in marker:gmatch("%S+") do
        local key = P.key(document, nextIndex, limit)
        local variant = word == "з" and (key == "із" or key == "зі")
            or word == "у" and key == "в" or word == "в" and key == "у"
        if not variant and key ~= word and key ~= ns.Engine.Normalize.word(word) then return nil end
        nextIndex = nextIndex + 1
    end
    if nextIndex > index then return nextIndex end
end

local function requiredUkComplement(frame)
    -- A discourse frame can recover the omitted complement from the preceding clause.
    if not frame.contextRole then return frame.ukImplicitObject end
end

local function verbObjectMarker(document, index, limit, frame)
    if document.direction == "en-uk" then
        if frame.enObjectPreposition then return afterObjectMarker(document, index, limit, frame.enObjectPreposition) end
    elseif frame.ukObjectCases then
        local key = P.key(document, index, limit)
        if key == "в" then key = "у" end
        local case = frame.ukObjectCases[key]
        if case then return index + 1, case end
    elseif frame.objectPreposition then
        return afterObjectMarker(document, index, limit, frame.objectPreposition)
    end
end

local propertyDegrees = {very="very", so="so", too="too", more="more",
    ["дуже"]="very", ["так"]="so", ["настільки"]="so", ["надто"]="too", ["більш"]="more"}

local function propertyAt(document, index, limit, case, subject)
    if index > limit then return nil end
    local english = document.direction == "en-uk"
    local degree = propertyDegrees[P.key(document, index, limit)]
    if degree then index = index + 1 end
    if index > limit then return nil end
    local forms = ns.Linguistics.propertyAdverbs
    local function allowed(candidate)
        local frame = lexemeFrame(candidate)
        return not frame.profileOnly and (not english or case ~= "adverb" or forms and forms.forms[candidate.lexeme.uk])
    end
    local adjective, finish
    if not english and case == "adverb" then
        local key = P.key(document, index, limit)
        for _, lemma in ipairs(forms and forms.lemmas[key] or {}) do
            local candidate = L.choose(document, lemma, "adj", {case="nominative"}, nil, allowed)
            if candidate then
                if adjective and candidate.lexeme.en ~= adjective.lexeme.en then return nil end
                adjective = candidate
            end
        end
    else
        local requested = not english and {case=case, number=subject and subject.number,
            gender=subject and subject.number ~= "plural" and subject.gender or nil} or nil
        if not english then
            adjective = L.genderPair(document, index, limit, "adj", requested, nil, allowed)
            if adjective then finish = index + 3 end
        end
        adjective = adjective or L.choose(document, index, "adj", requested, nil, allowed)
    end
    if adjective then return {entry=adjective, intensity=degree}, finish or index + 1 end
end

local function subjectReading(document, subject, frame)
    if subject and subject.headIndex and frame.subjectSense then
        return L.choose(document, subject.headIndex, "noun", {number=subject.number}, frame.subjectSense)
    end
end

local function refineSubject(document, subject, frame)
    local reading = subjectReading(document, subject, frame)
    if reading then
        subject.entry, subject.term = reading, nil
        subject.gender, subject.animacy = reading.head.gender, reading.head.animacy
    end
end

local function agreeingSubjectReading(document, subject, form)
    if not subject.headIndex or not subject.entry or not form.number or form.number == subject.number
        or subject.adjectives or subject.possessor or subject.quantity or subject.demonstrative then return nil end
    return L.choose(document, subject.headIndex, "noun", {case="nominative", number=form.number}, nil,
        function(candidate) return candidate.id == subject.entry.id end)
end

local function agreeSubject(document, subject, form)
    local reading = subject and agreeingSubjectReading(document, subject, form)
    if reading then subject.entry, subject.number = reading, reading.form.number end
end

local function recipientAt(document, index, limit, case, separateGenitiveObject)
    if document.direction == "uk-en" then
        local person, after = P.pronoun(document, index, limit, case, true)
        if person then return person, after end
    end
    return P.noun(document, index, limit, case, false, nil, separateGenitiveObject)
end

local function contentRecipientAt(document, index, limit, frame)
    local case = document.direction == "en-uk" and "accusative" or frame.contentRecipientCase
    local recipient, after = recipientAt(document, index, limit, case)
    if recipient and (recipient.pronoun or P.relativeAnimate(recipient)) then return recipient, after end
end

local function objectRecipientAt(document, index, limit, frame, objectCase)
    local english = document.direction == "en-uk"
    if not english and frame.possessorRecipient and P.key(document, index, limit) == "собі" then
        return {reflexive=true}, index + 1
    end
    local case = english and "accusative" or frame.recipientCase
    return recipientAt(document, index, limit, case, not english and objectCase == "genitive")
end

local adverbAt
local function measureAt(document, index, limit, frame)
    local english = document.direction == "en-uk"
    local marker = english and frame.measurePreposition
    if not english then marker = "на" end
    if not marker or P.key(document, index, limit) ~= marker then return nil end
    local quantity, after = P.quantity(document, index + 1, limit)
    if not quantity then return nil end
    if not english and frame.ukMeasureSuffix then
        if P.key(document, after, limit) ~= frame.ukMeasureSuffix then return nil end
        after = after + 1
    end
    return quantity, after
end

local function gradedAdverbAt(document, first, limit, context)
    local degrees, last = L.functional(document, "degrees", first, limit)
    if degrees then
        local degree = ns.Linguistics.grammar.degrees[degrees[1]]
        local adverb, after = adverbAt(document, last + 1, limit, context)
        if adverb and (context and adverb.context == context or not context and adverb.gradable)
            and (not degree.context or degree.context == context)
            and (not degree.comparativeOnly or adverb.comparative) then
            return {en={degree.en[1] .. " " .. (adverb.predicateEn or adverb.en[1])},
                uk={degree.uk[1] .. " " .. adverb.uk[1]}, intensified=true}, after
        end
    end
    if context then
        local adverb, after = adverbAt(document, first, limit, context)
        if adverb and adverb.context == context then return adverb, after end
    end
end

local function hasVerbForm(document, first, limit, form)
    if first > limit then return false end
    local phrase = L.phraseAt(document, first, limit, "verb")
    local entry, status = L.choose(document, phrase or first, "verb", form)
    -- The full complement resolves the lexical reading once its arguments are available.
    return entry ~= nil or status == "ambiguous"
end

local function objectDomain(document, index, limit, frame)
    local domains = frame.objectDomainByAdjunctClass
    if not domains then return nil end
    for start = index + 1, math.min(index + 12, limit - 1) do
        local key = P.key(document, start, limit)
        if key == "for" or key == "для" then
            local budget = document.relativeBudget
            local adjunct = P.preposition(document, start, limit)
            document.relativeBudget = budget
            local domain = adjunct and domains[P.semanticClass(adjunct.object)]
            if domain then return domain end
        elseif key and key:match("^[.!?;]$") then break end
    end
end

local function verb(document, index, limit, subject, base, imperative, sense, aspect, headword, previous)
    if index > limit then return nil end
    local english = document.direction == "en-uk"
    local after = index + 1
    local function compatible(candidate, separatedObject)
        local f = candidate.form
        local frame = lexemeFrame(candidate)
        if frame.subjectClasses and (english or frame.reverseSubjectClasses)
            and not frame.subjectClasses[P.semanticClass(subject)] then
            local reading = subjectReading(document, subject, frame)
            if not reading or not frame.subjectClasses[lexemeFrame(reading).semanticClass] then return false end
        end
        if english and frame.resultativeOnly and aspect ~= "resultative" then return false end
        if frame.contentRecipientCase and not contentRecipientAt(document, after, limit, frame) then return false end
        if not english and frame.requiresObjectMarker
            and not verbObjectMarker(document, after, limit, frame) then return false end
        if not english and frame.requiresContentMarker then
            local marker = after + (P.key(document, after, limit) == "," and 1 or 0)
            if P.key(document, marker, limit) ~= "що" then return false end
        end
        if frame.boundAdverb and not gradedAdverbAt(document, after, limit, frame.boundAdverb) then return false end
        if english and frame.rejectDirectObject and P.noun(document, after, limit, "accusative", false, nil, true) then
            return false
        end
        local required = not english and requiredUkComplement(frame)
        if required and not afterObjectMarker(document, after, limit, required) then return false end
        if frame.requiresSharedSubject and not (previous and previous.subject) then return false end
        if english and frame.subjectPronouns
            and not (subject and subject.pronoun and frame.subjectPronouns[subject.pronoun.id]) then return false end
        local context = frame.coordinatedAfter
        if context and not (previous and previous.verb and context[previous.verb.lexeme.en]) then return false end
        if frame.requiresDestination then
            local destination = P.noun(document, after, limit, "accusative", true)
            if not destination or not destination.term or destination.term.category ~= "places" then return false end
        end
        if english and frame.motionPreposition and not frame.motionPreposition[P.key(document, after, limit)] then return false end
        local typedObject = (frame.objectClasses or frame.objectPronouns or frame.animateObject or frame.requiresSpatialContainer)
            and (english or frame.reverseObjectClasses)
        if typedObject or not english and frame.reverseAdjunct then
            local objectAt = after
            if frame.recipientCase then
                local recipient, following = objectRecipientAt(document, objectAt, limit, frame, frame.objectCase)
                if not english and not recipient then return false end
                if recipient and (not english or recipient.pronoun or P.relativeAnimate(recipient)) then
                    objectAt = following
                end
            end
            local marker = english and frame.enObjectPreposition or not english and frame.objectPreposition
            local case = english and "accusative" or frame.objectCase or "accusative"
            if marker then
                local governedCase
                objectAt, governedCase = verbObjectMarker(document, objectAt, limit, frame)
                if not objectAt then return false end
                case = governedCase or case
            end
            local object, objectEnd = separatedObject, after
            if not object then
                object, objectEnd = P.noun(document, objectAt, limit, case, frame.requiresSpatialContainer,
                    nil, true, frame.objectSense, frame.requiresSpatialContainer and P.spatialContainer)
            end
            local class = P.semanticClass(object)
            if not class and object and object.raw and ns.Engine.Markup.isLink(object.raw, "item") then class = "equipment" end
            local pronoun = object and object.pronoun
            if typedObject and not (frame.objectClasses and frame.objectClasses[class]
                or frame.objectPronouns and pronoun and frame.objectPronouns[pronoun.id]
                or frame.animateObject and personNoun(object)
                or frame.requiresSpatialContainer and P.spatialContainer(object)) then return false end
            if not english and frame.reverseAdjunct then
                local adjunct = object and P.preposition(document, objectEnd, limit, false, false, frame.prepositionContext)
                if not adjunct or adjunct.rule.id ~= frame.reverseAdjunct then return false end
            end
            if frame.measurePreposition and not measureAt(document, objectEnd, limit, frame) then return false end
        end
        if frame.propertyCase then
            if frame.subjectAnimacy and subject then
                local pronoun = subject.pronoun
                local animacy = subject.animacy
                if pronoun then animacy = (pronoun.inanimate or pronoun.id == "it") and "inanimate" or "animate" end
                if animacy and animacy ~= frame.subjectAnimacy then return false end
            end
            if not propertyAt(document, after, limit, frame.propertyCase, subject) then return false end
        end
        if english and frame.gerundComplement then
            local infinitive = frame.alternateInfinitive and P.key(document, after, limit) == "to"
            local start = after + (infinitive and 1 or 0)
            local form = infinitive and {mood="base"} or {verbalForm="participle", tense="present"}
            if not hasVerbForm(document, start, limit, form) then return false end
        end
        if frame.requiredControl and (english or frame.controlVerbs) then
            local actor, at = controlledStart(document, after, limit, frame)
            if not actor then return false end
            local form = {mood=english and "base" or "infinitive"}
            if frame.controlVerbs then
                if not L.choose(document, at, "verb", form, nil, function(entry)
                    return frame.controlVerbs[entry.lexeme.en]
                end) then return false end
            elseif not hasVerbForm(document, at, limit, form) then return false end
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
        if imperative then
            return f.mood == "imperative"
                and (not subject or f.person == subject.person and f.number == subject.number)
        end
        if f.mood == "infinitive" or f.mood == "imperative" then return false end
        return f.tense ~= nil and (not subject
            or (not f.person or f.person == subject.person)
                and (not f.number or f.number == subject.number or not previous and agreeingSubjectReading(document, subject, f))
                and (not f.gender or not subject.gender or f.gender == subject.gender))
    end
    if english and not headword then
        local phrase, finish = L.phraseAt(document, index, limit, "verb")
        if phrase then
            after = finish
            local preposition = L.functional(document, "prepositions", index + 1, finish - 1)
            local selected = L.choose(document, phrase, "verb", nil, sense, function(candidate)
                local verbFrame = lexemeFrame(candidate)
                if not verbFrame.lexicalPhrase or not compatible(candidate) then return false end
                if preposition and verbFrame.particle then
                    local object = P.noun(document, after, limit, "accusative")
                    local frame = object and object.entry and lexemeFrame(object.entry)
                    if P.spatialContainer(object) or frame and frame.spatialPart then return false end
                end
                return true
            end)
            if selected then return selected, after end
            after = index + 1
        end
        local particles = ns.Linguistics and ns.Linguistics.verbParticles
        local head = P.key(document, index, limit)
        local options = particles and particles[head]
        if options then
            for position = index + 2, math.min(limit, index + 9) do
                local particle = P.key(document, position, limit)
                if options[particle] then
                    local object, ending = P.coordinated(document, index + 1, position - 1, "accusative")
                    if object and ending == position then
                        after = position + 1
                        local selected = L.choose(document, head .. " " .. particle, "verb", nil, sense, function(candidate)
                            return lexemeFrame(candidate).particle == particle and compatible(candidate, object)
                        end)
                        if selected then
                            -- Keep the object on this occurrence, outside the shared lexeme cache.
                            return {lexeme=selected.lexeme, head=selected.head, form=selected.form, id=selected.id,
                                separatedObject=object}, after
                        end
                    end
                end
            end
            after = index + 1
        end
    end
    if not english and not headword and P.key(document, index + 1, limit) == "/" then
        after = index + 3
        local paired = L.genderPair(document, index, limit, "verb", {tense="past", number="singular"}, sense, compatible)
        if paired then return paired, after end
        after = index + 1
    end
    if not english and not headword then
        for _, candidate in ipairs(L.at(document, index)) do
            local frame = lexemeFrame(candidate)
            if requiredUkComplement(frame) or frame.objectDomainByAdjunctClass then
                local scoped = L.choose(document, index, "verb", nil, sense, function(reading)
                    local scope = lexemeFrame(reading)
                    return compatible(reading)
                        and (requiredUkComplement(scope) or objectDomain(document, after, limit, scope))
                end)
                if scoped then return scoped, after end
                break
            end
        end
    end
    local selected = L.choose(document, headword or index, "verb", nil, sense, compatible)
    if selected then return selected, after end
end

adverbAt = function(document, first, limit, context, eligible)
    local rows, last = L.functional(document, "adverbs", first, limit)
    if not rows or last > limit then return nil end
    local fallback
    for _, row in ipairs(rows) do
        local adverb = ns.Linguistics.grammar.adverbs[row]
        if not eligible or eligible(adverb) then
            if adverb.context and adverb.context == context then return adverb, last + 1 end
            if not adverb.context and not fallback then fallback = adverb end
        end
    end
    if fallback then return fallback, last + 1 end
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
    ["how'd"]={kind="manner", role="manner", auxiliary="did"},
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

local function questionDeterminer(english, word)
    if english then return word == "what" or word == "which" end
    return word and word:sub(1, #"як") == "як" and P.relativeMarkers["uk-en"][word]
end

local needInfinitiveMarkers = {["потрібно"]="need", ["треба"]="need", ["необхідно"]="need", ["слід"]="should"}
local obligationTime = {["було"]="past", ["буде"]="future"}
local function obligationHead(document, first, limit)
    for marker = first + 1, math.min(first + 6, limit - 1) do
        local kind = needInfinitiveMarkers[P.key(document, marker, limit)]
        if kind then
            local last = marker - 1
            local negative = P.key(document, last, limit) == "не"
            if negative then last = last - 1 end
            local before = obligationTime[P.key(document, last, limit)]
            if before then last = last - 1 end
            if not negative and P.key(document, last, limit) == "не" then negative, last = true, last - 1 end
            local subject, finish = recipientAt(document, first, last, "dative", true)
            if not subject or finish ~= last + 1 then return nil end
            local after = obligationTime[P.key(document, marker + 1, limit)]
            if before and after then return nil end
            if kind == "should" and (before or after) then return nil end
            return subject, marker, marker + (after and 2 or 1), before or after or "present", negative, kind
        end
    end
end

local determinantCases = {"accusative", "genitive", "dative", "instrumental"}
local englishDeterminerCases = {"accusative"}
local function interrogativeObject(document, first, limit, english, indirect)
    local marker = P.key(document, first, limit)
    if not questionDeterminer(english, marker) then return nil end
    for _, case in ipairs(english and englishDeterminerCases or determinantCases) do
        local noun, after = P.noun(document, first + 1, limit, case, false, false, true)
        if noun and not (noun.pronoun or noun.raw or noun.article or noun.possessor or noun.demonstrative)
            and (english or P.relativePronoun(noun, case) == marker) then
            if not english and obligationHead(document, after, limit) then
                return {kind="thing", role="object", noun=noun, case=case, determiner="which"}, after
            end
            local head = P.key(document, after, limit)
            local helper = english and not indirect and auxiliary[head]
            local finiteCopula = english and not indirect and (copula[head] or negativeCopula[head])
            if not english or indirect or helper or finiteCopula then
                local subject, at = P.coordinated(document, after + ((helper or finiteCopula) and 1 or 0), limit, "nominative")
                if subject then
                    local negative = P.key(document, at, limit)
                    if negative == "not" or negative == "не" then at = at + 1 end
                    local _, afterAdverb = adverbAt(document, at, limit)
                    at = afterAdverb or at
                    local abilityAt
                    if english and (finiteCopula or helper and (helper.ability or helper.tense == "future")) then
                        abilityAt = abilityComplementStart(document, at, limit, finiteCopula)
                    elseif not english then
                        local _, start = inflectedAbility(document, at, limit)
                        abilityAt = start
                    end
                    local predicate = verb(document, abilityAt or at, limit, subject, helper or abilityAt ~= nil)
                    local frame = predicate and lexemeFrame(predicate)
                    if frame and frame.objectCase and not frame.motion and not frame.intransitive and not frame.objectPreposition
                        and (english or frame.objectCase == case) then
                        return {kind="thing", role="object", noun=noun, case=not english and case or nil,
                            determiner=english and marker or "which"}, after
                    end
                end
            end
        end
    end
end

local function interrogativeAt(document, first, limit, indirect)
    local english = document.direction == "en-uk"
    local firstWord, secondWord = P.key(document, first, limit), P.key(document, first + 1, limit)
    if english and firstWord == "what" and secondWord == "time" then
        return {kind="clock", role="manner"}, first + 2
    end
    if not english and (firstWord == "о" or firstWord == "об") and secondWord == "котрій" then
        local hour = P.key(document, first + 2, limit) == "годині"
        return {kind="clock", role="manner"}, first + (hour and 3 or 2)
    end
    local object, after = interrogativeObject(document, first, limit, english, indirect)
    if object then return object, after end
    local questions = english and englishQuestions or ukrainianQuestions
    local spec = questions[firstWord]
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
    if not role and not english and obligationHead(document, index, limit) then role = "object" end
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
                    or not english and (auxiliary[P.key(document, atVerb, limit)] or inflectedAbility(document, atVerb, limit)) then
                    role = "object"
                elseif copular and spec.kind == "thing" and after > limit then
                    role = "predicate"
                end
            end
        end
    end
    return {kind=kind, noun=quantified, role=role or "subject", case=spec.case, another=another, copula=spec.copula,
        auxiliary=spec.auxiliary,
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

local function alreadyCompleted(parent, child)
    if not child.verb or parent.tense ~= "past" or child.tense ~= "past" then return false end
    if child.since then return true end
    if child.leadingAdverb and child.leadingAdverb.en[1] == "already" then return true end
    for _, adverb in ipairs(child.adverbs or {}) do
        if adverb.en[1] == "already" then return true end
    end
    return false
end

local function hasFutureSchedule(tree)
    if tree.leadingAdverb and tree.leadingAdverb.futureSchedule then return true end
    for _, adverb in ipairs(tree.adverbs or {}) do
        if adverb.futureSchedule then return true end
    end
    return false
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
local function coordinatedObject(document, first, limit, case, locationOnly, enumeration, sense, headFilter)
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
    return P.coordinated(document, first, limit, case, startsPredicate, locationOnly, enumeration, sense, headFilter)
end

local complements
local controlledTemporal = {
    before={en={"before"}, uk={"перш ніж"}, temporal=true},
    after={en={"after"}, uk={"після того як"}, temporal=true},
}

local function controlledTimeClause(document, first, limit, main, depth)
    if main.aspect == "passive" then return nil end
    local subject = main.subject or main.imperative and personalSubject("you")
    if not subject then return nil end
    local action, after = verb(document, first, limit, subject, false, false, nil, "present")
    if not action then return nil end
    local dependent = {kind="clause", subject=subject, inherited=true, tense=main.tense == "past" and "past" or "present",
        temporalDependent=true, verb=action}
    local finish = complements(document, dependent, after, limit, depth + 1)
    if finish then return dependent, finish end
end
local function nominalInfinitive(document, noun, first, limit, depth)
    local head = noun.members and noun.members[#noun.members] or noun
    local frame = head.entry and head.entry.lexeme.frame
    local english = document.direction == "en-uk"
    if depth >= 3 or not frame or not frame.nominalInfinitive
        or english and P.key(document, first, limit) ~= "to" then return nil end
    local start = first + (english and 1 or 0)
    if not english and frame.nominalPurpose then
        if P.key(document, start, limit) == "," then start = start + 1 end
        if P.key(document, start, limit) ~= "щоб" then return nil end
        start = start + 1
    end
    local entry, after = verb(document, start, limit, nil, true)
    if not entry then return nil end
    local action = {verb=entry, tense="infinitive", purposeClause=true, nominalPurpose=frame.nominalPurpose}
    local finish = complements(document, action, after, limit, depth + 1)
    if finish then return action, finish end
end

local function attachNominalAction(document, noun, first, limit, depth)
    local action, finish = nominalInfinitive(document, noun, first, limit, depth)
    if action then noun.nominalAction = action; return finish end
    return first
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

local function perceptionSeries(document, event, index, limit, depth)
    local english = document.direction == "en-uk"
    for _ = 1, 3 do
        local comma = P.key(document, index, limit) == ","
        local join, marker = clauseConnector(document, index + (comma and 1 or 0), limit)
        if not join or (join.id ~= "and" and join.id ~= "or") then break end
        local start, continuation, finish = marker + 1
        if english then
            local negative = P.key(document, start, limit) == "not"
            if negative then start = start + 1 end
            local progressive = event.perceptionProgressive
            local entry, after = verb(document, start, limit, event.subject, not progressive, false, nil,
                progressive and "present" or nil)
            if not entry then break end
            refineSubject(document, event.subject, lexemeFrame(entry))
            continuation = {kind="clause", subject=event.subject, verb=entry, inherited=true,
                tense=event.tense, negative=negative, perceptionProgressive=progressive}
            finish = complements(document, continuation, after, limit, depth)
            if not finish or not boundary(document, finish, limit) then return nil end
        else
            continuation, finish = simple(document, start, limit, event, depth)
            if not continuation or not continuation.inherited or not continuation.verb or continuation.question then break end
        end
        event.perceptionSeries = event.perceptionSeries or {}
        event.perceptionSeries[#event.perceptionSeries + 1] = {event=continuation, join=join}
        index = finish
    end
    return index
end

local function complementaryInfinitive(document, index, limit, frame, depth, gap)
    if depth >= 3 or not frame.infinitive then return nil, index end
    local english = document.direction == "en-uk"
    local marker = P.key(document, index, limit)
    if english and marker ~= "to" and not (frame.bareInfinitive or frame.gerundComplement) then return nil, index end
    local at = english and marker == "to" and index + 1 or index
    local gerund = english and frame.gerundComplement and not (marker == "to" and frame.alternateInfinitive)
    local verbEntry, after = verb(document, at, limit, nil, not gerund, false, nil, gerund and "present")
    if verbEntry then
        local action = {verb=verbEntry, verbIndex=at, tense="infinitive", gerund=frame.gerundComplement, objectGap=gap}
        local finish = complements(document, action, after, limit, depth + 1)
        return finish and action, finish
    end
    if english and frame.omittedInfinitive and marker == "to" and index == limit then return nil, index + 1 end
    if not frame.gerundComplement then return nil, index end
end

local function bindQuestionObject(wh, expected)
    local observed = wh.case
    local animateGenitive = wh.kind == "person" and observed == "accusative" and expected == "genitive"
    if not expected or (observed and observed ~= expected and not animateGenitive)
        or (expected == "dative" and wh.kind == "thing" and not wh.noun)
        or (wh.kind == "quantity" and expected ~= "accusative" and expected ~= "genitive") then return false end
    wh.case, wh.role = expected, "object"
    return true
end

local function priceComplement(document, index, limit)
    local english = document.direction == "en-uk"
    local before = index
    local comma = P.key(document, index, limit) == ","
    if comma then index = index + 1 end
    local manner, after = adverbAt(document, index, limit, "valuation")
    if manner and manner.context == "valuation" then
        index = after
        if P.key(document, index, limit) == "—" then index = index + 1 end
    else manner = nil end
    local only = not english and P.key(document, index, limit) == "лише"
    if only then index = index + 1 end
    if not manner and comma or P.key(document, index, limit) ~= (english and "for" or "за") then
        return nil, before
    end
    index = index + 1
    if P.key(document, index, limit) == (english and "only" or "лише") then
        only, index = true, index + 1
    end
    local price, finish = ns.Engine.Grammar.moneyAt(document, index, limit)
    if not price then return nil, before end
    return {amount=price, manner=manner, only=only}, finish
end

complements = function(document, tree, index, limit, depth)
    depth = depth or 0
    local frame = lexemeFrame(tree.verb)
    local english = document.direction == "en-uk"
    if frame.boundAdverb then
        local adverb, after = gradedAdverbAt(document, index, limit, frame.boundAdverb)
        if not adverb then return nil end
        tree.adverbComplement, index = adverb, after
    end
    if not english and tree.leadingAdverb and (tree.leadingAdverb.preNegative
        or frame.ukPreverbalAdverbs and frame.ukPreverbalAdverbs[tree.leadingAdverb.en[1]]) then
        tree.adverbs = tree.adverbs or {}
        table.insert(tree.adverbs, 1, tree.leadingAdverb)
        tree.leadingAdverb = nil
    end
    local required = not english and requiredUkComplement(frame)
    if required then
        index = afterObjectMarker(document, index, limit, required)
        if not index then return nil end
    end
    if english and tree.wh and tree.wh.kind == "duration" and tree.verb.lexeme.en == "take" then return nil end
    local objectPreposition = english and frame.enObjectPreposition or not english and frame.objectPreposition
    local questionObject = tree.wh and tree.wh.role == "object"
    local gap = tree.objectGap
    if gap then
        local governed = type(gap) == "table" and frame.relativeMarkerUk and frame.relativeImplicitUk
        if not frame.objectCase or objectPreposition and not governed or frame.intransitive or frame.motion or frame.separation then return nil end
        if governed then
            if english and (gap.marker or frame.enObjectPreposition) then return nil end
            if not english then
                if gap.marker ~= frame.relativeMarkerUk then return nil end
                index = afterObjectMarker(document, index, limit, frame.relativeImplicitUk)
                if not index then return nil end
            end
            tree.relativeMarkerUk, tree.relativeImplicitUk = frame.relativeMarkerUk, frame.relativeImplicitUk
        elseif type(gap) == "table" and gap.marker then return nil end
        tree.relativeCase = tree.negative and frame.negativeObjectCase or frame.objectCase
    end
    local occupiedObject = questionObject or gap
    if tree.verb.separatedObject then
        if occupiedObject then return nil end
        tree.object = tree.verb.separatedObject
    end
    if questionObject then
        local action, finish = complementaryInfinitive(document, index, limit, frame, depth, true)
        if action then
            if not bindQuestionObject(tree.wh, action.relativeCase) then return nil end
            tree.infinitive, index = action, finish
        elseif objectPreposition or frame.motion or frame.intransitive or not bindQuestionObject(tree.wh, frame.objectCase) then
            return nil
        end
    end
    local preposition, governedCase = verbObjectMarker(document, index, limit, frame)
    if preposition then index = preposition end
    if frame.propertyCase then
        local property, finish = propertyAt(document, index, limit, frame.propertyCase, tree.subject)
        if not property then return nil end
        tree.property, index = property, finish
    end
    local objectCase = governedCase or (english and "accusative" or frame.objectCase or "accusative")
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
                if frame.controlVerbs and not frame.controlVerbs[entry.lexeme.en] then return nil end
                local action = {verb=entry, tense="infinitive", negative=negative, purposeClause=not negative}
                local finish = complements(document, action, after, limit, depth + 1)
                if finish then tree.controlled, index = {actor=actor, action=action}, finish end
            end
        end
    end
    if frame.requiredControl and not tree.controlled then return nil end
    if not occupiedObject and frame.perception and depth < 3 then
        local event, finish
        if english then
            local actor, start = P.noun(document, index, limit, "accusative", false, false, true)
            if actor then
                local observed, after = verb(document, start, limit, actor, true)
                local ongoing
                if not observed then
                    observed, after = verb(document, start, limit, actor, false, false, nil, "present")
                    ongoing = observed ~= nil
                end
                if observed then
                    refineSubject(document, actor, lexemeFrame(observed))
                    event = {kind="clause", subject=actor, verb=observed, perceptionProgressive=ongoing,
                        tense=tree.tense == "past" and "past" or "present"}
                    finish = complements(document, event, after, limit, depth + 1)
                end
            end
        else
            local start = index + (P.key(document, index, limit) == "," and 1 or 0)
            if P.key(document, start, limit) == "як" then
                event, finish = simple(document, start + 1, limit, nil, depth + 1)
                if event and (not event.subject or not event.verb or event.question or event.imperative) then event = nil end
            end
        end
        if event and finish and boundary(document, finish, limit) then
            finish = perceptionSeries(document, event, finish, limit, depth + 1)
            if not finish then return nil end
            tree.perception = event
            return finish
        end
    end
    if frame.content and not occupiedObject and depth < 3 then
        local marker = english and "that" or "що"
        local recipient, start
        if frame.contentRecipientCase then recipient, start = contentRecipientAt(document, index, limit, frame) end
        start = start or index
        if recipient and start > limit then
            tree.recipient = recipient
            return start
        end
        if not english and P.key(document, start, limit) == "," then start = start + 1 end
        local linker = P.key(document, start, limit)
        local following = P.key(document, start + 1, limit)
        local polar = english and (linker == "whether" or linker == "if") or not english and linker == "чи"
        local indirect = linker == "where" or linker == "де" or linker == "why" or linker == "чому"
            or linker == "when" or linker == "коли"
            or questionDeterminer(english, linker)
            or (english and englishQuestions[linker])
            or (not english and ukrainianQuestions[linker]
                and (linker ~= "що" or following == "саме" or following == "ще" or following == "таке"))
        local bare = english and frame.bareContent and following ~= nil and linker ~= marker and not indirect and not polar
        if linker == marker or indirect or polar or bare then
            local clauseStart = (indirect or bare) and start or start + 1
            local embedded, finish = simple(document, clauseStart, limit, nil, depth + 1, indirect or polar)
            if embedded and embedded.subject and not embedded.imperative and not embedded.question then
                embedded.polar, embedded.contentClause = polar, true
                if recipient then tree.recipient = recipient end
                if english and recipient and recipient.person == 3 and recipient.number == "singular"
                    and embedded.possessiveRecipient == "they" then
                    local pronoun = recipient.gender == "feminine" and "she" or "he"
                    embedded.recipient = personalSubject(pronoun)
                end
                if not english then
                    embedded.reportedAnterior = alreadyCompleted(tree, embedded)
                    embedded.reportedFuture = tree.tense == "past" and embedded.tense == "future"
                end
                if english and frame.reportedPresent and tree.tense == "past" and embedded.tense == "past"
                    and embedded.aspect == "continuous" and explicitTime(embedded) ~= "past" then
                    local scheduled = hasFutureSchedule(embedded)
                    embedded.tense = scheduled and "future" or "present"
                    if scheduled then embedded.sequencedEvent = true end
                end
                tree.content = {embedded}
                index = finish
                if indirect or polar then return index end
                for _ = 1, 2 do
                    local nextMarker = index
                    if P.key(document, nextMarker, limit) == "," then nextMarker = nextMarker + 1 end
                    local join = P.key(document, nextMarker, limit)
                    local andJoin = join == "and" or join == "і" or join == "й" or join == "та"
                    if not andJoin or P.key(document, nextMarker + 1, limit) ~= marker then break end
                    embedded, finish = simple(document, nextMarker + 2, limit, nil, depth + 1)
                    if not embedded or not embedded.subject or embedded.imperative or embedded.question then break end
                    embedded.contentClause = true
                    if not english then
                        embedded.reportedAnterior = alreadyCompleted(tree, embedded)
                        embedded.reportedFuture = tree.tense == "past" and embedded.tense == "future"
                    end
                    tree.content[#tree.content + 1] = embedded
                    index = finish
                end
                return index
            end
        end
    end
    if frame.requiresContent and not tree.controlled then return nil end
    local recipient, after
    if frame.recipientCase and not occupiedObject and not tree.controlled then
        recipient, after = objectRecipientAt(document, index, limit, frame, objectCase)
        if recipient then
            local object, last = coordinatedObject(document, after, limit, objectCase, frame.destinationObject,
                frame.enumeratesObject, frame.objectSense)
            if object then
                tree.recipient, tree.object, index = recipient, object, last
                local sense = english and frame.recipientObjectSenses and frame.recipientObjectSenses[P.semanticClass(object)]
                local reading = sense and L.choose(document, tree.verb.lexeme.en, "verb", nil, sense)
                if reading then tree.verb = reading end
            end
        end
    end
    if english and not occupiedObject and frame.benefitClasses and tree.modal == "could"
        and tree.subject and not tree.question and not tree.negative then
        local opening = P.key(document, index, limit)
        local start = index + (opening == "some" and 1 or 0)
        local resource, finish = P.noun(document, start, limit, "accusative", false, nil, false, "supportResource")
        local resourceFrame = resource and resource.entry and lexemeFrame(resource.entry)
        if resource and frame.benefitClasses[P.semanticClass(resource)]
            and (not resourceFrame or not resourceFrame.benefitIndefinite or resource.article == "indefinite") then
            tree.kind, tree.object, index = "benefit", resource, finish
        end
    end
    if english and frame.requiredInfinitive and not occupiedObject and not tree.controlled then
        local action, finish = complementaryInfinitive(document, index, limit, frame, depth)
        if not action then return nil end
        tree.infinitive, index = action, finish
    end
    if not occupiedObject and not tree.controlled and not tree.object and not tree.infinitive and not frame.motion and not frame.intransitive
        and not frame.gerundComplement
        and (not objectPreposition or preposition) then
        local object, nextIndex
        if frame.separation then object, nextIndex = P.noun(document, index, limit, objectCase, false, nil, true)
        else
            local previousDomain = document.transferDomain
            document.transferDomain = objectDomain(document, index, limit, frame) or previousDomain
            local negativeCase = not english and tree.negative and frame.negativeObjectCase
            local headFilter = frame.requiresSpatialContainer and P.spatialContainer
            object, nextIndex = coordinatedObject(document, index, limit, negativeCase or objectCase, frame.destinationObject,
                frame.enumeratesObject, frame.objectSense, headFilter)
            if not object and negativeCase then
                object, nextIndex = coordinatedObject(document, index, limit, objectCase, frame.destinationObject,
                    frame.enumeratesObject, frame.objectSense, headFilter)
            end
            document.transferDomain = previousDomain
        end
        if object then
            local objectFrame = object.entry and object.entry.lexeme.frame
            local quantity = tonumber(object.quantity)
            if english and tree.verb.lexeme.en == "open" and objectFrame and objectFrame.skillThreshold
                and object.number == "singular" and quantity and quantity >= 25 and quantity <= 999 then
                object.skillRequirement, object.quantity = object.quantity, nil
            end
            if english and not tree.recipient and frame.possessorRecipient and object.possessor then
                local owner = possessivePronouns[object.possessor.lexeme.en]
                if owner then
                    tree.recipient, tree.possessiveRecipient = personalSubject(owner), owner
                    object.possessor = nil
                end
            end
            tree.object, index = object, nextIndex
        elseif preposition then return nil end
    end
    if frame.separation and tree.object and P.key(document, index, limit) == (english and "of" or "від") then
        tree.separation, after = P.noun(document, index + 1, limit, "genitive")
        if not tree.separation then return nil end
        index = after
    end
    if tree.object then index = attachNominalAction(document, tree.object, index, limit, depth) end
    if english and frame.particle and not tree.object and not occupiedObject then return nil end
    if english and tree.object and frame.objectResults and index <= limit then
        local class = P.semanticClass(tree.object)
        for _, candidate in ipairs(L.at(document, index)) do
            local result = frame.objectResults[candidate.lexeme.en]
            if result and result.classes[class] and candidate.lexeme.pos == "verb"
                and candidate.form.verbalForm == "participle" and candidate.form.tense == "past" then
                local completed = L.choose(document, result.verb, "verb")
                if completed then tree.verb, index = completed, index + 1 end
                break
            end
        end
    end
    if english and frame.noObjectSense and not (tree.object or occupiedObject or tree.recipient or tree.controlled)
        and (not frame.noObjectPlural or tree.subject and tree.subject.number == "plural") then
        local intransitive = L.choose(document, tree.verb.lexeme.en, "verb", nil, frame.noObjectSense)
        if intransitive then
            tree.verb, frame = intransitive, lexemeFrame(intransitive)
        end
    end
    if priceAdverb then
        if not tree.object then return nil end
        tree.adverbs = {priceAdverb}
    end
    if not occupiedObject and not tree.controlled and not tree.object and not tree.infinitive and frame.infinitive then
        local action, finish = complementaryInfinitive(document, index, limit, frame, depth)
        if not finish then return nil end
        tree.infinitive, index = action, finish
    end
    if frame.requiredInfinitive and not tree.infinitive then return nil end
    if tree.object and (frame.priceAdverb or frame.cashComplement) then
        tree.priceComplement, index = priceComplement(document, index, limit)
    end
    local objectClass = P.semanticClass(tree.object)
    local prepositionContext = tree.kind == "benefit" and objectClass
        or tree.object and tree.object.sufficient and "supply"
        or frame.objectPrepositionContexts and frame.objectPrepositionContexts[objectClass]
        or frame.prepositionContext
    for _ = 1, 3 do
        local delay, delayed = P.delay(document, index, limit)
        if delay and not tree.delay then
            tree.delay, index = delay, delayed
        end
        if not tree.measure and (frame.measurePreposition or not english and frame.measuredPredicate) then
            local measure, after = measureAt(document, index, limit, frame)
            if measure then tree.measure, index = measure, after end
        end
        local rule = english and depth < 3 and controlledTemporal[P.key(document, index, limit)]
        if rule and not tree.temporalAction then
            local dependent, finish = controlledTimeClause(document, index + 1, limit, tree, depth)
            if dependent then
                tree.temporalAction = {rule=rule, clause=dependent}
                return finish
            end
        end
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
        local context = frame.priceAdverb and "price" or frame.adverbContext
        local adverb, endAt = gradedAdverbAt(document, index, limit)
        if not adverb then
            adverb, endAt = adverbAt(document, index, limit, context, function(candidate)
                return not candidate.preNegative or tree.negative
            end)
        end
        local pp, last
        if not adverb or not adverb.temporalAdjunct then
            pp, last = P.preposition(document, index, limit, frame.motion, frame.displacesObject and tree.object ~= nil,
                prepositionContext)
        end
        if pp then
            local entry = pp.object.entry
            if pp.rule.id == "since" then tree.since = true end
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
            if not adverb then break end
            if english and not tree.leadingAdverb and (adverb.preNegative
                or frame.ukPreverbalAdverbs and frame.ukPreverbalAdverbs[adverb.en[1]]) then
                tree.leadingAdverb = adverb
            else
                tree.adverbs = tree.adverbs or {}
                tree.adverbs[#tree.adverbs + 1] = adverb
            end
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

local function relativeDuration(document, first, limit, english)
    local marker = P.key(document, first, limit)
    local question = marker == (english and "why" or "чому")
    local cursor = first + (question and 1 or 0)
    local tense, recipient, factor, less
    if english then
        if question then
            local aux = P.key(document, cursor, limit)
            tense = aux ~= "do" and durationAuxiliaries[aux]
            if P.key(document, cursor + 1, limit) ~= "it" or P.key(document, cursor + 2, limit) ~= "take" then return end
            cursor = cursor + 3
        elseif P.key(document, cursor, limit) == "it" then
            local form = P.key(document, cursor + 1, limit)
            if form == "will" and P.key(document, cursor + 2, limit) == "take" then
                tense, cursor = "future", cursor + 3
            else
                tense, cursor = ({takes="present", took="past"})[form], cursor + 2
            end
        elseif P.key(document, cursor, limit) == "it'll" and P.key(document, cursor + 1, limit) == "take" then
            tense, cursor = "future", cursor + 2
        end
        if not tense then return end
        local person, after = P.noun(document, cursor, limit, "accusative", false, false, true)
        if person and (person.pronoun or person.animacy == "animate") then recipient, cursor = person, after end
        factor, cursor, less = P.multiplier(document, cursor, limit)
        if not factor or P.key(document, cursor, limit) ~= "as"
            or P.key(document, cursor + 1, limit) ~= "long" or P.key(document, cursor + 2, limit) ~= "to" then return end
        cursor = cursor + 3
    else
        local recipientAt = cursor
        local requiredAt
        for index = cursor, limit - 4 do
            local marker = requiredTime[P.key(document, index, limit)]
            if marker then
                local multiple, following = P.multiplier(document, index + 1, limit)
                if multiple then
                    tense, factor, cursor, requiredAt = marker, multiple, following, index
                    break
                end
            end
        end
        if not tense then return end
        if requiredAt > recipientAt then
            local person, after = P.noun(document, recipientAt, requiredAt - 1, "dative", false, false, true)
            if not person or after ~= requiredAt or not (person.pronoun or person.animacy == "animate") then return end
            recipient = person
        end
        local comparison = P.key(document, cursor, limit)
        if comparison ~= "більше" and comparison ~= "менше" then return end
        less = comparison == "менше"
        if P.key(document, cursor + 1, limit) ~= "часу" then return end
        cursor = cursor + 2
        if P.key(document, cursor, limit) == "," then cursor = cursor + 1 end
        if P.key(document, cursor, limit) ~= "щоб" then return end
        cursor = cursor + 1
    end
    local action, finish = durationAction(document, cursor, limit)
    if action and boundary(document, finish, limit) then
        return {kind="duration", question=question, tense=tense, action=action, recipient=recipient,
            multiplier=factor, lessTime=less}, finish
    end
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
        action = {verb=embedded, tense="infinitive", purposeClause=true}
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

local function predicateTime(document, tree, index, limit, scheduled)
    local marker = document.direction == "en-uk" and "for" or "на"
    if scheduled and P.key(document, index, limit) == marker then
        local target, after = adverbAt(document, index + 1, limit)
        if target and target.time then
            tree.scheduleTime = target
            return after
        end
    end
    local delay, finish = P.delay(document, index, limit)
    if delay then
        tree.delay = delay
        return finish
    end
    local adverb, after = adverbAt(document, index, limit)
    if adverb and adverb.time then
        tree.adverbs = tree.adverbs or {}
        tree.adverbs[#tree.adverbs + 1] = adverb
        return after
    end
    return index
end

local function servicePredicate(document, tree, index, limit)
    if document.direction == "en-uk" then
        local reopened = P.key(document, index, limit) == "back"
        local start = index + (reopened and 1 or 0)
        if P.key(document, start, limit) == "open" and P.key(document, start + 1, limit) == "for"
            and P.key(document, start + 2, limit) == "business" then
            local again = P.key(document, start + 3, limit) == "again"
            tree.openForBusiness, tree.reopened = true, reopened or again
            return predicateTime(document, tree, start + (again and 4 or 3), limit)
        end
    end
    if not personNoun(tree.subject) then
        local price, finish = gradedAdverbAt(document, index, limit, "price")
        local pronoun = tree.subject and tree.subject.pronoun
        if price and (price.intensified or finish > index + 1 or pronoun or document.direction == "uk-en"
            or P.semanticClass(tree.subject) == "services") and boundary(document, finish, limit) then
            tree.price = price
            return finish
        end
    end
end

local function predicate(document, tree, index, limit, depth)
    local head = P.key(document, index, limit)
    if tree.subject and tree.subject.number == "plural" and index < limit
        and (document.direction == "en-uk" and head == "all"
            or document.direction == "uk-en" and (head == "усі" or head == "всі")) then
        tree.allSubject, tree.allUnderNegation, index = true, tree.negative, index + 1
        local following = P.key(document, index, limit)
        if following == (document.direction == "en-uk" and "not" or "не") then
            tree.negative, index = true, index + 1
        end
    end
    if tree.leadingAdverb and tree.leadingAdverb.predicateModifier then
        tree.predicateAdverb, tree.leadingAdverb = tree.leadingAdverb, nil
    end
    local predicateAdverb, afterAdverb = adverbAt(document, index, limit)
    if predicateAdverb and predicateAdverb.predicateModifier and afterAdverb <= limit then
        tree.predicateAdverb, index = predicateAdverb, afterAdverb
    end
    local serviceEnd = servicePredicate(document, tree, index, limit)
    if serviceEnd then return serviceEnd end
    local adverb, after = adverbAt(document, index, limit, "predicate", function(candidate)
        return (not candidate.subjectClasses or candidate.subjectClasses[P.semanticClass(tree.subject)])
            and (not candidate.requiresAnimate or personNoun(tree.subject))
    end)
    local pronoun = tree.subject and tree.subject.pronoun
    if adverb and adverb.deicticEvaluation and deicticSubject(tree.subject) then
        tree.predicateAdverb = adverb
        return predicateTime(document, tree, after, limit)
    end
    if adverb and adverb.evaluativePredicate and pronoun and pronoun.id == "it" and (depth or 0) < 3 then
        local english = document.direction == "en-uk"
        local entry, actionStart = verb(document, after, limit, nil, not english, false, nil, english and "present" or nil)
        if entry then
            local action = {kind="clause", verb=entry, tense="infinitive", gerund=true}
            local finish = complements(document, action, actionStart, limit, (depth or 0) + 1)
            if finish then
                tree.implicitSubject, tree.evaluation = true, {rule=adverb, action=action}
                return finish
            end
        end
    end
    if adverb and adverb.statePredicate then
        tree.predicateAdverb = adverb
        tree.negative = tree.negative or P.key(document, index, limit) == adverb.negativeUk
        return predicateTime(document, tree, after, limit)
    end
    local timeAfter = adverb and adverb.bareState and adverbAt(document, after, limit)
    if adverb and adverb.location and (adverb.subjectClasses
        or adverb.bareState and (after > limit or timeAfter and timeAfter.time)) then
        if tree.predicateAdverb then
            tree.adverbs = tree.adverbs or {}
            table.insert(tree.adverbs, 1, adverb)
        else tree.predicateAdverb = adverb end
        return predicateTime(document, tree, after, limit, adverb.scheduleStatus)
    end
    local pp, finish = P.preposition(document, index, limit, nil, nil, "predicate")
    if pp then
        if pp.rule.resourceDepletion then tree.exhausted = pp.object
        else
            tree.prepositions = {pp}
            if spatialAdjuncts[pp.rule.id] then
                local place, after = P.preposition(document, finish, limit)
                if place and spatialAdjuncts[place.rule.id] then
                    tree.prepositions[2], finish = place, after
                end
            end
        end
        return predicateTime(document, tree, finish, limit)
    end
    if index > limit then return (tree.where or tree.wh and tree.wh.kind == "manner") and index end
    if tree.where then return nil end
    if document.direction == "en-uk" then
        local measure, after = P.quantity(document, index, limit)
        local head = P.key(document, after or index, limit)
        local predicates = ns.Linguistics.grammar.measuredPredicates
        local phrase = predicates and predicates[head]
        local measured = phrase and L.choose(document, phrase, "verb", nil, nil, function(candidate)
            return lexemeFrame(candidate).measuredPredicate == head
        end)
        if measured then
            tree.copula, tree.verb, tree.measure = nil, measured, measure
            if tree.modal == "might" then tree.tense = "future" end
            return complements(document, tree, (after or index) + 1, limit, depth)
        end
    end
    local modifier = P.key(document, index, limit)
    local number = P.key(document, index + 1, limit)
    if document.direction == "en-uk" and modifier == "real" and tree.subject and tree.subject.term
        and tree.subject.term.category == "places" then
        tree.exists = true
        return index + 1
    end
    if adverb and adverb.location and not adverb.subjectClasses then
        if document.direction == "en-uk" and adverb.en[1] == "back" and tree.tense == "future" then
            local delay, finish = P.delay(document, after, limit)
            local returning = delay and L.choose(document, "come back", "verb")
            if returning then
                tree.copula, tree.verb, tree.delay = nil, returning, delay
                tree.leadingAdverb = tree.predicateAdverb
                return finish
            end
        end
        if adverb.followLocation then
            local place, placeEnd = P.preposition(document, after, limit)
            if place then
                tree.predicateAdverb, tree.prepositions = adverb, {place}
                return predicateTime(document, tree, placeEnd, limit)
            end
        end
        tree.adverbs = {adverb}
        return predicateTime(document, tree, after, limit)
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
    local function adjectiveAllowed(candidate)
        local frame = lexemeFrame(candidate)
        local pronoun = tree.subject and tree.subject.pronoun
        return not frame.profileOnly and not (pronoun and pronoun.id == "someone" and frame.sense == "price")
    end
    local stateSense = personNoun(tree.subject) and "personalState"
    local nominative = {case="nominative"}
    local adjective = stateSense and L.genderPair(document, index, limit, "adj", nominative, stateSense, adjectiveAllowed)
        or L.genderPair(document, index, limit, "adj", nominative, nil, adjectiveAllowed)
    local adjectiveEnd = index + (adjective and 3 or 1)
    local paired = adjective ~= nil
    if not paired and index <= limit then
        adjective = stateSense and L.choose(document, index, "adj", nil, stateSense, adjectiveAllowed)
            or L.choose(document, index, "adj", nil, nil, adjectiveAllowed)
    end
    local object, nextIndex
    if adjective and (paired or intensity or adjective.lexeme.frame and adjective.lexeme.frame.ukExperiencer) then
        object = nil
    else
        object, nextIndex = P.coordinated(document, index, limit, "nominative")
    end
    if adjective and object and object.entry and nextIndex == adjectiveEnd
        and not (object.article or object.possessor or object.adjectives or object.genitive or object.quantity)
        and adjective.lexeme.preference < object.entry.lexeme.preference then
        object = nil
    end
    if object and (not intensity or not adjective) then
        tree.predicate = object
        local frame = object.entry and object.entry.lexeme.frame
        if frame and frame.predicateAdjuncts then
            local adjunct, finish = P.preposition(document, nextIndex, limit)
            local transfer = adjunct and frame.predicateAdjuncts[adjunct.rule.id]
            if transfer then
                if type(transfer) == "table" and document.direction == "en-uk" then
                    local target = transfer[P.semanticClass(adjunct.object)]
                    if target then adjunct.case, adjunct.targetUk = target.case, target.uk end
                end
                tree.prepositions, nextIndex = {adjunct}, finish
            end
        end
        return predicateTime(document, tree, nextIndex, limit)
    end
    if adjective then
        tree.adjective = {entry=adjective, intensity=intensity}
        local frame = adjective.lexeme.frame
        if frame and frame.infinitiveComplement and depth and depth < 3 then
            local english = document.direction == "en-uk"
            if not english or P.key(document, adjectiveEnd, limit) == "to" then
                local entry, nextIndex = verb(document, adjectiveEnd + (english and 1 or 0), limit, nil, true)
                if entry then
                    local action = {kind="clause", verb=entry, tense="infinitive", purposeClause=true}
                    local finish = complements(document, action, nextIndex, limit, depth + 1)
                    if finish then tree.infinitive = action; return finish end
                end
            end
        end
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
        local following, afterAdjective = P.preposition(document, adjectiveEnd, limit, nil, nil,
            frame and frame.prepositionContext)
        if following then
            tree.prepositions = {following}
            return predicateTime(document, tree, afterAdjective, limit)
        end
        return predicateTime(document, tree, adjectiveEnd, limit)
    end
end

local function everyoneAt(key, english)
    return english and (key == "all" or key == "everyone" or key == "everybody")
        or not english and (key == "усім" or key == "всім")
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
        if everyoneAt(P.key(document, nextIndex, limit), english) then
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

local function socialComplement(document, first, limit, depth)
    if not ns.Linguistics.grammar.socialActs then return nil end
    local choices, last = L.functional(document, "socialActs", first, limit)
    if not choices then return nil end
    local rule = ns.Linguistics.grammar.socialActs[choices[1]]
    local english = document.direction == "en-uk"
    local index = last + 1
    local mark = P.key(document, index, limit)
    local tree = {kind="social", social=rule}
    if rule.standaloneEn then
        local start = index + (mark == "," and 1 or 0)
        if everyoneAt(P.key(document, start, limit), english) then
            tree.everyone, index = true, start + 1
        elseif not english then
            local person, after = P.pronoun(document, index, limit, "dative")
            if person and person.pronoun.person == 2 then index = after end
        end
        mark = P.key(document, index, limit)
    end
    if rule.allowAddressee and not tree.everyone and mark and mark ~= rule.enMarker and not rule.ukMarkers[mark] then
        local afterComma = index + (mark == "," and 1 or 0)
        local address, after = P.noun(document, afterComma, limit, "vocative")
        if address and P.relativeAnimate(address) then
            local closing = P.key(document, after, limit) == ","
            local following = after + (closing and 1 or 0)
            local marker = P.key(document, following, limit)
            if english and marker == rule.enMarker or not english and rule.ukMarkers[marker]
                or rule.standaloneEn and mark == "," and after > limit then
                tree.recipient, index, mark = address, following, marker
            elseif not english and rule.action and closing and marker == "що" then
                tree.recipient, index, mark = address, after, ","
            end
        end
    end
    if index > limit then
        if rule.standaloneEn then return tree, index end
        return nil
    end
    if rule.action and not english and mark == "," and P.key(document, index + 1, limit) == "що" then
        local action, finish = simple(document, index + 2, limit, nil, depth + 1)
        local actor = action and action.subject and action.subject.pronoun
        if actor and actor.person == 2 and action.verb and action.tense ~= "future"
            and not action.modal and not action.question then
            action.subject, action.tense, action.gerund = nil, "infinitive", true
            tree.action = action
            return tree, finish
        end
    end
    local explicitMarker = english and mark == rule.enMarker or not english and rule.ukMarkers[mark]
    if not explicitMarker and not (english and rule.allowBareAction) then return nil end
    if explicitMarker then index = index + 1 end
    if english and rule.action then
        local negative = P.key(document, index, limit) == "not"
        local start = index + (negative and 1 or 0)
        local entry, after = verb(document, start, limit, nil, false, false, nil, "present")
        if entry then
            local action = {verb=entry, subject=personalSubject(tree.everyone and "you_plural" or "you"),
                tense="past", negative=negative}
            local finish = complements(document, action, after, limit, depth + 1)
            if finish and boundary(document, finish, limit) then
                tree.action = action
                return tree, finish
            end
        end
    end

    if not explicitMarker then return nil end
    local before = document.transferDomain
    document.transferDomain = rule.contextDomain or before
    local noun, finish = P.coordinated(document, index, limit, english and "accusative" or rule.ukCase,
        nil, nil, true, rule.objectSense)
    document.transferDomain = before
    if noun then
        tree.object = noun
        return tree, finish
    end
end

local function indefinitePerson(document, index, limit)
    local noun = P.pronoun(document, index, limit, "nominative")
    return noun and noun.pronoun.id == "someone"
end

local function persistenceAt(document, index, limit)
    local modifier, following = adverbAt(document, index, limit, "existence")
    if modifier and modifier.context == "existence" then return modifier, following end
end

local function existential(document, first, limit, depth)
    if depth >= 3 then return end
    local english = document.direction == "en-uk"
    local reason = P.key(document, first, limit) == (english and "why" or "чому")
    if reason then
        if english and P.key(document, first + 2, limit) ~= "there" then return nil end
        first = first + 1
    end
    local key, index, copulaNumber = P.key(document, first, limit), first
    local nextKey = P.key(document, first + 1, limit)
    local interrogative = document.tokens[limit + 1] and document.tokens[limit + 1].key == "?"
    local nearby, possessor, bareIndefinite, location, persistence
    local question = true
    if english then
        if key == "there's" or key == "there" and (nextKey == "is" or nextKey == "are") then
            copulaNumber, index = nextKey == "are" and "plural" or "singular", first + (key == "there's" and 1 or 2)
            question = interrogative or false
        elseif key == "any" and interrogative then
            index = index + 1
        elseif (interrogative or nextKey == "who") and indefinitePerson(document, first, limit) then
            bareIndefinite = true
            if nextKey == "who" then nearby = true end
        elseif (key == "is" or key == "are") and nextKey == "there" then
            copulaNumber, index = key == "is" and "singular" or "plural", index + 2
            if P.key(document, index, limit) == "any" then index = index + 1 end
        elseif key == "is" and indefinitePerson(document, first + 1, limit) then
            index = first + 1
        elseif key == "do" and nextKey == "we" and P.key(document, first + 2, limit) == "have"
            and indefinitePerson(document, first + 3, limit) then
            possessor, index = true, first + 3
        else return end
    else
        local marker = (key == "чи") and first + 1 or first
        local modifier, following = persistenceAt(document, marker, limit)
        if modifier then persistence, marker = modifier, following end
        local at, following = adverbAt(document, marker, limit)
        if at and at.location then
            local modifier, after = persistenceAt(document, following, limit)
            if P.key(document, after or following, limit) == "є" then
                location, persistence, marker = at, persistence or modifier, after or following
            end
        end
        if P.key(document, marker, limit) ~= "є" then return end
        index, question = marker + 1, key == "чи" or interrogative or false
        if key == "чи" then
            if P.key(document, index, limit) == "тут" then nearby, index = true, index + 1 end
            local preposition = P.key(document, index, limit)
            if (preposition == "в" or preposition == "у") and P.key(document, index + 1, limit) == "нас" then
                possessor, index = true, index + 2
            end
        end
    end
    if not persistence and (copulaNumber or not english) then
        local modifier, after = persistenceAt(document, index, limit)
        if modifier then persistence, index = modifier, after end
    end
    local subject, after = P.noun(document, index, limit, "nominative")
    local capacity
    if not subject or not (subject.article or subject.adjectives or subject.possessor or subject.quantity or subject.demonstrative) then
        local marker = P.key(document, index + 1, limit)
        local beneficiary
        if marker == (english and "for" or "для") then beneficiary = P.preposition(document, index + 1, limit) end
        if not marker or beneficiary and P.relativeAnimate(beneficiary.object) then
            capacity = L.choose(document, index, "noun", not english and {case="nominative"} or nil, nil,
                function(candidate)
                    return lexemeFrame(candidate).capacity and candidate.form.number ~= "plural"
                end)
        end
        if capacity then
            subject = {entry=capacity, person=3, number="singular", gender=capacity.head.gender, animacy=capacity.head.animacy}
            after = index + 1
        end
    end
    if not subject or (copulaNumber and subject.number ~= copulaNumber) then return end
    local adverb, finish = adverbAt(document, after, limit)
    local here = P.key(document, after, limit)
    if not location and adverb and adverb.location and finish > after + 1 then
        location, after = adverb, finish
    elseif here == "around" or here == "here" or here == "тут" then nearby, after = true, after + 1 end
    local tree = {kind="existential", subject=subject, question=question or reason, why=reason,
        nearby=nearby, possessor=possessor,
        capacity=capacity ~= nil, locationAdverb=location, persistence=persistence}
    after = attachNominalAction(document, subject, after, limit, depth)
    for _ = 1, 2 do
        local pp, finish = P.preposition(document, after, limit)
        if not pp or not (spatialAdjuncts[pp.rule.id] or pp.rule.id == "for" and not subject.pronoun) then break end
        tree.prepositions = tree.prepositions or {}
        tree.prepositions[#tree.prepositions + 1] = pp
        after = finish
    end
    adverb, finish = adverbAt(document, after, limit)
    if not tree.locationAdverb and adverb and adverb.location then tree.locationAdverb, after = adverb, finish end
    if after > limit then return tree, after end
    local comma = P.key(document, after, limit) == ","
    if comma then after = after + 1 end
    local marker = P.key(document, after, limit)
    local personal = P.relativeAnimate(subject)
    local explicit = english and (marker == "that" or marker == "who" and personal or marker == "which" and not personal)
        or not english and (marker == "що" or marker and marker == P.relativePronoun(subject, "nominative"))
    if explicit or (english and key == "any" and not comma) then
        local relative, finish = simple(document, after + (explicit and 1 or 0), limit, {subject=subject}, depth + 1, true)
        if relative and relative.inherited and not relative.question then
            tree.relative = relative
            local join, nextIndex = clauseConnector(document, finish, limit)
            if join and (join.id == "and" or join.id == "or") then
                local nextClause, ending = simple(document, nextIndex + 1, limit, relative, depth + 1, true)
                if nextClause and nextClause.inherited and not nextClause.question then
                    tree.relativeContinuation, finish = {clause=nextClause, rule=join}, ending
                end
            end
            return tree, finish
        end
    end
    -- A participial description and a relative clause can share the antecedent.
    if english and not comma and (copulaNumber or personal and (bareIndefinite or key == "is" or key == "are" or key == "any")) then
        local action, nextIndex = verb(document, after, limit, subject, false, false, nil, "present")
        if action then
            local description = {kind="clause", subject=subject, inherited=true, verb=action, tense="present", aspect="continuous"}
            local markerIndex = complements(document, description, nextIndex, limit, depth + 1)
            local linker = markerIndex and P.key(document, markerIndex, limit)
            if copulaNumber and markerIndex and boundary(document, markerIndex, limit) then
                tree.relative = description
                return tree, markerIndex
            end
            if personal and (linker == "who" or linker == "that") then
                local relative, finish = simple(document, markerIndex + 1, limit, {subject=subject}, depth + 1, true)
                if relative and relative.inherited and not relative.question then
                    tree.relative = description
                    tree.relativeContinuation = {clause=relative, rule={en={"and"},uk={"і"}}}
                    return tree, finish
                end
            end
        end
    end
    -- A reduced ability clause has the same subject as the availability question.
    if english and personal and not comma and marker == "able" and P.key(document, after + 1, limit) == "to" then
        local action, nextIndex = verb(document, after + 2, limit, subject, true)
        if action then
            local relative = {kind="clause", subject=subject, inherited=true, modal="can", verb=action, tense="present"}
            local ending = complements(document, relative, nextIndex, limit, depth + 1)
            if ending then tree.relative = relative; return tree, ending end
        end
    end
    if bareIndefinite and not tree.prepositions and not comma then
        local descriptor = {kind="clause", subject=subject, question=true, copula=true, tense="present"}
        local ending = predicate(document, descriptor, after, limit, depth)
        if descriptor.adjective and ending and ending > limit then return descriptor, ending end
    end
end

local needAgreement = {["потрібен"]="masculine", ["потрібна"]="feminine", ["потрібне"]="neuter", ["потрібні"]="plural"}

local function needClause(document, object, index, limit, subject, question, depth)
    local tree = {kind="need", object=object, subject=subject, question=question}
    index = attachNominalAction(document, object, index, limit, depth or 0)
    local place, finish = P.preposition(document, index, limit)
    if place and spatialAdjuncts[place.rule.id] then
        tree.prepositions, index = {place}, finish
    end
    return tree, index
end

local function personalNeed(document, first, limit)
    local question = P.key(document, first, limit) == "чи"
    local subjectAt = first + (question and 1 or 0)
    for marker = subjectAt + 1, math.min(subjectAt + 5, limit - 1) do
        local gender = needAgreement[P.key(document, marker, limit)]
        if gender then
            local subject, after = recipientAt(document, subjectAt, marker - 1, "dative", true)
            if not subject or after ~= marker then return nil end
            local object, finish = P.coordinated(document, marker + 1, limit, "nominative", nil, nil, nil, "reservation")
            local agreement = object and (object.number == "plural" and "plural" or object.gender)
            if agreement ~= gender then return nil end
            question = question or P.key(document, limit + 1, #document.tokens) == "?"
            return needClause(document, object, finish, limit, subject, question)
        end
    end
end

local function requiredAction(document, tree, first, limit, depth, indirect)
    local subject, marker, actionAt, tense, negative, kind = obligationHead(document, first, limit)
    if not subject then return nil end
    if kind == "should" then
        local action, after = verb(document, actionAt, limit, subject, true)
        if not action then return end
        local advice = {kind="clause", subject=subject, verb=action, verbIndex=actionAt,
            modal="should", tense=tense, negative=negative, wh=tree.wh, where=tree.where,
            why=tree.why, when=tree.when, objectGap=tree.objectGap,
            question=tree.question or not indirect and P.key(document, limit + 1, #document.tokens) == "?"}
        local finish = complements(document, advice, after, limit, depth)
        if finish then return advice, finish end
        return
    end
    local entry = L.choose(document, "потребувати", "verb", {mood="infinitive"}, nil, function(candidate)
        local frame = lexemeFrame(candidate)
        return frame.impersonalNeed and frame.infinitive
    end)
    if not entry then return nil end
    local wh = tree.wh
    local query = wh and (wh.kind == "thing" or wh.kind == "person" or wh.kind == "quantity")
    local action, ending = complementaryInfinitive(document, actionAt, limit,
        lexemeFrame(entry), depth, query or tree.objectGap)
    if not action or query and not bindQuestionObject(wh, action.relativeCase) then return nil end
    tree.subject, tree.verb, tree.verbIndex = subject, entry, marker
    tree.infinitive, tree.tense, tree.negative = action, tense, negative
    tree.relativeCase = tree.objectGap and action.relativeCase or nil
    tree.question = tree.question or not indirect and P.key(document, limit + 1, #document.tokens) == "?"
    return tree, ending
end

local function benefitClause(document, first, limit)
    for marker = first + 1, math.min(first + 12, limit - 3) do
        if P.key(document, marker, limit) == "не" then
            local shape, particle = P.key(document, marker + 1, limit), P.key(document, marker + 2, limit)
            if particle ~= "б" and particle ~= "би" then return nil end
            local beneficiary, at = P.pronoun(document, first, marker - 1, "dative", true)
            if not beneficiary then
                beneficiary, at = P.noun(document, first, marker - 1, "dative", false, false, true)
            end
            if not beneficiary or at ~= marker then return nil end
            local resource, finish = P.noun(document, marker + 3, limit, "nominative")
            if not resource then return nil end
            local agreement = resource.number == "plural" and "plural" or resource.gender
            if shape ~= P.benefitPast[agreement] then return nil end
            local tree = {kind="benefit", subject=beneficiary, object=resource, prepositions={}}
            local context = P.semanticClass(resource)
            while #tree.prepositions < 3 do
                local phrase, endAt = P.preposition(document, finish, limit, nil, nil, context)
                if not phrase then break end
                tree.prepositions[#tree.prepositions + 1], finish = phrase, endAt
            end
            return tree, finish
        end
    end
end

local function depletedOwner(document, first, limit)
    local question = P.key(document, first, limit) == "чи"
    local marker = first + (question and 1 or 0)
    local key = P.key(document, marker, limit)
    if key ~= "у" and key ~= "в" then return nil end
    local owner, index = P.pronoun(document, marker + 1, limit, "genitive", true)
    if not owner then owner, index = P.noun(document, marker + 1, limit, "genitive", false, false, true) end
    if not owner then return nil end
    local shape = P.key(document, index, limit)
    local following = P.key(document, index + 1, limit)
    local tense = shape == "немає" and "present"
        or shape == "не" and (following == "було" and "past" or following == "буде" and "future")
    if not tense then return nil end
    local resource, finish = P.noun(document, index + (shape == "не" and 2 or 1), limit, "genitive")
    if not P.isResource(resource) then return nil end
    local tree = {kind="clause", subject=owner, copula=true, tense=tense, exhausted=resource, question=question}
    return tree, predicateTime(document, tree, finish, limit)
end

local function statusWithSubject(document, first, limit)
    local question = P.key(document, first, limit) == "чи"
    local marker = first + (question and 1 or 0)
    local key = P.key(document, marker, limit)
    if key ~= "з" and key ~= "зі" and key ~= "із" then return nil end
    local phrase, at = P.preposition(document, marker, limit)
    if not phrase or phrase.rule.id ~= "with" then return nil end
    local aggregate, after = P.pronoun(document, at, limit, "nominative")
    if not aggregate or aggregate.pronoun.id ~= "everything" then return nil end
    local time = P.key(document, after, limit)
    local tense = time == "було" and "past" or time == "буде" and "future"
    local start = after + (tense and 1 or 0)
    local state, finish = adverbAt(document, start, limit, "predicate")
    if not state or not state.statePredicate then return nil end
    local tree = {kind="clause", subject=phrase.object, copula=true, tense=tense or "present",
        predicateAdverb=state, question=question, negative=P.key(document, start, limit) == state.negativeUk}
    return tree, predicateTime(document, tree, finish, limit)
end

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

local englishHortative = {["let's"]=true, lets=true}

local function hortative(document, first, limit, depth, english, key)
    local subject, action, after, negative
    if english and englishHortative[key] then
        subject = personalSubject("we")
        negative = P.key(document, first + 1, limit) == "not"
        action, after = verb(document, first + (negative and 2 or 1), limit, subject, true)
    elseif not english then
        subject = personalSubject("we")
        if key == "давай" or key == "давайте" then
            negative = P.key(document, first + 1, limit) == "не"
            local start = first + (negative and 2 or 1)
            action, after = verb(document, start, limit, subject, true)
            if not action then action, after = verb(document, start, limit, subject, false) end
        else
            negative = key == "не"
            local start = first + (negative and 1 or 0)
            if start <= limit then
                action, after = verb(document, start, limit, subject, false, true)
            end
        end
    end
    if action then
        local tree = {kind="clause", hortative=true, subject=subject, implicitSubject=true, verb=action,
            tense="present", negative=negative}
        local finish = complements(document, tree, after, limit, depth)
        if finish then return tree, finish end
    end
end

local function abilityNoun(document, first, limit)
    for _, span in ipairs(document.spans[first] or {}) do
        if span.last <= limit and span.term.category == "abilities" then
            local subject, after = P.noun(document, first, limit, "nominative", false, false, true, "ability")
            if subject and subject.term and subject.term.category == "abilities" then return subject, after end
            return nil
        end
    end
end

local function abilitySubject(document, first, limit)
    local subject, after = abilityNoun(document, first, limit)
    if not subject then return nil end
    local english = document.direction == "en-uk"
    local key = P.key(document, after, limit)
    local aux = auxiliary[key]
    local aspect = english and (copula[key] and "present" or have[key] and "past")
    local at = after + ((aux or aspect) and 1 or 0)
    local polarity = P.key(document, at, limit)
    if polarity == "not" or polarity == "не" then at = at + 1 end
    local predicate = verb(document, at, limit, subject, aux ~= nil, nil, nil, aspect)
    local classes = predicate and lexemeFrame(predicate).subjectClasses
    if classes and classes.abilities then return subject, after end
end

local function frontedIntransitivePredicate(document, first, limit, depth)
    local negative = P.key(document, first, limit) == "не"
    local at = first + (negative and 1 or 0)
    local subject, after = abilityNoun(document, at + 1, limit)
    if not subject then
        local fronted = L.choose(document, at, "verb", nil, nil, function(candidate)
            return lexemeFrame(candidate).postposedSubject and candidate.form.tense and not candidate.form.verbalForm
        end)
        if fronted then subject, after = P.noun(document, at + 1, limit, "nominative") end
    end
    if not subject then return nil end
    local predicate, ending = verb(document, at, limit, subject, false)
    local frame = predicate and lexemeFrame(predicate)
    if not frame or not (frame.postposedSubject or frame.subjectClasses and frame.subjectClasses.abilities)
        or ending ~= at + 1 then return nil end
    agreeSubject(document, subject, predicate.form)
    local tree = {kind="clause", verb=predicate, subject=subject, tense=predicate.form.tense,
        negative=negative, verbIndex=at}
    local finish = complements(document, tree, after, limit, depth)
    if finish then return tree, finish end
end

local function ellipticalEvaluation(document, first, limit, depth)
    local english = document.direction == "en-uk"
    local key = P.key(document, first, limit)
    local question = not english and key == "чи" or P.key(document, limit + 1, #document.tokens) == "?"
    local start = first + (not english and key == "чи" and 1 or 0)
    local negative = P.key(document, start, limit) == (english and "not" or "не")
    if negative then start = start + 1 end
    local modifier, following = adverbAt(document, start, limit)
    local at = modifier and modifier.predicateModifier and following or start
    local evaluation = adverbAt(document, at, limit, "predicate")
    if not evaluation or not evaluation.evaluativePredicate then return nil end
    local tree = {kind="clause", subject=personalSubject("it"), copula=true, tense="present",
        question=question, negative=negative}
    local finish = predicate(document, tree, start, limit, depth)
    if finish and tree.evaluation then return tree, finish end
end

local function ellipticalAdjective(document, first, limit, depth)
    local function supportsSpeaker(candidate) return lexemeFrame(candidate).ellipticalSpeaker end
    local requested = document.direction == "uk-en" and {case="nominative"} or nil
    local head = requested and L.genderPair(document, first, limit, "adj", requested, nil, supportsSpeaker)
        or L.choose(document, first, "adj", requested, nil, supportsSpeaker)
    if not head then return nil end
    local tree = {kind="clause", subject=personalSubject("i"), implicitSubject=true, copula=true, tense="present"}
    local finish = predicate(document, tree, first, limit, depth)
    if finish and tree.adjective and (tree.prepositions or tree.infinitive or clauseConnector(document, finish, limit)) then
        return tree, finish
    end
end

local function experienceHead(document, first, limit)
    local anchor = P.key(document, first, limit)
    if document.direction == "uk-en" then
        if anchor ~= "це" then return end
        local link = P.key(document, first + 1, limit)
        local tense = link == "був" and "past" or link == "буде" and "future"
        local opening = first + (tense and 2 or 1)
        if P.key(document, opening, limit) == "вже" then opening = opening + 1 end
        return tense or "present", opening
    end
    if anchor == "it's" or anchor == "that's" then return "present", first + 1 end
    if anchor ~= "it" and anchor ~= "that" and anchor ~= "this" then return nil end
    local link = P.key(document, first + 1, limit)
    if link == "is" or link == "was" then return copula[link], first + 2 end
    if link == "will" and P.key(document, first + 2, limit) == "be" then return "future", first + 3 end
end

local function ordinalEnding(digits)
    local value = tonumber(digits)
    local last, pair = value % 10, value % 100
    return pair >= 11 and pair <= 13 and "th"
        or last == 1 and "st" or last == 2 and "nd" or last == 3 and "rd" or "th"
end

local function occurrenceCount(document, first, limit)
    local english = document.direction == "en-uk"
    local word = P.key(document, first, limit)
    if not word then return end
    local after = first + 1
    local number
    if english then
        local digits, suffix = word:match("^(%d+)(%a%a)$")
        if digits and #digits <= 9 and digits:sub(1, 1) ~= "0" and suffix == ordinalEnding(digits) then
            number = {digits=digits, suffix=suffix}
        end
    elseif word:match("^[1-9]%d*$") and #word <= 9 and P.key(document, after, limit) == "-"
        and P.key(document, after + 1, limit) == P.ordinalSuffixes.nominative then
        number, after = {digits=word, suffix=ordinalEnding(word)}, after + 2
    end
    local requested = not english and {case="nominative",number="singular",gender="masculine"} or nil
    local entry = not number and L.choose(document, first, "adj", requested, nil, function(candidate)
        return lexemeFrame(candidate).eventOrdinal
    end)
    if (entry or number) and P.key(document, after, limit) == (english and "time" or "раз") then
        return number or {entry=entry}, after + 1
    end
end

local function eventExperience(document, first, limit, depth)
    local tense, opening = experienceHead(document, first, limit)
    if not tense then return end
    local english = document.direction == "en-uk"
    if english then
        local article = P.key(document, opening, limit)
        local owner = possessivePronouns[article]
        if owner then
            local ordinal, at = adverbAt(document, opening + 1, limit)
            if not ordinal or not ordinal.firstEvent then return end
            local action, after = verb(document, at, limit, nil, false, false, nil, "present")
            if not action then return end
            local event = {kind="clause", verb=action, verbIndex=at, subject=personalSubject(owner),
                tense=tense, leadingAdverb=ordinal, sequencedEvent=tense == "future"}
            local finish = complements(document, event, after, limit, depth)
            if finish then return event, finish end
            return
        end
        if article ~= "the" then return end
        opening = opening + 1
    end
    local ordinal, index = occurrenceCount(document, opening, limit)
    if not ordinal then return end
    local period, afterPeriod = adverbAt(document, index, limit, nil, function(rule) return rule.occurrenceAnchor end)
    index = afterPeriod or index
    if english then
        local connector = P.key(document, index, limit)
        if connector == "that" or connector == "when" then index = index + 1 end
    else
        if P.key(document, index, limit) == "," then index = index + 1 end
        if P.key(document, index, limit) ~= "коли" then return end
        index = index + 1
    end
    local event, finish = simple(document, index, limit, nil, depth + 1)
    if event and event.kind == "clause" and event.subject and event.verb and not event.imperative and not event.question then
        event.occurrencePerfect = not english and tense ~= "future" and event.tense == "past" and tense or nil
        return {kind="eventOccurrence", event=event, ordinal=ordinal, period=period, tense=tense}, finish
    end
end

local function comparedEvent(document, first, limit, depth)
    local expression, start = adverbAt(document, first, limit, "eventComparison")
    if not expression or expression.context ~= "eventComparison" then return nil end
    local event, finish
    if document.direction == "en-uk" then
        local subject, at = P.noun(document, start, limit, "accusative", false, false, true, "combatActor")
        if not subject then return nil end
        local action, following = verb(document, at, limit, subject, false, false, nil, "present")
        if not action then return nil end
        event = {kind="clause", subject=subject, verb=action, tense="present", perceptionProgressive=true}
        finish = complements(document, event, following, limit, depth + 1)
    else
        if P.key(document, start, limit) == "," then start = start + 1 end
        if P.key(document, start, limit) ~= "ніж" or P.key(document, start + 1, limit) ~= "коли" then return nil end
        event, finish = simple(document, start + 2, limit, nil, depth + 1)
        if not event or not event.subject or not event.verb or event.question or event.imperative then return nil end
        event.perceptionProgressive = true
    end
    if finish and boundary(document, finish, limit) then
        return {kind="eventComparison", event=event, expression=expression}, finish
    end
end

simple = function(document, first, limit, previous, depth, indirect, objectGap)
    local english = document.direction == "en-uk"
    local key = P.key(document, first, limit)
    if not previous and not indirect then
        local price, finish = gradedAdverbAt(document, first, limit, "price")
        if price and finish > limit and (price.intensified or finish > first + 1 or not english) then
            return {kind="adverbPhrase", expression=price}, finish
        end
        if depth < 3 and not objectGap then
            local comparison, ending = comparedEvent(document, first, limit, depth)
            if comparison then return comparison, ending end
        end
    end
    if english and not indirect and (key == "back" or key == "brb") then
        local delay, finish = P.delay(document, first + 1, limit)
        if not delay and key == "brb" then delay, finish = P.quantity(document, first + 1, limit) end
        local returning = delay and L.choose(document, "come back", "verb")
        if returning then
            return {kind="clause", subject=personalSubject("i"), implicitSubject=true, tense="future",
                verb=returning, delay=delay}, finish
        end
    end
    if depth < 3 and not indirect then
        local social, finish = socialComplement(document, first, limit, depth)
        if social then return social, finish end
    end
    if not indirect and (not english or englishHortative[key]) then
        local proposal, endAt = hortative(document, first, limit, depth, english, key)
        if proposal then return proposal, endAt end
    end
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
    if not previous and depth < 3 then
        if not objectGap then
            local experience, finish = eventExperience(document, first, limit, depth)
            if experience then return experience, finish end
        end
        local evaluation, finish = ellipticalEvaluation(document, first, limit, depth)
        if evaluation then return evaluation, finish end
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
        local prospective = tree and tree.tense == "future" and tree.verb and lexemeFrame(tree.verb).measuredPredicate
        if tree and finish and tree.kind == "clause" and (tree.tense == "present" or prospective) and tree.subject
            and not tree.modal and not tree.imperative and not tree.where and not tree.why and not tree.aspect then
            if tree.copula and tree.predicate and tree.subject.pronoun and tree.subject.pronoun.id == "this" then
                tree.subject = personalSubject("it")
            end
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
        special, after = relativeDuration(document, first, limit, english)
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
    if not indirect and not previous then
        special, after = ellipticalAdjective(document, first, limit, depth)
        if special then return special, after end
    end
    if not indirect then
        special, after = existential(document, first, limit, depth)
        if special then return special, after end
    end
    if not english and needAgreement[key] then
        local object, finish = P.coordinated(document, first + 1, limit, "nominative")
        local agreement = object and (object.number == "plural" and "plural" or object.gender)
        if agreement == needAgreement[key] then return needClause(document, object, finish, limit) end
    end
    if not english and not indirect then
        special, after = personalNeed(document, first, limit)
        if special then return special, after end
        special, after = benefitClause(document, first, limit)
        if special then return special, after end
        special, after = depletedOwner(document, first, limit)
        if special then return special, after end
        special, after = statusWithSubject(document, first, limit)
        if special then return special, after end
        special, after = frontedIntransitivePredicate(document, first, limit, depth)
        if special then return special, after end
    end
    local tree, index = {kind="clause", objectGap=objectGap}, first
    local wh, afterQuestion = interrogativeAt(document, first, limit, indirect)
    if wh and wh.kind == "quantity" and wh.noun and not indirect then
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
    elseif indirect and (key == "when" or key == "коли") then
        tree.when, index = true, index + 1
    elseif key == "чи" and not english then
        tree.question, index = true, index + 1
    end
    if not english then
        local requirement, finish = requiredAction(document, tree, index, limit, depth, indirect)
        if requirement then return requirement, finish end
    end
    if not english and (tree.when or wh and wh.kind == "clock") then
        local actor, afterActor = P.coordinated(document, index + 1, limit, "nominative")
        local action, afterVerb
        if actor then action, afterVerb = verb(document, index, limit, actor, false) end
        if action and afterVerb == index + 1 then
            local fronted = {kind="clause", subject=actor, verb=action, verbIndex=index,
                tense=action.form.tense or "present", wh=wh, when=tree.when, question=not indirect}
            local finish = complements(document, fronted, afterActor, limit, depth)
            if finish then return fronted, finish end
        end
    end
    local headIndex = index
    local syntheticAux = wh and wh.auxiliary
    local head = syntheticAux or P.key(document, index, limit)
    if english and index == first then
        local commandStart
        if head == "don't" or head == "dont" then commandStart = index + 1
        elseif head == "do" and P.key(document, index + 1, limit) == "not" then commandStart = index + 2 end
        if commandStart then
            local command, afterVerb = verb(document, commandStart, limit, nil, true, true)
            if command and not lexemeFrame(command).impersonalNeed then
                tree.verb, tree.imperative, tree.negative, tree.tense = command, true, true, "present"
                tree.verbIndex = commandStart
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
        if not syntheticCopula and not syntheticAux then index = index + 1 end
    end
    local subject, nextIndex
    local contraction = english and not inverted and contracted[head]
    if english and not inverted and not contraction and head then
        local id = head:match("^(%a+)'d$")
        local actor = id and personalSubject(id)
        if actor then
            local start = index + (P.key(document, index + 1, limit) == "not" and 2 or 1)
            local _, afterAdverb = adverbAt(document, start, limit)
            start = afterAdverb or start
            if verb(document, start, limit, actor, false, false, nil, "past")
                and not verb(document, start, limit, actor, true) then
                contraction = {id, "had"}
            end
        end
    end
    local indefinite = english and not inverted and indefiniteContractions[head]
    if not contraction and indefinite then
        local actor = personalSubject(indefinite)
        if verb(document, index + 1, limit, actor, false, false, nil, "present") then
            contraction = {indefinite, "is"}
        end
    end
    local mayOmitSubject = inverted and aux and not aux.negative and not wh and headIndex == first
        and not previous and not indirect and not (document.tokens[limit + 1] and document.tokens[limit + 1].key == "?")
    local omittedBenefitSubject = mayOmitSubject and aux.modal == "could"
        and P.key(document, index, limit) == "use"
    if questionSubject then
        subject = english and wh.noun or {person=3, number="singular", gender=wh.kind == "person" and "masculine" or "neuter"}
        nextIndex = index
    elseif contraction then
        subject, nextIndex = personalSubject(contraction[1]), index + 1
    elseif not relativeSubject and not continuedAux and not omittedBenefitSubject then
        subject, nextIndex = abilitySubject(document, index, limit)
        if not subject then subject, nextIndex = P.coordinated(document, index, limit, "nominative") end
        local pointer = subject and subject.pronoun and subject.pronoun.id
        if english and not inverted and index + 2 <= limit and (not subject or pointer == "this" or pointer == "that") then
            local event, ending = P.noun(document, index, limit, "nominative", nil, nil, nil, "recordable")
            if event and ending > (nextIndex or index) then
                local predicate = verb(document, ending, limit, event, false)
                if predicate and lexemeFrame(predicate).subjectSense == "recordable" then subject, nextIndex = event, ending end
            end
        end
    end
    if mayOmitSubject and not subject and (aux.modal == "can" or aux.tense == "future" or omittedBenefitSubject) then
        subject, nextIndex = personalSubject("i"), index
        tree.implicitSubject, tree.question, inverted = true, nil, nil
    end
    local nextPredicate = subject and P.key(document, nextIndex, limit)
    local unmarkedQuestion = english and subject and subject.pronoun
        and (subject.pronoun.id == "someone" or subject.pronoun.indefiniteQuestion)
        and not inverted and not contraction and not wh and not indirect
        and (P.key(document, limit + 1, #document.tokens) == "?" or nextPredicate == "wanna")
    if unmarkedQuestion and nextPredicate == "wanna" and P.key(document, limit + 1, #document.tokens) ~= "?" then
        tree.question = true
    end
    local questionLocation = tree.question or unmarkedQuestion
    if subject and not wh and not tree.copula and nextIndex <= limit
        and (questionLocation or not (subject.pronoun or subject.members or contraction)) then
        local place, finish = P.preposition(document, nextIndex, limit)
        if place and spatialAdjuncts[place.rule.id] and finish <= limit then
            local head = P.key(document, finish, limit)
            if questionLocation or copula[head] or negativeCopula[head] or auxiliary[head]
                or verb(document, finish, limit, subject, false) then
                tree.subjectLocation, nextIndex = {prepositions={place}}, finish
            end
        end
    end
    if subject then
        tree.subject, index = subject, nextIndex
        if not english and subject.number == "plural" then
            local quantifier = P.key(document, index, limit)
            local following = P.key(document, index + 1, limit)
            if (quantifier == "усі" or quantifier == "всі") and (following == "не" or auxiliary[following]) then
                tree.allSubject, index = true, index + 1
            end
        end
    end
    if english and subject and subject.number == "plural" and not inverted and not wh
        and P.key(document, index, limit) == "welcome" and index == limit then
        return {kind="welcomeGroup", subject=subject}, index + 1
    end
    local current = syntheticCopula or contraction and contraction[2] or P.key(document, index, limit)
    local contractedNegative = negativeCopula[current] or negativePerfect[current]
    if contractedNegative then current = contractedNegative end
    if english and subject and not inverted and not contraction and not indirect
        and document.tokens[limit + 1] and document.tokens[limit + 1].key == "?" then
        local ongoing, afterVerb = verb(document, index, limit, subject, false, false, nil, "present")
        if ongoing then
            tree.verb, tree.tense, tree.aspect, tree.question = ongoing, "present", "continuous", true
            tree.verbIndex = index
            local finish = complements(document, tree, afterVerb, limit, depth)
            if finish then return tree, finish end
            return nil
        end
    end
    -- Auxiliary selection is licensed by a participle. A possessive "have"
    -- and an ordinary copula continue through the existing paths.
    local aspectAux = inverted and tree.copula and invertedCopula or not inverted and current
    if english and contraction and aspectAux == "is" and P.key(document, index, limit) == "got" then aspectAux = "has" end
    local prospective
    if english and not subject and not previous and not wh and not indirect and key == "going" then
        prospective = first
    elseif english and subject and copula[aspectAux] == "present" then
        prospective = (inverted or contraction or syntheticCopula) and index or index + 1
    end
    if prospective then
        local negative = P.key(document, prospective, limit) == "not"
        if negative then prospective = prospective + 1 end
        local marker = P.key(document, prospective, limit)
        local actionStart = marker == "gonna" and prospective + 1
            or marker == "going" and P.key(document, prospective + 1, limit) == "to" and prospective + 2
        if actionStart then
            local actor = subject or personalSubject("i")
            local action, afterVerb = verb(document, actionStart, limit, actor, true)
            if action then
                tree.subject, tree.implicitSubject = actor, not subject or tree.implicitSubject
                tree.copula, tree.verb, tree.tense = nil, action, "future"
                tree.verbIndex = actionStart
                tree.negative = tree.negative or negative or contractedNegative ~= nil
                local finish = complements(document, tree, afterVerb, limit, depth)
                if finish then return tree, finish end
                return nil
            end
        end
    end
    local aspectSubject = subject or relativeSubject
    if english and aspectSubject and (have[aspectAux] or copula[aspectAux]) then
        local nextVerb = (inverted or contraction or syntheticCopula) and index or index + 1
        local aspect = have[aspectAux] and "past" or "present"
        local negative = P.key(document, nextVerb, limit) == "not"
        if negative then nextVerb = nextVerb + 1 end
        local adverb, afterAdverb = adverbAt(document, nextVerb, limit)
        if adverb then nextVerb = afterAdverb end
        if not adverb and copula[aspectAux] and deicticSubject(aspectSubject) then
            local state, finish = adverbAt(document, nextVerb, limit, "predicate")
            if state and state.deicticEvaluation and boundary(document, finish, limit) then
                tree.subject, tree.copula, tree.tense = aspectSubject, true, copula[aspectAux]
                tree.predicateAdverb = state
                tree.negative = tree.negative or negative or contractedNegative ~= nil
                return tree, finish
            end
        end
        local candidate, afterVerb = verb(document, nextVerb, limit, aspectSubject, false, false, nil, aspect)
        if have[aspectAux] and aspectAux ~= "had" and not adverb and P.key(document, nextVerb, limit) == "got"
            and (not candidate or afterVerb == nextVerb + 1) then
            local object = P.noun(document, nextVerb + 1, limit, "accusative")
            local head = object and object.entry
            local nominal = object and (object.article or object.possessor or object.demonstrative
                or object.sufficient or object.few or object.quantity or object.number == "plural"
                or object.pronoun or object.term or object.raw
                or head and (head.head.mass or lexemeFrame(head).mass))
            local possession = nominal and verb(document, nextVerb, limit, aspectSubject, true, nil, nil, nil, "have")
            if possession then
                tree.subject, tree.inherited = aspectSubject, not subject
                tree.copula, tree.verb, tree.tense = nil, possession, "present"
                tree.verbIndex, tree.negative = nextVerb, negative or contractedNegative ~= nil
                local finish = complements(document, tree, nextVerb + 1, limit, depth)
                if finish then return tree, finish end
                return nil
            end
        end
        local resultative, passive
        if not candidate and copula[aspectAux] then
            candidate, afterVerb = verb(document, nextVerb, limit, aspectSubject, false, false, nil, "resultative")
            resultative = candidate ~= nil
            if not candidate then
                candidate, afterVerb = verb(document, nextVerb, limit, aspectSubject, false, false, nil, "passive")
                passive = candidate ~= nil
            end
        end
        if candidate and (not inverted or wh or candidate.lexeme.frame) then
            tree.subject, tree.inherited = aspectSubject, not subject
            tree.copula, tree.verb = nil, candidate
            tree.verbIndex = nextVerb
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
            local helper = auxiliary[current]
            local operand = index + 1
            local lexical = english and helper.support and not helper.negative and not contraction
                and P.key(document, operand, limit) ~= "not"
                and P.noun(document, operand, limit, "accusative")
                and not verb(document, operand, limit, subject, true)
            if not lexical then
                aux = helper
                if not contraction then index = operand end
            end
        end
    end
    if not english and subject then
        local time, after = adverbAt(document, index, limit)
        if time and time.time and P.key(document, after, limit) == "не" then
            tree.adverbs, index = {time}, after
        end
    end
    if not english then
        local modifier, following = adverbAt(document, index, limit, nil, function(candidate)
            return candidate.preNegative
        end)
        if modifier and P.key(document, following, limit) == "не" then
            tree.leadingAdverb, index = modifier, following
        end
    end
    local negative = P.key(document, index, limit)
    if negative == "not" or negative == "не" then
        tree.negative, index = true, index + 1
    end
    if not english and not aux and auxiliary[P.key(document, index, limit)] then
        aux, index = auxiliary[P.key(document, index, limit)], index + 1
    end
    if not english and not aux and not tree.copula then
        local helper, following = inflectedAbility(document, index, limit)
        if helper then aux, index = helper, following end
    end
    if aux then
        tree.tense, tree.modal, tree.negative = aux.tense, aux.modal,
            tree.negative or aux.negative or (contraction and contraction[4])
        tree.ability = not english and aux.ability or nil
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
    if english then
        local ability = tree.copula and tree.tense or aux and (aux.ability or aux.tense == "future" and "future")
        local at = ability and abilityComplementStart(document, index, limit, tree.copula)
        if at then
            tree.ability, tree.copula, tree.modal, index = ability, nil, "can", at
            aux = aux or auxiliary.can
        elseif aux and aux.ability then return nil end
    end
    if not english and wh and wh.role == "predicate" then tree.copula = true end
    if english and tree.modal == "might" then
        if tree.where or tree.why or wh then return nil end
        if P.key(document, index, limit) == "be" then
            tree.copula, index = true, index + 1
        end
    elseif english and tree.tense == "future" and P.key(document, index, limit) == "be" then
        tree.copula, index = true, index + 1
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
    if english and subject and not (aux or tree.question or contractedNegative or indirect) then
        local finish = servicePredicate(document, tree, index, limit)
        if finish then tree.copula, tree.tense = true, "present"; return tree, finish end
    end
    local inheritedSubject = not subject and previous and previous.subject
    local inheritedImperative = not subject and previous and previous.imperative
    local sharedModal = inheritedSubject and not aux and previous.modal or nil
    tree.imperative = (not subject and not inheritedSubject and not aux and english) or inheritedImperative
    if inverted and not subject then return nil end
    local afterVerb
    local contractedPredicate = contraction and contraction[3]
    if (subject or inheritedSubject or tree.imperative) and not contractedPredicate then
        local adverb, following = adverbAt(document, index, limit)
        if adverb and (not tree.imperative or adverb.commandModifier)
            and (english or not adverb.location or following <= limit) then
            tree.leadingAdverb, index = adverb, following
            if tree.imperative and adverb.negativeCommand then
                tree.negative = true
            end
        end
    end
    local verbIndex = not contractedPredicate and index or nil
    if not english and wh and wh.kind == "thing" and wh.role == "object" and not wh.noun
        and boundary(document, index + 1, limit) then
        tree.verb, afterVerb = verb(document, index, limit, subject, aux ~= nil, tree.imperative, "generalAction")
    end
    if not tree.verb then
        tree.verb, afterVerb = verb(document, contractedPredicate and headIndex or index, limit,
            subject or inheritedSubject, aux ~= nil or sharedModal ~= nil, tree.imperative, nil, nil,
            contractedPredicate, inheritedSubject and previous)
    end
    if english and tree.imperative and tree.leadingAdverb and tree.leadingAdverb.pastUk then
        local past = L.choose(document, index, "verb", {tense="past"}, nil, function(candidate)
            return not candidate.form.verbalForm and not candidate.form.mood
        end)
        if past and (not tree.verb or past.lexeme.en ~= tree.verb.lexeme.en
            and past.lexeme.preference < tree.verb.lexeme.preference) then
            tree.verb, tree.imperative, tree.ellipticSubject, afterVerb = past, nil, true, index + 1
        end
    end
    if unmarkedQuestion and not tree.verb and not aux then
        tree.verb, afterVerb = verb(document, index, limit, subject, true)
        if tree.verb then tree.question = true end
    end
    if not tree.verb and not subject and not english and not aux then
        tree.verb, afterVerb = verb(document, index, limit, nil, false, true)
        tree.imperative = tree.verb ~= nil
    end
    if not tree.verb and not english and subject and (not aux or aux.tense == "future") then
        if not aux and subject.demonstrative then
            local pointer, following = P.pronoun(document, headIndex, limit, "nominative")
            if pointer and pointer.pronoun.id == "this" then
                local identity = {kind="clause", subject=pointer, copula=true, tense="present", question=tree.question}
                local finish = predicate(document, identity, following, limit, depth)
                if identity.predicate and finish and boundary(document, finish, limit) then return identity, finish end
            end
        end
        local finish = predicate(document, tree, index, limit, depth)
        if finish then
            tree.copula, tree.tense = true, tree.tense or "present"
            tree.predicateAdverb = tree.predicateAdverb or tree.leadingAdverb
            return tree, finish
        end
    end
    if not tree.verb and english and subject and not (subject.pronoun or subject.genitive or subject.destination)
        and not aux and not tree.question then
        local imperative, after = verb(document, first, limit, nil, false, true, nil, nil, nil, previous)
        if imperative then
            tree, subject, afterVerb = {kind="clause", verb=imperative, imperative=true}, nil, after
            verbIndex = first
            if previous and previous.subject and (previous.modal or previous.tense == "future") then
                inheritedSubject, sharedModal, tree.imperative = previous.subject, previous.modal, nil
            end
        end
    end
    if not tree.verb and tree.imperative and english and not subject and not aux then
        local statement, following = verb(document, index, limit, nil, false, false, "impersonal")
        if statement and statement.form.tense then
            tree.verb, tree.imperative, afterVerb = statement, nil, following
        else
            local past = L.choose(document, index, "verb", {tense="past"}, nil, function(candidate)
                return not candidate.form.verbalForm and not candidate.form.mood
            end)
            if past then
                tree.verb, tree.imperative, tree.ellipticSubject, afterVerb = past, nil, true, index + 1
            end
        end
    end
    if not tree.verb then return nil end
    tree.verbIndex = verbIndex
    if not english and verbIndex and afterVerb == verbIndex + 3 and P.key(document, verbIndex + 1, limit) == "/" then
        tree.verbAlternativesEnd = afterVerb - 1
    end
    if unmarkedQuestion and tree.subjectLocation then tree.question = true end
    local frame = lexemeFrame(tree.verb)
    if english and tree.imperative and not tree.negative and frame.impersonalNeed then
        local object, finish = P.coordinated(document, afterVerb, limit, "accusative", nil, nil, nil, frame.objectSense)
        if object then return needClause(document, object, finish, limit, nil, nil, depth) end
        return nil
    end
    if english and tree.imperative and not subject and not inheritedSubject and frame.subjectlessQuestion
        and P.key(document, limit + 1, #document.tokens) == "?" then
        subject, tree.question, tree.imperative = personalSubject("you"), true, nil
    end
    if english then refineSubject(document, subject, frame)
    else agreeSubject(document, subject, tree.verb.form) end
    local implicit = frame.implicitSubject
    if implicit and not inheritedSubject and (not subject or subject.pronoun and subject.pronoun.id == implicit) then
        subject = subject or personalSubject(implicit)
        tree.implicitSubject, tree.imperative = true, nil
    end
    tree.subject = subject or inheritedSubject
    tree.inherited = inheritedSubject ~= nil and inheritedSubject ~= false
    tree.modal, tree.sharedModal = tree.modal or sharedModal, sharedModal ~= nil
    if english and not aux and inheritedSubject and previous.tense == "future" and tree.verb.form.mood == "base" then
        tree.tense = "future"
    end
    tree.tense = tree.tense or tree.verb.form.tense or "present"
    local finish = complements(document, tree, afterVerb, limit, depth)
    if finish then
        if english and frame.dativeNeed and tree.subject and tree.object and not tree.wh
            and tree.tense == "present" and not (tree.modal or tree.aspect or tree.negative) then
            tree.kind = "need"
        end
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
    if tree.modal == "could" and tree.verb and tree.subject and not past and not tree.negative then
        local pronoun = tree.subject.pronoun
        if tree.question and pronoun and (pronoun.person == 2 or pronoun.id == "someone") then
            tree.modalSense = "request"
        elseif not tree.question and lexemeFrame(tree.verb).possibleOutcome then
            tree.modalSense = "possibility"
        end
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
    local english = document.direction == "en-uk"
    local preposition
    if not english and not P.relativeMarkers[document.direction][marker] then
        local keys, after = L.functional(document, "prepositions", markerIndex, limit)
        local nextMarker = after == markerIndex and P.key(document, after + 1, limit)
        if keys and nextMarker and P.relativeMarkers[document.direction][nextMarker] then
            preposition, marker, markerIndex = marker, nextMarker, after + 1
        end
    end
    local unmarked = english and not comma and document.relativeAnchors
        and document.relativeAnchors[first] == noun.headIndex and noun.headIndex ~= nil
    if not (unmarked or P.relativeMarkers[document.direction][marker]) or markerIndex >= limit
        or document.relativeBudget == 0 or document.relativeDepth >= 3 then return end
    local person = P.relativeAnimate(noun)
    if english and ((marker == "who" or marker == "whom") and not person or marker == "which" and person) then return end

    local subjectReading = not (unmarked or preposition)
        and (english and marker ~= "whom" or marker == P.relativePronoun(noun, "nominative"))
    local oldDepth = document.relativeDepth
    document.relativeDepth = oldDepth + 1
    local selected, ending, role
    local start = markerIndex + (unmarked and 0 or 1)
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
        local previousClass, previousMarker = document.relativeClass, document.relativeMarker
        document.relativeClass, document.relativeMarker = P.semanticClass(noun), preposition
        local tree, after = simple(document, start, limit, nil, oldDepth + 1, true, {marker=preposition})
        document.relativeClass, document.relativeMarker = previousClass, previousMarker
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

local function supportEllipsis(document, first, limit, antecedent)
    if antecedent.imperative or not (antecedent.verb or antecedent.copula and antecedent.adjective) then return nil end
    local subject, marker = P.coordinated(document, first, limit, "nominative")
    if not subject then return nil end
    if antecedent.copula then
        local key = P.key(document, marker, limit)
        local form = negativeCopula[key] or key
        local tense = copula[form]
        local negative = negativeCopula[key] ~= nil
        local index = marker + 1
        if not negative and P.key(document, index, limit) == "not" then negative, index = true, index + 1 end
        local plural = subject.number == "plural" or subject.person == 2
        local expected = tense == "past" and (plural and "were" or "was")
            or plural and "are" or subject.person == 1 and "am" or "is"
        if tense and form == expected and boundary(document, index, limit) then
            return {kind="clause", subject=subject, adjective=antecedent.adjective, copula=true,
                tense=tense, negative=negative}, index
        end
        return nil
    end
    local aux = auxiliary[P.key(document, marker, limit)]
    if not aux or not aux.support then return nil end
    local index = marker + 1
    local negative = aux.negative or P.key(document, index, limit) == "not"
    if negative and not aux.negative then index = index + 1 end
    if not boundary(document, index, limit) then return nil end
    return {kind="clause", subject=subject, verb=antecedent.verb, tense=aux.tense, negative=negative}, index
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
        if not tree and document.direction == "en-uk" and precedingJoin and precedingJoin.rule
            and precedingJoin.rule.predicateEllipsis then
            tree, after = supportEllipsis(document, index, limit, trees[#trees])
        end
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
                    local time, following = adverbAt(document, ending, limit)
                    local pp, finish = P.preposition(document, ending, limit)
                    if time and time.nominalTime and following > limit then
                        tree, after = {kind="nounPhrase", subject=noun, adverbs={time}}, following
                    elseif pp or ((noun.same or noun.adjectives or noun.possessor or noun.nominalObject or noun.genitive or noun.many or noun.more
                        or noun.destination or noun.term and noun.term.features and noun.term.features.canStandAlone)
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
        elseif comma and index < limit and tree.imperative and tree.verb and lexemeFrame(tree.verb).discourseCommand then
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
    for i, join in ipairs(joins) do
        local action, followup = trees[i], trees[i + 1]
        if join.rule and join.rule.id == "then" and action.tense == "future"
            and followup.tense == "future" and followup.inherited then
            action.sequencedEvent, followup.sequencedEvent = true, true
        elseif join.rule and (join.rule.id == "when" and action.imperative or join.rule.id == "whenever"
            or join.rule.id == "if" and (action.modal or action.tense == "future")) then
            followup.temporalDependent = true
        end
    end
    local main = trees[2]
    if prefix and prefix.id == "if" and main and (main.imperative or main.modal or main.tense == "future") then
        local condition = trees[1]
        condition.temporalDependent = true
        local pronoun = main.object and main.object.pronoun
        local senses = main.verb and lexemeFrame(main.verb).conditionalObjectSenses
        if document.direction == "en-uk" and senses and pronoun and pronoun.id == "it"
            and condition.verb and not (condition.object or condition.content or condition.controlled) then
            local sense = senses[P.semanticClass(condition.subject)]
            local reading = sense and L.choose(document, main.verb.lexeme.en, "verb", nil, sense)
            if reading then main.verb, main.sequencedEvent = reading, true end
        end
    end
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
    controlledTemporal.before,
    {source="uk", en={"after"}, uk={"після того як"}, ukTags={"ADP", "PRON", "SCONJ"},
        nominalHead=2, temporal=true, reverseAttachment=true},
    {source="uk", en={"after"}, uk={"після того, як"}, ukPattern="після того , як",
        ukTags={"ADP", "PRON", "PUNCT", "SCONJ"}, nominalHead=2, temporal=true},
    controlledTemporal.after,
    {id="until", en={"until"}, uk={"доки"}, ukStatus="аж до того, як", temporal=true, reverseAttachment=true},
    {source="uk", id="until", en={"until"}, uk={"аж до того, як"}, ukPattern="аж до того , як",
        ukTags={"ADV", "ADP", "PRON", "PUNCT", "SCONJ"}, nominalHead=3, temporal=true},
    {en={"once"}, uk={"щойно"}, temporal=true},
    {en={"by the time"}, uk={"на той час, коли"}, ukPattern="на той час , коли",
        ukTags={"ADP", "DET", "NOUN", "PUNCT", "ADV"}, nominalHead=3, temporal=true, deadline=true},
    {en={"next time"}, uk={"наступного разу, коли"}, ukPattern="наступного разу , коли",
        enTags={"ADJ", "NOUN"}, ukTags={"ADJ", "NOUN", "PUNCT", "ADV"},
        nominalHead=2, temporal=true, prospective=true},
}

local function temporalMarker(document, first, limit)
    local source = document.direction == "en-uk" and "en" or "uk"
    for _, rule in ipairs(temporalRules) do
        if not rule.source or rule.source == source then
            local index = first
            local pattern = source == "uk" and rule.ukPattern or rule[source][1]
            for word in pattern:gmatch("%S+") do
                if P.key(document, index, limit) ~= word then index = nil; break end
                index = index + 1
            end
            if index and index <= limit then return rule, index - 1 end
        end
    end
end

local function finiteClause(parsed, dependent)
    if not parsed or parsed.prefix then return false end
    local tree = parsed.trees[1]
    return tree.kind == "clause" and (tree.verb or tree.copula) and (not dependent or not tree.imperative)
end

local function scopedVerbs(document, first, last, role)
    local domains = {}
    for index = first, last do
        local token = document.tokens[index]
        if not token.protected then
            for _, entry in ipairs(L.lookup(document, token.key)) do
                local frame = entry.lexeme.frame
                if entry.lexeme.pos == "verb" and frame and frame.contextRole == role then
                    domains[frame.contextDomain] = true
                end
            end
        end
    end
    return domains
end

local function temporalDomain(document, mainFirst, mainLast, subordinateFirst, subordinateLast)
    if document.direction ~= "en-uk" then return nil end
    local action = scopedVerbs(document, mainFirst, mainLast, "action")
    if not next(action) then return nil end
    local ending = scopedVerbs(document, subordinateFirst, subordinateLast, "followup")
    local domain
    for name in pairs(ending) do
        if action[name] then
            if domain then return nil end
            domain = name
        end
    end
    return domain
end

local function inClass(noun, class)
    if not noun then return false end
    local frame = noun.entry and noun.entry.lexeme.frame
    if frame and frame.semanticClass == class then return true end
    return class == "equipment" and ((noun.raw and ns.Engine.Markup.isLink(noun.raw, "item"))
        or (noun.term and (noun.term.category == "goods" or noun.term.category == "equipment")))
end

local function matchesTemporalDomain(main, dependent, domain)
    if not finiteClause(main) or not finiteClause(dependent, true) then return false end
    local action, ending = main.trees[1], dependent.trees[1]
    if not action.verb or not ending.verb then return false end
    local actionFrame, endingFrame = lexemeFrame(action.verb), lexemeFrame(ending.verb)
    if actionFrame.contextDomain ~= domain or actionFrame.contextRole ~= "action"
        or endingFrame.contextDomain ~= domain or endingFrame.contextRole ~= "followup"
        or not inClass(action.object, actionFrame.contextObject) or ending.prepositions then return false end
    if not actionFrame.contextLocation then return true end
    for _, pp in ipairs(action.prepositions or {}) do
        if pp.rule.id == "in" and inClass(pp.object, actionFrame.contextLocation) then return true end
    end
    return false
end

local function temporalClauses(document, mainFirst, mainLast, subordinateFirst, subordinateLast)
    local domain = temporalDomain(document, mainFirst, mainLast, subordinateFirst, subordinateLast)
    if domain then
        document.transferDomain = domain
        local action = parseWithRelatives(document, mainFirst, mainLast)
        local ending = finiteClause(action) and parseWithRelatives(document, subordinateFirst, subordinateLast)
        document.transferDomain = nil
        if matchesTemporalDomain(action, ending, domain) then return action, ending end
    end

    local action = parseWithRelatives(document, mainFirst, mainLast)
    local ending = finiteClause(action) and parseWithRelatives(document, subordinateFirst, subordinateLast)
    if finiteClause(ending, true) then return action, ending end
end

local function markNominal(tags, noun)
    if not noun then return end
    if noun.headIndex then
        tags[noun.headIndex] = noun.term and noun.term.category == "places" and "PROPN" or "NOUN"
    end
    for _, member in ipairs(noun.members or {}) do markNominal(tags, member) end
end

local function markInfinitives(tags, clause)
    local action = clause.infinitive
    while action and action.verbIndex do
        tags[action.verbIndex] = {pos="VERB", lemma=action.verb.lexeme.uk, feats="VerbForm=Inf"}
        action = action.infinitive
    end
end

local function temporalArcs(parser, document, first, last, marker, markerEnd, markerTags, main, dependent, commaBefore, later)
    local english = document.direction == "en-uk"
    local tags = (not english or ns.UDPipeTagWeights) and {} or nil
    local alternatives
    for _, clause in ipairs({main, dependent, later and later.parsed or nil}) do
        for _, tree in ipairs(clause.trees) do
            if tags and (english or later) then
                markNominal(tags, tree.subject)
                markNominal(tags, tree.object)
                markNominal(tags, tree.recipient)
                for _, phrase in ipairs(tree.subjectLocation and tree.subjectLocation.prepositions or {}) do
                    markNominal(tags, phrase.object)
                end
                if tree.verbIndex then
                    local head = tree.verbIndex
                    local word = tree.verb and tree.verb.lexeme.en:match("^%S+")
                    local prefixTag = tree.verb and lexemeFrame(tree.verb).compoundModifierTag
                    while word do
                        local modifier, remainder = word:match("^([^-]+)%-(.+)$")
                        if not modifier or P.key(document, head, head) ~= modifier
                            or P.key(document, head + 1, head + 1) ~= "-" then break end
                        tags[head] = prefixTag
                        head, word = head + 2, remainder
                    end
                    tags[head] = "VERB"
                end
            end
            if not english then markInfinitives(tags, tree) end
            if not english and tree.verbAlternativesEnd then
                alternatives = alternatives or {}
                alternatives[tree.verbIndex] = tree.verbAlternativesEnd
            end
        end
    end
    if later then
        local laterTags = english and later.rule.enTags or later.rule.ukTags
        for index = later.marker, later.finish do
            tags[index] = laterTags and laterTags[index - later.marker + 1] or "SCONJ"
        end
    end
    return parser.analyzeDocument(document, first, last, marker, markerEnd, tags, markerTags, alternatives, commaBefore)
end

local function confirmedAttachment(arcs, offset, start, finish, subordinateFirst, subordinateLast, mainFirst, mainLast, rule)
    if rule.nominalHead then
        local anchor = start + rule.nominalHead - 1
        local noun = arcs[anchor - offset]
        local parent = noun and noun.head + offset
        if noun and parent >= mainFirst and parent <= mainLast then
            for index = subordinateFirst, subordinateLast do
                local clause = arcs[index - offset]
                if clause.head + offset == anchor and clause.relation:match("^acl") then return true end
            end
        end
    end
    for marker = start, finish do
        local arc = arcs[marker - offset]
        if arc and (arc.relation == "mark" or rule.nominalHead and marker == finish and arc.relation == "advmod")
            and arc.head > 0 then
            local dependent = arc.head + offset
            local predicate = arcs[arc.head]
            local parent = predicate.head + offset
            if rule.reverseAttachment and arc.relation == "mark" and predicate.head == 0
                and dependent >= subordinateFirst and dependent <= subordinateLast then
                for index = mainFirst, mainLast do
                    local main = arcs[index - offset]
                    if main.head + offset == dependent and main.relation == "advcl" then return true end
                end
            end
            -- A complete multiword temporal marker identifies the relation.
            -- In such cases the model still has to link the two clauses.
            local attached = predicate.relation:match("^advcl") or start < finish
                and (predicate.relation == "acl" or predicate.relation == "ccomp")
            if not attached and rule.nominalHead and marker == finish and predicate.relation == "parataxis" then
                local noun = arcs[start + rule.nominalHead - 1 - offset]
                local governor = noun and noun.head + offset
                attached = noun and noun.relation == "obl" and governor >= mainFirst and governor <= mainLast
            end
            if dependent >= subordinateFirst and dependent <= subordinateLast and attached and predicate.head > 0 then
                -- The relative clause in a nominal time expression may attach through its noun.
                if rule.nominalHead then
                    for _ = start, finish do
                        if parent < start or parent > finish then break end
                        local nextArc = arcs[parent - offset]
                        if not nextArc or nextArc.head <= 0 then break end
                        parent = nextArc.head + offset
                    end
                end
                if parent >= mainFirst and parent <= mainLast then return true end
            end
        end
    end
    return false
end

local function locativeState(tree)
    if not tree.copula then return false end
    if tree.predicateAdverb and tree.predicateAdverb.location then return true end
    for _, adverb in ipairs(tree.adverbs or {}) do
        if adverb.location then return true end
    end
    for _, phrase in ipairs(tree.prepositions or {}) do
        if spatialAdjuncts[phrase.rule.id] then return true end
    end
    return false
end

local function explicitUntilBoundary(document, rule, main, dependent, comma)
    if rule.id ~= "until" or rule.uk[1] ~= "доки" or #main.trees ~= 1 or #dependent.trees ~= 1
        or not main.trees[1].imperative then return false end
    local endpoint = dependent.trees[1]
    if not endpoint.subject or endpoint.question or not locativeState(endpoint) then return false end
    if document.direction == "en-uk" then return endpoint.tense == "present" end
    return comma and endpoint.tense == "future" and endpoint.negative
end

local function joined(document, left, right, junction, prefix, tail, dependency)
    local subordinate = prefix and left or right
    local main = prefix and right or left
    local rule = prefix or junction.rule
    local english = document.direction == "en-uk"
    local action = main.trees[1]
    for _, tree in ipairs(subordinate.trees) do
        tree.temporalDependent = true
        if rule and rule.prospective and tree.tense == "present" then tree.tense = "future" end
        if rule and rule.id == "until" and rule.uk[1] == "доки" and locativeState(tree) then
            if english and not tree.negative and tree.tense == "present"
                and (action.imperative or action.modal or action.tense == "future") then
                tree.tense, tree.expletiveNegative = "future", true
            elseif not english and tree.negative and tree.tense == "future" then
                tree.expletiveNegative = true
            end
        end
    end
    if rule and rule.deadline then
        for _, tree in ipairs(main.trees) do tree.deadlineMain = true end
        if main.trees[1].tense == "future" then
            for _, tree in ipairs(subordinate.trees) do tree.deadlineFuture = true end
        end
    end
    local trees, joins = {}, {}
    for _, tree in ipairs(left.trees) do trees[#trees + 1] = tree end
    for _, tree in ipairs(right.trees) do trees[#trees + 1] = tree end
    for _, join in ipairs(left.joins) do joins[#joins + 1] = join end
    joins[#joins + 1] = junction
    for _, join in ipairs(right.joins) do joins[#joins + 1] = join end
    if tail then
        joins[#joins + 1] = {rule=tail.rule, comma=true}
        for _, tree in ipairs(tail.parsed.trees) do trees[#trees + 1] = tree end
        for _, join in ipairs(tail.parsed.joins) do joins[#joins + 1] = join end
    end
    return {trees=trees, joins=joins, prefix=prefix, dependency=dependency}
end

local function frontedControlledTime(document, first, limit)
    if document.direction ~= "en-uk" then return nil end
    local rule = controlledTemporal[P.key(document, first, limit)]
    if not rule then return nil end
    for comma = first + 2, math.min(first + 12, limit - 1) do
        if P.key(document, comma, limit) == "," then
            local main = parseWithRelatives(document, comma + 1, limit)
            if finiteClause(main) then
                local dependent, finish = controlledTimeClause(document, first + 1, comma - 1, main.trees[1], 0)
                if dependent and finish == comma then
                    return joined(document, {trees={dependent}, joins={}}, main, {comma=true}, rule)
                end
            end
            return nil
        end
    end
end

local function temporalTail(document, first, limit)
    for comma = first, limit - 2 do
        if P.key(document, comma, limit) == "," then
            local rule, last = clauseConnector(document, comma + 1, limit)
            if rule and rule.id == "then" then
                local parsed = parseWithRelatives(document, last + 1, limit)
                if parsed and not parsed.prefix and parsed.trees[1].imperative then
                    return {finish=comma - 1, rule=rule, parsed=parsed}
                end
            end
        end
    end
end

local function unpunctuatedTemporal(document, parser, first, limit, rule, markerEnd, markerTags)
    local subordinateFirst = markerEnd + 1
    local split, main, dependent
    local attempts = 0
    for index = subordinateFirst + 2, limit do
        if verb(document, index, limit, nil, true, true) then
            attempts = attempts + 1
            if attempts > 4 then return nil end
            local action, timing = temporalClauses(document, index, limit, subordinateFirst, index - 1)
            if action and action.trees[1].imperative and timing.trees[1].subject then
                if split then return nil end
                split, main, dependent = index, action, timing
            end
        end
    end
    if not split then return nil end
    document.udpipeUsed = true
    local offset = first - 1
    local arcs = temporalArcs(parser, document, first, limit, first, markerEnd, markerTags, main, dependent, split)
    if not arcs then return nil end
    local attached = confirmedAttachment(arcs, offset, first, markerEnd,
        subordinateFirst, split - 1, split, limit, rule)
    if not attached then
        -- Without a comma, the model can attach the command under the
        -- relative predicate. The complete clauses already identify the roles.
        local actionIndex, timingIndex = main.trees[1].verbIndex, dependent.trees[1].verbIndex
        local action = actionIndex and arcs[actionIndex - offset]
        local timing = timingIndex and arcs[timingIndex - offset]
        attached = action and timing and action.head + offset == timingIndex
            and timing.head + offset == first + rule.nominalHead - 1
            and timing.relation:match("^acl") and (action.relation == "ccomp" or action.relation == "parataxis")
    end
    if attached then return joined(document, dependent, main, {comma=true}, rule, nil, true) end
end

local function markedPredicate(arcs, offset, first, last, tree)
    if not tree.verbIndex then return false end
    for index = first, last do
        local arc = arcs[index - offset]
        if arc and arc.relation == "mark" and arc.head + offset == tree.verbIndex then return true end
    end
    return false
end

local function temporalChain(document, parser, first, limit, marker, markerEnd, markerTags, rule, mainEnd)
    if rule.nominalHead then return nil end
    local middleStart = markerEnd + 1
    local later, middle, middleEnd
    for index = middleStart + 2, limit - 1 do
        local nextRule, finish = temporalMarker(document, index, limit)
        if nextRule and not nextRule.nominalHead then
            local ending = index - (P.key(document, index - 1, limit) == "," and 2 or 1)
            local candidate = parseWithRelatives(document, middleStart, ending)
            if finiteClause(candidate, true) and #candidate.trees == 1 then
                local last = parseWithRelatives(document, finish + 1, limit)
                if finiteClause(last, true) and #last.trees == 1 then
                    if later then return nil end
                    later = {rule=nextRule, parsed=last, marker=index, finish=finish}
                    middle, middleEnd = candidate, ending
                end
            end
        end
    end
    if not later then return nil end
    local main = parseWithRelatives(document, first, mainEnd)
    if not finiteClause(main) or #main.trees ~= 1 then return nil end
    document.udpipeUsed = true
    local arcs = temporalArcs(parser, document, first, limit, marker, markerEnd, markerTags, main, middle, nil, later)
    if not arcs then return nil end
    local offset = first - 1
    local attached = confirmedAttachment(arcs, offset, marker, markerEnd, middleStart, middleEnd, first, mainEnd, rule)
        and confirmedAttachment(arcs, offset, later.marker, later.finish,
            later.finish + 1, limit, first, middleEnd, later.rule)
    if not attached and document.direction == "uk-en" and mainEnd + 2 == marker and middleEnd + 2 == later.marker then
        -- Two explicit clause boundaries retain their finite predicates even when
        -- the model attaches a finite predicate below its infinitive complement.
        local root = main.trees[1].verbIndex
        local action = later.parsed.trees[1].infinitive
        local alternativeRoot = action and action.verbIndex
        local rooted = root and arcs[root - offset].head == 0
            or alternativeRoot and arcs[alternativeRoot - offset].head == 0
        attached = rooted
            and markedPredicate(arcs, offset, marker, markerEnd, middle.trees[1])
            and markedPredicate(arcs, offset, later.marker, later.finish, later.parsed.trees[1])
    end
    if not attached then return nil end
    local firstPair = joined(document, main, middle, {rule=rule}, nil, nil, true)
    return joined(document, firstPair, later.parsed, {rule=later.rule}, nil, nil, true)
end

local function temporalAttachment(document, first, limit)
    local parser = ns.Engine.UDPipe
    if not parser or not ns.UDPipeModels or document.udpipeUsed or limit - first >= 32 then return nil end
    local attempts = 0
    for marker = first, limit - 1 do
        local rule, markerEnd = temporalMarker(document, marker, limit)
        if rule then
            local markerTags = document.direction == "uk-en" and rule.ukTags or rule.enTags
            local subordinateFirst = markerEnd + 1
            if marker == first then
                local hasSeparator
                for separator = subordinateFirst + 1, limit - 1 do
                    if P.key(document, separator, limit) == "," then
                        hasSeparator = true
                        attempts = attempts + 1
                        if attempts > 4 then return nil end
                        local main, dependent = temporalClauses(document, separator + 1, limit,
                            subordinateFirst, separator - 1)
                        if main then
                            document.udpipeUsed = true
                            local arcs = temporalArcs(parser, document, first, limit, marker, markerEnd,
                                markerTags, main, dependent)
                            if arcs and confirmedAttachment(arcs, first - 1, marker, markerEnd,
                                subordinateFirst, separator - 1, separator + 1, limit, rule) then
                                return joined(document, dependent, main, {comma=true}, rule, nil, true)
                            end
                            return nil
                        end
                    end
                end
                if not hasSeparator and rule.nominalHead and limit - subordinateFirst >= 3 then
                    return unpunctuatedTemporal(document, parser, first, limit, rule, markerEnd, markerTags)
                end
            else
                attempts = attempts + 1
                if attempts > 4 then return nil end
                local comma = P.key(document, marker - 1, limit) == ","
                local mainEnd = marker - (comma and 2 or 1)
                if mainEnd >= first then
                    local tail = temporalTail(document, subordinateFirst + 1, limit)
                    local finish = tail and tail.finish or limit
                    local main, dependent = temporalClauses(document, first, mainEnd, subordinateFirst, finish)
                    if main then
                        document.udpipeUsed = true
                        local arcs = temporalArcs(parser, document, first, finish, marker, markerEnd,
                            markerTags, main, dependent)
                        local attachment = arcs and confirmedAttachment(arcs, first - 1, marker, markerEnd,
                            subordinateFirst, finish, first, mainEnd, rule)
                        if attachment or explicitUntilBoundary(document, rule, main, dependent, comma) then
                            return joined(document, main, dependent, {rule=rule}, nil, tail, attachment or nil)
                        end
                        return nil
                    end
                    if not tail then
                        local chain = temporalChain(document, parser, first, limit, marker, markerEnd, markerTags, rule, mainEnd)
                        if chain or document.udpipeUsed then return chain end
                    end
                end
            end
        end
    end
end

local function parseGroup(document, first, limit)
    return parseWithRelatives(document, first, limit) or frontedControlledTime(document, first, limit)
        or temporalAttachment(document, first, limit)
end

function A.parse(document, first, limit)
    local key = P.key(document, first, limit)
    if key == "please" or key == "будь" then
        local polite, after = adverbAt(document, first, limit)
        if polite and polite.clausePoliteness then
            local start = after + (P.key(document, after, limit) == "," and 1 or 0)
            if start > limit and document.direction == "en-uk" then
                return {trees={{kind="adverbPhrase", expression=polite}}, joins={}}
            end
            local parsed = start <= limit and parseGroup(document, start, limit)
            if parsed and parsed.trees[1].imperative and not parsed.prefix then
                parsed.politeness = polite
                return parsed
            end
        end
    end
    return parseGroup(document, first, limit)
end

local independentRelations = {root=true, parataxis=true, conj=true, ["acl:relcl"]=true}

local function dependencySequence(document, first, limit, arcs, words)
    local attempts = 0
    local ukrainian = document.direction == "uk-en"
    for offset = 3, limit - first do
        local subject = arcs[offset]
        local predicate = subject.head
        local relation = arcs[predicate] and arcs[predicate].relation
        local auxiliary = arcs[offset + 1]
        local detached = subject.relation == "nsubj" and predicate and predicate > offset
            and independentRelations[relation]
        local nextPredicate = ukrainian and words[offset + 1].upos == "AUX" and auxiliary.head and auxiliary.head > offset
        if words[offset].upos == "PRON" and (detached or nextPredicate) then
            local split = first + offset - 1
            local preceding = document.tokens[split - 1]
            local following = document.tokens[split]
            local sourcePronoun = P.pronoun(document, split, limit, "nominative", true)
            if sourcePronoun and following.first > preceding.last + 1 and not preceding.protected
                and not preceding.key:match("^%p$") then
                attempts = attempts + 1
                local left = parseWithRelatives(document, first, split - 1)
                local right = left and parseWithRelatives(document, split, limit)
                local leftTree = left and #left.trees == 1 and left.trees[1]
                local rightTree = right and #right.trees == 1 and right.trees[1]
                local leftFrame = leftTree and leftTree.verb and lexemeFrame(leftTree.verb)
                local expectsContent = leftFrame and leftFrame.content and not leftTree.content and not leftTree.controlled
                if leftTree and not left.prefix and not leftTree.question and not leftTree.wh
                    and not expectsContent and (leftTree.kind == "clause" or leftTree.kind == "need") and rightTree
                    and not right.prefix and not rightTree.question and rightTree.kind == "clause"
                    and rightTree.subject and rightTree.subject.pronoun == sourcePronoun.pronoun then
                    local frame = rightTree.verb and rightTree.verb.lexeme.frame
                    -- In a relative clause, a gap can be the only link to its
                    -- antecedent. A separate sentence must supply every such argument.
                    local closed = rightTree.copula or frame and (frame.intransitive or frame.motion or rightTree.object
                        or rightTree.controlled or rightTree.content or rightTree.infinitive or rightTree.perception)
                    if relation == "acl:relcl" and not (rightTree.object or rightTree.prepositions or rightTree.controlled) then
                        closed = false
                    end
                    if closed then
                        return {trees={leftTree,rightTree}, joins={{sentence=true}}, dependency=true}
                    end
                end
                if attempts == 3 then break end
            end
        end
    end
end

local subjectModifiers = {det=true, amod=true, compound=true, flat=true, ["nmod:poss"]=true, nummod=true}

local function unmarkedRelatives(document, first, limit, arcs)
    if document.direction ~= "en-uk" then return nil end
    local anchors, length = {}, limit - first + 1
    for offset = 2, length do
        local subject = arcs[offset]
        local rel = arcs[subject.head]
        if subject.relation == "nsubj" and rel and rel.relation == "acl:relcl" and rel.head > 0 and rel.head < offset then
            local opening = offset
            for modifier = rel.head + 1, offset - 1 do
                local arc = arcs[modifier]
                if arc.head == offset and subjectModifiers[arc.relation] then opening = math.min(opening, modifier) end
            end
            local start = first + opening - 1
            local mark = P.key(document, start, limit)
            if mark and not P.relativeMarkers[document.direction][mark] then
                anchors[start] = first + rel.head - 1
            end
        end
    end
    if not next(anchors) then return end
    document.relativeBudget, document.relativeDepth, document.relativeAnchors = 16, 0, anchors
    local parsed = parse(document, first, limit)
    document.relativeBudget, document.relativeDepth, document.relativeAnchors = nil, nil, nil
    if parsed then parsed.dependency = true; return parsed end
end

function A.parseDependencies(document, first, limit, arcs, words)
    return unmarkedRelatives(document, first, limit, arcs)
        or dependencySequence(document, first, limit, arcs, words)
end
