local _, ns = ...
local G = {}
ns.Engine.ClauseGeneration = G
local L, P = ns.Engine.Lexicon, ns.Engine.Phrases
local renderTree, pastOffsetText

local function render(tree, english, controller)
    if tree.kind == "nameLabel" then
        return tree.label.lexeme[english and "en" or "uk"] .. ": " .. tree.rawName
    end
    if tree.situationAcceptance then
        local past = tree.tense == "past"
        if english then return past and "it was what it was" or "it is what it is" end
        local be = past and "було" or "є"
        return be .. " як " .. be
    end
    local naming = tree.naming
    if naming then
        local person = tree.subject.pronoun
        if english then
            local copula = naming.past and " was " or " is "
            local owner = person.en.possessive .. " name"
            if tree.question then return "what" .. copula .. owner end
            return owner .. copula .. (naming.negative and "not " or "") .. naming.name
        end
        local owner = person.uk.accusative
        local verb = naming.past and " звали" or " звати"
        if tree.question then return "як " .. owner .. verb end
        return owner .. verb .. (naming.negative and " не " or " ") .. naming.name
    end
    if not english and tree.membershipRecruitment then
        local target = {}
        for key, value in pairs(tree) do target[key] = value end
        target.verb, target.purpose = tree.membershipRecruitment, nil
        tree = target
    end
    if not english and tree.activitySkill then
        local intensity = tree.adjective.intensity
        local degree = intensity == "very" and "дуже " or intensity == "so" and "так "
            or intensity == "too" and "надто " or intensity == "more" and "більш " or ""
        local function realize(source, inherited)
            local activity = {}
            for key, value in pairs(source) do activity[key] = value end
            activity.kind, activity.subject, activity.tense = "clause", tree.subject, tree.tense
            activity.inherited, activity.negative = inherited, tree.negative or source.negative
            activity.question = not inherited and tree.question
            if source.leadingAdverb then
                activity.additionalLeadingAdverbs = {source.leadingAdverb, unpack(source.additionalLeadingAdverbs or {})}
            end
            activity.leadingAdverb = {uk={degree .. tree.activitySkill}}
            return renderTree(activity, false, controller)
        end
        local value = realize(tree.infinitive, false)
        if not value then return nil end
        for _, step in ipairs(tree.infinitive.series or {}) do
            local following = realize(step.action, true)
            if not following then return nil end
            local separator = step.join and " " .. step.join.uk[1] .. " " or ", "
            value = value .. separator .. following
        end
        return value
    end
    local frame = tree.verb and tree.verb.lexeme.frame
    if english and frame and frame.passiveVoice and tree.tense == "past" and tree.verb.form.number == "plural"
        and not (tree.subject or tree.inherited or tree.wh or tree.recipient) and tree.object then
        local target = {}
        for key, value in pairs(tree) do target[key] = value end
        target.subject, target.object, target.aspect = tree.object, nil, "passive"
        tree = target
    end
    if not english and tree.aspect == "passive" and frame and (frame.passiveVoice or tree.allSubject) then
        local target = {}
        for key, value in pairs(tree) do target[key] = value end
        local patient = tree.subject
        if tree.allSubject then
            patient = {}
            for key, value in pairs(tree.subject) do patient[key] = value end
            patient.all, patient.allUnderNegation = true, tree.allUnderNegation
            target.allSubject = nil
            if tree.allUnderNegation then target.negative = false end
        end
        if frame.passiveChangeLemma and tree.measure and not (tree.passiveAgent or tree.wh or tree.modal) then
            target.aspect, target.passiveChange = nil, frame.passiveChangeLemma
            if P.semanticClass(patient) == "populationGroup" then
                local group = G.noun(patient, false, "genitive")
                if not group then return nil end
                target.subject = {raw="кількість " .. group, person=3, number="singular", gender="feminine"}
            else
                target.subject = patient
            end
        elseif frame.passiveVoice then
            target.aspect, target.inherited = nil, nil
            target.passivePastLemma = frame.passivePastLemma or frame.pastLemma
            if tree.passiveAgent then
                target.subject, target.object = tree.passiveAgent, patient
                target.implicitSubject = nil
                if frame.passiveEnclosure and not P.personNoun(tree.passiveAgent) then target.aspect = "continuous" end
            elseif tree.modal and not tree.wh then
                target.subject, target.object, target.impersonalPassive = nil, patient, true
            else
                target.subject, target.implicitSubject = {person=3, number="plural"}, true
                target.frontedPassivePatient = patient
            end
            if tree.wh and tree.wh.role == "subject" then
                local wh = {}
                for key, value in pairs(tree.wh) do wh[key] = value end
                wh.role, wh.case = "object", frame.objectCase or "accusative"
                wh.preposition = frame.objectPreposition
                target.wh, target.object, target.frontedPassivePatient = wh, nil, nil
            end
        else
            target.subject = patient
        end
        tree = target
    end
    local event = not english and frame and frame.eventSubjectTransfer
    if event and event.classes[P.semanticClass(tree.subject)] then
        local time = G.noun(tree.subject, false, event.case)
        if not time then return nil end
        local target = {}
        for key, value in pairs(tree) do target[key] = value end
        local head = L.head(event.ukSubject, "noun")
        target.subject = {raw=event.ukSubject, gender=head.gender, number=head.number or "singular", person=3}
        target.inherited = nil
        local value = renderTree(target, false, controller)
        return value and event.ukMarker .. " " .. time .. " " .. value:gsub(",+$", "")
    end
    local value = renderTree(tree, english, controller)
    local offset = tree.pastOffset
    if value and offset then
        local time = pastOffsetText(offset, english)
        if not time then return nil end
        if offset.fronted then value = time .. (offset.comma and ", " or " ") .. value
        else value = value .. " " .. time end
    end
    if value then return (value:gsub(",+$", "")) end
end

local function withComma(value)
    return value:sub(-1) == "," and value or value .. ","
end

