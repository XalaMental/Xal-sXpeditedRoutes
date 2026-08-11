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

local function SetPinAppearance(pin, nodeType, isTarget, styleOverride, alphaOverride)
    local baseSize = (XalsXRDB and XalsXRDB.pinSize) or DEFAULT_PIN_SIZE
    MarkerRenderer.SetAppearance(pin, nodeType, isTarget, baseSize, styleOverride, alphaOverride)
end

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
local DEFAULT_PROXIMITY_DISTANCE_YARDS = 200
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
            if px then
                local dx, dy = px - mx, py - my
                shouldBeNear = math.sqrt(dx * dx + dy * dy) <= thresholdPixels
            end

            if shouldBeNear ~= pin.isNear then
                pin.isNear = shouldBeNear
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
    
    -- Safety net: a character with saved nodes but detected as having NEITHER
    -- profession is far more likely a detection glitch than reality. Rather than
    -- risk silently blanking the whole map again, show everything in that case.
    if not showMining and not showHerbs then
        showMining, showHerbs = true, true
    end
    
    -- Get the player's current map for the minimap
    local playerMapID = C_Map.GetBestMapForUnit("player")
    
    -- Check if there's an active route and get the current node
    local targetNode = PathPlanner:CurrentStop()
    
    -- Load pins on the minimap (only for the player's current map)
    if playerMapID and XalsXRDB[playerMapID] then
        for _, node in ipairs(XalsXRDB[playerMapID]) do
            if node.x and node.y and node.type
                and ((node.type == "mine" and showMining) or (node.type == "herb" and showHerbs)) then
                local mPin = AcquireMinimapPin()
                local isTarget = (targetNode and targetNode.x == node.x and targetNode.y == node.y)
                local sameNodeAsBefore = (mPin.nodeX == node.x and mPin.nodeY == node.y)
                mPin.nodeX, mPin.nodeY, mPin.nodeType, mPin.isRouteTarget = node.x, node.y, node.type, isTarget
                if not sameNodeAsBefore then
                    -- This pin now represents a different node than last time (or is
                    -- brand new) - let the next proximity tick judge it fresh.
                    mPin.isNear = nil
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
                if node.x and node.y and node.type
                    and ((node.type == "mine" and showMining) or (node.type == "herb" and showHerbs)) then
                    local wPin = AcquireWorldmapPin()
                    local isTarget = (targetNode and targetNode.x == node.x and targetNode.y == node.y)
                    SetPinAppearance(wPin, node.type, isTarget)
                    
                    Engine.HBDPins:AddWorldMapIconMap(addonName, wPin, worldMapID, node.x, node.y)
                end
            end
        end
    end
end
