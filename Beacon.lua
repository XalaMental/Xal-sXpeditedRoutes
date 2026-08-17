-- Beacon.lua
local addonName, addonTable = ...
local Beacon = addonTable.Beacon
local Engine = addonTable.Engine
local PathPlanner = addonTable.PathPlanner
local Helpers = addonTable.Helpers
local Brand = addonTable.BrandStyle

local frame = nil
local arrow = nil
local textDistance = nil
local textNode = nil
local trailLine = nil
local updateInterval = 0.05 -- 20 FPS for smoothness
local TRAIL_LINE_WIDTH = 2 -- thin but noticeable, matches Brand.LINE_THICKNESS elsewhere

local PATH_CHECK_INTERVAL = 0.5 -- how often to judge "closer or farther", not every tick (avoids jitter)
local PATH_DEADBAND_YARDS = 1.5 -- ignore tiny fluctuations smaller than this
local pathCheckTimer = 0
local lastPathDistance = nil
local isOnPath = true
local ON_PATH_COLOR = { 0.25, 0.95, 0.35 }
local OFF_PATH_COLOR = { 0.95, 0.25, 0.25 }

local ARROW_STYLES = {
    custom3 = "Interface\\AddOns\\XalsXpeditedRoutes\\Textures\\Arrow3",
    custom4 = "Interface\\AddOns\\XalsXpeditedRoutes\\Textures\\RoutesArrow",
    blizzard = "Interface\\Minimap\\MiniMap-DeadArrow",
}
Beacon.ARROW_STYLES = { "custom4", "custom3", "blizzard" }
Beacon.ARROW_STYLE_LABELS = {
    custom3 = "Topdown 2D Arrow",
    custom4 = "Chevron (default)",
    blizzard = "Blizzard (Default)",
}

-- Applies whichever arrow texture is currently selected. Safe to call any time,
-- including before the frame exists yet (no-op in that case).
local BASE_ARROW_SIZE = 52
function Beacon:ApplyArrowStyle()
    if not arrow then return end
    local styleKey = (XalsXRDB and XalsXRDB.compassArrowStyle) or "custom4"
    arrow:SetTexture(ARROW_STYLES[styleKey] or ARROW_STYLES.custom4)
    arrow:SetVertexColor(1, 1, 1, 1)
    local scale = (XalsXRDB and XalsXRDB.arrowScale) or 1
    local size = BASE_ARROW_SIZE * scale
    arrow:SetSize(size, size)
    arrow:SetTexCoord(0, 1, 0, 1)
    arrow:SetRotation(0)
    self:Retarget()
end

local BASE_DISTANCE_FONT = 15
local BASE_NODE_FONT = 11
-- Scales the waypoint's distance + node-name text, driven by the "Waypoint text
-- size" slider so it can be enlarged for readability. Safe before Init (no-op).
function Beacon:ApplyTextScale()
    if not textDistance or not textNode then return end
    local scale = (XalsXRDB and XalsXRDB.arrowTextScale) or 1
    local fName = textDistance:GetFont()
    textDistance:SetFont(fName, BASE_DISTANCE_FONT * scale, "OUTLINE")
    local nName = textNode:GetFont()
    textNode:SetFont(nName, BASE_NODE_FONT * scale, "OUTLINE")
end

