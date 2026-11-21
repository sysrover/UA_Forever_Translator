local _, ns = ...
local S = {}; ns.Engine.Syntax = S
local M = ns.Engine.Morphology

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
function State:coordination()
    local comma = self:word(",")
    return self:any("and", "&", "+", "та", "і", "й") and "and"
        or self:any("or", "/", "або") and "or" or comma and "comma"
end
function State:noun(name, category, case)
    local candidate, reason = M.select(self.document, self.i, category, self.limit, case)
    local token = self.tokens[self.i]
    if not (candidate or reason) and category == "places" and self.document.direction == "en-uk"
        and self.i < self.limit and token.key == "the" then
        candidate, reason = M.select(self.document, self.i + 1, category, self.limit, case)
    end
    if reason == "ambiguous" then self.ambiguous = true end
    if not candidate then return false end
    self.slots[name] = {term=candidate.term, analysis=candidate,
        plural=candidate.features.number == "plural"}
    self.i = candidate.last + 1
    return true
end
function State:count(slot, words, multiplicity)
    local token = self.tokens[self.i]
    if self.i > self.limit or token.protected then return false end
    local amount = #token.key <= 3 and token.key:match("^%d+$")
    if multiplicity and not amount then
        amount = token.key:match("^(%d%d?%d?)x$") or token.key:match("^(%d%d?%d?)×$")
    end
    if not amount and words then
        local cardinal = ns.Engine.Phrases.cardinal(self.document, token.key, "genitive")
        if cardinal then amount = tostring(cardinal) end
    end
    if not amount or tonumber(amount) == 0 then return false end
    self.slots[slot or "count"] = {raw=amount}
    self.i = self.i + 1
    if multiplicity and token.key == amount then self:any("x", "×") end
    return true
end
local function compactTerm(alias, category)
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
    return selected
end
local function compactCountedTerm(token, category, multiplicity)
    if not token or token.protected then return end
    local amount, alias = token.key:match("^(%d%d?%d?)([a-z]+)$")
    if multiplicity and not amount then amount, alias = token.key:match("^(%d%d?%d?)×([a-z]+)$") end
    if not amount or tonumber(amount) == 0 then return end
    local term = compactTerm(alias, category)
    if not term and multiplicity and alias:sub(1, 1) == "x" then term = compactTerm(alias:sub(2), category) end
    return term, amount
end
function State:role(name, countKey, words, allowClass)
    local start, count = self.i, self.slots[countKey]
    local english = self.document.direction == "en-uk"
    if not count then self:count(countKey, words, english) end
    if english and not self.slots[countKey] then self:any("a", "an") end
    if self:noun(name, "roles") or allowClass and self:noun(name, "classes") then return true end
    local token = self.i <= self.limit and self.tokens[self.i]
    if english and not self.slots[countKey] then
        local term, amount = compactCountedTerm(token, "roles", true)
        if not term and allowClass then term, amount = compactCountedTerm(token, "classes", true) end
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
    if self.i <= self.limit and (token.linkKind == kind or kind == "quest" and token.questReference) then
        self.slots[name] = {raw=self.document.text:sub(token.first, token.last), kind=kind}
        self.i = self.i + 1; return true
    end
    return false
end
function State:questList()
    local token = self.i <= self.limit and self.tokens[self.i]
    if not token or (token.linkKind ~= "quest" and not token.questReference) then return end
    local quests = {}
    for index = 1, 8 do
        local before = self.i
        if index > 1 then self:word(",") end
        local slot = "quest" .. index
        if not self:link(slot, "quest") then self.i = before; break end
        quests[index] = self.slots[slot].raw
    end
    if #quests > 0 then return quests end
end
function State:money(name)
    local price, after = ns.Engine.Grammar.moneyAt(self.document, self.i, self.limit)
    if not price then return false end
    self.slots[name or "price"], self.i = price, after
    return true
end
local function emoteAt(p, start, limit)
    local colon, smile = p.tokens[start], p.tokens[start + 1]
    if start >= p.first and start + 1 <= limit and colon.key == ":" and smile.first == colon.last + 1
        and (smile.key == "d" or smile.key == "p" or smile.key == ")" or smile.key == "(") then
        return p.document.text:sub(colon.first, smile.last), start + 2
    end
end

function State:finish(kind, extra)
    extra = extra or {}
    local ending = self.limit
    local emote = ending > self.first and self.i < ending and emoteAt(self, ending - 1, ending)
    if emote then extra.emote, ending = emote, ending - 2 end
    if self.tokens[ending] and self.tokens[ending].key == "?" then extra.question = true end
    while self.i <= ending and self.tokens[self.i].key:match("^[.!?]$") do self.i = self.i + 1 end
    if self.i <= ending or self.ambiguous then return nil end
    return {kind=kind, slots=self.slots, features=extra, first=self.first, last=self.limit}
end
local function state(document, limit, first)
    return setmetatable({document=document, tokens=document.tokens, i=first, first=first, limit=limit, slots={}}, State)
end

local levelMarkers = {l=true, lv=true, lvl=true, level=true}
local function recruitLevel(p, uk)
    local start = p.i
    local token = p.i <= p.limit and p.tokens[p.i]
    local compact
    if not uk and token and not token.protected then
        local prefix, amount = token.key:match("^([a-z]+)(%d%d?%d?)$")
        if levelMarkers[prefix] then compact = amount
        else
            local amount, suffix = token.key:match("^(%d%d?%d?)([a-z]+)$")
            if levelMarkers[suffix] then compact = amount end
        end
    end
    if compact then
        if tonumber(compact) == 0 then return false end
        p.i = p.i + 1
    else
        local marker = uk and p:word("рівень") or not uk and token and levelMarkers[token.key] and p:word(token.key)
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
    local plus = not separator and p.i <= p.limit and p.tokens[p.i].first == p.tokens[p.i - 1].last + 1 and p:word("+")
    p.slots.level = {raw=raw, minimum=plus or nil}
    return true
