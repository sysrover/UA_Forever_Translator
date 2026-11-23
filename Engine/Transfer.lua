local _, ns = ...
local T = {}; ns.Engine.Transfer = T
local G, M = ns.Engine.Grammar, ns.Engine.Morphology

local gratuities = {
    appreciated={uk=". Буду вдячний за чайові", en=". Tips are appreciated"},
    appreciatedOptional={uk=". Чайові вітаються, але вони необов’язкові", en=". Tips are welcome but not required"},
    accepted={uk=". Приймаю чайові", en=". Tips accepted"},
    with={uk=" з чайовими", en=" with tips"},
}

local function servicePlace(place, uk)
    local generation = ns.Engine.ClauseGeneration
    local value, marker
    if place.accessSteps then
        value = generation.noun(place.object, not uk, uk and "genitive" or "nominative")
        if value and not uk then value = "the " .. value .. " steps" end
        marker = uk and "біля сходів" or "at"
    else
        value, marker = generation.preposition(place, not uk)
        if not uk and place.rule.id == "out-of-location" then marker = "outside" end
    end
    if value and marker then return marker .. " " .. value end
end

local function remainingStock(stock, uk)
    if not stock then return "" end
    return uk and ". Залишилося " .. stock.raw or ". " .. stock.raw .. " left"
end

local function serviceTerms(output, features, uk, stock)
    local tips = gratuities[features.tips]
    if tips then output = output .. (uk and tips.uk or tips.en) end
    for index, place in ipairs(features.places or {}) do
        local value = servicePlace(place, uk)
        if not value then return end
        local join = index == 1 and " " or ", "
        if features.compactFree and index == 1 then join = uk and ". Я " or ". I'm " end
        output = output .. join .. value
    end
    return output .. remainingStock(stock, uk) .. ((uk or features.compactFree) and "." or "")
end

local function practitionerLabel(term, uk, nominative)
    if not uk then return term.englishPractitioner end
    local forms = term.renderForms
    return forms and forms[nominative and "practitionerNominative" or "practitioner"]
end

