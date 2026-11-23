local _, ns = ...
local M = {}
ns.Engine.NeuralInference = M
local UNK, EOS, PAD = 1, 3, 4
M.UNK, M.BOS, M.EOS = UNK, 2, EOS
local MAX_PIECES = 48
local alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz!#$%&()*+-;<=>?@^_"
    .. string.char(96) .. "{|}~"
local digit = {}
for i = 1, #alphabet do digit[alphabet:byte(i)] = i - 1 end
local floor, exp = math.floor, math.exp

-- Matrix weights are signed; linked vocabulary IDs use unsigned bytes.
local signedBytes, unsignedBytes = {}, {}
for value = 0, 255 do
    unsignedBytes[value] = value
    signedBytes[value] = value < 128 and value or value - 256
end

local function decodeBytes(packed, bytes)
    bytes = bytes or unsignedBytes
    local row, index = {}, 1
    for start = 1, #packed, 5 do
        local a, b, c, d, e = packed:byte(start, start + 4)
        local value = (((digit[a] * 85 + digit[b]) * 85 + digit[c]) * 85 + digit[d]) * 85 + digit[e]
        row[index] = bytes[floor(value / 16777216)]
        row[index + 1] = bytes[floor(value / 65536) % 256]
        row[index + 2] = bytes[floor(value / 256) % 256]
        row[index + 3] = bytes[value % 256]
        index = index + 4
    end
    return row
end

local function rowAt(matrix, index)
    local row = matrix.rows[index]
    if not row then
        row = decodeBytes(matrix.packed[index], signedBytes)
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


local function transformerNetwork(values, matrix)
    local function attention(weights)
        return {qkv=matrix(weights.qkv), output=matrix(weights.output)}
    end
    local function blocks(rows)
        local result = {}
        for i, row in ipairs(rows) do
            result[i] = {
                selfNorm=row.selfNorm, attention=attention(row.attention), feedNorm=row.feedNorm,
                feedIn=matrix(row.feedIn), feedOut=matrix(row.feedOut),
                crossNorm=row.crossNorm, crossAttention=row.crossAttention and attention(row.crossAttention)
            }
        end
        return result
    end
    return {heads=values.heads, sourcePos=matrix(values.sourcePos), targetPos=matrix(values.targetPos),
        sourceNorm=values.sourceNorm, targetNorm=values.targetNorm,
        encoder=blocks(values.encoder), decoder=blocks(values.decoder)}
end

function M.prepare(data, checkpoint)
    assert(data.format == 1 or data.format == 2 or data.format == 3, "Unsupported translation student format")
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
        maxPieces=data.transformer and math.min(128, #data.transformer.sourcePos.packed,
            #data.transformer.targetPos.packed) or MAX_PIECES,
        source=matrix(data.source), target=matrix(data.target), encoder=data.encoder and network(data.encoder),
        transformer=data.transformer and transformerNetwork(data.transformer, matrix),
        decoder=data.decoder and network(data.decoder), combine=data.combine and matrix(data.combine), combineBias=data.combineBias,
        outputBias=data.outputBias}
end

function M.normalizeInput(text)
    text = text:gsub("’", "'"):gsub("‘", "'"):gsub("ʼ", "'"):gsub("[A-Z]", string.lower)
    return (text:gsub("^ +", ""):gsub(" +$", ""):gsub(" +", " "))
end

function M.tokenize(model, text, checkpoint, normalized)
    text = normalized or M.normalizeInput(text)
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

local function projectTransformer(matrix, index, vector, width)
    local values, scale = rowAt(matrix, index)
    local total = 0
    local last = width - width % 16
    for j = 1, last, 16 do
        total = total + values[j] * vector[j] + values[j + 1] * vector[j + 1]
            + values[j + 2] * vector[j + 2] + values[j + 3] * vector[j + 3]
            + values[j + 4] * vector[j + 4] + values[j + 5] * vector[j + 5]
            + values[j + 6] * vector[j + 6] + values[j + 7] * vector[j + 7]
            + values[j + 8] * vector[j + 8] + values[j + 9] * vector[j + 9]
            + values[j + 10] * vector[j + 10] + values[j + 11] * vector[j + 11]
            + values[j + 12] * vector[j + 12] + values[j + 13] * vector[j + 13]
            + values[j + 14] * vector[j + 14] + values[j + 15] * vector[j + 15]
    end
    for j = last + 1, width do total = total + values[j] * vector[j] end
    return total * scale
end

