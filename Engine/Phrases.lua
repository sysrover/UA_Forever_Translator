local _, ns = ...
local P = {}
ns.Engine.Phrases = P
local L = ns.Engine.Lexicon
local A = ns.Engine.Apertium
P.spatialAdjuncts = { ["in"]=true, on=true, near=true, ["on-layer"]=true,
    ["at-landmark"]=true, ["at-near-landmark"]=true }

local articles = {a="indefinite", an="indefinite", the="definite"}
local demonstratives = {this="near", these="near", that="far", those="far",
    ["цей"]="near", ["ця"]="near", ["це"]="near", ["ці"]="near", ["цю"]="near", ["цих"]="near",
    ["цього"]="near", ["цієї"]="near", ["цьому"]="near", ["цій"]="near", ["цим"]="near", ["цією"]="near", ["цими"]="near",
    ["того"]="far", ["той"]="far", ["та"]="far", ["те"]="far", ["ті"]="far", ["ту"]="far", ["тієї"]="far",
    ["тому"]="far", ["тій"]="far", ["тих"]="far", ["тим"]="far", ["тією"]="far", ["тими"]="far"}
local semanticNouns = {roles=true, classes=true, places=true, creatures=true, goods=true, game=true,
    professions=true, activities=true, equipment=true, stats=true, countries=true, territories=true, specializations=true,
    characters=true, addresses=true, lighting=true, guildTypes=true}
local allForms = {nominative="усі", accusative="усі", genitive="усіх", dative="усім", instrumental="усіма", locative="усіх"}
P.allForms = allForms
local ordinalSuffixes = {nominative="й", accusative="й", genitive="го", dative="му", locative="му", instrumental="м"}
P.ordinalSuffixes = ordinalSuffixes
local groupNouns = {group=true, party=true, team=true, raid=true}
local function assignedRole(noun)
    local category = noun.term and noun.term.category
    return category == "roles" or category == "classes"
end
local personalTerms = {roles=true, classes=true, characters=true, professions=true, creatures=true, addresses=true}
local relativeDeclension = {
    masculine={nominative="який", genitive="якого", dative="якому", accusative="який", instrumental="яким", locative="якому"},
    feminine={nominative="яка", genitive="якої", dative="якій", accusative="яку", instrumental="якою", locative="якій"},
    neuter={nominative="яке", genitive="якого", dative="якому", accusative="яке", instrumental="яким", locative="якому"},
    plural={nominative="які", genitive="яких", dative="яким", accusative="які", instrumental="якими", locative="яких"},
}
local indefiniteRelative = {nominative="хто", genitive="кого", dative="кому", accusative="кого", instrumental="ким"}
P.relativeMarkers = {["en-uk"]={who=true, whom=true, which=true, that=true}, ["uk-en"]={}}
for _, forms in pairs({relativeDeclension.masculine, relativeDeclension.feminine, relativeDeclension.neuter,
    relativeDeclension.plural, indefiniteRelative}) do
    for _, word in pairs(forms) do P.relativeMarkers["uk-en"][word] = true end
end

local function indefinitePerson(noun)
    local id = noun.pronoun and noun.pronoun.id
    return id == "someone" or id == "everyone"
end

function P.relativeAnimate(noun)
    return noun.animacy == "animate" or indefinitePerson(noun)
        or noun.term and personalTerms[noun.term.category]
end

function P.relativePronoun(noun, case)
    if indefinitePerson(noun) then return indefiniteRelative[case] end
    local gender = noun.gender
    if not gender and noun.term then
        gender = L.head(ns.Engine.Normalize.word(noun.term.uk), "noun").gender
    end
    local agreement = noun.number == "plural" and "plural" or gender
    local forms = relativeDeclension[agreement]
    if case == "accusative" and (agreement == "masculine" or agreement == "plural") and P.relativeAnimate(noun) then
        case = "genitive"
    end
    return forms and forms[case]
end
local timeUnits = {
    min="хвилина", mins="хвилина", minute="хвилина", minutes="хвилина",
    s="секунда", sec="секунда", secs="секунда", second="секунда", seconds="секунда",
    h="година", hr="година", hrs="година", hour="година", hours="година",
    day="день", days="день",
    ["хвилина"]="хвилина", ["хвилини"]="хвилина", ["хвилин"]="хвилина",
    ["секунда"]="секунда", ["секунди"]="секунда", ["секунд"]="секунда",
    ["година"]="година", ["години"]="година", ["годин"]="година",
    ["день"]="день", ["дня"]="день", ["дні"]="день", ["днів"]="день",
}
local englishUnits = {["хвилина"]="minute", ["секунда"]="second", ["година"]="hour", ["день"]="day"}

function P.key(document, index, limit)
    return index <= limit and document.tokens[index] and document.tokens[index].key
end

function P.raw(document, first, last)
    return document.text:sub(document.tokens[first].first, document.tokens[last].last)
end

local function acceptsCategory(term, locationOnly, sense)
    local category = term.category
    if sense == "ability" then return category == "abilities" and not locationOnly end
    if sense == "barAction" then return (category == "abilities" or category == "professions") and not locationOnly end
    return semanticNouns[category] and (not locationOnly or category == "places"
        or term.features and term.features.spatialContainer)
end

local function curatedNoun(candidate)
    local features = candidate.features
    return {term=candidate.term, person=3, number=features.number or "singular",
        gender=features.gender, animacy=features.animacy, sourceCase=features.case}
end

local function curated(document, first, last, requiredCase, locationOnly, agrees, sense)
    local selected
    for _, candidate in ipairs(document.spans[first] or {}) do
        local term = candidate.term
        local category = term.category
        local raw = candidate.last <= last and P.raw(document, first, candidate.last)
        -- Bare IF and HoT are contextual aliases. Full names can also serve in
        -- subject or object position, independently of a recruitment rule.
        local contextual = raw and category == "places" and not locationOnly
            and #raw == #document.tokens[first].key and #raw <= 3 and not raw:match("^[A-Z][A-Z]+$")
        if not locationOnly and category == "places" and not raw then contextual = true end
        local aliasSense = term.features and term.features.contextAliasSense
        if raw and aliasSense and sense ~= aliasSense then
            local language = document.direction == "en-uk" and "en" or "uk"
            local key = ns.Engine.Normalize.key(raw)
            for _, alias in ipairs(term.contextAliases and term.contextAliases[language] or {}) do
                if key == ns.Engine.Normalize.key(alias) then contextual = true; break end
            end
        end
        local caseSensitive = document.direction == "en-uk" and term.features and term.features.caseSensitiveEnglish
        if raw and (not caseSensitive or raw == term.en) and acceptsCategory(term, locationOnly, sense)
            and (not requiredCase or not candidate.features.case or requiredCase == candidate.features.case)
            and (not agrees or agrees(curatedNoun(candidate)))
            and not contextual then
            if not selected or candidate.last > selected.last then selected = candidate
            elseif candidate.last == selected.last then
                if candidate.id ~= selected.id then return nil, true end
                if requiredCase and candidate.features.case and not selected.features.case then selected = candidate end
            end
        end
    end
    return selected
