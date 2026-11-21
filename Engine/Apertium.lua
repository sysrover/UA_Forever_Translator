local _, ns = ...
local A = {}; ns.Engine.Apertium = A

-- Cache only decoded graph states. Readings stay scoped to each message.
local stateCaches = setmetatable({}, {__mode="k"})
local stateLimit = 1024

local function readState(graph, state)
    local block = graph.blocks[math.floor(state / graph.blockSize) + 1]
    if not block then return end
    local _, start = block:find("\n" .. state .. "\t", 1, true)
    if not start then return end
    local tab = block:find("\t", start + 1, true)
    local finish = block:find("\n", tab + 1, true)
    local row = {final=tonumber(block:sub(start + 1, tab - 1))}
    -- Store arcs in source order as input, target, output text and weight.
    local arcs = block:sub(tab + 1, finish - 1)
    for input, target, output, weight in arcs:gmatch("(%d+):(%d+):(%d+):([^,]+),") do
        row[#row + 1] = tonumber(input)
        row[#row + 1] = tonumber(target)
        row[#row + 1] = graph.output[tonumber(output)] or ""
        row[#row + 1] = tonumber(weight)
    end
    return row
end

local function stateAt(graph, cache, state)
    local row = cache.rows[state]
    if row ~= nil then return row end
    row = readState(graph, state) or false
    local slot = cache.next
    local previous = cache.order[slot]
    if previous then cache.rows[previous] = nil end
    cache.rows[state], cache.order[slot] = row, state
    cache.next = slot % stateLimit + 1
    return row
end

-- Run a weighted finite-state transducer. Keep alternatives until a word is
-- consumed and a final state is reached. Epsilon edges can emit tags.
local function run(graph, symbols, acceptTags)
    local cache = stateCaches[graph]
    if not cache then
        cache = {rows={}, order={}, next=1}
        stateCaches[graph] = cache
    end
    local paths = {{state=0, index=1, text="", weight=0, tags=acceptTags and ""}}
    local visited, values, steps = {}, {}, 0
    while #paths > 0 do
        local path = paths[#paths]
        paths[#paths] = nil
        local key = path.state .. ":" .. path.index .. ":" .. path.text .. "\t" .. (path.tags or "")
        if not visited[key] or path.weight < visited[key] then
            visited[key] = path.weight
            steps = steps + 1
            if steps > 2048 then return nil, "limit" end
            local row = stateAt(graph, cache, path.state)
            local final = row and row.final
            local input = symbols[path.index]
            if not input and final and (not acceptTags or acceptTags(path.tags)) then
                local weight = path.weight + final
                if not values[path.text] or values[path.text] > weight then values[path.text] = weight end
            end
            if row then
                for arc = 1, #row, 4 do
                    local left = row[arc]
                    local label = not input and acceptTags and graph.output[left]
                    local tag = label and label:match("^<[%w]+>$")
                    if left == 0 or left == input or tag then
                        local target, output, weight = row[arc + 1], row[arc + 2], row[arc + 3]
                        paths[#paths + 1] = {state=target, index=path.index + (left == input and 1 or 0),
                            text=path.text .. output, weight=path.weight + weight,
                            tags=tag and path.tags .. tag or path.tags}
                    end
                end
            end
        end
    end
    return values
end

local function wordSymbols(graph, word)
    if not graph or #word == 0 or #word > 96 then return nil end
    local symbols = {}
    for char in word:gmatch("[^\128-\191][\128-\191]*") do
        local symbol = graph.input[char]
        if not symbol then return nil end
        symbols[#symbols + 1] = symbol
    end
    if #symbols > 0 then return symbols end
end

local function analyze(word, lang)
    local graph = ns.ApertiumData and ns.ApertiumData.analysis[lang]
    local symbols = wordSymbols(graph, word)
    if symbols then return run(graph, symbols) end
end

function A.analyze(word, lang, document)
    if not document then return analyze(word, lang) end
    local analyses = document.apertiumAnalyses
    if not analyses then analyses = {}; document.apertiumAnalyses = analyses end
    local language = analyses[lang]
    if not language then language = {}; analyses[lang] = language end
    local result = language[word]
    if result then return result.values, result.reason end
    local values, reason = analyze(word, lang)
    language[word] = {values=values, reason=reason}
    return values, reason
end

local parts = {n="noun", adj="adj", det="det", adv="adv", vblex="verb"}
local cases = {nom="nominative", gen="genitive", dat="dative", acc="accusative",
    ins="instrumental", loc="locative", voc="vocative"}
local genders = {m="masculine", f="feminine", nt="neuter"}
local numbers = {sg="singular", pl="plural"}
local tenses = {pres="present", past="past", fut="future"}
local people = {p1=1, p2=2, p3=3}
local animacy = {aa="animate", nn="inanimate"}
local aspect = {perf="perfective", impf="imperfective"}
local degrees = {cmp="comparative", comp="comparative", sup="superlative"}

local fieldsByTag, valuesByTag = {}, {}
for field, mapping in pairs({case=cases, gender=genders, number=numbers, tense=tenses,
    person=people, animacy=animacy, aspect=aspect, degree=degrees}) do
    for tag, value in pairs(mapping) do
        fieldsByTag[tag], valuesByTag[tag] = field, value
    end
end

local function readTags(raw)
    local tags, features = {}, {}
    for tag in raw:gmatch("<([%w]+)>") do
        tags[tag] = true
        local field = fieldsByTag[tag]
        if field then features[field] = valuesByTag[tag] end
    end
    return tags, features
end

local function participle(tags, form)
    if not (tags.pp or tags.pprs) or not form.case or not form.number then return nil end
    if tags.pasv then form.voice = "passive"
    elseif tags.actv then form.voice = "active"
    else return nil end
    form.verbalForm = "participle"
    return form
end

function A.readParticiple(analysis)
    local base, raw = analysis:match("^([^<+/#]+)<vblex>(<[^+/#]+>)$")
    if not raw then return nil end
    local tags, features = readTags(raw)
    local form = participle(tags, features)
    if form then return base, "participle", form end
end

local function inflection(pos, tags, form, lang)
    if lang == "en" then
        if pos == "noun" and form.number and not tags.gen then return {number=form.number} end
        if pos == "verb" then
            if tags.inf then return {mood="base"} end
            if tags.pp then return {tense="past", verbalForm="participle"} end
            if tags.pprs then return {tense="present", verbalForm="participle"} end
            if form.tense == "past" or form.tense == "present" and form.person == 3 and form.number == "singular" then
                return form
            end
        elseif pos == "adj" and form.degree then return {degree=form.degree} end
    elseif (pos == "noun" or pos == "adj" or pos == "det") and form.case and form.number then
        return form
    elseif pos == "verb" and not (tags.pp or tags.pprs or tags.pasv or tags.actv or tags.impers) then
        if tags.inf then form.mood = "infinitive"
        elseif tags.imp and form.person and form.number then form.mood = "imperative"
        elseif form.tense == "past" and form.number and (form.number == "plural" or form.gender) then
            return form
        elseif (form.tense == "present" or form.tense == "future") and form.person and form.number then
            return form
        else return nil end
        return form
    end
end

function A.read(analysis, lang)
    local base, part, raw = analysis:match("^([^<+/#]+)<([%w]+)>(.+)$")
    local pos = part and parts[part]
    if not pos or not raw:match("^<[^+/#]+>$") then return nil end
    local tags, features = readTags(raw)
    local form = inflection(pos, tags, features, lang)
    if form then return base, pos, form end
end

-- UDPipe needs the raw tags even when the analysis has no transferable inflection.
function A.dependencyFeatures(part, raw, lang)
    local tags, features = readTags(raw)
    local pos = parts[part]
    local form
    if pos and raw:match("^<[^+/#]+>$") then
        if lang == "uk" and part == "vblex" then form = participle(tags, features) end
        form = form or inflection(pos, tags, features, lang)
    end
    return tags, form or {}
end

function A.generate(lemma, lang, pos, requested, head)
    local graph = ns.ApertiumData and ns.ApertiumData.generation[lang]
    local symbols = wordSymbols(graph, lemma)
    if not symbols then return nil end
    local function compatible(tags)
        local _, category, form
        if pos == "participle" and lang == "uk" then
            _, category, form = A.readParticiple(lemma .. tags)
        else
            _, category, form = A.read(lemma .. tags, lang)
        end
        if category ~= pos then return false end
        for key, value in pairs(requested or {}) do
            if key == "mood" and value == "indicative" then
                if form.mood or form.verbalForm then return false end
            elseif form[key] ~= value then return false end
        end
        return not head or not form.animacy or not head.animacy or head.animacy == form.animacy
    end
    local values = run(graph, symbols, compatible)
    local best, score, ambiguous
    for word, weight in pairs(values or {}) do
        if not score or weight < score then best, score, ambiguous = word, weight, false
        elseif weight == score then ambiguous = true end
    end
    if not ambiguous then return best end
end
