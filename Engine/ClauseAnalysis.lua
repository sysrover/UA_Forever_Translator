local _, ns = ...
local A = {}
ns.Engine.ClauseAnalysis = A
local P, L = ns.Engine.Phrases, ns.Engine.Lexicon
local spatialAdjuncts = P.spatialAdjuncts

local function lexemeFrame(entry)
    return entry.lexeme.frame or {}
end

local personNoun = P.personNoun

local function deicticSubject(noun)
    local pronoun = noun and noun.pronoun
    return pronoun and (pronoun.id == "it" or pronoun.deixis ~= nil)
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
    local marker = english and P.key(document, index, limit)
    local gerund = marker and marker == frame.controlGerundPreposition
    if gerund or english and frame.controlTo then
        if gerund or marker == "to" then index = index + 1
        elseif not frame.bareInfinitive then return nil end
        if not negative and P.key(document, index, limit) == "not" then
            negative, index = true, index + 1
        end
    end
    if index <= limit then return actor, index, negative, gerund end
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
local ukCopulaAgreement = {["був"]="masculine", ["була"]="feminine", ["було"]="neuter", ["були"]="plural"}
local negativeCopula = {["isn't"]="is", ["aren't"]="are", ["wasn't"]="was", ["weren't"]="were"}
local have = {have=true, has=true, had=true}
local negativePerfect = {["haven't"]="have", ["hasn't"]="has", ["hadn't"]="had"}
local contracted = {
    idk={"i","do","know",true},
    ["i'm"]={"i","am"}, ["you're"]={"you","are"}, ["we're"]={"we","are"}, ["they're"]={"they","are"},
    ["he's"]={"he","is"}, ["she's"]={"she","is"}, ["it's"]={"it","is"}, ["that's"]={"that","is"},
    ["i've"]={"i","have"}, ["you've"]={"you","have"}, ["we've"]={"we","have"}, ["they've"]={"they","have"},
    ["i'll"]={"i","will"}, ["you'll"]={"you","will"}, ["he'll"]={"he","will"}, ["she'll"]={"she","will"},
    ["it'll"]={"it","will"}, ["we'll"]={"we","will"}, ["they'll"]={"they","will"},
}
contracted.il = contracted["i'll"]
local indefiniteContractions = {
    ["someone's"]="someone", ["somebody's"]="someone", ["anyone's"]="someone", ["anybody's"]="someone",
    ["everyone's"]="everyone", ["everybody's"]="everyone",
}
do
    -- These spellings also have an ordinary English reading. The contextual
    -- copula check in simple handles "its" separately.
    local independentWords = {were=true, well=true, ill=true, hell=true, shell=true, its=true}
    for _, expansions in ipairs({contracted, indefiniteContractions}) do
        local aliases = {}
        for spelling, expansion in pairs(expansions) do
            local plain, removed = spelling:gsub("'", "")
            if removed > 0 and not independentWords[plain] then aliases[plain] = expansion end
        end
        for spelling, expansion in pairs(aliases) do expansions[spelling] = expansion end
    end
end
local auxiliary = {
    can={modal="can"}, cannot={modal="can", negative=true}, ["can't"]={modal="can", negative=true},
    could={modal="could"}, ["couldn't"]={modal="could", negative=true},
    might={modal="might"},
    ["might've"]={modal="might", perfect=true}, ["may've"]={modal="might", perfect=true},
    must={modal="must"}, should={modal="should"}, ["shouldn't"]={modal="should", negative=true},
    ["should've"]={modal="should", perfect=true}, ["shouldn't've"]={modal="should", perfect=true, negative=true},
    would={ability="conditional"}, ["wouldn't"]={ability="conditional", negative=true},
    will={tense="future", ellipsis=true}, shall={tense="future", ellipsis=true},
    ["won't"]={tense="future", negative=true, ellipsis=true},
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
for spelling, canonical in pairs(ns.Engine.Normalize.englishNegativeAliases) do
    auxiliary[spelling] = auxiliary[canonical]
    negativeCopula[spelling] = negativeCopula[canonical]
    negativePerfect[spelling] = negativePerfect[canonical]
end

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
    local helper = not entry and auxiliary[P.key(document, index, limit)]
    if not entry and not (helper and helper.modal == "could") then return end
    local form, after = entry and entry.form or helper, index + 1
    local tense = entry and form.tense or "past"
    if preposed and tense ~= "past" then return end
    particle = P.key(document, after, limit)
    local postposed = tense == "past" and (particle == "б" or particle == "би")
    local conditional, gender = preposed or postposed, form.gender
    if preposed and postposed or helper and not conditional then return end
    if postposed then after = after + 1 end
    if tense == "past" and gender == "masculine" and P.key(document, after, limit) == "/" then
        local feminine
        if helper then
            local alternative = auxiliary[P.key(document, after + 1, limit)]
            feminine = alternative and alternative.modal == "could" and alternative.gender == "feminine"
        else feminine = abilityReading(document, after + 1, {tense="past", number="singular", gender="feminine"}) end
        local alternativeParticle = P.key(document, after + 2, limit)
        local alternativePostposed = alternativeParticle == "б" or alternativeParticle == "би"
        if feminine and postposed == alternativePostposed then
            gender, after = nil, after + (alternativePostposed and 3 or 2)
        end
    end
    if after <= limit then
        return {ability=entry and (conditional and "conditional" or tense), modal=helper and "could" or "can",
            conditionalCould=not not helper, tense=tense,
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

function A.subjectPossessiveComplementAt(document, index, limit, complement, subject, imperative)
    local owner = P.subjectPossessive(subject) or (imperative and "your")
    if not owner or P.key(document, index, limit) ~= complement.preposition
        or P.key(document, index + 1, limit) ~= owner then return nil end
    local noun = P.key(document, index + 2, limit)
    if not noun then return nil end
    if noun == complement.plural and (owner == "your" or subject and subject.number == "plural") then
        return index + 3, "plural"
    end
    if noun == complement.singular and (not subject or subject.number ~= "plural" or owner == "your") then
        return index + 3, "singular"
    end
end

function A.conditionalParticleAt(document, index, limit)
    local particle = P.key(document, index, limit)
    return particle == "б" or particle == "би"
end

function A.conditionalComplementStart(document, index, limit, form)
    if form.tense == "past" and A.conditionalParticleAt(document, index, limit) then return index + 1 end
    return index
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

local propertyDegrees = {very="very", so="so", too="too", more="more", pretty="quite", quite="quite",
    ["дуже"]="very", ["так"]="so", ["настільки"]="so", ["надто"]="too", ["більш"]="more",
    ["доволі"]="quite", ["досить"]="quite"}

local function propertyAt(document, index, limit, case, subject, sense, compatible)
    if index > limit then return nil end
    local english = document.direction == "en-uk"
    local degreeMarker, last = P.propertyDegreeAt(document, index, limit)
    local pause, pauseIndex
    if degreeMarker then
        index = last + 1
        pauseIndex = ns.Engine.Parser.ellipsisEnd(document.tokens, index, limit)
        if pauseIndex then pause, index = P.raw(document, index, pauseIndex), pauseIndex + 1 end
    end
    local degree = propertyDegrees[P.key(document, index, limit)]
    if degree then index = index + 1 end
    if index > limit then return nil end
    local forms = ns.Linguistics.propertyAdverbs
    local function allowed(candidate)
        local frame = lexemeFrame(candidate)
        return not frame.profileOnly and (not english or case ~= "adverb" or forms and forms.forms[candidate.lexeme.uk])
            and (not compatible or compatible(candidate))
    end
    local adjective, finish
    if not english and case == "adverb" then
        local key = P.key(document, index, limit)
        for _, lemma in ipairs(forms and forms.lemmas[key] or {}) do
            local candidate = L.choose(document, lemma, "adj", {case="nominative"}, sense, allowed)
            if candidate then
                if adjective and candidate.lexeme.en ~= adjective.lexeme.en then return nil end
                adjective = candidate
            end
        end
    else
        local requested = not english and {case=case, number=subject and subject.number,
            gender=subject and subject.number ~= "plural" and subject.gender or nil} or nil
        local class = not sense and P.semanticClass(subject)
        if class then
            adjective = L.choose(document, index, "adj", requested, "nounModifier", function(candidate)
                local frame = lexemeFrame(candidate)
                return frame.predicateHead and frame.headClasses and frame.headClasses[class] and allowed(candidate)
            end)
        end
        if not english and not adjective then
            adjective = L.genderPair(document, index, limit, "adj", requested, sense, allowed)
            if adjective then finish = index + 3 end
        end
        adjective = adjective or L.choose(document, index, "adj", requested, sense, allowed)
    end
    if adjective then
        return {entry=adjective, intensity=degree, degreeMarker=degreeMarker, pause=pause, pauseIndex=pauseIndex},
            finish or index + 1
    end
end

local function canBeEquipped(object)
    return P.hasTrait(object, "equipable") or P.semanticClass(object) == "equipment"
        or object.raw and ns.Engine.Markup.isLink(object.raw, "item")
end

local function objectStateAt(document, index, limit, object)
    return propertyAt(document, index, limit, "instrumental", object, "objectState", function(candidate)
        if not lexemeFrame(candidate).equipableObject then return true end
        if not object.members then return canBeEquipped(object) end
        for _, member in ipairs(object.members) do
            if not canBeEquipped(member) then return false end
        end
        return true
    end)
end

local function bareAdjunctRule(id)
    if not id then return nil end
    for _, rule in ipairs(ns.Linguistics.grammar.prepositions) do
        if rule.id == id then return rule end
    end
end

function A.matchesBareAdjunct(rule, noun)
    local class = P.semanticClass(noun)
    return class and (class == rule.requiresClass or rule.requiresClasses and rule.requiresClasses[class])
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
    elseif subject and not subject.gender and subject.raw and frame.subjectLinkGender
        and ns.Engine.Markup.isLink(subject.raw, frame.subjectLinkKind) then
        subject.gender = frame.subjectLinkGender
    end
end

function A.subjectFromCopularPredicate(document, first, limit, inverted)
    for ending = first + 1, math.min(first + 8, limit - 1) do
        local marker = P.key(document, ending, limit)
        local start = inverted and ending
        if not inverted then
            if copula[marker] or negativeCopula[marker] then
                start = ending + 1
            elseif auxiliary[marker] and P.key(document, ending + 1, limit) == "be" then
                start = ending + 2
            end
        end
        if start and P.key(document, start, limit) == "not" then start = start + 1 end
        local rules = start and L.functional(document, "prepositions", start, limit)
        for _, id in ipairs(rules or {}) do
            local rule = ns.Linguistics.grammar.prepositions[id]
            if rule.context == "predicate" and rule.subjectSense then
                local subject, after = P.coordinated(document, first, ending - 1, "nominative",
                    nil, nil, nil, rule.subjectSense)
                if subject and after == ending then return subject, after end
            end
        end
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
    local case = document.direction == "en-uk" and "accusative" or frame.contentRecipientCase or frame.recipientCase
    local recipient, after = recipientAt(document, index, limit, case)
    if recipient and (recipient.pronoun or P.relativeAnimate(recipient)) then return recipient, after end
end

local function objectRecipientAt(document, index, limit, frame, objectCase, subject)
    local english = document.direction == "en-uk"
    if frame.selfBeneficiary then
        if not english and P.key(document, index, limit) == "собі" then return {reflexive=true}, index + 1 end
        if english and subject and subject.pronoun then
            local recipient, after = P.pronoun(document, index, limit, "accusative")
            if recipient and recipient.pronoun == subject.pronoun then return {reflexive=true}, after end
        end
        return nil
    end
    if not english and frame.possessorRecipient and P.key(document, index, limit) == "собі" then
        return {reflexive=true}, index + 1
    end
    local case = english and "accusative" or frame.recipientCase
    local recipient, after = recipientAt(document, index, limit, case, not english and objectCase == "genitive")
    if recipient and frame.recipientTrait and not (personNoun(recipient) or P.hasTrait(recipient, frame.recipientTrait)) then
        return nil
    end
    return recipient, after
end

local adverbAt
local function scheduleTimeAt(document, index, limit, futureOnly)
    local marker = document.direction == "en-uk" and "for" or "на"
    if P.key(document, index, limit) ~= marker then return nil end
    return adverbAt(document, index + 1, limit, nil, function(candidate)
        return candidate.time and (not futureOnly or candidate.futureSchedule)
    end)
end

local function measureAt(document, index, limit, frame)
    local english = document.direction == "en-uk"
    local marker = english and frame.measurePreposition
    if not english then marker = "на" end
    local key = P.key(document, index, limit)
    local loose = english and frame.measureKind == "quantity" and key == "in"
    if not (marker and key == marker or loose) then return nil end
    if frame.measureKind == "quantity" then return P.changeQuantityAt(document, index + 1, limit, loose) end
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
                uk={degree.uk[1] .. " " .. adverb.uk[1]}, intensified=true, comparative=adverb.comparative,
                standardEn=adverb.standardEn and degree.en[1] .. " " .. adverb.standardEn}, after
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

local function messageAt(document, index, limit, frame)
    if not frame.messageContent then return nil end
    local marker = document.direction == "en-uk" and P.key(document, index, limit) == "with"
    local content, finish = P.noun(document, index + (marker and 1 or 0), limit, "accusative")
    if content and frame.messageContent[P.semanticClass(content)] then return content, finish end
end

local function contextualAdverb(document, index, limit, context)
    local adverb = context and adverbAt(document, index, limit, context)
    return adverb and adverb.context == context
end

local function arrivalDestination(document, index, limit, frame)
    local key = P.key(document, index, limit)
    if key == "to" or key == "into" then
        return P.preposition(document, index, limit, frame.motion, nil, frame.prepositionContext) ~= nil
    end
    if contextualAdverb(document, index, limit, frame.adverbContext) then return true end
    local tokens = document.tokens
    local marker, opening = tokens[index], tokens[index + 1]
    if not (marker and opening and (marker.key == "." or marker.key == "!") and opening.first > marker.last + 1) then
        return false
    end
    local ending = index + 1
    while ending <= #tokens and ending - index <= 8 and not tokens[ending].key:match("^[.!?;]$") do
        ending = ending + 1
    end
    if ending <= #tokens and not tokens[ending].key:match("^[.!?;]$") then return false end
    local budget = document.relativeBudget
    document.relativeBudget = nil
    local place, after = P.noun(document, index + 1, ending - 1, "nominative", true)
    document.relativeBudget = budget
    return after == ending and P.spatialContainer(place)
end

local function verb(document, index, limit, subject, base, imperative, sense, aspect, headword, previous, sourceTense, recentObject)
    if index > limit then return nil end
    local english = document.direction == "en-uk"
    local following = index + 1
    local function compatible(candidate, separatedObject)
        local f = candidate.form
        local after = english and following or A.conditionalComplementStart(document, following, limit, f)
        local frame = lexemeFrame(candidate)
        local afterManner
        if english and frame.particleSuffixExclusions
            and frame.particleSuffixExclusions[P.key(document, after, limit)] then return false end
        if english and separatedObject and frame.particleExcludesPlace
            and P.noun(document, after, limit, "locative", true, nil, true, nil, P.spatialContainer) then return false end
        if frame.commandOnly and not imperative then return false end
        if english and frame.enPastOnly and (f.verbalForm
            or f.tense ~= "past" and not (base and sourceTense == "past")) then return false end
        if english and frame.enContentMarkers and not frame.enContentMarkers[P.key(document, after, limit)] then return false end
        if english and frame.arrivalDestination and not arrivalDestination(document, after, limit, frame) then return false end
        if english and frame.enSubjectPossessiveComplement
            and not A.subjectPossessiveComplementAt(document, after, limit,
                frame.enSubjectPossessiveComplement, subject, imperative) then return false end
        if english and frame.guildRecruitment and not (subject and (subject.term and subject.term.id == "game.guild"
            or subject.raw and subject.raw:match("^<[^<>]+>$"))) then return false end
        if english and frame.requiresContent and frame.implicitSubject and subject
            and (not subject.pronoun or subject.pronoun.id ~= frame.implicitSubject) then return false end
        if frame.selfChange then
            local emphasis = P.selfChangeEmphasis(subject, english)
            if not emphasis or P.key(document, after, limit) ~= emphasis then return false end
        end
        if frame.politeDesire and not english and not hasVerbForm(document, after, limit, {mood="infinitive"}) then
            return false
        end
        if not english and frame.excludedUkObjectPreposition
            and afterObjectMarker(document, after, limit, frame.excludedUkObjectPreposition) then return false end
        if not english and frame.requiresManner then
            local at = after
            if frame.objectCase then
                local start, case = verbObjectMarker(document, at, limit, frame)
                local object, ending
                if start or not frame.objectPreposition then
                    object, ending = P.noun(document, start or at, limit, case or frame.objectCase, false, nil, true)
                end
                if object then at = ending end
            end
            afterManner = afterObjectMarker(document, at, limit, frame.ukManner)
            if not afterManner then
                local content, finish = messageAt(document, at, limit, frame)
                afterManner = content and afterObjectMarker(document, finish, limit, frame.ukManner)
                if not afterManner then return false end
            end
        end
        if frame.subjectClasses and (english or frame.reverseSubjectClasses)
            and not frame.subjectClasses[P.semanticClass(subject)] then
            local reading = subjectReading(document, subject, frame)
            local linked = frame.subjectLinkKind and subject and subject.raw
                and ns.Engine.Markup.isLink(subject.raw, frame.subjectLinkKind)
            if not linked and (not reading or not frame.subjectClasses[lexemeFrame(reading).semanticClass]) then return false end
        end
        if english and frame.sourceClasses then
            local at = after
            local modifier, following = adverbAt(document, at, limit)
            if modifier then at = following end
            if P.key(document, at, limit) == "from" then
                local origin = P.noun(document, at + 1, limit, "genitive", nil, nil, true)
                if not frame.sourceClasses[P.semanticClass(origin)] then return false end
            end
        end
        if frame.requiresRecipient then
            local learner = objectRecipientAt(document, after, limit, frame, frame.objectCase)
            if not personNoun(learner) then return false end
        end
        if english and frame.resultativeOnly and aspect ~= "resultative" then return false end
        if english and frame.progressiveOnly and aspect ~= "present" then return false end
        if english and frame.nonAgentiveSubject and (personNoun(subject) or imperative and not subject) then return false end
        if frame.contentRecipientCase and not frame.defaultContentRecipient
            and not contentRecipientAt(document, after, limit, frame) then return false end
        if not english and frame.requiresObjectMarker
            and not verbObjectMarker(document, after, limit, frame) then return false end
        if not english and frame.requiresContentMarker then
            local marker = after + (P.key(document, after, limit) == "," and 1 or 0)
            if P.key(document, marker, limit) ~= "що" then return false end
        end
        if frame.boundAdverb and not gradedAdverbAt(document, after, limit, frame.boundAdverb) then return false end
        if english and frame.rejectDirectObject and P.noun(document, after, limit, "accusative", false, nil, true)
            and not (frame.elapsedDuration == true and P.durationSpan(document, after, limit, true)) then
            return false
        end
        if not english and frame.reverseComparison
            and not P.preposition(document, after, limit, nil, nil, "comparison", nil, "comparison") then return false end
        local required = not english and requiredUkComplement(frame)
        local complementStart = after
        if required then
            local objectStart = after
            local following = afterObjectMarker(document, objectStart, limit, required)
                or frame.ukNegativeImplicitObject and afterObjectMarker(document, objectStart, limit, frame.ukNegativeImplicitObject)
            if not following then return false end
            complementStart = following
            if frame.explicitCoordinationTrait then
                local rows, marker = L.functional(document, "connectors", following, limit)
                local join = rows and ns.Linguistics.grammar.connectors[rows[1]]
                local member = join and (join.id == "and" or join.id == "or")
                    and P.noun(document, marker + 1, limit, "accusative", false, nil, true)
                if P.hasTrait(member, frame.explicitCoordinationTrait) then return false end
            end
        end
        if frame.requiresSharedSubject and not (previous and previous.subject) then return false end
        if frame.requiresBarePredicate then
            local following = afterManner or after
            local key = P.key(document, following, limit)
            if key and not key:match("^[,.;!?]$") and not L.functional(document, "connectors", following, limit)
                and not contextualAdverb(document, following, limit, frame.adverbContext) then return false end
        end
        if english and frame.subjectPronouns
            and not (subject and subject.pronoun and frame.subjectPronouns[subject.pronoun.id]) then return false end
        local context = frame.coordinatedAfter
        if context and not (previous and previous.verb and context[previous.verb.lexeme.en]) then return false end
        if frame.requiresDestination then
            local destination = P.noun(document, after, limit, "accusative", true)
            if not destination or not destination.term or destination.term.category ~= "places" then return false end
        end
        if english and frame.motionPreposition and not frame.motionPreposition[P.key(document, after, limit)] then return false end
        local typedObject = (frame.objectClasses or frame.adjunctObjectClasses or frame.objectTrait or frame.objectPronouns
            or frame.objectLinkKind
            or frame.animateObject or frame.requiresSpatialContainer)
            and (english or frame.reverseObjectClasses)
        local requiredAdjunct = english and frame.requiredAdjunct or not english and frame.reverseAdjunct
        if requiredAdjunct and frame.motion and not frame.objectCase then
            local adjunct = P.preposition(document, after, limit, true, nil, frame.prepositionContext)
            if not adjunct or not (requiredAdjunct == adjunct.rule.id
                or type(requiredAdjunct) == "table" and requiredAdjunct[adjunct.rule.id]) then return false end
            requiredAdjunct = nil
        end
        if typedObject or frame.requiresDirectObject or frame.scheduleObject or requiredAdjunct then
            local objectAt = after
            if frame.recipientCase then
                local recipient, following = objectRecipientAt(document, objectAt, limit, frame, frame.objectCase)
                if not english and not recipient and not frame.recipientMarker then return false end
                if recipient and (not english or recipient.pronoun or P.relativeAnimate(recipient)) then
                    objectAt = following
                end
            end
            local marker = english and frame.enObjectPreposition or not english and frame.objectPreposition
            local case = english and "accusative" or frame.objectCase or "accusative"
            if marker then
                local marked, governedCase = verbObjectMarker(document, objectAt, limit, frame)
                if not marked and not (english and frame.optionalEnglishObjectPreposition) then return false end
                objectAt, case = marked or objectAt, governedCase or case
            end
            local object, objectEnd = separatedObject
                or aspect and (aspect == "passive" or aspect == "progressivePassive") and subject, after
            local referent = recentObject or previous and previous.object
            if not object and referent then
                object, objectEnd = A.objectReference(document, objectAt, limit, case, referent)
            end
            if not object then
                object, objectEnd = P.noun(document, objectAt, limit, case, frame.requiresSpatialContainer,
                    nil, not frame.objectNominalArguments, frame.objectSense,
                    frame.requiresSpatialContainer and P.spatialContainer)
            end
            if not object and frame.bareCountObject then
                object, objectEnd = P.bareCount(document, objectAt, limit)
            end
            if not object and not english and frame.animateObject then
                object, objectEnd = P.pronoun(document, objectAt, limit, case, true)
            end
            if frame.requiresDirectObject and not object then return false end
            if frame.excludesPersonObject and P.personNoun(object) then return false end
            if frame.ellipticObjectManner and not object then
                local following = P.key(document, objectAt, limit)
                if following and not following:match("^[,.;!?]$")
                    and not L.functional(document, "adverbs", objectAt, limit)
                    and not L.functional(document, "connectors", objectAt, limit) then return false end
            end
            local class = P.semanticClass(object)
            if not class and object and object.raw and ns.Engine.Markup.isLink(object.raw, "item") then class = "equipment" end
            local pronoun = object and object.pronoun
            local link = frame.objectLinkKind and object and object.raw
                and ns.Engine.Markup.isLink(object.raw, frame.objectLinkKind)
            local contextualClass = frame.adjunctObjectClasses and (frame.adjunctObjectClasses[class] or link)
            local required = requiredAdjunct or frame.reverseAdjunct
            local hasAdjunct
            if contextualClass or requiredAdjunct then
                local adjunct = object and P.preposition(document, objectEnd, limit, frame.motion,
                    frame.displacesObject, frame.prepositionContext)
                hasAdjunct = adjunct and (required == adjunct.rule.id or type(required) == "table" and required[adjunct.rule.id])
                    and (english or not frame.reverseAdjunctClass or P.semanticClass(adjunct.object) == frame.reverseAdjunctClass)
                if requiredAdjunct and not hasAdjunct then return false end
            end
            local coordinatedObject = not object and frame.ellipticCoordinateObject and document.coordinateObject
                and objectAt > limit and frame.objectClasses[document.coordinateObject]
            if typedObject and not (frame.optionalTypedObject and not object or coordinatedObject
                or frame.objectClasses and frame.objectClasses[class]
                or link and not frame.adjunctObjectClasses
                or contextualClass and hasAdjunct
                or frame.objectTrait and P.hasTrait(object, frame.objectTrait)
                or frame.objectPronouns and pronoun and frame.objectPronouns[pronoun.id]
                or frame.animateObject and personNoun(object)
                or frame.requiresSpatialContainer and P.spatialContainer(object)) then return false end
            if frame.scheduleObject and (not object or not scheduleTimeAt(document, objectEnd, limit, true)) then
                return false
            end
            if frame.measurePreposition and not frame.measureOptional
                and not measureAt(document, objectEnd, limit, frame) then return false end
        end
        if frame.propertyCase then
            if frame.subjectAnimacy and subject then
                local pronoun = subject.pronoun
                local animacy = subject.animacy
                if pronoun then animacy = (pronoun.inanimate or pronoun.id == "it") and "inanimate" or "animate" end
                if animacy and animacy ~= frame.subjectAnimacy then return false end
            end
            local property, propertyEnd = propertyAt(document, after, limit, frame.propertyCase, subject)
            if property and frame.stateChange and propertyEnd <= limit
                and P.noun(document, propertyEnd, limit, english and "accusative" or frame.propertyCase,
                    false, nil, true) then return false end
            if not property
                and not (frame.propertyComparison
                    and P.preposition(document, after, limit, nil, nil, frame.prepositionContext, nil, "comparison")) then
                return false
            end
        end
        if not english and frame.enLexicalNegative then
            local preceding = P.key(document, index - 1, limit)
            local helper = auxiliary[preceding]
            if preceding ~= "не" and not (helper and helper.tense == "future"
                and P.key(document, index - 2, limit) == "не") then return false end
        end
        if frame.requiredTopic then
            local topic = P.preposition(document, complementStart, limit)
            if not topic or topic.rule.id ~= frame.requiredTopic then return false end
        end
        if frame.gerundComplement then
            local infinitive = english and frame.alternateInfinitive and P.key(document, after, limit) == "to"
            local start = complementStart + (infinitive and 1 or 0)
            if not english and frame.ukInfinitivePattern then
                start = afterObjectMarker(document, start, limit, frame.ukInfinitivePattern)
                if not start then return false end
            end
            local form = not english and {mood="infinitive"}
                or infinitive and {mood="base"} or {verbalForm="participle", tense="present"}
            if not hasVerbForm(document, start, limit, form) then return false end
        end
        if frame.requiredControl and (english or frame.controlVerbs) then
            local actor, at, _, gerund = controlledStart(document, after, limit, frame)
            if not actor then return false end
            local form = gerund and {verbalForm="participle", tense="present"}
                or {mood=english and "base" or "infinitive"}
            if frame.controlVerbs then
                if not L.choose(document, at, "verb", form, nil, function(entry)
                    return frame.controlVerbs[entry.lexeme.en]
                end) then return false end
            elseif not hasVerbForm(document, at, limit, form) then return false end
        end
        if aspect then
            if aspect == "simplePast" then return f.tense == "past" and not (f.verbalForm or f.mood) end
            if f.verbalForm ~= "participle" then return false end
            if aspect == "resultative" then
                if f.tense ~= "past" or not frame.resultative then return false end
                if not frame.resultativeActor then return true end
                return (personNoun(subject) or P.hasTrait(subject, "membershipGroup"))
                    and not (P.key(document, after, limit) == "by"
                        and P.preposition(document, after, limit, nil, nil, "passiveAgent", nil, "passiveAgent"))
            end
            if aspect == "passive" then return f.tense == "past" and (frame.passiveUk or frame.passiveVoice) end
            if aspect == "progressivePassive" then
                return f.tense == "past" and (frame.passiveVoice or frame.passiveUk)
                    and candidate.head.aspect == "imperfective"
            end
            return f.tense == aspect
        end
        if f.verbalForm then return false end
        if english then
            if base or imperative then return f.mood == "base" end
            if f.mood == "base" then
                return frame.invariantPresent or not subject or subject.person ~= 3 or subject.number == "plural"
                    or P.semanticClass(subject) == "faction"
                    or frame.invariantPresentAliases and frame.invariantPresentAliases[P.key(document, index, limit)]
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
        if f.mood == "impersonal" then return not (subject or base or imperative) end
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
            following = finish
            local preposition = L.functional(document, "prepositions", index + 1, finish - 1)
            local selected = L.choose(document, phrase, "verb", nil, sense, function(candidate)
                local verbFrame = lexemeFrame(candidate)
                if not verbFrame.lexicalPhrase or not compatible(candidate) then return false end
                if preposition and verbFrame.particle then
                    local object = P.noun(document, following, limit, "accusative")
                    local frame = object and object.entry and lexemeFrame(object.entry)
                    if P.spatialContainer(object) or frame and frame.spatialPart then return false end
                end
                return true
            end)
            if selected then return selected, following end
            following = index + 1
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
                        following = position + 1
                        local selected = L.choose(document, head .. " " .. particle, "verb", nil, sense, function(candidate)
                            return lexemeFrame(candidate).particle == particle and compatible(candidate, object)
                        end)
                        if selected then
                            -- Keep the object on this occurrence, outside the shared lexeme cache.
                            return {lexeme=selected.lexeme, head=selected.head, form=selected.form, id=selected.id,
                                separatedObject=object}, following
                        end
                    end
                end
            end
            following = index + 1
        end
    end
    if not english and not headword then
        local offset = P.key(document, index + 1, limit) == "/" and 2
            or A.conditionalParticleAt(document, index + 1, limit)
                and P.key(document, index + 2, limit) == "/"
                and A.conditionalParticleAt(document, index + 4, limit) and 3
        if offset then
            following = index + offset + 1
            local paired = L.genderPair(document, index, limit, "verb", {tense="past", number="singular"},
                sense, compatible, index + offset)
            if paired then return paired, following end
            following = index + 1
        end
    end
    if not english and not headword then
        for _, candidate in ipairs(L.at(document, index)) do
            local frame = lexemeFrame(candidate)
            if requiredUkComplement(frame) or frame.objectDomainByAdjunctClass then
                local scoped = L.choose(document, index, "verb", nil, sense, function(reading)
                    local scope = lexemeFrame(reading)
                    local complement = A.conditionalComplementStart(document, following, limit, reading.form)
                    return compatible(reading)
                        and (requiredUkComplement(scope) or objectDomain(document, complement, limit, scope))
                end)
                if scoped then return scoped, following end
                break
            end
        end
    end
    local selected, reason = L.choose(document, headword or index, "verb", nil, sense, compatible)
    if not english and not headword and reason == "ambiguous" and following <= limit then
        selected = L.choose(document, index, "verb", nil, sense, function(candidate)
            local frame = lexemeFrame(candidate)
            if not frame.reverseAmount or not compatible(candidate) then return false end
            local start = A.conditionalComplementStart(document, following, limit, candidate.form)
            return P.amount(document, start, limit, frame.objectCase, frame.objectSense) ~= nil
        end)
    end
    if selected then return selected, following end
    if reason == "ambiguous" and not (english or headword or sense or base or imperative or aspect)
        and personNoun(subject) then
        local grammar = ns.Linguistics.grammar
        local readings = grammar.personalPredicateVerbs
        if not readings then return nil end
        local cue = P.key(document, following, limit)
        local modifier = adverbAt(document, following, limit)
        local bare = not cue or cue:match("^[,.;!?]$") or L.functional(document, "connectors", following, limit)
            or modifier and modifier.time
        local candidate = L.choose(document, index, "verb", nil, nil, function(entry)
            local row = readings[entry.lexeme.uk]
            local rule = row and grammar.adverbs[row]
            return rule and entry.lexeme.en == "be " .. rule.en[1] and compatible(entry)
                and (bare or P.preposition(document, following, limit, nil, nil, rule.prepositionContext, nil, "predicateTopic"))
        end)
        if candidate then
            return {lexeme=candidate.lexeme, head=candidate.head, form=candidate.form, id=candidate.id,
                personalPredicate=grammar.adverbs[readings[candidate.lexeme.uk]]}, following
        end
    end
end

adverbAt = function(document, first, limit, context, eligible)
    local rows, last = L.functional(document, "adverbs", first, limit)
    if not rows or last > limit then return nil end
    local fallback
    for _, row in ipairs(rows) do
        local adverb = ns.Linguistics.grammar.adverbs[row]
        local excluded = document.direction == "en-uk" and adverb.enSuffixExclusions
        local endOnly = document.direction == "en-uk" and adverb.enEndOnly
        local following = (excluded or endOnly) and P.key(document, last + 1, limit)
        if not (excluded and excluded[following])
            and not (endOnly and endOnly[P.key(document, first, limit)] and following and not following:match("^[,.;!?]$"))
            and (not eligible or eligible(adverb)) then
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
    ["how's"]={kind="manner", role="manner", copula="is"}, ["how'd"]={kind="manner", role="manner", auxiliary="did"},
}
englishQuestions.whats = englishQuestions["what's"]
do
    local spellings = {}
    for _, forms in ipairs({contracted, indefiniteContractions, auxiliary, negativeCopula, negativePerfect, englishQuestions}) do
        for key in pairs(forms) do
            if key:match("^[a-z]+'[a-z][a-z]?$") then spellings[key] = true end
        end
    end
    A.englishContractions = spellings
end
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
    for marker = first, math.min(first + 6, limit - 1) do
        local kind = needInfinitiveMarkers[P.key(document, marker, limit)]
        if kind then
            local last = marker - 1
            local negative = P.key(document, last, limit) == "не"
            if negative then last = last - 1 end
            local before = obligationTime[P.key(document, last, limit)]
            if before then last = last - 1 end
            if not negative and P.key(document, last, limit) == "не" then negative, last = true, last - 1 end
            local modifier = kind == "should" and last >= first and adverbAt(document, last, last, nil, function(candidate)
                return candidate.predicateModifier
            end)
            if modifier then last = last - 1 end
            local after = obligationTime[P.key(document, marker + 1, limit)]
            if before and after then return nil end
            local tense = before or after or "present"
            if kind == "should" and tense == "future" then return nil end
            local subject, finish
            if last >= first then
                subject, finish = recipientAt(document, first, last, "dative", true)
                if not subject or finish ~= last + 1 then return nil end
            end
            return subject, marker, marker + (after and 2 or 1), tense, negative, kind, modifier
        end
    end
end

local determinantCases = {"accusative", "genitive", "dative", "instrumental"}
local englishDeterminerCases = {"accusative"}
function A.embeddedAuxiliaryComplement(document, first, limit)
    local helper = auxiliary[P.key(document, first, limit)]
    if not helper or not (helper.support or helper.modal or helper.ability == "conditional"
        or helper.tense == "future") then return nil end
    local index = first + 1
    if P.key(document, index, limit) == "not" then index = index + 1 end
    local _, after = adverbAt(document, index, limit)
    return after or index
end

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
                    local embedded = english and indirect and A.embeddedAuxiliaryComplement(document, at, limit)
                    local predicate = verb(document, embedded or abilityAt or at, limit, subject,
                        not not (helper or embedded or abilityAt))
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
    local kind, quantified, indirectPredicate = spec.kind
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
    local embeddedSubject, embeddedAfter
    local bareIndirect = indirect and kind == "thing" and (english and firstWord == "what" or not english and firstWord == "чим")
    if bareIndirect then
        embeddedSubject, embeddedAfter = P.coordinated(document, index, limit, "nominative")
        if embeddedSubject then
            local linking = P.key(document, embeddedAfter, limit)
            local at = embeddedAfter + (linking == "не" and 1 or 0)
            local tail = at + 1
            local ending = P.key(document, tail, limit)
            if ending == "not" then tail = tail + 1; ending = P.key(document, tail, limit) end
            linking = P.key(document, at, limit)
            if (copula[linking] or negativeCopula[linking]) and (not ending or ending == ","
                or L.functional(document, "connectors", tail, limit)) then
                role, indirectPredicate = "predicate", true
            end
        end
    end
    if not role and not english and obligationHead(document, index, limit) then role = "object" end
    if not role then
        local copular = english and (spec.copula or negativeCopula[head] or copula[head] and head)
        local aux = english and auxiliary[head]
        if aux or copular or not english or indirect then
            local skipAux = (aux or copular) and not spec.copula
            local subject, after = embeddedSubject, embeddedAfter
            if skipAux or not bareIndirect then
                subject, after = P.coordinated(document, index + (skipAux and 1 or 0), limit, "nominative")
            end
            if subject then
                local nextKey = P.key(document, after, limit)
                if nextKey == "not" or nextKey == "не" then after = after + 1 end
                local _, adverbEnd = adverbAt(document, after, limit)
                local atVerb = adverbEnd or after
                local embedded = english and indirect and A.embeddedAuxiliaryComplement(document, atVerb, limit)
                local aspect = copular and "present" or nil
                if verb(document, embedded or atVerb, limit, subject, not not (aux or embedded), false, nil, aspect)
                    or not english and (auxiliary[P.key(document, atVerb, limit)] or inflectedAbility(document, atVerb, limit)) then
                    role = "object"
                elseif copular and spec.kind == "thing" then
                    local frame = subject.entry and lexemeFrame(subject.entry)
                    if after > limit or frame and frame.nominalInfinitive and nextKey == "to"
                        and hasVerbForm(document, after + 1, limit, {mood="base"}) then role = "predicate" end
                end
            end
        end
    end
    return {kind=kind, noun=quantified, role=role or "subject", case=spec.case, another=another, copula=spec.copula,
        auxiliary=spec.auxiliary,
        definite=spec.definite, gender=spec.gender, indirectPredicate=indirectPredicate}, index
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

local function recurringEvent(tree)
    if tree.leadingAdverb and tree.leadingAdverb.recurring or tree.sentenceAdverb and tree.sentenceAdverb.recurring then
        return true
    end
    for _, modifier in ipairs(tree.adverbs or {}) do
        if modifier.recurring then return true end
    end
end

function A.elapsedFromClause(tree)
    return tree.aspect == "perfect" or tree.perfectProgressive or tree.perfectState
        or tree.durationSpan and tree.durationSpan.ongoing
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
    local grammar = ns.Linguistics.grammar
    local choices, last = L.functional(document, "connectors", index, limit)
    local key = P.key(document, index, limit)
    local rule = choices and grammar.connectors[choices[1]]
    local alias
    if not rule then
        alias = document.direction == "en-uk" and grammar.englishClauseConnectorAliases
            and grammar.englishClauseConnectorAliases[key]
        if not alias then return nil end
        rule, last = grammar.connectors[alias], index
    elseif not (rule.alsoPreposition and rule.alsoPreposition[key]) then
        return rule, last
    end
    local opening = P.key(document, last + 1, limit)
    if contracted[opening] or indefiniteContractions[opening] then return rule, last end
    if alias and (auxiliary[opening] or verb(document, last + 1, limit, nil, false)) then
        return rule, last
    end
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

function A.pronounReference(document, referent)
    if not referent then return nil end
    local quest = referent.raw and ns.Engine.Markup.isLink(referent.raw, "quest")
    local animacy = referent.animacy or quest and "inanimate"
    local count = tonumber(referent.quantity)
    local plural = count and count ~= 1 or referent.number == "plural" or referent.few or referent.many
    if not animacy and not plural then return nil end
    local gender = referent.gender or quest and "neuter"
    local gendered = gender == "feminine" and "she" or gender == "masculine" and "he" or gender == "neuter" and "it"
    local english = document.direction == "en-uk"
    local source = plural and "they" or english and animacy == "inanimate" and "it" or gendered
    if not source then return nil end
    local target = source
    if not plural and animacy == "inanimate" then
        target = english and (gendered or "it") or "it"
    end
    return source, target ~= source and personalSubject(target).pronoun, P.semanticClass(referent) or quest and "objective"
end

function A.objectReference(document, first, limit, case, referent)
    if (case ~= "accusative" and case ~= "genitive") or first > limit then return nil end
    local source, target, class = A.pronounReference(document, referent)
    if not source then return nil end
    local pronoun, after = P.pronoun(document, first, first, case, nil, nil, source)
    if not pronoun or not (boundary(document, after, limit) or L.functional(document, "prepositions", after, limit)
        or adverbAt(document, after, limit)) then return nil end
    pronoun.targetPronoun, pronoun.referenceClass = target or nil, class
    return pronoun, after
end

local function purposeStart(document, index, limit, bare)
    local key = P.key(document, index, limit)
    if document.direction == "en-uk" then
        if key == "in" and P.key(document, index + 1, limit) == "order" then
            index = index + 2
        elseif not bare then return end
        local negative = P.key(document, index, limit) == "not"
        if negative then index = index + 1 end
        if P.key(document, index, limit) == "to" then
            if not negative and P.key(document, index + 1, limit) == "not" then return index + 2, true end
            return index + 1, negative
        end
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
function A.typedPredicateSubject(document, first, limit, invertedAux)
    local english = document.direction == "en-uk"
    for _, sense in ipairs(ns.Linguistics.grammar.subjectFallbackSenses) do
        local subject, after = P.coordinated(document, first, limit, "nominative", nil, nil, nil, sense)
        if subject and after <= limit then
            local helper = english and (invertedAux or auxiliary[P.key(document, after, limit)])
            local predicate = after + (helper and not invertedAux and 1 or 0)
            if P.key(document, predicate, limit) == (english and "not" or "не") then predicate = predicate + 1 end
            local entry = verb(document, predicate, limit, subject, helper ~= nil and helper ~= false)
            if entry and lexemeFrame(entry).subjectSense == sense then return subject, after end
        end
    end
end

function A.conditionalDesireAt(document, first, limit, subject)
    local entry = L.choose(document, first, "verb", {mood="base"}, "conditionalDesire")
    if not entry then return false end
    local start = first + 1
    if subject and subject.pronoun and lexemeFrame(entry).selfBeneficiary then
        local recipient, after = P.pronoun(document, start, limit, "accusative")
        if recipient and recipient.pronoun == subject.pronoun then start = after end
    end
    local marker = P.key(document, start, limit)
    return marker == "to" or marker == "a" or marker == "an" or marker == "some"
end

local function coordinatedObject(document, first, limit, case, locationOnly, enumeration, sense, headFilter, purposeHead,
    eventSeries, strandedPartner)
    local startsPredicate
    if document.direction == "en-uk" then
        local dependencies, anchoredDependencies, tags
        startsPredicate = function(index)
            if eventSeries then
                local action = verb(document, index, limit, nil, false, false, nil, "present")
                if action and lexemeFrame(action).eventNominal then return true end
            end
            local candidate, after = verb(document, index, limit, nil, true)
            if not candidate then return false end
            if strandedPartner and after == limit and lexemeFrame(candidate).intransitive then return true end
            if after <= limit then
                local object = P.noun(document, after, limit, "accusative")
                if object and (object.article or object.pronoun or object.possessor or object.quantity)
                    or P.preposition(document, after, limit, lexemeFrame(candidate).motion) then return true end
            end
            if not purposeHead then return false end
            if dependencies == nil then
                dependencies, tags = ns.Engine.UDPipe.analyzeDocumentWithTags(document, purposeHead, limit)
                dependencies = dependencies or false
            end
            local offset = index - purposeHead + 1
            local tag = tags and tags[offset]
            if not tag or tag.upos ~= "VERB" then return false end
            local arcs = dependencies
            if tags[1].upos ~= "VERB" then
                if anchoredDependencies == nil then
                    anchoredDependencies = ns.Engine.UDPipe.analyzeDocument(document, purposeHead, limit,
                        nil, nil, {[purposeHead]="VERB"}) or false
                end
                arcs = anchoredDependencies
            end
            local arc = arcs and arcs[offset]
            return arc and arc.relation == "conj" and arc.head == 1
        end
    end
    local object, after = P.coordinated(document, first, limit, case, startsPredicate, locationOnly, enumeration, sense, headFilter)
    if object and not enumeration and P.key(document, after, limit) == "," then
        -- A closing conjunction and complete nominal coverage keep the list in the object's case.
        local list, finish = P.coordinated(document, first, limit, case, startsPredicate, locationOnly, true, sense, headFilter)
        local lastJoin = list and list.joins and list.joins[#list.joins]
        if lastJoin and not lastJoin.comma and finish > limit then return list, finish end
    end
    return object, after
end

local complements, infinitiveSeries

function A.recruitmentRoles(noun)
    if not noun then return false end
    for _, member in ipairs(noun.members or {noun}) do
        local category = member.term and member.term.category
        if category ~= "roles" and category ~= "classes" then return false end
    end
    return true
end

function A.recruitmentDestinationObject(document, first, limit, case)
    local english = document.direction == "en-uk"
    -- The catalogue indexes at most twelve tokens per term.
    for start = math.max(first + 1, limit - 11), limit do
        for _, span in ipairs(document.spans[start] or {}) do
            if span.last == limit and span.term.category == "places"
                and span.term.features and span.term.features.clearableInstance then
                local marker = P.key(document, start - 1, limit)
                local explicit = marker == (english and "for" or "на")
                if english or explicit then
                    local lastRole = start - 1 - ((explicit or marker == ",") and 1 or 0)
                    if lastRole >= first then
                        local rule = bareAdjunctRule("for-instance-recruitment")
                        if not rule then return nil end
                        local place, after = P.noun(document, start, limit, rule.case, true, nil, true, rule.objectSense)
                        if place and place.term and after > limit and P.hasTrait(place, "clearableInstance") then
                            local list, finish = coordinatedObject(document, first, lastRole, case)
                            if finish == lastRole + 1 and A.recruitmentRoles(list) then
                                return list, after, {rule=rule, object=place, case=rule.case}
                            end
                        end
                    end
                end
                break
            end
        end
    end
end

function A.rosterSearch(document, subject, index, limit, depth)
    local key = P.key(document, index, limit)
    if not key or not key:match("ing$") or not A.recruitmentRoles(subject) then return nil end
    local counted
    for _, member in ipairs(subject.members or {subject}) do
        if member.quantity then counted = true; break end
    end
    if not counted then return nil end
    local action, after = verb(document, index, limit, subject, false, false, nil, "present")
    if not action or not lexemeFrame(action).recruitmentSearch then return nil end
    local request = {kind="clause", subject=subject, verb=action, verbIndex=index, tense="present", aspect="continuous"}
    local finish = complements(document, request, after, limit, depth)
    local destination = request.prepositions and request.prepositions[1]
    if finish == limit + 1 and destination and destination.rule.id == "for-instance-recruitment" then
        return request, finish
    end
end

function A.locativeSource(document, first, limit, depth)
    if depth >= 3 then return nil end
    local cue, start = adverbAt(document, first, limit, "locativeSource", function(candidate)
        return candidate.locativeSource
    end)
    if not cue or start > limit then return nil end
    local clause, finish = simple(document, start, limit, nil, depth + 1, true, nil, false)
    if not clause or clause.kind ~= "clause" or clause.question or clause.imperative or not boundary(document, finish, limit) then
        return nil
    end
    local form = clause.verb and clause.verb.form
    if not clause.subject and (document.direction == "en-uk" or not (form and form.person)) then return nil end
    if not (clause.verb or clause.copula) then return nil end
    if document.direction == "uk-en" and clause.verb and not (clause.aspect or clause.modal or recurringEvent(clause))
        and (clause.tense == "present" or clause.tense == "past") and lexemeFrame(clause.verb).ongoingLocativeState then
        clause.aspect = "continuous"
    end
    return {clause=clause, cue=cue}, finish
end

local function prepositionContext(tree, frame)
    local objectClass = P.semanticClass(tree.object)
    local personalPredicate = tree.verb and tree.verb.personalPredicate
    local context = tree.kind == "benefit" and objectClass
        or tree.object and tree.object.sufficient and "supply"
        or frame.objectPrepositionContexts and frame.objectPrepositionContexts[objectClass]
        or frame.prepositionContext
        or personalPredicate and personalPredicate.prepositionContext
        or frame.recruitmentSearch and tree.implicitSubject and personNoun(tree.object) and "recruitmentPurpose"
        or frame.recruitedSubject and personNoun(tree.object) and "activityInvitation"
    return context, frame.durationBoundary and "duration"
end
local controlledTemporal = {
    before={en={"before"}, uk={"перш ніж"}, temporal=true, prospectiveEvent=true, reverseAttachment=true},
    after={en={"after"}, uk={"після того як"}, temporal=true},
}

local function controlledTimeClause(document, first, limit, main, depth)
    local passive = main.aspect == "passive"
    if passive and (not main.modal or main.passiveAgent) then return nil end
    local subject = main.subject or main.imperative
        and personalSubject(main.imperativeNumber == "plural" and "you_plural" or "you")
    if not subject then return nil end
    local action, after = verb(document, first, limit, subject, false, false, nil, "present")
    if not action then return nil end
    local dependent = {kind="clause", subject=subject, inherited=true, tense=main.tense == "past" and "past" or "present",
        temporalDependent=true, verb=action}
    local finish = complements(document, dependent, after, limit, depth + 1)
    if finish then
        dependent.temporalRecurring = recurringEvent(main) or recurringEvent(dependent)
        if passive then
            local id = subject.number == "plural" and "they"
                or subject.gender == "feminine" and "she" or subject.gender == "masculine" and "he"
            dependent.subject = subject.pronoun and subject or id and personalSubject(id) or subject
            dependent.inherited = nil
            if not dependent.temporalRecurring then A.prospectiveEvent(dependent) end
        end
        return dependent, finish
    end
end
local function nominalPartnerAt(document, first, limit)
    local rows, last = L.functional(document, "prepositions", first, limit)
    for _, row in ipairs(rows or {}) do
        local rule = ns.Linguistics.grammar.prepositions[row]
        if rule.nominalPartner then return rule, last + 1 end
    end
end

local function nominalPartnerAction(document, noun, first, limit, depth, english)
    local head = noun.members and noun.members[#noun.members] or noun
    if not (personNoun(head) or P.hasTrait(head, "nominalPartnership")) then return end
    local start, partner
    if english then
        if P.key(document, first, limit) ~= "to" then return end
        start = first + 1
    else
        local marker = first + (P.key(document, first, limit) == "," and 1 or 0)
        local after
        partner, after = nominalPartnerAt(document, marker, limit)
        if not partner or P.key(document, after, limit) ~= P.relativePronoun(noun, partner.case) then return end
        start = after + 1
        if P.key(document, start, limit) == "можна" then start = start + 1 end
    end
    local entry, after = verb(document, start, limit, nil, true)
    if not entry then return end
    local action = {verb=entry, verbIndex=start, tense="infinitive",
        strandedPartner=english and nominalPartnerAt(document, limit, limit) ~= nil}
    local finish = complements(document, action, after, limit, depth + 1)
    if not finish then return end
    finish = infinitiveSeries(document, action, finish, limit, depth + 1, false, true)
    if english then partner, finish = nominalPartnerAt(document, finish, limit) end
    if partner and boundary(document, finish, limit) then
        action.nominalPartner = partner
        return action, finish
    end
end

local function nominalInfinitive(document, noun, first, limit, depth)
    if depth >= 3 then return nil end
    local head = noun.members and noun.members[#noun.members] or noun
    local frame = head.entry and head.entry.lexeme.frame
    local english = document.direction == "en-uk"
    local partnership, ending = nominalPartnerAction(document, noun, first, limit, depth, english)
    if partnership then return partnership, ending end
    if not frame or not frame.nominalInfinitive
        or english and P.key(document, first, limit) ~= "to" then return nil end
    local start = first + (english and 1 or 0)
    if not english and frame.nominalLocation then
        if P.key(document, start, limit) == "," then start = start + 1 end
        if P.key(document, start, limit) ~= "де" or P.key(document, start + 1, limit) ~= "можна" then return nil end
        start = start + 2
    elseif not english and frame.nominalPurpose then
        if P.key(document, start, limit) == "," then start = start + 1 end
        if P.key(document, start, limit) ~= "щоб" then return nil end
        start = start + 1
    end
    local entry, after = verb(document, start, limit, nil, true)
    if not entry then return nil end
    local action = {verb=entry, tense="infinitive", purposeClause=true,
        nominalPurpose=frame.nominalPurpose, nominalLocation=frame.nominalLocation}
    local finish = complements(document, action, after, limit, depth + 1)
    if finish then return action, finish end
end

local function attachNominalAction(document, noun, first, limit, depth)
    local action, finish = nominalInfinitive(document, noun, first, limit, depth)
    if action then noun.nominalAction = action; return finish end
    return first
end

infinitiveSeries = function(document, head, index, limit, depth, participle, allowTo)
    local english = document.direction == "en-uk"
    local previous = head
    for _ = 1, 3 do
        local comma = P.key(document, index, limit) == ","
        local start = index + (comma and 1 or 0)
        local selected, last = L.functional(document, "connectors", start, limit)
        local join = selected and ns.Linguistics.grammar.connectors[selected[1]]
        if join and (join.id == "and" or join.id == "or") then start = last + 1
        elseif comma and not join then join = nil
        else break end
        local negativeKey = english and "not" or "не"
        local negative = P.key(document, start, limit) == negativeKey
        if negative then start = start + 1 end
        local explicitTo = english and allowTo and P.key(document, start, limit) == "to"
        if explicitTo then start = start + 1 end
        if not negative and P.key(document, start, limit) == negativeKey then
            negative, start = true, start + 1
        end
        local adverb, afterAdverb = adverbAt(document, start, limit)
        local at = afterAdverb or start
        local entry, following = verb(document, at, limit, nil, not participle, false, nil, participle and "present",
            nil, nil, nil, previous.object)
        if not entry then break end
        local action = {verb=entry, verbIndex=at, tense="infinitive", negative=negative, leadingAdverb=adverb,
            purposeClause=head.purposeClause, intendedEvent=head.intendedEvent, gerund=head.gerund,
            eventSubjectPrefix=head.eventSubjectPrefix, strandedPartner=head.strandedPartner,
            previousObject=previous.object}
        local finish = complements(document, action, following, limit, depth)
        if not finish then break end
        action.previousObject, previous = nil, action
        head.series = head.series or {}
        head.series[#head.series + 1] = {action=action, join=join, explicitTo=explicitTo}
        index = finish
    end
    return index
end

function A.markPurposeAspect(action, openSeries)
    local entry = action.verb
    if not lexemeFrame(entry).purposeLemma or entry.head.aspect == "perfective" then return end
    local object = action.object
    local genericPlural = object and object.number == "plural" and (object.entry or object.term)
        and not (object.article or object.quantity or object.possessor or object.demonstrative or object.all
            or object.few or object.many or object.some or object.more or object.sufficient or object.distributive)
    action.ongoingPurpose = recurringEvent(action) or action.durationSpan ~= nil
        or openSeries and genericPlural and not (action.delay or explicitTime(action) or hasFutureSchedule(action))
end

local function purposeAt(document, index, limit, depth, bare, bareAction, forActivity)
    if depth >= 3 then return nil end
    local start, negative = purposeStart(document, index, limit, bare)
    local gerund = not start and forActivity and document.direction == "en-uk"
        and P.key(document, index, limit) == "for"
    if not start then
        if gerund then
            negative = P.key(document, index + 1, limit) == "not"
            start = index + (negative and 2 or 1)
        elseif bareAction then start = index
        else return nil end
    end
    if not negative and not gerund then
        local activity, finish = smallActivity(document, start, limit)
        if activity then return activity, finish end
    end
    local modifier, modifiedStart = adverbAt(document, start, limit)
    local at = modifiedStart or start
    local predicateVerb, after = verb(document, at, limit, nil, not gerund, false, nil, gerund and "present")
    if not predicateVerb and modifier then
        modifier, at = nil, start
        predicateVerb, after = verb(document, at, limit, nil, not gerund, false, nil, gerund and "present")
    end
    if not predicateVerb then return nil end
    local purpose = {verb=predicateVerb, verbIndex=at, tense="infinitive", negative=negative, leadingAdverb=modifier,
        purposeClause=true, gerundMarker=gerund and index or nil}
    local finish = complements(document, purpose, after, limit, depth + 1)
    if finish then
        local frame = lexemeFrame(predicateVerb)
        if gerund and not negative and frame.objectCase and not (purpose.object or purpose.infinitive
            or purpose.controlled or frame.intransitive or frame.motion) then return nil end
        finish = infinitiveSeries(document, purpose, finish, limit, depth + 1, gerund, not gerund)
        if document.direction == "en-uk" then
            local series = purpose.series
            local openSeries = frame.openEndedActivity
            for _, item in ipairs(series or {}) do
                if item.join and item.join.id == "or" then openSeries = false; break end
                openSeries = openSeries or lexemeFrame(item.action.verb).openEndedActivity
            end
            A.markPurposeAspect(purpose, series and openSeries)
            for _, item in ipairs(series or {}) do A.markPurposeAspect(item.action, openSeries) end
        end
        if not (bareAction or gerund) or boundary(document, finish, limit) then return purpose, finish end
    end
end

local function needPurposeObject(object)
    return object and (not object.pronoun or object.pronoun.id == "someone")
end

do
local function suitabilityMarker(document, index, limit)
    local key = P.key(document, index, limit)
    if document.direction == "en-uk" then return key == "for" and index or nil end
    if key == "для" or key == "щоб" then return index end
    if key == "," and P.key(document, index + 1, limit) == "щоб" then return index + 1 end
end

function A.suitabilityRating(document, first, limit)
    local marker = first + (document.direction == "en-uk" and 1 or 2)
    if marker < limit and suitabilityMarker(document, marker, limit) then
        local rating, after = adverbAt(document, first, limit, "suitability")
        if rating and rating.suitability then return rating, after end
    end
end

function A.suitabilityAt(document, tree, rule, first, limit, depth)
    local english = document.direction == "en-uk"
    local subject = tree.subject
    local predicate = ns.Linguistics.grammar.suitabilityVerb
    local function fitting(entry)
        if entry.lexeme.uk ~= predicate.uk or entry.lexeme.en ~= predicate.en then return false end
        local form = entry.form
        return english or form.tense and not (form.verbalForm or form.mood == "infinitive")
            and (not form.person or form.person == subject.person)
            and (not form.number or form.number == subject.number or agreeingSubjectReading(document, subject, form))
            and (not form.gender or not subject.gender or form.gender == subject.gender)
    end
    local index = first + (english and 0 or 1)
    if not suitabilityMarker(document, index, limit) then return nil end
    local fit = L.choose(document, english and predicate.en or first, "verb", english and {mood="base"} or nil, nil, fitting)
    if not fit then return nil end
    local uses, unresolved, known, join = {}, nil, false, nil
    for _ = 1, 4 do
        local marker = suitabilityMarker(document, index, limit)
        if not marker or marker == limit then return nil end
        local stop, nextJoin = limit + 1
        for at = marker + 1, limit do
            local key = P.key(document, at, limit)
            if key == "," or key == ";" or key == "!" or key == "?" or key == "." then stop = at; break end
            local connector, last = clauseConnector(document, at, limit)
            if connector then
                stop = at
                if (connector.id == "and" or connector.id == "or") and suitabilityMarker(document, last + 1, limit) then
                    nextJoin = connector
                end
                break
            end
        end
        if stop == marker + 1 then return nil end
        local start, ending = marker + 1, stop - 1
        local use = {join=join}
        local activityRows, last = L.functional(document, "activities", start, ending)
        local activity = activityRows and #activityRows == 1 and last == ending
            and ns.Linguistics.grammar.activities[activityRows[1]]
        if activity and activity.nominalUk then
            use.activity = activity
        else
            local phrase, finish = P.preposition(document, marker, ending)
            if phrase and phrase.rule.id == "for" and finish == stop then
                use.phrase = phrase
            else
                local action, after = purposeAt(document, marker, ending, depth, false, false, english)
                if action and after == stop then
                    if not english and action.verb then action.gerund = true end
                    use.action = action
                end
            end
        end
        if use.activity or use.phrase or use.action then known = true
        else
            use.raw = P.raw(document, start, ending)
            unresolved = unresolved or {}
            unresolved[#unresolved + 1] = {first=start, last=ending, reason="unresolved-purpose"}
        end
        uses[#uses + 1] = use
        index, join = stop, nextJoin
        if not join then break end
        index = index + 1
    end
    if join or not known then return nil end
    tree.suitabilityUses, tree.unresolvedRanges = uses, unresolved
    if english then
        tree.predicateVerb, tree.predicateModifier = fit, rule
    else
        agreeSubject(document, subject, fit.form)
        tree.copula, tree.tense, tree.predicateAdverb = true, fit.form.tense, rule
    end
    return index
end
end

local function sharedRecruitmentAction(document, object, purpose, finish, limit)
    if document.direction ~= "en-uk" or not purpose.verb or purpose.negative
        or P.key(document, finish - 1, limit) ~= "together" then return nil end
    if object.nominalAction or object.pronoun or object.article == "definite" or object.possessor
        or object.demonstrative then return nil end
    local last = purpose.series and purpose.series[#purpose.series].action or purpose
    local adverbs = last.adverbs
    local together = adverbs and adverbs[#adverbs]
    if not together or together.en[1] ~= "together" then return nil end
    for _, rule in ipairs(ns.Linguistics.grammar.prepositions) do
        if rule.nominalPartner and P.relativePronoun(object, rule.case) then
            adverbs[#adverbs] = nil
            purpose.nominalPartner = rule
            return purpose
        end
    end
end

local function membershipRecruitment(document, tree, purpose, marker, finish)
    local subject = tree.subject
    if document.direction ~= "en-uk" or not subject or tree.negative
        or not (subject.membershipGroup or P.hasTrait(subject, "membershipGroup")) then return nil end
    if purpose.verbIndex ~= marker + 1 or finish ~= purpose.verbIndex + 1 or purpose.object then return nil end
    return L.choose(document, "recruit", "verb", {mood="base"}, nil, function(entry)
        return lexemeFrame(entry).recruitmentSearch
    end)
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
    if not english and frame.ukInfinitivePattern then
        at = afterObjectMarker(document, index, limit, frame.ukInfinitivePattern)
        if not at then return nil, index end
    end
    local gerund = english and frame.gerundComplement and not (marker == "to" and frame.alternateInfinitive)
    local leading, additional
    for _ = 1, 3 do
        local modifier, following = adverbAt(document, at, limit, nil, function(candidate)
            return candidate.manner or (frame.infinitiveAdditive or frame.infinitiveAdverbs) and candidate.additive
                or frame.infinitiveAdverbs and candidate.predicateModifier
        end)
        if not modifier then break end
        if leading then
            additional = additional or {}
            additional[#additional + 1] = modifier
        else
            leading = modifier
        end
        at = following
    end
    local verbEntry, after = verb(document, at, limit, nil, not gerund, false, nil, gerund and "present")
    if verbEntry then
        local action = {verb=verbEntry, verbIndex=at, tense="infinitive", gerund=frame.gerundComplement, objectGap=gap,
            intendedEvent=frame.politeDesire or frame.sense == "conditionalDesire",
            leadingAdverb=leading, additionalLeadingAdverbs=additional,
            eventSubjectPrefix=frame.eventSubjectPrefix}
        local finish = complements(document, action, after, limit, depth + 1)
        if finish then
            local object = action.object
            if english and frame.impersonalNeed and object and (object.entityReference or object.referenceLabel
                or P.hasTrait(object, "proper") and P.relativeAnimate(object)) and not recurringEvent(action) then
                local actionFrame = lexemeFrame(action.verb)
                action.taskInfinitiveLemma = actionFrame.purposeLemma or actionFrame.indirectInfinitiveLemma
            end
            if not gap then
                finish = infinitiveSeries(document, action, finish, limit, depth + 1, gerund, not gerund)
            end
            if english and frame.intendedInfinitive then
                action.intendedEvent = not recurringEvent(action)
                for _, step in ipairs(action.series or {}) do step.action.intendedEvent = not recurringEvent(step.action) end
            end
            return action, finish
        end
        return nil
    end
    if english and frame.omittedInfinitive and marker == "to" and index == limit then return nil, index + 1 end
    if not frame.gerundComplement then return nil, index end
end

function A.adjectiveAction(document, entry, first, limit, depth)
    local marker = lexemeFrame(entry).governedAction
    if not marker or first > limit or depth >= 3 then return nil end
    local english = document.direction == "en-uk"
    if english and P.key(document, first, limit) ~= marker then return nil end
    local start = first + (english and 1 or 0)
    local negative = P.key(document, start, limit) == (english and "not" or "не")
    local action, finish = complementaryInfinitive(document, start + (negative and 1 or 0), limit,
        {infinitive=true, gerundComplement=true, infinitiveAdverbs=true}, depth)
    if action then action.negative = negative; return action, finish end
end

function A.nominalQualification(document, noun, first, limit, case)
    local previousDepth = document.qualificationDepth
    local depth = previousDepth or 0
    if first >= limit or depth >= 2 then return nil end
    local english = document.direction == "en-uk"
    local selection = noun.pronoun and noun.pronoun.requiresExplicitReferent
    local comma = P.key(document, first, limit) == ","
    if not english and not comma then return nil end
    local at = first + (comma and 1 or 0)
    if selection and not english then
        if not comma or P.key(document, at, limit) ~= "хто" then return nil end
        at = at + 1
    elseif selection and P.key(document, at, limit) == "who"
        and P.key(document, at + 1, limit) == "are" then
        at = at + 2
    end
    if english and P.key(document, at + 1, limit) ~= "of" then return nil end
    local features = not english and (selection and {case="nominative", number="singular", gender="masculine"}
        or {case=case, number=noun.number}) or nil
    local entry = L.choose(document, at, "adj", features, nil, function(candidate)
        return lexemeFrame(candidate).governedAction ~= nil
    end)
    if not entry then return nil end
    document.qualificationDepth = depth + 1
    local action, finish = A.adjectiveAction(document, entry, at + 1, limit, depth)
    local confirmedBoundary
    if english and case == "nominative" and action and noun.headIndex
        and limit - noun.headIndex < 32 and ns.UDPipeModels then
        -- A bare word at the end of the qualifier can be either its object or the main verb.
        local candidateAt = not boundary(document, finish, limit) and finish
            or finish == limit + 1 and action.object and action.object.headIndex == limit and limit
        local key = candidateAt and P.key(document, candidateAt, limit)
        local arcs = candidateAt and verb(document, candidateAt, limit, noun, false)
            and ns.Engine.UDPipe.analyzeDocument(document, noun.headIndex, limit)
        local candidate = arcs and arcs[candidateAt - noun.headIndex + 1]
        if candidateAt == finish and (auxiliary[key] or copula[key] or have[key]) then confirmedBoundary = true end
        if candidate and candidate.relation == "root" then
            if candidateAt == finish then confirmedBoundary = true
            else
                local reduced, ending = A.adjectiveAction(document, entry, at + 1, candidateAt - 1, depth)
                if reduced and ending == candidateAt then action, finish, confirmedBoundary = reduced, ending, true end
            end
        end
    end
    document.qualificationDepth = previousDepth
    if action and (confirmedBoundary or boundary(document, finish, limit)) then
        if not english and case == "nominative" and P.key(document, finish, limit) == ","
            and verb(document, finish + 1, limit, noun, false) then finish = finish + 1 end
        return {entry=entry, action=action, selection=selection}, finish
    end
end

local difficultyInfinitive = {infinitive=true}

local function difficultyAt(document, index, limit)
    local modifier, afterModifier
    if P.key(document, index, limit) ~= "too" then
        modifier, afterModifier = adverbAt(document, index, limit, nil, function(candidate) return candidate.additive end)
    end
    local first = afterModifier or index
    local rule, after = gradedAdverbAt(document, first, limit, "difficulty")
    if not rule then return nil end
    if rule.intensified and document.direction == "uk-en" then
        local _, degreeEnd = L.functional(document, "degrees", first, limit)
        local base = adverbAt(document, degreeEnd + 1, limit, "difficulty")
        if base and P.key(document, degreeEnd + 1, limit) == base.negativeUk then return nil end
    end
    return rule, after, modifier, P.key(document, first, limit) == rule.negativeUk
end

local function difficultyAction(document, index, limit, depth, patient)
    local action, finish = complementaryInfinitive(document, index, limit, difficultyInfinitive, depth, patient)
    if not action or not boundary(document, finish, limit) then return nil end
    local frame = lexemeFrame(action.verb)
    if not (patient or action.object or action.controlled or action.infinitive or frame.intransitive or frame.motion) then return nil end
    action.difficultyClause = true
    return action, finish
end

local function infinitiveQuestion(document, first, limit, depth)
    local english = document.direction == "en-uk"
    local key = P.key(document, first, limit)
    local kind = (key == "how" or key == "як") and "manner"
        or (key == "what" or key == "що") and "thing"
    local where = key == "where" or key == "де"
    local when = key == "when" or key == "коли"
    if not (kind or where or when) then return nil end
    local start = first + 1
    local negative = P.key(document, start, limit) == (english and "not" or "не")
    if negative then start = start + 1 end
    if english then
        if P.key(document, start, limit) ~= "to" then return nil end
        start = start + 1
        if not negative and P.key(document, start, limit) == "not" then negative, start = true, start + 1 end
    end
    local entry, after = verb(document, start, limit, nil, true)
    if not entry then return nil end
    local wh = kind and {kind=kind, role=kind == "thing" and "object" or "manner"}
    local action = {kind="clause", verb=entry, verbIndex=start, tense="infinitive", contentClause=true,
        wh=wh, where=where, when=when, negative=negative}
    local finish = complements(document, action, after, limit, depth + 1)
    if finish and boundary(document, finish, limit) then return action, finish end
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
    local marker = P.key(document, index, limit)
    local distributive = not english and marker == "по"
    local separated = not english and (marker == "—" or marker == "–" or marker == "-")
    if not manner and comma or marker ~= (english and "for" or "за")
        and not (english and marker == "at" or distributive or separated) then
        return nil, before
    end
    index = index + 1
    if P.key(document, index, limit) == (english and "only" or "лише") then
        only, index = true, index + 1
    end
    local grammar = ns.Engine.Grammar
    local amount, finish = grammar.moneyAt(document, index, limit)
    if amount then
        local basis, after = grammar.priceBasisAt(document, finish, limit)
        if separated and not basis or distributive and basis == "total" then return nil, before end
        return {amount=amount, manner=manner, only=only, basis=basis or distributive and "unit" or nil}, after
    end
    if separated or distributive then return nil, before end
    if english and marker ~= "at" or only or manner then return nil, before end
    local rate, after = P.noun(document, index, limit, "instrumental")
    if P.semanticClass(rate) ~= "price" then return nil, before end
    local separator = P.key(document, after, limit)
    local amountAt = after + ((separator == "—" or separator == "," or separator == ":") and 1 or 0)
    amount, finish = grammar.moneyAt(document, amountAt, limit)
    if amount or rate.argument and boundary(document, after, limit) then
        return {rate=rate, amount=amount}, finish or after
    end
    return nil, before
end

local function priceComparisonAt(document, first, limit)
    local price, after = gradedAdverbAt(document, first, limit, "tradePrice")
    if not price or not price.comparative then return price, after end
    local comma = P.key(document, after, limit) == ","
    local marker = after + (comma and 1 or 0)
    local key = P.key(document, marker, limit)
    local english = document.direction == "en-uk"
    if english and key ~= "than" or not english and key ~= "ніж" and key ~= "аніж" then return price, after end
    local standard, finish = P.preposition(document, marker + 1, limit)
    if standard and P.spatialContainer(standard.object) and standard.case == "locative" then
        return price, finish, standard
    end
    local venue, ending
    if english then venue, ending = P.noun(document, marker + 1, limit, "nominative", false, nil, true) end
    if P.semanticClass(venue) == "auctionVenue" then
        for _, rule in ipairs(ns.Linguistics.grammar.prepositions) do
            if rule.id == "at-auction" then
                return price, ending, {rule=rule, object=venue, case=rule.case}
            end
        end
    end
end

local function pricePhrase(document, first, limit)
    local amount, after = ns.Engine.Grammar.moneyAt(document, first, limit)
    local recipient
    if amount then
        local phrase, finish = P.preposition(document, after, limit)
        if phrase and phrase.rule.id == "for" then recipient, after = phrase, finish end
    end
    local comma = amount and P.key(document, after, limit) == ","
    local comparison, ending, standard
    if not amount or comma then
        comparison, ending, standard = priceComparisonAt(document, comma and after + 1 or first, limit)
    end
    if not recipient and not standard then return nil end
    return {kind="pricePhrase", amount=amount, prepositions=recipient and {recipient}, priceComma=comma and standard ~= nil,
        priceComparison=standard and comparison, priceStandard=standard}, standard and ending or after
end

local function acceptsOngoingSpan(tree)
    return (tree.tense == "present" or tree.tense == "past") and tree.verb.head.aspect ~= "perfective"
        and not (tree.modal or tree.ability or tree.imperative)
end

local function realizeObjectActions(document, tree, rules, object)
    local members = object.members or {object}
    local groups, changed = {}, false
    for index, member in ipairs(members) do
        local entry = tree.verb
        for _, rule in ipairs(rules) do
            if rule.trait and P.hasTrait(member, rule.trait)
                or rule.classes and rule.classes[P.semanticClass(member)] then
                local reading = L.choose(document, rule.verb, "verb", {mood="base"}, rule.sense)
                if not reading then return nil end
                entry, changed = reading, true
                break
            end
        end
        local group = groups[#groups]
        local join = object.joins and object.joins[index - 1]
        if not group or group.verb.id ~= entry.id then
            groups[#groups + 1] = {verb=entry, members={member}, joins={}, join=join}
        else
            group.members[#group.members + 1] = member
            group.joins[#group.joins + 1] = join
        end
    end
    if not changed then return nil end
    if #groups == 1 then return {{verb=groups[1].verb, object=object}} end
    local finalJoin = object.joins and object.joins[#members - 1]
    local actions = {}
    for _, group in ipairs(groups) do
        local complement = group.members[1]
        local lastJoin = group.joins[#group.joins]
        if lastJoin then
            if lastJoin.comma and finalJoin and finalJoin.uk then group.joins[#group.joins] = finalJoin end
            complement = {members=group.members, joins=group.joins, number="plural"}
        end
        actions[#actions + 1] = {verb=group.verb, object=complement, join=group.join}
    end
    return actions
end

local function objectBeforeActivityPurpose(document, first, limit, case, frame, headFilter, depth)
    for marker = first + 1, limit - 1 do
        if P.key(document, marker, limit) == "for" then
            local purpose, finish = purposeAt(document, marker, limit, depth, false, false, true)
            if purpose then
                local object, after = coordinatedObject(document, first, marker - 1, case,
                    frame.destinationObject, frame.enumeratesObject, frame.objectSense, headFilter)
                if object and after == marker then return object, after, purpose, finish end
            end
        end
    end
end

function A.transferReportedTime(document, reporter, reported, finish, limit)
    if document.direction == "uk-en" then
        reported.reportedAnterior = alreadyCompleted(reporter, reported)
        reported.reportedFuture = reporter.tense == "past" and reported.tense == "future"
    elseif reporter.tense == "past" and reported.conditional and hasFutureSchedule(reported) then
        local marker = finish + (P.key(document, finish, limit) == "," and 1 or 0)
        local connector = clauseConnector(document, marker, limit)
        if not (connector and (connector.id == "if" or connector.id == "unless")) then
            reported.conditional, reported.tense, reported.sequencedEvent = nil, "future", true
        end
    end
end

function A.prepareReportedClause(document, tree, embedded, recipient, finish, limit, polar)
    embedded.polar, embedded.contentClause = polar, true
    local frame = lexemeFrame(tree.verb)
    local english = document.direction == "en-uk"
    if english and polar and tree.tense == "future" and frame.prospectiveContent
        and not recurringEvent(embedded) then
        A.prospectiveEvent(embedded)
    end
    if english and recipient and recipient.person == 3 and recipient.number == "singular"
        and embedded.possessiveRecipient == "they" then
        local pronoun = recipient.gender == "feminine" and "she" or "he"
        embedded.recipient = personalSubject(pronoun)
    end
    A.transferReportedTime(document, tree, embedded, finish, limit)
    if english and frame.reportedPresent and tree.tense == "past" and embedded.tense == "past"
        and embedded.aspect == "continuous" and explicitTime(embedded) ~= "past" then
        local scheduled = hasFutureSchedule(embedded)
        embedded.tense = scheduled and "future" or "present"
        if scheduled then embedded.sequencedEvent = true end
    end
end

function A.relativePrepositionAt(document, index, limit, frame, gap)
    local choices, last = L.functional(document, "prepositions", index, limit)
    if not choices then return nil end
    for _, id in ipairs(choices) do
        local rule = ns.Linguistics.grammar.prepositions[id]
        if (rule.relativeAdjunct and gap and gap.fronted
            or rule.relativeContext and (rule.relativeContext == frame.prepositionContext
                or rule.relativeContext == frame.relativeContext))
            and (not rule.requiresMotion or frame.motion)
            and (not rule.relativeNounContent or gap and gap.nominalContent == rule.relativeNounContent)
            and (not rule.requiresClass or not gap or gap.class == rule.requiresClass
                or gap.nominalContent == "identity") then return rule, last + 1 end
    end
end

complements = function(document, tree, index, limit, depth, recentObject)
    if lexemeFrame(tree.verb).selfChange then index = index + 1 end
    depth = depth or 0
    local frame = lexemeFrame(tree.verb)
    local english = document.direction == "en-uk"
    if english and tree.negative and frame.enLexicalNegative then return nil end
    if english and tree.imperative and not tree.negative and frame.bareActionInvitation then
        local purpose, finish = purposeAt(document, index, limit, depth, false, true)
        if purpose then
            tree.purpose = purpose
            return finish
        end
    end
    local duration = frame.elapsedDuration
    local bareDuration = duration == true or not english and duration
    if not english and tree.durationSpan then
        if tree.durationSpan.ongoing then
            if not acceptsOngoingSpan(tree) then return nil end
            tree.perfectProgressive = true
        elseif not bareDuration then return nil end
    end
    local bareAdjunct = not english and bareAdjunctRule(frame.bareAdjunct)
    if frame.boundAdverb then
        local adverb, after = gradedAdverbAt(document, index, limit, frame.boundAdverb)
        if not adverb then return nil end
        tree.adverbComplement, index = adverb, after
    end
    if not english and tree.leadingAdverb and not tree.leadingAdverb.enKeepPreverbal and (tree.leadingAdverb.preNegative
        or frame.ukPreverbalAdverbs and frame.ukPreverbalAdverbs[tree.leadingAdverb.en[1]]) then
        tree.adverbs = tree.adverbs or {}
        table.insert(tree.adverbs, 1, tree.leadingAdverb)
        tree.leadingAdverb = nil
    end
    if english and frame.enSubjectPossessiveComplement then
        local after, number = A.subjectPossessiveComplementAt(document, index, limit,
            frame.enSubjectPossessiveComplement, tree.subject, tree.imperative)
        if not after then return nil end
        if tree.imperative then
            tree.imperativeNumber = number
        elseif number == "plural" and tree.subject and tree.subject.pronoun
            and tree.subject.pronoun.id == "you" then
            tree.subject = personalSubject("you_plural")
        end
        index = after
    end
    local required = not english and requiredUkComplement(frame)
    if required then
        index = afterObjectMarker(document, index, limit, required)
            or frame.ukNegativeImplicitObject and afterObjectMarker(document, index, limit, frame.ukNegativeImplicitObject)
        if not index then return nil end
    end
    if english and tree.wh and tree.wh.kind == "duration" and tree.verb.lexeme.en == "take" then return nil end
    local objectPreposition = english and frame.enObjectPreposition or not english and frame.objectPreposition
    local questionObject = tree.wh and tree.wh.role == "object"
    local gap = tree.objectGap
    local prepositionalGap = type(gap) == "table" and gap.prepositional and gap or nil
    if gap and not prepositionalGap then
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
    local occupiedObject = tree.aspect == "passive" or questionObject or gap and not prepositionalGap
    if english and frame.deicticObject and not occupiedObject and P.key(document, index, limit) == "so" then
        local following = index + 1
        tree.object = personalSubject("it")
        if boundary(document, following, limit) or adverbAt(document, following, limit) then
            index = following
        end
    end
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
    if tree.tense == "past" then
        local offset, after = P.pastOffset(document, index, limit)
        if offset then tree.pastOffset, index = offset, after end
    end
    if not tree.durationSpan and not tree.pastOffset and (bareDuration or english and frame.enObjectPreposition == "for") then
        local span, after = P.durationSpan(document, index, limit, bareDuration)
        if span and span.ongoing and not acceptsOngoingSpan(tree) then span = nil end
        if span and span.ongoing then tree.perfectProgressive = true end
        if span then tree.durationSpan, index = span, after end
    end
    local preposition, governedCase = verbObjectMarker(document, index, limit, frame)
    if preposition then index = preposition end
    local openingComparison, comparisonEnd, comparisonStart
    if frame.propertyCase then
        if frame.propertyComparison then
            openingComparison, comparisonEnd = P.preposition(document, index, limit, nil, nil,
                frame.prepositionContext, nil, "comparison")
        end
        if openingComparison then comparisonStart = index
        else
            local property, finish = propertyAt(document, index, limit, frame.propertyCase, tree.subject)
            if not property then return nil end
            tree.property, index = property, finish
        end
    end
    local predicateCase = tree.tense == "infinitive" and tree.verb.lexeme.en == "be"
        and tree.verb.lexeme.uk == "бути" and "instrumental"
    local objectCase = governedCase or (english and "accusative") or predicateCase or frame.objectCase or "accusative"
    if predicateCase then tree.infinitivePredicateCase = predicateCase end
    local priceAdverb
    if frame.priceAdverb and not occupiedObject then
        local adverb, after = adverbAt(document, index, limit, "price")
        local ambiguous = english and after == index + 1 and P.key(document, index, limit) == "free"
        if adverb and adverb.context == "price" and (not ambiguous or craftingObject(document, after, limit)) then
            priceAdverb, index = adverb, after
        end
    end
    if not occupiedObject and frame.controlCase and depth < 3 then
        local actor, start, negative, gerund = controlledStart(document, index, limit, frame)
        if not actor and english and frame.controlGerundPreposition
            and P.key(document, index, limit) == frame.controlGerundPreposition then
            gerund, start = true, index + 1
            negative = P.key(document, start, limit) == "not"
            if negative then start = start + 1 end
        end
        local action, finish
        if gerund then
            action, finish = complementaryInfinitive(document, start, limit,
                {infinitive=true, gerundComplement=true, infinitiveAdverbs=true}, depth)
            if action then
                action.negative, action.purposeClause = negative, not negative
                A.markPurposeAspect(action, false)
                for _, step in ipairs(action.series or {}) do
                    step.action.purposeClause = not step.action.negative
                    A.markPurposeAspect(step.action, false)
                end
            end
        elseif actor then
            local entry, after = verb(document, start, limit, nil, true)
            if entry and entry.lexeme.en ~= "be" then
                action = {verb=entry, tense="infinitive", negative=negative, purposeClause=not negative}
                finish = complements(document, action, after, limit, depth + 1)
            end
        end
        if action and frame.controlVerbs and not frame.controlVerbs[action.verb.lexeme.en] then return nil end
        if finish then
            if not gerund and frame.controlGerundPreposition then
                finish = infinitiveSeries(document, action, finish, limit, depth + 1, false, english)
            end
            if actor then tree.controlled = {actor=actor, action=action}
            else tree.infinitive = action end
            index = finish
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
        if frame.contentRecipientCase or frame.recipientCase then
            recipient, start = contentRecipientAt(document, index, limit, frame)
        end
        start = start or index
        if recipient and start > limit then
            tree.recipient = recipient
            return start
        end
        if not english and P.key(document, start, limit) == "," then start = start + 1 end
        if not english and frame.ukContentHead and P.key(document, start, limit) == frame.ukContentHead
            and P.key(document, start + 1, limit) == "," and P.key(document, start + 2, limit) == marker then
            start = start + 2
        end
        local linker = P.key(document, start, limit)
        local contentRecipient = recipient
        if not english and tree.imperative and not recipient and frame.defaultContentRecipient then
            contentRecipient = personalSubject(frame.defaultContentRecipient)
        end
        local action, actionEnd = infinitiveQuestion(document, start, limit, depth)
        if action then
            tree.recipient = contentRecipient
            tree.content = {action}
            return actionEnd
        end
        local following = P.key(document, start + 1, limit)
        local polar = english and (linker == "whether" or linker == "if") or not english and linker == "чи"
        local indirect = linker == "where" or linker == "де" or linker == "why" or linker == "чому"
            or linker == "when" or linker == "коли"
            or questionDeterminer(english, linker)
            or (english and englishQuestions[linker])
            or (not english and ukrainianQuestions[linker]
                and (linker ~= "що" or following == "саме" or following == "ще" or following == "таке"))
        local markedQuestion = indirect or polar
        if frame.declarativeContentOnly then indirect, polar = false, false end
        local bare = english and frame.bareContent and following ~= nil and linker ~= marker and not markedQuestion
        if linker == marker or indirect or polar or bare then
            local clauseStart = (indirect or bare) and start or start + 1
            local embedded, finish = simple(document, clauseStart, limit, nil, depth + 1, indirect or polar, nil, false)
            if embedded and embedded.subject and not embedded.imperative and not embedded.question then
                tree.recipient = contentRecipient
                A.prepareReportedClause(document, tree, embedded, recipient, finish, limit, polar)
                tree.content = {embedded}
                index = finish
                if indirect or polar then return index end
                for _ = 1, 2 do
                    local nextMarker = index
                    if P.key(document, nextMarker, limit) == "," then nextMarker = nextMarker + 1 end
                    local join = P.key(document, nextMarker, limit)
                    local andJoin = join == "and" or join == "і" or join == "й" or join == "та"
                    if not andJoin or P.key(document, nextMarker + 1, limit) ~= marker then break end
                    embedded, finish = simple(document, nextMarker + 2, limit, nil, depth + 1, nil, nil, false)
                    if not embedded or not embedded.subject or embedded.imperative or embedded.question then break end
                    embedded.contentClause = true
                    A.transferReportedTime(document, tree, embedded, finish, limit)
                    tree.content[#tree.content + 1] = embedded
                    index = finish
                end
                return index
            end
        end
    end
    if frame.bareEnContent and frame.implicitSubject == "it"
        and not (occupiedObject or tree.modal or tree.conditional) and depth < 3 then
        local nominalAt = english and index or P.key(document, index, limit) == "на" and index + 1
        if nominalAt then
            local nominal, finish = P.coordinated(document, nominalAt, limit, "accusative")
            if nominal and boundary(document, finish, limit) then
                tree.object, tree.nominalImpression = nominal, true
                return finish
            end
        end
        if english and P.key(document, index, limit) then
            -- A gerund names an event without identifying its performer.
            local implicit = personalSubject("they")
            local action, after = verb(document, index, limit, implicit, false, false, nil, "present")
            if action then
                local embedded = {kind="clause", subject=implicit, implicitSubject=true, verb=action,
                    verbIndex=index, tense="present", contentClause=true}
                local finish = complements(document, embedded, after, limit, depth + 1)
                if finish and boundary(document, finish, limit) then
                    tree.content = {embedded}
                    return finish
                end
            end
        end
    end
    if frame.requiresContent and not tree.controlled then return nil end
    local recipient, after
    if frame.recipientCase and occupiedObject and frame.requiresRecipient then
        recipient, after = objectRecipientAt(document, index, limit, frame, objectCase)
        if not personNoun(recipient) then return nil end
        tree.recipient, index = recipient, after
    elseif frame.recipientCase and not occupiedObject and not tree.controlled then
        recipient, after = objectRecipientAt(document, index, limit, frame, objectCase, tree.subject)
        if recipient then
            local object, last = coordinatedObject(document, after, limit, objectCase, frame.destinationObject,
                frame.enumeratesObject, frame.objectSense)
            if object then
                tree.recipient, tree.object, index = recipient, object, last
                local sense = english and frame.recipientObjectSenses and frame.recipientObjectSenses[P.semanticClass(object)]
                local reading = sense and L.choose(document, tree.verb.lexeme.en, "verb", nil, sense)
                if reading then tree.verb = reading end
            elseif frame.implicitTransferObject and personNoun(recipient) and boundary(document, after, limit)
                and (not english or tree.imperative
                    and (recipient.pronoun or recipient.term and
                        (recipient.term.category == "roles" or recipient.term.category == "classes"))) then
                tree.recipient, index = recipient, after
            elseif frame.requiresRecipient and personNoun(recipient) and boundary(document, after, limit) then
                tree.recipient, index = recipient, after
            end
        end
    end
    if frame.requiresRecipient and not tree.recipient then return nil end
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
    if frame.requiredInfinitive and frame.omittedInfinitive and boundary(document, index, limit) then
        tree.infinitiveEllipsis = true
    end
    if english and frame.requiredInfinitive and not tree.infinitiveEllipsis and not occupiedObject and not tree.controlled then
        local action, finish = complementaryInfinitive(document, index, limit, frame, depth, prepositionalGap)
        if not action then return nil end
        tree.infinitive, index = action, finish
    end
    local objectStart, activityPurpose, activityPurposeEnd
    local initialSpatial, initialSpatialEnd
    if not occupiedObject and not tree.controlled and not tree.object and not tree.infinitive and not tree.pastOffset
        and not frame.motion and not frame.intransitive
        and not frame.gerundComplement
        and (not objectPreposition or preposition or english and frame.optionalEnglishObjectPreposition) then
        if english and P.key(document, index, limit) ~= "on" then
            local calendar, following = P.calendar(document, index, limit)
            local event = calendar and P.noun(document, following, limit, objectCase, false, nil, true)
            if event and P.semanticClass(event) == "session" then
                tree.calendar, index = calendar, following
            end
        end
        objectStart = index
        local object, nextIndex, recruitmentDestination
        local referent = tree.previousObject or recentObject
        local requestedCase = not english and tree.negative and frame.negativeObjectCase or objectCase
        if referent then object, nextIndex = A.objectReference(document, index, limit, requestedCase, referent) end
        if not object and not english and frame.partitiveObject and requestedCase == "accusative" then
            object, nextIndex = coordinatedObject(document, index, limit, "genitive", false,
                frame.enumeratesObject, frame.objectSense,
                function(noun) return noun.number == "singular" and P.mass(noun) end)
        end
        if not object and frame.amountObject then
            object, nextIndex = P.amount(document, index, limit,
                requestedCase, frame.objectSense)
        end
        if not object and frame.separation then
            object, nextIndex = P.noun(document, index, limit, objectCase, false, nil, true)
        elseif not object then
            local previousDomain = document.transferDomain
            document.transferDomain = objectDomain(document, index, limit, frame) or previousDomain
            local negativeCase = not english and tree.negative and frame.negativeObjectCase
            local headFilter = frame.requiresSpatialContainer and P.spatialContainer
            if english and frame.forActivityPurpose and depth < 3 then
                object, nextIndex, activityPurpose, activityPurposeEnd =
                    objectBeforeActivityPurpose(document, index, limit, objectCase, frame, headFilter, depth)
            end
            if not object and frame.recruitmentSearch then
                object, nextIndex, recruitmentDestination = A.recruitmentDestinationObject(document, index, limit, objectCase)
            end
            if not object then
                object, nextIndex = coordinatedObject(document, index, limit, negativeCase or objectCase,
                    frame.destinationObject, frame.enumeratesObject, frame.objectSense, headFilter,
                    (tree.purposeClause or tree.strandedPartner) and tree.verbIndex, tree.eventSubjectPrefix,
                    tree.strandedPartner)
            end
            if not object and negativeCase then
                object, nextIndex = coordinatedObject(document, index, limit, objectCase, frame.destinationObject,
                    frame.enumeratesObject, frame.objectSense, headFilter)
            end
            if not object and not english and frame.animateObject then
                object, nextIndex = P.pronoun(document, index, limit, objectCase, true)
            end
            if not object and frame.headlessObjectPronoun then
                object, nextIndex = P.pronoun(document, index, limit, objectCase, nil, nil, frame.headlessObjectPronoun)
            end
            if not object and frame.bareCountObject then
                object, nextIndex = P.bareCount(document, index, limit)
            end
            document.transferDomain = previousDomain
        end
        if not object and english and frame.ellipticalGroupRole then
            object, nextIndex = P.ellipticalGroupMember(document, index, limit, frame.ellipticalGroupRole)
        end
        if english and object and not preposition then
            local head = object.members and object.members[1] or object
            if head.amount and head.amount.bareOver and (not frame.objectCase or frame.objectPreposition) then
                object, nextIndex = nil, nil
            end
        end
        if english and object and not preposition and (object.genitive or nextIndex <= limit) then
            local spatial, finish = P.preposition(document, index, limit, frame.motion, nil, nil, nil, "requiresSpatialAnchor")
            if spatial and finish >= nextIndex then
                initialSpatial, initialSpatialEnd = spatial, finish
                object, nextIndex = nil, nil
            end
        end
        if english and object and nextIndex <= limit and not preposition then
            local modifier, finish = adverbAt(document, index, limit, nil,
                function(candidate) return candidate.manner and candidate.prepositionalIdiom end)
            if modifier and finish > nextIndex then object, nextIndex = nil, nil end
        end
        if object and (frame.messageContent and not personNoun(object)
            or bareAdjunct and A.matchesBareAdjunct(bareAdjunct, object) and object.sourceCase == bareAdjunct.case) then
            object = nil
        end
        if object and not preposition and not objectPreposition then
            openingComparison, comparisonEnd = P.preposition(document, index, limit, nil, nil,
                frame.prepositionContext, nil, "comparison")
            if openingComparison then object, comparisonStart = nil, index end
        end
        if object and object.freeChoice and tree.negative then return nil end
        if object then
            if object.pronoun and nextIndex == index + 1 then object.headIndex = index end
            local objectFrame = object.entry and object.entry.lexeme.frame
            local quantity = tonumber(object.quantity)
            if not english and frame.genericPluralObject and tree.tense == "present"
                and objectFrame and objectFrame.semanticClass == frame.genericPluralObject
                and object.number == "singular" and object.headIndex
                and not (object.quantity or object.demonstrative or object.possessor or object.adjectives) then
                local generic = L.choose(document, object.headIndex, "noun", {case=object.sourceCase, number="plural"},
                    frame.objectSense, function(candidate) return candidate.id == object.entry.id end)
                if generic then object.entry, object.number = generic, generic.form.number end
            end
            if english and not object.skillRequirement and tree.verb.lexeme.en == "open" and objectFrame and objectFrame.skillThreshold
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
            if recruitmentDestination then
                tree.prepositions = tree.prepositions or {}
                tree.prepositions[#tree.prepositions + 1] = recruitmentDestination
                if not english and tree.tense == "present" and not (tree.aspect or tree.modal) then
                    tree.aspect = "continuous"
                end
            end
            if english and frame.objectActions then
                tree.objectActions = realizeObjectActions(document, tree, frame.objectActions, object)
            end
        elseif preposition then return nil end
    end
    if tree.object and not tree.recipient and frame.recipientMarker then
        local marked = english and P.key(document, index, limit) == frame.recipientMarker
        if marked or not english then
            recipient, after = objectRecipientAt(document, marked and index + 1 or index, limit, frame, objectCase)
            if recipient and (not english and not recipient.raw or personNoun(recipient)
                or frame.recipientTrait and P.hasTrait(recipient, frame.recipientTrait)) then
                tree.recipient, tree.recipientAfterObject, index = recipient, true, after
            end
        end
    end
    if tree.object and frame.objectState then
        local state, after = objectStateAt(document, index, limit, tree.object)
        if state then
            local sense = lexemeFrame(state.entry).stateObjectSense
            if english and objectStart and sense then
                local contextual, finish = coordinatedObject(document, objectStart, index - 1, objectCase,
                    frame.destinationObject, frame.enumeratesObject, sense)
                if contextual and finish == index then tree.object = contextual end
            end
            tree.objectState, index = state, after
        end
    end
    if frame.separation and tree.object and P.key(document, index, limit) == (english and "of" or "від") then
        tree.separation, after = P.noun(document, index + 1, limit, "genitive")
        if not tree.separation then return nil end
        index = after
    end
    if tree.object then index = attachNominalAction(document, tree.object, index, limit, depth) end
    if not english and frame.requiresManner then
        local mannerEnd = afterObjectMarker(document, index, limit, frame.ukManner)
        if not mannerEnd then
            local content, finish = messageAt(document, index, limit, frame)
            mannerEnd = content and afterObjectMarker(document, finish, limit, frame.ukManner)
            if not mannerEnd then return nil end
            tree.message = content
        end
        index = mannerEnd
    end
    if frame.messageContent and not tree.message then
        local content, finish = messageAt(document, index, limit, frame)
        if content then tree.message, index = content, finish end
    end
    local locationAvailability = english and frame.locationAvailability
    if locationAvailability and not (tree.wh or tree.modal or tree.aspect)
        and P.semanticClass(tree.subject) == locationAvailability.subjectClass then
        local objectClass = P.semanticClass(tree.object)
        local status, finish = adverbAt(document, index, limit, "predicate", function(candidate)
            return candidate.encounterAvailability and candidate.subjectClasses[objectClass]
        end)
        if status then
            for _, rule in ipairs(ns.Linguistics.grammar.prepositions) do
                if rule.id == locationAvailability.preposition then
                    tree.locationAvailability = {status=status, rule=rule}
                    index = finish
                    break
                end
            end
        end
    end
    if frame.scheduleObject then
        tree.scheduleTime, after = scheduleTimeAt(document, index, limit, true)
        if not tree.scheduleTime then return nil end
        index = after
    end
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
    if not occupiedObject and not tree.controlled and not tree.object and not tree.infinitive
        and not tree.infinitiveEllipsis and frame.infinitive then
        local action, finish = complementaryInfinitive(document, index, limit, frame, depth, prepositionalGap)
        if not finish then return nil end
        tree.infinitive, index = action, finish
    end
    if frame.requiredInfinitive and not (tree.infinitive or tree.infinitiveEllipsis) then return nil end
    if not tree.calendar then
        local calendar, after = P.calendarList(document, index, limit)
        if calendar then tree.calendar, index = calendar, after end
    end
    local clockStart = index + (tree.calendar and P.key(document, index, limit) == "," and 1 or 0)
    local range, afterRange = P.clockSchedule(document, clockStart, limit)
    if range then tree.clockRange, index = range, afterRange end
    if english and tree.infinitive and frame.infinitiveAntonym then
        local opposite = L.choose(document, frame.infinitiveAntonym, "verb")
        if not opposite then return nil end
        tree.verb, tree.negative, tree.infinitiveAntonym = opposite, not tree.negative, true
        tree.infinitive.intendedEvent = true
    end
    if tree.object then
        local emphasis = P.agentReflexive(tree.subject)
        if english and emphasis and P.key(document, index, limit) == emphasis then
            tree.agentEmphasis, index = true, index + 1
        elseif not english and emphasis then
            local adverb, after = adverbAt(document, index, limit, nil, function(candidate)
                return candidate.agentEmphasis
            end)
            if adverb then tree.agentEmphasis, index = true, after end
        end
    end
    if frame.cashComplement or tree.object and frame.priceAdverb then
        tree.priceComplement, index = priceComplement(document, index, limit)
    end
    if tree.object and frame.cashComplement then
        local comma = P.key(document, index, limit) == ","
        local price, finish, standard = priceComparisonAt(document, index + (comma and 1 or 0), limit)
        if price then
            tree.priceComparison, tree.priceComma, tree.priceStandard, index = price, comma, standard, finish
        end
    end
    local adjunctContext, secondaryContext = prepositionContext(tree, frame)
    local compensation = frame.amountObject and tree.object and (tree.object.amount or tree.object.quantity
        or P.semanticClass(tree.object) == "reward")
    local passive = tree.aspect == "passive" and (frame.passiveVoice or frame.passiveUk)
    if passive then
        secondaryContext = secondaryContext or adjunctContext
        adjunctContext = frame.passiveEnclosure and "passiveEnclosure" or "passiveAgent"
    end
    local relativeGap = prepositionalGap and not (tree.infinitive and tree.infinitive.relativePreposition)
    if relativeGap and (not english or prepositionalGap.fronted) then
        tree.relativePreposition = A.relativePrepositionAt(document, prepositionalGap.markerIndex,
            prepositionalGap.markerIndex, frame, prepositionalGap)
    end
    for _ = 1, 3 do
        if tree.tense == "past" and not tree.pastOffset then
            local offset, after = P.pastOffset(document, index, limit)
            if offset then tree.pastOffset, index = offset, after end
        end
        local ongoing = not english and acceptsOngoingSpan(tree)
        if not tree.durationSpan and (duration or tree.perfectProgressive or ongoing) then
            local span, after = P.durationSpan(document, index, limit, bareDuration)
            if span and (not span.ongoing or ongoing) then
                tree.durationSpan, index = span, after
                if span.ongoing then tree.perfectProgressive = true end
            end
        end
        if frame.postposedGovernedObject and not (occupiedObject or tree.object or tree.infinitive or tree.controlled)
            and tree.prepositions then
            local location = tree.prepositions[#tree.prepositions]
            if location and (spatialAdjuncts[location.rule.id] or location.rule.id == "out-of-location") then
                local start, case = verbObjectMarker(document, index, limit, frame)
                if start then
                    local object, after = coordinatedObject(document, start, limit, case or objectCase, false,
                        frame.enumeratesObject, frame.objectSense)
                    if object then tree.object, index = object, after end
                end
            end
        end
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
        if not tree.purpose then
            local recruits = frame.recruitmentSearch and personNoun(tree.object)
            local purpose, finish
            if activityPurpose and activityPurpose.gerundMarker == index then
                purpose, finish = activityPurpose, activityPurposeEnd
            else
                purpose, finish = purposeAt(document, index, limit, depth,
                    frame.motion or frame.contact or frame.barePurpose or frame.impersonalNeed and needPurposeObject(tree.object)
                        or recruits, nil, frame.forActivityPurpose)
            end
            if purpose then
                if recruits and purpose.verb and lexemeFrame(purpose.verb).recruitedSubject and not purpose.negative then
                    purpose.recruitedSubject = tree.object
                    tree.membershipRecruitment = membershipRecruitment(document, tree, purpose, index, finish)
                end
                local shared = recruits and not purpose.recruitedSubject
                    and sharedRecruitmentAction(document, tree.object, purpose, finish, limit)
                if shared then tree.object.nominalAction = shared
                else tree.purpose = purpose end
                return finish
            end
        end
        local context = frame.priceAdverb and "price" or frame.adverbContext
        local adverb, endAt = gradedAdverbAt(document, index, limit)
        if not adverb then
            adverb, endAt = adverbAt(document, index, limit, context, function(candidate)
                return (not candidate.preNegative or tree.negative)
                    and (not candidate.secondPersonState or tree.imperative or tree.subject and tree.subject.person == 2)
            end)
        end
        local pp, last
        local prepositionAt = adverb and adverb.scopesLocation and endAt or index
        if P.key(document, index, limit) == "," and not clauseConnector(document, index + 1, limit) then
            pp, last = P.preposition(document, index + 1, limit, nil, nil, nil, nil, "ukBeforeComma")
        end
        if not pp then
            if boundary(document, index, limit) and not (adverb and adverb.secondPersonState) then break end
            if initialSpatial and index == objectStart then pp, last = initialSpatial, initialSpatialEnd
            elseif openingComparison and index == comparisonStart then pp, last = openingComparison, comparisonEnd
            elseif not adverb or not (adverb.temporalAdjunct or adverb.secondPersonState or adverb.prepositionalIdiom) then
                local payout = compensation and P.key(document, index, limit) == (english and "for" or "за")
                pp, last = P.preposition(document, prepositionAt, limit, frame.motion, frame.displacesObject and tree.object ~= nil,
                    payout and "compensation" or adjunctContext, secondaryContext)
            end
        end
        if pp and prepositionAt ~= index then
            if spatialAdjuncts[pp.rule.id] then pp.locationAdverb = adverb
            else pp, last = nil, nil end
        end
        if not pp and bareAdjunct and index <= limit then
            local object, after = P.noun(document, index, limit, bareAdjunct.case, false, nil, true, nil,
                function(noun) return A.matchesBareAdjunct(bareAdjunct, noun) end)
            if object then
                pp, last = {rule=bareAdjunct, object=object, case=bareAdjunct.case}, after
            end
        end
        local gapRule, gapEnd
        if not pp and relativeGap and english and not tree.relativePreposition then
            gapRule, gapEnd = A.relativePrepositionAt(document, index, limit, frame, prepositionalGap)
        end
        if pp and pp.rule.passiveAgent then
            if tree.passiveAgent then return nil end
            tree.passiveAgent, index = pp.object, last
        elseif pp then
            if english and passive and pp.rule.id == "near"
                and P.key(document, index, limit) == "by" and not (P.spatialContainer(pp.object)
                    or P.hasTrait(pp.object, "spatialPart") or P.hasTrait(pp.object, "atNearLandmark")) then return nil end
            local entry = pp.object.entry
            if pp.rule.id == "since" then tree.since = true end
            local action, finish = nominalInfinitive(document, pp.object, last, limit, depth)
            if action then pp.infinitive, last = action, finish end
            if english and not tree.purpose and pp.rule.id == "for" and entry
                and frame.goalObjects and frame.goalObjects[entry.lexeme.en] then
                tree.purpose = {object=pp.object}
            else
                tree.prepositions = tree.prepositions or {}
                tree.prepositions[#tree.prepositions + 1] = pp
            end
            index = last
        elseif gapRule then
            tree.relativePreposition, index = gapRule, gapEnd
        elseif adverb then
            if english and not tree.leadingAdverb and (adverb.preNegative or adverb.ukPreverbal
                or frame.ukPreverbalAdverbs and frame.ukPreverbalAdverbs[adverb.en[1]]) then
                tree.leadingAdverb = adverb
            else
                tree.adverbs = tree.adverbs or {}
                tree.adverbs[#tree.adverbs + 1] = adverb
            end
            index = endAt
        else break end
    end
    if frame.perception or frame.motion then
        local source, finish = A.locativeSource(document, index, limit, depth)
        if source then tree.locativeSource, index = source, finish end
    end
    if frame.ellipticObjectManner and not (tree.object or occupiedObject) then
        local manner = tree.leadingAdverb and tree.leadingAdverb.manner
        for _, modifier in ipairs(tree.additionalLeadingAdverbs or {}) do manner = manner or modifier.manner end
        for _, modifier in ipairs(tree.adverbs or {}) do manner = manner or modifier.manner end
        if not manner then return nil end
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

local function predicateSpan(document, tree, index, limit)
    local english = document.direction == "en-uk"
    if tree.durationSpan or tree.tense == "future" or english and tree.tense ~= "past" then return nil end
    local span, after = P.durationSpan(document, index, limit, not english)
    if span and boundary(document, after, limit) then
        tree.durationSpan = span
        return after
    end
end

local function predicateTime(document, tree, index, limit, scheduled)
    if scheduled then
        local target, after = scheduleTimeAt(document, index, limit)
        if target then
            tree.scheduleTime = target
            return after
        end
    end
    local delay, finish = P.delay(document, index, limit)
    if delay then
        tree.delay = delay
        return finish
    end
    if tree.tense == "past" then
        local offset, after = P.pastOffset(document, index, limit)
        if offset then tree.pastOffset = offset; return after end
    end
    local elapsed = predicateSpan(document, tree, index, limit)
    if elapsed then return elapsed end
    local adverb, after = adverbAt(document, index, limit)
    if adverb and adverb.additive and not (tree.predicateModifier or tree.predicateAdverb and tree.predicateAdverb.additive)
        and boundary(document, after, limit) then
        tree.predicateModifier = adverb
        return after
    end
    if adverb and adverb.time then
        tree.adverbs = tree.adverbs or {}
        tree.adverbs[#tree.adverbs + 1] = adverb
        return after
    end
    local temporal, afterTemporal = P.preposition(document, index, limit)
    if temporal and temporal.rule.temporalAdjunct and boundary(document, afterTemporal, limit) then
        tree.prepositions = tree.prepositions or {}
        tree.prepositions[#tree.prepositions + 1] = temporal
        return afterTemporal
    end
    return index
end

local function addPredicateLocation(document, tree, place, finish, limit)
    tree.prepositions = {place}
    if P.spatialLocation(place) then
        local area, after = P.preposition(document, finish, limit)
        if P.spatialLocation(area) then
            tree.prepositions[2], finish = area, after
        end
    end
    return finish
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

function A.relativeNeed(document, marker, limit)
    if P.key(document, marker, limit) ~= "що" then return nil end
    local subject, at = recipientAt(document, marker + 1, limit, "dative", true)
    if not subject then return nil end
    local negative = P.key(document, at, limit) == "не"
    if negative then at = at + 1 end
    local predicate = P.key(document, at, limit)
    if predicate ~= "потрібно" and predicate ~= "потрібне" and predicate ~= "треба" then return nil end
    return {kind="need", subject=subject, negative=negative, wh={kind="thing", role="object", case="accusative"}},
        at + 1
end

function A.predicativeRelative(document, tree, index, limit, depth)
    if not tree.subject or depth >= 3 then return nil end
    local english = document.direction == "en-uk"
    local head = P.key(document, index, limit)
    local total, markerIndex, explicit
    if english then
        if head == "what" then markerIndex = index
        elseif head == "all" or head == "everything" then
            total = true
            explicit = P.key(document, index + 1, limit) == "that"
            markerIndex = index + (explicit and 2 or 1)
        end
    elseif head == "те" or head == "то" or head == "все" or head == "усе" then
        if P.key(document, index + 1, limit) ~= "," then return nil end
        total, markerIndex = head == "все" or head == "усе", index + 2
        local marker = P.key(document, markerIndex, limit)
        if marker ~= "що" and marker ~= "чого" and marker ~= "чим" then return nil end
    end
    if not markerIndex or markerIndex > limit or english and not total and markerIndex == limit then return nil end
    local embedded, finish
    if english and total then
        embedded, finish = simple(document, markerIndex, limit, nil, depth + 1, true, true, false)
        if embedded and embedded.relativeCase and embedded.subject and not embedded.wh then
            embedded.wh = {kind="thing", role="object", case=embedded.relativeCase}
        elseif explicit then
            embedded, finish = simple(document, markerIndex, limit, {subject=personalSubject("it")}, depth + 1, true)
            if embedded and embedded.inherited then embedded.wh = {kind="thing", role="subject"} end
        end
    else
        embedded, finish = simple(document, markerIndex, limit, nil, depth + 1, true, nil, false)
        if not embedded and not english then embedded, finish = A.relativeNeed(document, markerIndex, limit) end
    end
    local relative = embedded and embedded.wh
    if not relative or relative.kind ~= "thing" or relative.noun or relative.determiner or relative.another
        or not (embedded.verb or embedded.copula or embedded.kind == "need") or embedded.question or embedded.imperative
        or relative.role ~= "subject" and relative.role ~= "object" and not relative.indirectPredicate
        or not boundary(document, finish, limit) then return nil end
    local frame = embedded.verb and lexemeFrame(embedded.verb)
    if english and relative.role == "object" and frame and frame.impersonalNeed and embedded.subject
        and embedded.tense == "present" and not (embedded.aspect or embedded.modal or embedded.conditional or embedded.infinitive
            or embedded.leadingAdverb or embedded.adverbs or embedded.recipient or embedded.content) then
        embedded.kind = "need"
        relative.case = "accusative"
    end
    relative.boundRelative, relative.total = true, total
    local outer, inner = tree.subject.pronoun, embedded.subject and embedded.subject.pronoun
    if relative.indirectPredicate and outer and outer.id == "it" and inner and inner.id == "it"
        and embedded.tense == tree.tense and not (tree.negative or tree.question or embedded.negative)
        and P.key(document, limit + 1, #document.tokens) ~= "?" then tree.situationAcceptance = true end
    tree.predicativeRelative = {clause=embedded, total=total}
    return finish
end

local function predicate(document, tree, index, limit, depth)
    local offset, followingOffset = P.comparativeOffsetAt(document, index, limit)
    if offset then
        tree.comparativeOffset = offset
        return predicateTime(document, tree, followingOffset, limit)
    end
    local head = P.key(document, index, limit)
    local relativeEnd = A.predicativeRelative(document, tree, index, limit, depth or 0)
    if relativeEnd then return relativeEnd end
    local subjectEntry = tree.subject and tree.subject.entry
    local nominalContent = subjectEntry and lexemeFrame(subjectEntry).nominalContent
    if nominalContent and (depth or 0) < 3 then
        local start = index
        local english = document.direction == "en-uk"
        if not english then
            if head == "—" then start = start + 1 end
            local opening = P.key(document, start, limit)
            if nominalContent == "identity" and opening == "те" then
                start = start + 1
            elseif nominalContent == "explanation" and (opening == "в" or opening == "у")
                and P.key(document, start + 1, limit) == "тому" then
                start = start + 2
            else start = nil end
            if start and P.key(document, start, limit) == "," then start = start + 1 end
        end
        if start and P.key(document, start, limit) == (english and "that" or "що") then
            local content, finish = simple(document, start + 1, limit, nil, (depth or 0) + 1, nil, nil, false)
            if content and content.subject and (content.verb or content.copula or content.kind == "need")
                and not (content.imperative or content.question) and boundary(document, finish, limit) then
                tree.nominalContent, tree.contentClause = {kind=nominalContent, clause=content}, true
                return finish
            end
        end
    end
    if tree.subject then
        local grounded, after = P.groundedState(document, tree.subject, index, limit, "nominative")
        if grounded then
            tree.adjective, tree.prepositions, tree.predicateIndex = grounded, {grounded.complement}, index
            return after
        end
    end
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
    if tree.subject and boundary(document, index + 1, limit) then
        local owner = P.predicatePossessive(document, index, limit, tree.subject)
        if owner then
            tree.predicatePossessive = owner
            return index + 1
        end
    end
    local predicateAdverb, afterAdverb = adverbAt(document, index, limit, "predicate",
        function(candidate) return candidate.predicateModifier end)
    if predicateAdverb and predicateAdverb.predicateModifier and afterAdverb <= limit then
        local nominal, nominalEnd
        if document.direction == "uk-en" and L.choose(document, index, "adj", {case="nominative"}) then
            nominal, nominalEnd = P.noun(document, index, limit, "nominative")
        end
        if not (nominal and nominal.adjectives and nominalEnd > afterAdverb) then
            tree.predicateAdverb, index = predicateAdverb, afterAdverb
        end
    end
    if document.direction == "en-uk" and tree.subject and not tree.wh then
        local difficulty, after, additive = difficultyAt(document, index, limit)
        if difficulty and P.key(document, after, limit) == "to" then
            local action, finish = difficultyAction(document, after, limit, depth or 0, true)
            local patient = action ~= nil
            if not action and tree.subject.pronoun and tree.subject.pronoun.id == "it" then
                action, finish = difficultyAction(document, after, limit, depth or 0, false)
            end
            if not action then return nil end
            tree.evaluation = {rule=difficulty, action=action, difficulty=true, patient=patient, additive=additive}
            tree.implicitSubject = not patient
            return finish
        end
    end
    local serviceEnd = servicePredicate(document, tree, index, limit)
    if serviceEnd then return serviceEnd end
    if document.direction == "en-uk" and P.key(document, index + 1, limit) == "for" then
        local rating, after = adverbAt(document, index, limit, "suitability")
        if rating and rating.suitability then
            local finish = A.suitabilityAt(document, tree, rating, after, limit, depth or 0)
            if finish then return finish end
        end
    end
    local adverb, after = adverbAt(document, index, limit, "predicate", function(candidate)
        return (not candidate.subjectClasses or candidate.subjectClasses[P.semanticClass(tree.subject)])
            and (not candidate.requiresAnimate or personNoun(tree.subject))
            and (not candidate.quantifiedSubject or P.quantifiedSubject(tree.subject))
    end)
    local pronoun = tree.subject and tree.subject.pronoun
    if adverb and adverb.personalPredicate then
        local topic, finish = P.preposition(document, after, limit, nil, nil, adverb.prepositionContext, nil, "predicateTopic")
        local endAt = finish or after
        local join, marker = clauseConnector(document, endAt, limit)
        local sharedPredicate = join and (join.id == "and" or join.id == "or")
        if sharedPredicate then
            local opening = P.key(document, marker + 1, limit)
            local subject, nextWord = P.coordinated(document, marker + 1, limit, "nominative")
            local finite = subject and P.key(document, nextWord, limit)
            sharedPredicate = not (contracted[opening] or copula[finite] or negativeCopula[finite] or auxiliary[finite])
        end
        if not sharedPredicate then
            local action = L.choose(document, "be " .. adverb.en[1], "verb", {mood="base"}, nil,
                function(entry) return entry.lexeme.uk == adverb.uk[1] end)
            if action then
                tree.predicateVerb = action
                if topic then tree.prepositions = {topic} end
                return predicateTime(document, tree, endAt, limit)
            end
        end
    end
    if adverb and adverb.impersonalTiming and pronoun and pronoun.id == "it" then
        tree.implicitSubject, tree.predicateIndex = true, after - 1
        tree.predicateModifier, tree.predicateAdverb = tree.predicateAdverb, adverb
        local english = document.direction == "en-uk"
        if depth and depth < 3 and (not english or P.key(document, after, limit) == "to") then
            local start = after + (english and 1 or 0)
            local entry, following = verb(document, start, limit, nil, true)
            if entry then
                local action = {kind="clause", verb=entry, tense="infinitive", purposeClause=true, verbIndex=start}
                local finish = complements(document, action, following, limit, depth + 1)
                if finish and boundary(document, finish, limit) then tree.infinitive = action; return finish end
            end
        end
        return predicateTime(document, tree, after, limit)
    end
    if adverb and adverb.deicticEvaluation and deicticSubject(tree.subject) then
        tree.predicateModifier, tree.predicateAdverb = tree.predicateAdverb, adverb
        if adverb.clausalComplement and (depth or 0) < 3 then
            local english = document.direction == "en-uk"
            local marker = not english and P.key(document, after, limit) == "," and after + 1 or after
            if P.key(document, marker, limit) == (english and "that" or "що") then
                local content, finish = simple(document, marker + 1, limit, nil, (depth or 0) + 1, nil, nil, false)
                if content and content.subject and not (content.imperative or content.question)
                    and (content.verb or content.copula or content.kind == "need") and boundary(document, finish, limit) then
                    content.contentClause = true
                    tree.evaluationContent = content
                    return finish
                end
            end
        end
        return predicateTime(document, tree, after, limit)
    end
    if adverb and adverb.evaluativePredicate and pronoun and pronoun.id == "it" and (depth or 0) < 3 then
        local english = document.direction == "en-uk"
        local infinitive = english and adverb.evaluationInfinitive and P.key(document, after, limit) == "to"
        local tense = not english and tree.tense == "present" and obligationTime[P.key(document, after, limit)]
        local start = after + ((infinitive or tense) and 1 or 0)
        local entry, actionStart = verb(document, start, limit, nil, not english or infinitive, false, nil,
            english and not infinitive and "present" or nil)
        if entry then
            local action = {kind="clause", verb=entry, verbIndex=start, tense="infinitive",
                gerund=not adverb.evaluationInfinitive}
            local finish = complements(document, action, actionStart, limit, (depth or 0) + 1)
            if finish then
                local bounded = english and adverb.evaluationInfinitive and lexemeFrame(entry).indirectInfinitiveLemma
                if bounded and not (action.durationSpan or recurringEvent(action)) then action.taskInfinitiveLemma = bounded end
                if tense then tree.tense = tense end
                tree.implicitSubject, tree.evaluation = true, {rule=adverb, action=action}
                return finish
            end
        end
    end
    if adverb and (adverb.statePredicate or adverb.quantifiedSubject or adverb.punctuality) then
        tree.predicateAdverb = adverb
        tree.negative = tree.negative or P.key(document, index, limit) == adverb.negativeUk
        return predicateTime(document, tree, after, limit)
    end
    local timeAfter = adverb and adverb.bareState and adverbAt(document, after, limit)
    if adverb and adverb.location and (adverb.subjectClasses
        or adverb.bareState and (after > limit or timeAfter and timeAfter.time)) then
        tree.locativeAdverbIndex = index
        tree.predicateModifier, tree.predicateAdverb = tree.predicateAdverb, adverb
        local place, finish = P.preposition(document, after, limit)
        if place and spatialAdjuncts[place.rule.id] then
            after = addPredicateLocation(document, tree, place, finish, limit)
        end
        return predicateTime(document, tree, after, limit, adverb.scheduleStatus)
    end
    local pp, finish = P.preposition(document, index, limit, nil, nil, "predicate")
    if not pp and document.direction == "en-uk" then pp, finish = P.freeAbsence(document, index, limit, true) end
    if pp then
        if pp.rule.id == "over-location" and tree.subject and tree.subject.number == "plural"
            and pp.object.quantity and P.personNoun(pp.object) then
            local count, countEnd = P.noun(document, index, limit, "nominative", false, nil, nil, nil, P.personNoun)
            if count and count.amount and count.amount.bareOver and countEnd >= finish then
                tree.predicate, tree.predicateStart = count, index
                return predicateTime(document, tree, countEnd, limit)
            end
        end
        if pp.rule.subjectSense then refineSubject(document, tree.subject, pp.rule) end
        if pp.rule.resourceDepletion then tree.exhausted = pp.object
        else finish = addPredicateLocation(document, tree, pp, finish, limit) end
        return predicateTime(document, tree, finish, limit)
    end
    if tree.where then
        if index > limit then return not tree.negative and index or nil end
        local ending = predicateTime(document, tree, index, limit)
        if ending > index then return ending end
        return nil
    end
    if index > limit then return tree.wh and tree.wh.kind == "manner" and index end
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
                tree.locativeAdverbIndex = index
                return predicateTime(document, tree, placeEnd, limit)
            end
        end
        tree.adverbs = {adverb}
        tree.locativeAdverbIndex = index
        local finish = predicateTime(document, tree, after, limit)
        if tree.durationSpan then
            tree.predicateModifier = tree.predicateModifier or tree.predicateAdverb
            tree.predicateAdverb = adverb
            table.remove(tree.adverbs, 1)
            if #tree.adverbs == 0 then tree.adverbs = nil end
        end
        return finish
    end
    local intensity
    if modifier == "more" or modifier == "більш" or modifier == "very" or modifier == "дуже" or modifier == "so"
        or modifier == "too" and document.direction == "en-uk" or modifier == "надто" then
        intensity = (modifier == "more" or modifier == "більш") and "more" or modifier == "so" and "so"
            or (modifier == "too" or modifier == "надто") and "too" or "very"
        index = index + 1
    end
    if tree.subject and not tree.frontedLocation then
        local subject = tree.subject
        local agreement = document.direction == "uk-en" and {case="nominative", number=subject.number,
            gender=subject.number == "singular" and subject.gender or nil}
        local orientation, topic, finish = P.activityOrientation(document, index, limit, agreement or nil)
        if orientation then
            orientation.intensity = intensity
            tree.adjective, tree.prepositions, tree.predicateIndex = orientation, {topic}, orientation.index
            return predicateTime(document, tree, finish, limit)
        end
    end
    local modifierEnd = index + 1
    local function adjectiveAllowed(candidate)
        local frame = lexemeFrame(candidate)
        local pronoun = tree.subject and tree.subject.pronoun
        if tree.frontedLocation then
            local subject = tree.subject
            local agreement = {case="nominative", number=subject.number,
                gender=subject.number == "singular" and subject.gender or nil}
            if frame.predicateLocation ~= tree.frontedLocation.rule.id or not L.matches(candidate.form, agreement) then
                return false
            end
        end
        if frame.enPredicateMarker and document.direction == "en-uk"
            and not afterObjectMarker(document, modifierEnd, limit, frame.enPredicateMarker) then
            return false
        end
        if frame.noEnglishInfinitive and document.direction == "en-uk"
            and P.key(document, modifierEnd, limit) == "to" and L.choose(document, modifierEnd + 1, "verb") then
            return false
        end
        return not frame.profileOnly and not (pronoun and pronoun.id == "someone" and frame.sense == "price")
    end
    if document.direction == "en-uk" and personNoun(tree.subject) and not tree.modal
        and P.key(document, index + 1, limit) == "at" then
        local function ability(candidate) return lexemeFrame(candidate).activitySkill ~= nil end
        local skill = L.choose(document, index, "adj", nil, "activitySkill", ability)
            or L.choose(document, index, "adj", nil, nil, ability)
        local action, finish
        if skill then action, finish = complementaryInfinitive(document, index + 2, limit, lexemeFrame(skill), depth or 0) end
        if action and boundary(document, finish, limit) then
            tree.adjective, tree.infinitive = {entry=skill, intensity=intensity}, action
            tree.activitySkill = lexemeFrame(skill).activitySkill
            return finish
        end
    end
    local stateSense = personNoun(tree.subject) and "personalState"
    local subjectClass = P.semanticClass(tree.subject)
    local function contextualAdjective(candidate)
        local frame = lexemeFrame(candidate)
        if not frame.predicateHead or not adjectiveAllowed(candidate) then return false end
        if frame.headClasses[subjectClass] or frame.predicateDeictic and deicticSubject(tree.subject) then return true end
        local reading = subjectReading(document, tree.subject, frame)
        return reading and frame.headClasses[lexemeFrame(reading).semanticClass]
    end
    local nominative = {case="nominative"}
    local contextualSubject = subjectClass or deicticSubject(tree.subject)
    local adjective = contextualSubject and L.genderPair(document, index, limit, "adj", nominative, "nounModifier", contextualAdjective)
        or stateSense and L.genderPair(document, index, limit, "adj", nominative, stateSense, adjectiveAllowed)
        or L.genderPair(document, index, limit, "adj", nominative, nil, adjectiveAllowed)
    local adjectiveEnd = index + (adjective and 3 or 1)
    local paired = adjective ~= nil
    if not paired and index <= limit then
        local function chooseAdjective(source)
            return contextualSubject and L.choose(document, source, "adj", nil, "nounModifier", contextualAdjective)
                or stateSense and L.choose(document, source, "adj", nil, stateSense, adjectiveAllowed)
                or L.choose(document, source, "adj", nil, nil, adjectiveAllowed)
        end
        local phrase, after = L.phraseAt(document, index, limit, "adj")
        if phrase then
            modifierEnd = after
            adjective = chooseAdjective(phrase)
            if adjective then adjectiveEnd = after end
        end
        if not adjective then
            modifierEnd = index + 1
            adjective = chooseAdjective(index)
        end
    end
    if adjective and lexemeFrame(adjective).predicateHead and not lexemeFrame(adjective).headClasses[subjectClass] then
        refineSubject(document, tree.subject, lexemeFrame(adjective))
    end
    local object, nextIndex
    if adjective and (paired or intensity or adjective.lexeme.frame and adjective.lexeme.frame.ukExperiencer) then
        object = nil
    else
        object, nextIndex = P.coordinated(document, index, limit, "nominative")
        if tree.question and object and P.personNoun(tree.subject) and P.personNoun(object)
            and P.key(document, nextIndex, limit) == "," then
            local listing, finish = P.coordinated(document, index, limit, "nominative",
                nil, nil, "predicate", nil, P.personNoun)
            if listing and listing.members and boundary(document, finish, limit) then
                object, nextIndex = listing, finish
            end
        end
    end
    if not object and document.direction == "en-uk" and tree.subject and tree.subject.pronoun
        and tree.subject.pronoun.deixis then
        object, nextIndex = P.pronoun(document, index, limit, "accusative", true)
    end
    if not object and document.direction == "uk-en" and (tree.tense == "past" or tree.tense == "future") then
        object, nextIndex = P.coordinated(document, index, limit, "instrumental", nil, nil, nil, nil, function(noun)
            local frame = noun.entry and noun.entry.lexeme.frame
            return tree.conditional or nominalContent == "identity" or frame and frame.nonpresentPredicateCase == "instrumental"
        end)
    end
    local level, levelEnd = P.levelAt(document, index, limit)
    if level and not (object and object.characterLevel and nextIndex > levelEnd) then
        tree.level = level
        return predicateTime(document, tree, levelEnd, limit)
    end
    if adjective and object and adjectiveEnd > index + 1 and nextIndex < adjectiveEnd then
        object = nil
    end
    if adjective and object and object.entry and nextIndex == adjectiveEnd
        and not (object.article or object.possessor or object.adjectives or object.genitive or object.quantity)
        and adjective.lexeme.preference < object.entry.lexeme.preference then
        object = nil
    end
    if object and (not intensity or not adjective) then
        tree.predicate, tree.predicateStart = object, index
        local frame = object.entry and object.entry.lexeme.frame
        local english = document.direction == "en-uk"
        if english and frame and frame.personPredicateSense and personNoun(tree.subject) then
            local human = L.choose(document, object.headIndex, "noun", nil, frame.personPredicateSense)
            if human then
                object.entry, object.gender, object.animacy = human, human.head.gender, human.head.animacy
                frame = human.lexeme.frame
                if object.genitive and not object.argument and frame.nominalArguments then
                    object.argument = {object=object.genitive, form=frame.nominalArguments[1]}
                    object.genitive = nil
                end
            end
        end
        local subjectPronoun = tree.subject and tree.subject.pronoun
        if english and subjectPronoun and subjectPronoun.id == "you" and object.number == "plural"
            and personNoun(object) then
            -- Coordinated singular labels may all describe the same person.
            local pluralMembers = true
            for _, member in ipairs(object.members or {}) do
                if member.number ~= "plural" then
                    pluralMembers = false
                    break
                end
            end
            if pluralMembers then tree.subject = personalSubject("you_plural") end
        end
        if english and frame and frame.predicateGenderAgreement and tree.subject
            and tree.subject.number == "singular" and tree.subject.gender and object.number == "singular"
            and object.gender ~= tree.subject.gender then
            local agreed = L.choose(document, object.headIndex, "noun", nil, frame.sense, function(candidate)
                return candidate.head.gender == tree.subject.gender
            end)
            if agreed then object.entry, object.gender = agreed, agreed.head.gender end
        end
        if frame and frame.nominalPredicateTail then
            local start = nextIndex + (not english and P.key(document, nextIndex, limit) == "," and 1 or 0)
            local tail, finish = adverbAt(document, start, limit, frame.nominalPredicateTail, function(candidate)
                return candidate.context == frame.nominalPredicateTail
            end)
            if tail and boundary(document, finish, limit) then
                tree.nominalPredicateTail, nextIndex = tail, finish
            end
        end
        if frame and frame.nominalInfinitive and not tree.nominalPredicateTail then
            nextIndex = attachNominalAction(document, object, nextIndex, limit, depth or 0)
        end
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
        tree.predicateIndex = index
        local frame = adjective.lexeme.frame
        local action, finish = A.adjectiveAction(document, adjective, adjectiveEnd, limit, depth or 0)
        if action then
            tree.infinitive, tree.adjectiveActionMarker = action, frame.governedAction
            return finish
        end
        if frame and frame.predicateLocation then
            local place, finish = tree.frontedLocation, adjectiveEnd
            if not place then place, finish = P.preposition(document, adjectiveEnd, limit, nil, nil, "predicate") end
            if not place or place.rule.id ~= frame.predicateLocation then return nil end
            adjectiveEnd = addPredicateLocation(document, tree, place, finish, limit)
        end
        if depth and depth < 3 and (adjective.form.degree == "comparative" or intensity == "more") then
            local english = document.direction == "en-uk"
            local marker = adjectiveEnd
            if not english and P.key(document, marker, limit) == "," then marker = marker + 1 end
            local key = P.key(document, marker, limit)
            if english and key == "than" or not english and (key == "ніж" or key == "аніж") then
                local standard, finish = simple(document, marker + 1, limit, nil, depth + 1)
                if standard and standard.kind == "clause" and standard.subject and not standard.question
                    and not standard.imperative and boundary(document, finish, limit) then
                    tree.comparison = standard
                    return finish
                end
            end
        end
        if frame and frame.infinitiveComplement and depth and depth < 3 then
            local english = document.direction == "en-uk"
            if not english or P.key(document, adjectiveEnd, limit) == "to" then
                local priorDomain = document.transferDomain
                local pronoun = tree.subject and tree.subject.pronoun
                if frame.prepositionContext == "readiness"
                    and (P.hasTrait(tree.subject, "membershipGroup") or pronoun and pronoun.id == "we") then
                    document.transferDomain = "groupReadiness"
                end
                local entry, nextIndex = verb(document, adjectiveEnd + (english and 1 or 0), limit, nil, true)
                document.transferDomain = priorDomain
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
        local elapsed = predicateSpan(document, tree, adjectiveEnd, limit)
        if elapsed then return elapsed end
        local following, afterAdjective = P.preposition(document, adjectiveEnd, limit, nil, nil,
            frame and frame.prepositionContext)
        if following then
            tree.prepositions = {following}
            return predicateTime(document, tree, afterAdjective, limit)
        end
        local english = document.direction == "en-uk"
        local subject = tree.subject
        local number = subject and subject.number
        local gender = number ~= "plural" and (subject and subject.gender or adjective.form.gender) or nil
        local case = adjective.form.case == "instrumental" and "instrumental" or "nominative"
        local features = not english and {case=case, number=number, gender=gender} or nil
        for _ = 1, 3 do
            local join, connectorEnd = clauseConnector(document, adjectiveEnd, limit)
            if not join or (join.id ~= "and" and join.id ~= "or") then break end
            local start = connectorEnd + 1
            local negative = P.key(document, start, limit) == (english and "not" or "не")
            if negative then start = start + 1 end
            local qualifier, qualifiedAt = adverbAt(document, start, limit, "predicate",
                function(candidate) return candidate.predicateModifier end)
            if qualifier then start = qualifiedAt end
            local degree = P.key(document, start, limit) == (english and "very" or "дуже") and "very" or nil
            if degree then start = start + 1 end
            local phrase, ending = L.phraseAt(document, start, limit, "adj")
            modifierEnd = ending or start + 1
            local entry = L.choose(document, phrase or start, "adj", features, stateSense, adjectiveAllowed)
                or L.choose(document, phrase or start, "adj", features, nil, adjectiveAllowed)
            if not entry or not boundary(document, modifierEnd, limit) then break end
            tree.adjectiveSeries = tree.adjectiveSeries or {}
            tree.adjectiveSeries[#tree.adjectiveSeries + 1] = {
                join=join, entry=entry, intensity=degree, negative=negative, qualifier=qualifier,
            }
            adjectiveEnd = modifierEnd
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

local function socialComplement(document, first, limit, depth, standalone)
    if not ns.Linguistics.grammar.socialActs then return nil end
    local signal, afterSignal = adverbAt(document, first, limit, nil, function(candidate) return candidate.audienceSignal end)
    if signal and P.key(document, afterSignal, limit) ~= "," then signal = nil end
    local opening = signal and afterSignal + 1 or first
    local choices, last = L.functional(document, "socialActs", opening, limit)
    if not choices then return nil end
    local rule = ns.Linguistics.grammar.socialActs[choices[1]]
    if signal and not rule.audience then return nil end
    local english = document.direction == "en-uk"
    local index = last + 1
    local mark = P.key(document, index, limit)
    local tree = {kind="social", social=rule}
    if rule.audience then
        local audience, after = P.coordinated(document, index, limit, english and "accusative" or rule.ukCase,
            nil, nil, true, nil, P.relativeAnimate)
        if not audience then return nil end
        tree.object, tree.audienceSignal = audience, signal
        return tree, after
    end
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
    if not standalone and tree.everyone and document.relativeBudget then
        local recipient = personalSubject("everyone")
        local relative, after = A.relative(document, recipient, index, limit)
        if relative then
            recipient.relative, tree.relativeRecipient = relative, recipient
            index, mark = after, P.key(document, after, limit)
        end
    end
    if standalone or index > limit then
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
    if modifier and (modifier.context == "existence" or modifier.existentialPersistence) then return modifier, following end
end

function A.existentialHead(document, first, limit)
    local key = P.key(document, first, limit)
    local nextKey = P.key(document, first + 1, limit)
    if document.direction == "uk-en" then
        local negative = key == "не" or key == "немає" or key == "нема"
        local form = key == "не" and nextKey or key
        local tense = (form == "є" or form == "немає" or form == "нема") and "present"
            or (form == "буде" or form == "будуть") and "future"
            or ukCopulaAgreement[form] and "past"
        if not tense or negative and form ~= "немає" and form ~= "нема"
            and form ~= "було" and form ~= "буде" then return nil end
        local agreement = ukCopulaAgreement[form] or (form == "будуть" and "plural")
        local position = key == "не" and first + 1 or first
        return {tense=tense, negative=negative, agreement=agreement, singular=form == "буде",
            predicateIndex=position}, position + 1
    end
    local form, index, question, certainty
    if key == "there's" or key == "there'll" then
        form, index = key == "there's" and "is" or "will", first + 1
    elseif key == "there" then
        certainty, index = adverbAt(document, first + 1, limit, "existence",
            function(candidate) return candidate.existentialCertainty end)
        index = index or first + 1
        form, index = P.key(document, index, limit), index + 1
    elseif nextKey == "there" then
        form, index, question = key, first + 2, true
    else return nil end
    local base = negativeCopula[form] or form
    local inflection = auxiliary[base]
    local future = base == "will" or inflection and inflection.tense == "future" and inflection.negative
    if not future and base ~= "is" and base ~= "are" and base ~= "was" and base ~= "were" then return nil end
    local negative = negativeCopula[form] ~= nil or future and inflection.negative or false
    if future and not certainty then
        local modifier, following = adverbAt(document, index, limit, "existence",
            function(candidate) return candidate.existentialCertainty end)
        if modifier then certainty, index = modifier, following end
    end
    if P.key(document, index, limit) == "not" then negative, index = true, index + 1 end
    if future then
        if P.key(document, index, limit) ~= "be" then return nil end
        index = index + 1
    end
    local quantifier = P.key(document, index, limit)
    if quantifier == "no" or (negative or question) and quantifier == "any" then
        negative, index = negative or quantifier == "no", index + 1
    end
    local number = not future and ((base == "are" or base == "were") and "plural" or "singular")
    return {tense=future and "future" or copula[base], negative=negative, number=number,
        any=question and quantifier == "any" or nil,
        question=question, certainty=certainty}, index
end

local function existential(document, first, limit, depth, sentenceQuestion)
    if depth >= 3 then return end
    local english = document.direction == "en-uk"
    local reason = P.key(document, first, limit) == (english and "why" or "чому")
    if reason then
        if english and P.key(document, first + 2, limit) ~= "there" then return nil end
        first = first + 1
    end
    local key, index, copulaNumber = P.key(document, first, limit), first
    local nextKey = P.key(document, first + 1, limit)
    local interrogative = sentenceQuestion
    if interrogative == nil then interrogative = document.tokens[limit + 1] and document.tokens[limit + 1].key == "?" end
    local unpunctuatedAny = english and key == "any" and not interrogative
    local nearby, possessor, bareIndefinite, location, persistence, leadingPlace, leadingDistribution, possessorSubject
    local head, certainty
    local question = true
    if english then
        head, index = A.existentialHead(document, first, limit)
        if head then
            copulaNumber, certainty, question = head.number, head.certainty, head.question or interrogative or false
        elseif key == "any" then
            index = first + 1
        elseif (interrogative or nextKey == "who" or nextKey == "to") and indefinitePerson(document, first, limit) then
            bareIndefinite, index = true, first
            if nextKey == "who" then nearby = true end
        elseif key == "is" and indefinitePerson(document, first + 1, limit) then
            index = first + 1
        elseif key == "do" and nextKey == "we" and P.key(document, first + 2, limit) == "have"
            and indefinitePerson(document, first + 3, limit) then
            possessor, index = true, first + 3
        else return end
    else
        local marker = (key == "чи") and first + 1 or first
        local preposition = P.key(document, marker, limit)
        if preposition == "у" or preposition == "в" then
            local owner, following = P.pronoun(document, marker + 1, limit, "genitive", true)
            if owner and P.key(document, following, limit) == "є" then
                possessorSubject, marker = owner, following
            end
        end
        local place, placeEnd = P.preposition(document, marker, limit)
        if place and spatialAdjuncts[place.rule.id] then leadingPlace, marker = place, placeEnd
        elseif place and place.rule.id == "for" and place.object.distributive then
            leadingDistribution, marker = place, placeEnd
        end
        local modifier, following = persistenceAt(document, marker, limit)
        if modifier then persistence, marker = modifier, following end
        local at, following = adverbAt(document, marker, limit)
        if at and at.location then
            local modifier, after = persistenceAt(document, following, limit)
            if A.existentialHead(document, after or following, limit) then
                location, persistence, marker = at, persistence or modifier, after or following
            end
        end
        head, index = A.existentialHead(document, marker, limit)
        if not head then return end
        question = key == "чи" or interrogative or false
        if key == "чи" then
            if P.key(document, index, limit) == "тут" then nearby, index = true, index + 1 end
            local preposition = P.key(document, index, limit)
            if (preposition == "в" or preposition == "у") and P.key(document, index + 1, limit) == "нас" then
                possessor, index = true, index + 2
            end
        end
    end
    if not persistence and head then
        local modifier, after = persistenceAt(document, index, limit)
        if modifier then persistence, index = modifier, after end
    end
    if persistence and persistence.existentialCertainty then
        certainty, persistence = persistence, nil
    end
    if head and certainty and index > limit then
        return {kind="existential", tense=head.tense, negative=head.negative, existentialNumber=head.number,
            certainty=certainty, locationAdverb=location, question=question}, index
    end
    local focus, afterFocus = adverbAt(document, index, limit, nil, function(entry) return entry.quantityFocus end)
    if focus then index = afterFocus end
    local subjectCase = not english and head.negative and "genitive" or "nominative"
    local subject, after = P.noun(document, index, limit, subjectCase)
    local agrees
    if not english and not head.negative and (head.agreement or head.singular) then
        agrees = function(noun)
            if noun.number == "plural" then
                -- Ukrainian can use a singular copula with a counted group.
                return head.agreement == "plural" or (head.agreement == "neuter" or head.singular)
                    and (noun.quantity or noun.headlessCardinal or noun.few
                        or noun.pronoun and noun.pronoun.headlessQuantity or P.quantifiedSubject(noun))
            end
            if head.singular then return true end
            return head.agreement == noun.gender
        end
        if subject and not agrees(subject) then
            subject, after = P.noun(document, index, limit, subjectCase, nil, nil, nil, nil, agrees)
        end
    end
    local amount, amountEnd = P.pronoun(document, index, limit, "nominative", nil, true)
    if amount and amount.pronoun.id == "several"
        and (not subject or after <= amountEnd) then subject, after = amount, amountEnd end
    if not subject and head and subjectCase == "nominative" then
        local surface = P.key(document, index, limit)
        local grammar = ns.Linguistics.grammar
        local cardinal = english and grammar.cardinalEn[surface]
            or not english and surface ~= "одну" and (grammar.cardinalUk[surface] or grammar.collectiveUk[surface])
        if cardinal then
            subject = {headlessCardinal=cardinal, number=cardinal == 1 and "singular" or "plural", person=3}
            after = index + 1
        end
    end
    local capacity
    if not subject or not (subject.article or subject.adjectives or subject.possessor or subject.quantity or subject.demonstrative) then
        local marker = P.key(document, index + 1, limit)
        local following = marker and P.preposition(document, index + 1, limit, nil, nil, "roomCapacity")
        if not marker or leadingPlace or following and (spatialAdjuncts[following.rule.id]
            or following.rule.id == "for" and P.relativeAnimate(following.object)) then
            capacity = L.choose(document, index, "noun", not english and {case=subjectCase} or nil, nil,
                function(candidate)
                    return lexemeFrame(candidate).capacity and candidate.form.number ~= "plural"
                end)
        end
        if capacity then
            subject = {entry=capacity, person=3, number="singular", gender=capacity.head.gender,
                animacy=capacity.head.animacy, headIndex=index}
            after = index + 1
        end
    end
    if leadingPlace and not capacity and head.tense == "present" and not head.negative then return nil end
    if not subject or agrees and not agrees(subject) then return end
    local quantified = subject.quantity or subject.headlessCardinal or subject.few
        or subject.pronoun and subject.pronoun.headlessQuantity
    local informalPlural = english and subject.number == "plural" and quantified
        and (key == "there's" or key == "there" and nextKey == "is")
    if english and copulaNumber and not quantified then P.agreeInvariantNoun(subject, copulaNumber) end
    if copulaNumber and subject.number ~= copulaNumber and not informalPlural
        and not (head.any and copulaNumber == "singular" and subject.number == "plural"
            and P.relativeAnimate(subject)) then return end
    if not english and head.tense ~= "present" and not head.negative then
        local state = adverbAt(document, after, limit, "predicate")
        if state and state.context == "predicate"
            and (not state.subjectClasses or state.subjectClasses[P.semanticClass(subject)]) then return nil end
    end
    local adverb, finish = adverbAt(document, after, limit)
    local here = P.key(document, after, limit)
    if not location and adverb and adverb.location and finish > after + 1 then
        location, after = adverb, finish
    elseif here == "around" or here == "here" or here == "тут" then nearby, after = true, after + 1 end
    local tree = {kind="existential", subject=subject, question=question or reason, why=reason,
        nearby=nearby, possessor=possessor, possessorSubject=possessorSubject,
        tense=head and head.tense, negative=head and head.negative, certainty=certainty,
        capacity=capacity ~= nil, locationAdverb=location, persistence=persistence, quantityFocus=focus,
        existentialIndex=head and head.predicateIndex,
        locationPreposition=leadingPlace or leadingDistribution}
    after = attachNominalAction(document, subject, after, limit, depth)
    local category = subject.term and subject.term.category
    local context = capacity and "roomCapacity" or (category == "roles" or category == "classes") and "roleAvailability"
    for _ = 1, 2 do
        local pp, finish = P.preposition(document, after, limit, nil, nil, context)
        if not pp or not (P.spatialLocation(pp)
            or pp.rule.id == "for-instance-recruitment"
            or pp.rule.id == "for" and (not subject.pronoun or subject.pronoun.headlessQuantity)) then break end
        local distributedQuantity = subject.pronoun and subject.pronoun.headlessQuantity
            and pp.rule.id == "for" and pp.object.distributive
        if not tree.question and not (tree.locationPreposition or tree.prepositions)
            and (capacity and spatialAdjuncts[pp.rule.id] or distributedQuantity) then tree.locationPreposition = pp
        else
            tree.prepositions = tree.prepositions or {}
            tree.prepositions[#tree.prepositions + 1] = pp
        end
        after = finish
    end
    adverb, finish = adverbAt(document, after, limit)
    if not tree.locationAdverb and adverb and adverb.location then tree.locationAdverb, after = adverb, finish end
    local marker = P.key(document, after, limit)
    local purposeMarker = not english and marker == "," and P.key(document, after + 1, limit) or marker
    if (english and (purposeMarker == "to" or purposeMarker == "not" or purposeMarker == "in")
        or not english and (purposeMarker == "щоб" or purposeMarker == "аби"))
        and not subject.relative and P.relativeAnimate(subject) then
        local purpose, ending = purposeAt(document, after, limit, depth, true)
        if purpose and boundary(document, ending, limit) then
            tree.purpose = purpose
            return tree, ending
        end
    end
    if unpunctuatedAny and (after <= limit or not (P.relativeAnimate(subject) or P.hasTrait(subject, "availabilitySubject"))) then
        return nil
    end
    if after > limit then return tree, after end
    local comma = marker == ","
    if comma then after = after + 1; marker = P.key(document, after, limit) end
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
            if markerIndex and boundary(document, markerIndex, limit)
                and (copulaNumber or action.lexeme.frame and personal and (bareIndefinite or key == "is" or key == "are")) then
                if not (copulaNumber or tree.nearby or tree.locationAdverb or tree.prepositions or tree.persistence
                    or tree.possessor or tree.why) then
                    description.inherited, description.question = nil, tree.question
                    return description, markerIndex
                end
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

local function needPurpose(phrase)
    return phrase and (phrase.rule.id == "for" or phrase.rule.id == "for-journey")
end

local function addresseePurpose(phrase)
    local possessor = needPurpose(phrase) and phrase.object.possessor
    return possessor and possessor.lexeme.en == "your"
end

local function needClause(document, object, index, limit, subject, question, depth, predicateIndex)
    local tree = {kind="need", object=object, subject=subject, question=question, predicateIndex=predicateIndex}
    depth = depth or 0
    index = attachNominalAction(document, object, index, limit, depth)
    local phrase, finish = P.preposition(document, index, limit)
    if phrase and (spatialAdjuncts[phrase.rule.id] or needPurpose(phrase)) then
        tree.prepositions, index = {phrase}, finish
        if question and not subject and addresseePurpose(phrase) then tree.subject = personalSubject("you") end
    end
    if needPurposeObject(object) then
        local purpose, ending = purposeAt(document, index, limit, depth, true)
        if purpose then tree.purpose, index = purpose, ending end
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
            return needClause(document, object, finish, limit, subject, question, nil, marker)
        end
    end
end

local function requiredAction(document, tree, first, limit, depth, indirect)
    local subject, marker, actionAt, tense, negative, kind, modifier = obligationHead(document, first, limit)
    if not marker then return nil end
    if kind == "should" then
        local adverb, nextVerb = adverbAt(document, actionAt, limit)
        if modifier and adverb then return nil end
        actionAt = nextVerb or actionAt
        local action, after = verb(document, actionAt, limit, subject, true)
        if not action then return end
        local advice = {kind="clause", subject=subject, verb=action, verbIndex=actionAt,
            modal="should", modalPerfect=tense == "past", ellipticSubject=not subject, tense=tense,
            negative=negative, leadingAdverb=modifier or adverb, wh=tree.wh, where=tree.where,
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

local function ownerPredicate(document, first, limit)
    local question = P.key(document, first, limit) == "чи"
    local marker = first + (question and 1 or 0)
    local key = P.key(document, marker, limit)
    if key ~= "у" and key ~= "в" then return nil end
    local owner, index = P.pronoun(document, marker + 1, limit, "genitive", true)
    if not owner then owner, index = P.noun(document, marker + 1, limit, "genitive", false, false, true) end
    if not owner then return nil end
    local state, after = A.possessedAdjectiveAt(document, owner, index, limit, question)
    if state then return state, after end
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

function A.possessedAdjectiveAt(document, owner, first, limit, question, inherited)
    if not P.personNoun(owner) then return nil end
    local key = P.key(document, first, limit)
    local nextKey = key == "не" and P.key(document, first + 1, limit)
    local negative = key == "немає" or nextKey == "було" or nextKey == "буде"
    local marker = nextKey or key
    local markedTense = copula[marker] or (marker == "буде" or marker == "будуть") and "future"
    local tense = markedTense or "present"
    local index = first + (nextKey and negative and 2 or (negative or markedTense) and 1 or 0)
    local quantity = not negative and P.key(document, index, limit)
    local intensity = quantity == "багато" and "very" or quantity == "забагато" and "too"
        or quantity == "більше" and "more" or quantity == "стільки" and "so" or nil
    if intensity then index = index + 1 end
    local case = negative or intensity
    local state = L.choose(document, index, "noun", {case=case and "genitive" or "nominative"},
        "possessedState", function(entry)
            return entry.form.number == lexemeFrame(entry).stateNumber
        end)
    if not (state and boundary(document, index + 1, limit)) then return nil end
    local frame = lexemeFrame(state)
    if not (negative or intensity) and (key == "були" or key == "будуть") ~= (tense ~= "present"
        and frame.stateNumber == "plural") then return nil end
    local adjective = {lexeme={en=frame.possessedAdjective}, form={}}
    return {kind="clause", subject=owner, copula=true, tense=tense, inherited=inherited,
        negative=negative, question=question, adjective={entry=adjective, intensity=intensity}}, index + 1
end

local function statusWithSubject(document, first, limit)
    local question = P.key(document, first, limit) == "чи"
    local marker = first + (question and 1 or 0)
    local key = P.key(document, marker, limit)
    local negative = key == "не"
    local start = marker + (negative and 1 or 0)
    local link = P.key(document, start, limit)
    local statusTense = link == "було" and "past" or link == "буде" and "future"
    if statusTense then start = start + 1 end
    local status, afterStatus = adverbAt(document, start, limit, "predicate", function(candidate)
        return candidate.quantifiedSubject
    end)
    if status then
        local amount, finish = P.noun(document, afterStatus, limit, "nominative")
        if P.quantifiedSubject(amount) then
            local tree = {kind="clause", subject=amount, copula=true, tense=statusTense or "present", question=question,
                negative=negative or P.key(document, start, limit) == status.negativeUk, predicateAdverb=status}
            return tree, predicateTime(document, tree, finish, limit)
        end
    end
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

function A.isPolitenessMarker(adverb)
    return adverb.clausePoliteness
end

local function politeRequest(document, first, limit, english)
    local marker = english and limit or limit - 1
    local polite, after = adverbAt(document, marker, limit, nil, A.isPolitenessMarker)
    if not polite or after ~= limit + 1 then return nil end
    local last = marker - 1
    if not english and P.key(document, first, last) == "можна" then first = first + 1 end
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

function A.longLive(document, first, limit, english)
    local at = first + 1
    local actionKey = P.key(document, at, limit)
    if english then
        if actionKey ~= "live" then return nil end
    elseif actionKey ~= "живе" and actionKey ~= "живуть" then return nil end
    local subject, after = P.coordinated(document, at + 1, limit, "nominative")
    if not subject or not boundary(document, after, limit) then return nil end
    local action
    if english then action = verb(document, at, at, subject, true, nil, nil, nil, "live")
    else
        action = L.choose(document, at, "verb", {tense="present", person=3, number=subject.number},
            nil, function(candidate) return candidate.lexeme.en == "live" end)
    end
    if not action then return nil end
    return {kind="clause", optative=true, longLive=true, subject=subject, verb=action, verbIndex=at, tense="present"}, after
end

function A.optative(document, first, limit, depth, english)
    local case = english and "accusative" or "nominative"
    local subject, at = P.coordinated(document, first + 1, limit, case)
    if not subject or english and P.personNoun(subject) then return nil end
    local negative = P.key(document, at, limit) == (english and "not" or "не")
    if negative then at = at + 1 end
    local action, after = verb(document, at, limit, subject, english)
    if not action then return nil end
    local frame = lexemeFrame(action)
    local tense = action.form.tense
    if english and not frame.optative or not english and tense ~= "present" and tense ~= "future" then return nil end
    local tree = {kind="clause", optative=true, subject=subject, verb=action, verbIndex=at, negative=negative,
        tense=english and (frame.futureLemma and "future" or "present") or tense}
    local finish = complements(document, tree, after, limit, depth)
    if finish and boundary(document, finish, limit) then return tree, finish end
end

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
    local location
    if copula[key] or english and negativeCopula[key] then
        location = english and not negativeCopula[key] and at or after + 1
        if not english and P.key(document, location, limit) == "не" then location = location + 1 end
    elseif english and aux and aux.tense == "future" and P.key(document, at, limit) == "be" then
        location = at + 1
    elseif not english and not aux then
        location = at
    end
    if location then
        local place = P.preposition(document, location, limit, nil, nil, "predicate")
        if place and place.rule.subjectSense == "ability" then return subject, after end
    end
    local predicate = verb(document, at, limit, subject, aux ~= nil, nil, nil, aspect)
    local classes = predicate and lexemeFrame(predicate).subjectClasses
    if classes and classes.abilities then return subject, after end
end

function A.frontedIntransitivePredicate(document, first, limit, depth, temporalEndpoint)
    local negative = P.key(document, first, limit) == "не"
    local at = first + (negative and 1 or 0)
    local subject, after = abilityNoun(document, at + 1, limit)
    if not subject then
        local fronted = L.choose(document, at, "verb", nil, nil, function(candidate)
            local frame = lexemeFrame(candidate)
            return (frame.postposedSubject or temporalEndpoint and A.isPostposedEndpoint(candidate, frame))
                and candidate.form.tense and not candidate.form.verbalForm
        end)
        if fronted then subject, after = P.noun(document, at + 1, limit, "nominative") end
    end
    if not subject then return nil end
    local predicate, ending = verb(document, at, limit, subject, false)
    local frame = predicate and lexemeFrame(predicate)
    if not frame or not (frame.postposedSubject or frame.subjectClasses and frame.subjectClasses.abilities
            or temporalEndpoint and A.isPostposedEndpoint(predicate, frame))
        or ending ~= at + 1 then return nil end
    agreeSubject(document, subject, predicate.form)
    if frame.reverseSubjectSense then refineSubject(document, subject, frame) end
    local tree = {kind="clause", verb=predicate, subject=subject, tense=predicate.form.tense,
        negative=negative, verbIndex=at}
    local finish = complements(document, tree, after, limit, depth)
    if finish then return tree, finish end
end

function A.isPostposedEndpoint(candidate, frame)
    return candidate.form.tense == "future"
        and (candidate.form.aspect or candidate.head.aspect) == "perfective"
        and (frame.intransitive or frame.motion) and not frame.objectCase
end

local function ellipticalEvaluation(document, first, limit, depth)
    local english = document.direction == "en-uk"
    local key = P.key(document, first, limit)
    local question = not english and key == "чи" or P.key(document, limit + 1, #document.tokens) == "?"
    local start = first + (not english and key == "чи" and 1 or 0)
    local negative = P.key(document, start, limit) == (english and "not" or "не")
    if negative then start = start + 1 end
    local copularWord = start == first and key or P.key(document, start, limit)
    local tense = not english and obligationTime[copularWord]
        or english and (copularWord == "was" or negativeCopula[copularWord] == "was") and "past"
    if tense then
        start = start + 1
        negative = negative or english and negativeCopula[copularWord] ~= nil
        if not negative and P.key(document, start, limit) == (english and "not" or "не") then
            negative, start = true, start + 1
        end
    end
    local rating, predicateEnd = A.suitabilityRating(document, start, limit)
    if rating then
        local tree = {kind="clause", subject=personalSubject("it"), copula=true, tense=tense or "present",
            question=question, negative=negative, implicitSubject=true}
        local finish = A.suitabilityAt(document, tree, rating, predicateEnd, limit, depth)
        if finish then
            tree.omittedCopula = not english and tree.tense == "present" and not (question or negative) or nil
            return tree, finish
        end
    end
    local modifier, following = adverbAt(document, start, limit)
    local at = modifier and modifier.predicateModifier and following or start
    local evaluation = adverbAt(document, at, limit, "predicate")
    if not evaluation or not (evaluation.evaluativePredicate
        or evaluation.impersonalTiming and (not english or not tense)) then return nil end
    local tree = {kind="clause", subject=personalSubject("it"), copula=true, tense=tense or "present",
        question=question, negative=negative}
    local finish = predicate(document, tree, start, limit, depth)
    if finish and (tree.evaluation or evaluation.impersonalTiming) then return tree, finish end
end

local function impersonalDifficulty(document, first, limit, depth)
    local question = P.key(document, first, limit) == "чи"
    local start = first + (question and 1 or 0)
    local patient, index = P.coordinated(document, start, limit, "accusative")
    index = index or start
    local negative = P.key(document, index, limit) == "не"
    if negative then index = index + 1 end
    local tense = obligationTime[P.key(document, index, limit)]
    if tense then index = index + 1 end
    if not negative and P.key(document, index, limit) == "не" then negative, index = true, index + 1 end
    local rule, after, additive, fusedNegative = difficultyAt(document, index, limit)
    if not rule then return nil end
    local action, finish = difficultyAction(document, after, limit, depth or 0, patient ~= nil)
    if not action or patient and action.relativeCase ~= "accusative" then return nil end
    return {kind="clause", copula=true, subject=patient or personalSubject("it"), tense=tense or "present",
        implicitSubject=not patient, negative=negative or fusedNegative,
        question=question or P.key(document, limit + 1, #document.tokens) == "?",
        evaluation={rule=rule, action=action, difficulty=true, patient=patient ~= nil, additive=additive}}, finish
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

function A.collectiveReadiness(document, subject, index, limit, depth)
    if not P.hasTrait(subject, "membershipGroup") then return nil end
    local english = document.direction == "en-uk"
    if P.key(document, index, limit) == "," then index = index + 1 end
    local join = P.key(document, index, limit)
    if english and join == "and" or not english and (join == "і" or join == "й" or join == "та") then
        index = index + 1
    end
    local head = L.choose(document, index, "adj", not english and {case="nominative"} or nil, nil, function(candidate)
        return lexemeFrame(candidate).prepositionContext == "readiness"
    end)
    if not head then return nil end
    local state = {kind="clause", subject=subject, copula=true, tense="present"}
    local finish = predicate(document, state, index, limit, depth)
    if finish and finish > limit and state.infinitive then
        if not english and subject.number == "singular" and not subject.possessor and not subject.demonstrative then
            subject.article = subject.article or "indefinite"
        end
        return state, finish
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

local standaloneEvent
do
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

    local function standalonePredicateAttachment(document, first, limit, tree)
        if not ns.UDPipeModels or limit - first >= 32 then return false end
        local object = tree.object.members and tree.object.members[1] or tree.object
        if not object.headIndex then return false end
        local verbPosition = tree.verbIndex - first + 1
        local arcs = ns.Engine.UDPipe.analyzeDocument(document, first, limit, nil, nil, {[tree.verbIndex]="VERB"})
        local root = arcs and arcs[verbPosition]
        local argument = arcs and arcs[object.headIndex - first + 1]
        return root and root.relation == "root" and argument and argument.head == verbPosition
            and (argument.relation == "obj" or argument.relation == "obl" and lexemeFrame(tree.verb).lexicalPhrase)
    end

    function A.recruitmentCompanion(clause)
        for _, phrase in ipairs(clause.prepositions or {}) do
            local pronoun = phrase.object.pronoun
            if phrase.rule.id == "with" and pronoun and pronoun.id == "we" then return true end
        end
        return clause.infinitive and A.recruitmentCompanion(clause.infinitive)
    end

    standaloneEvent = function(document, first, limit, depth, key, english, sentenceQuestion)
        if depth < 3 then
            local comparison, finish = comparedEvent(document, first, limit, depth)
            if comparison then return comparison, finish end
        end
        if not english then return nil end
        local negative = key == "not"
        local index = first + (negative and 1 or 0)
        local head = P.key(document, index, limit)
        if not head then return nil end
        local separator = P.key(document, limit + 1, #document.tokens)
        local question = sentenceQuestion or separator == "?"
        local progressive = head:match("ing$") ~= nil
        if question and (progressive or not negative) then
            local addressee = personalSubject("you")
            local predicate, after = verb(document, index, limit, addressee, not progressive, false, nil,
                progressive and "present" or nil)
            local hints = predicate and lexemeFrame(predicate)
            if predicate and (progressive or hints.impersonalNeed) then
                local inquiry = {kind="clause", subject=addressee, verb=predicate, verbIndex=index, tense="present",
                    aspect=progressive and "continuous" or nil, question=true, negative=negative}
                local finish = complements(document, inquiry, after, limit, depth)
                local argument = inquiry.object or progressive and (inquiry.infinitive or inquiry.prepositions
                    or inquiry.controlled or inquiry.recipient or inquiry.delay)
                if finish and finish > limit and argument then
                    local search = separator == "?" and not negative and hints.ellipticPartnerSearch
                        and inquiry.object and not inquiry.object.raw
                    local arcs = not search and limit - first < 32
                        and ns.Engine.UDPipe.analyzeDocument(document, first, limit)
                    local root = arcs and arcs[index - first + 1]
                    if search or root and root.relation == "root" then
                        if not progressive then
                            inquiry.kind, inquiry.predicateIndex, inquiry.subject = "need", index, nil
                            for _, phrase in ipairs(inquiry.prepositions or {}) do
                                if addresseePurpose(phrase) then
                                    inquiry.subject = addressee
                                    break
                                end
                            end
                        end
                        inquiry.questionAttachment = not not root
                        return inquiry, finish
                    end
                end
            end
        end
        if not progressive then return nil end
        local entry, start = verb(document, index, limit, nil, false, false, nil, "present")
        if not entry then return nil end
        local frame = lexemeFrame(entry)
        if frame.cashComplement and separator ~= "?" then
            local offer = {kind="clause", subject=personalSubject("i"), implicitSubject=true, verb=entry,
                verbIndex=index, tense="present", aspect="continuous", negative=negative}
            local finish = complements(document, offer, start, limit, depth)
            if finish and finish > limit and (offer.object or offer.priceComplement) then return offer, finish end
        end
        local intention = frame.recruitmentIntent and not negative
        local search = frame.recruitmentSearch and separator ~= "?"
        local activity = not (intention or search or question) and frame.objectCase
        if not (intention or search or activity) then return nil end
        local following = separator and separator:match("^[.!]$") and P.key(document, limit + 2, #document.tokens)
        local question = separator == "?" and intention
        local actor = question and personalSubject("you")
            or (following == "we" or following == "i") and personalSubject(following)
        if not actor then
            for at = first - 2, math.max(1, first - 40), -1 do
                local speaker = P.key(document, at, limit)
                local stop = P.key(document, at - 1, limit)
                if (speaker == "we" or speaker == "i") and (at == 1 or stop and stop:match("^[.!?]$")) then
                    actor = personalSubject(speaker)
                    break
                end
            end
        end
        local recruitmentName = document.untranslatedRecruitmentObject
        local namedSearch = search and recruitmentName and recruitmentName.first == start
        local inferred = search and not actor and (frame.recruitmentActor or namedSearch and "i")
        local posting
        if search and not actor and not inferred then
            for at = start + 1, limit - 1 do
                if P.key(document, at, limit) == "for" then posting = true; break end
            end
        end
        local qualifiedSearch = search and not actor and not inferred and document.relativeBudget
            and frame.lexicalPhrase and frame.ellipticPartnerSearch
        if inferred then actor = personalSubject(inferred) end
        if qualifiedSearch then actor = personalSubject("i")
        elseif posting then actor = personalSubject("we") end
        if activity and not actor then actor = personalSubject("i") end
        if not intention and not actor then return nil end
        local request = {kind="clause", subject=actor, implicitSubject=not question, verb=entry, verbIndex=index,
            tense="present", aspect="continuous", intentionNote=not actor, question=question, negative=negative}
        local finish = complements(document, request, start, limit, depth)
        if not finish or finish <= limit then return nil end
        if intention and request.infinitive then return request, finish end
        if activity and request.object then
            local head = request.object.members and request.object.members[1] or request.object
            if (head.article or head.all or head.quantity or head.possessor or head.demonstrative or head.skillRequirement)
                and standalonePredicateAttachment(document, first, limit, request) then
                request.standaloneAttachment = true
                return request, finish
            end
        end
        if namedSearch and request.object and request.object.recruitmentName then return request, finish end
        if search and personNoun(request.object) then
            if posting and A.recruitmentActivity(request) then
                if qualifiedSearch then request.subject = personalSubject("we") end
                return request, finish
            end
            if qualifiedSearch then
                local qualified, groupActor
                for _, object in ipairs(request.object.members or {request.object}) do
                    local relative = object.relative
                    if relative and relative.case == "nominative" then
                        qualified = true
                        if A.recruitmentCompanion(relative.clause) then groupActor = true end
                    end
                end
                if not qualified then return nil end
                if groupActor then request.subject = personalSubject("we") end
            elseif posting then
                return nil
            end
            request.standaloneAttachment = inferred and standalonePredicateAttachment(document, first, limit, request)
            if not inferred or request.standaloneAttachment then return request, finish end
        end
    end
end

function A.recruitmentActivity(request)
    for _, phrase in ipairs(request.prepositions or {}) do
        if phrase.rule.id == "for" or phrase.rule.id == "for-recruitment-purpose" then
            for _, member in ipairs(phrase.object.members or {phrase.object}) do
                local class = P.semanticClass(member)
                if class == "operation" or class == "activities" or class == "event" or class == "session"
                    or class == "encounter" or class == "objective" then return true end
            end
        end
    end
    return false
end

function A.possessiveGot(document, index, limit, actor, elliptical)
    local object = P.noun(document, index + 1, limit, "accusative")
    if not object or elliptical and not (P.isResource(object) or P.semanticClass(object) == "equipment"
        or object.raw and ns.Engine.Markup.isLink(object.raw, "item")) then return nil end
    local nominal = object.article or object.possessor or object.demonstrative or object.sufficient or object.few
        or object.quantity or object.number == "plural" or object.pronoun or object.term or object.raw or P.mass(object)
    if nominal then return verb(document, index, limit, actor, true, nil, nil, nil, "have") end
end

function A.actionSubject(document, first, limit, depth)
    if depth >= 3 or limit - first > 20 then return nil end
    local surface = P.key(document, first, limit)
    local attached = P.key(document, first + 1, limit) == "-" and P.key(document, first + 2, limit)
    if not (surface and surface:match("ing$") or attached and attached:match("ing$")) then return nil end
    local gerund, start = verb(document, first, limit, nil, false, false, nil, "present")
    if not gerund or not lexemeFrame(gerund).eventNominal then return nil end
    local function nominalizable(action)
        local form = lexemeFrame(action.verb).eventNominal
        return form and not (action.negative or action.leadingAdverb or action.adverbs or action.infinitive
            or action.purpose or action.recipient or action.controlled or action.content or action.priceComplement)
            and (not action.object or not form.spatialObject or P.spatialContainer(action.object))
    end
    local selected, ending
    local structure = {infinitive=true, gerundComplement=true, eventSubjectPrefix=true}
    for split = start, limit do
        local head = verb(document, split, limit)
        if head and lexemeFrame(head).eventSubject then
            local action, after = complementaryInfinitive(document, first, split - 1, structure, depth)
            if action and after == split and nominalizable(action) then
                local number = "singular"
                for _, step in ipairs(action.series or {}) do
                    if not nominalizable(step.action) then action = nil; break end
                    if not step.join or step.join.id == "and" then number = "plural" end
                end
                if action then
                    local noun = lexemeFrame(action.verb).eventNominal.noun
                    local subject = {actionSubject=action, person=3, number=head.form.number or number,
                        ukNumber=number, gender=L.head(noun, "noun").gender, animacy="inanimate"}
                    if verb(document, split, limit, subject) then
                        if selected then return nil end
                        selected, ending = subject, split
                    end
                end
            end
        end
    end
    return selected, ending
end

function A.preverbalModalObject(document, first, limit, subject, negative)
    local pronoun, start = P.pronoun(document, first, limit, "accusative")
    if not pronoun then pronoun, start = P.pronoun(document, first, limit, "dative") end
    if not pronoun then return nil end
    local action, finish = verb(document, start, limit, subject, true)
    if not action then return nil end
    local frame = lexemeFrame(action)
    local case = negative and frame.negativeObjectCase or frame.objectCase
    if case and not (frame.objectPreposition or frame.intransitive or frame.motion or frame.separation) then
        local argument, after = P.pronoun(document, first, limit, case)
        if argument and after == start then return action, finish, argument, start end
    end
end

function A.frontedAbilityQuestion(document, first, limit, depth)
    local helper, subjectAt = auxiliary[P.key(document, first, limit)], first + 1
    if helper and helper.modal == "could" then
        helper, subjectAt = inflectedAbility(document, first, limit)
    end
    if not helper or not (helper.modal == "can" or helper.conditionalCould) then return nil end
    local subject, start = P.coordinated(document, subjectAt, limit, "nominative")
    if not subject or helper.person and helper.person ~= subject.person or helper.number ~= subject.number
        or helper.gender and subject.gender and helper.gender ~= subject.gender then return nil end
    local action, after = verb(document, start, limit, subject, true)
    local object, verbIndex
    if not action then action, after, object, verbIndex = A.preverbalModalObject(document, start, limit, subject) end
    if not action then return nil end
    local tree = {kind="clause", subject=subject, object=object, verb=action, verbIndex=verbIndex or start, modal=helper.modal,
        frontedModal=true, question=true, tense=helper.tense or "present"}
    local finish = complements(document, tree, after, limit, depth)
    if finish and boundary(document, finish, limit) then return tree, finish end
end

function A.omittedNeed(document, tree, first, limit, frame, depth)
    local action, finish = complementaryInfinitive(document, first, limit, frame, depth)
    if action and boundary(document, finish, limit) then
        tree.imperative, tree.infinitive, tree.tense = nil, action, "present"
        tree.question = P.key(document, limit + 1, #document.tokens) == "?"
        return tree, finish
    end
end

function A.nominalInference(document, first, limit, modal, subject, depth)
    if (modal ~= "must" and modal ~= "might" and modal ~= "could") or P.key(document, first, limit) ~= "be" then return nil end
    local tree = {kind="clause", subject=subject or personalSubject("it"), copula=true, tense="present",
        modal=modal == "must" and modal or "might", inference=modal == "must"}
    local finish = predicate(document, tree, first + 1, limit, depth)
    if finish and tree.predicate and (subject or not P.relativeAnimate(tree.predicate))
        and boundary(document, finish, limit) then return tree, finish end
end

function A.speculativePast(document, tree, index, limit, aux, subject, relativeSubject, mayOmitSubject, depth)
    local start = index
    if not aux.perfect then
        if P.key(document, start, limit) ~= "have" then return nil end
        start = start + 1
    end
    local negative = P.key(document, start, limit) == "not"
    if negative then start = start + 1 end
    local adverb, afterAdverb = adverbAt(document, start, limit)
    if adverb and tree.leadingAdverb then return nil end
    start = afterAdverb or start
    local actor = subject or relativeSubject
    local been = P.key(document, start, limit) == "been"
    if not actor then
        -- Only an impersonal state licenses a missing subject here.
        if not (mayOmitSubject and been and adverbAt(document, start + 1, limit, "predicate",
            function(candidate) return candidate.deicticEvaluation or candidate.impersonalTiming end)) then return nil end
        actor = personalSubject("it")
    end
    local action, after
    if not been then
        action, after = verb(document, start, limit, actor, false, false, nil, "past")
        if not action then return nil end
    end
    local past = {}
    for field, value in pairs(tree) do past[field] = value end
    past.subject, past.inherited = actor, not subject and relativeSubject and true or nil
    if not (subject or relativeSubject) then past.question, past.implicitSubject = nil, true end
    past.tense, past.modalPerfect = "past", true
    past.negative = tree.negative or negative
    past.leadingAdverb = tree.leadingAdverb or adverb
    local finish
    if been then
        past.copula = true
        finish = predicate(document, past, start + 1, limit, depth)
    else
        past.verb, past.verbIndex = action, start
        finish = complements(document, past, after, limit, depth)
    end
    if finish and boundary(document, finish, limit) then return past, finish end
end

function A.ellipticalPastLocation(document, first, limit, head, depth)
    if head ~= "was" and negativeCopula[head] ~= "was" then return nil end
    local phase = adverbAt(document, first + 1, limit)
    if not phase or not phase.earlierPhase then return nil end
    local tree = {kind="clause", subject=personalSubject("i"), copula=true, tense="past", negative=head ~= "was"}
    local finish = predicate(document, tree, first + 1, limit, depth)
    local place = tree.prepositions and tree.prepositions[1]
    if finish and place and spatialAdjuncts[place.rule.id] and boundary(document, finish, limit) then return tree, finish end
end

function A.omittedReporter(document, first, limit, head, depth)
    local support = auxiliary[head]
    local start = first
    if support then
        if not support.support then return nil end
        start = first + 1
        if not support.negative then
            if P.key(document, start, limit) ~= "not" then return nil end
            start = start + 1
        end
    elseif not L.phraseAt(document, first, limit, "verb") then
        return nil
    end
    local implicit = personalSubject("it")
    local impression, impressionEnd = verb(document, start, limit, implicit, support ~= nil)
    local frame = impression and lexemeFrame(impression)
    if frame and frame.implicitSubject == "it" and frame.requiresContent then
        local tree = {kind="clause", subject=implicit, implicitSubject=true, verb=impression,
            verbIndex=start, tense=support and support.tense or impression.form.tense, negative=support ~= nil}
        local finish = complements(document, tree, impressionEnd, limit, depth)
        if finish and (tree.content or tree.nominalImpression) and boundary(document, finish, limit) then return tree, finish end
    end
    if not support or head == "doesn't" or head == "doesnt" or head == "does" then return nil end
    local subject = personalSubject("i")
    local entry, after = verb(document, start, limit, subject, true)
    local allowed = entry and lexemeFrame(entry).omittedReporter
    if not allowed or not allowed[support.tense] then return nil end
    local tree = {kind="clause", subject=subject, verb=entry, verbIndex=start, tense=support.tense, negative=true}
    local finish = complements(document, tree, after, limit, depth)
    if finish and tree.content and boundary(document, finish, limit) then return tree, finish end
end

function A.impersonalAdverbContent(document, first, limit, depth)
    local negative = P.key(document, first, limit) == "не"
    local at = first + (negative and 1 or 0)
    local expression, after = adverbAt(document, at, limit, "impersonalContent", function(candidate)
        return candidate.contentPredicate ~= nil
    end)
    if not expression then return nil end
    local entry = L.choose(document, expression.contentPredicate, "verb", nil, "impersonal", function(candidate)
        return not lexemeFrame(candidate).contextOnlyReverse
    end)
    if not entry then return nil end
    local tree = {kind="clause", subject=personalSubject("it"), implicitSubject=true,
        verb=entry, verbIndex=at, tense="present", negative=negative}
    local finish = complements(document, tree, after, limit, depth)
    if finish and (tree.content or tree.nominalImpression) and boundary(document, finish, limit) then return tree, finish end
end

function A.routeQuestion(document, first, limit, depth)
    local cue, start = adverbAt(document, first, limit, "routeQuestion", function(entry) return entry.routeQuestion end)
    if not cue then return nil end
    local english = document.direction == "en-uk"
    local motion
    if english and depth < 3 and auxiliary[P.key(document, start, limit)] then
        local question, finish = simple(document, start, limit, nil, depth + 1, nil, nil, true)
        if question and question.question and question.verb and lexemeFrame(question.verb).motion
            and boundary(document, finish, limit) then
            question.where = "destination"
            for _, phrase in ipairs(question.prepositions or {}) do
                if phrase.rule.id == "from" then phrase.targetUk = phrase.rule.literalTargetUk end
            end
            return question, finish
        end
    elseif not english then
        local action, after = verb(document, start, limit, nil, true)
        if action and lexemeFrame(action).motion then motion, start = action, after end
    end
    if start > limit then return {kind="routeQuestion", question=true, cue=cue, routeMotion=motion}, start end
    local place, after = P.preposition(document, start, limit, true)
    if not place or after <= limit or not (place.rule.id == "to" or place.rule.id == "from") then return nil end
    if english then place.targetUk = place.rule.literalTargetUk
    else place.englishArticle = "definite" end
    return {kind="routeQuestion", question=true, cue=cue, prepositions={place}, routeMotion=motion}, after
end

function A.modalPredicateAt(document, first, limit)
    local start = first + (P.key(document, first, limit) == "not" and 1 or 0)
    local _, after = adverbAt(document, start, limit)
    start = after or start
    return P.key(document, start, limit) == "be" or hasVerbForm(document, start, limit, {mood="base"})
end

function A.impersonalModalPassive(document, first, limit, depth, sentenceQuestion)
    local question = P.key(document, first, limit) == "чи"
    local start = first + (question and 1 or 0)
    local cue = P.key(document, start, limit)
    if cue ~= "можна" and cue ~= "неможливо" then return nil end
    local past = P.key(document, start + 1, limit) == "було"
    local at = start + (past and 2 or 1)
    local patient, after = P.coordinated(document, at + 1, limit, "accusative")
    if not patient then patient, after = P.pronoun(document, at + 1, limit, "accusative", true) end
    if not patient then return nil end
    local action = L.choose(document, at, "verb", {mood="infinitive"}, nil, function(candidate)
        local frame = lexemeFrame(candidate)
        return frame.passiveVoice and not frame.objectPreposition
            and (not frame.animateObject or personNoun(patient))
    end)
    if not action then return nil end
    local tree = {kind="clause", subject=patient, verb=action, verbIndex=at, aspect="passive",
        modal=past and "could" or "can", negative=cue == "неможливо", question=question or sentenceQuestion}
    local finish = complements(document, tree, after, limit, depth)
    if finish and boundary(document, finish, limit) then return tree, finish end
end

function A.locativeName(document, first, limit, fronted, establishedEnd)
    local english = document.direction == "en-uk"
    local startsWithCapital = ns.Engine.Parser.startsWithCapital
    local index = first + (P.key(document, first, limit) == "the" and 1 or 0)
    local tokens = document.tokens
    if not startsWithCapital(document.text, tokens[index]) then return nil end

    local ending, unrecognized
    local bound = math.min(limit, first + 7)
    while index <= bound do
        local key = P.key(document, index, limit)
        if english and not fronted and (copula[key] or negativeCopula[key]) then break end
        if startsWithCapital(document.text, tokens[index]) then
            ending = index + 1
            if not unrecognized and #L.at(document, index) == 0 then unrecognized = true end
        elseif not ending or not (key == "of" or key == "the" or key == "de" or key == "з" or key == "із") then
            break
        end
        index = index + 1
    end
    if not (ending and unrecognized) or establishedEnd and ending <= establishedEnd then return nil end

    local marker = P.key(document, ending, limit)
    local gender, plural
    if english then
        marker = fronted or negativeCopula[marker] or marker
        if not (copula[marker] and marker ~= "am") then return nil end
        plural = marker == "are" or marker == "were"
    else
        if not fronted and ending <= limit and not copula[marker] then
            local time, after = adverbAt(document, ending, limit)
            if not (time and time.time and boundary(document, after, limit)) then return nil end
        end
        gender = fronted or ukCopulaAgreement[marker]
        plural = gender == "plural"
    end
    return {raw=P.raw(document, first, ending - 1), person=3,
        number=plural and "plural" or "singular", gender=not plural and gender or nil}, ending
end

function A.personalNaming(document, first, limit, english, key)
    local subject, index, question, marker, past, negative
    if english then
        if key == "name's" then
            subject, index = personalSubject("i"), first + 1
        else
            local start = first
            if key == "what's" then
                question, start = true, first + 1
            elseif key == "what" then
                marker = P.key(document, first + 1, limit)
                if marker ~= "is" and marker ~= "was" then return nil end
                question, past, start = true, marker == "was", first + 2
            end
            marker = P.key(document, start + 1, limit)
            if marker ~= "name" and (question or marker ~= "name's") then return nil end
            subject, index = P.pronoun(document, start, start, "possessive", true)
            if not subject or index ~= start + 1 then return nil end
            index = index + 1
            if not question and marker == "name" then
                local copulaKey = P.key(document, index, limit)
                local base = negativeCopula[copulaKey] or copulaKey
                if base ~= "is" and base ~= "was" then return nil end
                past, negative, index = base == "was", copulaKey ~= base, index + 1
            end
        end
        if not question and not negative and P.key(document, index, limit) == "not" then
            negative, index = true, index + 1
        end
    else
        question = key == "як"
        local start = first + (question and 1 or 0)
        local cue = P.key(document, start + 1, limit)
        local verbAt = start + 1 + (cue == "не" and 1 or 0)
        marker = P.key(document, verbAt, limit)
        if marker ~= "звати" and marker ~= "звуть" and marker ~= "звали" then return nil end
        subject, index = P.pronoun(document, start, start, "accusative", true)
        if not subject or index ~= start + 1 then return nil end
        past, negative, index = marker == "звали", cue == "не", verbAt + 1
        if not question and not negative and P.key(document, index, limit) == "не" then
            negative, index = true, index + 1
        end
    end
    if not subject.pronoun.en.possessive then return nil end
    local name, after
    if question then
        if negative or not boundary(document, index, limit) then return nil end
        after = index
    else
        name, after = P.openName(document, index, limit)
        if not name or not boundary(document, after, limit) then return nil end
    end
    return {kind="clause", subject=subject, question=question, naming={name=name, past=past, negative=negative}}, after
end

function A.addressAt(document, first, limit, allowPerson, requireTitle)
    if first > limit then return nil end
    local noun, after = P.noun(document, first, limit, "vocative", false, nil, true)
    if not noun or noun.article or noun.quantity or noun.demonstrative then return nil end
    local frame = noun.entry and lexemeFrame(noun.entry) or noun.term and noun.term.features
    local title = frame and frame.addressTitle
    local explicit = frame and frame.directAddress or noun.term and noun.term.category == "addresses"
    if requireTitle and not title or not (title or explicit or allowPerson and P.personNoun(noun)) then return nil end
    if title and after <= limit then
        local name, finish = P.openName(document, after, limit)
        if name and finish > limit then
            noun.addressName, noun.addressTitle = name, title
            return noun, finish
        end
    end
    if after > limit then
        noun.addressTitle = title
        return noun, after
    end
end

simple = function(document, first, limit, previous, depth, indirect, objectGap, sentenceQuestion, locativeGap)
    if document.checkpoint then document.checkpoint() end
    local english = document.direction == "en-uk"
    local key = P.key(document, first, limit)
    if not english and not (indirect or objectGap or sentenceQuestion) then
        local tense = key == "є" and "present" or key == "було" and "past"
        if tense and P.key(document, first + 1, limit) == "як" and P.key(document, first + 2, limit) == key
            and boundary(document, first + 3, limit) and P.key(document, limit + 1, #document.tokens) ~= "?" then
            return {kind="clause", subject=personalSubject("it"), situationAcceptance=true, copula=true, tense=tense}, first + 3
        end
    end
    if not (previous or indirect or objectGap) then
        local naming, finish = A.personalNaming(document, first, limit, english, key)
        if naming then return naming, finish end
    end
    if not english and not (indirect or objectGap) and (key == "чи" or key == "можна" or key == "неможливо") then
        local tree, finish = A.impersonalModalPassive(document, first, limit, depth, sentenceQuestion)
        if tree then return tree, finish end
    end
    if not english and not (indirect or objectGap) and previous and previous.analyticFuture and previous.subject then
        local negative = key == "не"
        local start = first + (negative and 1 or 0)
        local adverb, afterAdverb = adverbAt(document, start, limit)
        start = afterAdverb or start
        local entry, after = verb(document, start, limit, previous.subject, true)
        if entry then
            local action = {kind="clause", subject=previous.subject, inherited=true, verb=entry, verbIndex=start,
                tense="future", analyticFuture=true, sharedFuture=true, negative=negative, leadingAdverb=adverb}
            local finish = complements(document, action, after, limit, depth)
            if finish and boundary(document, finish, limit) then return action, finish end
        end
    end
    if not previous and not indirect then
        local audience, audienceEnd = P.welcomeAudience(document, first, limit)
        if audience and audienceEnd > limit then return {kind="welcoming", audience=audience}, audienceEnd end
        local welcome = L.choose(document, limit, "adj", not english and {case="nominative", number="plural"} or nil,
            "welcomingState")
        local welcomeOpening = not english and L.choose(document, first, "adj", {case="nominative", number="plural"},
            "welcomingState")
        if english and welcome or welcomeOpening then
            local participantCase = english and "nominative" or "dative"
            local participant, after = P.noun(document, first + (welcomeOpening and 1 or 0), limit, participantCase)
            if participant and P.relativeAnimate(participant) then
                local interests, finish = P.preposition(document, after, limit, nil, nil, "socialInterests")
                if interests and interests.rule.id == "for-social-interest" and finish == limit + (english and 0 or 1) then
                    return {kind="welcoming", recipient=participant, interests=interests}, limit + 1
                end
            end
        end
        if welcome then
            local welcomeCase = english and "nominative" or "dative"
            local welcomed, welcomeAt = P.pronoun(document, first, limit, welcomeCase, true, true)
            if not welcomed then welcomed, welcomeAt = P.coordinated(document, first, limit, welcomeCase) end
            if welcomed and (welcomed.pronoun or P.relativeAnimate(welcomed)
                or welcomed.members and P.relativeAnimate(welcomed.members[1])) then
                local marker = P.key(document, welcomeAt, limit)
                local present = not english or marker == (welcomed.number == "plural" and "are"
                    or welcomed.person == 1 and "am" or welcomed.person == 2 and "are" or "is")
                if present or welcomeAt == limit then
                    local at = welcomeAt + (english and present and 1 or 0)
                    local adverb, nextAt = adverbAt(document, at, limit, nil, function(item) return item.recurring or item.location end)
                    at = nextAt or at
                    local negative = P.key(document, at, limit) == (english and "not" or "не")
                    if at + (negative and 1 or 0) == limit then
                        return {kind="welcoming", recipient=welcomed, welcomeAdverb=adverb, negative=negative}, limit + 1
                    end
                end
            end
        end
        if P.exclusionMarker(document.direction, key) then
            local items, after = P.coordinated(document, first + 1, limit, english and "nominative" or "genitive")
            local following = after and after + (P.key(document, after, limit) == "," and 1 or 0)
            if items and (after > limit or P.exclusionMarker(document.direction, P.key(document, following, limit))
                or P.nominalRestriction(document, following, limit)) then
                local head = items.members and items.members[1] or items
                local marker = head.number == "plural" and "жодних" or head.gender == "feminine" and "жодної" or "жодного"
                if english or marker == key then return {kind="nounPhrase", subject=items, exclusion=marker}, after end
            end
        end
        local token = document.tokens[first]
        local labelEnd = first
        if first < limit and token and token.protected and P.raw(document, first, first):match("^%[[^%[%]]+%]$")
            and document.tokens[first + 1] and document.tokens[first + 1].protected then
            labelEnd = first + 1
        end
        local labelToken = document.tokens[labelEnd]
        if labelToken and labelToken.protected and not labelToken.linkKind then
            local label = P.raw(document, first, labelEnd)
            if P.raw(document, labelEnd, labelEnd):match("^<[^<>]+>$") then
                local separator = P.key(document, labelEnd + 1, limit)
                local opening = labelEnd + ((separator == "—" or separator == ":") and 2 or 1)
                if english and not objectGap then
                    local guild = {raw=label, number="singular", gender="feminine", person=3}
                    local entry, start = verb(document, opening, limit, guild, false)
                    local progressive
                    if not entry then
                        entry, start = verb(document, opening, limit, guild, false, false, nil, "present")
                        progressive = entry ~= nil
                    end
                    if entry and lexemeFrame(entry).recruitmentSearch then
                        local search = {kind="clause", subject=guild, verb=entry, verbIndex=opening,
                            tense=progressive and "present" or entry.form.tense, aspect=progressive and "continuous" or nil}
                        local finish = complements(document, search, start, limit, depth)
                        if finish == limit + 1 and search.object and P.relativeAnimate(search.object) then
                            return search, finish
                        end
                    end
                end
                local start = opening + (english and separator == "is" and 1 or 0)
                local description, ending = P.noun(document, start, limit, "nominative")
                if description and description.number == "singular" and P.hasTrait(description, "membershipGroup") then
                    if not boundary(document, ending, limit) then
                        local audience, after = P.preposition(document, ending, limit)
                        if audience and audience.rule.id == "for" and P.personNoun(audience.object)
                            and boundary(document, after, limit) then
                            description.prepositions = description.prepositions or {}
                            description.prepositions[#description.prepositions + 1] = audience
                            ending = after
                        end
                    end
                    if boundary(document, ending, limit) then
                        return {kind="nounPhrase", subject=description, descriptionLabel=label}, ending
                    end
                end
            end
        end
        local greeting, afterGreeting = adverbAt(document, first, limit, nil, function(candidate)
            return candidate.salutation or candidate.directAddress
        end)
        if greeting and greeting.salutation and afterGreeting > limit then
            return {kind="adverbPhrase", expression=greeting}, afterGreeting
        end
        local casualGreeting = english and (key == "hello" or key == "hellooo" or key == "hi" or key == "hey")
        if casualGreeting or greeting or not english and key == "вітаю" then
            local start = afterGreeting or first + 1
            if P.key(document, start, limit) == "," then start = start + 1 end
            local fellow = english and start < limit and P.key(document, start, limit) == "fellow"
                or not english and P.key(document, start, limit) == "друзі" and P.key(document, start + 1, limit) == "-"
            if english and fellow then
                local idiom, finish = P.noun(document, start, limit, "nominative", false, nil, true)
                if idiom and finish > limit and idiom.term and not idiom.adjectives and P.personNoun(idiom) then
                    return {kind="greeting", recipient=idiom, expression=greeting}, finish
                end
            end
            if english or fellow or greeting then
                if fellow then start = start + (english and 1 or 2) end
                local addressee, finish = A.addressAt(document, start, limit, true)
                if not addressee and casualGreeting and not fellow then
                    addressee, finish = P.noun(document, start, limit, "nominative")
                elseif not addressee and not english and greeting and greeting.directAddress then
                    local pronoun, after = P.pronoun(document, start, limit, "nominative", true)
                    if pronoun and pronoun.person == 2 then addressee, finish = pronoun, after end
                end
                if addressee and finish > limit then
                    return {kind="greeting", recipient=addressee, expression=greeting, fellowAddress=fellow}, finish
                end
            end
        end
        local price, finish = gradedAdverbAt(document, first, limit, "price")
        if price and finish > limit and (price.intensified or finish > first + 1 or not english) then
            return {kind="adverbPhrase", expression=price}, finish
        end
        if not objectGap then
            local event, ending = standaloneEvent(document, first, limit, depth, key, english, sentenceQuestion)
            if event then return event, ending end
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
    local tradeOpeners = ns.Linguistics.grammar.tradeOpeners
    local trade = english and not indirect and not objectGap and tradeOpeners and tradeOpeners[key]
    if trade then
        local at = first + (P.key(document, first + 1, limit) == ":" and 1 or 0)
        local subject = personalSubject("i")
        local entry, start = verb(document, at, limit, subject, true, nil, nil, nil, trade)
        if not entry then return nil end
        local tree = {kind="clause", subject=subject, implicitSubject=true, tense="future", verb=entry, sequencedEvent=true}
        local finish = complements(document, tree, start, limit, depth)
        if not finish or not tree.object then return nil end
        local linkedItem
        for _, item in ipairs(tree.object.members or {tree.object}) do
            if item.raw then
                if not ns.Engine.Markup.isLink(item.raw, "item") then return nil end
                linkedItem = true
            end
        end
        if finish <= limit and not tree.priceComplement and (not linkedItem or tree.object.quantity) then
            local grammar = ns.Engine.Grammar
            local price, after = grammar.moneyAt(document, finish, limit)
            if price then
                local basis, ending = grammar.priceBasisAt(document, after, limit)
                if ending > limit then tree.priceComplement, finish = {amount=price, basis=basis}, ending end
            end
        end
        return tree, finish
    end
    if depth < 3 and not indirect then
        local social, finish = socialComplement(document, first, limit, depth)
        if social then return social, finish end
    end
    if not (previous or indirect or objectGap) and (english and key == "long"
        or not english and (key == "нехай" or key == "хай")) then
        local wish, finish = A.longLive(document, first, limit, english)
        if wish then return wish, finish end
    end
    if not (previous or indirect or objectGap) and (english and key == "let"
        or not english and (key == "нехай" or key == "хай")) then
        local wish, finish = A.optative(document, first, limit, depth, english)
        if wish then return wish, finish end
    end
    if not indirect and (not english or englishHortative[key]) then
        local proposal, endAt = hortative(document, first, limit, depth, english, key)
        if proposal then return proposal, endAt end
    end
    if not (previous or indirect or objectGap) and P.key(document, limit + 1, #document.tokens) == "!" then
        local address, finish = A.addressAt(document, first, limit)
        if address then
            return {kind="greeting", recipient=address, bareAddress=true}, finish
        end
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
    if english and limit - first <= 1 and not (previous or indirect or objectGap)
        and P.key(document, limit + 1, #document.tokens) == "?" then
        local negative = key == "not"
        local start = first + (negative and 1 or 0)
        local modifier, after
        if start < limit then modifier, after = adverbAt(document, start, limit) end
        if (after or start) == limit then
            local action, finish = verb(document, limit, limit, nil, false, false, nil, "passive")
            if action and lexemeFrame(action).passiveUk then
                return {kind="clause", subject=personalSubject("it"), implicitSubject=true, verb=action,
                    verbIndex=limit, tense="present", aspect="passive", question=true, negative=negative,
                    leadingAdverb=modifier}, finish
            end
        end
    end
    if depth < 3 then
        local initial, after = adverbAt(document, first, limit, "sentenceInitial")
        local comma = after and P.key(document, after, limit) == ","
        if initial and initial.sentenceInitial and (english or not initial.ukInitialRequiresComma or comma) then
            if comma then after = after + 1 end
            local tree, finish = simple(document, after, limit, previous, depth + 1, indirect)
            if tree and not tree.sentenceAdverb then
                local request = english and initial.tentative and tree.modal == "can"
                    and (tree.question or sentenceQuestion or P.key(document, limit + 1, #document.tokens) == "?")
                    and tree.subject and tree.subject.pronoun and tree.subject.pronoun.id == "someone"
                if request then
                    tree.question = true
                    local frame = tree.verb and lexemeFrame(tree.verb)
                    if frame and frame.ellipticRequest and not recurringEvent(tree) then
                        tree.taskInfinitiveLemma = tree.taskInfinitiveLemma or frame.purposeLemma or frame.infinitiveLemma or frame.imperative
                    end
                else tree.sentenceAdverb = initial end
                return tree, finish
            end
        end
    end
    local prohibition = english and key == "no" and P.key(document, limit, limit) == "allowed"
        or not english and key == "під" and P.key(document, first + 1, limit) == "забороною"
    if prohibition then
        local objectFirst = first + (english and 1 or 2)
        local objectEnd = limit - (english and 1 or 0)
        local object, after = P.coordinated(document, objectFirst, objectEnd, "nominative", nil, nil, "predicate")
        if object and after > objectEnd then return {kind="prohibition", object=object}, limit + 1 end
    end
    if english and key == "no" then
        local object, after = P.coordinated(document, first + 1, limit, "nominative")
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
        local plural = object and object.number == "plural"
        if object and (plural and (requirement == "are" or requirement == "were")
            or not plural and (requirement == "is" or requirement == "was")) then
            local at = after + 1
            local action, finish = verb(document, at, limit, object, false, false, nil, "passive")
            if action then
                local tree = {kind="clause", subject=object, verb=action, verbIndex=at,
                    tense=copula[requirement], aspect="passive", negative=true, objectGap=objectGap}
                local ending = complements(document, tree, finish, limit, depth)
                if ending then return tree, ending end
            end
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
    if not english and (key == "можливо" or key == "напевно") and P.key(document, first + 1, limit) == "," and depth < 3 then
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
        if tree and finish and tree.kind == "clause" and (tree.tense == "present" or tree.tense == "past" or prospective) and tree.subject
            and not tree.modal and not tree.imperative and not tree.where and not tree.why and not tree.aspect then
            if tree.copula and (tree.predicate or tree.predicateAdverb and tree.predicateAdverb.deicticEvaluation)
                and tree.subject.pronoun and tree.subject.pronoun.id == "this" then
                tree.subject = personalSubject("it")
            end
            if key == "напевно" then
                if not (tree.tense == "present" and tree.copula and tree.predicate) then return nil end
                tree.modal, tree.inference = "must", true
            else
                tree.modal = "might"
                tree.modalPerfect = tree.tense == "past" or nil
            end
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
        special, after = A.routeQuestion(document, first, limit, depth)
        if special then return special, after end
        special, after = existential(document, first, limit, depth, sentenceQuestion)
        if special then return special, after end
    end
    if not english and needAgreement[key] then
        local object, finish = P.coordinated(document, first + 1, limit, "nominative")
        local agreement = object and (object.number == "plural" and "plural" or object.gender)
        if agreement == needAgreement[key] then
            local question = P.key(document, limit + 1, #document.tokens) == "?"
            return needClause(document, object, finish, limit, nil, question, depth, first)
        end
    end
    if not english and not indirect then
        special, after = A.impersonalAdverbContent(document, first, limit, depth)
        if special then return special, after end
        special, after = impersonalDifficulty(document, first, limit, depth)
        if special then return special, after end
        special, after = personalNeed(document, first, limit)
        if special then return special, after end
        special, after = benefitClause(document, first, limit)
        if special then return special, after end
        special, after = ownerPredicate(document, first, limit)
        if special then return special, after end
        special, after = statusWithSubject(document, first, limit)
        if special then return special, after end
        special, after = A.frontedIntransitivePredicate(document, first, limit, depth)
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
    elseif key == "where" or key == "де" or key == "куди" then
        tree.where, tree.question, index = key == "куди" and "destination" or true, not indirect, index + 1
    elseif key == "why" or key == "чому" then
        tree.why, tree.question, index = true, not indirect, index + 1
    elseif key == "when" or key == "коли" then
        tree.when, tree.question, index = true, not indirect, index + 1
    elseif key == "чи" and not english then
        tree.question, index = true, index + 1
    end
    if not english then
        if not (indirect or previous or objectGap or tree.wh or tree.where or tree.why or tree.when)
            and (tree.question or sentenceQuestion or P.key(document, limit + 1, #document.tokens) == "?") then
            local ability, finish = A.frontedAbilityQuestion(document, index, limit, depth)
            if ability then return ability, finish end
        end
        local requirement, finish = requiredAction(document, tree, index, limit, depth, indirect)
        if requirement then return requirement, finish end
    end
    if not english and (tree.when or wh and wh.kind == "clock" or key == "чи" and not indirect) then
        local negative = key == "чи" and P.key(document, index, limit) == "не"
        local at = index + (negative and 1 or 0)
        if key ~= "чи" or not ukCopulaAgreement[P.key(document, at, limit)] then
            local actor, afterActor = P.coordinated(document, at + 1, limit, "nominative")
            local action, afterVerb
            if actor then action, afterVerb = verb(document, at, limit, actor, false) end
            if action and afterVerb == at + 1 then
                local fronted = {kind="clause", subject=actor, verb=action, verbIndex=at, negative=negative,
                    tense=action.form.tense or "present", wh=wh, when=tree.when, question=not indirect}
                local finish = complements(document, fronted, afterActor, limit, depth)
                if finish and (key ~= "чи" or boundary(document, finish, limit)) then return fronted, finish end
            end
        end
    end
    local headIndex = index
    local syntheticAux = wh and wh.auxiliary
    local head = syntheticAux or P.key(document, index, limit)
    if english and index == first then
        if not (previous or indirect or objectGap or sentenceQuestion)
            and P.key(document, limit + 1, #document.tokens) ~= "?" then
            local reported, finish = A.omittedReporter(document, index, limit, head, depth)
            if reported then return reported, finish end
            local state, after = A.ellipticalPastLocation(document, index, limit, head, depth)
            if state then return state, after end
            local inference, finish = A.nominalInference(document, index + 1, limit, head, nil, depth)
            if inference then return inference, finish end
        end
        local commandStart
        if auxiliary[head] == auxiliary["don't"] then commandStart = index + 1
        elseif head == "do" and P.key(document, index + 1, limit) == "not" then commandStart = index + 2 end
        if not commandStart and head == "do" and not previous and not tree.question
            and P.key(document, limit + 1, #document.tokens) ~= "?" then
            local command, afterVerb = verb(document, index, limit, nil, true, true)
            if command then
                local action = {kind="clause", verb=command, verbIndex=index, imperative=true, tense="present"}
                local finish = complements(document, action, afterVerb, limit, depth)
                if action.object and finish == limit + 1 then return action, finish end
            end
        end
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
    local aux, unmarkedPermission
    if english then
        aux = auxiliary[head]
        if head == "may" and index == first then
            local ending = P.key(document, limit + 1, #document.tokens)
            if ending == "?" then aux = permission
            elseif not ending then aux, unmarkedPermission = permission, true end
        end
    end
    local questionSubject = wh and wh.role == "subject"
    local syntheticCopula = wh and wh.copula
    local invertedCopula = syntheticCopula or negativeCopula[head] or head
    local perfectHead = negativePerfect[head] or head
    local invertedPerfect = have[perfectHead] and perfectHead
    local relativeSubject = indirect and previous and previous.subject
    local continuedAux = english and previous and previous.subject and aux
        and verb(document, index + 1, limit, previous.subject, true, nil, nil, nil, nil, previous)
    if not continuedAux and english and previous and previous.subject and invertedPerfect then
        local lexical, after = verb(document, index, limit, previous.subject, false)
        continuedAux = lexical and after > index + 1 and lexemeFrame(lexical).requiredInfinitive
    end
    local inverted = english and not questionSubject and not relativeSubject and not continuedAux
        and (aux or copula[invertedCopula] or invertedPerfect)
    if inverted then
        tree.question = true
        if not aux and not invertedPerfect then
            tree.copula, tree.tense, tree.negative = true, copula[invertedCopula], negativeCopula[head] ~= nil
        end
        if not syntheticCopula and not syntheticAux then index = index + 1 end
    end
    local frontedNegative = not english and head == "не"
    local frontedHead = frontedNegative and P.key(document, index + 1, limit) or head
    local frontedCopula = not english and tree.question and ukCopulaAgreement[frontedHead]
    if frontedCopula then
        tree.copula, tree.tense, tree.negative = true, copula[frontedHead], frontedNegative or nil
        index = index + (frontedNegative and 2 or 1)
    end
    local subject, nextIndex
    local contraction = english and not inverted and contracted[head]
    if english and not inverted and head == "its" then
        local start = index + 1
        local following = P.key(document, start, limit)
        if following == "not" then start = start + 1 end
        local _, afterModifier = adverbAt(document, start, limit, nil, function(entry) return entry.predicateModifier end)
        local at = afterModifier or start
        local timing = adverbAt(document, at, limit, "predicate", function(entry) return entry.impersonalTiming end)
        local article = following == "a" or following == "an" or following == "the"
        local relative = following == "what" and not P.noun(document, index, limit, "nominative")
        if article or relative or (timing or L.choose(document, at, "adj")) and not P.noun(document, index, limit, "nominative") then
            contraction = contracted["it's"]
        end
    end
    if english and not inverted and not contraction and head then
        local id = head:match("^(%a+)'d$")
        local actor = id and personalSubject(id)
        if actor then
            local start = index + (P.key(document, index + 1, limit) == "not" and 2 or 1)
            local _, afterAdverb = adverbAt(document, start, limit)
            start = afterAdverb or start
            local base = verb(document, start, limit, actor, true) or A.conditionalDesireAt(document, start, limit, actor)
            if not base and verb(document, start, limit, actor, false, false, nil, "past") then
                contraction = {id, "had"}
            elseif (base or P.key(document, start, limit) == "be")
                and P.key(document, start, limit) ~= "better" then
                contraction = {id, "would"}
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
    local mayOmitSubject = inverted and aux and not wh and headIndex == first
        and not (previous or indirect or objectGap or sentenceQuestion or P.key(document, limit + 1, #document.tokens) == "?")
    local omittedBenefitSubject = mayOmitSubject and not aux.negative and aux.modal == "could"
        and P.key(document, index, limit) == "use"
    local omittedDesireSubject = mayOmitSubject and not aux.negative and aux.ability == "conditional"
        and A.conditionalDesireAt(document, index + (P.key(document, index, limit) == "not" and 1 or 0),
            limit, personalSubject("i"))
    if questionSubject then
        subject = english and wh.noun or {person=3, number="singular", gender=wh.kind == "person" and "masculine" or "neuter",
            animacy=wh.kind == "person" and "animate" or nil}
        nextIndex = index
    elseif contraction then
        subject, nextIndex = personalSubject(contraction[1]), index + 1
        if contraction[1] == "it" then tree.contractedSubjectIndex = index end
    elseif not relativeSubject and not continuedAux and not (omittedBenefitSubject or omittedDesireSubject) then
        subject, nextIndex = abilitySubject(document, index, limit)
        if not subject then
            local quantity, following = P.pronoun(document, index, limit, "nominative", nil, true)
            if quantity then
                local predicate = P.key(document, following, limit)
                if copula[predicate] or negativeCopula[predicate] or auxiliary[predicate]
                    or verb(document, following, limit, quantity)
                    or english and verb(document, following, limit, quantity, false, false, nil, "present") then
                    subject, nextIndex = quantity, following
                end
            end
        end
        if not subject and english and not inverted then
            subject, nextIndex = A.actionSubject(document, index, limit, depth)
        end
        if not subject then subject, nextIndex = P.coordinated(document, index, limit, "nominative") end
        local boundaryAt = english and not inverted and subject and subject.adjectives and subject.headIndex
        if boundaryAt and boundaryAt > index and auxiliary[P.key(document, boundaryAt, limit)]
            and A.modalPredicateAt(document, boundaryAt + 1, limit) then
            local shortened, following = P.coordinated(document, index, boundaryAt - 1, "nominative")
            if shortened and following == boundaryAt then subject, nextIndex = shortened, following end
        end
        if not subject then subject, nextIndex = A.typedPredicateSubject(document, index, limit, inverted and aux) end
        if english and not subject and (not inverted or tree.copula) then
            subject, nextIndex = A.subjectFromCopularPredicate(document, index, limit, inverted)
        end
        if tree.where == true and not (subject and (subject.pronoun or subject.raw))
            and (not english or not inverted or tree.copula) then
            local fronted = english and inverted and invertedCopula or frontedCopula
            local name, finish = A.locativeName(document, index, limit, fronted, nextIndex)
            if name then subject, nextIndex = name, finish end
        end
        local label = not subject and P.key(document, index, limit)
        if label and label:match("^%d+$") then
            local modifier, after
            if not english then
                modifier, after = adverbAt(document, index + 1, limit, nil, function(entry) return entry.predicateModifier end)
            end
            local marker = after or index + 1
            local copular = P.key(document, marker, limit)
            if copula[copular] or not english and copular == "—" then
                subject, nextIndex = {raw=label, person=3, number="singular", gender="neuter", numberLabel=true}, marker
                tree.predicateModifier = modifier
            end
        end
        if not english and not subject then
            local theme, ending = P.noun(document, index, limit, "nominative", nil, nil, nil, "selfChangeTheme")
            if theme then
                local at = ending + (P.key(document, ending, limit) == "не" and 1 or 0)
                local predicate = verb(document, at, limit, theme)
                if predicate and lexemeFrame(predicate).selfChange then subject, nextIndex = theme, ending end
            end
        end
        local pointer = subject and subject.pronoun and subject.pronoun.id
        if english and not inverted and index + 2 <= limit and (not subject or pointer == "this" or pointer == "that") then
            local event, ending = P.noun(document, index, limit, "nominative", nil, nil, nil, "recordable")
            if event and ending > (nextIndex or index) then
                local predicate = verb(document, ending, limit, event, false)
                if predicate and lexemeFrame(predicate).subjectSense == "recordable" then subject, nextIndex = event, ending end
            end
        end
    end
    local speakerModal = mayOmitSubject and (aux.modal == "can" or aux.tense == "future")
    -- A bare homograph licenses an inverted subject only when a predicate can follow it.
    if speakerModal and subject and not (subject.pronoun or subject.article or subject.possessor
        or subject.demonstrative or subject.quantity) and not A.modalPredicateAt(document, nextIndex, limit)
        and A.modalPredicateAt(document, index, limit) then
        subject = nil
    end
    local omittedModalSubject = not subject and (speakerModal or omittedBenefitSubject or omittedDesireSubject)
    if omittedModalSubject then
        subject, nextIndex = personalSubject("i"), index
        tree.implicitSubject, tree.question, inverted = true, nil, nil
    end
    if not subject and inverted and aux and aux.modal == "should" and headIndex == first and not (wh or previous or indirect)
        and P.key(document, limit + 1, #document.tokens) ~= "?" then
        tree.ellipticSubject, tree.question, inverted = true, nil, nil
    end
    local nextPredicate = subject and P.key(document, nextIndex, limit)
    if english and subject and not subject.members then
        local form = inverted and invertedCopula or negativeCopula[nextPredicate] or nextPredicate
        if form == "are" or form == "were" then P.agreeInvariantNoun(subject, "plural") end
    end
    local questionMark = sentenceQuestion
    if questionMark == nil then questionMark = P.key(document, limit + 1, #document.tokens) == "?" end
    if not english and subject and nextIndex > limit and subject.comparativeOffset
        and (subject.demonstrative or subject.possessor or tree.question or questionMark)
        and not (wh or tree.copula or indirect or objectGap) then
        tree.comparativeOffset, subject.comparativeOffset = subject.comparativeOffset, nil
        tree.subject, tree.copula, tree.tense = subject, true, "present"
        tree.question = tree.question or questionMark
        return tree, nextIndex
    end
    if not english and subject and nextIndex > limit and (tree.question or questionMark)
        and not (tree.copula or wh or tree.where or tree.why or tree.when or indirect or objectGap) then
        if subject.characterLevel then
            tree.level, subject.characterLevel = subject.characterLevel, nil
            tree.subject, tree.copula, tree.question, tree.tense = subject, true, true, "present"
            return tree, nextIndex
        end
        local phrases = subject.prepositions
        local absence = phrases and #phrases == 1 and phrases[1]
        local property = absence and absence.object.entry
        if property and absence.rule.id == "without" and lexemeFrame(property).sense == "absenceProperty" then
            -- In a polar question the final absence phrase can supply the missing predicate.
            subject.prepositions = nil
            tree.subject, tree.prepositions, tree.copula = subject, phrases, true
            tree.question, tree.tense, tree.absencePredicate = true, "present", true
            return tree, nextIndex
        end
    end
    local unmarkedQuestion = english and subject and subject.pronoun
        and (subject.pronoun.id == "someone" or subject.pronoun.indefiniteQuestion)
        and not inverted and not contraction and not wh and not indirect
        and (questionMark or nextPredicate == "wanna")
    if unmarkedQuestion and nextPredicate == "wanna" and not questionMark then
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
    if frontedCopula then
        local agreement = subject and (subject.number == "plural" and "plural" or subject.gender)
        if not subject or agreement and agreement ~= frontedCopula then return nil end
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
    if english and subject and not (inverted or aux or contraction or indirect or objectGap
        or previous or tree.question or questionMark) then
        local request, finish = A.rosterSearch(document, subject, index, limit, depth)
        if request then return request, finish end
    end
    if not english and subject and not (subject.pronoun or relativeSubject or wh or tree.question)
        and (not objectGap or type(objectGap) == "table" and objectGap.prepositional) then
        local class = P.semanticClass(subject)
        local negative = current == "не"
        local at = index + (negative and 1 or 0)
        local word = class and P.key(document, at, limit)
        if word and word:sub(-4) == "ть" then
            local action = L.choose(document, at, "verb", {tense="present", number="plural", person=3}, nil,
                function(candidate)
                    local frame = lexemeFrame(candidate)
                    return frame.anonymousPresentPassive and frame.objectClasses[class]
                end)
            if action then
                tree.verb, tree.verbIndex, tree.tense, tree.aspect = action, at, "present", "passive"
                tree.negative = negative
                local finish = complements(document, tree, at + 1, limit, depth)
                if finish then return tree, finish end
                return nil
            end
        end
    end
    local contractedNegative = negativeCopula[current] or negativePerfect[current]
    if contractedNegative then current = contractedNegative end
    if unmarkedQuestion and questionMark and current == "got" then
        local opening = P.key(document, headIndex, limit)
        if opening and opening:sub(1, 3) == "any" then
            local possession = A.possessiveGot(document, index, limit, subject, true)
            if possession then
                local state = {kind="clause", subject=subject, verb=possession, verbIndex=index,
                    tense="present", question=true, subjectLocation=tree.subjectLocation}
                local finish = complements(document, state, index + 1, limit, depth)
                if finish and boundary(document, finish, limit) and explicitTime(state) ~= "past" then return state, finish end
            end
        end
    end
    local headlessQuantity = subject and subject.pronoun and subject.pronoun.headlessQuantity
    if english and subject and not inverted and not contraction and not syntheticCopula and not indirect
        and (questionMark or headlessQuantity) then
        local ongoing, afterVerb = verb(document, index, limit, subject, false, false, nil, "present")
        if ongoing then
            tree.verb, tree.tense, tree.aspect = ongoing, "present", "continuous"
            tree.question = tree.question or questionMark
            tree.verbIndex = index
            local finish = complements(document, tree, afterVerb, limit, depth)
            if finish then return tree, finish end
            return nil
        end
    end
    -- Auxiliary selection is licensed by a participle. A possessive "have"
    -- and an ordinary copula continue through the existing paths.
    local aspectAux = inverted and (invertedPerfect or tree.copula and invertedCopula)
        or not (inverted or omittedModalSubject) and current
    if english and contraction and aspectAux == "is" then
        local following = P.key(document, index, limit)
        if following == "got" or following == "been" then aspectAux = "has" end
    end
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
    local sharedPassiveSubject = english and inverted and not (subject or relativeSubject or wh or sentenceQuestion)
        and copula[aspectAux] and previous
        and P.key(document, limit + 1, #document.tokens) ~= "?" and previous.subject
    local aspectSubject = subject or relativeSubject or sharedPassiveSubject
    local statusQuestion = english and inverted and wh and wh.kind == "manner" and copula[aspectAux]
        and not tree.negative
    local openSubjectEnd
    if statusQuestion and not aspectSubject and aspectAux ~= "am" and index < limit then
        local name, finish = P.properName(document, index, limit - 1)
        if not name then name, finish = P.openName(document, index, index) end
        if name then
            aspectSubject = {raw=name, person=3, number=(aspectAux == "are" or aspectAux == "were") and "plural" or "singular"}
            openSubjectEnd = finish
        end
    end
    if english and aspectSubject and (have[aspectAux] or copula[aspectAux]) then
        local nextVerb = openSubjectEnd or ((inverted or contraction or syntheticCopula) and index or index + 1)
        local aspect = have[aspectAux] and "past" or "present"
        local pluralPassive = copula[aspectAux] and aspectSubject.number == "plural" and not aspectSubject.all
        local allBeforeNegation = pluralPassive and P.key(document, nextVerb, limit) == "all"
        if allBeforeNegation then nextVerb = nextVerb + 1 end
        local negative = P.key(document, nextVerb, limit) == "not"
        if negative then nextVerb = nextVerb + 1 end
        local allAfterNegation = pluralPassive and not allBeforeNegation and P.key(document, nextVerb, limit) == "all"
        if allAfterNegation then nextVerb = nextVerb + 1 end
        local adverb, afterAdverb = adverbAt(document, nextVerb, limit)
        if adverb then nextVerb = afterAdverb end
        if not adverb and copula[aspectAux] and deicticSubject(aspectSubject) then
            local state, afterState = adverbAt(document, nextVerb, limit, "predicate")
            if state and state.predicateModifier then state = adverbAt(document, afterState, limit, "predicate") end
            if state and state.deicticEvaluation then
                local evaluation = {}
                for field, value in pairs(tree) do evaluation[field] = value end
                evaluation.subject, evaluation.copula, evaluation.tense = aspectSubject, true, copula[aspectAux]
                evaluation.negative = tree.negative or negative or contractedNegative ~= nil
                local finish = predicate(document, evaluation, nextVerb, limit, depth)
                if finish and evaluation.predicateAdverb and evaluation.predicateAdverb.deicticEvaluation
                    and boundary(document, finish, limit) then return evaluation, finish end
            end
        end
        local progressive, candidate, afterVerb
        local been = have[aspectAux] and P.key(document, nextVerb, limit) == "been" and nextVerb
        if been then
            local start = nextVerb + 1
            local innerAdverb, afterInner = adverbAt(document, start, limit)
            if innerAdverb and not adverb then start = afterInner end
            candidate, afterVerb = verb(document, start, limit, aspectSubject, false, false, nil, "present")
            if candidate then
                progressive, nextVerb, adverb = true, start, adverb or innerAdverb
            end
        end
        if been and not progressive then
            local state = {}
            for field, value in pairs(tree) do state[field] = value end
            state.subject, state.inherited, state.copula, state.tense = aspectSubject, not subject, true, "past"
            state.negative = tree.negative or negative or contractedNegative ~= nil
                or inverted and invertedPerfect and negativePerfect[head] ~= nil
            state.leadingAdverb = adverb
            local finish = predicate(document, state, been + 1, limit, depth)
            if finish and boundary(document, finish, limit) and not state.verb and not state.evaluation then
                if state.durationSpan then
                    state.perfectState = true
                    if aspectAux ~= "had" then state.tense = "present" end
                end
                return state, finish
            end
        end
        local resultative, passive, progressivePassive
        if not progressive then
            if copula[aspectAux] and P.key(document, nextVerb, limit) == "being" then
                local modifier, afterModifier = adverbAt(document, nextVerb + 1, limit)
                local participle = afterModifier or nextVerb + 1
                candidate, afterVerb = verb(document, participle, limit, aspectSubject, false, false, nil, "progressivePassive")
                if candidate then
                    nextVerb, passive, progressivePassive = participle, true, true
                    if modifier and adverb then tree.additionalLeadingAdverbs = {modifier} end
                    adverb = adverb or modifier
                end
            end
            if not candidate then
                candidate, afterVerb = verb(document, nextVerb, limit, aspectSubject, false, false, nil, aspect)
            end
        end
        if candidate and statusQuestion and not (passive or adverb or negative or allBeforeNegation or allAfterNegation)
            and lexemeFrame(candidate).sense == "generalAction" then
            -- A bare progressive DO with HOW asks about someone's state.
            -- An overt object or a manner modifier still belongs to the action.
            local time, finish = adverbAt(document, afterVerb, limit, nil,
                function(entry) return entry.time or entry.occurrenceAnchor end)
            finish = finish or afterVerb
            if boundary(document, finish, limit) then
                tree.subject, tree.statusInquiry, tree.statusTime = aspectSubject, true, time
                if openSubjectEnd and not document.tokens[index].protected then
                    tree.unresolved = {first=index, last=openSubjectEnd - 1, reason="unresolved-subject"}
                elseif aspectSubject.number == "plural" and (aspectAux == "is" or aspectAux == "was") then
                    local start = headIndex + (syntheticCopula and 0 or 1)
                    if start < nextVerb then
                        tree.statusSubjectText = P.raw(document, start, nextVerb - 1)
                        tree.unresolved = {first=start, last=nextVerb - 1, reason="unresolved-subject"}
                    end
                end
                return tree, finish
            end
        end
        if openSubjectEnd then return nil end
        if have[aspectAux] and aspectAux ~= "had" and not adverb and P.key(document, nextVerb, limit) == "got"
            and (not candidate or afterVerb == nextVerb + 1) then
            local possession = A.possessiveGot(document, nextVerb, limit, aspectSubject)
            if possession then
                tree.subject, tree.inherited = aspectSubject, not subject
                tree.copula, tree.verb, tree.tense = nil, possession, "present"
                tree.verbIndex, tree.negative = nextVerb, negative or contractedNegative ~= nil
                local finish = complements(document, tree, nextVerb + 1, limit, depth)
                if finish then return tree, finish end
                return nil
            end
        end
        if not candidate and copula[aspectAux] then
            candidate, afterVerb = verb(document, nextVerb, limit, aspectSubject, false, false, nil, "resultative")
            resultative = candidate ~= nil
            if not candidate then
                candidate, afterVerb = verb(document, nextVerb, limit, aspectSubject, false, false, nil, "passive")
                passive = candidate ~= nil
            end
        end
        if candidate and (passive or not (allBeforeNegation or allAfterNegation))
            and (not inverted or wh or candidate.lexeme.frame) then
            if sharedPassiveSubject then
                if not passive then return nil end
                tree.question = nil
            end
            tree.subject, tree.inherited = aspectSubject, not subject
            tree.copula, tree.verb = nil, candidate
            tree.verbIndex = nextVerb
            tree.negative = tree.negative or negative or contractedNegative ~= nil
                or inverted and invertedPerfect and negativePerfect[head] ~= nil
            if allBeforeNegation or allAfterNegation then
                tree.allSubject, tree.allUnderNegation = true, allAfterNegation and tree.negative
            end
            if progressive then
                tree.tense = aspectAux == "had" and "past" or "present"
                tree.aspect, tree.perfectProgressive = "continuous", true
            else
                tree.tense = (have[aspectAux] or resultative) and "past" or copula[aspectAux]
                tree.aspect = passive and "passive" or resultative and "resultative"
                    or have[aspectAux] and "perfect" or "continuous"
                tree.progressivePassive = progressivePassive
                tree.presentPerfect = tree.aspect == "perfect" and aspectAux ~= "had"
            end
            if adverb then tree.leadingAdverb = adverb end
            local finish = complements(document, tree, afterVerb, limit, depth)
            if finish then return tree, finish end
            return nil
        end
    end
    if inverted and invertedPerfect then return nil end
    if not (inverted or omittedModalSubject) then
        if copula[current] then
            tree.copula, tree.tense, tree.negative = true, copula[current], contractedNegative ~= nil
            if not contraction and not syntheticCopula then index = index + 1 end
        elseif auxiliary[current] or english and current == "may" then
            local helper = auxiliary[current] or auxiliary.might
            local operand = index + 1
            if not english and helper.modal == "could" then
                local inflected, after = inflectedAbility(document, index, limit)
                if inflected then helper, operand = inflected, after end
            end
            local lexical = english and helper.support and not helper.negative and not contraction
                and P.key(document, operand, limit) ~= "not"
                and (P.key(document, operand, limit) == "so" and not verb(document, operand + 1, limit, subject, true)
                    or P.noun(document, operand, limit, "accusative"))
                and not verb(document, operand, limit, subject, true)
            if not lexical then
                aux = helper
                if not contraction then index = operand end
            end
        end
    end
    if not english and subject then
        if not (aux or tree.copula) then
            local span, afterSpan = P.durationSpan(document, index, limit, true)
            if span then tree.durationSpan, index = span, afterSpan end
        end
        local time, after = adverbAt(document, index, limit)
        if time and time.time and P.key(document, after, limit) == "не" then
            tree.adverbs, index = {time}, after
        end
    end
    if not english then
        local modifier, following = adverbAt(document, index, limit, nil, function(candidate)
            return candidate.preNegative or candidate.sentenceInitial
        end)
        if modifier and P.key(document, following, limit) == "не" then
            tree.leadingAdverb, index = modifier, following
        end
    end
    if not english and not (aux or tree.copula) and A.conditionalParticleAt(document, index, limit) then
        local helper, following = inflectedAbility(document, index, limit)
        if helper then aux, index = helper, following
        else tree.conditional, index = true, index + 1 end
    end
    local negative = P.key(document, index, limit)
    if negative == "not" or negative == "не" then
        tree.negative, index = true, index + 1
    end
    if not english and subject and (tree.negative or tree.conditional) and not tree.copula then
        local tense = copula[P.key(document, index, limit)]
        if tense and (not tree.conditional or tense == "past") then
            tree.copula, tree.tense, index = true, tense, index + 1
        end
    end
    if not english and tree.copula and tree.tense == "past" and A.conditionalParticleAt(document, index, limit) then
        if tree.conditional then return nil end
        if P.key(document, index - 1, limit) == "був" and P.key(document, index + 1, limit) == "/"
            and P.key(document, index + 2, limit) == "була" and A.conditionalParticleAt(document, index + 3, limit) then
            index = index + 3
        end
        tree.conditional, index = true, index + 1
    end
    if not english and not aux then
        local helper = auxiliary[P.key(document, index, limit)]
        local inflected, following
        if not tree.copula and (not helper or helper.modal == "could") then
            inflected, following = inflectedAbility(document, index, limit)
        end
        if inflected then aux, index = inflected, following
        elseif helper then aux, index = helper, index + 1 end
    end
    if not english and aux == auxiliary["буде"] and P.quantifiedSubject(subject)
        and adverbAt(document, index, limit, "predicate", function(candidate)
            return candidate.quantifiedSubject
        end) then
        tree.copula, tree.tense, aux = true, aux.tense, nil
    end
    if aux then
        tree.tense, tree.modal, tree.negative = aux.tense, aux.modal,
            tree.negative or aux.negative or (contraction and contraction[4])
        if not english and aux.tense == "future" then tree.analyticFuture = true end
        tree.ability = not english and aux.ability or nil
        tree.inferred = aux.person and {person=aux.person, number=aux.number} or nil
        local auxiliarySubject = subject or (previous and previous.subject)
        if auxiliarySubject then
            if not english and aux.tense == "future" and aux.number == "plural"
                and subject and subject.pronoun and subject.pronoun.deixis then
                local finish = predicate(document, tree, index, limit, depth)
                if finish and tree.predicate and tree.predicate.number == aux.number then
                    tree.copula = true
                    return tree, finish
                end
                return nil
            end
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
    local politeDesire = english and aux and aux.ability == "conditional"
        and P.key(document, index, limit) == "like" and P.key(document, index + 1, limit) == "to"
    local conditionalDesire = english and aux and aux.ability == "conditional" and not politeDesire
        and A.conditionalDesireAt(document, index, limit, subject or relativeSubject)
    if english and (tree.modal == "can" or tree.modal == "could") and (subject or relativeSubject) then
        local marker = P.key(document, index, limit)
        if marker == "be" or marker == "get" then
            local patient = subject or relativeSubject
            local adverb, nextVerb = adverbAt(document, index + 1, limit)
            nextVerb = nextVerb or index + 1
            local action, after = verb(document, nextVerb, limit, patient, false, false, nil, "passive")
            if action and lexemeFrame(action).passiveVoice then
                tree.subject, tree.inherited, tree.verb, tree.verbIndex = patient, not subject, action, nextVerb
                tree.aspect, tree.leadingAdverb = "passive", adverb
                local finish = complements(document, tree, after, limit, depth)
                if finish then return tree, finish end
                return nil
            end
        end
    end
    if english then
        local ability = tree.copula and tree.tense or aux and (aux.ability or aux.tense == "future" and "future")
        local at = ability and abilityComplementStart(document, index, limit, tree.copula)
        if at then
            tree.ability, tree.copula, tree.modal, index = ability, nil, "can", at
            aux = aux or auxiliary.can
        elseif aux and aux.ability and not politeDesire then
            if aux.ability ~= "conditional" then return nil end
            tree.conditional = true
        end
    end
    if not english and wh and wh.role == "predicate" then tree.copula = true end
    if english and tree.modal == "must" and subject and subject.pronoun and deicticSubject(subject)
        and not (tree.question or tree.negative) then
        local inference, finish = A.nominalInference(document, index, limit, tree.modal, subject, depth)
        if inference then return inference, finish end
    end
    if english and tree.modal == "might" then
        if tree.where or tree.why or wh then return nil end
        local past, finish = A.speculativePast(document, tree, index, limit, aux, subject, relativeSubject, mayOmitSubject, depth)
        if past then return past, finish end
        if aux.perfect then return nil end
        if P.key(document, index, limit) == "be" then
            tree.copula, index = true, index + 1
        end
    elseif english and tree.conditional and P.key(document, index, limit) == "be" then
        tree.copula, tree.tense, index = true, "past", index + 1
    elseif english and tree.tense == "future" and P.key(document, index, limit) == "be" then
        local actor = subject or relativeSubject
        local adverb, following = adverbAt(document, index + 1, limit)
        local verbIndex = following or index + 1
        local action, afterVerb, aspect
        if actor then
            action, afterVerb = verb(document, verbIndex, limit, actor, false, false, nil, "present")
            aspect = "continuous"
            if not action then
                action, afterVerb = verb(document, verbIndex, limit, actor, false, false, nil, "passive")
                aspect = "passive"
            end
        end
        if action then
            tree.subject, tree.inherited = actor, not subject
            tree.verb, tree.verbIndex, tree.aspect = action, verbIndex, aspect
            tree.leadingAdverb = adverb
            local finish = complements(document, tree, afterVerb, limit, depth)
            if finish then return tree, finish end
            return nil
        end
        tree.copula, index = true, index + 1
    elseif not english and subject and P.key(document, index, limit) == "—" then
        tree.copula, index = true, index + 1
    end
    if not (aux or tree.copula or tree.negative or tree.question or indirect or objectGap) and subject then
        local ready, finish = A.collectiveReadiness(document, subject, index, limit, depth)
        if ready then return ready, finish end
    end
    if tree.copula then
        if not subject and relativeSubject then
            subject, tree.subject, tree.inherited = relativeSubject, relativeSubject, true
        end
        if not subject then return nil end
        tree.copula, tree.tense = true, tree.tense or "present"
        if locativeGap and not (wh or tree.question) and boundary(document, index, limit) then
            tree.locativeGap = true
            return tree, index
        end
        if wh and wh.role == "predicate" then
            if wh.indirectPredicate and boundary(document, index, limit) then return tree, index end
            local gender = subject.number == "plural" and "plural" or subject.gender
            wh.definite = wh.definite or subject.article == "definite" or subject.possessor ~= nil or subject.demonstrative ~= nil
            if tree.tense == "present" and not tree.negative
                and (not wh.definite or gender and (not wh.gender or wh.gender == gender)) then
                local action, finish = nominalInfinitive(document, subject, index, limit, depth)
                if action then subject.nominalAction, index = action, finish end
                if index > limit then return tree, index end
            end
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
    local sharedAdvice = not (subject or aux) and previous and previous.ellipticSubject
        and previous.modal == "should" and not previous.modalPerfect
    local sharedModal = (inheritedSubject and not aux or sharedAdvice) and previous.modal or nil
    local sharedConditional = english and inheritedSubject and not aux and previous.conditional
    local sharedPerfect = not subject and not aux and previous and previous.modalPerfect
    tree.imperative = (not (subject or inheritedSubject or aux or sharedAdvice) and english) or inheritedImperative
    if sharedAdvice then tree.ellipticSubject = true end
    if inverted and not subject then return nil end
    local afterVerb, adverbIndex
    local contractedPredicate = contraction and contraction[3]
    if (subject or inheritedSubject or tree.imperative or tree.ellipticSubject) and not contractedPredicate then
        if not english and subject and not (aux or wh) then
            local rating, after = A.suitabilityRating(document, index, limit)
            if rating then
                local finish = A.suitabilityAt(document, tree, rating, after, limit, depth)
                if finish then return tree, finish end
            end
        end
        local adverb, following = adverbAt(document, index, limit)
        if adverb and (not tree.imperative or sharedPerfect or adverb.commandModifier)
            and not (not english and adverb.participialQualifier
                and L.choose(document, following, "adj", nil, "participialState"))
            and (english or not adverb.location or not boundary(document, following, limit)) then
            adverbIndex = index
            tree.leadingAdverb, index = adverb, following
            if tree.imperative and adverb.negativeCommand then
                tree.negative = true
            end
        end
    end
    local verbIndex = not contractedPredicate and index or nil
    if sharedPerfect and not contractedPredicate then
        local action, after = verb(document, index, limit, inheritedSubject, not english, false, nil, english and "past" or nil)
        if action then
            tree.modalPerfect, tree.tense, tree.imperative = true, "past", nil
            tree.ellipticSubject = previous.ellipticSubject
            tree.verb, afterVerb, sharedModal = action, after, previous.modal
        elseif inheritedSubject then
            sharedModal = nil
        end
    end
    if english and aux and aux.modal == "should" and (aux.perfect or P.key(document, index, limit) == "have") then
        local start = index + (aux.perfect and 0 or 1)
        local negative = P.key(document, start, limit) == "not"
        if negative then start = start + 1 end
        local adverb, following = adverbAt(document, start, limit)
        start = following or start
        local action, after = verb(document, start, limit, subject or inheritedSubject, false, false, nil, "past")
        if action and not (adverb and tree.leadingAdverb) then
            tree.modalPerfect, tree.tense = true, "past"
            tree.negative, tree.leadingAdverb = tree.negative or negative, tree.leadingAdverb or adverb
            tree.verb, verbIndex, afterVerb = action, start, after
        elseif aux.perfect or tree.ellipticSubject or action then return nil end
    elseif tree.ellipticSubject and not (tree.modalPerfect or sharedAdvice or aux and aux.modal == "should") then return nil end
    if not english and wh and wh.kind == "thing" and wh.role == "object" and not wh.noun
        and boundary(document, index + 1, limit) then
        tree.verb, afterVerb = verb(document, index, limit, subject, aux ~= nil, tree.imperative, "generalAction")
    end
    if not tree.verb then
        tree.verb, afterVerb = verb(document, contractedPredicate and headIndex or index, limit,
            subject or inheritedSubject, aux ~= nil or sharedModal ~= nil or sharedConditional, tree.imperative,
            politeDesire and "politeDesire" or conditionalDesire and "conditionalDesire" or nil, nil,
            contractedPredicate, inheritedSubject and previous, aux and aux.tense, previous and previous.object)
    end
    if unmarkedPermission and not (subject and (subject.person == 1
        or tree.verb and lexemeFrame(tree.verb).permissionRequest)) then return nil end
    if not tree.verb and not english and aux and not (objectGap or wh) then
        local action, finish, argument, start = A.preverbalModalObject(document, index, limit,
            subject or inheritedSubject, tree.negative)
        if action then tree.verb, tree.object, verbIndex, afterVerb = action, argument, start, finish end
    end
    if english and tree.imperative and tree.leadingAdverb and tree.leadingAdverb.pastUk then
        local past, finish = verb(document, index, limit, subject or inheritedSubject, false, false, nil, "simplePast", nil, previous)
        if past and (not tree.verb or past.lexeme.en ~= tree.verb.lexeme.en
            and past.lexeme.preference < tree.verb.lexeme.preference) then
            tree.verb, tree.imperative, tree.ellipticSubject, afterVerb = past, nil, true, finish
        end
    end
    if unmarkedQuestion and not tree.verb and not aux then
        tree.verb, afterVerb = verb(document, index, limit, subject, true)
        if tree.verb then
            tree.question = true
            if lexemeFrame(tree.verb).ellipticRequest then tree.modal, tree.ellipticRequest = "can", true end
        end
    end
    if english and subject and index <= limit
        and not (tree.verb or aux or inverted or contraction or wh or indirect or tree.question) then
        local stateStart = index
        local knownSubject = subject.article == "definite"
            or subject.pronoun and subject.person ~= 2 and not unmarkedQuestion
        if knownSubject and not questionMark then
            local modifier, after = adverbAt(document, index, limit, "predicate",
                function(candidate) return candidate.predicateModifier end)
            if modifier then stateStart = after end
        end
        local adjective = not questionMark and L.choose(document, stateStart, "adj", nil, nil,
            function(candidate) return knownSubject or lexemeFrame(candidate).omittedCopula end)
        local evaluation = not (questionMark or adjective) and deicticSubject(subject)
            and adverbAt(document, stateStart, limit, "predicate", function(candidate) return candidate.deicticEvaluation end)
        if questionMark or adjective or evaluation then
            local state = {kind="clause", subject=subject, copula=true, tense="present", question=questionMark,
                negative=tree.negative, leadingAdverb=tree.leadingAdverb}
            local finish = predicate(document, state, index, limit, depth)
            if finish and boundary(document, finish, limit) and (state.adjective or state.predicateAdverb
                and (state.predicateAdverb.quantifiedSubject or state.predicateAdverb.deicticEvaluation)) then
                return state, finish
            end
        end
    end
    if not tree.verb and not subject and not english and not aux then
        tree.verb, afterVerb = verb(document, index, limit, nil, false, true)
        tree.imperative = tree.verb ~= nil
    end
    if not tree.verb and not english and (subject or relativeSubject) and (not aux or aux.tense == "future") then
        if not aux and subject and subject.demonstrative then
            local pointer, following = P.pronoun(document, headIndex, limit, "nominative")
            if pointer and pointer.pronoun.id == "this" then
                local identity = {kind="clause", subject=pointer, copula=true, tense="present", question=tree.question}
                local finish = predicate(document, identity, following, limit, depth)
                if (identity.predicate or identity.predicativeRelative) and finish
                    and boundary(document, finish, limit) then return identity, finish end
            end
        end
        if adverbIndex and tree.leadingAdverb.location and P.durationSpan(document, index, limit, true) then
            tree.leadingAdverb, index = nil, adverbIndex
        end
        if not subject then tree.subject, tree.inherited = relativeSubject, true end
        local finish = predicate(document, tree, index, limit, depth)
        if finish and (subject or boundary(document, finish, limit)) then
            local date = tree.prepositions and #tree.prepositions == 1 and tree.prepositions[1]
            if date and date.object.calendarYear and finish > limit and subject and not subject.pronoun
                and not (aux or tree.leadingAdverb or tree.predicateAdverb or tree.negative or tree.question or tree.wh) then
                tree.kind = "nounPhrase"
                return tree, finish
            end
            tree.copula, tree.tense = true, tree.tense or "present"
            tree.predicateAdverb = tree.predicateAdverb or tree.leadingAdverb
            return tree, finish
        end
    end
    if not tree.verb and english and subject and not (subject.pronoun or subject.genitive or subject.destination)
        and not aux and not tree.question then
        local actor = previous and previous.subject
        local modal = actor and previous.modal
        local base = actor and (modal ~= nil or previous.tense == "future" or previous.conditional)
        local action, after = verb(document, first, limit, actor, base, not actor, nil, nil, nil, previous)
        if action then
            tree, subject, afterVerb = {kind="clause", verb=action, imperative=not actor or nil}, nil, after
            verbIndex = first
            inheritedSubject, sharedModal = actor, modal
            sharedConditional = actor and previous.conditional
        end
    end
    if not tree.verb and tree.imperative and english and not subject and not aux then
        local statement, following = verb(document, index, limit, nil, false, false, "impersonal")
        if statement and statement.form.tense then
            tree.verb, tree.imperative, afterVerb = statement, nil, following
        else
            local past, endOfVerb = verb(document, index, limit, nil, false, false, nil, "simplePast")
            if past then
                tree.verb, tree.imperative, tree.ellipticSubject, afterVerb = past, nil, true, endOfVerb
            end
        end
    end
    if not tree.verb then return nil end
    tree.verbIndex = verbIndex
    if english and aux and aux.support and subject and not (inverted or tree.negative or tree.question or questionMark) then
        tree.emphaticDo = true
    elseif not english and tree.leadingAdverb and tree.leadingAdverb.emphaticDo
        and not (tree.negative or tree.question or tree.imperative or tree.modal or tree.tense == "future")
        and (tree.verb.form.tense == "present" or tree.verb.form.tense == "past") then
        tree.emphaticDo, tree.leadingAdverb = true, nil
    end
    if not english and verbIndex and (afterVerb == verbIndex + 3 and P.key(document, verbIndex + 1, limit) == "/"
        or afterVerb == verbIndex + 4 and P.key(document, verbIndex + 2, limit) == "/") then
        tree.verbAlternativesEnd = afterVerb - 1
    end
    if unmarkedQuestion and tree.subjectLocation then tree.question = true end
    local frame = lexemeFrame(tree.verb)
    if english then
        tree.conditional = tree.conditional or sharedConditional
    else
        if tree.conditional and (aux or tree.verb.form.tense ~= "past") then return nil end
        if tree.verb.form.tense == "past" and A.conditionalParticleAt(document, afterVerb, limit) then
            if tree.conditional then return nil end
            tree.conditional, afterVerb = true, afterVerb + 1
        end
    end
    if english and tree.imperative and not tree.negative and frame.impersonalNeed then
        local question = P.key(document, limit + 1, #document.tokens) == "?"
        if frame.infinitive and P.key(document, afterVerb, limit) == "to" then
            return A.omittedNeed(document, tree, afterVerb, limit, frame, depth)
        end
        local object, finish = P.coordinated(document, afterVerb, limit, "accusative", nil, nil, nil, frame.objectSense)
        if not object and frame.ellipticalGroupRole then
            object, finish = P.ellipticalGroupMember(document, afterVerb, limit, frame.ellipticalGroupRole)
        end
        if object then return needClause(document, object, finish, limit, nil, question, depth, tree.verbIndex) end
        return nil
    end
    if english and tree.imperative and not subject and not inheritedSubject and frame.subjectlessQuestion
        and P.key(document, limit + 1, #document.tokens) == "?" then
        subject, tree.question, tree.imperative = personalSubject("you"), true, nil
    end
    if not english then agreeSubject(document, subject, tree.verb.form) end
    if english or frame.reverseSubjectSense then refineSubject(document, subject, frame) end
    local inferredRecruitment = not english and not (subject or inheritedSubject or tree.imperative)
        and (frame.recruitmentSearch or frame.recruitmentIntent)
        and tree.verb.form.person == 1 and tree.verb.form.tense == "present"
    if inferredRecruitment then
        subject = personalSubject(tree.verb.form.number == "plural" and "we" or "i")
        tree.aspect = "continuous"
    end
    local implicit = frame.implicitSubject
    if implicit and not inheritedSubject and (not subject or subject.pronoun and subject.pronoun.id == implicit) then
        if not subject and not aux then tree.tense = frame.implicitTense or tree.tense end
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
    local finish = complements(document, tree, afterVerb, limit, depth, previous and previous.object)
    if finish then
        if tree.ellipticRequest and not recurringEvent(tree) then
            tree.taskInfinitiveLemma = frame.purposeLemma or frame.infinitiveLemma or frame.imperative
        end
        if inferredRecruitment and recurringEvent(tree) then tree.aspect = nil end
        if english and tree.subject and tree.object and not tree.wh
            and (frame.dativeNeed or frame.ellipticalGroupRole and tree.object.additional and tree.object.destination
                or frame.impersonalNeed and needPurposeObject(tree.object)
                    and (tree.purpose and tree.purpose.verb or tree.question and tree.subject.person == 2
                        and addresseePurpose(tree.prepositions and tree.prepositions[1]))
                    and not (tree.adverbs or tree.leadingAdverb or tree.delay))
            and tree.tense == "present" and not (tree.modal or tree.aspect or tree.negative) then
            tree.kind = "need"
        end
        if english and not aux and not tree.imperative and tree.verb.form.mood == "base"
            and lexemeFrame(tree.verb).unmarkedPast and explicitTime(tree) == "past" then
            tree.tense = "past"
        end
        if not english and frame.englishProgressiveEvent and not recurringEvent(tree)
            and (headlessQuantity or wh and wh.kind == "thing" and wh.role == "subject") then
            tree.aspect = "continuous"
        end
        if not english and frame.englishProgressiveAdjuncts and tree.tense == "present"
            and not (tree.imperative or tree.modal or tree.aspect or recurringEvent(tree)) then
            for _, adjunct in ipairs(tree.prepositions or {}) do
                if frame.englishProgressiveAdjuncts[adjunct.rule.id] then tree.aspect = "continuous"; break end
            end
        end
        if not english and frame.ellipticPartnerSearch and tree.tense == "present" and not recurringEvent(tree)
            and tree.object and (tree.question or tree.purpose and P.relativeAnimate(tree.object)
                or tree.object.nominalAction and tree.object.nominalAction.nominalPartner) then
            tree.aspect = "continuous"
        end
        return tree, finish
    end
end

local function chooseModalSense(tree, pastContext)
    local time = explicitTime(tree)
    local past = time == "past" or (time ~= "nonpast" and (pastContext or tree.tense == "past"))
    if (tree.modal == "could" or tree.modal == "can") and tree.verb and tree.subject
        and not (past or tree.negative or tree.modalPerfect) then
        local pronoun = tree.subject.pronoun
        local frame = lexemeFrame(tree.verb)
        local polar = tree.question and not (tree.wh or tree.where or tree.why or tree.when)
        if polar and pronoun and (pronoun.person == 2 or pronoun.id == "someone")
            and (tree.modal == "could" or frame.ellipticRequest) then
            if tree.modal == "could" then tree.modalSense = "request" end
            if not recurringEvent(tree) then
                tree.taskInfinitiveLemma = frame.modalLemma or frame.purposeLemma or frame.infinitiveLemma or frame.imperative
                    or tree.taskInfinitiveLemma
            end
        elseif tree.modal == "could" and not tree.question and frame.possibleOutcome then
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

local function extendRelativeActions(document, firstAction, index, limit, readAction)
    local clauses, joins = {firstAction}, {}
    for i = 1, 3 do
        if document.relativeBudget <= 0 then break end
        local comma = P.key(document, index, limit) == ","
        local connector, last = clauseConnector(document, index + (comma and 1 or 0), limit)
        if connector and connector.id ~= "and" and connector.id ~= "or" then break end
        if not (comma or connector) then break end
        local nextAction = connector and last + 1 or index + 1
        local action, finish = readAction(nextAction, clauses[i], connector, comma)
        if not action then break end
        joins[i] = connector or false
        clauses[i + 1], index = action, finish
    end
    return clauses, joins, index
end

local function participialRelative(document, noun, first, limit, anchor)
    if anchor.group and not noun.members then return nil end
    local depth = document.relativeDepth + 1
    local subject = {person=3, number=noun.number, gender=noun.gender, animacy=noun.animacy,
        membershipGroup=P.hasTrait(noun, "membershipGroup")}
    local function actionAt(index)
        local entry, after = verb(document, index, limit, subject, false, false, nil, "present")
        if not entry then return nil end
        local action = {kind="clause", subject=subject, inherited=true, tense=anchor.tense or "present", verb=entry, verbIndex=index}
        document.relativeBudget = document.relativeBudget - 1
        document.relativeDepth = depth
        local finish = complements(document, action, after, limit, depth)
        document.relativeDepth = depth - 1
        if finish then return action, finish end
    end
    local action, ending = actionAt(first)
    if not action then return nil end
    local clauses, joins, finish = extendRelativeActions(document, action, ending, limit, actionAt)
    if anchor.group and (#clauses < 2 or not joins[#joins]) then return nil end
    return {clause=action, case="nominative", actions=clauses, joins=joins}, finish
end

local function closeRelative(document, ending, limit)
    if P.key(document, ending, limit) == "," and ending < limit
        and not L.functional(document, "connectors", ending + 1, limit) then
        return ending + 1
    end
    return ending
end

local function locativeRelative(document, noun, markerIndex, limit, nonrestrictive)
    local head, arcs, offset = P.locativeRelativeHead(document, noun, markerIndex, limit)
    if not head then return nil end
    local depth = document.relativeDepth + 1
    document.relativeDepth = depth
    document.relativeBudget = document.relativeBudget - 1
    local tree, after = simple(document, markerIndex + 1, limit, nil, depth, true)
    local result
    if tree and tree.kind == "clause" and not (tree.question or tree.imperative)
        and (tree.verbIndex or tree.predicateIndex) == head then
        local actions, joins, ending = extendRelativeActions(document, tree, after, limit,
            function(index, previous, connector, comma)
                if not connector or comma then return nil end
                document.relativeBudget = document.relativeBudget - 1
                local action, finish = simple(document, index, limit, previous, depth)
                if not action or not action.verbIndex or action.question or action.imperative then return nil end
                local arc = arcs[action.verbIndex - offset]
                if arc and arc.relation == "conj" and (arc.head + offset == head
                    or arc.head + offset == previous.verbIndex) then
                    return action, finish
                end
            end)
        document.locativeRelative.used = true
        result = {clause=tree, locative=true, nonrestrictive=nonrestrictive,
            actions=#actions > 1 and actions or nil, joins=joins}
        after = closeRelative(document, ending, limit)
    end
    document.relativeDepth = depth - 1
    return result, after
end

-- The antecedent supplies a role within the dependent clause.
function A.relative(document, noun, first, limit)
    if document.relativeBudget <= 0 or document.relativeDepth >= 3 then return nil end
    local participle = document.participleAnchors and document.participleAnchors[first]
    if participle and participle.head == noun.headIndex then
        return participialRelative(document, noun, first, limit, participle)
    end
    local comma = P.key(document, first, limit) == ","
    local markerIndex = first + (comma and 1 or 0)
    local marker = P.key(document, markerIndex, limit)
    local english = document.direction == "en-uk"
    if document.locativeRelative and marker == P.locativeRelativeMarker[document.direction] then
        return locativeRelative(document, noun, markerIndex, limit, english and comma)
    end
    local preposition
    local following = english and P.key(document, markerIndex + 1, limit)
    if not P.relativeMarkers[document.direction][marker]
        and (not english or following == "which" or following == "whom") then
        local keys, after = L.functional(document, "prepositions", markerIndex, limit)
        local nextMarker = after == markerIndex and P.key(document, after + 1, limit)
        if keys and nextMarker and P.relativeMarkers[document.direction][nextMarker] then
            preposition, marker, markerIndex = marker, nextMarker, after + 1
        end
    end
    local unmarked = english and not comma and document.relativeAnchors
        and document.relativeAnchors[first] == noun.headIndex and noun.headIndex ~= nil
    if not (unmarked or P.relativeMarkers[document.direction][marker]) or markerIndex >= limit then return end
    local person = P.relativeAnimate(noun)
    if english and ((marker == "who" or marker == "whom") and not person or marker == "which" and person) then return end

    if not english and (preposition == "у" or preposition == "в")
        and person and marker == P.relativePronoun(noun, "genitive") then
        local owner = {person=3, number=noun.number, gender=noun.gender, animacy="animate"}
        local state, ending = A.possessedAdjectiveAt(document, owner, markerIndex + 1, limit, nil, true)
        if state then
            return {clause=state, case="genitive", nonrestrictive=comma}, closeRelative(document, ending, limit)
        end
    end
    local subjectReading = not (unmarked or preposition)
        and (english and marker ~= "whom" or marker == P.relativePronoun(noun, "nominative"))
    local oldDepth = document.relativeDepth
    document.relativeDepth = oldDepth + 1
    local selected, ending, role, governedPreposition
    local start = markerIndex + (unmarked and 0 or 1)
    if subjectReading then
        document.relativeBudget = document.relativeBudget - 1
        -- The inherited subject carries agreement only. Keeping the whole
        -- antecedent here would create a cycle in the syntax tree.
        local gender = noun.gender or (noun.pronoun and noun.pronoun.id == "everyone" and "masculine") or nil
        local subject = {person=3, number=noun.number, gender=gender, animacy=noun.animacy,
            membershipGroup=P.hasTrait(noun, "membershipGroup")}
        local tree, after = simple(document, start, limit, {subject=subject}, oldDepth + 1, true)
        if tree and tree.inherited and tree.kind == "clause" and not tree.question and not tree.imperative then
            selected, ending, role = tree, after, "nominative"
        end
    end
    if document.relativeBudget > 0 and not (english and preposition) then
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
    if (not selected or role ~= "nominative" and not boundary(document, ending, limit))
        and (english or preposition) and document.relativeBudget > 0 then
        document.relativeBudget = document.relativeBudget - 1
        local gap = {prepositional=true, markerIndex=markerIndex - 1, fronted=preposition ~= nil,
            class=P.semanticClass(noun), nominalContent=noun.entry and lexemeFrame(noun.entry).nominalContent}
        local tree, after = simple(document, start, limit, nil, oldDepth + 1, true, gap)
        if tree and tree.subject and not (tree.question or tree.imperative) then
            local action = tree
            while action and not action.relativePreposition do action = action.infinitive end
            local rule = action and action.relativePreposition
            if rule and (not ending or after > ending) and (english or marker == P.relativePronoun(noun, rule.case)) then
                selected, ending, role, governedPreposition = tree, after, rule.case, rule
            end
        end
    end
    local actions, joins
    if not english and role == "nominative" and selected and selected.verb then
        local clauses, junctions, finish = extendRelativeActions(document, selected, ending, limit, function(index)
            document.relativeBudget = document.relativeBudget - 1
            local tree, after = simple(document, index, limit, {subject=selected.subject}, oldDepth + 1, true)
            if tree and tree.inherited and tree.verb and not (tree.question or tree.imperative) then return tree, after end
        end)
        if #clauses > 1 and junctions[#junctions] and finish > limit then
            actions, joins, ending = clauses, junctions, finish
        end
    end
    document.relativeDepth = oldDepth
    if not selected then return nil end
    return {clause=selected, case=role, nonrestrictive=english and comma, actions=actions, joins=joins,
        preposition=governedPreposition},
        closeRelative(document, ending, limit)
end

do
    local function hasUnresolvedSearchTarget(document, action)
        local object = action.object
        if object and object.headIndex and object.number == "singular"
            and not (object.term or object.raw or object.article or object.possessor or object.demonstrative or object.quantity) then
            local spelling = P.raw(document, object.headIndex, object.headIndex)
            if spelling:match("^[A-Z][a-z]") then return true end
        end
        if action.infinitive and hasUnresolvedSearchTarget(document, action.infinitive) then return true end
        for _, step in ipairs(action.series or {}) do
            if hasUnresolvedSearchTarget(document, step.action) then return true end
        end
        return false
    end

    function A.searchQualification(document, first, limit, object, after, abbreviated)
        if not personNoun(object) then
            -- A role can also be read as an adjective in the longer noun phrase.
            if object and not object.adjectives then return nil end
            object, after = P.noun(document, first, limit, "accusative", false, nil, true, nil, personNoun)
        end
        if not personNoun(object) or after >= limit then return nil end
        local key = P.key(document, after, limit)
        local marker = key == "," and P.key(document, after + 1, limit) or key
        if marker and P.relativeMarkers["en-uk"][marker] then
            -- Full search clauses already resolve relatives and the speaker together.
            if not abbreviated then return nil end
            local budget, depth = document.relativeBudget, document.relativeDepth
            document.relativeBudget, document.relativeDepth = budget or 16, depth or 0
            local relative, finish = A.relative(document, object, after, limit)
            document.relativeBudget, document.relativeDepth = budget, depth
            if relative and relative.case == "nominative" and finish == limit + 1
                and not hasUnresolvedSearchTarget(document, relative.clause) then
                object.relative = relative
                return object, finish
            end
            return nil
        end

        local marked = purposeStart(document, after, limit, true)
        local action, finish = purposeAt(document, after, limit, 0, true, not marked)
        if not action or finish ~= limit + 1 or hasUnresolvedSearchTarget(document, action) then return nil end
        -- With no linker, require a parsed complement to distinguish the action
        -- from a trailing label or a word shared by a noun and a verb.
        if not marked and not (action.object or action.controlled or action.infinitive or action.kind == "activity") then
            return nil
        end
        return object, finish, action
    end
end

function A.finiteCopulaTail(document, marker, limit, subject, expandedForm)
    local key = expandedForm or P.key(document, marker, limit)
    local form = negativeCopula[key] or key
    local tense = copula[form]
    local negative = negativeCopula[key] ~= nil
    local index = marker + (expandedForm and 0 or 1)
    if not negative and P.key(document, index, limit) == "not" then negative, index = true, index + 1 end
    local plural = subject.number == "plural" or subject.person == 2
    local expected = tense == "past" and (plural and "were" or "was")
        or plural and "are" or subject.person == 1 and "am" or "is"
    if tense and form == expected and boundary(document, index, limit) then return tense, negative, index end
end

function A.locativeEllipsis(document, first, limit, antecedent)
    if not (antecedent and antecedent.copula and antecedent.subject)
        or antecedent.predicate or antecedent.adjective or antecedent.modal or antecedent.question then return nil end
    local adverb = antecedent.predicateAdverb
    if not adverb and antecedent.locativeAdverbIndex then
        adverb = adverbAt(document, antecedent.locativeAdverbIndex, limit)
    end
    local phrase = antecedent.prepositions and antecedent.prepositions[1]
    if not (adverb and adverb.location and not (adverb.scheduleStatus or adverb.encounterAvailability)
        or P.spatialLocation(phrase) or phrase and phrase.rule.id == "out-of-location") then return nil end
    local location = adverb and adverb.en[1] == "here" and "тут" or "там"
    local english = document.direction == "en-uk"
    local subject, marker = P.coordinated(document, first, limit, english and "nominative" or "genitive")
    local expandedForm
    if not subject and english then
        local expansion = contracted[P.key(document, first, limit)]
        if expansion and copula[expansion[2]] then
            subject, marker, expandedForm = personalSubject(expansion[1]), first + 1, expansion[2]
        end
    end
    if not subject then return nil end
    local tense, negative, finish
    if english then
        tense, negative, finish = A.finiteCopulaTail(document, marker, limit, subject, expandedForm)
    else
        local key = P.key(document, marker, limit)
        if key == "тут" or key == "там" then
            if key ~= location then return nil end
            marker = marker + 1
        end
        local head
        head, finish = A.existentialHead(document, marker, limit)
        if head and boundary(document, finish, limit) then tense, negative = head.tense, head.negative end
    end
    if tense and negative then
        return {kind="clause", subject=subject, copula=true, tense=tense, negative=true,
            locationEllipsis=location}, finish
    end
end

local function supportEllipsis(document, first, limit, antecedent, rule)
    local english = document.direction == "en-uk"
    if antecedent.copula and antecedent.predicate and antecedent.subject
        and not antecedent.modal and (rule.id == "and" or rule.id == "or" or rule.id == "but") then
        local negative = P.key(document, first, limit) == (english and "not" or "не")
        local tree = {kind="clause", subject=antecedent.subject, tense=antecedent.tense, copula=true,
            inherited=true, omittedCopula=true, negative=negative}
        local finish = predicate(document, tree, first + (negative and 1 or 0), limit, 0)
        if finish and tree.predicate then return tree, finish end
    end
    local locative, locativeEnd = A.locativeEllipsis(document, first, limit, antecedent)
    if locative then return locative, locativeEnd end
    if not english then return nil end
    if antecedent.imperative or not (antecedent.verb or antecedent.copula and antecedent.adjective) then return nil end
    local subject, marker = P.coordinated(document, first, limit, "nominative")
    if not subject then return nil end
    if antecedent.copula then
        local tense, negative, index = A.finiteCopulaTail(document, marker, limit, subject)
        if tense then
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

function A.prospectiveEvent(tree)
    if tree.verb and lexemeFrame(tree.verb).futureEventLemma and tree.tense == "present"
        and not (tree.aspect or tree.modal or tree.negative) then
        tree.tense, tree.sequencedEvent = "future", true
    end
end

local function scheduledWhen(document, action, condition)
    if not (condition.verb and lexemeFrame(condition.verb).futureEventLemma)
        or recurringEvent(action) or recurringEvent(condition) then return end
    local futureAction = action.tense == "future" or action.imperative
    if document.direction == "en-uk" and futureAction then
        A.prospectiveEvent(condition)
        if condition.sequencedEvent then condition.temporalDependent = true end
    elseif document.direction == "uk-en" and (futureAction or action.tense == "present")
        and condition.tense == "future" then
        condition.tense, condition.temporalDependent = "present", true
    end
end

local function conditionalEvent(document, action, condition)
    local english = document.direction == "en-uk"
    local object = action.object
    if object and object.pronoun and not (object.referenceClass or object.targetPronoun) then
        local source, target, class = A.pronounReference(document, condition.object)
        if object.pronoun.id == source then object.targetPronoun, object.referenceClass = target or nil, class end
    end
    if condition.verb and lexemeFrame(condition.verb).conditionalOccurrence then
        if english and not recurringEvent(action) and not recurringEvent(condition) then
            A.prospectiveEvent(condition)
        elseif not english and condition.tense == "future" then
            condition.temporalDependent = true
        end
    end
    local referent = condition.subject
    local pronoun = action.subject and action.subject.pronoun
    local gender = referent and referent.number == "singular" and referent.gender
    if action.predicatePossessive and pronoun and gender and referent.animacy == "inanimate"
        and not (referent.pronoun or condition.object or condition.content or condition.controlled) then
        if english and pronoun.id == "it" then
            action.subject = personalSubject(gender == "feminine" and "she" or gender == "masculine" and "he" or "it")
            action.possessionAntecedent = true
        elseif not english and pronoun.person == 3 and pronoun.gender == gender then
            action.subject = personalSubject("it")
            if condition.tense == "future" then condition.temporalDependent = true end
        end
    end
    if not english or action.tense ~= "future" or action.aspect or action.modal
        or not action.verb or not action.object or not lexemeFrame(action.verb).boundedConditionalFuture
        or recurringEvent(action) or recurringEvent(condition) then return end
    action.sequencedEvent = true
end

local function auctionListing(tree)
    for _, phrase in ipairs(tree and tree.prepositions or {}) do
        if phrase.rule.id == "at-auction" then return true end
    end
    return false
end

local intentionInfinitive = {infinitive=true, infinitiveAdverbs=true}
local function nominalIntention(document, first, limit)
    if document.direction ~= "uk-en" then return nil end
    local separator
    for index = first + 1, math.min(first + 4, limit - 1) do
        if P.key(document, index, limit) == "—" then separator = index; break end
    end
    if not separator then return nil end
    local subject, after = P.noun(document, first, separator - 1, "nominative", false, nil, true)
    if after ~= separator or not P.hasTrait(subject, "intentionSubject") then return nil end
    local negative = P.key(document, separator + 1, limit) == "не"
    local action, finish = complementaryInfinitive(document, separator + (negative and 2 or 1), limit,
        intentionInfinitive, 0)
    if not action or not boundary(document, finish, limit) then return nil end
    action.negative = negative
    return {kind="clause", intentionNote=true, subject=subject, infinitive=action}, finish
end

local function adjectiveFragment(document, first, limit)
    local english = document.direction == "en-uk"
    local negative = P.key(document, first, limit) == (english and "not" or "не")
    local adjective, topic, finish = P.activityOrientation(document, first + (negative and 1 or 0), limit,
        not english and {case="nominative"} or nil)
    if not adjective or finish <= limit then return nil end
    return {kind="adjectivePhrase", adjective=adjective, prepositions={topic}, negative=negative}, finish
end

local function scheduledListing(noun)
    if not noun.members then return P.isScheduledEvent(noun) end
    for _, member in ipairs(noun.members) do
        if not P.isScheduledEvent(member) then return false end
    end
    return true
end

function A.eventRoom(document, tree, after, limit)
    if document.direction ~= "en-uk" or not tree.verbIndex or P.key(document, tree.verbIndex, limit) ~= "got"
        or not tree.subject or not scheduledListing(tree.subject)
        or tree.negative or tree.modal or tree.aspect or tree.question or tree.leadingAdverb
        or tree.sentenceAdverb or tree.adverbs then return nil end
    local index = tree.verbIndex + 1
    if P.key(document, index, limit) == "some" then index = index + 1 end
    if index + 1 ~= after or not boundary(document, after, limit) then return nil end
    local space = L.choose(document, index, "noun", nil, nil, function(candidate)
        return lexemeFrame(candidate).capacity and candidate.form.number ~= "plural"
    end)
    if not space then return nil end
    return {kind="existential", capacity=true,
        subject={entry=space, person=3, number="singular", gender=space.head.gender, animacy=space.head.animacy},
        locationPreposition={object=tree.subject, case="locative", rule={en={"at"}, targetUk="на", englishArticle="definite"}}}
end

function A.activityListScope(document, first, limit)
    local english = document.direction == "en-uk"
    local tokens, split = document.tokens
    for index = first + 3, limit - 2 do
        local dash = tokens[index]
        local key = dash.key
        if key == "—" or key == "–" or key == "-" and dash.first > tokens[index - 1].last + 1
            and tokens[index + 1].first > dash.last + 1 then
            local quantifier = tokens[index + 1].key
            if english and quantifier == "all" or not english and (quantifier == "усе" or quantifier == "все") then
                split = index
                break
            end
        end
    end
    if not split then return end
    local listing, after = P.coordinated(document, first, split - 1, "nominative", nil, nil, true)
    if not listing or not listing.members or after ~= split then return end
    for _, activity in ipairs(listing.members) do
        if not (P.hasTrait(activity, "activityTopic") or P.isScheduledEvent(activity)) then return end
    end
    local start = split + 2
    local matches, ending = L.functional(document, "activityListQualifiers", start, limit)
    local scope
    if matches and ending == limit then
        local qualifier = ns.Linguistics.grammar.activityListQualifiers[matches[1]]
        scope = {kind="adverbPhrase", expression=qualifier}
    else
        local calendar, finish = P.calendarList(document, start, limit)
        if calendar then
            if finish > limit then scope = {kind="nounPhrase", calendar=calendar} end
        else
            local phrase
            phrase, finish = P.preposition(document, start, limit)
            if phrase and finish > limit then scope = {kind="nounPhrase", prepositions={phrase}} end
        end
    end
    if scope then return {trees={{kind="nounPhrase", subject=listing, listScope=scope}}, joins={}} end
end

local function scheduleAdverb(document, first, limit)
    return adverbAt(document, first, limit, "nominalSchedule", function(candidate) return candidate.nominalSchedule end)
end

function A.scheduledCalendar(document, first, limit, candidate)
    if document.hasCalendarDay == nil then
        local english = document.direction == "en-uk"
        local days = ns.Linguistics.grammar.index[english and "en" or "uk"].calendarDays or {}
        document.hasCalendarDay = false
        for _, token in ipairs(document.tokens) do
            local key = token.key
            if not token.protected and (days[key] or not english and (key == "кожної" or key == "кожного")) then
                document.hasCalendarDay = true
                break
            end
        end
    end
    if not document.hasCalendarDay then return nil end
    local calendar, dayEnd = P.calendarList(document, first, limit)
    if not calendar and not (candidate and scheduledListing(candidate)) then return nil end

    local function clockAt(index)
        local comma = P.key(document, index, limit) == ","
        return P.clockSchedule(document, index + (comma and 1 or 0), limit)
    end
    local function locationAt(index)
        local place, after = P.preposition(document, index, limit)
        if place and place.case == "locative" then return place, after end
    end

    local clock, clockEnd
    if calendar then
        clock, clockEnd = clockAt(dayEnd)
        first = clockEnd or dayEnd
        local separator = P.key(document, first, limit)
        if separator == "," or separator == "—" or separator == "–" then first = first + 1 end
    end
    local listing, index = P.coordinated(document, first, limit, "nominative", nil, nil, true, nil, scheduledListing, true)
    if not listing then return nil end

    local place, after
    if not calendar then
        calendar, dayEnd = P.calendarList(document, index, limit)
        if not calendar then
            place, after = locationAt(index)
            if not place then return nil end
            calendar, dayEnd = P.calendarList(document, after, limit)
            if not calendar then return nil end
        end
        index = dayEnd
    end
    if not clock then
        clock, clockEnd = clockAt(index)
        index = clockEnd or index
    end
    if not place then
        place, after = locationAt(index)
        index = after or index
    end
    if boundary(document, index, limit) then
        return {kind="nounPhrase", subject=listing, calendar=calendar, clockRange=clock, scheduleLocation=place}, index
    end
end

function A.preverbalPronoun(document, first, limit, previous)
    local actor, following = P.noun(document, first, limit, "nominative", false, nil, true)
    local opening = following or first
    local modifier, objectAt = adverbAt(document, opening, limit)
    objectAt = objectAt or opening
    local object, start = P.pronoun(document, objectAt, limit, "accusative")
    if not object or start > limit then return nil end
    local action, finish = simple(document, start, limit, actor and {subject=actor} or previous, 0, nil, true)
    if not action or not action.verb or not action.relativeCase or action.tense == "infinitive"
        or action.imperative or action.leadingAdverb and modifier or not boundary(document, finish, limit) then return nil end
    local argument, after = P.pronoun(document, objectAt, limit, action.relativeCase)
    if not argument or after ~= start then return nil end
    action.object, action.objectGap = argument, nil
    action.leadingAdverb = modifier or action.leadingAdverb
    if actor then action.inherited = nil end
    return action, finish
end

function A.coordinateReport(document, first, limit)
    local source, at = adverbAt(document, first, limit, "coordinateSource")
    if not source or source.context ~= "coordinateSource" then return nil end
    local report, start = adverbAt(document, at, limit, "coordinateReport")
    if not report or report.context ~= "coordinateReport" then return nil end
    local coordinates, after = P.coordinatesAt(document, start, limit)
    if not coordinates then return nil end
    local place, finish = P.preposition(document, after, limit, nil, nil, "coordinateLocation")
    if P.spatialLocation(place) and boundary(document, finish, limit) then
        return {kind="coordinateReport", coordinateSource=source, coordinateReport=report,
            coordinates=coordinates, prepositions={place}}, finish
    end
end

function A.sharedPredicateJoin(join)
    local id = join and join.rule and join.rule.id
    return id == "and" or id == "or" or id == "then" or id == "but"
end

function A.agreeCommandSeries(trees, joins)
    local first = 1
    while first < #trees do
        local last = first
        if trees[first].imperative then
            local number = trees[first].imperativeNumber
            local conflicting
            while A.sharedPredicateJoin(joins[last]) and trees[last + 1].imperative do
                last = last + 1
                local following = trees[last].imperativeNumber
                if following then
                    conflicting = conflicting or number and following ~= number
                    number = following
                end
            end
            if last > first and number == "plural" and not conflicting then
                for index = first, last do trees[index].imperativeNumber = number end
            end
        end
        first = last + 1
    end
end

function A.namedRecruitment(document, first, limit)
    local english = document.direction == "en-uk"
    local article = english and P.key(document, first, limit) == "the"
    local start = first + (article and 1 or 0)
    local predicate = start
    local startsWithCapital = ns.Engine.Parser.startsWithCapital
    while predicate <= math.min(start + 5, limit - 1) do
        if not startsWithCapital(document.text, document.tokens[predicate]) then break end
        predicate = predicate + 1
    end
    if predicate - start < 2 or predicate > limit then return nil end
    if L.choose(document, start, "pron", nil, nil, function(candidate) return lexemeFrame(candidate).possessive end) then
        return nil
    end
    local subject = {raw=P.raw(document, P.raw(document, first, first) == "the" and start or first, predicate - 1),
        number="singular", person=3, gender="feminine", animacy="inanimate"}
    local auxiliary = english and P.key(document, predicate, limit)
    local progressive = auxiliary == "is" or auxiliary == "was"
    local at = predicate + (progressive and 1 or 0)
    local action, after = verb(document, at, limit, subject, false, false, nil, progressive and "present")
    local frame = action and lexemeFrame(action)
    if not frame or not (frame.recruitmentIntent or frame.expandsMembership or frame.recruitmentSearch) then return nil end
    local tree = {kind="clause", subject=subject, verb=action, verbIndex=at,
        tense=progressive and copula[auxiliary] or action.form.tense or "present",
        aspect=progressive and "continuous" or nil}
    local finish = complements(document, tree, after, limit, 0)
    if not finish or not boundary(document, finish, limit) then return nil end
    local goal = tree.infinitive and tree.infinitive.verb and lexemeFrame(tree.infinitive.verb)
    if frame.expandsMembership or frame.recruitmentSearch and personNoun(tree.object)
        or goal and (goal.expandsMembership or goal.recruitmentSearch
            and personNoun(tree.infinitive.object)) then
        if not english and tree.tense == "present" and frame.recruitmentIntent then tree.aspect = "continuous" end
        return tree, finish
    end
end

local function parse(document, first, limit, sentenceQuestion)
    local trees, joins = {}, {}
    local prefix, prefixEnd = clauseConnector(document, first, limit)
    local discoursePrefix
    if prefix and (prefix.id == "but" or prefix.discourseForms and prefix.discourseForms[P.key(document, first, limit)]
        and not clauseConnector(document, prefixEnd + 1, limit)) then
        if prefixEnd >= limit or document.direction == "en-uk" and P.key(document, prefixEnd + 1, limit) == "for" then
            return nil
        end
        discoursePrefix, first = prefix, prefixEnd + 1
        prefix, prefixEnd = clauseConnector(document, first, limit)
    end
    if prefix then
        if prefix.id ~= "because" and prefix.id ~= "if" and prefix.id ~= "when"
            and prefix.id ~= "so" and prefix.id ~= "in-case" and prefix.id ~= "while" and not prefix.freeLocative then
            prefix = nil
        end
        if prefix and prefix.id == "if" and P.raw(document, first, first) == "IF"
            and copula[P.key(document, prefixEnd + 1, limit)] then prefix = nil end
        if prefix and prefix.id == "so" and P.pronoun(document, first, limit, "nominative", nil, true) then
            prefix = nil
        end
        if prefix and prefix.id == "when" and document.direction == "en-uk" then
            local opening = P.key(document, prefixEnd + 1, limit)
            if auxiliary[opening] or copula[opening] or negativeCopula[opening] or have[opening]
                or negativePerfect[opening] then prefix = nil end
        end
    end
    local index = prefix and prefixEnd + 1 or first
    local detached, detachedEnd
    for _ = 1, 4 do
        local precedingJoin = joins[#joins]
        local relation = #trees == 0 and prefix or precedingJoin and precedingJoin.rule
        local previous
        if A.sharedPredicateJoin(precedingJoin) then
            previous = trees[#trees]
        end
        local domain = document.transferDomain
        if precedingJoin and precedingJoin.rule and precedingJoin.rule.id == "if" and auctionListing(trees[#trees]) then
            document.transferDomain = "auction"
        end
        local tree, after = detached, detachedEnd
        detached, detachedEnd = nil, nil
        if not tree then tree, after = nominalIntention(document, index, limit) end
        if not tree then
            local question
            if index == first then question = sentenceQuestion end
            tree, after = simple(document, index, limit, previous, 0, nil, nil, question, relation and relation.freeLocative)
        end
        if not tree or not boundary(document, after, limit) then
            local report, finish = A.coordinateReport(document, index, limit)
            if report then tree, after = report, finish end
        end
        if tree and tree.verb and tree.verb.lexeme.en == "get" then
            tree = A.eventRoom(document, tree, after, limit) or tree
        end
        local subject = tree and tree.subject
        if not previous and (not tree or not boundary(document, after, limit)
            or subject and not (subject.term or subject.raw or subject.pronoun or subject.possessor)
                and tree.verb and lexemeFrame(tree.verb).recruitmentIntent) then
            local recruitment, finish = A.namedRecruitment(document, index, limit)
            if recruitment then tree, after = recruitment, finish end
        end
        if document.direction == "uk-en" and (not tree or not boundary(document, after, limit)) then
            local fronted, finish = A.preverbalPronoun(document, index, limit, previous)
            if fronted then tree, after = fronted, finish end
        end
        if not tree and not previous then tree, after = adjectiveFragment(document, index, limit) end
        document.transferDomain = domain
        if precedingJoin and precedingJoin.rule and precedingJoin.rule.predicateEllipsis
            and (not tree or not boundary(document, after, limit)) then
            local candidate, finish = supportEllipsis(document, index, limit, trees[#trees], precedingJoin.rule)
            if candidate and (not tree or finish > after) then
                if candidate.locationEllipsis then trees[#trees].locationEllipsisAnchor = true end
                tree, after = candidate, finish
            end
        end
        if precedingJoin and precedingJoin.sentence and not (tree and tree.subject and tree.verb and not tree.question) then
            return nil
        end
        if not tree and not prefix and #trees == 0 then
            tree, after = profile(document, index, limit)
        end
        if not tree and not prefix and #trees == 0 then
            tree, after = pricePhrase(document, index, limit)
        end
        if not tree and not prefix and #trees == 0 then
            local calendar, opening = P.calendarList(document, index, limit)
            if calendar then
                local start = opening + (P.key(document, opening, limit) == "," and 1 or 0)
                local clock, finish = P.clockSchedule(document, start, limit)
                if clock and finish > limit then
                    tree, after = {kind="nounPhrase", calendar=calendar, clockRange=clock}, finish
                end
            end
        end
        if not tree and not prefix and (#trees == 0 or trees[#trees].exclusion) then
            local restriction, opening = P.nominalRestriction(document, index, limit)
            if restriction then
                local items, finish = P.coordinated(document, opening, limit, "nominative", nil, nil, "implicit")
                local audience, audienceEnd
                if items and document.direction == "en-uk" and P.key(document, finish, limit) == "with" then
                    audience, audienceEnd = P.welcomeAudience(document, finish + 1, limit)
                    if audience then finish = audienceEnd end
                end
                if items and finish > limit then
                    tree, after = {kind="nounPhrase", subject=items, restriction=restriction, audience=audience}, finish
                end
            end
        end
        if (not tree or not boundary(document, after, limit)) and not prefix
            and (#trees == 0 or precedingJoin and precedingJoin.rule and precedingJoin.rule.id == "but") then
            local negative = P.key(document, index, limit) == (document.direction == "en-uk" and "not" or "не")
            local phrase, ending = adverbAt(document, index + (negative and 1 or 0), limit)
            if phrase and phrase.standalone and (not negative or phrase.negatable)
                and (#trees == 0 or phrase.negatable) then
                local comma = P.key(document, ending, limit) == ","
                local pp, finish = P.preposition(document, ending + (comma and 1 or 0), limit)
                if ending > limit or pp and finish > limit then
                    tree, after = {kind="adverbPhrase", expression=phrase, prepositions=pp and {pp},
                        comma=comma, negative=negative}, finish or ending
                end
            end
        end
        local unfinishedCommand = tree and tree.imperative and after <= limit and not boundary(document, after, limit)
        local nominalCompetitor = tree and document.direction == "en-uk" and tree.verbIndex and tree.subject
            and tree.subject.headIndex and tree.verbIndex == tree.subject.headIndex + 1
            and not (tree.question or tree.negative or tree.object or tree.wh)
            and ns.Linguistics.grammar.nominalCompoundClasses[P.semanticClass(tree.subject)]
        if (not tree or unfinishedCommand or nominalCompetitor) and not prefix and #trees == 0 then
            local outlook, start = scheduleAdverb(document, index, limit)
            local listing, ending = P.coordinated(document, start or index, limit, "nominative", nil, nil, true)
            local dependency
            if nominalCompetitor and listing then
                local head = listing.members and listing.members[1] or listing
                if head.headIndex == tree.verbIndex and head.argument and head.argument.compound and ns.UDPipeModels then
                    local arcs = ns.Engine.UDPipe.analyzeDocument(document, index, limit)
                    local arc = arcs and arcs[tree.subject.headIndex - index + 1]
                    dependency = arc and arc.relation == "compound" and arc.head == head.headIndex - index + 1
                end
                if not dependency then listing = nil end
            end
            local scheduled, scheduleEnd
            if not (outlook or nominalCompetitor) then
                scheduled, scheduleEnd = A.scheduledCalendar(document, index, limit, listing)
            end
            if scheduled then
                tree, after = scheduled, scheduleEnd
            elseif listing then
                local finish = ending
                if not outlook then outlook, finish = scheduleAdverb(document, ending, limit) end
                if outlook and scheduledListing(listing) and boundary(document, finish, limit) then
                    tree, after = {kind="nounPhrase", subject=listing, adverbs={outlook}, nominalAttachment=dependency}, finish
                elseif not start and (listing.members or listing.argument or listing.listExtension) and ending > limit then
                    tree, after = {kind="nounPhrase", subject=listing, nominalAttachment=dependency}, ending
                end
            end
        end
        if not tree and not prefix and #trees == 0 and P.key(document, index, limit) ==
            (document.direction == "en-uk" and "not" or "не") then
            local noun, ending
            if document.direction == "en-uk" then noun, ending = P.pronoun(document, index + 1, limit, "accusative") end
            if not noun then noun, ending = P.coordinated(document, index + 1, limit, "nominative") end
            if noun and ending > limit then
                tree, after = {kind="nounPhrase", subject=noun, negative=true}, ending
            end
        end
        if (not tree or unfinishedCommand and tree.imperative) and not prefix and #trees == 0 then
            local noun, ending = P.noun(document, index, limit, "nominative")
            if noun and (not tree or noun.activityDescriptors and ending > limit) then
                if unfinishedCommand then tree = nil end
                if noun.entry and lexemeFrame(noun.entry).nominalInfinitive then
                    ending = attachNominalAction(document, noun, ending, limit, 0)
                end
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
                    local heading = noun.entry and lexemeFrame(noun.entry).standaloneNominal
                    local junction = heading and clauseConnector(document,
                        ending + (P.key(document, ending, limit) == "," and 1 or 0), limit)
                    if time and time.nominalTime and following > limit then
                        tree, after = {kind="nounPhrase", subject=noun, adverbs={time}}, following
                    elseif heading and (ending > limit or junction and junction.id == "but") then
                        tree, after = {kind="nounPhrase", subject=noun}, ending
                    elseif pp or ((noun.all or noun.same or noun.adjectives or noun.possessor or noun.nominalObject or noun.genitive or noun.argument
                        or noun.inclusion or noun.many or noun.more or noun.abundance or noun.nominalMeasure or noun.skillRequirement
                        or noun.destination or noun.activityMode or noun.membershipAudience or noun.groundedState or noun.playableClass
                        or noun.activityDescriptors
                        or noun.comparativeOffset
                        or noun.relative or noun.progressiveModifier or noun.prepositions or noun.nominalAction or noun.nominalQualifier
                        or noun.term and noun.term.features and noun.term.features.canStandAlone)
                        and ending > limit) then
                        tree = {kind="nounPhrase", subject=noun}
                        after = pp and addPredicateLocation(document, tree, pp, finish, limit) or ending
                    end
                end
            elseif not tree then
                local pp, finish = P.preposition(document, index, limit)
                if pp and finish > limit then tree, after = {kind="nounPhrase", prepositions={pp}}, finish end
            end
        end
        if not tree or after <= index then break end
        local relative, relativeEnd = relativeApposition(document, tree, after, limit)
        if relative then tree.relativeApposition, after = relative, relativeEnd end
        if tree.kind == "clause" and P.key(document, after, limit) == "," then
            local address, finish = A.addressAt(document, after + 1, limit, tree.imperative)
            if address then tree.addressee, after = address, finish end
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
        if relation and relation.freeLocative then
            local person = document.direction == "uk-en" and tree.verb and tree.verb.form.person
            if not (tree.subject or person and person < 3) or tree.question or tree.imperative
                or not (tree.verb or tree.copula or tree.kind == "need") then return nil end
        end
        trees[#trees + 1] = tree
        index = after
        if index > limit then break end
        local token = document.tokens[index]
        local comma = token.key == ","
        local dash = token.key == "—" or token.key == "–"
            or token.key == "-" and token.first > document.tokens[index - 1].last + 1
                and index < limit and document.tokens[index + 1].first > token.last + 1
        local connectorAt = index + ((comma or dash) and 1 or 0)
        local found, last = clauseConnector(document, connectorAt, limit)
        if found and found.id == "because" and P.key(document, connectorAt, limit) == "since"
            and (not comma or A.elapsedFromClause(tree)) then found = nil end
        if found and found.id == "or" and prefix and comma and #trees == 1 and document.direction == "uk-en"
            and P.key(document, index + 1, limit) == "чи" then
            local question, ending = simple(document, index + 1, limit, nil, 0)
            if question and question.question and boundary(document, ending, limit) then found = nil end
        end
        local locativeContrast
        if not found and comma and index < limit then
            local afterComma = index + 1
            local contrast = P.key(document, afterComma, limit) == "а"
            if tree.kind == "clause" then
                detached, detachedEnd = A.locativeEllipsis(document, afterComma + (contrast and 1 or 0), limit, tree)
                locativeContrast = detached ~= nil
                if locativeContrast then tree.locationEllipsisAnchor = true end
                if not detached then detached, detachedEnd = adjectiveFragment(document, afterComma, limit) end
            end
            if not detached and (tree.kind == "clause" or tree.kind == "nounPhrase") then
                local audience, finish = P.welcomeAudience(document, index + 1, limit)
                if audience and finish > limit then
                    detached, detachedEnd = {kind="welcoming", audience=audience}, finish
                end
            end
        end
        if found and last < limit then
            joins[#joins + 1] = {rule=found, comma=comma, dash=dash,
                consequence=found.id == "or" and P.key(document, last + 1, limit) == "else" or nil}
            index = last + 1
        elseif detached then
            joins[#joins + 1] = {comma=true, locativeContrast=locativeContrast}
            index = index + 1
        elseif tree.exclusion and (P.exclusionMarker(document.direction, P.key(document, index + (comma and 1 or 0), limit))
            or P.nominalRestriction(document, index + (comma and 1 or 0), limit)) then
            joins[#joins + 1] = {comma=true}
            if comma then index = index + 1 end
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
    if #trees == 0 or #joins >= #trees or index <= limit then
        local last = trees[#trees]
        local needsRelative = document.direction == "en-uk" and last and last.predicate
            and last.predicate.headIndex and last.predicateStart
            and index <= limit and not boundary(document, index, limit)
        return nil, needsRelative and {nounStart=last.predicateStart, nounHead=last.predicate.headIndex, subjectStart=index}
    end
    for i, join in ipairs(joins) do
        local action, followup = trees[i], trees[i + 1]
        if document.direction == "en-uk" and join.rule and join.rule.id == "or"
            and not (join.comma or join.dash or join.consequence)
            and action.imperative and action.negative
            and followup.imperative and not (followup.subject or followup.negative) then
            followup.negative = true
            join.sharedNegation = true
        end
        if join.rule and (join.rule.id == "purpose" or join.rule.id == "so" and not join.comma) then
            local obligation = action.verb and followup.subject and followup.verb
                and lexemeFrame(followup.verb).purposeObligation
            if join.rule.id == "purpose" then
                if not obligation then return nil end
                join.purposeObligation = true
            elseif obligation and followup.negative and followup.infinitiveEllipsis then
                join.purposeObligation = true
            end
        end
        if join.rule and join.rule.id == "exception" and action.verb and action.prepositions
            and #action.prepositions == 1 and followup.object and followup.object.pronoun then
            local topic = action.prepositions[1]
            if lexemeFrame(action.verb).requiredTopic == topic.rule.id and not personNoun(topic.object)
                and topic.object.number == "singular" then
                local gender = topic.object.gender
                local pronoun = followup.object.pronoun
                if document.direction == "en-uk" and pronoun.id == "it" and (gender == "feminine" or gender == "masculine") then
                    followup.object = personalSubject(gender == "feminine" and "she" or "he")
                elseif document.direction == "uk-en" and pronoun.person == 3 and pronoun.number == "singular"
                    and pronoun.gender == gender and followup.verb then
                    local classes = lexemeFrame(followup.verb).topicReferenceClasses
                    if classes and classes[P.semanticClass(topic.object)] then followup.object = personalSubject("it") end
                end
            end
        end
        if join.rule and join.rule.id == "if" and action.verb and lexemeFrame(action.verb).invitationProgressive
            and followup.infinitive and lexemeFrame(followup.infinitive.verb).accompaniment then
            if document.direction == "en-uk" and action.ellipticSubject and explicitTime(action) ~= "past" then
                action.ellipticSubject, action.subject = nil, personalSubject("i")
                action.tense, action.aspect = "present", "continuous"
            elseif document.direction == "uk-en" and action.tense == "present" then
                action.aspect = "continuous"
            end
        end
        if join.rule and join.rule.id == "if" and followup.verb and lexemeFrame(followup.verb).sense == "auctionInterest" then
            local actor = action.subject and action.subject.pronoun
            if document.direction == "uk-en" and followup.tense == "present" then
                followup.aspect = "continuous"
            elseif document.direction == "en-uk" and (action.imperative or action.tense == "present" and actor and actor.id == "i")
                and not action.negative and action.verb and lexemeFrame(action.verb).unmarkedPast
                and action.leadingAdverb and action.leadingAdverb.pastUk then
                action.imperative, action.tense = nil, "past"
                action.subject = action.subject or personalSubject("i")
            end
        end
        if join.rule and join.rule.id == "if" then conditionalEvent(document, action, followup) end
        if join.rule and join.rule.id == "when" then scheduledWhen(document, action, followup) end
        if join.rule and join.rule.id == "then" and action.tense == "future"
            and followup.tense == "future" and followup.inherited then
            action.sequencedEvent, followup.sequencedEvent = true, true
        elseif join.rule and (join.rule.id == "when" and action.imperative or join.rule.id == "whenever"
            or join.rule.id == "if" and (action.modal or action.tense == "future")) then
            followup.temporalDependent = true
            if document.direction == "en-uk" and join.rule.id == "if" and action.priceComparison then
                A.prospectiveEvent(followup)
            end
        end
    end
    local main = trees[2]
    if document.direction == "en-uk" and main then A.agreeCommandSeries(trees, joins) end
    if prefix and prefix.id == "because" and P.key(document, first, limit) == "since"
        and (not main or A.elapsedFromClause(main)) then return nil end
    if prefix and prefix.id == "when" and main then scheduledWhen(document, main, trees[1]) end
    if prefix and prefix.id == "if" and main then conditionalEvent(document, main, trees[1]) end
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
        for _, tree in ipairs(trees) do
            local frame = tree.verb and lexemeFrame(tree.verb)
            if frame and frame.auctionVerb and tree.object and auctionListing(tree) then
                local reading = L.choose(document, frame.auctionVerb, "verb", nil, "saleListing")
                if reading then tree.verb = reading end
            end
            chooseModalSense(tree, pastContext)
        end
    end
    return {trees=trees, joins=joins, prefix=prefix or discoursePrefix, discoursePrefix=prefix and discoursePrefix,
        dependency=trees[1].nominalAttachment or trees[1].standaloneAttachment or trees[1].questionAttachment}
end

local subjectModifiers = {det=true, amod=true, compound=true, flat=true, ["nmod:poss"]=true, nummod=true}

function A.relativeDomainCandidate(document, verbIndex, limit)
    if not L.functional(document, "prepositions", limit, limit) then return nil end
    local selected
    for _, entry in ipairs(L.at(document, verbIndex)) do
        if entry.lexeme.pos == "verb" then
            local rule = A.relativePrepositionAt(document, limit, limit, lexemeFrame(entry))
            if rule and rule.relativeDomain then
                if selected and selected ~= rule then return nil end
                selected = rule
            end
        end
    end
    return selected
end

local function unmarkedRelatives(document, first, limit, arcs, arcsFirst)
    if document.direction ~= "en-uk" then return nil end
    arcsFirst = arcsFirst or first
    local anchors, scopedRule, length = {}, nil, limit - arcsFirst + 1
    for offset = 2, length do
        local subject = arcs[offset]
        local rel = arcs[subject.head]
        local referentialIt = subject.relation == "expl" and P.key(document, arcsFirst + offset - 1, limit) == "it"
        -- The relative parser still has to find a subject and a governed gap.
        if (subject.relation == "nsubj" or referentialIt) and rel and rel.relation == "acl:relcl"
            and rel.head > 0 and rel.head < offset then
            local opening = offset
            for modifier = rel.head + 1, offset - 1 do
                local arc = arcs[modifier]
                if arc.head == offset and subjectModifiers[arc.relation] then opening = math.min(opening, modifier) end
            end
            local start = arcsFirst + opening - 1
            local mark = P.key(document, start, limit)
            if mark and not P.relativeMarkers[document.direction][mark] then
                anchors[start] = arcsFirst + rel.head - 1
                scopedRule = scopedRule or A.relativeDomainCandidate(document, arcsFirst + subject.head - 1, limit)
            end
        end
    end
    if not next(anchors) then return end
    document.relativeBudget, document.relativeDepth, document.relativeAnchors = 16, 0, anchors
    local parsed = parse(document, first, limit)
    if scopedRule and not document.transferDomain then
        document.relativeBudget, document.transferDomain = 16, scopedRule.relativeDomain
        local scoped = parse(document, first, limit)
        document.transferDomain = nil
        for _, tree in ipairs(scoped and scoped.trees or {}) do
            local relative = tree.copula and tree.predicate and tree.predicate.relative
            if relative and relative.preposition == scopedRule
                and P.semanticClass(tree.subject) == scopedRule.requiresClass then
                parsed = scoped
                break
            end
        end
    end
    document.relativeBudget, document.relativeDepth, document.relativeAnchors = nil, nil, nil
    if parsed then parsed.dependency = true; return parsed end
end

local dependencySequence

local function parseWithRelatives(document, first, limit, sentenceQuestion)
    local parsed, relative = parse(document, first, limit, sentenceQuestion)
    if parsed then return parsed end
    local markers = P.relativeMarkers[document.direction]
    local locative = P.locativeRelativeMarker[document.direction]
    for index = first + 1, limit - 1 do
        local token = document.tokens[index]
        if not token.protected and (markers[token.key] or token.key == locative) then
            local evidence = {}
            document.relativeBudget, document.relativeDepth, document.locativeRelative = 16, 0, evidence
            parsed = parse(document, first, limit, sentenceQuestion)
            document.relativeBudget, document.relativeDepth, document.locativeRelative = nil, nil, nil
            if parsed then
                if evidence.used then parsed.dependency = true end
                return parsed
            end
            break
        end
    end
    if not relative or not ns.UDPipeModels or limit - first >= 32 then return nil end
    local memo = document.coordinatedRelatives or {attempts=0}
    document.coordinatedRelatives = memo
    local range = first .. ":" .. limit
    if memo[range] ~= nil then return memo[range] or nil end
    if memo.attempts >= 3 then return nil end
    memo.attempts = memo.attempts + 1
    local parser = ns.Engine.UDPipe
    local arcs = parser.analyzeDocument(document, first, limit)
    parsed = arcs and unmarkedRelatives(document, first, limit, arcs)
    if not parsed and arcs and document.direction == "en-uk" then
        parsed = dependencySequence(document, first, limit, arcs)
    end
    if not parsed and memo.attempts < 3 then
        local subject, action = P.coordinated(document, relative.subjectStart, limit, "nominative",
            nil, nil, nil, nil, nil, true)
        if subject and verb(document, action, limit, subject, false) then
            memo.attempts = memo.attempts + 1
            local tags = {[relative.nounHead]="NOUN", [action]="VERB"}
            if subject.headIndex then tags[subject.headIndex] = "NOUN" end
            arcs = parser.analyzeDocument(document, relative.nounStart, limit, nil, nil, tags)
            parsed = arcs and unmarkedRelatives(document, first, limit, arcs, relative.nounStart)
        end
    end
    memo[range] = parsed or false
    return parsed
end

function A.chatProgressive(document, first, limit, forms, arcs)
    for _, index in ipairs(forms) do
        local arc = arcs[index - first + 1]
        if arc and (arc.relation == "root" or arc.relation == "acl") then
            local negative = P.key(document, index - 1, limit) == "not"
            local subjectEnd = index - (negative and 1 or 0)
            local subject, after = P.coordinated(document, first, subjectEnd - 1, "nominative")
            if subject and after == subjectEnd then
                local head = subject.headIndex or subject.pronoun and first
                local anchor = head and arcs[head - first + 1]
                local followingArc = arcs[index - first + 2]
                if followingArc and followingArc.relation == "advmod" then followingArc = arcs[followingArc.head] end
                local linkedProperty = anchor and arc.relation == "root" and anchor.relation == "compound"
                    and anchor.head == index - first + 1 and P.spatialContainer(subject)
                    and followingArc and followingArc.relation == "xcomp" and followingArc.head == anchor.head
                local reportsAction = anchor and (arc.relation == "root" and anchor.relation == "nsubj"
                    and anchor.head == index - first + 1 or arc.relation == "acl" and anchor.relation == "root"
                    and arc.head == head - first + 1 and not subject.article and not subject.possessor
                    and P.hasTrait(subject, "membershipGroup"))
                if reportsAction or linkedProperty then
                    local action, following = verb(document, index, limit, subject, false, false, nil, "present")
                    if action then
                        local tree = {kind="clause", subject=subject, verb=action, verbIndex=index,
                            tense="present", aspect="continuous", negative=negative,
                            question=P.key(document, limit + 1, #document.tokens) == "?"}
                        if complements(document, tree, following, limit, 0) == limit + 1
                            and (not linkedProperty or tree.property)
                            and (arc.relation == "root" or tree.object or tree.prepositions or tree.adverbs) then
                            return {trees={tree}, joins={}, dependency=true}
                        end
                    end
                end
            end
        end
    end
end

local function parseWithParticiples(document, first, limit)
    if document.direction ~= "en-uk" or limit - first >= 32 or not ns.UDPipeModels then return nil end
    local forms, ampersand = {}, nil
    for index = first + 1, limit do
        local token = document.tokens[index]
        if index < limit and (token.key:match("^[.!?]$") or token.key == "…")
            and ns.Engine.Parser.sentenceBoundary(document.text, document.tokens, index) then
            -- An omitted subject or nominal anchor belongs to this sentence.
            -- Composition also submits ranges that cross sentence boundaries.
            return nil
        end
        if not token.protected and token.key:match("ing$")
            and hasVerbForm(document, index, limit, {verbalForm="participle", tense="present"}) then
            -- A new reduced relative or chat progressive needs a nominal
            -- anchor. Marked gerunds belong to a complement, and later
            -- coordinated participles are read from the first action.
            local previous = index - 1
            local marked = L.functional(document, "prepositions", previous, previous)
                or L.functional(document, "connectors", previous, previous)
            if not marked or L.choose(document, previous, "noun")
                or L.functional(document, "adverbs", previous, previous) then
                forms[#forms + 1] = index
            end
        elseif token.key == "&" then ampersand = index end
    end
    if #forms == 0 then return nil end
    local memo = document.participleParses or {attempts=0}
    document.participleParses = memo
    local key = first .. ":" .. limit
    if memo[key] ~= nil then return memo[key] or nil end
    if memo.attempts == 3 then return nil end
    memo.attempts = memo.attempts + 1
    local arcs = ns.Engine.UDPipe.analyzeDocument(document, first, limit, ampersand, ampersand, nil,
        ampersand and {"CCONJ"})
    local status = arcs and A.chatProgressive(document, first, limit, forms, arcs)
    if status then memo[key] = status; return status end
    local function copularPrefix(index)
        local prefix = parse(document, first, index - 1)
        local tree = prefix and not prefix.prefix and #prefix.trees == 1 and prefix.trees[1]
        local predicate = tree and (tree.copula and tree.predicate or tree.descriptionLabel and tree.subject)
        return predicate and predicate.headIndex, tree and tree.tense,
            predicate and predicate.amount and predicate.amount.bound
    end
    local function copularAnchor(index, position)
        if position < 4 then return nil end
        local hasCopula
        for offset = 1, position - 1 do
            local arc = arcs[offset]
            local word = document.tokens[first + offset - 1].key
            if arc.head == position and arc.relation == "aux" and (copula[word] or word == "be") then
                hasCopula = true
                break
            end
        end
        if not hasCopula then return nil end
        local head, tense = copularPrefix(index)
        local attachment = head and arcs[head - first + 1]
        -- Retain the nominal predicate when the parser promotes its modifier to the root.
        if attachment and attachment.head == position and attachment.relation == "nsubj" then
            return {head=head, tense=tense}
        end
    end
    local anchors = {}
    if arcs then
        for _, index in ipairs(forms) do
            local offset = index - first + 1
            local arc = arcs[offset]
            local head = arcs[arc.head]
            if head and arc.head < offset and arc.relation == "acl" then
                anchors[index] = {head=first + arc.head - 1}
            elseif arc.relation == "root" then
                anchors[index] = copularAnchor(index, offset)
            elseif head and arc.head == offset - 1 and arc.relation == "advcl" and head.relation == "root" then
                local nominalHead, tense, boundedGroup = copularPrefix(index)
                if boundedGroup and nominalHead == first + arc.head - 1 then
                    anchors[index] = {head=nominalHead, tense=tense}
                end
            elseif head and arc.head < offset and arc.relation == "conj" and head.relation == "root" then
                -- A nonfinite action directly after a closed nominal predicate can
                -- describe that predicate even if Parsito labelled the edge conj.
                local nominalHead = first + arc.head - 1
                if copularPrefix(index) == nominalHead then
                    local coordinated
                    for _, dependency in ipairs(arcs) do
                        if dependency.head == offset and dependency.relation == "cc" then
                            coordinated = true
                            break
                        end
                    end
                    if not coordinated then anchors[index] = {head=nominalHead} end
                end
            elseif head and arc.head < offset and arc.relation == "conj" and head.relation == "nmod" then
                -- Resolve a mislabelled attachment only when transfer finds the
                -- same coordinated nominal and a closed list of participles.
                anchors[index] = {head=first + arc.head - 1, group=true}
            end
        end
    end
    local parsed
    if next(anchors) then
        document.relativeBudget, document.relativeDepth, document.participleAnchors = 16, 0, anchors
        parsed = parse(document, first, limit)
        document.relativeBudget, document.relativeDepth, document.participleAnchors = nil, nil, nil
    end
    memo[key] = parsed or false
    if parsed then parsed.dependency = true; return parsed end
end



local temporalRules = {
    controlledTemporal.before,
    {id="if", en={"if"}, uk={"якщо"}, initialOnly=true, unpunctuated=true, reverseAttachment=true,
        preferRealizedCondition=true},
    {id="when", en={"when"}, uk={"коли"}, temporal=true, unpunctuated=true, reverseAttachment=true},
    {source="uk", en={"after"}, uk={"після того як"}, ukTags={"ADP", "PRON", "SCONJ"},
        nominalHead=2, temporal=true, reverseAttachment=true},
    {source="uk", en={"after"}, uk={"після того, як"}, ukPattern="після того , як",
        ukTags={"ADP", "PRON", "PUNCT", "SCONJ"}, nominalHead=2, temporal=true},
    controlledTemporal.after,
    {id="since", en={"since"}, uk={"відтоді, як"}, ukPattern="відтоді , як",
        ukTags={"ADV", "PUNCT", "SCONJ"}, temporal=true, startBoundary=true, reverseAttachment=true},
    {id="until", en={"until"}, uk={"доки"}, ukStatus="аж до того, як", temporal=true, reverseAttachment=true},
    {source="uk", id="until", en={"until"}, uk={"аж до того, як"}, ukPattern="аж до того , як",
        ukTags={"ADV", "ADP", "PRON", "PUNCT", "SCONJ"}, nominalHead=3, temporal=true},
    {en={"once"}, uk={"щойно"}, temporal=true, futureLocation=true},
    {en={"by the time"}, uk={"на той час, коли"}, ukPattern="на той час , коли",
        ukTags={"ADP", "DET", "NOUN", "PUNCT", "ADV"}, nominalHead=3, temporal=true, deadline=true},
    {en={"next time"}, uk={"наступного разу, коли"}, ukPattern="наступного разу , коли",
        enTags={"ADJ", "NOUN"}, ukTags={"ADJ", "NOUN", "PUNCT", "ADV"},
        nominalHead=2, temporal=true, prospective=true},
    {source="en", en={"every time", "each time"}, uk={"щоразу, коли"}, enTags={"DET", "NOUN"},
        nominalHead=2, temporal=true, recurring=true},
    {source="en", en={"whenever"}, uk={"щоразу, коли"}, temporal=true, recurring=true, reverseAttachment=true},
    {source="uk", en={"every time"}, uk={"щоразу, коли"}, ukPattern="щоразу , коли",
        ukTags={"ADV", "PUNCT", "SCONJ"}, temporal=true, recurring=true, reverseAttachment=true},
    {source="uk", en={"every time"}, uk={"щоразу, коли"}, ukPattern="щоразу коли",
        ukTags={"ADV", "SCONJ"}, temporal=true, recurring=true, reverseAttachment=true},
    {source="uk", en={"every time"}, uk={"кожного разу, коли"}, ukPattern="кожного разу , коли",
        ukTags={"DET", "NOUN", "PUNCT", "ADV"}, nominalHead=2, temporal=true, recurring=true},
}

local function temporalMarker(document, first, limit)
    local source = document.direction == "en-uk" and "en" or "uk"
    for _, rule in ipairs(temporalRules) do
        if not rule.source or rule.source == source then
            for _, surface in ipairs(rule[source]) do
                local index = first
                local pattern = source == "uk" and rule.ukPattern or surface
                for word in pattern:gmatch("%S+") do
                    if P.key(document, index, limit) ~= word then index = nil; break end
                    index = index + 1
                end
                if index and index <= limit then return rule, index - 1 end
            end
        end
    end
end

local function finiteClause(parsed, dependent)
    if not parsed or parsed.prefix then return false end
    local tree = parsed.trees[1]
    local predicate = tree.kind == "clause" and (tree.verb or tree.copula)
        or tree.kind == "need" and tree.predicateIndex
    return predicate and (not dependent or not tree.imperative)
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
        if pp.case == "locative" and spatialAdjuncts[pp.rule.id]
            and inClass(pp.object, actionFrame.contextLocation) then return true end
    end
    return false
end

local function temporalClauses(document, mainFirst, mainLast, subordinateFirst, subordinateLast, sentenceQuestion, rule)
    local domain = temporalDomain(document, mainFirst, mainLast, subordinateFirst, subordinateLast)
    if domain then
        document.transferDomain = domain
        local action = parseWithRelatives(document, mainFirst, mainLast, sentenceQuestion)
        local ending = finiteClause(action) and parseWithRelatives(document, subordinateFirst, subordinateLast, false)
        document.transferDomain = nil
        if matchesTemporalDomain(action, ending, domain) then return action, ending end
    end

    local action = parseWithRelatives(document, mainFirst, mainLast, sentenceQuestion)
    if not finiteClause(action) then return nil end
    local ending = parseWithRelatives(document, subordinateFirst, subordinateLast, false)
    if finiteClause(ending, true) then return action, ending end
    if document.direction == "uk-en" and rule.id == "until" and rule.uk[1] == "доки" then
        local endpoint, finish = A.frontedIntransitivePredicate(document, subordinateFirst, subordinateLast, 0, true)
        if endpoint and finish > subordinateLast then return action, {trees={endpoint}, joins={}} end
    end
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

local function temporalArcs(parser, document, first, last, marker, markerEnd, markerTags, main, dependent, commaBefore, later,
    preferVerbHeads)
    local english = document.direction == "en-uk"
    local tags = (not english or ns.UDPipeTagWeights) and {} or nil
    local alternatives, readings
    if not english and marker == first and markerEnd > marker and parser.ukNominalHint then
        local clause = dependent.trees[1]
        local object = clause.object
        local position = markerEnd + 1
        local subject = clause.subject and clause.subject.pronoun and clause.verbIndex and position < clause.verbIndex
            and P.pronoun(document, position, position, "nominative")
        if subject and subject.pronoun == clause.subject.pronoun and object and object.headIndex
            and object.headIndex > clause.verbIndex and lexemeFrame(clause.verb).reverseObjectClasses then
            local accusative = parser.ukNominalHint(object, "accusative")
            if accusative then
                -- Keep the locally established cases when a syncretic object can be tagged as a subject.
                tags[position], tags[object.headIndex] = parser.ukNominalHint(subject, "nominative"), accusative
            end
        end
    end
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
            if not english then
                if preferVerbHeads and tree.verbIndex then tags[tree.verbIndex] = "VERB" end
                if preferVerbHeads and marker == markerEnd and parser.ukNominalHint then
                    local subject, object = tree.subject, tree.object
                    local subjectIndex = subject and subject.headIndex
                    if subject and subject.pronoun and clause == dependent and not subjectIndex
                        and tree.verbIndex and markerEnd + 1 < tree.verbIndex
                        and P.pronoun(document, markerEnd + 1, markerEnd + 1, "nominative", nil, nil, subject.pronoun.id) then
                        subjectIndex = markerEnd + 1
                    end
                    if subjectIndex then tags[subjectIndex] = parser.ukNominalHint(subject, "nominative") end
                    if object and object.headIndex then
                        tags[object.headIndex] = parser.ukNominalHint(object, object.sourceCase or "accusative")
                    end
                end
                markInfinitives(tags, tree)
                if tree.locativeAdverbIndex then tags[tree.locativeAdverbIndex] = "ADV" end
            end
            if tags and tree.predicateIndex and tree.predicateAdverb and tree.predicateAdverb.impersonalTiming then
                tags[tree.predicateIndex] = english and "ADJ" or "ADV"
                if english and tree.contractedSubjectIndex then
                    readings = readings or {}
                    readings[tree.contractedSubjectIndex] = {
                        pos="PRON", modelForm="it", lemma="it", feats="Case=Nom|Gender=Neut|Number=Sing|Person=3|PronType=Prs",
                        auxiliary={form="is", lemma="be", upos="AUX", feats="Mood=Ind|Number=Sing|Person=3|Tense=Pres|VerbForm=Fin"},
                    }
                end
            end
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
    return parser.analyzeDocument(document, first, last, marker, markerEnd, tags, markerTags, alternatives, commaBefore, readings)
end

local function confirmedAttachment(arcs, offset, start, finish, subordinateFirst, subordinateLast, mainFirst, mainLast, rule, timingIndex)
    if rule.recurring and start < mainFirst then
        local position = start + (rule.nominalHead or 1) - 1 - offset
        local marker, relativeMarker = arcs[position], arcs[finish - offset]
        for index = subordinateFirst, subordinateLast do
            local clause = arcs[index - offset]
            local nominalTime = marker.relation == "obl:tmod" and marker.head + offset == index and clause.head == 0
            local adverbialTime = marker.head == 0 and clause.relation == "advcl" and clause.head == position
                and relativeMarker.relation == "mark" and relativeMarker.head + offset == index
            if nominalTime or adverbialTime then
                for action = mainFirst, mainLast do
                    local principal = arcs[action - offset]
                    if principal.relation == "parataxis" and principal.head + offset == index then return true end
                end
            end
        end
    end
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
        local timingBoundary = arc and rule == controlledTemporal.before and timingIndex == arc.head + offset
        if arc and (arc.relation == "mark"
                or rule.nominalHead and marker == finish and arc.relation == "advmod")
            and arc.head > 0 then
            local dependent = arc.head + offset
            local predicate = arcs[arc.head]
            local parent = predicate.head + offset
            if rule.reverseAttachment and arc.relation == "mark" and predicate.head == 0
                and dependent >= subordinateFirst and dependent <= subordinateLast then
                -- An explicit multiword marker fixes the temporal role when the model reverses the link.
                for index = mainFirst, mainLast do
                    local main = arcs[index - offset]
                    local linked = main.relation == "advcl" or rule.unpunctuated and main.relation == "parataxis" or start < finish
                        and (main.relation == "parataxis" or main.relation == "conj")
                    if linked and main.head + offset == dependent then return true end
                end
            end
            -- A complete multiword temporal marker identifies the relation.
            -- In such cases the model still has to link the two clauses.
            local attached = predicate.relation:match("^advcl") or timingBoundary and predicate.relation == "advmod" or start < finish
                and (predicate.relation == "acl" or predicate.relation == "ccomp")
            if not attached and rule.nominalHead and marker == finish and predicate.relation == "parataxis" then
                local noun = arcs[start + rule.nominalHead - 1 - offset]
                local governor = noun and noun.head + offset
                attached = noun and noun.relation == "obl" and governor >= mainFirst and governor <= mainLast
            end
            if dependent >= subordinateFirst and dependent <= subordinateLast and attached and predicate.head > 0 then
                -- The relative clause in a nominal time expression may attach through its noun.
                if rule.nominalHead or rule.reverseAttachment and start < finish then
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

function A.confirmTemporalPredicateHeads(parser, document, first, last, marker, markerEnd, markerTags, rule, main, dependent, arcs)
    if document.direction ~= "uk-en" or not arcs or marker == markerEnd or rule.nominalHead
        or not rule.reverseAttachment or #main.trees ~= 1 or #dependent.trees ~= 1 then return false end
    local mainHead = main.trees[1].verbIndex
    local subordinate = dependent.trees[1]
    local dependentHead = subordinate.verbIndex
    if not (mainHead and dependentHead) then return false end
    local offset = first - 1
    local subjectIndex = markerEnd + 1
    local subject = subordinate.subject and subordinate.subject.pronoun and subjectIndex < dependentHead
        and P.pronoun(document, subjectIndex, dependentHead - 1, "nominative")
    local subjectHead = subject and subject.pronoun == subordinate.subject.pronoun and subjectIndex - offset
    local function attached(readings)
        local predicate = readings and readings[dependentHead - offset]
        if not predicate or predicate.head + offset ~= mainHead or not (predicate.relation:match("^advcl")
            or predicate.relation == "conj" or predicate.relation == "ccomp") then return false end
        local subjectArc = subjectHead and readings[subjectHead]
        for index = marker, markerEnd do
            local arc = readings[index - offset]
            if arc and arc.relation == "mark" then
                if arc.head + offset == dependentHead then return true end
                if subjectArc and arc.head == subjectHead and subjectArc.head + offset == dependentHead then
                    return true
                end
            end
        end
        return false
    end
    if attached(arcs) then return true end
    return attached(temporalArcs(parser, document, first, last, marker, markerEnd, markerTags, main, dependent,
        nil, nil, true))
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

function A.hasEndpointNegation(tree)
    if tree.tense ~= "future" or not tree.negative or tree.question or tree.modal or tree.conditional then return false end
    if locativeState(tree) then return true end
    local action = tree.verb
    return action and (action.form.aspect or action.head.aspect) == "perfective"
end

local function explicitUntilBoundary(document, rule, main, dependent, comma)
    if rule.id ~= "until" or rule.uk[1] ~= "доки" or #main.trees ~= 1 or #dependent.trees ~= 1
        or not main.trees[1].imperative then return false end
    local endpoint = dependent.trees[1]
    if not endpoint.subject or endpoint.question then return false end
    if document.direction == "en-uk" then return endpoint.tense == "present" and locativeState(endpoint) end
    return comma and A.hasEndpointNegation(endpoint)
end

function A.contextualTemporalReading(document, action, event)
    if not event.verb or not event.verbIndex or event.recipient or event.controlled
        or event.infinitive or event.prepositions then return end
    local english = document.direction == "en-uk"
    local person = event.verb.form.person
    if not (personNoun(event.subject) or not english and not event.subject and (person == 1 or person == 2)) then return end
    local actionEntry = action.verb or action.kind == "need"
        and L.choose(document, english and "need" or "потребувати", "verb", nil, nil, function(candidate)
            local frame = lexemeFrame(candidate)
            return frame.impersonalNeed and frame.temporalObjectSenses
        end)
    local senses = actionEntry and lexemeFrame(actionEntry).temporalObjectSenses
    if not senses then return end
    local sense = senses[P.semanticClass(action.object)]
    for _, member in ipairs(action.object and action.object.members or {}) do
        local candidate = senses[P.semanticClass(member)]
        if sense and candidate and sense ~= candidate then return end
        sense = candidate or sense
    end
    if not sense then return end
    local object = event.object
    if english and object or not english and (not object or not object.entry or object.number ~= "singular"
        or object.adjectives or object.possessor or object.demonstrative or object.quantity or object.argument
        or object.relative or object.prepositions) then return end
    local entry = L.choose(document, event.verbIndex, "verb", nil, sense, function(candidate)
        local frame = lexemeFrame(candidate)
        return frame.contextRole == "followup" and (english and not frame.contextOnly
            or not english and frame.spokenObject == object.entry.lexeme.en)
    end)
    if not entry then return end
    event.verb = entry
    if not english then event.object = nil end
end

local function joined(document, left, right, junction, prefix, tail, dependency)
    local subordinate = prefix and left or right
    local main = prefix and right or left
    local rule = prefix or junction.rule
    local english = document.direction == "en-uk"
    local action = main.trees[1]
    if rule and rule.startBoundary then
        action.since = true
        if english and action.presentPerfect and not (action.negative or action.object)
            and action.verb and lexemeFrame(action.verb).elapsedDuration then
            action.tense, action.aspect = "present", nil
        end
    end
    if rule and rule.id == "if" then conditionalEvent(document, action, subordinate.trees[1]) end
    local futureAction = action.imperative or action.modal or action.tense == "future"
    local intention = action.infinitive
    local plannedBoundary = english and rule == controlledTemporal.before and action.question and action.verb
        and lexemeFrame(action.verb).prospectiveDesire and intention and not action.negative and not intention.negative
        and not (recurringEvent(action) or recurringEvent(intention) or recurringEvent(subordinate.trees[1]))
    if plannedBoundary and intention.verb and intention.object and lexemeFrame(intention.verb).boundedConditionalFuture then
        intention.intendedEvent = true
    end
    for _, tree in ipairs(subordinate.trees) do
        if rule and rule.temporal then A.contextualTemporalReading(document, action, tree) end
        if not rule or rule.id ~= "when" or action.imperative or action.tense == "future" then
            tree.temporalDependent = true
        end
        tree.temporalRecurring = rule and rule.recurring
        if rule and rule.prospective and tree.tense == "present" then tree.tense = "future" end
        local frame = tree.verb and lexemeFrame(tree.verb)
        local speaker = tree.subject and tree.subject.pronoun
        local plannedQuestion = prefix and action.question and speaker and speaker.id == "i"
            and frame and frame.ukDefaultAdjunct
        if english and rule and rule.prospectiveEvent and (futureAction or plannedQuestion or plannedBoundary) then
            A.prospectiveEvent(tree)
        end
        if english and rule == controlledTemporal.before and futureAction and tree.tense == "present"
            and tree.predicateAdverb and tree.predicateAdverb.impersonalTiming then tree.tense = "future" end
        if rule and rule.id == "when" then scheduledWhen(document, action, tree) end
        if english and rule and rule.futureLocation and futureAction and locativeState(tree) and tree.tense == "present" then
            tree.tense = "future"
        end
        if rule and rule.id == "until" and rule.uk[1] == "доки" then
            if english and not tree.negative and tree.tense == "present" and futureAction and locativeState(tree) then
                tree.tense, tree.expletiveNegative = "future", true
            elseif not english and A.hasEndpointNegation(tree) then
                tree.negative, tree.expletiveNegative = nil, true
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

function A.confirmOpeningCondition(document, arcs, first, main, condition)
    local marker = arcs[1]
    local command = main.imperative and main.verbIndex
    local head = condition.verbIndex
    local object = condition.object and condition.object.headIndex
    if not (marker and command and head and object) then return false end
    local predicate, argument = arcs[head - first + 1], arcs[object - first + 1]
    local governor = command - first + 1
    if marker.relation ~= "mark" or marker.head ~= governor or not predicate or not argument
        or argument.head ~= head - first + 1 or argument.relation ~= "obj" then return false end
    if predicate.head == governor then
        return predicate.relation:match("^advcl") or predicate.relation == "parataxis:discourse"
    end
    local subject = condition.subject
    local index = subject and subject.headIndex
    if not index and subject and subject.pronoun and first + 1 < head
        and P.pronoun(document, first + 1, first + 1, "nominative", nil, nil, subject.pronoun.id) then
        index = first + 1
    end
    local subjectArc = index and arcs[index - first + 1]
    return predicate.relation == "acl:relcl" and subjectArc and predicate.head == index - first + 1
        and subjectArc.relation == "nsubj" and subjectArc.head == governor
end

local function unpunctuatedTemporal(document, parser, first, limit, rule, markerEnd, markerTags, budget)
    local subordinateFirst = markerEnd + 1
    local split, main, dependent, evidence, ambiguous
    local attempts = 0
    local finiteMain = rule.recurring or rule.unpunctuated
    for index = subordinateFirst + 2, limit do
        local subject, nextIndex
        if finiteMain then subject, nextIndex = P.noun(document, index, limit, "nominative", false, nil, true) end
        if subject then
            local _, afterAdverb = adverbAt(document, nextIndex, limit)
            nextIndex = afterAdverb or nextIndex
        end
        local head = subject and P.key(document, nextIndex, limit)
        local finite = head and (copula[head] or negativeCopula[head] or auxiliary[head] or have[head]
            or negativePerfect[head] or verb(document, nextIndex, limit, subject, false))
        local english = document.direction == "en-uk"
        local command = not english and P.key(document, index, limit) == "не" and index + 1 or index
        if finite or verb(document, command, limit, nil, english, true) then
            attempts = attempts + 1
            if attempts > 4 then return nil end
            local action, timing = temporalClauses(document, index, limit, subordinateFirst, index - 1, nil, rule)
            if action and timing.trees[1].subject
                and (action.trees[1].imperative or finiteMain and action.trees[1].subject) then
                local condition = timing.trees[1]
                local realization = rule.preferRealizedCondition and action.trees[1].imperative
                    and (condition.object or condition.infinitive or condition.content) and 1 or 0
                if not split or realization > evidence then
                    split, main, dependent, evidence, ambiguous = index, action, timing, realization, nil
                elseif realization == evidence then
                    if not rule.preferRealizedCondition then return nil end
                    ambiguous = true
                end
            end
        end
    end
    if not split or ambiguous then return nil end
    budget.remaining = budget.remaining - 1
    local offset = first - 1
    local arcs = temporalArcs(parser, document, first, limit, first, markerEnd, markerTags, main, dependent, split,
        nil, rule.preferRealizedCondition)
    if not arcs then return nil end
    local attached = confirmedAttachment(arcs, offset, first, markerEnd,
        subordinateFirst, split - 1, split, limit, rule)
    if not attached and rule.preferRealizedCondition and document.direction == "uk-en" then
        -- When the marker attaches to the directive, confirm the dependent
        -- predicate by its direct object and its relation to the directive.
        attached = A.confirmOpeningCondition(document, arcs, first, main.trees[1], dependent.trees[1])
    end
    if not attached and rule.nominalHead and main.trees[1].imperative then
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

local function temporalChain(document, parser, first, limit, marker, markerEnd, markerTags, rule, mainEnd, budget)
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
    if document.direction == "en-uk" and (rule.startBoundary and not A.elapsedFromClause(main.trees[1])
        or later.rule.startBoundary and not A.elapsedFromClause(middle.trees[1])) then return nil end
    budget.remaining = budget.remaining - 1
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

local temporalAttachment
do
local function searchTemporalAttachment(document, parser, first, limit, budget)
    local attempts = 0
    for marker = first, limit - 1 do
        local rule, markerEnd = temporalMarker(document, marker, limit)
        if rule and (marker == first or not rule.initialOnly) then
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
                            subordinateFirst, separator - 1, nil, rule)
                        if main and rule.startBoundary and document.direction == "en-uk"
                            and not A.elapsedFromClause(main.trees[1]) then return nil end
                        if main then
                            budget.remaining = budget.remaining - 1
                            local arcs = temporalArcs(parser, document, first, limit, marker, markerEnd,
                                markerTags, main, dependent)
                            local endpoint = dependent.trees[1]
                            local timingIndex = endpoint.predicateAdverb and endpoint.predicateAdverb.impersonalTiming and endpoint.predicateIndex
                            local attachment = arcs and confirmedAttachment(arcs, first - 1, marker, markerEnd,
                                subordinateFirst, separator - 1, separator + 1, limit, rule, timingIndex)
                            attachment = attachment or A.confirmTemporalPredicateHeads(parser, document, first, limit, marker, markerEnd,
                                markerTags, rule, main, dependent, arcs)
                            if attachment or explicitUntilBoundary(document, rule, main, dependent, true) then
                                return joined(document, dependent, main, {comma=true}, rule, nil, attachment or nil)
                            end
                            return nil
                        end
                    end
                end
                if (not hasSeparator or rule.recurring) and (rule.nominalHead or rule.recurring or rule.unpunctuated)
                    and limit - subordinateFirst >= 3 then
                    return unpunctuatedTemporal(document, parser, first, limit, rule, markerEnd, markerTags, budget)
                end
            else
                attempts = attempts + 1
                if attempts > 4 then return nil end
                local comma = P.key(document, marker - 1, limit) == ","
                local mainEnd = marker - (comma and 2 or 1)
                if mainEnd >= first then
                    local tail = temporalTail(document, subordinateFirst + 1, limit)
                    local finish = tail and tail.finish or limit
                    local question = not tail and P.key(document, limit + 1, #document.tokens) == "?"
                    local main, dependent = temporalClauses(document, first, mainEnd, subordinateFirst, finish, question, rule)
                    if main and rule.startBoundary and document.direction == "en-uk"
                        and not A.elapsedFromClause(main.trees[1]) then return nil end
                    if main then
                        budget.remaining = budget.remaining - 1
                        local arcs = temporalArcs(parser, document, first, finish, marker, markerEnd,
                            markerTags, main, dependent)
                        local endpoint = dependent.trees[1]
                        local timingIndex = endpoint.predicateAdverb and endpoint.predicateAdverb.impersonalTiming and endpoint.predicateIndex
                        local attachment = arcs and confirmedAttachment(arcs, first - 1, marker, markerEnd,
                            subordinateFirst, finish, first, mainEnd, rule, timingIndex)
                        if not attachment and comma then
                            attachment = A.confirmTemporalPredicateHeads(parser, document, first, finish, marker, markerEnd,
                                markerTags, rule, main, dependent, arcs)
                        end
                        if attachment or explicitUntilBoundary(document, rule, main, dependent, comma) then
                            return joined(document, main, dependent, {rule=rule}, nil, tail, attachment or nil)
                        end
                        return nil
                    end
                    if not tail then
                        local remaining = budget.remaining
                        local chain = temporalChain(document, parser, first, limit, marker, markerEnd, markerTags, rule,
                            mainEnd, budget)
                        if chain or budget.remaining < remaining then return chain end
                    end
                end
            end
        end
    end
end

function temporalAttachment(document, first, limit)
    local parser = ns.Engine.UDPipe
    if not parser or not ns.UDPipeModels or limit - first >= 32 then return nil end
    local budget = document.temporalAttachment
    if not budget then
        budget = {remaining=3, rejected={}}
        document.temporalAttachment = budget
    end
    local rejected = budget.rejected[first]
    if budget.remaining == 0 or rejected and rejected[limit] then return nil end
    local remaining = budget.remaining
    local parsed = searchTemporalAttachment(document, parser, first, limit, budget)
    if not parsed and budget.remaining < remaining then
        if not rejected then
            rejected = {}
            budget.rejected[first] = rejected
        end
        rejected[limit] = true
    end
    return parsed
end
end

local function frontedRange(document, first, limit)
    local english = document.direction == "en-uk"
    if P.key(document, first, limit) ~= (english and "from" or "від")
        or limit - first >= 32 or not ns.UDPipeModels then return nil end
    local origin, nextAt = P.preposition(document, first, limit)
    if not origin or origin.rule.id ~= "from" or not origin.object.headIndex then return nil end
    local endpoint, body = P.preposition(document, nextAt, limit)
    if not endpoint or endpoint.rule.id ~= "to" or not endpoint.object.headIndex then return nil end
    local landmark, after = P.preposition(document, body, limit)
    if landmark and landmark.rule.id == "near" and landmark.object.headIndex then body = after
    else landmark = nil end
    local comma = P.key(document, body, limit) == ","
    if english and not comma then return nil end
    local core = parseWithRelatives(document, body + (comma and 1 or 0), limit)
    local tree = core and not core.prefix and core.trees[1]
    local governor = tree and tree.verbIndex
    if not governor or not tree.subject then return nil end
    local originHead, endpointHead = origin.object.headIndex, endpoint.object.headIndex
    local tags = {[originHead]="NOUN", [endpointHead]="NOUN", [governor]="VERB"}
    local arcs = ns.Engine.UDPipe.analyzeDocument(document, first, limit, nil, nil, tags)
    if not arcs then return nil end
    local offset = first - 1
    local startMarker, endMarker = arcs[1], arcs[nextAt - offset]
    local startArc, endArc = arcs[originHead - offset], arcs[endpointHead - offset]
    if startMarker.relation ~= "case" or startMarker.head + offset ~= originHead
        or endMarker.relation ~= "case" or endMarker.head + offset ~= endpointHead
        or startArc.relation ~= "obl" or startArc.head + offset ~= governor then return nil end
    if not (endArc.relation == "nmod" and endArc.head + offset == originHead
        or endArc.relation == "obl" and endArc.head + offset == governor) then return nil end
    if landmark then
        local site = arcs[landmark.object.headIndex - offset]
        if not (site.relation == "nmod" and site.head + offset == endpointHead
            or not english and site.relation == "obl" and site.head + offset == governor) then return nil end
    end
    origin.targetUk = origin.rule.literalTargetUk
    core.openingPrepositions, core.dependency = {origin, endpoint, landmark}, true
    return core
end

local frontedTemporalPreposition

function A.anonymousPastPassive(document, first, limit)
    if document.direction ~= "uk-en" then return nil end
    local question = P.key(document, first, limit) == "чи"
        or P.key(document, limit + 1, #document.tokens) == "?"
    local start = first + (P.key(document, first, limit) == "чи" and 1 or 0)
    local marker = P.key(document, start, limit) == "на" and "на" or nil
    if marker then start = start + 1 end
    local partial = P.key(document, start, limit) == "не"
    if partial then start = start + 1 end
    local patient, after, floatingAll
    local quantifier = P.key(document, start, limit)
    local of = (quantifier == "всіх" or quantifier == "усіх") and P.key(document, start + 1, limit)
    if of == "з" or of == "із" or of == "зі" then
        patient, after = P.pronoun(document, start + 2, limit, "genitive", true)
        if not patient then patient, after = P.coordinated(document, start + 2, limit, "genitive") end
        if not (patient and patient.number == "plural") then return nil end
        floatingAll = true
    else
        patient, after = P.coordinated(document, start, limit, "accusative")
        if patient and patient.pronoun and patient.number == "plural" then
            local following = P.key(document, after, limit)
            if following == "усіх" or following == "всіх" then floatingAll, after = true, after + 1 end
        end
    end
    if not patient and marker then patient, after = P.pronoun(document, start, limit, "accusative", true) end
    if not patient or after > limit or partial and not (patient.all or floatingAll) then return nil end
    local negative = P.key(document, after, limit) == "не"
    if partial and negative then return nil end
    local at = after + (negative and 1 or 0)
    local action = L.choose(document, at, "verb", {tense="past", number="plural"}, nil, function(candidate)
        local frame = lexemeFrame(candidate)
        return frame.passiveVoice and frame.objectPreposition == marker and not candidate.form.verbalForm
    end)
    if not action then return nil end
    local possibleActor = not marker and P.noun(document, start, after - 1, "nominative")
    if possibleActor and possibleActor.number == "plural" and personNoun(possibleActor) then return nil end
    if partial then patient.all = nil end
    local tree = {kind="clause", subject=patient, verb=action, verbIndex=at, aspect="passive",
        tense="past", negative=negative or partial, question=question,
        allSubject=partial or floatingAll, allUnderNegation=partial}
    local finish = complements(document, tree, at + 1, limit, 0)
    if finish == limit + 1 then return {trees={tree}, joins={}} end
end

function A.frontedPastOffset(document, first, limit, allowSpatial)
    local offset, after = P.pastOffset(document, first, limit)
    if not offset or after > limit then return nil end
    local comma = P.key(document, after, limit) == ","
    local start = after + (comma and 1 or 0)
    local core = parseWithRelatives(document, start, limit)
        or allowSpatial and A.frontedSpatialOpening(document, start, limit, true)
    local tree = core and not core.prefix and core.trees[1]
    if not tree or tree.tense ~= "past" or tree.pastOffset then return nil end
    offset.fronted, offset.comma, offset.first, offset.last = true, comma, first, start - 1
    if core.openingPrepositions then core.openingPastOffset = offset
    else tree.pastOffset = offset end
    return core
end

local function parseGroup(document, first, limit)
    local parsed = A.frontedPastOffset(document, first, limit, true)
        or parseWithRelatives(document, first, limit) or A.anonymousPastPassive(document, first, limit)
    if parsed then return parsed end
    local conditional = P.key(document, first, limit) == (document.direction == "en-uk" and "if" or "якщо")
    -- Try the explicit clause marker before looking for unmarked participles.
    if conditional then
        parsed = temporalAttachment(document, first, limit)
        if parsed then return parsed end
    end
    return parseWithParticiples(document, first, limit)
        or frontedRange(document, first, limit) or frontedControlledTime(document, first, limit)
        or not conditional and temporalAttachment(document, first, limit)
        or A.socialSequence(document, first, limit)
        or frontedTemporalPreposition(document, first, limit)
end

function A.discourseQuestion(document, first, limit)
    local lead, ending = verb(document, first, limit, nil, document.direction == "en-uk", true)
    if not lead or ending > limit or not lexemeFrame(lead).discourseCommand then return nil end
    local start = ending + (P.key(document, ending, limit) == "," and 1 or 0)
    if start > limit then return nil end
    local question = parseGroup(document, start, limit)
    if not question or question.prefix or not question.trees[1].question then return nil end
    local command, after = simple(document, first, ending - 1, nil, 0)
    if command and command.imperative and after == ending then
        table.insert(question.trees, 1, command)
        table.insert(question.joins, 1, {comma=true})
        return question
    end
end

do
local function finiteSequencePredicate(tree)
    return tree and tree.kind == "clause" and tree.verb and tree.verbIndex and tree.subject
        and not (tree.question or tree.imperative or tree.wh or tree.perception or tree.controlled
            or tree.modal or tree.infinitive)
end

local function sequenceLink(arcs, first, left, right, subjectEnd)
    local leftIndex, rightIndex = left.verbIndex - first + 1, right.verbIndex - first + 1
    local a, b = arcs[leftIndex], arcs[rightIndex]
    local function coordinated(arc, head)
        return arc.head == head and (arc.relation == "conj" or arc.relation == "parataxis")
    end
    if not (coordinated(a, rightIndex) or coordinated(b, leftIndex)) then return false end
    for index = subjectEnd - first + 1, #arcs do
        local arc = arcs[index]
        if (arc.head == leftIndex or arc.head == rightIndex)
            and (arc.relation:match("^nsubj") or arc.relation:match("^csubj")) then return false end
    end
    return true
end

function A.unmarkedSharedSubject(document, first, limit)
    local parser = ns.Engine.UDPipe
    if not parser or not ns.UDPipeModels or limit - first < 2 or limit - first >= 32
        or (document.sequenceAttempts or 0) >= 3 then return nil end
    local subject, subjectEnd = P.noun(document, first, limit, "nominative", false, nil, true)
    if not subject or not hasVerbForm(document, subjectEnd, limit, {}) then return nil end

    local seed = {subject=subject}
    local checked = 0
    for split = subjectEnd + 1, limit do
        local previous, current = document.tokens[split - 1], document.tokens[split]
        if not previous.key:match("^%p$") and not previous.protected and not current.protected
            and current.first > previous.last + 1 and not clauseConnector(document, split - 1, limit)
            and hasVerbForm(document, split, limit, {mood="indicative"}) then
            checked = checked + 1
            if checked > 3 then break end
            local right, ending = simple(document, split, limit, seed, 0)
            if finiteSequencePredicate(right) and right.inherited and ending == limit + 1 then
                local left, finish = simple(document, first, split - 1, nil, 0)
                if not left and right.object then
                    local objects = right.object.members
                    document.coordinateObject = P.semanticClass(objects and objects[1] or right.object)
                    if document.coordinateObject then left, finish = simple(document, first, split - 1, nil, 0) end
                    document.coordinateObject = nil
                end
                if finiteSequencePredicate(left) and finish == split then
                    document.sequenceAttempts = (document.sequenceAttempts or 0) + 1
                    right.subject = left.subject
                    local tags = {[left.verbIndex]="VERB", [right.verbIndex]="VERB"}
                    local arcs = parser.analyzeDocument(document, first, limit, nil, nil, tags)
                    local attached = arcs and sequenceLink(arcs, first, left, right, subjectEnd)
                    if not attached and not lexemeFrame(left.verb).content then
                        -- The morphology supplies two finite predicates. Ask the same
                        -- model to evaluate the candidate boundary as chat punctuation.
                        arcs = parser.analyzeDocument(document, first, limit, nil, nil, tags, nil, nil, split)
                        attached = arcs and sequenceLink(arcs, first, left, right, subjectEnd)
                    end
                    if attached then
                        return {trees={left,right}, joins={{comma=true}}, dependency=true}
                    end
                    if document.sequenceAttempts >= 3 then return nil end
                end
            end
        end
    end
end
end

local function questionTail(document, first, limit, preferred)
    local language = document.direction == "en-uk" and "en" or "uk"
    local grammar = ns.Linguistics.grammar
    local endings = grammar.preferredQuestionTailEndings
    if preferred and not (endings and endings[language][P.key(document, limit, limit)]) then return nil end
    local widths = grammar.indexWidths
    local width = widths and widths[language].adverbs or 3
    for opening = math.max(first + 1, limit - width + 1), limit do
        local tail, after = adverbAt(document, opening, limit, "questionTail")
        if tail and tail.context == "questionTail" and after == limit + 1
            and (tail.preferQuestionTail == true) == preferred then
            local comma = P.key(document, opening - 1, limit) == ","
            local before = opening - (comma and 2 or 1)
            local parsed = before >= first and parseGroup(document, first, before)
            local tree = parsed and parsed.trees[#parsed.trees]
            local person = tree and tree.subject and tree.subject.person
            local frame = tree and tree.verb and lexemeFrame(tree.verb)
            local request = tree and tree.modal and not tree.modalPerfect
                and (person == 1 or person == 2 or tree.controlled or tree.recipient or frame and frame.ellipticRequest)
            if tree and tree.question and (not tail.modalRequestOnly or request) then
                parsed.questionTail, parsed.questionTailComma = tail, comma
                return parsed
            end
        end
    end
end

function A.speakerComment(document, first, limit)
    if first >= limit then return nil end
    local grammar = ns.Linguistics.grammar
    local entries = grammar.speakerComments
    if not entries then return nil end
    local english = document.direction == "en-uk"
    local lang = english and "en" or "uk"
    local width = grammar.indexWidths[lang].speakerComments
    local function core(start, stop)
        local parsed = parseGroup(document, start, stop)
        if parsed then return parsed end
        local noun, after = P.coordinated(document, start, stop, "nominative")
        if not noun or after <= stop then noun, after = P.amount(document, start, stop, "nominative") end
        if noun and after == stop + 1 then return {trees={{kind="nounPhrase", subject=noun}}, joins={}} end
    end
    local leading, last = L.functional(document, "speakerComments", first, limit)
    local leadingComment = leading and entries[leading[1]]
    local leadingComma = leading and P.key(document, last + 1, limit) == ","
    local body = leading and last + (leadingComma and 2 or 1)
    if leadingComment and not leadingComment.trailingOnly
        and body <= limit
        and (leadingComma or english and leadingComment.omitLeadingCommaEn) then
        local address = leadingComment.directAddress and A.addressAt(document, body, limit)
        if address then
            return {trees={{kind="greeting", recipient=address, expression=leadingComment}}, joins={}}
        end
        local parsed = core(body, limit)
        if parsed then
            parsed.speakerComment, parsed.speakerCommentFirst = leadingComment, true
            return parsed
        end
    end
    for opening = math.max(first + 1, limit - width + 1), limit do
        local trailing, finish = L.functional(document, "speakerComments", opening, limit)
        if trailing and finish == limit then
            local comment = entries[trailing[1]]
            local comma = P.key(document, opening - 1, limit) == ","
            local stop = opening - (comma and 2 or 1)
            if stop < first or (not english or comment.requiresComma) and not comma
                or ns.Engine.Parser.sentenceBoundary(document.text, document.tokens, stop) then return nil end
            local parsed = core(first, stop)
            if not parsed then return nil end
            if not comma and comment.requiresBoundPredicate then
                local tree = parsed.trees[#parsed.trees]
                if not tree.predicativeRelative then return nil end
            end
            if not comma and comment.possibleObjectGap then
                local tree = #parsed.trees == 1 and parsed.trees[1]
                local noun = tree and tree.kind == "nounPhrase" and tree.subject
                local measure = noun and noun.quantity
                    and (P.hasTrait(noun, "durationUnit") or P.semanticClass(noun) == "timeBoundary")
                if not measure then
                    local parser = ns.Engine.UDPipe
                    local arcs = parser and parser.analyzeDocument(document, first, limit)
                    local edge = arcs and arcs[limit - first + 1]
                    -- Keep an unmarked relative when the comment verb can govern its object.
                    if not edge or edge.relation == "acl:relcl" or edge.relation == "acl" then return nil end
                    parsed.dependency = true
                end
            end
            parsed.speakerComment = comment
            return parsed
        end
    end
end

function A.levelAnnouncement(document, first, limit)
    local opening = P.key(document, first, limit)
    local level, after
    if document.direction == "en-uk" and opening == "ding" then
        local start = first + (P.key(document, first + 1, limit) == "," and 2 or 1)
        if start > limit then return {kind="levelAnnouncement"} end
        level, after = P.levelAt(document, start, limit)
        if not level then level, after = P.levelNumberAt(document, start, limit), start + 1 end
    elseif document.direction == "uk-en" and opening == "новий"
        and P.key(document, first + 1, limit) == "рівень" then
        local mark = P.key(document, first + 2, limit)
        if not mark then return {kind="levelAnnouncement"} end
        local start = first + ((mark == "—" or mark == "–" or mark == ":") and 3 or 2)
        level, after = P.levelNumberAt(document, start, limit), start + 1
        if P.key(document, after, limit) == "-" and P.key(document, after + 1, limit) == "й" then after = after + 2 end
    end
    if level and after == limit + 1 then return {kind="levelAnnouncement", level=level} end
end

function A.hypotheticalQuestion(document, first, limit)
    local english = document.direction == "en-uk"
    local head = P.key(document, first, limit)
    local contrast = english and head == "but" or not english and (head == "а" or head == "але")
    local start = first + (contrast and 1 or 0)
    if contrast and P.key(document, start, limit) == "," then start = start + 1 end
    if P.key(document, start, limit) ~= (english and "what" or "що") then return nil end
    local opener, after = adverbAt(document, start, limit, "hypotheticalOpening")
    if not opener or opener.context ~= "hypotheticalOpening" or after > limit then return nil end
    local parsed = parseGroup(document, after, limit)
    local tree = parsed and parsed.trees[1]
    if not tree or tree.imperative or tree.question or not (tree.verb or tree.copula or tree.kind == "need") then return nil end
    if english then
        for _, child in ipairs(parsed.trees) do
            if not recurringEvent(child) then A.prospectiveEvent(child) end
        end
    end
    parsed.hypothetical, parsed.hypotheticalContrast = opener, contrast
    return parsed
end

function A.leadingAddress(document, first, limit)
    local english = document.direction == "en-uk"
    local address, start, explicit
    for at = first + 1, math.min(first + 4, limit - 1) do
        if P.key(document, at, limit) == "," then
            address = A.addressAt(document, first, at - 1, true)
            start, explicit = at + 1, true
            break
        end
    end
    if not explicit and english then
        local opening = L.choose(document, first, "noun", {number="plural"}, nil, function(entry)
            return lexemeFrame(entry).unpunctuatedPluralAddress
        end)
        if opening then address, start = A.addressAt(document, first, first, true), first + 1 end
    end
    if not address then return nil end
    local parsed = parseGroup(document, start, limit)
    local tree = parsed and parsed.trees[1]
    local subject = tree and not tree.implicitSubject and tree.subject
    local secondPerson = subject and subject.person == 2
    if not (tree and (tree.imperative or (tree.verb or tree.copula) and (explicit or secondPerson))) then
        return nil
    end
    if english and address.number == "plural" then
        if secondPerson and subject.pronoun and subject.pronoun.id == "you" then
            tree.subject = personalSubject("you_plural")
        elseif tree.imperative then
            tree.imperativeNumber = "plural"
        end
    end
    parsed.leadingAddress = address
    return parsed
end

function A.messageFollowup(document, first, limit)
    if document.direction ~= "en-uk" or first <= 2 or limit - first < 2 then return nil end
    local parser, tokens = ns.Engine.Parser, document.tokens
    if not parser.sentenceBoundary(document.text, tokens, first - 1) then return nil end
    local group, at = P.pronoun(document, first, limit, "nominative")
    local modal = group and group.number == "plural" and auxiliary[P.key(document, at, limit)]
    if not modal or modal.modal ~= "can" then return nil end
    local domain
    for _, reading in ipairs(L.at(document, at + 1)) do
        local frame = reading.lexeme.frame
        if frame and frame.contextRole == "messageFollowup" then
            if domain and domain ~= frame.contextDomain then return nil end
            domain = frame.contextDomain
        end
    end
    if domain ~= "groupRecruitment" then return nil end
    local start, ending = first - 2, first - 2
    while start > 1 and ending - start < 31
        and not parser.sentenceBoundary(document.text, tokens, start - 1) do
        start = start - 1
    end
    if start > 1 and not parser.sentenceBoundary(document.text, tokens, start - 1) then return nil end
    local opening = parseGroup(document, start, ending)
    local tree = opening and opening.trees[#opening.trees]
    local action = tree and (tree.infinitive or tree)
    local frame = action and action.verb and lexemeFrame(action.verb)
    local role = tree and tree.kind == "need" and tree.object
    if not (role and P.semanticClass(role) == "roles"
        or frame and frame.groupRoleVerb and P.hasTrait(action.object, "clearableInstance")) then return nil end
    local previous = document.transferDomain
    document.transferDomain = domain
    local followup, finish = simple(document, first, limit, nil, 0)
    document.transferDomain = previous
    if followup and finish > limit and followup.verb and lexemeFrame(followup.verb).contextDomain == domain then
        return {trees={followup}, joins={}}
    end
end

function A.nominalExclamation(document, first, limit)
    local english = document.direction == "en-uk"
    local opening, marker = P.key(document, first, limit), P.key(document, first + 1, limit)
    local start
    if english and opening == "what" and (marker == "a" or marker == "an") then start = first + 1
    elseif not english and opening == "оце" and marker == "так" then start = first + 2 end
    if not start or start > limit then return nil end
    local parsed = parseGroup(document, start, limit)
    local tree = parsed and #parsed.trees == 1 and parsed.trees[1]
    if not (tree and tree.kind == "nounPhrase" and tree.subject) then
        local noun, finish = P.noun(document, start, limit, "nominative")
        if not noun or finish <= limit then return nil end
        tree = {kind="nounPhrase", subject=noun}
        parsed = {trees={tree}, joins={}}
    end
    parsed.exclamation, tree.exclamative = true, true
    return parsed
end

function A.trailingNameAddress(document, first, limit)
    if limit <= first then return nil end
    local comma = P.key(document, limit - 1, limit) == ","
    local english = document.direction == "en-uk"
    local command = L.choose(document, first, "verb", {mood=english and "base" or "imperative"}, nil, function(entry)
        local frame = lexemeFrame(entry)
        return comma or frame.intransitive and frame.rejectDirectObject
    end)
    if not command then return nil end
    local name = P.openName(document, limit, limit)
    if not name then return nil end
    local ending = limit - (comma and 2 or 1)
    if ending < first then return nil end
    local parsed = parseGroup(document, first, ending)
    local action = parsed and parsed.trees[#parsed.trees]
    local frame = action and action.verb and lexemeFrame(action.verb)
    if not (action and action.imperative and not action.addressee
        and (comma or frame and frame.intransitive and frame.rejectDirectObject)) then return nil end
    action.addressee = {raw=name, person=3, number="singular"}
    return parsed
end

function A.guildHeadingWord(text, tokens, first, last)
    local label, word, ending = tokens[last - 2], tokens[last - 1], tokens[last]
    if not ending or ending.key ~= "!" or not word or word.protected
        or not label or not label.protected or text:sub(label.first, label.first) ~= "<" then return end
    if first ~= last - 2 then
        local language = tokens[first]
        if first ~= last - 3 or not language.protected or text:sub(language.first, language.first) ~= "[" then return end
    end
    if text:sub(word.first, word.last):match("^[A-Z]+$") then return last - 1 end
end

function A.parse(document, first, limit, afterRating)
    if not afterRating then
        local rating, following = P.ratingNote(document, first, limit)
        if rating then
            if following > limit then return {trees={{kind="ratingNote"}}, joins={}, rating=rating} end
            local parsed = A.parse(document, following, limit, true)
            if parsed then
                parsed.rating = rating
                return parsed
            end
        end
    end
    local menu = P.menuPath(document, first, limit)
    if menu then return {trees={menu}, joins={}} end
    local scopedActivities = A.activityListScope(document, first, limit)
    if scopedActivities then return scopedActivities end
    local announcement = A.levelAnnouncement(document, first, limit)
    if announcement then return {trees={announcement}, joins={}} end
    if first < limit and document.spans[first] then
        for _, candidate in ipairs(document.spans[first]) do
            local features = candidate.term.features
            if candidate.last == limit and features and features.canStandAlone then
                local noun, after = P.noun(document, first, limit, "nominative")
                if noun and noun.term == candidate.term and after == limit + 1 then
                    return {trees={{kind="nounPhrase", subject=noun}}, joins={}}
                end
                break
            end
        end
    end
    local provider, finish = P.preposition(document, first, limit, nil, nil, "providerAttribution", nil, "openProperName")
    if provider and finish > limit then return {trees={{kind="nounPhrase", prepositions={provider}}}, joins={}} end
    local key = P.key(document, first, limit)
    if key == (document.direction == "en-uk" and "name" or "ім'я") then
        local separator = P.key(document, first + 1, limit)
        local start = first + ((separator == ":" or separator == "—") and 2 or 1)
        local name, after = P.openName(document, start, limit)
        local label = name and after > limit and L.choose(document, first, "noun", nil, "personalPossession")
        if label then return {trees={{kind="nameLabel", label=label, rawName=name}}, joins={}} end
    end
    if key == "what" or key == "оце" then
        local exclamation = A.nominalExclamation(document, first, limit)
        if exclamation then return exclamation end
    end
    local token = document.tokens[first]
    if first < limit and token.protected and document.direction == "en-uk" then
        local word = A.guildHeadingWord(document.text, document.tokens, first, limit + 1)
        local action = word and L.choose(document, word, "verb", {tense="present", verbalForm="participle"}, nil,
            function(candidate)
                local frame = lexemeFrame(candidate)
                return not frame.requiresDirectObject and (frame.recruitmentActor == "we"
                    or frame.openEndedActivity and frame.intransitive)
            end)
        if action then
            local tree = {kind="clause", subject=personalSubject("we"), verb=action, verbIndex=word,
                tense="present", aspect="continuous", leadingLabel=P.raw(document, first, word - 1)}
            return {trees={tree}, joins={}}
        end
    end
    if first < limit and token.protected and not token.linkKind
        and P.key(document, limit + 1, #document.tokens) == "?" then
        local label = P.raw(document, first, first):match("^<[^<>]+>$")
        local inquiry = label and parseGroup(document, first + 1, limit)
        local tree = inquiry and inquiry.trees[1]
        local subject = tree and tree.question and not tree.implicitSubject and tree.subject
        if subject and subject.person == 2 and not inquiry.prefix then
            tree.leadingLabel = label
            return inquiry
        end
    end
    local polite, after = adverbAt(document, first, limit, nil, A.isPolitenessMarker)
    if polite then
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
    if key == "by" or key == "за" then
        local authority, after = P.preposition(document, first, limit, nil, nil, nil, nil, "authorityOpening")
        if authority then
            local comma = P.key(document, after, limit) == ","
            local start = after + (comma and 1 or 0)
            local core = start <= limit and parseGroup(document, start, limit)
            if core and core.trees[1].kind == "clause" then
                core.openingPrepositions = {authority}
                core.openingPrepositionComma = authority.apposition ~= nil
                return core
            end
        end
    end
    local linkedAddress = limit - first <= 7 and document.tokens[limit].linkKind == "player"
    if linkedAddress then
        local address = A.addressAt(document, first, limit, false, true)
        if address and address.addressName then
            return {trees={{kind="greeting", recipient=address, bareAddress=true}}, joins={}}
        end
    end
    local parsed = A.hypotheticalQuestion(document, first, limit) or A.speakerComment(document, first, limit)
        or questionTail(document, first, limit, true) or parseGroup(document, first, limit)
        or A.leadingAddress(document, first, limit) or A.messageFollowup(document, first, limit)
        or A.trailingNameAddress(document, first, limit)
    if not (parsed or linkedAddress) and limit - first <= 7 then
        local address = A.addressAt(document, first, limit, false, true)
        if address then return {trees={{kind="greeting", recipient=address, bareAddress=true}}, joins={}} end
    end
    if parsed or limit <= first then return parsed end
    parsed = A.frontedSpatialOpening(document, first, limit)
    if parsed then return parsed end
    local scope, after = adverbAt(document, first, limit, nil, function(candidate) return candidate.scopesMainClause end)
    if scope then
        local start = after + (P.key(document, after, limit) == "," and 1 or 0)
        local connector = start < limit and temporalMarker(document, start, limit)
        parsed = connector and connector.id == "when" and parseGroup(document, start, limit)
        local main = parsed and parsed.prefix and parsed.prefix.id == "when" and parsed.trees[2]
        if main and main.verb and not main.leadingAdverb then
            main.leadingAdverb = scope
            return parsed
        end
    end
    return questionTail(document, first, limit, false)
        or A.discourseQuestion(document, first, limit) or A.unmarkedSharedSubject(document, first, limit)
end

local independentRelations = {root=true, parataxis=true, conj=true, ["acl:relcl"]=true}

local function independentPredicate(tree, relation)
    local frame = tree.verb and lexemeFrame(tree.verb)
    -- A separate clause must supply arguments that a relative could borrow.
    if relation == "acl:relcl" and not (tree.object or tree.prepositions or tree.controlled) then return false end
    return tree.copula or frame and (frame.intransitive or frame.motion or tree.object
        or tree.controlled or tree.content or tree.infinitive or tree.perception)
end

function A.socialSequence(document, first, limit, arcs)
    if not arcs and (not ns.UDPipeModels or limit - first >= 32) then return nil end
    local social, split = socialComplement(document, first, limit, 0, true)
    if not social or split >= limit then return nil end
    if not arcs and not social.social.audience then return nil end
    local token, previous = document.tokens[split], document.tokens[split - 1]
    if token.first <= previous.last + 1 or token.protected or previous.protected
        or token.key:match("^%p$") or P.relativeMarkers[document.direction][token.key] then return nil end
    local right = parseWithRelatives(document, split, limit)
    local clause = right and not right.prefix and #right.trees == 1 and right.trees[1]
    if not clause or clause.kind ~= "clause" or not clause.subject or clause.question or clause.wh then return nil end
    local predicate = clause.verbIndex or clause.predicateIndex
    arcs = arcs or ns.Engine.UDPipe.analyzeDocument(document, first, limit, nil, nil,
        predicate and {[predicate]="VERB"} or nil)
    local arc = predicate and arcs and arcs[predicate - first + 1]
    if not arc or not (independentRelations[arc.relation]
        or arc.relation == "ccomp" and arc.head > 0 and arc.head <= split - first) then return nil end
    if independentPredicate(clause, arc.relation) then
        return {trees={social,clause}, joins={{sentence=true, punctuation=social.social.audience and "!" or nil}}, dependency=true}
    end
end

do
local function overtDeicticObject(document, first, limit, arcs, governor)
    for index = governor + 1, limit - first + 1 do
        local arc = arcs[index]
        if arc.head == governor and arc.relation == "obj" then
            local word = P.key(document, first + index - 1, limit)
            if word == "it" or word == "this" or word == "that" then return true end
        end
    end
end

dependencySequence = function(document, first, limit, arcs, words)
    local attempts = 0
    local ukrainian = document.direction == "uk-en"
    for offset = 3, limit - first do
        local subject = arcs[offset]
        local predicate = subject.head
        local relation = arcs[predicate] and arcs[predicate].relation
        local auxiliary = arcs[offset + 1]
        local detached = subject.relation == "nsubj" and predicate and predicate > offset
            and independentRelations[relation]
        local nextPredicate = ukrainian and words and words[offset + 1].upos == "AUX" and auxiliary.head and auxiliary.head > offset
        -- An overt object can close the clause before we spend another inference on a possible relative gap.
        local candidates = (detached or nextPredicate) and (words and words[offset].upos == "PRON"
            or not words and overtDeicticObject(document, first, limit, arcs, predicate))
        if candidates then
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
                    if independentPredicate(rightTree, relation) then
                        return {trees={leftTree,rightTree}, joins={{sentence=true}}, dependency=true}
                    end
                end
                if attempts == 3 then break end
            end
        end
    end
end
end

local function frontedPrepositionGovernor(arcs, first)
    local marker = arcs[1]
    local noun = marker and marker.relation == "case" and marker.head > 1 and arcs[marker.head]
    if noun and noun.relation:match("^[^:]+") == "obl" and noun.head > marker.head then
        return first + noun.head - 1, first + marker.head - 1
    end
end

local function attachFrontedPreposition(document, core, first, ending, governor, keepOpening)
    local tree = core and core.trees[1]
    if not tree or (tree.verbIndex or tree.predicateIndex) ~= governor then return nil end
    -- Decode the same constituent with the governing predicate's actual valency.
    local frame = tree.verb and lexemeFrame(tree.verb) or {}
    local adjunct, after = P.preposition(document, first, ending, frame.motion,
        frame.displacesObject and tree.object ~= nil, prepositionContext(tree, frame))
    if not adjunct or after ~= ending + 1 then return nil end
    if keepOpening then
        core.openingPrepositions = {adjunct}
    else
        tree.prepositions = tree.prepositions or {}
        table.insert(tree.prepositions, 1, adjunct)
    end
    core.dependency = true
    return core
end

local function frontedPreposition(document, first, limit, arcs, words)
    local governor = frontedPrepositionGovernor(arcs, first)
    if not governor or governor > limit then return nil end

    local group = P.dependencyNominals(document, first, arcs, words, {}, true)[1]
    if not group or group.first ~= first or not group.preposition or group.last >= governor then return nil end
    local start = group.last + 1
    if P.key(document, start, limit) == "," then start = start + 1 end
    local core = parseWithRelatives(document, start, limit)
    return attachFrontedPreposition(document, core, first, group.last, governor)
end

function A.frontedSpatialOpening(document, first, limit, allowSingle)
    if not ns.UDPipeModels or limit - first < 4 or limit - first >= 32
        or (document.spatialOpeningAttempts or 0) >= 2 then return nil end
    local primary, start = P.preposition(document, first, limit)
    local noun = primary and primary.object.headIndex
    if not noun or not spatialAdjuncts[primary.rule.id] then return nil end
    local last = start - 1
    local qualifiers = {}
    for _ = 1, 2 do
        local location, after = P.preposition(document, start, limit)
        local head = location and location.object.headIndex
        if not head or not spatialAdjuncts[location.rule.id] then break end
        qualifiers[#qualifiers + 1] = {phrase=location, marker=start, head=head}
        start = after
    end
    local comma = P.key(document, start, limit) == ","
    if comma then start = start + 1 end
    local timed = A.frontedPastOffset(document, start, limit)
    if not timed and #qualifiers == 0 and not allowSingle then return nil end
    local core = timed or parseWithRelatives(document, start, limit)
    local tree = core and not core.prefix and core.trees[1]
    local predicate = tree and (tree.verbIndex or tree.predicateIndex)
    if not predicate then return nil end

    local hints = {[first]="ADP", [noun]="NOUN", [predicate]=tree.verbIndex and "VERB" or "ADJ"}
    for _, location in ipairs(qualifiers) do
        hints[location.marker], hints[location.head] = "ADP", "NOUN"
    end
    document.spatialOpeningAttempts = (document.spatialOpeningAttempts or 0) + 1
    -- The temporal quantity is already attached to this finite clause. Exclude
    -- it from this inference, which checks only the spatial attachments.
    local arcs = ns.Engine.UDPipe.analyzeDocument(document, first, limit, nil, nil, hints,
        nil, nil, nil, nil, timed and tree.pastOffset)
    if not arcs then return nil end
    local governor, anchor = frontedPrepositionGovernor(arcs, first)
    if governor ~= predicate or anchor ~= noun then return nil end
    local parent = noun
    for _, location in ipairs(qualifiers) do
        local marker = arcs[location.marker - first + 1]
        local position = location.head - first + 1
        local attachment = arcs[position]
        if not marker or marker.relation ~= "case" or marker.head ~= position or not attachment then return nil end
        local relation, head = attachment.relation:match("^[^:]+"), first + attachment.head - 1
        if not (relation == "nmod" and (head == noun or head == parent)
            or relation == "obl" and head == governor) then return nil end
        parent = location.head
    end
    core = attachFrontedPreposition(document, core, first, last, predicate, true)
    if not core then return nil end
    core.openingPrepositionComma = comma
    for _, location in ipairs(qualifiers) do
        core.openingPrepositions[#core.openingPrepositions + 1] = location.phrase
    end
    return core
end

frontedTemporalPreposition = function(document, first, limit)
    local phrase, after = P.preposition(document, first, limit)
    local noun = phrase and phrase.rule.temporalAdjunct and phrase.object.headIndex
    if not noun or after > limit or after - first > 8 then return nil end
    local comma = P.key(document, after, limit) == ","
    local start = after + (comma and 1 or 0)
    local core = parseWithRelatives(document, start, limit)
    local tree = core and not core.prefix and core.trees[1]
    local predicate = tree and (tree.verbIndex or tree.predicateIndex)
    if not predicate then return nil end
    local tags = {[first]="ADP", [noun]="NOUN", [predicate]=tree.verbIndex and "VERB" or "ADJ"}
    local arcs = ns.Engine.UDPipe.analyzeDocument(document, first, limit, nil, nil, tags)
    if not arcs then return nil end
    local governor, attachedNoun = frontedPrepositionGovernor(arcs, first)
    local nominalArc = arcs[noun - first + 1]
    local infinitive = tree.infinitive
    local restoredBoundary
    if governor ~= predicate and not comma and nominalArc and nominalArc.relation == "root" and tree.subject then
        -- The complete temporal phrase and the finite clause license a boundary
        -- which chat spelling can leave unmarked. Parse it with the same weights.
        if infinitive and infinitive.verbIndex then tags[infinitive.verbIndex] = "VERB" end
        for _, step in ipairs(infinitive and infinitive.series or {}) do
            tags[step.action.verbIndex] = "VERB"
        end
        local alternate = ns.Engine.UDPipe.analyzeDocument(document, first, limit, nil, nil, tags, nil, nil, start)
        if alternate then
            governor, attachedNoun = frontedPrepositionGovernor(alternate, first)
            restoredBoundary = governor == predicate and attachedNoun == noun
        end
    end
    if governor ~= predicate or attachedNoun ~= noun then return nil end
    local keepOpening = restoredBoundary or infinitive and infinitive.series
    return attachFrontedPreposition(document, core, first, after - 1, governor, keepOpening)
end

local function completeLocativeSubject(document, start, limit)
    local subject, finish = P.noun(document, start, limit, "nominative")
    if not subject or finish ~= limit + 1 then return nil end
    local head = subject.headIndex or (subject.raw or subject.pronoun) and start
    if head then return subject, head end
end

local function frontedNominalLocation(document, tree, start, first, limit, arcs, locationPosition, place)
    local subject, head = completeLocativeSubject(document, start, limit)
    if not subject then return nil end
    for _, adjective in ipairs(subject.adjectives or {}) do
        if lexemeFrame(adjective.entry).predicateLocation then return nil end
    end
    local position = head - first + 1
    local subjectArc, locationArc = arcs[position], arcs[locationPosition]
    if subjectArc and locationArc and (subjectArc.relation == "nsubj" and subjectArc.head == locationPosition
        or subjectArc.relation == "root" and locationArc.relation == "obl" and locationArc.head == position) then
        tree.subject, tree.prepositions = subject, {place}
        return {trees={tree}, joins={}, dependency=true}
    end
end

local function frontedLocativePredicate(document, first, limit, arcs)
    local marker = arcs[1]
    if not marker or marker.relation ~= "case" or marker.head <= 1 then return nil end
    local place, cursor = P.preposition(document, first, limit, nil, nil, "predicate")
    if not place or not (spatialAdjuncts[place.rule.id] or place.rule.id == "out-of-location")
        or first + marker.head - 1 >= cursor then return nil end

    local english = document.direction == "en-uk"
    local key = P.key(document, cursor, limit)
    local negative = not english and key == "не"
    local predicateIndex = cursor + (negative and 1 or 0)
    key = P.key(document, predicateIndex, limit)
    local verbKey = negativeCopula[key] or key
    local tense = copula[verbKey]
    local subjectStart = predicateIndex + 1
    if tense and english and P.key(document, subjectStart, limit) == "not" then
        negative, subjectStart = true, subjectStart + 1
    end
    negative = negative or negativeCopula[key] ~= nil
    if not tense and english then return nil end
    local tree = {kind="clause", copula=true, tense=tense or "present", negative=negative}
    if not tense and not negative then
        local declarative = frontedNominalLocation(document, tree, cursor, first, limit, arcs, marker.head, place)
        if declarative then return declarative end
    end
    local subject, subjectHead = completeLocativeSubject(document, subjectStart, limit)
    if not subject then return nil end

    local subjectPosition, predicatePosition = subjectHead - first + 1, predicateIndex - first + 1
    local subjectArc, predicateArc, locationArc = arcs[subjectPosition], arcs[predicatePosition], arcs[marker.head]
    if not (subjectArc and predicateArc and locationArc) then return nil end
    local subjectBound = subjectArc.relation:match("^[^:]+") == "nsubj" and subjectArc.head == predicatePosition
    tree.subject = subject
    if tense then
        if not subjectBound and (predicateArc.relation ~= "cop"
            or predicateArc.head ~= subjectPosition and predicateArc.head ~= marker.head) then return nil end
        local plural = subject.number == "plural"
        if english then
            local many = plural or subject.person == 2
            local expected = tense == "past" and (many and "were" or "was")
                or many and "are" or subject.person == 1 and "am" or "is"
            if verbKey ~= expected then return nil end
        else
            local expected = ukCopulaAgreement[key]
            if expected and expected ~= (plural and "plural" or subject.gender) then return nil end
        end
        tree.prepositions = {place}
    else
        if not subjectBound and locationArc.head ~= predicatePosition
            and (predicateArc.relation ~= "amod" or predicateArc.head ~= subjectPosition) then return nil end
        tree.frontedLocation = place
        local ending = predicate(document, tree, predicateIndex, subjectStart - 1, 1)
        tree.frontedLocation = nil
        if not tree.adjective or ending ~= subjectStart then return nil end
    end
    return {trees={tree}, joins={}, dependency=true}
end

do
(function()
local reverseTemporalLinks = {advcl=true, parataxis=true, ccomp=true, xcomp=true}

local function temporalHeads(arcs, limit, reverse)
    local marker = arcs[1]
    if not marker or marker.relation ~= "mark" or marker.head <= 1 or marker.head > limit then return nil end
    local endpoint = arcs[marker.head]
    if not endpoint then return nil end
    if endpoint.relation:match("^advcl") and endpoint.head > marker.head and endpoint.head <= limit then
        return marker.head, endpoint.head
    end
    if not reverse or endpoint.head ~= 0 then return nil end
    local principal
    for position = marker.head + 1, limit do
        local arc = arcs[position]
        if arc and arc.head == marker.head and reverseTemporalLinks[arc.relation] then
            if principal then return nil end
            principal = position
        end
    end
    if principal then return marker.head, principal, true end
end

local function dependencyOwner(arcs, position, left, right, count)
    for _ = 1, count do
        if position == left or position == right then return position end
        local arc = arcs[position]
        if not arc or arc.head == 0 then return nil end
        position = arc.head
    end
end

local function dependencyPredicateMatches(tree, position, word)
    if not tree or not word then return false end
    if word.upos == "VERB" then return tree.verbIndex == position end
    return word.upos == "ADJ" and tree.copula and tree.adjective and tree.predicateIndex == position
end

function A.temporalFromDependencies(document, first, limit, arcs, words)
    local rule, markerEnd = temporalMarker(document, first, limit)
    if not rule or rule.nominalHead or not (rule.temporal or rule.id == "if") then return nil end
    local count = limit - first + 1
    local endpoint, principal, reversed = temporalHeads(arcs, count, rule.reverseAttachment)
    if not endpoint and (not arcs[1] or arcs[1].relation ~= "mark")
        and not document.temporalMarkerRetagged and ns.UDPipeModels
        and (not document.temporalAttachment or document.temporalAttachment.remaining > 0) then
        document.temporalMarkerRetagged = true
        if document.temporalAttachment then
            document.temporalAttachment.remaining = document.temporalAttachment.remaining - 1
        end
        local markerTags = document.direction == "uk-en" and rule.ukTags or rule.enTags
        local guided = ns.Engine.UDPipe.analyzeDocument(document, first, limit, first, markerEnd, nil, markerTags)
        if guided then
            arcs = guided
            endpoint, principal, reversed = temporalHeads(arcs, count, rule.reverseAttachment)
        end
    end
    if not endpoint or not words[endpoint] or not words[principal]
        or (words[endpoint].upos ~= "VERB" and words[endpoint].upos ~= "ADJ")
        or words[principal].upos ~= "VERB" then return nil end

    local mainFirst
    for index = markerEnd + 1, limit do
        local position = index - first + 1
        local arc = arcs[position]
        if arc and arc.relation ~= "punct" then
            local key = document.tokens[index].key
            local negatesPrincipal = position == principal - 1 and (key == "не" or key == "don't" or key == "dont")
            local owner = negatesPrincipal and principal or dependencyOwner(arcs, position, endpoint, principal, count)
            if owner == principal then
                mainFirst = mainFirst or index
            elseif owner ~= endpoint or mainFirst then
                return nil
            end
        end
    end
    if not mainFirst or mainFirst <= markerEnd + 1 then return nil end
    local comma = P.key(document, mainFirst - 1, limit) == ","
    local main, dependent = temporalClauses(document, mainFirst, limit, markerEnd + 1,
        mainFirst - (comma and 2 or 1), nil, rule)
    local action, condition = main and main.trees[1], dependent and dependent.trees[1]
    if not dependencyPredicateMatches(action, first + principal - 1, words[principal])
        or not dependencyPredicateMatches(condition, first + endpoint - 1, words[endpoint])
        or reversed and not action.imperative then return nil end
    local objectPronoun = action.object and action.object.pronoun
    if words[endpoint].upos == "ADJ" and objectPronoun and objectPronoun.person == 3 and condition.subject
        and not action.object.targetPronoun then
        local source, target = A.pronounReference(document, condition.subject)
        if not source or target and source == objectPronoun.id then return nil end
    end
    if rule.startBoundary and document.direction == "en-uk" and not A.elapsedFromClause(action) then return nil end
    return joined(document, dependent, main, {comma=true}, rule, nil, true)
end

local function coordinatedRanges(arcs, words, left, right, separator, count)
    local leftSubject, rightSubject
    for index = 1, count do
        local arc = arcs[index]
        if not arc or not words[index] then return false end
        if index ~= separator and arc.relation ~= "punct" then
            local expected = index < separator and left or right
            if dependencyOwner(arcs, index, left, right, count) ~= expected then return false end
            if arc.head == expected and arc.relation:match("^nsubj") then
                if expected == left then leftSubject = true else rightSubject = true end
            end
        end
    end
    return leftSubject and rightSubject
end

function A.coordinatedFromDependencies(document, first, limit, arcs, words)
    local count = limit - first + 1
    for offset = 2, count - 1 do
        local marker = arcs[offset]
        local right = marker and marker.relation == "cc" and marker.head
        local clause = right and arcs[right]
        local left = clause and clause.relation == "conj" and clause.head
        if left and left > 0 and left < offset and right > offset and right <= count
            and arcs[left] and arcs[left].relation == "root" and words[offset] and words[offset].upos == "CCONJ" then
            local index = first + offset - 1
            local rule, last = clauseConnector(document, index, index)
            if rule and last == index and A.sharedPredicateJoin({rule=rule})
                and coordinatedRanges(arcs, words, left, right, offset, count) then
                local comma = P.key(document, index - 1, limit) == ","
                local leftEnd = index - (comma and 2 or 1)
                local action, afterLeft = simple(document, first, leftEnd, nil, 0)
                local question = P.key(document, limit + 1, #document.tokens) == "?"
                local following, afterRight = simple(document, index + 1, limit, nil, 0, nil, nil, question)
                if afterLeft == leftEnd + 1 and afterRight == limit + 1
                    and dependencyPredicateMatches(action, first + left - 1, words[left])
                    and dependencyPredicateMatches(following, first + right - 1, words[right])
                    and action.subject and following.subject and not (action.implicitSubject or following.implicitSubject) then
                    return {trees={action, following}, joins={{rule=rule, comma=comma}}, dependency=true}
                end
            end
        end
    end
end

local function reportedBoundary(arcs, governor, dependent, count)
    local opening
    for index = 1, count do
        local arc = arcs[index]
        if not arc then return nil end
        if arc.relation ~= "punct" then
            local owner = dependencyOwner(arcs, index, governor, dependent, count)
            if owner == dependent then
                opening = opening or index
            elseif owner ~= governor or opening then
                return nil
            end
        end
    end
    if opening and opening > governor then return opening end
end

local function reportedMatrix(document, first, limit)
    local tree, finish = simple(document, first, limit, nil, 0)
    if not tree or finish ~= limit + 1 or not tree.verb or not tree.subject or tree.implicitSubject
        or tree.question or tree.imperative or tree.object or tree.content or tree.controlled
        or tree.infinitive or tree.perception or tree.prepositions or tree.purpose then return nil end
    local frame = lexemeFrame(tree.verb)
    if frame.content or frame.perception then return tree, frame end
end

local function reportedPredicate(tree, position, word)
    if dependencyPredicateMatches(tree, position, word) then return true end
    if not word then return false end
    if tree.kind == "existential" and tree.existentialIndex == position then
        return word.upos == "VERB" or word.upos == "AUX"
    end
    if word.upos == "ADV" then
        return tree.copula and tree.locativeAdverbIndex == position
    end
    if word.upos == "NOUN" or word.upos == "PROPN" then
        if tree.kind == "existential" then return tree.subject.headIndex == position end
        local location = tree.copula and tree.prepositions and tree.prepositions[1]
        return location and P.spatialLocation(location) and location.object.headIndex == position
    end
end

local function reportedContent(document, first, limit)
    local embedded, finish = simple(document, first, limit, nil, 1)
    if embedded and finish == limit + 1 and embedded.subject and not embedded.implicitSubject
        and not (embedded.imperative or embedded.question or embedded.wh or embedded.why
            or embedded.when or embedded.where) then return embedded end
end

local function missingReportedObject(embedded)
    local frame = embedded.verb and lexemeFrame(embedded.verb)
    return frame and (frame.objectCase or frame.content) and not (embedded.object or embedded.content
        or embedded.controlled or embedded.perception or embedded.infinitive)
end

local function fromReportedGraph(document, first, limit, arcs, words, ambiguousMarker)
    local english = document.direction == "en-uk"
    local marker = english and "that" or "що"
    local count = limit - first + 1
    for dependent = 2, count do
        local arc = arcs[dependent]
        local governor = arc and arc.head
        local root = governor and arcs[governor]
        if arc and arc.relation == "ccomp" and root and root.relation == "root"
            and governor > 0 and governor < dependent and words[governor] and words[governor].upos == "VERB" then
            local opening = reportedBoundary(arcs, governor, dependent, count)
            if opening then
                local start = first + opening - 1
                local marked = P.key(document, start, limit) == marker
                local markerArc = arcs[opening]
                local leftEnd = start - (P.key(document, start - 1, limit) == "," and 2 or 1)
                local tree, frame = reportedMatrix(document, first, leftEnd)
                if tree and tree.verbIndex == first + governor - 1
                    and (marked and markerArc.relation == "mark" and markerArc.head == dependent
                        or not marked and english and frame.bareContent) then
                    local embedded = reportedContent(document, start + (marked and 1 or 0), limit)
                    if embedded and reportedPredicate(embedded, first + dependent - 1, words[dependent])
                        and not (ambiguousMarker == start and missingReportedObject(embedded))
                        and not ns.Engine.Acceptance.rejectRoles({trees={embedded}}, first, arcs, words) then
                        A.prepareReportedClause(document, tree, embedded, tree.recipient, limit + 1, limit)
                        tree.content = {embedded}
                        return {trees={tree}, joins={}, dependency=true}
                    end
                end
            end
        end
    end
end

local function ukrainianReportedMarker(document, first, limit)
    for index = first + 2, limit - 1 do
        if P.key(document, index, limit) == "що" and P.key(document, index - 1, limit) == ","
            and not document.tokens[index].protected and reportedMatrix(document, first, index - 2) then
            return index
        end
    end
end

function A.reportedFromDependencies(document, first, limit, arcs, words, index)
    local parsed = fromReportedGraph(document, first, limit, arcs, words)
    if parsed or document.direction ~= "uk-en" then return parsed end
    index = index or ukrainianReportedMarker(document, first, limit)
    if not index then return nil end
    local offset = index - first + 1
    local marker = arcs[offset]
    local ambiguous = marker and marker.relation == "obj" and index
    local last = limit + (#arcs == limit - first + 2 and 1 or 0)
    local function withReadings(hints)
        local guided = ns.Engine.UDPipe.analyzeDocument(document, first, last, index, index, hints, {"SCONJ"})
        if document.checkpoint then document.checkpoint() end
        return guided and fromReportedGraph(document, first, limit, guided, words, ambiguous) or nil
    end
    if words[offset] and words[offset].upos ~= "SCONJ" then
        parsed = withReadings()
        if parsed then return parsed end
    end
    local embedded = reportedContent(document, index + 1, limit)
    local subject = embedded and embedded.subject
    local predicate = embedded and embedded.existentialIndex
    local word = predicate and words[predicate - first + 1]
    local hints
    if word and word.upos == "AUX" and (subject.quantity or subject.few or P.quantifiedSubject(subject)) then
        -- The counted phrase identifies an existential verb rather than an adjectival copula.
        hints = {[predicate]={pos="VERB", lemma="бути", feats="VerbForm=Fin"}}
        parsed = withReadings(hints)
        if parsed then return parsed end
    end
    local model = ns.UDPipeModels and ns.UDPipeModels.uk
    if not (model and model.reportedOutput and embedded) or P.key(document, limit + 1, #document.tokens) == "?"
        or ambiguous and missingReportedObject(embedded) then return nil end
    local tried = document.reportedOutputTried
    local attempt = tried and tried[first]
    if attempt then
        return attempt.last == last and attempt.arcs and fromReportedGraph(document, first, limit, attempt.arcs, words, ambiguous) or nil
    end
    if tried and tried.remaining == 0 then return nil end
    tried = tried or {remaining=3}
    attempt = {last=last}
    tried[first], tried.remaining, document.reportedOutputTried = attempt, tried.remaining - 1, tried
    local guided = ns.Engine.UDPipe.analyzeReportedDocument(document, first, last, index, hints)
    attempt.arcs = guided
    if document.checkpoint then document.checkpoint() end
    return guided and fromReportedGraph(document, first, limit, guided, words, ambiguous) or nil
end

function A.disambiguateReportedClause(document, first, limit, last)
    if document.direction ~= "uk-en" or last - first >= 32 or limit - first < 4
        or not (ns.UDPipeModels and ns.UDPipeModels.uk) then return nil end
    if document.preserve then
        for start, span in pairs(document.preserve) do
            if start <= last and span.last >= first then return nil end
        end
    end
    local memo = document.reportedDisambiguation
    local ranges = memo and memo[first]
    local previous = ranges and ranges[last]
    if previous ~= nil then return previous or nil end
    if memo and memo.remaining == 0 then return nil end
    for index = first, limit do
        local token = document.tokens[index]
        if not token.protected and (token.key:match("^[.!?;]$") or token.key == "…") then return nil end
    end
    local marker = ukrainianReportedMarker(document, first, limit)
    if not marker then return nil end
    memo = memo or {remaining=3}
    ranges = ranges or {}
    document.reportedDisambiguation, memo[first] = memo, ranges
    memo.remaining = memo.remaining - 1
    local arcs, words = ns.Engine.UDPipe.analyzeDocumentWithTags(document, first, last)
    if document.checkpoint then document.checkpoint() end
    local parsed = arcs and words and A.reportedFromDependencies(document, first, limit, arcs, words, marker)
    ranges[last] = parsed or false
    return parsed
end

local function passiveControlEntry(document, position)
    local frames, reverse = {}, {direction="uk-en"}
    local entry = L.choose(document, position, "verb", {tense="past", verbalForm="participle"}, nil, function(candidate)
        local frame = lexemeFrame(candidate)
        if frame.controlCase then frames[candidate.id] = frame; return true end
        local lemma = candidate.lexeme.uk
        local best, preference
        for _, donor in ipairs(L.lookup(reverse, lemma)) do
            local known = lexemeFrame(donor)
            local rank = donor.lexeme.preference
            if donor.lexeme.pos == "verb" and donor.lexeme.uk == lemma and known.controlCase then
                if best and best.controlCase ~= known.controlCase then return false end
                if not preference or rank < preference then best, preference = known, rank end
            end
        end
        if best then frames[candidate.id] = best; return true end
    end)
    if not entry then return nil end
    local selected = frames[entry.id]
    if selected == entry.lexeme.frame then return entry end
    local lexeme = {}
    for key, value in pairs(entry.lexeme) do lexeme[key] = value end
    lexeme.frame = selected
    return {id=entry.id, lexeme=lexeme, form=entry.form, head=entry.head}
end

local function passiveControlPatient(document, first, last)
    if last < first then return nil end
    local patient, after = P.pronoun(document, first, last, "nominative", true)
    if not patient then patient, after = P.noun(document, first, last, "nominative") end
    if patient and after == last + 1 and (patient.pronoun or patient.animacy == "animate") then return patient end
end

local function passiveControlMatrix(document, first, limit, arcs, governor)
    local main = first + governor - 1
    local auxiliaryIndex, subjectIndex, tense, negative
    for index = 1, governor - 1 do
        local sibling = arcs[index]
        if sibling and sibling.head == governor then
            if sibling.relation == "nsubj:pass" or sibling.relation == "nsubj" then subjectIndex = index end
            if sibling.relation == "aux:pass" or sibling.relation == "aux" then
                local position = first + index - 1
                local key = P.key(document, position, limit)
                local base = negativeCopula[key] or key
                if copula[base] then auxiliaryIndex, tense, negative = position, copula[base], base ~= key end
            end
        end
    end
    if not (auxiliaryIndex and subjectIndex) then return nil end
    local why = P.key(document, first, limit) == "why"
    local inverted = auxiliaryIndex == first + (why and 1 or 0)
    local detachedNegative = P.key(document, main - 1, limit) == "not"
    if not inverted and (why or auxiliaryIndex + (detachedNegative and 2 or 1) ~= main) then return nil end
    local start = inverted and auxiliaryIndex + 1 or first
    local stop = inverted and main - (detachedNegative and 2 or 1) or auxiliaryIndex - 1
    if stop < start then return nil end
    local patient = passiveControlPatient(document, start, stop)
    if not patient or (patient.headIndex or start) ~= first + subjectIndex - 1 then return nil end
    return {kind="clause", verbIndex=main, tense=tense, subject={person=3, number="plural"}, implicitSubject=true,
        controlled={actor=patient}, negative=negative or detachedNegative, question=inverted, why=why}
end

function A.passiveControlFromDependencies(document, first, limit, arcs, words, expectedPredicate, entry)
    if document.direction ~= "en-uk" then return nil end
    for dependent = 4, limit - first + 1 do
        local arc = arcs[dependent]
        local governor = arc and arc.head
        local root = governor and arcs[governor]
        if arc and arc.relation == "xcomp" and root and root.relation == "root" and governor < dependent
            and words[governor] and words[governor].upos == "VERB" and words[dependent] and words[dependent].upos == "VERB" then
            local main = first + governor - 1
            local marker = arcs[governor + 1]
            if (not expectedPredicate or expectedPredicate == main) and P.key(document, main + 1, limit) == "to"
                and marker and marker.relation == "mark" and marker.head == dependent then
                local tree = passiveControlMatrix(document, first, limit, arcs, governor)
                local predicate = tree and (entry or passiveControlEntry(document, main))
                if predicate then
                    local action, finish = complementaryInfinitive(document, main + 1, limit,
                        {infinitive=true, infinitiveAdverbs=true}, 0)
                    if action and finish == limit + 1 and action.verbIndex == first + dependent - 1 then
                        tree.verb, tree.controlled.action = predicate, action
                        return {trees={tree}, joins={}, dependency=true}
                    end
                end
            end
        end
    end
end

function A.passiveWhyFromDependencies(document, first, limit, arcs, words)
    if document.direction ~= "en-uk" or P.key(document, first, limit) ~= "why" then return nil end
    local auxiliary = P.key(document, first + 1, limit)
    if not copula[negativeCopula[auxiliary] or auxiliary] then return nil end
    local last = limit + (#arcs == limit - first + 2 and 1 or 0)
    local ranges = document.passiveWhyRanges
    if ranges and (ranges[first] and ranges[first] ~= last or not ranges[first] and ranges.remaining == 0) then return nil end

    for predicate = first + 3, limit - 2 do
        if P.key(document, predicate + 1, limit) == "to" then
            local stop = predicate - (P.key(document, predicate - 1, limit) == "not" and 2 or 1)
            local patient = passiveControlPatient(document, first + 2, stop)
            local entry = patient and passiveControlEntry(document, predicate)
            if entry then
                if not ranges or not ranges[first] then
                    ranges = ranges or {remaining=3}
                    ranges[first], ranges.remaining, document.passiveWhyRanges = last, ranges.remaining - 1, ranges
                end
                -- Keep the question word in the source and in generation. Its position is restored after parsing.
                local alternate = ns.Engine.UDPipe.analyzeDocument(document, first, last,
                    nil, nil, nil, nil, nil, nil, nil, {first=first, last=first})
                if document.checkpoint then document.checkpoint() end
                return alternate and A.passiveControlFromDependencies(document, first, limit, alternate, words, predicate, entry) or nil
            end
        end
    end
end

function A.disambiguatePassiveControl(document, first, limit, last, predicate)
    if not predicate or last - first >= 32 or P.key(document, predicate + 1, limit) ~= "to"
        or not (ns.UDPipeModels and ns.UDPipeModels.en) then return nil end
    local entry = passiveControlEntry(document, predicate)
    if not entry then return nil end
    local pipe = ns.Engine.UDPipe
    local arcs, words = pipe.analyzeDocumentWithTags(document, first, last)
    if document.checkpoint then document.checkpoint() end
    if not (arcs and words) then return nil end
    return A.passiveControlFromDependencies(document, first, limit, arcs, words, predicate, entry)
        or A.passiveWhyFromDependencies(document, first, limit, arcs, words)
end
end)()
end

function A.parseDependencies(document, first, limit, arcs, words)
    local fronted = frontedLocativePredicate(document, first, limit, arcs)
        or frontedPreposition(document, first, limit, arcs, words)
    if fronted then return fronted end
    local marker = arcs[1]
    local noun = marker and marker.relation == "case" and arcs[marker.head]
    local last = limit - first + 1
    if noun and noun.relation == "root" and #arcs == last + 1 and words[last + 1].upos == "PUNCT" then
        -- Terminal punctuation can make a fronted nominal look like the root of a fragment.
        local alternate, tags = ns.Engine.UDPipe.analyzeDocumentWithTags(document, first, limit)
        fronted = alternate and tags and frontedPreposition(document, first, limit, alternate, tags)
        if fronted then return fronted end
    end
    return A.temporalFromDependencies(document, first, limit, arcs, words)
        or frontedTemporalPreposition(document, first, limit) or A.socialSequence(document, first, limit, arcs)
        or unmarkedRelatives(document, first, limit, arcs)
        or dependencySequence(document, first, limit, arcs, words)
        or A.coordinatedFromDependencies(document, first, limit, arcs, words)
        or A.reportedFromDependencies(document, first, limit, arcs, words)
        or A.passiveControlFromDependencies(document, first, limit, arcs, words)
        or A.passiveWhyFromDependencies(document, first, limit, arcs, words)
        or A.parseWithRecoveredPredicate(document, first, limit, arcs, words)
end

local function recordGerund(readings, action, head)
    readings[action.verbIndex] = {
        pos="VERB", lemma=action.verb.lexeme.en:match("^%S+"), feats="VerbForm=Ger",
        governor=head, relation=head and "conj",
    }
end

local function collectInputReadings(document, node, readings, visited)
    if visited[node] then return end
    visited[node] = true
    if node.headIndex then
        for _, modifier in ipairs(node.adjectives or {}) do
            local token = document.tokens[modifier.index]
            if modifier.entry and not modifier.spelling and token
                and (token.key:match("ing$") or token.key:match("ed$")) then
                readings[modifier.index] = {pos="ADJ", lemma=modifier.entry.lexeme.en, feats="Degree=Pos",
                    nominalHead=node.headIndex}
            end
        end
    end
    if node.gerundMarker then
        readings[node.gerundMarker] = {pos="SCONJ", lemma="for", feats="", governor=node.verbIndex, relation="mark"}
        recordGerund(readings, node)
        for _, step in ipairs(node.series or {}) do recordGerund(readings, step.action, node.verbIndex) end
    end
    for key, child in pairs(node) do
        if type(child) == "table" and key ~= "entry" and key ~= "term" and key ~= "verb"
            and key ~= "rule" and key ~= "pronoun" and key ~= "form" and key ~= "join" then
            collectInputReadings(document, child, readings, visited)
        end
    end
end

function A.dependencyInputReadings(document, first, limit)
    if document.direction ~= "en-uk" or not ns.Linguistics then return nil end
    for index = first, limit do
        local token = document.tokens[index]
        if not token.protected and (token.key:match("ing$")
            or token.key:match("ed$") and L.choose(document, index, "adj")) then
            local parsed = parse(document, first, limit)
            local readings = {}
            if parsed then
                collectInputReadings(document, parsed.trees, readings, {})
            else
                local clause, after = simple(document, first, limit, nil, 0)
                if clause and clause.kind == "clause" and clause.verb and after and boundary(document, after, limit) then
                    collectInputReadings(document, clause, readings, {})
                end
            end
            return next(readings) and readings or nil
        end
    end
end

local untranslatedNominal = {
    modifiers={amod=true, compound=true, goeswith=true, nummod=true},
    cases={Acc="accusative", Dat="dative", Gen="genitive", Ins="instrumental", Loc="locative"},
}

local function untranslatedPositions(node, positions, seen, compounds, arcs, first)
    if seen[node] then return end
    seen[node] = true
    if node.rawModifier then positions[node.index] = "untranslated-modifier" end
    if node.untranslatedHeadIndex then
        positions[node.untranslatedHeadIndex] = node.recruitmentName and "preserved-recruitment-name" or "untranslated-nominal"
    end
    if compounds and node.adjectives then
        local compound, discourse
        for _, modifier in ipairs(node.adjectives) do
            if modifier.index then
                local arc = arcs[modifier.index - first + 1]
                compound = compound or modifier.rawModifier and compounds[modifier.index]
                discourse = discourse or arc and arc.relation == "discourse"
            end
        end
        if compound and discourse then return false end
    end
    for key, child in pairs(node) do
        if type(child) == "table" and key ~= "entry" and key ~= "term" and key ~= "rule"
            and key ~= "form" and key ~= "lexeme" and key ~= "pronoun" then
            if untranslatedPositions(child, positions, seen, compounds, arcs, first) == false then return false end
        end
    end
end

function A.parseWithRecruitmentName(document, first, limit)
    if document.direction ~= "en-uk" or limit <= first + 1 or limit - first >= 32
        or not ns.Engine.Parser.startsWithCapital(document.text, document.tokens[limit]) then return nil end
    local dictionary = ns.Engine.Dictionary
    if #L.at(document, limit) > 0 or dictionary.literal(document, limit) or dictionary.general(document, limit) then return nil end
    local more = P.key(document, limit - 1, limit) == "more"
    local objectFirst = limit - (more and 1 or 0)
    local recruitmentVerbs
    for index = first, objectFirst - 1 do
        local phrase = L.phraseAt(document, index, objectFirst - 1, "verb")
        local action = L.choose(document, phrase or index, "verb", nil, nil, function(entry)
            return lexemeFrame(entry).recruitmentSearch == true
        end)
        if action then
            recruitmentVerbs = recruitmentVerbs or {}
            recruitmentVerbs[index] = true
        end
    end
    if not recruitmentVerbs then return nil end
    local arcs, words = ns.Engine.UDPipe.analyzeDocumentWithTags(document, first, limit)
    local position = limit - first + 1
    local arc, word = arcs and arcs[position], words and words[position]
    if not (arc and word and word.upos == "PROPN") then return nil end
    if more then
        local modifier = arcs[position - 1]
        if not (modifier and modifier.head == position and (modifier.relation == "amod" or modifier.relation == "det")) then
            return nil
        end
    end
    local predicate = words[arc.head]
    local verbIndex = first + arc.head - 1
    if not (recruitmentVerbs[verbIndex] and predicate and predicate.upos == "VERB") then return nil end
    if arc.relation == "obl" then
        local marker = arcs[objectFirst - first]
        if not (marker and marker.head == position and marker.relation == "case"
            and P.key(document, objectFirst - 1, limit) == "for") then return nil end
    elseif arc.relation ~= "obj" then return nil end
    local previous = document.untranslatedRecruitmentObject
    document.untranslatedRecruitmentObject = {first=objectFirst, index=limit, more=more or nil}
    local parsed = A.parse(document, first, limit)
    document.untranslatedRecruitmentObject = previous
    if not parsed then return nil end
    local positions = {}
    untranslatedPositions(parsed, positions, {})
    if positions[limit] ~= "preserved-recruitment-name" then return nil end
    parsed.untranslated = {{index=limit, reason=positions[limit]}}
    parsed.dependency = true
    return parsed
end

function A.parseWithUntranslatedNominals(document, first, limit, arcs, words)
    local modifiers, prepositionalHeads = {}, {}
    local compounds
    local dictionary = ns.Engine.Dictionary
    for index = first, limit do
        local position = index - first + 1
        local token, word, arc = document.tokens[index], words[position], arcs[position]
        local spelling = token.key:gsub("'", "")
        if not token.protected and word and arc
            and #spelling >= 3 and spelling:match("^[a-z\208\209\128-\191]+$") then
            local nextArc = arcs[position + 1]
            local modifier = word.upos == "ADJ" or word.upos == "X"
            local headWord = words[arc.head]
            local nominalCompound = document.direction == "en-uk" and arc.relation == "compound"
                and (word.upos == "NOUN" or word.upos == "PROPN") and headWord
                and (headWord.upos == "NOUN" or headWord.upos == "PROPN")
            local forward = (modifier or nominalCompound) and arc.head > position and arc.head <= position + 3
                and untranslatedNominal.modifiers[arc.relation]
            local reverse = document.direction == "uk-en" and word.upos == "X"
                and nextArc and nextArc.head == position and nextArc.relation == "appos"
            local head = forward and first + arc.head - 1 or reverse and index + 1
            if head and (head > limit or document.tokens[head].protected) then head = nil end
            local caseMarker = arcs[position - 1]
            local predicate = words[arc.head]
            local markedObject = (word.upos == "X" or word.upos == "NOUN" or word.upos == "PROPN")
                and arc.relation == "obl" and caseMarker and caseMarker.relation == "case"
                and caseMarker.head == position and predicate and predicate.upos == "VERB"
                and not document.tokens[index - 1].protected
            if (head or markedObject)
                and #L.at(document, index) == 0 and not dictionary.literal(document, index)
                and not dictionary.general(document, index) then
                modifiers[index] = head
                if head and nominalCompound then
                    compounds = compounds or {}
                    compounds[index] = true
                end
                if markedObject then
                    local case = (word.feats or ""):match("Case=(%a+)")
                    prepositionalHeads[index] = {marker=index - 1, case=untranslatedNominal.cases[case]}
                end
            end
        end
    end
    if not (next(modifiers) or next(prepositionalHeads)) then return nil end
    document.untranslatedModifiers, document.untranslatedPrepositionalHeads = modifiers, prepositionalHeads
    local parsed = A.parse(document, first, limit)
    document.untranslatedModifiers, document.untranslatedPrepositionalHeads = nil, nil
    if not parsed then return nil end
    local positions, untranslated = {}, {}
    if untranslatedPositions(parsed, positions, {}, compounds, arcs, first) == false then return nil end
    for index = first, limit do
        if positions[index] then untranslated[#untranslated + 1] = {index=index, reason=positions[index]} end
    end
    if #untranslated == 0 then return nil end
    parsed.untranslated, parsed.dependency = untranslated, true
    return parsed
end

do
(function()
local function transposedVerb(document, source)
    local selected, readings
    for index = 1, #source - 1 do
        local one, two = source:sub(index, index), source:sub(index + 1, index + 1)
        if one ~= two then
            local spelling = source:sub(1, index - 1) .. two .. one .. source:sub(index + 2)
            local options = L.lookup(document, spelling)
            for _, entry in ipairs(options) do
                if entry.lexeme.pos == "verb" then
                    if selected and selected ~= spelling then return nil end
                    selected, readings = spelling, options
                    break
                end
            end
        end
    end
    return readings
end

function A.parseWithRecoveredPredicate(document, first, limit, arcs, words)
    if document.direction ~= "en-uk" then return nil end
    local dictionary = ns.Engine.Dictionary
    local repair, readings, attempts
    for index = first, limit do
        local token, word = document.tokens[index], words[index - first + 1]
        if word and (word.upos == "X" or word.upos == "VERB") and not token.protected
            and #token.key >= 4 and #token.key <= 16 and token.key:match("^[a-z]+$")
            and P.raw(document, index, index) == token.key and #L.at(document, index) == 0
            and not dictionary.literal(document, index) and not dictionary.general(document, index) then
            attempts = (attempts or 0) + 1
            if attempts > 2 then return nil end
            local options = transposedVerb(document, token.key)
            if options then
                if repair then return nil end
                repair, readings = index, options
            end
            if document.checkpoint then document.checkpoint() end
        end
    end
    if not repair then return nil end
    local previous = document.tokenReadings[repair]
    document.tokenReadings[repair] = readings
    local parsed = A.parse(document, first, limit) or A.parseWithUntranslatedNominals(document, first, limit, arcs, words)
    document.tokenReadings[repair] = previous
    if not parsed then return nil end
    for _, tree in ipairs(parsed.trees) do
        if tree.verbIndex == repair and tree.verb and tree.subject and not tree.implicitSubject then
            parsed.dependency = true
            return parsed
        end
    end
end
end)()
end
