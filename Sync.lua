-- Sync.lua
-- Xal's Xpedited Routes
--
-- Shares newly found nodes with other players running this addon, so nodes any
-- of you finds can fill gaps in everyone's map. OFF by default (Options ->
-- Database -> Sharing).
--
-- How: everyone who turns it on joins one hidden chat channel (never shown in
-- your chat windows) and swaps invisible addon messages through it. The
-- channel name includes the game version, so Forever players only talk to
-- Forever players and Retail to Retail.
--
-- Rules that keep it safe and quiet:
--   * Only nodes YOU gathered yourself are ever sent. Nodes that arrived from
--     other players or from the built-in data are never passed on, so one bad
--     report can't spread.
--   * A node is sent live only while fewer than PUSH_KNOWN_LIMIT other players
--     are known to have it, so the fuller the map, the quieter the channel.
--   * Entering a zone asks "I know N nodes here, who has more?" - only players
--     who know more answer, at most MAX_RESPONDERS of them.
--   * Guild members and friends are trusted at once; everyone else needs
--     CONFIRMATIONS different players to report the same node first.
--   * Every message is strictly validated (plain whole numbers, known zone,
--     known type), each sender is rate limited, and received data is only ever
--     read as text, never run.
--   * Every received node goes through the same duplicate check as nodes you
--     gather yourself, so it never lands on top of one you already have.
--
-- Wire format (prefix "XalsXR", messages up to 240 characters):
--   N:<mapID>;<x>,<y>,<t>;<x>,<y>,<t>...   x and y are 0-10000, t is h/m/l
--   Q:<mapID>:<count>                      "I know <count> nodes here"
local addonName, addonTable = ...
local Sync = addonTable.Sync
local Helpers = addonTable.Helpers
local Engine = addonTable.Engine

local PREFIX = "XalsXR"
local CHANNEL = "XalsXRSync" .. tostring(WOW_PROJECT_ID or 0)
local CONFIRMATIONS = 3
local PUSH_KNOWN_LIMIT = 3
local MAX_RESPONDERS = 3
local SEND_INTERVAL = 1.2
local MAX_MSG_LEN = 240
local QUEUE_MAX = 60
local RECV_BUDGET = 40             -- incoming messages handled per second
local RATE_WINDOW = 60
local RATE_MAX_NODES = 150         -- nodes accepted per sender per window
local QUERY_COOLDOWN = 600         -- seconds before asking for the same zone again
local ANSWER_COOLDOWN = 300
local JOIN_DELAY = 8               -- let General/Trade join first
local PENDING_PER_ZONE = 300
local PENDING_PER_REPORTER = 30
local PENDING_TOTAL = 1000
local ANNOUNCE_DELAY, ANNOUNCE_GAP = 20, 180

local TYPE_CODE = { herb = "h", mine = "m", lumber = "l" }
local CODE_TYPE = { h = "herb", m = "mine", l = "lumber" }

local queue = {}
local channelID
local playerFull
local rate = {}
local lastQuery = {}
local answering = {}
local answeredAt = {}
local pending = {}                 -- mapID -> list of { x, y, type, reporters, count, first, by }
local heard = setmetatable({}, { __mode = "k" }) -- node table -> number of other players known to have it
local recv = { start = 0, count = 0, processed = 0 }
local stats = { received = 0, added = 0, dropped = 0 }
local announce = { zones = {}, total = 0, lastAt = 0, pending = false }

local function Enabled()
    return XalsXRDB and XalsXRDB.shareEnabled == true
end

local function ShortName(sender)
    return Ambiguate and Ambiguate(sender, "none") or sender
end

local function IsSelf(sender)
    return sender == playerFull or ShortName(sender) == UnitName("player")
end

local function IsTrusted(sender, distribution)
    if distribution == "GUILD" then return true end
    if C_FriendList and C_FriendList.GetFriendInfo then
        local ok, info = pcall(C_FriendList.GetFriendInfo, ShortName(sender))
        if ok and info then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- Sending
