local _, ns = ...
local L = {}; ns.Engine.Lexicon = L
local N = ns.Engine.Normalize

local function byteLess(a, b)
    for i=1,math.min(#a,#b) do
        local x,y=a:byte(i),b:byte(i)
        if x~=y then return x<y end
    end
    return #a<#b
end
local function find(index, key)
    if not index then return nil end
    local low,high=1,#index.starts
    while low<=high do
        local middle=math.floor((low+high)/2)
        if byteLess(key,index.starts[middle]) then high=middle-1 else low=middle+1 end
    end
    if high==0 then return nil end
    local block=index.blocks[high]
    local _,last=block:find("\n"..key.."\t",1,true)
    if last then return block:sub(last+1,(block:find("\n",last+1,true) or (#block+1))-1) end
end

local function decode(document, data, id)
    local memo = document.lexemeMemo
    if not memo then memo = {}; document.lexemeMemo = memo end
    if memo[id] then return memo[id] end
    local en, uk, pos, family, feature, sense, preference, labels = data.lexemes[id]:match(
        "^([^\t]+)\t([^\t]+)\t([^\t]+)\t(%d+)\t(%d+)\t([^\t]+)\t(-?%d+)\t(.*)$")
    if not en then return nil end
    local lexeme = {en=en, uk=uk, pos=pos, family=tonumber(family), features=tonumber(feature),
        sense=sense, preference=tonumber(preference), labels=labels, frame=data.frames[tostring(id)]}
    memo[id] = lexeme
    return lexeme
end

function L.lookup(document, word)
    local data=ns.Linguistics
    if not data then return {} end
    document.lexicalMemo=document.lexicalMemo or {}
    local cached=document.lexicalMemo[word]
    if cached then return cached end
    local language=document.direction=="en-uk" and "en" or "uk"
    local row=find(data.analysis[language],word)
    local result={}
    document.lexicalMemo[word]=result
    if not row then return result end
    for id,feature in row:gmatch("(%d+):(%d+)") do
        if #result==64 then result.truncated=true; break end
        id,feature=tonumber(id),tonumber(feature)
        local lexeme=decode(document,data,id)
        if lexeme then
            result[#result+1]={id=id,lexeme=lexeme,form=data.features[feature],head=data.features[lexeme.features]}
        end
    end
    return result
end

function L.at(document, index)
    local token = document.tokens[index]
    if not token or token.protected then return {} end
    return L.lookup(document, token.key)
end

local function matches(form, requested)
    for key,value in pairs(requested or {}) do
        if key=="mood" and value=="indicative" then
            if form.mood or form.verbalForm then return false end
        elseif form[key]~=value then return false end
    end
    return true
end

-- Choice is a lexical operation, not a spelling-order tie breaker. Project
-- valency/sense entries rank above imported alternatives. Equal target meanings
-- may share source analyses; different equally-ranked meanings remain visible.
function L.choose(document, first, pos, requested, sense, compatible)
    local candidates=type(first) == "string" and L.lookup(document, first) or L.at(document, first)
    local selected,score,ambiguous
    local target = document.direction == "en-uk" and "uk" or "en"
    for _,candidate in ipairs(candidates) do
        local lexeme,form=candidate.lexeme,candidate.form
        if lexeme.pos==pos and (not requested or matches(form,requested))
            and (not lexeme.frame or lexeme.frame.sense ~= "duration" or sense == "duration")
            and (not sense or lexeme.frame and lexeme.frame.sense==sense)
            and (not compatible or compatible(candidate)) then
            local rank=-(lexeme.preference or 0)
            if not score or rank>score then selected,score,ambiguous=candidate,rank,false
            elseif rank==score and selected.lexeme[target]~=lexeme[target] then ambiguous=true end
        end
    end
    if ambiguous or candidates.truncated then return nil,"ambiguous" end
    return selected
end

local function familyForm(id, requested)
    local data=ns.Linguistics
    local family=data and data.families[id]
    if not family then return nil end
    local best,bestWords
    for feature,word in family:gmatch("(%d+)\t([^\n]+)") do
        local f=data.features[tonumber(feature)]
        if matches(f,requested) then
            local _,spaces=word:gsub(" ","")
            if not best or spaces<bestWords then best,bestWords=word,spaces end
        end
    end
    return best
end

function L.inflect(candidate, requested)
    return familyForm(candidate.lexeme.family,requested)
end
function L.inflectLemma(lemma,pos,requested)
    local data=ns.Linguistics
    local id=data and data.generation[lemma..":"..pos]
    return id and familyForm(id,requested)
end

function L.head(lemma,pos)
    local data=ns.Linguistics
    local id=data and data.generation[lemma..":"..pos]
    local family=id and data.families[id]
    if not family then return {} end
    local first=family:match("(%d+)\t")
    return first and data.features[tonumber(first)] or {}
end

function L.nominalize(candidate)
    local lexeme=candidate.lexeme
    local words=ns.Linguistics.nominalizations[lexeme.uk]
    if words and #words==1 then return words[1] end
    return lexeme.frame and lexeme.frame.nominalization
end

local formNames={nominative="nominativePlural",genitive="genitivePlural",accusative="accusativePlural"}
function L.curatedForm(term,case,number)
    local forms=term.forms or {}
    if number=="plural" then
        local key=formNames[case] or case.."Plural"
        if forms[key] then return forms[key] end
    else
        if forms[case.."Singular"] then return forms[case.."Singular"] end
        if forms[case] then return forms[case] end
    end
    local lemma=N.word(term.uk)
    local requested={case=case,number=number or "singular"}
    local head=L.head(lemma,"noun")
    if case=="accusative" and term.features and term.features.animacy=="animate" and head.animacy=="inanimate" then
        requested.case="genitive"
    end
    local result=L.inflectLemma(lemma,"noun",requested)
    if result then return result end
    if case=="nominative" and (number~="plural" or term.features and term.features.number=="plural"
        or term.morphology and term.morphology.number=="plural") then return term.uk end
end

function L.functional(document, group, first, limit)
    local data=ns.Linguistics
    if not data then return nil end
    local lang=document.direction=="en-uk" and "en" or "uk"
    local index=data.grammar.index[lang][group]
    local tokens=document.tokens
    local key,last="",nil
    local selected
    for i=first,math.min(#tokens,limit or #tokens,first+2) do
        if tokens[i].protected then break end
        key=key=="" and tokens[i].key or key.." "..tokens[i].key
        if index[key] then selected,last=index[key],i end
    end
    return selected,last
end

L.matches=matches
