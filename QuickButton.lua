-- QuickButton.lua
-- Xal's Xpedited Routes
--
-- A small, draggable floating control for one-click route control, for players who
-- don't want to remember /xxr chat commands. It adapts to what THIS character can
-- actually gather:
--   - Mining (bottom-left), Herbalism (bottom-right), Lumberjacking (top-center,
--     triangle layout, confirmed 2026-08-17) - each an independent on/off toggle.
--     Any combination of icons lit builds one combined route through those types;
--     all off = no route.
--   - A profession this character doesn't know still gets its fixed slot position,
--     just hidden, so the layout never shifts around based on what's learned.
--   - Knows none of the three -> a single greyed placeholder, nothing to click
--
-- Each button is drawn with MarkerRenderer (the same shape system used for map/minimap
-- pins) at a larger size, so it always matches whatever marker style is selected in
-- Settings instead of being a generic shape of its own.
--
-- Click: flips that type's toggle and regenerates the route to match whichever
-- type(s) are now on (or clears it if all end up off).
-- Drag the whole thing: reposition (position is saved).
local addonName, addonTable = ...
local QuickButton = addonTable.QuickButton
local PathPlanner = addonTable.PathPlanner
local Helpers = addonTable.Helpers
local MarkerRenderer = addonTable.MarkerRenderer
local Brand = addonTable.BrandStyle

local container = nil -- outer draggable frame
local slotMine, slotHerb, slotLumber = nil, nil, nil -- slotMine doubles as the only button when just one profession (or none) is known. slotLumber sits centered above the mine/herb pair, triangle-style.
local gatherBtn = nil -- "Gather" button under the stack; opens the Gather Tally
local dungeonBtn, dungeonMenu = nil, nil -- Xperimental dungeon-waypoint button + its popup list

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

local SLOT_SIZE = 40 -- clickable hit area
local BUTTON_PIN_SIZE = 30 -- drawn shape size (bigger than the default 14px map pin)
local SLOT_GAP = 4
local GATHER_BTN_HEIGHT = 24 -- the "Gather" button under the profession slot(s) - bumped from 18 for breathing room around the label
-- Matches slotsWidth (SLOT_SIZE*2 + SLOT_GAP) in UpdateLayout so the button
-- spans the full width under both side-by-side profession slots instead of
-- looking like a narrow stem under a wider top. Confirmed 2026-08-09.
local GATHER_BTN_WIDTH = SLOT_SIZE * 2 + SLOT_GAP
local COUNT_LABEL_SPACE = 20 -- room reserved for the bottom slot's count label - bumped from 14 to fit the larger 16pt count font
local DUNGEON_BTN_SIZE = 64 -- bumped from 22 to match the profession X icons, and moved to sit below Gather instead of beside it
local DISABLED_COLOR = { 0.4, 0.4, 0.4 }
local refreshInterval = 0.5
local refreshTimer = 0

local LABELS = { mine = "Mining", herb = "Herbalism", lumber = "Lumberjacking" }

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

-- Builds one slot button: a 40x40 clickable area, rendered via MarkerRenderer, with a
-- node-count label underneath. Called once per slot at Init - after that,
-- ConfigureSlot() just repaints/rebinds it.
local function CreateSlot(parent)
    local slot = CreateFrame("Button", nil, parent)
    slot:SetSize(SLOT_SIZE, SLOT_SIZE)
    MarkerRenderer.EnsureParts(slot)

    -- TEST ONLY, 2026-08-09: visual test of the new rune-X icon on the
    -- floating helper button, isolated from MarkerRenderer entirely so
    -- actual map/minimap markers are untouched. Two complete baked icon
    -- variants (idle = transparent interior, active = interior pre-filled
    -- solid yellow) instead of layering a separate tintable mask - simpler,
    -- and avoids any layering/z-order fragility. ConfigureSlot just swaps
    -- which one SetTexture points at.
    local runeXTest = slot:CreateTexture(nil, "ARTWORK")
    runeXTest:SetTexture("Interface\\AddOns\\XalsXpeditedRoutes\\Textures\\RuneX_Test")
    runeXTest:SetSize(64, 64) -- bumped way up from BUTTON_PIN_SIZE (30) for visibility testing
    runeXTest:SetPoint("CENTER", slot, "CENTER", 0, 0)
    slot.runeXTest = runeXTest

    local countText = slot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countText:SetPoint("TOP", slot, "BOTTOM", 0, -2)
    countText:SetTextColor(1, 1, 1, 1)
    -- Bumped up from GameFontNormalSmall's default (~10pt) - the node count
    -- was hard to read against busy terrain at the old size.
    do
        local font, _, flags = countText:GetFont()
        countText:SetFont(font, 16, flags)
    end
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

