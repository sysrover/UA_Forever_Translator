local _, ns = ...
local S = {}; ns.Engine.Syntax = S
local M = ns.Engine.Morphology
local currency = {
    ["золоту монету"]="g", ["золоті монети"]="g", ["золотих монет"]="g", ["золотої монети"]="g",
    ["срібну монету"]="s", ["срібні монети"]="s", ["срібних монет"]="s", ["срібної монети"]="s",
    ["мідну монету"]="c", ["мідні монети"]="c", ["мідних монет"]="c", ["мідної монети"]="c",
}

local State = {}; State.__index = State
function State:word(key)
    local token = self.tokens[self.i]
    if self.i <= self.limit and not token.protected and token.key == key then
        self.i = self.i + 1; return true
    end
    return false
end
function State:phrase(value)
    local start = self.i
    for key in value:gmatch("%S+") do
        if not self:word(key) then self.i = start; return false end
    end
    return true
end
function State:any(...)
    for n = 1, select("#", ...) do
        if self:phrase(select(n, ...)) then return true end
    end
    return false
end
function State:noun(name, category, case)
    local candidate, reason = M.select(self.document, self.i, category, self.limit, case)
    if reason == "ambiguous" then self.ambiguous = true end
    if not candidate then return false end
    self.slots[name] = {term=candidate.term, analysis=candidate,
        plural=candidate.features.number == "plural"}
    self.i = candidate.last + 1
    return true
end
function State:count(slot)
    local token = self.tokens[self.i]
    if self.i <= self.limit and token.key:match("^%d+$") and #token.key <= 3
        and tonumber(token.key) > 0 then
        self.slots[slot or "count"] = {raw=token.key}; self.i = self.i + 1; return true
    end
    return false
end
local function compactCountedTerm(token, category)
    if not token or token.protected then return end
    local amount, alias = token.key:match("^(%d%d?%d?)([a-z]+)$")
    if not amount or tonumber(amount) == 0 then return end
    local index = ns.Data.linguistics and ns.Data.linguistics.analysis["en-uk"]
    local application = index and index[alias]
    if not application then return end
    local selected
    for _, candidate in ipairs(application._analyses or {}) do
        local term = ns.Data.terms[candidate.id]
        if term.category == category then
            if selected and selected ~= term then return end
            selected = term
        end
    end
    if selected then return selected, amount end
end
function State:role(name, countKey)
    local start, count = self.i, self.slots[countKey]
    local english = self.document.direction == "en-uk"
    if not count then self:count(countKey) end
    if english and not self.slots[countKey] then self:any("a", "an") end
    if self:noun(name, "roles") then return true end
    local token = self.i <= self.limit and self.tokens[self.i]
    if english and not self.slots[countKey] then
        local term, amount = compactCountedTerm(token, "roles")
        if term then
            self.slots[name] = {term=term}
            self.slots[countKey] = {raw=amount}
            self.i = self.i + 1
            return true
        end
    end
    self.i, self.slots[countKey] = start, count
    return false
end
function State:link(name, kind)
    local token = self.tokens[self.i]
    if self.i <= self.limit and token.linkKind == kind then
        self.slots[name] = {raw=self.document.text:sub(token.first, token.last), kind=kind}
        self.i = self.i + 1; return true
    end
    return false
end
function State:money()
    local start = self.i
    if start > self.limit then return false end
    for last = math.min(self.limit, start + 4), start, -1 do
        local raw = self.document.text:sub(self.tokens[start].first, self.tokens[last].last)
        local amount, unit = raw:match("^(%d+[%.,]?%d*)%s*([gsc])$")
        if not amount and self.document.direction == "uk-en" then
            local number, name = raw:match("^(%d+[%.,]?%d*)%s+(.+)$")
            if number and currency[name] then amount, unit = number, currency[name] end
        end
        if amount then
            self.slots.price = {raw=amount .. unit, sourceRaw=raw, amount=amount, unit=unit}
            self.i = last + 1; return true
        end
    end
    return false
end
function State:finish(kind, extra)
    extra = extra or {}
    if self.tokens[self.limit].key == "?" then extra.question = true end
    while self.i <= self.limit and self.tokens[self.i].key:match("^[.!?]$") do self.i = self.i + 1 end
    if self.i <= self.limit or self.ambiguous then return nil end
    return {kind=kind, slots=self.slots, features=extra, first=1, last=self.limit}
