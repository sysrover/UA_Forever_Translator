local _, ns = ...
local A = {}; ns.Engine.Apertium = A

local function arcsAt(graph, state)
    local block = graph.blocks[math.floor(state / graph.blockSize) + 1]
    if not block then return end
    local _, start = block:find("\n" .. state .. "\t", 1, true)
    if not start then return end
    local tab = block:find("\t", start + 1, true)
    local finish = block:find("\n", tab + 1, true)
    return tonumber(block:sub(start + 1, tab - 1)), block:sub(tab + 1, finish - 1)
end

-- Run a weighted finite-state transducer. Keep alternatives until a word is
-- consumed and a final state is reached. Epsilon edges can emit tags.
local function run(graph, symbols, acceptTags)
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
            local final, arcs = arcsAt(graph, path.state)
            local input = symbols[path.index]
            if not input and final and (not acceptTags or acceptTags(path.tags)) then
                local weight = path.weight + final
                if not values[path.text] or values[path.text] > weight then values[path.text] = weight end
            end
            if arcs then
                for inputID, target, outputID, weight in arcs:gmatch("(%d+):(%d+):(%d+):([^,]+),") do
                    local left, right = tonumber(inputID), tonumber(outputID)
                    local label = not input and acceptTags and graph.output[left]
                    local tag = label and label:match("^<[%w]+>$")
                    if left == 0 or left == input or tag then
                        paths[#paths + 1] = {state=tonumber(target), index=path.index + (left == input and 1 or 0),
                            text=path.text .. (graph.output[right] or ""), weight=path.weight + tonumber(weight),
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

local function readTags(raw)
    local tags, features = {}, {}
    local function assign(key, value)
        if value then features[key] = value end
    end
    for tag in raw:gmatch("<([%w]+)>") do
        tags[tag] = true
        assign("case", cases[tag])
        assign("gender", genders[tag])
        assign("number", numbers[tag])
        assign("tense", tenses[tag])
        assign("person", people[tag])
        assign("animacy", animacy[tag])
        assign("aspect", aspect[tag])
        assign("degree", degrees[tag])
    end
    return tags, features
end

function A.readParticiple(analysis)
    local base, raw = analysis:match("^([^<+/#]+)<vblex>(<[^+/#]+>)$")
    if not raw then return nil end
    local tags, form = readTags(raw)
    if not (tags.pp or tags.pprs) or not form.case or not form.number then return nil end
    if tags.pasv then form.voice = "passive"
    elseif tags.actv then form.voice = "active"
    else return nil end
    form.verbalForm = "participle"
    return base, "participle", form
end

function A.read(analysis, lang)
    local base, part, raw = analysis:match("^([^<+/#]+)<([%w]+)>(.+)$")
    local pos = part and parts[part]
    if not pos or not raw:match("^<[^+/#]+>$") then return nil end
    local tags, form = readTags(raw)
    if lang == "en" then
        if pos == "noun" and form.number and not tags.gen then return base, pos, {number=form.number} end
        if pos == "verb" then
            if tags.inf then return base, pos, {mood="base"} end
            if tags.pp then return base, pos, {tense="past", verbalForm="participle"} end
            if tags.pprs then return base, pos, {tense="present", verbalForm="participle"} end
            if form.tense == "past" or form.tense == "present" and form.person == 3 and form.number == "singular" then
                return base, pos, form
            end
        elseif pos == "adj" and form.degree then return base, pos, {degree=form.degree} end
    elseif (pos == "noun" or pos == "adj" or pos == "det") and form.case and form.number then
        return base, pos, form
    elseif pos == "verb" and not (tags.pp or tags.pprs or tags.pasv or tags.actv or tags.impers) then
        if tags.inf then form.mood = "infinitive"
        elseif tags.imp and form.person and form.number then form.mood = "imperative"
        elseif form.tense == "past" and form.number and (form.number == "plural" or form.gender) then
            return base, pos, form
        elseif (form.tense == "present" or form.tense == "future") and form.person and form.number then
            return base, pos, form
        else return nil end
        return base, pos, form
    end
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
