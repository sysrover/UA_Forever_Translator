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
local warmLimits = {universal_tag=32, feats=24, form=40, deprel=24}
local embeddingLimit = 256
local greedyDecisionLimit = 512
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

local function outputRows(model, checkpoint)
    local flat = decode(model.output, checkpoint)
    local count, width = #model.labels * 2 + 1, model.hiddenSize
    local rows = {}
    for transition = 1, count do
        local row = {bias=flat[width * count + transition]}
        local offset = transition
        for column = 1, width do
            row[column], offset = flat[offset], offset + count
        end
        rows[transition] = row
        if checkpoint and transition % 8 == 0 then checkpoint() end
    end
    return rows
end

local function cacheModel(model, checkpoint)
    local matrix = matrices[model]
    if matrix then return matrix end
    matrix = {hidden=decode(model.hidden, checkpoint), output=outputRows(model, checkpoint),
        readyProjections={}, projections={}, projectionOrder={}, nextProjection=1,
        embeddings={}, embeddingOrder={}, nextEmbedding=1}
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

local function embeddingWeights(model, matrix, feature, id)
    -- The same input vector feeds every selector's separate projection.
    local cache = matrix.embeddings[feature]
    if not cache then cache = {}; matrix.embeddings[feature] = cache end
    local values = cache[id]
    if values then return values end

    values = {}
    local first = (id - 1) * feature.dimension
    for dimension = 0, feature.dimension - 1 do
        local offset = first + dimension
        local block = feature.weights[floor(offset / model.blockSize) + 1]
        values[dimension + 1] = readFloat(block, (offset % model.blockSize) * 5 + 1)
    end

    local index = matrix.nextEmbedding
    local slot = matrix.embeddingOrder[index]
    if slot then slot.cache[slot.id] = nil
    else slot = {}; matrix.embeddingOrder[index] = slot end
    slot.cache, slot.id = cache, id
    cache[id] = values
    matrix.nextEmbedding = index == embeddingLimit and 1 or index + 1
    return values
end

local function projection(model, matrix, selector, group, feature, id, checkpoint, pin)
    local ready = matrix.readyProjections[selector]
    local prepared = ready and ready[group] and ready[group][id]
    if prepared then return prepared end

    local cache = pin and matrix.readyProjections or matrix.projections
    local groups = cache[selector]
    if not groups then groups = {}; cache[selector] = groups end
    local vectors = groups[group]
    if not vectors then vectors = {}; groups[group] = vectors end
    if vectors[id] then return vectors[id] end

    local width, vector = model.hiddenSize, {}
    local weights = matrix.hidden
    local embedding = embeddingWeights(model, matrix, feature, id)
    local rowOffset = ((selector - 1) * model.dimension + feature.offset) * width
    for column = 1, width do vector[column] = 0 end
    local dimensionCount = feature.dimension
    -- Keep the original addition order and share one vector update and checkpoint across four rows.
    local grouped = dimensionCount - dimensionCount % 4
    for dimension = 1, grouped, 4 do
        local first, second = rowOffset, rowOffset + width
        local third, fourth = second + width, second + 2 * width
        local a, b = embedding[dimension], embedding[dimension + 1]
        local c, d = embedding[dimension + 2], embedding[dimension + 3]
        for column = 1, width do
            local value = vector[column] + a * weights[first + column]
            value = value + b * weights[second + column]
            value = value + c * weights[third + column]
            vector[column] = value + d * weights[fourth + column]
        end
        rowOffset = fourth + width
        if checkpoint then checkpoint() end
    end
    for dimension = grouped + 1, dimensionCount do
        accumulate(vector, weights, rowOffset, embedding[dimension], width)
        rowOffset = rowOffset + width
    end

    -- Numerical vectors depend only on the immutable model and embedding ID.
    if vectors[id] then return vectors[id] end
    if pin then
        vectors[id] = vector
        return vector
    end
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
    -- Parsito assigns low dictionary IDs to frequent values in these models.
    -- Keep this fixed startup set outside the ring used by rare values from chat.
    local selected = {}
    for group, feature in ipairs(model.features) do
        local ids = {}
        local limit = warmLimits[feature.kind] or 0
        for _, id in pairs(feature.dictionary) do
            if id <= limit then ids[id] = true end
        end
        local defaults = {feature.unknown, feature.dictionary[""], feature.dictionary["<root>"]}
        for _, id in pairs(defaults) do ids[id] = true end
        selected[group] = ids
    end
    for selector = 1, #model.selectors do
        for group, feature in ipairs(model.features) do
            for id in pairs(selected[group]) do
                projection(model, matrix, selector, group, feature, id, nil, true)
            end
        end
    end
    matrix.prepared = true
