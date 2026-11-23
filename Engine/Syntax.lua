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
function State:noun(name, category, case, correctDungeonSpelling)
    local first = self.i
    local candidate, reason = M.select(self.document, first, category, self.limit, case)
    local token = self.tokens[first]
    if not (candidate or reason) and category == "places" and self.document.direction == "en-uk"
        and first < self.limit and token.key == "the" then
        first = first + 1
        candidate, reason = M.select(self.document, first, category, self.limit, case)
    end
    if not (candidate or reason) and correctDungeonSpelling and first <= self.limit then
        candidate = M.dungeonSpelling(self.document, first)
    end
    if reason == "ambiguous" then self.ambiguous = true end
    if not candidate then return false end
    self.slots[name] = {term=candidate.term, analysis=candidate,
        plural=candidate.features.number == "plural"}
    self.i = candidate.last + 1
    return true
end
function State:count(slot, words, multiplicity, allowZero)
    local token = self.tokens[self.i]
    if self.i > self.limit or token.protected then return false end
    local amount = #token.key <= 3 and token.key:match("^%d+$")
    if multiplicity and not amount then
        amount = token.key:match("^(%d%d?%d?)x$") or token.key:match("^(%d%d?%d?)×$")
    end
    local spelled
    if not amount and words then
        local cardinal = ns.Engine.Phrases.cardinal(self.document, token.key, "genitive")
        if cardinal then amount, spelled = tostring(cardinal), true end
    end
    if not amount or (not allowZero and tonumber(amount) == 0) then return false end
    self.slots[slot or "count"] = {raw=amount, spelled=spelled}
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
    local classAllowed = allowClass and (allowClass ~= "counted" or self.slots[countKey])
    if self:noun(name, "roles") or classAllowed and self:noun(name, "classes") then return true end
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
    local question = ns.Engine.Normalize.tokenQuestion(self.document.text, self.tokens, self.first, ending)
    if question then extra.question, extra.questionEnd = true, question end
    while self.i <= ending and self.tokens[self.i].key:match("^[.!?]$") do self.i = self.i + 1 end
    if self.i <= ending or self.ambiguous then return nil end
    return {kind=kind, slots=self.slots, features=extra, first=self.first, last=self.limit}
end
-- Reuse the attempt state while keeping each parser's slots and flags isolated.
function State:reset()
    self.i, self.ambiguous, self.classJoins = self.first, nil, nil
    if next(self.slots) then self.slots = {} end
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

local function readyToGo(p, uk)
    if uk then return p:any("готові вирушати", "готові йти") end
    return p:any("ready to go", "good to go")
end

local function groupRoster(p, direction, afterRecruitment)
    local uk = direction == "uk-en"
    local explicit, already, readyOnly
    if uk then
        if p:any("у нас", "в нас") then
            already = p:any("уже", "вже")
            explicit = p:word("є")
        elseif afterRecruitment then readyOnly = true
        else return end
    elseif p:word("we've") then
        already = p:word("already")
        if not p:word("got") then return end
        explicit = true
    elseif afterRecruitment and p:any("have", "got") then
        explicit = true
    elseif p:word("we") then
        already = p:word("already")
        explicit = p:any("have", "got")
    elseif afterRecruitment then readyOnly = true
    else return end
    local members = {}
    for index = 1, 8 do
        local join
        if index > 1 then
            local comma = p:word(",")
            join = p:any("and", "&", "+", "та", "і", "й") or (readyOnly and not uk and p:word("n")) or comma
            if join and not uk then p:any("have", "got") end
        end
        local name, countKey = "member" .. index, "memberCount" .. index
        if not p:role(name, countKey, true, true) then
            if join then return end
            break
        end
        local quantity = p.slots[countKey] and p.slots[countKey].raw
        if (index > 1 and not join or not explicit and not readyOnly and not uk and index == 1)
            and not quantity then return end
        members[index] = {slot=name, quantity=quantity}
    end
    if #members == 0 then return end
    local ready
    if readyOnly then
        if #members < 2 then return end
        if readyToGo(p, uk) then ready = "toGo"
        elseif p:word(uk and "готові" or "ready") then ready = "ready"
        else return end
    end
    local result = p:finish("groupRoster", {members=members, already=already, ready=ready})
    if result and not result.features.question then return result end
end

local function lastSpotMarker(p, uk)
    if uk then return p:any("останнє місце", "залишилося одне місце", "лишилося одне місце") end
    return p:any("last spot", "last slot", "one spot left", "one slot left")
end

