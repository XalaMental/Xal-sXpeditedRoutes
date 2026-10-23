-- SettingsPanel.lua
-- Xal's Xpedited Routes
-- Adds a proper in-game Settings panel (Escape -> SettingsPanel -> AddOns -> Xal's Xpedited Routes)
-- for players who don't want to remember the /xxr chat commands.
--
-- Buttons here are drawn from scratch (backdrop + text) rather than using Blizzard's
-- shared UIPanelButtonTemplate, since that template is a common target for UI-skinning
-- addons and can end up reskinned in ways we don't control. Checkboxes/sliders still
-- use the standard templates.
local addonName, addonTable = ...
local SettingsPanel = addonTable.SettingsPanel
local PathPlanner = addonTable.PathPlanner
local NodeLogger = addonTable.NodeLogger
local Markers = addonTable.Markers
local Beacon = addonTable.Beacon
local QuickButton = addonTable.QuickButton
local Helpers = addonTable.Helpers
local Brand = addonTable.BrandStyle

local rootPanel, waypointPanel, markersPanel, dataPanel, integrationsPanel, gatherPanel, floatingPanel
local statsText = nil
local pinStyleButtons = {}

local function GetStatsString()
    local totalNodes = 0
    local mapCount = 0
    if XalsXRDB then
        for mapID, nodes in pairs(XalsXRDB) do
            if mapID ~= "showPins" and mapID ~= "compassPosition" and mapID ~= "autoAdvanceDistance"
                and mapID ~= "pinStyle" and mapID ~= "pinSize" and mapID ~= "showHelperButton"
                and mapID ~= "helperButtonPosition" and mapID ~= "showGlow"
                and mapID ~= "proximityDistanceYards"
                and mapID ~= "arrowProgressColor" and mapID ~= "pinAlpha"
                and mapID ~= "duplicateDistanceYards" and mapID ~= "compassArrowStyle" and mapID ~= "arrowScale" and mapID ~= "tomtomSyncEnabled" and mapID ~= "freshnessMinutes"
                and mapID ~= "showHaulSummary" and mapID ~= "haulFramePosition" and mapID ~= "haulShowIcons" and mapID ~= "haulFontScale"
                and mapID ~= "haulGatherTimer" and mapID ~= "haulRouteTimer" and mapID ~= "arrowTextScale"
                and mapID ~= "dungeonCoords" and mapID ~= "dungeonButtonEnabled" and mapID ~= "dungeonButtonSide"
                and mapID ~= "minimap" and mapID ~= "helperButtonScale" and mapID ~= "groupingDistanceYards"
                and mapID ~= "showTrailLine" and mapID ~= "boundaryNodes" and mapID ~= "helperButtonFadeWhenIdle"
                and mapID ~= "optionsWindowPoint" and mapID ~= "dungeonCompassPosition" and mapID ~= "lumberEnabled"
                and mapID ~= "dungeonButtonPosition" and type(nodes) == "table" then
                mapCount = mapCount + 1
                totalNodes = totalNodes + #nodes
            end
        end
    end
    return string.format("%d nodes saved across %d maps.", totalNodes, mapCount)
end

local function RefreshStats()
    if statsText then
        statsText:SetText(GetStatsString())
    end
end

StaticPopupDialogs["XALMORASXR_RESET_ALL"] = {
    text = "Delete the ENTIRE Xal's Xpedited Routes database (all maps, all zones)? This cannot be undone.",
    button1 = "Delete Everything",
    button2 = "Cancel",
    OnAccept = function()
        for key in pairs(XalsXRDB) do
            if key ~= "showPins" and key ~= "compassPosition" and key ~= "autoAdvanceDistance"
                and key ~= "pinStyle" and key ~= "pinSize" and key ~= "showHelperButton"
                and key ~= "helperButtonPosition" and key ~= "showGlow"
                and key ~= "proximityDistanceYards"
                and key ~= "arrowProgressColor" and key ~= "pinAlpha"
                and key ~= "duplicateDistanceYards" and key ~= "compassArrowStyle" and key ~= "arrowScale" and key ~= "tomtomSyncEnabled" and key ~= "freshnessMinutes"
                and key ~= "showHaulSummary" and key ~= "haulFramePosition" and key ~= "haulShowIcons" and key ~= "haulFontScale"
                and key ~= "haulGatherTimer" and key ~= "haulRouteTimer" and key ~= "arrowTextScale"
                and key ~= "dungeonCoords" and key ~= "dungeonButtonEnabled" and key ~= "dungeonButtonSide"
                and key ~= "minimap" and key ~= "helperButtonScale" and key ~= "groupingDistanceYards"
                and key ~= "showTrailLine" and key ~= "boundaryNodes" and key ~= "helperButtonFadeWhenIdle"
                and key ~= "optionsWindowPoint" and key ~= "dungeonCompassPosition" and key ~= "lumberEnabled"
                and key ~= "dungeonButtonPosition" then
                XalsXRDB[key] = nil
            end
        end
        print("|cff00ccffXal's XR:|r All records have been deleted.")
        PathPlanner:CancelPath()
        Markers:UpdatePins()
        RefreshStats()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- First of what's meant to become a standard "Defaults" button on every
-- settings panel (confirmed 2026-08-09) - testing it here first on the new
-- Floating Button panel before promoting the pattern into BrandStyle for
-- every panel across every addon.
StaticPopupDialogs["XALXR_RESET_FLOATING_DEFAULTS"] = {
    text = "Reset the Floating Button panel to its defaults (shown, 100% scale)?",
    button1 = "Reset",
    button2 = "Cancel",
    OnAccept = function()
        XalsXRDB.showHelperButton = nil
        XalsXRDB.helperButtonScale = nil
        QuickButton:Show()
        if QuickButton.ApplyScale then QuickButton:ApplyScale() end
        if floatingPanel and floatingPanel.Refresh then floatingPanel.Refresh() end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Thin positioning wrapper around Brand.MakeButton (the ONE confirmed
-- button standard for this addon, 2026-08-09) - kept as its own function
-- only because every call site anchors via (anchorTo, xOffset, yOffset)
-- TOPLEFT/BOTTOMLEFT instead of Brand.MakeButton's own anchor-agnostic
-- signature. There used to be a second, hand-rolled button implementation
-- here with its own border/selection logic - that was a mistake (two
-- parallel styles drifting out of sync, each with its own border bugs).
-- btn:SetSelected(bool) and btn:SetBorderColor(...) both come straight from
-- Brand.MakeButton now.
local function CreateButton(parentPanel, anchorTo, xOffset, yOffset, label, width, onClick)
    local btn = Brand.MakeButton(parentPanel, label, width or 160, 24, onClick)
    PixelUtil.SetPoint(btn, "TOPLEFT", anchorTo, "BOTTOMLEFT", xOffset, yOffset)
    btn.text = btn.label -- old call sites (e.g. the red Reset ALL Data override) use btn.text
    return btn
end

-- Small, unobtrusive "Defaults" button anchored to a panel's own top-right
-- corner - the first instance of what's meant to become a standard on
-- every settings panel (2026-08-09). Shows a confirm popup (by name, so
-- each panel supplies its own StaticPopupDialogs entry with the exact
-- reset behavior for that panel) rather than resetting instantly, same
-- caution as the existing "Reset All" button.
-- Built on Brand.MakeButton (the confirmed standard button, not a
-- one-off) - it should never have been hand-rolled with a separate
-- border implementation in the first place.
local function CreateDefaultsButton(parentPanel, popupName)
    local btn = Brand.MakeButton(parentPanel, "Defaults", 76, 20, function()
        StaticPopup_Show(popupName)
    end)
    PixelUtil.SetPoint(btn, "TOPRIGHT", parentPanel, "TOPRIGHT", -12, -16)

    -- Brand.MakeButton already wires its own OnEnter/OnLeave hover-brighten;
    -- re-set here to ALSO keep that AND add the tooltip, same pattern as
    -- the Gather button's OnEnter/OnLeave override.
    btn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Reset this panel's settings to their defaults.")
        GameTooltip:Show()
    end)
    btn:HookScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    return btn
end

-- Font sizes, same two tiers used across every panel in this file: dim
-- description text and brighter label text.
local PANEL_DESC_FONT_SIZE = 13
local PANEL_LABEL_FONT_SIZE = 14
local RIGHT_MARGIN = 16
local DESC_GRAY = 0.62

--------------------------------------------------------------------------------
-- Shared page-building helpers - the family settings layout (matches Xal's
-- Warchest's SettingsPanel.lua, the current reference): a section header,
-- then a hand-drawn checkbox with a short label, then a dim description,
-- with a divider between groups. Each helper returns the last element it
-- built so the next one can anchor to it.
--------------------------------------------------------------------------------
local function PageTitle(panel, text)
    local fs = Brand.FS(panel, text, Brand.TITLE_FONT_PATH, 22, nil,
        Brand.HEADER_COLOR[1], Brand.HEADER_COLOR[2], Brand.HEADER_COLOR[3])
    fs:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
    fs:SetJustifyH("LEFT")
    return fs
end

local function AddNote(panel, anchorTo, yGap, text)
    local fs = Brand.FS(panel, text, Brand.BODY_FONT_PATH, PANEL_DESC_FONT_SIZE, nil,
        DESC_GRAY, DESC_GRAY, DESC_GRAY)
    fs:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, yGap)
    fs:SetPoint("RIGHT", panel, "RIGHT", -RIGHT_MARGIN, 0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    return fs
end

local function AddSection(panel, anchorTo, text, yGap)
    local fs = Brand.FS(panel, text, Brand.TITLE_FONT_PATH, 15, nil,
        Brand.HEADER_COLOR[1], Brand.HEADER_COLOR[2], Brand.HEADER_COLOR[3])
    fs:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, yGap or -14)
    fs:SetJustifyH("LEFT")
    return fs
end

local function AddDivider(panel, anchorTo, yGap)
    local div = Brand.DrawDivider(panel, 0, 0, 1)
    div:ClearAllPoints()
    div:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, yGap or -14)
    div:SetPoint("RIGHT", panel, "RIGHT", -RIGHT_MARGIN, 0)
    return div
end

-- A checkbox with a short label beside it and a dim description under it.
-- onToggle runs with the NEW state already applied (self:GetChecked()).
-- Returns the description (anchor for whatever comes next) and the checkbox.
local function AddToggle(panel, anchorTo, yGap, label, description, onToggle)
    local cb = Brand.MakeCheckbox(panel, 20)
    cb:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, yGap)
    cb.OnToggle = onToggle

    local text = Brand.FS(panel, label, Brand.BODY_FONT_PATH, PANEL_LABEL_FONT_SIZE, nil,
        Brand.HEADER_COLOR[1], Brand.HEADER_COLOR[2], Brand.HEADER_COLOR[3])
    text:SetPoint("LEFT", cb, "RIGHT", 8, 0)
    text:SetPoint("RIGHT", panel, "RIGHT", -RIGHT_MARGIN, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(true)

    local desc = AddNote(panel, cb, -4, description)
    return desc, cb
end

-- A label above a native slider (Blizzard's OptionsSliderTemplate is the one
-- widget still used native). formatFn turns the snapped value into the text
-- shown above the track. slider:Sync(value) sets the value AND the text, for
-- the panel's Refresh function. Needs a real global frame name - the
-- template's Low/High/Text sub-regions are only reachable by name.
local function AddSlider(panel, anchorTo, yGap, name, label, min, max, step, formatFn, onChange)
    local lbl = Brand.FS(panel, label, Brand.BODY_FONT_PATH, PANEL_LABEL_FONT_SIZE, nil,
        Brand.HEADER_COLOR[1], Brand.HEADER_COLOR[2], Brand.HEADER_COLOR[3])
    lbl:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, yGap)
    lbl:SetJustifyH("LEFT")

    local slider = CreateFrame("Slider", name, panel, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 4, -22)
    slider:SetWidth(220)
    slider:SetMinMaxValues(min, max)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)

    _G[name .. "Low"]:SetText("")
    _G[name .. "High"]:SetText("")
    local valueText = _G[name .. "Text"]
    valueText:SetFont(Brand.BODY_FONT_PATH, PANEL_LABEL_FONT_SIZE, "")
    -- Blizzard's template hardcodes this text gold - doesn't read Brand.*.
    valueText:SetTextColor(Brand.HEADER_COLOR[1], Brand.HEADER_COLOR[2], Brand.HEADER_COLOR[3])

    slider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value / step + 0.5) * step
        valueText:SetText(formatFn(value))
        onChange(value)
    end)

    function slider:Sync(value)
        self:SetValue(value)
        valueText:SetText(formatFn(value))
    end

    return slider, lbl
