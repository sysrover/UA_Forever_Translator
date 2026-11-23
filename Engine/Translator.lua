local _, ns = ...
local E = {}; ns.Translator = E
local C, N, A = ns.Compat, ns.Engine.Normalize, ns.Engine.Acceptance
local neuralRuntime, neuralModel = ns.Engine.NeuralRuntime
local contextFields = {"event", "line", "author", "sender", "language", "target"}
local cache, queue, head, tail, bytes, count = {}, {}, 1, 0, 0, 0
function E.clearCache()
    cache, queue, head, tail, bytes, count = {}, {}, 1, 0, 0, 0
end
local function cachedKey(text, direction, context, neural)
    if not context or not C.public(context.event, context.line, context.author, context.sender, context.language, context.target) then return nil end
    if type(context.line) ~= "number" or context.line <= 0 or context.line % 1 ~= 0 then return nil end
    if neural then
        -- The translation uses the original text. Incoming still checks and displays each chat line separately.
        for _, name in ipairs(contextFields) do
            local value = context[name]
            if value ~= nil and type(value) ~= "string" and type(value) ~= "number" then return nil end
        end
        return "neural|" .. ns.Data.manifest.version .. "|" .. tostring(ns.Database.revision or 0) .. "|" .. text
    end
    local parts = {direction, ns.Data.manifest.version, tostring(ns.Database.revision or 0), text}
    for _, name in ipairs(contextFields) do
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
local function byteSpan(tokens, range)
    return {first=tokens[range.first].first, last=tokens[range.last].last,
        protected=range.first == range.last and tokens[range.first].protected == true,
        reason=range.reason}
