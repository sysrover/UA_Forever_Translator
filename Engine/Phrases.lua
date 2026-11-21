local _, ns = ...
local P = {}
ns.Engine.Phrases = P
local L = ns.Engine.Lexicon
local A = ns.Engine.Apertium
P.spatialAdjuncts = { ["in"]=true, ["in-chat"]=true, on=true, near=true, behind=true, ["on-layer"]=true,
    ["outside-access"]=true,
    ["at-landmark"]=true, ["at-near-landmark"]=true, ["at-spatial-boundary"]=true }

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
local wholeForms = {
    nominative={masculine="весь", feminine="уся", neuter="усе"},
    genitive={masculine="усього", feminine="усієї", neuter="усього"},
    dative={masculine="усьому", feminine="усій", neuter="усьому"},
    accusative={masculine="весь", feminine="усю", neuter="усе"},
    instrumental={masculine="усім", feminine="усією", neuter="усім"},
    locative={masculine="усьому", feminine="усій", neuter="усьому"},
}
P.wholeForms = wholeForms

local function wholeAgreement(key, case)
    local genders
    for gender, form in pairs(wholeForms[case] or {}) do
        if key == form or key == "в" .. form:sub(3) or form == "весь" and key == "увесь" then
            genders = genders or {}
            genders[gender] = true
        end
    end
    return genders
end
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
P.locativeRelativeMarker = {["en-uk"]="where", ["uk-en"]="де"}
function P.exclusionMarker(direction, key)
    if direction == "en-uk" then return key == "no" end
    return key == "жодних" or key == "жодного" or key == "жодної"
end

function P.nominalRestriction(document, first, limit)
    local choices, last = L.functional(document, "adverbs", first, limit)
    for _, id in ipairs(choices or {}) do
        local adverb = ns.Linguistics.grammar.adverbs[id]
        if adverb.context == "nominalRestriction" then return adverb, last + 1 end
    end
end
local agreeingRelative = {}
for _, forms in pairs(relativeDeclension) do
    for _, word in pairs(forms) do
        agreeingRelative[word] = true
        P.relativeMarkers["uk-en"][word] = true
    end
end
for _, word in pairs(indefiniteRelative) do P.relativeMarkers["uk-en"][word] = true end

local function indefinitePerson(noun)
    local id = noun.pronoun and noun.pronoun.id
    return id == "someone" or id == "everyone"
end

function P.relativeAnimate(noun)
    if noun.members then
        for _, member in ipairs(noun.members) do
            if not P.relativeAnimate(member) then return false end
        end
        return true
    end
    return noun.animacy == "animate" or indefinitePerson(noun)
        or noun.term and personalTerms[noun.term.category]
end

function P.personNoun(noun)
    local pronoun = noun and noun.pronoun
    return noun and (P.relativeAnimate(noun) or pronoun and not (pronoun.inanimate or pronoun.id == "it")
        or noun.raw and ns.Engine.Markup.isLink(noun.raw, "player"))
end

function P.subjectPossessive(subject)
    if not subject then return nil end
    local pronoun = subject.pronoun
    if pronoun and pronoun.en.possessive then return pronoun.en.possessive end
    if subject.person == 1 then return subject.number == "plural" and "our" or "my" end
    if subject.person == 2 then return "your" end
    if subject.number == "plural" or P.relativeAnimate(subject) then return "their" end
    return "its"
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

local selfEmphasisUk = {masculine="сам", feminine="сама", neuter="само"}
function P.selfChangeEmphasis(subject, english)
    if not subject or subject.person ~= 3 or P.relativeAnimate(subject) then return nil end
    if subject.number == "plural" then return english and "themselves" or "самі" end
    if english then return "itself" end
    return selfEmphasisUk[subject.gender]
end

function P.agentReflexive(subject)
    if not subject then return nil end
    local plural = subject.number == "plural"
    if subject.person == 1 then return plural and "ourselves" or "myself" end
    if subject.person == 2 then return plural and "yourselves" or "yourself" end
    if plural then return "themselves" end
    if subject.pronoun and subject.pronoun.inanimate or subject.animacy == "inanimate" then return "itself" end
    if subject.gender == "masculine" then return "himself" end
    if subject.gender == "feminine" then return "herself" end
end
local timeUnits = {
    min="хвилина", mins="хвилина", minute="хвилина", minutes="хвилина",
    s="секунда", sec="секунда", secs="секунда", second="секунда", seconds="секунда",
    h="година", hr="година", hrs="година", hour="година", hours="година",
    day="день", days="день",
    week="тиждень", weeks="тиждень", wk="тиждень", wks="тиждень",
    month="місяць", months="місяць",
    year="рік", years="рік", yr="рік", yrs="рік",
    ["хвилина"]="хвилина", ["хвилини"]="хвилина", ["хвилин"]="хвилина",
    ["секунда"]="секунда", ["секунди"]="секунда", ["секунд"]="секунда",
    ["година"]="година", ["години"]="година", ["годин"]="година",
    ["день"]="день", ["дня"]="день", ["дні"]="день", ["днів"]="день",
    ["тиждень"]="тиждень", ["тижні"]="тиждень", ["тижнів"]="тиждень",
    ["місяць"]="місяць", ["місяці"]="місяць", ["місяців"]="місяць",
    ["рік"]="рік", ["роки"]="рік", ["років"]="рік",
}
local englishUnits = {["хвилина"]="minute", ["секунда"]="second", ["година"]="hour", ["день"]="day",
    ["тиждень"]="week", ["місяць"]="month", ["рік"]="year"}
local singularTimeForms = {
    ["хвилину"]="хвилина", ["хвилини"]="хвилина", ["секунду"]="секунда", ["секунди"]="секунда",
    ["годину"]="година", ["години"]="година", ["день"]="день", ["дня"]="день",
    ["тиждень"]="тиждень", ["тижня"]="тиждень", ["місяць"]="місяць", ["місяця"]="місяць",
    ["рік"]="рік", ["року"]="рік",
}

function P.key(document, index, limit)
    return index <= limit and document.tokens[index] and document.tokens[index].key
end

function P.raw(document, first, last)
    return document.text:sub(document.tokens[first].first, document.tokens[last].last)
end

function P.ratingNote(document, first, limit)
    local tokens = document.tokens
    local opening = P.key(document, first, limit)
    local closing = opening == "(" and ")" or opening == "[" and "]" or opening == "*" and "*"
    local start = first + (closing and 1 or 0)
    local key = P.key(document, start, limit)
    if not key or start >= limit then return nil end
    local value = key:match("^%d+$")
    local labels, ending = L.functional(document, "ratingLabels", start + (value and 1 or 0), limit)
    if not labels or #labels ~= 1 then return nil end
    if not value then
        ending = ending + (P.key(document, ending + 1, limit) == ":" and 2 or 1)
        local quantity = P.key(document, ending, limit)
        value = quantity and quantity:match("^%d+$")
        if not value then return nil end
    end
    if closing then
        ending = ending + 1
        if P.key(document, ending, limit) ~= closing then return nil end
    elseif ending ~= limit then return nil end
    if ending < limit and tokens[ending].last + 1 >= tokens[ending + 1].first then return nil end
    return {label=ns.Linguistics.grammar.ratingLabels[labels[1]], value=value,
        opening=closing and opening, closing=closing}, ending + 1
end

