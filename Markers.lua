-- Markers.lua
--
-- Renders node markers on the minimap and world map. All the actual shape/color
-- drawing lives in MarkerRenderer.lua (shared with the floating helper button, so
-- both always show the same style) - this file just handles pin pooling and
-- deciding which nodes are visible right now.
--
-- Minimap pins also get hidden entirely once you're within a set distance of a
-- node, since the actual node model in the world is what matters at that range,
-- not our marker. Always on, distance is the only adjustable part. World map
-- pins don't get this - the map you're viewing isn't necessarily the zone you're
-- standing in, so "distance to player" isn't meaningful there.
local addonName, addonTable = ...
local Markers = addonTable.Markers
local Engine = addonTable.Engine
local PathPlanner = addonTable.PathPlanner
local Helpers = addonTable.Helpers
local MarkerRenderer = addonTable.MarkerRenderer

local minimapPinPool = {}
local worldmapPinPool = {}

local DEFAULT_PIN_SIZE = 14 -- base size in pixels for a normal (non-target) marker
local PROXIMITY_CHECK_INTERVAL = 0.3
local proximityTimer = 0

-- Re-exported for backward compatibility with code (SettingsPanel.lua) that reads these
-- off Markers; MarkerRenderer.lua is the source of truth.
Markers.PIN_STYLES = MarkerRenderer.PIN_STYLES
Markers.PIN_STYLE_LABELS = MarkerRenderer.PIN_STYLE_LABELS

-- Closer than this the node highlight (NodeHighlight.lua, 15 yards at most) takes
-- over, so a live node stops pulsing on the minimap.
local LIVE_NEAR_YARDS = 15

local function SetPinAppearance(pin, nodeType, isTarget, styleOverride, alphaOverride)
    local baseSize = (XalsXRDB and XalsXRDB.pinSize) or DEFAULT_PIN_SIZE
    local state = pin.liveState
    if pin.liveNear then state = nil end
    MarkerRenderer.SetAppearance(pin, nodeType, isTarget, baseSize, styleOverride, alphaOverride, state)
end

--------------------------------------------------------------------------------
-- Live node state (filled by LiveScan.lua)
--
-- After a scan, each saved node on the minimap is either "live" (the game's own
-- tracking dot was found on it), "gone" (checked, nothing there) or unknown.
-- A result is only trusted for LIVE_TTL seconds - nodes get picked by other
-- players and respawn - then the marker goes back to normal.
--------------------------------------------------------------------------------
local LIVE_TTL = 120
Markers.LIVE_TTL = LIVE_TTL
local liveState = {} -- ["mapID:x:y"] = { live = bool, t = GetTime() }

local function NodeKey(mapID, x, y)
    return string.format("%d:%.4f:%.4f", mapID, x, y)
end
Markers.NodeKey = NodeKey

-- "rare" is a live node whose name is a rare herb or ore (and the player kept
-- the rare pulse on); it counts as live everywhere and just pulses gold.
local function LiveStateOf(mapID, x, y)
    local entry = liveState[NodeKey(mapID, x, y)]
    if entry and GetTime() - entry.t <= LIVE_TTL then
        if not entry.live then return "gone" end
        if entry.rare and not (XalsXRDB and XalsXRDB.liveScanRare == false) then return "rare" end
        return "live"
    end
    return nil
end

-- results: { [nodeKey] = true (live) / false (checked, gone) } for nodes on mapID.
-- rare: optional { [nodeKey] = true } for live nodes that are rare herbs/ore.
function Markers:SetLiveResults(mapID, results, rare)
    local now = GetTime()
    for key, live in pairs(results) do
        liveState[key] = { live = live, t = now, mapID = mapID, rare = rare and rare[key] or nil }
    end
    self:UpdatePins()
    -- Put the markers back to normal once these results run out.
    C_Timer.After(LIVE_TTL + 1, function() Markers:UpdatePins() end)
end

-- A node was just gathered at (x, y): the nearest live node within a short
-- distance is gone now, so its pulse stops and it fades like any other node the
-- scan found empty. (The player stands a few yards from the node when picking
-- it, so this is the nearest live one, not an exact match.)
local GATHER_MATCH_YARDS = 20
function Markers:MarkGathered(mapID, x, y)
    local bestKey, bestDistance
    local now = GetTime()
    for key, entry in pairs(liveState) do
        if entry.live and entry.mapID == mapID and now - entry.t <= LIVE_TTL then
            local _, kx, ky = key:match("^(%d+):([%d%.]+):([%d%.]+)$")
            kx, ky = tonumber(kx), tonumber(ky)
            if kx and ky then
                local distance = Helpers.NodeDistanceYards(Engine, mapID, x, y, kx, ky)
                if distance <= GATHER_MATCH_YARDS and (not bestDistance or distance < bestDistance) then
                    bestKey, bestDistance = key, distance
                end
            end
        end
    end
    if bestKey then
        local entry = liveState[bestKey]
        entry.live, entry.rare, entry.t = false, nil, now
        self:UpdatePins()
    end