local function countedVacancy(p, uk)
    if uk and not p:any("залишилося", "лишилося") then return end
    local writtenOne = p:word(uk and "одне" or "one")
    if not writtenOne and not p:count("vacancies") then return end
    if uk then
        if not p:any("місце", "місця", "місць") then return end
        p:any("у групі", "в групі")
        if not p:word("до") then return end
    elseif not p:any("spot", "spots", "slot", "slots", "place", "places")
        or not p:phrase("left for") then return end
    if not p:noun("place", "places", uk and "genitive" or nil, not uk) then return end
    local features = p.slots.place.term.features
    if not (features and features.clearableInstance) then return end
    return p:finish("groupVacancy", {counted=true, writtenOne=writtenOne})
end

local function groupVacancy(p, direction)
    local uk = direction == "uk-en"
    local start = p.i
    local counted = countedVacancy(p, uk)
    if counted then return counted end
    p.i, p.slots.vacancies, p.slots.place = start, nil, nil
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
    {"urgent", true, {"fast","quick","quickly"}, {"терміново"}},
    {"summon", true, {"can summon"}, {"можемо прикликати"}},
    {"go", true, {"and go","then go","n go","n ' go"}, {"і йдемо","і вирушаємо"}},
    {"fillsGroup", true, {"and full", "and we're full", "and we are full", "then we're full",
        "then the group will be full"}, {"після цього група буде повна", "і група буде повна"}},
}

local function recruitReadiness(p, uk)
    local start = p.i
    local afterFill
    if uk then
        afterFill = p:phrase("після цього") and p:phrase("можемо вирушати")
    else
        afterFill = p:any("and then", "and", "then") and p:any("we're", "we are") and readyToGo(p, false)
    end
    if afterFill then return "afterFill" end
    p.i = start
    return readyToGo(p, uk)
end

local function recruitNotes(p, uk)
    local notes = {}
    for _ = 1, #recruitNoteForms + 1 do
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
        if not matched and not notes.ready then
            notes.ready = recruitReadiness(p, uk) or nil
            matched = notes.ready
        end
        if not matched then p.i = start; break end
    end
    return notes
end

function S.recruitRoleRequestEnd(tokens, first, last)
    if first >= last or tokens[first].protected then return end
    local key = tokens[first].key
    if key == "need" then return first + 1 end
    if first + 1 < last and not tokens[first + 1].protected then
        local nextKey = tokens[first + 1].key
        if key == "we" and nextKey == "need" or key == "looking" and nextKey == "for" then return first + 2 end
    end
end

local function instanceWing(p, index)
    local selected, ending
    for last = p.i, math.min(p.limit, p.i + 11) do
        local token = p.tokens[last]
        if token.protected then break end
        index = index[token.key]
        if type(index) ~= "table" then break end
        if index._id then selected, ending = ns.Data.terms[index._id], last + 1 end
    end
    if selected then p.i = ending; return {term=selected} end
end

