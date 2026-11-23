local _, ns = ...
local P = {}; ns.ChatPresentation = P
local C, DB, Log = ns.Compat, ns.Database, ns.ChatLog

local function plain(value)
    return (value:gsub("|", "||"))
end

local function display(frame, message, r, g, b, id)
    if r then frame:AddMessage(message, r, g, b, id)
    else frame:AddMessage(message) end
end

local function playerLink(author, chatType, channelIndex, line)
    local caption = "[" .. plain(author) .. "]"
    if author == "" or author:find("[|:%c]") then return caption end
    if type(GetPlayerLink) == "function" then
        local chatGroup, chatTarget
        if ChatFrameUtil and type(ChatFrameUtil.GetChatCategory) == "function" then
            local ok, category = pcall(ChatFrameUtil.GetChatCategory, chatType)
            if ok and not C.secret(category) and type(category) == "string" then
                chatGroup = category
                if type(FCFManager_GetChatTarget) == "function" then
                    local found, target = pcall(FCFManager_GetChatTarget, category, author, channelIndex)
                    if found and not C.secret(target) then chatTarget = target end
                end
            end
        end
        local ok, link = pcall(GetPlayerLink, author, caption, line, chatGroup, chatTarget)
        if ok and not C.secret(link) and type(link) == "string" and link ~= "" then return link end
    end
    return "|Hplayer:" .. author .. "|h" .. caption .. "|h"
end

function P.show(job, result, originalOnly, tab, main)
    local group, context = job.group, job.context
    local event, author, line = context.event, context.author, context.line
    local channel, channelIndex = job.channel, job.channelIndex
    local sourceName = ns.L.chatSources[group]
    local source = sourceName and "[" .. sourceName .. "]" or ""
    local chatType = event:sub(10)
    local infoType = chatType
    if group == "channel" then
        if type(channel) == "string" and channel ~= "" then source = "[" .. plain(channel) .. "]" end
        if type(channelIndex) == "number" and channelIndex > 0 and channelIndex % 1 == 0 then
            infoType = chatType .. channelIndex
            source = "|Hchannel:channel:" .. channelIndex .. "|h" .. source .. "|h"
        end
    end
    local info = ChatTypeInfo and ChatTypeInfo[infoType]
    local player = playerLink(author, chatType, channelIndex, line)
    local message = (source ~= "" and source .. " " or "") .. player .. ": "
        .. (originalOnly and job.text or result.text)
    local r, g, b, id
    local color = not originalOnly and DB.settings.translationColor
    if color then r, g, b = color.r, color.g, color.b
    elseif info and C.public(info.r, info.g, info.b, info.id) then r, g, b, id = info.r, info.g, info.b, info.id end
    local logTranslation = not originalOnly and DB.settings.logTranslations
    if tab then display(tab, message, r, g, b, id) end
    if not originalOnly and main and main ~= tab then display(main, message, r, g, b, id) end
    if logTranslation then
        Log.record(event, job.text, result, "en-uk", job.translationMs, job.maxSliceMs, Log.duration(job.queuedAt))
    end
end

