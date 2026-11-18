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
function State:noun(name, category)
    local candidate, reason = M.select(self.document, self.i, category, self.limit)
    if reason == "ambiguous" then self.ambiguous = true end
    if not candidate then return false end
    self.slots[name] = {term=candidate.term, analysis=candidate,
        plural=candidate.features.number == "plural"}
    self.i = candidate.last + 1
    return true
end
function State:count()
    local token = self.tokens[self.i]
    if self.i <= self.limit and token.key:match("^%d+$") and #token.key <= 3
        and tonumber(token.key) > 0 then
        self.slots.count = {raw=token.key}; self.i = self.i + 1; return true
    end
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

local function recruit(p, direction)
    local uk = direction == "uk-en"
    if uk then
        if not p:any("шукаємо", "потрібно", "потрібен", "потрібні") then return end
        p:word("ще")
    elseif not p:any("lfm", "lf", "looking for", "need") then return end
    local count = p:count()
    local compact = count and p:word("m")
    local lastSpot = p:any("last spot", "last slot", "останнє місце")
    local role, place, go
    for _ = 1, 4 do
        p:word(",")
        if not role and p:noun("role", "roles") then role = true
        elseif not place then
            local start = p.i
            local introduced = p:any("for", "для", "у", "в", ". місце :")
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
    if p:any("and go", "і йдемо", "і вирушаємо") then go = true end
    if not role and not (place and count) then return end
    if lastSpot and p.slots.count and tonumber(p.slots.count.raw) > 1 then return end
    return p:finish("recruit", {compact=compact, lastSpot=lastSpot, go=go})
end

local function enhancement(p, direction)
    local demand
    if direction == "en-uk" then demand = p:any("lf", "looking for")
    else demand = p:any("шукаю", "потрібен") end
    if demand then
        if not p:noun("profession", "professions") then return end
        if not p:any("for", "для") then return end
    end
    if not p:word("+") or not p:count() then return end
    p:word("до")
    if not p:noun("stat", "stats") then return end
    if not p:any("on", "на", "до") or not p:noun("equipment", "equipment") then return end
    p:word(",")
    local mats = p:any("got mats", "have mats", "i have mats", "матеріали є", "маю матеріали")
    return p:finish("enhancement", {demand=demand, mats=mats})
end

local function service(p, direction)
    local demand, offer
    if direction == "en-uk" then
        demand = p:any("wtb", "lf", "looking for")
        if not demand then offer = p:any("wts", "lfw", "offering") end
    else
        demand = p:any("шукаю послуги", "шукаю майстра", "шукаю")
        if not demand then offer = p:any("пропоную послуги", "пропоную", "послуги") end
    end
    p:word(":")
    if not p:link("trade", "trade") and not p:noun("profession", "professions") then return end
    if not demand and not offer then
        if not p:any("lfw", "приймаю замовлення") then return end
    end
    local priced = p:any("for", "за")
    if priced and not p:money() then return end
    return p:finish("service", {demand=demand, priced=priced})
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

local parsers = {recruit, enhancement, service, reward, statement}
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