-- Reuse each input block while preserving the addition order within each dot product.
local function projectFour(matrix, first, second, third, fourth, vector, width)
    local firstRow, firstScale = rowAt(matrix, first)
    local secondRow, secondScale = rowAt(matrix, second)
    local thirdRow, thirdScale = rowAt(matrix, third)
    local fourthRow, fourthScale = rowAt(matrix, fourth)
    local firstSum, secondSum, thirdSum, fourthSum = 0, 0, 0, 0
    -- Constant indexes avoid loop arithmetic at the deployed model width.
    -- Keep the additions in the same order as the general path.
    if width == 128 then
        do
            local x0, x1, x2, x3 = vector[1], vector[2], vector[3], vector[4]
            local x4, x5, x6, x7 = vector[5], vector[6], vector[7], vector[8]
            firstSum = firstSum + firstRow[1] * x0 + firstRow[2] * x1 + firstRow[3] * x2 + firstRow[4] * x3
                + firstRow[5] * x4 + firstRow[6] * x5 + firstRow[7] * x6 + firstRow[8] * x7
            secondSum = secondSum + secondRow[1] * x0 + secondRow[2] * x1 + secondRow[3] * x2 + secondRow[4] * x3
                + secondRow[5] * x4 + secondRow[6] * x5 + secondRow[7] * x6 + secondRow[8] * x7
            thirdSum = thirdSum + thirdRow[1] * x0 + thirdRow[2] * x1 + thirdRow[3] * x2 + thirdRow[4] * x3
                + thirdRow[5] * x4 + thirdRow[6] * x5 + thirdRow[7] * x6 + thirdRow[8] * x7
            fourthSum = fourthSum + fourthRow[1] * x0 + fourthRow[2] * x1 + fourthRow[3] * x2 + fourthRow[4] * x3
                + fourthRow[5] * x4 + fourthRow[6] * x5 + fourthRow[7] * x6 + fourthRow[8] * x7
        end
        do
            local x0, x1, x2, x3 = vector[9], vector[10], vector[11], vector[12]
            local x4, x5, x6, x7 = vector[13], vector[14], vector[15], vector[16]
            firstSum = firstSum + firstRow[9] * x0 + firstRow[10] * x1 + firstRow[11] * x2 + firstRow[12] * x3
                + firstRow[13] * x4 + firstRow[14] * x5 + firstRow[15] * x6 + firstRow[16] * x7
            secondSum = secondSum + secondRow[9] * x0 + secondRow[10] * x1 + secondRow[11] * x2 + secondRow[12] * x3
                + secondRow[13] * x4 + secondRow[14] * x5 + secondRow[15] * x6 + secondRow[16] * x7
            thirdSum = thirdSum + thirdRow[9] * x0 + thirdRow[10] * x1 + thirdRow[11] * x2 + thirdRow[12] * x3
                + thirdRow[13] * x4 + thirdRow[14] * x5 + thirdRow[15] * x6 + thirdRow[16] * x7
            fourthSum = fourthSum + fourthRow[9] * x0 + fourthRow[10] * x1 + fourthRow[11] * x2 + fourthRow[12] * x3
                + fourthRow[13] * x4 + fourthRow[14] * x5 + fourthRow[15] * x6 + fourthRow[16] * x7
        end
        do
            local x0, x1, x2, x3 = vector[17], vector[18], vector[19], vector[20]
            local x4, x5, x6, x7 = vector[21], vector[22], vector[23], vector[24]
            firstSum = firstSum + firstRow[17] * x0 + firstRow[18] * x1 + firstRow[19] * x2 + firstRow[20] * x3
                + firstRow[21] * x4 + firstRow[22] * x5 + firstRow[23] * x6 + firstRow[24] * x7
            secondSum = secondSum + secondRow[17] * x0 + secondRow[18] * x1 + secondRow[19] * x2 + secondRow[20] * x3
                + secondRow[21] * x4 + secondRow[22] * x5 + secondRow[23] * x6 + secondRow[24] * x7
            thirdSum = thirdSum + thirdRow[17] * x0 + thirdRow[18] * x1 + thirdRow[19] * x2 + thirdRow[20] * x3
                + thirdRow[21] * x4 + thirdRow[22] * x5 + thirdRow[23] * x6 + thirdRow[24] * x7
            fourthSum = fourthSum + fourthRow[17] * x0 + fourthRow[18] * x1 + fourthRow[19] * x2 + fourthRow[20] * x3
                + fourthRow[21] * x4 + fourthRow[22] * x5 + fourthRow[23] * x6 + fourthRow[24] * x7
        end
        do
            local x0, x1, x2, x3 = vector[25], vector[26], vector[27], vector[28]
            local x4, x5, x6, x7 = vector[29], vector[30], vector[31], vector[32]
            firstSum = firstSum + firstRow[25] * x0 + firstRow[26] * x1 + firstRow[27] * x2 + firstRow[28] * x3
                + firstRow[29] * x4 + firstRow[30] * x5 + firstRow[31] * x6 + firstRow[32] * x7
            secondSum = secondSum + secondRow[25] * x0 + secondRow[26] * x1 + secondRow[27] * x2 + secondRow[28] * x3
                + secondRow[29] * x4 + secondRow[30] * x5 + secondRow[31] * x6 + secondRow[32] * x7
            thirdSum = thirdSum + thirdRow[25] * x0 + thirdRow[26] * x1 + thirdRow[27] * x2 + thirdRow[28] * x3
                + thirdRow[29] * x4 + thirdRow[30] * x5 + thirdRow[31] * x6 + thirdRow[32] * x7
            fourthSum = fourthSum + fourthRow[25] * x0 + fourthRow[26] * x1 + fourthRow[27] * x2 + fourthRow[28] * x3
                + fourthRow[29] * x4 + fourthRow[30] * x5 + fourthRow[31] * x6 + fourthRow[32] * x7
        end
        do
            local x0, x1, x2, x3 = vector[33], vector[34], vector[35], vector[36]
            local x4, x5, x6, x7 = vector[37], vector[38], vector[39], vector[40]
            firstSum = firstSum + firstRow[33] * x0 + firstRow[34] * x1 + firstRow[35] * x2 + firstRow[36] * x3
                + firstRow[37] * x4 + firstRow[38] * x5 + firstRow[39] * x6 + firstRow[40] * x7
            secondSum = secondSum + secondRow[33] * x0 + secondRow[34] * x1 + secondRow[35] * x2 + secondRow[36] * x3
                + secondRow[37] * x4 + secondRow[38] * x5 + secondRow[39] * x6 + secondRow[40] * x7
            thirdSum = thirdSum + thirdRow[33] * x0 + thirdRow[34] * x1 + thirdRow[35] * x2 + thirdRow[36] * x3
                + thirdRow[37] * x4 + thirdRow[38] * x5 + thirdRow[39] * x6 + thirdRow[40] * x7
            fourthSum = fourthSum + fourthRow[33] * x0 + fourthRow[34] * x1 + fourthRow[35] * x2 + fourthRow[36] * x3
                + fourthRow[37] * x4 + fourthRow[38] * x5 + fourthRow[39] * x6 + fourthRow[40] * x7
        end
        do
            local x0, x1, x2, x3 = vector[41], vector[42], vector[43], vector[44]
            local x4, x5, x6, x7 = vector[45], vector[46], vector[47], vector[48]
            firstSum = firstSum + firstRow[41] * x0 + firstRow[42] * x1 + firstRow[43] * x2 + firstRow[44] * x3
                + firstRow[45] * x4 + firstRow[46] * x5 + firstRow[47] * x6 + firstRow[48] * x7
            secondSum = secondSum + secondRow[41] * x0 + secondRow[42] * x1 + secondRow[43] * x2 + secondRow[44] * x3
                + secondRow[45] * x4 + secondRow[46] * x5 + secondRow[47] * x6 + secondRow[48] * x7
            thirdSum = thirdSum + thirdRow[41] * x0 + thirdRow[42] * x1 + thirdRow[43] * x2 + thirdRow[44] * x3
                + thirdRow[45] * x4 + thirdRow[46] * x5 + thirdRow[47] * x6 + thirdRow[48] * x7
            fourthSum = fourthSum + fourthRow[41] * x0 + fourthRow[42] * x1 + fourthRow[43] * x2 + fourthRow[44] * x3
                + fourthRow[45] * x4 + fourthRow[46] * x5 + fourthRow[47] * x6 + fourthRow[48] * x7
        end
        do
            local x0, x1, x2, x3 = vector[49], vector[50], vector[51], vector[52]
            local x4, x5, x6, x7 = vector[53], vector[54], vector[55], vector[56]
            firstSum = firstSum + firstRow[49] * x0 + firstRow[50] * x1 + firstRow[51] * x2 + firstRow[52] * x3
                + firstRow[53] * x4 + firstRow[54] * x5 + firstRow[55] * x6 + firstRow[56] * x7
            secondSum = secondSum + secondRow[49] * x0 + secondRow[50] * x1 + secondRow[51] * x2 + secondRow[52] * x3
                + secondRow[53] * x4 + secondRow[54] * x5 + secondRow[55] * x6 + secondRow[56] * x7
            thirdSum = thirdSum + thirdRow[49] * x0 + thirdRow[50] * x1 + thirdRow[51] * x2 + thirdRow[52] * x3
                + thirdRow[53] * x4 + thirdRow[54] * x5 + thirdRow[55] * x6 + thirdRow[56] * x7
            fourthSum = fourthSum + fourthRow[49] * x0 + fourthRow[50] * x1 + fourthRow[51] * x2 + fourthRow[52] * x3
                + fourthRow[53] * x4 + fourthRow[54] * x5 + fourthRow[55] * x6 + fourthRow[56] * x7
        end
        do
            local x0, x1, x2, x3 = vector[57], vector[58], vector[59], vector[60]
            local x4, x5, x6, x7 = vector[61], vector[62], vector[63], vector[64]
            firstSum = firstSum + firstRow[57] * x0 + firstRow[58] * x1 + firstRow[59] * x2 + firstRow[60] * x3
                + firstRow[61] * x4 + firstRow[62] * x5 + firstRow[63] * x6 + firstRow[64] * x7
            secondSum = secondSum + secondRow[57] * x0 + secondRow[58] * x1 + secondRow[59] * x2 + secondRow[60] * x3
                + secondRow[61] * x4 + secondRow[62] * x5 + secondRow[63] * x6 + secondRow[64] * x7
            thirdSum = thirdSum + thirdRow[57] * x0 + thirdRow[58] * x1 + thirdRow[59] * x2 + thirdRow[60] * x3
                + thirdRow[61] * x4 + thirdRow[62] * x5 + thirdRow[63] * x6 + thirdRow[64] * x7
            fourthSum = fourthSum + fourthRow[57] * x0 + fourthRow[58] * x1 + fourthRow[59] * x2 + fourthRow[60] * x3
                + fourthRow[61] * x4 + fourthRow[62] * x5 + fourthRow[63] * x6 + fourthRow[64] * x7
        end
        do
            local x0, x1, x2, x3 = vector[65], vector[66], vector[67], vector[68]
            local x4, x5, x6, x7 = vector[69], vector[70], vector[71], vector[72]
            firstSum = firstSum + firstRow[65] * x0 + firstRow[66] * x1 + firstRow[67] * x2 + firstRow[68] * x3
                + firstRow[69] * x4 + firstRow[70] * x5 + firstRow[71] * x6 + firstRow[72] * x7
            secondSum = secondSum + secondRow[65] * x0 + secondRow[66] * x1 + secondRow[67] * x2 + secondRow[68] * x3
                + secondRow[69] * x4 + secondRow[70] * x5 + secondRow[71] * x6 + secondRow[72] * x7
            thirdSum = thirdSum + thirdRow[65] * x0 + thirdRow[66] * x1 + thirdRow[67] * x2 + thirdRow[68] * x3
                + thirdRow[69] * x4 + thirdRow[70] * x5 + thirdRow[71] * x6 + thirdRow[72] * x7
            fourthSum = fourthSum + fourthRow[65] * x0 + fourthRow[66] * x1 + fourthRow[67] * x2 + fourthRow[68] * x3
                + fourthRow[69] * x4 + fourthRow[70] * x5 + fourthRow[71] * x6 + fourthRow[72] * x7
        end
        do
            local x0, x1, x2, x3 = vector[73], vector[74], vector[75], vector[76]
            local x4, x5, x6, x7 = vector[77], vector[78], vector[79], vector[80]
            firstSum = firstSum + firstRow[73] * x0 + firstRow[74] * x1 + firstRow[75] * x2 + firstRow[76] * x3
                + firstRow[77] * x4 + firstRow[78] * x5 + firstRow[79] * x6 + firstRow[80] * x7
            secondSum = secondSum + secondRow[73] * x0 + secondRow[74] * x1 + secondRow[75] * x2 + secondRow[76] * x3
                + secondRow[77] * x4 + secondRow[78] * x5 + secondRow[79] * x6 + secondRow[80] * x7
            thirdSum = thirdSum + thirdRow[73] * x0 + thirdRow[74] * x1 + thirdRow[75] * x2 + thirdRow[76] * x3
                + thirdRow[77] * x4 + thirdRow[78] * x5 + thirdRow[79] * x6 + thirdRow[80] * x7
            fourthSum = fourthSum + fourthRow[73] * x0 + fourthRow[74] * x1 + fourthRow[75] * x2 + fourthRow[76] * x3
                + fourthRow[77] * x4 + fourthRow[78] * x5 + fourthRow[79] * x6 + fourthRow[80] * x7
        end
        do
            local x0, x1, x2, x3 = vector[81], vector[82], vector[83], vector[84]
            local x4, x5, x6, x7 = vector[85], vector[86], vector[87], vector[88]
            firstSum = firstSum + firstRow[81] * x0 + firstRow[82] * x1 + firstRow[83] * x2 + firstRow[84] * x3
                + firstRow[85] * x4 + firstRow[86] * x5 + firstRow[87] * x6 + firstRow[88] * x7
            secondSum = secondSum + secondRow[81] * x0 + secondRow[82] * x1 + secondRow[83] * x2 + secondRow[84] * x3
                + secondRow[85] * x4 + secondRow[86] * x5 + secondRow[87] * x6 + secondRow[88] * x7
            thirdSum = thirdSum + thirdRow[81] * x0 + thirdRow[82] * x1 + thirdRow[83] * x2 + thirdRow[84] * x3
                + thirdRow[85] * x4 + thirdRow[86] * x5 + thirdRow[87] * x6 + thirdRow[88] * x7
            fourthSum = fourthSum + fourthRow[81] * x0 + fourthRow[82] * x1 + fourthRow[83] * x2 + fourthRow[84] * x3
                + fourthRow[85] * x4 + fourthRow[86] * x5 + fourthRow[87] * x6 + fourthRow[88] * x7
        end
        do
            local x0, x1, x2, x3 = vector[89], vector[90], vector[91], vector[92]
            local x4, x5, x6, x7 = vector[93], vector[94], vector[95], vector[96]
            firstSum = firstSum + firstRow[89] * x0 + firstRow[90] * x1 + firstRow[91] * x2 + firstRow[92] * x3
                + firstRow[93] * x4 + firstRow[94] * x5 + firstRow[95] * x6 + firstRow[96] * x7
            secondSum = secondSum + secondRow[89] * x0 + secondRow[90] * x1 + secondRow[91] * x2 + secondRow[92] * x3
                + secondRow[93] * x4 + secondRow[94] * x5 + secondRow[95] * x6 + secondRow[96] * x7
            thirdSum = thirdSum + thirdRow[89] * x0 + thirdRow[90] * x1 + thirdRow[91] * x2 + thirdRow[92] * x3
                + thirdRow[93] * x4 + thirdRow[94] * x5 + thirdRow[95] * x6 + thirdRow[96] * x7
            fourthSum = fourthSum + fourthRow[89] * x0 + fourthRow[90] * x1 + fourthRow[91] * x2 + fourthRow[92] * x3
                + fourthRow[93] * x4 + fourthRow[94] * x5 + fourthRow[95] * x6 + fourthRow[96] * x7
        end
        do
            local x0, x1, x2, x3 = vector[97], vector[98], vector[99], vector[100]
            local x4, x5, x6, x7 = vector[101], vector[102], vector[103], vector[104]
            firstSum = firstSum + firstRow[97] * x0 + firstRow[98] * x1 + firstRow[99] * x2 + firstRow[100] * x3
                + firstRow[101] * x4 + firstRow[102] * x5 + firstRow[103] * x6 + firstRow[104] * x7
            secondSum = secondSum + secondRow[97] * x0 + secondRow[98] * x1 + secondRow[99] * x2 + secondRow[100] * x3
                + secondRow[101] * x4 + secondRow[102] * x5 + secondRow[103] * x6 + secondRow[104] * x7
            thirdSum = thirdSum + thirdRow[97] * x0 + thirdRow[98] * x1 + thirdRow[99] * x2 + thirdRow[100] * x3
                + thirdRow[101] * x4 + thirdRow[102] * x5 + thirdRow[103] * x6 + thirdRow[104] * x7
            fourthSum = fourthSum + fourthRow[97] * x0 + fourthRow[98] * x1 + fourthRow[99] * x2 + fourthRow[100] * x3
                + fourthRow[101] * x4 + fourthRow[102] * x5 + fourthRow[103] * x6 + fourthRow[104] * x7
        end
        do
            local x0, x1, x2, x3 = vector[105], vector[106], vector[107], vector[108]
            local x4, x5, x6, x7 = vector[109], vector[110], vector[111], vector[112]
            firstSum = firstSum + firstRow[105] * x0 + firstRow[106] * x1 + firstRow[107] * x2 + firstRow[108] * x3
                + firstRow[109] * x4 + firstRow[110] * x5 + firstRow[111] * x6 + firstRow[112] * x7
            secondSum = secondSum + secondRow[105] * x0 + secondRow[106] * x1 + secondRow[107] * x2 + secondRow[108] * x3
                + secondRow[109] * x4 + secondRow[110] * x5 + secondRow[111] * x6 + secondRow[112] * x7
            thirdSum = thirdSum + thirdRow[105] * x0 + thirdRow[106] * x1 + thirdRow[107] * x2 + thirdRow[108] * x3
                + thirdRow[109] * x4 + thirdRow[110] * x5 + thirdRow[111] * x6 + thirdRow[112] * x7
            fourthSum = fourthSum + fourthRow[105] * x0 + fourthRow[106] * x1 + fourthRow[107] * x2 + fourthRow[108] * x3
                + fourthRow[109] * x4 + fourthRow[110] * x5 + fourthRow[111] * x6 + fourthRow[112] * x7
        end
        do
            local x0, x1, x2, x3 = vector[113], vector[114], vector[115], vector[116]
            local x4, x5, x6, x7 = vector[117], vector[118], vector[119], vector[120]
            firstSum = firstSum + firstRow[113] * x0 + firstRow[114] * x1 + firstRow[115] * x2 + firstRow[116] * x3
                + firstRow[117] * x4 + firstRow[118] * x5 + firstRow[119] * x6 + firstRow[120] * x7
            secondSum = secondSum + secondRow[113] * x0 + secondRow[114] * x1 + secondRow[115] * x2 + secondRow[116] * x3
                + secondRow[117] * x4 + secondRow[118] * x5 + secondRow[119] * x6 + secondRow[120] * x7
            thirdSum = thirdSum + thirdRow[113] * x0 + thirdRow[114] * x1 + thirdRow[115] * x2 + thirdRow[116] * x3
                + thirdRow[117] * x4 + thirdRow[118] * x5 + thirdRow[119] * x6 + thirdRow[120] * x7
            fourthSum = fourthSum + fourthRow[113] * x0 + fourthRow[114] * x1 + fourthRow[115] * x2 + fourthRow[116] * x3
                + fourthRow[117] * x4 + fourthRow[118] * x5 + fourthRow[119] * x6 + fourthRow[120] * x7
        end
        do
            local x0, x1, x2, x3 = vector[121], vector[122], vector[123], vector[124]
            local x4, x5, x6, x7 = vector[125], vector[126], vector[127], vector[128]
            firstSum = firstSum + firstRow[121] * x0 + firstRow[122] * x1 + firstRow[123] * x2 + firstRow[124] * x3
                + firstRow[125] * x4 + firstRow[126] * x5 + firstRow[127] * x6 + firstRow[128] * x7
            secondSum = secondSum + secondRow[121] * x0 + secondRow[122] * x1 + secondRow[123] * x2 + secondRow[124] * x3
                + secondRow[125] * x4 + secondRow[126] * x5 + secondRow[127] * x6 + secondRow[128] * x7
            thirdSum = thirdSum + thirdRow[121] * x0 + thirdRow[122] * x1 + thirdRow[123] * x2 + thirdRow[124] * x3
                + thirdRow[125] * x4 + thirdRow[126] * x5 + thirdRow[127] * x6 + thirdRow[128] * x7
            fourthSum = fourthSum + fourthRow[121] * x0 + fourthRow[122] * x1 + fourthRow[123] * x2 + fourthRow[124] * x3
                + fourthRow[125] * x4 + fourthRow[126] * x5 + fourthRow[127] * x6 + fourthRow[128] * x7
        end
        return firstSum * firstScale, secondSum * secondScale, thirdSum * thirdScale, fourthSum * fourthScale
    end
    for j = 1, width, 8 do
        local j1, j2, j3, j4 = j + 1, j + 2, j + 3, j + 4
        local j5, j6, j7 = j + 5, j + 6, j + 7
        local x0, x1, x2, x3 = vector[j], vector[j1], vector[j2], vector[j3]
        local x4, x5, x6, x7 = vector[j4], vector[j5], vector[j6], vector[j7]
        firstSum = firstSum + firstRow[j] * x0 + firstRow[j1] * x1 + firstRow[j2] * x2 + firstRow[j3] * x3
            + firstRow[j4] * x4 + firstRow[j5] * x5 + firstRow[j6] * x6 + firstRow[j7] * x7
        secondSum = secondSum + secondRow[j] * x0 + secondRow[j1] * x1 + secondRow[j2] * x2 + secondRow[j3] * x3
            + secondRow[j4] * x4 + secondRow[j5] * x5 + secondRow[j6] * x6 + secondRow[j7] * x7
        thirdSum = thirdSum + thirdRow[j] * x0 + thirdRow[j1] * x1 + thirdRow[j2] * x2 + thirdRow[j3] * x3
            + thirdRow[j4] * x4 + thirdRow[j5] * x5 + thirdRow[j6] * x6 + thirdRow[j7] * x7
        fourthSum = fourthSum + fourthRow[j] * x0 + fourthRow[j1] * x1 + fourthRow[j2] * x2 + fourthRow[j3] * x3
            + fourthRow[j4] * x4 + fourthRow[j5] * x5 + fourthRow[j6] * x6 + fourthRow[j7] * x7
    end
    return firstSum * firstScale, secondSum * secondScale, thirdSum * thirdScale, fourthSum * fourthScale
