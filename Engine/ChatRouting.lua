local _, ns = ...
local R = {}; ns.Engine.ChatRouting = R

local beForms = ns.Engine.Normalize.englishCopulas
local numbers, message = ns.Engine.NeuralNumbers, ns.Engine.Message
local finderAction = {open=true, use=true, check=true, enable=true, disable=true}
function R.finderReference(tokens, first)
    local before, after = tokens[first - 1], tokens[first + 1]
    return before and (beForms[before.key] or finderAction[before.key])
        or after and beForms[after.key]
end

local chatOpeners = {lf=true, lfg=true, lfm=true, wts=true, wtb=true, wtt=true, lfw=true,
    afk=true, brb=true, oom=true, pst=true}
local tradeLinkOpeners = {lfw=true, wts=true, wtb=true, wtt=true}
function R.chatOpener(tokens, first)
    local head, nextWord = tokens[first], tokens[first + 1]
    if head and head.linkKind == "trade" and nextWord and tradeLinkOpeners[nextWord.key] then
        first = first + 1
        head, nextWord = nextWord, tokens[first + 1]
    end
    if head and not head.protected and chatOpeners[head.key]
        and (head.key ~= "lfg" or not R.finderReference(tokens, first))
        and not (nextWord and (nextWord.key == "means" or nextWord.key == "stands")) then
        return first
    end
end
local separators = {[","]=true, [";"]=true, ["—"]=true, ["–"]=true}

local clauseDependent = {he=true, she=true, they=true, it=true, this=true, that=true,
    these=true, those=true, because=true, whereas=true, although=true, which=true}
local conditionalContinuation = {unless=true, ["if"]=true, ["while"]=true, since=true}
local periodAbbreviation = {dr=true, mr=true, mrs=true, ms=true, st=true, vs=true, lvl=true, etc=true,
    no=true, approx=true, prof=true, sr=true, jr=true, inc=true}

local function independentChat(text, tokens, ranges, engine)
    if #ranges < 2 or #ranges > 6 or #tokens < 12 then return false end
    local parser = engine.Parser
    local twoSentences = #ranges == 2
    local minimumWords = twoSentences and 4 or 2
    local total, strongBoundary = 0, false
    for i, range in ipairs(ranges) do
        local first, last = range[1], range[2]
        local initial = tokens[first]
        if i > 1 and (clauseDependent[initial.key] or twoSentences and conditionalContinuation[initial.key]
            or not parser.startsWithCapital(text, initial)) then return false end
        if i < #ranges then
            local stop = tokens[last]
            if stop.key ~= "." and stop.key ~= "!" and stop.key ~= "?" then return false end
            local previousIndex = last - 1
            -- Adjacent question and exclamation marks can emphasize a single sentence ending.
            if stop.key ~= "." then
                strongBoundary = true
                while previousIndex >= first and tokens[previousIndex].key:match("^[!?]$")
                    and tokens[previousIndex].last + 1 == tokens[previousIndex + 1].first do
                    previousIndex = previousIndex - 1
                end
            end
            if previousIndex < first then return false end
            local previous = tokens[previousIndex]
            if previous.key:match("^[.?!]$") or previous.key == "…" or periodAbbreviation[previous.key]
                or stop.key == "." and #previous.key < 2 then return false end
        end
        local count, hasNumbers = 0, false
        for j = first, last do
            local token = tokens[j]
            if not token.protected then
                if token.key == "/" or token.key == "…" then return false end
                hasNumbers = hasNumbers or token.key:find("[0-9]") ~= nil
                if token.key:find("[A-Za-z]") then count = count + 1 end
            end
        end
        if count < minimumWords and not (i == 1 and count == 1
            and engine.ClauseAnalysis.guildHeadingWord(text, tokens, first, last)) then return false end
        if hasNumbers then
            local source = text:sub(tokens[first].first, tokens[last].last)
            if not numbers.ranges(source, numbers.prices(source)) then return false end
        end
        total = total + count
    end
    return total >= 21 or strongBoundary and total >= 10
end

local enchantmentOpenings = {free=true, selling=true, offering=true, last=true}
local clauseJoin = {["and"]=true, ["or"]=true, but=true}

