-- EN → UK student inference shared by the addon and the offline evaluator.
local _, ns = ...
local M = {}
if ns then ns.Engine.NeuralRuntime = M end
local UNK, BOS, EOS, PAD = 1, 2, 3, 4
local MAX_PIECES = 48
local alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz!#$%&()*+-;<=>?@^_"
    .. string.char(96) .. "{|}~"
local digit = {}
for i = 1, #alphabet do digit[alphabet:byte(i)] = i - 1 end
local floor, exp = math.floor, math.exp

local function decodeBytes(packed)
    local row = {}
    for start = 1, #packed, 5 do
        local a, b, c, d, e = packed:byte(start, start + 4)
        local value = (((digit[a] * 85 + digit[b]) * 85 + digit[c]) * 85 + digit[d]) * 85 + digit[e]
        row[#row + 1] = floor(value / 16777216)
        row[#row + 1] = floor(value / 65536) % 256
        row[#row + 1] = floor(value / 256) % 256
        row[#row + 1] = value % 256
    end
    return row
end

local function rowAt(matrix, index)
    local row = matrix.rows[index]
    if not row then
        row = decodeBytes(matrix.packed[index])
        for i, value in ipairs(row) do
            if value >= 128 then row[i] = value - 256 end
        end
        matrix.rows[index] = row
    end
    return row, matrix.scales[index]
end

local function embedding(matrix, index, width)
    local row, scale = rowAt(matrix, index)
    local values = {}
    for i = 1, width do values[i] = row[i] * scale end
    return values
end

local function project(matrix, index, values, width)
    local row, scale = rowAt(matrix, index)
    local total = 0
    for i = 1, width do total = total + row[i] * values[i] end
    return total * scale
end

local function sigmoid(value)
    return 1 / (1 + exp(-value))
end

local function tanh(value)
    local decay = exp(-2 * math.abs(value))
    local positive = (1 - decay) / (1 + decay)
    return value < 0 and -positive or positive
end

local function gru(network, input, state, width, checkpoint)
    local nextState = {}
    local inputWidth = #input
    for i = 1, width do
        local reset = sigmoid(project(network.input, i, input, inputWidth) + network.inputBias[i]
            + project(network.state, i, state, width) + network.stateBias[i])
        local updateIndex = width + i
        local update = sigmoid(project(network.input, updateIndex, input, inputWidth) + network.inputBias[updateIndex]
            + project(network.state, updateIndex, state, width) + network.stateBias[updateIndex])
        local cellIndex = 2 * width + i
        local cell = tanh(project(network.input, cellIndex, input, inputWidth) + network.inputBias[cellIndex]
            + reset * (project(network.state, cellIndex, state, width) + network.stateBias[cellIndex]))
        nextState[i] = (1 - update) * cell + update * state[i]
        if checkpoint and i % 8 == 0 then checkpoint() end
    end
    return nextState
end

function M.prepare(data, checkpoint)
    assert(data.format == 1 or data.format == 2, "Unsupported translation student format")
    local function matrix(values)
        return {packed=values.packed, scales=values.scales, rows={}}
    end
    local function network(values)
        return {input=matrix(values.input), state=matrix(values.state), inputBias=values.inputBias,
            stateBias=values.stateBias}
    end
    local pieces, maximumBytes = {}, 0
    for id = PAD + 1, #data.sourcePieces do
        local piece = data.sourcePieces[id]
        pieces[piece] = {id=id, score=data.sourceScores[id]}
        maximumBytes = math.max(maximumBytes, #piece)
        if checkpoint and id % 128 == 0 then checkpoint() end
    end
    local reserved, allCandidates = {}, {EOS}
    for _, id in ipairs(data.targetSlots or {}) do reserved[id] = true end
    for id = PAD + 1, #data.targetPieces do
        if not reserved[id] then allCandidates[#allCandidates + 1] = id end
        if checkpoint and id % 128 == 0 then checkpoint() end
    end
    return {width=data.width, pieces=pieces, maximumBytes=maximumBytes, unknownScore=data.unknownScore,
        targetPieces=data.targetPieces, fallback=data.fallback, linked=data.linked, linkedCache={},
        allCandidates=allCandidates, reserved=reserved, inputAttention=data.format == 2,
        source=matrix(data.source), target=matrix(data.target), encoder=network(data.encoder),
        decoder=network(data.decoder), combine=matrix(data.combine), combineBias=data.combineBias,
        outputBias=data.outputBias}
end

function M.tokenize(model, text, checkpoint)
    text = text:gsub("’", "'"):gsub("‘", "'"):gsub("ʼ", "'"):gsub("[A-Z]", string.lower)
    text = text:gsub("^ +", ""):gsub(" +$", ""):gsub(" +", " ")
    if text == "" then return {EOS} end
    text = "▁" .. text:gsub(" ", "▁")
    local positions = {}
    for start in text:gmatch("()[^\128-\191][\128-\191]*") do positions[#positions + 1] = start end
    positions[#positions + 1] = #text + 1
    local scores, back, ids = {[1]=0}, {}, {}
    for first = 1, #positions - 1 do
        local score, foundSingle = scores[first], false
        if score then
            for last = first + 1, #positions do
                local firstByte, nextByte = positions[first], positions[last]
                if nextByte - firstByte > model.maximumBytes then break end
                local piece = model.pieces[text:sub(firstByte, nextByte - 1)]
                if piece then
                    if last == first + 1 then foundSingle = true end
                    local total = score + piece.score
                    if not scores[last] or total > scores[last] then
                        scores[last], back[last], ids[last] = total, first, piece.id
                    end
                end
            end
            if not foundSingle then
                local last, total = first + 1, score + model.unknownScore
                if not scores[last] or total > scores[last] then
                    scores[last], back[last], ids[last] = total, first, UNK
                end
            end
        end
        if checkpoint and first % 24 == 0 then checkpoint() end
    end
    local reversed, index = {}, #positions
    while back[index] do
        local id = ids[index]
        if id ~= UNK or reversed[#reversed] ~= UNK then reversed[#reversed + 1] = id end
        index = back[index]
    end
    local tokens = {}
    for i = #reversed, 1, -1 do tokens[#tokens + 1] = reversed[i] end
    tokens[#tokens + 1] = EOS
    return tokens
end

function M.encode(model, tokens, checkpoint)
    local width, state, encoded = model.width, {}, {}
    for i = 1, width do state[i] = 0 end
    for i, id in ipairs(tokens) do
        state = gru(model.encoder, embedding(model.source, id, width), state, width, checkpoint)
        encoded[i] = state
    end
    return encoded, state
end

local function sourceContext(query, encoded, width)
    local attention, maximum = {}, -math.huge
    local divisor = math.sqrt(width)
    for i, row in ipairs(encoded) do
        local total = 0
        for j = 1, width do total = total + row[j] * query[j] end
        attention[i] = total / divisor
        maximum = math.max(maximum, attention[i])
    end
    local sum = 0
    for i, value in ipairs(attention) do
        attention[i] = exp(value - maximum)
        sum = sum + attention[i]
    end
    local context = {}
    for j = 1, width do context[j] = 0 end
    for i, row in ipairs(encoded) do
        local weight = attention[i] / sum
        for j = 1, width do context[j] = context[j] + row[j] * weight end
    end
    return context
end

function M.decode(model, previous, encoded, state, checkpoint)
    local width = model.width
    local input = embedding(model.target, previous, width)
    if model.inputAttention then
        local context = sourceContext(input, encoded, width)
        for i = 1, width do input[width + i] = context[i] end
    end
    state = gru(model.decoder, input, state, width, checkpoint)
    local context, combined = sourceContext(state, encoded, width), {}
    for i = 1, width do combined[i], combined[width + i] = state[i], context[i] end
    local features = {}
    for j = 1, width do
        features[j] = tanh(project(model.combine, j, combined, width * 2) + model.combineBias[j])
        if checkpoint and j % 8 == 0 then checkpoint() end
    end
    return features, state
end

function M.candidates(model, source)
    local found, candidates = {}, {}
    local function add(group)
        for _, id in ipairs(group) do
            if not found[id] and not model.reserved[id] then found[id], candidates[#candidates + 1] = true, id end
        end
    end
    add(model.fallback)
    for _, piece in ipairs(source) do
        local linked = model.linkedCache[piece]
        if not linked and model.linked[piece] then
            linked = {}
            local bytes = decodeBytes(model.linked[piece])
            for i = 1, #bytes, 2 do
                local id = bytes[i] + 256 * bytes[i + 1]
                if id ~= 0 then linked[#linked + 1] = id end
            end
            model.linkedCache[piece] = linked
        end
        if linked then add(linked) end
    end
    table.sort(candidates)
    return candidates
end

function M.score(model, features, id)
    return project(model.target, id, features, model.width) + model.outputBias[id]
end

local function translatePlain(model, text, checkpoint, fullVocabulary)
    local source = M.tokenize(model, text, checkpoint)
    if #source < 2 or #source > MAX_PIECES then return nil, "source-length" end
    for _, id in ipairs(source) do
        if id == UNK then return nil, "source-vocabulary" end
    end
    local choices = fullVocabulary and model.allCandidates or M.candidates(model, source)
    local encoded, state = M.encode(model, source, checkpoint)
    local target, previous = {}, BOS
    for _ = 1, MAX_PIECES do
        local features
        features, state = M.decode(model, previous, encoded, state, checkpoint)
        local best, highest = EOS, -math.huge
        for index, id in ipairs(choices) do
            local score = M.score(model, features, id)
            if score > highest then best, highest = id, score end
            if checkpoint and index % 32 == 0 then checkpoint() end
        end
        if best == EOS then
            local output = table.concat(target):gsub("▁", " "):gsub("^ +", "")
            if output == "" then return nil, "empty" end
            return output, "complete", #choices
        end
        target[#target + 1], previous = model.targetPieces[best], best
    end
    return nil, "target-length", #choices
end

function M.withProtected(text, split, translate)
    local segments = split(text)
    if #segments == 0 or (#segments == 1 and not segments[1].protected) then
        return translate(text)
    end
    local pieces, protected, calls, largest = {}, {}, 0, 0
    local changed, incomplete = false, false
    for _, segment in ipairs(segments) do
        local original = text:sub(segment.first, segment.last)
        local value = original
        if segment.protected then
            protected[#protected + 1] = original
        elseif original:find("[A-Za-z]") then
            local leading, body, trailing = original:match("^(%s*)(.-)(%s*)$")
            local result, _, candidates = translate(body)
            calls = calls + 1
            largest = math.max(largest, candidates or 0)
            if result then
                value = leading .. result:gsub("%s+$", "") .. trailing
                changed = changed or value ~= original
            else
                incomplete = true
            end
        end
        pieces[#pieces + 1] = value
    end
    if not changed then return text, "unchanged", largest, calls end
    local output, index = table.concat(pieces), 0
    for _, segment in ipairs(split(output)) do
        if segment.protected then
            index = index + 1
            if protected[index] ~= output:sub(segment.first, segment.last) then
                return text, "protected-output", largest, calls
            end
        end
    end
    if index ~= #protected then return text, "protected-output", largest, calls end
    return output, incomplete and "partial" or "complete", largest, calls
end

function M.translate(model, text, checkpoint, fullVocabulary, split)
    if not split then return translatePlain(model, text, checkpoint, fullVocabulary) end
    return M.withProtected(text, split, function(fragment)
        return translatePlain(model, fragment, checkpoint, fullVocabulary)
    end)
end

local chatOpeners = {lf=true, lfg=true, lfm=true, wts=true, wtb=true, wtt=true, lfw=true,
    afk=true, brb=true, oom=true, pst=true}
local separators = {[","]=true, [";"]=true, ["—"]=true, ["–"]=true}

function M.routeChat(ns, text, translate, checkpoint, tokens, facts)
    local engine, direction = ns.Engine, "en-uk"
    tokens = tokens or engine.Tokenizer.scan(text, engine.ClauseAnalysis.englishContractions)
    local function opener(first)
        local head, nextWord = tokens[first], tokens[first + 1]
        return head and not head.protected and chatOpeners[head.key]
            and not (nextWord and (nextWord.key == "means" or nextWord.key == "stands"))
    end
    if not tokens or #tokens == 0 then
        local result, mode = translate(text)
        return result, mode, 1, 0
    end
    local ranges, first, routed = {}, 1, false
    for i = 1, #tokens - 1 do
        if engine.Parser.sentenceBoundary(text, tokens, i) then
            local known = opener(first)
            ranges[#ranges + 1], first = {first, i, known}, i + 1
            routed = routed or known
        end
    end
    local known = opener(first)
    ranges[#ranges + 1] = {first, #tokens, known}
    if not (routed or known) then
        local result, mode = translate(text)
        return result, mode, 1, 0
    end

    local document = engine.Morphology.analyze(text, tokens, direction)
    document.checkpoint = checkpoint
    facts = facts or engine.Acceptance.measure(text, tokens, direction)
    local calls, rules = 0, 0
    local function raw(start, finish)
        return text:sub(tokens[start].first, tokens[finish].last)
    end
    local function rule(start, finish)
        local exact = ns.Data.exact[direction][engine.Normalize.key(raw(start, finish))]
        local value = exact and exact.text or engine.Syntax.translateRange(document, start, finish)
            or engine.Parser.translate(text, tokens, direction, start, finish)
        if value and not engine.Acceptance.reject(facts, start, finish, value) then return value end
    end
    local function neural(start, finish)
        calls = calls + 1
        local value, mode = translate(raw(start, finish))
        if value and not engine.Acceptance.reject(facts, start, finish, value) then return value, mode end
        return raw(start, finish), "partial"
    end
    local function mixed(start, finish)
        local whole = rule(start, finish)
        if whole then rules = rules + 1; return whole, "complete" end
        for i = start + 1, math.min(finish - 1, start + 16) do
            if not tokens[i].protected and separators[tokens[i].key] then
                local prefix = rule(start, i - 1)
                if prefix then
                    local tail, mode = neural(i + 1, finish)
                    local join = text:sub(tokens[i - 1].last + 1, tokens[i + 1].first - 1)
                    rules = rules + 1
                    return prefix:gsub("[.!?]+$", "") .. join .. tail, mode
                end
            end
        end
        local head, number, suffix = tokens[start], tokens[start + 1], tokens[start + 2]
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
        local tail, mode = neural(stop + 1, finish)
        local join = text:sub(tokens[stop].last + 1, tokens[stop + 1].first - 1)
        if join == "" and (tokens[stop + 1].protected or not tokens[stop + 1].key:match("^%p$")) then join = " " end
        return prefix:gsub("[.!?]+$", "") .. join .. tail, mode
    end

    local pieces, cursor, complete = {}, 1, true
    for _, range in ipairs(ranges) do
        local start, finish, isKnown = unpack(range)
        local value, mode
        if isKnown then value, mode = mixed(start, finish)
        else value, mode = neural(start, finish) end
        pieces[#pieces + 1] = text:sub(cursor, tokens[start].first - 1)
        pieces[#pieces + 1] = value
        cursor = tokens[finish].last + 1
        complete = complete and mode == "complete"
    end
    pieces[#pieces + 1] = text:sub(cursor)
    local output = table.concat(pieces)
    if engine.Acceptance.reject(facts, 1, #tokens, output) then return text, "unchanged", calls, rules end
    return output, complete and "complete" or "partial", calls, rules
end

return M
