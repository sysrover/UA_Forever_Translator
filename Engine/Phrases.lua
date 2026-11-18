local _, ns = ...
local P = {}
ns.Engine.Phrases = P
local L = ns.Engine.Lexicon

local articles = {a="indefinite", an="indefinite", the="definite"}
local demonstratives = {this="near", these="near", that="far", those="far",
    ["цей"]="near", ["ця"]="near", ["це"]="near", ["ці"]="near", ["цю"]="near", ["цих"]="near",
    ["того"]="far", ["той"]="far", ["та"]="far", ["те"]="far", ["ті"]="far", ["ту"]="far"}
local semanticNouns = {roles=true, classes=true, places=true, creatures=true, goods=true, game=true,
    professions=true, activities=true, equipment=true, stats=true, countries=true, territories=true}
local groupNouns = {group=true, party=true, team=true, raid=true}
local timeUnits = {
    min="хвилина", mins="хвилина", minute="хвилина", minutes="хвилина",
    s="секунда", sec="секунда", secs="секунда", second="секунда", seconds="секунда",
    h="година", hr="година", hrs="година", hour="година", hours="година",
    day="день", days="день",
    ["хвилина"]="хвилина", ["хвилини"]="хвилина", ["хвилин"]="хвилина",
    ["секунда"]="секунда", ["секунди"]="секунда", ["секунд"]="секунда",
    ["година"]="година", ["години"]="година", ["годин"]="година",
    ["день"]="день", ["дні"]="день", ["днів"]="день",
}
local englishUnits = {["хвилина"]="minute", ["секунда"]="second", ["година"]="hour", ["день"]="day"}

function P.key(document, index, limit)
    return index <= limit and document.tokens[index] and document.tokens[index].key
end

function P.raw(document, first, last)
    return document.text:sub(document.tokens[first].first, document.tokens[last].last)
end

local function curated(document, first, last, requiredCase, locationOnly)
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
        if raw and semanticNouns[category] and (not locationOnly or category == "places")
            and (not requiredCase or not candidate.features.case or requiredCase == candidate.features.case)
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

local function curatedNoun(candidate)
    local features = candidate.features
    return {term=candidate.term, person=3, number=features.number or "singular",
        gender=features.gender, animacy=features.animacy, sourceCase=features.case}
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

local function possessive(candidate)
    local frame = candidate.lexeme.frame
    return frame and frame.possessive
end

function P.pronoun(document, first, limit, case, personOnly)
    local choices, last = L.functional(document, "pronouns", first, limit)
    if not choices then return nil end
    local selected
    for _, match in ipairs(choices) do
        local valid = case == match.case or (case ~= "nominative" and match.case ~= "nominative"
            and match.case ~= "possessive" and document.direction == "en-uk")
        local candidate = ns.Linguistics.grammar.pronouns[match.id]
        if valid and (not personOnly or candidate.id ~= "it") then
            if selected and selected ~= candidate then return false end
            selected = candidate
        end
    end
    if selected then
        return {pronoun=selected, person=selected.person, gender=selected.gender, number=selected.number}, last + 1
    end
end

