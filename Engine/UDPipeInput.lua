local _, ns = ...
local U = ns.Engine.UDPipe
local A, L = ns.Engine.Apertium, ns.Engine.Lexicon

local parts = {
    n="NOUN", np="PROPN", adj="ADJ", adv="ADV", det="DET", prn="PRON", pr="ADP",
    vblex="VERB", vaux="AUX", vbser="AUX", vbhaver="AUX", vbmod="AUX", vbdo="AUX",
    cnjcoo="CCONJ", cnjsub="SCONJ", cnjadv="SCONJ", num="NUM", ij="INTJ", part="PART",
}
local lexicalParts = {noun="NOUN", verb="VERB", adj="ADJ", adv="ADV", pron="PRON", num="NUM"}
local ranks = {NOUN=5, VERB=4, ADJ=3, ADV=3, SCONJ=4, ADP=6, AUX=6, PROPN=5}
local auxiliaryClitics = {
    is={"is","be","present"}, are={"are","be","present"},
    was={"was","be","past"}, were={"were","be","past"},
    ["do"]={"do","do","present"}, does={"does","do","present"}, did={"did","do","past"},
    have={"have","have","present"}, has={"has","have","present"}, had={"had","have","past"},
    ca={"can","can"}, could={"could","could"}, wo={"will","will"},
    would={"would","would"}, should={"should","should"}, must={"must","must"}, might={"might","might"},
}
local dimensions = {
    case={nominative="Nom", genitive="Gen", dative="Dat", accusative="Acc",
        instrumental="Ins", locative="Loc", vocative="Voc"},
    gender={masculine="Masc", feminine="Fem", neuter="Neut"},
    number={singular="Sing", plural="Plur"},
    tense={present="Pres", past="Past", future="Fut"},
    aspect={perfective="Perf", imperfective="Imp"},
    animacy={animate="Anim", inanimate="Inan"},
    degree={comparative="Cmp", superlative="Sup"},
}

