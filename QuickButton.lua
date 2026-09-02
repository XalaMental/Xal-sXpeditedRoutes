-- QuickButton.lua
-- Xal's Xpedited Routes
--
-- A small, draggable floating control for one-click route control, for players who
-- don't want to remember /xxr chat commands. It adapts to what THIS character can
-- actually gather:
--   - Mining, Herbalism, Lumberjacking - each an independent on/off toggle. Any
--     combination lit builds one combined route through those types; all off = no
--     route.
--   - A profession this character doesn't know still gets its fixed slot position,
--     just hidden, so the layout never shifts around based on what's learned.
--   - Knows none of the three -> a single greyed placeholder, nothing to click
--
-- Two layouts, picked in Settings (XalsXRDB.helperButtonLayout, "compact" default):
--   Compact - Gather as a glowing text link on top, the three X's stacked in one
--     left-aligned column below it, each smaller with its node-count centered
--     inside the X instead of hanging below it.
--   Classic - the original layout: mine/herb triangle-topped-by-lumber, a boxed
--     "Gather" button underneath.
-- Confirmed 2026-09-01: Compact replaces the old triangle+box look as the default
-- after "the whole thing is blocky" feedback - Classic is kept for anyone who
-- preferred the original.
--
-- The dungeon-waypoint shortcut is its OWN separate draggable frame (not part of
-- this cluster at all) so it can be tucked somewhere out of the way independently
-- of wherever the profession/Gather cluster lives - confirmed 2026-09-01.
--
-- Each X is drawn with MarkerRenderer (the same shape system used for map/minimap
-- pins), so it always matches whatever marker style is selected in Settings instead
-- of being a generic shape of its own.
--
-- Click an X: flips that type's toggle and regenerates the route to match whichever
-- type(s) are now on (or clears it if all end up off).
-- Drag the cluster or the dungeon shortcut: reposition (each position is saved
-- separately).
local addonName, addonTable = ...
local QuickButton = addonTable.QuickButton
local PathPlanner = addonTable.PathPlanner
local Helpers = addonTable.Helpers
local MarkerRenderer = addonTable.MarkerRenderer
local Brand = addonTable.BrandStyle

local container = nil -- outer draggable frame for the profession cluster + Gather
local slotMine, slotHerb, slotLumber = nil, nil, nil
local gatherBtn = nil -- opens the Gather Tally; boxed button (Classic) or text link (Compact)
local dungeonContainer, dungeonMenu = nil, nil -- fully independent draggable piece

local function OnDragStartShared()
    container:StartMoving()
end

local function OnDragStopShared()
    container:StopMovingOrSizing()
    local point, _, _, x, y = container:GetPoint()
    if Helpers.IsValidPoint({ point = point, x = x, y = y }) then
        XalsXRDB.helperButtonPosition = { point = point, x = x, y = y }
    end
    -- If GetPoint() came back malformed (interrupted drag), leave the last
    -- known-good saved position alone rather than saving something broken.
end

local function OnDungeonDragStart()
    dungeonContainer:StartMoving()
end

local function OnDungeonDragStop()
    dungeonContainer:StopMovingOrSizing()
    local point, _, _, x, y = dungeonContainer:GetPoint()
    if Helpers.IsValidPoint({ point = point, x = x, y = y }) then
        XalsXRDB.dungeonButtonPosition = { point = point, x = x, y = y }
    end
end

