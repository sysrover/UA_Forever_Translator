local _, ns = ...
local P = {}; ns.Engine.Parser = P
local category = {
    role = "roles", place = "places", profession = "professions", class = "classes",
    goods = "goods", goods2 = "goods", activity = "activities", address = "addresses",
    creature = "creatures", creaturePlural = "creatures", behavior = "behaviors", recipient = "recipients",
    equipment = "equipment", stat = "stats", country = "countries", nationality = "nationalities", territory = "territories",
    craftService = "craftServices",
}
local requiredCase = { address = "vocative", creature = "accusative", creaturePlural = "nominative" }
local requiredNumber = { creaturePlural = "plural" }
local dashJoins = { ["—"] = " — ", ["–"] = " – " }
local sentenceJoins = { ["."] = ". ", ["!"] = "! ", ["?"] = "? ", ["…"] = "… " }
local alternatives = { ["or"] = true, ["або"] = true, ["чи"] = true }
local sharedPredicateJoins = {["and"]=true, ["or"]=true, ["і"]=true, ["й"]=true, ["та"]=true, ["або"]=true, ["чи"]=true}

function P.startsWithCapital(text, token)
    if not token or token.protected then return false end
    local capitalized = ns.Engine.Normalize.upperStart(token.key)
    if capitalized == token.key then return false end
    local first = capitalized:match("^[A-Z]") or capitalized:sub(1, 2)
    return text:sub(token.first, token.first + #first - 1) == first
end

function P.sentenceBoundary(text, tokens, index)
    local punctuation, following = tokens[index], tokens[index + 1]
    if not sentenceJoins[punctuation.key] then return false end
    if not following or following.first > punctuation.last + 1 then return true end
    if punctuation.key ~= "." or not P.startsWithCapital(text, following) then return false end
    local previous = tokens[index - 1]
    if not previous or previous.last + 1 ~= punctuation.first then return false end
    if previous.protected or previous.key == ")" or previous.key == "»" or previous.key == '"' then return true end
    -- Digits and compact initials or title abbreviations also attach to periods.
    if not previous.key:match("[%a\128-\255]") then return false end
    local _, length = previous.key:gsub("[\128-\191]", "")
    local characters = #previous.key - length
    return characters > 4 or characters > 1 and not P.startsWithCapital(text, previous)
end

function P.ellipsisEnd(tokens, first, limit)
    if first > limit then return nil end
    local token = tokens[first]
    if not token then return nil end
    if token.key == "…" then return first end
    if token.key ~= "." or first + 2 > limit then return nil end
    local middle, last = tokens[first + 1], tokens[first + 2]
    if middle.key == "." and last.key == "." and middle.first == token.last + 1
        and last.first == middle.last + 1 then return first + 2 end
end

local function spacedDash(tokens, index)
    local token = tokens[index]
    if token.protected then return end
    local before, after = tokens[index - 1], tokens[index + 1]
    if before and after and token.first > before.last + 1 and after.first > token.last + 1
        and not (before.key:match("^%d") and after.key:match("^%d")) then
        return dashJoins["—"]
    end
end

local function joinAt(text, tokens, index, joins)
    local current = tokens[index]
    local wordJoin = joins[current.key] or dashJoins[current.key]
        or current.key == "-" and spacedDash(tokens, index)
    if wordJoin then return wordJoin end
    if current.key == "а" and tokens[index + 1].key == "коли" then return ", and " end
    local stop = sentenceJoins[current.key]
    if stop and (current.key == "!" or current.key == "?" or P.sentenceBoundary(text, tokens, index)) then
        return stop, true
    end
    if tokens[index + 1].first <= current.last + 1 then return nil end
    if current.key == "," then return ", " end
end
local function tokenText(text, tokens, first, last)
    return text:sub(tokens[first].first, tokens[last].last)
end

local function inferredStarts(text, tokens, direction)
    local starts
    for i = 3, #tokens - 1 do
        local token, previous = tokens[i], tokens[i - 1]
        local intrinsicCapital = direction == "en-uk" and (token.key == "i" or token.key:sub(1, 2) == "i'")
        if not (token.protected or intrinsicCapital) and token.first > previous.last + 1
            and (previous.protected or not previous.key:match("^%p$")) and not sentenceJoins[previous.key] then
            if P.startsWithCapital(text, token) then
                starts = starts or {}
                starts[i] = true
            end
        end
    end
    return starts
end

local function trailingPunctuation(text, tokens, start, finish)
    local last = finish
    while last > start and sentenceJoins[tokens[last].key] do last = last - 1 end
    local punctuation = last < finish and tokenText(text, tokens, last + 1, finish) or ""
    return last, punctuation
end

local function withoutSentenceEnd(value)
    return (value:gsub("…$", ""):gsub("[.!?]+$", ""))
end

local function addressed(text, tokens, direction, start, finish, resolveCore)
    local last, punctuation = trailingPunctuation(text, tokens, start, finish)
    for comma = last - 1, math.max(start + 1, last - 12), -1 do
        if tokens[comma].key == "," then
            local address, ending = ns.Engine.Dictionary.longest(tokens, comma + 1, direction, "addresses", last, "vocative")
            if address and ending == last and address.category == "addresses" then
                local core = resolveCore(start, comma - 1)
                local rendered = ns.Engine.Grammar.render("{address:vocative}", {address={term=address}}, direction)
                if core and rendered then
                    local slots = {}
                    for name, value in pairs(core.slots or {}) do slots[name] = value end
                    slots.finalAddress = {term=address}
                    local rule = {intent=core.rule.intent or core.rule.id, sourceRefs=core.rule.sourceRefs,
                        imperative=core.rule.imperative, unknownSpans=core.rule.unknownSpans}
                    return withoutSentenceEnd(core.text) .. ", " .. rendered .. punctuation, rule, slots
                end
            end
            break
        end
    end
end

function P.addressedExact(text, tokens, direction, first, last)
    return addressed(text, tokens, direction, first or 1, last or #tokens, function(start, finish)
        local exact = ns.Data.exact[direction][ns.Engine.Normalize.key(tokenText(text, tokens, start, finish))]
        if exact then return {text=exact.text, rule=exact} end
    end)
end

local function lowerStart(value)
    if value:match("^I[^%w]") or value == "I" then return value end
    local leadingWord = value:match("^[A-Z][A-Za-z]+")
    if leadingWord and leadingWord:find("[A-Z]", 2) then return value end
    local first = value:match("^[\192-\223][\128-\191]") or value:sub(1, 1)
    return ns.Engine.Normalize.word(first) .. value:sub(#first + 1)
end

function P.hasExactOpening(text, tokens, direction)
    local composition = ns.Data.composition and ns.Data.composition[direction]
    local expressions = ns.Data.exact[direction]
    if not composition or tokens[1].protected then return false end
    for index = 2, math.min(12, #tokens - 1) do
        local _, sentence = joinAt(text, tokens, index, composition.joins)
        if sentence or composition.joins[tokens[index].key] then
            local finish = tokens[index - 1].key == "," and index - 2 or index - 1
            local key = finish > 0 and ns.Engine.Normalize.key(tokenText(text, tokens, 1, finish))
            if expressions[key] then return true end
        end
    end
    return false
end

function P.compose(text, tokens, direction, grammarFallback, sentenceBudget, annotation, accept)
    local composition = ns.Data.composition and ns.Data.composition[direction]
    if not composition or #tokens == 0 or #tokens > 96 then return nil end
    local prefixes, joins = composition.prefixes, composition.joins
    local inferred = grammarFallback and inferredStarts(text, tokens, direction)
    local function prefixAt(start, limit)
        local ending, prefix = start, prefixes[tokens[start].key]
        local second = tokens[start + 1] and tokens[start + 1].key == "," and start + 2 or start + 1
        if second <= limit and not tokens[second].protected then
            local pair = prefixes[tokens[start].key .. " " .. tokens[second].key]
            if pair then prefix, ending = pair, second end
        end
        if not prefix then return start end
        local separator = tokens[ending + 1] and tokens[ending + 1].key
        local joined = separator == "," or dashJoins[separator] or separator == "-" and spacedDash(tokens, ending + 1)
        return ending + (joined and 2 or 1), prefix
    end
    local first, prefix = prefixAt(1, #tokens)
    if prefix then
        if first > #tokens then return nil end
    else
        local found
        for i = 2, #tokens - 1 do
            if joinAt(text, tokens, i, joins) or tokens[i].key == "," then found = true; break end
        end
        if not found and not inferred then return nil end
    end
    local attempts, memo = 24, {}
    local sentenceEndAt
    local annotationDocument = annotation and {text=text, tokens=tokens, direction=direction}
    local function translateClause(start, finish)
        if start > finish or sentenceEndAt and finish > sentenceEndAt[start] then return nil end
        local row = memo[start]
        if row and row[finish] ~= nil then return row[finish] or nil end
        if attempts == 0 or sentenceBudget and sentenceBudget.remaining == 0 then return nil end
        attempts = attempts - 1
        if sentenceBudget then sentenceBudget.remaining = sentenceBudget.remaining - 1 end
        if not row then row = {}; memo[start] = row end
        local output, rule, slots
        -- The entry point already checked exact, structural and grammar matches for the full message.
        if start ~= 1 or finish ~= #tokens then
            local key = ns.Engine.Normalize.key(tokenText(text, tokens, start, finish))
            local exact = ns.Data.exact[direction][key]
            if exact then output, rule = exact.text, exact
            else
                output, rule, slots = P.addressedExact(text, tokens, direction, start, finish)
                if not output and grammarFallback then output, rule, slots = grammarFallback(start, finish) end
                if not output then output, rule, slots = P.translate(text, tokens, direction, start, finish) end
                if annotationDocument and finish > start and (not output or rule.imperative) then
                    local last = trailingPunctuation(text, tokens, start, finish)
                    local descriptor, ending = ns.Engine.Dictionary.literal(annotationDocument, start)
                    if descriptor and descriptor.text and ending == last and ending > start then
                        output, slots = descriptor.text, nil
                        rule = {intent="annotation", sourceRefs=descriptor.sourceRefs}
                    end
                end
            end
            if not output then
                local last = trailingPunctuation(text, tokens, start, finish)
                local name, nameEnd = ns.Engine.Dictionary.longest(tokens, start, direction, "characters", last)
                local features = name and name.features
                if features and features.verbatim and nameEnd == last and (not features.caseSensitiveEnglish
                    or tokenText(text, tokens, start, last) == name.en) then
                    output = tokenText(text, tokens, start, finish)
                    rule = {intent="preserve_name", sourceRefs=name.sourceRefs}
                end
            end
        end
        if not output then
            output, rule, slots = addressed(text, tokens, direction, start, finish, translateClause)
        end
        if not output then
            local rest, lead = prefixAt(start, finish)
            if lead then
                local matched = translateClause(rest, finish)
                if matched then output, rule, slots = lead .. lowerStart(matched.text), matched.rule, matched.slots end
            end
        end
        local match = output and (not accept or accept(output, start, finish))
            and {text = output, rule = rule, slots = slots} or false
        row[finish] = match
        return match or nil
    end
    local function endBefore(joinIndex)
        return tokens[joinIndex - 1].key == "," and joinIndex - 2 or joinIndex - 1
    end
    local function composeSentences()
        if sentenceBudget then return nil end
        local ends = {}
        for index = 2, #tokens - 1 do
            local key, previous = tokens[index].key, tokens[index - 1]
            local closesSentence = key == ")" and sentenceJoins[previous.key]
                and tokens[index].first == previous.last + 1
            if P.sentenceBoundary(text, tokens, index)
                or closesSentence and tokens[index + 1].first > tokens[index].last + 1 then
                -- The shared clause-attempt budget also bounds paragraphs with many short sentences.
                ends[#ends + 1] = index
            end
        end
        if #ends == 0 and tokens[1].key ~= "(" then return nil end
        ends[#ends + 1] = #tokens
        if grammarFallback and ns.Linguistics then
            local language = direction == "en-uk" and "en" or "uk"
            local width = ns.Linguistics.grammar.indexWidths[language].degrees
            local degreeDocument
            local start, part = 1, 1
            while part < #ends do
                local ending = ends[part]
                local pause = tokens[ending].key == "…" and ending
                    or ending - 2 >= start and P.ellipsisEnd(tokens, ending - 2, ending) == ending and ending - 2
                if pause and not tokens[ending + 1].protected and not P.startsWithCapital(text, tokens[ending + 1]) then
                    degreeDocument = degreeDocument or {tokens=tokens, direction=direction}
                    for first = math.max(start, pause - width), pause - 1 do
                        local _, last = ns.Engine.Phrases.propertyDegreeAt(degreeDocument, first, pause - 1)
                        if last == pause - 1 then
                            local continuation = translateClause(start, ends[part + 1])
                            if continuation and continuation.rule.propertyPause == ending then
                                table.remove(ends, part)
                                ending = ends[part]
                            end
                            break
                        end
                    end
                end
                start, part = ending + 1, part + 1
            end
        end
        local opening, closing = {}, {}
        local part, depth, startPart = 1, 0, nil
        local startToken = 1
        for index, token in ipairs(tokens) do
            if token.key == "(" then
                if depth == 0 then startPart = index == startToken and part or nil end
                depth = depth + 1
            elseif token.key == ")" and depth > 0 then
                depth = depth - 1
                if depth == 0 and startPart
                    and (index == ends[part] or index == trailingPunctuation(text, tokens, startToken, ends[part])) then
                    opening[startPart], closing[part] = true, index
                end
            end
            if index == ends[part] then part, startToken = part + 1, index + 1 end
        end
        if #ends <= 2 and not next(opening) then return nil end
        local matches, parts, fragments, partials, start, complete = {}, {}, {}, {}, 1, true
        local nestedBudget = {remaining=16}
        local confirmedEnds = {}
        for part, segmentEnd in ipairs(ends) do
            local first = start + (opening[part] and 1 or 0)
            local finish = closing[part] and closing[part] - 1 or segmentEnd
            local match = translateClause(first, finish)
            if not match and grammarFallback and nestedBudget.remaining > 0 and finish - first >= 3 then
                local offset = first - 1
                local sentence = {unpack(tokens, first, finish)}
                local acceptSentence = accept and function(value, first, last)
                    return accept(value, first + offset, last + offset)
                end
                local value, subclauses, subfragments = P.compose(text, sentence, direction, function(first, last)
                    return grammarFallback(first + offset, last + offset)
                end, nestedBudget, opening[part] and closing[part], acceptSentence)
                if value then
                    local refs, slots = {}, {}
                    local unknown, dependency
                    for _, clause in ipairs(subclauses) do
                        for _, ref in ipairs(clause.rule.sourceRefs or {}) do refs[#refs + 1] = ref end
                        for _, slot in pairs(clause.slots or {}) do slots[#slots + 1] = slot end
                        dependency = dependency or clause.rule.dependency
                        if clause.rule.unknownSpans then
                            unknown = unknown or {}
                            for _, span in ipairs(clause.rule.unknownSpans) do unknown[#unknown + 1] = span end
                        end
                    end
                    match = {text=value, rule={intent="composition", sourceRefs=refs, unknownSpans=unknown,
                        dependency=dependency}, slots=slots}
                elseif subfragments then
                    for localFirst, fragment in pairs(subfragments) do
                        fragment.last = fragment.last + offset
                        partials[localFirst + offset] = fragment
                    end
                end
            end
            if match then
                local value = match.text
                if sentenceJoins[tokens[finish].key] then
                    local punctuation = finish
                    while punctuation > first and sentenceJoins[tokens[punctuation - 1].key]
                        and tokens[punctuation].first == tokens[punctuation - 1].last + 1 do
                        punctuation = punctuation - 1
                    end
                    value = withoutSentenceEnd(value) .. tokenText(text, tokens, punctuation, finish)
                end
                if opening[part] then value = "(" .. value end
                if closing[part] then
                    if not sentenceJoins[tokens[finish].key] then value = withoutSentenceEnd(value) end
                    value = value .. tokenText(text, tokens, closing[part], segmentEnd)
                end
                matches[part], parts[part] = match, value
                if start > 1 and tokens[start - 1].last + 1 == tokens[start].first then value = " " .. value end
                fragments[start] = {text=value, last=segmentEnd, rule=match.rule, slots=match.slots}
            else
                complete = false
            end
            if segmentEnd < #tokens then
                local stop, previous = tokens[segmentEnd], tokens[segmentEnd - 1]
                local labelSeparator = tokens[segmentEnd + 2]
                local continuation = labelSeparator and labelSeparator.key == ":"
                local singlePeriod = stop.key == "." and not (previous.key == "." and previous.last + 1 == stop.first)
                if not continuation and (stop.key == "?" or stop.key == "!" or match and singlePeriod) then
                    confirmedEnds[#confirmedEnds + 1] = segmentEnd
                end
            end
            start = segmentEnd + 1
        end
        if complete then return table.concat(parts, " "), matches end
        if #confirmedEnds > 0 then
            -- Retry clauses within a sentence. An unconfirmed period or pause may still join text.
            sentenceEndAt = {}
            confirmedEnds[#confirmedEnds + 1] = #tokens
            local first = 1
            for _, ending in ipairs(confirmedEnds) do
                for index = first, ending do sentenceEndAt[index] = ending end
                first = ending + 1
            end
        end
        return nil, nil, fragments, partials
    end
    local paragraph, sentences, sentenceFragments, sentencePartials = composeSentences()
    if paragraph then return paragraph, sentences end
    local function independentStart(match, start)
        local unit = match and match.rule.sentenceUnit
        -- A title such as “No Rules” is also a nominal exclusion in isolation.
        return unit and (unit ~= "exclusion" or not inferred[start + 1])
    end
    local chart = {}
    local function parseFrom(start, depth, noCommand, needQuestion, allowInference)
        local states = chart[start]
        if not states then states = {}; chart[start] = states end
        local state = depth * 8 + (allowInference and 4 or 0) + (noCommand and 2 or 0) + (needQuestion and 1 or 0)
        if states[state] ~= nil then return states[state] or nil end
        local match = translateClause(start, #tokens)
        if match and (not noCommand or not match.rule.imperative) and (not needQuestion or match.text:sub(-1) == "?") then
            local result = {match=match, last=#tokens}
            states[state] = result
            return result
        end
        if depth == 1 then states[state] = false; return nil end
        for i = start + 1, #tokens - 1 do
            local join, sentence = joinAt(text, tokens, i, joins)
            local inferredJoin = not join and allowInference and inferred[i + 1]
            if inferredJoin then join, sentence = ". ", true end
            if join then
                local finish = inferredJoin and i or endBefore(i)
                if sentence and not inferredJoin then
                    local punctuation = i
                    while punctuation > start + 1 and sentenceJoins[tokens[punctuation - 1].key]
                        and tokens[punctuation].first == tokens[punctuation - 1].last + 1 do punctuation = punctuation - 1 end
                    local marks = tokenText(text, tokens, punctuation, i)
                    finish = punctuation - 1
                    if marks == "..." then join = marks .. " " end
                end
                local matched = translateClause(start, finish)
                local left = matched and matched.text
                local sourceEnd = tokens[finish] and tokens[finish].key
                local sourceHasEnd = sourceEnd == "?" or sourceEnd == "!"
                local questionBeforeComma = left and matched.rule.question and tokens[i].key == ","
                    and not sourceHasEnd and left:sub(-1) == "?"
                if questionBeforeComma then join, sentence = "? ", true end
                local alternativeQuestion = left and not sourceHasEnd and alternatives[tokens[i].key]
                    and left:sub(-1) == "?"
                if left and (not inferredJoin or matched.rule.sentenceUnit) and (not noCommand or not matched.rule.imperative)
                    and (sentence or alternativeQuestion or (not sourceHasEnd and not left:match("[?!]$"))) then
                    local right = parseFrom(i + 1, depth - 1,
                        not inferredJoin and sharedPredicateJoins[tokens[i].key] and not matched.rule.imperative,
                        needQuestion or alternativeQuestion, allowInference)
                    if right and (not inferredJoin or independentStart(right.match, i + 1)) then
                        if grammarFallback and direction == "uk-en" and not (sentence or needQuestion)
                            and tokens[i].key == "," and tokens[i + 1].key == "що" and right.match.rule.question then
                            local united = translateClause(start, right.last)
                            if united and united.rule.reportedContent then
                                local result = {match=united, last=right.last, join=right.join, sentence=right.sentence,
                                    alternative=right.alternative, next=right.next}
                                states[state] = result
                                return result
                            end
                        end
                        if inferredJoin and left:match("[!?]$") then join = left:sub(-1) .. " " end
                        local unit = matched.rule.sentenceUnit
                        if not sentence and tokens[i].key == "," and (unit == "clause" or unit == "restriction")
                            and right.match.rule.sentenceUnit == "clause" and right.match.rule.earlierPhase then
                            join, sentence = ". ", true
                        end
                        if direction == "en-uk" and tokens[i].key == "and" and matched.rule.imperative
                            and right.match.rule.initialWhen then join = ", а " end
                        local result = {match=matched, last=finish, join=join, sentence=sentence,
                            alternative=alternativeQuestion, next=right}
                        states[state] = result
                        return result
                    end
                end
            end
        end
        states[state] = false
    end
    local path = parseFrom(first, 8) or inferred and parseFrom(first, 8, nil, nil, true)
    if path then
        local parts, matches, sentenceStart = {}, {}, true
        while path do
            local value = sentenceStart and path.match.text or lowerStart(path.match.text)
            if path.join then
                if path.sentence or path.alternative then value = withoutSentenceEnd(value)
                else value = value:gsub("%.$", "") end
            end
            parts[#parts + 1], matches[#matches + 1] = value, path.match
            if path.join then parts[#parts + 1] = path.join end
            sentenceStart, path = path.sentence, path.next
        end
        local output = table.concat(parts)
        if prefix then output = prefix .. lowerStart(output) end
        return output, matches
    end

    -- A failed composition can still contribute complete clauses to a preview.
    -- Keep their original boundaries so the caller can preserve every gap.
    local starts, ends, sentenceEnds, linked = {first}, {}, {}, {}
    local inferredEnds, inferredBeginnings, fragments = {}, {}, {}
    local sentenceStart = 1
    for i = first + 1, #tokens - 1 do
        local join, sentence = joinAt(text, tokens, i, joins)
        local inferredJoin
        if not join and inferred and inferred[i + 1] then
            local complete = translateClause(starts[sentenceStart], i)
            if complete and complete.rule.sentenceUnit then
                for last = i + 2, math.min(i + 4, #tokens) do
                    local following = translateClause(i + 1, last)
                    local nextToken = tokens[last + 1]
                    local repeatExclusion = nextToken and ns.Engine.Phrases.exclusionMarker(direction, nextToken.key)
                    if following and following.rule.sentenceUnit == "exclusion" and independentStart(following, i + 1)
                        and (not nextToken or sentenceJoins[nextToken.key] or repeatExclusion) then
                        inferredJoin, join, sentence = true, ". ", true
                        inferredEnds[i], inferredBeginnings[i + 1] = true, true
                        if repeatExclusion then
                            fragments[i + 1] = {text=withoutSentenceEnd(following.text) .. ",", last=last,
                                rule=following.rule, slots=following.slots}
                        end
                        break
                    end
                end
            end
        end
        if join then
            ends[#ends + 1] = inferredJoin and i or endBefore(i)
            if sharedPredicateJoins[tokens[i].key] then linked[i + 1] = starts[#starts] end
            starts[#starts + 1] = i + 1
            if sentence then
                for segment = sentenceStart, #ends do sentenceEnds[segment] = #ends end
                sentenceStart = #ends + 1
            end
        end
    end
    if #starts < 2 then
        for start, fragment in pairs(sentencePartials or {}) do sentenceFragments[start] = fragment end
        return nil, nil, sentenceFragments
    end
    ends[#ends + 1] = #tokens
    local segment, accepted = 1, 0
    while segment <= #starts and accepted < 4 and attempts > 0 do
        local start = starts[segment]
        local nextSegment = segment + 1
        for block = sentenceEnds[segment] or #ends, segment, -1 do
            if attempts == 0 then break end
            local finish = ends[block]
            local match = translateClause(start, finish)
            if match then
                local last = finish
                while last > start and tokens[last].key:match("^[.!?]$") do last = last - 1 end
                local previous = linked[start] and fragments[linked[start]]
                if linked[start] and match.rule.imperative and not (previous and previous.rule and previous.rule.imperative) then
                    fragments[start] = {last=last, preserve="unresolved-predicate-scope"}
                    nextSegment = block + 1
                    break
                end
                local sourceEnd = tokens[last + 1]
                local hasEnd = sourceEnd and sentenceJoins[sourceEnd.key]
                local replacement = inferredEnds[last] and match.text:gsub("([^.!?])$", "%1.")
                    or match.text:gsub(hasEnd and "[.!?]+$" or "[.!]+$", "")
                if sourceEnd and sourceEnd.key == "," and match.rule.question and replacement:sub(-1) == "?" then
                    last = last + 1
                    inferredBeginnings[last + 1] = true
                end
                if start ~= 1 and not inferredBeginnings[start] then
                    local before = tokens[start - 1]
                    if not sentenceJoins[before.key] then replacement = lowerStart(replacement)
                    elseif before.last + 1 == tokens[start].first then replacement = " " .. replacement end
                end
                fragments[start] = {text = replacement, last = last, rule = match.rule, slots = match.slots}
                accepted, nextSegment = accepted + 1, block + 1
                break
            end
        end
        segment = nextSegment
    end
    for start, sentence in pairs(sentenceFragments or {}) do
        for first, old in pairs(fragments) do
            if first <= sentence.last and old.last >= start then fragments[first] = nil end
        end
        fragments[start] = sentence
    end
    for start, partial in pairs(sentencePartials or {}) do
        local covered
        for first, old in pairs(fragments) do
            if first <= partial.last and old.last >= start then covered = true; break end
        end
        if not covered then fragments[start] = partial end
    end
    return nil, nil, next(fragments) and fragments or nil
end
local function slot(text, tokens, index, name, direction, limit)
    if index > limit then return nil end
    local token = tokens[index]
    if category[name] then
        local start = index
        if category[name] == "goods" then
            if token.protected then
                local raw = tokenText(text, tokens, index, index)
                local kind = ns.Engine.Markup.linkKind(raw)
                if kind == "item" or kind == "spell" then return {raw = raw}, index + 1 end
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
            local partitive = index > start and token.key == "some" and term.features and term.features.mass
                and forms.genitiveSingular ~= nil
            return {term = term, raw = raw, plural = plural, partitive = partitive}, last + 1
        end
    elseif name == "count" then
        if token.key:match("^%d+$") and #token.key <= 3 and tonumber(token.key) > 0 then
            return {raw = token.key}, index + 1
        end
    elseif name == "item" or name == "trade" or name == "quest" then
        -- Scoped links distinguish service offers and quest requests from sales.
        if not token.protected then return nil end
        local raw = tokenText(text, tokens, index, index)
        local kind = ns.Engine.Markup.linkKind(raw)
        -- Legacy {item} also serves spell recipes, but never a profession or quest.
        if kind == name or (name == "item" and kind == "spell") then return {raw = raw}, index + 1 end
    elseif name == "offerPrice" then
        local grammar = ns.Engine.Grammar
        local parts, after = grammar.offerPriceAt({text=text, tokens=tokens}, index, limit)
        if parts then return {raw=grammar.offerPriceText(parts, true), parts=parts}, after end
    elseif name == "price" or name == "time" then
        if token.protected then return nil end
        local pattern = name == "price" and "^(%d+[%.,]?%d*)%s*([gsc])$" or "^(%d+[%.,]?%d*)%s*([mh])$"
        for last = math.min(limit, index + 4), index, -1 do
            local raw = tokenText(text, tokens, index, last)
            local amount, unit = raw:lower():match(pattern)
            if amount then return {raw = raw, amount = amount, unit = unit}, last + 1 end
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
local function selectMatch(matches, text, tokens, direction, first, last, selected, selectedRule, selectedSlots, ambiguous)
    local priority = selectedRule and (selectedRule.priority or 100)
    for _, rule in ipairs(matches) do
        local currentPriority = rule.priority or 100
        if not selected or currentPriority >= priority then
            local output, slots = matchRule(rule, text, tokens, direction, first, last)
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
    return selected, selectedRule, selectedSlots, ambiguous
end

function P.translate(text, tokens, direction, first, last)
    first, last = first or 1, last or #tokens
    if first > last then return nil end
    local node = ns.Data.rules[direction]
    local selected, selectedRule, selectedSlots, ambiguous
    if node.leading then
        local token = tokens[first]
        local bucket
        if token.protected then
            if token.linkKind == "item" or token.linkKind == "spell" then bucket = node.leading.item
            else bucket = node.leading.link end
        else
            local byte = token.key:byte()
            if byte and byte >= 48 and byte <= 57 then bucket = node.leading.price end
        end
        if bucket then
            selected, selectedRule, selectedSlots, ambiguous = selectMatch(bucket.matches, text, tokens, direction, first, last)
        end
    end
    for i = first, last do
        if not node.next or tokens[i].protected then break end
        node = node.next[tokens[i].key]
        if not node then break end
        if node.matches then
            selected, selectedRule, selectedSlots, ambiguous = selectMatch(node.matches, text, tokens, direction, i + 1, last,
                selected, selectedRule, selectedSlots, ambiguous)
        end
    end
    if selected and not ambiguous then return selected, selectedRule, selectedSlots end
end
