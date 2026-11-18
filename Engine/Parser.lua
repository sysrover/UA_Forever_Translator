local _, ns = ...
local P = {}; ns.Engine.Parser = P
local category = {
    role = "roles", place = "places", profession = "professions", class = "classes",
    goods = "goods", goods2 = "goods", activity = "activities", address = "addresses",
    creature = "creatures", creaturePlural = "creatures", behavior = "behaviors", recipient = "recipients",
}
local requiredCase = { address = "vocative", creature = "accusative", creaturePlural = "nominative" }
local requiredNumber = { creaturePlural = "plural" }
local dashJoins = { ["—"] = " — ", ["–"] = " – " }
local sentenceJoins = { ["."] = ". ", ["!"] = "! ", ["?"] = "? " }
local alternatives = { ["or"] = true, ["або"] = true, ["чи"] = true }
local function joinAt(tokens, index, joins)
    local current = tokens[index]
    local wordJoin = joins[current.key] or dashJoins[current.key]
    if wordJoin then return wordJoin end
    -- A decimal separator is part of a number when followed without a gap.
    if tokens[index + 1].first <= current.last + 1 then return nil end
    if sentenceJoins[current.key] then return sentenceJoins[current.key], true end
    if current.key == "," then return ", " end
end
local function tokenText(text, tokens, first, last)
    return text:sub(tokens[first].first, tokens[last].last)
end