local function append(parts, value)
    if value and value ~= "" then parts[#parts + 1] = value end
end

local function modifierOrder(modifier)
    local frame = modifier.entry and modifier.entry.lexeme.frame
    return frame and not (modifier.join or modifier.comma) and frame.ukModifierOrder
end

local function ukrainianModifiers(modifiers)
    local ordered = modifiers
    for index = 2, #modifiers do
        local order = modifierOrder(modifiers[index])
        local left = index - 1
        while order and left > 0 do
            local previousOrder = modifierOrder(ordered[left])
            if not previousOrder or previousOrder <= order then break end
            if ordered == modifiers then
                ordered = {}
                for position, modifier in ipairs(modifiers) do ordered[position] = modifier end
            end
            ordered[left + 1] = ordered[left]
            left = left - 1
        end
        if left < index - 1 then ordered[left + 1] = modifiers[index] end
    end
    return ordered
end

local function euphonicZ(marker, value)
    if marker ~= "з" then return marker end
    local key = ns.Engine.Normalize.word(value)
    local initial = key:sub(1, 2)
    if key == "мною" then return "зі" end
    if initial == "з" or initial == "с" or initial == "ш" or initial == "щ" then return "зі" end
    return marker
end

local objectPrepositionWords = {["від"]=true, ["до"]=true, ["для"]=true, ["з"]=true, ["із"]=true, ["зі"]=true,
    ["за"]=true, ["на"]=true, ["про"]=true, ["у"]=true, ["в"]=true}
local function ukrainianPrepositionalPronoun(node, case, objectMarker)
    if objectMarker and not objectPrepositionWords[objectMarker:match("%S+$")] then return nil end
    if node.pronoun and (case == "genitive" or case == "accusative") then
        return node.pronoun.ukGenitiveAfterPreposition
    end
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
    if modifier.rawModifier then
        local degree = modifier.intensity
        if degree == "more" then return (english and "more " or "більш ") .. modifier.rawModifier end
        if degree == "very" then return (english and "very " or "дуже ") .. modifier.rawModifier end
        return modifier.rawModifier
    end
    local entry, intensity = modifier.entry, modifier.intensity
    local qualifier = modifier.qualifier
    local modifierText = qualifier and (english and qualifier.en or qualifier.uk)[1] .. " " or ""
    local degree = entry.form.degree
    if english then
        local base = entry.lexeme.en
        local capitalized = entry.lexeme.frame and entry.lexeme.frame.capitalizeEnglish
        local apertium = ns.Engine.Apertium
        if degree and not intensity and apertium then
            local inflected = apertium.generate(base, "en", "adj", {degree=degree})
            if inflected then return modifierText .. (capitalized and ns.Engine.Normalize.upperStart(inflected) or inflected) end
        end
        if capitalized then base = ns.Engine.Normalize.upperStart(base) end
        if degree == "comparative" then base = "more " .. base
        elseif degree == "superlative" then base = "most " .. base end
        local prefix = intensity == "more" and "more " or intensity == "very" and "very " or intensity == "so" and "so "
            or intensity == "too" and "too " or intensity == "most" and "most " or intensity == "quite" and "quite " or ""
        return modifierText .. prefix .. base
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
    return modifierText .. (intensity == "more" and "більш " or intensity == "very" and "дуже " or intensity == "so" and so
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
    if not english and node.ukNumber then return node.ukNumber end
    if node.entry then
        local frame = node.entry.lexeme.frame
        if english and frame and frame.englishNumber then return frame.englishNumber end
        if not english and frame and frame.ukNumber and not node.quantity then return frame.ukNumber end
        if not english and node.entry.head.number == "plural" then return "plural" end
    end
    return node.number
end

local speechPossessives = {my=true, our=true, your=true}
local reflexiveEn = {my="myself", your="yourself", our="ourselves", his="himself", her="herself",
    its="itself", their="themselves"}
local function possessiveText(entry, english, case, number, gender, animacy, owner, emphaticOwner)
    if english and entry.lexeme.frame.reflexivePossessive and owner then return owner end
    if not english and owner and (speechPossessives[owner] or emphaticOwner) and owner == entry.lexeme.en then
        local features = {case=adjectiveCase(case, number, gender, animacy), number=number,
            gender=number ~= "plural" and gender or nil}
        local reflexive = L.inflectLemma("свій", "det", features) or L.inflectLemma("свій", "pron", features)
        if reflexive then return reflexive end
    end
    return adjective({entry=entry}, english, case, number, gender, animacy)
end

local function addInfinitiveSeries(parts, head, english, owner)
    for _, item in ipairs(head.series or {}) do
        local continuation = render(item.action, english, owner)
        if not continuation then return false end
        if item.join then append(parts, (english and item.join.en or item.join.uk)[1])
        else parts[#parts] = withComma(parts[#parts]) end
        if english and item.action.negative then append(parts, "not") end
        if english and item.explicitTo and not head.gerund then append(parts, "to") end
        append(parts, continuation)
    end
    return true
end

local function nounWithAction(node, value, english, owner)
    if not value or not node.nominalAction then return value end
    local tree = node.nominalAction
    local action = render(tree, english, owner)
    if not action then return nil end
    if tree.series then
        local parts = {action}
        if not addInfinitiveSeries(parts, tree, english, owner) then return nil end
        action = table.concat(parts, " ")
    end
    local partner = tree.nominalPartner
    if partner and english then return value .. " to " .. action .. " " .. partner.en[1] end
    if partner then
        local relative = P.relativePronoun(node, partner.case)
        return relative and value .. ", " .. euphonicZ(partner.targetUk, relative) .. " " .. relative .. " можна " .. action
    end
    local marker = english and " to " or tree.nominalLocation and ", де можна "
        or tree.nominalPurpose and ", щоб " or " "
    return value .. marker .. action
end

local function bareNominalArgument(node)
    return not (node.adjectives or node.article or node.demonstrative or node.possessor or node.members
        or node.quantity or node.genitive or node.prepositions or node.relative or node.argument)
end

local function activityArgumentNeedsMarker(argument)
    for _, topic in ipairs(argument.members or {argument}) do
        if not bareNominalArgument(topic)
            or topic.number == "plural" and P.hasTrait(topic, "activityTopicGenericPlural") then
            return true
        end
    end
    return false
end

local function withNumber(node, number)
    if not number or number == node.number then return node end
    local adjusted = {}
    for key, value in pairs(node) do adjusted[key] = value end
    adjusted.number = number
    return adjusted
end

local function ukrainianArgumentNumber(head, number)
    local dependent = head.argument.object
    if dependent.term and dependent.term.category == "places" then return dependent.number end
    return number and (number.uk == "head" and head.number or number.uk)
end

local function amountText(amount, english)
    local value = amount.lower
    if amount.upper then value = value .. (english and " to " or "–") .. amount.upper end
    if amount.approximate then value = (english and "about " or "приблизно ") .. value end
    return value
end

local function noun(node, english, case, article, compoundModifier, owner, commonHead)
    if node.calendarYear then return node.calendarYear .. (english and "" or " року") end
    if node.substantive then
        local value = adjective(node.substantive, english, case, "plural", nil, "animate")
        return value and (english and "the " .. value or value)
    end
    if node.amount and not node.quantity then return amountText(node.amount, english) end
    if node.headlessCardinal then
        local number = node.headlessCardinal
        if not english and number <= 2 then return number == 1 and "один" or "два" end
        local grammar = ns.Linguistics.grammar
        for word, cardinal in pairs(english and grammar.cardinalEn or grammar.cardinalUk) do
            if cardinal == number then return word end
        end
        return tostring(number)
    end
    if node.channelName then
        local normalize = ns.Engine.Normalize
        local language = english and "en" or "uk"
        local name = normalize.upperStart(node.channelName.lexeme[language])
        local qualifier = normalize.upperStart(node.channelLanguage.lexeme[language])
        if english then return name .. " - " .. qualifier end
        local channel = L.inflect(node.entry, {case=case, number="singular"})
        if channel then return channel .. " «" .. name .. " — " .. qualifier .. "»" end
        return nil
    end
    if node.subset then
        local group = node.subset
        local value = G.noun(group, english, english and "accusative" or "genitive", nil, nil, owner)
        if not value then return nil end
        if english and not (group.pronoun or group.article or group.possessor or group.demonstrative) then
            value = "the " .. value
        end
        local count = node.subsetCount
        local amount = count == 1 and (english and "one" or P.one(node.gender, case, node.animacy)) or tostring(count)
        local marker = english and "of" or count == 1 and ("ауеоєю"):find(amount:sub(-2), 1, true)
            and euphonicZ("з", value) or "із"
        return nounWithAction(node, amount .. " " .. marker .. " " .. value, english, owner)
    end
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
        return nounWithAction(node, table.concat(values, " "), english, owner)
    end
    if node.raw then
        local quantity = node.amount and amountText(node.amount, english) or node.quantity
        local value = quantity and quantity .. " " .. node.raw or node.raw
        return nounWithAction(node, value, english, owner)
    end
    if node.ownPeople then
        local entry = node.possessor
        local controller = owner or not english and entry.lexeme.en
        local value = possessiveText(entry, english, case, node.number, nil, node.animacy, controller, true)
        if english and value and not value:match(" own$") then value = value .. " own" end
        return value
    end
    if node.pronoun then
        local pronoun = node.targetPronoun or node.pronoun
        local forms = english and pronoun.en or pronoun.uk
        local value = forms[case] or (english and forms.accusative)
        if value and node.all and not english then
            if node.allUnderNegation and case == "accusative" then
                local group = pronoun.ukGenitiveAfterPreposition or forms.genitive
                if not group then return nil end
                return "всіх із " .. group
            end
            local quantifierCase = case == "accusative" and "genitive" or case
            value = value .. " " .. (P.allForms[quantifierCase] or "усі")
        end
        if value and node.postpositive then
            local modifier = adjective(node.postpositive, english, case, node.number, node.gender, node.animacy)
            if not modifier then return nil end
            value = value .. " " .. modifier
        end
        return nounWithAction(node, value, english, owner)
    end
    local number, requested = compoundModifier and "singular" or targetNumber(node, english), case
    -- An indefinite mass noun can retain its governed oblique case without an article.
    local explicitSome = node.some and (english or case == "nominative" or case == "accusative" or case == "genitive")
    if not english and case == "accusative" and node.partitive then requested = "genitive" end
    if node.few and not english and (case == "nominative" or case == "accusative") then requested = "genitive" end
    if not english and (node.sufficient or explicitSome or node.many or node.more or node.abundance) then requested = "genitive" end
    if node.quantity then
        if english then
            local frame = node.entry and node.entry.lexeme.frame
            number = (tonumber(node.quantity) == 1 or frame and frame.countInvariant) and "singular" or "plural"
        else
            requested, number = P.countedCase(node.quantity, case, node.animacy == "animate")
        end
    end
    local value
    if node.term then
        if english then
            local term = L.curatedNumber(node.term, number)
            value = term.en
            if number == "plural" and not (term.morphology and term.morphology.number == "plural")
                and not (term.features and term.features.number == "plural") then
                value = term.englishPlural or englishForm(value, "plural", "noun")
            end
        else
            value = L.curatedForm(node.term, requested, number)
        end
    elseif node.entry then
        if english then
            value = node.entry.lexeme.en
            local frame = node.entry.lexeme.frame
            if number == "plural" then value = frame and frame.englishPlural or englishForm(value, "plural", "noun") end
            if frame and frame.capitalizeEnglish then value = ns.Engine.Normalize.upperStart(value) end
        else
            local frame = node.entry.lexeme.frame
            value = frame and node.quantity and requested == "nominative" and number == "plural" and frame.countedFewUk
                or L.inflect(node.entry, {case=requested, number=number})
        end
    end
    if not value then return nil end
    local frame = node.entry and node.entry.lexeme.frame
    local mass = P.mass(node)
    if node.term and (commonHead or mass or node.term.category == "classes"
        or node.term.features and node.term.features.proseCommonNoun
        or english and node.term.features and node.term.features.englishCommon
        or english and node.term.category == "roles" and not (node.term.features and node.term.features.proper)
            and value:find("%l")) then
        value = ns.Engine.Normalize.word(value)
    end
    if node.destination and node.term and node.term.category == "game" then
        value = ns.Engine.Normalize.word(value)
    end
    local placeCompound = english and frame and frame.placeCompound and node.genitive
        and node.genitive.term and node.genitive.term.category == "places"
    local parts = {}
    local possessiveEmphasis
    local modifiers = node.adjectives
    if not english and modifiers and #modifiers > 1 then modifiers = ukrainianModifiers(modifiers) end
    for _, modifier in ipairs(modifiers or {}) do
        if not modifier.impliedByPossession then
            local modifierFrame = modifier.entry and modifier.entry.lexeme.frame
            possessiveEmphasis = possessiveEmphasis or modifierFrame and modifierFrame.possessiveEmphasis
            if english and article == true and not node.article and modifier.entry
                and (modifier.entry.form.degree == "superlative" or modifierFrame and modifierFrame.definiteHead) then
                article = "definite"
            end
            if english or not (modifierFrame and modifierFrame.ukPossessedState) then
                local word = adjective(modifier, english, requested, number, node.gender, node.animacy)
                if not word then return nil end
                local join = modifier.join
                local contrast = join and join.id == "but"
                if #parts > 0 and (contrast and not english or not contrast and modifier.comma) then
                    parts[#parts] = withComma(parts[#parts])
                end
                if join and #parts > 0 then append(parts, (english and join.en or join.uk)[1]) end
                append(parts, word)
            end
        end
    end
    if placeCompound then
        local place = G.noun(node.genitive, true, "genitive")
        if not place then return nil end
        append(parts, (place:gsub("^The ", "")))
        if frame.placeCompoundTitle then
            value = value:gsub("%a+", function(word) return ns.Engine.Normalize.upperStart(word) end)
        end
    end
    local argumentCompound = english and node.argument and node.argument.form.englishCompound
    local argumentNumber = argumentCompound and node.argument.form.compoundNumber
    local hyphenate = argumentCompound and node.argument.form.englishCompoundHyphenate
    if argumentNumber or hyphenate then
        local argument = node.argument.object
        argumentCompound = bareNominalArgument(argument)
            and (not argumentNumber or argument.number == ukrainianArgumentNumber(node, argumentNumber))
    end
    if argumentCompound and node.argument.form.activityTopics and activityArgumentNeedsMarker(node.argument.object) then
        argumentCompound = false
    end
    if argumentCompound then
        local dependent = withNumber(node.argument.object, argumentNumber and argumentNumber.en)
        local argument = G.noun(dependent, true, "nominative", false, true, owner)
        if not argument then return nil end
        if dependent.term and dependent.term.category == "places" then argument = argument:gsub("^The ", "") end
        if hyphenate then argument = argument:gsub(" ", "-") end
        append(parts, argument)
        if article == true and not node.article then article = node.argument.form.englishCompoundArticle or "definite" end
    end
    if node.membershipAudience then
        local audience = withNumber(node.membershipAudience, english and "singular" or "plural")
        local composition = node.membershipComposition
        local audienceCase = english and "nominative" or composition and "instrumental" or "genitive"
        local restriction = G.noun(audience, english, audienceCase, false)
        if not restriction then return nil end
        if english then value = (composition and "all-" .. restriction or restriction .. "-only") .. " " .. value
        else value = value .. (composition and " лише з " or " лише для ") .. restriction end
    end
    if node.activityMode then
        value = node.activityMode .. (english and " " or "-") .. value
    end
    local measure = node.nominalMeasure
    if english and measure then append(parts, measure.quantity .. "-" .. measure.entry.lexeme.en) end
    append(parts, value)
    value = table.concat(parts, " ")
    if node.characterLevel then
        value = english and ("level " .. node.characterLevel .. " " .. value) or (value .. " " .. node.characterLevel .. "-го рівня")
    end
    if node.levelThreshold then
        value = english and (node.levelThreshold .. "+ " .. value) or (value .. " від " .. node.levelThreshold .. "-го рівня")
    end
    if node.nominalObject then
        local object = G.noun(node.nominalObject, english, node.nominalCase, false, english, owner)
        if not object then return nil end
        value = english and (object .. " " .. value) or (value .. " " .. object)
    end
    local inferredOwner = english and possessiveEmphasis and not node.possessor and owner
    if inferredOwner then
        value = inferredOwner .. " " .. value
    elseif node.possessor and (english or not possessiveEmphasis or speechPossessives[owner]
        or owner ~= node.possessor.lexeme.en) then
        local sameGroup = frame and frame.semanticClass == "membershipRanks"
        local possessive = possessiveText(node.possessor, english, requested, number, node.gender, node.animacy,
            owner, node.emphaticOwner or sameGroup)
        if not possessive then return nil end
        value = possessive .. (english and node.englishOwn and " own " or " ") .. value
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
    if node.playableClass then
        local class = G.noun(withNumber(node.playableClass, number), english, requested, false)
        if not class then return nil end
        value = value .. (english and " " or "-") .. class
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
        if not english and node.argument.compound and form.compoundNumber and bareNominalArgument(argument) then
            argument = withNumber(argument, ukrainianArgumentNumber(node, form.compoundNumber))
        end
        if english and form.partitive and not (argument.article or argument.possessor or argument.demonstrative
            or argument.pronoun or argument.raw or P.hasTrait(argument, "proper")
            or argument.term and argument.term.category == "places") then
            local definite = {}
            for key, field in pairs(argument) do definite[key] = field end
            definite.article = "definite"
            argument = definite
        end
        local article = form.englishArticle
        if article == nil then article = true end
        local object = not english and form.uk ~= "" and ukrainianPrepositionalPronoun(argument, form.case)
            or G.noun(argument, english, english and "accusative" or form.case, article, nil, owner)
        if not object then return nil end
        local marker = english and form.en or euphonicZ(form.uk, object)
        value = value .. (marker == "" and " " or " " .. marker .. " ") .. object
    end
    if measure and not english then
        local unitCase, unitNumber = P.countedCase(measure.quantity, "accusative", false)
        local unit = L.inflect(measure.entry, {case=unitCase, number=unitNumber})
        if not unit then return nil end
        value = value .. " на " .. measure.quantity .. " " .. unit
    end
    if node.inclusion then
        local inclusion = node.inclusion
        local case = not english and inclusion.audience and "genitive" or "nominative"
        local detail = G.noun(inclusion.object, english, case)
        if not detail then return nil end
        local marker = english and (inclusion.audience and "including for " or "including ")
            or (inclusion.audience and "зокрема для " or "зокрема ")
        value = value .. ", " .. marker .. detail
    end
    value = nounWithAction(node, value, english, owner)
    if not value then return nil end
    if node.channelNumber then value = value .. " " .. node.channelNumber end
    if node.ordinal then
        if english then value = value .. " " .. node.ordinal
        else value = node.ordinal .. "-" .. (P.ordinalSuffixes[requested] or "й") .. " " .. value end
        if not node.same then return value end
    end
    if node.skillRequirement then
        value = english and (value .. " requiring skill " .. node.skillRequirement)
            or (value .. " (навичка " .. node.skillRequirement .. ")")
    end
    if node.quantity then
        if node.additional then
            local one = tonumber(node.quantity) == 1
            if english then value = (one and "one" or node.quantity) .. " more " .. value
            else value = "ще " .. (one and P.one(node.gender, case, node.animacy) or node.quantity) .. " " .. value end
        else value = (node.amount and amountText(node.amount, english) or node.quantity) .. " " .. value end
        if not node.same then return value end
        number = tonumber(node.quantity) == 1 and "singular" or "plural"
    end
    if node.sufficient then return (english and "enough " or "достатньо ") .. value end
    if node.many then return (english and "lots of " or "багато ") .. value end
    if node.abundance then return (english and "plenty of " or "вдосталь ") .. value end
    if node.more then
        if node.degreeMore then
            local quantifier = english and (number == "plural" and "many more " or "much more ") or "значно більше "
            return quantifier .. value
        end
        local emphasis = node.evenMore and (english and "even " or "ще ") or ""
        return emphasis .. (english and "more " or "більше ") .. value
    end
    if explicitSome then return (english and "some " or "трохи ") .. value end
    if node.indefiniteChoice then
        local determiner = P.relativePronoun(node, case)
        return english and ("some " .. value) or determiner and (determiner .. "сь " .. value)
    end
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
        local amount
        local allCase = adjectiveCase(requested, number, node.gender, node.animacy)
        if english then
            local proper = node.term and node.term.features and node.term.features.proper
            local whole = node.allOf or number == "singular" and proper
            amount = (whole and "all of" or "all") .. (node.article == "definite" and " the" or "")
        elseif number == "singular" and P.wholeForms[allCase] then
            amount = P.wholeForms[allCase][node.gender]
        end
        local quantifier = amount or P.allForms[allCase] or "усі"
        if node.allUnderNegation and not english then quantifier = "в" .. quantifier:sub(#"у" + 1) end
        return quantifier .. " " .. value
    end
    if node.distributive then
        if english then return node.distributive .. " " .. value end
        local agreementCase = adjectiveCase(requested, number, node.gender, node.animacy)
        local marker = L.inflectLemma("кожний", "det", {case=agreementCase, number=number, gender=node.gender})
        return marker and marker .. " " .. value
    end
    if node.demonstrative then
        local determiner = demonstrative(node, english, requested, number)
        return determiner and determiner .. " " .. value
    end
    if node.freeChoice then
        local form = english and "any" or P.relativePronoun(node, case)
        return form and (english and form or "будь-" .. form) .. " " .. value
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
    if english and not inferredOwner and not node.possessor and not (node.nominalObject and node.nominalObject.possessor) then
        if node.article == "definite" then return "the " .. value end
        if not node.article and frame and frame.englishArticle ~= nil
            and (article or frame.englishArticle == "bare-unmodified" and node.adjectives) then
            article = frame.englishArticle
        end
        if article == "bare-unmodified" then article = node.adjectives and #node.adjectives > 0 and "definite" or false end
        local proper = node.channelNumber or node.term and (node.term.category == "places"
            or node.term.features and node.term.features.proper)
        local uncountable = mass and not (frame and frame.englishCountable)
            or node.term and node.term.features and node.term.features.englishUncountable
        local definiteName = node.term and node.term.features and node.term.features.englishDefinite
        if definiteName and (article == "definite"
            or article == true and not node.article and node.term.category == "goods") then return "the " .. value end
        if article == "definite" and not proper and not uncountable and number == "singular" then return "the " .. value end
        if (article or node.article == "indefinite") and not proper and not uncountable and number == "singular" then
            local leadingMeasure = measure and value:match("^(%d+)%-")
            local vowelNumber = leadingMeasure and (leadingMeasure:sub(1, 1) == "8"
                or leadingMeasure == "11" or leadingMeasure == "18")
            local indefinite = frame and not node.adjectives and not argumentCompound and frame.englishIndefiniteArticle
                or (vowelNumber or value:match("^[AEIOUaeiou]") or value:match("^RP[/ ]")) and "an" or "a"
            return indefinite .. " " .. value
        end
    end
    return value
end

function G.noun(node, english, case, article, compoundModifier, owner, commonHead)
    if node.controlLabel then
        local label = node.controlLabel
        return english and label.en[1] or "«" .. label.uk[1] .. "»"
    end
    if node.bracketedTitle or node.titleDescription then
        local value = node.raw or "[" .. (english and node.term.en or node.term.uk) .. "]"
        if not node.titleDescription then return value end
        local detail = G.noun(node.titleDescription, english, case, english, nil, owner)
        return detail and value .. (english and ", " or " — ") .. detail
    end
    local relative = node.relative
    if english and relative and not article and not (relative.nonrestrictive or relative.locative) then article = "definite" end
    if english and node.groupLabel and not node.article then article = "definite" end
    local partialGroup = not english and node.members and node.allUnderNegation
    local value = noun(node, english, partialGroup and "genitive" or case, article, compoundModifier, owner, commonHead)
    if value and not english and node.members and node.all then
        if partialGroup then value = "всіх із " .. value
        else
            local animate = false
            for _, member in ipairs(node.members) do
                if member.animacy == "animate" or P.personNoun(member) then animate = true; break end
            end
            local quantifierCase = adjectiveCase(case, "plural", nil, animate and "animate" or nil)
            value = (P.allForms[quantifierCase] or "усі") .. " " .. value
        end
    end
    if value and node.allUnderNegation and not english then value = "не " .. value end
    if value and node.groupLabel then value = value .. " " .. node.groupLabel end
    if value and node.nominalQualifier then
        local qualifier = node.nominalQualifier
        local selection = qualifier.selection
        local desc = adjective(qualifier, english, selection and "nominative" or case,
            selection and "singular" or node.number, selection and "masculine" or node.gender, node.animacy)
        local action = render(qualifier.action, english, owner)
        if not (desc and action) then return nil end
        if english then
            local marker = qualifier.entry.lexeme.frame.governedAction
            return value .. " " .. desc .. " " .. marker .. (qualifier.action.negative and " not " or " ") .. action
        end
        return withComma(value) .. (selection and " хто " or " ") .. withComma(desc .. " " .. action)
    end
    if value and node.referenceLabel then value = value .. " " .. node.referenceLabel end
    if value and node.groundedState then
        local state = node.groundedState
        local adjectiveValue = adjective(state, english, case, targetNumber(node, english), node.gender, node.animacy)
        local basis, marker = G.preposition(state.complement, english, owner)
        if not adjectiveValue or not basis then return nil end
        local description = adjectiveValue .. " " .. (marker ~= "" and marker .. " " or "") .. basis
        value = english and value .. " " .. description or withComma(value) .. " " .. withComma(description)
    end
    if value and node.prepositions then
        for _, phrase in ipairs(node.prepositions) do
            local object, marker = G.preposition(phrase, english, owner)
            if not object or not marker then return nil end
            value = value .. " " .. marker .. " " .. object
        end
    end
    if value and node.listExtension then
        value = value .. " " .. (english and node.listExtension.en or node.listExtension.uk)[1]
    end
    if value and node.comparativeOffset then
        local offset = G.comparativeOffset(node.comparativeOffset, english)
        if not offset then return nil end
        value = value .. " " .. offset
    end
    if value and not english and node.adjectives then
        for _, modifier in ipairs(node.adjectives) do
            local frame = modifier.entry and modifier.entry.lexeme.frame
            local state = frame and frame.ukPossessedState
            if state then
                local possessor = P.relativePronoun(node, "genitive")
                local property = L.inflectLemma(state.lemma, "noun", {case="nominative", number=state.number})
                if not (possessor and property) then return nil end
                value = withComma(value) .. " у " .. possessor .. " " .. withComma(property)
            end
        end
    end
    if not value or not relative then return value end
    local clause = render(relative.clause, english)
    if not clause then return nil end
    if relative.actions then
        local parts = {clause}
        for index = 2, #relative.actions do
            local action = render(relative.actions[index], english)
            if not action then return nil end
            local connector = relative.joins[index - 1]
            if connector then append(parts, (english and connector.en or connector.uk)[1])
            else parts[#parts] = withComma(parts[#parts]) end
            append(parts, action)
        end
        clause = table.concat(parts, " ")
    end
    if english then
        local marker = relative.locative and P.locativeRelativeMarker["en-uk"]
            or P.relativeAnimate(node) and "who" or (relative.nonrestrictive and "which" or "that")
        if relative.preposition then
            local rule = relative.preposition
            marker = (rule.targetEn or rule.en[1]) .. (P.relativeAnimate(node) and " whom" or " which")
        end
        if not relative.nonrestrictive then return value .. " " .. marker .. " " .. clause end
        return withComma(value) .. " " .. marker .. " " .. withComma(clause)
    end
    local marker = relative.locative and P.locativeRelativeMarker["uk-en"] or P.relativePronoun(node, relative.case)
    if not marker then return nil end
    if relative.preposition then marker = relative.preposition.targetUk .. " " .. marker
    elseif relative.clause.relativeMarkerUk then marker = relative.clause.relativeMarkerUk .. " " .. marker end
    return withComma(value) .. " " .. marker .. " " .. withComma(clause)
end

function G.comparativeOffset(offset, english)
    local measure = G.noun(offset.measure, english, "accusative")
    if not measure then return nil end
    local text = (english and "" or "на ") .. measure .. " " .. (english and offset.direction.en or offset.direction.uk)
    if offset.standard then
        local standard = not english and ukrainianPrepositionalPronoun(offset.standard, "accusative", "за")
            or G.noun(offset.standard, english, "accusative", true)
        if not standard then return nil end
        text = text .. (english and " than " or " за ") .. standard
    end
    return text
end

function G.address(address, english)
    local case = english and "nominative" or "vocative"
    if english and address.addressName then return address.addressTitle .. " " .. address.addressName end
    local value = G.noun(address, english, case)
    if not value and not english then value = G.noun(address, english, "nominative") end
    if value and address.addressName then return value .. " " .. address.addressName end
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
    local value
    if english then value = adjective(property, true)
    elseif case == "adverb" then
        local forms = ns.Linguistics.propertyAdverbs
        value = forms and forms.forms[property.entry.lexeme.uk]
    else
        local _, number, gender = agreement(tree)
        value = agreedAdjective({entry=property.entry}, false, case, tree.subject, number, gender)
    end
    if not value then return nil end
    if not english then value = (propertyDegreeUk[property.intensity] or "") .. value end
    local marker = property.degreeMarker
    if marker then value = (english and marker.en or marker.uk)[1] .. (property.pause or "") .. " " .. value end
    return value
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
    if tree.impersonalPassive then
        local cue = tree.negative and "неможливо" or "можна"
        local time = tree.modal == "could" and " було " or " "
        local lemma = frame.passiveModalLemma or frame.purposeLemma or frame.infinitiveLemma or entry.lexeme.uk
        local adverb = tree.leadingAdverb and tree.leadingAdverb.uk[1]
        return cue .. time .. (adverb and adverb .. " " or "") .. lemma
    end
    local lemma = entry.lexeme.uk
    local modality = tree.modalSense == "request" and "can" or tree.modal
    local leading = tree.leadingAdverb
    if modality == "can" and not tree.negative and leading and leading.limitsAbility
        and (frame.stative or frame.perception) then modality = nil end
    local verbalModal = modality and modality ~= "might"
    local adverb = leading and ((tree.tense == "past" and not tree.negative and leading.pastUk) or leading.uk[1]) .. " " or ""
    for _, modifier in ipairs(tree.additionalLeadingAdverbs or {}) do
        adverb = adverb .. modifier.uk[1] .. " "
    end
    if tree.emphaticDo and not (leading and leading.emphaticDo) then adverb = adverb .. "таки " end
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
    if tree.passiveChange then
        local tense = tree.tense or "present"
        local lemma = tense == "present" and frame.passiveChangePresent or tree.passiveChange
        local form = L.inflectLemma(lemma, "verb", {tense=tense, mood="indicative",
            person=tense ~= "past" and person or nil, number=number, gender=tense == "past" and gender or nil})
        return form and (tree.negative and "не " or "") .. adverb .. form
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
    local durative = tree.durationSpan and frame.openEndedActivity
    if tree.imperative then
        local features = {mood="imperative", person=2, number=tree.imperativeNumber or "singular"}
        if frame.imperative and not (tree.negative or durative) then form = L.inflectLemma(frame.imperative, "verb", features)
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
        form = tree.taskInfinitiveLemma
            or tree.modalPerfect and not tree.negative and (frame.pastLemma or frame.completed or frame.futureEventLemma)
            or tree.purposeClause and (tree.ongoingPurpose and lemma or frame.purposeLemma)
            or tree.difficultyClause and (frame.indirectInfinitiveLemma or frame.purposeLemma)
            or tree.intendedEvent and not tree.negative
                and (frame.purposeLemma or frame.infinitiveLemma or frame.imperative or frame.modalLemma or frame.futureEventLemma)
            or tree.contentClause and tree.tense == "infinitive" and not tree.negative and frame.indirectInfinitiveLemma
            or modality == "should" and not tree.negative and frame.adviceLemma
            or tree.tense == "infinitive" and tree.controlled and frame.controlledInfinitiveLemma
            or craft and frame.itemModalLemma
            or (modality == "can" or modality == "may" or modality == "could")
                and (tree.infinitive or tree.controlled) and frame.modalWithInfinitiveLemma
            or ((modality == "can" or modality == "may") and object and object.number == "singular") and frame.modalLemma
            or (modality == "can" or modality == "could") and frame.possibleOutcome or frame.infinitiveLemma or lemma
    elseif (tree.temporalDependent and not tree.temporalRecurring and tree.tense == "present" and frame.ukSequencedLemma)
        or ((tree.deadlineFuture and tree.tense == "present" or tree.deadlineMain and tree.tense == "future")
            and frame.pastLemma) then
        form = L.inflectLemma(frame.ukSequencedLemma or frame.pastLemma, "verb",
            {tense="future", mood="indicative", person=person, number=number})
    elseif tree.tense == "past" and tree.ellipticSubject and frame.ellipticPastUk then
        form = frame.ellipticPastUk
    elseif tree.tense == "past" or tree.conditional then
        local ongoingNegation = tree.negative and tree.since and tree.aspect == "perfect"
        local progressive = tree.aspect == "continuous"
        local completed = not (progressive or ongoingNegation or durative)
            and (tree.passivePastLemma or frame.pastLemma or (tree.aspect == "perfect" and frame.completed))
        if frame.pastByMeans and not progressive then
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
            if masculine and feminine then
                form = masculine .. (tree.conditional and " би/" or "/") .. feminine .. (tree.conditional and " б" or "")
            end
        elseif completed then form = L.inflectLemma(completed, "verb", features)
        else form = L.inflect(entry, features) end
        if form and tree.conditional and (number ~= "singular" or gender) then
            form = form .. (number == "singular" and gender == "masculine" and " би" or " б")
        end
    elseif tree.tense == "future" and not durative
        and (tree.passivePastLemma or frame.futureLemma or frame.futureEventLemma and singleEvent) then
        form = L.inflectLemma(tree.passivePastLemma or frame.futureLemma or frame.futureEventLemma, "verb",
            {tense="future", mood="indicative", person=person, number=number})
    elseif tree.tense == "future" and entry.head.aspect ~= "perfective" then
        form = tree.sharedFutureAuxiliary and lemma or future[key] .. " " .. lemma
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
        elseif tree.modalPerfect and modality == "should" then modal = "слід було"
        elseif tree.modalSense == "request" then
            local forms = ukrainianModals.could
            if number == "plural" then modal = forms.plural .. " б"
            elseif not gender and person == 2 then modal = forms.masculine .. " би/" .. forms.feminine .. " б"
            elseif gender and gender ~= "masculine" then modal = forms[gender] .. " б"
            else modal = forms.masculine .. " би" end
        elseif modality == "can" or modality == "may" or tree.modalSense == "possibility" then modal = ukrainianModals.can[key]
        elseif modality == "could" then
            modal = modal[number == "plural" and "plural" or gender]
                or (number == "singular" and (person == 1 or person == 2)
                    and ukrainianModals.could.masculine .. "/" .. ukrainianModals.could.feminine)
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
    local passiveAll = tree.allSubject and tree.aspect == "passive"
    if tree.allSubject and subject and not passiveAll then subject = subject .. " all" end
    local lexeme = tree.verb.lexeme
    local frame = lexeme.frame or {}
    if frame.impersonalNeed and tree.infinitive and not (subject or tree.imperative or tree.modal) then
        local be = tree.tense == "past" and "was" or tree.tense == "future" and "will" or "is"
        local opening = tree.question and (be .. " it") or ("it " .. be)
        return opening .. (tree.negative and " not" or "") .. (be == "will" and " be necessary" or " necessary")
    end
    local form = tree.verb.form
    local lemma = form and form.mood == "impersonal" and frame.ellipticPastEn
        or tree.content and not tree.recipient and frame.enContentWithoutRecipient or lexeme.en
    if frame.enByDirectionalAdverb then
        for _, adverb in ipairs(tree.adverbs or {}) do
            local directional = adverb.context == "arrival" and frame.enByDirectionalAdverb[adverb.en[1]]
            if directional then lemma = directional; break end
        end
    end
    local particle = frame.particle
    if particle and tree.object and (tree.object.pronoun or frame.objectBeforeParticle) then
        lemma = lemma:sub(1, -#particle - 2)
    end
    local leading = tree.leadingAdverb
    local adverb = leading and not leading.postposedEn and leading.en[1] .. " " or ""
    for _, modifier in ipairs(tree.additionalLeadingAdverbs or {}) do
        if not modifier.postposedEn then adverb = adverb .. modifier.en[1] .. " " end
    end
    if tree.hortative then return "Let's " .. (tree.negative and "not " or "") .. adverb .. lemma end
    if tree.longLive then return "long live " .. subject end
    if tree.optative then return "let " .. subject .. (tree.negative and " not " or " ") .. adverb .. lemma end
    if tree.sharedModal or tree.sharedFuture then
        if tree.modalPerfect then lemma = englishForm(lemma, "participle", "verb") end
        return (tree.negative and "not " or "") .. adverb .. lemma
    end
    if tree.tense == "infinitive" then return adverb .. (tree.gerund and englishForm(lemma, "ing", "verb") or lemma) end
    local person, number = agreement(tree, true)
    local third = person == 3 and number == "singular"
    local inversion = tree.question and not (tree.wh and tree.wh.role == "subject"
        or tree.sentenceAdverb and tree.sentenceAdverb.tentative)
    local prefix
    if tree.aspect == "passive" then
        lemma = englishForm(lemma, "participle", "verb")
        if tree.modal then
            prefix, lemma = tree.modal, "be " .. lemma
        else
            prefix = tree.tense == "past" and ((number == "plural" or person == 2) and "were" or "was")
                or presentBe(person, number)
        end
    elseif tree.ability then
        if tree.ability == "future" or tree.ability == "conditional" then
            prefix = tree.ability == "future" and "will" or "would"
            lemma = "be able to " .. lemma
        else
            prefix = tree.ability == "past" and ((number == "plural" or person == 2) and "were" or "was")
                or presentBe(person, number)
            lemma = "able to " .. lemma
        end
    elseif tree.conditional or frame.politeDesire then prefix = "would"
    elseif tree.modal then
        prefix = tree.modal
        if tree.modalPerfect then lemma = "have " .. englishForm(lemma, "participle", "verb") end
    elseif tree.reportedFuture then prefix = "would"
    elseif tree.reportedAnterior or tree.deadlineMain and tree.tense == "past" and tree.verb.head.aspect == "perfective" then
        prefix, lemma = "had", englishForm(lemma, "participle", "verb")
    elseif tree.perfectProgressive then
        prefix, lemma = tree.tense == "past" and "had" or third and "has" or "have",
            (lemma == "be" or frame.stative) and englishForm(lemma, "participle", "verb")
                or "been " .. englishForm(lemma, "ing", "verb")
    elseif tree.occurrencePerfect or tree.since and (tree.tense == "past" or tree.tense == "present") then
        prefix, lemma = tree.occurrencePerfect == "past" and "had" or third and "has" or "have",
            englishForm(lemma, "participle", "verb")
    elseif tree.tense == "present" and (tree.aspect == "continuous" or frame.englishProgressiveWithPurpose and tree.purpose
        or frame.englishProgressiveStill and leading and leading.en[1] == "still") then
        prefix, lemma = presentBe(person, number), englishForm(lemma, "ing", "verb")
    elseif tree.tense == "past" and tree.aspect == "continuous" then
        prefix, lemma = (number == "plural" or person == 2) and "were" or "was", englishForm(lemma, "ing", "verb")
    elseif tree.tense == "future" and not tree.temporalDependent then
        prefix = "will"
        if tree.aspect == "continuous" then lemma = "be " .. englishForm(lemma, "ing", "verb") end
    elseif tree.negative or inversion or tree.emphaticDo then
        prefix = tree.tense == "past" and "did" or (third and not tree.imperative and "does" or "do")
    end
    if prefix then
        local negative = tree.negative and " not" or ""
        if passiveAll then negative = tree.allUnderNegation and negative .. " all" or " all" .. negative end
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

local function paceObject(node, english, owner)
    if not node.possessor or not owner then return node end
    local own, modifiers = false, {}
    for _, modifier in ipairs(node.adjectives or {}) do
        if modifier.entry and modifier.entry.lexeme.en == "own" then own = true
        else modifiers[#modifiers + 1] = modifier end
    end
    local reflexive = node.possessor.lexeme.frame.reflexivePossessive
    local sameOwner = owner == node.possessor.lexeme.en
    local removeOwn = not english and own and (reflexive or sameOwner)
    local addOwn = english and reflexive and not own
    if not (removeOwn or addOwn) then return node end
    local adapted = {}
    for key, value in pairs(node) do adapted[key] = value end
    if removeOwn then adapted.adjectives, adapted.emphaticOwner = modifiers, sameOwner end
    if addOwn then adapted.englishOwn = true end
    return adapted
end

local ukrainianVowels = { ["а"]=true, ["е"]=true, ["є"]=true, ["и"]=true, ["і"]=true,
    ["ї"]=true, ["о"]=true, ["у"]=true, ["ю"]=true, ["я"]=true }

function G.preposition(complement, english, owner)
    local rule = complement.rule
    local case = complement.case
    local object = not english and complement.possessiveObject
        or rule.reflexivePace and paceObject(complement.object, english, owner) or complement.object
    local reference = rule.deicticReference and object.pronoun and object.pronoun.id
    local marked = reference and (reference == "that" and (english and "that" or "те") or (english and "it" or "це"))
        or not english and ukrainianPrepositionalPronoun(object, case)
    local article = complement.englishArticle
    if article == nil then article = rule.englishArticle end
    if article == nil then article = true end
    local entry = complement.object.entry
    local frame = entry and entry.lexeme.frame
    if english and case == "locative" and frame and frame.englishLocativeArticle ~= nil then
        article = frame.englishLocativeArticle
    end
    local value = marked or G.noun(object, english, case, article, nil, owner)
    if not value then return nil end
    if complement.apposition then
        local title = G.noun(complement.apposition, english, case, "definite", nil, owner)
        if not title then return nil end
        value = withComma(value) .. " " .. title
    end
    local term = complement.object.term
    local locative = rule.id == "in" and complement.case == "locative"
        and (frame and frame.locativePreposition or term and term.features and term.features.locativePreposition)
    local targetEn = rule.targetEnByClass and rule.targetEnByClass[P.semanticClass(complement.object)]
    local marker = english and (targetEn or rule.targetEn or rule.en[1]) or complement.targetUk or locative or rule.targetUk
    if not english then
        if marker == "у" and rule.directional and ukrainianVowels[ns.Engine.Normalize.word(value:sub(1, 2))] then marker = "в"
        else marker = euphonicZ(marker, value) end
        if rule.inclusive then value = value .. " " .. rule.inclusive end
    end
    if complement.extension then
        local extension = complement.extension
        local parts = {value, (english and extension.expression.en or extension.expression.uk)[1]}
        if extension.manner then append(parts, (english and extension.manner.en or extension.manner.uk)[1]) end
        if extension.company then
            local company, companyMarker = G.preposition(extension.company, english, owner)
            if not company then return nil end
            append(parts, companyMarker)
            append(parts, company)
        end
        value = table.concat(parts, " ")
    end
    return value, marker
end

local function addPrepositions(parts, tree, english, owner)
    for _, complement in ipairs(tree.prepositions or {}) do
        local value, marker = G.preposition(complement, english, owner)
        if not value then return false end
        if not english and complement.rule.ukBeforeComma and #parts > 0 then
            parts[#parts] = withComma(parts[#parts])
        end
        if complement.locationAdverb then
            append(parts, (english and complement.locationAdverb.en or complement.locationAdverb.uk)[1])
        end
        append(parts, marker)
        append(parts, value)
        if complement.infinitive then
            local action = render(complement.infinitive, english, owner)
            if not action then return false end
            if english then append(parts, "to") end
            append(parts, action)
        end
    end
    if tree.locativeSource then
        local source = tree.locativeSource
        local dependent = render(source.clause, english)
        if not dependent then return false end
        append(parts, (english and source.cue.en or source.cue.uk)[1])
        append(parts, dependent)
    end
    return true
end

local function addPriceComparison(parts, tree, english, owner)
    local price, standard = tree.priceComparison, tree.priceStandard
    if not price then return true end
    if tree.priceComma then parts[#parts] = withComma(parts[#parts]) end
    local value = english and (standard and price.standardEn or price.en[1]) or price.uk[1]
    if not standard then append(parts, value); return true end
    local object, marker = G.preposition(standard, english, owner)
    if not object then return false end
    append(parts, value .. (english and " than" or ", ніж"))
    append(parts, marker)
    append(parts, object)
    return true
end

local function addPurpose(parts, purpose, english, owner)
    if not purpose then return true end
    local value, marker
    if purpose.verb or purpose.kind == "activity" then
        value = render(purpose, english, owner)
        marker = english and (purpose.negative and "not to" or "to") or "щоб"
        if not english and purpose.recruitedSubject then
            local subject = purpose.recruitedSubject
            local relative = P.relativePronoun(subject, "nominative")
            if relative then marker = relative .. (subject.number == "plural" and " хочуть" or " хоче") end
        end
    else
        value = G.noun(purpose.object, english, "accusative", true, nil, owner)
        marker = english and "for" or "щоб отримати"
    end
    if not value then return false end
    if not english then parts[#parts] = withComma(parts[#parts]) end
    append(parts, marker)
    append(parts, value)
    return addInfinitiveSeries(parts, purpose, english, owner)
end

function G.search(object, purpose, english, group, emphatic)
    local value = G.noun(object, english, "accusative", english)
    if not value then return nil end
    local opening = english and "Looking for " or group and "Шукаємо " or "Шукаю "
    local ending = emphatic and "!" or "."
    if not purpose then
        if object.relative then value = (value:gsub(",+$", "")) end
        return opening .. value .. ending
    end
    local parts = {opening .. value}
    if addPurpose(parts, purpose, english) then return table.concat(parts, " ") .. ending end
end

local function subjectText(tree, english)
    if tree.inherited or (not english and tree.implicitSubject) or (tree.wh and tree.wh.role == "subject") then return "" end
    if english and tree.verb and tree.verb.form and tree.verb.form.mood == "impersonal" then return "" end
    local frame = tree.verb and tree.verb.lexeme.frame
    if not tree.subject and frame and frame.impersonalNeed and tree.infinitive then return "" end
    if tree.modal == "should" and tree.ellipticSubject then return english and tree.question and "one" or "" end
    if tree.subject then
        if english and tree.optative then return G.noun(tree.subject, true, "accusative", "definite") end
        if tree.subject.actionSubject then return G.actionSubjectText(tree.subject.actionSubject) end
        if not english and tree.modal == "should" then return G.noun(tree.subject, false, "dative") end
        local article, value
        local pronoun = tree.subject.pronoun
        if not english and tree.predicatePossessive and not tree.possessionAntecedent and pronoun and pronoun.id == "it" then
            return "це"
        end
        if english and frame and frame.ukContentHead and tree.content and pronoun
            and (pronoun.id == "this" or pronoun.id == "that") then return "it" end
        local preposition = tree.copula and tree.prepositions and tree.prepositions[1]
        if not english and preposition and preposition.rule.deicticSubjectUk and pronoun and pronoun.id == "it" then
            return preposition.rule.deicticSubjectUk
        end
        if not english and frame and frame.deicticSubject and pronoun
            and (pronoun.id == "that" or pronoun.id == "this"
                or pronoun.id == "it" and frame.deicticSubjectIt) then return frame.deicticSubject end
        if english and tree.question and (tree.copula or not tree.modal or tree.subjectLocation)
            and tree.subject.pronoun and tree.subject.pronoun.id == "someone"
            and not (tree.sentenceAdverb and tree.sentenceAdverb.tentative) then
            value = "anyone"
        end
        if english and tree.exclamative then article = true
        elseif english and tree.wh and tree.wh.role == "predicate" then article = tree.wh.definite and "definite" or true
        elseif english and tree.aspect == "passive" then article = "definite"
        elseif english and tree.wh and tree.wh.kind == "clock" then article = "definite"
        elseif english and (tree.kind == "need" or tree.subjectLocation or tree.temporalDependent
            or tree.contentClause or tree.predicateAdverb or tree.adverbComplement or tree.absencePredicate
            or tree.locationEllipsis or tree.locationEllipsisAnchor
            or tree.where and not tree.question) then
            article = "definite"
        end
        if english and not article and frame and frame.impersonalNeed and tree.infinitive then article = "definite" end
        local predicateFrame = frame or tree.adjective and tree.adjective.entry.lexeme.frame
        if english and not article and (preposition and preposition.rule.definiteSubject or predicateFrame
            and (predicateFrame.definiteSubject or predicateFrame.definiteSubjectClasses
                and predicateFrame.definiteSubjectClasses[P.semanticClass(tree.subject)])) then
            article = "definite"
        end
        if english and not article and tree.evaluation and tree.evaluation.patient then article = true end
        if english and not article and (tree.ability or tree.frontedModal) then article = true end
        local affiliation = tree.subject.argument
        if english and not article and affiliation then article = affiliation.form.englishSubjectArticle end
        if english and not article and tree.kind == "clause" and P.semanticClass(tree.subject) == "playableRace" then
            article = true
        end
        if english and not article and tree.subject.term then
            local category = tree.subject.term.category
            for _, phrase in ipairs(tree.prepositions or {}) do
                if phrase.rule.definiteParticipants and (category == "roles" or category == "classes") then
                    article = "definite"
                    break
                end
            end
        end
        local fragment = tree.kind == "nounPhrase" and tree.negative
        local category = tree.subject.term and tree.subject.term.category
        local common = english and tree.frontedModal and (category == "roles" or category == "classes")
        local case = english and fragment and pronoun and "accusative" or "nominative"
        value = value or G.noun(tree.subject, english, case, article or fragment, nil, nil, common)
        if not value or not tree.subjectLocation then return value end
        local parts = {value}
        if addPrepositions(parts, tree.subjectLocation, english) then return table.concat(parts, " ") end
    end
    if tree.kind == "nounPhrase" or tree.imperative or tree.tense == "infinitive" or not english then return "" end
    local _, number, gender, key = agreement(tree)
    return inferredPronouns[key] or (number == "singular" and inferredPronouns[gender])
end

function G.actionSubjectText(action)
    local function nominal(event)
        local form = event.verb.lexeme.frame.eventNominal
        local parts = {form.noun}
        if event.object then
            local object = G.noun(event.object, false, "genitive")
            if not object then return nil end
            append(parts, form.objectMarker and euphonicZ(form.objectMarker, object))
            append(parts, object)
        end
        if not addPrepositions(parts, event, false) then return nil end
        return table.concat(parts, " ")
    end
    local first = nominal(action)
    if not first then return nil end
    local parts = {first}
    for _, step in ipairs(action.series or {}) do
        local value = nominal(step.action)
        if not value then return nil end
        if step.join then append(parts, step.join.uk[1])
        else parts[#parts] = withComma(parts[#parts]) end
        append(parts, value)
    end
    return table.concat(parts, " ")
end

local whPerson = {accusative="кого", genitive="кого", dative="кому", instrumental="ким"}
local whThing = {accusative="що", genitive="чого", instrumental="чим"}
local whDefinite = {masculine="який", feminine="яка", neuter="яке", plural="які"}
local function questionWord(tree, english)
    local wh = tree.wh
    if wh then
        if wh.indirectPredicate then return english and "what" or "чим" end
        if wh.boundRelative then
            if english then
                if not wh.total then return "what" end
                return wh.role == "subject" and "that" or ""
            end
            return wh.role == "subject" and "що" or whThing[wh.case]
        end
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
    if not english and tree.inference then return "напевно," end
    if not english and tree.modal == "might" and not tree.sharedModal then return "можливо," end
    if tree.where then
        if english then return "where" end
        local frame = tree.verb and tree.verb.lexeme.frame
        return (tree.where == "destination" or frame and frame.displacesObject and tree.object) and "куди" or "де"
    end
    if tree.why then return english and "why" or "чому" end
    if tree.when then return english and "when" or "коли" end
    if tree.question and not english and not (tree.sentenceAdverb and tree.sentenceAdverb.tentative) then return "чи" end
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

local function quantityText(quantity, english, context)
    local approximation = quantity.approximate and (english or context ~= "delay")
        and (english and "about " or "приблизно ") or ""
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
        else case, number = P.countedCase(quantity.amount, "accusative", false) end
        word = L.inflectLemma(quantity.unit, "noun", {case=case, number=number})
    end
    if not word then return nil end
    if quantity.indefinite and not quantity.few and (quantity.approximate or context == "elapsed") then
        if english then return approximation .. (word == "hour" and "an " or "a ") .. word end
        return approximation .. word
    end
    local amount = quantity.few and (english and "a few" or "кілька") or quantity.amount
    return approximation .. amount .. " " .. word
end

pastOffsetText = function(offset, english)
    local value = quantityText(offset.quantity, english, "elapsed")
    if not value then return nil end
    local suffix = english and " ago" or " тому"
    if offset.alternative then
        local alternative = pastOffsetText(offset.alternative, english)
        if not alternative then return nil end
        return (english and "not " or "не ") .. value .. suffix .. (english and " but " or ", а ") .. alternative
    end
    local bound = offset.bound
    if bound == "less" then value = (english and "less than " or "менше ніж ") .. value
    elseif bound == "more" then value = (english and "more than " or "більше ніж ") .. value end
    return value .. suffix
end

local function pastAppraisal(tree)
    local topic, subject = tree.predicate, tree.subject
    local pointer = subject and subject.pronoun
    if not topic or not topic.adjectives or not pointer or (pointer.id ~= "that" and pointer.id ~= "this")
        or tree.tense ~= "past" or tree.negative or tree.question or tree.prepositions or tree.adverbs then return end
    local remaining, manner = {}
    for _, modifier in ipairs(topic.adjectives) do
        local frame = modifier.entry and modifier.entry.lexeme.frame
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

local inferredPossessives = {I="my", you="your", we="our", they="their", he="his", she="her", it="its"}

local function welcomeAudience(audience, english)
    local groups = G.noun(audience.groups, english, english and "nominative" or "genitive")
    if not groups then return nil end
    local recipient = audience.recipient
    local people = recipient and G.noun(recipient, english, english and "nominative" or "dative")
    if recipient and not people then return nil end
    if english then
        local subject = people and (people .. " of " .. groups) or audience.freeChoice and ("players of " .. groups) or groups
        local be = recipient and presentBe(recipient.person, recipient.number) or "are"
        return subject .. " " .. be .. (audience.negative and " not welcome" or " welcome")
    end
    return (audience.negative and "не раді " or "раді ") .. (people or "гравцям") .. " " .. groups
end

local function realizeFirstObjectAction(tree)
    local actions = tree.objectActions
    if not actions or tree.aspect == "passive" then return tree end
    local sharedFuture = #actions > 1 and tree.tense == "future" and not tree.modal
    if sharedFuture then
        for _, action in ipairs(actions) do
            local frame = action.verb.lexeme.frame or {}
            if action.verb.head.aspect == "perfective" or frame.futureLemma or frame.futureEventLemma then
                sharedFuture = false
                break
            end
        end
    end
    if tree.negative and #actions > 1 and not (sharedFuture or tree.modal and tree.modal ~= "might") then
        return tree
    end
    local first = {}
    for key, value in pairs(tree) do first[key] = value end
    first.verb, first.object, first.realizedObjectActions = actions[1].verb, actions[1].object, actions
    first.sharedObjectFuture = sharedFuture
    return first
end

local function addObjectActions(parts, tree, owner)
    local actions = tree.realizedObjectActions
    for index = 2, #actions do
        local action = actions[index]
        local value = render({kind="clause", verb=action.verb, object=action.object, subject=tree.subject,
            inferred=tree.inferred, inherited=true, tense=tree.tense, aspect=tree.aspect,
            sharedFutureAuxiliary=tree.sharedObjectFuture,
            imperative=tree.imperative, hortative=tree.hortative, modal=tree.modal, modalSense=tree.modalSense,
            modalPerfect=tree.modalPerfect, sharedModal=tree.modal ~= nil, ability=tree.ability,
            purposeClause=tree.purposeClause, intendedEvent=tree.intendedEvent}, false, owner)
        if not value then return false end
        local join = action.join
        if join.comma then parts[#parts] = withComma(parts[#parts])
        else
            local previous = actions[index - 1].object
            append(parts, join.id == "and" and previous.members and join.uk[3] or join.uk[1])
        end
        append(parts, value)
    end
    return true
end

renderTree = function(tree, english, controller)
    local lexicalFrame = tree.verb and tree.verb.lexeme.frame
    if lexicalFrame and lexicalFrame.enLexicalNegative then
        local predicate = {}
        for key, value in pairs(tree) do predicate[key] = value end
        predicate.negative = not english
        tree = predicate
    end
    if not english and tree.objectActions then tree = realizeFirstObjectAction(tree) end
    if tree.kind == "adjectivePhrase" then
        local value = adjective(tree.adjective, english, "nominative", "plural")
        if not value then return nil end
        local parts = {}
        if tree.negative then append(parts, english and "not" or "не") end
        append(parts, value)
        if not addPrepositions(parts, tree, english, controller) then return nil end
        return table.concat(parts, " ")
    end
    if tree.intentionNote then
        local action = tree.infinitive
        local subject = "Мета"
        if english then subject = G.noun(tree.subject, true, "nominative", "definite") end
        local value = render(action, english, controller)
        if not subject or not value then return nil end
        local parts = {subject, english and (action.negative and "is not to" or "is to") or "—", value}
        if not addInfinitiveSeries(parts, action, english, controller) then return nil end
        return table.concat(parts, " ")
    end
    if tree.kind == "welcoming" then
        if tree.audience then return welcomeAudience(tree.audience, english) end
        local recipient = G.noun(tree.recipient, english, english and "nominative" or "dative", english)
        if not recipient then return nil end
        if tree.interests then
            local interests, marker = G.preposition(tree.interests, english)
            if not interests then return nil end
            local audience = recipient .. " " .. marker .. " " .. interests
            return english and (audience .. " " .. presentBe(tree.recipient.person, tree.recipient.number) .. " welcome")
                or ("раді " .. audience)
        end
        local adverb = tree.welcomeAdverb
        local parts
        if english then
            parts = {recipient, presentBe(tree.recipient.person, tree.recipient.number)}
            if adverb then append(parts, adverb.en[1]) end
            if tree.negative then append(parts, "not") end
            append(parts, "welcome")
        else
            parts = {recipient}
            if adverb then append(parts, adverb.uk[1]) end
            if tree.negative then append(parts, "не") end
            append(parts, "раді")
        end
        return table.concat(parts, " ")
    end
    if tree.exclusion then
        local items = G.noun(tree.subject, english, english and "nominative" or "genitive")
        return items and (english and "no" or tree.exclusion) .. " " .. items
    end
    if tree.restriction then
        local items = G.noun(tree.subject, english, "nominative", true)
        if not items then return nil end
        local output = (english and tree.restriction.en or tree.restriction.uk)[1] .. " " .. items
        if not tree.audience then return output end
        local welcome = welcomeAudience(tree.audience, english)
        return welcome and output .. ". " .. ns.Engine.Normalize.upperStart(welcome)
    end
    if tree.descriptionLabel then
        local description = G.noun(tree.subject, english, "nominative", english)
        return description and tree.descriptionLabel .. (english and " is " or " — ") .. description
    end
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
    if tree.kind == "levelAnnouncement" then
        if english then return tree.level and "Ding, level " .. tree.level or "Ding" end
        return tree.level and "Новий рівень — " .. tree.level .. "-й" or "Новий рівень"
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
        local objectCase = english and tree.kind == "need" and "accusative" or "nominative"
        local value = object and G.noun(object, english, objectCase, true)
        if not value and not (tree.kind == "need" and tree.wh and tree.wh.boundRelative) then return nil end
        local agreement = object and (object.number == "plural" and "plural" or object.gender)
        local forms = {masculine="потрібен", feminine="потрібна", neuter="потрібне", plural="потрібні"}
        if tree.kind == "need" then
            local predicate = english and "need" or forms[agreement] or "потрібно"
            local parts = {}
            if tree.wh then append(parts, questionWord(tree, english)) end
            if tree.subject then
                local subject = english and subjectText(tree, true) or G.noun(tree.subject, false, "dative")
                if not subject then return nil end
                local third = tree.subject.person == 3 and tree.subject.number == "singular"
                if tree.question then append(parts, english and (third and "does" or "do") or "чи")
                elseif english and tree.negative then predicate = third and "does not need" or "do not need"
                elseif english and third then predicate = "needs" end
                append(parts, subject)
                if tree.allSubject then append(parts, english and "all" or "усім") end
            end
            if not english and tree.negative then append(parts, "не") end
            append(parts, predicate)
            append(parts, value)
            if not addPrepositions(parts, tree, english) then return nil end
            if not addPurpose(parts, tree.purpose, english) then return nil end
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
        local name = G.address(tree.recipient, english)
        if tree.bareAddress then return name end
        if name then
            local polite = tree.recipient.number == "plural" or tree.recipient.addressTitle
            local greeting = tree.expression and (not english and polite and tree.expression.pluralUk
                or (english and tree.expression.en or tree.expression.uk)[1])
                or (english and "Hello" or "Вітаю")
            local address = tree.fellowAddress and (english and "fellow " or "друзі-") or ""
            return greeting .. ", " .. address .. name
        end
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
    if tree.kind == "adverbPhrase" or tree.kind == "pricePhrase" then
        local parts = {}
        if tree.amount then
            append(parts, english and tree.amount.raw or ns.Engine.Grammar.moneyText(tree.amount, true))
        elseif tree.expression then
            local value = (english and tree.expression.en or tree.expression.uk)[1]
            if tree.negative then append(parts, english and "not" or "не") end
            append(parts, value .. (tree.comma and "," or ""))
        end
        if not addPrepositions(parts, tree, english) then return nil end
        if not addPriceComparison(parts, tree, english) then return nil end
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
    if tree.kind == "coordinateReport" then
        local language = english and "en" or "uk"
        local parts = {tree.coordinateSource[language][1], tree.coordinateReport[language][1], tree.coordinates}
        if not addPrepositions(parts, tree, english) then return nil end
        return table.concat(parts, " ")
    end
    if tree.kind == "routeQuestion" then
        local cue = tree.cue
        local parts = {english and cue.en[1] or cue.uk[1]}
        if english then
            local action = tree.routeMotion
            if action and action.lexeme.uk ~= cue.routeInfinitiveUk then append(parts, "to " .. action.lexeme.en) end
        else
            append(parts, cue.routeInfinitiveUk)
        end
        if not addPrepositions(parts, tree, english) then return nil end
        return table.concat(parts, " ")
    end
    if tree.kind == "existential" then
        local noun = tree.subject
        local category = noun and noun.term and noun.term.category
        local profession = category == "classes" or category == "roles"
        local _, number, gender = agreement(tree, english)
        local plural = (tree.existentialNumber or number) == "plural"
        local tense = tree.tense or "present"
        local case = not english and tree.negative and "genitive" or "nominative"
        local any = english and tree.negative and (plural or tree.capacity or noun and P.mass(noun))
        local subject = noun and G.noun(noun, english, case, not (tree.capacity or any), nil, nil, profession)
        if noun and not subject then return nil end
        local indefinite = noun and noun.pronoun and noun.pronoun.id == "someone"
        local parts
        local locationValue, locationMarker
        if tree.locationPreposition then
            local place = tree.locationPreposition
            if english and tree.capacity and place.rule.id == "on" and P.isScheduledEvent(place.object) then
                locationValue, locationMarker = G.noun(place.object, true, place.case, "definite"), "at"
            else
                locationValue, locationMarker = G.preposition(place, english)
            end
            if not locationValue then return nil end
        end
        local frontedLocation = not english and (not tree.question or tree.why) and tree.locationAdverb and not tree.possessor
        if english then
            if indefinite and tree.question then subject = "anyone" end
            local located = tree.nearby or tree.prepositions or tree.locationAdverb
            local be = tense == "past" and (plural and "were" or "was")
                or tense == "future" and "will" or (plural and "are" or "is")
            local certainty = tree.certainty and tree.certainty.en[1]
            local opening
            if tree.possessorSubject then
                local owner = tree.possessorSubject
                local actor = G.noun(owner, true, "nominative")
                local third = owner.person == 3 and owner.number ~= "plural"
                if not actor then return nil end
                if tree.question then opening = (third and "does " or "do ") .. actor .. " have"
                else opening = actor .. (third and " has" or " have") end
            elseif tree.question then
                opening = tree.possessor and "do we have"
                    or tense == "present" and indefinite and located and "is" or be .. " there"
            else opening = "there " .. (certainty and certainty .. " " or "") .. be end
            if tree.why then opening = "why " .. opening end
            parts = {opening}
            if tree.question and certainty then append(parts, certainty == "sure" and "really" or certainty) end
            if tree.negative then append(parts, "not") end
            if tense == "future" then append(parts, "be") end
            if tree.persistence then append(parts, tree.persistence.en[1]) end
            if tree.quantityFocus then append(parts, tree.quantityFocus.en[1]) end
            if any and subject then append(parts, "any") end
            append(parts, subject)
            if tree.nearby then append(parts, "around") end
            append(parts, locationMarker)
            append(parts, locationValue)
        else
            parts = {}
            if tree.why then append(parts, "Чому") end
            append(parts, locationMarker)
            append(parts, locationValue)
            if frontedLocation then append(parts, tree.locationAdverb.uk[1]) end
            if tree.question and not tree.why then append(parts, "чи") end
            if tree.persistence and tree.nearby and not tree.possessor then append(parts, "тут") end
            if tree.persistence then append(parts, tree.persistence.uk[1]) end
            if tree.certainty then append(parts, tree.certainty.uk[1]) end
            local exists = "є"
            if tense == "future" then exists = plural and "будуть" or "буде"
            elseif tense == "past" then exists = pastCopula[plural and "plural" or gender] or "було" end
            if tree.negative then
                exists = tense == "past" and "не було" or tense == "future" and "не буде" or "немає"
            end
            append(parts, exists)
            if tree.possessor then append(parts, "в нас") end
            if tree.nearby and (not tree.persistence or tree.possessor) then append(parts, "тут") end
            if tree.quantityFocus then append(parts, tree.quantityFocus.uk[1]) end
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
        if rule.audience then
            local audience = G.noun(tree.object, english, english and "accusative" or rule.ukCase)
            if not audience then return nil end
            local signal = tree.audienceSignal
            local prefix = signal and (english and signal.en[1] or signal.uk[1]) .. ", " or ""
            return prefix .. (english and rule.targetEn or rule.targetUk) .. " " .. audience
        end
        local standalone = not tree.object and not tree.action
        local head = english and (standalone and not tree.everyone and rule.standaloneEn or rule.en[1]) or rule.uk[1]
        if tree.everyone then
            local everyone = tree.relativeRecipient and G.noun(tree.relativeRecipient, english, "dative")
            if tree.relativeRecipient and not everyone then return nil end
            head = head .. " " .. (everyone or (english and "everyone" or "всім"))
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
    local parts = not english and tree.optative and {"нехай"} or {}
    local subject = subjectText(tree, english)
    if subject == nil then return nil end
    local reference = tree.subject and tree.subject.pronoun
    if english and tree.evaluationContent then subject = "it" end
    if not english and tree.predicativeRelative and reference
        and (reference.deixis or reference.id == "it") then subject = "це" end
    local identity = tree.copula and tree.predicate and reference and reference.deixis
    local pluralIdentity = english and identity and targetNumber(tree.predicate, true) == "plural"
        and not (tree.predicate.quantity and P.hasTrait(tree.predicate, "durationUnit"))
    if pluralIdentity and subject ~= "" then
        subject = demonstrative({demonstrative=identity}, true, "nominative", "plural")
    end
    local question = questionWord(tree, english)
    local questionPreposition = not english and tree.wh and tree.wh.preposition
    if question and questionPreposition then question = euphonicZ(questionPreposition, question) .. " " .. question end
    local owner = P.subjectPossessive(tree.subject) or (tree.imperative and "your") or (tree.hortative and "our")
        or (tree.tense == "infinitive" and controller) or inferredPossessives[subject]
    local verbFrame = tree.verb and tree.verb.lexeme.frame
    local measuredPredicate = english and verbFrame and verbFrame.measuredPredicate
    if tree.wh and not question then return nil end
    if tree.kind == "nounPhrase" then
        if tree.negative then append(parts, english and "not" or "не") end
        append(parts, subject)
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
        if pluralIdentity then number = "plural" end
        local pronoun = reference
        local evaluation = tree.evaluation
        local difficulty = evaluation and evaluation.difficulty
        local status = tree.predicateAdverb
        local quantified = status and status.quantifiedSubject
        local fusedNegative = not english and tree.negative
            and (difficulty and evaluation.rule.negativeUk or quantified and status.negativeUk)
        local demonstrative = pronoun and pronoun.deixis
        local adjectiveFrame = tree.adjective and tree.adjective.entry.lexeme.frame
        local possessedState = not english and adjectiveFrame and adjectiveFrame.ukPossessedState
        if not english and tree.adjectiveContent and tree.tense == "present" and not tree.negative then
            local verb = L.inflectLemma(adjectiveFrame.ukContentLemma, "verb",
                {person=person, number=number, tense="present", mood="indicative"})
            local content = render(tree.adjectiveContent, english)
            if verb and content then return subject .. " " .. verb .. ", що " .. content end
            return nil
        end
        local experiencer = not english and adjectiveFrame and adjectiveFrame.ukExperiencer
        local state = not english and tree.predicateAdverb and tree.predicateAdverb.statePredicate
        local initialPhase = not english and not (state or tree.omittedCopula or tree.exhausted)
            and tree.predicateAdverb and tree.predicateAdverb.earlierPhase
        local degree = experiencer and tree.adjective.intensity
        if degree then
            experiencer = (degree == "more" and "більш " or degree == "so" and "так " or degree == "too" and "надто " or "дуже ")
                .. experiencer
        end
        if possessedState then
            local possessor = ukrainianPrepositionalPronoun(tree.subject, "genitive")
                or G.noun(tree.subject, false, "genitive")
            local intensity = tree.adjective.intensity
            local quantity = intensity == "too" and "забагато" or intensity == "more" and "більше"
                or intensity == "so" and "стільки" or intensity and "багато"
            local case = (tree.negative or quantity) and "genitive" or "nominative"
            local property = L.inflectLemma(possessedState.lemma, "noun", {case=case, number=possessedState.number})
            if not (possessor and property) then return nil end
            append(parts, question)
            append(parts, "у " .. possessor)
            if tree.predicateModifier then append(parts, tree.predicateModifier.uk[1]) end
            if tree.negative and not quantity then
                append(parts, tree.tense == "past" and "не було" or tree.tense == "future" and "не буде" or "немає")
            else
                local plural = not quantity and possessedState.number == "plural"
                if tree.tense == "past" then
                    append(parts, plural and pastCopula.plural or pastCopula[possessedState.gender] or "було")
                elseif tree.tense == "future" then append(parts, plural and "будуть" or "буде") end
                if tree.negative then quantity = (quantity == "багато" and "не" or "не ") .. quantity end
            end
            append(parts, quantity)
            append(parts, property)
        elseif tree.omittedCopula then
            if tree.negative then append(parts, english and "not" or "не") end
        elseif english then
            local be
            local futureCopula = tree.tense == "future" and not tree.temporalDependent
            local perfectCopula = tree.durationSpan and tree.durationSpan.ongoing
                and not (futureCopula or tree.modal or tree.reportedFuture)
            if tree.modal == "might" or tree.inference then be = tree.modal
            elseif tree.conditional or tree.reportedFuture then be = "would"
            elseif futureCopula then be = "will"
            elseif perfectCopula then
                be = tree.tense == "past" and "had" or person == 3 and number == "singular" and "has" or "have"
            elseif tree.tense == "past" then be = (number == "plural" or person == 2) and "were" or "was"
            else be = presentBe(person, number) end
            append(parts, question)
            if tree.question and not (tree.wh and tree.wh.role == "subject") then append(parts, be); append(parts, subject)
            else append(parts, subject); append(parts, be) end
            if tree.allSubject and tree.negative and not tree.expletiveNegative and not tree.allUnderNegation then
                append(parts, "all")
            end
            if tree.negative and not tree.expletiveNegative then append(parts, "not") end
            if tree.modal == "might" or tree.inference or futureCopula or tree.conditional or tree.reportedFuture then
                append(parts, tree.modalPerfect and "have been" or "be")
            end
            if perfectCopula then append(parts, "been") end
            if tree.allSubject and (not tree.negative or tree.expletiveNegative or tree.allUnderNegation) then
                append(parts, "all")
            end
        elseif tree.locationEllipsis then
            local absent = G.noun(tree.subject, false, "genitive")
            if not absent then return nil end
            append(parts, absent)
            append(parts, tree.locationEllipsis)
            append(parts, tree.tense == "past" and "не було" or tree.tense == "future" and "не буде" or "немає")
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
            elseif difficulty and evaluation.patient then
                subject = G.noun(tree.subject, false, evaluation.action.relativeCase)
                if not subject then return nil end
            end
            if tree.predicate and (demonstrative or pronoun and pronoun.id == "it") then
                subject = pronoun.ukIdentity or "це"
                number, gender = tree.predicate.number, tree.predicate.gender or gender
            elseif tree.predicateAdverb and tree.predicateAdverb.deicticEvaluation then
                subject = "це"
            elseif tree.price and pronoun and pronoun.id == "it" then
                subject = "це"
            elseif tree.modal == "might" and tree.predicate and tree.subject.pronoun and tree.subject.pronoun.id == "it" then
                subject = "це"
            end
            local nominalAll = tree.allSubject and tree.adjective and not (pronoun or experiencer)
            if nominalAll then append(parts, tree.allUnderNegation and "не всі" or "усі") end
            append(parts, subject)
            if initialPhase then append(parts, tree.predicateAdverb.uk[1]) end
            if tree.allSubject and not (nominalAll or tree.allUnderNegation) then append(parts, "всі") end
            if tree.modal == "might" and tree.predicate and not tree.subject.pronoun then append(parts, "—") end
            if (tree.negative and not (fusedNegative or nominalAll and tree.allUnderNegation))
                or tree.expletiveNegative then append(parts, "не") end
            if tree.allUnderNegation and not nominalAll then append(parts, "всі") end
            if tree.tense == "future" then
                append(parts, (experiencer or difficulty or quantified) and "буде" or future[key])
            elseif tree.tense == "past" then
                local be = (experiencer or difficulty or quantified) and "було"
                    or pastCopula[number == "plural" and "plural" or gender]
                    or number == "singular" and pronoun and (pronoun.id == "i" or pronoun.id == "you") and "був/була"
                if not be then return nil end
                if tree.conditional then
                    be = be == "був/була" and "був би/була б"
                        or be .. (be == "був" and " би" or " б")
                end
                append(parts, be)
            elseif tree.wh and tree.wh.indirectPredicate then
                append(parts, "є")
            end
        end
        if tree.predicateModifier and not possessedState then
            local modifier = tree.predicateModifier
            append(parts, not english and tree.tense == "past" and modifier.pastUk
                or (english and modifier.en or modifier.uk)[1])
        end
        if tree.predicateAdverb and not (state or initialPhase) then
            local adverb = tree.predicateAdverb
            append(parts, not english and tree.prepositions and adverb.followLocation
                or quantified and fusedNegative or english and adverb.predicateEn or (english and adverb.en or adverb.uk)[1])
            if tree.evaluationContent then
                local content = render(tree.evaluationContent, english)
                if not content then return nil end
                if not english then parts[#parts] = withComma(parts[#parts]) end
                append(parts, english and "that" or "що")
                append(parts, content)
            end
            if adverb.impersonalTiming and tree.infinitive then
                local action = render(tree.infinitive, english, owner)
                if not action then return nil end
                if english then append(parts, "to") end
                append(parts, action)
            end
        end
        if tree.comparativeOffset then
            local offset = G.comparativeOffset(tree.comparativeOffset, english)
            if not offset then return nil end
            append(parts, offset)
        elseif tree.exhausted then
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
        elseif tree.predicatePossessive then
            local entry = tree.predicatePossessive
            local value
            if english then
                for predicate, determiner in pairs(ns.Linguistics.grammar.predicatePossessives) do
                    if determiner == entry.lexeme.en then value = predicate; break end
                end
            else
                value = possessiveText(entry, false, "nominative", number, gender, tree.subject.animacy, nil, true)
            end
            if not value then return nil end
            append(parts, value)
        elseif tree.predicativeRelative then
            local relative = tree.predicativeRelative
            local content = render(relative.clause, english)
            if not content then return nil end
            if english then
                if relative.total then append(parts, "all") end
            else
                if tree.tense == "present" and not tree.negative
                    and not (reference and (reference.deixis or reference.id == "it")) then append(parts, "—") end
                append(parts, relative.total and "все," or "те,")
            end
            append(parts, content)
        elseif tree.nominalContent then
            local content = render(tree.nominalContent.clause, english)
            if not content then return nil end
            if english then append(parts, "that")
            elseif tree.nominalContent.kind == "identity" then
                if tree.tense == "present" and not tree.negative then append(parts, "—") end
                append(parts, "те, що")
            else
                append(parts, "в тому, що")
            end
            append(parts, content)
        elseif tree.predicate then
            local frame = tree.predicate.entry and tree.predicate.entry.lexeme.frame
            local subjectFrame = tree.subject.entry and tree.subject.entry.lexeme.frame
            local case = not english and tree.tense ~= "present" and (
                frame and frame.nonpresentPredicateCase
                or (tree.conditional and not (demonstrative or pronoun and pronoun.id == "it")
                    or subjectFrame and subjectFrame.nominalContent == "identity") and "instrumental")
                or "nominative"
            if english and identity and tree.predicate.pronoun and not tree.predicate.pronoun.inanimate then
                case = "accusative"
            end
            local tail = tree.nominalPredicateTail
            local article = english and tail and not tree.predicate.article and not tree.predicate.adjectives and "definite" or true
            local value = G.noun(tree.predicate, english, case, article, nil, owner)
            if not value then return nil end
            local label = tree.subject.raw and tree.subject.raw:match("^<[^<>]+>$")
            if not english and not tree.omittedCopula and not tree.subject.pronoun
                and (tree.predicate.members or tree.subject.subset or tree.subject.numberLabel or tail or label
                    or frame and frame.nominalPredicateDash or tree.predicate.relative and tree.predicate.relative.preposition)
                and tree.tense == "present"
                and not tree.negative then append(parts, "—") end
            if tail then value = value .. (english and " " or ", ") .. (english and tail.en or tail.uk)[1] end
            append(parts, value)
        elseif tree.evaluation then
            local action = render(evaluation.action, english, owner)
            if not action then return nil end
            if evaluation.additive then append(parts, (english and evaluation.additive.en or evaluation.additive.uk)[1]) end
            append(parts, fusedNegative or (english and evaluation.rule.en or evaluation.rule.uk)[1])
            if english and difficulty then append(parts, "to") end
            append(parts, action)
        elseif measuredPredicate then
            if tree.measure then
                local amount = quantityText(tree.measure, true)
                if not amount then return nil end
                append(parts, amount)
            end
            append(parts, measuredPredicate)
        elseif tree.adjective then
            if not possessedState then
                local value = experiencer or agreedAdjective(tree.adjective, english, "nominative", tree.subject, number, gender)
                if not value then return nil end
                append(parts, value)
            end
            local separate = possessedState
            for _, member in ipairs(tree.adjectiveSeries or {}) do
                local frame = member.entry.lexeme.frame
                separate = separate or not english and frame and frame.ukPossessedState
                local following
                if separate then
                    following = render({kind="clause", copula=true, subject=tree.subject, tense=tree.tense,
                        adjective=member, predicateModifier=member.qualifier, negative=member.negative}, false)
                    parts[#parts] = withComma(parts[#parts])
                else
                    following = agreedAdjective(member, english, "nominative", tree.subject, number, gender)
                end
                if not following then return nil end
                append(parts, (english and member.join.en or member.join.uk)[1])
                if member.negative and not separate then append(parts, english and "not" or "не") end
                append(parts, following)
            end
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
                if english then
                    append(parts, tree.adjectiveActionMarker or "to")
                    if tree.adjectiveActionMarker and tree.infinitive.negative then append(parts, "not") end
                end
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
            local need = frame.impersonalNeed and tree.infinitive and not tree.modal
            if need and tree.subject then subject = G.noun(tree.subject, false, "dative") end
            if tree.aspect == "passive" then
                local pronoun = tree.subject.pronoun
                subject = pronoun and pronoun.id == "it" and "це" or G.noun(tree.subject, false, "accusative")
            end
            if not subject then return nil end
            append(parts, question)
            if tree.frontedPassivePatient then
                local case = tree.negative and frame.negativeObjectCase or frame.objectCase or "accusative"
                local patient = frame.objectPreposition
                    and ukrainianPrepositionalPronoun(tree.frontedPassivePatient, case, frame.objectPreposition)
                    or G.noun(tree.frontedPassivePatient, false, case, nil, nil, owner)
                if not patient then return nil end
                append(parts, euphonicZ(frame.objectPreposition, patient))
                append(parts, patient)
            end
            local postposed = tree.subject and not tree.subject.pronoun and (tree.longLive
                or tree.wh and tree.wh.kind == "clock" or frame.postposedSubject and tree.temporalDependent)
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
            and (english and (tree.recipientAfterObject or frame.enPostposedRecipient
                or not tree.object and frame.implicitTransferObject) or not english and not frame.ukPreposedRecipient
                and tree.recipientAfterObject)
        local recipient
        if not english and frame.selfBeneficiary and tree.recipient and tree.recipient.reflexive then append(parts, "собі") end
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
            local object = tree.object
            if not english and frame.genericObjects and object.article == "indefinite" and not object.relative
                and P.hasTrait(object, "genericPlural") then object = withNumber(object, "plural") end
            local value = not english and frame.objectPreposition
                and ukrainianPrepositionalPronoun(object, requested, frame.objectPreposition)
                or G.noun(object, english, requested, article, nil, owner)
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
            if tree.realizedObjectActions and not addObjectActions(parts, tree, owner) then return nil end
        elseif not (tree.wh and tree.wh.role == "object") then
            append(parts, english and postposeRecipient and frame.implicitTransferObject or english and frame.enImplicitObject
                or not english and (tree.relativeImplicitUk or tree.negative and frame.ukNegativeImplicitObject
                    or frame.ukImplicitObject or frame.omittedObjectUk))
        end
        if frame.selfChange then
            local emphasis = P.selfChangeEmphasis(tree.subject, english)
            if not emphasis then return nil end
            append(parts, emphasis)
        end
        if tree.agentEmphasis then append(parts, english and P.agentReflexive(tree.subject) or "самостійно") end
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
            if not english then append(parts, frame.ukInfinitiveMarker) end
            append(parts, value)
            if not addInfinitiveSeries(parts, tree.infinitive, english, owner) then return nil end
        end
        if tree.controlled then
            local control = tree.controlled
            local actor = G.noun(control.actor, english, english and "accusative" or frame.controlCase, true, nil, owner)
            local action = render(control.action, english, P.subjectPossessive(control.actor))
            if not actor or not action then return nil end
            append(parts, actor)
            if english and control.action.negative then append(parts, "not") end
            if english and frame.controlTo and not frame.bareInfinitive then append(parts, "to") end
            append(parts, action)
            if not addInfinitiveSeries(parts, control.action, english, P.subjectPossessive(control.actor)) then return nil end
        end
        if not english and frame.ukManner then append(parts, frame.ukManner) end
        if english and frame.enSubjectPossessiveComplement then
            if not owner then return nil end
            local complement = frame.enSubjectPossessiveComplement
            local _, number = agreement(tree, true)
            append(parts, complement.preposition .. " " .. owner .. " "
                .. (number == "plural" and complement.plural or complement.singular))
        end
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
                local value = render(embedded, english, P.subjectPossessive(tree.recipient) or owner)
                if not value then return nil end
                if index > 1 then append(parts, english and "and" or "і")
                elseif not english and frame.ukContentHead then append(parts, frame.ukContentHead .. ",")
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
    local preposedAdverb = english and "enBeforePrepositions" or "ukBeforePrepositions"
    if tree.prepositions and tree.adverbs then
        for _, adverb in ipairs(tree.adverbs) do
            if adverb[preposedAdverb] then
                if adverb.afterComma then parts[#parts] = withComma(parts[#parts]) end
                append(parts, (english and adverb.en or adverb.uk)[1])
            end
        end
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
        local rate = price.rate and G.noun(price.rate, english, "instrumental", "definite", nil, owner)
        if price.rate and not rate then return nil end
        if price.manner then
            parts[#parts] = withComma(parts[#parts])
            append(parts, (english and price.manner.en or price.manner.uk)[1])
            if not english then append(parts, "—") end
        end
        if not english and price.only then append(parts, "лише") end
        append(parts, english and (rate and "at" or "for") or "за")
        if english and price.only then append(parts, "only") end
        if rate then
            append(parts, english and price.amount and withComma(rate) or rate)
            if not english and price.amount then append(parts, "—") end
        end
        if price.amount then append(parts, english and price.amount.raw or ns.Engine.Grammar.moneyText(price.amount)) end
    end
    if not addPriceComparison(parts, tree, english, owner) then return nil end
    local span = tree.durationSpan
    if span then
        local value
        if span.expression then value = (english and span.expression.en or span.expression.uk)[1]
        elseif span.quantity then value = quantityText(span.quantity, english, "elapsed")
        else value = G.noun(span.noun, english, "accusative", true) end
        if not value then return nil end
        if english and not span.expression then append(parts, "for") end
        local modifier = tree.leadingAdverb or tree.predicateModifier or tree.predicateAdverb
        if not english and (tree.perfectProgressive or tree.perfectState)
            and not (modifier and modifier.en[1] == "already") then
            append(parts, "вже")
        end
        append(parts, value)
    end
    local measureMarker = english and verbFrame and verbFrame.measurePreposition or not english and "на"
    if tree.measure and measureMarker then
        local measure = tree.measure
        local amount = measure.nominalAmount and G.noun(measure.nominalAmount, english, "accusative")
        if not measure.nominalAmount then amount = quantityText(measure, english) end
        if amount and measure.amountScale then
            local scale = G.noun(measure.amountScale, english, "genitive")
            amount = scale and amount .. (english and " of " or " ") .. scale
        end
        if not amount then return nil end
        append(parts, measureMarker .. " " .. amount)
        if not english and verbFrame then append(parts, verbFrame.ukMeasureSuffix) end
    end
    for _, adverb in ipairs(tree.adverbs or {}) do
        if not (tree.prepositions and adverb[preposedAdverb]) then
            if adverb.afterComma then parts[#parts] = withComma(parts[#parts]) end
            append(parts, (english and adverb.en or adverb.uk)[1])
        end
    end
    if english and tree.leadingAdverb and tree.leadingAdverb.postposedEn then
        append(parts, tree.leadingAdverb.en[1])
    end
    if english then
        for _, modifier in ipairs(tree.additionalLeadingAdverbs or {}) do
            if modifier.postposedEn then append(parts, modifier.en[1]) end
        end
    end
    if tree.scheduleTime then
        local time = (english and tree.scheduleTime.en or tree.scheduleTime.uk)[1]
        append(parts, (english and "for " or "на ") .. time)
    end
    if tree.calendar then
        local days = tree.calendar.members or {tree.calendar}
        local names = {}
        for i, item in ipairs(days) do
            local day, phase, repeated = item.day, item.phase, item.repeated
            local name
            if english then
                name = (i == 1 and "on " or "") .. day.name
                if phase then name = name .. " " .. phase.en[repeated and 2 or 1]
                elseif repeated then name = name .. "s" end
            else
                name = repeated and day.uk[2] or i > 1 and not days[i - 1].repeated and day.uk[1] or day.onUk
                if phase then name = name .. " " .. phase.uk[1] end
            end
            names[i] = name
        end
        if #names > 1 then
            local last = table.remove(names)
            append(parts, table.concat(names, ", ") .. (english and " and " or " і ") .. last)
        else
            append(parts, names[1])
        end
    end
    if tree.clockRange then
        local range = tree.clockRange
        local time = range.ending and ((english and "from " or "з ") .. range.start
            .. (english and " to " or " до ") .. range.ending)
            or ((english and "at " or range.start:match("^11:") and "об " or "о ") .. range.start)
        append(parts, range.zone and time .. " " .. range.zone or time)
    end
    if tree.scheduleLocation then
        local location, marker = G.preposition(tree.scheduleLocation, english, owner)
        if not location then return nil end
        append(parts, marker)
        append(parts, location)
    end
    if tree.delay then
        if tree.delay.soon then append(parts, english and "soon" or "незабаром")
        else
            local value = quantityText(tree.delay, english, "delay")
            if not value then return nil end
            if not english and tree.delay.approximate then append(parts, "приблизно") end
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
    if not addPurpose(parts, tree.purpose, english, owner) then return nil end
    if tree.apposition then
        local description = G.noun(tree.apposition, english, "nominative")
        if not description then return nil end
        append(parts, "—")
        append(parts, description)
    end
    if tree.addressee then
        local address = G.address(tree.addressee, english)
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

local subordinateConnectors = {because=true, ["if"]=true, ["in-case"]=true, unless=true, when=true, whenever=true,
    ["while"]=true, exception=true}

function G.render(parse, direction, punctuation)
    local english = direction == "uk-en"
    local first = parse.trees[1]
    local rating = parse.rating
    local prefix
    if rating then
        local label = (english and rating.label.en or rating.label.uk)[1]
        local text = english and rating.label.valueFirstEn and rating.value .. " " .. label
            or ns.Engine.Normalize.upperStart(label) .. " " .. rating.value
        prefix = (rating.opening or "") .. text .. (rating.closing or "")
        if first.kind == "ratingNote" then return prefix .. (punctuation or "") end
    end
    if first.kind == "menuPath" then
        local parts = {}
        for i, label in ipairs(first.labels) do
            append(parts, (english and label.en or label.uk)[1])
            append(parts, first.separators[i])
        end
        return (prefix and prefix .. " " or "") .. table.concat(parts) .. (punctuation or "")
    end
    local parts, last = {}, nil
    if parse.exclamation then append(parts, english and "what" or "оце так") end
    if parse.leadingAddress then
        local address = G.address(parse.leadingAddress, english)
        if not address then return nil end
        append(parts, withComma(address))
    end
    local comment = parse.speakerComment and (english and parse.speakerComment.en or parse.speakerComment.uk)[1]
    local commentFirst = parse.speakerCommentFirst and (not english or parse.speakerComment.preserveLeading)
    if comment and commentFirst then append(parts, withComma(comment)) end
    if parse.openingPastOffset then
        local value = pastOffsetText(parse.openingPastOffset, english)
        if not value then return nil end
        append(parts, parse.openingPastOffset.comma and withComma(value) or value)
    end
    if parse.openingPrepositions then
        if not addPrepositions(parts, {prepositions=parse.openingPrepositions}, english) then return nil end
        if english or parse.openingPrepositionComma then parts[#parts] = withComma(parts[#parts]) end
    end
    if english and punctuation == "?" and not parse.hypothetical then
        local question = parse.trees[#parse.trees]
        for i = #parse.trees, 1, -1 do
            local tree, join = parse.trees[i], parse.joins[i - 1]
            if tree.question then question = tree; break end
            if not join or join.sentence then break end
            local rule = join.rule
            if question == tree and (tree.omittedCopula or rule and (rule.temporal or subordinateConnectors[rule.id])) then
                question = parse.trees[i - 1]
            end
        end
        if question.kind == "clause" and not question.imperative then question.question = true end
    end
    if parse.politeness then
        append(parts, english and parse.politeness.en[1] or withComma(parse.politeness.uk[1]))
    end
    if parse.hypothetical then
        local opening = (english and parse.hypothetical.en or parse.hypothetical.uk)[1]
        if parse.hypotheticalContrast then append(parts, english and "But" or "А") end
        append(parts, opening)
    end
    if parse.discoursePrefix then append(parts, (english and parse.discoursePrefix.en or parse.discoursePrefix.uk)[1]) end
    if parse.prefix then append(parts, (english and parse.prefix.en or parse.prefix.uk)[1]) end
    for i, tree in ipairs(parse.trees) do
        local join = parse.joins[i - 1]
        local purpose = join and join.purposeObligation
        local hypotheticalFuture = english and parse.hypothetical and tree.tense == "future"
        if purpose or hypotheticalFuture then
            local subordinate = {}
            for key, value in pairs(tree) do subordinate[key] = value end
            subordinate.tense = purpose and (not english or parse.trees[i - 1].tense == "past") and "past" or "present"
            tree = subordinate
        end
        local value = render(tree, english)
        if not value or value == "" then return nil end
        if tree.sentenceAdverb then
            local modifier = tree.sentenceAdverb
            local word = (english and modifier.en or modifier.uk)[1]
            local comma = modifier.sentenceInitialComma or not english and modifier.sentenceInitialCommaUk
            value = (comma and withComma(word) or word) .. " " .. value
        end
        if tree.leadingLabel then value = tree.leadingLabel .. " " .. ns.Engine.Normalize.upperStart(value) end
        if join and join.sentence then
            parts[#parts] = parts[#parts] .. (join.punctuation or ".")
            value = ns.Engine.Normalize.upperStart(value)
        elseif join then
            local id = join.rule and join.rule.id
            local trailingSubordinate = id == "if" or id == "when" or id == "while"
            local previous = parse.trees[i - 1]
            local independent = not (english or parse.prefix or parse.hypothetical or previous.sentenceAdverb
                or previous.question or tree.question)
                and (id == "and" or id == "or") and previous.kind == "clause" and tree.kind == "clause"
                and previous.subject and tree.subject and not (previous.implicitSubject or tree.implicitSubject or tree.inherited)
            local comma = join.comma and not (english and trailingSubordinate)
                or (join.rule and join.rule.temporal and not join.rule.nominalHead and not english)
                or id == "but" or id == "because" or not english and trailingSubordinate or id == "whenever"
                or id == "unless" or id == "so" or id == "exception"
                or not english and (id == "and" or id == "or") and tree.kind == "benefit"
                or not english and (id == "and" or id == "or") and tree.inherited and tree.passiveAgent
                or independent
                or not english and (id == "and" or id == "or") and previous.perception and tree.subject and not tree.inherited
            if join.dash then append(parts, "—")
            elseif purpose and not english or comma and not purpose then parts[#parts] = withComma(parts[#parts]) end
            if purpose then append(parts, english and "so that" or "щоб")
            elseif join.locativeContrast then append(parts, english and "but" or "а")
            elseif join.rule then
                local status = not english and previous.predicateAdverb and previous.predicateAdverb.statePredicate
                append(parts, status and join.rule.ukStatus or (english and join.rule.en or join.rule.uk)[1])
            end
        end
        append(parts, value)
        last = tree
    end
    if parse.questionTail then
        if parse.questionTailComma then parts[#parts] = withComma(parts[#parts]) end
        append(parts, (english and parse.questionTail.en or parse.questionTail.uk)[1])
    end
    if comment and not commentFirst then
        parts[#parts] = withComma(parts[#parts])
        append(parts, comment)
    end
    return (prefix and prefix .. " " or "") .. ns.Engine.Normalize.upperStart(table.concat(parts, " "))
        .. ((last.question or parse.hypothetical) and "?" or punctuation
            or ((parse.exclamation or last.kind == "levelAnnouncement") and "!" or "."))
end
