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

function D.literal(document, first, fragments)
    local tokens, direction = document.tokens, document.direction
    if tokens[first].protected then return nil end
    local node = ns.Data.aliases[direction]
    local entry, last
    for i = first, math.min(#tokens, first + 11) do
        local fragment = fragments and fragments[i]
        if tokens[i].protected or (i > first and fragment and not fragment.preserve) then break end
        node = node[tokens[i].key]
        if not node then break end
        local literal = node._literal or node._plural
        local term = node._id and ns.Data.terms[node._id]
        if literal then
            entry, last = literal, i
        elseif term and (direction ~= "en-uk" or not term.englishLookupOnly) then
            entry, last = term, i
        elseif node._morph then
            local derived = derivedTerm(node, direction)
            if derived then entry, last = derived, i end
        end
    end
    if entry then return entry, last end
    local token = tokens[first]
    local single = ns.Data.aliases[direction][token.key]
    local contextual = single and single._id and ns.Data.terms[single._id]
    if direction == "en-uk" and contextual and contextual.englishLookupOnly then
        local raw = document.text:sub(token.first, token.last)
        local previous = tokens[first - 1]
        -- Keep a spelled-out acronym or a possible unit out of ordinary word lookup.
        if (raw == contextual.en and raw:match("%u.*%u")) or (previous and previous.key:match("^%d+$")) then return nil end
    end
    local general = ns.Engine.GeneralDictionary.lookup(token.key, direction)
    if general then return general, first end
end
