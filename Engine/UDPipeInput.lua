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

local function choose(document, index, lang, previous, following)
    local token = document.tokens[index]
    local readings = A.analyze(token.key, lang) or {}
    local best, priority, order
    local function offer(lemma, pos, form, tags, weight, key)
        local score = rank(pos, previous, following, tags) - weight
        if not best or score > priority or (score == priority and key < order) then
            best, priority, order = {lemma=lemma, pos=pos, form=form, tags=tags}, score, key
        end
    end
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
        end
    end
    if not best then
        for _, entry in ipairs(L.at(document, index)) do
            local pos = lexicalParts[entry.lexeme.pos]
            if pos then
                local lemma = entry.lexeme[lang]
                offer(lemma,pos,entry.form,{},0,pos .. ":" .. lemma)
            end
        end
    end
    return best
end

function U.analyzeDocument(document, first, last, marker, markerEnd)
    local lang = document.direction == "en-uk" and "en" or "uk"
    local model = ns.UDPipeModels and ns.UDPipeModels[lang]
    if not model or last - first >= 32 then return end
    local words, previous = {}
    for index = first, last do
        local token = document.tokens[index]
        local raw = document.text:sub(token.first,token.last)
        local candidate, pos, lemma, feats
        if token.protected then raw = lang == "en" and "item" or "предмет"; pos = "NOUN"
        elseif index >= marker and index <= markerEnd then pos = "SCONJ"
        elseif token.key:match("^%d+$") then pos = "NUM"
        elseif token.key:match("^%p$") or token.key == "…" or token.key == "—" then pos = "PUNCT"
        else
            local pronouns, finish = L.functional(document,"pronouns",index,index)
            if pronouns and finish == index then
                local reading = pronouns[1]
                local pronoun = ns.Linguistics.grammar.pronouns[reading.id]
                candidate = {lemma=pronoun[lang].nominative,pos="PRON",
                    form={person=pronoun.person,number=pronoun.number,gender=pronoun.gender,case=reading.case},tags={}}
            else
                candidate = choose(document,index,lang,previous,document.tokens[index+1] and document.tokens[index+1].key or "")
            end
            if candidate then
                pos, lemma, feats = candidate.pos, candidate.lemma, udFeatures(candidate,lang)
            else pos = raw ~= token.key and "PROPN" or "X" end
        end
        words[#words+1] = {form=raw,lemma=lemma or token.key,upos=pos,feats=feats}
        previous = pos
    end
    return U.parse(model, words, 1)
end
