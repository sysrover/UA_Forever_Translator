local _, ns = ...
local D = {}; ns.Engine.Dictionary = D
local function derivedTerm(node, direction, category, requiredCase, requiredNumber)
    if not node._morph or (category and category ~= "creatures" and category ~= "addresses") then return nil end
    local selected
    for id, cases in pairs(node._morph) do
        local candidate = ns.Data.terms[id]
        local allowedCase = direction ~= "uk-en" or not requiredCase or cases[requiredCase]
            or (requiredCase == "vocative" and cases.nominative)
        if allowedCase and (not requiredNumber or candidate.morphology.number == requiredNumber) then
            if selected then return nil end
            selected = candidate
        end
    end
    return selected
end
function D.longest(tokens, first, direction, category, limit, requiredCase, requiredNumber)
    local node, term, last = ns.Data.aliases[direction], nil, nil
    for i = first, math.min(limit or #tokens, first + 11) do
        if tokens[i].protected then break end
        node = node[tokens[i].key]
        if not node then break end
        local id = (category and node._byCategory and node._byCategory[category]) or node._id
        local candidate = id and ns.Data.terms[id]
        if candidate and not requiredNumber and (not category or candidate.category == category
            or (category == "goods" and candidate.englishObject)
            or (category == "activities" and candidate.englishActivity)) then
            term, last = candidate, i
        elseif node._morph then
            candidate = derivedTerm(node, direction, category, requiredCase, requiredNumber)
            if candidate then term, last = candidate, i end
        end
    end
    return term, last
end

local function generalTerm(token, direction)
    if token.protected then return nil end
    local curated = ns.Data.aliases[direction][token.key]
    -- Leave intentionally ambiguous curated forms for the user's review.
    if curated and (curated._id or curated._literal or curated._morph or curated._byCategory) then return nil end
    return ns.Engine.GeneralDictionary.lookup(token.key, direction)
end

function D.lookup(text, direction)
    local tokens = ns.Engine.Tokenizer.scan(text)
    if not tokens or #tokens == 0 then return nil end
    local term, last = D.longest(tokens, 1, direction)
    if last == #tokens then return term end
    if #tokens == 1 then return generalTerm(tokens[1], direction) end
end

local function agreesWithLexicon(document, first, term)
    local language = document.direction == "en-uk" and "uk" or "en"
    local gloss = ns.Engine.Normalize.word(term[language])
    local analyses = ns.Engine.Lexicon.at(document, first)
    if analyses.truncated or #analyses == 0 then return false end
    local pos = analyses[1].lexeme.pos
    if pos ~= "noun" and pos ~= "verb" and pos ~= "adj" then return false end
    for _, candidate in ipairs(analyses) do
        if candidate.lexeme.pos ~= pos or ns.Engine.Normalize.word(candidate.lexeme[language]) ~= gloss then return false end
    end
    return true
end

function D.literal(document, first, fragments, contextual)
    local tokens, direction, preserved = document.tokens, document.direction, document.preserve
    local node = ns.Data.aliases[direction]
    local entry, last
    for i = first, math.min(#tokens, first + 11) do
        if tokens[i].protected or (i > first and ((fragments and fragments[i]) or (preserved and preserved[i]))) then break end
        node = node[tokens[i].key]
        if not node then break end
        local literal = node._literal
        local term = node._id and ns.Data.terms[node._id]
        if literal then
            entry, last = literal, i
        elseif term and (term.category ~= "places" or term.literalInChat)
            and (direction ~= "en-uk" or not term.englishLookupOnly) then
            entry, last = term, i
        elseif node._morph then
            local derived = derivedTerm(node, direction)
            if derived then entry, last = derived, i end
        end
    end
    if entry then return entry, last end
    local general = generalTerm(tokens[first], direction)
    if general and (not contextual or agreesWithLexicon(document, first, general)) then return general, first end
end
