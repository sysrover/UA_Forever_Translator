local _, ns = ...
local M = {}; ns.Engine.Message = M
local N, A = ns.Engine.Normalize, ns.Engine.Acceptance

function M.parse(text, direction, checkpoint, tokens, offset)
    if not tokens then
        local contractions = direction == "en-uk" and ns.Engine.ClauseAnalysis.englishContractions
        tokens = ns.Engine.Tokenizer.scan(text, contractions)
    end
    if not tokens or #tokens == 0 then return nil end
    return {text=text, direction=direction, tokens=tokens, checkpoint=checkpoint, offset=offset or 0,
        key=N.key(text), facts=A.measure(text, tokens, direction),
        question=N.tokenQuestion(text, tokens, 1, #tokens)}
end

function M.range(source, first, last)
    local tokens = source.tokens
    local offset = tokens[first].first - 1
    local ending = tokens[last].last
    local part = {}
    for i = first, last do
        local token = {}
        for key, value in pairs(tokens[i]) do token[key] = value end
        token.first, token.last = token.first - offset, token.last - offset
        part[#part + 1] = token
    end
    return M.parse(source.text:sub(offset + 1, ending), source.direction, source.checkpoint,
        part, source.offset + offset)
end

function M.analysis(source)
    local base = source.morphology
    if not base then
        base = ns.Engine.Morphology.analyze(source.text, source.tokens, source.direction)
        source.morphology = base
    end
    -- Each candidate can leave its own decisions about ambiguous or unresolved ranges.
    local document = {checkpoint=source.checkpoint}
    for key, value in pairs(base) do document[key] = value end
    if base.preserve then
        document.preserve = {}
        for first, span in pairs(base.preserve) do document.preserve[first] = span end
    end
    return document
end
