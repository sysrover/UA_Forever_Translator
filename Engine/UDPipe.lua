local _, ns = ...
local U = {}; ns.Engine.UDPipe = U
local Normalize = ns.Engine.Normalize

-- The model format and arc-standard inference follow Parsito in UDPipe 1.4.0.
-- https://github.com/ufal/udpipe/tree/v1.4.0/src/parsito
local alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz!#$%&()*+-;<=>?@^_"
    .. string.char(96) .. "{|}~"
local digit = {}
for index = 1, #alphabet do digit[alphabet:byte(index)] = index - 1 end
local floor, exp = math.floor, math.exp
local matrices = setmetatable({}, {__mode="k"})
local projectionLimit = 768
local floatScale = {}
for exponent = 0, 255 do
    floatScale[exponent] = 2 ^ (exponent == 0 and -149 or exponent - 150)
end

local function readFloat(block, position)
    local a, b, c, d, e = block:byte(position, position + 4)
    local encoded = (((digit[a] * 85 + digit[b]) * 85 + digit[c]) * 85 + digit[d]) * 85 + digit[e]
    local low = floor(encoded / 16777216)
    local middle = floor(encoded / 65536) % 256
    local high = floor(encoded / 256) % 256
    local sign = encoded % 256
    local mantissa = (high % 128) * 65536 + middle * 256 + low
    local exponent = (sign % 128) * 2 + floor(high / 128)
    local value = (mantissa + (exponent == 0 and 0 or 8388608)) * floatScale[exponent]
    return sign < 128 and value or -value
end

local function decode(blocks, checkpoint)
    local values, index, nextCheckpoint = {}, 0, 256
    for _, block in ipairs(blocks) do
        for position = 1, #block, 5 do
            index = index + 1
            values[index] = readFloat(block, position)
            if checkpoint and index == nextCheckpoint then
                nextCheckpoint = nextCheckpoint + 256
                checkpoint()
            end
        end
    end
    return values
end

local function cacheModel(model, checkpoint)
    local matrix = matrices[model]
    if matrix then return matrix end
    matrix = {hidden=decode(model.hidden, checkpoint), output=decode(model.output, checkpoint),
        projections={}, projectionOrder={}, nextProjection=1}
    if matrices[model] then return matrices[model] end
    matrices[model] = matrix
    return matrix
end

local function valueOf(node, kind)
    if kind == "form" then return node.form
    elseif kind == "universal_tag" then return node.upos
    elseif kind == "tag" then return node.xpos
    elseif kind == "feats" then return node.feats
    elseif kind == "universal_tag_feats" then return node.upos .. node.feats
    elseif kind == "lemma_id" and node.misc then return node.misc:match("LId=([^|]+)") or node.lemma
    end
    return node.lemma
end