-- Repaints a slot for a given node type ("mine"/"herb"), or nil for the disabled
-- "no professions known" placeholder. Uses whatever marker style is selected in
-- Settings, same as the map pins, just at BUTTON_PIN_SIZE instead of the map size.
local function ConfigureSlot(slot, nodeType)
    slot.nodeType = nodeType

    -- TEST ONLY, 2026-08-09: while testing the new rune-X icon, skip the
    -- normal MarkerRenderer draw for this slot entirely and just show the
    -- static test texture instead. Glow color now follows the slot's actual
    -- node type - Mining red or Herbalism green, same colors used everywhere
    -- else in the addon - instead of being hardcoded to Mining.
    if slot.runeXTest then
        for _, tex in ipairs(slot.segTex or {}) do tex:Hide() end
        if slot.dotTex then slot.dotTex:Hide() end
        if slot.glowTex then
            local glowColor = (nodeType == "herb" and MarkerRenderer.HERB_COLOR)
                or (nodeType == "lumber" and MarkerRenderer.LUMBER_COLOR)
                or MarkerRenderer.MINE_COLOR
            slot.glowTex:ClearAllPoints()
            slot.glowTex:SetSize(64 * 1.6, 64 * 1.6)
            slot.glowTex:SetPoint("CENTER", slot.runeXTest, "CENTER", 0, 0)
            slot.glowTex:SetVertexColor(glowColor[1], glowColor[2], glowColor[3], 0.8)
            slot.glowTex:Show()
        end
        -- Active-state test: swap to the pre-baked yellow-interior icon when
        -- this profession's route is the one currently running, back to the
        -- transparent-interior icon otherwise. Reuses IsTypeOn() - the same
        -- check the old MarkerRenderer isTarget flag used - rather than
        -- inventing new logic.
        if nodeType and IsTypeOn(nodeType) then
            slot.runeXTest:SetTexture("Interface\\AddOns\\XalsXpeditedRoutes\\Textures\\RuneX_Active_Test")
        else
            slot.runeXTest:SetTexture("Interface\\AddOns\\XalsXpeditedRoutes\\Textures\\RuneX_Test")
        end
        slot.runeXTest:Show()
    end

    if nodeType then
        slot.countText:SetText(tostring(GetZoneNodeCount(nodeType)))
        slot.countText:Show()
    else
        -- No professions known: a plain grey hexagon placeholder regardless of the
        -- chosen map style, since there's no "mine"/"herb" icon that would apply.
        if not slot.runeXTest then
            local thickness = math.max(1.5, BUTTON_PIN_SIZE / 7)
            MarkerRenderer.Draw(slot, "hollowx", DISABLED_COLOR, BUTTON_PIN_SIZE, thickness)
        end
        slot.countText:Hide()
    end
end

