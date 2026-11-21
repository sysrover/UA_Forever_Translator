local _, ns = ...
local L = {}; ns.Engine.Lexicon = L
local N, A = ns.Engine.Normalize, ns.Engine.Apertium

local function byteLess(a, b)
    for i=1,math.min(#a,#b) do
        local x,y=a:byte(i),b:byte(i)
        if x~=y then return x<y end
    end
    return #a<#b
end
local function find(index, key)
    if not index then return nil end
    local low,high=1,#index.starts
    while low<=high do
        local middle=math.floor((low+high)/2)
        if byteLess(key,index.starts[middle]) then high=middle-1 else low=middle+1 end
    end
    if high==0 then return nil end
    local block=index.blocks[high]
    local _,last=block:find("\n"..key.."\t",1,true)
    if last then return block:sub(last+1,(block:find("\n",last+1,true) or (#block+1))-1) end
end

local function decode(document, data, id)
    local memo = document.lexemeMemo
    if not memo then memo = {}; document.lexemeMemo = memo end
    if memo[id] then return memo[id] end
    local en, uk, pos, family, feature, sense, preference, labels = data.lexemes[id]:match(
        "^([^\t]+)\t([^\t]+)\t([^\t]+)\t(%d+)\t(%d+)\t([^\t]+)\t(-?%d+)\t(.*)$")
    if not en then return nil end
    local lexeme = {en=en, uk=uk, pos=pos, family=tonumber(family), features=tonumber(feature),
        sense=sense, preference=tonumber(preference), labels=labels, frame=data.frames[tostring(id)]}
    memo[id] = lexeme
    return lexeme
end

function L.lookup(document, word)
    local data=ns.Linguistics
    if not data then return {} end
    document.lexicalMemo=document.lexicalMemo or {}
    local cached=document.lexicalMemo[word]
    if cached then return cached end
    local language=document.direction=="en-uk" and "en" or "uk"
    local row=find(data.analysis[language],word)
    local result={}
    document.lexicalMemo[word]=result
    if not row then return result end
    for id,feature in row:gmatch("(%d+):(%d+)") do
        id = tonumber(id)
        if #result == 64 then
            result.truncated = true
            if data.rankedAnalysis then
                local omitted = decode(document, data, id)
                result.omittedPreference = omitted and omitted.preference
            end
            break
        end
        local lexeme = decode(document, data, id)
        if lexeme then
            result[#result+1]={id=id,lexeme=lexeme,form=data.features[tonumber(feature)],head=data.features[lexeme.features]}
        end
    end
    return result
end

local function ends(word, suffix)
    return word:sub(-#suffix) == suffix
end

local plural = {number="plural"}
local thirdPerson = {tense="present", person=3, number="singular"}
local past = {tense="past"}
local pastParticiple = {tense="past", verbalForm="participle"}
local presentParticiple = {tense="present", verbalForm="participle"}

local function doublesConsonant(stem)
    -- A single short vowel followed by one consonant takes a doubled ending.
    return stem:gsub("qu", "q"):match("^[^aeiou]+[aeiou][^aeiouwxy]$") ~= nil
end

local function undouble(stem)
    local final = stem:sub(-1)
    local base = stem:sub(1, -2)
    if ends(base, final) and doublesConsonant(base) then return base end
end

local function englishForms(word, add)
    if not word:match("^[a-z]+$") then return end
    if ends(word, "s") then
        local function pluralOrThird(stem, verbOnly)
            if #stem < 2 then return end
            if not verbOnly then add(stem, "noun", plural, "plural") end
            add(stem, "verb", thirdPerson, "third")
        end
        local stem = word:sub(1, -2)
        if not stem:match("[^aeiou]y$") and not stem:match("[sxz]$") and not stem:match("[cs]h$") then
            pluralOrThird(stem, false)
        end
        if ends(word, "es") then
            stem = word:sub(1, -3)
            if stem:match("[sxz]$") or stem:match("[cs]h$") then
                pluralOrThird(stem, false)
            elseif ends(stem, "o") then
                pluralOrThird(stem, true)
            end
        end
        if ends(word, "ies") then
            stem = word:sub(1, -4)
            if stem:match("[^aeiou]$") then pluralOrThird(stem .. "y", false) end
        end
    elseif ends(word, "ed") then
        local stem = word:sub(1, -3)
        local function pastForms(lemma)
            if #lemma < 2 then return end
            add(lemma, "verb", past, "past")
            add(lemma, "verb", pastParticiple, "participle")
        end
        if not ends(stem, "e") and not stem:match("[^aeiou]y$") and not doublesConsonant(stem) then pastForms(stem) end
        local shortened = undouble(stem)
        if shortened then pastForms(shortened) end
        pastForms(stem .. "e")
        if ends(word, "ied") and stem:sub(1, -2):match("[^aeiou]$") then pastForms(stem:sub(1, -2) .. "y") end
    elseif ends(word, "ing") then
        local stem = word:sub(1, -4)
        if #stem < 2 then return end
        if (not ends(stem, "e") or ends(stem, "ee")) and not doublesConsonant(stem) then
            add(stem, "verb", presentParticiple, "ing")
        end
        local shortened = undouble(stem)
        if shortened then add(shortened, "verb", presentParticiple, "ing") end
        if not ends(stem, "e") then add(stem .. "e", "verb", presentParticiple, "ing") end
        if ends(stem, "y") then add(stem:sub(1, -2) .. "ie", "verb", presentParticiple, "ing") end
    end
end

local dativeEndings = {
    {"ові", "у"}, {"еві", "ю"}, {"єві", "ю"}, {"у", "ові"}, {"ю", "еві"}, {"ю", "єві"},
}

local function ukrainianForms(word, add)
    if not word:match("^[\208-\210]") then return end
    for _, endings in ipairs(dativeEndings) do
        local from, to = endings[1], endings[2]
        if #word > #from and ends(word, from) then add(word:sub(1, -#from - 1) .. to, "noun") end
    end
end

-- Reverse only productive endings. Exact analyses and authored exceptions take
-- precedence, and every derived analysis must lead back to an attested entry.
local function derived(document, word)
    local data = ns.Linguistics
    if not data then return {} end
    document.derivedMemo = document.derivedMemo or {}
    local cached = document.derivedMemo[word]
    if cached then return cached end
    local result, seen = {}, {}
    document.derivedMemo[word] = result
    local english = document.direction == "en-uk"
    local language = english and "en" or "uk"
    local function add(base, pos, inferred, slot)
        local attested = not slot and inferred ~= nil
        local special = english and data.englishIrregular[base]
        local exception = special and (special[slot] or slot == "participle" and special.past)
        if exception and word ~= exception then return end
        local entries = L.lookup(document, base)
        if entries.truncated then result.truncated = true; return end
        for _, entry in ipairs(entries) do
            local lexeme, form = entry.lexeme, entry.form
            local matchesLemma = attested and lexeme[language] == base
            local productive = not attested and (english and lexeme.en == base
                and (pos == "verb" and form.mood == "base" or pos == "noun" and form.number == "singular" and not entry.head.mass)
                or not english and form.case == "dative" and form.number == "singular" and form.gender == "masculine")
            if lexeme.pos == pos and (matchesLemma or productive) then
                local analysis = inferred or form
                local readings = seen[entry.id]
                if not readings then readings = {}; seen[entry.id] = readings end
                if not readings[analysis] then
                    if #result == 64 then result.truncated = true; return end
                    readings[analysis] = true
                    result[#result+1] = {id=entry.id, lexeme=lexeme, form=analysis, head=entry.head}
                end
            end
        end
    end
    local analyses = A and A.analyze(word, language, document)
    if analyses then
        local ordered = {}
        for analysis in pairs(analyses) do ordered[#ordered + 1] = analysis end
        table.sort(ordered, function(left, right)
            if analyses[left] == analyses[right] then return byteLess(left, right) end
            return analyses[left] < analyses[right]
        end)
        for _, analysis in ipairs(ordered) do
            local lemma, pos, form = A.read(analysis, language)
            if lemma then add(N.word(lemma), pos, form) end
        end
        if #result > 0 or result.truncated then return result end
    end
    if english then englishForms(word, add)
    else ukrainianForms(word, add) end
    return result
end

function L.at(document, index)
    local token = document.tokens[index]
    if not token or token.protected then return {} end
    if not ns.Linguistics then return L.lookup(document, token.key) end
    local memo = document.tokenReadings
    if not memo then memo = {}; document.tokenReadings = memo end
    local cached = memo[index]
    if cached then return cached end

    local direct = L.lookup(document, token.key)
    local readings = #direct > 0 and direct or derived(document, token.key)
    memo[index] = readings
    return readings
end

local function available(lexeme, document, sense)
    local frame = lexeme.frame
    local domain = frame and frame.contextDomain
    local english = document.direction == "en-uk"
    return not domain or domain == document.transferDomain or sense ~= nil and frame.sense == sense
        or frame.contextRole and (english and frame.requiredAdjunct or not english and frame.reverseAdjunct)
        or document.relativeClass and frame.relativeObjectClasses and frame.relativeObjectClasses[document.relativeClass]
            and (english or document.relativeMarker == frame.relativeMarkerUk)
end

function L.derivedLiteral(document, word)
    if not ns.Linguistics or #L.lookup(document, word) > 0 then return nil end
    local candidates = derived(document, word)
    if candidates.truncated then return nil end
    local target = document.direction == "en-uk" and "uk" or "en"
    local translation
    for _, entry in ipairs(candidates) do
        if available(entry.lexeme, document) then
            local equivalent = entry.lexeme[target]
            if translation and translation ~= equivalent then return nil end
            translation = equivalent
        end
    end
    if translation then return {id="morphology:" .. word, text=translation, sourceRefs=ns.Linguistics.manifest.sourceRefs} end
end

function L.phraseAt(document, first, limit, partOfSpeech)
    local data = ns.Linguistics
    local lengthsByPart = data and (document.direction == "en-uk" and data.phraseLengths or data.ukPhraseLengths)
    local index = lengthsByPart and lengthsByPart[partOfSpeech]
    local head = document.tokens[first]
    if not index or not head or head.protected then return nil end
    local lengths = index[head.key]
    if not lengths then return nil end
    for _, length in ipairs(lengths) do
        local last = first + length - 1
        if last <= limit then
            local words = {}
            local previous, consumed
            for position = first, last do
                local token = document.tokens[position]
                if token.protected then break end
                if previous and previous.last + 1 == token.first
                    and (token.key == "-" or previous.key == "-" or token.key == "." or previous.key == ".") then
                    words[#words] = words[#words] .. token.key
                else
                    words[#words + 1] = token.key
                end
                previous, consumed = token, position
            end
            if consumed == last then
                local phrase = table.concat(words, " ")
                for _, candidate in ipairs(L.lookup(document, phrase)) do
                    local lexeme = candidate.lexeme
                    if lexeme.pos == partOfSpeech and lexeme.frame and lexeme.frame.lexicalPhrase then
                        return phrase, last + 1
                    end
                end
            end
        end
    end
end

local function matches(form, requested)
    for key,value in pairs(requested or {}) do
        if key=="mood" and value=="indicative" then
            if form.mood or form.verbalForm then return false end
        elseif form[key]~=value then return false end
    end
    return true
end

local noReadings = {}
local function byPart(document, candidates, pos)
    local memo = document.lexicalParts
    if not memo then memo = {}; document.lexicalParts = memo end
    local parts = memo[candidates]
    if not parts then
        parts = {}
        for _, candidate in ipairs(candidates) do
            local part = candidate.lexeme.pos
            local list = parts[part]
            if not list then list = {}; parts[part] = list end
            list[#list + 1] = candidate
        end
        memo[candidates] = parts
    end
    return parts[pos] or noReadings
end

-- Choice is a lexical operation, not a spelling-order tie breaker. Project
-- valency/sense entries rank above imported alternatives. Equal target meanings
-- may share source analyses; different equally-ranked meanings remain visible.
function L.choose(document, first, pos, requested, sense, compatible)
    local candidates=type(first) == "string" and L.lookup(document, first) or L.at(document, first)
    local selected,score,ambiguous
    local target = document.direction == "en-uk" and "uk" or "en"
    local matching = #candidates > 8 and byPart(document, candidates, pos) or candidates
    for _,candidate in ipairs(matching) do
        local lexeme,form=candidate.lexeme,candidate.form
        local frame=lexeme.frame
        if lexeme.pos==pos and available(lexeme, document, sense) and (not requested or matches(form,requested))
            and (not frame or frame.sense ~= "duration" or sense == "duration")
            and (not frame or not frame.headClasses or sense == "nounModifier")
            and (not frame or frame.sense ~= "identityDeterminer" or sense == "identityDeterminer")
            and (not frame or sense ~= nil or document.direction == "en-uk" and not frame.contextOnly
                or document.direction == "uk-en" and not frame.contextOnlyReverse)
            and (not sense or frame and frame.sense==sense)
            and (not compatible or compatible(candidate)) then
            local rank=-(lexeme.preference or 0)
            if not score or rank>score then selected,score,ambiguous=candidate,rank,false
            elseif rank==score then
                if selected.lexeme[target]~=lexeme[target] then
                    ambiguous=true
                elseif selected.id==candidate.id and pos=="verb" and candidate.head.aspect and form.aspect==candidate.head.aspect
                    and selected.form.aspect and selected.form.aspect~=form.aspect and selected.form.tense~=form.tense then
                    -- Conflicting analyses of the same surface can model the lemma as both aspects.
                    selected=candidate
                end
            end
        end
    end
    -- An omitted reading can still tie or outrank the visible candidates.
    local omitted = candidates.omittedPreference
    if ambiguous or candidates.truncated and (not score or not omitted or score <= -omitted) then
        return nil, "ambiguous"
    end
    return selected
end

function L.genderPair(document, first, limit, pos, requested, sense, compatible, secondIndex)
    secondIndex = secondIndex or first + 2
    local separator = document.tokens[secondIndex - 1]
    if document.direction ~= "uk-en" or secondIndex > limit or not separator or separator.key ~= "/" then return nil end
    local second = L.at(document, secondIndex)
    return L.choose(document, first, pos, requested, sense, function(candidate)
        local form = candidate.form
        local opposite = form.gender == "masculine" and "feminine" or form.gender == "feminine" and "masculine"
        if not opposite or form.number ~= "singular" or compatible and not compatible(candidate) then return false end
        for _, other in ipairs(second) do
            local nextForm = other.form
            if candidate.id == other.id and nextForm.gender == opposite and nextForm.number == form.number
                and nextForm.case == form.case and nextForm.tense == form.tense and nextForm.mood == form.mood
                and nextForm.degree == form.degree and nextForm.verbalForm == form.verbalForm then
                return true
            end
        end
        return false
    end)
end

local function familyForm(id, requested)
    local data=ns.Linguistics
    local family=data and data.families[id]
    if not family then return nil end
    local best,bestWords
    for feature,word in family:gmatch("(%d+)\t([^\n]+)") do
        local f=data.features[tonumber(feature)]
        if matches(f,requested) then
            local _,spaces=word:gsub(" ","")
            if not best or spaces<bestWords then best,bestWords=word,spaces end
        end
    end
    return best
end

function L.inflect(candidate, requested)
    local lexeme = candidate.lexeme
    return familyForm(lexeme.family, requested)
        or A and A.generate(lexeme.uk, "uk", lexeme.pos, requested, candidate.head)
end
function L.inflectLemma(lemma,pos,requested)
    local data=ns.Linguistics
    local id=data and data.generation[lemma..":"..pos]
    return (id and familyForm(id, requested))
        or A and A.generate(lemma, "uk", pos, requested, id and L.head(lemma, pos))
end

function L.head(lemma,pos)
    local data=ns.Linguistics
    local id=data and data.generation[lemma..":"..pos]
    local family=id and data.families[id]
    if not family then return {} end
    local first=family:match("(%d+)\t")
    return first and data.features[tonumber(first)] or {}
end

function L.nominalize(candidate)
    local lexeme=candidate.lexeme
    local words=ns.Linguistics.nominalizations[lexeme.uk]
    if words and #words==1 then return words[1] end
    return lexeme.frame and lexeme.frame.nominalization
end

local formNames={nominative="nominativePlural",genitive="genitivePlural",accusative="accusativePlural"}
function L.curatedForm(term,case,number)
    local forms=term.forms or {}
    if number=="plural" then
        local key=formNames[case] or case.."Plural"
        if forms[key] then return forms[key] end
        local fixedNumber = term.morphology and term.morphology.number or term.features and term.features.number
        if fixedNumber == "plural" and forms[case] then return forms[case] end
    else
        if forms[case.."Singular"] then return forms[case.."Singular"] end
        if forms[case] then return forms[case] end
    end
    local lemma=N.word(term.uk)
    local requested={case=case,number=number or "singular"}
    local head=L.head(lemma,"noun")
    if case=="accusative" and term.features and term.features.animacy=="animate" and head.animacy=="inanimate" then
        requested.case="genitive"
    end
    local result=L.inflectLemma(lemma,"noun",requested)
    if result then return result end
    if case=="nominative" and (number~="plural" or term.features and term.features.number=="plural"
        or term.morphology and term.morphology.number=="plural") then return term.uk end
end

function L.functional(document, group, first, limit)
    local data = ns.Linguistics
    if not data then return nil end
    local tokens = document.tokens
    limit = limit or #tokens
    if first > limit or not tokens[first] or tokens[first].protected then return nil end
    local memo = document.functionalMemo
    if not memo then memo = {}; document.functionalMemo = memo end
    local groups = memo[first]
    if not groups then groups = {}; memo[first] = groups end
    local hits = groups[group]
    if hits == nil then
        local lang = document.direction == "en-uk" and "en" or "uk"
        local index = data.grammar.index[lang][group]
        hits = false
        if index then
            -- Keep all matching endings so a shorter parse can still use its own limit.
            local key = ""
            local widths = data.grammar.indexWidths
            local width = widths and widths[lang][group] or 3
            for last = first, math.min(#tokens, first + width - 1) do
                local token = tokens[last]
                if token.protected then break end
                key = key == "" and token.key or key .. " " .. token.key
                local readings = index[key]
                if readings then
                    if not hits then hits = {} end
                    hits[#hits + 1] = {readings=readings, last=last}
                end
            end
        end
        groups[group] = hits
    end
    if hits then
        for i = #hits, 1, -1 do
            local hit = hits[i]
            if hit.last <= limit then return hit.readings, hit.last end
        end
    end
end

L.matches=matches