end

-- A grid of pick-one buttons (marker style, arrow style). onPick(key) runs on
-- click and every button's selected look is updated to match. Returns the
-- buttons by key and a spacer frame to anchor the next element to.
local function AddPickerGrid(panel, anchorTo, yGap, keys, labels, cols, btnW, btnH, onPick)
    local gapX, gapY = 8, 6
    local rows = math.ceil(#keys / cols)
    local grid = CreateFrame("Frame", nil, panel)
    grid:SetSize(1, rows * (btnH + gapY))
    grid:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, yGap)

    local buttons = {}
    for i, key in ipairs(keys) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local btn = Brand.MakeButton(grid, labels[key], btnW, btnH, function()
            onPick(key)
            for otherKey, otherBtn in pairs(buttons) do
                otherBtn:SetSelected(otherKey == key)
            end
        end)
        PixelUtil.SetPoint(btn, "TOPLEFT", grid, "TOPLEFT", col * (btnW + gapX), -row * (btnH + gapY))
        buttons[key] = btn
    end
    return buttons, grid
end

--------------------------------------------------------------------------------
-- General (root) panel: Lumberjacking, minimap button, auto-advance distance,
-- keybinds, Gather Tally window
--------------------------------------------------------------------------------
local function BuildRootPanel()
    rootPanel = CreateFrame("Frame")
    rootPanel.name = "Xal's Xpedited Routes"

    local logo = rootPanel:CreateTexture(nil, "ARTWORK")
    logo:SetTexture("Interface\\AddOns\\XalsXpeditedRoutes\\Textures\\AddonIcon")
    logo:SetSize(48, 48)
    logo:SetPoint("TOPLEFT", 16, -14)

    local title = Brand.FS(rootPanel, "Xal's Xpedited Routes", Brand.TITLE_FONT_PATH, 22, nil,
        Brand.HEADER_COLOR[1], Brand.HEADER_COLOR[2], Brand.HEADER_COLOR[3])
    title:SetPoint("LEFT", logo, "RIGHT", 10, 0)
    title:SetJustifyH("LEFT")

    local credit = AddNote(rootPanel, logo, -10,
        "See the sub-sections in the list on the left for Map Markers and Database.")
    local professionNote = AddNote(rootPanel, credit, -10,
        "Markers and routes automatically skip node types this character doesn't have the profession to gather - e.g. a pure-Herbalism character won't see Mining nodes another character on your account recorded.")

    local div1 = AddDivider(rootPanel, professionNote, -14)

    -- Lumberjacking gets its own on/off toggle, unlike Mining/Herbalism -
    -- those come from actively choosing to level a profession, while
    -- Lumberjacking comes from Player Housing content, so a character could
    -- have the ability without ever wanting to gather wood on purpose.
    -- Defaults on. Confirmed 2026-08-17.
    local lumberHeader = AddSection(rootPanel, div1, "Lumberjacking")
    local lumberDesc, lumberCheck = AddToggle(rootPanel, lumberHeader, -10,
        "Enable Lumberjacking gathering",
        "Retail only. Turn this off if you'd rather not see lumber nodes, lumber map pins, or the lumber icon on the floating button.",
        function(self)
            XalsXRDB.lumberEnabled = self:GetChecked() and true or false
            if addonTable.Markers.UpdatePins then addonTable.Markers:UpdatePins() end
            if addonTable.QuickButton.Refresh then addonTable.QuickButton:Refresh() end
        end)
    rootPanel.lumberCheck = lumberCheck

    local div2 = AddDivider(rootPanel, lumberDesc, -14)

    local minimapHeader = AddSection(rootPanel, div2, "Minimap button")
    local minimapDesc, minimapCheck = AddToggle(rootPanel, minimapHeader, -10,
        "Show the minimap button",
        "Left-click opens these settings, right-click opens the Gather Tally.",
        function(self)
            if addonTable.MinimapButton and addonTable.MinimapButton.SetShown then
                addonTable.MinimapButton:SetShown(self:GetChecked() and true or false)
            end
        end)
    rootPanel.minimapCheck = minimapCheck

    local div3 = AddDivider(rootPanel, minimapDesc, -14)

    local advanceHeader = AddSection(rootPanel, div3, "Auto-advance")
    local slider = AddSlider(rootPanel, advanceHeader, -10, "XalsXRAdvanceSlider",
        "Auto-advance distance", 10, 150, 5,
        function(v) return v .. " yd" end,
        function(v) XalsXRDB.autoAdvanceDistance = v end)
    rootPanel.slider = slider
    local sliderHelp = AddNote(rootPanel, slider, -16,
        "How close you need to be to a node before the compass automatically advances to the next one.")

    local div4 = AddDivider(rootPanel, sliderHelp, -14)

    local keybindHeader = AddSection(rootPanel, div4, "Keybinds")
    local keybindHelp = AddNote(rootPanel, keybindHeader, -10,
        "Set these in the game's own Options -> Key Bindings menu, under the \"Xal's Xpedited Routes\" section: Start/Update Route, Stop Route, and Skip Current Node. Not bound to anything by default.")

    local div5 = AddDivider(rootPanel, keybindHelp, -14)

    local haulHeader = AddSection(rootPanel, div5, "Gather Tally")
    local _, haulCheck = AddToggle(rootPanel, haulHeader, -10,
        "Show the live Gather Tally window during a route",
        "A small movable window that tallies what you gather. It stays open after a route ends so you can read it - close it with its X. Open it anytime with the Gather button or /xxr haul. More options under the Gather Tally section.",
        function(self)
            XalsXRDB.showHaulSummary = self:GetChecked() and true or false
            if addonTable.RunTracker and addonTable.RunTracker.OnSettingChanged then
                addonTable.RunTracker:OnSettingChanged()
            end
        end)
    rootPanel.haulCheck = haulCheck

    local RefreshRootPanel = function()
        haulCheck:SetChecked(not (XalsXRDB and XalsXRDB.showHaulSummary == false))
        minimapCheck:SetChecked(not (XalsXRDB and XalsXRDB.minimap and XalsXRDB.minimap.hide == true))
        lumberCheck:SetChecked(not (XalsXRDB and XalsXRDB.lumberEnabled == false))
        slider:Sync((XalsXRDB and XalsXRDB.autoAdvanceDistance) or 50)
    end
    rootPanel:SetScript("OnShow", RefreshRootPanel)
    rootPanel.Refresh = RefreshRootPanel

    return rootPanel