function Beacon:Init()
    if frame then return end
    
    -- Create the main frame
    frame = CreateFrame("Frame", "XalsXRCompassFrame", UIParent, "BackdropTemplate")
    frame:SetSize(70, 70)
    
    -- Configure dragging and position
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    
    local pos = XalsXRDB.compassPosition
    if pos and pos.y == 100 and pos.x == 0 and pos.point == "CENTER" then
        pos.y = 180
    end
    pos = Helpers.SanitizePoint(pos, { point = "CENTER", x = 0, y = 180 })
    XalsXRDB.compassPosition = pos
    frame:ClearAllPoints()
    frame:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
    
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        if Helpers.IsValidPoint({ point = point, x = x, y = y }) then
            XalsXRDB.compassPosition = { point = point, x = x, y = y }
        end
        -- If GetPoint() came back malformed (interrupted drag), leave the last
        -- known-good saved position alone rather than saving something broken.
    end)
    
    -- Right-click to skip the current node
    frame:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            PathPlanner:SkipPin()
        end
    end)
    
    -- Explanatory tooltip
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("|cff00ccffXal's XR: Beacon|r")
        GameTooltip:AddLine("Drag with |cff00ff00Left-Click|r to move.")
        GameTooltip:AddLine("|cffff9900Right-Click|r to skip this node.")
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
    -- Navigation arrow in the center
    arrow = frame:CreateTexture(nil, "ARTWORK")
    arrow:SetPoint("CENTER", frame, "CENTER", 0, 0)
    Beacon:ApplyArrowStyle()
    
    -- Distance text
    textDistance = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    local fontName, fontSize, fontFlags = textDistance:GetFont()
    textDistance:SetFont(fontName, 15, "OUTLINE")
    textDistance:SetPoint("BOTTOM", frame, "BOTTOM", 0, -18)
    textDistance:SetTextColor(1, 1, 1, 1) -- White
    
    -- Node name text
    textNode = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    local fontNameN, fontSizeN, fontFlagsN = textNode:GetFont()
    textNode:SetFont(fontNameN, 11, "OUTLINE")
    textNode:SetPoint("TOP", frame, "TOP", 0, 14)
    textNode:SetTextColor(0, 0.8, 1, 1) -- Bright blue

    Beacon:ApplyTextScale()

    frame:Hide()

    -- Trail line: a thin bar stretched from the minimap's center to the
    -- current target's pin, parented directly to Minimap (not `frame`) so it
    -- keeps working regardless of whether the HUD arrow itself is shown -
    -- it's a minimap decoration, not part of the floating arrow widget.
    -- Plain white 1x1 texture tinted via SetVertexColor, the standard WoW UI
    -- technique for a solid-color line - no custom art asset needed.
    trailLine = Minimap:CreateTexture(nil, "ARTWORK")
    trailLine:SetTexture("Interface\\Buttons\\WHITE8x8")
    trailLine:SetVertexColor(1, 1, 1, 0.9)
    trailLine:Hide()

    -- Update loop runs on its OWN frame, deliberately never hidden - if it lived
    -- on `frame` itself, WoW simply stops firing OnUpdate on a hidden frame,
    -- which would silently stop route progression (the auto-advance check)
    -- entirely whenever the arrow itself is hidden, e.g. while TomTom is
    -- handling navigation instead. The visual arrow updates inside
    -- RunUpdateLoop still only apply while `frame` is actually shown; only the
    -- distance-check/auto-advance logic needs to keep running regardless.
    local driver = CreateFrame("Frame")
    local elapsedTimer = 0
    driver:SetScript("OnUpdate", function(self, elapsed)
        elapsedTimer = elapsedTimer + elapsed
        if elapsedTimer >= updateInterval then
            elapsedTimer = 0
            Beacon:RunUpdateLoop()
        end
    end)
end

function Beacon:Show()
    if not frame then self:Init() end
    frame:Show()
    self:Retarget()
end

function Beacon:Hide()
    if not frame then self:Init() end
    frame:Hide()
end

function Beacon:Retarget()
    if not frame or not frame:IsShown() then return end

    local target = PathPlanner:CurrentStop()
    if not target then
        self:Hide()
        return
    end
    
    local nodeLabel
    if target.type == "mixed" then
        nodeLabel = "Mixed"
    elseif target.type == "mine" then
        nodeLabel = "Mine"
    else
        nodeLabel = "Herb"
    end
    local total = #PathPlanner.currentPath
    local index = PathPlanner.stopCursor
    local memberCount = target.members and #target.members or 1
    if memberCount > 1 then
        textNode:SetText(string.format("%s (%d/%d)  ·  %d known nodes", nodeLabel, index, total, memberCount))
    else
        textNode:SetText(string.format("%s (%d/%d)", nodeLabel, index, total))
    end
    
    -- New target: don't judge progress against the previous node's distance
    lastPathDistance = nil
    pathCheckTimer = 0
end

-- Draws a thin line from the minimap's center (you're always centered on
-- your own minimap) to the current target's pin position - reusing the
-- pin's REAL position (already correctly placed by HereBeDragons, including
-- minimap rotation and edge-clamping for out-of-radius targets) instead of
-- recalculating any of that separately. Independent of the HUD arrow
-- `frame`'s own visibility - this is a minimap decoration, not part of that
-- widget, so it keeps working even if the player hid the arrow itself.
local function UpdateTrailLine()
    if not trailLine then return end
    if not (XalsXRDB and XalsXRDB.showTrailLine ~= false) then
        trailLine:Hide()
        return
    end
    if not PathPlanner:InProgress() then
        trailLine:Hide()
        return
    end

    local targetPin = addonTable.Markers and addonTable.Markers.GetTargetPin and addonTable.Markers:GetTargetPin()
    if not targetPin then
        trailLine:Hide()
        return
    end

    local mx, my = Minimap:GetCenter()
    local px, py = targetPin:GetCenter()
    if not mx or not px then
        trailLine:Hide()
        return
    end

    local dx, dy = px - mx, py - my
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 2 then
        -- Close enough that a visible line would just be noise
        trailLine:Hide()
        return
    end

    trailLine:ClearAllPoints()
    trailLine:SetSize(dist, TRAIL_LINE_WIDTH)
    trailLine:SetPoint("CENTER", Minimap, "CENTER", dx / 2, dy / 2)
    trailLine:SetRotation(math.atan2(dy, dx))
    trailLine:Show()
