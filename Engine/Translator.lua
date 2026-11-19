local _, ns = ...
local E = {}; ns.Translator = E
local C, N = ns.Compat, ns.Engine.Normalize
local cache, queue, head, tail, bytes, count = {}, {}, 1, 0, 0, 0
function E.clearCache()
    cache, queue, head, tail, bytes, count = {}, {}, 1, 0, 0, 0
end
local function cachedKey(text, direction, context)
    if not context or not C.public(context.event, context.line, context.author, context.sender, context.language, context.target) then return nil end
    if type(context.line) ~= "number" or context.line <= 0 or context.line % 1 ~= 0 then return nil end
    local parts = {direction, ns.Data.manifest.version, tostring(ns.Database.revision or 0), text}
    for _, name in ipairs({"event", "line", "author", "sender", "language", "target"}) do
        local value = context[name]
        if value ~= nil and type(value) ~= "string" and type(value) ~= "number" then return nil end
        local raw = value == nil and "" or tostring(value)
        parts[#parts + 1] = type(value) .. ":" .. #raw .. ":" .. raw
    end
    for i = 1, 4 do parts[i] = #parts[i] .. ":" .. parts[i] end
    return table.concat(parts, "|")
end
local function store(key, result)
    if not key then return end
    local cost = #key + #result.text + 512 + #result.unknownSpans * 128 + #result.matchedTerms * 128
    if cost > ns.Limits.cacheBytes then return end
    while count >= ns.Limits.cacheEntries or bytes + cost > ns.Limits.cacheBytes do
        local oldKey = queue[head]
        local old = cache[oldKey]
        cache[oldKey], queue[head], head = nil, nil, head + 1
        bytes, count = bytes - old.cost, count - 1
    end
    -- Compact after bounded churn; queue indices must not grow for the session.
    if head > ns.Limits.cacheEntries * 2 then
        local compact = {}
        for i = head, tail do compact[#compact + 1] = queue[i] end
        queue, head, tail = compact, 1, #compact
    end
    tail = tail + 1; queue[tail] = key
    cache[key], bytes, count = {result = result, cost = cost}, bytes + cost, count + 1
end
local function unchanged(text, reason)
    local unknown = {}
    if reason == "unsupported" and #text > 0 then unknown[1] = {first=1,last=#text} end
    return {text = text, mode = "unchanged", matchedTerms = {}, unknownSpans = unknown, sourceRefs = {}, reason = reason}
end
local function addRefs(refs, seen, additions)
    for _, ref in ipairs(additions) do
        if not seen[ref] then refs[#refs + 1], seen[ref] = ref, true end
    end
end
local function addClause(matched, refs, seen, rule, slots)
    addRefs(refs, seen, rule.sourceRefs)
    if not slots then return end
    for _, value in pairs(slots) do
        if value.term then
            matched[#matched + 1] = value.term.id
            addRefs(refs, seen, value.term.sourceRefs)
        end
    end
end
local function grammarClause(document, first, last)
    if last - first >= 64 then return nil end
    local tail, colon = document.tokens[last], document.tokens[last - 1]
    local emote
    if last > first and colon.key == ":" and tail.first == colon.last + 1
        and (tail.key == ")" or tail.key == "(" or tail.key == "d") then
        emote = document.text:sub(colon.first, tail.last)
        last = last - 2
    end
    local punctuation, endToken = nil, last
    while last >= first and (document.tokens[last].key:match("^[.!?]$") or document.tokens[last].key == "…") do
        local key = document.tokens[last].key
        if not punctuation or key == "?" then punctuation = key end
        last = last - 1
    end
    if punctuation == "." and endToken - last == 3 then
        local raw = document.text:sub(document.tokens[last + 1].first, document.tokens[endToken].last)
        if raw == "..." then punctuation = raw end
    end
    local prefix
    local lead = document.tokens[first]
    if first + 1 <= last and lead.key == "…" then
        prefix = document.text:sub(lead.first, document.tokens[first + 1].first - 1)
        first = first + 1
    elseif first + 3 <= last and lead.key == "." and document.tokens[first + 1].key == "."
        and document.tokens[first + 2].key == "." and document.tokens[first + 2].last == lead.first + 2 then
        prefix = document.text:sub(lead.first, document.tokens[first + 3].first - 1)
        first = first + 3
    end
    if last < first then return nil end
    local parsed = ns.Engine.ClauseAnalysis.parse(document, first, last)
    if not parsed then return nil end
    local output = ns.Engine.ClauseGeneration.render(parsed, document.direction, punctuation)
    if output and prefix then output = prefix .. output end
    if output and emote then output = output .. " " .. emote end
    if output then
        local slots
        for _, tree in ipairs(parsed.trees) do
            local address = tree.addressee or tree.recipient
            if address and address.term then
                slots = slots or {}
                slots[#slots + 1] = address
            end
        end
        return output, {intent=parsed.trees[1].kind, imperative=parsed.trees[1].imperative == true,
            initialWhen=parsed.prefix and parsed.prefix.id == "when" and #parsed.trees > 1,
            sourceRefs=ns.Linguistics.manifest.sourceRefs, dependency=parsed.dependency == true}, slots
    end
end
local function placePhrase(document, first, fragments)
    local phrase, after = ns.Engine.Phrases.preposition(document, first, #document.tokens)
    local term = phrase and phrase.object.term
    if not term or term.category ~= "places" then return nil end
    for i = first + 1, after - 1 do
        if (fragments and fragments[i]) or (document.preserve and document.preserve[i]) then return nil end
    end
    phrase.targetUk = phrase.rule.literalTargetUk
    local value, marker = ns.Engine.ClauseGeneration.preposition(phrase, document.direction == "uk-en")
    if value and marker and marker ~= "" then return term, after - 1, marker .. " " .. value end
end

local function dependencyFragments(document, fragments)
    local tokens = document.tokens
    if not ns.Engine.UDPipe or not ns.Engine.UDPipe.analyzeDocumentWithTags then return fragments, false end
    local blocked, lastFragment, first, attempts, used = {}, 0, 1, 0, false
    for index = 1, #tokens do
        local fragment = fragments and fragments[index] or document.preserve and document.preserve[index]
        if fragment then lastFragment = math.max(lastFragment, fragment.last) end
        if index <= lastFragment then blocked[index] = true end
    end
    local phrases, generation = ns.Engine.Phrases, ns.Engine.ClauseGeneration
    local english = document.direction == "uk-en"
    for ending = 1, #tokens do
        local token = tokens[ending]
        local sentenceEnd = not token.protected and token.key:match("^[.!?]$")
            and (ending == #tokens or tokens[ending + 1].first > token.last + 1)
        if sentenceEnd or ending == #tokens then
            if ending - first >= 2 and ending - first < 32 and attempts < 3 then
                local open, occupied = 0, false
                for index = first, ending do
                    if blocked[index] then occupied = true end
                    if not blocked[index] and not tokens[index].protected then open = open + 1 end
                end
                if open >= 2 then
                    attempts = attempts + 1
                    local arcs, words = ns.Engine.UDPipe.analyzeDocumentWithTags(document, first, ending)
                    local rendered
                    if arcs and words and not occupied then
                        local marker = sentenceEnd and token.key or nil
                        local limit = marker and ending - 1 or ending
                        local parsed = ns.Engine.ClauseAnalysis.parseDependencies(document, first, limit, arcs, words)
                        local output = parsed and generation.render(parsed, document.direction, marker)
                        local original = phrases.raw(document, first, ending)
                        if output and N.key(output) ~= N.key(original) then
                            local intent = #parsed.trees > 1 and "composition" or parsed.trees[1].kind
                            if first == 1 and ending == #tokens then return fragments, false, output, intent end
                            fragments = fragments or {}
                            fragments[first] = {text=output, last=ending, rule={sourceRefs=ns.Linguistics.manifest.sourceRefs}}
                            used, rendered = true, true
                        end
                    end
                    local groups = not rendered and arcs and words
                        and phrases.dependencyNominals(document, first, arcs, words, blocked) or {}
                    local previous = 0
                    for _, group in ipairs(groups) do
                        if group.first > previous then
                            local nominal = group.preposition and group.phrase.object or group.phrase
                            local value
                            if group.preposition then
                                local object, marker = generation.preposition(group.phrase, english)
                                if object and marker then value = marker == "" and object or marker .. " " .. object end
                            else
                                value = generation.noun(group.phrase, english, group.case)
                            end
                            local original = phrases.raw(document, group.first, group.last)
                            if value and value ~= "" and N.key(original) ~= N.key(value) then
                                local _, literalEnd = ns.Engine.Dictionary.literal(document, group.first, fragments)
                                if not literalEnd or literalEnd <= group.last then
                                    if group.first == first then value = N.upperStart(value) end
                                    fragments = fragments or {}
                                    fragments[group.first] = {text=value, last=group.last,
                                        rule={sourceRefs=ns.Linguistics.manifest.sourceRefs},
                                        slots=nominal.term and {object={term=nominal.term}} or nil}
                                    previous, used = group.last, true
                                end
                            end
                        end
                    end
                end
            end
            first = ending + 1
        end
    end
    return fragments, used
end

local function compute(text, direction)
    local tokens = ns.Engine.Tokenizer.scan(text)
    if not tokens or #tokens == 0 then return unchanged(text, "token-limit-or-empty") end
    local exact = ns.Data.exact[direction][N.key(text)]
    if exact then
        return {text = exact.text, mode = "exact", intent = exact.id, matchedTerms = {}, unknownSpans = {}, sourceRefs = exact.sourceRefs}
    end
    local document = ns.Engine.Morphology.analyze(text, tokens, direction)
    local output, tree, syntaxFragments = ns.Engine.Syntax.translate(document)
    local rule, slots
    if tree then
        rule, slots = {intent=tree.kind, sourceRefs={"project-authored:apertium-pipeline-1"}}, tree.slots
    elseif not document.truncated and not document.ambiguities then
        output, rule, slots = ns.Engine.Parser.addressedExact(text, tokens, direction)
    end
    local clauses, fragments
    local general
    local grammarEnabled = ns.Linguistics and not document.truncated and not document.ambiguities
    local grammarFallback
    if grammarEnabled then
        grammarFallback = function(first, last)
            local value, structure = ns.Engine.Syntax.translateRange(document, first, last)
            if value then
                return value, {intent=structure.kind, sourceRefs={"project-authored:apertium-pipeline-1"}}, structure.slots
            end
            return grammarClause(document, first, last)
        end
    end
    local composedOpening
    if not output and not document.truncated and not document.ambiguities
        and ns.Engine.Parser.hasExactOpening(text, tokens, direction) then
        output, clauses, fragments = ns.Engine.Parser.compose(text, tokens, direction, grammarFallback)
        composedOpening = true
    end
    if not output and grammarEnabled then
        local rendered, grammarRule, grammarSlots = grammarClause(document, 1, #tokens)
        if rendered and N.key(rendered) ~= N.key(text) then
            output, rule, general, slots = rendered, grammarRule, true, grammarSlots
        end
    end
    if not output and not document.truncated and not document.ambiguities then
        output, rule, slots = ns.Engine.Parser.translate(text, tokens, direction)
    end
    if not output and not composedOpening and not document.truncated and not document.ambiguities then
        output, clauses, fragments = ns.Engine.Parser.compose(text, tokens, direction, grammarFallback)
    end
    if syntaxFragments and not output then
        fragments = fragments or {}
        for first, fragment in pairs(syntaxFragments) do
            -- Keep a translated sentence that already covers this opening.
            local sentence = fragments[first]
            if not (sentence and sentence.text and sentence.last > fragment.last) then
                for start, old in pairs(fragments) do
                    if start <= fragment.last and old.last >= first then fragments[start] = nil end
                end
                fragments[first] = fragment
            end
        end
    end
    if output then
        if clauses and N.key(output) == N.key(text) then return unchanged(text, "identical") end
        local matched, refs, seen = {}, {}, {}
        if clauses then
            for _, clause in ipairs(clauses) do addClause(matched, refs, seen, clause.rule, clause.slots) end
        else
            addClause(matched, refs, seen, rule, slots)
        end
        table.sort(matched)
        table.sort(refs)
        return {text = output, mode = "template", intent = clauses and "composition" or rule.intent,
            matchedTerms = matched, unknownSpans = {}, sourceRefs = refs,
            coverage = {complete=true, pipeline=clauses and "composition" or general and "grammar"
                or tree and "structural" or "legacy", dependency=rule and rule.dependency == true or nil}}
    end
    local usedDependency
    if grammarEnabled then
        local rendered, intent
        fragments, usedDependency, rendered, intent = dependencyFragments(document, fragments)
        if rendered then
            return {text=rendered, mode="template", intent=intent, matchedTerms={}, unknownSpans={},
                sourceRefs=ns.Linguistics.manifest.sourceRefs,
                coverage={complete=true, pipeline="grammar", dependency=true}}
        end
    end
    local chunks, matched, unknown, refs, refSeen, i, cursor = {}, {}, {}, {}, {}, 1, 1
    local reason, reasonEnd
    while i <= #tokens do
        local token = tokens[i]
        local fragment = fragments and fragments[i]
        local preserve = document.preserve and document.preserve[i]
        if fragment and fragment.preserve then
            preserve, fragment = {last=fragment.last, reason=fragment.preserve}, nil
        end
        if preserve then reason, reasonEnd = preserve.reason, preserve.last end
        local term, last, replacement
        if fragment then
            last, replacement = fragment.last, fragment.text
            addClause(matched, refs, refSeen, fragment.rule, fragment.slots)
        elseif not token.protected then
            term, last = ns.Engine.Dictionary.literal(document, i, fragments)
            if grammarEnabled and not (reasonEnd and i <= reasonEnd) and (not last or last == i) then
                local place, finish, value = placePhrase(document, i, fragments)
                if place then term, last, replacement = place, finish, value end
            end
            if not term then term, last = ns.Engine.Dictionary.general(document, i) end
            if term then
                replacement = replacement or term.features and term.features.verbatim and text:sub(token.first, tokens[last].last)
                    or term.text or (direction == "en-uk" and term.uk or term.en)
                matched[#matched + 1] = term.id
                addRefs(refs, refSeen, term.sourceRefs)
            end
        end
        if replacement then
            chunks[#chunks + 1] = text:sub(cursor, token.first - 1)
            chunks[#chunks + 1] = replacement
            cursor, i = tokens[last].last + 1, last + 1
        else
            unknown[#unknown + 1] = {first = token.first, last = token.last, protected = token.protected or false,
                reason = reasonEnd and i <= reasonEnd and reason or nil}
            i = i + 1
        end
    end
    if #chunks == 0 then return unchanged(text, "unsupported") end
    chunks[#chunks + 1] = text:sub(cursor)
    local translated = table.concat(chunks)
    if translated == text or N.key(translated) == N.key(text) then return unchanged(text, "identical") end
    return {text = translated, mode = "partial", matchedTerms = matched, unknownSpans = unknown, sourceRefs = refs,
        coverage = usedDependency and {complete=false, pipeline="dictionary", dependency=true} or nil}
end
function E.translate(text, direction, context)
    if C.secret(text) or C.secret(direction) then return nil end
    if type(text) ~= "string" or (direction ~= "en-uk" and direction ~= "uk-en") then return nil end
    if #text > ns.Limits.messageBytes then return unchanged(text, "byte-limit") end
    local key = cachedKey(text, direction, context)
    local entry = key and cache[key]
    if entry then return entry.result end
    local result = compute(text, direction)
    store(key, result)
    return result
end
