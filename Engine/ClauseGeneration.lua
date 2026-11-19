local _, ns = ...
local G = {}
ns.Engine.ClauseGeneration = G
local L, P = ns.Engine.Lexicon, ns.Engine.Phrases
local renderTree

local function render(tree, english, controller)
    local value = renderTree(tree, english, controller)
    if value then return (value:gsub(",+$", "")) end
end

local function withComma(value)
    return value:sub(-1) == "," and value or value .. ","
end

local function append(parts, value)
    if value and value ~= "" then parts[#parts + 1] = value end
end

local function euphonicZ(marker, value)
    if marker ~= "з" then return marker end
    local initial = ns.Engine.Normalize.word(value):sub(1, 2)
    if initial == "з" or initial == "с" or initial == "ш" or initial == "щ" then return "зі" end
    return marker
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
    past={tense="past", mood="indicative"}, ing={tense="present", verbalForm="participle"},
    participle={tense="past", verbalForm="participle"}}

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
    if form == "past" or form == "participle" then
        if form == "participle" and special and special.past then return special.past end
        if lemma:match("e$") then return lemma .. "d" end
        if lemma:match("[^aeiou]y$") then return lemma:sub(1, -2) .. "ied" end
        return lemma .. "ed"
    end
    if form == "ing" then
        if lemma:match("ie$") then return lemma:sub(1, -3) .. "ying" end
        if lemma:match("[^eoy]e$") and #lemma > 2 then return lemma:sub(1, -2) .. "ing" end
        return lemma .. "ing"
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

local function adjectiveCase(case, number, gender, animacy)
    if case == "accusative" and (number == "plural" or gender == "masculine") then
        return animacy == "animate" and "genitive" or "nominative"
    end
    return case
end

local function adjective(modifier, english, case, number, gender, animacy)
    local entry, intensity = modifier.entry, modifier.intensity
    local degree = entry.form.degree
    if english then
        local base = entry.lexeme.en
        local apertium = ns.Engine.Apertium
        if degree and not intensity and apertium then
            local inflected = apertium.generate(base, "en", "adj", {degree=degree})
            if inflected then return inflected end
        end
        if degree == "comparative" then base = "more " .. base
        elseif degree == "superlative" then base = "most " .. base end
        local prefix = intensity == "more" and "more " or intensity == "very" and "very " or intensity == "so" and "so "
            or intensity == "too" and "too " or intensity == "most" and "most " or intensity == "quite" and "quite " or ""
        return prefix .. base
    end
    if entry.lexeme.frame and entry.lexeme.frame.invariable then return entry.lexeme.uk end
    if not gender and number ~= "plural" then return nil end
    local requestedCase = adjectiveCase(case, number, gender, animacy)
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

local function targetNumber(node, english)
    if node.entry then
        local frame = node.entry.lexeme.frame
        if english and frame and frame.englishNumber then return frame.englishNumber end
        if not english and node.entry.head.number == "plural" then return "plural" end
    end
    return node.number
end

local speechPossessives = {my=true, our=true, your=true}
local reflexiveEn = {my="myself", your="yourself", our="ourselves", his="himself", her="herself",
    its="itself", their="themselves"}
local function possessiveText(entry, english, case, number, gender, animacy, owner)
    if english and entry.lexeme.frame.reflexivePossessive and owner then return owner end
    if not english and owner and speechPossessives[owner] and owner == entry.lexeme.en then
        local features = {case=adjectiveCase(case, number, gender, animacy), number=number,
            gender=number ~= "plural" and gender or nil}
        local reflexive = L.inflectLemma("свій", "det", features) or L.inflectLemma("свій", "pron", features)
        if reflexive then return reflexive end
    end
    return adjective({entry=entry}, english, case, number, gender, animacy)
end