end

function Beacon:RunUpdateLoop()
    UpdateTrailLine()

    if not PathPlanner:InProgress() then
        self:Hide()
        return
    end

    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return end

    -- Redundant, tick-level safety net (don't rely solely on the zone-change
    -- EVENT to catch this) - if the player's current map no longer matches
    -- the map the route was actually plotted under, every distance/bearing
    -- calculation below would be comparing two different coordinate spaces,
    -- producing a nonsense number instead of erroring outright. PAUSES
    -- rather than cancels (see PathPlanner:CheckZone) - a brief zone-boundary
    -- clip shouldn't force a full replot.
    PathPlanner:CheckZone()
    if PathPlanner.paused then
        return
    end

    local px, py = nil, nil
    if Engine.HBD then
        px, py = Engine.HBD:GetPlayerZonePosition()
    end
    
    if not px or not py then
        local position = C_Map.GetPlayerMapPosition(mapID, "player")
        if position then
            px, py = position:GetXY()
        end
    end
    
    if not px or not py then return end
    
    local target = PathPlanner:CurrentStop()
    if not target then return end
    
    local distance = nil
    local deltaX, deltaY = nil, nil
    
    if Engine.HBD then
        -- Was missing the destination zone ID (GetZoneDistance takes
        -- oZone, oX, oY, dZone, dX, dY - 6 args) - target.x was silently
        -- sliding into the dZone slot instead. Always fell through to the
        -- yards-per-unit fallback below instead of HereBeDragons' real
        -- calc. mapID for both sides is correct here: PathPlanner:CheckZone
        -- (called just above) already pauses the route the moment the
        -- player's map diverges from the one the route was plotted under,
        -- so by this point they're guaranteed to match. Found during the
        -- 2026-08-17 border audit, fixed on request.
        distance, deltaX, deltaY = Engine.HBD:GetZoneDistance(mapID, px, py, mapID, target.x, target.y)
    end
    
    -- Fallback if HereBeDragons can't calculate distances - shares the same
    -- approximation constant Helpers.NodeDistanceYards uses elsewhere in the
    -- addon, rather than each spot picking its own separate number.
    if not distance or not deltaX or not deltaY then
        deltaX = target.x - px
        deltaY = py - target.y
        distance = math.sqrt(deltaX^2 + deltaY^2) * Helpers.FALLBACK_YARDS_PER_UNIT
    end
    
    -- Arrival check runs regardless of whether the arrow itself is visible -
    -- route progression can't depend on the visual arrow being shown, since
    -- e.g. TomTom may be handling navigation instead while this stays hidden.
    local advanceDistance = (XalsXRDB and XalsXRDB.autoAdvanceDistance) or 50
    if distance <= advanceDistance then
        PathPlanner:StepForward()
        return
    end
    
    -- Everything below here is purely visual (arrow color/rotation, distance
    -- text) - only worth doing while the arrow is actually shown.
    if not frame or not frame:IsShown() then return end
    
    -- Display the distance in yards
    textDistance:SetText(string.format("%.0f yd", distance))
    
    -- Green when the distance to target is shrinking (on path), red when it's
    -- growing (off path) - checked every half-second rather than every tick so
    -- normal minor position jitter doesn't flicker the color back and forth.
    if XalsXRDB and XalsXRDB.arrowProgressColor ~= false then
        pathCheckTimer = pathCheckTimer + updateInterval
        if pathCheckTimer >= PATH_CHECK_INTERVAL then
            pathCheckTimer = 0
            if lastPathDistance then
                local delta = distance - lastPathDistance
                if delta < -PATH_DEADBAND_YARDS then
                    isOnPath = true
                elseif delta > PATH_DEADBAND_YARDS then
                    isOnPath = false
                end
                -- else: no significant change - keep whatever state it already was
            end
            lastPathDistance = distance
            local color = isOnPath and ON_PATH_COLOR or OFF_PATH_COLOR
            arrow:SetVertexColor(color[1], color[2], color[3], 1)
        end
    else
        arrow:SetVertexColor(1, 1, 1, 1)
    end
    
    -- The arrow texture points "up" (north, 0 degrees) by default. SetRotation()
    -- spins textures counterclockwise for positive radians, and both
    -- GetPlayerFacing() and our own bearing-to-target calculation increase
    -- counterclockwise too - so pointing the arrow at the target means undoing
    -- both of those rotations together.
    local playerFacing = GetPlayerFacing()
    if not playerFacing then return end
    
    local bearingToTarget = math.atan2(deltaX, deltaY)
    local totalRotationNeeded = playerFacing + bearingToTarget
    arrow:SetRotation(-totalRotationNeeded)
end