-- Xperimental dungeon-waypoint button + its popup list. Retail-only (the waypoint
-- API doesn't exist on Classic), so the button stays hidden there.
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

local function CreateDungeonButton(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(DUNGEON_BTN_SIZE, DUNGEON_BTN_SIZE)
    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    -- TEST ONLY, 2026-08-09: trying the new custom rune-framed dungeon-
    -- entrance icon in place of the stock Blizzard map icon. No TexCoord
    -- crop here (unlike the old icon) since this one already has its own
    -- full border baked in - the 0.07-0.93 crop was only there to trim
    -- Blizzard's generic icon bevel.
    tex:SetTexture("Interface\\AddOns\\XalsXpeditedRoutes\\Textures\\DungeonNavIcon_Test")
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.25)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("|cff00ccffXal's XR: Dungeon waypoint |cff888888(Xperimental)|r")
        GameTooltip:AddLine("|cff00ff00Click|r: pick a Season 2 dungeon to waypoint to.")
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    btn:SetScript("OnClick", function(self)
        if not dungeonMenu then dungeonMenu = BuildDungeonMenu() end
        if dungeonMenu:IsShown() then
            dungeonMenu:Hide()
        else
            dungeonMenu:ClearAllPoints()
            dungeonMenu:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
            dungeonMenu:Show()
        end
    end)
    return btn
end

-- The "Gather" button under the profession slots: opens the Gather Tally window
-- and starts a manual tracking session (tallies loot even outside a route).
local function CreateGatherButton(parent)
    local btn = Brand.MakeButton(parent, "Gather", GATHER_BTN_WIDTH, GATHER_BTN_HEIGHT, function()
        if addonTable.RunTracker and addonTable.RunTracker.StartManualSession then
            addonTable.RunTracker:StartManualSession()
        end
    end)
    Brand.ApplyBackgroundImage(btn)
    -- Bump the label size to fill the now-wider button proportionally,
    -- instead of small text floating in a lot of empty space.
    do
        local font, size, flags = btn.label:GetFont()
        btn.label:SetFont(font, size + 2, flags)
    end
    -- Brand.MakeButton already wires OnEnter/OnLeave for its own hover
    -- brighten effect; re-set here to ALSO keep that effect AND add the
    -- tooltip, rather than replacing it outright.
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.18, 0.18, 0.18, 0.75)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("|cff00ccffXal's Xpedited Routes|r")
        GameTooltip:AddLine("|cff00ff00Click|r: Open the Gather Tally and start tracking your haul.")
        GameTooltip:AddLine("|cff888888Drag|r: Move this")
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.1, 0.1, 0.1, 0.6)
        GameTooltip:Hide()
    end)
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", OnDragStartShared)
    btn:SetScript("OnDragStop", OnDragStopShared)
    return btn
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

    -- Mining, Herbalism, and Lumberjacking each have a PERMANENT position -
    -- Mining always left, Herbalism always right (of the Gather button's own
    -- horizontal center, x=0), Lumberjacking always centered above that pair
    -- (triangle layout, confirmed 2026-08-17) - regardless of which
    -- professions this character actually has. Deliberately NOT conditional
    -- on "all known" - a character missing one still gets that slot's fixed
    -- position, just hidden, so the layout never shifts around based on what's
    -- learned. Confirmed 2026-08-09 - "don't care if it's a little off
    -- center... have it be a permanent position" so professions being
    -- added/detected later can't cause a misalignment.
    local slotsWidth = SLOT_SIZE * 2 + SLOT_GAP
    local rowHeight = SLOT_SIZE + COUNT_LABEL_SPACE + SLOT_GAP
    local halfOffset = SLOT_SIZE / 2 + SLOT_GAP / 2

    slotLumber:ClearAllPoints()
    slotLumber:SetPoint("TOP", container, "TOP", 0, 0)
    if hasLumber then
        ConfigureSlot(slotLumber, "lumber")
        slotLumber:Show()
    else
        slotLumber:Hide()
    end

    slotMine:ClearAllPoints()
    slotMine:SetPoint("TOP", container, "TOP", -halfOffset, -rowHeight)
    if hasMining then
        ConfigureSlot(slotMine, "mine")
        slotMine:Show()
    else
        slotMine:Hide()
    end

    slotHerb:ClearAllPoints()
    slotHerb:SetPoint("TOP", container, "TOP", halfOffset, -rowHeight)
    if hasHerb then
        ConfigureSlot(slotHerb, "herb")
        slotHerb:Show()
    else
        slotHerb:Hide()
    end

    -- The Gather button hangs below both rows (past the mine/herb row's count
    -- label), and the container grows to include it so the whole thing drags as one.
    if gatherBtn then
        gatherBtn:ClearAllPoints()
        gatherBtn:SetPoint("TOP", container, "TOP", 0, -(rowHeight * 2))
    end

    -- TEST, 2026-08-09: moved from beside the Gather button to centered
    -- underneath it, on the same vertical axis as everything else - beside
    -- it (even with the player-selectable side) reintroduced the exact
    -- left/right asymmetry the profession-slot layout was just fixed to
    -- avoid. Also bumped up to match the profession X icons' size (64px),
    -- up from the old 22px stock-icon size.
    local dungeonBtnVisible = dungeonBtn and gatherBtn and DungeonNavAvailable()
        and XalsXRDB and XalsXRDB.dungeonButtonEnabled

    local containerHeight = (rowHeight * 2) + (gatherBtn and GATHER_BTN_HEIGHT or 0)
    if dungeonBtnVisible then
        containerHeight = containerHeight + SLOT_GAP + DUNGEON_BTN_SIZE
    end
    container:SetSize(slotsWidth, containerHeight)

    if dungeonBtn then
        if dungeonBtnVisible then
            dungeonBtn:ClearAllPoints()
            dungeonBtn:SetPoint("TOP", gatherBtn, "BOTTOM", 0, -SLOT_GAP)
            dungeonBtn:Show()
        else
            dungeonBtn:Hide()
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
    dungeonBtn = CreateDungeonButton(container)

    -- HookScript (not SetScript) on every child button - each already has
    -- its own OnEnter/OnLeave for tooltips, which a plain SetScript here
    -- would silently replace. Hooking means hovering ANY slot/button in the
    -- cluster correctly counts as "still active" for the fade timer, not
    -- just the container frame's own (smaller) hit area.
    for _, btn in ipairs({ slotMine, slotHerb, slotLumber, gatherBtn, dungeonBtn }) do
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
