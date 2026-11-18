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
    local punctuation
    while last >= first and document.tokens[last].key:match("^[.!?]$") do
        local key = document.tokens[last].key
        if not punctuation or key == "?" then punctuation = key end
        last = last - 1
    end
    if last < first then return nil end
    local parsed = ns.Engine.ClauseAnalysis.parse(document, first, last)
    if not parsed then return nil end
    local output = ns.Engine.ClauseGeneration.render(parsed, document.direction, punctuation)
    if output then return output, {intent=parsed.trees[1].kind, imperative=parsed.trees[1].imperative == true,
        sourceRefs=ns.Linguistics.manifest.sourceRefs} end
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
        output, rule, slots = ns.Engine.Parser.translate(text, tokens, direction)
    end
    local clauses, fragments
    local general
    local grammarEnabled = ns.Linguistics and not document.truncated and not document.ambiguities
    if not output and grammarEnabled then
        local rendered, grammarRule = grammarClause(document, 1, #tokens)
        if rendered and N.key(rendered) ~= N.key(text) then
            output, rule, general = rendered, grammarRule, true
        end
    end
    if not output and not document.truncated and not document.ambiguities then
        local grammarFallback
        if grammarEnabled then
            grammarFallback = function(first, last) return grammarClause(document, first, last) end
        end
        output, clauses, fragments = ns.Engine.Parser.compose(text, tokens, direction, grammarFallback)
    end
    if syntaxFragments and not output then
        fragments = fragments or {}
        -- Structural chunks take priority; discard overlapping legacy clauses.
        for first, fragment in pairs(syntaxFragments) do
            for start, old in pairs(fragments) do
                if start <= fragment.last and old.last >= first then fragments[start] = nil end
            end
            fragments[first] = fragment
        end
    end
    if output then
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
            coverage = {complete=true, pipeline=general and "grammar" or (tree and "structural" or "legacy")}}
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
            if term then
                replacement = term.text or (direction == "en-uk" and term.uk or term.en)
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
    return {text = translated, mode = "partial", matchedTerms = matched, unknownSpans = unknown, sourceRefs = refs}
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