local function nounHead(document, first, limit, case, locationOnly)
    local key = P.key(document, first, limit)
    if not key then return nil end
    local token = document.tokens[first]
    if token.protected then
        local raw = P.raw(document, first, first)
        if token.linkKind or raw:match("^<.+>$") or raw:sub(1, 1) == "@" then
            return {raw=raw, number="singular", person=3}, first + 1
        end
        return nil
    end
    local phrase, phraseEnd = L.phraseAt(document, first, limit, "noun")
    if phrase then
        local entry = L.choose(document, phrase, "noun")
        if entry then return lexicalNoun(entry), phraseEnd end
    end
    if not locationOnly then
        local pronoun, after = P.pronoun(document, first, limit, case)
        if pronoun ~= nil then return pronoun or nil, after end
    end
    local reverseCase = document.direction == "uk-en" and case or nil
    local known, ambiguous = curated(document, first, limit, reverseCase, locationOnly)
    if known then return curatedNoun(known), known.last + 1 end
    if ambiguous then return nil end
    local lexeme = L.choose(document, first, "noun", nil, nil, function(candidate)
        local frame = candidate.lexeme.frame
        if document.direction == "en-uk" and frame and frame.requiresLocation and not locationOnly then return false end
        return not reverseCase or candidate.form.case == reverseCase
            or (reverseCase == "nominative" and candidate.form.case == nil)
    end)
    if not lexeme and reverseCase and not locationOnly and groupDestination(document, first + 1, limit) then
        lexeme = L.choose(document, first, "noun", {case=reverseCase}, nil, function(candidate)
            return groupNouns[candidate.lexeme.en]
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
end

function P.noun(document, first, limit, case, locationOnly, count, simple)
    local index = first
    local key = P.key(document, index, limit)
    if key == "\"" then
        if P.key(document, first + 1, limit) == "\"" then return nil end
        local quoted, after = P.noun(document, first + 1, limit, case, locationOnly, count)
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
    local ownerIndex, owner = index
    if not article and not demonstrative and not emphatic and index <= limit then
        owner = L.choose(document, index, "pron", nil, nil, possessive)
    end
    if article or demonstrative then index = index + 1 end
    if owner then index = index + 1 end
    local quantity = P.key(document, index, limit)
    if count ~= false and quantity and quantity:match("^%d+$") then
        index = index + 1
    else quantity = nil end
    local adjectives, best, nextIndex, headIndex = {}
    local degree = P.key(document, index, limit)
    local intensity
    if degree == "very" or degree == "дуже" or degree == "more" or degree == "більш" then
        intensity = (degree == "more" or degree == "більш") and "more" or "very"
        index = index + 1
    end
    -- Check the head after each adjective. The longest grammatical noun phrase
    -- wins, with a bounded number of modifiers.
    for _ = 0, 2 do
        local head, after = nounHead(document, index, limit, case, locationOnly)
        if head and (not head.pronoun or index == first) and (not intensity or #adjectives > 0)
            and (not best or after > nextIndex or (after == nextIndex and head.term and not best.term)) then
            best, nextIndex, headIndex = head, after, index
            if #adjectives > 0 then best.adjectives = {unpack(adjectives)} end
        end
        if index > limit then break end
        local adjective = L.choose(document, index, "adj", nil, nil, function(candidate)
            return document.direction == "en-uk" or candidate.form.case == case
        end)
        if not adjective then break end
        adjectives[#adjectives + 1] = {entry=adjective, intensity=#adjectives == 0 and intensity or nil}
        index = index + 1
    end
    if not best then
        if owner then return nounHead(document, first, limit, case, locationOnly) end
        return nil
    end
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
            local requested = {case=case, number=best.number, gender=best.number ~= "plural" and best.gender or nil}
            owner = L.choose(document, ownerIndex, "pron", nil, nil, function(candidate)
                return possessive(candidate)
                    and (candidate.lexeme.frame.invariable or L.matches(candidate.form, requested))
            end)
            if not owner then return nil end
        end
        if best.nominalObject then best.nominalObject.possessor = owner
        else best.possessor = owner end
    end
    best.article, best.quantity, best.demonstrative = article, quantity, demonstrative
    best.emphatic = emphatic
    local frame = best.entry and best.entry.lexeme.frame
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
        local lemma = best.entry and best.entry.lexeme.en or best.term and best.term.en
        if lemma and groupNouns[ns.Engine.Normalize.word(lemma)] then
            local destination, after = groupDestination(document, nextIndex, limit)
            if destination then best.destination, nextIndex = destination, after end
        end
        if not best.destination and (not en or marker == "of") then
            local dependent, after = P.noun(document, nextIndex + (en and 1 or 0), limit,
                "genitive", false, false, true)
            if dependent and not dependent.pronoun and (en or dependent.sourceCase == "genitive") then
                best.genitive, nextIndex = dependent, after
            end
        end
    end
    return best, nextIndex
end

function P.preposition(document, first, limit, motion)
    if document.direction == "en-uk" and P.key(document, first, limit) == "of" then return nil end
    local choices, last = L.functional(document, "prepositions", first, limit)
    if not choices or last > limit then return nil end
    local selected, after, priority, ambiguous
    for _, id in ipairs(choices) do
        local rule = ns.Linguistics.grammar.prepositions[id]
        local case = motion and rule.id == "in" and "accusative" or rule.case
        local object, ending = P.noun(document, last + 1, limit, case,
            rule.id == "in" or rule.id == "to" or rule.id == "from")
        local frame = object and object.entry and object.entry.lexeme.frame
        if object and (not rule.requiresLexicalLocative or (frame and frame.locativePreposition == rule.targetUk))
            and (not rule.requiresNearLandmark or (frame and frame.atNearLandmark)) then
            local rank = (rule.requiresLexicalLocative or rule.requiresNearLandmark) and 1 or 0
            if not priority or rank > priority then
                selected, after, priority, ambiguous = {rule=rule, object=object, case=case}, ending, rank, false
            elseif rank == priority then ambiguous = true end
        end
    end
    if not ambiguous then return selected, after end
end

function P.coordinated(document, first, limit, case, startsPredicate, locationOnly)
    local head, index = P.noun(document, first, limit, case, locationOnly)
    if not head then return nil end
    local members, joins = {head}, {}
    for _ = 2, 4 do
        local choices, last = L.functional(document, "connectors", index, limit)
        local connector = choices and ns.Linguistics.grammar.connectors[choices[1]]
        if not connector or (connector.id ~= "and" and connector.id ~= "or") then break end
        local member, after = P.noun(document, last + 1, limit, case, locationOnly)
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
    if not amount and key:match("^%d+$") then
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
    if amount and lemma and #amount <= 12 then
        return {amount=amount, unit=lemma, approximate=approximate}, after
    end
end
P.englishUnits = englishUnits