end

local function lexicalNoun(lexeme)
    return {entry=lexeme, person=3, number=lexeme.form.number or lexeme.head.number or "singular",
        gender=lexeme.form.gender or lexeme.head.gender, animacy=lexeme.head.animacy, sourceCase=lexeme.form.case}
end

function P.semanticClass(noun)
    if not noun then return nil end
    noun = noun.subset or noun
    local frame = noun.entry and noun.entry.lexeme.frame
    local term = noun.term
    return frame and frame.semanticClass or term and (term.features and term.features.semanticClass or term.category)
end

function P.hasTrait(noun, trait)
    noun = noun and (noun.subset or noun)
    local frame = noun and noun.entry and noun.entry.lexeme.frame
    local term = noun and noun.term
    return frame and frame[trait] == true or term and term.features and term.features[trait] == true
end

function P.spatialContainer(noun)
    if not noun then return false end
    return noun.term and noun.term.category == "places" or P.hasTrait(noun, "spatialContainer")
end

function P.isResource(noun)
    local classes = ns.Linguistics.grammar.resourceClasses
    return classes and classes[P.semanticClass(noun)] == true
end

function P.mass(noun)
    local term, entry = noun.term, noun.entry
    return term and term.features and term.features.mass or entry and (entry.head.mass
        or entry.lexeme.frame and entry.lexeme.frame.mass)
end

function P.quantifiedSubject(noun)
    return noun and (noun.more or noun.many or noun.abundance)
end

local function declinedCuratedNoun(document, first, case, locationOnly, agrees, sense)
    local index = ns.Data.linguistics and ns.Data.linguistics.analysis["uk-en"]
    if not index then return nil end
    local selected, selectedId
    local readings = L.at(document, first)
    if readings.truncated then return nil end
    for _, reading in ipairs(readings) do
        local form = reading.form
        if reading.lexeme.pos == "noun" and form.case == case and form.number then
            local lemma = ns.Engine.Normalize.word(reading.lexeme.uk)
            local canonical = index[lemma]
            for _, candidate in ipairs(canonical and canonical._analyses or {}) do
                local term = ns.Data.terms[candidate.id]
                local features = term.features or {}
                if candidate.pos == "noun" and acceptsCategory(term, locationOnly, sense)
                    and not features.verbatim
                    and ns.Engine.Normalize.word(term.uk) == lemma then
                    local noun = {term=term, person=3, number=form.number, sourceCase=case,
                        gender=features.gender or form.gender, animacy=features.animacy or form.animacy}
                    if not agrees or agrees(noun) then
                        if selected and (selectedId ~= candidate.id or selected.number ~= form.number) then return nil end
                        selected, selectedId = noun, candidate.id
                    end
                end
            end
        end
    end
    return selected
end

local function groupDestination(document, first, limit)
    local english = document.direction == "en-uk"
    local marker = P.key(document, first, limit)
    if english and marker ~= "for" or not english and marker ~= "на" and marker ~= "до" then return nil end
    local start = first + 1
    local case = not english and (marker == "на" and "accusative" or "genitive") or nil
    local place = curated(document, start, limit, case, true)
    if not place and english and P.key(document, start, limit) == "the" then
        place = curated(document, start + 1, limit, case, true)
    end
    if place then return curatedNoun(place), place.last + 1 end
end

-- A recruitment predicate can recover an omitted role when an actual group
-- destination follows the additional count.
function P.ellipticalGroupMember(document, first, limit, roleId)
    local key = P.key(document, first, limit)
    local count = key and (ns.Linguistics.grammar.cardinalEn[key] or tonumber(key))
    if not count or count < 1 or count > 999 or count % 1 ~= 0
        or P.key(document, first + 1, limit) ~= "more" then return nil end
    local place, after = groupDestination(document, first + 2, limit)
    local term = ns.Data.terms[roleId]
    if not place or not term then return nil end
    return {term=term, person=3, number=count == 1 and "singular" or "plural",
        gender=term.features.gender, animacy=term.features.animacy, quantity=tostring(count),
        additional=true, destination=place}, after
end

local function possessive(candidate)
    local frame = candidate.lexeme.frame
    return frame and frame.possessive
end

local function possessiveReading(document, index, case, noun)
    local number = noun.number
    local gender = number ~= "plural" and noun.gender or nil
    local requested = {case=case, number=number, gender=gender}
    return L.choose(document, index, "pron", nil, nil, function(candidate)
        if not possessive(candidate) then return false end
        if candidate.lexeme.frame.invariable or L.matches(candidate.form, requested) then return true end
        return case == "accusative" and noun.animacy == "animate"
            and (number == "plural" or gender == "masculine")
            and L.matches(candidate.form, {case="genitive", number=number, gender=gender})
    end)
end

function P.pronoun(document, first, limit, case, personOnly, headlessQuantity)
    local choices, last = L.functional(document, "pronouns", first, limit)
    if not choices then return nil end
    local selected
    for _, match in ipairs(choices) do
        local valid = case == match.case or (case ~= "nominative" and match.case ~= "nominative"
            and match.case ~= "possessive" and document.direction == "en-uk")
        local candidate = ns.Linguistics.grammar.pronouns[match.id]
        if valid and candidate.headlessQuantity == headlessQuantity
            and (not personOnly or candidate.id ~= "it" and not candidate.inanimate) then
            if selected and selected ~= candidate then return false end
            selected = candidate
        end
    end
    if selected then
        local number = document.direction == "uk-en" and selected.ukNumber or selected.number
        return {pronoun=selected, person=selected.person, gender=selected.gender, number=number}, last + 1
    end
end

