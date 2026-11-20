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
        elseif form.mood == "impersonal" then put("VerbForm", "Imps")
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
        if pos == "ADJ" and form.voice then
            put("Aspect", dimensions.aspect[form.aspect])
            put("VerbForm", "Part")
            put("Voice", form.voice == "passive" and "Pass" or "Act")
        end
    end
    table.sort(values)
    return table.concat(values, "|")
end

function U.ukNominalHint(node, case)
    local pronoun = node.pronoun
    local entry = node.entry
    if not pronoun and not (entry and entry.lexeme.pos == "noun" and node.sourceCase == case) then return nil end
    local pos = pronoun and "PRON" or "NOUN"
    local form = {case=case, number=node.number, gender=node.gender, animacy=node.animacy,
        person=pronoun and node.person or nil}
    local lemma = pronoun and pronoun.uk.nominative or entry.lexeme.uk
    return {pos=pos, lemma=lemma, feats=udFeatures({pos=pos, form=form, tags={}}, "uk")}
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
    local readings = A.analyze(token.key, lang, document) or {}
    local found
    for raw, weight in pairs(readings) do
        local lemma, kind, suffix = raw:match("^([^<+/#]+)<(%w+)>(.*)$")
        if kind and parts[kind] and not suffix:find("[+/#]") then
            local tags = {}
            for tag in suffix:gmatch("<(%w+)>") do tags[tag] = true end
            local pos = parts[kind]
            local _, _, form = A.read(raw, lang)
            -- Ukrainian UD uses ADJ for declined participles, including predicative ones.
            if lang == "uk" and kind == "vblex" and (tags.pasv or tags.actv) then
                local _, _, participle = A.readParticiple(raw)
                if participle then
                    pos, form = "ADJ", participle
                end
            end
            form = form or {}
            if not form.person then form.person = tags.p1 and 1 or tags.p2 and 2 or tags.p3 and 3 or nil end
            if not form.number then form.number = tags.sg and "singular" or tags.pl and "plural" or nil end
            if not form.case and lang == "en" and kind == "prn" then
                form.case = tags.subj and "nominative" or tags.obj and "accusative" or nil
            end
            offer(lemma, pos, form, tags, weight, raw)
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

local function agrees(form, nominal)
    return form.case == nominal.case and form.number == nominal.number
        and (form.number == "plural" or form.gender == nominal.gender)
        and (not form.animacy or not nominal.animacy or form.animacy == nominal.animacy)
end