end

--------------------------------------------------------------------------------
-- Floating Button panel: show/hide, scale, reset position, and the first
-- test of the "Defaults" button pattern (2026-08-09) - resets just this
-- panel's own settings, not the whole addon.
--------------------------------------------------------------------------------
local function BuildFloatingButtonPanel()
    floatingPanel = CreateFrame("Frame")
    floatingPanel.name = "Floating Button"

    local title = PageTitle(floatingPanel, "Floating Button")
    local intro = AddNote(floatingPanel, title, -10,
        "The movable button near your character that shows your gathering professions, the Gather button, and (if enabled) the dungeon-waypoint shortcut.")

    CreateDefaultsButton(floatingPanel, "XALXR_RESET_FLOATING_DEFAULTS")

    local div1 = AddDivider(floatingPanel, intro, -14)

    local helperHeader = AddSection(floatingPanel, div1, "Floating helper")
    local helperDesc, helperButtonCheck = AddToggle(floatingPanel, helperHeader, -10,
        "Show the floating helper button",
        "Click it to start or stop a route, drag it anywhere to move it.",
        function(self)
            if self:GetChecked() then
                QuickButton:Show()
            else
                QuickButton:Hide()
            end
        end)
    floatingPanel.helperButtonCheck = helperButtonCheck

    local resetButtonPosBtn = CreateButton(floatingPanel, helperDesc, 0, -10, "Reset Button Position", 200, function()
        QuickButton:ResetPosition()
    end)

    local div2 = AddDivider(floatingPanel, resetButtonPosBtn, -14)

    local sizeHeader = AddSection(floatingPanel, div2, "Size")
    local scaleSlider = AddSlider(floatingPanel, sizeHeader, -10, "XalsXRHelperScaleSlider",
        "Scale", 50, 150, 5,
        function(v) return v .. "%" end,
        function(v)
            XalsXRDB.helperButtonScale = v / 100
            if QuickButton.ApplyScale then QuickButton:ApplyScale() end
        end)
    floatingPanel.scaleSlider = scaleSlider
    local scaleHelp = AddNote(floatingPanel, scaleSlider, -16,
        "Resize the whole floating button. 100% is the default size.")

    local div3 = AddDivider(floatingPanel, scaleHelp, -14)

    -- Off by default (explicit request 2026-08-16) - the button stays fully
    -- visible at all times unless this is turned on.
    local fadeHeader = AddSection(floatingPanel, div3, "Fade when idle")
    local _, fadeCheck = AddToggle(floatingPanel, fadeHeader, -10,
        "Fade the button when you're not near it",
        "Off by default. The button stays fully visible unless this is on.",
        function(self)
            XalsXRDB.helperButtonFadeWhenIdle = self:GetChecked() and true or false
            if QuickButton.ApplyFadeSetting then QuickButton:ApplyFadeSetting() end
        end)
    floatingPanel.fadeCheck = fadeCheck

    local RefreshFloatingPanel = function()
        helperButtonCheck:SetChecked(not (XalsXRDB and XalsXRDB.showHelperButton == false))
        scaleSlider:Sync(math.floor(((XalsXRDB and XalsXRDB.helperButtonScale) or 1) * 100 + 0.5))
        fadeCheck:SetChecked(XalsXRDB and XalsXRDB.helperButtonFadeWhenIdle == true)
    end
    floatingPanel:SetScript("OnShow", RefreshFloatingPanel)
    floatingPanel.Refresh = RefreshFloatingPanel

    return floatingPanel
end