-- Fade-when-idle - OFF by default (explicit request 2026-08-16: "I don't
-- want to put a fade on the floating button by default... but do put a fade
-- into it as a toggle in settings"). Same hold/fade shape as Compendium's
-- tracker window (5s hold, 0.4s fade), gated entirely behind the setting so
-- it's a no-op unless the player turns it on themselves.
local HOVER_FADE_HOLD = 5
local HOVER_FADE_DURATION = 0.4
local fadeOutToken = nil

local function IsFadeEnabled()
    return XalsXRDB and XalsXRDB.helperButtonFadeWhenIdle == true
end

local function HandleHoverEnter()
    if not container then return end
    fadeOutToken = nil
    container:SetAlpha(1)
end

local function HandleHoverLeave()
    if not container or not IsFadeEnabled() then return end
    local token = {}
    fadeOutToken = token
    C_Timer.After(HOVER_FADE_HOLD, function()
        if fadeOutToken ~= token then return end
        if container:IsMouseOver() then return end
        UIFrameFadeOut(container, HOVER_FADE_DURATION, container:GetAlpha(), 0)
    end)
end

-- Called by the Settings checkbox - snaps back to fully visible immediately
-- when turned off (so it doesn't stay faded from a previous idle state).
function QuickButton:ApplyFadeSetting()
    if container and not IsFadeEnabled() then
        fadeOutToken = nil
        container:SetAlpha(1)
    end
end

local function IsCompactLayout()
    return not (XalsXRDB and XalsXRDB.helperButtonLayout == "classic")
end

-- Classic sizes (unchanged from the original layout)
local SLOT_SIZE = 40 -- clickable hit area
local BUTTON_PIN_SIZE = 30 -- drawn shape size
local COUNT_LABEL_SPACE = 20 -- room reserved below the slot for the count label
local GATHER_BTN_HEIGHT = 24
local GATHER_BTN_WIDTH = SLOT_SIZE * 2 + 4 -- spans the mine/herb pair's combined width

-- Compact sizes - smaller hit area/mark, count moves inside the X instead of
-- needing space below it, confirmed 2026-09-01.
local COMPACT_PIN_SIZE = 26
-- Deliberately small padding, not the Classic +10 - the drawn X fills almost
-- the entire frame, so a 0px icon-to-icon gap actually reads as the icons
-- touching instead of hiding a 5px-per-side margin inside each frame.
local COMPACT_HIT_PADDING = 2
local COMPACT_SLOT_SIZE = COMPACT_PIN_SIZE + COMPACT_HIT_PADDING
local COMPACT_GATHER_HEIGHT = 18

local SLOT_GAP = 4
local COMPACT_GAP = 6 -- Gather-to-first-X gap
local COMPACT_ICON_GAP = 0 -- X-to-X gap - tighter than the Gather gap, confirmed 2026-09-01

-- The rune-X icon art is baked at a fixed 64px/30px ratio (see ConfigureSlot) -
-- this keeps that same proportion when the drawn pin size shrinks for Compact.
local RUNE_TEX_SCALE = 64 / BUTTON_PIN_SIZE

-- Independent now (2026-09-01) - no longer forced to match the profession X
-- icons' size since it's not visually stacked with them anymore.
local DUNGEON_BTN_SIZE = 48
local DISABLED_COLOR = { 0.4, 0.4, 0.4 }
local refreshInterval = 0.5
local refreshTimer = 0

local LABELS = { mine = "Mining", herb = "Herbalism", lumber = "Lumberjacking" }

-- Gather text-link colors (Compact layout) - deep orange, plain black
-- shadow (see CreateCompactGatherButton), no colored glow.
local GATHER_COLOR = { 0.72, 0.30, 0.0 }
local GATHER_COLOR_HOVER = { 0.88, 0.42, 0.05 }

-- Whether a given type is currently included in the active route - true whenever
-- that type is running solo OR as part of an unrestricted (combined) route.
local function IsTypeOn(nodeType)
    if not PathPlanner:InProgress() then return false end
    local filter = PathPlanner.pathTypeFilter
    return filter == nil or filter[nodeType] == true
end

local function GetZoneNodeCount(nodeType)
    local mapID = C_Map.GetBestMapForUnit("player")
    local count = 0
    if mapID and XalsXRDB and XalsXRDB[mapID] then
        for _, node in ipairs(XalsXRDB[mapID]) do
            if node.type == nodeType then
                count = count + 1
            end
        end
    end
    return count
end

-- Flips one type's toggle and regenerates the route to match the resulting
-- combination of on/off states.
local function ToggleType(nodeType)
    local on = { mine = IsTypeOn("mine"), herb = IsTypeOn("herb"), lumber = IsTypeOn("lumber") }
    on[nodeType] = not on[nodeType]

    if on.mine and on.herb and on.lumber then
        PathPlanner:PlotCourse()
    elseif on.mine or on.herb or on.lumber then
        PathPlanner:PlotCourse(on)
    else
        PathPlanner:CancelPath()
    end
end

-- Builds one slot button: a clickable area, rendered via MarkerRenderer, with a
-- node-count label either below it (Classic) or centered inside it (Compact).
-- Called once per slot at Init - after that, ConfigureSlot() just repaints/rebinds it.
local function CreateSlot(parent)
    local slot = CreateFrame("Button", nil, parent)
    slot:SetSize(SLOT_SIZE, SLOT_SIZE)

    -- The rune-X icon: two complete baked variants (idle = transparent
    -- interior, active = interior pre-filled solid yellow) instead of
    -- layering a separate tintable mask - simpler, and avoids any
    -- layering/z-order fragility. ConfigureSlot just swaps which one
    -- SetTexture points at and resizes it to match the current layout.
    -- Classic-only: soft glow behind the rune icon. Its own texture, created
    -- here directly - not shared with or read from MarkerRenderer/map pins.
    local glowTex = slot:CreateTexture(nil, "BACKGROUND")
    glowTex:SetTexture("Interface\\AddOns\\XalsXpeditedRoutes\\Textures\\Glow")
    glowTex:Hide()
    slot.glowTex = glowTex

    local runeXTest = slot:CreateTexture(nil, "ARTWORK")
    runeXTest:SetTexture("Interface\\AddOns\\XalsXpeditedRoutes\\Textures\\RuneX_Test")
    runeXTest:SetPoint("CENTER", slot, "CENTER", 0, 0)
    slot.runeXTest = runeXTest

    local countText = slot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countText:SetTextColor(1, 1, 1, 1)
    -- Drop shadow so the count reads clearly over any world/terrain behind it.
    countText:SetShadowColor(0, 0, 0, 1)
    countText:SetShadowOffset(1.5, -1.5)
    slot.countText = countText

    slot:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("|cff00ccffXal's Xpedited Routes|r")
        if self.nodeType then
            local label = LABELS[self.nodeType]
            if IsTypeOn(self.nodeType) then
                GameTooltip:AddLine("|cff00ff00Click|r: Remove " .. label .. " from the active route")
                GameTooltip:AddLine("Route active: |cffffffff" .. PathPlanner.stopCursor .. "/" .. #PathPlanner.currentPath .. "|r")
            else
                GameTooltip:AddLine("|cff00ff00Click|r: Add " .. label .. " to the route (starts one if none is active)")
            end
            GameTooltip:AddLine(label .. " nodes saved in this zone: |cffffffff" .. GetZoneNodeCount(self.nodeType) .. "|r")
            local visibleSlots = 0
            for _, s in ipairs({ slotMine, slotHerb, slotLumber }) do
                if s and s:IsShown() then visibleSlots = visibleSlots + 1 end
            end
            if visibleSlots > 1 then
                GameTooltip:AddLine("|cff888888Tip: light up multiple icons for one combined route.|r")
            end
        else
            GameTooltip:AddLine("No gathering professions known on this character.")
            GameTooltip:AddLine("|cff888888Learn Mining, Herbalism, or Lumberjacking to use this.|r")
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff888888Drag|r: Move this")
        GameTooltip:Show()
    end)
    slot:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    slot:RegisterForClicks("LeftButtonUp")
    slot:SetScript("OnClick", function(self)
        if not self.nodeType then return end
        ToggleType(self.nodeType)
    end)

    -- Slots fully cover the container, so dragging has to be handled here too -
    -- otherwise the container's own drag scripts would never get a chance to fire.
    slot:RegisterForDrag("LeftButton")
    slot:SetScript("OnDragStart", OnDragStartShared)
    slot:SetScript("OnDragStop", OnDragStopShared)

    return slot
end

-- Compact's X shape - fully self-contained (2026-09-01, replacing the earlier
-- version that called into MarkerRenderer, the map/minimap pin system). That
-- reuse was a shortcut and a mistake: it silently inherited map-pin settings
-- (the marker opacity slider, the glow toggle, the pin-style picker) that
-- have nothing to do with this button, and should never have been touched.
-- This shape, its colors, and its rendering are entirely private to
-- QuickButton.lua - nothing here reads from or calls into MarkerRenderer or
-- any Settings key that also affects the map/minimap.
local COMPACT_X_POINTS = {
    {-0.445,0.757}, {0.000,0.311}, {0.445,0.757}, {0.757,0.445},
    {0.311,-0.000}, {0.757,-0.445}, {0.445,-0.757}, {-0.000,-0.311},
    {-0.445,-0.757}, {-0.757,-0.445}, {-0.311,0.000}, {-0.757,0.445},
}
-- Bright magenta/lime/cyan - originally a visibility diagnostic, kept as the
-- real Compact palette per direct request 2026-09-01 ("I like the bright
-- colors... don't revert them").
local COMPACT_COLORS = {
    mine = { 1, 0, 1 },
    herb = { 0, 1, 0 },
    lumber = { 0, 1, 1 },
}
local COMPACT_DISABLED_COLOR = { 0.4, 0.4, 0.4 }

-- The original muted red/green/blue, from before Compact's line color became
-- bright neon - used ONLY as the active-route glow now, never as the line
-- itself. Confirmed 2026-09-02: using the same bright color for both would
-- just wash the line out instead of standing apart from it.
local COMPACT_CLASSIC_COLORS = {
    mine = { 0.85, 0.2, 0.2 },
    herb = { 0.15, 0.85, 0.25 },
    lumber = { 0.15, 0.3, 0.75 },
}

-- Creates the (initially hidden) texture parts a slot needs to draw the
-- Compact X. Safe to call repeatedly - only builds them once per slot.
local function EnsureCompactXParts(slot)
    if slot.compactSeg then return end
    slot.compactSeg = {}
    for i = 1, #COMPACT_X_POINTS do
        local tex = slot:CreateTexture(nil, "ARTWORK")
        tex:Hide()
        slot.compactSeg[i] = tex
    end
    -- Active-route glow - BACKGROUND layer so it sits behind the line
    -- segments (ARTWORK). Reuses the addon's existing glow art asset (the
    -- same one the old rune icons/map pins use), just tinted per-profession
    -- here - not calling into MarkerRenderer or reading any of its settings.
    local glow = slot:CreateTexture(nil, "BACKGROUND")
    glow:SetTexture("Interface\\AddOns\\XalsXpeditedRoutes\\Textures\\Glow")
    glow:Hide()
    slot.compactGlow = glow
end

-- Positions+rotates a texture to form a line from (x1,y1) to (x2,y2), both
-- offsets relative to the slot's own center. Solid color, always full alpha -
-- Compact never fades, regardless of any other setting in the addon.
local function PlaceCompactSegment(slot, tex, x1, y1, x2, y2, thickness, color)
    local dx, dy = x2 - x1, y2 - y1
    local length = math.max(math.sqrt(dx * dx + dy * dy), 0.1)
    local angle = math.atan2(dy, dx)
    tex:ClearAllPoints()
    tex:SetSize(length, thickness)
    tex:SetPoint("CENTER", slot, "CENTER", (x1 + x2) / 2, (y1 + y2) / 2)
    tex:SetRotation(angle)
    tex:SetColorTexture(color[1], color[2], color[3], 1)
    tex:Show()
end

-- Draws the Compact X onto `slot` - the line itself is always solid color,
-- full opacity, no glow. isTarget (the active route target) adds a soft
-- glow behind it in classicColor (the muted original palette), not the
-- line's own bright color.
local function DrawCompactX(slot, color, size, thickness, isTarget, classicColor)
    EnsureCompactXParts(slot)
    local half = size / 2
    local n = #COMPACT_X_POINTS
    for i = 1, n do
        local p1, p2 = COMPACT_X_POINTS[i], COMPACT_X_POINTS[(i % n) + 1]
        PlaceCompactSegment(slot, slot.compactSeg[i],
            p1[1] * half, p1[2] * half, p2[1] * half, p2[2] * half, thickness, color)
    end
    if isTarget and classicColor then
        local glowSize = size * 2.2
        slot.compactGlow:ClearAllPoints()
        slot.compactGlow:SetSize(glowSize, glowSize)
        slot.compactGlow:SetPoint("CENTER", slot, "CENTER", 0, 0)
        slot.compactGlow:SetVertexColor(classicColor[1], classicColor[2], classicColor[3], 0.8)
        slot.compactGlow:Show()
    else
        slot.compactGlow:Hide()
    end
end

-- Repaints a slot for a given node type ("mine"/"herb"/"lumber"), or nil for the
-- disabled "no professions known" placeholder. centered = true (Compact) draws
-- the self-contained thin X above, with the count centered inside it.
-- centered = false (Classic) keeps the original baked rune-icon texture with
-- the count below it.
local function ConfigureSlot(slot, nodeType, pinSize, centered)
    slot.nodeType = nodeType

    -- Compact's hit area sits close to the drawn X (COMPACT_HIT_PADDING);
    -- Classic keeps its original larger +10 padding, unchanged.
    local hitPadding = centered and COMPACT_HIT_PADDING or 10
    slot:SetSize(pinSize + hitPadding, pinSize + hitPadding)

    if centered then
        if slot.runeXTest then slot.runeXTest:Hide() end
        if slot.glowTex then slot.glowTex:Hide() end
        local color = nodeType and (COMPACT_COLORS[nodeType] or COMPACT_COLORS.herb) or COMPACT_DISABLED_COLOR
        local classicColor = nodeType and COMPACT_CLASSIC_COLORS[nodeType]
        -- Fixed thin thickness, not scaled up with size - at the shape's
        -- narrow waist, a thickness that scales with pinSize touches itself
        -- and merges into a solid blob instead of staying a hollow outline.
        local thickness = 1.5
        DrawCompactX(slot, color, pinSize, thickness, nodeType and IsTypeOn(nodeType), classicColor)
    else
        if slot.compactSeg then
            for _, tex in ipairs(slot.compactSeg) do tex:Hide() end
        end
        if slot.compactGlow then slot.compactGlow:Hide() end

        local texSize = pinSize * RUNE_TEX_SCALE
        if slot.runeXTest then
            slot.runeXTest:SetSize(texSize, texSize)
            if slot.glowTex then
                local glowColor = COMPACT_COLORS[nodeType] or COMPACT_COLORS.mine
                slot.glowTex:ClearAllPoints()
                slot.glowTex:SetSize(texSize * 1.6, texSize * 1.6)
                slot.glowTex:SetPoint("CENTER", slot.runeXTest, "CENTER", 0, 0)
                slot.glowTex:SetVertexColor(glowColor[1], glowColor[2], glowColor[3], 0.8)
                slot.glowTex:Show()
            end
            -- Active-state: swap to the pre-baked yellow-interior icon when this
            -- profession's route is the one currently running, back to the
            -- transparent-interior icon otherwise.
            if nodeType and IsTypeOn(nodeType) then
                slot.runeXTest:SetTexture("Interface\\AddOns\\XalsXpeditedRoutes\\Textures\\RuneX_Active_Test")
            else
                slot.runeXTest:SetTexture("Interface\\AddOns\\XalsXpeditedRoutes\\Textures\\RuneX_Test")
            end
            slot.runeXTest:Show()
        end
    end

    slot.countText:ClearAllPoints()
    if centered then
        slot.countText:SetJustifyH("CENTER")
        -- Nudged slightly right - it was reading consistently left of center.
        slot.countText:SetPoint("CENTER", slot, "CENTER", 1.5, 0)
        local font = slot.countText:GetFont()
        slot.countText:SetFont(font, math.max(9, math.floor(pinSize * 0.42)), "OUTLINE")
        -- The 1.5px drop shadow set below (for the Classic below-icon label)
        -- visibly drags the digit off its true centered anchor at this small
        -- size - zeroed here so it actually sits centered in the X.
        slot.countText:SetShadowOffset(0, 0)
    else
        slot.countText:SetPoint("TOP", slot, "BOTTOM", 0, -2)
        local font = slot.countText:GetFont()
        slot.countText:SetFont(font, 16)
        slot.countText:SetShadowOffset(1.5, -1.5)
    end

    if nodeType then
        slot.countText:SetText(tostring(GetZoneNodeCount(nodeType)))
        slot.countText:Show()
    else
        slot.countText:Hide()
    end
end

-- Xperimental dungeon-waypoint button, in its own popup list. Retail-only (the
-- waypoint API doesn't exist on Classic), so the button stays hidden there.
local function DungeonNavAvailable()
    return (C_Map and C_Map.SetUserWaypoint) and true or false
end

local function BuildDungeonMenu()
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    local menu = CreateFrame("Frame", "XalsXRDungeonMenu", UIParent, template)
    menu:SetFrameStrata("DIALOG")
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu:Hide()
    if menu.SetBackdrop then
        menu:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        menu:SetBackdropColor(0, 0, 0, 0.95)
        menu:SetBackdropBorderColor(0.25, 0.55, 0.75, 1)
    end

    local dungeons = (addonTable.DungeonNav and addonTable.DungeonNav.SEASON2) or {}
    local width, pad, rowH = 178, 8, 18

    local header = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    header:SetPoint("TOPLEFT", pad, -pad)
    header:SetText("|cff00ccffWaypoint to dungeon:|r")

    local y = -pad - rowH
    for _, d in ipairs(dungeons) do
        local dungeon = d
        local row = CreateFrame("Button", nil, menu)
        row:SetSize(width - pad * 2, rowH)
        row:SetPoint("TOPLEFT", pad, y)
        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", 2, 0)
        fs:SetText(dungeon.name)
        row:SetScript("OnEnter", function() fs:SetTextColor(1, 0.82, 0) end)
        row:SetScript("OnLeave", function() fs:SetTextColor(1, 1, 1) end)
        row:SetScript("OnClick", function()
            if addonTable.DungeonNav and addonTable.DungeonNav.Command then
                addonTable.DungeonNav:Command(dungeon.name)
            end
            menu:Hide()
        end)
        y = y - rowH
    end

    menu:SetSize(width, pad * 2 + rowH + #dungeons * rowH)
    return menu
end

-- Fully independent draggable frame - not parented to or positioned relative to
-- the profession/Gather cluster at all, confirmed 2026-09-01, so it can sit
-- tucked somewhere inconspicuous instead of always hanging off Gather.
local function CreateDungeonContainer()
    local frame = CreateFrame("Button", "XalsXRDungeonButton", UIParent)
    frame:SetSize(DUNGEON_BTN_SIZE, DUNGEON_BTN_SIZE)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForClicks("LeftButtonUp")
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", OnDungeonDragStart)
    frame:SetScript("OnDragStop", OnDungeonDragStop)

    local tex = frame:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture("Interface\\AddOns\\XalsXpeditedRoutes\\Textures\\DungeonNavIcon_Test")
    frame.tex = tex
    local hl = frame:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.25)

    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("|cff00ccffXal's XR: Dungeon waypoint |cff888888(Xperimental)|r")
        GameTooltip:AddLine("|cff00ff00Click|r: pick a Season 2 dungeon to waypoint to.")
        GameTooltip:AddLine("|cff888888Drag|r: Move this")
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame:SetScript("OnClick", function(self)
        if not dungeonMenu then dungeonMenu = BuildDungeonMenu() end
        if dungeonMenu:IsShown() then
            dungeonMenu:Hide()
        else
            dungeonMenu:ClearAllPoints()
            dungeonMenu:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
            dungeonMenu:Show()
        end
    end)

    return frame
end

-- The Classic "Gather" button: a boxed button with the shared background image.
local function CreateClassicGatherButton(parent)
    local btn = Brand.MakeButton(parent, "Gather", GATHER_BTN_WIDTH, GATHER_BTN_HEIGHT, function()
        if addonTable.RunTracker and addonTable.RunTracker.StartManualSession then
            addonTable.RunTracker:StartManualSession()
        end
    end)
    Brand.ApplyBackgroundImage(btn)
    do
        local font, size, flags = btn.label:GetFont()
        btn.label:SetFont(font, size + 2, flags)
    end
    return btn
end

-- The Compact "Gather" text link: plain orange text, no box, no background
-- image. Uses Brand.Title() - the same font and shadow as the Gather Tally
-- window's header - instead of a plain fontstring, confirmed 2026-09-02
-- ("use the same title font on the floating helper button, gather tally" -
-- the floating helper is what changes to match Gather Tally, not the other
-- way around).
local function CreateCompactGatherButton(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(60, COMPACT_GATHER_HEIGHT)

    local label = Brand.Title(btn, "Gather", 15, "CENTER", btn, "CENTER", 0, 0)
    label:SetTextColor(GATHER_COLOR[1], GATHER_COLOR[2], GATHER_COLOR[3])
    btn.label = label

    btn:SetScript("OnEnter", function()
        label:SetTextColor(GATHER_COLOR_HOVER[1], GATHER_COLOR_HOVER[2], GATHER_COLOR_HOVER[3], 1)
    end)
    btn:SetScript("OnLeave", function()
        label:SetTextColor(GATHER_COLOR[1], GATHER_COLOR[2], GATHER_COLOR[3], 1)
    end)
    btn:SetScript("OnClick", function()
        if addonTable.RunTracker and addonTable.RunTracker.StartManualSession then
            addonTable.RunTracker:StartManualSession()
        end
    end)

    return btn
end

local function CreateGatherButton(parent)
    local btn = IsCompactLayout() and CreateCompactGatherButton(parent) or CreateClassicGatherButton(parent)
    btn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("|cff00ccffXal's Xpedited Routes|r")
        GameTooltip:AddLine("|cff00ff00Click|r: Open the Gather Tally and start tracking your haul.")
        GameTooltip:AddLine("|cff888888Drag|r: Move this")
        GameTooltip:Show()
    end)
    btn:HookScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", OnDragStartShared)
    btn:SetScript("OnDragStop", OnDragStopShared)
    return btn
end

-- Rebuilds the Gather button from scratch when the layout setting changes (the
-- two versions are different enough - box vs. text link - that repainting one
-- frame type isn't practical).
local function RebuildGatherButton()
    if gatherBtn then
        gatherBtn:Hide()
        gatherBtn:SetParent(nil)
        gatherBtn = nil
    end
    gatherBtn = CreateGatherButton(container)
end

-- Positions the Classic layout: lumber centered above the mine/herb pair
-- (triangle), a boxed Gather button spanning underneath both.
local function LayoutClassic()
    local slotsWidth = SLOT_SIZE * 2 + SLOT_GAP
    local rowHeight = SLOT_SIZE + COUNT_LABEL_SPACE + SLOT_GAP
    local halfOffset = SLOT_SIZE / 2 + SLOT_GAP / 2

    slotLumber:ClearAllPoints()
    slotLumber:SetPoint("TOP", container, "TOP", 0, 0)

    slotMine:ClearAllPoints()
    slotMine:SetPoint("TOP", container, "TOP", -halfOffset, -rowHeight)

    slotHerb:ClearAllPoints()
    slotHerb:SetPoint("TOP", container, "TOP", halfOffset, -rowHeight)

    gatherBtn:ClearAllPoints()
    gatherBtn:SetPoint("TOP", container, "TOP", 0, -(rowHeight * 2))

    container:SetSize(slotsWidth, (rowHeight * 2) + GATHER_BTN_HEIGHT)
end

-- Positions the Compact layout: Gather text link on top, then the KNOWN
-- profession X's stacked directly under it with no gaps - a profession this
-- character doesn't have just isn't in the stack at all, rather than leaving
-- its old fixed slot empty. Confirmed 2026-09-01 ("it should automatically
-- populate up if there's nothing in the other space") - this replaces the
-- fixed-slot-per-type principle Classic still uses.
local function LayoutCompact(visibleSlots)
    local iconRowHeight = COMPACT_SLOT_SIZE + COMPACT_ICON_GAP

    gatherBtn:ClearAllPoints()
    gatherBtn:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)

    local y = -(COMPACT_GATHER_HEIGHT + COMPACT_GAP)
    for _, slot in ipairs(visibleSlots) do
        slot:ClearAllPoints()
        slot:SetPoint("TOPLEFT", container, "TOPLEFT", 0, y)
        y = y - iconRowHeight
    end

    local width = math.max(COMPACT_SLOT_SIZE, gatherBtn:GetWidth())
    local iconsHeight = #visibleSlots > 0 and (iconRowHeight * #visibleSlots - COMPACT_ICON_GAP) or 0
    local height = COMPACT_GATHER_HEIGHT + COMPACT_GAP + iconsHeight
    container:SetSize(width, height)
end

-- Recomputes which professions this character knows and lays the slot(s) out
-- accordingly. Cheap enough to call on every refresh tick so it self-corrects if
-- the character learns a new profession mid-session.
local function UpdateLayout()
    if not container then return end

    local hasMining = Helpers.HasGatheringProfession(Helpers.MINING_SKILL_LINE, Helpers.MINING_NAMES)
    local hasHerb = Helpers.HasGatheringProfession(Helpers.HERBALISM_SKILL_LINE, Helpers.HERBALISM_NAMES)
    local hasLumber = Helpers.HasLumberjacking()

    -- Safety net: same detection-glitch guard as Markers.lua/PathPlanner.lua - "knows
    -- none of the three" is far more likely stale/uncached detection than reality.
    if not hasMining and not hasHerb and not hasLumber then
        hasMining, hasHerb, hasLumber = true, true, true
    end

    local compact = IsCompactLayout()
    local pinSize = compact and COMPACT_PIN_SIZE or BUTTON_PIN_SIZE

    local visibleSlots = {}
    if hasMining then
        ConfigureSlot(slotMine, "mine", pinSize, compact); slotMine:Show()
        table.insert(visibleSlots, slotMine)
    else slotMine:Hide() end
    if hasHerb then
        ConfigureSlot(slotHerb, "herb", pinSize, compact); slotHerb:Show()
        table.insert(visibleSlots, slotHerb)
    else slotHerb:Hide() end
    if hasLumber then
        ConfigureSlot(slotLumber, "lumber", pinSize, compact); slotLumber:Show()
        table.insert(visibleSlots, slotLumber)
    else slotLumber:Hide() end

    if compact then
        LayoutCompact(visibleSlots)
    else
        LayoutClassic()
    end

    local dungeonVisible = dungeonContainer and DungeonNavAvailable()
        and XalsXRDB and XalsXRDB.dungeonButtonEnabled
    if dungeonContainer then
        if dungeonVisible then
            dungeonContainer:Show()
        else
            dungeonContainer:Hide()
            if dungeonMenu then dungeonMenu:Hide() end
        end
    end
end

function QuickButton:Init()
    if container then return end
    if XalsXRDB and XalsXRDB.showHelperButton == false then return end

    container = CreateFrame("Frame", "XalsXRHelperButton", UIParent)
    container:SetSize(SLOT_SIZE, SLOT_SIZE)
    container:SetMovable(true)
    container:EnableMouse(true)
    container:RegisterForDrag("LeftButton")

    local pos = Helpers.SanitizePoint(XalsXRDB and XalsXRDB.helperButtonPosition,
        { point = "CENTER", x = 100, y = 180 })
    if XalsXRDB then
        XalsXRDB.helperButtonPosition = pos
    end
    container:ClearAllPoints()
    container:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)

    container:SetScript("OnDragStart", OnDragStartShared)
    container:SetScript("OnDragStop", OnDragStopShared)
    container:SetScript("OnEnter", HandleHoverEnter)
    container:SetScript("OnLeave", HandleHoverLeave)

    slotMine = CreateSlot(container)
    slotHerb = CreateSlot(container)
    slotLumber = CreateSlot(container)
    gatherBtn = CreateGatherButton(container)

    dungeonContainer = CreateDungeonContainer()
    local dungeonPos = Helpers.SanitizePoint(XalsXRDB and XalsXRDB.dungeonButtonPosition,
        { point = "CENTER", x = 0, y = 0 })
    if XalsXRDB then
        XalsXRDB.dungeonButtonPosition = dungeonPos
    end
    dungeonContainer:ClearAllPoints()
    dungeonContainer:SetPoint(dungeonPos.point, UIParent, dungeonPos.point, dungeonPos.x, dungeonPos.y)

    -- HookScript (not SetScript) on every child button - each already has
    -- its own OnEnter/OnLeave for tooltips, which a plain SetScript here
    -- would silently replace. Hooking means hovering ANY slot/button in the
    -- cluster correctly counts as "still active" for the fade timer, not
    -- just the container frame's own (smaller) hit area.
    for _, btn in ipairs({ slotMine, slotHerb, slotLumber, gatherBtn }) do
        if btn then
            btn:HookScript("OnEnter", HandleHoverEnter)
            btn:HookScript("OnLeave", HandleHoverLeave)
        end
    end

    container:SetScale((XalsXRDB and XalsXRDB.helperButtonScale) or 1)

    UpdateLayout()

    container:SetScript("OnUpdate", function(self, elapsed)
        refreshTimer = refreshTimer + elapsed
        if refreshTimer >= refreshInterval then
            refreshTimer = 0
            UpdateLayout()
        end
    end)
end

function QuickButton:Show()
    if not container then
        XalsXRDB.showHelperButton = true
        self:Init()
    end
    if container then container:Show() end
    XalsXRDB.showHelperButton = true
end

function QuickButton:Hide()
    if container then container:Hide() end
    if dungeonMenu then dungeonMenu:Hide() end
    XalsXRDB.showHelperButton = false
end

function QuickButton:Toggle()
    if container and container:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

function QuickButton:Refresh()
    UpdateLayout()
end

-- Called by the Settings layout picker (Compact/Classic) - the two Gather
-- button styles are different enough to need a full rebuild, not a repaint.
function QuickButton:ApplyLayout()
    if not container then return end
    RebuildGatherButton()
    if gatherBtn then
        gatherBtn:HookScript("OnEnter", HandleHoverEnter)
        gatherBtn:HookScript("OnLeave", HandleHoverLeave)
    end
    UpdateLayout()
end

-- Called by the Floating Button settings panel's scale slider (and its
-- Defaults reset) - live-applies without needing a reload.
function QuickButton:ApplyScale()
    if container then
        container:SetScale((XalsXRDB and XalsXRDB.helperButtonScale) or 1)
    end
end

function QuickButton:ResetPosition()
    XalsXRDB.helperButtonPosition = { point = "CENTER", x = 100, y = 180 }
    if container then
        container:ClearAllPoints()
        container:SetPoint("CENTER", UIParent, "CENTER", 100, 180)
    end
end

function QuickButton:ResetDungeonPosition()
    XalsXRDB.dungeonButtonPosition = { point = "CENTER", x = 0, y = 0 }
    if dungeonContainer then
        dungeonContainer:ClearAllPoints()
        dungeonContainer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end
