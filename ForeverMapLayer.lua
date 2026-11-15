-- ForeverMapLayer.lua
-- Xal's Xpedited Routes
--
-- Our own map layer for WoW: Forever, so the addon needs no HereBeDragons there. It offers
-- the same small set of functions the rest of the addon already calls on HereBeDragons
-- (Engine.HBD and Engine.HBDPins), built from the game's own map calls:
--   position and distance: where you are on your zone map, a zone's real size in yards
--     (Helpers.ZoneSize), and the distance between two map points, in the same zone or
--     across zones of one continent (through Blizzard's map-to-world conversion);
--   pins: icons placed on the minimap (turning with a rotating minimap, following its zoom
--     and shape) and on the world map's canvas, below Questie's marks.
-- Engine.lua uses this on Forever and HereBeDragons everywhere else.
local addonName, addonTable = ...

local Layer = {}
addonTable.ForeverMapLayer = Layer

local Helpers = addonTable.Helpers

local IS_FOREVER = WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT

local HBD = {}
local Pins = {}
Layer.HBD, Layer.HBDPins = HBD, Pins

-- The map calls this layer relies on; if the client lacks any, Engine falls back to HereBeDragons.
function Layer.Available()
    return IS_FOREVER
        and C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition
        and C_Map.GetWorldPosFromMapPos and CreateVector2D
        and C_Minimap and C_Minimap.GetViewRadius
        and Minimap and true or false -- (the world map frame may not exist yet at load: it is looked up when used)
end

--------------------------------------------------------------------------------
-- Position and distance
--------------------------------------------------------------------------------
local function BestMap()
    return C_Map.GetBestMapForUnit("player")
end

-- A point on a zone map as a world point: continent id, x, y in yards (nil when unknown).
local function WorldPoint(mapID, x, y)
    local ok, continent, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
    if not ok or not continent or not pos then return nil end
    local wx, wy = pos:GetXY()
    if not wx or not wy then return nil end
    return continent, wx, wy
end

-- East and north as unit vectors in a continent's world axes, measured from a zone map on it
-- (so no axis convention is assumed): { ex, ey, nx, ny }, cached per continent.
local axesCache = {}
local function Axes(mapID)
    local continent, ax, ay = WorldPoint(mapID, 0.5, 0.5)
    if not continent then return nil end
    local cached = axesCache[continent]
    if cached then return cached end
    local _, ex, ey = WorldPoint(mapID, 0.6, 0.5)
    local _, nx, ny = WorldPoint(mapID, 0.5, 0.4)
    if not (ex and nx) then return nil end
    local elen = math.sqrt((ex - ax) ^ 2 + (ey - ay) ^ 2)
    local nlen = math.sqrt((nx - ax) ^ 2 + (ny - ay) ^ 2)
    if elen == 0 or nlen == 0 then return nil end
    cached = { (ex - ax) / elen, (ey - ay) / elen, (nx - ax) / nlen, (ny - ay) / nlen }
    axesCache[continent] = cached
    return cached
end

-- x, y (0-1), uiMapID of the player on their zone map.
function HBD:GetPlayerZonePosition()
    local mapID = BestMap()
    if not mapID then return nil end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    if not x or not y or (x == 0 and y == 0) then return nil end
    return x, y, mapID
end

-- x, y in world yards and the continent id.
function HBD:GetPlayerWorldPosition()
    local x, y, mapID = self:GetPlayerZonePosition()
    if not x then return nil end
    local continent, wx, wy = WorldPoint(mapID, x, y)
    if not continent then return nil end
    return wx, wy, continent
end

-- width, height of a zone map in yards.
function HBD:GetZoneSize(mapID)
    local size = Helpers.ZoneSize(mapID)
    if not size then return nil end
    return size.w, size.h
end

-- distance in yards, then east (positive) and north (positive) offsets from point 1 to point 2.
function HBD:GetZoneDistance(map1, x1, y1, map2, x2, y2)
    if not (map1 and map2 and x1 and y1 and x2 and y2) then return nil end
    if map1 == map2 then
        return Helpers.ZoneVector(map1, x1, y1, x2, y2)
    end
    local c1, wx1, wy1 = WorldPoint(map1, x1, y1)
    local c2, wx2, wy2 = WorldPoint(map2, x2, y2)
    if not (c1 and c2 and c1 == c2) then return nil end -- different continents: nothing sane to give
    local axes = Axes(map1)
    if not axes then return nil end
    local dx, dy = wx2 - wx1, wy2 - wy1
    return math.sqrt(dx * dx + dy * dy), dx * axes[1] + dy * axes[2], dx * axes[3] + dy * axes[4]
end

--------------------------------------------------------------------------------
-- Pins
--------------------------------------------------------------------------------
local mini, world = {}, {}

local function Number(v)
    return type(v) == "number" and v == v and not (issecretvalue and issecretvalue(v))
end

local function UpdateMinimap()
    if #mini == 0 then return end
    local px, py, mapID = HBD:GetPlayerZonePosition()
    local size = px and Helpers.ZoneSize(mapID)
    local radiusYards = C_Minimap.GetViewRadius()
    if not (px and size and Number(radiusYards) and radiusYards > 0) then
        for _, e in ipairs(mini) do if e.icon:IsShown() then e.icon:Hide() end end
        return
    end

    local mmRadius = Minimap:GetWidth() / 2
    local scale = mmRadius / radiusYards
    local sinF, cosF
    if GetCVar and GetCVar("rotateMinimap") == "1" and GetPlayerFacing then
        local ok, facing = pcall(GetPlayerFacing)
        if ok and Number(facing) then sinF, cosF = math.sin(facing), math.cos(facing) end
    end
    local square = GetMinimapShape and GetMinimapShape() == "SQUARE"
    local limitSq = mmRadius * mmRadius

    for _, e in ipairs(mini) do
        local icon = e.icon
        if e.map ~= mapID then
            if icon:IsShown() then icon:Hide() end
        else
            local dx, dy = (e.x - px) * size.w, (py - e.y) * size.h -- east, north (yards)
            if sinF then
                -- rotating minimap: your facing is up. Rotating a point by -facing from north-up.
                dx, dy = dx * cosF + dy * sinF, -dx * sinF + dy * cosF
            end
            local sx, sy = dx * scale, dy * scale
            local outside
            if square then outside = math.max(math.abs(sx), math.abs(sy)) > mmRadius
            else outside = (sx * sx + sy * sy) > limitSq end
            local show = true
            if outside then
                if e.float then
                    local len = square and math.max(math.abs(sx), math.abs(sy)) or math.sqrt(sx * sx + sy * sy)
                    if len > 0 then sx, sy = sx / len * mmRadius, sy / len * mmRadius end
                else
                    show = false
                end
            end
            if show then
                if e.sx ~= sx or e.sy ~= sy or not icon:IsShown() then
                    e.sx, e.sy = sx, sy
                    icon:ClearAllPoints()
                    icon:SetPoint("CENTER", Minimap, "CENTER", sx, sy)
                end
                if not icon:IsShown() then icon:Show() end
            elseif icon:IsShown() then
                icon:Hide()
            end
        end
    end
end

-- Our pins sit above the map's tiles and below Questie's marks (Questie's world map icons
-- start at frame level 2016, its lines at 2015).
local WORLD_LEVEL = 2012

local function CanvasScale()
    local ok, s = pcall(function() return WorldMapFrame:GetCanvasScale() end)
    if ok and Number(s) and s > 0 then return s end
    return 1
end

local function UpdateWorld()
    if #world == 0 then return end
    if not (WorldMapFrame and WorldMapFrame:IsShown()) then return end
    local shownMap = WorldMapFrame:GetMapID()
    local canvas = WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
    if not (canvas and shownMap) then return end
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    local cs = CanvasScale()
    local s = 1 / cs
    for _, e in ipairs(world) do
        local icon = e.icon
        if e.map ~= shownMap then
            if icon:IsShown() then icon:Hide() end
        else
            if icon:GetParent() ~= canvas then
                icon:SetParent(canvas)
                pcall(icon.SetFrameLevel, icon, WORLD_LEVEL)
            end
            if e.scale ~= s or e.w ~= w or e.h ~= h then
                e.scale, e.w, e.h = s, w, h
                icon:SetScale(s)
                icon:ClearAllPoints()
                icon:SetPoint("CENTER", canvas, "TOPLEFT", (e.x * w) / s, -(e.y * h) / s)
            end
            if not icon:IsShown() then icon:Show() end
        end
    end
end

local driver
local elapsedSum = 0
local function EnsureDriver()
    if driver then return end
    driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function(_, elapsed)
        elapsedSum = elapsedSum + elapsed
        if elapsedSum < 0.1 then return end
        elapsedSum = 0
        UpdateMinimap()
        UpdateWorld()
    end)