--------------------------------------------------------------------------------
-- Waypoint panel: arrow style, progress coloring, uniform scale
--------------------------------------------------------------------------------
local function BuildWaypointPanel()
    waypointPanel = CreateFrame("Frame")
    waypointPanel.name = "Waypoint"

    local title = PageTitle(waypointPanel, "Waypoint")
    local intro = AddNote(waypointPanel, title, -10,
        "The floating directional arrow that points at your next node.")

    local div1 = AddDivider(waypointPanel, intro, -14)

    local arrowHeader = AddSection(waypointPanel, div1, "Arrow style")
    local arrowStyleButtons, arrowGrid = AddPickerGrid(waypointPanel, arrowHeader, -10,
        Beacon.ARROW_STYLES, Beacon.ARROW_STYLE_LABELS, 2, 170, 24,
        function(key)
            XalsXRDB.compassArrowStyle = key
            Beacon:ApplyArrowStyle()
        end)

    local div2 = AddDivider(waypointPanel, arrowGrid, -14)

    local progressHeader = AddSection(waypointPanel, div2, "Progress color")
    local progressDesc, progressColorCheck = AddToggle(waypointPanel, progressHeader, -10,
        "Color the arrow by progress",
        "Green while you're closing in, red when you're moving away. Works best with plain/light-colored arrow art - tinting already-colorful art can look muddy.",
        function(self)
            XalsXRDB.arrowProgressColor = self:GetChecked() and true or false
        end)
    waypointPanel.progressColorCheck = progressColorCheck

    local div3 = AddDivider(waypointPanel, progressDesc, -14)

    -- Uniform scale only - no separate width/height. Non-uniform scaling would
    -- distort the art (stretched, not just resized) and adds a real class of
    -- bugs (aspect ratio drift, inconsistent hitboxes) for very little benefit
    -- over just picking a bigger or smaller arrow overall.
    local sizeHeader = AddSection(waypointPanel, div3, "Arrow size")
    local scaleSlider = AddSlider(waypointPanel, sizeHeader, -10, "XalsXRArrowScaleSlider",
        "Arrow scale", 50, 150, 5,
        function(v) return v .. "%" end,
        function(v)
            XalsXRDB.arrowScale = v / 100
            Beacon:ApplyArrowStyle()
        end)
    waypointPanel.scaleSlider = scaleSlider
    local scaleHelp = AddNote(waypointPanel, scaleSlider, -16,
        "Resizes the arrow uniformly - same shape, just bigger or smaller.")

    local textScaleSlider = AddSlider(waypointPanel, scaleHelp, -16, "XalsXRArrowTextScaleSlider",
        "Text size", 100, 250, 10,
        function(v) return v .. "%" end,
        function(v)
            XalsXRDB.arrowTextScale = v / 100
            Beacon:ApplyTextScale()
        end)
    waypointPanel.textScaleSlider = textScaleSlider
    local textScaleHelp = AddNote(waypointPanel, textScaleSlider, -16,
        "Enlarges the distance and node-name text under the arrow - handy if the default is hard to read.")

    local div4 = AddDivider(waypointPanel, textScaleHelp, -14)

    local trailHeader = AddSection(waypointPanel, div4, "Minimap trail line")
    local _, trailLineCheck = AddToggle(waypointPanel, trailHeader, -10,
        "Show a trail line to your next stop",
        "A thin line on your minimap that points straight from you to your next stop, on top of the usual arrow.",
        function(self)
            XalsXRDB.showTrailLine = self:GetChecked() and true or false
        end)
    waypointPanel.trailLineCheck = trailLineCheck

    local RefreshWaypointPanel = function()
        local currentArrowStyle = (XalsXRDB and XalsXRDB.compassArrowStyle) or "custom4"
        for styleKey, styleBtn in pairs(arrowStyleButtons) do
            styleBtn:SetSelected(styleKey == currentArrowStyle)
        end
        progressColorCheck:SetChecked(not (XalsXRDB and XalsXRDB.arrowProgressColor == false))
        scaleSlider:Sync(math.floor(((XalsXRDB and XalsXRDB.arrowScale) or 1) * 100 + 0.5))
        textScaleSlider:Sync(math.floor(((XalsXRDB and XalsXRDB.arrowTextScale) or 1) * 100 + 0.5))
        trailLineCheck:SetChecked(not (XalsXRDB and XalsXRDB.showTrailLine == false))
    end
    waypointPanel:SetScript("OnShow", RefreshWaypointPanel)
    waypointPanel.Refresh = RefreshWaypointPanel

    return waypointPanel
end

--------------------------------------------------------------------------------
-- Map Markers panel: marker style picker, size, opacity, proximity hide
--------------------------------------------------------------------------------
local function BuildMarkersPanel()
    markersPanel = CreateFrame("Frame")
    markersPanel.name = "Map Markers"

    local title = PageTitle(markersPanel, "Map Markers")
    local intro = AddNote(markersPanel, title, -10,
        "How gathering nodes are drawn on the minimap and world map. Green = Herbalism, red = Mining. Your active route target gets a small dot at its center.")

    local div1 = AddDivider(markersPanel, intro, -14)

    local styleHeader = AddSection(markersPanel, div1, "Marker style")
    local styleButtons, styleGrid = AddPickerGrid(markersPanel, styleHeader, -10,
        Markers.PIN_STYLES, Markers.PIN_STYLE_LABELS, 2, 165, 22,
        function(key)
            XalsXRDB.pinStyle = key
            Markers:UpdatePins()
        end)
    pinStyleButtons = styleButtons

    local div2 = AddDivider(markersPanel, styleGrid, -14)

    local appearanceHeader = AddSection(markersPanel, div2, "Appearance")
    local pinSizeSlider = AddSlider(markersPanel, appearanceHeader, -10, "XalsXRPinSizeSlider",
        "Marker size", 8, 28, 2,
        function(v) return v .. "px" end,
        function(v)
            XalsXRDB.pinSize = v
            Markers:UpdatePins()
        end)
    markersPanel.pinSizeSlider = pinSizeSlider
    local pinSizeHelp = AddNote(markersPanel, pinSizeSlider, -16,
        "Size of a normal marker. The active route target is always drawn about 40% larger than this.")

    local pinAlphaSlider = AddSlider(markersPanel, pinSizeHelp, -16, "XalsXRPinAlphaSlider",
        "Marker opacity", 30, 100, 5,
        function(v) return v .. "%" end,
        function(v)
            XalsXRDB.pinAlpha = v / 100
            Markers:UpdatePins()
        end)
    markersPanel.pinAlphaSlider = pinAlphaSlider
    local pinAlphaHelp = AddNote(markersPanel, pinAlphaSlider, -16,
        "Overall transparency of every marker, applied globally.")

    local glowDesc, glowCheck = AddToggle(markersPanel, pinAlphaHelp, -16,
        "Show a colored glow behind markers",
        "A soft glow behind each marker (green for Herbalism, red for Mining) so it stands out against busy terrain.",
        function(self)
            XalsXRDB.showGlow = self:GetChecked() and true or false
            Markers:UpdatePins()
        end)
    markersPanel.glowCheck = glowCheck

    local div3 = AddDivider(markersPanel, glowDesc, -14)

    -- Proximity hide - always on, distance is the only adjustable part
    local proximityHeader = AddSection(markersPanel, div3, "Hide markers when close")
    local proximitySlider = AddSlider(markersPanel, proximityHeader, -10, "XalsXRProximitySlider",
        "Hide distance", 20, 500, 10,
        function(v) return v .. " yd" end,
        function(v) XalsXRDB.proximityDistanceYards = v end)
    markersPanel.proximitySlider = proximitySlider
    local proximityHelp = AddNote(markersPanel, proximitySlider, -16,
        "Once you're this close to a node, its marker disappears entirely - the actual node model in the world is what matters at that range. Always on. Applies to the minimap only.")

    local div4 = AddDivider(markersPanel, proximityHelp, -14)

    -- Node grouping - nearby nodes become one route stop instead of a separate
    -- stop for each one. On by default; only the distance is adjustable.
    local groupingHeader = AddSection(markersPanel, div4, "Node grouping")
    local groupingSlider = AddSlider(markersPanel, groupingHeader, -10, "XalsXRGroupingSlider",
        "Grouping distance", 50, 500, 10,
        function(v) return v .. " yd" end,
        function(v) XalsXRDB.groupingDistanceYards = v end)
    markersPanel.groupingSlider = groupingSlider
    AddNote(markersPanel, groupingSlider, -16,
        "Nearby nodes within this distance are treated as one stop on your route instead of a separate stop for each one, so routes flow instead of zig-zagging through a dense patch. Keep this a bit above your Hide Distance above.")

    local RefreshMarkersPanel = function()
        local currentStyle = (XalsXRDB and XalsXRDB.pinStyle) or "hollowx"
        for styleKey, styleBtn in pairs(pinStyleButtons) do
            styleBtn:SetSelected(styleKey == currentStyle)
        end
        pinSizeSlider:Sync((XalsXRDB and XalsXRDB.pinSize) or 14)
        pinAlphaSlider:Sync(math.floor(((XalsXRDB and XalsXRDB.pinAlpha) or 1) * 100 + 0.5))
        glowCheck:SetChecked(not (XalsXRDB and XalsXRDB.showGlow == false))
        proximitySlider:Sync((XalsXRDB and XalsXRDB.proximityDistanceYards) or 200)
        groupingSlider:Sync((XalsXRDB and XalsXRDB.groupingDistanceYards) or 240)
    end
    markersPanel:SetScript("OnShow", RefreshMarkersPanel)
    markersPanel.Refresh = RefreshMarkersPanel

    return markersPanel