end

local function linearSlice(matrix, vector, first, count, checkpoint, result)
    local width = #vector
    result = result or {}
    local grouped = width % 8 == 0 and count - count % 4 or 0
    for i = 1, grouped, 4 do
        local row = first + i - 1
        result[i], result[i + 1], result[i + 2], result[i + 3] =
            projectFour(matrix, row, row + 1, row + 2, row + 3, vector, width)
        if checkpoint and i % 8 == 5 then checkpoint() end
    end
    for i = grouped + 1, count do
        result[i] = projectTransformer(matrix, first + i - 1, vector, width)
        if checkpoint and i % 8 == 0 then checkpoint() end
    end
    return result
end

local function normalize(vector, parameters, out)
    local width, total = #vector, 0
    for i = 1,width do total = total + vector[i] end
    local mean, variance = total / width, 0
    for i = 1,width do
        local delta = vector[i] - mean
        variance = variance + delta * delta
    end
    local inv = 1 / math.sqrt(variance / width + .00001)
    out = out or {}
    local scale, bias = parameters[1], parameters[2]
    for i = 1,width do out[i] = (vector[i] - mean) * inv * scale[i] + bias[i] end
    return out
end

local function keyValue(attention, vector, width, checkpoint)
    local matrix = attention.qkv
    return linearSlice(matrix, vector, width + 1, width, checkpoint),
        linearSlice(matrix, vector, 2 * width + 1, width, checkpoint)
