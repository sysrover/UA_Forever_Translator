local _, ns = ...
local A = {}; ns.Engine.Acceptance = A
local empty = {}
local metalNames = {gold=true, silver=true, copper=true}
local amountIntroduces = {["for"]=true, ["to"]=true}
local scopeStops = { [","]=true, [";"]=true, ["—"]=true, ["–"]=true }

local function decimalKey(amount)
    local whole, fraction = amount:match("^(%d+)[.,]?(%d*)$")
    whole = whole:gsub("^0+", "")
    fraction = fraction:gsub("0+$", "")
    return (whole == "" and "0" or whole) .. "." .. fraction
end

local function scopeFences(text, tokens, direction)
    local fences
    local english = direction == "en-uk"
    local first, boundaryStart, command, linked = 1, nil, false, false
    for index = 1, #tokens + 1 do
        local token, following = tokens[index], tokens[index + 1]
        local key = token and token.key
        local consequence = english and key == "or" and following and following.key == "else"
        if not token or scopeStops[key] or consequence or ns.Engine.Parser.sentenceBoundary(text, tokens, index) then
            if linked then
                fences = fences or {}
                fences[#fences + 1] = {first=boundaryStart or first, last=index - 1,
                    kind=command and "unresolved-predicate-scope" or "unresolved-temporal-scope"}
            end
            first, boundaryStart, command, linked = index + 1, nil, false, false
        elseif english then
            if index == first then
                command = key == "don't" or key == "dont" or key == "do" and following and following.key == "not"
            elseif command and key == "or" and following then linked = true end
        elseif key == "доки" then
            boundaryStart = boundaryStart or index
        elseif boundaryStart and key == "не" then
            linked = true
        end
    end
    return fences
end

function A.measure(text, tokens, direction)
    local fences = direction and scopeFences(text, tokens, direction)
    local facts, first = fences, 1
    local document = {text=text, tokens=tokens}
    while first <= #tokens do
        local token, nextToken = tokens[first], first + 1
        local kind, value
        if token.protected then
            kind, value = "protected-content", text:sub(token.first, token.last)
        elseif token.key:match("^%d") then
            local clock, after = ns.Engine.Phrases.clockAt(document, first, #tokens)
            if clock then
                kind, value, nextToken = "clock-content", clock:gsub("^0(%d:)", "%1"), after
            else
                local price, ending = ns.Engine.Grammar.moneyAt(document, first, #tokens)
                if price then
                    local amount = decimalKey(price.amount)
                    local metal = ns.Engine.Normalize.key(price.sourceRaw):match("^%d+[.,]?%d* (%a+)$")
                    local following = tokens[ending]
                    -- A bare metal can be a material adjective before an item.
                    local unambiguous = not metalNames[metal] or not following
                        or not following.protected and (following.key:match("^%p$")
                            or amountIntroduces[following.key]
                            or ns.Engine.Grammar.priceBasisAt(document, ending, #tokens))
                    -- Zero can be rendered as "free" or "безкоштовно".
                    if unambiguous and amount ~= "0." then
                        kind, value, nextToken = "currency-content", amount .. price.unit, ending
                    end
                end
            end
        end
        if kind then
            facts = facts or {}
            facts[#facts + 1] = {first=first, last=nextToken - 1, kind=kind, key=kind .. ":" .. value}
        end
        first = nextToken
    end
    if fences then table.sort(facts, function(a, b) return a.first < b.first end) end
    return facts
end

function A.reject(facts, first, last, output)
    local expected, tracked
    for _, fact in ipairs(facts or empty) do
        if fact.first > last then break end
        if fact.last >= first then
            if fact.first < first or fact.last > last then return fact.kind end
            if fact.key then
                expected, tracked = expected or {}, tracked or {}
                expected[fact.key] = (expected[fact.key] or 0) + 1
                tracked[fact.kind] = true
            end
        end
    end

    -- Unprotected prose only needs to be scanned if the rendering opens a protected span.
    if not expected and not output:find("[|@<{/%[]") and not output:find("[Ww][Ww][Ww]%.") then return nil end
    if not tracked or not (tracked["clock-content"] or tracked["currency-content"]) then
        for _, segment in ipairs(ns.Engine.Markup.split(output)) do
            if segment.protected then
                local key = "protected-content:" .. output:sub(segment.first, segment.last)
                if not expected or not expected[key] then return "protected-content" end
                expected[key] = expected[key] - 1
                if expected[key] < 0 then return "protected-content" end
            end
        end
    else
        local tokens = ns.Engine.Tokenizer.scan(output)
        if not tokens then return "unverifiable-content" end
        for _, fact in ipairs(A.measure(output, tokens) or empty) do
            if fact.kind == "protected-content" or tracked[fact.kind] then
                if not expected[fact.key] then return fact.kind end
                expected[fact.key] = expected[fact.key] - 1
                if expected[fact.key] < 0 then return fact.kind end
            end
        end
    end
    for _, fact in ipairs(facts or empty) do
        if fact.first > last then break end
        if fact.key and fact.last >= first and expected[fact.key] ~= 0 then return fact.kind end
    end
end

function A.preserveScopes(facts, ranges)
    if not facts then return ranges end
    local preserved, position = {}, 1
    for _, range in ipairs(ranges) do
        local first, last, reason = range.first, range.last, range.reason
        local fact = facts[position]
        while fact and fact.first <= last do
            if not fact.key and fact.last >= first then
                first, last, reason = math.min(first, fact.first), math.max(last, fact.last), fact.kind
            end
            position = position + 1
            fact = facts[position]
        end
        local previous = preserved[#preserved]
        if previous and first <= previous.last then
            previous.last, previous.reason = math.max(previous.last, last), previous.reason or reason
        else
            preserved[#preserved + 1] = {first=first, last=last, inline=range.inline, reason=reason}
        end
    end
    return preserved
end

function A.rejectRoles(parsed, first, arcs, words)
    for _, tree in ipairs(parsed.trees) do
        local verb = tree.verbIndex and tree.verbIndex - first + 1
        local predicate = verb and words[verb]
        local subject = tree.subject and tree.subject.headIndex
        local object = tree.object and tree.object.headIndex
        if predicate and predicate.upos == "VERB" and subject and object and not tree.inherited then
            local subjectArc, objectArc = arcs[subject - first + 1], arcs[object - first + 1]
            if subjectArc and objectArc and subjectArc.head == verb and objectArc.head == verb
                and subjectArc.relation == "obj" and objectArc.relation == "nsubj" then
                return "role-conflict"
            end
        end
    end
end
