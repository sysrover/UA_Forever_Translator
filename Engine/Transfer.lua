local _, ns = ...
local T = {}; ns.Engine.Transfer = T
local G, M = ns.Engine.Grammar, ns.Engine.Morphology

local gratuities = {
    appreciated={uk=". Буду вдячний за чайові", en=". Tips are appreciated"},
    accepted={uk=". Приймаю чайові", en=". Tips accepted"},
    with={uk=" з чайовими", en=" with tips"},
}

local function serviceTerms(output, features, uk)
    local tips = gratuities[features.tips]
    if tips then output = output .. (uk and tips.uk or tips.en) end
    for index, place in ipairs(features.places or {}) do
        local value, marker = ns.Engine.ClauseGeneration.preposition(place, not uk)
        if not value then return nil end
        if not uk and place.rule.id == "out-of-location" then marker = "outside" end
        output = output .. (index == 1 and " " or ", ") .. marker .. " " .. value
    end
    return output .. (uk and "." or "")
end

function T.render(tree, direction)
    local s, f, uk = tree.slots, tree.features, direction == "en-uk"
    local function render(template) return G.render(template, s, direction) end
    if tree.kind == "recruit" then
        local output
        local total = s.total and s.total.raw
        local function totalPlayers(amount)
            local form = G.numberForm(amount) == "genitiveSingular" and "гравця" or "гравців"
            return "Шукаємо ще " .. amount .. " " .. form
        end
        local function appendLevel(value)
            if not s.level then return value end
            return value .. (uk and ". Рівень: " or " L") .. s.level.raw
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
            if f.run == "full" then value = value .. (uk and ". Повне проходження" or ", full run")
            elseif f.run == "fresh" then value = value .. (uk and ". Проходження з початку" or ", fresh run")
            elseif f.run == "quest" then value = value .. (uk and ". Проходження із завданнями" or ", quest run") end
            if f.urgent then value = value .. (uk and ". Терміново" or ", quick") end
            if f.summon then value = value .. (uk and ". Можемо прикликати" or ", can summon") end
            if f.go then value = value .. (uk and ". І вирушаємо" or " and go") end
            return value .. (f.question and "?" or uk and "." or "")
        end
        if f.classJoins then
            local classes = {}
            for index = 1, #f.classJoins + 1 do
                local class = G.render(uk and "{class:genitiveSingular}" or "{class}",
                    {class=s["class" .. index]}, direction)
                if not class then return nil end
                local join = f.classJoins[index - 1]
                if join then
                    classes[#classes + 1] = join == "comma" and ", "
                        or uk and (join == "or" and " або " or " і ") or " " .. join .. " "
                end
                classes[#classes + 1] = uk and class or class:lower()
            end
            local amount = total or (s.count and s.count.raw)
            if uk then output = amount and totalPlayers(amount) .. ": " or "Шукаємо "
            else output = amount and "LF" .. amount .. "M " or "LFM " end
            output = output .. table.concat(classes)
            if s.role then
                local role = render(uk and "{role:genitiveSingular}" or "{role}")
                if not role then return nil end
                output = output .. (uk and " на роль " or " ") .. role
            end
            output = appendLevel(output)
            if s.place then output = output .. (uk and ". Місце: " or " for ") .. render("{place}") end
            if f.lastSpot then output = output .. (uk and ". Залишилося одне місце" or ", last spot") end
            return appendConditions(output)
        end
        if f.roleJoins and #f.roleJoins > 0 then
            local roles = {}
            for n = 1, #f.roleJoins + 1 do
                local suffix = n == 1 and "" or tostring(n)
                local values = {role=s["role" .. suffix], count=s["count" .. suffix]}
                local format = values.count and (uk and "{count} {role:counted}" or "{count} {role}")
                    or (uk and "{role:genitiveSingular}" or "{role}")
                local value = G.render(format, values, direction)
                if not value then return nil end
                if n > 1 then
                    local isAnd = f.roleJoins[n - 1] == "and"
                    roles[#roles + 1] = uk and (isAnd and "і" or "або") or f.roleJoins[n - 1]
                end
                roles[#roles + 1] = value
            end
            local prefix
            if uk then prefix = total and totalPlayers(total) .. ": " or "Шукаємо "
            else prefix = total and "LF" .. total .. "M " or "Looking for " end
            output = appendLevel(prefix .. table.concat(roles, " "))
            if s.place then output = output .. (uk and ". Місце: " or " for ") .. render("{place}") end
            if f.lastSpot then output = output .. (uk and ". Залишилося одне місце" or ", last spot") end
            return appendConditions(output)
        end
        if uk then
            if f.lastSpot and s.role and s.place and not s.level and not (s.count and s.total) and (not (s.count or s.total)
                or (s.count or s.total).raw == "1") then
                output = render("Шукаємо {role:genitiveSingular} — {place}. Залишилося одне місце.")
                if output then return appendConditions((output:gsub("%.$", ""))) end
                return nil
            end
            if s.role then
                if total and s.count then
                    local role = render("{count} {role:counted}")
                    if not role then return end
                    output = totalPlayers(total) .. ": " .. role .. "."
                elseif total then
                    output = render("Набір у групу: ще {total}; роль: {role}.")
                elseif s.count then
                    output = render(f.additional and "Шукаємо ще {count} {role:counted}." or "Шукаємо {count} {role:counted}.")
                else output = render("Шукаємо {role:genitiveSingular}.") end
            elseif total or s.count then
                output = totalPlayers(total or s.count.raw) .. "."
            else output = "Шукаємо гравців."
            end
            if not output then return end
            if s.level then output = appendLevel((output:gsub("%.$", ""))) .. "." end
            if s.place then output = output .. " " .. render("Місце: {place}.") end
            if f.lastSpot then output = output .. " Залишилося одне місце." end
        else
            output = total and "LF" .. total .. "M" or s.count and render("LF{count}M") or "LFM"
            if s.role then
                output = output .. " " .. render(total and s.count and "{count} {role}" or "{role}")
            end
            output = appendLevel(output)
            if s.place then output = output .. " for " .. render("{place}") end
            if f.lastSpot then output = output .. ", last spot" end
        end
        return appendConditions((output:gsub("%.$", "")))
    elseif tree.kind == "groupSearch" then
        if not uk and s.role and not s.place then return render("{role} LFG") end
        local output = uk and "Шукаю групу" or "LFG"
        if s.place then output = output .. render(uk and ". Місце: {place}" or " {place}") end
        if s.role then output = output .. render(uk and ". Роль: {role}" or " as {role}") end
        return output .. (uk and "." or "")
    elseif tree.kind == "search" then
        local object = ns.Engine.ClauseGeneration.noun(f.object, not uk, "accusative", not uk)
        if object then return (uk and "Шукаю " or "Looking for ") .. object .. "." end
    elseif tree.kind == "price" then
        local amount = render(uk and (f.introduced and "{price:money}" or "{price:moneyNominative}") or "{price}")
        local only = f.linked and (uk and "лише " or "only ") or (uk and "Лише " or "Only ")
        local value = (f.only and only or "") .. amount
        if f.linked then
            value = s.item.raw .. (f.introduced and (uk and " за " or " for ") or " — ") .. value
        end
        if f.each then
            value = value .. (f.each == "bottle" and (uk and " за пляшку" or " a bottle") or (uk and " за штуку" or " each"))
        end
        return value
    elseif tree.kind == "availability" then
        local profession = ns.Engine.ClauseGeneration.noun(f.occupation, not uk, "nominative")
        if not profession then return end
        local places = {online={"онлайн","online"}, ["онлайн"]={"онлайн","online"},
            around={"поблизу","around"}, ["поблизу"]={"поблизу","around"}, here={"тут","here"}, ["тут"]={"тут","here"}}
        local place = places[f.place][uk and 1 or 2]
        local skill = s.skill.raw .. "+"
        if uk then return "Чи є " .. profession .. " із навичкою " .. skill .. " " .. place end
        return "Any " .. skill .. " " .. profession .. " " .. place
    elseif tree.kind == "service" then
        if s.recipe then
            local profession = uk and s.profession.term.renderForms and s.profession.term.renderForms.practitioner
                or not uk and s.profession.term.englishPractitioner
            if not profession then return end
            return (uk and "Шукаю " or "Looking for ") .. profession
                .. (uk and " із рецептом «" or " with ") .. render("{recipe}") .. (uk and "»." or ".")
        end
        local subject = s.trade and s.trade.raw or M.generate(s.profession.term, direction)
        if not subject then return end
        for index = 2, 4 do
            local link = s["trade" .. index]
            if not link then break end
            subject = subject .. ", " .. link.raw
        end
        local output = (uk and (f.demand and "Шукаю послуги: " or "Пропоную послуги: ")
            or (f.demand and "Looking for " or "Offering ")) .. subject
        if f.priced then output = output .. (uk and " за " or " for ") .. s.price.raw end
        if f.free then output = output .. (uk and " безкоштовно" or " for free") end
        if f.materials then
            output = output .. (uk and " — принесіть матеріали" or " — bring materials")
            if f.promise then output = output .. (uk and ", і я виготовлю" or " and I'll make it") end
        end
        return serviceTerms(output, f, uk)
    elseif tree.kind == "reward" then
        return render(uk and "Заплачу {price:money} тому, хто допоможе мені з {quest}."
            or "{price} for anyone who helps me with {quest}")
    elseif tree.kind == "questNeed" then
        return render(uk and "Комусь із {class:genitivePlural} потрібне завдання {quest}?"
            or "Do any {class} need {quest}?")
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
        end
        local output = table.concat(items)
        if f.demand then
            local professionForm = f.inquiry and "practitionerNominative" or "practitioner"
            local profession = uk and s.profession.term.renderForms and s.profession.term.renderForms[professionForm]
                or (not uk and s.profession.term.englishPractitioner)
            if not profession then return end
            local separator = uk and (#f.joins > 0 and " — " or " для ") or " for "
            local lead = uk and (f.inquiry and "Чи є " or "Шукаю ") or (f.inquiry and "Any " or "Looking for ")
            output = lead .. profession .. separator .. output
        end
        if f.mats then output = output .. (uk and ", матеріали є" or ", got mats") end
        if f.free then output = output .. (uk and " безкоштовно" or " for free") end
        return serviceTerms(output, f, uk)
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
