-- MarkerRenderer.lua
-- Xal's Xpedited Routes
--
-- Shared marker-drawing system used by both the map/minimap pins (Markers.lua) and
-- the floating helper button (QuickButton.lua), so both always render the exact
-- same style and colors the player picked in Settings - just at different sizes.
--
--   Green = Herbalism node
--   Red   = Mining node
--   Blue  = Lumberjacking node
--
-- No separate "active target" color - the current route destination is the same
-- green/red as any other node, just with a small dot marked at its center so it
-- reads as "this one" without needing a whole different color scheme.
--
-- Every shape is built at runtime out of small rotated rectangle textures (WoW
-- frames can't draw arbitrary vector shapes, only straight lines/rectangles), so
-- it only makes sense to use shapes that are naturally straight-edged - a true
-- circle would need a lot of segments to not look like a lumpy polygon, which is
-- exactly why the default is an X (naturally straight-edged, renders exactly
-- right at any segment budget) rather than a circle.
local addonName, addonTable = ...
local MarkerRenderer = addonTable.MarkerRenderer

MarkerRenderer.HERB_COLOR = { 0.15, 0.85, 0.25 }
MarkerRenderer.MINE_COLOR = { 0.85, 0.2, 0.2 }
MarkerRenderer.LUMBER_COLOR = { 0.15, 0.3, 0.75 }

local NODE_COLORS = { mine = MarkerRenderer.MINE_COLOR, herb = MarkerRenderer.HERB_COLOR, lumber = MarkerRenderer.LUMBER_COLOR }

local MAX_SEGMENTS = 12 -- the hollow X outline needs 12

-- Every shape is a single closed outline (last point connects back to the
-- first), defined in unit space (-1..1 on each axis, centered on the pin).
--
-- hollowx: a plus-sign outline (12 points) rotated 45 degrees - this traces the
-- X shape's actual boundary as ONE continuous polygon, so the crossing arms
-- don't create a separate overlapping "box" artifact in the middle the way two
-- independently-drawn crossing bars would.
local SHAPES = {
    hollowx = {
        points = {
            {-0.445,0.757}, {0.000,0.311}, {0.445,0.757}, {0.757,0.445},
            {0.311,-0.000}, {0.757,-0.445}, {0.445,-0.757}, {-0.000,-0.311},
            {-0.445,-0.757}, {-0.757,-0.445}, {-0.311,0.000}, {-0.757,0.445},
        },
    },
    star = {
        points = {
            {0,-1}, {0.225,-0.309}, {0.951,-0.309}, {0.363,0.118}, {0.588,0.809},
            {0,0.382}, {-0.588,0.809}, {-0.363,0.118}, {-0.951,-0.309}, {-0.225,-0.309},
        },
    },
}

-- Display order + labels for the Settings panel
MarkerRenderer.PIN_STYLES = { "hollowx", "star" }
MarkerRenderer.PIN_STYLE_LABELS = {
    hollowx = "Hollow X",
    star = "Hollow star",
}

-- Creates the (initially hidden) texture parts a pin needs to render any style.
-- Safe to call repeatedly - only builds them once per frame.
function MarkerRenderer.EnsureParts(pin)
    if pin.segTex then return end

    -- Soft colored glow, drawn behind everything else (BACKGROUND layer, under
    -- the ARTWORK-layer outline), so markers stand out against busy terrain.
    pin.glowTex = pin:CreateTexture(nil, "BACKGROUND")
    pin.glowTex:SetTexture("Interface\\AddOns\\XalsXpeditedRoutes\\Textures\\Glow")
    pin.glowTex:Hide()

    pin.segTex = {}
    for i = 1, MAX_SEGMENTS do
        local tex = pin:CreateTexture(nil, "ARTWORK")
        tex:Hide()
        pin.segTex[i] = tex
    end

    -- Small filled square shown at the center of the current route target -
    -- reads as a "destination dot" without needing a whole separate color.
    -- (A true filled circle has the same straight-edges-only limitation as the
    -- outline shapes; at the tiny size this renders, a square is indistinguishable
    -- from a dot to the eye.)
    pin.dotTex = pin:CreateTexture(nil, "ARTWORK")
    pin.dotTex:Hide()
end

-- Positions+rotates a texture to form a line from (x1,y1) to (x2,y2), both offsets
-- relative to the pin's own center.
local function PlaceSegment(pin, tex, x1, y1, x2, y2, thickness, color, alphaMult)
    local dx, dy = x2 - x1, y2 - y1
    local length = math.max(math.sqrt(dx * dx + dy * dy), 0.1)
    local angle = math.atan2(dy, dx)
    tex:ClearAllPoints()
    tex:SetSize(length, thickness)
    tex:SetPoint("CENTER", pin, "CENTER", (x1 + x2) / 2, (y1 + y2) / 2)
    tex:SetRotation(angle)
    tex:SetColorTexture(color[1], color[2], color[3], 0.95 * alphaMult)
    tex:Show()
end

-- Draws one styled marker onto `pin` (already sized via SetSize by the caller).
-- isTarget adds the small destination dot at the center; it no longer changes
-- the color or size of the shape itself.
-- alphaOverride, if given, replaces the global opacity slider entirely (used for
-- the proximity fade - fully hidden by default once you're close, see Markers.lua).
-- liveState (optional, from the live node scan in LiveScan.lua): "live" makes the
-- marker pop with a big pulsing glow; "gone" (the scan checked and found
-- nothing there) fades it, if the player left that option on.
function MarkerRenderer.Draw(pin, styleKey, color, size, thickness, nodeType, isTarget, alphaOverride, liveState)
    MarkerRenderer.EnsureParts(pin)
    for _, tex in ipairs(pin.segTex) do tex:Hide() end
    pin.dotTex:Hide()

    local alphaMult = alphaOverride or (XalsXRDB and XalsXRDB.pinAlpha) or 1
    -- (On WoW Forever an empty node is not faded at a distance; markers only dim up close.)
    local onForever = WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT
    if liveState == "gone" and alphaOverride == nil and not onForever and not (XalsXRDB and XalsXRDB.liveScanDim == false) then
        alphaMult = alphaMult * 0.35
    end

    -- A thin dark rim sits behind a live node's glow. A bright glow on bright
    -- ground (the snow zones) has almost no contrast whatever its color, so the
    -- rim is what keeps it visible there; on dark ground it's barely noticed.
    if not pin.rimTex then
        pin.rimTex = pin:CreateTexture(nil, "BACKGROUND", nil, -1)
        pin.rimTex:SetTexture("Interface\\AddOns\\XalsXpeditedRoutes\\Textures\\Glow")
        pin.rimTex:SetVertexColor(0, 0, 0, 0)
        pin.rimTex:Hide()
    end
    pin.rimTex:Hide()

    if (liveState == "live" or liveState == "rare") and alphaOverride == nil then
        -- Always draw the glow for a live node, even with glows turned off
        -- elsewhere: it's the whole point of the marker. Warm yellow for a live
        -- node; violet and bigger for a rare herb or ore (so the two can't be
        -- mistaken for each other).
        local glowSize = size * (liveState == "rare" and 4.2 or 3.4)
        pin.rimTex:ClearAllPoints()
        pin.rimTex:SetSize(glowSize * 1.18, glowSize * 1.18)
        pin.rimTex:SetPoint("CENTER", pin, "CENTER", 0, 0)
        pin.rimTex:SetVertexColor(0, 0, 0, 0.7)
        pin.rimTex:Show()
        pin.glowTex:ClearAllPoints()
        pin.glowTex:SetSize(glowSize, glowSize)
        pin.glowTex:SetPoint("CENTER", pin, "CENTER", 0, 0)
        if liveState == "rare" then
            pin.glowTex:SetVertexColor(0.82, 0.38, 1, 1)
        else
            pin.glowTex:SetVertexColor(1, 0.82, 0.12, 1)
        end
        pin.glowTex:Show()
    elseif XalsXRDB and XalsXRDB.showGlow == false then
        pin.glowTex:Hide()
    else
        local glowSize = size * (isTarget and 2.4 or 2.2)
        pin.glowTex:ClearAllPoints()
        pin.glowTex:SetSize(glowSize, glowSize)
        pin.glowTex:SetPoint("CENTER", pin, "CENTER", 0, 0)
        pin.glowTex:SetVertexColor(color[1], color[2], color[3], (isTarget and 0.65 or 0.55) * alphaMult)
        pin.glowTex:Show()
    end
    pin.glowTex:SetAlpha(1)

    local shape = SHAPES[styleKey] or SHAPES.hollowx
    local half = size / 2
    local pts = shape.points
    local n = #pts
    for i = 1, n do
        local p1, p2 = pts[i], pts[(i % n) + 1]
        PlaceSegment(pin, pin.segTex[i], p1[1] * half, p1[2] * half, p2[1] * half, p2[2] * half, thickness, color, alphaMult)
    end

    if isTarget then
        -- The active/target marker gets a bright YELLOW filled center so the
        -- "this one" node pops against every other red/green marker. Map pins
        -- and the floating Gather button both render through here, so the fill
        -- shows up in both places from this single spot.
        local dotSize = math.max(4, size * 0.34)
        pin.dotTex:ClearAllPoints()
        pin.dotTex:SetSize(dotSize, dotSize)
        pin.dotTex:SetPoint("CENTER", pin, "CENTER", 0, 0)
        pin.dotTex:SetColorTexture(1, 0.82, 0.0, 1 * alphaMult)
        pin.dotTex:Show()
    end
end

-- Convenience wrapper: picks color/thickness from node type + a base size, then
-- draws. This is what most callers actually want to use.
function MarkerRenderer.SetAppearance(pin, nodeType, isTarget, baseSize, styleKey, alphaOverride, liveState)
    local color = NODE_COLORS[nodeType] or MarkerRenderer.HERB_COLOR
    styleKey = styleKey or (XalsXRDB and XalsXRDB.pinStyle) or "hollowx"

    local size = isTarget and math.floor(baseSize * 1.4 + 0.5) or baseSize
    -- A live node is drawn a bit larger than the rest.
    if (liveState == "live" or liveState == "rare") and alphaOverride == nil then size = math.floor(size * 1.3 + 0.5) end
    local thickness = isTarget and math.max(2, baseSize / 6 + 0.5) or math.max(1.5, baseSize / 7)

    pin:SetSize(size, size)
    MarkerRenderer.Draw(pin, styleKey, color, size, thickness, nodeType, isTarget, alphaOverride, liveState)
end