end

function Markers:ClearLiveState()
    wipe(liveState)
    self:UpdatePins()
end

-- Fresh live nodes: a list of { mapID, x, y, type }.
function Markers:GetLiveNodes()
    local list = {}
    local now = GetTime()
    for key, entry in pairs(liveState) do
        if entry.live and now - entry.t <= LIVE_TTL then
            local mapID, x, y = key:match("^(%d+):([%d%.]+):([%d%.]+)$")
            if mapID then
                local nodeType
                for _, node in ipairs(XalsXRDB[tonumber(mapID)] or {}) do
                    if NodeKey(tonumber(mapID), node.x, node.y) == key then nodeType = node.type break end
                end
                list[#list + 1] = { mapID = tonumber(mapID), x = tonumber(x), y = tonumber(y), type = nodeType }
            end
        end
    end
    return list
end

-- The pins the scan can probe: herb/ore pins on the minimap right now, with where
-- each one sits on the minimap measured from its bottom-left corner (the same
-- units as Minimap:GetLeft()/GetBottom()). HereBeDragons places every pin with
-- SetPoint("CENTER", minimap, "CENTER", x, y), so that offset is read straight
-- from the pin instead of recomputing bearings and rotation.
function Markers:GetScanTargets()
    local targets = {}
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return targets, nil end
    local half = Minimap:GetWidth() / 2
    for _, pin in ipairs(minimapPinPool) do
        if pin.inUse and pin:IsShown() and pin.nodeX and (pin.nodeType == "herb" or pin.nodeType == "mine") then
            local sx, sy = self.SpotOf(pin)
            if sx then
                local dx, dy = sx - half, sy - Minimap:GetHeight() / 2
                -- Skip pins parked on the edge (the route target floats there
                -- when out of range): their position isn't the node's.
                if dx * dx + dy * dy <= (half * 0.94) ^ 2 then
                    targets[#targets + 1] = {
                        pin = pin, key = NodeKey(mapID, pin.nodeX, pin.nodeY), dist2 = dx * dx + dy * dy,
                    }
                end
            end
        end
    end
    table.sort(targets, function(a, b) return a.dist2 < b.dist2 end)
    return targets, mapID
end

-- A pin's spot on the minimap measured from its bottom-left corner, or nil.
function Markers.SpotOf(pin)
    local point, _, relativePoint, ox, oy = pin:GetPoint(1)
    if point ~= "CENTER" or relativePoint ~= "CENTER" or not ox or not oy then return nil end
    return Minimap:GetWidth() / 2 + ox, Minimap:GetHeight() / 2 + oy
end

-- Live pins pulse: one shared driver, running only while at least one is live.
local pulseFrame = CreateFrame("Frame")
local pulseClock = 0
pulseFrame:SetScript("OnUpdate", function(_, elapsed)
    pulseClock = pulseClock + elapsed
    local any = false
    for _, pin in ipairs(minimapPinPool) do
        if pin.inUse and not pin.liveNear and (pin.liveState == "live" or pin.liveState == "rare") and pin.glowTex then
            any = true
            -- Rare nodes pulse faster so they read as different at a glance.
            local speed = pin.liveState == "rare" and 8 or 5
            pin.glowTex:SetAlpha(0.55 + 0.45 * math.sin(pulseClock * speed))
        end
    end
    if not any then pulseFrame:Hide() end
end)
pulseFrame:Hide()

local function AcquireMinimapPin()
    for _, pin in ipairs(minimapPinPool) do
        if not pin.inUse then
            pin.inUse = true
            return pin
        end
    end
    
    local pin = CreateFrame("Frame", nil, Minimap)
    pin:SetSize(DEFAULT_PIN_SIZE, DEFAULT_PIN_SIZE)
    MarkerRenderer.EnsureParts(pin)
    
    pin.inUse = true
    table.insert(minimapPinPool, pin)
    return pin
end

local function AcquireWorldmapPin()
    for _, pin in ipairs(worldmapPinPool) do
        if not pin.inUse then
            pin.inUse = true
            return pin
        end
    end
    
    local pin = CreateFrame("Frame", nil, WorldMapFrame)
    pin:SetSize(DEFAULT_PIN_SIZE, DEFAULT_PIN_SIZE)
    MarkerRenderer.EnsureParts(pin)
    
    pin.inUse = true
    table.insert(worldmapPinPool, pin)
    return pin
end

local function ReleaseAllPins()
    if Engine.HBDPins then
        Engine.HBDPins:RemoveAllMinimapIcons(addonName)
        Engine.HBDPins:RemoveAllWorldMapIcons(addonName)
    end
    for _, pin in ipairs(minimapPinPool) do
        pin.inUse = false
        pin:Hide()
    end
    for _, pin in ipairs(worldmapPinPool) do
        pin.inUse = false
        pin:Hide()
    end
end

-- Runs on a throttled timer (not every frame) while the player has minimap pins
-- visible. Hides a marker entirely once it's within XalsXRDB.proximityDistanceYards
-- of you, since the actual node model in the world is what matters at that range,
-- not our marker. Always on - only the distance itself is adjustable.
--
-- Measured as on-screen pixel distance on the minimap (pin center to minimap
-- center) converted to real yards using the minimap's own CURRENT view radius
-- (C_Minimap.GetViewRadius(), yards) - this accounts for zoom level and
-- indoor/outdoor live. It also sidesteps HereBeDragons' per-zone distance
-- calibration gaps (some newer/less common zones don't have that data) entirely,
-- since it comes straight from the client's own minimap rendering state rather
-- than a lookup table. Falls back to a flat percentage of the minimap radius
-- only if that API is ever unavailable.
local DEFAULT_PROXIMITY_DISTANCE_YARDS = 15
local FALLBACK_RADIUS_PERCENT = 65

local function ProximityTick(elapsed)
    proximityTimer = proximityTimer + elapsed
    if proximityTimer < PROXIMITY_CHECK_INTERVAL then return end
    proximityTimer = 0

    if not Engine.HBDPins then return end

    local mx, my = Minimap:GetCenter()
    if not mx then return end
    local minimapRadius = Minimap:GetWidth() / 2
    if not minimapRadius or minimapRadius <= 0 then return end

    local viewRadiusYards = C_Minimap and C_Minimap.GetViewRadius and C_Minimap.GetViewRadius()
    local thresholdPixels
    if viewRadiusYards and viewRadiusYards > 0 then
        local thresholdYards = (XalsXRDB and XalsXRDB.proximityDistanceYards) or DEFAULT_PROXIMITY_DISTANCE_YARDS
        thresholdPixels = (thresholdYards / viewRadiusYards) * minimapRadius
    else
        thresholdPixels = minimapRadius * (FALLBACK_RADIUS_PERCENT / 100)
    end

    for _, pin in ipairs(minimapPinPool) do
        if pin.inUse and pin:IsShown() then
            local px, py = pin:GetCenter()
            local shouldBeNear = false
            local liveNear = false
            if px then
                local dx, dy = px - mx, py - my
                local pixels = math.sqrt(dx * dx + dy * dy)
                shouldBeNear = pixels <= thresholdPixels
                -- Within the highlight's reach the live pulse stops: the game's own
                -- highlight takes over there, whatever the hide distance is set to.
                if viewRadiusYards and viewRadiusYards > 0 then
                    liveNear = (pixels / minimapRadius) * viewRadiusYards <= LIVE_NEAR_YARDS
                end
            end

            if shouldBeNear ~= pin.isNear or liveNear ~= pin.liveNear then
                pin.isNear = shouldBeNear
                pin.liveNear = liveNear
                SetPinAppearance(pin, pin.nodeType, pin.isRouteTarget, nil, shouldBeNear and 0 or nil)
            end
        end
    end
end

-- Returns the minimap pin currently representing the active route's target
-- node, if one exists and is actually visible right now (not hidden by
-- proximity fade). Lets other modules (Beacon.lua's trail line) draw to the
-- pin's REAL on-screen position instead of separately recalculating bearing/
-- rotation/minimap-edge-clipping - HereBeDragons already solves all of that
-- correctly for pin placement, so there's no reason to solve it twice.
function Markers:GetTargetPin()
    for _, pin in ipairs(minimapPinPool) do
        if pin.inUse and pin.isRouteTarget and pin:IsShown() then
            return pin
        end
    end
    return nil
end

function Markers:Init()
    if WorldMapFrame then
        hooksecurefunc(WorldMapFrame, "OnMapChanged", function() self:UpdatePins() end)
        WorldMapFrame:HookScript("OnShow", function() self:UpdatePins() end)
        WorldMapFrame:HookScript("OnHide", function() self:UpdatePins() end)
    end

    local ticker = CreateFrame("Frame")
    ticker:SetScript("OnUpdate", function(_, elapsed)
        ProximityTick(elapsed)
    end)

    self:UpdatePins()
end

function Markers:UpdatePins()
    if not Engine.HBD or not Engine.HBDPins then return end
    
    ReleaseAllPins()
    
    if not XalsXRDB or XalsXRDB.showPins == false then return end
    
    -- Don't clutter the map with node types this character can't even gather
    -- (e.g. a pure-Herbalism character seeing every Mining node another
    -- character on the account recorded). Helpers.HasGatheringProfession fails
    -- open (assumes known) if detection is ever inconclusive.
    local showMining = Helpers.HasGatheringProfession(Helpers.MINING_SKILL_LINE, Helpers.MINING_NAMES)
    local showHerbs = Helpers.HasGatheringProfession(Helpers.HERBALISM_SKILL_LINE, Helpers.HERBALISM_NAMES)
    local showLumber = Helpers.HasLumberjacking()

    -- Safety net: a character with saved nodes but detected as having NONE of
    -- the three is far more likely a detection glitch than reality. Rather than
    -- risk silently blanking the whole map again, show everything in that case.
    if not showMining and not showHerbs and not showLumber then
        showMining, showHerbs, showLumber = true, true, true
    end

    local function TypeIsVisible(nodeType)
        return (nodeType == "mine" and showMining)
            or (nodeType == "herb" and showHerbs)
            or (nodeType == "lumber" and showLumber)
    end
    
    -- Get the player's current map for the minimap
    local playerMapID = C_Map.GetBestMapForUnit("player")
    
    -- Check if there's an active route and get the current node
    local targetNode = PathPlanner:CurrentStop()
    
    -- Load pins on the minimap (only for the player's current map)
    if playerMapID and XalsXRDB[playerMapID] then
        for _, node in ipairs(XalsXRDB[playerMapID]) do
            if node.x and node.y and node.type and TypeIsVisible(node.type) then
                local mPin = AcquireMinimapPin()
                local isTarget = (targetNode and targetNode.x == node.x and targetNode.y == node.y)
                local sameNodeAsBefore = (mPin.nodeX == node.x and mPin.nodeY == node.y)
                mPin.nodeX, mPin.nodeY, mPin.nodeType, mPin.isRouteTarget = node.x, node.y, node.type, isTarget
                mPin.liveState = LiveStateOf(playerMapID, node.x, node.y)
                if mPin.liveState == "live" or mPin.liveState == "rare" then pulseFrame:Show() end
                if not sameNodeAsBefore then
                    -- This pin now represents a different node than last time (or is
                    -- brand new) - let the next proximity tick judge it fresh.
                    mPin.isNear = nil
                    mPin.liveNear = nil
                end
                -- UpdatePins() runs far more often than the proximity tick (every zone
                -- change, route event, successful gather...). If we blindly redrew at
                -- full opacity here and waited for the next tick to re-hide it, a pin
                -- that was already correctly hidden would flicker back to visible
                -- every time one of those unrelated events fired. Re-apply whatever
                -- near/far state it already had instead of discarding it.
                SetPinAppearance(mPin, node.type, isTarget, nil, mPin.isNear and 0 or nil)
                
                -- floatOnEdge = isTarget: the active route target clamps to the
                -- minimap's edge when out of view range instead of disappearing,
                -- so it (and the trail line pointing to it) stays visible at any
                -- distance. Every other recorded node stays floatOnEdge=false -
                -- otherwise every node in the zone would clutter the minimap edge,
                -- not just the one you're actually routing to.
                Engine.HBDPins:AddMinimapIconMap(addonName, mPin, playerMapID, node.x, node.y, true, isTarget)
            end
        end
    end
    
    -- Load pins on the world map (only for the map currently being viewed)
    if WorldMapFrame and WorldMapFrame:IsShown() then
        local worldMapID = WorldMapFrame:GetMapID()
        if worldMapID and XalsXRDB[worldMapID] then
            for _, node in ipairs(XalsXRDB[worldMapID]) do
                if node.x and node.y and node.type and TypeIsVisible(node.type) then
                    local wPin = AcquireWorldmapPin()
                    local isTarget = (targetNode and targetNode.x == node.x and targetNode.y == node.y)
                    SetPinAppearance(wPin, node.type, isTarget)
                    
                    Engine.HBDPins:AddWorldMapIconMap(addonName, wPin, worldMapID, node.x, node.y)
                end
            end
        end
    end
end