end

local function queryKeyValue(attention, vector, width, checkpoint, queries)
    local matrix = attention.qkv
    return linearSlice(matrix, vector, 1, width, checkpoint, queries),
        linearSlice(matrix, vector, width + 1, width, checkpoint),
        linearSlice(matrix, vector, 2 * width + 1, width, checkpoint)
end

local function addAttention(vector, attention, query, keys, values, heads, checkpoint, scratch)
    local width, context, weights = #query, scratch.context, scratch.weights
    local span = width / heads
    local inverse = 1 / math.sqrt(span)
    for head = 1,heads do
        local first, last = (head - 1) * span + 1, head * span
        local peak = -math.huge
        for i, key in ipairs(keys) do
            local value = 0
            for j = first,last do value = value + key[j] * query[j] end
            value = value * inverse
            weights[i] = value
            if value > peak then peak = value end
        end
        local total = 0
        for i = 1, #keys do
            weights[i] = exp(weights[i] - peak)
            total = total + weights[i]
        end
        for j = first,last do context[j] = 0 end
        for i, value in ipairs(values) do
            local weight = weights[i] / total
            for j = first,last do context[j] = context[j] + value[j] * weight end
        end
        if checkpoint then checkpoint() end
    end
    local grouped = width % 8 == 0 and width - width % 4 or 0
    for i = 1, grouped, 4 do
        local a, b, c, d = projectFour(attention.output, i, i + 1, i + 2, i + 3, context, width)
        vector[i], vector[i + 1] = vector[i] + a, vector[i + 1] + b
        vector[i + 2], vector[i + 3] = vector[i + 2] + c, vector[i + 3] + d
        if checkpoint and i % 8 == 5 then checkpoint() end
    end
    for i = grouped + 1, width do
        vector[i] = vector[i] + projectTransformer(attention.output, i, context, width)
        if checkpoint and i % 8 == 0 then checkpoint() end
    end