local function udFeatures(candidate, lang)
    local form, pos, tags = candidate.form, candidate.pos, candidate.tags
    local values = {}
    local function put(key, value)
        if value then values[#values + 1] = key .. "=" .. value end
    end
    put("Number", dimensions.number[form.number])
    if lang == "uk" or pos == "PRON" then
        put("Animacy", lang == "uk" and dimensions.animacy[form.animacy])
        put("Case", dimensions.case[form.case])
        put("Gender", dimensions.gender[form.gender])
    end
    if pos == "VERB" or pos == "AUX" then
        if tags.neg then put("Polarity", "Neg") end
        put("Aspect", lang == "uk" and dimensions.aspect[form.aspect])
        if form.mood == "infinitive" or tags.inf then put("VerbForm", "Inf")
        elseif form.verbalForm == "participle" or tags.ger then
            put("Tense", dimensions.tense[form.tense])
            put("VerbForm", tags.ger and "Ger" or "Part")
        elseif form.tense or tags.pres or tags.past or tags.imp then
            put("Mood", (form.mood == "imperative" or tags.imp) and "Imp" or "Ind")
            put("Person", form.person)
            put("Tense", dimensions.tense[form.tense] or (tags.pres and "Pres") or (tags.past and "Past"))
            put("VerbForm", "Fin")
        end
    elseif pos == "PRON" then
        put("Person", form.person)
        put("PronType", tags.rel and "Rel" or tags.itg and "Int" or tags.dem and "Dem" or "Prs")
    elseif pos == "DET" then
        put("PronType", tags.dem and "Dem" or tags.itg and "Int" or (tags.def or tags.ind) and "Art")
        put("Definite", tags.def and "Def" or tags.ind and "Ind")
    elseif pos == "ADJ" or pos == "ADV" then
        put("Degree", dimensions.degree[form.degree] or (tags.sint and "Pos"))
    end
    table.sort(values)
    return table.concat(values, "|")
end

local function rank(pos, previous, following, tags)
    local score = ranks[pos] or 8
    if pos == "NOUN" and (previous == "DET" or previous == "ADJ" or previous == "ADP") then score = score + 12 end
    if pos == "VERB" and (previous == "NOUN" or previous == "PRON" or previous == "AUX") then score = score + 8 end
    if pos == "ADJ" and previous == "DET" and following ~= "" then score = score + 10 end
    if pos == "VERB" and (tags.pres or tags.past or tags.pprs) then score = score + 1 end
    if tags.inf or tags.imp then score = score - 2 end
    return score
end

local function lexicalCandidates(document, index, lang, offer)
    local token = document.tokens[index]
    local readings = A.analyze(token.key, lang) or {}
    local found
    for raw, weight in pairs(readings) do
        local lemma, kind, suffix = raw:match("^([^<+/#]+)<(%w+)>(.*)$")
        if kind and parts[kind] and not suffix:find("[+/#]") then
            local tags = {}
            for tag in suffix:gmatch("<(%w+)>") do tags[tag] = true end
            local _, _, form = A.read(raw, lang)
            form = form or {}
            if not form.person then form.person = tags.p1 and 1 or tags.p2 and 2 or tags.p3 and 3 or nil end
            if not form.number then form.number = tags.sg and "singular" or tags.pl and "plural" or nil end
            if not form.case and lang == "en" and kind == "prn" then
                form.case = tags.subj and "nominative" or tags.obj and "accusative" or nil
            end
            offer(lemma, parts[kind], form, tags, weight, raw)
            found = true
        end
    end
    if not found then
        for _, entry in ipairs(L.at(document, index)) do
            local pos = lexicalParts[entry.lexeme.pos]
            if pos then
                local lemma = entry.lexeme[lang]
                offer(lemma,pos,entry.form,{},0,pos .. ":" .. lemma)
            end
        end
    end
    for _, entry in ipairs(document.spans[index] or {}) do
        local features = entry.features
        if entry.last == index and features.pos == "noun" and not features.verbatim then
            local lemma = ns.Engine.Normalize.word(entry.lemma)
            offer(lemma, "NOUN", features, {}, 0, "curated:" .. entry.id)
        end
    end
end

local function choose(document, index, lang, previous, following, hint)
    local best, priority, order
    lexicalCandidates(document, index, lang, function(lemma, pos, form, tags, weight, key)
        if hint and pos ~= hint then return end
        local score = rank(pos, previous, following, tags) - weight
        if not best or score > priority or (score == priority and key < order) then
            best, priority, order = {lemma=lemma, pos=pos, form=form, tags=tags}, score, key
        end
    end)
    return best
end

local function fixedTag(token, index, marker, markerEnd, markerTags)
    if token.protected then return "NOUN" end
    if marker and index >= marker and index <= markerEnd then
        return markerTags and markerTags[index - marker + 1] or "SCONJ"
    end
    if token.key:match("^%d+$") then return "NUM" end
    if token.key:match("^%p$") or token.key == "…" or token.key == "—" then return "PUNCT" end
end

local function pronounCandidate(document, index, lang)
    local readings, finish = L.functional(document, "pronouns", index, index)
    if not readings or finish ~= index then return end
    local reading = readings[1]
    local pronoun = ns.Linguistics.grammar.pronouns[reading.id]
    local number = lang == "uk" and pronoun.ukNumber or pronoun.number
    return {lemma=pronoun[lang].nominative, pos="PRON", tags={},
        form={person=pronoun.person, number=number, gender=pronoun.gender, case=reading.case}}
end

local function englishCandidates(document, index, raw, weights)
    local tagIds = weights.ids
    local key = document.tokens[index].key
    local contraction = auxiliaryClitics[key:match("^(%a+)n't$")]
    if contraction then
        local surface, lemma, tense = unpack(contraction)
        return {[tagIds.AUX]={lemma=lemma, pos="AUX", modelForm=surface,
            form={tense=tense}, tags={neg=true}}}
    end
    local candidates = {}
    lexicalCandidates(document, index, "en", function(lemma, pos, form, tags, weight, reading)
        local id = tagIds[pos]
        local score = rank(pos, nil, "", tags) - weight
        local previous = candidates[id]
        if not previous or score > previous.rank or (score == previous.rank and reading < previous.reading) then
            candidates[id] = {lemma=lemma, pos=pos, form=form, tags=tags, rank=score, reading=reading}
        end
    end)

    local pronoun = pronounCandidate(document, index, "en")
    if pronoun then candidates[tagIds.PRON] = pronoun end
    local word = weights.words[key]
    if word then
        for _, candidate in pairs(candidates) do candidate.emission = word[1] end
        for offset = 2, #word, 3 do
            local id, emission, feats = word[offset], word[offset + 1], word[offset + 2]
            local candidate = candidates[id] or {lemma=key, pos=weights.tags[id]}
            candidate.emission, candidate.feats = emission, feats
            candidates[id] = candidate
        end
    end
    if raw ~= key then
        candidates[tagIds.PROPN] = candidates[tagIds.PROPN] or {lemma=key, pos="PROPN", emission=word and word[1]}
    elseif candidates[tagIds.PROPN] and not candidates[tagIds.PROPN].form then
        candidates[tagIds.PROPN].emission = candidates[tagIds.PROPN].emission - 180
    end
    if not next(candidates) then candidates[tagIds.X] = {lemma=key, pos="X"} end
    return candidates
end

local function tagEnglish(document, first, last, marker, markerEnd, weights, hints, markerTags)
    local tagIds = weights.ids
    local boundary = tagIds[""]
    local previous = {[boundary]={score=0}}
    local words = {}
    local quantifiedHeads
    -- Viterbi over the available readings, retaining one predecessor for each part of speech.
    for index = first, last do
        local token = document.tokens[index]
        if ns.Linguistics and (token.key == "many" or token.key == "much" and document.tokens[index + 1]
            and document.tokens[index + 1].key == "more") then
            local noun = ns.Engine.Phrases.noun(document, index, last, "nominative", nil, nil, true)
            if noun and noun.headIndex and (noun.many or noun.degreeMore) then
                quantifiedHeads = quantifiedHeads or {}
                quantifiedHeads[noun.headIndex] = "NOUN"
            end
        end
        local raw = token.protected and "item" or document.text:sub(token.first, token.last)
        local pos = fixedTag(token, index, marker, markerEnd, markerTags)
        local candidates = pos and {[tagIds[pos]]={pos=pos, lemma=token.key}}
            or englishCandidates(document, index, raw, weights)
        local hint = not pos and (hints and hints[index] or quantifiedHeads and quantifiedHeads[index])
        local hintedId = tagIds[hint == true and "VERB" or hint]
        if hintedId then
            candidates = {[hintedId]=candidates[hintedId] or {pos=weights.tags[hintedId], lemma=token.key}}
        end
        for id, candidate in pairs(candidates) do
            local best, from
            for previousId, entry in pairs(previous) do
                local score = entry.score + weights.transitions[previousId][id]
                if not best or score > best or (score == best and previousId < from) then
                    best, from = score, previousId
                end
            end
            candidate.score = best + (candidate.emission or 0)
            candidate.previous = previous[from]
            candidate.raw = candidate.modelForm or raw
        end
        previous = candidates
    end
    local best, selected
    for id, candidate in pairs(previous) do
        local score = candidate.score + weights.transitions[id][boundary]
        if not best or score > best or (score == best and id < selected) then
            best, selected = score, id
        end
    end
    local candidate = previous[selected]
    for index = last - first + 1, 1, -1 do
        local feats = candidate.feats
        if feats == nil and candidate.form then feats = udFeatures(candidate, "en") end
        words[index] = {form=candidate.raw, lemma=candidate.lemma, upos=candidate.pos, feats=feats}
        candidate = candidate.previous
    end
    return words
end

local function analyzeDocument(document, first, last, marker, markerEnd, hints, markerTags, alternatives, commaBefore)
    local lang = document.direction == "en-uk" and "en" or "uk"
    local model = ns.UDPipeModels and ns.UDPipeModels[lang]
    if not model or last < first or last - first >= 32 then return end
    local words
    local original = (alternatives or commaBefore) and {}
    if lang == "en" and ns.UDPipeTagWeights then
        words = tagEnglish(document, first, last, marker, markerEnd, ns.UDPipeTagWeights, hints, markerTags)
        if original then
            for offset = 1, #words do original[offset] = offset end
        end
    else
        local previous
        local index = first
        words = {}
        while index <= last do
            local token = document.tokens[index]
            local raw = document.text:sub(token.first,token.last)
            local pos = fixedTag(token, index, marker, markerEnd, markerTags)
            local lemma, feats
            if token.protected then raw = lang == "en" and "item" or "предмет" end
            if not pos then
                local hint = hints and hints[index]
                if type(hint) == "table" then
                    pos, lemma, feats = hint.pos, hint.lemma, hint.feats
                else
                    local candidate = (not hint or hint == "PRON") and pronounCandidate(document, index, lang)
                        or choose(document, index, lang, previous, document.tokens[index + 1] and document.tokens[index + 1].key or "", hint)
                    if candidate then
                        pos, lemma, feats = candidate.pos, candidate.lemma, udFeatures(candidate,lang)
                    else pos = hint or (raw ~= token.key and "PROPN" or "X") end
                end
            end
            words[#words+1] = {form=raw,lemma=lemma or token.key,upos=pos,feats=feats}
            if original then original[#words] = index - first + 1 end
            previous = pos
            index = (alternatives and alternatives[index] or index) + 1
        end
    end
    if commaBefore then
        local separator = commaBefore - first + 1
        for compact, offset in ipairs(original) do
            if offset >= separator then
                table.insert(words, compact, {form=",", lemma=",", upos="PUNCT"})
                table.insert(original, compact, false)
                break
            end
        end
    end
    local arcs = U.parse(model, words, 1)
    if not arcs or not original then return arcs, words end
    -- Keep source token positions when the model sees an inserted comma or one of two verb forms.
    local expanded, previousOffset = {}, 0
    for compact, arc in ipairs(arcs) do
        local offset = original[compact]
        if offset then
            local head = arc.head
            if original[head] == false then head = arcs[head].head end
            expanded[offset] = {head=original[head] or 0, relation=arc.relation}
            for alternative = previousOffset + 1, offset - 1 do
                expanded[alternative] = {head=previousOffset, relation="dep"}
            end
            previousOffset = offset
        end
    end
    for alternative = previousOffset + 1, last - first + 1 do
        expanded[alternative] = {head=previousOffset, relation="dep"}
    end
    return expanded
end

function U.analyzeDocument(...)
    local arcs = analyzeDocument(...)
    return arcs
end

function U.analyzeDocumentWithTags(document, first, last)
    return analyzeDocument(document, first, last)
end