end

--------------------------------------------------------------------------------
-- Database panel: stats, cleanup/reset
--------------------------------------------------------------------------------
local function BuildDataPanel()
    dataPanel = CreateFrame("Frame")
    dataPanel.name = "Database"

    local title = PageTitle(dataPanel, "Database")

    statsText = Brand.FS(dataPanel, GetStatsString(), Brand.BODY_FONT_PATH, PANEL_LABEL_FONT_SIZE, nil,
        0.85, 0.85, 0.85)
    statsText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    statsText:SetJustifyH("LEFT")

    local div1 = AddDivider(dataPanel, statsText, -14)

    local dupHeader = AddSection(dataPanel, div1, "Duplicates")
    local dupSlider = AddSlider(dataPanel, dupHeader, -10, "XalsXRDupSlider",
        "Duplicate detection distance", 5, 50, 5,
        function(v) return v .. " yd" end,
        function(v) XalsXRDB.duplicateDistanceYards = v end)
    dataPanel.dupSlider = dupSlider
    local dupHelp = AddNote(dataPanel, dupSlider, -16,
        "How close two saved nodes need to be to count as the same one. If \"already recorded\" fires with no marker nearby, try lowering this.")

    local div2 = AddDivider(dataPanel, dupHelp, -14)

    local freshnessHeader = AddSection(dataPanel, div2, "Node freshness")
    local freshnessSlider = AddSlider(dataPanel, freshnessHeader, -10, "XalsXRFreshnessSlider",
        "Freshness window", 0, 60, 5,
        function(v) return v == 0 and "Off" or (v .. " min") end,
        function(v) XalsXRDB.freshnessMinutes = v end)
    dataPanel.freshnessSlider = freshnessSlider
    local freshnessHelp = AddNote(dataPanel, freshnessSlider, -16,
        "Skips nodes you gathered more recently than this when building a route, since they probably haven't respawned yet. Off routes to every saved node regardless of when it was last picked.")

    local div3 = AddDivider(dataPanel, freshnessHelp, -14)

    local cleanupHeader = AddSection(dataPanel, div3, "Cleanup")
    local cleanupBtn = CreateButton(dataPanel, cleanupHeader, 0, -10, "Cleanup Duplicates", 170, function()
        local removed = NodeLogger.RemoveDuplicates()
        print("|cff00ccffXal's XR:|r Cleanup complete. Removed |cffff9900" .. removed .. "|r duplicates.")
        Markers:UpdatePins()
        RefreshStats()
    end)
    -- Stacked vertically (CreateButton's own default: new button's TOP
    -- anchors to the given anchor's BOTTOM), not side by side. Confirmed
    -- 2026-08-09.
    CreateButton(dataPanel, cleanupBtn, 0, -8, "Reset Current Zone", 170, function()
        local currentMapID = C_Map.GetBestMapForUnit("player")
        if currentMapID and XalsXRDB[currentMapID] then
            XalsXRDB[currentMapID] = nil
            print("|cff00ccffXal's XR:|r Records for the current map have been deleted.")
            PathPlanner:CancelPath()
        else
            print("|cff00ccffXal's XR:|r There are no records for this map.")
        end
        Markers:UpdatePins()
        RefreshStats()
    end)

    -- Deliberately far from the other buttons, pinned to the panel's own
    -- bottom-right corner - the mirror of the close button's top-right
    -- position - so a destructive action never sits within easy misclick
    -- range of the harmless ones above it. Confirmed 2026-08-09.
    local resetAllBtn = CreateButton(dataPanel, cleanupBtn, 0, -34, "Reset ALL Data", 170, function()
        StaticPopup_Show("XALMORASXR_RESET_ALL")
    end)
    resetAllBtn:ClearAllPoints()
    resetAllBtn:SetPoint("BOTTOMRIGHT", dataPanel, "BOTTOMRIGHT", -16, 16)
    -- Intentionally styled as a warning - this one's destructive
    resetAllBtn:SetBorderColor(0.75, 0.2, 0.2, 1)
    resetAllBtn.text:SetTextColor(1, 0.55, 0.5)

    local RefreshDataPanel = function()
        RefreshStats()
        dupSlider:Sync((XalsXRDB and XalsXRDB.duplicateDistanceYards) or 15)
        freshnessSlider:Sync((XalsXRDB and XalsXRDB.freshnessMinutes) or Helpers.DEFAULT_FRESHNESS_MINUTES)
    end
    dataPanel:SetScript("OnShow", RefreshDataPanel)
    dataPanel.Refresh = RefreshDataPanel

    return dataPanel
end

--------------------------------------------------------------------------------
-- Integrations panel: any optional third-party addon this one can hand off to.
-- Home for TomTom now; anywhere future optional addon interop settings belong.
--------------------------------------------------------------------------------
local function BuildIntegrationsPanel()
    integrationsPanel = CreateFrame("Frame")
    integrationsPanel.name = "Integrations"

    local title = PageTitle(integrationsPanel, "Integrations")
    local intro = AddNote(integrationsPanel, title, -10,
        "Optional hand-offs to other addons, if you have them installed. Nothing here is required for this addon's own features to work.")

    local div1 = AddDivider(integrationsPanel, intro, -14)

    local tomtomHeader = AddSection(integrationsPanel, div1, "TomTom")
    local _, tomtomCheck = AddToggle(integrationsPanel, tomtomHeader, -10,
        "Sync TomTom's arrow to your route",
        "Off by default. Does nothing if TomTom isn't installed. When on, keeps TomTom's own arrow pointed at whatever stop this addon's route currently considers next.",
        function(self)
            XalsXRDB.tomtomSyncEnabled = self:GetChecked() and true or false
            if XalsXRDB.tomtomSyncEnabled then
                if addonTable.TomTomBridge.ShowIntegrationTip then
                    addonTable.TomTomBridge:ShowIntegrationTip()
                end
            elseif addonTable.TomTomBridge.ClearWaypoints then
                addonTable.TomTomBridge:ClearWaypoints()
            end
        end)
    integrationsPanel.tomtomCheck = tomtomCheck

    local RefreshIntegrationsPanel = function()
        tomtomCheck:SetChecked(XalsXRDB and XalsXRDB.tomtomSyncEnabled == true)
    end
    integrationsPanel:SetScript("OnShow", RefreshIntegrationsPanel)
    integrationsPanel.Refresh = RefreshIntegrationsPanel

    return integrationsPanel
end

--------------------------------------------------------------------------------
-- Gather Tally panel: the two timers and the dungeon-waypoint button.
--------------------------------------------------------------------------------
local function BuildGatherTallyPanel()
    gatherPanel = CreateFrame("Frame")
    gatherPanel.name = "Gather Tally"

    local title = PageTitle(gatherPanel, "Gather Tally")
    local intro = AddNote(gatherPanel, title, -10,
        "The live window that tallies what you gather. Open it with the Gather button on the floating helper, or /xxr haul.")

    local div1 = AddDivider(gatherPanel, intro, -14)

    local timerHeader = AddSection(gatherPanel, div1, "Timers")
    local gatherTimerDesc, gatherTimerCheck = AddToggle(gatherPanel, timerHeader, -10,
        "Gather timer",
        "Times the sessions you open with the Gather button. Off by default.",
        function(self)
            XalsXRDB.haulGatherTimer = self:GetChecked() and true or false
            if addonTable.RunTracker and addonTable.RunTracker.Render then addonTable.RunTracker:Render() end
        end)
    gatherPanel.gatherTimerCheck = gatherTimerCheck

    local routeTimerDesc, routeTimerCheck = AddToggle(gatherPanel, gatherTimerDesc, -14,
        "Route timer",
        "Times how long a route has run. Off by default.",
        function(self)
            XalsXRDB.haulRouteTimer = self:GetChecked() and true or false
            if addonTable.RunTracker and addonTable.RunTracker.Render then addonTable.RunTracker:Render() end
        end)
    gatherPanel.routeTimerCheck = routeTimerCheck

    local div2 = AddDivider(gatherPanel, routeTimerDesc, -14)

    local dungeonHeader = AddSection(gatherPanel, div2, "Dungeon Nav (Xperimental)")
    -- The old "put it on the left" side toggle was removed 2026-08-09 - the
    -- dungeon button no longer sits beside the Gather button at all, it's
    -- its own independent draggable piece now (2026-09-01), so
    -- dungeonButtonSide stopped doing anything visible.
    local dungeonDesc, dungeonEnableCheck = AddToggle(gatherPanel, dungeonHeader, -10,
        "Show a dungeon-waypoint button",
        "Retail only. A small, separately draggable map icon - not attached to the Gather button. Click it to pick a Season 2 dungeon and drop a waypoint at its entrance. Also available as /xxr dungeon.",
        function(self)
            XalsXRDB.dungeonButtonEnabled = self:GetChecked() and true or false
            if QuickButton and QuickButton.Refresh then QuickButton:Refresh() end
        end)
    gatherPanel.dungeonEnableCheck = dungeonEnableCheck

    CreateButton(gatherPanel, dungeonDesc, 0, -10, "Reset Dungeon Button Position", 220, function()
        QuickButton:ResetDungeonPosition()
    end)

    local RefreshGatherPanel = function()
        gatherTimerCheck:SetChecked(XalsXRDB and XalsXRDB.haulGatherTimer == true)
        routeTimerCheck:SetChecked(XalsXRDB and XalsXRDB.haulRouteTimer == true)
        dungeonEnableCheck:SetChecked(XalsXRDB and XalsXRDB.dungeonButtonEnabled == true)
    end
    gatherPanel:SetScript("OnShow", RefreshGatherPanel)
    gatherPanel.Refresh = RefreshGatherPanel

    return gatherPanel
end

--------------------------------------------------------------------------------
-- Standalone floating window: the PRIMARY way into settings now (the native
-- Esc -> Options list entry stays too, as a secondary/additional path - same
-- split established for every addon going forward, see project_addon_settings_pattern).
--
-- This REUSES the exact same panel frames built above by reparenting them into
-- this window's content area, rather than rebuilding all their controls a
-- second time. Every widget inside a panel is already positioned relative to
-- that panel's OWN frame, not to wherever the frame sits in the world - so
-- moving the frame doesn't disturb anything inside it, and every field binding
-- and Refresh() function keeps working completely unchanged. When the player
-- later opens the native Esc -> Options entry, Blizzard's Settings system
-- re-parents the panel back into its own canvas automatically the way it
-- always does for any RegisterCanvasLayoutCategory panel, so nothing here
-- needs to undo the reparenting itself.
--------------------------------------------------------------------------------
local standaloneFrame, standaloneContent
local standaloneScroll, standaloneThumb
local standaloneTabs = {}
local standalonePanels

-- The pages use the family section layout (header, toggle, description,
-- divider), which runs longer than a fixed-height window can hold for the
-- biggest pages - so the content area scrolls with the mouse wheel. The
-- scroll child's height is measured from the page's real laid-out content
-- each time a tab opens; if that measurement ever fails it falls back to the
-- visible height (no scrolling), never a blank page.
--
-- The same scroll is used in BOTH places the pages can open - this window and
-- the native Esc -> Options entry (see WrapForNativeScroll below) - so the
-- thumb/measure helpers take the scroll pieces as arguments.
local function ScrollUpdateThumb(scroll, content, thumb)
    if not (scroll and thumb) then return end
    local viewH = scroll:GetHeight()
    local contentH = content:GetHeight()
    if not viewH or viewH <= 0 or contentH <= viewH + 1 then
        thumb:Hide()
        return
    end
    local range = contentH - viewH
    local thumbH = math.max(24, viewH * viewH / contentH)
    local pos = scroll:GetVerticalScroll() / range
    thumb:SetHeight(thumbH)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 0, -(viewH - thumbH) * pos)
    thumb:Show()