end

local function classify(model, matrix, stack, buffer, nodes, memo, scores, hidden, checkpoint, allowed, allowedCount)
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
                    for unit = 1, width do hidden[unit] = hidden[unit] + vector[unit] end
                end
            end
        end
        if checkpoint then checkpoint() end
    end

    local output = matrix.output
    for index = 1, width do hidden[index] = activate(hidden[index], model.activation) end
    for choice = 1, allowedCount or #output do
        local index = allowed and allowed[choice] or choice
        local row = output[index]
        local score = row.bias
        for unit = 1, width do
            score = score + hidden[unit] * row[unit]
        end
        scores[index] = score
        if checkpoint and choice % 8 == 0 then checkpoint() end
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

local function greedyKey(model, state, shape, parts)
    local count = 1
    parts[1] = shape
    for _, selector in ipairs(model.selectors) do
        local node = nodeAt(selector, state.stack, state.buffer, state.nodes)
        if node then
            for group, feature in ipairs(model.features) do
                local id = node.embeddings[group]
                if feature.kind == "deprel" then id = embeddingID(feature, node.relation) end
                count = count + 1
                parts[count] = id or "_"
            end
        else
            count = count + 1
            parts[count] = "-"
        end
    end
    return table.concat(parts, ",", 1, count)
end

local function searchGreedy(model, matrix, memo, state, checkpoint, decisions)
    local scores, hidden, parts, transitionLists = {}, {}, {}, {}
    while not finish(state) do
        local stack, buffer = state.stack, state.buffer
        local size = #stack
        -- The legal transition list depends on stack size, root position and a nonempty buffer.
        local shape = math.min(size, 3) + (#buffer > 0 and 4 or 0) + (stack[size - 1] == 0 and 8 or 0)
        local allowed = transitionLists[shape]
        if not allowed then
            allowed = {}
            transitions(model, stack, buffer, function(transition) allowed[#allowed + 1] = transition end)
            transitionLists[shape] = allowed
        end
        local count = #allowed
        if count == 0 then return nil end
        -- A forced transition needs no score. With a choice, only the best
        -- applicable score matters to greedy decoding.
        local best = allowed[1]
        if count > 1 then
            local key = decisions and greedyKey(model, state, shape, parts)
            local cached = key and decisions.entries[key]
            if cached then
                best = cached
            else
                classify(model, matrix, stack, buffer, state.nodes, memo, scores, hidden, checkpoint, allowed, count)
                for index = 2, count do
                    local transition = allowed[index]
                    if scores[transition] > scores[best] then best = transition end
                end
                -- Scoring may yield while another parse stores the same decision.
                if key and not decisions.entries[key] then
                    local slot = decisions.next
                    local previous = decisions.order[slot]
                    if previous then decisions.entries[previous] = nil end
                    decisions.order[slot] = key
                    decisions.entries[key] = best
                    decisions.next = slot == greedyDecisionLimit and 1 or slot + 1
                end
            end
        end
        if checkpoint then checkpoint() end
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
        if checkpoint and index % 8 == 0 then checkpoint() end
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
    if beam == 1 then
        local decisions
        if workspace and #words >= 5 then
            -- A model can reuse the same transition for identical embedding IDs
            -- and legal moves across ranges and messages.
            decisions = matrix.greedyDecisions
            if not decisions then
                decisions = {entries={}, order={}, next=1}
                matrix.greedyDecisions = decisions
            end
        end
        nodes = searchGreedy(model, matrix, memo, initial, checkpoint, decisions)
    else nodes = searchBeam(model, matrix, memo, initial, beam, checkpoint) end
    if not nodes then return nil end
    local arcs = {}
    for index = 1, #words do arcs[index] = {head=nodes[index].head, relation=nodes[index].relation} end
    return arcs
end