end

local function feedForward(layer, vector, width, checkpoint, scratch)
    local input = normalize(vector, layer.feedNorm, scratch.normalized)
    local hidden = linearSlice(layer.feedIn, input, 1, width * 2, checkpoint, scratch.hidden)
    -- Pack active values into the already visited part of hidden.
    local indexes = scratch.indexes
    local count = 0
    for j = 1,#hidden do
        local value = hidden[j]
        if value > 0 then
            count = count + 1
            indexes[count], hidden[count] = j, value
        end
    end
    local last = count - count % 4
    -- Share the active indexes and values across two output rows.
    local paired = width - width % 2
    for i = 1, paired, 2 do
        local leftRow, leftScale = rowAt(layer.feedOut, i)
        local rightRow, rightScale = rowAt(layer.feedOut, i + 1)
        local left, right = 0, 0
        for j = 1, last, 4 do
            local a, b, c, d = indexes[j], indexes[j + 1], indexes[j + 2], indexes[j + 3]
            local x, y, z, w = hidden[j], hidden[j + 1], hidden[j + 2], hidden[j + 3]
            left = left + leftRow[a] * x + leftRow[b] * y + leftRow[c] * z + leftRow[d] * w
            right = right + rightRow[a] * x + rightRow[b] * y + rightRow[c] * z + rightRow[d] * w
        end
        for j = last + 1, count do
            local k, value = indexes[j], hidden[j]
            left, right = left + leftRow[k] * value, right + rightRow[k] * value
        end
        vector[i], vector[i + 1] = vector[i] + left * leftScale, vector[i + 1] + right * rightScale
        if checkpoint and i % 8 == 7 then checkpoint() end
    end
    if paired < width then
        local row, scale = rowAt(layer.feedOut, width)
        local total = 0
        for j = 1, count do total = total + row[indexes[j]] * hidden[j] end
        vector[width] = vector[width] + total * scale
    end