function P.menuPath(document, first, limit)
    if limit - first < 2 then return nil end
    if document.hasMenuSeparator == nil then
        local text = document.text
        document.hasMenuSeparator = not not (text:find(">", 1, true) or text:find("→", 1, true) or text:find("›", 1, true))
    end
    if not document.hasMenuSeparator then return nil end
    local labels, separators = {}, {}
    local index = first
    for _ = 1, 8 do
        local choices, ending = L.functional(document, "menuLabels", index, limit)
        if not choices or #choices ~= 1 then return nil end
        labels[#labels + 1] = ns.Linguistics.grammar.menuLabels[choices[1]]
        if ending == limit then
            if #labels > 1 then return {kind="menuPath", labels=labels, separators=separators} end
            return nil
        end
        local nextIndex = ending + 1
        local marker = P.key(document, nextIndex, limit)
        if marker == "-" and P.key(document, nextIndex + 1, limit) == ">"
            and document.tokens[nextIndex].last + 1 == document.tokens[nextIndex + 1].first then
            index = nextIndex + 2
        elseif marker == ">" or marker == "→" or marker == "›" then
            index = nextIndex + 1
        else
            return nil
        end
        if index > limit then return nil end
        separators[#separators + 1] = document.text:sub(document.tokens[ending].last + 1, document.tokens[index].first - 1)
    end
end

function P.calendar(document, first, limit, shared)
    local english = document.direction == "en-uk"
    local marker = P.key(document, first, limit)
    local preposition = english and marker == "on" or not english and (marker == "у" or marker == "в")
    local start = first + (preposition and 1 or 0)
    local choices, last = L.functional(document, "calendarDays", start, limit)
    if not choices or #choices ~= 1 then return nil end
    local day = ns.Linguistics.grammar.calendarDays[choices[1]]
    local key = P.key(document, start, limit)
    local repeated = key == (english and day.en[2] or day.uk[2])
    local abbreviated = english and key ~= day.en[1] and not repeated
    if abbreviated and not (preposition or shared) then return nil end
    if not english and not (preposition or repeated or shared) then return nil end
    local phases, finish = L.functional(document, "calendarPhases", last + 1, limit)
    local phase = phases and #phases == 1 and ns.Linguistics.grammar.calendarPhases[phases[1]] or nil
    if phase then
        repeated = repeated or english and P.key(document, last + 1, limit) == phase.en[2]
        last = finish
    end
    return {day=day, phase=phase, repeated=repeated, bareAbbreviation=abbreviated and not preposition}, last + 1
end

local clockSeparators = {["-"]=true, ["–"]=true, ["—"]=true, ["‐"]=true, ["‑"]=true}
local clockZones = {utc=true, gmt=true, cet=true, cest=true, est=true, edt=true, pst=true, pdt=true}

local function clockAt(document, first, limit)
    local hour = P.key(document, first, limit)
    local minute = P.key(document, first + 2, limit)
    if not hour or not hour:match("^%d%d?$") or tonumber(hour) > 23
        or P.key(document, first + 1, limit) ~= ":" or not minute or not minute:match("^%d%d$") or tonumber(minute) > 59 then
        return nil
    end
    return hour .. ":" .. minute, first + 3
end

function P.clockSchedule(document, first, limit)
    local english = document.direction == "en-uk"
    local marker = P.key(document, first, limit)
    local from = english and marker == "from" or not english and (marker == "з" or marker == "із" or marker == "зі")
    local point = english and marker == "at" or not english and (marker == "о" or marker == "об")
    local start, after = clockAt(document, first + ((from or point) and 1 or 0), limit)
    if not start then return nil end
    local ending, finish = nil, after
    if not point then
        local separator = P.key(document, after, limit)
        if not (clockSeparators[separator] or from and separator == (english and "to" or "до")) then return nil end
        ending, finish = clockAt(document, after + 1, limit)
        if not ending then return nil end
    end
    local zone
    local zoneKey = P.key(document, finish, limit)
    if clockZones[zoneKey] then
        local zoneStart = finish
        finish = finish + 1
        local sign = P.key(document, finish, limit)
        if (zoneKey == "utc" or zoneKey == "gmt") and (sign == "+" or sign == "-" or sign == "−") then
            local hour = P.key(document, finish + 1, limit)
            if not hour or not hour:match("^%d%d?$") or tonumber(hour) > 23 then return nil end
            finish = finish + 2
            if P.key(document, finish, limit) == ":" then
                local minute = P.key(document, finish + 1, limit)
                if not minute or not minute:match("^%d%d$") or tonumber(minute) > 59 then return nil end
                finish = finish + 2
            end
        end
        zone = P.raw(document, zoneStart, finish - 1)
    end
    return {start=start, ending=ending, zone=zone}, finish
end

function P.calendarList(document, first, limit)
    local head, finish = P.calendar(document, first, limit, document.direction == "en-uk")
    if not head then return nil end
    local members
    for _ = 2, 7 do
        local join = P.key(document, finish, limit)
        local comma = join == ","
        if comma then join = P.key(document, finish + 1, limit) end
        local connector = join == "&" or (document.direction == "en-uk" and join == "and")
            or (document.direction == "uk-en" and (join == "і" or join == "й" or join == "та"))
        if not (comma or connector) then break end
        local member, after = P.calendar(document, finish + (comma and 1 or 0) + (connector and 1 or 0), limit, true)
        if not member then break end
        members = members or {head}
        members[#members + 1], finish = member, after
    end
    if members then return {members=members}, finish end
    if head.bareAbbreviation then
        local nextIndex = finish + (P.key(document, finish, limit) == "," and 1 or 0)
        if not P.clockSchedule(document, nextIndex, limit) then return nil end
    end
    return head, finish
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
        local additionalSenses = term.features and term.features.contextAliasSenses
        if raw and aliasSense and sense ~= aliasSense and not (additionalSenses and additionalSenses[sense]) then
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
    if noun.controlLabel then return "uiControl" end
    local frame = noun.entry and noun.entry.lexeme.frame
    local term = noun.term
    return noun.referenceClass or frame and frame.semanticClass
        or term and (term.features and term.features.semanticClass or term.category)
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

function P.predicatePossessive(document, index, limit, subject)
    local key = P.key(document, index, limit)
    if not key then return nil end
    if document.direction == "en-uk" then
        local determiner = ns.Linguistics.grammar.predicatePossessives[key]
        return determiner and L.choose(document, determiner, "pron", nil, nil, possessive)
    end
    return possessiveReading(document, index, "nominative", subject)
end

local function ownPeople(document, first, limit, case)
    local english = document.direction == "en-uk"
    if english and P.key(document, first + 1, limit) ~= "own" then return nil end
    local after = first + (english and 2 or 1)
    local following = P.key(document, after, limit)
    if following and not following:match("^[,.;!?]$") and not L.functional(document, "connectors", after, limit) then
        return nil
    end
    local noun = {person=3, number="plural", animacy="animate", ownPeople=true}
    local possessiveEntry
    if english then possessiveEntry = L.choose(document, first, "pron", nil, nil, possessive)
    else possessiveEntry = possessiveReading(document, first, case, noun) end
    if not possessiveEntry then return nil end
    noun.possessor = possessiveEntry
    return noun, after
end

function P.pronoun(document, first, limit, case, personOnly, headlessQuantity, matchingReferent)
    local choices, last = L.functional(document, "pronouns", first, limit)
    if not choices then return nil end
    local selected
    for _, match in ipairs(choices) do
        local valid = case == match.case or (case ~= "nominative" and match.case ~= "nominative"
            and match.case ~= "possessive" and document.direction == "en-uk")
        local candidate = ns.Linguistics.grammar.pronouns[match.id]
        if valid and (not candidate.requiresExplicitReferent or matchingReferent == candidate.id)
            and candidate.headlessQuantity == headlessQuantity
            and (not personOnly or candidate.id ~= "it" and not candidate.inanimate)
            and (not matchingReferent or candidate.id == matchingReferent) then
            if selected and selected ~= candidate then return false end
            selected = candidate
        end
    end
    if selected then
        local number = document.direction == "uk-en" and selected.ukNumber or selected.number
        local animacy = selected.headlessQuantity and not selected.inanimate and "animate" or nil
        return {pronoun=selected, person=selected.person, gender=selected.gender, number=number, animacy=animacy}, last + 1
    end
end

local function allowsNounSpelling(document, entry, first, last, limit, sense)
    local frame = entry.lexeme.frame
    local aliases = document.direction == "en-uk" and frame and frame.restrictedNounAliases
    local alias = aliases and first == last and aliases[document.tokens[first].key]
    return not alias or alias.sense == sense and (not alias.spelling or P.raw(document, first, last) == alias.spelling)
        and not (alias.excludesFollowing and alias.excludesFollowing[P.key(document, last + 1, limit)])
end

local function namedReference(document, index, annotation)
    local token = document.tokens[index]
    if not token or not token.protected then return nil end
    local raw = P.raw(document, index, index)
    if token.linkKind == "unit" or token.linkKind == "player" then
        return {raw=raw, person=3, number="singular", animacy="animate", entityReference=true}
    end
    if token.linkKind and not (annotation and token.linkKind == "quest") then return nil end
    local label = ns.Engine.Markup.bracketLabel(raw)
    if not label then return nil end
    local dictionary = ns.Engine.Dictionary
    for _, direction in ipairs({"en-uk", "uk-en"}) do
        local term = dictionary.lookup(label, direction)
        local features = term and term.features
        if features and features.proper and (term.category == "creatures" or term.category == "characters") then
            return {raw=raw, person=3, number="singular", gender=features.gender, animacy="animate", entityReference=true}
        end
    end
end

local function nounHead(document, first, limit, case, locationOnly, sense, agrees, adjectivalComplement)
    local key = P.key(document, first, limit)
    if not key then return nil end
    local token = document.tokens[first]
    if token.protected then
        local reference = not locationOnly and namedReference(document, first)
        if reference then
            if not agrees or agrees(reference) then return reference, first + 1 end
            return nil
        end
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
                and allowsNounSpelling(document, candidate, first, phraseEnd - 1, limit, sense)
                and (not agrees or agrees(lexicalNoun(candidate)))
        end
        local entry = adjectivalComplement and L.choose(document, phrase, "noun", nil, "adjectivalComplement",
            function(candidate) return grammaticalPhrase(candidate) and adjectivalComplement(candidate) end)
            or sense and L.choose(document, phrase, "noun", nil, sense, grammaticalPhrase)
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
            function(candidate)
                return allowsNounSpelling(document, candidate, first, first, limit, sense)
                    and (not agrees or agrees(lexicalNoun(candidate)))
            end)
        if contextual then return lexicalNoun(contextual), first + 1 end
    end
    if known then
        local practitioner = document.direction == "en-uk" and known.term.englishPractitioner
        if practitioner and known.last == first and key == ns.Engine.Normalize.word(practitioner) then
            local entry = L.choose(document, first, "noun", nil, nil, function(candidate)
                local frame = candidate.lexeme.frame
                return frame and frame.practitionerOf == known.term.id and (not agrees or agrees(lexicalNoun(candidate)))
            end)
            if entry then return lexicalNoun(entry), first + 1 end
        end
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
        return allowsNounSpelling(document, candidate, first, first, limit, sense)
            and (not reverseCase or candidate.form.case == reverseCase
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

local function determinerForms(document, key, lemma)
    if not key or not ns.ApertiumData then return nil end
    local options
    for raw in pairs(A.analyze(key, "uk", document) or {}) do
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

local function nominalMarkerPhrase(document, first, limit, phrase)
    local index = first
    for word in phrase:gmatch("%S+") do
        if P.key(document, index, limit) ~= word then return nil end
        index = index + 1
    end
    return index
end

local function nominalMarkerEnd(document, first, limit, rule, english)
    if first > limit then return nil end
    local marker = english and rule.en or not english and rule.uk
    if marker then
        local after = nominalMarkerPhrase(document, first, limit, marker)
        if after then return after end
    end
    local aliases = english and rule.enAliases or not english and rule.ukAliases
    for _, alias in ipairs(aliases or {}) do
        local after = nominalMarkerPhrase(document, first, limit, alias)
        if after then return after end
    end
end

local function nominalCompoundArgument(head, prefix, sense)
    local frame = head and head.entry and head.entry.lexeme.frame
    for _, argument in ipairs(frame and frame.nominalArguments or {}) do
        if argument.englishCompound and argument.classes and argument.classes[P.semanticClass(prefix)]
            and (not argument.argumentTrait or P.hasTrait(prefix, argument.argumentTrait))
            and (not sense or argument.argumentSense == sense) then return argument end
    end
end

local function contextualNominalCompound(document, first, limit, case, locationOnly, classes)
    for _, candidate in ipairs(document.spans[first] or {}) do
        local features = candidate.term.features
        local sense = features and features.contextAliasSense
        if sense and classes[features.semanticClass] and candidate.last < limit then
            local anchor = candidate.last + 1
            local head, after = nounHead(document, anchor, limit, case, locationOnly)
            -- A context-only spelling needs a head that governs that sense.
            local prefix = curatedNoun(candidate)
            local argument = nominalCompoundArgument(head, prefix, sense)
            if argument then
                head.argument = {object=prefix, form=argument, compound=true}
                return head, after, anchor
            end
        end
    end
    if first >= limit then return nil end
    for _, entry in ipairs(L.at(document, first)) do
        local frame = entry.lexeme.frame
        if entry.lexeme.pos == "noun" and frame and frame.contextOnly and frame.sense and classes[frame.semanticClass] then
            local anchor = first + 1
            local head, after = nounHead(document, anchor, limit, case, locationOnly)
            local reading = L.choose(document, first, "noun", nil, frame.sense, function(candidate)
                return allowsNounSpelling(document, candidate, first, first, limit, frame.sense)
            end)
            local prefix = reading and lexicalNoun(reading)
            local argument = prefix and nominalCompoundArgument(head, prefix, frame.sense)
            if argument then
                head.argument = {object=prefix, form=argument, compound=true}
                return head, after, anchor
            end
        end
    end
end

local function activityTopic(noun)
    return P.hasTrait(noun, "activityTopic")
end

local function activityAudience(noun)
    return P.hasTrait(noun, "activityAudience") and noun.argument ~= nil
end

local function activityTopics(document, first, limit, case)
    return P.coordinated(document, first, limit, case, nil, nil, true, nil, activityTopic, true)
end

local function audienceWithTopics(document, first, limit, prefix, required)
    local topics, after
    local beforeHead = activityTopic(prefix)
    local anchor = first
    if beforeHead then
        topics, anchor = activityTopics(document, first, limit, "nominative")
        if not topics then return end
        after = anchor + 1
    elseif P.key(document, first + 1, limit) ~= "of" then
        return
    end
    local entry = L.choose(document, anchor, "noun", nil, "activityAudience",
        required and function(candidate) return required(lexicalNoun(candidate)) end)
    if not entry then return end
    if not beforeHead then topics, after = activityTopics(document, first + 2, limit, "nominative") end
    if not topics then return end
    local noun = lexicalNoun(entry)
    noun.argument = {object=topics, form=entry.lexeme.frame.nominalArguments[1]}
    return noun, after, anchor
end

local function nominalInclusion(document, first, limit, english)
    local start = first + (P.key(document, first, limit) == "," and 1 or 0)
    if P.key(document, start, limit) ~= (english and "including" or "зокрема") then return end
    local explicitAudience = P.key(document, start + 1, limit) == (english and "for" or "для")
    local members, finish = P.coordinated(document, start + (explicitAudience and 2 or 1), limit,
        explicitAudience and "genitive" or "nominative", nil, nil, true, nil, function(candidate)
            return activityTopic(candidate) or P.hasTrait(candidate, "activityAudience")
        end)
    if not members then return end
    local audience = activityAudience(members.members and members.members[1] or members)
    if explicitAudience and not audience then return end
    for _, member in ipairs(members.members or {members}) do
        if audience and not activityAudience(member) or not audience and not activityTopic(member) then return end
    end
    return {object=members, audience=audience}, finish
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

function P.cardinal(document, key, case)
    local grammar = ns.Linguistics and ns.Linguistics.grammar
    if not grammar or not key then return nil end
    if document.direction == "en-uk" then return grammar.cardinalEn[key] end
    local byCase = case and grammar.cardinalUkByCase and grammar.cardinalUkByCase[case]
    return oneSurfaces[key] and 1 or grammar.cardinalUk[key]
        or grammar.collectiveUk and grammar.collectiveUk[key] or byCase and byCase[key]
end

function P.countedCase(amount, case, animate)
    local number = tonumber((amount:gsub(",", ".")))
    if not number or number % 1 ~= 0 then return "genitive", "singular" end
    local last, pair = number % 10, number % 100
    if last == 1 and pair ~= 11 then return case, "singular" end
    if case == "nominative" or case == "accusative" then
        if last >= 2 and last <= 4 and (pair < 12 or pair > 14) and not (case == "accusative" and animate) then
            return "nominative", "plural"
        end
        return "genitive", "plural"
    end
    return case, "plural"
end

function P.nominalMeasureAt(document, index, limit, compound)
    local key = P.key(document, index, limit)
    local count = key and key:match("^%d+$") and tonumber(key) or P.cardinal(document, key, "accusative")
    if not count or count < 1 or count > 999999999 then return nil end
    local unitAt = index + 1
    if compound and P.key(document, unitAt, limit) == "-" then unitAt = unitAt + 1 end
    if unitAt > limit then return nil end
    local quantity = tostring(count)
    local features
    if document.direction == "en-uk" then
        features = {number=(compound or count == 1) and "singular" or "plural"}
    else
        local case, number = P.countedCase(quantity, "accusative", false)
        features = {case=case, number=number}
    end
    local unit = L.choose(document, unitAt, "noun", features, "nominalMeasure")
    if unit then return {entry=unit, quantity=quantity}, unitAt + 1 end
end

function P.levelNumberAt(document, index, limit)
    local number = P.key(document, index, limit)
    if number and number:match("^%d%d?%d?$") and tonumber(number) > 0 then return number end
end

function P.skillRequirementAt(document, index, limit, english)
    local key = P.key(document, index, limit)
    local nextKey = P.key(document, index + 1, limit)
    if english and key == "requiring" and nextKey == "skill" then
        local amount = P.levelNumberAt(document, index + 2, limit)
        if amount then return amount, index + 3 end
    elseif not english and key == "(" and nextKey == "навичка" and P.key(document, index + 3, limit) == ")" then
        local amount = P.levelNumberAt(document, index + 2, limit)
        if amount then return amount, index + 4 end
    elseif not english and key == "з" and nextKey == "вимогою" and P.key(document, index + 2, limit) == "навички" then
        local amount = P.levelNumberAt(document, index + 3, limit)
        if amount then return amount, index + 4 end
    end
end

function P.skillRequirementPrefix(document, index, limit, case, sense)
    local marker = P.key(document, index, limit)
    if marker ~= "level" and marker ~= "lvl" then return nil end
    local amount = P.levelNumberAt(document, index + 1, limit)
    if not amount then return nil end
    local scoped = sense == "openable" and "skillRequirementHead" or nil
    local head = nounHead(document, index + 2, limit, case, false, scoped, function(noun)
        return P.hasTrait(noun, "skillThreshold")
    end)
    if head then return amount, scoped end
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
local function describeTitle(document, node, after, limit, case, class)
    if not class then return node, after end
    local separator = P.key(document, after, limit)
    local start = after + ((separator == "," or separator == "—") and 1 or 0)
    local key = P.key(document, start, limit)
    if key and key ~= "[" and not document.tokens[start].protected then
        local description, finish = P.noun(document, start, limit, case)
        if P.semanticClass(description) == class and description.number == node.number then
            node.titleDescription, after = description, finish
        end
    end
    return node, after
end

local function bracketedGoods(document, first, limit, case, simple)
    local name = curated(document, first + 1, limit - 1, nil, false, function(node)
        return node.term.category == "goods"
    end)
    if not name or P.key(document, name.last + 1, limit) ~= "]" then return nil end
    local node, after = curatedNoun(name), name.last + 2
    node.bracketedTitle, node.headIndex = true, first + 1
    local class = not simple and name.term.features and name.term.features.titleDescriptionClass
    return describeTitle(document, node, after, limit, case, class)
end

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

local function nominalArcs(document, first, limit, marker, tag)
    local parser = ns.Engine.UDPipe
    if not parser or not ns.UDPipeModels then return nil end
    local tokens = document.tokens
    while first > 1 and not tokens[first - 1].key:match("^[.!?;]$") do first = first - 1 end
    local finish = first
    while finish < limit and not tokens[finish].key:match("^[.!?;]$") do finish = finish + 1 end
    if finish - first >= 32 then return nil end
    local memo = document.nominalArcs or {attempts=0}
    document.nominalArcs = memo
    local key = first .. ":" .. finish .. ":" .. (marker or 0) .. ":" .. (tag or "")
    if memo[key] == nil and memo.attempts < 3 then
        memo.attempts = memo.attempts + 1
        memo[key] = parser.analyzeDocument(document, first, finish, marker, marker, nil,
            marker and {tag or "CCONJ"}) or false
    end
    return memo[key], first - 1
end

local function nominalSentenceArcs(document, first, limit, marker, tag)
    local terminal = P.key(document, limit + 1, #document.tokens)
    local through = terminal and terminal:match("^[.!?]$") and limit + 1 or limit
    return nominalArcs(document, first, through, marker, tag)
end

local activityOrientationRule = {en={"to"}, targetUk="до", case="genitive", englishArticle=false}

function P.activityOrientation(document, first, limit, features)
    local english = document.direction == "en-uk"
    if first >= limit then return nil end
    local adjective, topics, finish
    local anchor = first
    if not english or P.key(document, first, limit) == "open" then
        if P.key(document, first + 1, limit) ~= (english and "to" or "до") then return nil end
        adjective = L.choose(document, first, "adj", features, "activityOrientation")
        if not adjective then return nil end
        topics, finish = activityTopics(document, first + 2, limit, english and "nominative" or "genitive")
    else
        for index = first + 1, math.min(first + 31, limit) do
            if P.key(document, index, limit) == "friendly" then anchor = index; break end
        end
        if anchor == first then return nil end
        local topicEnd = anchor - (P.key(document, anchor - 1, limit) == "-" and 2 or 1)
        topics, finish = activityTopics(document, first, topicEnd, "nominative")
        if not topics or finish ~= topicEnd + 1 then return nil end
        adjective = L.choose(document, anchor, "adj", nil, "activityOrientation")
        finish = anchor + 1
    end
    if not adjective or not topics then return nil end
    local complement = {rule=activityOrientationRule, case=activityOrientationRule.case, object=topics}
    return {entry=adjective, index=anchor}, complement, finish
end

local function possessionQualification(noun)
    local reading, class
    for _, adjective in ipairs(noun.adjectives or {}) do
        if adjective.join or adjective.comma then return nil end
        local frame = adjective.entry and adjective.entry.lexeme.frame
        if frame and frame.possessionQualification then
            reading, class = adjective, frame.possessionQualification
        end
    end
    return reading, class
end

local function unqualifiedPossession(noun)
    if noun.members or noun.article or noun.possessor or noun.demonstrative or noun.quantity
        or noun.some or noun.few or noun.more or noun.many or noun.sufficient or noun.abundance then return false end
    for _, adjective in ipairs(noun.adjectives or {}) do
        local frame = adjective.entry and adjective.entry.lexeme.frame
        if not (frame and frame.qualificationDomain) or adjective.intensity or adjective.qualifier then return false end
    end
    return true
end

local function nominalAdpositions(document, noun, first, limit)
    local choices = L.functional(document, "prepositions", first, limit)
    if not choices then return nil end
    local rules = ns.Linguistics.grammar.prepositions
    for _, id in ipairs(choices) do
        if rules[id].nominalAdjunct then
            local arcs, offset = nominalSentenceArcs(document, noun.headIndex, limit)
            local marker = arcs and arcs[first - offset]
            local modifier = marker and marker.relation == "case" and arcs[marker.head]
            if not modifier then return nil end
            local relation = modifier.relation:match("^[^:]+")
            local attached = modifier.head + offset == noun.headIndex and relation == "nmod"
            local qualification, class
            if rules[id].id == "with" then qualification, class = possessionQualification(noun) end
            if not attached and not (qualification and relation == "obl") then return nil end
            local phrase, after = P.preposition(document, first, limit, nil, nil, nil, nil, "nominalAdjunct")
            if not phrase or phrase.object.headIndex ~= marker.head + offset then return nil end
            local hasQualification = qualification and phrase.rule.id == "with" and class == P.semanticClass(phrase.object)
            if not (attached or hasQualification) then return nil end
            if hasQualification and not (qualification.intensity or qualification.qualifier or qualification.entry.form.degree
                or noun.degreeMore) and unqualifiedPossession(phrase.object) then
                qualification.impliedByPossession = true
            end
            return phrase, after
        end
    end
end

function P.locativeRelativeHead(document, noun, markerIndex, limit)
    if not noun.headIndex then return nil end
    local arcs, offset = nominalSentenceArcs(document, noun.headIndex, limit)
    local marker = arcs and arcs[markerIndex - offset]
    if not marker or (marker.relation ~= "mark" and marker.relation ~= "advmod") then return nil end
    local predicate = arcs[marker.head]
    if not predicate or predicate.head + offset ~= noun.headIndex then return nil end
    local relation = predicate.relation
    if relation == "acl" or relation == "acl:relcl" or relation == "advcl" then
        return marker.head + offset, arcs, offset
    end
    if relation == "parataxis" and marker.relation == "advmod" and document.direction == "en-uk"
        and P.key(document, markerIndex - 1, limit) ~= "," then
        -- Compare the subordinating reading without changing the proposed heads.
        local alternate = nominalSentenceArcs(document, noun.headIndex, limit, markerIndex, "SCONJ")
        local link = alternate and alternate[markerIndex - offset]
        local dependent = link and alternate[link.head]
        if dependent and link.relation == "mark" and link.head == marker.head
            and dependent.head == predicate.head and dependent.relation == "advcl" then
            return link.head + offset, alternate, offset
        end
    end
end

local function nominalAbsence(document, first, limit, case, sense, agrees, determined)
    local opening = P.key(document, first, limit)
    if not opening or first >= limit then return nil end
    local following = P.key(document, first + 1, limit)
    local hyphen = following == "-"
    local absentIndex, headAt, property
    if opening == "no" then
        if not (hyphen or determined) then return nil end
        absentIndex = first + (hyphen and 2 or 1)
        if absentIndex >= limit then return nil end
        local arcs, offset = nominalSentenceArcs(document, first, limit)
        local modifier = arcs and arcs[absentIndex - offset]
        if not modifier or modifier.relation ~= "compound" or modifier.head + offset ~= absentIndex + 1 then return nil end
        local marker = arcs[first - offset]
        if not marker or not ((marker.relation == "advmod" or marker.relation == "det")
            and (marker.head == absentIndex - offset or marker.head == modifier.head)) then return nil end
    else
        local propertyHead = opening:match("^(%a+)free$")
        if propertyHead then headAt = first + 1
        elseif hyphen and P.key(document, first + 2, limit) == "free" or determined and following == "free" then
            propertyHead, headAt = opening, first + (hyphen and 3 or 2)
        end
        if not propertyHead or headAt > limit then return nil end
        property = L.choose(document, propertyHead, "noun", nil, "absenceProperty")
        if not property then return nil end
    end
    local grammar = ns.Linguistics.grammar
    local ids = grammar.index.en.prepositions.without
    local rule = ids and grammar.prepositions[ids[1]]
    if not rule then return nil end
    local object
    if property then object = lexicalNoun(property)
    else
        object, headAt = nounHead(document, absentIndex, absentIndex, rule.case, false, nil,
            function(noun) return not (noun.pronoun or noun.raw) end)
    end
    if not object then return nil end
    local head, after = nounHead(document, headAt, limit, case, false, sense, agrees)
    if not head or head.pronoun or head.raw then return nil end
    local frame = object.entry and object.entry.lexeme.frame
    if frame and frame.absenceNumber then object.number = frame.absenceNumber end
    head.prepositions = {{rule=rule, object=object, case=rule.case}}
    return head, after, headAt
end

local function participialQualifier(document, index, limit)
    local choices, last = L.functional(document, "adverbs", index, limit)
    for _, id in ipairs(choices or {}) do
        local adverb = ns.Linguistics.grammar.adverbs[id]
        if adverb.participialQualifier then return adverb, last + 1 end
    end
end

local agentRule = {en={"by"}, uk={}, targetUk="", case="instrumental"}

function P.groundedState(document, noun, first, limit, case, attributive)
    local english = document.direction == "en-uk"
    local comma = attributive and P.key(document, first, limit) == ","
    if not english and attributive and not comma then return nil end
    local start = first + (comma and 1 or 0)
    local qualifier, following = participialQualifier(document, start, limit)
    start = following or start
    local key = P.key(document, start + 1, limit)
    local foundation = key == (english and "on" or "на")
    if not key or english and not foundation and key ~= "by" then return nil end
    local requested = not english and {case=case, number=noun.number,
        gender=noun.number == "singular" and noun.gender or nil} or nil
    local sense = foundation and (P.spatialContainer(noun) and "groundedStructure" or "groundedState")
        or "participialState"
    local modifier = L.choose(document, start, "adj", requested, sense)
    if not modifier then return nil end
    local basis, finish
    if foundation then
        basis, finish = P.preposition(document, start + 1, limit, nil, nil, "foundation")
        if not basis or basis.rule.id ~= "on-foundation" then return nil end
    elseif not english and (key == "біля" or key == "поруч") then
        basis, finish = P.preposition(document, start + 1, limit)
        if not basis or basis.rule.id ~= "near" then return nil end
    else
        local agent
        agent, finish = P.noun(document, start + (english and 2 or 1), limit, "instrumental", false, nil, true)
        if not agent then return nil end
        local group = agent.term and (agent.term.id == "game.guild" or agent.term.id == "game.party")
        local person = agent.pronoun and not agent.pronoun.inanimate and agent.pronoun.id ~= "it"
        if P.relativeAnimate(agent) or group or person then
            basis = {rule=agentRule, object=agent, case=agentRule.case}
        elseif english and (agent.article or agent.demonstrative or agent.possessor) then
            basis, finish = P.preposition(document, start + 1, limit)
        end
        if not basis then return nil end
    end
    if english and attributive then
        local terminal = P.key(document, limit + 1, #document.tokens)
        local through = terminal and terminal:match("^[.!?]$") and limit + 1 or limit
        local arcs, offset = nominalArcs(document, start, through)
        local arc = arcs and arcs[start - offset]
        if not arc or not noun.headIndex then return nil end
        local head = basis.object.members and basis.object.members[1] or basis.object
        local dependency = head.headIndex and arcs[head.headIndex - offset]
        local attached = arc.relation == "acl" and arc.head + offset == noun.headIndex
            and (foundation or dependency and dependency.head + offset == start
                and dependency.relation:match("^obl"))
        if not attached then
            local nominal = arcs[noun.headIndex - offset]
            attached = dependency and (arc.relation == "case" and arc.head + offset == head.headIndex
                and dependency.relation == "nmod" and dependency.head + offset == noun.headIndex
                or arc.relation == "root" and nominal.relation == "nsubj" and nominal.head + offset == start
                    and dependency.relation == "obl" and dependency.head + offset == start)
        end
        if not attached then return nil end
    end
    return {entry=modifier, qualifier=qualifier, complement=basis}, finish
end

local modeSymbols = {rp="RP", pvp="PvP", pve="PvE"}
local function modePrefix(document, index, limit)
    local label = modeSymbols[P.key(document, index, limit)]
    if not label then return nil end
    local after = index + 1
    if P.key(document, after, limit) == "/" then
        local second = modeSymbols[P.key(document, after + 1, limit)]
        if not second or second == label then return nil end
        label, after = label .. "/" .. second, after + 2
    elseif P.key(document, after, limit) == "-" and modeSymbols[P.key(document, after + 1, limit)] then
        local second = modeSymbols[P.key(document, after + 1, limit)]
        if second == label then return nil end
        label, after = label .. "-" .. second, after + 2
    end
    if P.key(document, after, limit) == "-" then after = after + 1 end
    return label, after
end

local function attachedCoordination(document, owner, limit, start, dependent, after, case, sense, adposition)
    local marker = P.key(document, after, limit)
    if marker ~= "," and marker ~= "&" and not L.functional(document, "connectors", after, limit) then return nil end
    local list, finish = P.coordinated(document, start, limit, case, nil, nil, true, sense, nil, true)
    if not list or not list.members then return nil end
    local english = document.direction == "en-uk"
    if english and P.key(document, finish, limit) == "of" then return nil end
    for _, member in ipairs(list.members) do
        if member.pronoun or (english and member.article and not dependent.article)
            or (not english and member.sourceCase ~= case) then return nil end
    end
    if not english then return list, finish end
    local ampersand
    for index = after, finish - 1 do
        if document.tokens[index].key == "&" then
            if ampersand then return nil end
            ampersand = index
        end
    end
    local arcs, offset = nominalArcs(document, owner, limit, ampersand)
    if not arcs or not dependent.headIndex then return nil end
    local head = dependent.headIndex - offset
    local attachment = arcs[adposition and owner - offset or head]
    local target = adposition and head or owner - offset
    local relation = adposition and "case" or "nmod"
    if not attachment or attachment.head ~= target or attachment.relation:match("^[^:]+") ~= relation then return nil end
    for index = 2, #list.members do
        local member = list.members[index]
        local arc = member.headIndex and arcs[member.headIndex - offset]
        if not arc or arc.relation ~= "conj" or arc.head ~= head then return nil end
    end
    return list, finish
end

local function contextualAdjective(document, modifier, head, case)
    local class = P.semanticClass(head)
    if not class then return nil end
    local requested
    if document.direction == "uk-en" then
        requested = {case=case, number=head.number or "singular"}
        if requested.number == "singular" then requested.gender = head.gender end
    end
    return L.choose(document, modifier.spelling or modifier.index, "adj", requested, "nounModifier", function(candidate)
        local frame = candidate.lexeme.frame
        return not frame.profileOnly and frame.headClasses and frame.headClasses[class]
    end)
end

local function nominalArgumentAt(document, first, limit, rule, english)
    local start = nominalMarkerEnd(document, first, limit, rule, english)
    if not start then return nil end
    local object, after
    if rule.activityTopics then object, after = activityTopics(document, start, limit, rule.case)
    else object, after = P.noun(document, start, limit, rule.case, rule.requiresSpatialTarget, nil, true, rule.argumentSense) end
    if not object then return nil end
    local class = P.semanticClass(object)
    if not class and object.raw and ns.Engine.Markup.isLink(object.raw, "item") then class = "equipment" end
    local frame = object.entry and object.entry.lexeme.frame
    local spatial = class == "places" or frame and (frame.spatialContainer or frame.spatialPart)
    if (not rule.classes or rule.classes[class]) and (not rule.argumentTrait or P.hasTrait(object, rule.argumentTrait))
        and (not rule.requiresPeople or P.personNoun(object))
        and (not rule.requiresPluralArgument or object.number == "plural") and (not rule.requiresSpatialTarget or spatial) then
        return {object=object, form=rule}, after
    end
end

local function markedNominalHead(document, first, limit, case, agrees, english, argumentStart)
    local arguments = {}
    local requested = not english and {case=case} or nil
    local entry = L.choose(document, first, "noun", requested, "nominalArgumentHead", function(candidate)
        if agrees and not agrees(lexicalNoun(candidate)) then return false end
        for _, rule in ipairs(candidate.lexeme.frame.nominalArguments or {}) do
            local marker = english and rule.en or rule.uk
            if marker and (marker ~= "" or rule.requiresPeople or rule.classes) then
                local argument, after = nominalArgumentAt(document, argumentStart or first + 1, limit, rule, english)
                if argument then arguments[candidate.id] = {argument=argument, after=after}; return true end
            end
        end
        return false
    end)
    if entry then
        local head, match = lexicalNoun(entry), arguments[entry.id]
        head.argument = match.argument
        return head, match.after
    end
end

local function controlLabelAt(document, first, limit)
    local opening = P.key(document, first, limit)
    local closing = opening == "«" and "»" or opening == "“" and "”" or opening == "„" and "“"
        or opening == '"' and '"'
    local labels, ending = L.functional(document, "menuLabels", first + (closing and 1 or 0), limit)
    if not labels or #labels ~= 1 then return nil end
    local label = ns.Linguistics.grammar.menuLabels[labels[1]]
    if not label.control then return nil end
    if closing then
        if P.key(document, ending + 1, limit) ~= closing then return nil end
        ending = ending + 1
    end
    return {controlLabel=label, person=3, number="singular", animacy="inanimate", headIndex=first}, ending + 1
end

function P.noun(document, first, limit, case, locationOnly, count, simple, sense, headFilter)
    local index = first
    local key = P.key(document, index, limit)
    local english = document.direction == "en-uk"
    if not (simple or locationOnly or sense) and first < limit and demonstratives[key] == "far" then
        local selection, after = P.pronoun(document, first, limit, case, true, nil, "qualifiedPeople")
        if selection then
            selection.animacy, selection.headIndex = "animate", first
            local qualifier, finish = ns.Engine.ClauseAnalysis.nominalQualification(document, selection, after, limit, case)
            if qualifier and (not headFilter or headFilter(selection)) then
                selection.nominalQualifier = qualifier
                return selection, finish
            end
        end
    end
    if sense == "uiControl" and not locationOnly then
        local control, after = controlLabelAt(document, first, limit)
        if control and (not headFilter or headFilter(control)) then return control, after end
    end
    if not (simple or locationOnly) and case ~= "nominative" and first < limit and document.tokens[first + 1].protected then
        local pronoun, after = P.pronoun(document, first, first, case, true)
        local reference = pronoun and pronoun.person == 3 and pronoun.number == "singular"
            and namedReference(document, first + 1, true)
        if reference and (not reference.gender or reference.gender == pronoun.gender) and (not headFilter or headFilter(pronoun)) then
            pronoun.referenceLabel, pronoun.headIndex = reference.raw, first
            return pronoun, after + 1
        end
    end
    if english and case == "locative" and not (sense or headFilter) then
        local number = P.key(document, index + 1, limit)
        if number and number:match("^%d%d?%d?$") then
            local language = L.choose(document, index, "adj", nil, "nounModifier", function(entry)
                return entry.lexeme.frame and entry.lexeme.frame.numberedChannelLanguage
            end)
            local channel = language and L.choose(document, "channel", "noun")
            if channel then
                return {entry=channel, number="singular", gender=channel.head.gender, person=3,
                    sourceCase=case, adjectives={{entry=language}}, channelNumber=number}, index + 2
            end
        end
    end
    if sense == "ownPeople" and not (locationOnly or headFilter) then
        local people, after = ownPeople(document, first, limit, case)
        if people then return people, after end
    end
    if key == "[" and not (locationOnly or headFilter) then
        local title, after = bracketedGoods(document, first, limit, case, simple)
        if title then return title, after end
        if case == "nominative" then return bracketedGuildSubject(document, first, limit) end
        return nil
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
    local whole = not english and wholeAgreement(key, case)
    local allAnimate = not english and case == "accusative" and (key == "усіх" or key == "всіх")
    local all = english and key == "all"
        or whole or allAnimate or not english and allForm and (key == allForm or key == "в" .. allForm:sub(3))
    if all then index = index + 1; key = P.key(document, index, limit) end
    local allOf = english and all and key == "of"
    if allOf then index = index + 1; key = P.key(document, index, limit) end
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
        sameForms = determinerForms(document, P.key(document, index, limit), "самий")
        if sameForms or not ns.ApertiumData and L.choose(document, index, "adj", {case=case}, "identityDeterminer") then
            sameAt, index = index, index + 1
        end
    end
    if not english and determiner then
        pointerForms = determinerForms(document, determiner, demonstrative == "far" and "той" or "цей")
    end
    local quantity = P.key(document, index, limit)
    local audience = sense == "audienceFacet"
    local levelThreshold, freeChoice
    if english then
        local any = quantity == "any"
        local thresholdAt = index + (any and 1 or 0)
        local digits = any and P.key(document, thresholdAt, limit) or quantity
        if digits and digits:match("^%d%d?%d?$") and P.key(document, thresholdAt + 1, limit) == "+"
            and levelAreaAt(document, thresholdAt + 2, limit) then
            levelThreshold, freeChoice, index = digits, any and "any" or nil, thresholdAt + 2
            quantity = P.key(document, index, limit)
        elseif any and audience then
            freeChoice, index, quantity = "any", thresholdAt, digits
        end
    elseif quantity == "будь" and P.key(document, index + 1, limit) == "-" then
        local form = P.key(document, index + 2, limit)
        if P.relativeMarkers["uk-en"][form] and (audience or levelAreaAt(document, index + 3, limit)) then
            freeChoice, index = form, index + 3
            quantity = P.key(document, index, limit)
        end
    end
    local characterLevel, skillRequirement, skillHeadSense
    if english and not locationOnly and (quantity == "level" or quantity == "lvl") then
        local level = P.levelNumberAt(document, index + 1, limit)
        if level then
            if curated(document, index + 2, limit, nil, false, assignedRole) then
                characterLevel = level
            else
                skillRequirement, skillHeadSense = P.skillRequirementPrefix(document, index, limit, case, sense)
            end
            if characterLevel or skillRequirement then
                index = index + 2
                quantity = P.key(document, index, limit)
            end
        end
    end
    local few = count ~= false and (english and (article == "indefinite" and quantity == "few"
            or not (article or demonstrative or owner) and quantity == "several")
        or not english and (quantity and quantity == fewForms[case] or case == "accusative" and quantity == "кількох"))
    local sufficient = count ~= false and not (article or demonstrative or owner) and
        quantity == (english and "enough" or "достатньо")
    local some = count ~= false and not (article or demonstrative or owner) and
        quantity == (english and "some" or "трохи")
    local quantifierStart = count ~= false and not (article or demonstrative or owner)
    local indefiniteForm = not english and quantifierStart and quantity and quantity:match("^(.+)сь$")
    if not agreeingRelative[indefiniteForm] then indefiniteForm = nil end
    local distributiveForms = not english and quantifierStart and quantity and quantity:sub(1, #"кож") == "кож"
        and determinerForms(document, quantity, "кожний")
    local distributive = quantifierStart and (english and (quantity == "every" or quantity == "each") and quantity
        or distributiveForms and "every")
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
    local measure, measureEnd, measureStart
    if english and not locationOnly then
        measureStart = index
        measure, measureEnd = P.nominalMeasureAt(document, index, limit, true)
    end
    if indefiniteForm or distributive then
        index, quantity = index + 1, nil
    elseif many or more or abundance then
        index, article, quantity = index + ((lot or lots or evenMore or degreeMore or abundance and english) and 2 or 1), nil, nil
        if not english then case = "genitive" end
    elseif few or sufficient or some then
        index, article, quantity = index + 1, nil, nil
        if not english and (sufficient or some or case == "nominative" or case == "accusative") then case = "genitive" end
    elseif another then
        additional, quantity, index = true, "1", index + 1
    elseif count ~= false and not measure and quantity and quantity:match("^%d+$") then
        local followsQuantity = english and P.key(document, index + 1, limit) == "more"
        additional, index = additional or followsQuantity, index + (followsQuantity and 2 or 1)
        if collective then case = "genitive" end
    else quantity = nil end
    if english and quantity and not (locationOnly or skillRequirement or characterLevel) then
        skillRequirement, skillHeadSense = P.skillRequirementPrefix(document, index, limit, case, sense)
        if skillRequirement then index = index + 2 end
    end
    local agrees = headFilter
    if english and (article == "indefinite" or quantity) then
        agrees = function(head)
            return not P.hasTrait(head, "uncountableOnly") and (not headFilter or headFilter(head))
        end
    elseif not english and (sameAt or pointerForms or owner or distributiveForms) then
        local counted = quantity and (tonumber(quantity) == 1 and "singular" or "plural")
        agrees = function(head)
            if headFilter and not headFilter(head) then return false end
            if owner and not possessiveReading(document, ownerIndex, case, head) then return false end
            local number = counted or head.number or "singular"
            local features = {case=case, number=number, gender=number ~= "plural" and head.gender or nil}
            if pointerForms and not determinerMatches(pointerForms, features, head.animacy) then return false end
            if distributiveForms and not determinerMatches(distributiveForms, features, head.animacy) then return false end
            if not sameAt then return true end
            if sameForms then return determinerMatches(sameForms, features, head.animacy) end
            return L.choose(document, sameAt, "adj", features, "identityDeterminer") ~= nil
        end
    end
    local nounSense = skillHeadSense or sense or (english and owner and "possessedNoun" or nil)
    local adjectives, best, nextIndex, headIndex, untranslatedHead, hasContextualAdjective = {}
    local bestMeasure
    local degree = P.key(document, index, limit)
    local intensity
    if degree == "very" or degree == "дуже" or degree == "more" or degree == "більш"
        or article == "definite" and degree == "most" then
        intensity = (degree == "more" or degree == "більш") and "more" or degree == "most" and "most" or "very"
        index = index + 1
    end
    -- Check the head after each adjective. The longest grammatical noun phrase
    -- wins, with a bounded number of modifiers.
    for _ = 0, 3 do
        if english and not locationOnly and not measure and index ~= measureStart then
            measureStart = index
            measure, measureEnd = P.nominalMeasureAt(document, index, limit, true)
        end
        if measureEnd then index, measureEnd = measureEnd, nil end
        local required = agrees
        if skillRequirement or measure or hasContextualAdjective or not english and #adjectives > 0 then
            required = function(head)
                if agrees and not agrees(head) then return false end
                if skillRequirement and not P.hasTrait(head, "skillThreshold") then return false end
                if measure and P.semanticClass(head) ~= measure.entry.lexeme.frame.measureHeadClass then return false end
                local number = head.number or "singular"
                local gender = number == "singular" and head.gender
                for _, modifier in ipairs(adjectives) do
                    if modifier.contextOnly then
                        if not contextualAdjective(document, modifier, head, case) then return false end
                    elseif not english and modifier.entry then
                        local matches
                        local readings = modifier.spelling and L.lookup(document, modifier.spelling) or L.at(document, modifier.index)
                        for _, reading in ipairs(readings) do
                            if reading.id == modifier.entry.id and reading.form.case == case
                                and (not reading.form.number or reading.form.number == number)
                                and (not gender or not reading.form.gender or reading.form.gender == gender) then
                                matches = true
                                break
                            end
                        end
                        if not matches then return false end
                    end
                end
                return true
            end
        end
        local contextual, adjectivalComplement
        local finalAdjective = adjectives[#adjectives]
        if not sense and finalAdjective and finalAdjective.entry and index <= limit then
            local requested = not english and {case=case} or nil
            adjectivalComplement = function(candidate)
                local allowed = candidate.lexeme.frame.modifyingAdjectives
                return allowed and allowed[finalAdjective.entry.lexeme.en]
            end
            contextual = L.choose(document, index, "noun", requested, "adjectivalComplement", function(candidate)
                return adjectivalComplement(candidate) and (not required or required(lexicalNoun(candidate)))
            end)
        end
        local head, after
        local compoundHead
        if contextual then head, after = lexicalNoun(contextual), index + 1
        else head, after = nounHead(document, index, limit, case, locationOnly, nounSense, required, adjectivalComplement) end
        if not (head or simple or locationOnly or nounSense) and index < limit
            and (not english or P.key(document, index + 1, limit) == "of") then
            head, after = markedNominalHead(document, index, limit, case, required, english)
        end
        if english and not (simple or locationOnly) then
            local absent, finish, anchor = nominalAbsence(document, index, limit, case, nounSense, required,
                article or demonstrative or owner)
            if absent and (not head or finish > after or finish == after and not head.term) then
                head, after, compoundHead = absent, finish, anchor
            end
        end
        if not locationOnly then
            local mode, modeEnd = modePrefix(document, index, limit)
            local audience, marker = head, after
            if mode then
                local group, finish = nounHead(document, modeEnd, limit, case, false, nounSense, required)
                audience, marker = group, finish
                local groupLemma = group and group.entry and group.entry.lexeme.en
                if group and (group.term and group.term.id == "game.guild" or groupNouns[groupLemma]) then
                    group.activityMode = mode
                    head, after, compoundHead = group, finish, modeEnd
                end
            end
            if not simple then
                if english then
                    if P.personNoun(audience) and not audience.pronoun then
                        if P.key(document, marker, limit) == "-" then marker = marker + 1 end
                        if P.key(document, marker, limit) == "only" then
                            local group, finish = nounHead(document, marker + 1, limit, case, false, nounSense, required)
                            if P.hasTrait(group, "membershipGroup") then
                                group.activityMode, group.membershipAudience = mode, audience
                                head, after, compoundHead = group, finish, marker + 1
                            end
                        end
                    end
                elseif P.hasTrait(head, "membershipGroup") and P.key(document, after, limit) == "лише"
                    and P.key(document, after + 1, limit) == "для" then
                    local audience, finish = nounHead(document, after + 2, limit, "genitive", false, nil,
                        function(candidate) return not candidate.pronoun and P.personNoun(candidate) end)
                    if audience then head.membershipAudience, after = audience, finish end
                end
            end
        end
        if english and not simple and not locationOnly then
            local audience, ending, anchor = audienceWithTopics(document, index, limit, head, required)
            if audience then head, after, compoundHead = audience, ending, anchor end
        end
        if english and not simple then
            local prefix, following = head, after
            local definitePlace = P.key(document, index, limit) == "the"
            if definitePlace then
                local place = curated(document, index + 1, limit, nil, true)
                if place then prefix, following = curatedNoun(place), place.last + 1 end
            end
            local frame = prefix and prefix.entry and prefix.entry.lexeme.frame
            local place = prefix and prefix.term and prefix.term.category == "places"
            local prefixClass = P.semanticClass(prefix)
            local compoundClasses = ns.Linguistics.grammar.nominalCompoundClasses
            local nominalPrefix = compoundClasses and compoundClasses[prefixClass]
            if following and following <= limit and (place or nominalPrefix or frame and frame.spatialContainer) then
                local part, ending = nounHead(document, following, limit, case, locationOnly)
                local relation = part and part.entry and part.entry.lexeme.frame
                local prefixArgument = nominalPrefix and nominalCompoundArgument(part, prefix)
                if nominalPrefix and not prefixArgument then
                    local function governedHead(noun) return nominalCompoundArgument(noun, prefix) ~= nil end
                    local contextual, finish = nounHead(document, following, limit, case, locationOnly,
                        "nominalArgumentHead", governedHead)
                    if contextual then
                        part, ending, prefixArgument = contextual, finish, nominalCompoundArgument(contextual, prefix)
                    end
                end
                local session, sessionEnd
                if place and not locationOnly then
                    session, sessionEnd = nounHead(document, following, limit, case, false, "iteration")
                    local sessionFrame = session and session.entry and session.entry.lexeme.frame
                    local requiredTrait = sessionFrame and sessionFrame.placeCompoundTrait
                    if not session or requiredTrait and not P.hasTrait(prefix, requiredTrait) then
                        session, sessionEnd = nounHead(document, following, limit, case, false, "locationGroup")
                    end
                elseif nominalPrefix and not locationOnly and P.hasTrait(prefix, "clearableInstance") then
                    local iteration, finish = nounHead(document, following, limit, case, false, "iteration")
                    local argument = nominalCompoundArgument(iteration, prefix)
                    if argument then part, ending, prefixArgument = iteration, finish, argument end
                end
                if prefixArgument and (article ~= "indefinite" or part.number ~= "plural") then
                    part.argument = {object=prefix, form=prefixArgument, compound=true}
                    head, after, compoundHead = part, ending, following
                elseif session and session.entry and session.entry.lexeme.frame and session.entry.lexeme.frame.placeCompound then
                    session.genitive = prefix
                    head, after = session, sessionEnd
                    if session.entry.lexeme.frame.placeCompoundTitle then compoundHead = sessionEnd - 1 end
                elseif #adjectives == 0 and (not definitePlace or owner) and relation and relation.spatialPart then
                    if relation.pathTo then part.pathTo = prefix
                    else part.genitive = prefix end
                    head, after = part, ending
                elseif #adjectives == 0 and (not definitePlace or owner) and part and place and assignedRole(part) then
                    part.destination = prefix
                    head, after = part, ending
                end
            end
            if not nominalPrefix and not compoundHead and compoundClasses then
                local contextual, ending, anchor = contextualNominalCompound(document, index, limit, case,
                    locationOnly, compoundClasses)
                if contextual then head, after, compoundHead = contextual, ending, anchor end
            end
            for _ = 1, 2 do
                if not (compoundHead and head.argument and head.argument.compound and after <= limit
                    and compoundClasses and compoundClasses[P.semanticClass(head)]) then break end
                local outer, ending = nounHead(document, after, limit, case, locationOnly)
                local argument = nominalCompoundArgument(outer, head)
                if not argument or (article == "indefinite" and outer.number == "plural") then break end
                outer.argument = {object=head, form=argument, compound=true}
                head, after, compoundHead = outer, ending, after
            end
        end
        if head and (not untranslatedHead or untranslatedHead == index and after == index + 1)
            and (not headFilter or headFilter(head)) and (not demonstrativeNumber or head.number == demonstrativeNumber
            or demonstrativeNumber == "plural" and head.number == "singular" and P.mass(head))
            and (not few or head.number == "plural")
            and (not head.pronoun or index == first) and (not intensity or #adjectives > 0)
            and (not best or after > nextIndex or (after == nextIndex and head.term and not best.term)) then
            best, nextIndex, headIndex = head, after, compoundHead or index
            bestMeasure = measure
            if #adjectives > 0 then best.adjectives = {unpack(adjectives)} end
            best.untranslatedHead = untranslatedHead
        end
        if index > limit then break end
        local comma = #adjectives > 0 and P.key(document, index, limit) == ","
        if comma then index = index + 1 end
        local join
        if #adjectives > 0 then
            local rows, last = L.functional(document, "connectors", index, limit)
            local connector = rows and ns.Linguistics.grammar.connectors[rows[1]]
            if connector and (connector.id == "and" or connector.id == "or" or connector.id == "but") then
                join, index = connector, last + 1
            end
        end
        local qualifier, following = participialQualifier(document, index, limit)
        if following then index = following end
        local phrase, ending = L.phraseAt(document, index, limit, "adj")
        local function modifierAllowed(candidate)
            local frame = candidate.lexeme.frame
            if frame and frame.profileOnly or qualifier and not (frame and frame.participialState) then return false end
            return document.direction == "en-uk" or candidate.form.case == case
        end
        local function readModifier(key)
            local adjective = L.choose(document, key, "adj", nil, nil, modifierAllowed)
            if adjective then return adjective end
            local readings = type(key) == "string" and L.lookup(document, key) or L.at(document, key)
            for _, reading in ipairs(readings) do
                local frame = reading.lexeme.frame
                if reading.lexeme.pos == "adj" and frame and frame.headClasses and frame.sense == "nounModifier"
                    and modifierAllowed(reading) then return nil, true end
            end
        end
        local adjective, contextOnly
        if phrase then adjective, contextOnly = readModifier(phrase) end
        if not (adjective or contextOnly) then
            phrase, ending = nil, index + 1
            adjective, contextOnly = readModifier(index)
        end
        local targetHead = not qualifier and not (adjective or contextOnly)
            and document.untranslatedModifiers and document.untranslatedModifiers[index]
        if not (adjective or contextOnly or targetHead) then break end
        if targetHead and untranslatedHead and targetHead ~= untranslatedHead then break end
        untranslatedHead = untranslatedHead or targetHead
        hasContextualAdjective = hasContextualAdjective or contextOnly
        adjectives[#adjectives + 1] = {entry=adjective, rawModifier=targetHead and P.raw(document, index, index),
            index=index, spelling=phrase, comma=comma, join=join, contextOnly=contextOnly, qualifier=qualifier,
            intensity=#adjectives == 0 and intensity or nil}
        index = ending
    end
    if not best then
        if (more or some) and english then
            return P.noun(document, first, limit, case, locationOnly, false, simple, sense, headFilter)
        end
        if (demonstrative or all) and not locationOnly and not headFilter then return P.pronoun(document, first, limit, case) end
        if owner then return nounHead(document, first, limit, case, locationOnly, nil, headFilter) end
        return nil
    end
    if case ~= "nominative" and best.pronoun and best.pronoun.postpositiveAdjective and nextIndex <= limit then
        local features
        if not english then
            local agreementCase = case == "accusative" and not best.pronoun.inanimate and "genitive" or case
            features = {case=agreementCase, gender=best.gender, number=best.number}
        end
        local phrase, ending = L.phraseAt(document, nextIndex, limit, "adj")
        local entry = phrase and L.choose(document, phrase, "adj", features)
        if not entry then
            entry, ending = L.choose(document, nextIndex, "adj", features), nextIndex + 1
        end
        if entry and not (entry.lexeme.frame and entry.lexeme.frame.profileOnly) then
            best.postpositive = {entry=entry}
            best.animacy = best.pronoun.inanimate and "inanimate" or "animate"
            nextIndex = ending
        end
    end
    if countOnly and best.number ~= "plural" or massOnly and not P.mass(best) then return nil end
    if more and english and (not P.mass(best) and best.number ~= "plural"
        or best.adjectives and not (degreeMore or best.untranslatedHead)) then
        return P.noun(document, first, limit, case, locationOnly, false, simple, sense, headFilter)
    end
    if some and english then
        if best.number == "plural" then few, some = true, nil
        elseif not P.mass(best) then
            indefiniteForm, some = true, nil
        end
    end
    if indefiniteForm and (best.pronoun or not english and indefiniteForm ~= P.relativePronoun(best, case)) then return nil end
    if oneSurface and P.one(best.gender, case, best.animacy) ~= oneSurface then return nil end
    if all and (best.pronoun or best.number ~= "plural" and not (whole
        or english and (P.mass(best) or article == "definite" or best.term and best.term.features
            and best.term.features.proper))) then return nil end
    if sameAt then
        if best.pronoun or best.raw then return nil end
        best.same, demonstrative = true, "far"
    end
    if whole and (best.number == "plural" or not whole[best.gender]) then return nil end
    if allAnimate and best.animacy ~= "animate" then return nil end
    if distributive and (best.pronoun or best.raw or best.number ~= "singular") then return nil end
    best.all, best.allOf = all and true or nil, allOf or nil
    best.distributive = distributive or nil
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
    if skillRequirement and not P.hasTrait(best, "skillThreshold") then return nil end
    best.article, best.quantity, best.demonstrative = article, quantity, demonstrative
    best.characterLevel = characterLevel
    best.emphatic, best.few = emphatic, few or nil
    best.sufficient, best.additional, best.many = sufficient or nil, additional or nil, many or nil
    best.abundance = abundance or nil
    best.more, best.evenMore, best.degreeMore = more or nil, evenMore or nil, degreeMore or nil
    best.some = some or nil
    best.indefiniteChoice = indefiniteForm and true or nil
    local frame = best.entry and best.entry.lexeme.frame
    if best.argument and best.argument.form.englishCompound and en then
        best.headIndex = headIndex
    elseif frame and frame.dependencyHead then
        best.headIndex = headIndex + frame.dependencyHead - 1
    elseif nextIndex == headIndex + 1 and (best.entry or best.term) then best.headIndex = headIndex end
    if frame and frame.semanticClass == "levelArea" then
        if not en and P.key(document, nextIndex, limit) == "від" then
            local level, after = P.noun(document, nextIndex + 1, limit, "genitive", false, false, true)
            local levelFrame = level and level.entry and level.entry.lexeme.frame
            if levelFrame and levelFrame.postposedNumber and level.ordinal then
                levelThreshold, nextIndex = level.ordinal, after
            end
        end
        best.levelThreshold = levelThreshold
    elseif levelThreshold then return nil end
    if freeChoice then
        if not (frame and frame.semanticClass == "levelArea"
                or audience and P.hasTrait(best, "audienceFacet") and best.number == "singular")
            or not en and freeChoice ~= P.relativePronoun(best, case) then return nil end
        best.freeChoice = true
    end
    if ordinal then
        if not frame or not frame.postposedNumber then return nil end
        best.ordinal = ordinal
    end
    if en and frame and frame.postposedNumber then
        local numberAfter = P.key(document, nextIndex, limit)
        if numberAfter and numberAfter:match("^%d+$") then best.ordinal, nextIndex = numberAfter, nextIndex + 1 end
    end
    if frame and frame.numberedChannel and not best.quantity then
        local channelNumber = P.key(document, nextIndex, limit)
        if channelNumber and channelNumber:match("^%d%d?%d?$") then
            best.channelNumber, nextIndex = channelNumber, nextIndex + 1
        end
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
        local nominalHead
        if not (frame and frame.nominalArguments) then
            nominalHead = L.choose(document, headIndex, "noun", not en and {case=case} or nil, "nominalArgumentHead")
            if not nominalHead and en and marker == "of" then
                nominalHead = L.choose(document, headIndex, "noun", nil, "iteration")
            end
        end
        local valency = nominalHead and nominalHead.lexeme.frame or frame
        for _, governed in ipairs(valency and valency.nominalArguments or {}) do
            if best.argument then break end
            local argument, after = nominalArgumentAt(document, nextIndex, limit, governed, en)
            if argument then
                local sense = en and governed.sense or not en and governed.reverseSense
                local reading = sense and L.choose(document, headIndex, "noun", nil, sense) or nominalHead
                if reading then
                    best.entry, best.term = reading, nil
                    best.gender, best.animacy = reading.head.gender, reading.head.animacy
                    frame = reading.lexeme.frame
                end
                local object = argument.object
                if not en and governed.uk == "" and not best.quantity and governed.compoundNumber
                    and governed.compoundNumber.uk == "head" and not (object.term and object.term.category == "places") then
                    best.number = object.number
                end
                best.argument, nextIndex = argument, after
                break
            end
        end
        if not en and not best.argument then
            local scoped, after = markedNominalHead(document, headIndex, limit, case, nil, false, nextIndex)
            if scoped then
                best.entry, best.term = scoped.entry, nil
                best.gender, best.animacy = scoped.gender, scoped.animacy
                best.argument, nextIndex, frame = scoped.argument, after, scoped.entry.lexeme.frame
            end
        end
        if not best.argument and frame and frame.pathTo and marker == (en and "to" or "до") then
            local goal, after = P.noun(document, nextIndex + 1, limit, "genitive", false, false, true)
            if goal then best.pathTo, nextIndex = goal, after end
        end
        local lemma = best.entry and best.entry.lexeme.en or best.term and best.term.en
        if lemma and (groupNouns[ns.Engine.Normalize.word(lemma)] or assignedRole(best)) then
            local destination, after = groupDestination(document, nextIndex, limit)
            if destination then best.destination, nextIndex = destination, after end
        end
        if not best.destination and not best.pathTo and not best.argument and not best.genitive and (not en or marker == "of") then
            local contextual = en and L.choose(document, headIndex, "noun", nil, "genitiveComplement")
            local context = contextual and contextual.lexeme.frame or frame
            local dependentStart = nextIndex + (en and 1 or 0)
            local dependent, after = P.noun(document, dependentStart, limit,
                "genitive", false, false, true, context and context.complementSense)
            if dependent and not dependent.pronoun and (en or dependent.sourceCase == "genitive") then
                local dependentFrame = dependent.entry and dependent.entry.lexeme.frame
                if not best.characterLevel and assignedRole(best) and dependent.ordinal
                    and dependentFrame and dependentFrame.postposedNumber then
                    best.characterLevel = dependent.ordinal
                else
                    local list, finish = attachedCoordination(document, headIndex, limit, dependentStart,
                        dependent, after, "genitive", context and context.complementSense)
                    best.genitive, after = list or dependent, finish or after
                end
                nextIndex = after
                if contextual and context.complementClasses and context.complementClasses[P.semanticClass(dependent)] then
                    best.entry, best.term = contextual, nil
                    best.gender, best.animacy = contextual.head.gender, contextual.head.animacy
                end
            end
        end
        if frame and frame.nominalInclusion then
            local included, after = nominalInclusion(document, nextIndex, limit, en)
            if included then best.inclusion, nextIndex = included, after end
        end
    end
    for _, modifier in ipairs(best.adjectives or {}) do
        local reading = not modifier.rawModifier and contextualAdjective(document, modifier, best, case)
        if reading then modifier.entry = reading
        elseif modifier.contextOnly then return nil end
    end
    if not locationOnly and not bestMeasure and P.key(document, nextIndex, limit) == (en and "with" or "на") then
        local suffix, after = P.nominalMeasureAt(document, nextIndex + 1, limit)
        if suffix and P.semanticClass(best) == suffix.entry.lexeme.frame.measureHeadClass then
            bestMeasure, nextIndex = suffix, after
        end
    end
    best.nominalMeasure = bestMeasure
    if not skillRequirement and P.hasTrait(best, "skillThreshold") then
        local amount, after = P.skillRequirementAt(document, nextIndex, limit, en)
        if amount then skillRequirement, nextIndex = amount, after end
    end
    best.skillRequirement = skillRequirement
    if not simple and best.headIndex and nextIndex < limit then
        local state, finish = P.groundedState(document, best, nextIndex, limit, case, true)
        if state then best.groundedState, nextIndex = state, finish end
        if not state and not locationOnly then
            local qualifier, ending = ns.Engine.ClauseAnalysis.nominalQualification(document, best, nextIndex, limit, case)
            if qualifier then best.nominalQualifier, nextIndex = qualifier, ending end
        end
    end
    if not simple and best.headIndex and not best.raw then
        while nextIndex < limit do
            local phrase, after = nominalAdpositions(document, best, nextIndex, limit)
            if not phrase then break end
            best.prepositions = best.prepositions or {}
            best.prepositions[#best.prepositions + 1], nextIndex = phrase, after
        end
    end
    if not simple and best.raw and nextIndex <= limit and document.tokens[headIndex].linkKind == "item" then
        local id = ns.Engine.Markup.itemId(best.raw)
        local classes = ns.Data.itemTitleClasses
        return describeTitle(document, best, nextIndex, limit, case, classes and classes[id])
    end
    if document.relativeBudget and not simple and not best.raw
        and (not best.pronoun or best.pronoun.id == "someone") and nextIndex <= limit then
        local dependent = best.genitive
        local antecedent = dependent and dependent.members and dependent or best
        local relative, finish = ns.Engine.ClauseAnalysis.relative(document, antecedent, nextIndex, limit)
        if not relative and antecedent ~= best then
            antecedent = best
            relative, finish = ns.Engine.ClauseAnalysis.relative(document, best, nextIndex, limit)
        end
        if relative then antecedent.relative, nextIndex = relative, finish end
    end
    return best, nextIndex
end

local function directionalTarget(noun)
    return P.spatialContainer(noun) or P.hasTrait(noun, "spatialMedium")
end

local function predicateOwner(noun)
    local pronoun = noun and noun.pronoun
    return noun and not noun.quantity and (P.relativeAnimate(noun) or P.hasTrait(noun, "membershipGroup")
        or pronoun and not (pronoun.inanimate or pronoun.id == "it")
        or noun.raw and ns.Engine.Markup.isLink(noun.raw, "player"))
end

local function possessivePredicateObject(document, first, limit, rule, english)
    local object, ending = P.noun(document, first, limit, rule.case, false, nil, not english)
    if english then
        if not predicateOwner(object) then return end
        local entry = L.choose(document, rule.possessiveHead, "noun")
        if not entry then return end
        local head = lexicalNoun(entry)
        local possessor = object.pronoun and object.pronoun.en.possessive
        head.possessor = possessor and L.choose(document, possessor, "pron", nil, nil, possessive)
        if not head.possessor then head.genitive = object end
        return object, ending, head
    end
    if not object or not object.entry or object.entry.lexeme.en ~= rule.possessiveHead
        or object.quantity or object.adjectives or object.demonstrative then return end
    if object.possessor then
        local owner = object.possessor.lexeme.en
        for _, pronoun in ipairs(ns.Linguistics.grammar.pronouns) do
            if pronoun.en.possessive == owner then
                return {pronoun=pronoun, person=pronoun.person, number=pronoun.number, gender=pronoun.gender}, ending
            end
        end
    else
        local actor, after = P.noun(document, ending, limit, "genitive")
        if predicateOwner(actor) then return actor, after end
    end
end

local function namedChannel(document, first, limit)
    local english = document.direction == "en-uk"
    local index = first
    local channel
    if not english then
        if P.key(document, first + 1, limit) ~= "«" then return nil end
        channel = L.choose(document, first, "noun", {case="locative", number="singular"}, nil, function(candidate)
            return candidate.lexeme.frame and candidate.lexeme.frame.numberedChannel
        end)
        if not channel then return nil end
        index = first + 2
    end
    local dash = P.key(document, index + 1, limit)
    if dash ~= "-" and dash ~= "–" and dash ~= "—" then return nil end
    local name = L.choose(document, index, "noun", nil, "chatChannelLabel")
    local language = name and L.choose(document, index + 2, "noun", nil, nil, function(candidate)
        return candidate.lexeme.frame and candidate.lexeme.frame.semanticClass == "language"
    end)
    local after = index + 3
    if not language or not english and P.key(document, after, limit) ~= "»" then return nil end
    channel = channel or L.choose(document, "channel", "noun")
    if channel then
        local node = lexicalNoun(channel)
        node.channelName, node.channelLanguage, node.headIndex = name, language, first
        return node, after + (english and 0 or 1)
    end
end

function P.preposition(document, first, limit, motion, displacement, context, secondaryContext, requiredTrait)
    local english = document.direction == "en-uk"
    if english and P.key(document, first, limit) == "of" then return nil end
    local choices, last = L.functional(document, "prepositions", first, limit)
    if not choices or last > limit then return nil end
    local selected, after, priority, ambiguous
    for _, id in ipairs(choices) do
        local rule = ns.Linguistics.grammar.prepositions[id]
        local case = english and displacement and rule.id == "in" and "accusative" or rule.case
        local container = rule.directional and directionalTarget or P.spatialContainer
        local object, ending, possessiveObject
        if (not requiredTrait or rule[requiredTrait]) and (not rule.requiresMotion or motion) and (not rule.excludesMotion or not motion)
            and (not rule.directional or english or motion or displacement)
            and (not rule.context or rule.context == context or rule.context == secondaryContext)
            and (not rule.contexts or rule.contexts[context] or rule.contexts[secondaryContext]) then
            local spatial = rule.requiresSpatialContainer or displacement and rule.id == "in"
            local locationOnly = rule.requiresSpatialContainer
                or not displacement and (rule.id == "in" or rule.id == "to" or rule.id == "from")
            local sense = (not rule.bareContextAlias or P.key(document, last + 1, limit) == rule.bareContextAlias)
                and rule.objectSense or nil
            if rule.possessiveHead then
                object, ending, possessiveObject = possessivePredicateObject(document, last + 1, limit, rule, english)
            elseif rule.enumeratedObject then
                object, ending = P.coordinated(document, last + 1, limit, case, nil, nil, true, sense, nil,
                    not rule.objectNominalArguments)
            else
                if rule.id == "in-chat" then
                    object, ending = namedChannel(document, last + 1, limit)
                end
                if not object then
                    object, ending = P.noun(document, last + 1, limit, case, locationOnly, nil, nil,
                        sense, spatial and container)
                end
            end
            if not object and spatial and not rule.requiresSpatialContainer then
                object, ending = P.noun(document, last + 1, limit, case, locationOnly, nil, nil, sense)
            end
            if not object and context == "roomCapacity" and rule.id == "for" then
                object, ending = P.pronoun(document, last + 1, limit, case, true, true)
            end
        end
        if object and rule.id == "in-chat" and object.channelNumber then object = nil end
        if object and not english and rule.inclusive then
            if P.key(document, ending, limit) == rule.inclusive then ending = ending + 1
            else object = nil end
        end
        local frame = object and object.entry and object.entry.lexeme.frame
        local class = P.semanticClass(object)
        local person = rule.requiresPerson and P.personNoun(object)
        local reference = object and object.pronoun and object.pronoun.id
        if object and (not rule.requiresCategory or (object.term and object.term.category == rule.requiresCategory))
            and (not rule.requiresPerson or person)
            and (not rule.deicticReference or reference == "it" or reference == "this" or reference == "that")
            and (not rule.requiresClass or class == rule.requiresClass)
            and (not rule.requiresClasses or rule.requiresClasses[class])
            and (not rule.requiresTrait or P.hasTrait(object, rule.requiresTrait))
            and (not rule.requiresResource or P.isResource(object))
            and (not rule.requiresSpatialContainer or container(object))
            and (not rule.requiresLexicalLocative or (frame and frame.locativePreposition == rule.targetUk))
            and (not rule.requiresNearLandmark or (frame and frame.atNearLandmark)) then
            local rank = (person or rule.requiresLexicalLocative or rule.requiresNearLandmark or rule.requiresCategory
                or rule.requiresClass or rule.requiresClasses or rule.requiresTrait or rule.requiresResource
                or rule.requiresSpatialContainer or rule.possessiveHead) and 1 or 0
            if rule.context or rule.contexts then rank = rank + 2 end
            if not priority or rank > priority then
                selected, after, priority, ambiguous = {rule=rule, object=object, case=case,
                    possessiveObject=possessiveObject}, ending, rank, false
            elseif rank == priority then ambiguous = true end
        end
    end
    if ambiguous or not selected then return nil end
    if selected.rule.authorityOpening and P.hasTrait(selected.object, "proper")
        and P.key(document, after, limit) == "," then
        local title, finish = P.noun(document, after + 1, limit, selected.case, false, nil, true)
        if P.hasTrait(title, "appositiveTitle") and (finish > limit or P.key(document, finish, limit) == ",") then
            selected.apposition, after = title, finish
        end
    end
    if priority == 0 and not selected.rule.targetEnByClass and not selected.rule.objectSense then
        local group, finish = attachedCoordination(document, first, limit, last + 1, selected.object,
            after, selected.case, nil, true)
        if group then selected.object, after = group, finish end
    end
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

function P.durationSpan(document, index, limit, allowBare)
    local english = document.direction == "en-uk"
    local key = P.key(document, index, limit)
    local ongoing = not english and (key == "вже" or key == "уже")
    local marked = english and key == "for" or ongoing
    if not key or not (marked or allowBare) then return end
    local start = index + (marked and 1 or 0)
    if marked then
        local choices, last = L.functional(document, "adverbs", english and index or start, limit)
        for _, id in ipairs(choices or {}) do
            local expression = ns.Linguistics.grammar.adverbs[id]
            if expression.durationSpan then return {expression=expression, ongoing=ongoing}, last + 1 end
        end
    end
    if english and marked then
        local phrase, after = P.preposition(document, index, limit, nil, nil, nil, nil, "elapsedSpan")
        if phrase then return {noun=phrase.object}, after end
    elseif not english and (marked or timeUnits[key] or singularTimeForms[key]) then
        local noun, after = P.noun(document, start, limit, "accusative", false, nil, true, nil,
            function(candidate) return P.hasTrait(candidate, "durationUnit") end)
        if noun then return {noun=noun, ongoing=ongoing}, after end
    end
    local quantity, after = P.quantity(document, start, limit)
    if not quantity or P.key(document, after, limit) == "of" then return nil end
    if english and after <= limit then
        local nominalStart = start + (quantity.approximate and 1 or 0)
        local _, nominalEnd = P.noun(document, nominalStart, limit, "accusative", false, nil, true)
        if nominalEnd and nominalEnd > after then return nil end
    end
    return {quantity=quantity, ongoing=ongoing}, after
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

local function listExtension(document, first, limit)
    local rows, last = L.functional(document, "adverbs", first, limit)
    if not rows then return nil end
    local size = #document.tokens
    local nextKey = P.key(document, last + 1, size)
    if nextKey and not nextKey:match("^[,;.!?]$") and not L.functional(document, "connectors", last + 1, size) then
        return nil
    end
    for _, id in ipairs(rows) do
        local expression = ns.Linguistics.grammar.adverbs[id]
        if expression.listExtension then return expression, last + 1 end
    end
end

function P.coordinated(document, first, limit, case, startsPredicate, locationOnly, enumeration, sense, headFilter, simple)
    local head, index = P.noun(document, first, limit, case, locationOnly, nil, simple, sense, headFilter)
    if not head then return nil end
    local members, joins = {head}, {}
    local arcs, extension
    for _ = 2, enumeration and 6 or 4 do
        local comma = enumeration and P.key(document, index, limit) == ","
        local start = index + (comma and 1 or 0)
        local rest, finish = listExtension(document, start, limit)
        if rest then
            extension, index = rest, finish
            break
        end
        local choices, last = L.functional(document, "connectors", start, limit)
        local connector = choices and ns.Linguistics.grammar.connectors[choices[1]]
        local shorthand = P.key(document, start, limit)
        if enumeration and (shorthand == "&" or enumeration == "audience" and shorthand == "n"
            and document.direction == "en-uk") then connector, last = listingAnd, start
        elseif comma and not connector then connector, last = listingComma, index end
        local member, after
        if not connector and enumeration == "implicit" and index < limit and limit - first < 32
            and ns.UDPipeModels and not document.tokens[index].protected then
            local previous = members[#members]
            if previous.headIndex and (previous.adjectives or previous.article) then
                member, after = P.noun(document, start, limit, case, locationOnly, nil, simple, sense, headFilter)
                if member and member.headIndex and (member.adjectives or member.article) then
                    if arcs == nil then arcs = ns.Engine.UDPipe.analyzeDocument(document, first, limit) or false end
                    local arc = arcs and arcs[member.headIndex - first + 1]
                    if arc and (arc.relation == "conj" or arc.relation == "appos")
                        and (arc.head + first - 1 == previous.headIndex or arc.head + first - 1 == head.headIndex) then
                        connector, last = listingComma, start - 1
                    end
                end
            end
        end
        if not connector or (connector.id ~= "and" and connector.id ~= "or") then break end
        if not member then member, after = P.noun(document, last + 1, limit, case, locationOnly, nil, simple, sense, headFilter) end
        if not member or (startsPredicate and startsPredicate(last + 1)) then break end
        members[#members + 1] = member
        joins[#joins + 1] = connector
        index = after
    end
    if #members == 1 then
        head.listExtension = extension
        return head, index
    end
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
    return {members=members, joins=joins, person=person, number=number, headIndex=head.headIndex,
        listExtension=extension}, index
end

local function player(noun)
    return noun.term and noun.term.id == "role.player" or noun.entry and noun.entry.lexeme.en == "player"
end

local function welcomePredicate(document, first, limit, features, negation)
    local negative = P.key(document, first, limit) == negation
    local at = first + (negative and 1 or 0)
    if at <= limit and L.choose(document, at, "adj", features, "welcomingState") then return at + 1, negative end
end

function P.welcomeAudience(document, first, limit)
    local english = document.direction == "en-uk"
    local index = first
    local agreement = not english and {case="nominative", number="plural"} or nil
    local recipient, opening, negative
    if english then
        if not welcomePredicate(document, limit, limit, nil, "not") then return nil end
        local key = P.key(document, index, limit)
        if key ~= "all" and key ~= "any" then
            local after
            recipient, after = P.noun(document, index, limit, "nominative", nil, nil, true)
            if not recipient or not P.relativeAnimate(recipient) or P.key(document, after, limit) ~= "of" then return nil end
            index = after + 1
        end
    else
        opening, negative = welcomePredicate(document, index, limit, agreement, "не")
        if not opening and not welcomePredicate(document, limit, limit, agreement, "не") then return nil end
        recipient, index = P.noun(document, opening or index, limit, "dative", nil, nil, true)
        if not recipient or not P.relativeAnimate(recipient) then return nil end
    end
    local groups, after = P.coordinated(document, index, limit, english and "nominative" or "genitive",
        nil, nil, "audience", "audienceFacet", function(noun) return P.hasTrait(noun, "audienceFacet") end)
    if not groups then return nil end
    local firstGroup = groups.members and groups.members[1] or groups
    if not (firstGroup.all or firstGroup.freeChoice) then return nil end
    for _, member in ipairs(groups.members or {}) do
        if member.number ~= firstGroup.number or (member.all and not firstGroup.all)
            or (member.freeChoice and not firstGroup.freeChoice) then return nil end
        if english and firstGroup.freeChoice and member.gender ~= firstGroup.gender then member.freeChoice = true end
    end
    if not opening then
        local at = after
        if english then
            local subject = recipient or groups
            local be = subject.number == "plural" and "are" or "is"
            if P.key(document, at, limit) == be then at = at + 1 end
        end
        after, negative = welcomePredicate(document, at, limit, agreement, english and "not" or "не")
        if not after then return nil end
    end
    if not english and firstGroup.all and recipient.number == "plural" and player(recipient)
        and not (recipient.adjectives or recipient.possessor or recipient.demonstrative) then recipient = nil end
    return {groups=groups, recipient=recipient, freeChoice=firstGroup.freeChoice, negative=negative}, after
end

function P.amount(document, first, limit, case, sense)
    local english = document.direction == "en-uk"
    local index = first
    local entries, markerEnd = L.functional(document, "adverbs", index, limit)
    local approximate
    if entries then
        for _, entry in ipairs(entries) do
            if ns.Linguistics.grammar.adverbs[entry].context == "quantity" then
                approximate, index = true, markerEnd + 1
                break
            end
        end
    end
    local from = P.key(document, index, limit) == (english and "from" or "від")
    if from then index = index + 1 end
    local lower = P.key(document, index, limit)
    if not (lower and lower:match("^%d+$")) then return nil end
    local separator = P.key(document, index + 1, limit)
    local to = english and "to" or "до"
    local range = separator == to or not from and (separator == "-" or separator == "–" or separator == "—")
    if from and not range then return nil end
    local upper
    if range then
        upper = P.key(document, index + 2, limit)
        if not (upper and upper:match("^%d+$")) then return nil end
        local lowDigits, highDigits = lower:gsub("^0+", ""), upper:gsub("^0+", "")
        if #highDigits < #lowDigits or #highDigits == #lowDigits and highDigits < lowDigits then return nil end
        index = index + 2
    end
    local amount = {lower=lower, upper=upper, approximate=approximate}
    local noun, after
    if english then
        noun, after = P.noun(document, index, limit, case, nil, nil, true, sense)
    else
        local government = separator == to and "genitive" or case
        local amountSense = sense or "quantifiedObject"
        local countedCase, countedNumber = P.countedCase(upper or lower, government, false)
        noun, after = P.noun(document, index, limit, countedCase, nil, nil, true, amountSense,
            function(node) return node.raw or node.number == countedNumber end)
        local animateCase, animateNumber = P.countedCase(upper or lower, government, true)
        if animateCase ~= countedCase then
            local animate, finish = P.noun(document, index, limit, animateCase, nil, nil, true, amountSense,
                function(node) return node.animacy == "animate" and node.number == animateNumber end)
            if animate and (not noun or finish > after) then noun, after = animate, finish end
        end
    end
    if noun and (noun.quantity or noun.raw) then
        if english and not (approximate or range) then return nil end
        noun.amount, noun.quantity = amount, noun.quantity or upper or lower
        return noun, after
    end
    if not (approximate or range) and separator
        and not (separator:match("^[,.;!?]$") or separator == (english and "for" or "за")) then return nil end
    return {amount=amount, person=3, number="plural"}, index + 1
end

function P.quantity(document, first, limit, leadingApproximation)
    local key = P.key(document, first, limit)
    if not key then return nil end
    local approximationMarker = key == "like" or key == "around" or key == "about" or key == "approximately"
        or key == "приблизно" or key == "близько"
    if approximationMarker then first = first + 1; key = P.key(document, first, limit) end
    if not key then return nil end
    local approximate = approximationMarker or leadingApproximation
    local amount, unit = key:match("^(%d+)([a-z]+)$")
    local after = first + 1
    local english = document.direction == "en-uk"
    local grammar = ns.Linguistics.grammar
    local cardinals = english and grammar.cardinalEn or grammar.cardinalUk
    local cardinal = cardinals and cardinals[key]
    local indefinite = english and (key == "a" or key == "an")
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
    elseif cardinal or indefinite then
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
    elseif approximate and not english and singularTimeForms[key] then
        amount, unit, indefinite = "1", singularTimeForms[key], true
    end
    local lemma = timeUnits[unit] or singularTimeForms[unit]
    if lemma and (half or few or amount and #amount <= 12) then
        return {amount=amount, unit=lemma, approximate=approximate, few=few, half=half, indefinite=indefinite}, after
    end
end

function P.delay(document, first, limit)
    local marker = P.key(document, first, limit)
    local english = document.direction == "en-uk"
    local approximate = not english and marker == "приблизно"
    if approximate then first = first + 1; marker = P.key(document, first, limit) end
    if not (english and marker == "in" or not english and (marker == "за" or marker == "через")) then return end
    local quantity, after = P.quantity(document, first + 1, limit, approximate)
    if quantity then return quantity, after end
    if english and P.key(document, first + 1, limit) == "a" and P.key(document, first + 2, limit) == "few" then
        return {soon=true}, first + 3
    end
end

function P.pastOffset(document, first, limit, contrasted)
    if first >= limit then return nil end
    local english = document.direction == "en-uk"
    local marker = P.key(document, first, limit)
    local negative = marker == (english and "not" or "не")
    local bound
    if negative then
        if contrasted then return nil end
        first = first + 1
    elseif english and (marker == "less" or marker == "more")
        and P.key(document, first + 1, limit) == "than" then
        first, bound = first + 2, marker
    elseif not english and (marker == "менше" or marker == "більше")
        and P.key(document, first + 1, limit) == "ніж" then
        first, bound = first + 2, marker == "менше" and "less" or "more"
    end
    local quantity, after = P.quantity(document, first, limit)
    if not quantity and not english then
        local unit = singularTimeForms[P.key(document, first, limit)]
        if unit then quantity, after = {amount="1", unit=unit, indefinite=true}, first + 1 end
    end
    if not quantity or P.key(document, after, limit) ~= (english and "ago" or "тому") then return nil end
    local sentenceEnd = #document.tokens
    if not english and P.key(document, after + 1, sentenceEnd) == "що" then return nil end
    if negative then
        local nextIndex = after + 1
        if P.key(document, nextIndex, sentenceEnd) == "," then nextIndex = nextIndex + 1 end
        if P.key(document, nextIndex, sentenceEnd) == (english and "but" or "а") then
            local alternative, finish = P.pastOffset(document, nextIndex + 1, limit, true)
            if alternative then return {quantity=quantity, alternative=alternative}, finish end
            return nil
        end
        if not english then return nil end
        bound = "less"
    end
    return {quantity=quantity, bound=bound}, after + 1
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
