local _, ns = ...
local M = {}; ns.Engine.Morphology = M

-- One bounded analysis per message. Byte offsets always refer to original text.
function M.analyze(text, tokens, direction)
    local index = ns.Data.linguistics and ns.Data.linguistics.analysis[direction]
    local document = {text=text, tokens=tokens, direction=direction, spans={}, truncated=false, limited={}}
    if not index then return document end
    for first = 1, #tokens do
        local node, spans = index, {}
        document.spans[first] = spans
        for last = first, math.min(#tokens, first + 11) do
            if tokens[last].protected then break end
            node = node[tokens[last].key]
            if not node then break end
            for _, candidate in ipairs(node._analyses or {}) do
                if #spans >= 32 then
                    document.truncated, document.limited[first] = true, true
                    document.preserve = document.preserve or {}
                    document.preserve[first] = {last=last, reason="analysis-limit"}
                    break
                end
                spans[#spans + 1] = {first=first, last=last, byteFirst=tokens[first].first,
                    byteLast=tokens[last].last, id=candidate.id, lemma=candidate.lemma,
                    pos=candidate.pos, sense=candidate.sense, features=candidate.features,
                    sourceRefs=candidate.sourceRefs, term=ns.Data.terms[candidate.id]}
            end
        end
    end
    return document
end

-- Context selects a category; equal meanings at the longest span stay unresolved.
function M.select(document, first, category, limit, requiredCase)
    if document.limited and document.limited[first] then return nil, "ambiguous" end
    local selected, ambiguous, last
    for _, candidate in ipairs(document.spans[first] or {}) do
        local features = candidate.features
        local compatible = candidate.term.category == category
            or (category == "goods" and candidate.term.englishObject)
        if candidate.last <= limit and compatible
            and (not requiredCase or not features.case or features.case == requiredCase) then
            if not last or candidate.last > last then
                selected, ambiguous, last = candidate, false, candidate.last
            elseif candidate.last == last and candidate.id ~= selected.id then
                ambiguous = true
            end
        end
    end
    if ambiguous then
        document.ambiguities = true
        document.preserve = document.preserve or {}
        document.preserve[first] = {last=last, reason="ambiguous-sense"}
        return nil, "ambiguous", last
    end
    return selected
end

function M.generate(term, direction, form)
    local data = ns.Data.linguistics and ns.Data.linguistics.generation[term.id]
    local language = direction == "en-uk" and "uk" or "en"
    return data and data[language] and data[language][form or "canonical"]
end