end

local function positionalEmbedding(tokens, id, positions, position, width)
    local token, tokenScale = rowAt(tokens, id)
    local offset, offsetScale = rowAt(positions, position)
    local result = {}
    for i = 1, width do result[i] = token[i] * tokenScale + offset[i] * offsetScale end
    return result
end

local function transformerEncode(model, tokens, checkpoint)
    local network, width = model.transformer, model.width
    local encoded = {}
    local scratch = {normalized={}, query={}, context={}, weights={}, hidden={}, indexes={}}
    for i, id in ipairs(tokens) do
        encoded[i] = positionalEmbedding(model.source, id, network.sourcePos, i, width)
    end
    for _, layer in ipairs(network.encoder) do
        local queries, keys, values = {}, {}, {}
        for i, vector in ipairs(encoded) do
            local input = normalize(vector, layer.selfNorm, scratch.normalized)
            queries[i], keys[i], values[i] = queryKeyValue(layer.attention, input, width, checkpoint)
        end
        for i, vector in ipairs(encoded) do
            addAttention(vector, layer.attention, queries[i], keys, values, network.heads, checkpoint, scratch)
            feedForward(layer, vector, width, checkpoint, scratch)
        end
    end
    for i, vector in ipairs(encoded) do encoded[i] = normalize(vector, network.sourceNorm) end
    return encoded, {position=0, cache={}, scratch=scratch}
