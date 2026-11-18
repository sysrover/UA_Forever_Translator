local _, ns = ...
local T = {}; ns.Engine.Transfer = T
local G, M = ns.Engine.Grammar, ns.Engine.Morphology

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
        local function appendConditions(value)
            if f.run == "full" then value = value .. (uk and ". Повне проходження" or ", full run")
            elseif f.run == "fresh" then value = value .. (uk and ". Проходження з початку" or ", fresh run") end
            if f.summon then value = value .. (uk and ". Можемо прикликати" or ", can summon") end
            if f.go then value = value .. (uk and ". І вирушаємо" or " and go") end
            return value .. (f.question and "?" or uk and "." or "")
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
            output = prefix .. table.concat(roles, " ")
            if s.place then output = output .. (uk and ". Місце: " or " for ") .. render("{place}") end
            if f.lastSpot then output = output .. (uk and ". Залишилося одне місце" or ", last spot") end
            return appendConditions(output)
        end
        if uk then
            if f.lastSpot and s.role and s.place and not (s.count and s.total) and (not (s.count or s.total)
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
                    output = render("Шукаємо {count} {role:counted}.")
                else output = render("Шукаємо {role:genitiveSingular}.") end
            else
                output = totalPlayers(total or s.count.raw) .. "."
            end
            if not output then return end
            if s.place then output = output .. " " .. render("Місце: {place}.") end
            if f.lastSpot then output = output .. " Залишилося одне місце." end
        else
            output = total and "LF" .. total .. "M" or s.count and render("LF{count}M") or "LFM"
            if s.role then
                output = output .. " " .. render(total and s.count and "{count} {role}" or "{role}")
            end
            if s.place then output = output .. " for " .. render("{place}") end
            if f.lastSpot then output = output .. ", last spot" end
        end
        return appendConditions((output:gsub("%.$", "")))
    elseif tree.kind == "service" then
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
        return output .. (uk and "." or "")
    elseif tree.kind == "reward" then
        return render(uk and "Заплачу {price:money} тому, хто допоможе мені з {quest}."
            or "{price} for anyone who helps me with {quest}")
    elseif tree.kind == "enhancement" then
        local output = render(uk and "+{count} до {stat:genitivePlural} на {equipment:locative}"
            or "+{count} {stat} on {equipment}")
        if not output then return end
        if f.demand then
            local profession = uk and s.profession.term.renderForms and s.profession.term.renderForms.practitioner
                or (not uk and s.profession.term.englishPractitioner)
            if not profession then return end
            output = (uk and "Шукаю " or "Looking for ") .. profession .. (uk and " для " or " for ") .. output
        end
        if f.mats then output = output .. (uk and ", матеріали є" or ", got mats") end
        return output .. (uk and "." or "")
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