local function embeddingID(feature, value)
    local dictionary = feature.dictionary
    local id = dictionary[value]
    if id then return id end
    local first = value:match("^[^\128-\191][\128-\191]*")
    if first then
        local tail = value:sub(#first + 1)
        local lowerTail = Normalize.word(tail)
        local lowerFirst = Normalize.word(first)
        if first ~= lowerFirst and tail ~= lowerTail then
            id = dictionary[first .. lowerTail]
            if id then return id end
        end
        if first ~= lowerFirst or tail ~= lowerTail then
            id = dictionary[lowerFirst .. lowerTail]
            if id then return id end
        end
        if first:match("^%d$") and not tail:find("[%a\192-\244]") then
            id = dictionary[first]
            if id then return id end
        end
    end
    return feature.unknown
end

local function nodeAt(selector, stack, buffer, nodes)
    local side = selector.stack and stack or buffer
    local selected = side[#side - selector.offset]
    if selected == nil then return nil end
    for _, move in ipairs(selector.path) do
        local node = nodes[selected]
        if move.parent then
            selected = node.head and node.head > 0 and node.head or nil
        else
            local index = move.child >= 0 and move.child + 1 or #node.children + move.child + 1
            selected = index > 0 and node.children[index] or nil
        end
        if not selected then return nil end
        if selected == 0 then break end
    end
    return nodes[selected]
end

local function accumulate(destination, source, offset, factor, width)
    for index = 1, width do
        destination[index] = destination[index] + factor * source[offset + index]
    end
end

local function activate(value, kind)
    if kind == 2 then return math.max(0, value) end
    if kind == 1 then return value * value * value end
    if value <= -10 then return -1 end
    if value >= 10 then return 1 end
    local adjusted = floor((value + 10) * 32768) / 32768 - 10
    return 2 / (1 + exp(-2 * adjusted)) - 1
end

local function projection(model, matrix, selector, group, feature, id, checkpoint)
    local groups = matrix.projections[selector]
    if not groups then groups = {}; matrix.projections[selector] = groups end
    local vectors = groups[group]
    if not vectors then vectors = {}; groups[group] = vectors end
    if vectors[id] then return vectors[id] end

    local width, vector, embedding = model.hiddenSize, {}, {}
    local weights, dimensionCount = matrix.hidden, feature.dimension
    local first = (id - 1) * feature.dimension
    local rowOffset = ((selector - 1) * model.dimension + feature.offset) * width
    for dimension = 0, dimensionCount - 1 do
        local offset = first + dimension
        local block = feature.weights[floor(offset / model.blockSize) + 1]
        embedding[dimension + 1] = readFloat(block, (offset % model.blockSize) * 5 + 1)
    end
    for column = 1, width do
        local value, offset = 0, rowOffset + column
        for dimension = 1, dimensionCount do
            value = value + embedding[dimension] * weights[offset]
            offset = offset + width
        end
        vector[column] = value
        if checkpoint and column % 16 == 0 then checkpoint() end
    end

    -- Numerical vectors depend only on the immutable model and embedding ID.
    if vectors[id] then return vectors[id] end
    local nextProjection = matrix.nextProjection
    local slot = matrix.projectionOrder[nextProjection]
    if slot then slot.vectors[slot.id] = nil
    else slot = {}; matrix.projectionOrder[nextProjection] = slot end
    slot.vectors, slot.id = vectors, id
    vectors[id] = vector
    matrix.nextProjection = nextProjection == projectionLimit and 1 or nextProjection + 1
    return vector
end

function U.prepare(model)
    if not model then return end
    local matrix = cacheModel(model)
    if matrix.prepared then return end
    -- Seed the bounded projection cache with closed-class tags and default embeddings.
    for selector = 1, #model.selectors do
        for group, feature in ipairs(model.features) do
            local function prepare(id)
                if id then projection(model, matrix, selector, group, feature, id) end
            end
            prepare(feature.unknown)
            prepare(feature.dictionary[""])
            prepare(feature.dictionary["<root>"])
            if feature.kind == "universal_tag" then
                for _, id in pairs(feature.dictionary) do prepare(id) end
            end
        end
    end
    matrix.prepared = true
end

local function classify(model, matrix, stack, buffer, nodes, memo, scores, hidden, checkpoint)
    local width = model.hiddenSize
    local bias = #model.selectors * model.dimension * width
    for index = 1, width do hidden[index] = matrix.hidden[bias + index] end
    for index, slot in ipairs(model.selectors) do
        local node = nodeAt(slot, stack, buffer, nodes)
        if node then
            local projected = memo[index]
            for group, feature in ipairs(model.features) do
                local id = node.embeddings[group]
                -- Only dependency labels change as the parser applies arcs.
                if feature.kind == "deprel" then id = embeddingID(feature, node.relation) end
                if id then
                    local cache = projected[group]
                    local vector = cache[id]
                    if not vector then
                        vector = projection(model, matrix, index, group, feature, id, checkpoint)
                        cache[id] = vector
                        memo.count = memo.count + 1
                    end
                    accumulate(hidden, vector, 0, 1, width)
                end
            end
        end
        if checkpoint then checkpoint() end
    end

    local count, output = #model.labels * 2 + 1, matrix.output
    for index = 1, width do hidden[index] = activate(hidden[index], model.activation) end
    for index = 1, count do
        local score, offset = output[width * count + index], index
        for unit = 1, width do
            score = score + hidden[unit] * output[offset]
            offset = offset + count
        end
        scores[index] = score
        if checkpoint and index % 8 == 0 then checkpoint() end
    end
end

local function transitions(model, stack, buffer, visit)
    if #buffer > 0 then visit(1) end
    local size = #stack
    if size < 2 then return end
    for index, label in ipairs(model.labels) do
        local root = model.singleRoot and label == "root"
        if not root and stack[size - 1] ~= 0 then visit(2 * index) end
        if not model.singleRoot or (root and size == 2 and #buffer == 0) or (not root and size > 2) then
            visit(2 * index + 1)
        end
    end
end

local function applyArc(nodes, child, parent, relation)
    local node, children = nodes[child], nodes[parent].children
    node.head, node.relation = parent, relation
    local insert = #children + 1
    while insert > 1 and children[insert - 1] > child do insert = insert - 1 end
    table.insert(children, insert, child)
end

local function apply(model, state, transition)
    local stack, buffer, nodes = state.stack, state.buffer, state.nodes
    local size = #stack
    if transition == 1 then
        stack[size + 1] = buffer[#buffer]
        buffer[#buffer] = nil
    else
        local top, below = stack[size], stack[size - 1]
        local label = model.labels[floor(transition / 2)]
        if transition % 2 == 0 then
            applyArc(nodes, below, top, label)
            stack[size - 1] = top
        else
            applyArc(nodes, top, below, label)
        end
        stack[size] = nil
    end
end

local function copy(values)
    local result = {}
    for key, value in pairs(values) do result[key] = value end
    return result
end

local function branch(state)
    local nodes = {}
    for index, node in pairs(state.nodes) do
        nodes[index] = copy(node)
        nodes[index].children = copy(node.children)
    end
    return {stack=copy(state.stack), buffer=copy(state.buffer), nodes=nodes}
end

local function finish(state)
    return #state.stack <= 1 and #state.buffer == 0
end

local function searchGreedy(model, matrix, memo, state, checkpoint)
    local scores, hidden = {}, {}
    local best, bestCost
    local function visit(transition)
        local cost = state.cost + scores[transition]
        if not best or cost > bestCost then best, bestCost = transition, cost end
    end
    while not finish(state) do
        classify(model, matrix, state.stack, state.buffer, state.nodes, memo, scores, hidden, checkpoint)
        best, bestCost = nil, nil
        transitions(model, state.stack, state.buffer, visit)
        if not best then return nil end
        state.cost = bestCost
        apply(model, state, best)
    end
    return state.nodes
end

local function normalizedLoss(scores)
    local maximum = scores[1]
    for index = 2, #scores do maximum = math.max(maximum, scores[index]) end
    local total = 0
    for _, score in ipairs(scores) do total = total + exp(score - maximum) end
    return math.log(total) + maximum
end

local function searchBeam(model, matrix, memo, initial, beam, checkpoint)
    local states = {initial}
    local scores, hidden = {}, {}
    while not finish(states[1]) do
        local candidates = {}
        for _, state in ipairs(states) do
            classify(model, matrix, state.stack, state.buffer, state.nodes, memo, scores, hidden, checkpoint)
            local norm = normalizedLoss(scores)
            transitions(model, state.stack, state.buffer, function(transition)
                local cost = state.cost + scores[transition] - norm
                local at = #candidates + 1
                while at > 1 and candidates[at - 1].cost < cost do at = at - 1 end
                if at <= beam then
                    table.insert(candidates, at, {state=state, transition=transition, cost=cost})
                    candidates[beam + 1] = nil
                end
            end)
        end
        if #candidates == 0 then return nil end
        states = {}
        for _, selected in ipairs(candidates) do
            local state = branch(selected.state)
            state.cost = selected.cost
            apply(model, state, selected.transition)
            states[#states + 1] = state
        end
    end
    -- Every projective path takes exactly two transitions per source word.
    return states[1].nodes
end

-- The caller supplies the same UD features consumed by the native parser.
-- Head zero denotes the root.
function U.parse(model, words, beam, workspace, checkpoint)
    beam = beam or 5
    if not model or #words == 0 or #words > 64 or beam < 1 or beam > 5 or beam % 1 ~= 0 then return nil end
    local matrix = cacheModel(model, checkpoint)
    local stack, buffer = {0}, {}
    local nodes = {[0]={form="<root>", lemma="<root>", upos="<root>", xpos="<root>",
        feats="<root>", children={}, relation=""}}
    for index, word in ipairs(words) do
        nodes[index] = {form=word.form:gsub(" ", "\194\160"), lemma=(word.lemma or ""):gsub(" ", "\194\160"),
            upos=word.upos or "", xpos=word.xpos or "", 
            feats=word.feats or "", misc=word.misc, children={}, relation=""}
        buffer[#words - index + 1] = index
    end
    for index = 0, #words do
        local node, embeddings = nodes[index], {}
        for group, feature in ipairs(model.features) do
            if feature.kind ~= "deprel" then
                embeddings[group] = embeddingID(feature, valueOf(node, feature.kind))
            end
        end
        node.embeddings = embeddings
    end
    local memo = workspace and workspace[model]
    -- Reuse projections for this message and model. Retain at most one parse's
    -- growth above the reuse threshold before resetting on the next range.
    if not memo or memo.count >= 512 then
        memo = {count=0}
        for index = 1, #model.selectors do
            memo[index] = {}
            for feature = 1, #model.features do memo[index][feature] = {} end
        end
        if workspace then workspace[model] = memo end
    end

    local initial = {stack=stack, buffer=buffer, nodes=nodes, cost=0}
    if beam == 1 then nodes = searchGreedy(model, matrix, memo, initial, checkpoint)
    else nodes = searchBeam(model, matrix, memo, initial, beam, checkpoint) end
    if not nodes then return nil end
    local arcs = {}
    for index = 1, #words do arcs[index] = {head=nodes[index].head, relation=nodes[index].relation} end
    return arcs
end