local function nounHead(document, first, limit, case, locationOnly, sense, agrees)
    local key = P.key(document, first, limit)
    if not key then return nil end
    local token = document.tokens[first]
    if token.protected then
        local raw = P.raw(document, first, first)
        if token.linkKind or token.questReference or raw:match("^<.+>$") or raw:sub(1, 1) == "@" then
            return {raw=raw, number="singular", person=3}, first + 1
        end
        return nil
    end
    local reverseCase = document.direction == "uk-en" and case or nil
    local phrase, phraseEnd = L.phraseAt(document, first, limit, "noun")
    if phrase then
        local function grammaticalPhrase(candidate)
            local frame = candidate.lexeme.frame
            return frame and frame.lexicalPhrase and (not reverseCase or candidate.form.case == reverseCase)
                and (not agrees or agrees(lexicalNoun(candidate)))
        end
        local entry = sense and L.choose(document, phrase, "noun", nil, sense, grammaticalPhrase)
            or L.choose(document, phrase, "noun", nil, nil, grammaticalPhrase)
        if entry then return lexicalNoun(entry), phraseEnd end
    end
    if not locationOnly and not agrees then
        local pronoun, after = P.pronoun(document, first, limit, case)
        if pronoun ~= nil then return pronoun or nil, after end
    end
    local known, ambiguous = curated(document, first, limit, reverseCase, locationOnly, agrees, sense)
    if sense and (not known or known.last == first) then
        local contextual = L.choose(document, first, "noun", reverseCase and {case=reverseCase}, sense,
            agrees and function(candidate) return agrees(lexicalNoun(candidate)) end)
        if contextual then return lexicalNoun(contextual), first + 1 end
    end
    if known then
        local noun = curatedNoun(known)
        if known.term.features and known.term.features.verbatim then noun.raw = P.raw(document, first, known.last) end
        local objectPhrase = known.term.englishObject
        if document.direction == "en-uk" and case == "accusative" and known.features.mass
            and objectPhrase and objectPhrase:sub(1, 5) == "some " and key == "some" then
            noun.partitive = true
        end
        return noun, known.last + 1
    end
    if ambiguous then return nil end
    local lexeme = L.choose(document, first, "noun", nil, nil, function(candidate)
        local frame = candidate.lexeme.frame
        if document.direction == "en-uk" and frame and frame.requiresLocation and not locationOnly then return false end
        return (not reverseCase or candidate.form.case == reverseCase
            or (reverseCase == "nominative" and candidate.form.case == nil))
            and (not agrees or agrees(lexicalNoun(candidate)))
    end)
    if not lexeme and reverseCase and not locationOnly and groupDestination(document, first + 1, limit) then
        lexeme = L.choose(document, first, "noun", {case=reverseCase}, nil, function(candidate)
            return groupNouns[candidate.lexeme.en] and (not agrees or agrees(lexicalNoun(candidate)))
        end)
    end
    if lexeme then
        local node = lexicalNoun(lexeme)
        local frame = lexeme.lexeme.frame
        if document.direction == "en-uk" and frame and frame.nominalModifier then
            local head
            local modifier = lexeme.lexeme.en
            if first < limit then
                head = L.choose(document, first + 1, "noun", nil, nil, function(candidate)
                    local valency = candidate.lexeme.frame
                    return valency and valency.nominalComplements and valency.nominalComplements[modifier]
                end)
            end
            if head then
                local compound = lexicalNoun(head)
                local valency = head.lexeme.frame
                node.number = valency.nominalComplements[modifier]
                compound.nominalObject, compound.nominalCase = node, valency.nominalCase
                return compound, first + 2
            end
            if frame.compoundAlias == key then return nil end
        end
        return node, first + 1
    end
    if reverseCase then
        local noun = declinedCuratedNoun(document, first, reverseCase, locationOnly, agrees, sense)
        if noun then return noun, first + 1 end
    end
end

