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

local dungeonSpellings
local function dungeonSpellingIndex()
    local exact, missing = {}, {}
    local function add(index, key, term)
        local prior = index[key]
        if prior == nil then index[key] = term
        elseif prior ~= term then index[key] = false end
    end
    local function spellings(aliases, term)
        for _, value in ipairs(aliases) do
            local key = ns.Engine.Normalize.key(value):gsub("^the ", "")
            if #key >= 6 and #key <= 24 and key:match("^[a-z]+$") then
                add(exact, key, term)
                for i = 1, #key do add(missing, key:sub(1, i - 1) .. key:sub(i + 1), term) end
            end
        end
    end
    for _, term in pairs(ns.Data.terms) do
        if term.category == "places" and term.features and term.features.clearableInstance then
            spellings({term.en}, term)
            spellings(term.aliases and term.aliases.en or {}, term)
            spellings(term.contextAliases and term.contextAliases.en or {}, term)
        end
    end
    return {exact=exact, missing=missing}
end

-- Call only from a grammar position that requires a dungeon destination.
function M.dungeonSpelling(document, first)
    local token = document.tokens[first]
    if document.direction ~= "en-uk" or not token or token.protected then return end
    local key = token.key
    if #key < 5 or #key > 25 or not key:match("^[a-z]+$") then return end
    -- Exact names are resolved before this fallback. A known word can name a different entity.
    for _, reading in ipairs(document.spans[first] or {}) do
        if reading.last == first then return end
    end
    dungeonSpellings = dungeonSpellings or dungeonSpellingIndex()
    local exact, missing = dungeonSpellings.exact, dungeonSpellings.missing
    local selected = missing[key]
    local function consider(term)
        if term ~= nil then
            if selected == nil then selected = term
            elseif selected ~= term then selected = false end
        end
    end
    for i = 1, #key do
        local prefix, suffix = key:sub(1, i - 1), key:sub(i + 1)
        consider(exact[prefix .. suffix])
        if i < #key and key:sub(i, i) ~= key:sub(i + 1, i + 1) then
            consider(exact[prefix .. key:sub(i + 1, i + 1) .. key:sub(i, i) .. key:sub(i + 2)])
        end
        if selected == false then return end
    end
    if not selected or #ns.Engine.Lexicon.at(document, first) > 0 then return end
    return {term=selected, last=first, features=selected.features}
end

function M.generate(term, direction, form)
    local data = ns.Data.linguistics and ns.Data.linguistics.generation[term.id]
    local language = direction == "en-uk" and "uk" or "en"
    return data and data[language] and data[language][form or "canonical"]
end

local classSpellingByRegistry = setmetatable({}, {__mode="k"})
function M.classSpelling(key)
    local registry = ns.Data.terms
    local spellings = classSpellingByRegistry[registry]
    if not spellings then
        spellings = {}
        for _, term in pairs(registry) do
            local canonical = term.category == "classes" and term.status == "approved"
                and ns.Engine.Normalize.key(term.en)
            if canonical and canonical:match("^[a-z][a-z][a-z][a-z]+$") then
                for i = 1, #canonical - 1 do
                    local left, right = canonical:sub(i, i), canonical:sub(i + 1, i + 1)
                    if left ~= right then
                        local spelling = canonical:sub(1, i - 1) .. right .. left .. canonical:sub(i + 2)
                        local prior = spellings[spelling]
                        if prior == nil then spellings[spelling] = term
                        elseif prior ~= term then spellings[spelling] = false end
                    end
                end
            end
        end
        classSpellingByRegistry[registry] = spellings
    end
    return spellings[key] or nil
end