end
local function addClause(matched, refs, seen, rule, slots, unknown)
    addRefs(refs, seen, rule.sourceRefs)
    if rule.unknownSpans then
        for _, span in ipairs(rule.unknownSpans) do unknown[#unknown + 1] = span end
    end
    if not slots then return end
    for _, value in pairs(slots) do
        if value.term then
            matched[#matched + 1] = value.term.id
            addRefs(refs, seen, value.term.sourceRefs)
        end
    end
end
local function hasDegree(modifier)
    local degree = modifier and modifier.entry and modifier.entry.form.degree
    return degree == "comparative" or degree == "superlative"
end

local function grammarClause(document, first, last, inAside)
    if last - first >= 64 then return nil end
    local tail, beforeTail = document.tokens[last], document.tokens[last - 1]
    local emote, chatReaction
    local separated = last > first + 1 and beforeTail.first > document.tokens[last - 2].last + 1
    if last > first and tail.first == beforeTail.last + 1 and (
        beforeTail.key == ":" and (tail.key == ")" or tail.key == "(" or tail.key == "d")
        or beforeTail.key == ";" and tail.key == ")"
        or separated and (beforeTail.key == "x" and tail.key == ")" or beforeTail.key == "<" and tail.key == "3")) then
        emote = document.text:sub(beforeTail.first, tail.last)
        last = last - 2
    elseif last > first and not tail.protected and tail.key == "xd" and beforeTail.key:match("^[.!?]$")
        and tail.first > beforeTail.last + 1 then
        emote = document.text:sub(tail.first, tail.last)
        last = last - 1
    elseif last > first and not tail.protected and tail.key == "lol" and tail.first > beforeTail.last + 1
        and document.text:sub(tail.first, tail.last) == "lol" then
        emote, chatReaction, last = "lol", true, last - 1
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
    elseif first + 2 <= last and lead.key == "." and document.tokens[first + 1].key == "."
        and document.tokens[first + 1].first == lead.last + 1 then
        local ending = first + 2
        if ending < last and document.tokens[ending].key == "."
            and document.tokens[ending].last == lead.first + 2 then ending = ending + 1 end
        prefix = document.text:sub(lead.first, document.tokens[ending].first - 1)
        first = ending
    end
    if last < first then return nil end
    local aside = first + 2 <= last and document.tokens[first].key == "(" and document.tokens[last].key == ")"
    local innerPunctuation
    if aside then
        first, last = first + 1, last - 1
        local inner = document.tokens[last].key
        if inner:match("^[.!?]$") then innerPunctuation, last = inner, last - 1 end
    end
    if last < first then return nil end
    local analysis = ns.Engine.ClauseAnalysis
    local parsed = analysis.parse(document, first, last)
    if not parsed and ns.UDPipeModels then parsed = analysis.parseWithRecruitmentName(document, first, last) end
    local reported
    local firstTree = parsed and #parsed.trees == 1 and parsed.trees[1]
    if document.direction == "en-uk" and firstTree and firstTree.copula and firstTree.adjective then
        local following = document.tokens[last + 1]
        local modelEnd = following and following.key:match("^[.!?]$") and last + 1 or last
        parsed = analysis.disambiguatePassiveControl(document, first, last, modelEnd, firstTree.predicateIndex) or parsed
    end
    if document.direction == "uk-en" and (not parsed or parsed.trees[1].question or parsed.hypothetical) then
        local following = document.tokens[last + 1]
        local marker = innerPunctuation or punctuation
        if marker ~= "?" and not (following and following.key == "?") then
            local modelEnd = following and following.key:match("^[.!]$") and last + 1 or last
            reported = analysis.disambiguateReportedClause(document, first, last, modelEnd)
            parsed = reported or parsed
        end
    end
    if not parsed and not (aside or inAside or emote or prefix or punctuation == "?")
        and document.tokens[last].key == ")" then
        for opening = last - 1, first + 1, -1 do
            local token = document.tokens[opening]
            if token.key == ")" then break end
            if token.key == "(" then
                if token.first <= document.tokens[opening - 1].last + 1 then break end
                local note, noteRule = grammarClause(document, opening, last, true)
                if not (noteRule and noteRule.intent == "prohibition" and not noteRule.unknownSpans) then break end
                local main, rule, slots = grammarClause(document, first, opening - 1, true)
                if rule and rule.imperative and not (rule.question or rule.unknownSpans) then
                    rule.attachedRestriction = true
                    return main:gsub("[.!]+$", "") .. " " .. note .. (punctuation or ""), rule, slots
                end
                break
            end
        end
    end
    if not parsed then return nil end
    if chatReaction and not punctuation and not parsed.trees[#parsed.trees].content then return nil end
    local output = ns.Engine.ClauseGeneration.render(parsed, document.direction, innerPunctuation or punctuation)
    if output and aside then
        output = "(" .. output:gsub("[.!?]+$", "") .. (innerPunctuation or "") .. ")" .. (punctuation or "")
    end
    if output and prefix then output = prefix .. output end
    if output and emote then
        if chatReaction and not punctuation then output = output:gsub("%.$", "") end
        output = output .. " " .. emote
    end
    if output then
        local slots, propertyPause, unknown
        if parsed.untranslated then
            unknown = {}
            for _, span in ipairs(parsed.untranslated) do
                unknown[#unknown + 1] = byteSpan(document.tokens, {first=span.index, last=span.index, reason=span.reason})
            end
        end
        for _, tree in ipairs(parsed.trees) do
            if tree.unresolved then
                unknown = unknown or {}
                unknown[#unknown + 1] = byteSpan(document.tokens, tree.unresolved)
            end
            if tree.unresolvedRanges then
                unknown = unknown or {}
                for _, range in ipairs(tree.unresolvedRanges) do
                    unknown[#unknown + 1] = byteSpan(document.tokens, range)
                end
            end
            if tree.property and tree.property.pauseIndex then propertyPause = tree.property.pauseIndex end
            local address = tree.addressee or tree.recipient
            if address and address.term then
                slots = slots or {}
                slots[#slots + 1] = address
            end
        end
        local firstTree = parsed.trees[1]
        local frame = firstTree.verb and firstTree.verb.lexeme.frame
        local state = firstTree.predicateAdverb
        local predicate = firstTree.predicate
        local preferredInChat = frame and frame.preferredInChat or state and state.preferredInChat
            or firstTree.descriptionLabel or predicate and predicate.amount and predicate.amount.bound
        if not preferredInChat and firstTree.prepositions then
            for _, phrase in ipairs(firstTree.prepositions) do
                if phrase.rule.preferredInChat then preferredInChat = true; break end
            end
        end
        local graded
        if firstTree.copula then
            graded = hasDegree(firstTree.adjective)
            if not graded and firstTree.subject and firstTree.subject.adjectives then
                for _, modifier in ipairs(firstTree.subject.adjectives) do
                    if hasDegree(modifier) then graded = true; break end
                end
            end
        end
        local politeRequest
        local actor = firstTree.subject and firstTree.subject.pronoun
        if firstTree.question and (firstTree.modal == "can" or firstTree.modal == "could")
            and actor and (actor.person == 2 or actor.id == "someone") and firstTree.tense == "present"
            and not (firstTree.negative or firstTree.modalPerfect or firstTree.wh or firstTree.where
                or firstTree.why or firstTree.when) then
            for _, adverb in ipairs(firstTree.adverbs or {}) do
                if adverb.clausePoliteness then politeRequest = true; break end
            end
        end
        local sentenceUnit = firstTree.exclusion and "exclusion" or firstTree.restriction and "restriction" or
            ((firstTree.kind == "clause" or firstTree.kind == "need") and "clause")
        return output, {intent=firstTree.kind, imperative=firstTree.imperative == true,
            question=firstTree.question == true or parsed.hypothetical ~= nil,
            directQuestion=#parsed.trees == 1 and firstTree.question == true and not aside and not emote,
            modal=firstTree.modal or firstTree.ability, copular=firstTree.copula, graded=graded,
            politeRequest=politeRequest, preferredInChat=preferredInChat,
            sentenceUnit=sentenceUnit, propertyPause=propertyPause, unknownSpans=unknown,
            earlierPhase=firstTree.sentenceAdverb and firstTree.sentenceAdverb.earlierPhase
                or firstTree.predicateAdverb and firstTree.predicateAdverb.earlierPhase,
            initialWhen=parsed.prefix and parsed.prefix.id == "when" and #parsed.trees > 1,
            reportedContent=reported ~= nil, sourceRefs=ns.Linguistics.manifest.sourceRefs,
            dependency=parsed.dependency == true}, slots
    end
end
local function placePhrase(document, first, fragments, limit)
    local phrase, after = ns.Engine.Phrases.preposition(document, first, limit)
    local term = phrase and phrase.object.term
    if not term or term.category ~= "places" then return nil end
    for i = first + 1, after - 1 do
        if (fragments and fragments[i]) or (document.preserve and document.preserve[i]) then return nil end
    end
    phrase.targetUk = phrase.rule.literalTargetUk
    local value, marker = ns.Engine.ClauseGeneration.preposition(phrase, document.direction == "uk-en")
    if value and marker and marker ~= "" then return term, after - 1, marker .. " " .. value end
end

local function activityProfileFragment(document, first, limit, fragments)
    if first > 1 and not ns.Engine.Parser.sentenceBoundary(document.text, document.tokens, first - 1) then return nil end
    local phrases = ns.Engine.Phrases
    if not phrases.activityDescriptorPrefix(document, first, limit) then return nil end
    local noun, after = phrases.noun(document, first, limit, "nominative")
    if not (noun and noun.activityDescriptors) then return nil end
    for i = first + 1, after - 1 do
        if fragments and fragments[i] or document.preserve and document.preserve[i] then return nil end
    end
    local value = ns.Engine.ClauseGeneration.noun(noun, false, "nominative")
    if value then
        return {text=N.upperStart(value), last=after - 1, rule={sourceRefs=ns.Linguistics.manifest.sourceRefs}}
    end
end

local function clauseBeforeUnknownTail(document, first, ending)
    local tokens = document.tokens
    local punctuation = tokens[ending]
    local tail, previous = tokens[ending - 1], tokens[ending - 2]
    if not punctuation.key:match("^[.!?;]$") or tail.protected or previous.protected
        or punctuation.first ~= tail.last + 1 or tail.first <= previous.last + 1
        or not tail.key:match("^[%a\128-\255]+$") then return nil end
    local index = ending - 1
    local dictionary = ns.Engine.Dictionary
    if #ns.Engine.Lexicon.at(document, index) > 0 or dictionary.literal(document, index)
        or dictionary.general(document, index) then return nil end
    local output, rule, slots = grammarClause(document, first, index - 1)
    if output and rule.sentenceUnit == "clause" and not (rule.question or rule.imperative) then
        return {text=output:gsub("%.$", ""), last=index - 1, rule=rule, slots=slots}
    end
end

local function renderDependency(document, parsed, first, ending, arcs, words, marker, accept)
    if not parsed then return nil end
    local reason = A.rejectRoles(parsed, first, arcs, words)
    if reason then return nil, reason end
    return accept(ns.Engine.ClauseGeneration.render(parsed, document.direction, marker), first, ending)
end

local function dependencyFragments(document, fragments, verbatim, accept)
    local tokens = document.tokens
    if not ns.Engine.UDPipe or not ns.Engine.UDPipe.analyzeDocumentWithTags then return fragments, false end
    local blocked, preserveEnd, fragmentEnd, first, attempts, used = {}, 0, 0, 1, 0, false
    local crossing = {}
    local newVerbatim
    for index = 1, #tokens do
        local fragment = fragments and fragments[index]
        local preserve = document.preserve and document.preserve[index]
        if fragment then fragmentEnd = math.max(fragmentEnd, fragment.last) end
        if preserve then preserveEnd = math.max(preserveEnd, preserve.last) end
        if index < fragmentEnd then crossing[index] = true end
        if index <= preserveEnd or verbatim and verbatim[index] then blocked[index] = "preserve"
        elseif index <= fragmentEnd then blocked[index] = true end
    end
    local phrases, generation = ns.Engine.Phrases, ns.Engine.ClauseGeneration
    local english = document.direction == "uk-en"
    -- Closing chat punctuation can trail a complete sentence. Leave the suffix outside the graph.
    local finalSentenceEnd = #tokens
    while finalSentenceEnd > 1 and not tokens[finalSentenceEnd].protected
        and tokens[finalSentenceEnd].key:match("^[%)%]%}>]+$") do
        finalSentenceEnd = finalSentenceEnd - 1
    end
    for ending = 1, #tokens do
        local token = tokens[ending]
        local sentenceEnd = not token.protected and token.key:match("^[.!?]$")
            and (ending == finalSentenceEnd or ns.Engine.Parser.sentenceBoundary(document.text, tokens, ending))
        if sentenceEnd or ending == #tokens then
            if ending - first >= 2 and ending - first < 32 and attempts < 3 then
                local open, occupied, preservation = 0, false, crossing[first - 1] or crossing[ending]
                for index = first, ending do
                    if blocked[index] then occupied = true end
                    if blocked[index] == "preserve" then preservation = true end
                    if not blocked[index] and not tokens[index].protected then open = open + 1 end
                end
                if open >= 2 then
                    attempts = attempts + 1
                    local arcs, words = ns.Engine.UDPipe.analyzeDocumentWithTags(document, first, ending)
                    if document.checkpoint then document.checkpoint() end
                    local rendered
                    if arcs and words and not preservation then
                        local marker = sentenceEnd and token.key or nil
                        local limit = marker and ending - 1 or ending
                        local parsed = ns.Engine.ClauseAnalysis.parseDependencies(document, first, limit, arcs, words)
                        local output, reason = renderDependency(document, parsed, first, ending, arcs, words, marker, accept)
                        local conflict = reason == "role-conflict"
                        if not output and not occupied then
                            parsed = ns.Engine.ClauseAnalysis.parseWithUntranslatedNominals(document, first, limit, arcs, words)
                            output, reason = renderDependency(document, parsed, first, ending, arcs, words, marker, accept)
                            conflict = conflict or reason == "role-conflict"
                        end
                        local original = phrases.raw(document, first, ending)
                        if output and (not occupied or not parsed.untranslated) and N.key(output) ~= N.key(original) then
                            local intent = #parsed.trees > 1 and "composition" or parsed.trees[1].kind
                            if first == 1 and ending == #tokens and not parsed.untranslated then
                                return fragments, false, output, intent
                            end
                            if first == 1 and sentenceEnd and ending == finalSentenceEnd and not parsed.untranslated then
                                local complete = accept(output .. document.text:sub(token.last + 1), first, #tokens)
                                if complete then return fragments, false, complete, intent end
                            end
                            fragments = fragments or {}
                            for index = first, ending do fragments[index] = nil end
                            fragments[first] = {text=output, last=ending, untranslated=parsed.untranslated,
                                rule={sourceRefs=ns.Linguistics.manifest.sourceRefs}}
                            used, rendered = true, true
                        elseif conflict and not occupied then
                            fragments = fragments or {}
                            fragments[first] = {last=ending, preserve="role-conflict"}
                            newVerbatim, rendered = true, true
                        end
                        if not rendered and not occupied then
                            local prefix = clauseBeforeUnknownTail(document, first, ending)
                            if prefix and accept(prefix.text, first, prefix.last) then
                                fragments = fragments or {}
                                fragments[first] = prefix
                                rendered = true
                                used = used or prefix.rule.dependency
                            end
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
                        if value and value ~= "" and N.key(original) ~= N.key(value)
                            and accept(value, group.first, group.last) then
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
    return fragments, used, nil, nil, newVerbatim
end

local function verbatimRanges(document, fragments)
    local verbatim, resolvedEnd = nil, 0
    for first = 1, #document.tokens do
        local fragment = fragments and fragments[first]
        local unresolved = document.preserve and document.preserve[first]
        if fragment and fragment.text and not fragment.untranslated
            and not (fragment.rule and fragment.rule.unknownSpans) then
            resolvedEnd = math.max(resolvedEnd, fragment.last)
        end
        -- A complete composition can resolve a range left open by a failed structural attempt.
        if unresolved and unresolved.reason == "unresolved-destination" and unresolved.last > resolvedEnd then
            verbatim = verbatim or {}
            for i = first, unresolved.last do verbatim[i] = unresolved.reason end
        end
        if fragment and fragment.preserve then
            verbatim = verbatim or {}
            for i = first, fragment.last do verbatim[i] = fragment.preserve end
        end
    end
    if not verbatim then return nil end

    local stops, nextStop = {}, #document.tokens + 1
    for i = #document.tokens, 1, -1 do
        if verbatim[i] then nextStop = i end
        stops[i] = nextStop - 1
    end
    return verbatim, stops
end

local function exactResult(exact)
    return {text=exact.text, mode="exact", intent=exact.id, matchedTerms={}, unknownSpans={}, sourceRefs=exact.sourceRefs}
end

local function compute(text, direction, tokens, checkpoint, facts, tryNeural)
    local normalized = N.key(text)
    local failure
    local function accept(value, first, last)
        if value then
            local reason = A.reject(facts, first or 1, last or #tokens, value)
            if not reason then return value end
            failure = reason
            return nil, reason
        end
    end
    local exact = ns.Data.exact[direction][normalized]
    if exact and accept(exact.text) then
        local result = exactResult(exact)
        return tryNeural and tryNeural(result, true) or result
    end
    local document = ns.Engine.Morphology.analyze(text, tokens, direction)
    document.checkpoint = checkpoint
    local output, tree, syntaxFragments = ns.Engine.Syntax.translate(document)
    if output and not accept(output) then output, tree = nil, nil end
    local rule, slots
    if tree then
        rule, slots = {intent=tree.kind, sourceRefs={"project-authored:apertium-pipeline-1"}}, tree.slots
    elseif not document.truncated and not document.ambiguities then
        output, rule, slots = ns.Engine.Parser.addressedExact(text, tokens, direction)
        output = accept(output)
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
        output, clauses, fragments = ns.Engine.Parser.compose(text, tokens, direction, grammarFallback, nil, nil, accept)
        output = accept(output)
        if not output then clauses = nil end
        composedOpening = true
    end
    if not output and grammarEnabled then
        local rendered, grammarRule, grammarSlots = grammarClause(document, 1, #tokens)
        if rendered and N.key(rendered) ~= normalized and accept(rendered) then
            output, rule, general, slots = rendered, grammarRule, true, grammarSlots
        end
    end
    if not output and not document.truncated and not document.ambiguities then
        output, rule, slots = ns.Engine.Parser.translate(text, tokens, direction)
        output = accept(output)
    end
    if not output and not composedOpening and not document.truncated and not document.ambiguities then
        output, clauses, fragments = ns.Engine.Parser.compose(text, tokens, direction, grammarFallback, nil, nil, accept)
        output = accept(output)
        if not output then clauses = nil end
    end
    -- Without a complete rendering, build the fallback only if the model declines.
    if tryNeural and not output then
        local result = tryNeural()
        if result then return result end
    end
    local verbatim, stops
    if not output and (fragments or document.preserve) then
        verbatim, stops = verbatimRanges(document, fragments)
    end
    if syntaxFragments and not output then
        fragments = fragments or {}
        for first, fragment in pairs(syntaxFragments) do
            -- Keep a translated sentence that already covers this opening.
            local sentence = fragments[first]
            if (not stops or fragment.last <= stops[first]) and accept(fragment.text, first, fragment.last)
                and not (sentence and sentence.text and sentence.last > fragment.last) then
                for start, old in pairs(fragments) do
                    if start <= fragment.last and old.last >= first then fragments[start] = nil end
                end
                fragments[first] = fragment
            end
        end
    end
    if output then
        if clauses and N.key(output) == normalized then
            local result = unchanged(text, "identical")
            return tryNeural and tryNeural(result) or result
        end
        local matched, refs, seen, unknown = {}, {}, {}, {}
        local dependency = rule and rule.dependency == true or nil
        if clauses then
            for _, clause in ipairs(clauses) do
                addClause(matched, refs, seen, clause.rule, clause.slots, unknown)
                dependency = dependency or clause.rule.dependency
            end
        else
            addClause(matched, refs, seen, rule, slots, unknown)
        end
        table.sort(matched)
        table.sort(refs)
        local unresolved = tree and tree.features.unresolved
        if unresolved then unknown[#unknown + 1] = byteSpan(tokens, unresolved) end
        local complete = #unknown == 0
        local place = tree and tree.slots.place
        local dungeon = place and place.term.features and place.term.features.clearableInstance
        local role = tree and tree.slots.role
        local groupPattern = place and tree.kind == "recruit" and (dungeon or role and role.term.category == "roles")
            or dungeon and (tree.kind == "groupVacancy" or tree.kind == "roleInquiry")
        local serviceOffer = tree and tree.kind == "service" and tree.features.compactFree and tree.slots.trade
        local enchantmentOffer = tree and tree.kind == "enhancement" and tree.features.offer == "enchanting"
            and tree.slots.count and tree.slots.stat
        local itemAction = tree and (tree.kind == "linkedSale" or tree.kind == "lockRequest" or tree.kind == "lockOffer")
        local skillInquiry = tree and tree.kind == "availability"
        local preservedNames = not complete
        for _, span in ipairs(unknown) do
            if span.reason ~= "preserved-recruitment-name" then preservedNames = false; break end
        end
        local preferred = preservedNames or unresolved and tree.kind == "roleInquiry"
            or complete and (groupPattern or serviceOffer or enchantmentOffer or itemAction or skillInquiry or clauses ~= nil
                or general and (rule.graded or rule.politeRequest or rule.preferredInChat
                    or not (rule.modal or rule.copular)))
        local result = {text = output, mode = complete and "template" or "partial", intent = clauses and "composition" or rule.intent,
            matchedTerms = matched, unknownSpans = unknown, sourceRefs = refs,
            coverage = {complete=complete, pipeline=clauses and "composition" or general and "grammar"
                or tree and "structural" or "legacy", dependency=dependency}}
        return tryNeural and tryNeural(result, preferred, complete and general and rule.directQuestion) or result
    end
    local usedDependency
    if grammarEnabled then
        local rendered, intent, newVerbatim
        fragments, usedDependency, rendered, intent, newVerbatim = dependencyFragments(document, fragments, verbatim, accept)
        if rendered then
            return {text=rendered, mode="template", intent=intent, matchedTerms={}, unknownSpans={},
                sourceRefs=ns.Linguistics.manifest.sourceRefs,
                coverage={complete=true, pipeline="grammar", dependency=true}}
        end
        if newVerbatim then verbatim, stops = verbatimRanges(document, fragments) end
    end
    local chunks, matched, unknown, refs, refSeen, i, cursor = {}, {}, {}, {}, {}, 1, 1
    local reason, reasonEnd
    local nextCheckpoint = 5
    while i <= #tokens do
        if checkpoint and i >= nextCheckpoint then
            nextCheckpoint = i + 4
            checkpoint()
        end
        local token = tokens[i]
        local fragment = fragments and fragments[i]
        local preserve = document.preserve and document.preserve[i]
        if preserve then reason, reasonEnd = preserve.reason, preserve.last end
        local limit = stops and stops[i] or #tokens
        local keep = verbatim and verbatim[i]
        if not (fragment or keep or reasonEnd and i <= reasonEnd) and grammarEnabled
            and direction == "en-uk" and document.hasHyphen then
            fragment = activityProfileFragment(document, i, limit, fragments)
        end
        local term, last, replacement, rejected
        if fragment and fragment.last <= limit then
            replacement, rejected = accept(fragment.text, i, fragment.last)
        end
        if replacement then
            last = fragment.last
            addClause(matched, refs, refSeen, fragment.rule, fragment.slots, unknown)
            for _, span in ipairs(fragment.untranslated or {}) do
                local literal = tokens[span.index]
                unknown[#unknown + 1] = {first=literal.first, last=literal.last, protected=false,
                    reason=span.reason}
            end
        elseif not keep and not token.protected then
            term, last = ns.Engine.Dictionary.literal(document, i, fragments, limit)
            if grammarEnabled and not (reasonEnd and i <= reasonEnd) and (not last or last == i) then
                local place, finish, value = placePhrase(document, i, fragments, limit)
                if place then term, last, replacement = place, finish, value end
            end
            if not term then term, last = ns.Engine.Dictionary.general(document, i) end
            if term then
                replacement = replacement or term.features and term.features.verbatim and text:sub(token.first, tokens[last].last)
                    or term.text or (direction == "en-uk" and term.uk or term.en)
                local reason
                replacement, reason = accept(replacement, i, last)
                rejected = reason or rejected
                if replacement then
                    matched[#matched + 1] = term.id
                    addRefs(refs, refSeen, term.sourceRefs)
                end
            end
        end
        if replacement then
            chunks[#chunks + 1] = text:sub(cursor, token.first - 1)
            chunks[#chunks + 1] = replacement
            cursor, i = tokens[last].last + 1, last + 1
        else
            unknown[#unknown + 1] = {first = token.first, last = token.last, protected = token.protected or false,
                reason = keep or rejected or (reasonEnd and i <= reasonEnd and reason or nil)}
            i = i + 1
        end
    end
    if #chunks == 0 then
        local result = unchanged(text, failure or "unsupported")
        if verbatim or failure then result.unknownSpans = unknown end
        return result
    end
    chunks[#chunks + 1] = text:sub(cursor)
    local translated = table.concat(chunks)
    if translated == text or N.key(translated) == normalized then return unchanged(text, "identical") end
    if not accept(translated) then return unchanged(text, failure) end
    return {text = translated, mode = "partial", matchedTerms = matched, unknownSpans = unknown, sourceRefs = refs,
        coverage = usedDependency and {complete=false, pipeline="dictionary", dependency=true} or nil}
end

local function translateMixed(text, direction, tokens, ranges, checkpoint)
    local chunks, matched, unknown, refs, seen = {}, {}, {}, {}, {}
    local cursor, nextToken, changed = 1, 1, false
    local separators = ns.Engine.SourceLanguage.clauseEnd
    local function translatePart(first, last, continues)
        local clipped = last < #tokens and separators[tokens[last].key]
        while first <= last and separators[tokens[first].key] do first = first + 1 end
        if clipped then
            while first <= last and separators[tokens[last].key] do last = last - 1 end
        end
        if first > last then return end
        local offset = tokens[first].first - 1
        local ending = tokens[last].last
        local source = text:sub(offset + 1, ending)
        local part = {}
        for i = first, last do
            local token = {}
            for key, value in pairs(tokens[i]) do token[key] = value end
            token.first, token.last = token.first - offset, token.last - offset
            part[#part + 1] = token
        end
        if checkpoint then checkpoint() end
        local result = compute(source, direction, part, checkpoint, A.measure(source, part, direction))
        local value = result.text
        if (clipped or continues) and value ~= source then value = (value:gsub("%.$", "")) end
        chunks[#chunks + 1] = text:sub(cursor, offset)
        chunks[#chunks + 1] = value
        cursor = ending + 1
        changed = changed or value ~= source
        for _, term in ipairs(result.matchedTerms) do matched[#matched + 1] = term end
        addRefs(refs, seen, result.sourceRefs)
        for _, span in ipairs(result.unknownSpans) do
            unknown[#unknown + 1] = {first=span.first + offset, last=span.last + offset,
                protected=span.protected, reason=span.reason}
        end
    end
    for _, range in ipairs(ranges) do
        if range.first > nextToken then translatePart(nextToken, range.first - 1, range.inline) end
        for i = range.first, range.last do
            local token = tokens[i]
            unknown[#unknown + 1] = {first=token.first, last=token.last, protected=token.protected or false,
                reason=range.reason or "unsupported-source-language"}
        end
        nextToken = range.last + 1
    end
    if nextToken <= #tokens then translatePart(nextToken, #tokens) end
    if not changed then
        local result = unchanged(text, "unsupported-source-language")
        result.unknownSpans = unknown
        return result
    end
    chunks[#chunks + 1] = text:sub(cursor)
    table.sort(refs)
    return {text=table.concat(chunks), mode="partial", matchedTerms=matched, unknownSpans=unknown, sourceRefs=refs,
        coverage={complete=false, pipeline="composition"}}
end

local function digitsMatch(text, output)
    local digits = output:gmatch("%d+")
    for original in text:gmatch("%d+") do
        if digits() ~= original then return false end
    end
    return digits() == nil
end

local noFacts = {}
local function translateNeural(text, tokens, checkpoint, facts, directQuestion)
    local english
    for _, token in ipairs(tokens) do
        if not token.protected then
            if token.key:find("[\208\209][\128-\191]") then return end
            english = english or token.key:find("[A-Za-z]")
        end
    end
    if not english then return end
    local output, mode, calls = neuralRuntime.routeChat(ns, text, function(value, context)
        if not neuralModel then neuralModel = neuralRuntime.prepare(ns.Data.translationStudent, checkpoint) end
        return neuralRuntime.translate(neuralModel, value, checkpoint, false, ns.Engine.Markup.split, context, true)
    end, checkpoint, tokens, facts or noFacts, grammarClause, false, true)
    if mode ~= "complete" or not output or output == text then return end
    local last = tokens[#tokens]
    if (directQuestion or not last.protected and last.key == "?") and not output:find("?", 1, true) then
        local tail = output:match("%s*$")
        output = output:sub(1, #output - #tail):gsub("…$", ""):gsub("[.!]+$", "") .. "?" .. tail
    end
    if #output > ns.Limits.messageBytes or A.reject(facts, 1, #tokens, output) then return end
    if not digitsMatch(text, output) then return end
    if neuralRuntime.hasVisibleCyrillic(output, ns.Engine.Markup.split) then
        return {text=output, mode=calls > 0 and "neural" or "template",
            matchedTerms={}, unknownSpans={}, sourceRefs={}}
    end
end

local function translateText(text, direction, checkpoint, neural)
    local contractions = direction == "en-uk" and ns.Engine.ClauseAnalysis.englishContractions
    local tokens = ns.Engine.Tokenizer.scan(text, contractions)
    if not tokens or #tokens == 0 then return unchanged(text, "token-limit-or-empty") end
    local foreign = ns.Engine.SourceLanguage.foreignRanges(tokens, text)
    local facts = A.measure(text, tokens, direction)
    if foreign then
        local normalized = N.key(text)
        local exact = ns.Data.exact[direction][normalized]
        if exact and not A.reject(facts, 1, #tokens, exact.text) then return exactResult(exact) end
        local result = translateMixed(text, direction, tokens, A.preserveScopes(facts, foreign), checkpoint)
        local reason = result.mode ~= "unchanged" and A.reject(facts, 1, #tokens, result.text)
        return reason and unchanged(text, reason) or result
    end
    if neural then
        if neuralRuntime.chatOpener(tokens, 1) then
            return translateNeural(text, tokens, checkpoint, facts) or compute(text, direction, tokens, checkpoint, facts)
        end
        return compute(text, direction, tokens, checkpoint, facts, function(grammatical, preferred, directQuestion)
            if preferred and digitsMatch(text, grammatical.text) then return grammatical end
            return translateNeural(text, tokens, checkpoint, facts, directQuestion)
        end)
    end
    return compute(text, direction, tokens, checkpoint, facts)
end

function E.translate(text, direction, context, checkpoint)
    if C.secret(text) or C.secret(direction) then return nil end
    if type(text) ~= "string" or (direction ~= "en-uk" and direction ~= "uk-en") then return nil end
    if #text > ns.Limits.messageBytes then return unchanged(text, "byte-limit") end
    local settings = ns.Database.settings
    local neural = direction == "en-uk" and context and checkpoint and settings and settings.neuralIncoming
        and neuralRuntime and ns.Data.translationStudent
    local key = cachedKey(text, direction, context, neural)
    local entry = key and cache[key]
    if entry then return entry.result end
    local result = translateText(text, direction, checkpoint, neural)
    store(key, result)
    return result
end
