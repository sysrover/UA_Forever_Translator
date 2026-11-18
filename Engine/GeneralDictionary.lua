local _, ns = ...
local G = {}; ns.Engine.GeneralDictionary = G

-- Match the importer's byte ordering regardless of the client's C locale.
local function byteLess(left, right)
    for i = 1, math.min(#left, #right) do
        local a, b = left:byte(i), right:byte(i)
        if a ~= b then return a < b end
    end
    return #left < #right
end

local function find(data, key)
    if not data then return nil end
    local low, high = 1, #data.starts
    while low <= high do
        local mid = math.floor((low + high) / 2)
        if byteLess(key, data.starts[mid]) then high = mid - 1 else low = mid + 1 end
    end
    if high < 1 then return nil end
    local block = data.blocks[high]
    local _, endOfKey = block:find("\n" .. key .. "\t", 1, true)
    if not endOfKey then return nil end
    local endOfRow = block:find("\n", endOfKey + 1, true)
    return data.translations[tonumber(block:sub(endOfKey + 1, endOfRow - 1))]
end

function G.lookup(key, direction)
    local firstByte = key:byte(1)
    if not firstByte then return nil end
    if direction == "uk-en" then
        if firstByte < 208 or firstByte > 210 then return nil end
        if key:find("\204\129", 1, true) then key = key:gsub("\204\129", "") end
        local data = ns.GeneralUkEnData
        local text = find(data, key)
        if text then return {id = "stardict:" .. key, uk = key, en = text, sourceRefs = data.sourceRefs} end
    elseif direction == "en-uk" and firstByte >= 97 and firstByte <= 122
        and not key:find("[^a-z']") then
        local data = ns.GeneralEnUkData
        local text = find(data, key)
        if text then return {id = "stardict:" .. key, uk = text, en = key, sourceRefs = data.sourceRefs} end
    end
end
