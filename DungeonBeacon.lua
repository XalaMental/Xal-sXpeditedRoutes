-- DungeonBeacon.lua
-- Xal's Xpedited Routes
--
-- Dungeon nav's own on-screen compass arrow - fully independent from
-- Beacon.lua (the gathering-route arrow). They used to share one frame,
-- which meant the two systems had to actively negotiate who "owns" it (a
-- HasFixedTarget/supersede check) - a real bug surfaced live 2026-08-17
-- where the mining route's own zone-pause logic was hiding the dungeon
-- arrow just because dungeon-nav travel crossed a zone unrelated to the
-- mining route. Splitting them into separate widgets removes that whole
-- class of bug: there's nothing shared left to fight over. Seeing both
-- arrows on screen at once (a gathering route AND a dungeon trip active
-- together) is fine and expected, not a bug - confirmed 2026-08-17.
local addonName, addonTable = ...
local DungeonBeacon = addonTable.DungeonBeacon
local Engine = addonTable.Engine
local Helpers = addonTable.Helpers
local Brand = addonTable.BrandStyle

local frame, arrow, textDistance, textNode
local target = nil -- { uiMapID, x, y, label }
local updateInterval = 0.05 -- matches Beacon's own tick rate

local ARROW_TEXTURE = "Interface\\AddOns\\XalsXpeditedRoutes\\Textures\\RoutesArrow"
local BASE_ARROW_SIZE = 52
local ARRIVAL_YARDS = 15

function DungeonBeacon:Init()
    if frame then return end

    frame = CreateFrame("Frame", "XalsXRDungeonCompassFrame", UIParent, "BackdropTemplate")
    frame:SetSize(70, 70)

    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")

    -- Own saved position, offset from the gathering compass's own default
    -- (y=180) so the two don't spawn stacked directly on top of each other
    -- the first time both are ever shown together.
    local pos = Helpers.SanitizePoint(XalsXRDB and XalsXRDB.dungeonCompassPosition,
        { point = "CENTER", x = 0, y = 100 })
    if XalsXRDB then XalsXRDB.dungeonCompassPosition = pos end
    frame:ClearAllPoints()
    frame:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)

    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        if Helpers.IsValidPoint({ point = point, x = x, y = y }) then
            XalsXRDB.dungeonCompassPosition = { point = point, x = x, y = y }
        end
    end)

    -- Right-click cancels the dungeon waypoint entirely, same gesture the
    -- gathering compass uses for "skip" - the dungeon equivalent of that is
    -- just giving up on the trip.
    frame:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            DungeonBeacon:Clear()
            if addonTable.DungeonNav then addonTable.DungeonNav.activeTarget = nil end
        end
    end)

    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("|cff00ccffXal's XR: Dungeon Nav|r")
        GameTooltip:AddLine("Drag with |cff00ff00Left-Click|r to move.")
        GameTooltip:AddLine("|cffff9900Right-Click|r to cancel.")
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    arrow = frame:CreateTexture(nil, "ARTWORK")
    arrow:SetPoint("CENTER", frame, "CENTER", 0, 0)
    arrow:SetTexture(ARROW_TEXTURE)
    arrow:SetSize(BASE_ARROW_SIZE, BASE_ARROW_SIZE)
    arrow:SetVertexColor(1, 1, 1, 1)

    textDistance = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    textDistance:SetFont(Brand.BODY_FONT_PATH, 15, "OUTLINE")
    textDistance:SetPoint("BOTTOM", frame, "BOTTOM", 0, -18)
    textDistance:SetTextColor(1, 1, 1, 1)

    textNode = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    textNode:SetFont(Brand.BODY_FONT_PATH, 11, "OUTLINE")
    textNode:SetPoint("TOP", frame, "TOP", 0, 14)
    textNode:SetTextColor(0, 0.8, 1, 1)

    frame:Hide()

    local driver = CreateFrame("Frame")
    local elapsedTimer = 0
    driver:SetScript("OnUpdate", function(self, elapsed)
        elapsedTimer = elapsedTimer + elapsed
        if elapsedTimer >= updateInterval then
            elapsedTimer = 0
            DungeonBeacon:RunUpdateLoop()
        end
    end)
end

-- Points the arrow at a single stationary destination. uiMapID/x/y match the
-- normalized (0-1) map position convention used everywhere else in the addon.
function DungeonBeacon:Show(uiMapID, x, y, label)
    if not frame then self:Init() end
    target = { uiMapID = uiMapID, x = x, y = y, label = label }
    textNode:SetText(label or "Waypoint")
    frame:Show()
end

function DungeonBeacon:Clear()
    target = nil
    if frame then frame:Hide() end
end

function DungeonBeacon:HasTarget()
    return target ~= nil
end

function DungeonBeacon:RunUpdateLoop()
    if not target then return end
    if not frame or not frame:IsShown() then return end

    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return end

    local px, py = nil, nil
    if Engine.HBD then
        px, py = Engine.HBD:GetPlayerZonePosition()
    end
    if not px or not py then
        local position = C_Map.GetPlayerMapPosition(mapID, "player")
        if position then px, py = position:GetXY() end
    end
    if not px or not py then return end

    local distance, deltaX, deltaY = nil, nil, nil
    if Engine.HBD then
        distance, deltaX, deltaY = Engine.HBD:GetZoneDistance(mapID, px, py, target.uiMapID, target.x, target.y)
    end
    if not distance then
        -- Different continents/instance boundary HereBeDragons can't
        -- bridge - nothing sane to show; leave the arrow up but blank
        -- until it can.
        textDistance:SetText("--")
        return
    end

    if distance <= ARRIVAL_YARDS then
        print(string.format("|cff00ff00Xal's XR:|r Arrived at %s.", target.label or "the waypoint"))
        local label = target.label
        self:Clear()
        if addonTable.DungeonNav then addonTable.DungeonNav.activeTarget = nil end
        return
    end

    textDistance:SetText(string.format("%.0f yd", distance))

    local playerFacing = GetPlayerFacing()
    if not playerFacing then return end
    local bearingToTarget = math.atan2(deltaX, deltaY)
    arrow:SetRotation(-(playerFacing + bearingToTarget))
end