local function noun(node, english, case, article, compoundModifier, owner)
    if node.members then
        local values = {}
        for index, member in ipairs(node.members) do
            local join = node.joins[index - 1]
            if join and join.comma then values[#values] = withComma(values[#values])
            elseif join then append(values, (english and join.en or join.uk)[1]) end
            local value = G.noun(member, english, case, article, nil, owner)
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
    local number, requested = compoundModifier and "singular" or targetNumber(node, english), case
    if not english and case == "accusative" and node.partitive then requested = "genitive" end
    if node.few and not english and (case == "nominative" or case == "accusative") then requested = "genitive" end
    if not english and (node.sufficient or node.some or node.many or node.more or node.abundance) then requested = "genitive" end
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
            local frame = node.entry.lexeme.frame
            value = frame and node.quantity and requested == "nominative" and number == "plural" and frame.countedFewUk
                or L.inflect(node.entry, {case=requested, number=number})
        end
    end
    if not value then return nil end
    local frame = node.entry and node.entry.lexeme.frame
    local mass = P.mass(node)
    if node.term and (mass or node.term.category == "classes"
        or english and node.term.features and node.term.features.englishCommon
        or english and (article == "definite" or node.destination) and node.term.category == "roles" and node.term.en:find("%l")) then
        value = ns.Engine.Normalize.word(value)
    end
    if node.destination and node.term and node.term.category == "game" then
        value = ns.Engine.Normalize.word(value)
    end
    local placeCompound = english and frame and frame.placeCompound and node.genitive
        and node.genitive.term and node.genitive.term.category == "places"
    local parts = {}
    for _, modifier in ipairs(node.adjectives or {}) do
        local modifierFrame = modifier.entry.lexeme.frame
        if english and article == true and not node.article and modifierFrame and modifierFrame.definiteHead then
            article = "definite"
        end
        local word = adjective(modifier, english, requested, number, node.gender, node.animacy)
        if not word then return nil end
        append(parts, word)
    end
    if placeCompound then
        local place = G.noun(node.genitive, true, "genitive")
        if not place then return nil end
        append(parts, (place:gsub("^The ", "")))
    end
    local argumentCompound = english and node.argument and node.argument.form.englishCompound
    if argumentCompound then
        local argument = G.noun(node.argument.object, true, "nominative", false, true, owner)
        if not argument then return nil end
        append(parts, argument)
        if article == true and not node.article then article = "definite" end
    end
    append(parts, value)
    value = table.concat(parts, " ")
    if node.nominalObject then
        local object = G.noun(node.nominalObject, english, node.nominalCase, false, english, owner)
        if not object then return nil end
        value = english and (object .. " " .. value) or (value .. " " .. object)
    end
    if node.possessor then
        local possessive = possessiveText(node.possessor, english, requested, number, node.gender, node.animacy, owner)
        if not possessive then return nil end
        value = possessive .. " " .. value
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
    if node.genitive and not placeCompound then
        local dependent = G.noun(node.genitive, english, "genitive", english and "definite", nil, owner)
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
        local goal = G.noun(node.pathTo, english, "genitive", english)
        if not goal then return nil end
        value = value .. (english and " to " or " до ") .. goal
    end
    if node.argument and not argumentCompound then
        local argument, form = node.argument.object, node.argument.form
        local object = G.noun(argument, english, english and "accusative" or form.case, true, nil, owner)
        if not object then return nil end
        local marker = english and form.en or euphonicZ(form.uk, object)
        value = value .. " " .. marker .. " " .. object
    end
    if node.nominalAction then
        local action = render(node.nominalAction, english, owner)
        if not action then return nil end
        value = value .. (english and " to " or node.nominalAction.nominalPurpose and ", щоб " or " ") .. action
    end
    if node.ordinal then
        if english then value = value .. " " .. node.ordinal
        else value = node.ordinal .. "-" .. (P.ordinalSuffixes[requested] or "й") .. " " .. value end
        if not node.same then return value end
    end
    if node.skillRequirement then
        value = english and (value .. " requiring " .. node.skillRequirement)
            or (value .. " (навичка " .. node.skillRequirement .. ")")
        if not node.same then return value end
    end
    if node.quantity then
        if node.additional then
            local one = tonumber(node.quantity) == 1
            if english then value = (one and "one" or node.quantity) .. " more " .. value
            else value = "ще " .. (one and P.one(node.gender, case, node.animacy) or node.quantity) .. " " .. value end
        else value = node.quantity .. " " .. value end
        if not node.same then return value end
        number = tonumber(node.quantity) == 1 and "singular" or "plural"
    end
    if node.sufficient then return (english and "enough " or "достатньо ") .. value end
    if node.many then return (english and "lots of " or "багато ") .. value end
    if node.abundance then return (english and "plenty of " or "вдосталь ") .. value end
    if node.more then
        local emphasis = node.evenMore and (english and "even " or "ще ") or ""
        return emphasis .. (english and "more " or "більше ") .. value
    end
    if node.some then return (english and "some " or "трохи ") .. value end
    if node.few then
        local quantifier = english and "a few" or P.fewForms[case]
        if not quantifier then return nil end
        return quantifier .. " " .. value
    end
    if node.same then
        if english then return (node.all and "all the same " or "the same ") .. value end
        local determiner = demonstrative(node, false, case, number)
        local gender = number ~= "plural" and node.gender or nil
        local same = ns.Engine.Apertium.generate("самий", "uk", "det",
            {case=case, number=number, gender=gender}, node)
        if not same and not ns.ApertiumData then
            local fallback = adjectiveCase(case, number, gender, node.animacy)
            same = L.inflectLemma("самий", "adj", {case=fallback, number=number, gender=gender})
        end
        if not determiner or not same then return nil end
        local allCase = adjectiveCase(case, number, gender, node.animacy)
        local all = node.all and (P.allForms[allCase] or "усі") .. " " or ""
        return all .. determiner .. " " .. same .. " " .. value
    end
    if node.all then
        return (english and (node.article == "definite" and "all the" or "all") or P.allForms[requested] or "усі") .. " " .. value
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
        if article and not node.article and frame and frame.englishArticle ~= nil then article = frame.englishArticle end
        if article == "bare-unmodified" then article = node.adjectives and #node.adjectives > 0 and "definite" or false end
        local proper = node.term and (node.term.category == "places" or node.term.features and node.term.features.proper)
        local uncountable = mass and not (frame and frame.englishCountable)
            or node.term and node.term.features and node.term.features.englishUncountable
        if article == "definite" and not proper and not uncountable and number == "singular" then return "the " .. value end
        if (article or node.article == "indefinite") and not proper and not uncountable and number == "singular" then
            local indefinite = frame and not node.adjectives and not argumentCompound and frame.englishIndefiniteArticle
                or value:match("^[AEIOUaeiou]") and "an" or "a"
            return indefinite .. " " .. value
        end
    end
    return value
end

function G.noun(node, english, case, article, compoundModifier, owner)
    local relative = node.relative
    if english and relative and not article and not relative.nonrestrictive then article = "definite" end
    local value = noun(node, english, case, article, compoundModifier, owner)
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
    if relative.clause.relativeMarkerUk then marker = relative.clause.relativeMarkerUk .. " " .. marker end
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
    local pronoun = subject.pronoun
    local number = pronoun and pronoun.ukNumber and (english and pronoun.number or pronoun.ukNumber)
        or targetNumber(subject, english) or "singular"
    local gender = subject.gender
    if not english and not gender and tree.copula and tree.adjective
        and subject.pronoun and subject.pronoun.id == "someone" then gender = "masculine" end
    return person, number, gender, tostring(person) .. number
end

local function agreedAdjective(modifier, english, case, subject, number, gender)
    local animacy = subject and subject.animacy
    local value = adjective(modifier, english, case, number, gender, animacy)
    local pronoun = subject and subject.pronoun
    if value or english or gender or number ~= "singular" or not pronoun
        or (pronoun.id ~= "i" and pronoun.id ~= "you") then return value end
    local masculine = adjective(modifier, false, case, number, "masculine", animacy)
    local feminine = adjective(modifier, false, case, number, "feminine", animacy)
    if masculine and feminine then
        local degree = modifier.intensity
        local prefix = degree == "too" and "надто " or degree == "more" and "більш " or degree == "very" and "дуже " or ""
        if prefix ~= "" and feminine:sub(1, #prefix) == prefix then feminine = feminine:sub(#prefix + 1) end
        return masculine .. "/" .. feminine
    end
end

local propertyDegreeUk = {more="більш ", very="дуже ", so="настільки ", too="надто ", quite="доволі "}
local function propertyValue(tree, english, case)
    local property = tree.property
    if english then return adjective(property, true) end
    local value
    if case == "adverb" then
        local forms = ns.Linguistics.propertyAdverbs
        value = forms and forms.forms[property.entry.lexeme.uk]
    else
        local _, number, gender = agreement(tree)
        value = agreedAdjective({entry=property.entry}, false, case, tree.subject, number, gender)
    end
    if value then return (propertyDegreeUk[property.intensity] or "") .. value end
end

local function renderObserved(event, english)
    if not english then return render(event, false) end
    local bare = {}
    for key, value in pairs(event) do bare[key] = value end
    bare.inherited, bare.tense, bare.gerund = true, "infinitive", event.perceptionProgressive
    local action = render(bare, true)
    if action and event.negative then return "not " .. action end
    return action
end

local function ukrainianVerb(tree)
    local entry = tree.verb
    local person, number, gender, key = agreement(tree)
    local frame = entry.lexeme.frame or {}
    local lemma = entry.lexeme.uk
    local modality = tree.modalSense == "request" and "can" or tree.modal
    local verbalModal = modality and modality ~= "might"
    local leading = tree.leadingAdverb
    local adverb = leading and ((tree.tense == "past" and not tree.negative and leading.pastUk) or leading.uk[1]) .. " " or ""
    local preNegative = ""
    if tree.negative and leading and (leading.preNegative or tree.infinitiveAntonym and leading.sentenceInitial) then
        preNegative, adverb = adverb, ""
    end
    if tree.deadlineMain and tree.aspect == "perfect" and not tree.negative and not tree.leadingAdverb then
        local explicit
        for _, modifier in ipairs(tree.adverbs or {}) do
            if modifier.en[1] == "already" then
                explicit = true
                break
            end
        end
        if not explicit then adverb = "вже " end
    end
    if tree.hortative then
        local features = {mood="imperative", person=1, number="plural"}
        local chosen = not tree.negative and frame.imperative or lemma
        local form = L.inflectLemma(chosen, "verb", features)
        local negative = tree.negative and "не " or ""
        if form then return negative .. adverb .. form end
        return "давай " .. negative .. adverb .. (frame.infinitiveLemma or chosen)
    end
    if tree.aspect == "passive" then
        return adverb .. (tree.negative and "не " or "") .. (tree.tense == "past" and "було " or "") .. frame.passiveUk
    end
    local singleEvent = tree.delay or tree.sequencedEvent or tree.sentenceAdverb and tree.sentenceAdverb.singleEvent
    if not singleEvent and tree.tense == "future" and frame.futureEventLemma then
        for _, modifier in ipairs(tree.adverbs or {}) do
            if modifier.singleEvent then singleEvent = true; break end
        end
    end
    local form
    if tree.imperative then
        local features = {mood="imperative", person=2, number="singular"}
        if frame.imperative and not tree.negative then form = L.inflectLemma(frame.imperative, "verb", features)
        else form = L.inflect(entry, features) end
    elseif verbalModal or tree.tense == "infinitive" then
        local object = tree.object
        local craft = modality == "can" and frame.itemModalLemma and object
            and ((object.term and object.term.category == "goods") or (object.raw and ns.Engine.Markup.isLink(object.raw, "item")))
        if not craft and tree.ability and frame.itemModalLemma then
            for _, adjunct in ipairs(tree.prepositions or {}) do
                if adjunct.rule.id == "with" and P.semanticClass(adjunct.object) == "craftingMaterials" then
                    craft = true
                    break
                end
            end
        end
        form = tree.purposeClause and frame.purposeLemma
            or tree.intendedEvent and not tree.negative
                and (frame.purposeLemma or frame.infinitiveLemma or frame.imperative or frame.modalLemma)
            or tree.contentClause and tree.tense == "infinitive" and not tree.negative and frame.indirectInfinitiveLemma
            or modality == "should" and not tree.negative and frame.adviceLemma
            or tree.tense == "infinitive" and tree.controlled and frame.controlledInfinitiveLemma
            or craft and frame.itemModalLemma
            or (modality == "can" or modality == "may" or modality == "could")
                and (tree.infinitive or tree.controlled) and frame.modalWithInfinitiveLemma
            or ((modality == "can" or modality == "may") and object and object.number == "singular") and frame.modalLemma
            or (modality == "can" or modality == "could") and frame.possibleOutcome or frame.infinitiveLemma or lemma
    elseif (tree.temporalDependent and tree.tense == "present" and frame.ukSequencedLemma)
        or ((tree.deadlineFuture and tree.tense == "present" or tree.deadlineMain and tree.tense == "future")
            and frame.pastLemma) then
        form = L.inflectLemma(frame.ukSequencedLemma or frame.pastLemma, "verb",
            {tense="future", mood="indicative", person=person, number=number})
    elseif tree.tense == "past" then
        local ongoingNegation = tree.negative and tree.since and tree.aspect == "perfect"
        local completed = not ongoingNegation and (frame.pastLemma or (tree.aspect == "perfect" and frame.completed))
        if frame.pastByMeans then
            for _, complement in ipairs(tree.prepositions or {}) do
                if complement.rule.id == "on" then
                    local variant = frame.pastByMeans[P.semanticClass(complement.object)]
                    if variant then completed = variant; break end
                end
            end
        end
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
    elseif tree.tense == "future" and (frame.futureLemma or frame.futureEventLemma and singleEvent) then
        form = L.inflectLemma(frame.futureLemma or frame.futureEventLemma, "verb",
            {tense="future", mood="indicative", person=person, number=number})
    elseif tree.tense == "future" and entry.head.aspect ~= "perfective" then
        form = future[key] .. " " .. lemma
    else
        form = L.inflect(entry, {tense=tree.tense or "present", mood="indicative", number=number, person=person})
    end
    if not form then return nil end
    if verbalModal and not tree.sharedModal then
        local modal = ukrainianModals[modality]
        if tree.ability and tree.ability ~= "present" then
            local conditional = tree.ability == "conditional"
            local features = {tense=tree.ability == "future" and "future" or "past", mood="indicative",
                number=number, gender=number == "singular" and gender or nil}
            if features.tense == "future" then
                features.person, features.gender = person, nil
            end
            if features.tense == "past" and number == "singular" and not gender then
                features.gender = "masculine"
                local masculine = L.inflectLemma("змогти", "verb", features)
                features.gender = "feminine"
                local feminine = L.inflectLemma("змогти", "verb", features)
                modal = masculine and feminine and (masculine .. (conditional and " би/" or "/")
                    .. feminine .. (conditional and " б" or ""))
            else
                modal = L.inflectLemma("змогти", "verb", features)
                if modal and conditional then modal = modal .. (features.gender == "masculine" and " би" or " б") end
            end
        elseif modality == "can" or modality == "may" or tree.modalSense == "possibility" then modal = ukrainianModals.can[key]
        elseif modality == "could" then modal = modal[number == "plural" and "plural" or gender]
        elseif modality == "must" then
            modal = L.inflectLemma(modal, "verb", {tense="present", number=number, person=person, mood="indicative"})
        end
        if not modal then return nil end
        form = modal .. " " .. adverb .. form
    else
        form = adverb .. form
    end
    return preNegative .. (tree.negative and "не " or "") .. form
end

local function presentBe(person, number)
    if number == "plural" or person == 2 then return "are" end
    return person == 1 and "am" or "is"
end

local function englishVerb(tree, subject)
    if tree.allSubject and subject then subject = subject .. " all" end
    local lexeme = tree.verb.lexeme
    local frame = lexeme.frame or {}
    local lemma = tree.content and not tree.recipient and frame.enContentWithoutRecipient or lexeme.en
    local particle = frame.particle
    if particle and tree.object and (tree.object.pronoun or frame.objectBeforeParticle) then
        lemma = lemma:sub(1, -#particle - 2)
    end
    local leading = tree.leadingAdverb
    local adverb = leading and not leading.postposedEn and leading.en[1] .. " " or ""
    if tree.hortative then return "Let's " .. (tree.negative and "not " or "") .. adverb .. lemma end
    if tree.sharedModal then return (tree.negative and "not " or "") .. adverb .. lemma end
    if tree.tense == "infinitive" then return adverb .. (tree.gerund and englishForm(lemma, "ing", "verb") or lemma) end
    local person, number = agreement(tree, true)
    local third = person == 3 and number == "singular"
    local inversion = tree.question and not (tree.wh and tree.wh.role == "subject")
    local prefix
    if tree.ability then
        if tree.ability == "future" or tree.ability == "conditional" then
            prefix = tree.ability == "future" and "will" or "would"
            lemma = "be able to " .. lemma
        else
            prefix = tree.ability == "past" and ((number == "plural" or person == 2) and "were" or "was")
                or presentBe(person, number)
            lemma = "able to " .. lemma
        end
    elseif tree.modal then prefix = tree.modal
    elseif tree.reportedFuture then prefix = "would"
    elseif tree.reportedAnterior or tree.deadlineMain and tree.tense == "past" and tree.verb.head.aspect == "perfective" then
        prefix, lemma = "had", englishForm(lemma, "participle", "verb")
    elseif tree.occurrencePerfect or tree.since and (tree.tense == "past" or tree.tense == "present") then
        prefix, lemma = tree.occurrencePerfect == "past" and "had" or third and "has" or "have",
            englishForm(lemma, "participle", "verb")
    elseif tree.tense == "present" and (tree.aspect == "continuous" or frame.englishProgressiveWithPurpose and tree.purpose
        or frame.englishProgressiveStill and leading and leading.en[1] == "still") then
        prefix, lemma = presentBe(person, number), englishForm(lemma, "ing", "verb")
    elseif tree.tense == "future" and not tree.temporalDependent then
        prefix = "will"
        if tree.aspect == "continuous" then lemma = "be " .. englishForm(lemma, "ing", "verb") end
    elseif tree.negative or inversion then
        prefix = tree.tense == "past" and "did" or (third and not tree.imperative and "does" or "do")
    end
    if prefix then
        local negative = tree.negative and " not" or ""
        if inversion then
            if not subject then return nil end
            return prefix .. " " .. subject .. negative .. " " .. adverb .. lemma
        end
        if tree.negative and leading and leading.sentenceInitial then
            return (subject and subject .. " " or "") .. adverb .. prefix .. negative .. " " .. lemma
        end
        return (subject and subject .. " " or "") .. prefix .. negative .. " " .. adverb .. lemma
    end
    local form = not tree.imperative and tree.tense == "past" and "past"
        or not tree.imperative and tree.tense ~= "infinitive" and third and "third" or "base"
    return (subject and subject .. " " or "") .. adverb .. englishForm(lemma, form, "verb")
end

function G.preposition(complement, english, owner)
    local rule = complement.rule
    local case = complement.case
    local pronoun = not english and complement.object.pronoun
    local marked = pronoun and (case == "genitive" or case == "accusative") and pronoun.ukGenitiveAfterPreposition
    local article = rule.englishArticle
    if article == nil then article = true end
    local value = marked or G.noun(complement.object, english, case, article, nil, owner)
    if not value then return nil end
    local entry = complement.object.entry
    local frame = entry and entry.lexeme.frame
    local locative = rule.id == "in" and complement.case == "locative" and frame and frame.locativePreposition
    local targetEn = rule.targetEnByClass and rule.targetEnByClass[P.semanticClass(complement.object)]
    local marker = english and (targetEn or rule.targetEn or rule.en[1]) or complement.targetUk or locative or rule.targetUk
    if not english then marker = euphonicZ(marker, value) end
    return value, marker
end

local function addPrepositions(parts, tree, english, owner)
    for _, complement in ipairs(tree.prepositions or {}) do
        local value, marker = G.preposition(complement, english, owner)
        if not value then return false end
        append(parts, marker)
        append(parts, value)
        if complement.infinitive then
            local action = render(complement.infinitive, english, owner)
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
        if not english and tree.modal == "should" then return G.noun(tree.subject, false, "dative") end
        local article, value
        local frame = tree.verb and tree.verb.lexeme.frame
        local pronoun = tree.subject.pronoun
        if not english and frame and frame.deicticSubject and pronoun
            and (pronoun.id == "that" or pronoun.id == "this") then return frame.deicticSubject end
        if english and tree.question and (tree.copula or not tree.modal or tree.subjectLocation)
            and tree.subject.pronoun and tree.subject.pronoun.id == "someone" then
            value = "anyone"
        end
        if english and tree.wh and tree.wh.role == "predicate" then article = tree.wh.definite and "definite" or true
        elseif english and tree.wh and tree.wh.kind == "clock" then article = "definite"
        elseif english and (tree.kind == "need" or tree.subjectLocation or tree.temporalDependent
            or tree.contentClause or tree.predicateAdverb or tree.adverbComplement
            or tree.where and not tree.question) then
            article = "definite"
        end
        if english and not article and frame and frame.impersonalNeed and tree.infinitive then article = "definite" end
        if english and not article and frame and frame.definiteSubject then article = "definite" end
        if english and not article and tree.ability then article = true end
        if english and not article and tree.subject.term then
            local category = tree.subject.term.category
            for _, phrase in ipairs(tree.prepositions or {}) do
                if phrase.rule.definiteParticipants and (category == "roles" or category == "classes") then
                    article = "definite"
                    break
                end
            end
        end
        value = value or G.noun(tree.subject, english, "nominative", article)
        if not value or not tree.subjectLocation then return value end
        local parts = {value}
        if addPrepositions(parts, tree.subjectLocation, english) then return table.concat(parts, " ") end
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
        elseif wh.kind == "clock" then return english and "what time" or "о котрій"
        elseif wh.determiner then
            local case = english and "accusative" or wh.case
            local noun = G.noun(wh.noun, english, case)
            local marker = english and wh.determiner or P.relativePronoun(wh.noun, case)
            if noun and marker then return marker .. " " .. noun end
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
            if not english and not tree.question and tree.tense ~= "infinitive" and wh.role == "object" and word == "що" then
                return "що саме"
            end
            return word
        end
    end
    if not english and tree.modal == "might" and not tree.sharedModal then return "можливо," end
    if tree.where then return english and "where" or "де" end
    if tree.why then return english and "why" or "чому" end
    if tree.when then return english and "when" or "коли" end
    if tree.question and not english then return "чи" end
end

local requiredTime = {present="потрібно", past="знадобилося", future="знадобиться"}
local nominalTime = {
    present={singular="займає", plural="займають"}, future={singular="займе", plural="займуть"},
    past={masculine="зайняв", feminine="зайняла", neuter="зайняло", plural="зайняли"},
}

local function relativeDuration(tree, english)
    local parts, factor = {}, tree.multiplier
    if tree.question then append(parts, english and "why" or "чому") end
    if english then
        if tree.question then
            local aux = tree.tense == "past" and "did" or tree.tense == "future" and "will" or "does"
            append(parts, aux .. " it take")
        else
            local verb = tree.tense == "past" and "took" or tree.tense == "future" and "will take" or "takes"
            append(parts, "it " .. verb)
        end
    end
    if tree.recipient then
        local recipient = G.noun(tree.recipient, english, english and "accusative" or "dative", true)
        if not recipient then return nil end
        append(parts, recipient)
    end
    if english then
        local fraction = tree.lessTime and (({[2]="half", [3]="a third", [4]="a quarter"})[factor] or ("1/" .. factor))
        append(parts, (fraction or (factor == 2 and "twice" or factor .. " times")) .. " as long to")
    else
        append(parts, requiredTime[tree.tense])
        local last, pair = factor % 10, factor % 100
        local unit = last == 1 and pair ~= 11 and "раз"
            or last >= 2 and last <= 4 and (pair < 12 or pair > 14) and "рази" or "разів"
        append(parts, factor == 2 and "удвічі" or factor == 3 and "утричі" or "у " .. factor .. " " .. unit)
        append(parts, tree.lessTime and "менше часу, щоб" or "більше часу, щоб")
    end
    local action = render(tree.action, english)
    if not action then return nil end
    append(parts, action)
    return table.concat(parts, " ")
end

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

local function quantityText(quantity, english)
    local approximation = quantity.approximate and (english and "about " or "приблизно ") or ""
    if quantity.half then
        if english then
            local unit = P.englishUnits[quantity.unit]
            local article = unit == "hour" and "an " or "a "
            return approximation .. "half " .. article .. unit
        end
        local unit = L.inflectLemma(quantity.unit, "noun", {case="genitive", number="singular"})
        return unit and (approximation .. "пів " .. unit)
    end
    local word
    if english then
        local unit = P.englishUnits[quantity.unit]
        word = not quantity.few and tonumber((quantity.amount:gsub(",", "."))) == 1 and unit
            or englishForm(unit, "plural", "noun")
    else
        local case, number
        if quantity.few then case, number = "genitive", "plural"
        else case, number = countedCase(quantity.amount, "accusative", false) end
        word = L.inflectLemma(quantity.unit, "noun", {case=case, number=number})
    end
    if not word then return nil end
    local amount = quantity.few and (english and "a few" or "кілька") or quantity.amount
    return approximation .. amount .. " " .. word
end

local function pastAppraisal(tree)
    local topic, subject = tree.predicate, tree.subject
    local pointer = subject and subject.pronoun
    if not topic or not topic.adjectives or not pointer or (pointer.id ~= "that" and pointer.id ~= "this")
        or tree.tense ~= "past" or tree.negative or tree.question or tree.prepositions or tree.adverbs then return end
    local remaining, manner = {}
    for _, modifier in ipairs(topic.adjectives) do
        local frame = modifier.entry.lexeme.frame
        if frame and frame.outcome and not modifier.intensity then
            if manner then return nil end
            manner = frame.outcome
        else remaining[#remaining + 1] = modifier end
    end
    if not manner then return end
    local entity = {}
    for key, value in pairs(topic) do entity[key] = value end
    entity.adjectives = remaining
    local frame = entity.entry and entity.entry.lexeme.frame
    if frame and (frame.appraisalTarget or frame.semanticClass == "opponent") then
        local opponent = G.noun(entity, false, "instrumental")
        if opponent then return "З " .. opponent .. " упоралися " .. manner end
    else
        local event = G.noun(entity, false, "nominative")
        local agreement = entity.number == "plural" and "plural" or entity.gender
        local completed = ({masculine="пройшов", feminine="пройшла", neuter="пройшло", plural="пройшли"})[agreement]
        if event and completed then return event .. " " .. completed .. " " .. manner end
    end
end

local function duration(tree, english)
    local required = tree.tense == "past" and "знадобилося" or "потрібно"
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
            rendered = "Щоб " .. action .. ", " .. required
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
            rendered = "Щоб " .. action .. ", " .. required
        end
    end
    local quantity = quantityText(tree.quantity, english)
    if not quantity then return nil end
    local take = english and (tree.tense == "past" and " took" or " takes")
        or (tree.tense == "past" and " займало" or " займає")
    if rendered:match("^Щоб ") then take = "" end
    return rendered .. take .. " " .. quantity
end

local function possessiveOf(subject)
    if not subject then return nil end
    local pronoun = subject.pronoun
    if pronoun and pronoun.en.possessive then return pronoun.en.possessive end
    if subject.person == 1 then return subject.number == "plural" and "our" or "my" end
    if subject.person == 2 then return "your" end
    if subject.number == "plural" or P.relativeAnimate(subject) then return "their" end
    return "its"
end

local inferredPossessives = {I="my", you="your", we="our", they="their", he="his", she="her", it="its"}

renderTree = function(tree, english, controller)
    if tree.locationAvailability then
        local availability = tree.locationAvailability
        local place = {object=tree.subject, case=availability.rule.case, rule=availability.rule}
        local prepositions = {place}
        for _, phrase in ipairs(tree.subjectLocation and tree.subjectLocation.prepositions or {}) do
            append(prepositions, phrase)
        end
        for _, phrase in ipairs(tree.prepositions or {}) do append(prepositions, phrase) end
        return render({kind="clause", subject=tree.object, question=tree.question, negative=tree.negative,
            tense=tree.tense, copula=true, predicateAdverb=availability.status, prepositions=prepositions,
            predicateModifier=tree.leadingAdverb, adverbs=tree.adverbs}, english, controller)
    end
    if tree.kind == "duration" then
        if tree.multiplier then return relativeDuration(tree, english) end
        return duration(tree, english)
    end
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
        local agreement = object.number == "plural" and "plural" or object.gender
        local forms = {masculine="потрібен", feminine="потрібна", neuter="потрібне", plural="потрібні"}
        if tree.kind == "need" then
            local predicate = english and "need" or forms[agreement] or "потрібно"
            local parts = {}
            if tree.subject then
                local subject = english and subjectText(tree, true) or G.noun(tree.subject, false, "dative")
                if not subject then return nil end
                local third = tree.subject.person == 3 and tree.subject.number == "singular"
                if tree.question then append(parts, english and (third and "does" or "do") or "чи")
                elseif english and third then predicate = "needs" end
                append(parts, subject)
                if tree.allSubject then append(parts, english and "all" or "усім") end
            end
            append(parts, predicate)
            append(parts, value)
            if not addPrepositions(parts, tree, english) then return nil end
            return table.concat(parts, " ")
        end
        if english then return "No " .. value .. " required" end
        local statement = value .. " не " .. (forms[agreement] or "потрібно")
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
    if tree.kind == "eventOccurrence" then
        local ordinal = tree.ordinal
        local value = ordinal.digits and (english and ordinal.digits .. ordinal.suffix or ordinal.digits .. "-й")
            or adjective(ordinal, english, "nominative", "singular", "masculine", "inanimate")
        local event = render(tree.event, english)
        if not value or not event then return nil end
        local period = tree.period and " " .. (english and tree.period.en or tree.period.uk)[1] or ""
        if english then
            local opening = tree.tense == "past" and "That was" or tree.tense == "future" and "This will be" or "This is"
            return opening .. " the " .. value .. " time" .. period .. " " .. event
        end
        local opening = tree.tense == "past" and "Це був" or tree.tense == "future" and "Це буде" or "Це вже"
        return opening .. " " .. value .. " раз" .. period .. ", коли " .. event
    end
    if tree.kind == "eventComparison" then
        local action = renderObserved(tree.event, english)
        if not action then return nil end
        if english then
            local actor = G.noun(tree.event.subject, true, "accusative", true)
            if not actor then return nil end
            return tree.expression.en[1] .. " " .. actor .. " " .. action
        end
        return tree.expression.uk[1] .. ", ніж коли " .. action
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
        local subject = G.noun(noun, english, "nominative", not tree.capacity)
        if not subject then return nil end
        local category = noun.term and noun.term.category
        local profession = category == "classes" or category == "roles"
        if profession then subject = ns.Engine.Normalize.word(subject) end
        local indefinite = noun.pronoun and noun.pronoun.id == "someone"
        local parts
        local frontedLocation = not english and (not tree.question or tree.why) and tree.locationAdverb and not tree.possessor
        if english then
            if indefinite and tree.question then subject = "anyone" end
            local located = tree.nearby or tree.prepositions or tree.locationAdverb
            local opening
            if tree.question then
                opening = tree.possessor and "do we have" or indefinite and located and "is"
                    or (noun.number == "plural" and "are there" or "is there")
            else opening = noun.number == "plural" and "there are" or "there is" end
            if tree.why then opening = "why " .. opening end
            parts = {opening}
            if tree.persistence then append(parts, tree.persistence.en[1]) end
            append(parts, subject)
            if tree.nearby then append(parts, "around") end
        else
            parts = {}
            if tree.why then append(parts, "Чому") end
            if frontedLocation then append(parts, tree.locationAdverb.uk[1]) end
            if tree.question and not tree.why then append(parts, "чи") end
            if tree.persistence and tree.nearby and not tree.possessor then append(parts, "тут") end
            if tree.persistence then append(parts, tree.persistence.uk[1]) end
            append(parts, "є")
            if tree.possessor then append(parts, "в нас") end
            if tree.nearby and (not tree.persistence or tree.possessor) then append(parts, "тут") end
            append(parts, subject)
        end
        if not addPrepositions(parts, tree, english) then return nil end
        if tree.locationAdverb and not frontedLocation then
            append(parts, (english and tree.locationAdverb.en or tree.locationAdverb.uk)[1])
        end
        local output = table.concat(parts, " ")
        if not tree.relative then return output end
        local relative = render(tree.relative, english)
        if not relative then return nil end
        if tree.relativeContinuation then
            local continuation = tree.relativeContinuation
            local value = render(continuation.clause, english)
            if not value then return nil end
            relative = relative .. " " .. (english and continuation.rule.en or continuation.rule.uk)[1] .. " " .. value
        end
        local person = P.relativeAnimate(noun)
        local connector = english and (person and " who " or " that ")
            or ", " .. (P.relativePronoun(noun, "nominative") or "що") .. " "
        return output .. connector .. relative
    end
    if tree.kind == "benefit" then
        local actor = G.noun(tree.subject, english, english and "nominative" or "dative")
        local resource = G.noun(tree.object, english, "nominative", true)
        if not actor or not resource then return nil end
        if tree.allSubject then actor = actor .. (english and " all" or " усім") end
        local parts
        if english then parts = {actor, "could use", resource}
        else
            local gender = targetNumber(tree.object, false) == "plural" and "plural" or tree.object.gender
            local verb = P.benefitPast[gender]
            if not verb then return nil end
            parts = {actor, "не", verb, gender == "masculine" and "би" or "б", resource}
        end
        if not addPrepositions(parts, tree, english) then return nil end
        return table.concat(parts, " ")
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
    if tree.kind == "social" then
        local rule = tree.social
        local standalone = not tree.object and not tree.action
        local head = english and (standalone and not tree.everyone and rule.standaloneEn or rule.en[1]) or rule.uk[1]
        if tree.everyone then
            head = head .. (english and " everyone" or " всім")
        elseif tree.recipient then
            local addressee = G.noun(tree.recipient, english, "vocative")
            if not addressee then return nil end
            head = head .. ", " .. addressee
        end
        if standalone then return head end
        if tree.action then
            local action = render(tree.action, english)
            if not action then return nil end
            if english then
                if tree.recipient then head = withComma(head) end
                return head .. " " .. rule.enMarker .. (tree.action.negative and " not " or " ") .. action
            end
            return withComma(head) .. " що " .. action
        end
        local object = G.noun(tree.object, english, english and "accusative" or rule.ukCase, "definite")
        if not object then return nil end
        if tree.recipient then head = withComma(head) end
        return head .. " " .. (english and rule.enMarker or rule.ukMarker) .. " " .. object
    end
    local parts = {}
    local subject = subjectText(tree, english)
    if subject == nil then return nil end
    local question = questionWord(tree, english)
    local owner = possessiveOf(tree.subject) or (tree.imperative and "your") or (tree.hortative and "our")
        or (tree.tense == "infinitive" and controller) or inferredPossessives[subject]
    local verbFrame = tree.verb and tree.verb.lexeme.frame
    local measuredPredicate = english and verbFrame and verbFrame.measuredPredicate
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
    elseif tree.copula or measuredPredicate then
        if not english then
            local appraisal = pastAppraisal(tree)
            if appraisal then return appraisal end
        end
        local person, number, gender, key = agreement(tree, english)
        local pronoun = tree.subject and tree.subject.pronoun
        local demonstrative = pronoun and pronoun.inanimate and (pronoun.id == "this" or pronoun.id == "that")
        local adjectiveFrame = tree.adjective and tree.adjective.entry.lexeme.frame
        if not english and tree.adjectiveContent and tree.tense == "present" and not tree.negative then
            local verb = L.inflectLemma(adjectiveFrame.ukContentLemma, "verb",
                {person=person, number=number, tense="present", mood="indicative"})
            local content = render(tree.adjectiveContent, english)
            if verb and content then return subject .. " " .. verb .. ", що " .. content end
            return nil
        end
        local experiencer = not english and adjectiveFrame and adjectiveFrame.ukExperiencer
        local state = not english and tree.predicateAdverb and tree.predicateAdverb.statePredicate
        local degree = experiencer and tree.adjective.intensity
        if degree then
            experiencer = (degree == "more" and "більш " or degree == "so" and "так " or degree == "too" and "надто " or "дуже ")
                .. experiencer
        end
        if english then
            local be
            local futureCopula = tree.tense == "future" and not tree.temporalDependent
            if tree.modal == "might" then be = "might"
            elseif tree.reportedFuture then be = "would"
            elseif futureCopula then be = "will"
            elseif tree.tense == "past" then be = (number == "plural" or person == 2) and "were" or "was"
            else be = presentBe(person, number) end
            append(parts, question)
            if tree.question and not (tree.wh and tree.wh.role == "subject") then append(parts, be); append(parts, subject)
            else append(parts, subject); append(parts, be) end
            if tree.allSubject and tree.negative and not tree.expletiveNegative and not tree.allUnderNegation then
                append(parts, "all")
            end
            if tree.negative and not tree.expletiveNegative then append(parts, "not") end
            if tree.modal == "might" or futureCopula then append(parts, "be") end
            if tree.allSubject and (not tree.negative or tree.expletiveNegative or tree.allUnderNegation) then
                append(parts, "all")
            end
        elseif tree.exhausted then
            local pronoun = tree.subject.pronoun
            local owner = pronoun and pronoun.ukGenitiveAfterPreposition or G.noun(tree.subject, false, "genitive")
            if not owner then return nil end
            append(parts, question)
            append(parts, "у")
            append(parts, owner)
            local exists = tree.tense == "past" and "було" or tree.tense == "future" and "буде" or "є"
            if tree.negative then append(parts, "ще " .. exists)
            else append(parts, tree.tense == "present" and "немає" or "не " .. exists) end
        elseif state then
            append(parts, question)
            local reference = tree.subject.pronoun and tree.subject.pronoun.id
            if reference ~= "everything" and reference ~= "it" then
                local topic = G.noun(tree.subject, false, "instrumental")
                if not topic then return nil end
                local first = ns.Engine.Normalize.word(topic):sub(1, 2)
                append(parts, (first == "з" or first == "с" or first == "ш" or first == "щ") and "зі" or "з")
                append(parts, topic)
            end
            append(parts, "усе")
            if tree.tense == "past" then append(parts, "було")
            elseif tree.tense == "future" then append(parts, "буде") end
            append(parts, tree.negative and tree.predicateAdverb.negativeUk or tree.predicateAdverb.uk[1])
        else
            append(parts, question)
            if experiencer then
                subject = G.noun(tree.subject, false, "dative")
                if not subject then return nil end
            end
            if tree.predicate and demonstrative then
                subject = "це"
                number, gender = tree.predicate.number, tree.predicate.gender or gender
            elseif tree.predicateAdverb and tree.predicateAdverb.deicticEvaluation then
                subject = "це"
            elseif tree.price and pronoun and pronoun.id == "it" then
                subject = "це"
            elseif tree.modal == "might" and tree.predicate and tree.subject.pronoun and tree.subject.pronoun.id == "it" then
                subject = "це"
            end
            append(parts, subject)
            if tree.allSubject and not tree.allUnderNegation then append(parts, "всі") end
            if tree.modal == "might" and tree.predicate and not tree.subject.pronoun then append(parts, "—") end
            if tree.negative or tree.expletiveNegative then append(parts, "не") end
            if tree.allUnderNegation then append(parts, "всі") end
            if tree.tense == "future" then
                append(parts, experiencer and "буде" or future[key])
            elseif tree.tense == "past" then
                local be = experiencer and "було" or pastCopula[number == "plural" and "plural" or gender]
                if not be then return nil end
                append(parts, be)
            end
        end
        if tree.predicateModifier then
            local modifier = tree.predicateModifier
            append(parts, not english and tree.tense == "past" and modifier.pastUk
                or (english and modifier.en or modifier.uk)[1])
        end
        if tree.predicateAdverb and not state then
            local adverb = tree.predicateAdverb
            append(parts, not english and tree.prepositions and adverb.followLocation
                or (english and adverb.en or adverb.uk)[1])
        end
        if tree.exhausted then
            local case = (english or tree.negative) and "nominative" or "genitive"
            local supply = G.noun(tree.exhausted, english, case, english)
            if not supply then return nil end
            if english then append(parts, "out of") end
            append(parts, supply)
        elseif tree.exists then
            append(parts, english and "real" or "існує")
        elseif tree.openForBusiness then
            if tree.reopened then append(parts, english and "back" or "знову") end
            if english then append(parts, "open for business")
            else
                local class = P.semanticClass(tree.subject)
                local lemma = class == "services" and "доступний" or class == "business" and "відкритий" or "готовий"
                local features = {case="nominative", number=number, gender=number == "singular" and gender or nil}
                local state
                if number == "singular" and not gender then
                    features.gender = "masculine"
                    local masculine = L.inflectLemma(lemma, "adj", features)
                    features.gender = "feminine"
                    local feminine = L.inflectLemma(lemma, "adj", features)
                    if masculine and feminine then state = masculine .. "/" .. feminine end
                else state = L.inflectLemma(lemma, "adj", features) end
                if not state then return nil end
                append(parts, state)
                if lemma == "готовий" then append(parts, "до роботи") end
            end
        elseif tree.price then
            local price = tree.price
            append(parts, english and (price.predicateEn or price.en[1]) or price.uk[1])
        elseif tree.level then
            append(parts, english and ("level " .. tree.level) or (tree.level .. "-го рівня"))
        elseif tree.predicate then
            local value = G.noun(tree.predicate, english, "nominative", true, nil, owner)
            if not value then return nil end
            if not english and not tree.subject.pronoun and tree.predicate.members and tree.tense == "present"
                and not tree.negative then append(parts, "—") end
            append(parts, value)
        elseif tree.evaluation then
            local evaluation = tree.evaluation
            local action = render(evaluation.action, english, owner)
            if not action then return nil end
            append(parts, (english and evaluation.rule.en or evaluation.rule.uk)[1])
            append(parts, action)
        elseif measuredPredicate then
            if tree.measure then
                local amount = quantityText(tree.measure, true)
                if not amount then return nil end
                append(parts, amount)
            end
            append(parts, measuredPredicate)
        elseif tree.adjective then
            local value = experiencer or agreedAdjective(tree.adjective, english, "nominative", tree.subject, number, gender)
            if not value then return nil end
            append(parts, value)
            if tree.comparison then
                local standard = render(tree.comparison, english)
                if not standard then return nil end
                if not english then parts[#parts] = withComma(parts[#parts]) end
                append(parts, english and "than" or "ніж")
                append(parts, standard)
            end
            if tree.infinitive then
                local action = render(tree.infinitive, english, owner)
                if not action then return nil end
                if english then append(parts, "to") end
                append(parts, action)
            end
        end
    else
        local frame = tree.verb.lexeme.frame or {}
        if english then
            append(parts, question)
            if tree.contentClause and tree.tense == "infinitive" then
                if tree.negative then append(parts, "not") end
                append(parts, "to")
            end
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
            local postposed = tree.subject and not tree.subject.pronoun
                and (tree.wh and tree.wh.kind == "clock" or frame.postposedSubject and tree.temporalDependent)
            if not postposed then
                append(parts, subject)
                if tree.allSubject then append(parts, "всі") end
            end
            local time = tree.tense == "past" and "було " or tree.tense == "future" and "буде " or ""
            local value = need and ((tree.negative and "не " or "") .. time .. "потрібно") or ukrainianVerb(tree)
            if not value then return nil end
            append(parts, value)
            if postposed then
                append(parts, subject)
                if tree.allSubject then append(parts, "всі") end
            end
        end
        if tree.property then
            local value = propertyValue(tree, english, frame.propertyCase)
            if not value then return nil end
            append(parts, value)
        end
        local postposeRecipient = tree.recipient and not tree.recipient.reflexive and frame.recipientMarker
            and (tree.recipientAfterObject or english and not tree.object and frame.implicitTransferObject)
        local recipient
        if tree.recipient and not tree.recipient.reflexive then
            local article = (frame.contentRecipientCase or frame.possessorRecipient) and "definite" or true
            if english and postposeRecipient and tree.recipient.term and tree.recipient.term.category == "roles" then
                article = "definite"
            end
            local reflexive = not english and tree.possessiveRecipient and speechPossessives[owner]
                and tree.recipient.pronoun.en.possessive == owner
            recipient = reflexive and "собі" or G.noun(tree.recipient, english,
                english and "accusative" or frame.recipientCase or "dative", article, nil, owner)
            if not recipient then return nil end
            if not postposeRecipient then append(parts, recipient) end
        end
        if tree.object then
            local requested = english and "accusative"
                or tree.negative and frame.negativeObjectCase or frame.objectCase or "accusative"
            local skill = english and frame.skillObject and P.semanticClass(tree.object) == "professions"
            local article = not skill and (english and frame.englishObjectArticle or true)
            local value = G.noun(tree.object, english, requested, article, nil, owner)
            if not value then return nil end
            if skill then value = ns.Engine.Normalize.word(value) end
            append(parts, english and frame.enObjectPreposition or not english and euphonicZ(frame.objectPreposition, value))
            local pronoun = tree.object.pronoun
            if not english and frame.deicticObject and pronoun then
                local id = pronoun.id
                if id == "it" or id == "this" or id == "that" then value = frame.deicticObject end
            end
            append(parts, value)
            if english and tree.recipient and tree.recipient.reflexive then
                local recipient = owner == "your" and tree.subject and tree.subject.number == "plural"
                    and "yourselves" or reflexiveEn[owner]
                if not recipient then return nil end
                append(parts, "for")
                append(parts, recipient)
            end
            if english and (tree.object.pronoun or frame.objectBeforeParticle) then append(parts, frame.particle) end
            if tree.objectState then
                local number = targetNumber(tree.object, english)
                local gender = tree.object.gender or (tree.object.raw and "masculine")
                local state = agreedAdjective(tree.objectState, english, "instrumental", tree.object, number, gender)
                if not state then return nil end
                append(parts, state)
            end
        elseif not (tree.wh and tree.wh.role == "object") then
            append(parts, english and postposeRecipient and frame.implicitTransferObject or english and frame.enImplicitObject
                or not english and (tree.relativeImplicitUk or frame.ukImplicitObject))
        end
        if postposeRecipient then
            if english then append(parts, frame.recipientMarker) end
            append(parts, recipient)
        end
        if tree.separation then
            local removed = G.noun(tree.separation, english, "genitive", nil, nil, owner)
            if not removed then return nil end
            append(parts, english and "of" or "від")
            append(parts, removed)
        end
        if tree.infinitive then
            local value = render(tree.infinitive, english, owner)
            if not value then return nil end
            if english and not (frame.bareInfinitive or frame.gerundComplement) then append(parts, "to") end
            append(parts, value)
        end
        if tree.controlled then
            local control = tree.controlled
            local actor = G.noun(control.actor, english, english and "accusative" or frame.controlCase, true, nil, owner)
            local action = render(control.action, english, possessiveOf(control.actor))
            if not actor or not action then return nil end
            append(parts, actor)
            if english and control.action.negative then append(parts, "not") end
            if english and frame.controlTo and not frame.bareInfinitive then append(parts, "to") end
            append(parts, action)
        end
        if not english and frame.ukManner then append(parts, frame.ukManner) end
        if tree.message then
            local content = G.noun(tree.message, english, "accusative", true, nil, owner)
            if not content then return nil end
            if english then append(parts, "with") end
            append(parts, content)
        end
        if tree.perception then
            local event = tree.perception
            if english then
                local actor = G.noun(event.subject, true, "accusative", "definite")
                if not actor then return nil end
                append(parts, actor)
            else
                parts[#parts] = withComma(parts[#parts])
                append(parts, "як")
            end
            local action = renderObserved(event, english)
            if not action then return nil end
            append(parts, action)
            for _, step in ipairs(event.perceptionSeries or {}) do
                local continuation = renderObserved(step.event, english)
                if not continuation then return nil end
                append(parts, (english and step.join.en or step.join.uk)[1])
                append(parts, continuation)
            end
        end
        if tree.content then
            for index, embedded in ipairs(tree.content) do
                local value = render(embedded, english, possessiveOf(tree.recipient) or owner)
                if not value then return nil end
                if index > 1 then append(parts, english and "and" or "і")
                elseif not english then parts[#parts] = withComma(parts[#parts]) end
                if embedded.polar then append(parts, english and "whether" or "чи")
                elseif not (embedded.where or embedded.why or embedded.when or embedded.wh
                    or english and frame.bareEnContent) then
                    append(parts, english and "that" or "що")
                end
                append(parts, value)
            end
        end
    end
    if tree.adverbComplement then
        local language = english and "en" or "uk"
        append(parts, tree.adverbComplement[language][1])
    end
    if not addPrepositions(parts, tree, english, owner) then return nil end
    local defaultAdjunct = not english and verbFrame and verbFrame.ukDefaultAdjunct
    if defaultAdjunct then
        local present
        for _, adjunct in ipairs(tree.prepositions or {}) do
            if defaultAdjunct.skipWith[adjunct.rule.id] then present = true; break end
        end
        if not present then append(parts, defaultAdjunct.text) end
    end
    if tree.priceComplement then
        local price = tree.priceComplement
        if price.manner then
            parts[#parts] = withComma(parts[#parts])
            append(parts, (english and price.manner.en or price.manner.uk)[1])
            if not english then append(parts, "—") end
        end
        if not english and price.only then append(parts, "лише") end
        append(parts, english and "for" or "за")
        if english and price.only then append(parts, "only") end
        append(parts, english and price.amount.raw or ns.Engine.Grammar.moneyText(price.amount))
    end
    if tree.priceComparison then
        if tree.priceComma then parts[#parts] = withComma(parts[#parts]) end
        append(parts, (english and tree.priceComparison.en or tree.priceComparison.uk)[1])
    end
    local measureMarker = english and verbFrame and verbFrame.measurePreposition or not english and "на"
    if tree.measure and measureMarker then
        local amount = quantityText(tree.measure, english)
        if not amount then return nil end
        append(parts, measureMarker .. " " .. amount)
        if not english and verbFrame then append(parts, verbFrame.ukMeasureSuffix) end
    end
    for _, adverb in ipairs(tree.adverbs or {}) do
        if adverb.afterComma then parts[#parts] = withComma(parts[#parts]) end
        append(parts, (english and adverb.en or adverb.uk)[1])
    end
    if english and tree.leadingAdverb and tree.leadingAdverb.postposedEn then
        append(parts, tree.leadingAdverb.en[1])
    end
    if tree.scheduleTime then
        local time = (english and tree.scheduleTime.en or tree.scheduleTime.uk)[1]
        append(parts, (english and "for " or "на ") .. time)
    end
    if tree.delay then
        if tree.delay.soon then append(parts, english and "soon" or "незабаром")
        else
            local value = quantityText(tree.delay, english)
            if not value then return nil end
            append(parts, (english and "in " or "за ") .. value)
        end
    end
    if tree.temporalAction then
        local temporal = tree.temporalAction
        local dependent = render(temporal.clause, english)
        if not dependent then return nil end
        if not english then parts[#parts] = withComma(parts[#parts]) end
        append(parts, (english and temporal.rule.en or temporal.rule.uk)[1])
        append(parts, dependent)
    end
    if tree.purpose then
        local purpose = tree.purpose
        local value, marker
        if purpose.verb or purpose.kind == "activity" then
            value = render(purpose, english, owner)
            marker = english and (purpose.negative and "not to" or "to") or "щоб"
        else
            value = G.noun(purpose.object, english, "accusative", true, nil, owner)
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

local subordinateConnectors = {because=true, ["if"]=true, ["in-case"]=true, unless=true, when=true, whenever=true, ["while"]=true}

function G.render(parse, direction, punctuation)
    local english = direction == "uk-en"
    local parts, last = {}, nil
    if english and punctuation == "?" then
        local question = parse.trees[#parse.trees]
        for i = #parse.trees, 1, -1 do
            local tree, join = parse.trees[i], parse.joins[i - 1]
            if tree.question then question = tree; break end
            if not join or join.sentence then break end
            local rule = join.rule
            if question == tree and rule and (rule.temporal or subordinateConnectors[rule.id]) then
                question = parse.trees[i - 1]
            end
        end
        if question.kind == "clause" and not question.imperative then question.question = true end
    end
    if parse.politeness then
        append(parts, english and parse.politeness.en[1] or withComma(parse.politeness.uk[1]))
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
            local trailingSubordinate = id == "if" or id == "when" or id == "while"
            local comma = join.comma and not (english and trailingSubordinate)
                or (join.rule and join.rule.temporal and not join.rule.nominalHead and not english)
                or id == "but" or id == "because" or not english and trailingSubordinate or id == "whenever"
                or id == "unless" or id == "so"
                or not english and (id == "and" or id == "or") and tree.kind == "benefit"
                or not english and (id == "and" or id == "or") and parse.trees[i - 1].perception
                    and tree.subject and not tree.inherited
            if join.dash then append(parts, "—")
            elseif comma then parts[#parts] = withComma(parts[#parts]) end
            if join.rule then
                local previous = parse.trees[i - 1]
                local status = not english and previous.predicateAdverb and previous.predicateAdverb.statePredicate
                append(parts, status and join.rule.ukStatus or (english and join.rule.en or join.rule.uk)[1])
            end
        end
        append(parts, value)
        last = tree
    end
    if parse.questionTail then append(parts, (english and parse.questionTail.en or parse.questionTail.uk)[1]) end
    return ns.Engine.Normalize.upperStart(table.concat(parts, " ")) .. (last.question and "?" or punctuation or ".")
end