end

-- Sizes `content` (the scroll child) to the page's real laid-out height.
local function ScrollMeasure(scroll, content, thumb, panel)
    if not (scroll and panel and panel:IsShown()) then return end
    local viewH = scroll:GetHeight()
    local top = panel:GetTop()
    if not viewH or viewH <= 0 or not top then return end

    local lowest
    local function consider(obj)
        local bottom = obj.GetBottom and obj:GetBottom()
        if bottom and (not lowest or bottom < lowest) then lowest = bottom end
    end
    for _, child in ipairs({ panel:GetChildren() }) do
        if child:IsShown() then consider(child) end
    end
    for _, region in ipairs({ panel:GetRegions() }) do
        if region:IsShown() then consider(region) end
    end
    if not lowest then return end

    content:SetHeight(math.max(viewH, top - lowest + 16))
    ScrollUpdateThumb(scroll, content, thumb)
end

local function UpdateScrollThumb()
    ScrollUpdateThumb(standaloneScroll, standaloneContent, standaloneThumb)
end

local function SizeStandaloneContent(panel)
    ScrollMeasure(standaloneScroll, standaloneContent, standaloneThumb, panel)
end

-- Family-wide standard confirmed 2026-09-20: a standalone window's sidebar
-- tabs use Brand.HEADER_COLOR when selected and a muted blue-gray when not,
-- NOT the shared Brand.MakeButton white/orange scheme every other button in
-- this addon still uses (marker-style pickers, arrow-style pickers, etc.) -
-- scoped to just these sidebar tabs by recoloring the
-- label after Brand.MakeButton builds it, same pattern as Brand.Title()'s
-- override, rather than changing MakeButton itself. HookScript on OnLeave
-- restores the right color after a hover, since MakeButton's own OnLeave
-- would otherwise put it back to its own white/orange.
local SIDEBAR_UNSELECTED_COLOR = { 0.196, 0.196, 0.392 } -- #323264
local function SetSidebarTabSelected(tab, selected)
    tab:SetSelected(selected)
    local color = selected and Brand.HEADER_COLOR or SIDEBAR_UNSELECTED_COLOR
    tab.label:SetTextColor(color[1], color[2], color[3], 1)
    tab.sidebarSelected = selected
end

local function ShowStandaloneTab(index)
    local entry = standalonePanels[index]
    for i, tab in ipairs(standaloneTabs) do
        SetSidebarTabSelected(tab, i == index)
    end
    for i, other in ipairs(standalonePanels) do
        if i ~= index then other.panel:Hide() end
    end
    local panel = entry.panel
    panel:SetParent(standaloneContent)
    panel:ClearAllPoints()
    panel:SetAllPoints(standaloneContent)
    -- Back to the visible height and the top of the page before measuring -
    -- a previous tab's taller content height would otherwise carry over.
    standaloneContent:SetHeight(standaloneScroll:GetHeight() > 0 and standaloneScroll:GetHeight() or 1)
    standaloneScroll:SetVerticalScroll(0)
    panel:Show()
    if panel.Refresh then panel.Refresh() end
    UpdateScrollThumb()
    -- Layout isn't resolved until the next frame, so measure then.
    C_Timer.After(0, function() SizeStandaloneContent(panel) end)
end

