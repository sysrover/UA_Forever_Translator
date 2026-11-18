local _, ns = ...
local T = {}; ns.Engine.Transfer = T
local G, M = ns.Engine.Grammar, ns.Engine.Morphology

function T.render(tree, direction)
    local s, f, uk = tree.slots, tree.features, direction == "en-uk"
    local function render(template) return G.render(template, s, direction) end
    if tree.kind == "recruit" then
        local output
        if uk then
            if f.lastSpot and s.role and s.place and (not s.count or s.count.raw == "1") then
                output = render("Шукаємо {role:genitiveSingular} — {place}. Залишилося одне місце.")
                if output and f.go then output = output .. " І вирушаємо." end
                if output and f.question then output = output:gsub("%.$", "") .. "?" end
                return output
            end
            if s.role then
                if s.count and f.compact then
                    output = render("Набір у групу: ще {count}; роль: {role}.")
                elseif s.count then
                    output = render("Шукаємо {count} {role:counted}.")
                else output = render("Шукаємо {role:genitiveSingular}.") end
            else
                local form = G.numberForm(s.count.raw) == "genitiveSingular" and "гравця" or "гравців"
                output = render("Шукаємо ще {count} ") .. form .. "."
            end
            if not output then return end
            if s.place then output = output .. " " .. render("Місце: {place}.") end
            if f.lastSpot then output = output .. " Залишилося одне місце." end
            if f.go then output = output .. " І вирушаємо." end
        else
            output = s.count and render("LF{count}M") or "LFM"
            if s.role then output = output .. " " .. render("{role}") end
            if s.place then output = output .. " for " .. render("{place}") end
            if f.lastSpot then output = output .. ", last spot" end
            if f.go then output = output .. " and go" end
        end
        if f.question then output = output:gsub("%.$", "") .. "?" end
        return output
    elseif tree.kind == "service" then
        local subject = s.trade and s.trade.raw or M.generate(s.profession.term, direction)
        if not subject then return end
        local output = (uk and (f.demand and "Шукаю послуги: " or "Пропоную послуги: ")
            or (f.demand and "Looking for " or "Offering ")) .. subject
        if f.priced then output = output .. (uk and " за " or " for ") .. s.price.raw end
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
