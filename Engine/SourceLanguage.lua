local _, ns = ...
local S = {}
ns.Engine.SourceLanguage = S

local frenchAnchor = {
    avec=true, bonjour=true, chez=true, dans=true, depuis=true, elles=true, eux=true,
    je=true, lui=true, mais=true, merci=true, moi=true, nous=true, pourquoi=true,
    pouvez=true, recrute=true, recrutons=true, salut=true, sommes=true, suis=true, toi=true, une=true, voici=true,
    vous=true, voulez=true, ["êtes"]=true, ["voilà"]=true,
}
local frenchFunction = {
    au=true, aux=true, ce=true, ces=true, cette=true, de=true, des=true, du=true,
    en=true, est=true, et=true, il=true, ils=true, la=true, le=true, les=true,
    leur=true, leurs=true, mes=true, ne=true, nos=true, ont=true, ou=true, par=true, pas=true,
    pour=true, que=true, qui=true, sans=true, se=true, ses=true, tes=true, un=true, vos=true, ["à"]=true,
}
local distinctiveFunction = {aux=true, ces=true, cette=true, des=true, du=true, leurs=true, sans=true}
local englishAnchor = {
    am=true, are=true, can=true, could=true, does=true, dont=true, how=true,
    i=true, is=true, lf=true, lfm=true, looking=true, need=true, should=true,
    thanks=true, the=true, they=true, this=true, want=true, was=true, we=true,
    were=true, what=true, will=true, with=true, would=true, wtb=true, wts=true, wtt=true, you=true, your=true,
}
local englishFunction = {["and"]=true, ["for"]=true, from=true, have=true, of=true, to=true}
local sentenceEnd = {["."]=true, ["?"]=true, ["!"]=true, ["…"]=true, [";"]=true}
local clauseEnd = {[","]=true, [":"]=true, ["—"]=true, ["–"]=true}
S.clauseEnd = clauseEnd
local accents = {}
for letter in ("àâäçéèêëîïôöùûüÿœÀÂÄÇÉÈÊËÎÏÔÖÙÛÜŸŒ"):gmatch("[\195\197][\128-\191]") do
    accents[letter] = true
end

local function measure(tokens, first, last)
    local words, anchors, french, marked, supported, definiteFunction = 0, 0, 0, 0, 0, false
    for index = first, last do
        local token = tokens[index]
        local word = token.key
        if not token.protected and word:find("[%a\195\197\208\209]") then
            words = words + 1
            if frenchAnchor[word] then anchors = anchors + 1
            elseif frenchFunction[word] or word:match("^[cdjlmnst]'[%a\195\197]") then
                french = french + 1
                definiteFunction = definiteFunction or distinctiveFunction[word]
            end
            if englishAnchor[word] or word:match("^[\208\209][\128-\191]")
                or word:match("^i'[%a]") then supported = supported + 2
            elseif englishFunction[word] then supported = supported + 1 end
            for letter in word:gmatch("[\195\197][\128-\191]") do
                if accents[letter] then marked = marked + 1; break end
            end
        end
    end
    -- An accent by itself can belong to an English loanword or a name.
    local strength = anchors * 2 + french + math.min(marked, 2)
    local distinctive = anchors >= 2 or anchors >= 1 and french + marked > 0
        or marked >= 1 and french >= 2 or marked >= 2 and french >= 1
        or french >= 3 and definiteFunction and supported == 0
    return words >= 3 and distinctive and strength >= 2 * supported + 2, supported >= 2
end

function S.foreignRanges(tokens)
    if #tokens < 3 then return nil end
    local ranges
    local function add(first, last)
        ranges = ranges or {}
        ranges[#ranges + 1] = {first=first,last=last}
    end
    local function inspect(first, last)
        local foreign, clearlySupported
        local start = first
        for finish = first, last do
            local split = finish < last and clauseEnd[tokens[finish].key]
                and tokens[finish + 1].first > tokens[finish].last + 1
            if split or finish == last then
                local ending = split and finish - 1 or finish
                local rejected, supported = measure(tokens, start, ending)
                if not split and start == first then
                    if rejected then add(first, last) end
                    return
                end
                if rejected then
                    foreign = foreign or {}
                    foreign[#foreign + 1] = {first=start,last=ending}
                elseif supported then clearlySupported = true end
                start = finish + 1
            end
        end
        -- Joining weak evidence across a sentence is only safe without a clear language switch.
        if not clearlySupported and measure(tokens, first, last) then
            add(first, last)
        else
            for _, range in ipairs(foreign or {}) do add(range.first, range.last) end
        end
    end
    local start = 1
    for index, token in ipairs(tokens) do
        if index == #tokens or sentenceEnd[token.key] and tokens[index + 1].first > token.last + 1 then
            inspect(start, index)
            start = index + 1
        end
    end
    return ranges
end