local function followingNominals(document, index, lang)
    local forms = {}
    lexicalCandidates(document, index, lang, function(_, pos, candidate)
        if pos == "NOUN" or pos == "PROPN" then forms[#forms + 1] = candidate end
    end)
    return forms
end

local function choose(document, index, lang, previous, following, hint, previousParticiple)
    local best, priority, order, nominalForms
    local nextKey = following and following.key or ""
    lexicalCandidates(document, index, lang, function(lemma, pos, form, tags, weight, key)
        if hint and pos ~= hint then return end
        local score = rank(pos, previous, nextKey, tags) - weight
        if previousParticiple and (pos == "NOUN" or pos == "PROPN") and agrees(previousParticiple, form) then
            score = score + 2
        elseif pos == "ADJ" and form.voice and following and not following.protected then
            nominalForms = nominalForms or followingNominals(document, index + 1, lang)
            for _, nominal in ipairs(nominalForms) do
                if agrees(form, nominal) then
                    score = score + 2
                    break
                end
            end
        end
        if not best or score > priority or (score == priority and key < order) then
            best, priority, order = {lemma=lemma, pos=pos, form=form, tags=tags}, score, key
        end
    end)
    if best and best.pos == "ADJ" and best.form.voice then
        local form = best.form
        best.lemma = A.generate(best.lemma, "uk", "participle", {
            case="nominative", number="singular", gender="masculine", aspect=form.aspect, voice=form.voice,
        }) or document.tokens[index].key
    end
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

local function tagEnglish(document, first, last, marker, markerEnd, weights, hints, markerTags, readings)
    local tagIds = weights.ids
    local boundary = tagIds[""]
    local previous = {[boundary]={score=0}}
    local words = {}
    local quantifiedHeads, hasAuxiliary
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
        local resolved = not pos and not hintedId and readings and readings[index]
        if resolved then
            local id = tagIds[resolved.pos]
            local candidate = candidates[id] or {pos=resolved.pos, lemma=token.key}
            candidate.lemma = resolved.lemma or candidate.lemma
            candidate.feats = resolved.feats or candidate.feats
            candidate.modelForm = resolved.modelForm or candidate.modelForm
            candidate.auxiliary = resolved.auxiliary
            hasAuxiliary = hasAuxiliary or resolved.auxiliary ~= nil
            candidates = {[id]=candidate}
        elseif hintedId then
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
        words[index] = {form=candidate.raw, lemma=candidate.lemma, upos=candidate.pos,
            feats=feats, auxiliary=candidate.auxiliary}
        candidate = candidate.previous
    end
    return words, hasAuxiliary
end

local modelFields = {"form", "lemma", "upos", "xpos", "feats", "misc"}
local function parseModelInput(document, model, words)
    local parts = {}
    for _, word in ipairs(words) do
        for _, field in ipairs(modelFields) do
            local value = word[field] or ""
            parts[#parts + 1] = #value .. ":" .. value
        end
    end
    local key = table.concat(parts)
    local models = document.udpipeInferences
    if not models then models = {}; document.udpipeInferences = models end
    local memo = models[model]
    if not memo then memo = {count=0}; models[model] = memo end
    local cached = memo[key]
    if cached ~= nil then return cached or nil end

    local projections = document.udpipeProjections
    if not projections then projections = {}; document.udpipeProjections = projections end
    local arcs = U.parse(model, words, 1, projections, document.checkpoint)
    if memo.count < 8 then
        memo[key] = arcs or false
        memo.count = memo.count + 1
    end
    return arcs
end

local function analyzeDocument(document, first, last, marker, markerEnd, hints, markerTags, alternatives, commaBefore, readings)
    local lang = document.direction == "en-uk" and "en" or "uk"
    local model = ns.UDPipeModels and ns.UDPipeModels[lang]
    if not model or last < first or last - first >= 32 then return end
    local words
    local original = (alternatives or commaBefore) and {}
    if lang == "en" and ns.UDPipeTagWeights then
        local hasAuxiliary
        words, hasAuxiliary = tagEnglish(document, first, last, marker, markerEnd, ns.UDPipeTagWeights, hints, markerTags, readings)
        if hasAuxiliary then original = original or {} end
        if original then
            for offset = 1, #words do original[offset] = offset end
        end
        if hasAuxiliary then
            for offset = #words, 1, -1 do
                local auxiliary = words[offset].auxiliary
                if auxiliary then
                    table.insert(words, offset + 1, auxiliary)
                    table.insert(original, offset + 1, false)
                end
            end
        end
    else
        local previous, previousParticiple
        local index = first
        words = {}
        while index <= last do
            local token = document.tokens[index]
            local nextIndex = (alternatives and alternatives[index] or index) + 1
            local following = nextIndex == index + 1 and nextIndex <= last and document.tokens[nextIndex]
            local raw = document.text:sub(token.first,token.last)
            local pos = fixedTag(token, index, marker, markerEnd, markerTags)
            local lemma, feats, participle
            if token.protected then raw = lang == "en" and "item" or "предмет" end
            if not pos then
                local hint = hints and hints[index]
                if type(hint) == "table" then
                    pos, lemma, feats = hint.pos, hint.lemma, hint.feats
                else
                    local candidate = (not hint or hint == "PRON") and pronounCandidate(document, index, lang)
                        or choose(document, index, lang, previous, following, hint, previousParticiple)
                    if candidate then
                        pos, lemma, feats = candidate.pos, candidate.lemma, udFeatures(candidate,lang)
                        if pos == "ADJ" and candidate.form.voice then participle = candidate.form end
                    else pos = hint or (raw ~= token.key and "PROPN" or "X") end
                end
            end
            words[#words+1] = {form=raw,lemma=lemma or token.key,upos=pos,feats=feats}
            if original then original[#words] = index - first + 1 end
            previous, previousParticiple = pos, following and participle
            index = nextIndex
        end
    end
    if commaBefore then
        local separator = commaBefore - first + 1
        for compact, offset in ipairs(original) do
            if offset and offset >= separator then
                table.insert(words, compact, {form=",", lemma=",", upos="PUNCT"})
                table.insert(original, compact, false)
                break
            end
        end
    end
    -- The same annotated words can be produced by the plain and guided attempts.
    -- Cache compact arcs; each caller maps them back to its own source positions.
    local arcs = parseModelInput(document, model, words)
    if not arcs or not original then return arcs, words end
    -- Keep source positions after adding a contraction's auxiliary, adding a comma, or compacting verb alternatives.
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

local function attachedModifier(arcs, position, head)
    for _ = 1, #arcs do
        local arc = arcs[position]
        if not arc then return false end
        if arc.relation ~= "conj" then return arc.relation == "amod" and arc.head == head end
        position = arc.head
    end
    return false
end

local function supportedAttachment(first, arcs, index, reading)
    local position = index - first + 1
    if reading.nominalHead then return attachedModifier(arcs, position, reading.nominalHead - first + 1) end
    if not reading.governor then return true end
    local arc = arcs[position]
    return arc and arc.relation == reading.relation and arc.head == reading.governor - first + 1
end

local function missingReadings(document, first, arcs, words, readings)
    local missing = {}
    for index, reading in pairs(readings) do
        local head = reading.nominalHead
        local position = index - first + 1
        local word = words[position]
        local needsReading = not head and (word.upos ~= reading.pos or word.feats ~= reading.feats)
        local needsAttachment = not supportedAttachment(first, arcs, index, reading)
        if needsReading or needsAttachment then
            missing[index] = reading
            if head and not document.tokens[head].protected and not readings[head] then
                missing[head] = {pos="NOUN"}
            end
        end
    end
    return next(missing) and missing or nil
end

local function normalizeAttachedModifiers(first, arcs, words, readings)
    for index, reading in pairs(readings) do
        if reading.nominalHead and supportedAttachment(first, arcs, index, reading) then
            local word = words[index - first + 1]
            word.upos, word.lemma, word.feats = reading.pos, reading.lemma, reading.feats
        end
    end
end

function U.analyzeDocumentWithTags(document, first, last)
    local grammar = ns.Engine.ClauseAnalysis
    if not grammar or not grammar.dependencyInputReadings or document.direction ~= "en-uk"
        or last < first or last - first >= 32 then return analyzeDocument(document, first, last) end
    local token = document.tokens[last]
    local limit = token.key:match("^[.!?]$") and last - 1 or last
    local readings = limit >= first and grammar.dependencyInputReadings(document, first, limit)
    if not readings then return analyzeDocument(document, first, last) end
    local arcs, words = analyzeDocument(document, first, last)
    if not arcs or not words then return arcs, words end
    local missing = missingReadings(document, first, arcs, words, readings)
    if missing then
        local guided, tagged = analyzeDocument(document, first, last, nil, nil, nil, nil, nil, nil, missing)
        if guided and tagged then
            local supported = true
            for index, reading in pairs(readings) do
                if not supportedAttachment(first, guided, index, reading) then
                    supported = false
                    break
                end
            end
            if supported then arcs, words = guided, tagged end
        end
    end
    normalizeAttachedModifiers(first, arcs, words, readings)
    return arcs, words
end