local function BuildStandaloneWindow()
    if standaloneFrame then return standaloneFrame end
    if not rootPanel then SettingsPanel:Init() end

    -- Fixed window size; pages taller than the content area scroll (see
    -- SizeStandaloneContent).
    local FW, FH = 640, 820
    local f = CreateFrame("Frame", "XalsXRStandaloneOptions", UIParent, "BackdropTemplate")
    tinsert(UISpecialFrames, "XalsXRStandaloneOptions") -- lets the Escape key close it, like any other UI panel
    f:SetSize(FW, FH)
    -- This window is 640x820 - too large for a small offset from CENTER to
    -- meaningfully separate it from another addon's similarly large window.
    -- Anchors to a screen CORNER instead (only used the first time; once
    -- dragged, its real position is remembered permanently via
    -- XalsXRDB.optionsWindowPoint) - part of a shared corner scheme across
    -- every Xal's addon's big settings window, see the "Default window
    -- position" rule in the shared brand-style memory.
    local savedPoint = XalsXRDB.optionsWindowPoint
    if savedPoint then
        f:SetPoint(savedPoint[1], UIParent, savedPoint[2], savedPoint[3], savedPoint[4])
    else
        f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 40, 40)
    end
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        XalsXRDB.optionsWindowPoint = { point, relPoint, x, y }
    end)
    f:SetClampedToScreen(true)

    -- Solid dark indigo instead of Brand.BG + the swirl background image -
    -- confirmed 2026-09-02 ("we're removing the background image... I
    -- wanted a dark blue bordering on purple"). Scoped to just this window,
    -- not Brand.BG itself.
    local WINDOW_BG = { 0.03, 0.028, 0.06 } -- #08070f
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(WINDOW_BG[1], WINDOW_BG[2], WINDOW_BG[3], 1)

    -- Outer window border, at the family-wide inset (1, flush against the
    -- true outer edge) - color defaults to Brand.DIVIDER_COLOR now (2026-09-20
    -- standard), no override needed.
    Brand.DrawBorder(f, 1)

    -- Centered (not left-justified) and given real room below the border,
    -- per design feedback 2026-08-09. Recolored to Brand.HEADER_COLOR
    -- (2026-09-20 family-wide standard for a window's main title).
    local windowTitle = Brand.Title(f, "Xal's Xpedited Routes", 30, "TOP", f, "TOP", 0, -28)
    windowTitle:SetTextColor(Brand.HEADER_COLOR[1], Brand.HEADER_COLOR[2], Brand.HEADER_COLOR[3])

    -- Text-link style close ("Close" in accent gold), not a boxed button -
    -- confirmed preference 2026-08-16.
    local closeBtn = Brand.MakeCloseButton(f, function() f:Hide() end)
    PixelUtil.SetPoint(closeBtn, "TOPRIGHT", f, "TOPRIGHT", -Brand.SAFE_MARGIN, -Brand.SAFE_MARGIN)

    -- Horizontal divider separating the title from the tabs/content below -
    -- same feedback pass. Pushed down 8px from its original 58 to give the
    -- larger (30pt, up from 20pt) title room to breathe without crowding it.
    -- Uses DrawHeaderDivider (2026-09-20) since this is THE one header
    -- divider directly under the main title - every other divider in this
    -- window stays on Brand.DrawDivider's muted tone.
    Brand.DrawHeaderDivider(f, Brand.SAFE_MARGIN, 66, FW - Brand.SAFE_MARGIN * 2)

    -- Left-side tab list, matching the established sidebar-tabs convention.
    local sidebar = CreateFrame("Frame", nil, f)
    sidebar:SetPoint("TOPLEFT", f, "TOPLEFT", Brand.SAFE_MARGIN, -78)
    sidebar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", Brand.SAFE_MARGIN, Brand.SAFE_MARGIN)
    sidebar:SetWidth(132)

    -- Sidebar/content divider - NOT the header divider, so it stays on the
    -- muted Brand.DIVIDER_COLOR tone (2026-09-20), not orange.
    local vDivider = f:CreateTexture(nil, "ARTWORK")
    vDivider:SetWidth(Brand.LINE_THICKNESS)
    vDivider:SetColorTexture(Brand.DIVIDER_COLOR[1], Brand.DIVIDER_COLOR[2], Brand.DIVIDER_COLOR[3], 1)
    vDivider:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 10, 0)
    vDivider:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMRIGHT", 10, 0)

    -- Scrollable content area (see SizeStandaloneContent) - the scroll frame
    -- fills the space the content frame used to, and the content frame is
    -- its scroll child, fixed to the visible width so every page's RIGHT
    -- margin anchors resolve exactly as they did before.
    local contentViewW = FW - Brand.SAFE_MARGIN - 132 - 10 - Brand.LINE_THICKNESS - 12 - Brand.SAFE_MARGIN
    standaloneScroll = CreateFrame("ScrollFrame", nil, f)
    standaloneScroll:SetPoint("TOPLEFT", vDivider, "TOPRIGHT", 12, 0)
    standaloneScroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -Brand.SAFE_MARGIN, Brand.SAFE_MARGIN)
    standaloneScroll:EnableMouseWheel(true)
    standaloneScroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * 40)))
        UpdateScrollThumb()
    end)

    standaloneContent = CreateFrame("Frame", nil, standaloneScroll)
    standaloneContent:SetSize(contentViewW, FH - 92)
    standaloneScroll:SetScrollChild(standaloneContent)

    -- Thin scroll indicator along the scroll area's right edge, only shown
    -- when the page is actually taller than the window.
    standaloneThumb = f:CreateTexture(nil, "OVERLAY")
    standaloneThumb:SetWidth(3)
    standaloneThumb:SetColorTexture(Brand.HEADER_COLOR[1], Brand.HEADER_COLOR[2], Brand.HEADER_COLOR[3], 0.9)
    standaloneThumb:Hide()

    standalonePanels = {
        { label = "General", panel = rootPanel },
        { label = "Floating", panel = floatingPanel }, -- shorter than "Floating Button" so it doesn't crowd the 116px-wide sidebar tab (the page's own title still says "Floating Button" in full)
        { label = "Waypoint", panel = waypointPanel },
        { label = "Map Markers", panel = markersPanel },
        { label = "Gather Tally", panel = gatherPanel },
        { label = "Database", panel = dataPanel },
        { label = "Integrations", panel = integrationsPanel },
    }

    -- 8px inset on BOTH sides (116-wide tab in a 132-wide sidebar) - the
    -- first version anchored tabs flush to the sidebar's left edge (0
    -- offset) with slack only on the right toward the divider, which read
    -- as lopsided/asymmetric. Fixed 2026-08-09 after seeing it live.
    local TAB_SIDE_PAD = 8
    local anchorTab = nil
    for i, entry in ipairs(standalonePanels) do
        local tab = Brand.MakeButton(sidebar, entry.label, 116, 24, function() ShowStandaloneTab(i) end)
        -- Restores the sidebar-specific color after a hover, since
        -- MakeButton's own OnLeave (already wired via SetScript inside
        -- MakeButton) would otherwise reset the label to white/orange.
        tab:HookScript("OnLeave", function(self)
            local color = self.sidebarSelected and Brand.HEADER_COLOR or SIDEBAR_UNSELECTED_COLOR
            self.label:SetTextColor(color[1], color[2], color[3], 1)
        end)
        tab:ClearAllPoints()
        if anchorTab then
            PixelUtil.SetPoint(tab, "TOPLEFT", anchorTab, "BOTTOMLEFT", 0, -4)
        else
            PixelUtil.SetPoint(tab, "TOPLEFT", sidebar, "TOPLEFT", TAB_SIDE_PAD, 0)
        end
        standaloneTabs[i] = tab
        anchorTab = tab
    end

    -- Bottom-pinned sidebar Discord logo link, family standard confirmed
    -- 2026-09-20 - just the logo, no separate text, distinct from the text
    -- link already on the General page.
    local sidebarDiscord = Brand.MakeDiscordLogoLink(sidebar, 100)
    sidebarDiscord:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMLEFT", TAB_SIDE_PAD, 0)

    f:Hide()
    standaloneFrame = f
    return f
end

-- Opens on the General tab every time, so switching between the two access
-- paths never leaves the player looking at a stale/unrelated tab.
function SettingsPanel:ToggleStandalone()
    local f = BuildStandaloneWindow()
    if f:IsShown() then
        f:Hide()
    else
        ShowStandaloneTab(1)
        f:Show()
    end
end

-- Opens the standalone window straight to the Integrations tab (the TomTom
-- checkbox lives there) - used by WhatsNew's upgrade-notice button so
-- existing players can jump straight to the setting instead of hunting for
-- it themselves.
function SettingsPanel:OpenIntegrations()
    local f = BuildStandaloneWindow()
    for i, entry in ipairs(standalonePanels) do
        if entry.label == "Integrations" then
            ShowStandaloneTab(i)
            break
        end
    end
    f:Show()