local function lowerStart(value)
    if value:match("^I[^%w]") or value == "I" then return value end
    local first = value:match("^[\192-\223][\128-\191]") or value:sub(1, 1)
    return ns.Engine.Normalize.word(first) .. value:sub(#first + 1)
end

function P.compose(text, tokens, direction)
    local composition = ns.Data.composition and ns.Data.composition[direction]
    if not composition or #tokens == 0 or #tokens > 96 then return nil end
    local prefixes, joins = composition.prefixes, composition.joins
    local first, prefix = 1, prefixes[tokens[1].key]
    if prefix then
        local separator = tokens[2] and tokens[2].key
        first = (separator == "," or dashJoins[separator]) and 3 or 2
        if first > #tokens then return nil end
    else
        local found
        for i = 2, #tokens - 1 do
            if joinAt(tokens, i, joins) then found = true; break end
        end
        if not found then return nil end
    end
    local attempts, memo = 24, {}
    local function translateClause(start, finish)
        if start > finish then return nil end
        local row = memo[start]
        if row and row[finish] ~= nil then return row[finish] or nil end
        if attempts == 0 then return nil end
        attempts = attempts - 1
        if not row then row = {}; memo[start] = row end
        local key = ns.Engine.Normalize.key(tokenText(text, tokens, start, finish))
        local exact = ns.Data.exact[direction][key]
        local output, rule, slots
        if exact then
            output, rule = exact.text, exact
        else
            output, rule, slots = P.translate(text, tokens, direction, start, finish)
        end
        local match = output and {text = output, rule = rule, slots = slots} or false
        row[finish] = match
        return match or nil
    end
    local function endBefore(joinIndex)
        return tokens[joinIndex - 1].key == "," and joinIndex - 2 or joinIndex - 1
    end
    local function joinFrom(start, depth)
        if attempts == 0 then return nil end
        -- A complete clause takes precedence over splitting its object list.
        if start ~= 1 or prefix then
            local match = translateClause(start, #tokens)
            if match then return match.text, {match} end
        end
        if depth == 1 then return nil end
        for i = start + 1, #tokens - 1 do
            local join, sentence = joinAt(tokens, i, joins)
            if join then
                local finish = endBefore(i)
                local matched = translateClause(start, finish)
                local left = matched and matched.text
                local sourceEnd = tokens[finish] and tokens[finish].key
                local sourceHasEnd = sourceEnd == "?" or sourceEnd == "!"
                local alternativeQuestion = left and not sourceHasEnd and alternatives[tokens[i].key]
                    and left:sub(-1) == "?"
                if left and (sentence or alternativeQuestion or (not sourceHasEnd and not left:match("[?!]$"))) then
                    local right, rest = joinFrom(i + 1, depth - 1)
                    if right and (not alternativeQuestion or right:sub(-1) == "?") then
                        table.insert(rest, 1, matched)
                        local leftText = left:gsub((sentence or alternativeQuestion) and "[.!?]+$" or "%.$", "")
                        return leftText .. join .. (sentence and right or lowerStart(right)), rest
                    end
                end
            end
        end
    end
    local output, matches = joinFrom(first, 4)
    if output then
        if prefix then output = prefix .. lowerStart(output) end
        return output, matches
    end

    -- A failed composition can still contribute complete clauses to a preview.
    -- Keep their original boundaries so the caller can preserve every gap.
    local starts, ends = {first}, {}
    for i = first + 1, #tokens - 1 do
        if joinAt(tokens, i, joins) then
            ends[#ends + 1] = endBefore(i)
            starts[#starts + 1] = i + 1
        end
    end
    if #starts < 2 then return nil end
    ends[#ends + 1] = #tokens
    local fragments = {}
    local segment, accepted = 1, 0
    while segment <= #starts and accepted < 4 and attempts > 0 do
        local start = starts[segment]
        local nextSegment = segment + 1
        for block = #ends, segment, -1 do
            if attempts == 0 then break end
            local finish = ends[block]
            local match = translateClause(start, finish)
            if match then
                local last = finish
                while last > start and tokens[last].key:match("^[.!?]$") do last = last - 1 end
                local replacement = match.text:gsub(last < finish and "[.!?]+$" or "[.!]+$", "")
                if start ~= 1 and not sentenceJoins[tokens[start - 1].key] then replacement = lowerStart(replacement) end
                fragments[start] = {text = replacement, last = last, rule = match.rule, slots = match.slots}
                accepted, nextSegment = accepted + 1, block + 1
                break
            end
        end
        segment = nextSegment
    end
    return nil, nil, accepted > 0 and fragments or nil
end
local function slot(text, tokens, index, name, direction, limit)
    if index > limit then return nil end
    local token = tokens[index]
    if category[name] then
        local start = index
        if category[name] == "goods" then
            if token.protected then
                local raw = tokenText(text, tokens, index, index)
                if ns.Engine.Markup.isLink(raw) then return {raw = raw}, index + 1 end
            elseif direction == "en-uk" and (token.key == "a" or token.key == "an" or token.key == "some") then
                index = index + 1
            end
        end
        local term, last = ns.Engine.Dictionary.longest(tokens, index, direction, category[name], limit,
            requiredCase[name], requiredNumber[name])
        if term then
            local raw = tokenText(text, tokens, start, last)
            local key = ns.Engine.Normalize.key(tokenText(text, tokens, index, last))
            local forms = term.forms or {}
            local plural = (direction == "uk-en" and (key == forms.genitivePlural or key == forms.nominativePlural or key == forms.accusativePlural))
                or (direction == "en-uk" and term.englishPlural and key == ns.Engine.Normalize.word(term.englishPlural))
            return {term = term, raw = raw, plural = plural}, last + 1
        end
    elseif name == "count" then
        if token.key:match("^%d+$") and #token.key <= 3 and tonumber(token.key) > 0 then
            return {raw = token.key}, index + 1
        end
    elseif name == "item" then
        -- Full trade templates accept a protected hyperlink only. Unknown plain
        -- item names stay in a visibly partial result instead of swallowing conditions.
        local raw = tokenText(text, tokens, index, index)
        if token.protected and ns.Engine.Markup.isLink(raw) then return {raw = raw}, index + 1 end
    elseif name == "price" or name == "time" then
        for last = math.min(limit, index + 4), index, -1 do
            local raw = tokenText(text, tokens, index, last)
            local pattern = name == "price" and "^%d+[%.,]?%d*%s*[gsc]$" or "^%d+[%.,]?%d*%s*[mh]$"
            if not token.protected and raw:lower():match(pattern) then return {raw = raw}, last + 1 end
        end
    end
end
local function matchRule(rule, text, tokens, direction, first, last)
    local index, slots = first, {}
    for _, part in ipairs(rule.pattern) do
        local name, form = part:match("^{([%w_]+):?([%w_]*)}$")
        if name and form ~= "" then
            local previous = slots[name]
            local forms = previous and previous.term and previous.term.renderForms
            local expected = forms and forms[form]
            if not expected or index > last or tokens[index].protected
                or tokens[index].key ~= ns.Engine.Normalize.word(expected) then return nil end
            index = index + 1
        elseif name then
            local value, nextIndex = slot(text, tokens, index, name, direction, last)
            local previous = slots[name]
            if not value then return nil end
            if previous and (previous.term ~= value.term or (not value.term and previous.raw ~= value.raw)) then
                return nil
            end
            slots[name], index = value, nextIndex
        elseif index <= last and not tokens[index].protected and tokens[index].key == part then index = index + 1
        else return nil end
    end
    -- Only terminal sentence punctuation can be ignored. No unknown tail,
    -- omitted negation, requirement, price or timer becomes a full translation.
    while index <= last and tokens[index].key:match("^[.!?]$") do index = index + 1 end
    if index <= last then return nil end
    local output = ns.Engine.Grammar.render(rule.output, slots, direction)
    if output and tokens[last].key == "?" then
        output = output:gsub("[.!?]+$", "") .. "?"
    end
    if output then return output, slots end
end
function P.translate(text, tokens, direction, first, last)
    first, last = first or 1, last or #tokens
    if first > last then return nil end
    local node = ns.Data.rules[direction]
    local selected, selectedRule, selectedSlots, priority, ambiguous
    for i = first, last do
        if not node.next or tokens[i].protected then break end
        node = node.next[tokens[i].key]
        if not node then break end
        if node.matches then
            for _, rule in ipairs(node.matches) do
                local currentPriority = rule.priority or 100
                if not selected or currentPriority >= priority then
                    local output, slots = matchRule(rule, text, tokens, direction, i + 1, last)
                    if output then
                        if not selected or currentPriority > priority then
                            selected, selectedRule, selectedSlots = output, rule, slots
                            priority, ambiguous = currentPriority, false
                        elseif selected ~= output then
                            ambiguous = true
                        elseif rule.order < selectedRule.order then
                            selectedRule, selectedSlots = rule, slots
                        end
                    end
                end
            end
        end
    end
    if selected and not ambiguous then return selected, selectedRule, selectedSlots end
end