local function recruitWings(p, uk)
    local term = p.slots.place.term
    local parent = term.features and term.features.instanceParent
    local index = ns.Data.instanceWings and ns.Data.instanceWings[parent or term.id]
    index = index and index[p.document.direction]
    if not index then return end
    local joins
    for _ = 1, 4 do
        local start = p.i
        local join = p:coordination()
        if (not join or join == "comma") and p:word(uk and "потім" or "then") then join = "then" end
        if not parent and not join and p:word(":") then join = "comma" end
        if not join or not parent and join ~= "comma" or joins and #joins == 3 then
            p.i = start
            break
        end
        local wing = instanceWing(p, index)
        if not wing then p.i = start; break end
        if not parent then
            p.slots.place, parent = wing, term.id
        else
            joins = joins or {}
            joins[#joins + 1] = join
            p.slots["place" .. (#joins + 1)] = wing
        end
    end
    return joins
end

local function recruit(p, direction)
    local uk = direction == "uk-en"
    local bareGroupWords = uk
    local leadingPlace, countDirect, additional, bareVacancy, bareCount, openRecruitment, needsRoles
    local groupRequest = not uk and p:word("lfm")
    if uk then
        if not p:any("шукаємо", "потрібно", "потрібен", "потрібна", "потрібне", "потрібні") then return end
        additional = p:word("ще")
        groupRequest = p:word("гравців")
    elseif groupRequest or p:word("lf") or compactRecruitRole(p) then
        bareGroupWords = true
        p:word("for")
    elseif p:any("recruiting for", "recruiting players for") then
        openRecruitment = true
    elseif p:any("need", "we need") then
        needsRoles = true
    elseif not p:any("looking for", "lookng for", "we're looking for", "we are looking for") then
        local start = p.i
        local leadingCount = p:count(nil, true)
        if leadingCount and p:word("more") then countDirect = true
        else
            p.i, p.slots.count = start, nil
            local token = p.tokens[start]
            if lastSpotMarker(p, false) then
                bareVacancy = true
                p:word("for")
            elseif token and not token.protected and (leadingCount or token.key:match("^%d"))
                and p:role("role", "count", true) and p.slots.count then
                bareCount = true
            else
                p.i, p.slots.role, p.slots.count = start, nil, nil
                if not p:noun("place", "places") then return end
                p:any(",", ":", "-", "—", "–")
                if not (p:any("lfm", "lf", "looking for", "lookng for", "need") or compactRecruitRole(p)) then return end
                leadingPlace, bareGroupWords = true, true
            end
        end
    end
    local count = countDirect or not p.slots.role and p:count(nil, true, not uk)
    additional = additional or countDirect or count and not uk and p:word("more")
    local compact = count and (p:word("m") or (uk and p:any("гравця :", "гравців :", "гравця", "гравців")))
    if compact then p.slots.total, p.slots.count = p.slots.count, nil end
    local lastSpot = bareVacancy or lastSpotMarker(p, uk)
    local role, place, refinements, destinationRun = nil, leadingPlace, nil, nil
    local destinationRoles, wingJoins, roleNeeded
    local roleJoins = {}
    for _ = 1, 4 do
        local separator = p:any(",", ".", ":")
        local roleRequest
        if not role then
            if not uk and place then
                local after = S.recruitRoleRequestEnd(p.tokens, p.i, p.limit)
                if after then p.i, roleRequest = after, true end
            elseif p.slots.excluded or place and separator then
                p:any("need", "потрібно", "потрібні")
            end
        end
        local classes = roleRequest and "counted"
        if separator and role and not lastSpot and lastSpotMarker(p, uk) then
            lastSpot = true
        elseif not role and (p.slots.role or p:role("role", "count", true, classes)) then
            role, destinationRoles = true, roleRequest
            for n = 2, 4 do
                local start = p.i
                local join = p:coordination()
                local suffix = tostring(n)
                if p:role("role" .. suffix, "count" .. suffix, true, classes)
                    and (join or p.slots["count" .. suffix] or roleRequest) then
                    roleJoins[#roleJoins + 1] = join or "and"
                else
                    p.i = start
                    p.slots["role" .. suffix], p.slots["count" .. suffix] = nil, nil
                    break
                end
            end
            if not uk and (countDirect or bareCount) and p:any("needed", "is needed", "are needed") then
                if ns.Engine.Phrases.key(p.document, p.i, p.limit) ~= "for" then return end
                roleNeeded = true
            end
        elseif not role and recruitClasses(p, uk) then
            role = true
        elseif roleRequest then
            return
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
            local introduced = runMarker or p:any("for", "для", "до", "у", "в", "місце :", "місця :")
            if not introduced and not uk then p:word("to") end
            if p:noun("place", "places", uk and runMarker and "genitive",
                not uk and (role or introduced or openRecruitment)) then
                local features = p.slots.place.term.features
                if runMarker and not (features and features.clearableInstance) then return end
                place, destinationRun = true, runMarker
                wingJoins = recruitWings(p, uk)
            else
                local token = p.tokens[p.i]
                local quest = token and (token.linkKind == "quest" or token.questReference)
                if introduced and not quest and p.i <= p.limit and p.limit == #p.tokens then
                    local last = p.limit
                    for i = p.i, last do
                        if ns.Engine.Parser.sentenceBoundary(p.document.text, p.tokens, i) then
                            last = i - 1
                            break
                        end
                    end
                    if last >= p.i then
                        p.document.preserve = p.document.preserve or {}
                        p.document.preserve[p.i] = {last=last, reason="unresolved-destination"}
                    end
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
    if bareVacancy and not role or bareCount and not (role and place) or roleNeeded and not place then return end
    if not role and vacancies and vacancies.spelled and not bareGroupWords then return end
    if not role and not (p.slots.total or quests and groupRequest
        or place and (openRecruitment or p.slots.count or p.slots.level or notes.run == "quest" and groupRequest)) then return end
    if lastSpot then
        local total = p.slots.total
        local conflict = total and tonumber(total.raw) > 1
        for n = 1, #roleJoins + 1 do
            local join = roleJoins[n - 1]
            local amount = p.slots[n == 1 and "count" or "count" .. n]
            if join and join ~= "or" or amount and tonumber(amount.raw) > 1 then
                conflict = true
                break
            end
        end
        if conflict then
            -- Keep the coordinated request intact. Treating its parts as separate
            -- clauses could hide the conflict between roles and available places.
            notes.unresolved = {first=p.first, last=p.limit, reason="conflicting-vacancy"}
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
    notes.roster, notes.destinationRun, notes.roleNeeded = roster and roster.features, destinationRun, roleNeeded
    notes.wingJoins = wingJoins
    notes.needsRoles = needsRoles and place and not p.slots.total
        and (roleJoins[1] == "and" or roleJoins[1] == "comma")
    notes.destinationRoles = notes.needsRoles
        or destinationRoles and (not p.slots.count or p.slots.role.term.category == "classes")
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
    local place = p:noun("place", "places", nil, not uk and (destination or p.slots.role))
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
        local start = p.i
        local finalOffer = p:word("last")
        local free = p:word("free")
        if free or not finalOffer and p:any("offering", "selling") then
            local plural = p:any("enchants", "enchantments")
            if plural or p:any("enchant", "enchantment") then
                return "enchanting", free, finalOffer and (plural and "plural" or "singular")
            end
        end
        p.i = start
        if p:word("wts") then return "selling" end
    else
        if p:phrase("останнє безкоштовне зачарування") then return "enchanting", true, "singular" end
        if p:phrase("останні безкоштовні зачарування") then return "enchanting", true, "plural" end
        if p:phrase("пропоную зачарування") then return "enchanting" end
        if p:word("продам") then return "selling" end
    end
end

local function enhancementOffer(p, english)
    local offer, free, finalOffer = enhancementOfferMarker(p, english)
    if offer then
        p:word(":")
        return offer, nil, free, finalOffer
    end
    local first = p.i
    local N, P = ns.Engine.Normalize, ns.Engine.Phrases
    for separator = first, math.min(first + 6, p.limit - 1) do
        local mark = p.tokens[separator]
        if mark.protected then return end
        if mark.key == "," or mark.key == ":" then
            if separator < first + 2 then return end
            local last = p.tokens[separator - 1]
            p.i = separator + 1
            offer, free, finalOffer = enhancementOfferMarker(p, english)
            if offer then
                local profession = compactTerm(last.key, "professions")
                if not profession then
                    local choice = M.select(p.document, separator - 1, "professions", separator - 1)
                    profession = choice and choice.term
                end
                if profession then
                    if profession.id == "profession.enchanting" then offer = "enchanting" end
                    p:word(":")
                    return offer, P.raw(p.document, first, separator - 1), free, finalOffer
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
    if p:any("tip", "tips", "gratuities") then
        p:any("are", "is")
        if p:any("appreciated", "greatly appreciated", "welcome", "would be nice") then
            local after = p.i
            p:word(",")
            if p:any("but not expected", "but not required", "but not needed", "but optional") then
                return "appreciatedOptional"
            end
            p.i = after
            return "appreciated"
        end
        if p:word("accepted") then return "accepted" end
    else
        if p:phrase("чайові вітаються") then
            local after = p.i
            p:word(",")
            if p:any("але вони необов'язкові", "але необов'язкові") then return "appreciatedOptional" end
            p.i = after
            return "appreciated"
        end
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
    local offer, header, freeOffer, finalOffer = enhancementOffer(p, english)
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
    local free = zeroPrice(p) or freeOffer
    if freeOffer then
        for index = 1, #joins + 1 do
            local price = p.slots[index == 1 and "price" or "price" .. index]
            if price and tonumber((price.amount:gsub(",", "."))) ~= 0 then return end
        end
    end
    local tips = gratuity(p, free)
    local beforeStock = p.i
    if offer then p:any(",", ".", "-", "—", "–") end
    local limited = offer and p:any("limited stock", "limited supply", "запас обмежений", "запаси обмежені")
    if not limited then p.i = beforeStock end
    return p:finish("enhancement", {demand=demand, inquiry=inquiry, question=inquiry, mats=mats,
        free=free, tips=tips, joins=joins, offer=offer, header=header, materials=materials, limited=limited,
        finalOffer=finalOffer})
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

local function serviceLocation(p, english, compact)
    local P = ns.Engine.Phrases
    if compact then
        p:any(".", ",", ";")
        if english then p:any("i'm", "i am") else p:word("я") end
        if not english and p:phrase("біля сходів") then
            local owner, after = P.noun(p.document, p.i, p.limit, "genitive", true)
            if P.spatialContainer(owner) then return {object=owner, accessSteps=true}, after end
            return
        end
    else
        p:word(",")
    end
    local place, after = P.preposition(p.document, p.i, p.limit, nil, nil, "predicate",
        compact and "service-location" or nil)
    if not place or not (P.spatialAdjuncts[place.rule.id] or place.rule.id == "out-of-location"
        or compact and P.spatialLocation(place)) then return end
    if compact and english and P.spatialContainer(place.object) and after <= p.limit then
        local nextWord = p.tokens[after]
        if not nextWord.protected and (nextWord.key == "steps" or nextWord.key == "stairs") then
            return {object=place.object, accessSteps=true}, after + 1
        end
    end
    return place, after
end

local function remainingStock(p, english)
    local start = p.i
    p:any(".", ",", ";", ":", "-", "—", "–")
    local remaining
    if english then
        remaining = p:count("stock", nil, nil, true) and p:any("left", "remaining", "letf")
    else
        remaining = p:any("залишилося", "лишилося") and p:count("stock", nil, nil, true)
    end
    if not remaining then p.i, p.slots.stock = start, nil end
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
    local compactFree = not (demand or offer) and (english and p:word("free")
        or not english and p:any("безкоштовно накладу", "безкоштовно пропоную послуги"))
    p:word(":")
    local linked = p:link("trade", "trade") or p:link("trade", "enchant")
    if compactFree and not linked then return end
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
    local free = compactFree or zeroPrice(p)
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
    if tips or compactFree then
        places = {}
        for index = 1, 2 do
            local before = p.i
            local place, after = serviceLocation(p, english, compactFree)
            if not place then
                p.i = before
                break
            end
            places[index], p.i = place, after
        end
    end
    if compactFree then remainingStock(p, english) end
    return p:finish("service", {demand=demand, practitioner=practitioner, priced=priced, free=free, materials=materials, promise=promise,
        tips=tips, places=places, compactFree=compactFree})
end

local function lockedItemLink(p)
    local token = p.tokens[p.i]
    if p.i > p.limit or not token or token.linkKind ~= "item" then return end
    local link = p.document.text:sub(token.first, token.last)
    local label = ns.Engine.Markup.bracketLabel(link)
    if not label then return end
    local key = " " .. ns.Engine.Normalize.key(label)
    if key:match(" lockbox$") or key:match(" lock box$") or key:match(" locked chest$")
        or key:match(" locked box$") or key:match(" замкнена скриня$") or key:match(" замкнена скринька$") then
        p.i = p.i + 1
        return link
    end
end

local function lockedItemList(p)
    local first = lockedItemLink(p)
    if not first then return end
    local links = {first}
    for i = 2, 6 do
        local before = p.i
        p:word(",")
        p:any("and", "і", "й", "та")
        local link = lockedItemLink(p)
        if not link then p.i = before; break end
        links[i] = link
    end
    return links
end

local function lockActor(p, english)
    local token = p.i <= p.limit and p.tokens[p.i]
    if not token or token.protected then return end
    if p:noun("actor", "classes") then return p.slots.actor.term.id == "class.rogue" end
    local corrected = english and M.classSpelling(token.key)
    if corrected and corrected.id == "class.rogue" then
        p.slots.actor, p.i = {term=corrected}, p.i + 1
        return true
    end
end

local function lockLocation(p)
    local key = ns.Engine.Phrases.key(p.document, p.i, p.limit)
    if key ~= "in" and key ~= "at" and key ~= "near" and key ~= "у" and key ~= "в" and key ~= "біля" then return end
    local place, after = ns.Engine.Phrases.preposition(p.document, p.i, p.limit, nil, nil, "predicate")
    if ns.Engine.Phrases.spatialLocation(place) then p.i = after; return place end
end

local function lockSkill(p, english)
    local P = ns.Engine.Phrases
    local amount, after = P.skillRequirementAt(p.document, p.i, p.limit, english)
    if amount then p.i = after; return amount end
    local start = p.i
    if english then
        amount = P.levelNumberAt(p.document, p.i, p.limit)
        if amount then
            p.i = p.i + 1
            if p:word("skill") then return amount end
        end
    end
    p.i = start
    if p:word(english and "skill" or "навичка") then
        amount = P.levelNumberAt(p.document, p.i, p.limit)
        if amount then p.i = p.i + 1; return amount end
        p.i = start
    end
end

local lockOfferOpenings = {opening=true, unlocking=true, lockpicking=true, i=true, ["i'm"]=true,
    rogue=true, rogues=true, rouge=true, ["відмикаю"]=true, ["відкриваю"]=true, ["можу"]=true,
    ["розбійник"]=true, ["розбійники"]=true}

local function offeredLockObject(p, english)
    local P = ns.Engine.Phrases
    local qualified = english and p:any("lock", "locked") or not english and p:any("замкнену", "замкнені")
    if qualified then
        local requested = not english and {case="accusative"} or nil
        local noun = ns.Engine.Lexicon.choose(p.document, p.i, "noun", requested, nil, function(candidate)
            local word = candidate.lexeme.en
            return word == "lockbox" or word == "chest"
        end)
        if noun then p.i = p.i + 1; return P.lexicalNoun(noun) end
        return
    end
    if not ns.Linguistics then return end
    local noun, after = P.noun(p.document, p.i, p.limit, "accusative", nil, nil, true)
    if P.hasTrait(noun, "skillThreshold") then p.i = after; return noun end
end

local function lockOffer(p, direction)
    local first = p.tokens[p.i]
    if not first or first.protected or not lockOfferOpenings[first.key] then return end
    local english = direction == "en-uk"
    local provider, ability, descriptive
    if english then
        ability = p:any("i can open", "i can unlock")
        descriptive = not ability and p:any("i'm opening", "i am opening", "i open", "i unlock")
        if not (ability or descriptive) and not p:any("opening", "unlocking", "lockpicking") then
            if not (lockActor(p, english) and p:any("lf opening", "lf unlocking")) then return end
            provider = true
        end
    else
        ability = p:phrase("можу відкрити")
        descriptive = not ability and p:word("відкриваю")
        if not (ability or descriptive or p:word("відмикаю")) then
            if not (lockActor(p, english) and p:any("шукає , кому відкрити", "шукають , кому відкрити")) then return end
            provider = true
        end
    end
    if english then p:any("a", "an", "the") end
    local links = lockedItemList(p)
    local object = not links and offeredLockObject(p, english)
    if not (links or object) then return end
    local place, skill, tips
    for _ = 1, 3 do
        local before = p.i
        p:any(".", ",", ";", "-", "–", "—")
        local qualifier = p.i
        local value, after
        if not place then value, after = serviceLocation(p, english, true) end
        if value then place, p.i = value, after
        else
            -- The location parser can consume a separator or a subject before failing.
            p.i = qualifier
            if not skill then value = lockSkill(p, english) end
            if value then skill = value
            else
                if not tips then value = gratuity(p) end
                if value then tips = value else p.i = before; break end
            end
        end
    end
    -- An item requirement belongs to the object. An independent skill or tip can signal an offer.
    if descriptive and not (skill or tips) then return end
    local result = p:finish("lockOffer", {provider=provider, ability=ability, links=links, object=object,
        place=place, skill=skill, tips=tips})
    if result and not result.features.question then return result end
end

local lockRequestOpenings = {
    ["en-uk"]={lf=true, looking=true, ["i'm"]=true, any=true, anyone=true, someone=true, can=true, could=true},
    ["uk-en"]={["шукаю"]=true, ["чи"]=true, ["є"]=true, ["хтось"]=true},
}

local function requestPoliteness(p)
    if p.i > p.limit then return end
    local entry, last = ns.Engine.Dictionary.literal(p.document, p.i, nil, p.limit)
    if entry and entry.id == "literal.please" then
        p.i = last + 1
        return true
    end
end

local function lockRequest(p, direction)
    local first = p.tokens[p.i]
    if not first or (first.linkKind ~= "item" and not lockRequestOpenings[direction][first.key]) then return end
    local english = direction == "en-uk"
    local links = lockedItemList(p)
    local fronted = links ~= nil
    if fronted then p:any(":", "—", "-", ",") end

    local request, anyone, kind
    if english then
        if p:any("lf", "looking for", "i'm looking for") then request = "search"
        elseif p:any("can anyone", "could anyone", "anyone", "can someone", "could someone", "someone") then
            request, anyone = "question", true
        elseif p:word("any") then request = "question"
        else return end
        if request == "search" and p:any("lockpick", "lockpicker") then kind = "lockpicker" end
    else
        if p:word("шукаю") then request = "search"
        elseif p:phrase("чи є") then request = "question"
        elseif fronted and p:word("є") then request = "question"
        elseif p:word("хтось") then request, anyone = "question", true
        else return end
        if request == "search" and p:phrase(", хто") then kind = "lockpicker" end
    end
    if not (anyone or kind or lockActor(p, english)) then return end
    local location = lockLocation(p)
    p:word(",")
    local willing, action, ability
    if english then
        p:any("who", "that")
        willing = p:any("willing to", "want to")
        ability = p:any("can", "could")
        if not ability then p:word("to") end
        if p:any("lockpick", "pick the lock on", "pick the lock") then action = "pick"
        elseif p:any("open", "unlock") then action = "open" end
    else
        p:any("який", "які", "щоб")
        willing = p:any("готовий", "готові", "згоден", "згодні", "хоче")
        ability = p:any("може", "можуть")
        if p:any("зламати замок", "зламає замок", "відмикати") then
            action = "pick"
            p:word("на")
        elseif p:any("відкрити", "відкриє", "відчинити", "відмикнути") then action = "open" end
    end
    if not action and not fronted then p:word(english and "for" or "для") end
    local recipient = p:any("for me", "мені", "для мене")
    local please = requestPoliteness(p)
    if fronted and not english and action == "open" then p:any("її", "їх", "скриньку", "скриньки") end
    local amount
    if not fronted then
        local before = p.i
        local token = p.i <= p.limit and p.tokens[p.i]
        amount = token and not token.protected and (token.key:match("^x(%d%d?%d?)$") or token.key:match("^×(%d%d?%d?)$"))
        if amount and tonumber(amount) > 0 then p.i = p.i + 1
        else
            amount = p:count("lockCount", false, english) and p.slots.lockCount.raw
        end
        links = lockedItemList(p)
        if not links then amount, p.i = nil, before end
    end
    if not links and action ~= "pick" then return end
    if anyone and not action then return end
    if not recipient then recipient = p:any("for me", "мені", "для мене") end
    if not please then
        local before = p.i
        p:word(",")
        please = requestPoliteness(p)
        if not please then p.i = before end
    end
    local skill = links and lockSkill(p, english)
    return p:finish("lockRequest", {request=request, anyone=anyone, kind=kind, location=location,
        willing=willing, action=action, ability=ability, links=links, fronted=fronted and not action, amount=amount,
        recipient=recipient, please=please, skill=skill})
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
    if p:noun("place", "places", not english and "accusative" or nil, english) then
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

local function skillFloor(p)
    local start = p.i
    if p:count("skill") and p:word("+") then return true end
    p.i, p.slots.skill = start, nil
end

local function availability(p, direction)
    if not ns.Linguistics or p.document.truncated or p.document.ambiguities then return end
    local english = direction == "en-uk"
    local search
    if english then
        search = p:any("lf", "looking for", "i'm looking for")
        if not search and not p:any("any", "is there a", "is there an") then return end
    else
        search = p:word("шукаю")
        if not search and not p:any("чи є", "є") then return end
    end
    local plus = p.i <= p.limit and p.document.text:find("+", p.tokens[p.i].first, true)
    if not plus or plus > p.tokens[p.limit].last then return end
    local P, D = ns.Engine.Phrases, ns.Engine.Dictionary
    if english and search then p:any("a", "an") end
    local preposed = english and skillFloor(p)
    local case = search and "accusative" or "nominative"
    local occupation, after = P.noun(p.document, p.i, p.limit, case, nil, nil, true, nil,
        function(noun) return P.semanticClass(noun) == "occupation" end)
    local profession
    if not occupation and english then
        local key = P.key(p.document, p.i, p.limit)
        profession = D.craftingAlias(key)
        local term = profession and ns.Data.terms[profession .. ".practitioner"]
        if term then
            occupation, after = {term=term, person=3, number="singular"}, p.i + 1
        end
    end
    if not occupation then return end
    p.i = after
    if not preposed then
        if english then
            if p:word("with") then p:word("skill")
            elseif not search then return end
        elseif not p:any("із навичкою", "з навичкою") then return end
        if not skillFloor(p) then return end
    end
    if english and not preposed and not p:word("skill") then
        local entry = occupation.entry
        local term = occupation.term
        profession = profession or entry and entry.lexeme.frame.practitionerOf
            or term and term.id:match("^(profession%..+)%.practitioner$")
        if profession then
            local following = P.key(p.document, p.i, p.limit)
            if D.craftingAlias(following) == profession then p.i = p.i + 1
            else
                local candidate = M.select(p.document, p.i, "professions", p.limit)
                if candidate and candidate.id == profession then p.i = candidate.last + 1 end
            end
        end
    end
    local place
    if p:any("online", "around", "here", "онлайн", "у мережі", "поблизу", "тут") then
        place = p.tokens[p.i - 1].key
        if place == "мережі" then place = "online" end
    end
    return p:finish("availability", {question=not search, search=search, place=place, occupation=occupation})
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

local function linkedStockOffer(p, direction)
    local english = direction == "en-uk"
    local prefixed = zeroPrice(p)
    if prefixed then p:word(":")
    elseif english then return end
    if not (p:link("item", "item") or p:link("item", "spell") or p:link("item", "enchant")) then return end
    if not prefixed and not zeroPrice(p) then return end
    p:word(",")
    if english then
        if not p:any("while", "until") then return end
        p:word("the")
        if not p:any("supplies", "supply", "stocks", "stock", "mats", "materials", "inventory") then return end
        if not p:any("last", "lasts", "run out", "runs out") then return end
    elseif not p:any("поки є запаси", "доки є запаси", "доки не скінчаться запаси") then return end
    return p:finish("freeOffer", {stockLimited=true})
end

local function freeOffer(p, direction)
    local stockOffer = linkedStockOffer(p, direction)
    if stockOffer then return stockOffer end
    p:reset()
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
    local each, after = ns.Engine.Grammar.priceBasisAt(p.document, p.i, p.limit)
    p.i = after
    return p:finish("price", {only=only, linked=linked, each=each, introduced=introduced})
end

local function auctionComparison(p, english)
    local start = p.i
    local emphatic, comparison
    if english then
        emphatic = p:any("much", "far", "significantly")
        if p:word("cheaper") and p:any("than", "then") then
            p:word("at")
            p:word("the")
            comparison = true
        end
    else
        emphatic = p:any("набагато", "значно")
        if p:word("дешевше") then
            p:word(",")
            comparison = p:phrase("ніж на")
        end
    end
    if comparison and p:noun("market", "game") and p.slots.market.term.id == "game.auction_house" then
        return emphatic and "emphatic" or "plain"
    end
    p.i, p.slots.market = start, nil
end

local function auctionCondition(p, english)
    local start = p.i
    p:any(",", "-", "–", "—")
    local comparison = auctionComparison(p, english)
    if comparison then return comparison end
    if english or p:word("на") then
        local amount, after = ns.Engine.Grammar.offerPriceAt(p.document, p.i, p.limit)
        if amount then
            p.i = after
            comparison = auctionComparison(p, english)
            if comparison then return comparison, amount end
        end
    end
    p.i = start
end

local function sellerMaterials(p, english)
    local start = p.i
    p:word(",")
    local parenthesized = p:word("(")
    local provided = english and p:any("my mats", "my materials", "with my mats", "with my materials")
        or not english and p:any("матеріали мої", "з моїми матеріалами")
    if provided and (not parenthesized or p:word(")")) then return true end
    p.i = start
end

local function linkedSale(p, direction)
    local english = direction == "en-uk"
    if english then
        if not p:any("wts", "selling", "i'm selling", "i am selling") then return end
    elseif not p:any("продам", "продаю") then return end
    p:word(":")
    local offers, detailed = {}, false
    local grammar = ns.Engine.Grammar
    for index = 1, 6 do
        local slot = "sale" .. index
        if not (p:link(slot, "item") or p:link(slot, "enchant")) then return end
        p:any("-", "–", "—")
        local explicitPrice = p:word(english and "for" or "за")
        local amount, after = grammar.offerPriceAt(p.document, p.i, p.limit)
        local basis
        if amount then
            basis, p.i = grammar.priceBasisAt(p.document, after, p.limit)
        end
        local link = p.slots[slot]
        local materials, comparison, discount
        if link.kind == "item" then
            -- An unintroduced amount directly before the comparative is the difference.
            local nextToken = p.tokens[p.i]
            if english and amount and not (explicitPrice or basis) and nextToken and nextToken.key == "cheaper" then
                comparison = auctionComparison(p, english)
                if comparison then discount, amount = amount, nil end
            end
            if not comparison then comparison, discount = auctionCondition(p, english) end
        elseif amount then
            materials = sellerMaterials(p, english)
        end
        if not (amount or comparison) then return end
        offers[index] = {link=link.raw, amount=amount, basis=basis, materials=materials,
            comparison=comparison, discount=discount}
        if index == 1 and link.kind == "item" then remainingStock(p, english) end
        if p.slots.stock then return p:finish("linkedSale", {offers=offers}) end
        detailed = detailed or comparison or #amount > 1 or materials or basis == "enchant"
        local separator = p:any(",", ";")
        local join = english and p:word("and") or not english and p:any("а", "і", "й", "та")
        if not (separator or join) then
            if detailed or index > 1 then return p:finish("linkedSale", {offers=offers}) end
            return
        end
    end
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

local parsers = {lockRequest, lockOffer, recruit, groupRoster, groupVacancy, enhancement, availability, enchantmentTrade, linkedSale, service, enchantmentList, gratuityNote, reward, questNeed, questAttendance,
    statement, freeOffer, price, groupSearch, search}
function S.parse(document, limit, first)
    if document.checkpoint then document.checkpoint() end
    limit, first = limit or #document.tokens, first or 1
    local p = state(document, limit, first)
    if not (document.truncated or document.ambiguities)
        and ns.Engine.Normalize.tokenQuestion(document.text, document.tokens, first, limit) then
        local result = roleInquiry(p, document.direction)
        if result then return result end
        p:reset()
    end
    for _, parse in ipairs(parsers) do
        local result = parse(p, document.direction)
        if result then return result end
        p:reset()
    end
end

function S.translateRange(document, first, last, allowPartial)
    local tree = S.parse(document, last, first)
    if tree then
        if tree.features.unresolved and not allowPartial then return nil end
        local output = ns.Engine.Transfer.render(tree, document.direction)
        if output and tree.features.question then
            output = ns.Engine.Normalize.endAsQuestion(output, tree.features.questionEnd or "?")
        end
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
                if output:sub(-1) ~= document.tokens[last].key then output = output:gsub("[.!]+$", "") end
                return nil, nil, {[1]={text=output, last=last,
                    rule={sourceRefs={"project-authored:apertium-pipeline-1"}}, slots=tree.slots}}
            end
        end
    end
end
