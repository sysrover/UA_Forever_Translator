local _, ns = ...
local G = {}
ns.Engine.ClauseGeneration = G
local L, P = ns.Engine.Lexicon, ns.Engine.Phrases

local function append(parts, value)
    if value and value ~= "" then parts[#parts + 1] = value end
end

local function countedCase(amount, case, animate)
    local number = tonumber((amount:gsub(",", ".")))
    if not number or number % 1 ~= 0 then return "genitive", "singular" end
    local last, pair = number % 10, number % 100
    if last == 1 and pair ~= 11 then return case, "singular" end
    if case == "nominative" or case == "accusative" then
        if last >= 2 and last <= 4 and (pair < 12 or pair > 14) and not (case == "accusative" and animate) then
            return "nominative", "plural"
        end
        return "genitive", "plural"
    end
    return case, "plural"
end

local function englishForm(lemma, form, pos)
    local irregular = ns.Linguistics.englishIrregular or {}
    local special = irregular[lemma]
    if special and special[form] then return special[form] end
    if lemma:find(" ", 1, true) then
        local head, tail = lemma:match("^(%S+) (.+)$")
        if pos == "verb" then return englishForm(head, form, pos) .. " " .. tail end
        local prefix, last = lemma:match("^(.*) (%S+)$")
        return prefix .. " " .. englishForm(last, form, pos)
    end
    if form == "past" then
        if lemma:match("e$") then return lemma .. "d" end
        if lemma:match("[^aeiou]y$") then return lemma:sub(1, -2) .. "ied" end
        return lemma .. "ed"
    end
    if form == "third" or form == "plural" then
        if lemma:match("[^aeiou]y$") then return lemma:sub(1, -2) .. "ies" end
        if lemma:match("[sxz]$") or lemma:match("[cs]h$") or (form == "third" and lemma:match("o$")) then
            return lemma .. "es"
        end
        return lemma .. "s"
    end
    return lemma
end

local function adjective(modifier, english, case, number, gender, animacy)
    local entry, intensity = modifier.entry, modifier.intensity
    local degree = entry.form.degree
    if english then
        local base = entry.lexeme.en
        if degree == "comparative" then base = "more " .. base
        elseif degree == "superlative" then base = "most " .. base end
        local prefix = intensity == "more" and "more " or intensity == "very" and "very " or ""
        return prefix .. base
    end
    if not gender and number ~= "plural" then return nil end
    local requestedCase = case
    if case == "accusative" and number == "plural" then
        requestedCase = animacy == "animate" and "genitive" or "nominative"
    elseif case == "accusative" and gender == "masculine" then
        requestedCase = animacy == "animate" and "genitive" or "nominative"
    end
    local value = L.inflect(entry, {case=requestedCase, number=number,
        gender=number ~= "plural" and gender or nil, degree=degree})
    if not value then return nil end
    return (intensity == "more" and "більш " or intensity == "very" and "дуже " or "") .. value
end

local demonstratives = {
    near={masculine="цей", feminine="ця", neuter="це", plural="ці", genitive="цього",
        genitivePlural="цих", feminineAccusative="цю", feminineGenitive="цієї"},
    far={masculine="той", feminine="та", neuter="те", plural="ті", genitive="того",
        genitivePlural="тих", feminineAccusative="ту", feminineGenitive="тієї"},
}

local function demonstrative(node, english, case, number)
    if english then
        if node.demonstrative == "near" then return number == "plural" and "these" or "this" end
        return number == "plural" and "those" or "that"
    end
    local forms = demonstratives[node.demonstrative]
    if case == "genitive" or (case == "accusative" and node.animacy == "animate" and node.gender ~= "feminine") then
        return number == "plural" and forms.genitivePlural or (node.gender == "feminine" and forms.feminineGenitive or forms.genitive)
    end
    if case == "accusative" and node.gender == "feminine" and number ~= "plural" then return forms.feminineAccusative end
    if case == "accusative" or case == "nominative" then return forms[number == "plural" and "plural" or node.gender] end
end

function G.noun(node, english, case, article)
    if node.members then
        local values = {}
        for index, member in ipairs(node.members) do
            local join = node.joins[index - 1]
            if join then append(values, (english and join.en or join.uk)[1]) end
            local value = G.noun(member, english, case, article)
            if not value then return nil end
            append(values, value)
        end
        return table.concat(values, " ")
    end
    if node.raw then return node.raw end
    if node.pronoun then
        local forms = english and node.pronoun.en or node.pronoun.uk
        return forms[case] or (english and forms.accusative)
    end
    local number, requested = node.number, case
    if node.quantity then
        if english then
            number = tonumber(node.quantity) == 1 and "singular" or "plural"
        else
            requested, number = countedCase(node.quantity, case, node.animacy == "animate")
        end
    end
    local value
    if node.term then
        if english then
            value = node.term.en
            if number == "plural" and not (node.term.morphology and node.term.morphology.number == "plural")
                and not (node.term.features and node.term.features.number == "plural") then
                value = node.term.englishPlural or englishForm(value, "plural", "noun")
            end
        else
            value = L.curatedForm(node.term, requested, number)
        end
    elseif node.entry then
        if english then
            value = node.entry.lexeme.en
            if number == "plural" then value = englishForm(value, "plural", "noun") end
        else
            value = L.inflect(node.entry, {case=requested, number=number})
        end
    end
    if not value then return nil end
    local parts = {}
    for _, modifier in ipairs(node.adjectives or {}) do
        local word = adjective(modifier, english, requested, number, node.gender, node.animacy)
        if not word then return nil end
        append(parts, word)
    end
    append(parts, value)
    value = table.concat(parts, " ")
    if node.class then
        if english then
            value = ns.Engine.Normalize.word(node.class.term.en) .. " " .. value
        else
            local class = L.curatedForm(node.class.term, "genitive", "plural")
            if not class then return nil end
            value = value .. " " .. ns.Engine.Normalize.word(class)
        end
    end
    if node.quantity then return node.quantity .. " " .. value end
    if node.demonstrative then
        local determiner = demonstrative(node, english, requested, number)
        return determiner and determiner .. " " .. value
    end
    if node.emphatic then
        if english then value = "such " .. (number == "plural" and "" or "a ") .. value
        else
            local agreement = {masculine="такий", feminine="така", neuter="таке", plural="такі"}
            local emphatic = agreement[number == "plural" and "plural" or node.gender]
            if not emphatic or case ~= "nominative" then return nil end
            value = emphatic .. " " .. value
        end
        return value
    end
    if node.quoted then return "\"" .. value .. "\"" end
    if english then
        if node.article == "definite" then return "the " .. value end
        local proper = node.term and node.term.category == "places"
        local mass = node.entry and node.entry.head.mass
        if (article or node.article == "indefinite") and not proper and not mass and number == "singular" then
            local indefinite = value:match("^[AEIOUaeiou]") and "an" or "a"
            return indefinite .. " " .. value
        end
    end
    return value
end

local ukrainianModals = {
    can={["1singular"]="можу", ["2singular"]="можеш", ["3singular"]="може",
        ["1plural"]="можемо", ["2plural"]="можете", ["3plural"]="можуть"},
    could={masculine="міг", feminine="могла", neuter="могло", plural="могли"},
    must="мусити", should="слід",
}
local future = {["1singular"]="буду", ["2singular"]="будеш", ["3singular"]="буде",
    ["1plural"]="будемо", ["2plural"]="будете", ["3plural"]="будуть"}
local pastCopula = {masculine="був", feminine="була", neuter="було", plural="були"}
local inferredPronouns = {["1singular"]="I", ["2singular"]="you", ["1plural"]="we",
    ["2plural"]="you", ["3plural"]="they", masculine="he", feminine="she", neuter="it"}

local function agreement(tree)
    local subject = tree.subject or tree.inferred or (tree.verb and tree.verb.form) or {}
    local person = subject.person or 3
    local number = subject.number or "singular"
    return person, number, subject.gender, tostring(person) .. number
end

local function ukrainianVerb(tree)
    local entry = tree.verb
    local person, number, gender, key = agreement(tree)
    local frame = entry.lexeme.frame or {}
    local lemma = entry.lexeme.uk
    local form
    if tree.imperative then
        form = L.inflect(entry, {mood="imperative", person=2, number="singular"})
    elseif tree.modal or tree.tense == "infinitive" then
        form = (tree.modal == "can" or tree.modalSense == "possibility") and frame.possibleOutcome or lemma
    elseif tree.tense == "past" then
        if number == "singular" and not gender then return nil end
        local features = {tense="past", mood="indicative", number=number, gender=number == "singular" and gender or nil}
        local completed = tree.aspect == "perfect" and frame.completed
        if completed then form = L.inflectLemma(completed, "verb", features)
        else form = L.inflect(entry, features) end
    elseif tree.tense == "future" and entry.head.aspect ~= "perfective" then
        form = future[key] .. " " .. lemma
    else
        form = L.inflect(entry, {tense=tree.tense or "present", mood="indicative", number=number, person=person})
    end
    if not form then return nil end
    if tree.modal then
        local modal = ukrainianModals[tree.modal]
        if tree.modal == "can" or tree.modalSense == "possibility" then modal = ukrainianModals.can[key]
        elseif tree.modal == "could" then modal = modal[number == "plural" and "plural" or gender]
        elseif tree.modal == "must" then
            modal = L.inflectLemma(modal, "verb", {tense="present", number=number, person=person, mood="indicative"})
        end
        if not modal then return nil end
        form = modal .. " " .. form
    end
    return (tree.negative and "не " or "") .. form
end

local function englishVerb(tree, subject)
    local lemma = tree.verb.lexeme.en
    local person, number = agreement(tree)
    local third = person == 3 and number == "singular"
    local prefix
    if tree.modal then prefix = tree.modal
    elseif tree.tense == "future" then prefix = "will"
    elseif tree.negative or tree.question then
        prefix = tree.tense == "past" and "did" or (third and not tree.imperative and "does" or "do")
    end
    if prefix then
        local negative = tree.negative and " not" or ""
        if tree.question then
            if not subject then return nil end
            return prefix .. " " .. subject .. negative .. " " .. lemma
        end
        return (subject and subject .. " " or "") .. prefix .. negative .. " " .. lemma
    end
    local form = not tree.imperative and tree.tense == "past" and "past"
        or not tree.imperative and tree.tense ~= "infinitive" and third and "third" or "base"
    return (subject and subject .. " " or "") .. englishForm(lemma, form, "verb")
end

local function addPrepositions(parts, tree, english)
    for _, complement in ipairs(tree.prepositions or {}) do
        local value = G.noun(complement.object, english, complement.case, true)
        if not value then return false end
        append(parts, english and complement.rule.en[1] or complement.rule.targetUk)
        append(parts, value)
    end
    return true
end

local function subjectText(tree, english)
    if tree.inherited then return "" end
    if tree.subject then return G.noun(tree.subject, english, "nominative", false) end
    if tree.imperative or tree.tense == "infinitive" or not english then return "" end
    local _, number, gender, key = agreement(tree)
    return inferredPronouns[key] or (number == "singular" and inferredPronouns[gender])
end

local function questionWord(tree, english)
    if tree.where then return english and "where" or "де" end
    if tree.why then return english and "why" or "чому" end
    if tree.question and not english then return "чи" end
end

local render
local function duration(tree, english)
    local rendered
    if english then
        if not tree.action.noun then return nil end
        rendered = G.noun(tree.action.noun, true, "nominative")
        if not rendered then return nil end
    else
        local noun = L.nominalize(tree.action.verb)
        if not noun then
            local action = render(tree.action, false)
            if not action then return nil end
            rendered = "Щоб " .. action .. ", потрібно"
        else
            rendered = noun
            if tree.action.object then
                local object = G.noun(tree.action.object, false, "genitive")
                if not object then return nil end
                rendered = rendered .. " " .. object
            end
        end
        if tree.action.recipient or tree.action.infinitive or tree.action.adverbs or tree.action.prepositions then
            local action = render(tree.action, false)
            if not action then return nil end
            rendered = "Щоб " .. action .. ", потрібно"
        end
    end
    local quantity = tree.quantity
    local word
    if english then
        local unit = P.englishUnits[quantity.unit]
        word = tonumber((quantity.amount:gsub(",", "."))) == 1 and unit or englishForm(unit, "plural", "noun")
    else
        local case, number = countedCase(quantity.amount, "accusative", false)
        word = L.inflectLemma(quantity.unit, "noun", {case=case, number=number})
    end
    if not word then return nil end
    local take = english and (tree.tense == "past" and " took" or " takes")
        or (tree.tense == "past" and " займало" or " займає")
    if rendered:match("^Щоб ") then take = "" end
    return rendered .. take .. (quantity.approximate and (english and " about" or " приблизно") or "")
        .. " " .. quantity.amount .. " " .. word
end

render = function(tree, english)
    if tree.kind == "duration" then return duration(tree, english) end
    local parts = {}
    local subject = subjectText(tree, english)
    if subject == nil then return nil end
    if tree.kind == "nounPhrase" then append(parts, subject)
    elseif tree.elliptic then
        append(parts, questionWord(tree, english))
        if english then
            if tree.question then append(parts, "will"); append(parts, subject)
            else append(parts, subject); append(parts, "will") end
            if tree.negative then append(parts, "not") end
        else
            local _, _, _, key = agreement(tree)
            append(parts, subject)
            if tree.negative then append(parts, "не") end
            append(parts, future[key])
        end
    elseif tree.copula then
        local person, number, gender = agreement(tree)
        if english then
            local be
            if tree.tense == "past" then be = (number == "plural" or person == 2) and "were" or "was"
            else be = (number == "plural" or person == 2) and "are" or (person == 1 and "am" or "is") end
            append(parts, questionWord(tree, english))
            if tree.question then append(parts, be); append(parts, subject)
            else append(parts, subject); append(parts, be) end
            if tree.negative then append(parts, "not") end
        else
            append(parts, questionWord(tree, english))
            append(parts, subject)
            if tree.negative then append(parts, "не") end
            if tree.tense == "past" then
                local be = pastCopula[number == "plural" and "plural" or gender]
                if not be then return nil end
                append(parts, be)
            elseif tree.negative and tree.prepositions then append(parts, "перебуває") end
        end
        if tree.predicate then
            local value = G.noun(tree.predicate, english, "nominative", true)
            if not value then return nil end
            append(parts, value)
        elseif tree.adjective then
            local value = adjective(tree.adjective, english, "nominative", number, gender, tree.subject.animacy)
            if not value then return nil end
            append(parts, value)
        end
    else
        local frame = tree.verb.lexeme.frame or {}
        if english then
            append(parts, questionWord(tree, english))
            local value = englishVerb(tree, subject ~= "" and subject or nil)
            if not value then return nil end
            append(parts, value)
        else
            append(parts, questionWord(tree, english))
            append(parts, subject)
            if tree.leadingAdverb then append(parts, tree.leadingAdverb.uk[1]) end
            local value = ukrainianVerb(tree)
            if not value then return nil end
            append(parts, value)
        end
        if tree.recipient then
            local value = G.noun(tree.recipient, english, "dative", true)
            if not value then return nil end
            append(parts, value)
        end
        if tree.object then
            local requested = english and "accusative" or frame.objectCase or "accusative"
            local value = G.noun(tree.object, english, requested, true)
            if not value then return nil end
            if not english then append(parts, frame.objectPreposition) end
            append(parts, value)
        end
        if tree.infinitive then
            local value = render(tree.infinitive, english)
            if not value then return nil end
            if english then append(parts, "to") end
            append(parts, value)
        end
        if tree.content then
            for index, embedded in ipairs(tree.content) do
                local value = render(embedded, english)
                if not value then return nil end
                if index > 1 then append(parts, english and "and" or "і")
                elseif not english then parts[#parts] = parts[#parts] .. "," end
                append(parts, english and "that" or "що")
                append(parts, value)
            end
        end
    end
    if not addPrepositions(parts, tree, english) then return nil end
    for _, adverb in ipairs(tree.adverbs or {}) do append(parts, (english and adverb.en or adverb.uk)[1]) end
    return table.concat(parts, " ")
end

local function upperStart(value)
    local word = value:match("^[a-z]") or value:match("^[\208\209\210][\128-\191]")
    if not word then return value end
    local lower = "абвгґдеєжзиіїйклмнопрстуфхцчшщьюя"
    local upper = "АБВГҐДЕЄЖЗИІЇЙКЛМНОПРСТУФХЦЧШЩЬЮЯ"
    local index = lower:find(word, 1, true)
    return (index and upper:sub(index, index + 1) or word:upper()) .. value:sub(#word + 1)
end

function G.render(parse, direction, punctuation)
    local english = direction == "uk-en"
    local parts, last = {}, nil
    local final = parse.trees[#parse.trees]
    if english and punctuation == "?" and final.kind == "clause" and not final.imperative then
        final.question = true
    end
    if parse.prefix then append(parts, (english and parse.prefix.en or parse.prefix.uk)[1]) end
    for i, tree in ipairs(parse.trees) do
        local value = render(tree, english)
        if not value or value == "" then return nil end
        local join = parse.joins[i - 1]
        if join then
            local id = join.rule and join.rule.id
            local comma = join.comma or id == "but" or id == "because" or id == "if" or id == "when" or id == "unless"
            if comma then parts[#parts] = parts[#parts] .. "," end
            if join.rule then append(parts, (english and join.rule.en or join.rule.uk)[1]) end
        end
        append(parts, value)
        last = tree
    end
    return upperStart(table.concat(parts, " ")) .. (last.question and "?" or punctuation or ".")
end
