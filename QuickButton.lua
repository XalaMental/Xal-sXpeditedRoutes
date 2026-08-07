-- QuickButton.lua
-- Xal's Xpedited Routes
--
-- A small, draggable floating control for one-click route control, for players who
-- don't want to remember /xxr chat commands. It adapts to what THIS character can
-- actually gather:
--   - Knows both Mining and Herbalism -> two buttons, stacked vertically, each an
--     independent on/off toggle. Both on at once = one combined route. Only one on
--     = a route restricted to that type. Both off = no route.
--   - Knows only one                  -> a single button for that profession
--   - Knows neither                   -> a single greyed placeholder, nothing to click
--
-- Each button is drawn with MarkerRenderer (the same shape system used for map/minimap
-- pins) at a larger size, so it always matches whatever marker style is selected in
-- Settings instead of being a generic shape of its own.
--
-- Click: flips that type's toggle and regenerates the route to match whichever
-- type(s) are now on (or clears it if both end up off).
-- Drag the whole thing: reposition (position is saved).
local addonName, addonTable = ...
local QuickButton = addonTable.QuickButton
local PathPlanner = addonTable.PathPlanner
local Helpers = addonTable.Helpers
local MarkerRenderer = addonTable.MarkerRenderer

local container = nil -- outer draggable frame
local slotMine, slotHerb = nil, nil -- slotMine doubles as the only button when just one profession (or none) is known
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

local SLOT_SIZE = 40 -- clickable hit area
local BUTTON_PIN_SIZE = 30 -- drawn shape size (bigger than the default 14px map pin)
local SLOT_GAP = 4
local GATHER_BTN_HEIGHT = 18 -- the "Gather" button under the profession slot(s)
local GATHER_BTN_WIDTH = 52
local COUNT_LABEL_SPACE = 14 -- room reserved for the bottom slot's count label
local DUNGEON_BTN_SIZE = 22 -- the Xperimental dungeon-waypoint icon beside Gather
local DISABLED_COLOR = { 0.4, 0.4, 0.4 }
local refreshInterval = 0.5
local refreshTimer = 0

local LABELS = { mine = "Mining", herb = "Herbalism" }

