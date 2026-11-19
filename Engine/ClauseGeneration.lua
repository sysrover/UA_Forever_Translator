local _, ns = ...
local G = {}
ns.Engine.ClauseGeneration = G
local L, P = ns.Engine.Lexicon, ns.Engine.Phrases
local renderTree

local function render(tree, english)
    local value = renderTree(tree, english)
    if value then return (value:gsub(",+$", "")) end
end

local function withComma(value)
    return value:sub(-1) == "," and value or value .. ","
end

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

local englishForms = {plural={number="plural"}, third={tense="present", person=3, number="singular"},
    past={tense="past", mood="indicative"}}

local function englishForm(lemma, form, pos)
    local irregular = ns.Linguistics.englishIrregular or {}
    local special = irregular[lemma]
    if special and special[form] then return special[form] end
    local request = englishForms[form]
    local apertium = ns.Engine.Apertium
    if request and apertium then
        local generated = apertium.generate(lemma, "en", pos, request)
        if generated then return generated end
    end
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
        local prefix = intensity == "more" and "more " or intensity == "very" and "very " or intensity == "so" and "so "
            or intensity == "too" and "too " or intensity == "most" and "most " or ""
        return prefix .. base
    end
    if entry.lexeme.frame and entry.lexeme.frame.invariable then return entry.lexeme.uk end
    if not gender and number ~= "plural" then return nil end
    local requestedCase = case
    if case == "accusative" and number == "plural" then
        requestedCase = animacy == "animate" and "genitive" or "nominative"
    elseif case == "accusative" and gender == "masculine" then
        requestedCase = animacy == "animate" and "genitive" or "nominative"
    end
    local features = {case=requestedCase, number=number, gender=number ~= "plural" and gender or nil, degree=degree}
    if intensity == "most" and not degree then
        features.degree = "superlative"
        local synthetic = L.inflect(entry, features)
        if synthetic then return synthetic end
        features.degree = nil
    end
    local value = L.inflect(entry, features)
    if not value then return nil end
    local so = number == "plural" and "такі " or gender == "feminine" and "така " or gender == "neuter" and "таке " or "такий "
    return (intensity == "more" and "більш " or intensity == "very" and "дуже " or intensity == "so" and so
        or intensity == "too" and "надто " or intensity == "most" and "найбільш " or "") .. value
end