end

local function recruitCandidate(p, slot)
    if p:noun(slot, "classes") then return true end
    local start = p.i
    if not p:noun(slot, "roles") then return false end
    local features = p.slots[slot].term.features
    if features and features.recruitmentAlternative then return true end
    p.i, p.slots[slot] = start, nil
    return false
end

local function recruitClasses(p, uk, roleKnown)
    local start = p.i
    if not uk then p:any("a", "an") end
    if not recruitCandidate(p, "class1") then p.i = start; return false end
    local joins = {}
    for index = 2, 4 do
        local beforeJoin = p.i
        local comma = p:any(",", ".")
        local join = p:any("or", "/", "або") and "or"
            or p:any("and", "&", "та", "і", "й") and "and"
            or comma and "comma"
        if not join or not recruitCandidate(p, "class" .. index) then p.i = beforeJoin; break end
        joins[#joins + 1] = join
    end
    local beforeRole = p.i
    if not roleKnown and (not uk or p:phrase("на роль")) then
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

local function recruitExclusion(p, uk)
    local start = p.i
    if not p:word(uk and "без" or "no") then return false end
    if p:noun("excluded", "classes", uk and "genitive")
        or p:noun("excluded", "roles", uk and "genitive") then return true end
    p.i = start
    return false
end

local function compactRecruitRole(p)
    local token = p.i <= p.limit and p.tokens[p.i]
    if not token or token.protected or token.key:sub(1, 2) ~= "lf" then return end
    local amount, alias = token.key:match("^lf(%d?%d?%d?)([a-z]+)$")
    if not alias or tonumber(amount) == 0 then return end
    local role = compactTerm(alias, "roles")
    local more = not role and alias:sub(1, 1) == "m"
    if more then role = compactTerm(alias:sub(2), "roles") end
    if not role then return end
    p.slots.role = {term=role}
    if amount ~= "" then p.slots[more and "total" or "count"] = {raw=amount} end
    p.i = p.i + 1
    return true
end

local function groupRoster(p, direction, afterRecruitment)
    local uk = direction == "uk-en"
    local explicit, already
    if uk then
        if not p:any("у нас", "в нас") then return end
        already = p:any("уже", "вже")
        explicit = p:word("є")
    elseif p:word("we've") then
        already = p:word("already")
        if not p:word("got") then return end
        explicit = true
    elseif afterRecruitment and p:any("have", "got") then
        explicit = true
    else
        if not p:word("we") then return end
        already = p:word("already")
        explicit = p:any("have", "got")
    end
    local members = {}
    for index = 1, 8 do
        local join
        if index > 1 then
            local comma = p:word(",")
            join = p:any("and", "&", "+", "та", "і", "й") or comma
            if join and not uk then p:any("have", "got") end
        end
        local name, countKey = "member" .. index, "memberCount" .. index
        if not p:role(name, countKey, true, true) then
            if join then return end
            break
        end
        local quantity = p.slots[countKey] and p.slots[countKey].raw
        if (index > 1 and not join or not explicit and not uk and index == 1) and not quantity then return end
        members[index] = {slot=name, quantity=quantity}
    end
    if #members == 0 then return end
    local result = p:finish("groupRoster", {members=members, already=already})
    if result and not result.features.question then return result end
end

local function lastSpotMarker(p, uk)
    if uk then return p:any("останнє місце", "залишилося одне місце", "лишилося одне місце") end
    return p:any("last spot", "last slot", "one spot left", "one slot left")
end

local function groupVacancy(p, direction)
    local uk = direction == "uk-en"
    local identity
    if uk then
        identity = p:word("це")
        if identity then
            if not p:phrase("останнє місце") then return end
        elseif not lastSpotMarker(p, uk) then return end
    else
        identity = p:any("it's", "that's", "it", "this", "that")
        if identity then
            p:word("is")
            if not p:word("the") then return end
        end
        if identity then
            if not p:any("last spot", "last slot") then return end
        elseif not lastSpotMarker(p, uk) then return end
    end
    local destination = uk and p:word("на") or not uk and p:word("for")
    local located = not destination and (uk and p:any("у", "в") or not uk and p:any("in", "at"))
    if not p:noun("place", "places", uk and (destination and "accusative" or located and "locative") or nil)
        and (destination or located) then return end
    return p:finish("groupVacancy", {identity=identity, destination=destination})
end

local recruitNoteForms = {
    {"run", "full", {"full run"}, {"повне проходження"}},
    {"run", "fresh", {"fresh run"}, {"проходження з початку"}},
    {"run", "quest", {"quest run"}, {"проходження із завданнями"}},
    {"pace", true, {"fast run","quick run"}, {"швидке проходження"}},
    {"clear", true, {"full clear"}, {"повна зачистка"}},
    {"ready", true, {"ready to go"}, {"готові вирушати","готові йти"}},
    {"urgent", true, {"fast","quick","quickly"}, {"терміново"}},
    {"summon", true, {"can summon"}, {"можемо прикликати"}},
    {"go", true, {"and go","then go","n go","n ' go"}, {"і йдемо","і вирушаємо"}},
}

local function recruitNotes(p, uk)
    local notes = {}
    for _ = 1, #recruitNoteForms do
        if p.i > p.limit then break end
        local start = p.i
        p:any(".", ",", ";")
        local matched
        for _, row in ipairs(recruitNoteForms) do
            if not notes[row[1]] and p:any(unpack(row[uk and 4 or 3])) then
                notes[row[1]], matched = row[2], true
                break
            end
        end
        if not matched then p.i = start; break end
    end
    return notes
end

local function recruit(p, direction)
    local uk = direction == "uk-en"
    local countWords = uk
    local leadingPlace, countDirect, additional, bareVacancy, bareCount
    local groupRequest = not uk and p:word("lfm")
    if uk then
        if not p:any("шукаємо", "потрібно", "потрібен", "потрібна", "потрібне", "потрібні") then return end
        additional = p:word("ще")
        groupRequest = p:word("гравців")
    elseif groupRequest or p:word("lf") or compactRecruitRole(p) then
        countWords = true
        p:word("for")
    elseif not p:any("looking for", "lookng for", "need", "we're looking for", "we are looking for", "we need") then
        local start = p.i
        if p:count() and p:word("more") then countDirect = true
        else
            p.i, p.slots.count = start, nil
            local token = p.tokens[start]
            if lastSpotMarker(p, false) then
                bareVacancy = true
                p:word("for")
            elseif token and not token.protected and token.key:match("^%d")
                and p:role("role", "count") and p.slots.count then
                bareCount = true
            else
                p.i, p.slots.role, p.slots.count = start, nil, nil
                if not p:noun("place", "places") then return end
                p:word(",")
                if not (p:any("lfm", "lf", "looking for", "lookng for", "need") or compactRecruitRole(p)) then return end
                leadingPlace, countWords = true, true
            end
        end
    end
    local count = countDirect or not p.slots.role and p:count(nil, countWords, not uk)
    additional = additional or countDirect or count and not uk and p:word("more")
    local compact = count and (p:word("m") or (uk and p:any("гравця :", "гравців :", "гравця", "гравців")))
    if compact then p.slots.total, p.slots.count = p.slots.count, nil end
    local lastSpot = bareVacancy or lastSpotMarker(p, uk)
    local role, place, refinements, destinationRun = nil, leadingPlace, nil, nil
    local roleJoins = {}
    for _ = 1, 4 do
        local separator = p:any(",", ".", ":")
        if not role and (place and separator or p.slots.excluded) then p:any("need", "потрібно", "потрібні") end
        if separator and role and not lastSpot and lastSpotMarker(p, uk) then
            lastSpot = true
        elseif not role and (p.slots.role or p:role("role", "count", countWords)) then
            role = true
            for n = 2, 4 do
                local start = p.i
                local join = p:coordination()
                local suffix = tostring(n)
                if p:role("role" .. suffix, "count" .. suffix, countWords) and (join or p.slots["count" .. suffix]) then
                    roleJoins[#roleJoins + 1] = join or "and"
                else
                    p.i = start
                    p.slots["role" .. suffix], p.slots["count" .. suffix] = nil, nil
                    break
                end
            end
        elseif not role and recruitClasses(p, uk) then
            role = true
        elseif role and not place and separator and #roleJoins == 0 and not p.classJoins
            and recruitClasses(p, uk, true) then
            refinements = true
        elseif not p.slots.excluded and recruitExclusion(p, uk) then
            -- A participation restriction can precede the requested role.
        elseif role and not p.slots.preferred and preferredClass(p, uk) then
            -- The class is a preference for the requested role.
        elseif not p.slots.level and recruitLevel(p, uk) then
            -- The level belongs to the recruitment regardless of its position.
        elseif not place then
            local start = p.i
            local runMarker = uk and p:phrase("для проходження") or not uk and p:phrase("to run")
            local introduced = runMarker or p:any("for", "для", "до", "у", "в", "місце :")
            if not introduced and not uk then p:word("to") end
            if p:noun("place", "places", uk and runMarker and "genitive") then
                local features = p.slots.place.term.features
                if runMarker and not (features and features.clearableInstance) then return end
                place, destinationRun = true, runMarker
            else
                local token = p.tokens[p.i]
                local quest = token and (token.linkKind == "quest" or token.questReference)
                if introduced and not quest and p.limit == #p.tokens then
                    p.document.preserve = p.document.preserve or {}
                    local unresolved = p.i <= p.limit and p.i or start
                    p.document.preserve[unresolved] = {last=p.limit, reason="unresolved-destination"}
                end
                p.i = start
                break
            end
        else break end
        if lastSpotMarker(p, uk) then lastSpot = true end
        if p.i < p.limit and p.tokens[p.i].key == "!" then p.i = p.i + 1 end
    end
    p:word(",")
    local start = p.i
    local questMarker = p:any("for", "на завдання")
    local quests = (questMarker or not place) and p:questList()
    if not quests then p.i = start end
    if lastSpotMarker(p, uk) then lastSpot = true end
    local vacancies = p.slots.total or p.slots.count
    if vacancies and tonumber(vacancies.raw) == 1 and #roleJoins == 0 and p:phrase("full group") then lastSpot = true end
    local notes = recruitNotes(p, uk)
    if bareVacancy and not role or bareCount and not (role and place) then return end
    if not role and not (p.slots.total or quests and groupRequest
        or place and (p.slots.count or p.slots.level or notes.run == "quest" and groupRequest)) then return end
    if lastSpot then
        local total = p.slots.total
        if total and tonumber(total.raw) > 1 then return end
        for n = 1, #roleJoins + 1 do
            if bareVacancy and n > 1 and roleJoins[n - 1] ~= "or" then return end
            local amount = p.slots[n == 1 and "count" or "count" .. n]
            if amount and tonumber(amount.raw) > 1 then return end
        end
    end
    local roster
    if p.i <= p.limit then
        local attached = state(p.document, p.limit, p.i)
        attached:any(".", ";", ",", "—", "-")
        roster = groupRoster(attached, direction, true)
        if roster then
            p.i = attached.i
            for key, slot in pairs(roster.slots) do p.slots[key] = slot end
        end
    end
    notes.lastSpot, notes.roleJoins, notes.classJoins = lastSpot, roleJoins, p.classJoins
    notes.additional, notes.quests, notes.refinements = additional, quests, refinements
    notes.roster, notes.destinationRun = roster and roster.features, destinationRun
    return p:finish("recruit", notes)
end

local function groupSearchOpening(p, uk)
    if uk then return p:any("шукаю групу", "підшукую групу") end
    return p:any("lfg", "looking for group", "looking for a group", "i'm looking for group", "i'm looking for a group")
end

local function groupRoleOffer(p, uk)
    local first = p.i
    p:word(uk and "я" or "i")
    local negative = uk and p:phrase("не можу") or not uk and p:any("can't", "cannot", "can not")
    if not negative and not p:word(uk and "можу" or "can") then p.i = first; return end
    if uk then
        if not p:any("грати за", "зіграти за", "грати як") then p.i = first; return end
    else
        p:any("play as", "be")
    end
    local offer = {roles={}, joins={}, negative=negative}
    for index = 1, 4 do
        local start = p.i
        local join = index > 1 and p:coordination()
        if index > 1 and not join then break end
        if not uk then p:any("a", "an") end
        local role, reason = M.select(p.document, p.i, "roles", p.limit)
        if reason == "ambiguous" then p.ambiguous = true end
        if not role or (role.features.number == "plural" and not role.term.en:match("^[A-Z]+$")) then
            p.i = start
            break
        end
        if join then offer.joins[index - 1] = join end
        offer.roles[index], p.i = role, role.last + 1
    end
    if #offer.roles > 0 then return offer end
    p.i = first
end

local function groupObjectives(p, uk, place)
    local start = p.i
    if place then
        p:any(".", ",", ":")
        p:word(uk and "на" or "for")
    end
    local marker = p.i
    if uk then p:word("завдання") end
    local links = p:questList()
    if links then return links end
    p.i = marker
    if ns.Linguistics and p.i <= p.limit then
        local phrases = ns.Engine.Phrases
        local noun, after = phrases.noun(p.document, p.i, p.limit, "accusative", false, nil, true)
        if noun and phrases.semanticClass(noun) == "objective" then
            p.i = after
            return nil, noun
        end
    end
    p.i = start
end

local function groupSearch(p, direction)
    local uk = direction == "uk-en"
    if uk then p:word("я") end
    if not groupSearchOpening(p, uk) then
        if not p:noun("role", "roles") then return end
        p:word(",")
        if not groupSearchOpening(p, uk) then return end
    end
    p:any(".", ",", ":")
    local offer = groupRoleOffer(p, uk)
    if offer then p:any(".", ",") end
    if not uk and not p.slots.role then
        if p:noun("role", "roles") then p:word(",") end
    end
    local destination = uk and p:any("для", "у", "в", "на", "місце :") or not uk and p:word("for")
    local place = p:noun("place", "places")
    local quests, objective = groupObjectives(p, uk, place)
    if destination and not (place or quests or objective) then return end
    p:any(".", ",")
    local role = uk and p:any("як", "роль :") or not uk and p:word("as")
    if role and (p.slots.role or not p:noun("role", "roles")) then return end
    if not offer then
        p:any(".", ",", ";")
        offer = groupRoleOffer(p, uk)
    end
    return p:finish("groupSearch", {roleOffer=offer, quests=quests, objective=objective})
end

local function search(p, direction)
    if not ns.Linguistics or p.document.truncated or p.document.ambiguities then return end
    if direction == "en-uk" then
        if p.tokens[p.limit].key == "?" and p:phrase("looking for") then return nil end
        if not p:any("lf", "looking for", "i'm looking for") then return nil end
    elseif not p:any("шукаю", "підшукую") then return nil end
    local object, after = ns.Engine.Phrases.coordinated(p.document, p.i, p.limit, "accusative")
    local purpose, group, emphatic
    if direction == "en-uk" then
        local limit = p.limit
        while limit > p.i and p.tokens[limit].key:match("^[.!?]$") do limit = limit - 1 end
        local grammar = ns.Engine.ClauseAnalysis
        local opening = p.tokens[p.first].key
        local agent, finish, action = grammar.searchQualification(p.document, p.i, limit, object, after, opening == "lf")
        if agent then
            object, after, purpose = agent, finish, action
            emphatic = p.tokens[p.limit].key == "!"
            group = opening ~= "i'm" and grammar.recruitmentCompanion(action or agent.relative.clause)
        end
    end
    if not object then return nil end
    if object.term then p.slots.object = {term=object.term} end
    p.i = after
    return p:finish("search", {object=object, purpose=purpose, group=group, emphatic=emphatic})
end

local function enhancementBonus(p, suffix, english, allowOption)
    local count, stat = "count" .. suffix, "stat" .. suffix
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
    return true
end

local function enhancementEquipment(p, equipment, english)
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
    if noun.term.forms and noun.term.forms[noun.locative] then return true end
    p.i, p.slots[equipment] = start, nil
end

local function enhancementItem(p, suffix, english, allowOption, offer)
    local equipment = "equipment" .. suffix
    local equipmentFirst = offer and english and enhancementEquipment(p, equipment, english)
    if not enhancementBonus(p, suffix, english, allowOption) then return end
    if not equipmentFirst then
        local marker = p:any("on", "на", "до")
        if not (marker or offer and english) or not enhancementEquipment(p, equipment, english) then return end
    end
    if offer then
        local beforePrice = p.i
        p:any("for", "за", "-", "—", "–")
        if not p:money("price" .. suffix) then p.i = beforePrice end
    end
    return true
end

local function enhancementOfferMarker(p, english)
    if english then
        if p:any("offering enchants", "selling enchants") then return "enchanting" end
        if p:word("wts") then return "selling" end
    else
        if p:phrase("пропоную зачарування") then return "enchanting" end
        if p:word("продам") then return "selling" end
    end
end

local function enhancementOffer(p, english)
    local offer = enhancementOfferMarker(p, english)
    if offer then p:word(":"); return offer end
    local first = p.i
    local N, P = ns.Engine.Normalize, ns.Engine.Phrases
    for separator = first, math.min(first + 6, p.limit - 1) do
        local mark = p.tokens[separator]
        if mark.protected then return end
        if mark.key == "," or mark.key == ":" then
            if separator < first + 2 then return end
            local last = p.tokens[separator - 1]
            p.i = separator + 1
            offer = enhancementOfferMarker(p, english)
            if offer then
                local profession = compactTerm(last.key, "professions")
                if not profession then
                    local choice = M.select(p.document, separator - 1, "professions", separator - 1)
                    profession = choice and choice.term
                end
                if profession then
                    if profession.id == "profession.enchanting" then offer = "enchanting" end
                    p:word(":")
                    return offer, P.raw(p.document, first, separator - 1)
                end
            end
            p.i = first
            return
        end
        local word = P.raw(p.document, separator, separator)
        if word == mark.key or word ~= N.upperStart(word) then return end
    end
end

local function enhancementMaterials(p, english)
    local before = p.i
    p:word(",")
    local marked = p:any("with", "з", "зі", "із")
    local P = ns.Engine.Phrases
    if not marked and not english then p.i = before; return end
    local materials, after = P.noun(p.document, p.i, p.limit, english and "accusative" or "instrumental",
        false, false, true)
    if P.semanticClass(materials) == "craftingMaterials" and (marked or materials.possessor) then
        p.i = after
        return materials
    end
    p.i = before
end

local function zeroPrice(p)
    return p:any("for free", "free of charge", "free", "безкоштовно", "безплатно")
end

local function gratuity(p, free)
    local start = p.i
    p:any(",", ".", "|", "i", "—")
    if p:any("tips", "gratuities") then
        p:word("are")
        if p:any("appreciated", "greatly appreciated", "welcome") then return "appreciated" end
        if p:word("accepted") then return "accepted" end
    else
        if p:any("буду вдячний за чайові", "дякую за чайові") then return "appreciated" end
        if p:any("приймаю чайові", "чайові приймаються") then return "accepted" end
        if free and p:any("with tips", "з чайовими", "із чайовими") then return "with" end
    end
    p.i = start
end

local function gratuityNote(p)
    local tips = gratuity(p)
    if not tips then return end
    local emote, after = emoteAt(p, p.i, p.limit)
    if emote then p.i = after end
    local references = {}
    for index = 1, 4 do
        local slot = "reference" .. index
        if not (p:link(slot, "enchant") or p:link(slot, "trade")) then break end
        references[index] = p.slots[slot].raw
    end
    return p:finish("gratuityNote", {tips=tips, inlineEmote=emote, references=references})
end

local function enchantmentStats(p, slot)
    local start, stats = p.i, {}
    for index = 1, 4 do
        local stat = slot .. "Stat" .. index
        if not p:noun(stat, "stats") then break end
        stats[index] = stat
        if not p:word("/") then return stats end
    end
    for _, stat in ipairs(stats) do p.slots[stat] = nil end
    p.i = start
end

local function enchantmentMember(p, english, index)
    local start, slot = p.i, "enchantment" .. index
    local quoted = p:word("«")
    if p:link(slot, "enchant") or p:noun(slot, "craftServices") then
        local entry = p.slots[slot]
        local features = entry.term and entry.term.features
        if (entry.raw or features and features.serviceProfession == "profession.enchanting")
            and (not quoted or p:word("»")) then
            if english then p:any("enchants", "enchantments") end
            return {kind="recipe", slot=slot}, true
        end
    end
    p.i, p.slots[slot] = start, nil

    local explicit = english and p:any("enchants for", "enchantments for")
        or not english and p:any("зачарування на", "чари на")
    local stats = english and enchantmentStats(p, slot) or nil
    if stats and not explicit then explicit = p:any("enchants for", "enchantments for") end
    if (english or explicit) and p:noun(slot, "equipment", not english and "accusative" or nil) then
        local features = p.slots[slot].term.features
        if features and features.enchantmentSlot then
            local qualified = explicit or english and p:any("enchants", "enchantments")
            if not english and p:word("(") then
                stats = enchantmentStats(p, slot)
                if not stats or not p:word(")") then return nil end
            end
            return {kind="slot", slot=slot, stats=stats}, qualified or stats ~= nil
        end
    end
    for _, stat in ipairs(stats or {}) do p.slots[stat] = nil end
    p.i, p.slots[slot] = start, nil
    local additive = not english and p:word("ще")
    local other = not additive and (english and p:word("other") or not english and p:word("інші"))
    local P = ns.Engine.Phrases
    local plural = other and function(head) return head.number == "plural" end
    local noun, after = P.noun(p.document, p.i, p.limit, "nominative", nil, nil, nil, nil, plural)
    if noun and (P.quantifiedSubject(noun) or other) and P.hasTrait(noun, "enchantment")
        and (not additive or noun.many) then
        if additive then noun.more, noun.degreeMore, noun.many = true, true, nil
        elseif other then noun.more = true end
        p.i = after
        return {kind="amount", noun=noun}, true
    end
    p.i = start
end

local function enchantmentList(p, direction)
    if not ns.Linguistics then return end
    local english = direction == "en-uk"
    local qualified, status
    if english and p:any("available enchants", "available enchantments", "enchants available", "enchantments available") then
        if not p:word(":") then return end
        qualified, status = true, "available"
    elseif not english then
        status = p:word("доступні") and "available" or p:word("недоступні") and "unavailable"
        if not status then return end
        p:word(":")
    end
    if not status then
        local last = p.limit
        if emoteAt(p, last - 1, last) then last = last - 2 end
        while last >= p.i and p.tokens[last].key:match("^[.!?]$") do last = last - 1 end
        local predicate = ns.Engine.Phrases.key(p.document, last, p.limit)
        if predicate ~= "available" and predicate ~= "unavailable" then return end
    end

    local items, joins = {}, {}
    local nextJoin
    for index = 1, 6 do
        local item, identifiesOffer = enchantmentMember(p, english, index)
        if not item then return end
        items[index], joins[index] = item, nextJoin
        qualified = qualified or identifiesOffer
        local comma = p:word(",")
        nextJoin = p:any("and", "і", "й", "та") and "and"
            or p:any("or", "або") and "or" or comma and "comma"
        if not nextJoin then break end
        if index == 6 then return end
    end
    if #items == 1 and items[1].kind ~= "slot" or not qualified then return end
    if not status then
        status = p:any("are not available", "not available", "are unavailable", "unavailable") and "unavailable"
            or p:any("are available", "available") and "available"
        if not status then return end
    end
    local exclamation = p.i <= p.limit and p.tokens[p.i].key == "!"
    return p:finish("enchantmentList", {items=items, joins=joins, status=status, exclamation=exclamation})
end

local function takeProfession(p, english, demand)
    if english and demand then p:any("a", "an") end
    local first = p.i
    if not p:noun("profession", "professions") then
        if english or not demand or not p:word("майстра") or not p:noun("profession", "professions") then return end
    end
    local term = p.slots.profession.term
    local forms = term.renderForms
    local name = english and term.englishPractitioner or not english and forms and forms.practitioner
    local normalize = ns.Engine.Normalize.key
    local person = name and normalize(ns.Engine.Phrases.raw(p.document, first, p.i - 1)) == normalize(name)
    return true, person
end

local function enhancement(p, direction)
    local english = direction == "en-uk"
    local offer, header = enhancementOffer(p, english)
    local demand, inquiry
    if not offer and english then
        inquiry = p:any("any", "is there an", "is there a")
        demand = inquiry or p:any("lf", "looking for")
    elseif not offer then
        inquiry = p:any("чи є", "є")
        demand = inquiry or p:any("шукаю", "потрібен")
    end
    if demand then
        if not takeProfession(p, english, true) then return end
        if not p:any("for", "with", "для", "з", "—") then return end
    end
    if not enhancementItem(p, "", english, demand or offer, offer) then return end
    local joins, mats = {}
    while p.i <= p.limit do
        local comma = p:word(",")
        mats = p:any("got mats", "have mats", "i have mats", "матеріали є", "маю матеріали")
        if mats then break end
        local join = p:any("and", "і", "й", "та") and "and"
            or p:any("or", "або") and "or" or comma and "comma"
        if not join then break end
        local before = p.i
        if not enhancementItem(p, tostring(#joins + 2), english, true, offer) then
            if join ~= "comma" then return end
            p.i = before
            break
        end
        joins[#joins + 1] = join
    end
    local materials = offer and enhancementMaterials(p, english)
    local free = zeroPrice(p)
    local tips = gratuity(p, free)
    local beforeStock = p.i
    if offer then p:any(",", ".", "-", "—", "–") end
    local limited = offer and p:any("limited stock", "limited supply", "запас обмежений", "запаси обмежені")
    if not limited then p.i = beforeStock end
    return p:finish("enhancement", {demand=demand, inquiry=inquiry, question=inquiry, mats=mats,
        free=free, tips=tips, joins=joins, offer=offer, header=header, materials=materials, limited=limited})
end

local function enchantmentSlot(p, case)
    local start = p.i
    if p:noun("equipment", "equipment", case) then
        local equipment = p.slots.equipment.term
        if equipment.features and equipment.features.enchantmentSlot then return true end
    end
    p.i, p.slots.equipment = start, nil
end

local function enchantmentTrade(p, direction)
    if not ns.Linguistics then return nil end
    local english = direction == "en-uk"
    local buy = p:word(english and "wtb" or "куплю")
    if not (buy or p:word(english and "wts" or "продам")) then return nil end
    p:word(":")
    if english then
        p:any("a", "an", "the")
        enchantmentSlot(p)
        p:noun("stat", "stats")
    end
    local phrases = ns.Engine.Phrases
    local noun, after = phrases.noun(p.document, p.i, p.limit, "accusative", nil, nil, true, nil,
        function(head) return phrases.hasTrait(head, "enchantment") end)
    if not noun then return nil end
    p.i = after
    if not english and p:word("на") and not p:noun("stat", "stats", "accusative") then return nil end
    if not p.slots.equipment then
        local marker = english and p:any("for", "on") or not english and p:word("для")
        if marker and not enchantmentSlot(p, not english and "genitive" or nil) then return nil end
    end
    if not (p.slots.stat or p.slots.equipment) then return nil end
    return p:finish("enchantmentTrade", {buy=buy, enchantment=noun})
end

local function service(p, direction)
    local english = direction == "en-uk"
    local demand, offer
    if english then
        demand = p:any("wtb", "lf", "looking for")
        if not demand then offer = p:any("wts", "lfw", "offering", "selling", "crafting") end
    else
        demand = p:any("шукаю послуги", "шукаю")
        if not demand then offer = p:any("пропоную послуги", "пропоную", "послуги") end
    end
    p:word(":")
    local linked = p:link("trade", "trade") or p:link("trade", "enchant")
    local practitioner
    if linked then
        for index = 2, 4 do
            local previous = p.i
            p:word(",")
            if not p:link("trade" .. index, "enchant") then p.i = previous; break end
        end
    else
        local qualified = english and demand and p:noun("recipe", "craftServices")
        local found
        found, practitioner = takeProfession(p, english, demand)
        if not found or qualified and not practitioner then return end
    end
    if not demand and not offer then offer = p:any("lfw", "приймаю замовлення") end
    if demand and not linked then
        local withRecipe
        if not p.slots.recipe then
            local start = p.i
            withRecipe = p:any("with recipe", "with", "із рецептом", "з рецептом")
            local specified = withRecipe or p:any("for", "для чарів", "для зачарування", "із зачаруванням", "з зачаруванням")
            if not specified then withRecipe = p:any("зі", "із") end
            if specified or withRecipe then
                local quoted = p:word("«")
                if p:noun("recipe", "craftServices") or p:link("recipe", "enchant") then
                    if quoted and not p:word("»") then return end
                else
                    p.i = start
                end
            end
        end
        local recipe = p.slots.recipe
        if recipe and recipe.term then
            local features = recipe.term.features
            if not features or features.serviceProfession ~= p.slots.profession.term.id then return end
        end
        if recipe then
            local before = p.i
            p:word(",")
            local mats = p:any("got mats", "have mats", "i have mats", "матеріали є", "маю матеріали")
            if not mats then p.i = before end
            return p:finish("service", {demand=true, practitioner=true, withRecipe=withRecipe, mats=mats})
        end
    end
    local free = zeroPrice(p)
    local priceIntroduced = not free and p:any("for", "за")
    local priced = not free and p:money()
    if priceIntroduced and not priced then return end
    local previous = p.i
    p:any("-", "—", ",")
    local materials = p:any("with your mats", "with your materials", "bring mats", "bring your own materials",
        "з вашими матеріалами", "з твоїми матеріалами", "принесіть матеріали")
    if not materials then p.i = previous end
    local promise = materials and p:any("and i make for you", "and i'll make it", "і я виготовлю", ", і я виготовлю")
    local tips = not demand and gratuity(p, free)
    if not (demand or offer or linked and (free or tips)) then return end
    local places
    if tips then
        local P = ns.Engine.Phrases
        places = {}
        for index = 1, 2 do
            local before = p.i
            p:word(",")
            local place, after = P.preposition(p.document, p.i, p.limit, nil, nil, "predicate")
            if not place or not (P.spatialAdjuncts[place.rule.id] or place.rule.id == "out-of-location") then
                p.i = before
                break
            end
            places[index], p.i = place, after
        end
    end
    return p:finish("service", {demand=demand, practitioner=practitioner, priced=priced, free=free, materials=materials, promise=promise,
        tips=tips, places=places})
end

local function roleInquiry(p, direction)
    local english = direction == "en-uk"
    local explicit, here
    if english then
        explicit = p:any("any", "is there a", "is there an")
    else
        explicit = p:phrase("чи є")
        here = explicit and p:word("тут")
    end
    if not p:noun("role", "roles", not english and "nominative" or nil)
        or not p:word(english and "for" or "на") then return end

    local start = p.i
    local name, unresolved
    if p:noun("place", "places", not english and "accusative" or nil) then
        local features = p.slots.place.term.features
        if not features or not features.clearableInstance then return end
    else
        if not english or p.ambiguous then return end
        local last = p.limit - 1
        if p.tokens[last].key == "here" then last = last - 1 end
        if last < start or p.tokens[start].protected then return end
        local after
        name, after = ns.Engine.Phrases.openName(p.document, start, last)
        if not name or after ~= last + 1 then return end
        unresolved = {first=start, last=last, reason="unresolved-destination"}
        p.i = after
    end
    here = here or p:word(english and "here" or "тут")
    return p:finish("roleInquiry", {explicit=explicit, here=here, name=name, unresolved=unresolved})
end

local function availability(p, direction)
    if not ns.Linguistics or p.document.truncated or p.document.ambiguities then return end
    local english = direction == "en-uk"
    if english then
        if not p:any("any", "is there a", "is there an") then return end
    elseif not p:any("чи є", "є") then return end
    local P = ns.Engine.Phrases
    if english and (not p:count("skill") or not p:word("+")) then return end
    local occupation, after = P.noun(p.document, p.i, p.limit, "nominative", nil, nil, true)
    if P.semanticClass(occupation) ~= "occupation" then return end
    p.i = after
    if not english and (not p:phrase("із навичкою") or not p:count("skill") or not p:word("+")) then return end
    if not p:any("online", "around", "here", "онлайн", "у мережі", "поблизу", "тут") then return end
    local place = p.tokens[p.i - 1].key
    if place == "мережі" then place = "online" end
    return p:finish("availability", {question=true, place=place, occupation=occupation})
end

local pricedClasses = {goods=true, equipment=true, consumables=true, resource=true, craftingMaterials=true, services=true}

local function pricedObject(noun)
    if noun.members then
        for _, member in ipairs(noun.members) do
            if not pricedObject(member) then return false end
        end
        return true
    end
    return pricedClasses[ns.Engine.Phrases.semanticClass(noun)]
        or noun.term and noun.term.category == "goods"
        or noun.raw and (ns.Engine.Markup.isLink(noun.raw, "item") or ns.Engine.Markup.isLink(noun.raw, "enchant"))
end

local function freeOffer(p)
    local prefixed = zeroPrice(p)
    if prefixed then
        local label = p:word(":")
        if not label and p.i <= p.limit and p.tokens[p.i].key == "the" then return end
    else
        local last = p.limit
        while last > p.first and p.tokens[last].key:match("^[.!?]$") do last = last - 1 end
        local key = p.tokens[last].key
        if last == p.first or not (key == "free" or key == "charge" or key == "безкоштовно" or key == "безплатно") then return end
    end
    local object
    if ns.Linguistics then
        local after
        object, after = ns.Engine.Phrases.coordinated(p.document, p.i, p.limit, "nominative",
            nil, nil, true, "lootItem", nil, true)
        if not object or not pricedObject(object) then return end
        p.i = after
    elseif not (p:link("item", "item") or p:link("item", "enchant")) then return end
    if not prefixed then
        p:any("—", "–", ":")
        if not zeroPrice(p) then return end
    end
    local recipient
    if ns.Linguistics and p.i < p.limit then
        local phrase, after = ns.Engine.Phrases.preposition(p.document, p.i, p.limit)
        if phrase and phrase.rule.id == "for" then recipient, p.i = phrase, after end
    end
    local ending = p.i
    local offer = p:finish("freeOffer", {object=object, recipient=recipient})
    if offer and not offer.features.emote and ending <= p.limit then
        offer.features.punctuation = p.document.text:sub(p.tokens[ending].first, p.tokens[p.limit].last)
    end
    return offer
end

local function price(p)
    local linked = p:link("item", "item")
    local introduced = linked and p:any("for", "за")
    local only = p:any("only", "лише")
    if not p:money() then return end
    local each = p:any("a bottle", "per bottle", "за пляшку") and "bottle"
        or p:any("each", "per item", "за штуку") and "unit"
    return p:finish("price", {only=only, linked=linked, each=each, introduced=introduced})
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

local function questAttendance(p, direction)
    local quests
    if direction == "en-uk" then
        if p:any("anyone", "anybody") then
            p:word("for")
            quests = p:questList()
        else
            quests = p:questList()
            if not quests then return end
            p:word(",")
            if not p:any("anyone", "anybody") then return end
        end
    elseif p:any("хтось іде на завдання", "хтось йде на завдання") then
        quests = p:questList()
    end
    if quests then return p:finish("questAttendance", {quests=quests, question=true}) end
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

local parsers = {recruit, groupRoster, groupVacancy, enhancement, availability, enchantmentTrade, service, enchantmentList, gratuityNote, reward, questNeed, questAttendance,
    statement, freeOffer, price, groupSearch, search}
function S.parse(document, limit, first)
    if document.checkpoint then document.checkpoint() end
    limit, first = limit or #document.tokens, first or 1
    local ending = document.tokens[limit]
    if ending and ending.key == "?" and not (document.truncated or document.ambiguities) then
        local result = roleInquiry(state(document, limit, first), document.direction)
        if result then return result end
    end
    for _, parse in ipairs(parsers) do
        local result = parse(state(document, limit, first), document.direction)
        if result then return result end
    end
end

function S.translateRange(document, first, last, allowPartial)
    local tree = S.parse(document, last, first)
    if tree then
        if tree.features.unresolved and not allowPartial then return nil end
        local output = ns.Engine.Transfer.render(tree, document.direction)
        if output and tree.features.question then output = output:gsub("[.!?]+$", "") .. "?" end
        if output and tree.features.emote then output = output:gsub("%.$", "") .. " " .. tree.features.emote end
        if output and not document.truncated then return output, tree end
    end
end

function S.translate(document)
    local output, tree = S.translateRange(document, 1, #document.tokens, true)
    if output then return output, tree end
    -- Preserve the original remainder, including unknown conditions and links.
    -- No unbounded chart search and no reconstruction of the input from words.
    local minimum = math.max(1, #document.tokens - 24)
    for last = #document.tokens - 1, minimum, -1 do
        tree = S.parse(document, last)
        if tree and not tree.features.unresolved and tree.kind ~= "price" and tree.kind ~= "search" and tree.kind ~= "groupSearch" then
            local output = ns.Engine.Transfer.render(tree, document.direction)
            if output then
                return nil, nil, {[1]={text=output:gsub("[.!]+$", ""), last=last,
                    rule={sourceRefs={"project-authored:apertium-pipeline-1"}}, slots=tree.slots}}
            end
        end
    end
end