local function enchantmentAdvertisement(engine, text, tokens, checkpoint, source)
    if not enchantmentOpenings[tokens[1].key]
        or not (text:find("..", 1, true) or text:find("…", 1, true)) then return end
    local parser = engine.Parser
    local ranges, first, i = {}, 1, 1
    while i < #tokens do
        local ending = parser.ellipsisEnd(tokens, i, #tokens)
        if not ending and tokens[i].key == "." and tokens[i + 1].key == "."
            and tokens[i].last + 1 == tokens[i + 1].first then ending = i + 1 end
        if ending then
            while ending < #tokens and tokens[ending + 1].key == "."
                and tokens[ending].last + 1 == tokens[ending + 1].first do
                ending = ending + 1
            end
            if ending == #tokens then break end
            local initial = tokens[ending + 1]
            if i <= first or #ranges == 5 or clauseJoin[initial.key] or clauseDependent[initial.key]
                or conditionalContinuation[initial.key] or not parser.startsWithCapital(text, initial) then return end
            ranges[#ranges + 1] = {first, i - 1}
            first, i = ending + 1, ending
        end
        i = i + 1
    end
    if #ranges == 0 then return end
    local document = source and message.analysis(source) or engine.Morphology.analyze(text, tokens, "en-uk")
    document.checkpoint = checkpoint
    local output, tree = engine.Syntax.translateRange(document, 1, ranges[1][2])
    if not (output and tree.kind == "enhancement" and tree.features.offer == "enchanting"
        and tree.slots.count and tree.slots.stat) then return end
    ranges[#ranges + 1] = {first, #tokens}
    return ranges, document, output
end

local function contactCommand(tokens, first)
    local head, command = tokens[first], tokens[first + 1]
    return head.key == "whisper" or head.key == "/" and command
        and (command.key == "w" or command.key == "whisper") and command.first == head.last + 1
end

local dependentContactOpening = {when=true, once=true, because=true, although=true, whereas=true, provided=true}

local function contactBoundary(tokens, first)
    local stop, previous = tokens[first - 1], tokens[first - 2]
    if previous and contactCommand(tokens, first) and stop.key:match("^[.!?]$")
        and not previous.key:match("^[.!?]$") and previous.key ~= "…"
        and not (stop.key == "." and periodAbbreviation[previous.key]) then
        return first, first - 1
    end
    -- A conditional or temporal opening may need the contact command as its main clause.
    local opening = first
    while opening < #tokens and tokens[opening].protected do opening = opening + 1 end
    local key = tokens[opening].key
    if conditionalContinuation[key] or dependentContactOpening[key] then return end
    for i = #tokens - 1, math.max(first + 1, 2), -1 do
        local separator, before, after = tokens[i], tokens[i - 1], tokens[i + 1]
        if (separator.key == "—" or separator.key == "–" or separator.key == "-")
            and before.last + 1 < separator.first and separator.last + 1 < after.first
            and contactCommand(tokens, i + 1) then return i + 1, i - 1 end
    end
end

local function trailingContact(engine, text, tokens, first, grammarClause, checkpoint)
    local head = tokens[first]

    -- A protected heading can travel with the prefix; keep inline links and chat formatting in their existing route.
    local visible
    for _, token in ipairs(tokens) do
        if token.protected then
            if visible then return end
        else visible = true end
    end

    local tail = text:sub(head.first, tokens[#tokens].last)
    local words = engine.Tokenizer.scan(tail, engine.ClauseAnalysis.englishContractions)
    if not words then return end
    local document = engine.Morphology.analyze(tail, words, "en-uk")
    if document.truncated or document.ambiguities then return end
    document.checkpoint = checkpoint
    local translated, clause = grammarClause(document, 1, #words)
    -- A translated restriction can remain in the grammar fallback without splitting an unverified body.
    if clause and clause.imperative and not (clause.question or clause.unknownSpans or clause.attachedRestriction) then
        return translated
    end
end

function R.routeChat(ns, text, translate, checkpoint, tokens, facts, grammarClause, skipContact, requireComplete, trace, source)
    local engine, direction = ns.Engine, "en-uk"
    local function whole()
        if trace then return translate(text, nil, 1) end
        return translate(text)
    end
    tokens = tokens or engine.Tokenizer.scan(text, engine.ClauseAnalysis.englishContractions)
    if not tokens or #tokens == 0 then
        local result, mode = whole()
        return result, mode, 1, 0
    end
    local ranges, first, routed = {}, 1, false
    for i = 1, #tokens - 1 do
        if engine.Parser.sentenceBoundary(text, tokens, i) then
            local known = R.chatOpener(tokens, first)
            ranges[#ranges + 1], first = {first, i, known}, i + 1
            routed = routed or known
        end
    end
    local known = R.chatOpener(tokens, first)
    ranges[#ranges + 1] = {first, #tokens, known}
    local calls, rules = 0, 0
    if not (routed or known or skipContact) and grammarClause then
        local contact, prefixEnd = contactBoundary(tokens, first)
        local tail = contact and trailingContact(engine, text, tokens, contact, grammarClause, checkpoint)
        if tail then
            facts = facts or engine.Acceptance.measure(text, tokens, direction)
            if not engine.Acceptance.reject(facts, contact, #tokens, tail) then
                local boundary = tokens[prefixEnd].last
                local prefix = text:sub(1, boundary)
                local body, mode, attempts, bodyRules = R.routeChat(ns, prefix, translate, checkpoint,
                    nil, nil, grammarClause, true, requireComplete, trace)
                if body and mode == "complete" and ns.Engine.NeuralRuntime.hasVisibleCyrillic(body, engine.Markup.split) then
                    if prefixEnd < contact - 1 and not tokens[prefixEnd].key:match("^[.!?]$") then
                        body = body:gsub("%.$", "")
                    end
                    local output = body .. text:sub(boundary + 1, tokens[contact].first - 1)
                        .. tail .. text:sub(tokens[#tokens].last + 1)
                    if not engine.Acceptance.reject(facts, 1, #tokens, output) then
                        return output, mode, attempts, bodyRules + 1
                    end
                end
                calls = attempts
            end
        end
    end
    local advertisement, document, firstOffer
    if not (routed or known) then
        advertisement, document, firstOffer = enchantmentAdvertisement(engine, text, tokens, checkpoint, source)
        if advertisement then ranges = advertisement end
    end
    local independent = advertisement ~= nil or not (routed or known) and independentChat(text, tokens, ranges, engine)
    if not (routed or known or independent) then
        local result, mode = whole()
        return result, mode, calls + 1, 0
    end

    document = document or (source and message.analysis(source) or engine.Morphology.analyze(text, tokens, direction))
    document.checkpoint = checkpoint
    facts = facts or engine.Acceptance.measure(text, tokens, direction)
    local tradeOpeners = ns.Linguistics and ns.Linguistics.grammar.tradeOpeners
    local function raw(start, finish)
        return text:sub(tokens[start].first, tokens[finish].last)
    end
    local ruleAttempts = {}
    local function rule(start, finish)
        local key = start * (#tokens + 1) + finish
        local previous = ruleAttempts[key]
        if previous ~= nil then return previous or nil end
        local value = engine.Parser.exact(raw(start, finish), direction)
            or engine.Syntax.translateRange(document, start, finish)
            or engine.Parser.translate(text, tokens, direction, start, finish)
        if not value and grammarClause and tradeOpeners and tradeOpeners[tokens[start].key]
            and not document.truncated and not document.ambiguities then
            local translated, clause = grammarClause(document, start, finish)
            if translated and not clause.unknownSpans then value = translated end
        end
        if value then
            local reason = engine.Acceptance.reject(facts, start, finish, value)
            if trace then trace("chat-rule", tokens[start].first, tokens[finish].last, value, reason) end
            if not reason then
                ruleAttempts[key] = value
                return value
            end
        end
        ruleAttempts[key] = false
    end
    local function neural(start, finish, context)
        calls = calls + 1
        local value, mode
        if trace then value, mode = translate(raw(start, finish), context, tokens[start].first)
        else value, mode = translate(raw(start, finish), context) end
        if value and not engine.Acceptance.reject(facts, start, finish, value) then return value, mode end
        return raw(start, finish), "partial"
    end
    local function mixed(start, finish)
        local whole = rule(start, finish)
        if whole then rules = rules + 1; return whole, "complete" end
        local head, number, suffix = tokens[start], tokens[start + 1], tokens[start + 2]
        local recruiting = head.key == "lf" or head.key == "lfm"
        for i = start + 1, math.min(finish - 1, start + 16) do
            if not tokens[i].protected and separators[tokens[i].key] then
                -- A role requirement still depends on the recruitment before the separator.
                if recruiting and engine.Syntax.recruitRoleRequestEnd(tokens, i + 1, finish) then break end
                local prefix = rule(start, i - 1)
                if prefix then
                    local tail, mode = neural(i + 1, finish, head.key)
                    local join = text:sub(tokens[i - 1].last + 1, tokens[i + 1].first - 1)
                    rules = rules + 1
                    return prefix:gsub("[.!?]+$", "") .. join .. tail, mode
                end
            end
        end
        local stop, prefix = start, nil
        if head.key == "lf" and number and suffix and start + 2 <= finish and number.key:match("^%d+$")
            and suffix.key == "m" and head.last + 1 == number.first and number.last + 1 == suffix.first then
            stop = start + 2
            prefix = rule(start, stop)
        end
        if not prefix then
            local entry = engine.Dictionary.literal(document, start, nil, start)
            prefix = entry and (entry.text or entry.uk)
            stop = start
        end
        if not prefix then return neural(start, finish) end
        rules = rules + 1
        if stop == finish then return prefix, "complete" end
        local following = tokens[stop + 1]
        local join = text:sub(tokens[stop].last + 1, following.first - 1)
        prefix = prefix:gsub("[.!?]+$", "")
        if following.key:match("^[.!?]$") then
            local punctuation = raw(stop + 1, finish)
            if punctuation:match("^[.!?]+$") then return prefix .. join .. punctuation, "complete" end
        end
        local tail, mode = neural(stop + 1, finish, tokens[start].key)
        if join == "" and (following.protected or not following.key:match("^%p$")) then join = " " end
        return prefix .. join .. tail, mode
    end

    local pieces, cursor, complete = {}, 1, true
    for _, range in ipairs(ranges) do
        local start, finish, opener = unpack(range)
        local value, mode
        if opener then
            value, mode = mixed(opener, finish)
            if opener > start then
                value = text:sub(tokens[start].first, tokens[opener].first - 1) .. value
            end
        elseif independent then
            local parsed, clause
            if advertisement then parsed = start == 1 and firstOffer or rule(start, finish) end
            if not parsed and grammarClause and not document.truncated and not document.ambiguities then
                parsed, clause = grammarClause(document, start, finish)
            end
            if parsed and not (clause and clause.unknownSpans) and not engine.Acceptance.reject(facts, start, finish, parsed) then
                value, mode, rules = parsed, "complete", rules + 1
            else
                value, mode = neural(start, finish)
            end
        else
            value, mode = neural(start, finish)
        end
        local join = text:sub(cursor, tokens[start].first - 1)
        if cursor > 1 then
            if advertisement then join = join:match("^%s*(.-)%s*$") .. " "
            elseif independent and join == "" then join = " " end
        end
        pieces[#pieces + 1] = join
        pieces[#pieces + 1] = advertisement and finish < #tokens and value:gsub("[.!]+$", "") or value
        cursor = tokens[finish].last + 1
        complete = complete and mode == "complete"
        if independent and not complete then
            local result, status = whole()
            return result, status, calls + 1, rules
        end
        if requireComplete and not complete then return nil, "partial", calls, rules end
    end
    pieces[#pieces + 1] = text:sub(cursor)
    local output = table.concat(pieces)
    if engine.Acceptance.reject(facts, 1, #tokens, output) then
        if independent then
            local result, status = whole()
            return result, status, calls + 1, rules
        end
        return text, "unchanged", calls, rules
    end
    return output, complete and "complete" or "partial", calls, rules
end

function R.select(source, neural, providers, trace, modelFirst)
    local acceptance = ns.Engine.Acceptance
    local text, direction, tokens, facts = source.text, source.direction, source.tokens, source.facts
    local foreign = ns.Engine.SourceLanguage.foreignRanges(tokens, text)
    if trace then
        trace("class", 1, #text, nil, foreign and "mixed"
            or direction == "uk-en" and "draft"
            or R.chatOpener(tokens, 1) and "chat-opening" or "prose")
    end
    if foreign then
        local output, exact = ns.Engine.Parser.exact(text, direction, source.key)
        if output and not acceptance.reject(facts, 1, #tokens, output) then return providers.exact(output, exact) end
        local result = providers.mixed(source, acceptance.preserveScopes(facts, foreign), trace)
        local reason = result.mode ~= "unchanged" and acceptance.reject(facts, 1, #tokens, result.text)
        return reason and providers.original(text, reason) or result
    end
    if neural and R.chatOpener(tokens, 1) then
        local routed = providers.model(source, nil, trace)
        if routed then return routed end
        return providers.rules(source, trace)
    end
    local candidate, preferred, directQuestion, partial = providers.rules(source, trace, neural)
    if modelFirst and candidate then
        local coverage = candidate.coverage
        local trade = candidate.intent == "trade_buy" or candidate.intent == "trade_sell"
        preferred = candidate.mode == "exact" or coverage and coverage.complete
            and (coverage.pipeline == "structural" or trade)
    end
    if neural and not (preferred and providers.digitsMatch(text, candidate.text)) then
        candidate = providers.model(source, directQuestion, trace) or candidate
    end
    return candidate or partial()
end