local demonstratives = {
    near={masculine="цей", feminine="ця", neuter="це", plural="ці", genitive="цього",
        genitivePlural="цих", feminineAccusative="цю", feminineGenitive="цієї",
        dative={masculine="цьому",feminine="цій",neuter="цьому",plural="цим"},
        locative={masculine="цьому",feminine="цій",neuter="цьому",plural="цих"},
        instrumental={masculine="цим",feminine="цією",neuter="цим",plural="цими"}},
    far={masculine="той", feminine="та", neuter="те", plural="ті", genitive="того",
        genitivePlural="тих", feminineAccusative="ту", feminineGenitive="тієї",
        dative={masculine="тому",feminine="тій",neuter="тому",plural="тим"},
        locative={masculine="тому",feminine="тій",neuter="тому",plural="тих"},
        instrumental={masculine="тим",feminine="тією",neuter="тим",plural="тими"}},
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
    local oblique = forms[case]
    if type(oblique) == "table" then return oblique[number == "plural" and "plural" or node.gender] end
end

local function noun(node, english, case, article, compoundModifier)
    if node.members then
        local values = {}
        for index, member in ipairs(node.members) do
            local join = node.joins[index - 1]
            if join and join.comma then values[#values] = withComma(values[#values])
            elseif join then append(values, (english and join.en or join.uk)[1]) end
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
    local number, requested = compoundModifier and "singular" or node.number, case
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
    local mass = node.term and node.term.features and node.term.features.mass or node.entry and node.entry.head.mass
    if mass and node.term then value = ns.Engine.Normalize.word(value) end
    if node.destination and node.term and node.term.category == "game" then
        value = ns.Engine.Normalize.word(value)
    end
    local parts = {}
    for _, modifier in ipairs(node.adjectives or {}) do
        local word = adjective(modifier, english, requested, number, node.gender, node.animacy)
        if not word then return nil end
        append(parts, word)
    end
    append(parts, value)
    value = table.concat(parts, " ")
    if node.nominalObject then
        local object = G.noun(node.nominalObject, english, node.nominalCase, false, english)
        if not object then return nil end
        value = english and (object .. " " .. value) or (value .. " " .. object)
    end
    if node.possessor then
        local owner = adjective({entry=node.possessor}, english, requested, number, node.gender, node.animacy)
        if not owner then return nil end
        value = owner .. " " .. value
    end
    if node.class then
        if english then
            value = ns.Engine.Normalize.word(node.class.term.en) .. " " .. value
        else
            local class = L.curatedForm(node.class.term, "genitive", "plural")
            if not class then return nil end
            value = value .. " " .. ns.Engine.Normalize.word(class)
        end
    end
    if node.genitive then
        local dependent = G.noun(node.genitive, english, "genitive", english and "definite")
        if not dependent then return nil end
        value = value .. (english and " of " or " ") .. dependent
    end
    if node.destination then
        local destination = G.noun(node.destination, english, "accusative")
        local marker = english and " for " or " на "
        if not destination and not english then
            destination, marker = G.noun(node.destination, false, "genitive"), " до "
        end
        if not destination then return nil end
        if english then destination = destination:gsub("^The ", "the ") end
        value = value .. marker .. destination
    end
    if node.pathTo then
        local goal = G.noun(node.pathTo, english, "genitive")
        if not goal then return nil end
        value = value .. (english and " to " or " до ") .. goal
    end
    if node.ordinal then
        if english then return value .. " " .. node.ordinal end
        return node.ordinal .. "-" .. (P.ordinalSuffixes[requested] or "й") .. " " .. value
    end
    if node.skillRequirement then return english and (value .. " requiring " .. node.skillRequirement)
        or (value .. " (навичка " .. node.skillRequirement .. ")") end
    if node.quantity then return node.quantity .. " " .. value end
    if node.all then
        local forms = {nominative="усі", accusative="усі", genitive="усіх", dative="усім", instrumental="усіма", locative="усіх"}
        return (english and (node.article == "definite" and "all the" or "all") or forms[requested] or "усі") .. " " .. value
    end
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
    if english and not node.possessor and not (node.nominalObject and node.nominalObject.possessor) then
        if node.article == "definite" then return "the " .. value end
        local proper = node.term and (node.term.category == "places" or node.term.features and node.term.features.proper)
        if article == "definite" and not proper and not mass and number == "singular" then return "the " .. value end
        if (article or node.article == "indefinite") and not proper and not mass and number == "singular" then
            local indefinite = value:match("^[AEIOUaeiou]") and "an" or "a"
            return indefinite .. " " .. value
        end
    end
    return value
end

function G.noun(node, english, case, article, compoundModifier)
    local relative = node.relative
    if english and relative and not article and not relative.nonrestrictive then article = "definite" end
    local value = noun(node, english, case, article, compoundModifier)
    if not value or not relative then return value end
    local clause = render(relative.clause, english)
    if not clause then return nil end
    if english then
        local marker = P.relativeAnimate(node) and "who" or (relative.nonrestrictive and "which" or "that")
        if not relative.nonrestrictive then return value .. " " .. marker .. " " .. clause end
        return withComma(value) .. " " .. marker .. " " .. withComma(clause)
    end
    local marker = P.relativePronoun(node, relative.case)
    if not marker then return nil end
    return withComma(value) .. " " .. marker .. " " .. withComma(clause)
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

local function agreement(tree, english)
    local wh = tree.wh
    local subject = tree.subject or tree.inferred or (tree.verb and tree.verb.form) or {}
    if wh and wh.noun and wh.role == "subject" then
        if not english then return 3, "singular", "neuter", "3singular" end
        subject = wh.noun
    end
    local person = subject.person or 3
    local number = subject.number or "singular"
    return person, number, subject.gender, tostring(person) .. number
end

local function ukrainianVerb(tree)
    local entry = tree.verb
    local person, number, gender, key = agreement(tree)
    local frame = entry.lexeme.frame or {}
    local lemma = entry.lexeme.uk
    local verbalModal = tree.modal and tree.modal ~= "might"
    local adverb = tree.leadingAdverb and tree.leadingAdverb.uk[1] .. " " or ""
    if tree.aspect == "passive" then
        return adverb .. (tree.negative and "не " or "") .. (tree.tense == "past" and "було " or "") .. frame.passiveUk
    end
    local form
    if tree.imperative then
        local features = {mood="imperative", person=2, number="singular"}
        if frame.imperative and not tree.negative then form = L.inflectLemma(frame.imperative, "verb", features)
        else form = L.inflect(entry, features) end
    elseif verbalModal or tree.tense == "infinitive" then
        local object = tree.object
        local craft = tree.modal == "can" and frame.itemModalLemma and object
            and ((object.term and object.term.category == "goods") or (object.raw and ns.Engine.Markup.isLink(object.raw, "item")))
        form = tree.purposeClause and frame.purposeLemma
            or craft and frame.itemModalLemma
            or ((tree.modal == "can" or tree.modal == "may") and object and object.number == "singular") and frame.modalLemma
            or (tree.modal == "can" or tree.modal == "could") and frame.possibleOutcome or frame.infinitiveLemma or lemma
    elseif tree.tense == "past" then
        local completed = frame.pastLemma or (tree.aspect == "perfect" and frame.completed)
        local features = {tense="past", mood="indicative", number=number, gender=number == "singular" and gender or nil}
        if number == "singular" and not gender then
            local pronoun = tree.subject and tree.subject.pronoun
            if not (tree.ellipticSubject or tree.wh or (pronoun and (pronoun.id == "i" or pronoun.id == "you"))) then return nil end
            features.gender = "masculine"
            local masculine = L.inflectLemma(completed or lemma, "verb", features)
            features.gender = "feminine"
            local feminine = L.inflectLemma(completed or lemma, "verb", features)
            if masculine and feminine then form = masculine .. "/" .. feminine end
        elseif completed then form = L.inflectLemma(completed, "verb", features)
        else form = L.inflect(entry, features) end
    elseif tree.tense == "future" and frame.futureEventLemma and tree.sentenceAdverb and tree.sentenceAdverb.singleEvent then
        form = L.inflectLemma(frame.futureEventLemma, "verb",
            {tense="future", mood="indicative", person=person, number=number})
    elseif tree.tense == "future" and entry.head.aspect ~= "perfective" then
        form = future[key] .. " " .. lemma
    else
        form = L.inflect(entry, {tense=tree.tense or "present", mood="indicative", number=number, person=person})
    end
    if not form then return nil end
    if verbalModal and not tree.sharedModal then
        local modal = ukrainianModals[tree.modal]
        if tree.modal == "can" or tree.modal == "may" or tree.modalSense == "possibility" then modal = ukrainianModals.can[key]
        elseif tree.modal == "could" then modal = modal[number == "plural" and "plural" or gender]
        elseif tree.modal == "must" then
            modal = L.inflectLemma(modal, "verb", {tense="present", number=number, person=person, mood="indicative"})
        end
        if not modal then return nil end
        form = modal .. " " .. adverb .. form
    else
        form = adverb .. form
    end
    return (tree.negative and "не " or "") .. form
end

local function englishVerb(tree, subject)
    local lemma = tree.verb.lexeme.en
    local adverb = tree.leadingAdverb and tree.leadingAdverb.en[1] .. " " or ""
    if tree.sharedModal then return (tree.negative and "not " or "") .. adverb .. lemma end
    if tree.tense == "infinitive" then return adverb .. lemma end
    local person, number = agreement(tree, true)
    local third = person == 3 and number == "singular"
    local inversion = tree.question and not (tree.wh and tree.wh.role == "subject")
    local prefix
    if tree.modal then prefix = tree.modal
    elseif tree.tense == "future" then prefix = "will"
    elseif tree.negative or inversion then
        prefix = tree.tense == "past" and "did" or (third and not tree.imperative and "does" or "do")
    end
    if prefix then
        local negative = tree.negative and " not" or ""
        if inversion then
            if not subject then return nil end
            return prefix .. " " .. subject .. negative .. " " .. adverb .. lemma
        end
        return (subject and subject .. " " or "") .. prefix .. negative .. " " .. adverb .. lemma
    end
    local form = not tree.imperative and tree.tense == "past" and "past"
        or not tree.imperative and tree.tense ~= "infinitive" and third and "third" or "base"
    return (subject and subject .. " " or "") .. adverb .. englishForm(lemma, form, "verb")
end

local function addPrepositions(parts, tree, english)
    for _, complement in ipairs(tree.prepositions or {}) do
        local value = G.noun(complement.object, english, complement.case, true)
        if not value then return false end
        local rule = complement.rule
        local entry = complement.object.entry
        local frame = entry and entry.lexeme.frame
        local locative = rule.id == "in" and complement.case == "locative" and frame and frame.locativePreposition
        append(parts, english and (rule.targetEn or rule.en[1]) or locative or rule.targetUk)
        append(parts, value)
        if complement.infinitive then
            local action = render(complement.infinitive, english)
            if not action then return false end
            if english then append(parts, "to") end
            append(parts, action)
        end
    end
    return true
end

local function subjectText(tree, english)
    if tree.inherited or (not english and tree.implicitSubject) or (tree.wh and tree.wh.role == "subject") then return "" end
    if tree.subject then
        local article
        if english and tree.wh and tree.wh.role == "predicate" then article = tree.wh.definite and "definite" or true
        elseif english and (tree.temporalDependent or tree.where and not tree.question) then article = "definite" end
        return G.noun(tree.subject, english, "nominative", article)
    end
    if tree.kind == "nounPhrase" or tree.imperative or tree.tense == "infinitive" or not english then return "" end
    local _, number, gender, key = agreement(tree)
    return inferredPronouns[key] or (number == "singular" and inferredPronouns[gender])
end

local whPerson = {accusative="кого", genitive="кого", dative="кому", instrumental="ким"}
local whThing = {accusative="що", genitive="чого", instrumental="чим"}
local whDefinite = {masculine="який", feminine="яка", neuter="яке", plural="які"}
local function questionWord(tree, english)
    local wh = tree.wh
    if wh then
        local word
        if wh.kind == "manner" then return english and "how" or "як"
        elseif wh.kind == "duration" then return english and "how long" or "як довго"
        elseif wh.kind == "quantity" then
            local noun = G.noun(wh.noun, english, english and "nominative" or "genitive")
            if not noun then return nil end
            local opening = english and (wh.noun.number == "plural" and "how many " or "how much ") or "скільки "
            return opening .. noun
        elseif english then word = wh.kind == "person" and "who" or "what"
        elseif wh.role == "predicate" and wh.kind == "person" then word = "хто"
        elseif wh.role == "predicate" then
            local gender = tree.subject.number == "plural" and "plural" or tree.subject.gender
            word = wh.definite and whDefinite[gender] or "що таке"
        elseif wh.role == "subject" then word = wh.kind == "person" and "хто" or "що"
        elseif wh.kind == "person" then word = whPerson[wh.case]
        else word = whThing[wh.case] end
        if word then
            if wh.another then return word .. (english and " else" or " ще") end
            if not english and not tree.question and wh.role == "object" and word == "що" then return "що саме" end
            return word
        end
    end
    if not english and tree.modal == "might" and not tree.sharedModal then return "можливо," end
    if tree.where then return english and "where" or "де" end
    if tree.why then return english and "why" or "чому" end
    if tree.question and not english then return "чи" end
end

local requiredTime = {present="потрібно", past="знадобилося", future="знадобиться"}
local nominalTime = {
    present={singular="займає", plural="займають"}, future={singular="займе", plural="займуть"},
    past={masculine="зайняв", feminine="зайняла", neuter="зайняло", plural="зайняли"},
}

local function durationQuery(tree, english)
    local noun = tree.action and tree.action.noun
    local tense, parts = tree.tense, {}
    if english then
        local aux = tense == "past" and "did" or tense == "future" and "will"
            or noun and noun.number == "plural" and "do" or "does"
        append(parts, "how long " .. aux)
        local subject = noun and G.noun(noun, true, "nominative", true) or (not noun and "it")
        if not subject then return nil end
        append(parts, subject)
        append(parts, "take")
    else
        append(parts, "скільки часу")
    end
    if tree.recipient then
        local recipient = G.noun(tree.recipient, english, english and "accusative" or "dative", true)
        if not recipient then return nil end
        append(parts, recipient)
    end
    if not english then
        if noun then
            local agreement = tense == "past" and noun.number ~= "plural" and noun.gender or noun.number
            local verb = nominalTime[tense][agreement]
            local subject = G.noun(noun, false, "nominative")
            if not verb or not subject then return nil end
            append(parts, verb)
            append(parts, subject)
        else append(parts, requiredTime[tense]) end
    end
    if tree.action and not noun then
        local action = render(tree.action, english)
        if not action then return nil end
        if not english then parts[#parts] = withComma(parts[#parts]) end
        append(parts, english and "to" or "щоб")
        append(parts, action)
    end
    return table.concat(parts, " ")
end

local function duration(tree, english)
    if tree.question then return durationQuery(tree, english) end
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

renderTree = function(tree, english)
    if tree.kind == "duration" then return duration(tree, english) end
    if tree.kind == "levelQuestion" then
        local place = G.noun(tree.place, english, "genitive")
        if not place then return nil end
        local requester = tree.requester.pronoun
        if english then
            local helper = requester.person == 3 and requester.number == "singular" and "does" or "do"
            return "What level " .. helper .. " " .. requester.en.nominative .. " need for " .. place
        end
        return "Який рівень " .. requester.uk.dative .. " потрібен для " .. place
    end
    if tree.kind == "skillLevel" then
        local skill = G.noun(tree.skill, english, english and "accusative" or "genitive")
        if skill then return (english and "level " or "підвищити рівень ") .. ns.Engine.Normalize.word(skill) end
        return nil
    end
    if tree.kind == "requiredQuantity" then
        local quantity = questionWord(tree, english)
        if not quantity then return nil end
        local past = tree.tense == "past"
        return quantity .. (english and (past and " did it take" or " does it take")
            or (past and " знадобилося" or " потрібно"))
    end
    if tree.kind == "priceQuestion" then
        local item = G.noun(tree.subject, english, "nominative", true)
        if not item then return nil end
        local plural = tree.subject.number == "plural"
        local adverb = tree.adverb and " " .. (english and tree.adverb.en or tree.adverb.uk)[1] or ""
        if english then return (plural and "how much do " or "how much does ") .. item .. " cost" .. adverb end
        return (plural and "скільки коштують " or "скільки коштує ") .. item .. adverb
    end
    if tree.kind == "activity" then
        return english and ("do a bit of " .. tree.activity.en[1]) or ("трохи " .. tree.activity.targetUk)
    end
    if tree.kind == "politeRequest" then
        local case = not english and tree.some and "genitive" or "accusative"
        local noun = G.noun(tree.object, english, case, not tree.some)
        if not noun then return nil end
        if english then return (tree.some and "some " or "") .. noun .. ", please" end
        local quantity = tree.some and (tree.object.number == "plural" and "кілька " or "трохи ") or ""
        return (tree.question and "можна " or "") .. quantity .. noun .. ", будь ласка"
    end
    if tree.kind == "need" or tree.kind == "notRequired" then
        local object = tree.object
        local value = G.noun(object, english, "nominative", true)
        if not value then return nil end
        if english then return tree.kind == "need" and ("Need " .. value) or ("No " .. value .. " required") end
        local agreement = object.number == "plural" and "plural" or object.gender
        local forms = {masculine="Потрібен", feminine="Потрібна", neuter="Потрібне", plural="Потрібні"}
        if tree.kind == "notRequired" then
            local statement = value .. " не " .. ns.Engine.Normalize.word(forms[agreement] or "потрібно")
            if not tree.qualification then return statement end
            local qualification = G.noun(tree.qualification, false, "genitive")
            if not qualification then return nil end
            if tree.qualificationAction then
                local action = render(tree.qualificationAction, false)
                if not action then return nil end
                qualification = qualification .. " " .. action
            end
            return statement .. ". Достатньо " .. qualification
        end
        return (forms[agreement] or "Потрібно") .. " " .. value
    end
    if tree.kind == "welcomeGroup" then
        local group = G.noun(tree.subject, english, "accusative")
        if not group then return nil end
        return english and (group .. " welcome") or ("Радо приймемо " .. group)
    end
    if tree.kind == "description" then
        local noun = tree.subject
        local topic, action = G.noun(noun, english, "nominative"), render(tree.action, english)
        if not topic or not action then return nil end
        local relative = {masculine="який", feminine="яка", neuter="яке", plural="які"}
        return topic .. ", " .. (relative[noun.number == "plural" and "plural" or noun.gender] or "що") .. " " .. action
    end
    if tree.kind == "salute" then
        local recipient = G.noun(tree.recipient, english, "dative")
        if not recipient then return nil end
        return (english and "All hail to " or "Слава ") .. recipient
    end
    if tree.kind == "greeting" then
        local name = G.noun(tree.recipient, english, english and "nominative" or "vocative")
            or G.noun(tree.recipient, english, "nominative")
        if name then return (english and "Hello, " or "Вітаю, ") .. name end
        return nil
    end
    if tree.kind == "adverbPhrase" then
        local value = (english and tree.expression.en or tree.expression.uk)[1]
        local parts = {value .. (tree.comma and "," or "")}
        if not addPrepositions(parts, tree, english) then return nil end
        return table.concat(parts, " ")
    end
    if tree.kind == "profile" then
        local noun, parts = tree.subject, {}
        for _, descriptor in ipairs(tree.modifiers) do
            local value = adjective(descriptor, english, "nominative", noun.number, noun.gender, noun.animacy)
            if not value then return nil end
            append(parts, withComma(value))
        end
        local subject = G.noun(noun, english, "nominative")
        if not subject then return nil end
        append(parts, subject)
        if not addPrepositions(parts, tree, english) then return nil end
        return table.concat(parts, " ")
    end
    if tree.kind == "existential" then
        local noun = tree.subject
        local subject = G.noun(noun, english, "nominative", true)
        if not subject then return nil end
        local category = noun.term and noun.term.category
        local profession = category == "classes" or category == "roles"
        if profession then subject = ns.Engine.Normalize.word(subject) end
        local opening = english and (noun.number == "plural" and "Are there " or "Is there ")
            or (tree.nearby and "Чи є тут " or "Чи є ")
        local output = opening .. subject .. (english and tree.nearby and " around" or "")
        if not tree.relative then return output end
        local relative = render(tree.relative, english)
        if not relative then return nil end
        local person = noun.animacy == "animate" or profession or tree.relativeMarker == "who" or tree.relativeMarker == "хто"
        local markers = {masculine="який", feminine="яка", neuter="яке", plural="які"}
        local agreement = noun.number == "plural" and "plural" or noun.gender or (profession and "masculine")
        local connector = english and (person and " who " or " that ")
            or ", " .. (markers[agreement] or (person and "хто" or "що")) .. " "
        return output .. connector .. relative
    end
    if tree.kind == "wish" then
        local parts = {english and "Good luck" or tree.everyone and "Усім удачі" or "Удачі"}
        if tree.everyone and english then append(parts, "to everyone") end
        if tree.recipient then
            local recipient = G.noun(tree.recipient, english, "dative")
            if not recipient then return nil end
            if english then append(parts, "to") end
            append(parts, recipient)
        end
        if not addPrepositions(parts, tree, english) then return nil end
        return table.concat(parts, " ")
    end
    local parts = {}
    local subject = subjectText(tree, english)
    if subject == nil then return nil end
    local question = questionWord(tree, english)
    if tree.wh and not question then return nil end
    if tree.kind == "nounPhrase" then append(parts, subject)
    elseif tree.elliptic then
        append(parts, question)
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
        local person, number, gender = agreement(tree, english)
        local adjectiveFrame = tree.adjective and tree.adjective.entry.lexeme.frame
        if not english and tree.adjectiveContent and tree.tense == "present" and not tree.negative then
            local verb = L.inflectLemma(adjectiveFrame.ukContentLemma, "verb",
                {person=person, number=number, tense="present", mood="indicative"})
            local content = render(tree.adjectiveContent, english)
            if verb and content then return subject .. " " .. verb .. ", що " .. content end
            return nil
        end
        local experiencer = not english and adjectiveFrame and adjectiveFrame.ukExperiencer
        local degree = experiencer and tree.adjective.intensity
        if degree then
            experiencer = (degree == "more" and "більш " or degree == "so" and "так " or degree == "too" and "надто " or "дуже ")
                .. experiencer
        end
        if english then
            local be
            if tree.modal == "might" then be = "might"
            elseif tree.tense == "past" then be = (number == "plural" or person == 2) and "were" or "was"
            else be = (number == "plural" or person == 2) and "are" or (person == 1 and "am" or "is") end
            append(parts, question)
            if tree.question and not (tree.wh and tree.wh.role == "subject") then append(parts, be); append(parts, subject)
            else append(parts, subject); append(parts, be) end
            if tree.negative then append(parts, "not") end
            if tree.modal == "might" then append(parts, "be") end
        else
            append(parts, question)
            if experiencer then
                subject = G.noun(tree.subject, false, "dative")
                if not subject then return nil end
            end
            if tree.modal == "might" and tree.predicate and tree.subject.pronoun and tree.subject.pronoun.id == "it" then
                subject = "це"
            end
            append(parts, subject)
            if tree.modal == "might" and tree.predicate and not tree.subject.pronoun then append(parts, "—") end
            if tree.negative then append(parts, "не") end
            if tree.tense == "past" then
                local be = experiencer and "було" or pastCopula[number == "plural" and "plural" or gender]
                if not be then return nil end
                append(parts, be)
            elseif tree.negative and tree.prepositions and not experiencer then append(parts, "перебуває") end
        end
        if tree.exists then
            append(parts, english and "real" or "існує")
        elseif tree.openForBusiness then
            append(parts, english and "open for business" or "готові до роботи")
        elseif tree.level then
            append(parts, english and ("level " .. tree.level) or (tree.level .. "-го рівня"))
        elseif tree.predicate then
            local value = G.noun(tree.predicate, english, "nominative", true)
            if not value then return nil end
            if not english and not tree.subject.pronoun and tree.predicate.members and tree.tense == "present"
                and not tree.negative then append(parts, "—") end
            append(parts, value)
        elseif tree.adjective then
            local value = experiencer or adjective(tree.adjective, english, "nominative", number, gender, tree.subject.animacy)
            local pronoun = tree.subject.pronoun
            if not value and not english and not gender and number == "singular" and pronoun
                and (pronoun.id == "i" or pronoun.id == "you") then
                local masculine = adjective(tree.adjective, false, "nominative", number, "masculine", tree.subject.animacy)
                local feminine = adjective(tree.adjective, false, "nominative", number, "feminine", tree.subject.animacy)
                if masculine and feminine then
                    local degree = tree.adjective.intensity
                    local prefix = degree == "too" and "надто " or degree == "more" and "більш " or degree == "very" and "дуже " or ""
                    if prefix ~= "" and feminine:sub(1, #prefix) == prefix then feminine = feminine:sub(#prefix + 1) end
                    value = masculine .. "/" .. feminine
                end
            end
            if not value then return nil end
            append(parts, value)
        end
    else
        local frame = tree.verb.lexeme.frame or {}
        if english then
            append(parts, question)
            local value = englishVerb(tree, subject ~= "" and subject or nil)
            if not value then return nil end
            append(parts, value)
        else
            local need = frame.impersonalNeed and tree.infinitive and tree.subject and not tree.modal
            if need then subject = G.noun(tree.subject, false, "dative") end
            if tree.aspect == "passive" then
                local pronoun = tree.subject.pronoun
                subject = pronoun and pronoun.id == "it" and "це" or G.noun(tree.subject, false, "accusative")
            end
            if not subject then return nil end
            append(parts, question)
            append(parts, subject)
            local time = tree.tense == "past" and "було " or tree.tense == "future" and "буде " or ""
            local value = need and ((tree.negative and "не " or "") .. time .. "потрібно") or ukrainianVerb(tree)
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
            append(parts, english and frame.enObjectPreposition or not english and frame.objectPreposition)
            if not english and frame.deicticObject and tree.object.pronoun and tree.object.pronoun.id == "it" then
                value = frame.deicticObject
            end
            append(parts, value)
        elseif not english and frame.ukImplicitObject and not (tree.wh and tree.wh.role == "object") then
            append(parts, frame.ukImplicitObject)
        end
        if tree.separation then
            local removed = G.noun(tree.separation, english, "genitive")
            if not removed then return nil end
            append(parts, english and "of" or "від")
            append(parts, removed)
        end
        if tree.infinitive then
            local value = render(tree.infinitive, english)
            if not value then return nil end
            if english and not frame.bareInfinitive then append(parts, "to") end
            append(parts, value)
        end
        if tree.controlled then
            local control = tree.controlled
            local actor = G.noun(control.actor, english, english and "accusative" or frame.controlCase, true)
            local action = render(control.action, english)
            if not actor or not action then return nil end
            append(parts, actor)
            if english and control.action.negative then append(parts, "not") end
            append(parts, action)
        end
        if not english and frame.ukManner then append(parts, frame.ukManner) end
        if tree.content then
            for index, embedded in ipairs(tree.content) do
                local value = render(embedded, english)
                if not value then return nil end
                if index > 1 then append(parts, english and "and" or "і")
                elseif not english then parts[#parts] = withComma(parts[#parts]) end
                if not embedded.where and not embedded.why and not embedded.wh then append(parts, english and "that" or "що") end
                append(parts, value)
            end
        end
    end
    if not addPrepositions(parts, tree, english) then return nil end
    for _, adverb in ipairs(tree.adverbs or {}) do
        if adverb.afterComma then parts[#parts] = withComma(parts[#parts]) end
        append(parts, (english and adverb.en or adverb.uk)[1])
    end
    if tree.purpose then
        local purpose = tree.purpose
        local value, marker
        if purpose.verb or purpose.kind == "activity" then
            value = render(purpose, english)
            marker = english and (purpose.negative and "not to" or "to") or "щоб"
        else
            value = G.noun(purpose.object, english, "accusative", true)
            marker = english and "for" or "щоб отримати"
        end
        if not value then return nil end
        if not english then parts[#parts] = withComma(parts[#parts]) end
        append(parts, marker)
        append(parts, value)
        for _, item in ipairs(purpose.series or {}) do
            local continuation = render(item.action, english)
            if not continuation then return nil end
            if item.join then append(parts, (english and item.join.en or item.join.uk)[1])
            else parts[#parts] = withComma(parts[#parts]) end
            append(parts, continuation)
        end
    end
    if tree.apposition then
        local description = G.noun(tree.apposition, english, "nominative")
        if not description then return nil end
        append(parts, "—")
        append(parts, description)
    end
    if tree.addressee then
        local address = G.noun(tree.addressee, english, english and "nominative" or "vocative")
        if not address then return nil end
        parts[#parts] = withComma(parts[#parts])
        append(parts, address)
    end
    if tree.relativeApposition then
        local relative = tree.relativeApposition
        local content = render(relative.clause, english)
        if not content then return nil end
        local antecedent = tree.predicate
        local demonstrative = antecedent.number == "plural" and "ті" or antecedent.gender == "feminine" and "та" or "той"
        parts[#parts] = withComma(parts[#parts]) .. " " .. demonstrative .. ","
        append(parts, relative.linker)
        append(parts, content)
    end
    return table.concat(parts, " ")
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
        if tree.sentenceAdverb then
            value = (english and tree.sentenceAdverb.en or tree.sentenceAdverb.uk)[1] .. " " .. value
        end
        local join = parse.joins[i - 1]
        if join and join.sentence then
            parts[#parts] = parts[#parts] .. (join.punctuation or ".")
            value = ns.Engine.Normalize.upperStart(value)
        elseif join then
            local id = join.rule and join.rule.id
            local comma = join.comma or (join.rule and join.rule.temporal and not english)
                or id == "but" or id == "because" or id == "if" or id == "when"
                or id == "unless" or id == "so" or id == "while"
            if join.dash then append(parts, "—")
            elseif comma then parts[#parts] = withComma(parts[#parts]) end
            if join.rule then append(parts, (english and join.rule.en or join.rule.uk)[1]) end
        end
        append(parts, value)
        last = tree
    end
    return ns.Engine.Normalize.upperStart(table.concat(parts, " ")) .. (last.question and "?" or punctuation or ".")
end