end

-- How many pins are registered and how many are showing right now (for /xxr maplayer).
function Layer.Counts()
    local miniShown, worldShown = 0, 0
    for _, e in ipairs(mini) do if e.icon:IsShown() then miniShown = miniShown + 1 end end
    for _, e in ipairs(world) do if e.icon:IsShown() then worldShown = worldShown + 1 end end
    return #mini, miniShown, #world, worldShown
end

-- Same signatures as HereBeDragons-Pins-2.0 for the calls the addon makes.
function Pins:AddMinimapIconMap(ref, icon, uiMapID, x, y, showInParentZone, floatOnEdge)
    mini[#mini + 1] = { ref = ref, icon = icon, map = uiMapID, x = x, y = y, float = floatOnEdge and true or false }
    EnsureDriver()
    UpdateMinimap()
end

function Pins:RemoveAllMinimapIcons(ref)
    for i = #mini, 1, -1 do
        if mini[i].ref == ref then
            mini[i].icon:Hide()
            table.remove(mini, i)
        end
    end
end

function Pins:AddWorldMapIconMap(ref, icon, uiMapID, x, y)
    world[#world + 1] = { ref = ref, icon = icon, map = uiMapID, x = x, y = y }
    EnsureDriver()
    UpdateWorld()
end

function Pins:RemoveAllWorldMapIcons(ref)
    for i = #world, 1, -1 do
        if world[i].ref == ref then
            world[i].icon:Hide()
            table.remove(world, i)
        end
    end
end