local function determinerForms(key, lemma)
    if not key or not ns.ApertiumData then return nil end
    local options
    for raw in pairs(A.analyze(key, "uk") or {}) do
        local base, pos, form = A.read(raw, "uk")
        if base == lemma and pos == "det" then
            options = options or {}
            options[#options + 1] = form
        end
    end
    return options
end

local function determinerMatches(options, requested, animacy)
    for _, form in ipairs(options or {}) do
        if L.matches(form, requested) and (not animacy or not form.animacy or form.animacy == animacy) then return true end
    end
    return false
end

local function nominalMarkerEnd(document, first, limit, rule, english)
    if first > limit then return nil end
    if P.key(document, first, limit) == (english and rule.en or rule.uk) then return first + 1 end
    local aliases = english and rule.enAliases or not english and rule.ukAliases
    for _, alias in ipairs(aliases or {}) do
        local index = first
        for word in alias:gmatch("%S+") do
            if P.key(document, index, limit) ~= word then index = nil; break end
            index = index + 1
        end
        if index then return index end
    end
end

local fewForms = {nominative="кілька", accusative="кілька", genitive="кількох",
    dative="кільком", instrumental="кількома", locative="кількох"}
P.fewForms = fewForms
P.benefitPast = {masculine="завадив", feminine="завадила", neuter="завадило", plural="завадили"}
local oneForms = {
    masculine={nominative="один", genitive="одного", dative="одному", accusative="один", instrumental="одним", locative="одному"},
    feminine={nominative="одна", genitive="однієї", dative="одній", accusative="одну", instrumental="однією", locative="одній"},
    neuter={nominative="одне", genitive="одного", dative="одному", accusative="одне", instrumental="одним", locative="одному"},
}
local oneSurfaces = {}
for _, forms in pairs(oneForms) do
    for _, value in pairs(forms) do oneSurfaces[value] = true end
end

function P.one(gender, case, animacy)
    if gender == "masculine" and case == "accusative" and animacy == "animate" then case = "genitive" end
    local forms = oneForms[gender]
    return forms and forms[case]
end

local function subsetAt(document, first, limit, case, sense, headFilter)
    local key, marker = P.key(document, first, limit), P.key(document, first + 1, limit)
    local english = document.direction == "en-uk"
    if not key or (english and marker ~= "of")
        or (not english and marker ~= "із" and marker ~= "з" and marker ~= "зі") then return nil end
    local grammar = ns.Linguistics.grammar
    local byCase = not english and grammar.cardinalUkByCase and grammar.cardinalUkByCase[case]
    local cardinal = english and grammar.cardinalEn[key] or not english and grammar.cardinalUk[key]
    local collective = not english and (case == "nominative" or case == "accusative")
        and grammar.collectiveUk and grammar.collectiveUk[key]
    local one = not english and oneSurfaces[key]
    local count = one and 1 or cardinal or collective or (byCase and byCase[key])
        or (key:match("^%d+$") and tonumber(key))
    if not count or count < 1 then return nil end
    if not english and count > 1 and not key:match("^%d+$") and case ~= "nominative" and case ~= "accusative"
        and not (byCase and byCase[key]) then return nil end
    local group, after = P.noun(document, first + 2, limit, "genitive", false, false, true, sense, headFilter)
    if not group or group.number ~= "plural" then return nil end
    local gender = group.gender
    local animacy = group.animacy or (group.pronoun and not group.pronoun.inanimate and "animate")
    if not english and one then
        if gender and P.one(gender, case, animacy) ~= key then return nil end
        if not gender then
            for _, candidate in ipairs({"masculine", "feminine", "neuter"}) do
                if P.one(candidate, case, animacy) == key then gender = candidate; break end
            end
            if not gender then return nil end
        end
    end
    return {subset=group, subsetCount=count, person=3, number=count == 1 and "singular" or "plural",
        gender=gender or "masculine", animacy=animacy, headIndex=first}, after
end

local function levelAreaAt(document, index, limit)
    if index > limit then return nil end
    return L.choose(document, index, "noun", nil, nil, function(candidate)
        return candidate.lexeme.frame and candidate.lexeme.frame.semanticClass == "levelArea"
    end)
end

local guildNameCopula = {is=true, are=true, was=true, were=true}
local function bracketedGuildSubject(document, first, limit)
    local english = document.direction == "en-uk"
    for ending = first + 1, math.min(limit - 1, first + 10) do
        local token = document.tokens[ending]
        if token.protected or token.key == "[" then return end
        if token.key == "]" then
            if ending == first + 1 then return end
            local following = P.key(document, ending + 1, limit)
            if english and not guildNameCopula[following] then return end
            local description = P.noun(document,
                ending + ((english or following == "—" or following == "є") and 2 or 1),
                limit, "nominative", nil, nil, true)
            if description and description.term and description.term.id == "game.guild" then
                local plural = english and (following == "are" or following == "were")
                return {raw=P.raw(document, first, ending), person=3, number=plural and "plural" or "singular"}, ending + 1
            end
            return
        end
    end
end

function P.noun(document, first, limit, case, locationOnly, count, simple, sense, headFilter)
    local index = first
    local key = P.key(document, index, limit)
    local english = document.direction == "en-uk"
    if key == "[" and case == "nominative" and not (locationOnly or headFilter) then
        return bracketedGuildSubject(document, first, limit)
    end
    if not locationOnly and count ~= false then
        local subset, after = subsetAt(document, first, limit, case, sense, headFilter)
        if subset then return subset, after end
    end
    local ordinal
    if not english and key and key:match("^%d+$") and P.key(document, index + 1, limit) == "-"
        and P.key(document, index + 2, limit) == ordinalSuffixes[case] then
        ordinal, index = key, index + 3
        key = P.key(document, index, limit)
    end
    local allForm = allForms[case]
    local all = english and key == "all"
        or not english and allForm and (key == allForm or key == "в" .. allForm:sub(3))
    if all then index = index + 1; key = P.key(document, index, limit) end
    if key == "\"" then
        if P.key(document, first + 1, limit) == "\"" then return nil end
        local quoted, after = P.noun(document, first + 1, limit, case, locationOnly, count, nil, nil, headFilter)
        if quoted and quoted.term and quoted.term.category == "places" and P.key(document, after, limit) == "\"" then
            quoted.quoted = true
            return quoted, after + 1
        end
        return nil
    end
    local emphatic = key == "such" or key == "такий" or key == "така" or key == "таке" or key == "такі"
    if emphatic then
        index = index + 1
        key = P.key(document, index, limit)
    end
    local article = document.direction == "en-uk" and articles[key]
    local demonstrative = demonstratives[key]
    local determiner = demonstrative and key
    local demonstrativeNumber = english and demonstrative and ((key == "these" or key == "those") and "plural" or "singular")
    local ownerIndex, owner = index
    if not article and not demonstrative and not emphatic and index <= limit then
        owner = L.choose(document, index, "pron", nil, nil, possessive)
    end
    if article or demonstrative then index = index + 1 end
    if owner then index = index + 1 end
    local sameAt, sameForms, pointerForms
    if english and not demonstrative and not owner and P.key(document, index, limit) == "same" then
        sameAt, index = index, index + 1
    elseif not english and demonstrative == "far" then
        sameForms = determinerForms(P.key(document, index, limit), "самий")
        if sameForms or not ns.ApertiumData and L.choose(document, index, "adj", {case=case}, "identityDeterminer") then
            sameAt, index = index, index + 1
        end
    end
    if not english and determiner then
        pointerForms = determinerForms(determiner, demonstrative == "far" and "той" or "цей")
    end
    local quantity = P.key(document, index, limit)
    local levelThreshold, freeChoice
    if english then
        local any = quantity == "any"
        local thresholdAt = index + (any and 1 or 0)
        local digits = any and P.key(document, thresholdAt, limit) or quantity
        if digits and digits:match("^%d%d?%d?$") and P.key(document, thresholdAt + 1, limit) == "+"
            and levelAreaAt(document, thresholdAt + 2, limit) then
            levelThreshold, freeChoice, index = digits, any and "any" or nil, thresholdAt + 2
            quantity = P.key(document, index, limit)
        end
    elseif quantity == "будь" and P.key(document, index + 1, limit) == "-" then
        local form = P.key(document, index + 2, limit)
        if P.relativeMarkers["uk-en"][form] and levelAreaAt(document, index + 3, limit) then
            freeChoice, index = form, index + 3
            quantity = P.key(document, index, limit)
        end
    end
    local characterLevel
    if english and not locationOnly and (quantity == "level" or quantity == "lvl") then
        local level = P.key(document, index + 1, limit)
        if level and level:match("^%d%d?%d?$") and tonumber(level) > 0
            and curated(document, index + 2, limit, nil, false, assignedRole) then
            characterLevel, index = level, index + 2
            quantity = P.key(document, index, limit)
        end
    end
    local few = count ~= false and (english and article == "indefinite" and quantity == "few"
        or not english and (quantity and quantity == fewForms[case] or case == "accusative" and quantity == "кількох"))
    local sufficient = count ~= false and not (article or demonstrative or owner) and
        quantity == (english and "enough" or "достатньо")
    local some = count ~= false and not (article or demonstrative or owner) and
        quantity == (english and "some" or "трохи")
    local quantifierStart = count ~= false and not (article or demonstrative or owner)
    local another = quantifierStart and english and quantity == "another"
    local lot = count ~= false and english and article == "indefinite" and quantity == "lot"
        and P.key(document, index + 1, limit) == "of"
    local lots = quantifierStart and english and quantity == "lots" and P.key(document, index + 1, limit) == "of"
    local abundance = quantifierStart and (english and quantity == "plenty" and P.key(document, index + 1, limit) == "of"
        or not english and quantity == "вдосталь")
    local moreKey = english and "more" or "більше"
    local followedByMore = quantifierStart and P.key(document, index + 1, limit) == moreKey
    local evenMore = followedByMore and quantity == (english and "even" or "ще")
    local degreeMore = followedByMore and (english and (quantity == "many" or quantity == "much")
        or not english and (quantity == "значно" or quantity == "набагато"))
    local countOnly = english and quantifierStart and quantity == "many"
    local massOnly = english and degreeMore and quantity == "much"
    local many = lot or lots or countOnly and not degreeMore or quantifierStart and not english and quantity == "багато"
    local more = quantifierStart and (evenMore or degreeMore or quantity == moreKey)
    local grammar = ns.Linguistics.grammar
    local cardinals = english and grammar.cardinalEn or grammar.cardinalUk
    local caseCardinals = not english and grammar.cardinalUkByCase and grammar.cardinalUkByCase[case]
    local additional, oneSurface
    if not english and count ~= false and not (demonstrative or owner) and quantity == "ще" then
        local amount = P.key(document, index + 1, limit)
        if oneSurfaces[amount] or amount and (amount:match("^%d+$") or cardinals[amount]
            or caseCardinals and caseCardinals[amount] or grammar.collectiveUk and grammar.collectiveUk[amount]) then
            additional, oneSurface, index = true, oneSurfaces[amount] and amount, index + 1
            quantity = oneSurface and "1" or amount
        end
    end
    local collective = not english and grammar.collectiveUk and grammar.collectiveUk[quantity]
    local cardinal = collective or cardinals and cardinals[quantity] or caseCardinals and caseCardinals[quantity]
    if cardinal then quantity = tostring(cardinal) end
    if many or more or abundance then
        index, article, quantity = index + ((lot or lots or evenMore or degreeMore or abundance and english) and 2 or 1), nil, nil
        if not english then case = "genitive" end
    elseif few or sufficient or some then
        index, article, quantity = index + 1, nil, nil
        if not english and (sufficient or some or case == "nominative" or case == "accusative") then case = "genitive" end
    elseif another then
        additional, quantity, index = true, "1", index + 1
    elseif count ~= false and quantity and quantity:match("^%d+$") then
        local followsQuantity = english and P.key(document, index + 1, limit) == "more"
        additional, index = additional or followsQuantity, index + (followsQuantity and 2 or 1)
        if collective then case = "genitive" end
    else quantity = nil end
    local agrees = headFilter
    if not english and (sameAt or pointerForms or owner) then
        local counted = quantity and (tonumber(quantity) == 1 and "singular" or "plural")
        agrees = function(head)
            if headFilter and not headFilter(head) then return false end
            if owner and not possessiveReading(document, ownerIndex, case, head) then return false end
            local number = counted or head.number or "singular"
            local features = {case=case, number=number, gender=number ~= "plural" and head.gender or nil}
            if pointerForms and not determinerMatches(pointerForms, features, head.animacy) then return false end
            if not sameAt then return true end
            if sameForms then return determinerMatches(sameForms, features, head.animacy) end
            return L.choose(document, sameAt, "adj", features, "identityDeterminer") ~= nil
        end
    end
    local nounSense = sense or (english and owner and "possessedNoun" or nil)
    local adjectives, best, nextIndex, headIndex = {}
    local degree = P.key(document, index, limit)
    local intensity
    if degree == "very" or degree == "дуже" or degree == "more" or degree == "більш"
        or article == "definite" and degree == "most" then
        intensity = (degree == "more" or degree == "більш") and "more" or degree == "most" and "most" or "very"
        index = index + 1
    end
    -- Check the head after each adjective. The longest grammatical noun phrase
    -- wins, with a bounded number of modifiers.
    for _ = 0, 2 do
        local required = agrees
        if not english and #adjectives > 0 then
            required = function(head)
                if agrees and not agrees(head) then return false end
                local number = head.number or "singular"
                local gender = number == "singular" and head.gender
                for _, modifier in ipairs(adjectives) do
                    local matches
                    for _, reading in ipairs(L.at(document, modifier.index)) do
                        if reading.id == modifier.entry.id and reading.form.case == case
                            and (not reading.form.number or reading.form.number == number)
                            and (not gender or not reading.form.gender or reading.form.gender == gender) then
                            matches = true
                            break
                        end
                    end
                    if not matches then return false end
                end
                return true
            end
        end
        local contextual
        if not sense and #adjectives > 0 and index <= limit then
            local requested = not english and {case=case} or nil
            contextual = L.choose(document, index, "noun", requested, "adjectivalComplement", function(candidate)
                local allowed = candidate.lexeme.frame.modifyingAdjectives
                return allowed and allowed[adjectives[#adjectives].entry.lexeme.en]
                    and (not required or required(lexicalNoun(candidate)))
            end)
        end
        local head, after
        if contextual then head, after = lexicalNoun(contextual), index + 1
        else head, after = nounHead(document, index, limit, case, locationOnly, nounSense, required) end
        if english and not simple then
            local prefix, following = head, after
            local definitePlace = P.key(document, index, limit) == "the"
            if definitePlace then
                local place = curated(document, index + 1, limit, nil, true)
                if place then prefix, following = curatedNoun(place), place.last + 1 end
            end
            local frame = prefix and prefix.entry and prefix.entry.lexeme.frame
            local place = prefix and prefix.term and prefix.term.category == "places"
            local nominalPrefix = prefix and prefix.term and prefix.term.features and prefix.term.features.nominalArgumentPrefix
            if following and following <= limit and (place or nominalPrefix or frame and frame.spatialContainer) then
                local part, ending = nounHead(document, following, limit, case, locationOnly)
                local relation = part and part.entry and part.entry.lexeme.frame
                local prefixArgument
                if nominalPrefix then
                    local class = P.semanticClass(prefix)
                    for _, argument in ipairs(relation and relation.nominalArguments or {}) do
                        if argument.englishCompound and argument.classes and argument.classes[class] then
                            prefixArgument = argument
                            break
                        end
                    end
                end
                local session, sessionEnd
                if place and not locationOnly then
                    session, sessionEnd = nounHead(document, following, limit, case, false, "iteration")
                end
                if prefixArgument then
                    part.argument = {object=prefix, form=prefixArgument}
                    head, after = part, ending
                elseif session and session.entry and session.entry.lexeme.frame and session.entry.lexeme.frame.placeCompound then
                    session.genitive = prefix
                    head, after = session, sessionEnd
                elseif #adjectives == 0 and (not definitePlace or owner) and relation and relation.spatialPart then
                    if relation.pathTo then part.pathTo = prefix
                    else part.genitive = prefix end
                    head, after = part, ending
                elseif #adjectives == 0 and (not definitePlace or owner) and part and place and assignedRole(part) then
                    part.destination = prefix
                    head, after = part, ending
                end
            end
        end
        if head and (not headFilter or headFilter(head)) and (not demonstrativeNumber or head.number == demonstrativeNumber
            or demonstrativeNumber == "plural" and head.number == "singular" and P.mass(head))
            and (not few or head.number == "plural")
            and (not head.pronoun or index == first) and (not intensity or #adjectives > 0)
            and (not best or after > nextIndex or (after == nextIndex and head.term and not best.term)) then
            best, nextIndex, headIndex = head, after, index
            if #adjectives > 0 then best.adjectives = {unpack(adjectives)} end
        end
        if index > limit then break end
        local adjective = L.choose(document, index, "adj", nil, nil, function(candidate)
            if candidate.lexeme.frame and candidate.lexeme.frame.profileOnly then return false end
            return document.direction == "en-uk" or candidate.form.case == case
        end)
        if not adjective then break end
        adjectives[#adjectives + 1] = {entry=adjective, index=index, intensity=#adjectives == 0 and intensity or nil}
        index = index + 1
    end
    if not best then
        if (more or some) and english then
            return P.noun(document, first, limit, case, locationOnly, false, simple, sense, headFilter)
        end
        if (demonstrative or all) and not locationOnly and not headFilter then return P.pronoun(document, first, limit, case) end
        if owner then return nounHead(document, first, limit, case, locationOnly, nil, headFilter) end
        return nil
    end
    if countOnly and best.number ~= "plural" or massOnly and not P.mass(best) then return nil end
    if more and english and (not P.mass(best) and best.number ~= "plural" or best.adjectives and not degreeMore) then
        return P.noun(document, first, limit, case, locationOnly, false, simple, sense, headFilter)
    end
    if some and english then
        if best.number == "plural" then few, some = true, nil
        else
            if not P.mass(best) then return P.noun(document, first, limit, case, locationOnly, false, simple, sense, headFilter) end
        end
    end
    if oneSurface and P.one(best.gender, case, best.animacy) ~= oneSurface then return nil end
    if all and (best.pronoun or best.number ~= "plural") then return nil end
    if sameAt then
        if best.pronoun or best.raw then return nil end
        best.same, demonstrative = true, "far"
    end
    best.all = all or nil
    local en = document.direction == "en-uk"
    if owner then
        if best.raw or best.pronoun or quantity then return nil end
        if best.term and not best.gender and best.number ~= "plural" then
            local normalize = ns.Engine.Normalize.word
            local enLemma, ukLemma = normalize(best.term.en), normalize(best.term.uk)
            local matchingEntry = L.choose(document, headIndex, "noun", nil, nil, function(candidate)
                return candidate.lexeme.en == enLemma and candidate.lexeme.uk == ukLemma
            end)
            if matchingEntry then
                best.gender, best.animacy = matchingEntry.head.gender, best.animacy or matchingEntry.head.animacy
            end
        end
        if not en then
            owner = possessiveReading(document, ownerIndex, case, best)
            if not owner then return nil end
        end
        if best.nominalObject then best.nominalObject.possessor = owner
        else best.possessor = owner end
    end
    if characterLevel and not assignedRole(best) then return nil end
    best.article, best.quantity, best.demonstrative = article, quantity, demonstrative
    best.characterLevel = characterLevel
    best.emphatic, best.few = emphatic, few or nil
    best.sufficient, best.additional, best.many = sufficient or nil, additional or nil, many or nil
    best.abundance = abundance or nil
    best.more, best.evenMore, best.degreeMore = more or nil, evenMore or nil, degreeMore or nil
    best.some = some or nil
    if best.argument and best.argument.form.englishCompound and en then
        best.headIndex = nextIndex - 1
    elseif nextIndex == headIndex + 1 and (best.entry or best.term) then best.headIndex = headIndex end
    local frame = best.entry and best.entry.lexeme.frame
    if frame and frame.semanticClass == "levelArea" then
        if not en and P.key(document, nextIndex, limit) == "від" then
            local level, after = P.noun(document, nextIndex + 1, limit, "genitive", false, false, true)
            local levelFrame = level and level.entry and level.entry.lexeme.frame
            if levelFrame and levelFrame.postposedNumber and level.ordinal then
                levelThreshold, nextIndex = level.ordinal, after
            end
        end
        if freeChoice and not en and freeChoice ~= P.relativePronoun(best, case) then return nil end
        best.levelThreshold, best.freeChoice = levelThreshold, freeChoice ~= nil
    elseif levelThreshold or freeChoice then return nil end
    if ordinal then
        if not frame or not frame.postposedNumber then return nil end
        best.ordinal = ordinal
    end
    if en and frame and frame.postposedNumber then
        local numberAfter = P.key(document, nextIndex, limit)
        if numberAfter and numberAfter:match("^%d+$") then best.ordinal, nextIndex = numberAfter, nextIndex + 1 end
    end
    if not en and not simple and frame and frame.nominalComplements then
        local object, after = P.noun(document, nextIndex, limit, frame.nominalCase, false, false, true)
        if object and object.entry and frame.nominalComplements[object.entry.lexeme.en] then
            best.nominalObject, best.nominalCase, nextIndex = object, frame.nominalCase, after
        end
    end
    if en and best.term and best.term.category == "classes"
        and P.key(document, nextIndex, limit) == "trainer" then
        local head, after = nounHead(document, nextIndex, limit, case)
        if head and head.entry and head.entry.lexeme.sense == "project:trainer.person" then
            head.class, head.article = best, article
            return head, after
        end
    end
    if document.direction == "uk-en" and best.entry and best.entry.lexeme.sense == "project:trainer.person" then
        local class, after = nounHead(document, nextIndex, limit, "genitive")
        if class and class.term and class.term.category == "classes" then
            best.class, nextIndex = class, after
        end
    end
    if not simple and not (best.raw or best.pronoun or best.nominalObject or best.class) and nextIndex <= limit then
        local marker = P.key(document, nextIndex, limit)
        if frame and frame.pathTo and marker == (en and "to" or "до") then
            local goal, after = P.noun(document, nextIndex + 1, limit, "genitive", false, false, true)
            if goal then best.pathTo, nextIndex = goal, after end
        end
        for _, governed in ipairs(frame and frame.nominalArguments or {}) do
            local start = nominalMarkerEnd(document, nextIndex, limit, governed, en)
            if start then
                local argument, after = P.noun(document, start, limit, governed.case, false, nil, true,
                    governed.argumentSense)
                local class = P.semanticClass(argument)
                if not class and argument and argument.raw and ns.Engine.Markup.isLink(argument.raw, "item") then
                    class = "equipment"
                end
                local targetFrame = argument and argument.entry and argument.entry.lexeme.frame
                local spatial = class == "places" or targetFrame and (targetFrame.spatialContainer or targetFrame.spatialPart)
                if argument and (not governed.classes or governed.classes[class])
                    and (not governed.requiresSpatialTarget or spatial) then
                    local sense = en and governed.sense or not en and governed.reverseSense
                    local reading = sense and L.choose(document, headIndex, "noun", nil, sense)
                    if reading then
                        best.entry, best.term = reading, nil
                        best.gender, best.animacy = reading.head.gender, reading.head.animacy
                    end
                    best.argument, nextIndex = {object=argument, form=governed}, after
                    break
                end
            end
        end
        local lemma = best.entry and best.entry.lexeme.en or best.term and best.term.en
        if lemma and (groupNouns[ns.Engine.Normalize.word(lemma)] or assignedRole(best)) then
            local destination, after = groupDestination(document, nextIndex, limit)
            if destination then best.destination, nextIndex = destination, after end
        end
        if not best.destination and not best.pathTo and not best.argument and not best.genitive and (not en or marker == "of") then
            local contextual = en and L.choose(document, headIndex, "noun", nil, "genitiveComplement")
            local context = contextual and contextual.lexeme.frame
            local dependent, after = P.noun(document, nextIndex + (en and 1 or 0), limit,
                "genitive", false, false, true, context and context.complementSense)
            if dependent and not dependent.pronoun and (en or dependent.sourceCase == "genitive") then
                local dependentFrame = dependent.entry and dependent.entry.lexeme.frame
                if not best.characterLevel and assignedRole(best) and dependent.ordinal
                    and dependentFrame and dependentFrame.postposedNumber then
                    best.characterLevel = dependent.ordinal
                else best.genitive = dependent end
                nextIndex = after
                if best.genitive and context and context.complementClasses and context.complementClasses[P.semanticClass(dependent)] then
                    best.entry, best.term = contextual, nil
                    best.gender, best.animacy = contextual.head.gender, contextual.head.animacy
                end
            end
        end
    end
    local class = best.adjectives and P.semanticClass(best)
    if class then
        local requested = not english and {case=case} or nil
        for _, modifier in ipairs(best.adjectives) do
            local reading = L.choose(document, modifier.index, "adj", requested,
                "nounModifier", function(candidate)
                    local classes = candidate.lexeme.frame.headClasses
                    return classes and classes[class]
                end)
            if reading then modifier.entry = reading end
        end
    end
    if document.relativeBudget and not simple and not best.raw
        and (not best.pronoun or best.pronoun.id == "someone") and nextIndex <= limit then
        local relative, finish = ns.Engine.ClauseAnalysis.relative(document, best, nextIndex, limit)
        if relative then best.relative, nextIndex = relative, finish end
    end
    return best, nextIndex
end

function P.preposition(document, first, limit, motion, displacement, context, secondaryContext)
    local english = document.direction == "en-uk"
    if english and P.key(document, first, limit) == "of" then return nil end
    local choices, last = L.functional(document, "prepositions", first, limit)
    if not choices or last > limit then return nil end
    local selected, after, priority, ambiguous
    for _, id in ipairs(choices) do
        local rule = ns.Linguistics.grammar.prepositions[id]
        local case = english and displacement and rule.id == "in" and "accusative" or rule.case
        local object, ending
        if (not rule.requiresMotion or motion) and (not rule.excludesMotion or not motion)
            and (not rule.directional or english or motion or displacement)
            and (not rule.context or rule.context == context or rule.context == secondaryContext) then
            local spatial = rule.requiresSpatialContainer or displacement and rule.id == "in"
            local locationOnly = rule.requiresSpatialContainer
                or not displacement and (rule.id == "in" or rule.id == "to" or rule.id == "from")
            local sense = (not rule.bareContextAlias or P.key(document, last + 1, limit) == rule.bareContextAlias)
                and rule.objectSense or nil
            object, ending = P.noun(document, last + 1, limit, case, locationOnly, nil, nil,
                sense, spatial and P.spatialContainer)
            if not object and spatial and not rule.requiresSpatialContainer then
                object, ending = P.noun(document, last + 1, limit, case, locationOnly, nil, nil, sense)
            end
        end
        local frame = object and object.entry and object.entry.lexeme.frame
        local class = P.semanticClass(object)
        if object and (not rule.requiresCategory or (object.term and object.term.category == rule.requiresCategory))
            and (not rule.requiresClass or class == rule.requiresClass)
            and (not rule.requiresClasses or rule.requiresClasses[class])
            and (not rule.requiresTrait or P.hasTrait(object, rule.requiresTrait))
            and (not rule.requiresResource or P.isResource(object))
            and (not rule.requiresSpatialContainer or P.spatialContainer(object))
            and (not rule.requiresLexicalLocative or (frame and frame.locativePreposition == rule.targetUk))
            and (not rule.requiresNearLandmark or (frame and frame.atNearLandmark)) then
            local rank = (rule.requiresLexicalLocative or rule.requiresNearLandmark or rule.requiresCategory
                or rule.requiresClass or rule.requiresClasses or rule.requiresTrait or rule.requiresResource
                or rule.requiresSpatialContainer) and 1 or 0
            if rule.context then rank = rank + 2 end
            if not priority or rank > priority then
                selected, after, priority, ambiguous = {rule=rule, object=object, case=case}, ending, rank, false
            elseif rank == priority then ambiguous = true end
        end
    end
    if ambiguous or not selected then return nil end
    local eventLemma = english and selected.rule.opponentEvent
    if eventLemma and P.semanticClass(selected.object) == "opponent" then
        local entry = L.choose(document, eventLemma, "noun")
        local frame = entry and entry.lexeme.frame
        local argument = frame and frame.nominalArguments and frame.nominalArguments[1]
        if not argument then return nil end
        local event = lexicalNoun(entry)
        event.argument = {object=selected.object, form=argument}
        selected.object = event
    end
    return selected, after
end

local nominalCases = {root="nominative", nsubj="nominative", obj="accusative",
    iobj="dative", vocative="vocative", nmod="genitive"}
local nominalTags = {NOUN=true, PROPN=true, PRON=true}
local nominalModifiers = {
    amod={ADJ=true}, det={DET=true, PRON=true}, nummod={NUM=true},
    compound={NOUN=true, PROPN=true}, flat={PROPN=true}, ["nmod:poss"]={NOUN=true, PROPN=true, PRON=true},
    nmod={NOUN=true, PROPN=true}, case={ADP=true}, advmod={ADV=true},
}

-- Recover a complete, contiguous nominal group from the dependency graph.
-- The weighted parse proposes the span and grammatical role. The phrase
-- parser must independently consume the span before it can be rendered.
function P.dependencyNominals(document, first, arcs, words, blocked, motion)
    local children, groups = {}, {}
    for position, arc in ipairs(arcs) do
        if arc.head > 0 then
            local list = children[arc.head] or {}
            list[#list + 1], children[arc.head] = position, list
        end
    end
    for head, arc in ipairs(arcs) do
        local role = arc.relation:match("^[^:]+")
        local case = nominalCases[role]
        if (case or role == "obl") and nominalTags[words[head].upos] then
            local left, right, count, adposition = head, head, 0, nil
            local pending, seen = {head}, {}
            while #pending > 0 and count <= 8 do
                local position = table.remove(pending)
                if not seen[position] then
                    seen[position], count = true, count + 1
                    left, right = math.min(left, position), math.max(right, position)
                    for _, child in ipairs(children[position] or {}) do
                        local relation = arcs[child].relation
                        local allowed = nominalModifiers[relation]
                        if allowed and allowed[words[child].upos]
                            and (relation ~= "advmod" or words[position].upos == "ADJ") then
                            pending[#pending + 1] = child
                            if position == head and relation == "case" then adposition = child end
                        end
                    end
                end
            end
            local start, finish = first + left - 1, first + right - 1
            local usable = count > 1 and count <= 8 and count == right - left + 1 and #pending == 0
                and (adposition == left or not adposition and case)
            if usable then
                for index = start, finish do
                    if blocked[index] or document.tokens[index].protected then usable = false; break end
                end
            end
            if usable then
                local phrase, after
                if adposition then phrase, after = P.preposition(document, start, finish, motion)
                else phrase, after = P.noun(document, start, finish, case) end
                if phrase and after == finish + 1 then
                    groups[#groups + 1] = {first=start, last=finish, case=case, phrase=phrase, preposition=adposition ~= nil}
                end
            end
        end
    end
    table.sort(groups, function(a, b)
        if a.first == b.first then return a.last > b.last end
        return a.first < b.first
    end)
    return groups
end

local listingComma = {id="and", comma=true}
local listingAnd = {id="and", en={"and"}, uk={"і"}}
function P.coordinated(document, first, limit, case, startsPredicate, locationOnly, enumeration, sense, headFilter)
    local head, index = P.noun(document, first, limit, case, locationOnly, nil, nil, sense, headFilter)
    if not head then return nil end
    local members, joins = {head}, {}
    for _ = 2, enumeration and 6 or 4 do
        local comma = enumeration and P.key(document, index, limit) == ","
        local start = index + (comma and 1 or 0)
        local choices, last = L.functional(document, "connectors", start, limit)
        local connector = choices and ns.Linguistics.grammar.connectors[choices[1]]
        if enumeration and P.key(document, start, limit) == "&" then connector, last = listingAnd, start
        elseif comma and not connector then connector, last = listingComma, index end
        if not connector or (connector.id ~= "and" and connector.id ~= "or") then break end
        local member, after = P.noun(document, last + 1, limit, case, locationOnly, nil, nil, sense, headFilter)
        if not member or (startsPredicate and startsPredicate(last + 1)) then break end
        members[#members + 1] = member
        joins[#joins + 1] = connector
        index = after
    end
    if #members == 1 then return head, index end
    local person, number = head.person, head.number
    for i, connector in ipairs(joins) do
        local member = members[i + 1]
        if connector.id == "and" then
            person, number = math.min(person, member.person), "plural"
        elseif case == "nominative" then
            -- Agreement across a disjunction is language-specific. Leave a
            -- mixed-number subject unresolved instead of guessing a form.
            if person ~= member.person or number ~= member.number then return nil end
        end
    end
    return {members=members, joins=joins, person=person, number=number}, index
end

function P.quantity(document, first, limit)
    local key = P.key(document, first, limit)
    if not key then return nil end
    local approximate = key == "like" or key == "around" or key == "about" or key == "approximately"
        or key == "приблизно" or key == "близько"
    if approximate then first = first + 1; key = P.key(document, first, limit) end
    if not key then return nil end
    local amount, unit = key:match("^(%d+)([a-z]+)$")
    local after = first + 1
    local english = document.direction == "en-uk"
    local grammar = ns.Linguistics.grammar
    local cardinals = english and grammar.cardinalEn or grammar.cardinalUk
    local cardinal = cardinals and cardinals[key]
    local noArticle = key == "кілька"
    local few = noArticle or (english and key == "a" and P.key(document, after, limit) == "few")
    local half = english and key == "half" or not english and (key == "пів" or key == "півгодини")
    if half then
        if key == "півгодини" then unit = "години"
        else
            local article = english and P.key(document, after, limit)
            if article == "a" or article == "an" then after = after + 1 end
            unit, after = P.key(document, after, limit), after + 1
        end
    elseif few then
        if not noArticle then after = after + 1 end
        unit, after = P.key(document, after, limit), after + 1
    elseif cardinal or english and (key == "a" or key == "an") then
        amount, unit, after = tostring(cardinal or 1), P.key(document, after, limit), after + 1
    elseif not amount and key:match("^%d+$") then
        amount, unit, after = key, P.key(document, after, limit), after + 1
        local separator = unit
        if separator == "." or separator == "," then
            local decimal, decimalUnit = (P.key(document, after, limit) or ""):match("^(%d+)([a-z]*)$")
            if not decimal or document.tokens[first].last + 1 ~= document.tokens[first + 1].first
                or document.tokens[first + 1].last + 1 ~= document.tokens[after].first then return nil end
            amount, unit, after = amount .. separator .. decimal, decimalUnit, after + 1
            if unit == "" then unit, after = P.key(document, after, limit), after + 1 end
        end
    end
    local lemma = timeUnits[unit]
    if lemma and (half or few or amount and #amount <= 12) then
        return {amount=amount, unit=lemma, approximate=approximate, few=few, half=half}, after
    end
end

function P.delay(document, first, limit)
    local marker = P.key(document, first, limit)
    local english = document.direction == "en-uk"
    if not (english and marker == "in" or not english and (marker == "за" or marker == "через")) then return end
    local quantity, after = P.quantity(document, first + 1, limit)
    if quantity then return quantity, after end
    if english and P.key(document, first + 1, limit) == "a" and P.key(document, first + 2, limit) == "few" then
        return {soon=true}, first + 3
    end
end

function P.multiplier(document, first, limit)
    local head = P.key(document, first, limit)
    if document.direction == "en-uk" then
        if head == "twice" or head == "half" then return 2, first + 1, head == "half" end
        if head == "a" or head == "one" then
            local fraction = ({third=3, quarter=4})[P.key(document, first + 1, limit)]
            if fraction then return fraction, first + 2, true end
        elseif head == "1" and P.key(document, first + 1, limit) == "/" then
            local denominator = P.key(document, first + 2, limit)
            local cardinal = denominator and denominator:match("^%d+$") and tonumber(denominator)
            if cardinal and cardinal >= 2 and cardinal < 1000 then return cardinal, first + 3, true end
        end
        local cardinal = head and (ns.Linguistics.grammar.cardinalEn[head] or tonumber(head))
        if cardinal and cardinal >= 2 and cardinal < 1000 and cardinal % 1 == 0
            and P.key(document, first + 1, limit) == "times" then return cardinal, first + 2 end
    else
        if head == "удвічі" or head == "вдвічі" then return 2, first + 1 end
        if head == "утричі" or head == "втричі" then return 3, first + 1 end
        local amount = P.key(document, first + 1, limit)
        local cardinal = amount and amount:match("^%d+$") and tonumber(amount)
        local unit = P.key(document, first + 2, limit)
        if (head == "у" or head == "в") and cardinal and cardinal >= 2 and cardinal < 1000
            and (unit == "рази" or unit == "разів" or unit == "раз") then return cardinal, first + 3 end
    end
end
P.englishUnits = englishUnits