--------------------------------------------------------------------------------
local function Enqueue(text)
    if #queue >= QUEUE_MAX then
        stats.dropped = stats.dropped + 1
        return
    end
    queue[#queue + 1] = text
end

local function SendNext()
    if not Enabled() or not (channelID and channelID > 0) then return end
    local text = table.remove(queue, 1)
    if not text then return end
    pcall(C_ChatInfo.SendAddonMessage, PREFIX, text, "CHANNEL", channelID)
end

local function EncodeNode(node)
    return string.format("%d,%d,%s",
        math.floor(node.x * 10000 + 0.5), math.floor(node.y * 10000 + 0.5), TYPE_CODE[node.type] or "x")
end

-- Packs a list of nodes of one zone into as few messages as possible.
local function SendNodes(mapID, nodes)
    local head = "N:" .. mapID
    local msg = head
    for _, node in ipairs(nodes) do
        local part = ";" .. EncodeNode(node)
        if #msg + #part > MAX_MSG_LEN then
            Enqueue(msg)
            msg = head
        end
        msg = msg .. part
    end
    if msg ~= head then Enqueue(msg) end
end

-- Only nodes this player gathered themselves (lastGathered is set only by a
-- real gather) and that are a type we share. Imported, built-in and received
-- nodes have no lastGathered and are never passed on.
local function IsShareable(node)
    return node.lastGathered ~= nil and not node.shared and TYPE_CODE[node.type] ~= nil
end

function Sync:Share(mapID, node)
    if not Enabled() or not IsShareable(node) then return end
    if (heard[node] or 0) >= PUSH_KNOWN_LIMIT then return end
    SendNodes(mapID, { node })
end

--------------------------------------------------------------------------------
-- Receiving
--------------------------------------------------------------------------------
local function RateOK(sender, count)
    local r = rate[sender]
    if not r or time() - r.start > RATE_WINDOW then
        r = { start = time(), count = 0 }
        rate[sender] = r
    end
    r.count = r.count + count
    return r.count <= RATE_MAX_NODES
end

local function WithinBudget()
    local now = GetTime()
    if now - recv.start >= 1 then
        recv.start, recv.count, recv.processed = now, 0, 0
    end
    if recv.processed >= RECV_BUDGET then
        stats.dropped = stats.dropped + 1
        return false
    end
    recv.processed = recv.processed + 1
    return true
end

local function Announce(mapID)
    announce.zones[mapID] = true
    announce.total = announce.total + 1
    if announce.pending then return end
    announce.pending = true
    local wait = math.max(ANNOUNCE_DELAY, announce.lastAt + ANNOUNCE_GAP - time())
    C_Timer.After(wait, function()
        announce.pending, announce.lastAt = false, time()
        local names = {}
        for zone in pairs(announce.zones) do
            local info = C_Map.GetMapInfo(zone)
            names[#names + 1] = info and info.name or tostring(zone)
            if #names >= 3 then break end
        end
        if announce.total > 0 then
            print(string.format("|cff00ccffXal's XR:|r %d node(s) shared by other players added (%s).",
                announce.total, table.concat(names, ", ")))
        end
        announce.zones, announce.total = {}, 0
        if addonTable.Markers and addonTable.Markers.UpdatePins then addonTable.Markers:UpdatePins() end
    end)
end

local function CountPending()
    local n = 0
    for _, list in pairs(pending) do n = n + #list end
    return n
end

local function AddNode(mapID, x, y, nodeType)
    XalsXRDB[mapID] = XalsXRDB[mapID] or {}
    table.insert(XalsXRDB[mapID], { x = x, y = y, type = nodeType, shared = true })
    stats.added = stats.added + 1
    Announce(mapID)
end

local function HandleNode(mapID, entry, sender, trusted)
    local xs, ys, code = strsplit(",", entry)
    -- Plain whole numbers only: tonumber alone lets "nan", "1e3" or hex through.
    if not (xs and ys and code and xs:match("^%d+$") and ys:match("^%d+$")) then return end
    local nodeType = CODE_TYPE[code]
    local x, y = tonumber(xs), tonumber(ys)
    if not (nodeType and x and y) or x > 10000 or y > 10000 then return end
    x, y = x / 10000, y / 10000
    local who = ShortName(sender)

    local zoneNodes = XalsXRDB[mapID]
    local duplicateYards = Helpers.GetDuplicateYards()

    -- Already known: just remember another player has it too.
    if zoneNodes then
        local index = Helpers.FindNearbyNodeIndex(zoneNodes, Engine, mapID, x, y, duplicateYards)
        if index then
            local node = zoneNodes[index]
            heard[node] = (heard[node] or 0) + 1
            return
        end
    end

    -- New to us. Trusted senders are added at once; strangers need confirmations.
    if trusted then
        AddNode(mapID, x, y, nodeType)
        return
    end

    pending[mapID] = pending[mapID] or {}
    local list = pending[mapID]
    local match
    for _, p in ipairs(list) do
        if p.type == nodeType and Helpers.NodeDistanceYards(Engine, mapID, p.x, p.y, x, y) < duplicateYards then
            match = p
            break
        end
    end
    if not match then
        local mine = 0
        for _, p in ipairs(list) do
            if p.by == who then mine = mine + 1 end
        end
        if mine >= PENDING_PER_REPORTER or CountPending() >= PENDING_TOTAL then return end
        if #list >= PENDING_PER_ZONE then table.remove(list, 1) end
        match = { x = x, y = y, type = nodeType, reporters = {}, count = 0, by = who, first = time() }
        list[#list + 1] = match
    end
    if not match.reporters[who] then
        match.reporters[who] = true
        match.count = match.count + 1
    end
    if match.count >= CONFIRMATIONS then
        for i, p in ipairs(list) do
            if p == match then table.remove(list, i) break end
        end
        AddNode(mapID, match.x, match.y, match.type)
    end
end

local function OwnShareable(mapID)
    local own = {}
    for _, node in ipairs(XalsXRDB[mapID] or {}) do
        if IsShareable(node) then own[#own + 1] = node end
    end
    return own
end

local function OnNodes(body, sender, trusted)
    local parts = { strsplit(";", body) }
    if not (parts[1] and parts[1]:match("^%d+$")) then return end
    local mapID = tonumber(parts[1])
    if not mapID or not C_Map.GetMapInfo(mapID) then return end
    if not RateOK(sender, #parts - 1) then return end
    -- Someone answered a zone question: we may not need to answer it ourselves.
    if answering[mapID] then answering[mapID].responders[sender] = true end
    for i = 2, #parts do
        HandleNode(mapID, parts[i], sender, trusted)
    end
end

local function OnQuery(body, sender)
    local mapID, theirCount = body:match("^(%d+):(%d+)$")
    mapID, theirCount = tonumber(mapID), tonumber(theirCount)
    if not (mapID and theirCount) or not RateOK(sender, 10) then return end
    if answering[mapID] or time() - (answeredAt[mapID] or 0) < ANSWER_COOLDOWN then return end
    if #queue >= 20 then return end
    local own = OwnShareable(mapID)
    if #own <= theirCount then return end -- nothing to add
    answering[mapID] = { responders = {} }
    -- Wait a random moment; if enough others answer first, stay quiet.
    C_Timer.After(2 + math.random() * 6, function()
        local a = answering[mapID]
        answering[mapID] = nil
        if not (a and Enabled()) then return end
        local count = 0
        for _ in pairs(a.responders) do count = count + 1 end
        if count >= MAX_RESPONDERS then return end
        answeredAt[mapID] = time()
        table.sort(own, function(p, q) return (p.lastGathered or 0) > (q.lastGathered or 0) end)
        for i = #own, RATE_MAX_NODES + 1, -1 do own[i] = nil end
        SendNodes(mapID, own)
    end)
end

local function Receive(prefix, text, distribution, sender)
    if prefix ~= PREFIX or not Enabled() or type(text) ~= "string" then return end
    if IsSelf(sender) or not WithinBudget() then return end
    stats.received = stats.received + 1
    local kind, body = text:match("^(%u):(.*)$")
    if kind == "N" then
        OnNodes(body, sender, IsTrusted(sender, distribution))
    elseif kind == "Q" then
        OnQuery(body, sender)
    end
end

--------------------------------------------------------------------------------
-- Channel and questions
--------------------------------------------------------------------------------
local function HideChannelFromChat()
    if not ChatFrame_RemoveChannel then return end
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local frame = _G["ChatFrame" .. i]
        if frame then pcall(ChatFrame_RemoveChannel, frame, CHANNEL) end
    end
end

local function JoinChannel()
    if not Enabled() then return end
    local id = GetChannelName(CHANNEL)
    if not id or id == 0 then
        JoinTemporaryChannel(CHANNEL)
        id = GetChannelName(CHANNEL)
    end
    channelID = id
    HideChannelFromChat()
end

local function LeaveChannel()
    local id = GetChannelName(CHANNEL)
    if id and id > 0 then LeaveChannelByName(CHANNEL) end
    channelID = nil
    wipe(queue)
end

local function QueryZone()
    if not Enabled() or not (channelID and channelID > 0) then return end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID or time() - (lastQuery[mapID] or 0) < QUERY_COOLDOWN then return end
    lastQuery[mapID] = time()
    -- Count what sharing can add: nodes we gathered ourselves or received.
    local known = 0
    for _, node in ipairs(XalsXRDB[mapID] or {}) do
        if node.lastGathered or node.shared then known = known + 1 end
    end
    Enqueue(string.format("Q:%d:%d", mapID, known))
end

function Sync:SetEnabled(enabled)
    if not XalsXRDB then return end
    XalsXRDB.shareEnabled = enabled and true or false
    if enabled then
        JoinChannel()
        C_Timer.After(2, QueryZone)
    else
        LeaveChannel()
    end
end

function Sync:PrintStatus()
    print(string.format("|cff00ccffXal's XR:|r Sharing %s. Channel %s. Received %d message(s), added %d node(s), %d waiting for confirmation, %d dropped.",
        Enabled() and "|cff00ff00ON|r" or "|cffff9900OFF|r",
        (channelID and channelID > 0) and ("#" .. channelID) or "not joined",
        stats.received, stats.added, CountPending(), stats.dropped))
end

function Sync:Init()
    if self.inited then return end
    self.inited = true
    playerFull = (UnitName("player") or "") .. "-" .. (GetNormalizedRealmName() or "")
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    C_Timer.NewTicker(SEND_INTERVAL, SendNext)

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_ADDON" then
            local prefix, text, distribution, sender = ...
            if issecretvalue and (issecretvalue(prefix) or issecretvalue(text) or issecretvalue(sender)) then return end
            Receive(prefix, text, distribution, sender)
        else
            C_Timer.After(3, QueryZone)
        end
    end)

    C_Timer.After(JOIN_DELAY, function()
        if Enabled() then
            JoinChannel()
            C_Timer.After(2, QueryZone)
        end
    end)
end