end

local function transformerDecode(model, previous, encoded, state, checkpoint)
    local network, width = model.transformer, model.width
    local position, scratch = state.position + 1, state.scratch
    local vector = positionalEmbedding(model.target, previous, network.targetPos, position, width)
    for i, layer in ipairs(network.decoder) do
        local cache = state.cache[i]
        if not cache then
            cache = {keys={}, values={}, crossKeys={}, crossValues={}}
            for j, row in ipairs(encoded) do
                cache.crossKeys[j], cache.crossValues[j] = keyValue(layer.crossAttention, row, width, checkpoint)
            end
            state.cache[i] = cache
        end
        local input = normalize(vector, layer.selfNorm, scratch.normalized)
        local query
        query, cache.keys[position], cache.values[position] =
            queryKeyValue(layer.attention, input, width, checkpoint, scratch.query)
        addAttention(vector, layer.attention, query, cache.keys, cache.values, network.heads, checkpoint, scratch)
        input = normalize(vector, layer.crossNorm, scratch.normalized)
        query = linearSlice(layer.crossAttention.qkv, input, 1, width, checkpoint, scratch.query)
        addAttention(vector, layer.crossAttention, query, cache.crossKeys, cache.crossValues,
            network.heads, checkpoint, scratch)
        feedForward(layer, vector, width, checkpoint, scratch)
    end
    state.position = position
    return normalize(vector, network.targetNorm), state