-- Whether a given type is currently included in the active route - true whenever
-- that type is running solo OR as part of an unrestricted (combined) route.
local function IsTypeOn(nodeType)
    return PathPlanner:InProgress() and (PathPlanner.pathTypeFilter == nil or PathPlanner.pathTypeFilter == nodeType)
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
    local mineOn = IsTypeOn("mine")
    local herbOn = IsTypeOn("herb")

    if nodeType == "mine" then
        mineOn = not mineOn
    else
        herbOn = not herbOn
    end

    if mineOn and herbOn then
        PathPlanner:PlotCourse()
    elseif mineOn then
        PathPlanner:PlotCourse("mine")
    elseif herbOn then
        PathPlanner:PlotCourse("herb")
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

    local countText = slot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countText:SetPoint("TOP", slot, "BOTTOM", 0, -2)
    countText:SetTextColor(1, 1, 1, 1)
    -- Drop shadow so the count reads clearly over any world/terrain behind it.
    countText:SetShadowColor(0, 0, 0, 1)
    countText:SetShadowOffset(1, -1)
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
        else
            GameTooltip:AddLine("No gathering professions known on this character.")
            GameTooltip:AddLine("|cff888888Learn Mining or Herbalism to use this.|r")
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

    if nodeType then
        MarkerRenderer.SetAppearance(slot, nodeType, IsTypeOn(nodeType), BUTTON_PIN_SIZE)
        slot.countText:SetText(tostring(GetZoneNodeCount(nodeType)))
        slot.countText:Show()
    else
        -- No professions known: a plain grey hexagon placeholder regardless of the
        -- chosen map style, since there's no "mine"/"herb" icon that would apply.
        local thickness = math.max(1.5, BUTTON_PIN_SIZE / 7)
        MarkerRenderer.Draw(slot, "hollowx", DISABLED_COLOR, BUTTON_PIN_SIZE, thickness)
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
    tex:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
    tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
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
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(GATHER_BTN_WIDTH, GATHER_BTN_HEIGHT)
    btn:SetText("Gather")
    btn:SetNormalFontObject("GameFontNormalSmall")
    btn:SetHighlightFontObject("GameFontHighlightSmall")
    btn:RegisterForClicks("LeftButtonUp")
    btn:SetScript("OnClick", function()
        if addonTable.RunTracker and addonTable.RunTracker.StartManualSession then
            addonTable.RunTracker:StartManualSession()
        end
    end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("|cff00ccffXal's Xpedited Routes|r")
        GameTooltip:AddLine("|cff00ff00Click|r: Open the Gather Tally and start tracking your haul.")
        GameTooltip:AddLine("|cff888888Drag|r: Move this")
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
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

    -- Safety net: same detection-glitch guard as Markers.lua/PathPlanner.lua - "knows
    -- neither" is far more likely stale/uncached profession data than reality.
    if not hasMining and not hasHerb then
        hasMining, hasHerb = true, true
    end

    local slotsHeight
    if hasMining and hasHerb then
        slotsHeight = SLOT_SIZE * 2 + SLOT_GAP
        slotMine:ClearAllPoints()
        slotMine:SetPoint("TOP", container, "TOP", 0, 0)
        slotHerb:ClearAllPoints()
        slotHerb:SetPoint("TOP", container, "TOP", 0, -(SLOT_SIZE + SLOT_GAP))
        ConfigureSlot(slotMine, "mine")
        ConfigureSlot(slotHerb, "herb")
        slotHerb:Show()
    elseif hasMining or hasHerb then
        slotsHeight = SLOT_SIZE
        slotMine:ClearAllPoints()
        slotMine:SetPoint("TOP", container, "TOP", 0, 0)
        ConfigureSlot(slotMine, hasMining and "mine" or "herb")
        slotHerb:Hide()
    else
        slotsHeight = SLOT_SIZE
        slotMine:ClearAllPoints()
        slotMine:SetPoint("TOP", container, "TOP", 0, 0)
        ConfigureSlot(slotMine, nil)
        slotHerb:Hide()
    end

    -- The Gather button hangs below the slot(s) (past the bottom slot's count
    -- label), and the container grows to include it so the whole thing drags as one.
    if gatherBtn then
        gatherBtn:ClearAllPoints()
        gatherBtn:SetPoint("TOP", container, "TOP", 0, -(slotsHeight + COUNT_LABEL_SPACE + SLOT_GAP))
        container:SetSize(SLOT_SIZE, slotsHeight + COUNT_LABEL_SPACE + SLOT_GAP + GATHER_BTN_HEIGHT)
    else
        container:SetSize(SLOT_SIZE, slotsHeight)
    end

    -- Xperimental dungeon button hangs off the side of the Gather button (the side
    -- is player-selectable so it never crowds a UI), only when enabled and on retail.
    if dungeonBtn then
        if gatherBtn and DungeonNavAvailable() and XalsXRDB and XalsXRDB.dungeonButtonEnabled then
            dungeonBtn:ClearAllPoints()
            if ((XalsXRDB and XalsXRDB.dungeonButtonSide) or "right") == "left" then
                dungeonBtn:SetPoint("RIGHT", gatherBtn, "LEFT", -4, 0)
            else
                dungeonBtn:SetPoint("LEFT", gatherBtn, "RIGHT", 4, 0)
            end
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

    slotMine = CreateSlot(container)
    slotHerb = CreateSlot(container)
    gatherBtn = CreateGatherButton(container)
    dungeonBtn = CreateDungeonButton(container)

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

function QuickButton:ResetPosition()
    XalsXRDB.helperButtonPosition = { point = "CENTER", x = 100, y = 180 }
    if container then
        container:ClearAllPoints()
        container:SetPoint("CENTER", UIParent, "CENTER", 100, 180)
    end
end
