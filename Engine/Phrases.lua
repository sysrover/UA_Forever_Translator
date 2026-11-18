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
            elseif candidate.last == selected.last and candidate.id ~= selected.id then return nil, true end
        end
    end
    return selected
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
    local pronouns, last = L.functional(document, "pronouns", first, limit)
    if pronouns and last <= limit and not locationOnly then
        local selected
        for _, match in ipairs(pronouns) do
            local valid = case == match.case or (case ~= "nominative" and match.case ~= "nominative"
                and match.case ~= "possessive" and document.direction == "en-uk")
            if valid then
                local candidate = ns.Linguistics.grammar.pronouns[match.id]
                if selected and selected ~= candidate then return nil end
                selected = candidate
            end
        end
        if selected then
            return {pronoun=selected, person=selected.person, gender=selected.gender,
                number=selected.number}, last + 1
        end
    end
    local reverseCase = document.direction == "uk-en" and case or nil
    local known, ambiguous = curated(document, first, limit, reverseCase, locationOnly)
    if known then
        local term, features = known.term, known.features
        return {term=term, person=3, number=features.number or "singular",
            gender=features.gender, animacy=features.animacy}, known.last + 1
    end
    if ambiguous then return nil end
    local lexeme = L.choose(document, first, "noun", nil, nil, function(candidate)
        return not reverseCase or candidate.form.case == reverseCase
            or (reverseCase == "nominative" and candidate.form.case == nil)
    end)
    if lexeme then
        return {entry=lexeme, person=3, number=lexeme.form.number or lexeme.head.number or "singular",
            gender=lexeme.form.gender or lexeme.head.gender,
            animacy=lexeme.head.animacy}, first + 1
    end
end

function P.noun(document, first, limit, case, locationOnly, count)
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
    if article or demonstrative then index = index + 1 end
    local quantity = P.key(document, index, limit)
    if count ~= false and quantity and quantity:match("^%d+$") then
        index = index + 1
    else quantity = nil end
    local adjectives, best, nextIndex = {}
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
        if head and (not intensity or #adjectives > 0) then
            best, nextIndex = head, after
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
    if not best then return nil end
    best.article, best.quantity, best.demonstrative = article, quantity, demonstrative
    best.emphatic = emphatic
    if document.direction == "en-uk" and best.term and best.term.category == "classes"
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
    return best, nextIndex
end

function P.preposition(document, first, limit, motion)
    local choices, last = L.functional(document, "prepositions", first, limit)
    if not choices or last > limit then return nil end
    local selected, after
    for _, id in ipairs(choices) do
        local rule = ns.Linguistics.grammar.prepositions[id]
        local case = motion and rule.id == "in" and "accusative" or rule.case
        local object, ending = P.noun(document, last + 1, limit, case,
            rule.id == "in" or rule.id == "to" or rule.id == "from")
        if object then
            if selected then return nil end
            selected, after = {rule=rule, object=object, case=case}, ending
        end
    end
    return selected, after
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