end

-- Recolors every checkbox label and slider Low/High/Text on a panel (and its
-- children) to the one accent color - covers every checkbox/slider across
-- every settings panel from ONE call per panel, instead of touching each of
-- the ~25 individual widgets at its own creation site. Confirmed 2026-09-02
-- ("anything that has the gold yellow in it, I want it to turn to our
-- accent"), color updated 2026-09-25. Blizzard's checkbox/slider templates
-- default that text gold; this just overrides it after the fact.
local function RecolorLabelsOrange(panel)
    local o = Brand.HEADER_COLOR
    local function walk(f)
        if not f or not f.GetObjectType then return end
        local otype = f:GetObjectType()
        if otype == "CheckButton" and f.Text then
            f.Text:SetTextColor(o[1], o[2], o[3])
        elseif otype == "Slider" then
            local name = f:GetName()
            if name then
                for _, suffix in ipairs({ "Text", "Low", "High" }) do
                    local fs = _G[name .. suffix]
                    if fs then fs:SetTextColor(o[1], o[2], o[3]) end
                end
            end
        end
        if f.GetChildren then
            for _, child in ipairs({ f:GetChildren() }) do
                walk(child)
            end
        end
    end
    walk(panel)
end

-- Native Esc -> Options entry: Blizzard shows the registered frame in a
-- fixed-size canvas, so a page taller than that would be clipped with no way
-- to reach the rest. Each page is registered through a thin wrapper that holds
-- its own scroll area (mouse wheel + a thumb that only appears when the page
-- overflows - same behavior as the standalone window). The real panel is
-- re-parented into the wrapper's scroll child every time the wrapper is shown,
-- since the standalone window borrows the same panel frames.
local function WrapForNativeScroll(panel)
    local wrapper = CreateFrame("Frame")
    wrapper.name = panel.name
    panel:Hide() -- stays hidden until its wrapper (or the standalone window) shows it

    local scroll = CreateFrame("ScrollFrame", nil, wrapper)
    scroll:SetPoint("TOPLEFT", wrapper, "TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", wrapper, "BOTTOMRIGHT", -8, 0)
    scroll:EnableMouseWheel(true)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)

    local thumb = wrapper:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(3)
    thumb:SetColorTexture(Brand.HEADER_COLOR[1], Brand.HEADER_COLOR[2], Brand.HEADER_COLOR[3], 0.9)
    thumb:Hide()

    scroll:SetScript("OnSizeChanged", function(_, width)
        if width and width > 0 then content:SetWidth(width) end
    end)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * 40)))
        ScrollUpdateThumb(scroll, content, thumb)
    end)

    wrapper:SetScript("OnShow", function()
        panel:SetParent(content)
        panel:ClearAllPoints()
        panel:SetAllPoints(content)
        local viewH = scroll:GetHeight()
        content:SetHeight(viewH and viewH > 0 and viewH or 1)
        scroll:SetVerticalScroll(0)
        panel:Show()
        if panel.Refresh then panel.Refresh() end
        ScrollUpdateThumb(scroll, content, thumb)
        -- Layout isn't resolved until the next frame, so measure then.
        C_Timer.After(0, function() ScrollMeasure(scroll, content, thumb, panel) end)
    end)

    return wrapper
end

function SettingsPanel:Init()
    if rootPanel then return end
    BuildRootPanel()
    BuildFloatingButtonPanel()
    BuildWaypointPanel()
    BuildMarkersPanel()
    BuildGatherTallyPanel()
    BuildDataPanel()
    BuildIntegrationsPanel()

    for _, panel in ipairs({ rootPanel, floatingPanel, waypointPanel, markersPanel, gatherPanel, dataPanel, integrationsPanel }) do
        RecolorLabelsOrange(panel)
    end

    -- Each page registers through a scrolling wrapper (see WrapForNativeScroll).
    local rootWrap = WrapForNativeScroll(rootPanel)
    local floatingWrap = WrapForNativeScroll(floatingPanel)
    local waypointWrap = WrapForNativeScroll(waypointPanel)
    local markersWrap = WrapForNativeScroll(markersPanel)
    local gatherWrap = WrapForNativeScroll(gatherPanel)
    local dataWrap = WrapForNativeScroll(dataPanel)
    local integrationsWrap = WrapForNativeScroll(integrationsPanel)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        -- Modern Settings API (retail 10.0+), with real sub-sections in the category tree
        local rootCategory = Settings.RegisterCanvasLayoutCategory(rootWrap, rootWrap.name)
        rootCategory.ID = rootWrap.name
        Settings.RegisterAddOnCategory(rootCategory)
        SettingsPanel.category = rootCategory

        if Settings.RegisterCanvasLayoutSubcategory then
            Settings.RegisterCanvasLayoutSubcategory(rootCategory, floatingWrap, floatingWrap.name)
            Settings.RegisterCanvasLayoutSubcategory(rootCategory, waypointWrap, waypointWrap.name)
            Settings.RegisterCanvasLayoutSubcategory(rootCategory, markersWrap, markersWrap.name)
            Settings.RegisterCanvasLayoutSubcategory(rootCategory, gatherWrap, gatherWrap.name)
            Settings.RegisterCanvasLayoutSubcategory(rootCategory, dataWrap, dataWrap.name)
            Settings.RegisterCanvasLayoutSubcategory(rootCategory, integrationsWrap, integrationsWrap.name)
        end
    elseif InterfaceOptions_AddCategory then
        -- Legacy fallback for older clients: nest sub-panels under the root by name
        InterfaceOptions_AddCategory(rootWrap)
        floatingWrap.parent = rootWrap.name
        InterfaceOptions_AddCategory(floatingWrap)
        waypointWrap.parent = rootWrap.name
        InterfaceOptions_AddCategory(waypointWrap)
        markersWrap.parent = rootWrap.name
        InterfaceOptions_AddCategory(markersWrap)
        gatherWrap.parent = rootWrap.name
        InterfaceOptions_AddCategory(gatherWrap)
        dataWrap.parent = rootWrap.name
        InterfaceOptions_AddCategory(dataWrap)
        integrationsWrap.parent = rootWrap.name
        InterfaceOptions_AddCategory(integrationsWrap)
    end

    -- Backstop: OnShow does not reliably fire for these panels when switching
    -- between sub-categories inside the modern Settings window (confirmed live -
    -- every slider on every sub-page was showing its bare label with no current
    -- value, every time, with no errors - meaning OnShow just wasn't running,
    -- not that anything inside it was wrong). Polling actual frame visibility
    -- directly sidesteps that entirely, since it doesn't depend on any
    -- particular script event firing at all.
    local panels = { rootPanel, floatingPanel, waypointPanel, markersPanel, gatherPanel, dataPanel, integrationsPanel }
    local wasVisible = {}
    local pollTimer = 0
    local poller = CreateFrame("Frame")
    poller:SetScript("OnUpdate", function(self, elapsed)
        pollTimer = pollTimer + elapsed
        if pollTimer < 0.1 then return end
        pollTimer = 0
        for _, panel in ipairs(panels) do
            local isVisible = panel:IsVisible()
            if isVisible and not wasVisible[panel] and panel.Refresh then
                panel.Refresh()
            end
            wasVisible[panel] = isVisible
        end
    end)
end

function SettingsPanel:Open()
    if not rootPanel then self:Init() end
    if Settings and Settings.OpenToCategory and SettingsPanel.category then
        -- Called twice due to a long-standing Blizzard bug where the first call
        -- sometimes opens the panel to the wrong category.
        Settings.OpenToCategory(SettingsPanel.category:GetID())
        Settings.OpenToCategory(SettingsPanel.category:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(rootPanel)
        InterfaceOptionsFrame_OpenToCategory(rootPanel)
    else
        print("|cff00ccffXal's XR:|r Open Game Menu -> SettingsPanel -> AddOns -> Xal's Xpedited Routes.")
    end
end