end

local gruEncode, gruDecode, gruScore = M.encode, M.decode, M.score
function M.score(model, vector, index)
    if model.transformer then return projectTransformer(model.target, index, vector, model.width) + model.outputBias[index] end
    return gruScore(model, vector, index)
end
function M.encode(model, tokens, checkpoint)
    if model.transformer then return transformerEncode(model, tokens, checkpoint) end
    return gruEncode(model, tokens, checkpoint)
end
function M.decode(model, previous, encoded, state, checkpoint)
    if model.transformer then return transformerDecode(model, previous, encoded, state, checkpoint) end
    return gruDecode(model, previous, encoded, state, checkpoint)
end

local nativeScore = M.score
function M.bestTarget(model, features, choices, checkpoint, score)
    local best, highest = EOS, -math.huge
    if model.transformer and score == nativeScore and model.width % 8 == 0 then
        local count, bias, width = #choices, model.outputBias, model.width
        local grouped = count - count % 4
        for index = 1, grouped, 4 do
            local first, second = choices[index], choices[index + 1]
            local third, fourth = choices[index + 2], choices[index + 3]
            local a, b, c, d = projectFour(model.target, first, second, third, fourth, features, width)
            a, b, c, d = a + bias[first], b + bias[second], c + bias[third], d + bias[fourth]
            if a > highest then best, highest = first, a end
            if b > highest then best, highest = second, b end
            if c > highest then best, highest = third, c end
            if d > highest then best, highest = fourth, d end
            if checkpoint and index % 32 == 29 then checkpoint() end
        end
        for index = grouped + 1, count do
            local candidate = choices[index]
            local score = nativeScore(model, features, candidate)
            if score > highest then best, highest = candidate, score end
        end
        return best
    end
    for index, id in ipairs(choices) do
        local value = score(model, features, id)
        if value > highest then best, highest = id, value end
        if checkpoint and index % 32 == 0 then checkpoint() end
    end
    return best
end

return M