local function lockLinks(links, uk)
    if #links < 2 then return links[1] or "" end
    return table.concat(links, ", ", 1, #links - 1) .. (uk and " і " or " and ") .. links[#links]
end

local function lockOffer(slots, features, uk)
    local entry = features.object and features.object.entry
    local chest = entry and entry.lexeme.en == "chest"
    local object = features.links and lockLinks(features.links, uk)
        or ns.Engine.ClauseGeneration.noun(features.object, not uk, "accusative", not uk and not chest)
    if not object then return end
    if chest then
        local plural = features.object.number == "plural"
        local locked = uk and (plural and "замкнені " or "замкнену ") or (plural and "locked " or "a locked ")
        object = locked .. object
    end
    local lead
    if features.provider then
        local plural = slots.actor.plural
        if uk then lead = plural and "Розбійники шукають, кому відкрити " or "Розбійник шукає, кому відкрити "
        else lead = plural and "Rogues LF opening " or "Rogue LF opening " end
    elseif uk then lead = features.ability and "Можу відкрити " or "Відмикаю "
    else lead = features.ability and "I can open " or "Opening " end
    local text = lead .. object
    if features.place then
        local where = servicePlace(features.place, uk)
        if not where then return end
        text = text .. " " .. where
    end
    if features.skill then text = text .. (uk and ". Навичка " or ". Skill ") .. features.skill end
    local tips = gratuities[features.tips]
    if tips then text = text .. (uk and tips.uk or tips.en) end
    return text .. "."
end

local function lockRequest(slots, features, uk, direction)
    local location = ""
    if features.location then
        local value, marker = ns.Engine.ClauseGeneration.preposition(features.location, not uk)
        if not value or not marker then return end
        location = " " .. marker .. " " .. value
    end
    local linkList = features.links or {}
    local links = lockLinks(linkList, uk)
    local actor, plural = slots.actor, slots.actor and slots.actor.plural
    local role
    if actor then
        local form = uk and (features.request == "search" and (plural and "genitivePlural" or "genitiveSingular")
            or plural and "nominativePlural" or "canonical") or nil
        role = not uk and plural and actor.term.englishPlural or M.generate(actor.term, direction, form)
        if not role then return end
        role = ns.Engine.Normalize.word(role)
    end

    local lead, action
    local pick = features.action == "pick" or features.kind == "lockpicker"
    if uk then
        action = pick and (features.kind and "зламає замок" or "зламати замок") or "відкрити"
        if features.kind then
            lead = "Шукаю, хто" .. location .. " "
        elseif features.anyone then
            lead = features.willing and "Хтось згоден " or "Хтось може "
        elseif features.request == "search" then
            local qualification = features.willing and (plural and ", які готові " or ", який готовий ")
                or (features.ability or pick) and (plural and ", які можуть " or ", який може ") or ", щоб "
            lead = "Шукаю " .. role .. location .. qualification
        else
            local ability = features.willing and (plural and "готові" or "готовий") or (plural and "можуть" or "може")
            lead = (features.fronted and "є " or "Чи є ") .. role .. location
                .. (plural and ", які " or ", який ") .. ability .. " "
        end
        if features.recipient then action = action .. " мені" end
    else
        action = pick and "pick the lock" or "open"
        if features.kind then lead = "LF lockpicker" .. location .. " to "
        elseif features.anyone then lead = features.willing and "Anyone want to " or "Can anyone "
        elseif features.request == "search" then
            lead = "LF " .. role .. location
                .. (features.willing and " willing to " or features.ability and " who can " or " to ")
        else lead = "Any " .. role .. location .. (features.willing and " willing to " or " who can ") end
    end
    local value = lead .. action
    if features.fronted then
        value = links .. " — " .. value
        if uk and features.request == "search" then value = value .. (#linkList == 1 and " скриньку" or " скриньки") end
    elseif links ~= "" then
        local marker = pick and (uk and " на " or " on ") or " "
        value = value .. marker .. (features.amount and features.amount .. " " or "") .. links
    end
    if features.recipient and not uk then value = value .. " for me" end
    if features.please then value = value .. (uk and ", будь ласка" or ", please") end
    if features.skill then
        value = value .. (uk and " (навичка " .. features.skill .. ")" or " requiring skill " .. features.skill)
    end
    return value .. (features.request == "question" and "?" or ".")
end

local function practitionerRequest(term, uk, article)
    local profession = practitionerLabel(term, uk)
    if not profession then return nil end
    if uk then return "Шукаю " .. profession end
    local determiner = article and (profession:match("^[AEIOUaeiou]") and "an " or "a ") or ""
    return "Looking for " .. determiner .. profession
end

local function recipeLabel(entry, direction)
    if entry.raw then return entry.raw end
    local forms = entry.term.renderForms
    return forms and forms[direction == "en-uk" and "serviceUk" or "serviceEn"] or M.generate(entry.term, direction)
end

local function enchantmentList(slots, features, direction)
    local uk = direction == "en-uk"
    local parts = {}
    for index, item in ipairs(features.items) do
        local value
        if item.kind == "recipe" then
            value = recipeLabel(slots[item.slot], direction)
            if value and uk then value = "«" .. value .. "»" end
        elseif item.kind == "slot" then
            local term = slots[item.slot].term
            local label = M.generate(term, direction, uk and "accusative" or nil)
            if label then
                if uk then value = "зачарування на " .. label
                elseif term.features.number == "plural" then value = "enchants for " .. label
                else value = ns.Engine.Normalize.word(label) .. " enchants" end
                if item.stats then
                    local stats = {}
                    for _, stat in ipairs(item.stats) do
                        local name = M.generate(slots[stat].term, direction)
                        if not name then return nil end
                        stats[#stats + 1] = ns.Engine.Normalize.word(name)
                    end
                    local attributes = table.concat(stats, "/")
                    value = uk and value .. " (" .. attributes .. ")" or attributes .. " " .. value
                end
            end
        else
            local amount = item.noun
            local additive = uk and index > 1 and amount.more and not amount.evenMore
            local marker
            if additive then
                local nominal = {}
                for key, feature in pairs(amount) do nominal[key] = feature end
                nominal.many, nominal.more, nominal.degreeMore = amount.degreeMore, nil, nil
                marker = amount.degreeMore and "ще " or "інші "
                amount = nominal
            end
            value = ns.Engine.ClauseGeneration.noun(amount, not uk, "nominative")
            if marker and value then value = marker .. value end
        end
        if not value then return nil end
        local join = features.joins[index]
        if join == "comma" then parts[#parts + 1] = ", "
        elseif join then parts[#parts + 1] = join == "or" and (uk and " або " or " or ")
            or (uk and " та " or " and ") end
        parts[#parts + 1] = value
    end
    local list = table.concat(parts)
    local available = features.status == "available"
    if uk then list = (available and "Доступні " or "Недоступні ") .. list
    else list = ns.Engine.Normalize.upperStart(list) .. (available and " are available" or " are not available") end
    return list .. (features.exclamation and "!" or ".")
end

local function groupRoster(slots, features, uk)
    local parts = {}
    for index, member in ipairs(features.members) do
        local slot = slots[member.slot]
        local term = slot.term
        local grammatical = slot.analysis and slot.analysis.features or term.features or {}
        local noun = {term=term, gender=grammatical.gender, animacy=grammatical.animacy,
            number=slot.plural and "plural" or grammatical.number or "singular", quantity=member.quantity}
        local common = not term.en:match("^[A-Z]+$")
        local value = ns.Engine.ClauseGeneration.noun(noun, not uk, "nominative", not uk, nil, nil, common)
        if not value then return nil end
        if index > 1 then parts[#parts + 1] = index < #features.members and ", " or (uk and " і " or " and ") end
        parts[#parts + 1] = value
    end
    local list = table.concat(parts)
    if features.ready then
        local status = uk and (features.ready == "toGo" and " готові вирушати." or " готові.")
            or (features.ready == "toGo" and " are ready to go." or " are ready.")
        return ns.Engine.Normalize.upperStart(list) .. status
    end
    local opening = uk and (features.already and "У нас уже є " or "У нас ")
        or (features.already and "We already have " or "We have ")
    return opening .. list .. "."
end

local function recruitmentJoin(join, uk)
    if join == "comma" then return ", " end
    if uk then return join == "and" and " і " or " або " end
    return " " .. join .. " "
end

function T.render(tree, direction)
    local s, f, uk = tree.slots, tree.features, direction == "en-uk"
    local function render(template) return G.render(template, s, direction) end
    if tree.kind == "lockRequest" then return lockRequest(s, f, uk, direction)
    elseif tree.kind == "lockOffer" then return lockOffer(s, f, uk)
    elseif tree.kind == "recruit" then
        local output
        local total = s.total and s.total.raw
        local writtenRoleCount = s.role and s.count and s.count.spelled
        if not writtenRoleCount and f.roleJoins then
            for index = 2, #f.roleJoins + 1 do
                local count = s["count" .. index]
                if count and count.spelled then writtenRoleCount = true; break end
            end
        end
        local contextualPlace, quickDestination
        if uk and f.destinationRoles and s.place and not f.wingJoins and not writtenRoleCount then
            local features = s.place.term.features
            if f.pace and features and features.clearableInstance then
                local format = s.place.plural and "{place:genitivePlural}" or "{place:genitiveSingular}"
                quickDestination = render(" на швидке проходження " .. format)
            end
            contextualPlace = quickDestination or render(" у {place:object}")
            if not contextualPlace and f.needsRoles and ns.Linguistics then
                local place = ns.Engine.Lexicon.curatedForm(s.place.term, "accusative", s.place.plural and "plural" or "singular")
                if place then contextualPlace = " у " .. ns.Engine.Normalize.upperStart(place) end
            end
        end
        local function totalPlayers(amount)
            local form = G.numberForm(amount) == "genitiveSingular" and "гравця" or "гравців"
            return "Шукаємо ще " .. amount .. " " .. form
        end
        local function appendLevel(value)
            if not s.level then return value end
            return value .. (uk and ". Рівень: " or " L") .. s.level.raw .. (s.level.minimum and "+" or "")
        end
        local function destinationText(format)
            local first = render(format)
            if not first or not f.wingJoins then return first end
            local parts = {first}
            for i, join in ipairs(f.wingJoins) do
                local wing = G.render(format, {place=s["place" .. (i + 1)]}, direction)
                if not wing then return end
                parts[#parts + 1] = join == "then" and (uk and ", потім " or ", then ") or recruitmentJoin(join, uk)
                parts[#parts + 1] = wing
            end
            return table.concat(parts)
        end
        local function appendPlace(value, afterSentence)
            if not s.place then return value end
            if not uk then return value .. (f.destinationRun and " to run " or " for ") .. destinationText("{place}") end
            if contextualPlace then
                return value:gsub("%.$", "") .. contextualPlace .. (afterSentence and "." or "")
            end
            if f.destinationRun or f.fillsGroup or f.roleNeeded or writtenRoleCount then
                local format = s.place.plural and "{place:genitivePlural}" or "{place:genitiveSingular}"
                local destination = destinationText(format)
                if f.destinationRun or destination then
                    local preposition = f.destinationRun and " для проходження " or " до "
                    return value:gsub("%.$", "") .. preposition .. (destination or destinationText("{place}"))
                        .. (afterSentence and "." or "")
                end
            end
            return value .. (afterSentence and " " or ". ") .. (f.wingJoins and "Місця: " or "Місце: ")
                .. destinationText("{place}") .. (afterSentence and "." or "")
        end
        local function appendConditions(value)
            if f.quests then
                value = value .. (uk and " на завдання " or " for ") .. table.concat(f.quests, ", ")
            end
            if s.preferred then
                local class = G.render(uk and "{class:genitiveSingular}" or "{class}", {class=s.preferred}, direction)
                if not class then return nil end
                value = value .. (uk and ". Бажано " .. class or ", preferably " .. class:lower())
            end
            if s.excluded then
                local form = s.excluded.plural and "{excluded:genitivePlural}" or "{excluded:genitiveSingular}"
                local excluded = render(uk and form or "{excluded}")
                if not excluded then return nil end
                value = value .. (uk and ". Без " or ", no ") .. excluded
            end
            if f.run == "full" then value = value .. (uk and ". Повне проходження" or ", full run")
            elseif f.run == "fresh" then value = value .. (uk and ". Проходження з початку" or ", fresh run")
            elseif f.run == "quest" then value = value .. (uk and ". Проходження із завданнями" or ", quest run") end
            if f.pace and not quickDestination then value = value .. (uk and ". Швидке проходження" or ", fast run") end
            if f.clear then value = value .. (uk and ". Повна зачистка" or ", full clear") end
            if f.ready == "afterFill" then
                value = value .. (uk and ". Після цього можемо вирушати" or ", then we're ready to go")
            elseif f.ready then value = value .. (uk and ". Готові вирушати" or ". Ready to go") end
            if f.urgent then value = value .. (uk and ". Терміново" or ", quick") end
            if f.summon then value = value .. (uk and ". Можемо прикликати" or ", can summon") end
            if f.go then value = value .. (uk and ". І вирушаємо" or " and go") end
            if f.fillsGroup then
                value = value .. (uk and ". Після цього група буде повна" or ", then the group will be full")
            end
            if f.roster then
                local roster = groupRoster(s, f.roster, uk)
                return roster and value .. (f.question and "? " or ". ") .. roster
            end
            return value .. (f.question and "?" or uk and "." or "")
        end
        if f.classJoins then
            local classes = {}
            for index = 1, #f.classJoins + 1 do
                local slot = s["class" .. index]
                local class = G.render(uk and "{class:genitiveSingular}" or "{class}",
                    {class=slot}, direction)
                if not class then return nil end
                local join = f.classJoins[index - 1]
                if join then
                    classes[#classes + 1] = recruitmentJoin(join, uk)
                end
                classes[#classes + 1] = (uk or slot.term.category == "roles") and class or class:lower()
            end
            local amount = total or (s.count and s.count.raw)
            if uk then output = amount and totalPlayers(amount) .. ": " or "Шукаємо "
            else output = amount and "LF" .. amount .. "M " or "LFM " end
            local role = s.role and render(uk and "{role:genitiveSingular}" or "{role}")
            if s.role and not role then return nil end
            if f.refinements then
                output = output .. role .. ": " .. table.concat(classes)
            else
                output = output .. table.concat(classes)
            end
            if role and not f.refinements then
                output = output .. (uk and " на роль " or " ") .. role
            end
            output = appendLevel(output)
            output = appendPlace(output)
            if f.lastSpot then output = output .. (uk and ". Залишилося одне місце" or ", last spot") end
            return appendConditions(output)
        end
        if f.roleJoins and #f.roleJoins > 0 then
            local roles = {}
            for n = 1, #f.roleJoins + 1 do
                local suffix = n == 1 and "" or tostring(n)
                local values = {role=s["role" .. suffix], count=s["count" .. suffix]}
                local value
                local additional = n == 1 and f.additional and values.count and not total
                if uk and f.needsRoles then
                    local term = values.role.term
                    local amount = values.count and values.count.raw
                    local case, number = "nominative", values.role.plural and "plural" or "singular"
                    if amount then case, number = ns.Engine.Phrases.countedCase(amount, case, false) end
                    local label = term.uk
                    if not label:match("^[A-Z%d]+$") then
                        label = ns.Engine.Lexicon.curatedForm(term, case, number)
                        if not label then return nil end
                        label = ns.Engine.Normalize.word(label)
                    end
                    value = amount and G.roleQuantity(values.count, term) .. " " .. label or label
                else
                    local format = values.count and (uk and "{count:roleQuantity} {role:counted}"
                        or additional and "{count} more {role}" or "{count} {role}")
                        or (uk and "{role:genitiveSingular}" or "{role}")
                    value = G.render(format, values, direction)
                    if not value then return nil end
                end
                if uk and additional then value = "ще " .. value end
                local join = f.roleJoins[n - 1]
                if join then
                    roles[#roles + 1] = recruitmentJoin(join, uk)
                end
                roles[#roles + 1] = value
            end
            local prefix
            if contextualPlace and total then prefix = appendPlace(totalPlayers(total)) .. ": "
            elseif uk and f.needsRoles then prefix = "Потрібні "
            elseif uk then prefix = total and totalPlayers(total) .. ": " or "Шукаємо "
            else prefix = total and "LF" .. total .. "M " or "Looking for " end
            output = appendLevel(prefix .. table.concat(roles))
            if not (contextualPlace and total) then output = appendPlace(output) end
            if f.lastSpot then output = output .. (uk and ". Залишилося одне місце" or ", last spot") end
            return appendConditions(output)
        end
        if uk then
            local requested = s.count or s.total
            if f.lastSpot and not f.destinationRun and s.role and s.place and not s.level and not (s.count and s.total) and (not requested
                or requested.raw == "1") then
                local amount = requested and not requested.spelled and (s.total and "ще {total} " or "{count} ") or ""
                output = render("Шукаємо " .. amount .. "{role:genitiveSingular} — {place}. Залишилося одне місце.")
                if output then return appendConditions((output:gsub("%.$", ""))) end
                return nil
            end
            if s.role then
                if contextualPlace and total then
                    local role = render(s.count and "{count:roleQuantity} {role:counted}" or "{role:genitiveSingular}")
                    if not role then return end
                    output = appendPlace(totalPlayers(total)) .. ": " .. role .. "."
                elseif total and s.count then
                    local role = render("{count:roleQuantity} {role:counted}")
                    if not role then return end
                    output = totalPlayers(total) .. ": " .. role .. "."
                elseif total then
                    output = render("Набір у групу: ще {total}; роль: {role}.")
                elseif s.count then
                    output = render(f.additional and "Шукаємо ще {count:roleQuantity} {role:counted}."
                        or "Шукаємо {count:roleQuantity} {role:counted}.")
                else output = render("Шукаємо {role:genitiveSingular}.") end
            elseif total or s.count then
                output = totalPlayers(total or s.count.raw) .. "."
            else output = "Шукаємо гравців."
            end
            if not output then return end
            if s.level then output = appendLevel((output:gsub("%.$", ""))) .. "." end
            if not (contextualPlace and total and s.role) then output = appendPlace(output, true) end
            if f.lastSpot then output = output .. " Залишилося одне місце." end
        else
            output = total and "LF" .. total .. "M" or s.count and render("LF{count}M") or "LFM"
            if s.role then
                output = output .. " " .. render(total and s.count and "{count} {role}" or "{role}")
            end
            output = appendLevel(output)
            output = appendPlace(output)
            if f.lastSpot then output = output .. ", last spot" end
        end
        return appendConditions((output:gsub("%.$", "")))
    elseif tree.kind == "groupRoster" then
        return groupRoster(s, f, uk)
    elseif tree.kind == "groupVacancy" then
        if f.counted then
            local raw = s.vacancies and s.vacancies.raw or "1"
            if not uk then
                local amount = f.writtenOne and "One" or raw
                local unit = tonumber(raw) == 1 and " spot" or " spots"
                return amount .. unit .. " left for " .. render("{place}") .. "."
            end
            local form = s.place.plural and "{place:genitivePlural}" or "{place:genitiveSingular}"
            local place = render(form)
            local case, number = ns.Engine.Phrases.countedCase(raw, "nominative", false)
            local unit = ns.Engine.Lexicon.inflectLemma("місце", "noun", {case=case, number=number})
            if not place or not unit then return nil end
            local amount = f.writtenOne and "одне" or raw
            return "Залишилося " .. amount .. " " .. unit .. " у групі до " .. place .. "."
        end
        local output = uk and (f.identity and "Це останнє місце" or "Залишилося одне місце")
            or (f.identity and "This is the last spot" or "Last spot")
        if s.place then
            local place = M.generate(s.place.term, direction, uk and (f.destination and "accusative" or "locative") or nil)
            if not place then return nil end
            local marker = uk and (f.destination and " на " or " в ") or (f.destination and " for " or " in ")
            output = output .. marker .. place
        end
        return output .. "."
    elseif tree.kind == "groupSearch" then
        if not uk and s.role and not s.place and not f.quests and not f.objective and not f.roleOffer then
            return render("{role} LFG")
        end
        local output = uk and "Шукаю групу" or "LFG"
        if s.place then output = output .. render(uk and ". Місце: {place}" or " {place}") end
        if f.quests or f.objective then
            local objective = f.quests and ((uk and "завдання " or "") .. table.concat(f.quests, ", "))
                or ns.Engine.ClauseGeneration.noun(f.objective, not uk, "accusative")
            if not objective then return nil end
            output = output .. (uk and (s.place and ". На " or " на ") or " for ") .. objective
        end
        if s.role then output = output .. render(uk and ". Роль: {role}" or " as {role}") end
        if f.roleOffer then
            local offer = f.roleOffer
            local opening = uk and (offer.negative and ". Не можу грати за " or ". Можу грати за ")
                or (offer.negative and ". I cannot play as " or ". I can play as ")
            local parts = {output, opening}
            for index, role in ipairs(offer.roles) do
                local term = role.term
                local join = offer.joins[index - 1]
                if join then parts[#parts + 1] = recruitmentJoin(join, uk) end
                local common = not term.en:match("^[A-Z]+$")
                local noun = {term=term, number="singular", gender=role.features.gender, animacy=role.features.animacy}
                local value = ns.Engine.ClauseGeneration.noun(noun, not uk, uk and "accusative" or "nominative",
                    not uk and common, nil, nil, common)
                if not value then return nil end
                parts[#parts + 1] = value
            end
            return table.concat(parts) .. "."
        end
        return output .. (uk and "." or "")
    elseif tree.kind == "search" then
        return ns.Engine.ClauseGeneration.search(f.object, f.purpose, not uk, f.group, f.emphatic)
    elseif tree.kind == "linkedSale" then
        local values = {uk and "Продам " or "WTS "}
        for index, offer in ipairs(f.offers) do
            if index > 1 then values[#values + 1] = uk and ", а " or "; and " end
            local value = offer.link
            if offer.amount then
                local marker = uk and (index == 1 and " за " or " — за ") or " for "
                value = value .. marker .. G.offerPriceText(offer.amount, not uk)
            end
            if offer.basis then value = value .. " " .. G.priceBasisText(offer.basis, not uk) end
            if offer.materials then value = value .. (uk and ", матеріали мої" or " (my mats)") end
            if offer.comparison then
                local separator = offer.amount and (uk and ", " or " - ") or " "
                local discount = offer.discount and G.offerPriceText(offer.discount, not uk)
                if discount then separator = separator .. (uk and "на " or "") .. discount .. " " end
                if offer.comparison == "emphatic" then separator = separator .. (uk and "набагато " or "much ") end
                value = value .. separator .. (uk and "дешевше, ніж на аукціоні" or "cheaper than the auction house")
            end
            values[#values + 1] = value
        end
        return table.concat(values) .. remainingStock(s.stock, uk) .. "."
    elseif tree.kind == "freeOffer" then
        local value = f.object and ns.Engine.ClauseGeneration.noun(f.object, not uk, "nominative")
            or s.item and s.item.raw
        if not value then return end
        if f.stockLimited then
            if uk then return value .. " безкоштовно, поки є запаси!" end
            return "Free " .. value .. " while supplies last!"
        end
        if f.recipient then
            local recipient, marker = ns.Engine.ClauseGeneration.preposition(f.recipient, not uk)
            if not recipient then return end
            value = value .. " " .. marker .. " " .. recipient
        end
        return (uk and "Безкоштовно: " or "Free: ") .. value .. (f.punctuation or "")
    elseif tree.kind == "price" then
        local amount = render(uk and (f.introduced and "{price:money}" or "{price:moneyNominative}") or "{price}")
        local only = f.linked and (uk and "лише " or "only ") or (uk and "Лише " or "Only ")
        local value = (f.only and only or "") .. amount
        if f.linked then
            value = s.item.raw .. (f.introduced and (uk and " за " or " for ") or " — ") .. value
        end
        if f.each then
            value = value .. " " .. G.priceBasisText(f.each, not uk)
        end
        return value
    elseif tree.kind == "roleInquiry" then
        local plural = s.role.plural
        local role = render(uk and plural and "{role:nominativePlural}" or "{role}")
        local place = f.name or (uk and render("{place:accusative}")) or render("{place}")
        if not role or not place then return nil end
        local normalize = ns.Engine.Normalize
        if not s.role.term.en:match("^[A-Z]+$") then role = normalize.word(role) end
        local lead = f.explicit and (uk and "Чи є " or plural and "Are there " or "Any ") or ""
        local marker = uk and (f.unresolved and " для " or " на ") or " for "
        local here = f.here and (uk and " тут" or " here") or ""
        return normalize.upperStart(lead .. role .. marker .. place .. here)
    elseif tree.kind == "availability" then
        local case = f.search and "accusative" or "nominative"
        local profession = ns.Engine.ClauseGeneration.noun(f.occupation, not uk, case)
        if not profession then return end
        local places = {online={"онлайн","online"}, ["онлайн"]={"онлайн","online"},
            around={"поблизу","around"}, ["поблизу"]={"поблизу","around"}, here={"тут","here"}, ["тут"]={"тут","here"}}
        local place = f.place and " " .. places[f.place][uk and 1 or 2] or ""
        local skill = s.skill.raw .. "+"
        if uk then
            local lead = f.search and "Шукаю " or "Чи є "
            return lead .. profession .. " із навичкою " .. skill .. place .. (f.search and "." or "")
        end
        if f.search then return "LF " .. profession .. " with " .. skill .. " skill" .. place end
        return "Any " .. skill .. " " .. profession .. place
    elseif tree.kind == "enchantmentList" then
        return enchantmentList(s, f, direction)
    elseif tree.kind == "enchantmentTrade" then
        local name = ns.Engine.ClauseGeneration.noun(f.enchantment, not uk, "accusative")
        if not name then return nil end
        local normalize = ns.Engine.Normalize
        if s.stat then
            local stat = M.generate(s.stat.term, direction, uk and "accusative" or nil)
            if not stat then return nil end
            stat = normalize.word(stat)
            name = uk and name .. " на " .. stat or stat .. " " .. name
        end
        if s.equipment then
            local case = uk and (s.equipment.plural and "genitivePlural" or "genitive") or nil
            local equipment = M.generate(s.equipment.term, direction, case)
            if not equipment then return nil end
            name = name .. (uk and " для " or " for ") .. normalize.word(equipment)
        end
        local lead = uk and (f.buy and "Куплю " or "Продам ") or (f.buy and "WTB " or "WTS ")
        return lead .. name .. (uk and "." or "")
    elseif tree.kind == "gratuityNote" then
        local tips = gratuities[f.tips]
        local output = (uk and tips.uk or tips.en):sub(3)
        if f.inlineEmote then output = output .. " " .. f.inlineEmote end
        if #f.references > 0 then return output .. " " .. table.concat(f.references, " ") end
        return output .. (f.inlineEmote and "" or ".")
    elseif tree.kind == "service" then
        if s.recipe then
            local request = practitionerRequest(s.profession.term, uk, not f.withRecipe)
            local recipe = recipeLabel(s.recipe, direction)
            if not request or not recipe then return end
            local marker = f.withRecipe and (uk and " із рецептом " or " with ") or (uk and " для чарів " or " for ")
            local output = request .. marker .. (uk and "«" .. recipe .. "»" or recipe)
            if f.mats then output = output .. (uk and ", матеріали є" or ", got mats") end
            return output .. "."
        end
        local subject = s.trade and s.trade.raw or M.generate(s.profession.term, direction)
        if not subject then return end
        for index = 2, 4 do
            local link = s["trade" .. index]
            if not link then break end
            subject = subject .. ", " .. link.raw
        end
        local output = f.demand and f.practitioner and practitionerRequest(s.profession.term, uk, true)
            or (uk and (f.demand and "Шукаю послуги: " or "Пропоную послуги: ")
                or (f.demand and "Looking for " or "Offering ")) .. subject
        if f.priced then output = output .. (uk and " за " or " for ") .. s.price.raw end
        if f.compactFree then
            local lead = s.trade.kind == "enchant" and "Безкоштовно накладу " or "Безкоштовно пропоную послуги: "
            output = (uk and lead or "Free ") .. subject
        elseif f.free then output = output .. (uk and " безкоштовно" or " for free") end
        if f.materials then
            output = output .. (uk and " — принесіть матеріали" or " — bring materials")
            if f.promise then output = output .. (uk and ", і я виготовлю" or " and I'll make it") end
        end
        return serviceTerms(output, f, uk, s.stock)
    elseif tree.kind == "reward" then
        return render(uk and "Заплачу {price:money} тому, хто допоможе мені з {quest}."
            or "{price} for anyone who helps me with {quest}")
    elseif tree.kind == "questNeed" then
        return render(uk and "Комусь із {class:genitivePlural} потрібне завдання {quest}?"
            or "Do any {class} need {quest}?")
    elseif tree.kind == "questAttendance" then
        return (uk and "Хтось іде на завдання " or "Anyone for ") .. table.concat(f.quests, ", ")
    elseif tree.kind == "enhancement" then
        local items = {}
        for index = 1, #f.joins + 1 do
            local suffix = index == 1 and "" or tostring(index)
            local count, stat, option, equipment = s["count" .. suffix], s["stat" .. suffix],
                s["option" .. suffix], s["equipment" .. suffix]
            local shape
            if option then shape = "{option}"
            elseif count then shape = uk and "+{count} до {stat:genitivePlural}" or "+{count} {stat}"
            else shape = uk and "бонус до {stat:genitivePlural}" or "+{stat}" end
            local bonus = G.render(shape, {count=count, stat=stat, option=option}, direction)
            local item = G.render(uk and "{equipment:" .. (equipment.locative or "locative") .. "}" or "{equipment}",
                {equipment=equipment}, direction)
            if not bonus or not item then return end
            if index > 1 then
                local join = f.joins[index - 1]
                items[#items + 1] = join == "comma" and ", "
                    or (uk and (join == "and" and " та " or " або ") or " " .. join .. " ")
            end
            items[#items + 1] = bonus .. (uk and " на " or " on ") .. item
            local price = s["price" .. suffix]
            if price then
                local value = G.render(uk and " за {price:money}" or " for {price}", {price=price}, direction)
                if not value then return nil end
                items[#items + 1] = value
            end
        end
        local output = table.concat(items)
        if f.demand then
            local profession = practitionerLabel(s.profession.term, uk, f.inquiry)
            if not profession then return end
            local separator = uk and (#f.joins > 0 and " — " or " для ") or " for "
            local lead = uk and (f.inquiry and "Чи є " or "Шукаю ") or (f.inquiry and "Any " or "Looking for ")
            output = lead .. profession .. separator .. output
        elseif f.offer then
            local lead = f.finalOffer == "plural" and (uk and "Останні безкоштовні зачарування: " or "Last free enchants: ")
                or f.finalOffer == "singular" and (uk and "Останнє безкоштовне зачарування: " or "Last free enchant: ")
                or f.offer == "enchanting" and (uk and "Пропоную зачарування: " or "Offering enchants: ")
                or (uk and "Продам: " or "WTS ")
            output = lead .. output
            if f.header then output = f.header .. ", " .. output end
        end
        if f.mats then output = output .. (uk and ", матеріали є" or ", got mats") end
        if f.materials then
            local materials = ns.Engine.ClauseGeneration.noun(f.materials, not uk, uk and "instrumental" or "accusative")
            if not materials then return nil end
            output = output .. (uk and ", з " or ", with ") .. materials
        end
        if f.free and not f.finalOffer then output = output .. (uk and " безкоштовно" or " for free") end
        local value = serviceTerms(output, f, uk)
        if value and f.limited then return value .. (uk and " Запас обмежений." or ". Limited stock") end
        return value
    elseif tree.kind == "statement" then
        local function noun(slot)
            local object = slot.term
            local form = slot.plural and not object.morphology and "accusativePlural" or "accusative"
            if uk then return M.generate(object, direction, form) end
            return slot.plural and (object.englishPlural or object.en) or object.englishObject or object.en
        end
        local value = noun(s.object)
        if not value then return end
        if s.object2 then
            local second = noun(s.object2)
            if not second then return end
            value = value .. (uk and (f.conjunction == "and" and " і " or " або ") or " " .. f.conjunction .. " ") .. second
        end
        local output
        if uk and not f.negative and not f.modal and not f.question then output = "Бачу " .. value
        elseif uk then output = "Я " .. (f.negative and "не " or "") .. (f.modal and "можу бачити " or "бачу ") .. value
        elseif f.question then output = "Can I " .. (f.negative and "not " or "") .. "see " .. value
        else output = "I " .. (f.modal and (f.negative and "cannot " or "can ") or (f.negative and "do not " or "")) .. "see " .. value end
        if uk and f.question then output = "Чи " .. ns.Engine.Normalize.word(output:sub(1, 2)) .. output:sub(3) end
        return output .. (f.question and "?" or ".")
    end
end