end
local function state(document, limit)
    return setmetatable({document=document, tokens=document.tokens, i=1, limit=limit, slots={}}, State)
end

local function recruitLevel(p, uk)
    local start = p.i
    local token = p.i <= p.limit and p.tokens[p.i]
    local compact = not uk and token and not token.protected and token.key:match("^l(%d%d?%d?)$")
    if compact then
        if tonumber(compact) == 0 then return false end
        p.i = p.i + 1
    else
        local marker = uk and p:word("рівень") or not uk and p:any("level", "lvl", "l")
        if not marker then return false end
        if uk then p:word(":") end
        if not p:count("level") then p.i = start; return false end
    end
    local raw = compact or p.slots.level.raw
    local separator = p:word("/") and "/" or p:any("-", "–") and "-"
    if separator then
        if not p:count("level") then p.i, p.slots.level = start, nil; return false end
        raw = raw .. separator .. p.slots.level.raw
    end
    p.slots.level = {raw=raw}
    return true
end

local function recruitClasses(p, uk)
    local start = p.i
    if not uk then p:any("a", "an") end
    if not p:noun("class1", "classes") then p.i = start; return false end
    local joins = {}
    for index = 2, 4 do
        local beforeJoin = p.i
        local comma = p:word(",")
        local join = p:any("or", "/", "або") and "or"
            or p:any("and", "&", "та", "і", "й") and "and"
            or comma and "comma"
        if not join or not p:noun("class" .. index, "classes") then p.i = beforeJoin; break end
        joins[#joins + 1] = join
    end
    local beforeRole = p.i
    if not uk or p:phrase("на роль") then
        if not p:noun("role", "roles") then p.i = beforeRole end
    end
    p.classJoins = joins
    return true
end

local function preferredClass(p, uk)
    local start = p.i
    local marker = uk and p:word("бажано") or not uk and p:any("preferably", "prefer", "pref")
    if marker then
        if p:noun("preferred", "classes") then return true end
    elseif not uk and p:noun("preferred", "classes") and p:any("pref", "preferred") then
        return true
    end
    p.i, p.slots.preferred = start, nil
    return false
end

local function recruit(p, direction)
    local uk = direction == "uk-en"
    local leadingPlace
    if uk then
        if not p:any("шукаємо", "потрібно", "потрібен", "потрібні") then return end
        p:word("ще")
        p:word("гравців")
    elseif not p:any("lfm", "lf", "looking for", "need") then
        if not p:noun("place", "places") then return end
        p:word(",")
        if not p:any("lfm", "lf", "looking for", "need") then return end
        leadingPlace = true
    end
    local count = p:count()
    local compact = count and (p:word("m") or (uk and p:any("гравця :", "гравців :", "гравця", "гравців")))
    if compact then p.slots.total, p.slots.count = p.slots.count, nil end
    local lastSpot = p:any("last spot", "last slot", "останнє місце")
    local role, place, go = nil, leadingPlace, nil
    local roleJoins = {}
    for _ = 1, 4 do
        local separator = p:any(",", ".")
        if not role and place and separator then p:any("need", "потрібно", "потрібні") end
        if not role and p:role("role", "count") then
            role = true
            for n = 2, 4 do
                local start = p.i
                local join = p:any("and", "&", "+", "та", "і", "й") and "and" or p:any("or", "/", "або") and "or"
                if not join then p:word(",") end
                local suffix = tostring(n)
                if p:role("role" .. suffix, "count" .. suffix) and (join or p.slots["count" .. suffix]) then
                    roleJoins[#roleJoins + 1] = join or "and"
                else
                    p.i = start
                    p.slots["role" .. suffix], p.slots["count" .. suffix] = nil, nil
                    break
                end
            end
        elseif not role and recruitClasses(p, uk) then
            role = true
        elseif role and not p.slots.preferred and preferredClass(p, uk) then
            -- The class is a preference for the requested role.
        elseif not p.slots.level and recruitLevel(p, uk) then
            -- The level belongs to the recruitment regardless of its position.
        elseif not place then
            local start = p.i
            local introduced = p:any("for", "для", "у", "в", "місце :")
            if p:noun("place", "places") then place = true
            else
                if introduced and p.limit == #p.tokens then
                    p.document.preserve = p.document.preserve or {}
                    local unresolved = p.i <= p.limit and p.i or start
                    p.document.preserve[unresolved] = {last=p.limit, reason="unresolved-destination"}
                end
                p.i = start
                break
            end
        else break end
        if p:any("last spot", "last slot", "останнє місце") then lastSpot = true end
        if p.i < p.limit and p.tokens[p.i].key == "!" then p.i = p.i + 1 end
    end
    p:word(",")
    if p:any("last spot", "last slot", "останнє місце") then lastSpot = true end
    local run
    if p:any("full run", "повне проходження", ". повне проходження") then run = "full"
    elseif p:any("fresh run", "проходження з початку", ". проходження з початку") then run = "fresh" end
    p:word(",")
    local summon = p:any("can summon", "можемо прикликати", ". можемо прикликати")
    if p:any("and go", "then go", "і йдемо", "і вирушаємо", ". і вирушаємо") then go = true end
    if not role and not (place and (p.slots.count or p.slots.total or p.slots.level)) then return end
    if lastSpot then
        local total = p.slots.total
        if total and tonumber(total.raw) > 1 then return end
        for n = 1, #roleJoins + 1 do
            local amount = p.slots[n == 1 and "count" or "count" .. n]
            if amount and tonumber(amount.raw) > 1 then return end
        end
    end
    return p:finish("recruit", {lastSpot=lastSpot, go=go, roleJoins=roleJoins, classJoins=p.classJoins,
        run=run, summon=summon})
end

local function enhancementItem(p, suffix, english, allowOption)
    local count, stat, equipment = "count" .. suffix, "stat" .. suffix, "equipment" .. suffix
    if p:word("+") then
        local token = p.i <= p.limit and p.tokens[p.i]
        local compact, amount
        if english then compact, amount = compactCountedTerm(token, "stats") end
        if compact then
            p.slots[count], p.slots[stat] = {raw=amount}, {term=compact}
            p.i = p.i + 1
        else
            p:count(count)
            p:word("до")
            if not p:noun(stat, "stats") then return end
        end
    elseif not english and p:phrase("бонус до") then
        if not p:noun(stat, "stats") then return end
    elseif not allowOption or not p:noun("option" .. suffix, "enhancements") then return end
    if not p:any("on", "на", "до") then return end
    if english then p:any("a", "the") end
    local start = p.i
    local case = not english and "locative" or nil
    if p:noun(equipment, "equipment", case) then return true end
    if not p:noun(equipment, "goods", case) then return end
    local noun = p.slots[equipment]
    if english and noun.term.englishPlural then
        local key = ns.Engine.Normalize.key
        noun.plural = key(ns.Engine.Phrases.raw(p.document, start, p.i - 1)) == key(noun.term.englishPlural)
    end
    noun.locative = noun.plural and "locativePlural" or "locative"
    return noun.term.forms and noun.term.forms[noun.locative] ~= nil
end

local function enhancement(p, direction)
    local english = direction == "en-uk"
    local demand
    if english then demand = p:any("lf", "looking for")
    else demand = p:any("шукаю", "потрібен") end
    if demand then
        if not p:noun("profession", "professions") then return end
        if not p:any("for", "для", "—") then return end
    end
    if not enhancementItem(p, "", english, demand) then return end
    local joins, mats = {}
    while p.i <= p.limit do
        local comma = p:word(",")
        mats = p:any("got mats", "have mats", "i have mats", "матеріали є", "маю матеріали")
        if mats then break end
        local join = p:any("and", "і", "й", "та") and "and"
            or p:any("or", "або") and "or" or comma and "comma"
        if not join then break end
        if not enhancementItem(p, tostring(#joins + 2), english, true) then return end
        joins[#joins + 1] = join
    end
    return p:finish("enhancement", {demand=demand, mats=mats, joins=joins})
end

local function service(p, direction)
    local demand, offer
    if direction == "en-uk" then
        demand = p:any("wtb", "lf", "looking for")
        if not demand then offer = p:any("wts", "lfw", "offering", "selling", "crafting") end
    else
        demand = p:any("шукаю послуги", "шукаю майстра", "шукаю")
        if not demand then offer = p:any("пропоную послуги", "пропоную", "послуги") end
    end
    p:word(":")
    local linked = p:link("trade", "trade") or p:link("trade", "enchant")
    if linked then
        for index = 2, 4 do
            local previous = p.i
            p:word(",")
            if not p:link("trade" .. index, "enchant") then p.i = previous; break end
        end
    elseif not p:noun("profession", "professions") then return end
    if not demand and not offer then
        if not p:any("lfw", "приймаю замовлення") then return end
    end
    local free = p:any("for free", "free", "безкоштовно")
    local priceIntroduced = not free and p:any("for", "за")
    local priced = not free and p:money()
    if priceIntroduced and not priced then return end
    local previous = p.i
    p:any("-", "—", ",")
    local materials = p:any("with your mats", "with your materials", "bring mats", "bring your own materials",
        "з вашими матеріалами", "з твоїми матеріалами", "принесіть матеріали")
    if not materials then p.i = previous end
    local promise = materials and p:any("and i make for you", "and i'll make it", "і я виготовлю", ", і я виготовлю")
    return p:finish("service", {demand=demand, priced=priced, free=free, materials=materials, promise=promise})
end

local function reward(p, direction)
    if direction == "uk-en" then p:word("заплачу") end
    if not p:money() then return end
    if direction == "en-uk" then
        if not p:any("for anyone that helps me with", "for anyone who helps me with", "for help with") then return end
    elseif not p:any("тому хто допоможе мені з", "тому , хто допоможе мені з", "за допомогу з") then return end
    if not p:link("quest", "quest") then return end
    return p:finish("reward")
end

local function questNeed(p, direction)
    if direction == "en-uk" then
        p:any("do", "does")
        if not p:word("any") or not p:noun("class", "classes") or not p:any("need", "needs") then return end
    else
        if not p:any("комусь із", "комусь з")
            or not p:noun("class", "classes") or not p:phrase("потрібне завдання") then return end
    end
    if not p:link("quest", "quest") then return end
    if not p.slots.class.term.englishPlural then return end
    p.slots.class.plural = true
    return p:finish("questNeed", {question=true})
end

local function statement(p, direction)
    local negative, question, modal
    if direction == "en-uk" then
        if p:phrase("can i") then question, modal = true, true
        elseif not p:word("i") then return end
        if p:any("cannot", "can't") then negative, modal = true, true
        else negative = p:any("do not", "don't") end
        if not negative then modal = modal or p:word("can") end
        if not p:word("see") then return end
    else
        question = p:word("чи")
        p:word("я")
        negative = p:word("не")
        modal = p:word("можу")
        if not p:any("бачу", "бачити") then return end
    end
    if not p:noun("object", "creatures") and not p:noun("object", "goods") then return end
    local conjunction
    if p:any("and", "і", "й", "та") then conjunction = "and"
    elseif p:any("or", "або", "чи") then conjunction = "or" end
    if conjunction and not p:noun("object2", "creatures") and not p:noun("object2", "goods") then return end
    return p:finish("statement", {negative=negative, question=question, modal=modal, conjunction=conjunction})
end

local parsers = {recruit, enhancement, service, reward, questNeed, statement}
function S.parse(document, limit)
    for _, parse in ipairs(parsers) do
        local result = parse(state(document, limit or #document.tokens), document.direction)
        if result then return result end
    end
end

function S.translate(document)
    local tree = S.parse(document)
    if tree then
        local output = ns.Engine.Transfer.render(tree, document.direction)
        if output and tree.features.question then output = output:gsub("[.!?]+$", "") .. "?" end
        if output and not document.truncated then return output, tree end
    end
    -- Preserve the original remainder, including unknown conditions and links.
    -- No unbounded chart search and no reconstruction of the input from words.
    local minimum = math.max(1, #document.tokens - 24)
    for last = #document.tokens - 1, minimum, -1 do
        tree = S.parse(document, last)
        if tree then
            local output = ns.Engine.Transfer.render(tree, document.direction)
            if output then
                return nil, nil, {[1]={text=output:gsub("[.!]+$", ""), last=last,
                    rule={sourceRefs={"project-authored:apertium-pipeline-1"}}, slots=tree.slots}}
            end
        end
    end
end
