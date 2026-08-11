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
                and mapID ~= "showTrailLine" and mapID ~= "boundaryNodes" and type(nodes) == "table" then
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
                and key ~= "showTrailLine" and key ~= "boundaryNodes" then
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

local function CreateHeader(parentPanel, anchorTo, text, yOffset)
    local header = parentPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, yOffset or -20)
    header:SetText(text)
    return header
end

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
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.18, 0.18, 0.18, 0.75)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Reset this panel's settings to their defaults.")
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.1, 0.1, 0.1, 0.6)
        GameTooltip:Hide()
    end)

    return btn
end

-- Readability font-size bump, confirmed 2026-08-09 as the addon-wide
-- standard after testing on the Map Markers panel alone first - two tiers,
-- dim description text and brighter label/checkbox/slider text, scaled up
-- proportionately from Blizzard's default ~10px template size. Every panel
-- in this file uses these two constants so the whole settings UI reads
-- consistently, not just the one panel it was piloted on.
local PANEL_DESC_FONT_SIZE = 13
local PANEL_LABEL_FONT_SIZE = 14
local function BumpFont(fs, size)
    local font, _, flags = fs:GetFont()
    fs:SetFont(font, size, flags)
end

--------------------------------------------------------------------------------
-- General (root) panel: visibility toggles, helper button, auto-advance distance
--------------------------------------------------------------------------------
local function BuildRootPanel()
    rootPanel = CreateFrame("Frame")
    rootPanel.name = "Xal's Xpedited Routes"

    local logo = rootPanel:CreateTexture(nil, "ARTWORK")
    logo:SetTexture("Interface\\AddOns\\XalsXpeditedRoutes\\Textures\\AddonIcon")
    logo:SetSize(48, 48)
    logo:SetPoint("TOPLEFT", 16, -14)

    local title = rootPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    title:SetPoint("LEFT", logo, "RIGHT", 10, 0)
    title:SetText("Xal's Xpedited Routes")

    local credit = rootPanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    BumpFont(credit, PANEL_DESC_FONT_SIZE)
    credit:SetPoint("TOPLEFT", logo, "BOTTOMLEFT", 0, -10)
    credit:SetText("See the sub-sections in the list on the left for Map Markers and Database.")
    credit:SetPoint("RIGHT", rootPanel, "RIGHT", -16, 0)
    credit:SetJustifyH("LEFT")

    local professionNote = rootPanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    BumpFont(professionNote, PANEL_DESC_FONT_SIZE)
    professionNote:SetPoint("TOPLEFT", credit, "BOTTOMLEFT", -2, -18)
    professionNote:SetPoint("RIGHT", rootPanel, "RIGHT", -16, 0)
    professionNote:SetJustifyH("LEFT")
    professionNote:SetText("Markers and routes automatically skip node types this character doesn't have the profession to gather - e.g. a pure-Herbalism character won't see Mining nodes another character on your account recorded.")

    -- "Show the floating helper button" and its Reset Button Position button
    -- moved out to the dedicated Floating Button panel, 2026-08-09 - along
    -- with the new scale slider and that panel's own Defaults reset.
    local minimapCheck = CreateFrame("CheckButton", nil, rootPanel, "UICheckButtonTemplate")
    minimapCheck:SetPoint("TOPLEFT", professionNote, "BOTTOMLEFT", 2, -10)
    -- The click-behavior explanation was dropped 2026-08-09 - it's redundant
    -- with the minimap button's own in-game tooltip, and just ate space/
    -- forced a wrap here for no reason.
    minimapCheck.Text:SetText("Show the minimap button")
    BumpFont(minimapCheck.Text, PANEL_LABEL_FONT_SIZE)
    minimapCheck.Text:SetWordWrap(true)
    minimapCheck.Text:SetPoint("RIGHT", rootPanel, "RIGHT", -16, 0)
    minimapCheck:SetScript("OnClick", function(self)
        if addonTable.MinimapButton and addonTable.MinimapButton.SetShown then
            addonTable.MinimapButton:SetShown(self:GetChecked() and true or false)
        end
    end)
    rootPanel.minimapCheck = minimapCheck

    local slider = CreateFrame("Slider", "XalsXRAdvanceSlider", rootPanel, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", minimapCheck, "BOTTOMLEFT", 4, -20)
    slider:SetWidth(220)
    slider:SetMinMaxValues(10, 60)
    slider:SetValueStep(5)
    slider:SetObeyStepOnDrag(true)
    _G[slider:GetName() .. "Low"]:SetText("10 yd")
    BumpFont(_G[slider:GetName() .. "Low"], PANEL_LABEL_FONT_SIZE)
    _G[slider:GetName() .. "High"]:SetText("60 yd")
    BumpFont(_G[slider:GetName() .. "High"], PANEL_LABEL_FONT_SIZE)
    _G[slider:GetName() .. "Text"]:SetText("Auto-advance distance")
    BumpFont(_G[slider:GetName() .. "Text"], PANEL_LABEL_FONT_SIZE)
    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        XalsXRDB.autoAdvanceDistance = value
        _G[self:GetName() .. "Text"]:SetText("Auto-advance distance: " .. value .. " yd")
        BumpFont(_G[self:GetName() .. "Text"], PANEL_LABEL_FONT_SIZE)
    end)
    rootPanel.slider = slider

    local sliderHelp = rootPanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    BumpFont(sliderHelp, PANEL_DESC_FONT_SIZE)
    sliderHelp:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", -6, -16)
    sliderHelp:SetPoint("RIGHT", rootPanel, "RIGHT", -16, 0)
    sliderHelp:SetJustifyH("LEFT")
    sliderHelp:SetText("How close you need to be to a node before the compass automatically advances to the next one.")

    local keybindHeader = CreateHeader(rootPanel, sliderHelp, "Keybinds", -22)

    local keybindHelp = rootPanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    BumpFont(keybindHelp, PANEL_DESC_FONT_SIZE)
    keybindHelp:SetPoint("TOPLEFT", keybindHeader, "BOTTOMLEFT", 2, -10)
    keybindHelp:SetPoint("RIGHT", rootPanel, "RIGHT", -16, 0)
    keybindHelp:SetJustifyH("LEFT")
    keybindHelp:SetText("Set these in the game's own Options -> Key Bindings menu, under the \"Xal's Xpedited Routes\" section: Start/Update Route, Stop Route, and Skip Current Node. Not bound to anything by default.")

    local haulHeader = CreateHeader(rootPanel, keybindHelp, "Gather Tally", -22)

    local haulCheck = CreateFrame("CheckButton", nil, rootPanel, "UICheckButtonTemplate")
    haulCheck:SetPoint("TOPLEFT", haulHeader, "BOTTOMLEFT", 2, -8)
    haulCheck.Text:SetText("Show the live Gather Tally window during a route")
    BumpFont(haulCheck.Text, PANEL_LABEL_FONT_SIZE)
    haulCheck.Text:SetWordWrap(true)
    haulCheck.Text:SetPoint("RIGHT", rootPanel, "RIGHT", -16, 0)
    haulCheck:SetScript("OnClick", function(self)
        XalsXRDB.showHaulSummary = self:GetChecked() and true or false
        if addonTable.RunTracker and addonTable.RunTracker.OnSettingChanged then
            addonTable.RunTracker:OnSettingChanged()
        end
    end)
    rootPanel.haulCheck = haulCheck

    local haulHelp = rootPanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    BumpFont(haulHelp, PANEL_DESC_FONT_SIZE)
    haulHelp:SetPoint("TOPLEFT", haulCheck, "BOTTOMLEFT", -2, -16)
    haulHelp:SetPoint("RIGHT", rootPanel, "RIGHT", -16, 0)
    haulHelp:SetJustifyH("LEFT")
    haulHelp:SetText("A small movable window that tallies what you gather. It stays open after a route ends so you can read it - close it with its X. Open it anytime with the Gather button or /xxr haul. More options under the Gather Tally section.")

    local RefreshRootPanel = function()
        haulCheck:SetChecked(not (XalsXRDB and XalsXRDB.showHaulSummary == false))
        minimapCheck:SetChecked(not (XalsXRDB and XalsXRDB.minimap and XalsXRDB.minimap.hide == true))
        local dist = (XalsXRDB and XalsXRDB.autoAdvanceDistance) or 20
        slider:SetValue(dist)
        _G[slider:GetName() .. "Text"]:SetText("Auto-advance distance: " .. dist .. " yd")
        BumpFont(_G[slider:GetName() .. "Text"], PANEL_LABEL_FONT_SIZE)
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

    local title = floatingPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Floating Button")

    local intro = floatingPanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    BumpFont(intro, PANEL_DESC_FONT_SIZE)
    intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    intro:SetPoint("RIGHT", floatingPanel, "RIGHT", -16, 0)
    intro:SetJustifyH("LEFT")
    intro:SetText("The movable button near your character that shows your gathering professions, the Gather button, and (if enabled) the dungeon-waypoint shortcut.")

    local defaultsBtn = CreateDefaultsButton(floatingPanel, "XALXR_RESET_FLOATING_DEFAULTS")

    local helperButtonCheck = CreateFrame("CheckButton", nil, floatingPanel, "UICheckButtonTemplate")
    helperButtonCheck:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 2, -14)
    helperButtonCheck.Text:SetText("Show the floating helper button (click to route/unroute)")
    BumpFont(helperButtonCheck.Text, PANEL_LABEL_FONT_SIZE)
    helperButtonCheck.Text:SetWordWrap(true)
    helperButtonCheck.Text:SetPoint("RIGHT", floatingPanel, "RIGHT", -16, 0)
    helperButtonCheck:SetScript("OnClick", function(self)
        if self:GetChecked() then
            QuickButton:Show()
        else
            QuickButton:Hide()
        end
    end)
    floatingPanel.helperButtonCheck = helperButtonCheck

    local resetButtonPosBtn = CreateButton(floatingPanel, helperButtonCheck, 2, -10, "Reset Button Position", 200, function()
        QuickButton:ResetPosition()
    end)

    local scaleSlider = CreateFrame("Slider", "XalsXRHelperScaleSlider", floatingPanel, "OptionsSliderTemplate")
    scaleSlider:SetPoint("TOPLEFT", resetButtonPosBtn, "BOTTOMLEFT", 4, -24)
    scaleSlider:SetWidth(220)
    scaleSlider:SetMinMaxValues(50, 150)
    scaleSlider:SetValueStep(5)
    scaleSlider:SetObeyStepOnDrag(true)
    _G[scaleSlider:GetName() .. "Low"]:SetText("50%")
    BumpFont(_G[scaleSlider:GetName() .. "Low"], PANEL_LABEL_FONT_SIZE)
    _G[scaleSlider:GetName() .. "High"]:SetText("150%")
    BumpFont(_G[scaleSlider:GetName() .. "High"], PANEL_LABEL_FONT_SIZE)
    _G[scaleSlider:GetName() .. "Text"]:SetText("Scale")
    BumpFont(_G[scaleSlider:GetName() .. "Text"], PANEL_LABEL_FONT_SIZE)
    scaleSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / 5 + 0.5) * 5
        XalsXRDB.helperButtonScale = value / 100
        _G[self:GetName() .. "Text"]:SetText("Scale: " .. value .. "%")
        BumpFont(_G[self:GetName() .. "Text"], PANEL_LABEL_FONT_SIZE)
        if QuickButton.ApplyScale then QuickButton:ApplyScale() end
    end)
    floatingPanel.scaleSlider = scaleSlider

    local scaleHelp = floatingPanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    BumpFont(scaleHelp, PANEL_DESC_FONT_SIZE)
    scaleHelp:SetPoint("TOPLEFT", scaleSlider, "BOTTOMLEFT", -6, -16)
    scaleHelp:SetPoint("RIGHT", floatingPanel, "RIGHT", -16, 0)
    scaleHelp:SetJustifyH("LEFT")
    scaleHelp:SetText("Resize the whole floating button. 100% is the default size.")

    local RefreshFloatingPanel = function()
        helperButtonCheck:SetChecked(not (XalsXRDB and XalsXRDB.showHelperButton == false))
        local scalePct = math.floor(((XalsXRDB and XalsXRDB.helperButtonScale) or 1) * 100 + 0.5)
        scaleSlider:SetValue(scalePct)
        _G[scaleSlider:GetName() .. "Text"]:SetText("Scale: " .. scalePct .. "%")
        BumpFont(_G[scaleSlider:GetName() .. "Text"], PANEL_LABEL_FONT_SIZE)
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

    local title = waypointPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Waypoint")

    local intro = waypointPanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    BumpFont(intro, PANEL_DESC_FONT_SIZE)
    intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    intro:SetPoint("RIGHT", waypointPanel, "RIGHT", -16, 0)
    intro:SetJustifyH("LEFT")
    intro:SetText("The floating directional arrow that points at your next node.")

    local arrowHeader = CreateHeader(waypointPanel, intro, "Arrow Style", -18)

    local arrowStyleButtons = {}
    local arrowBtnWidth = 170
    local arrowBtnHeight = 24
    local arrowCols = 2
    for i, key in ipairs(Beacon.ARROW_STYLES) do
        local col = (i - 1) % arrowCols
        local row = math.floor((i - 1) / arrowCols)
        local btn = CreateButton(waypointPanel, arrowHeader,
            col * (arrowBtnWidth + 8), -10 - row * (arrowBtnHeight + 6),
            Beacon.ARROW_STYLE_LABELS[key], arrowBtnWidth, function()
                XalsXRDB.compassArrowStyle = key
                Beacon:ApplyArrowStyle()
                for styleKey, styleBtn in pairs(arrowStyleButtons) do
                    styleBtn:SetSelected(styleKey == key)
                end
            end)
        arrowStyleButtons[key] = btn
    end
    local arrowRows = math.ceil(#Beacon.ARROW_STYLES / arrowCols)

    local progressColorCheck = CreateFrame("CheckButton", nil, waypointPanel, "UICheckButtonTemplate")
    progressColorCheck:SetPoint("TOPLEFT", arrowHeader, "BOTTOMLEFT", 2, -10 - arrowRows * (arrowBtnHeight + 6) - 6)
    progressColorCheck.Text:SetText("Color the arrow green when closing in, red when moving away")
    BumpFont(progressColorCheck.Text, PANEL_LABEL_FONT_SIZE)
    progressColorCheck.Text:SetWordWrap(true)
    progressColorCheck.Text:SetPoint("RIGHT", waypointPanel, "RIGHT", -16, 0)
    progressColorCheck:SetScript("OnClick", function(self)
        XalsXRDB.arrowProgressColor = self:GetChecked() and true or false
    end)
    waypointPanel.progressColorCheck = progressColorCheck

    local progressColorHelp = waypointPanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    BumpFont(progressColorHelp, PANEL_DESC_FONT_SIZE)
    progressColorHelp:SetPoint("TOPLEFT", progressColorCheck, "BOTTOMLEFT", -2, -16)
    progressColorHelp:SetPoint("RIGHT", waypointPanel, "RIGHT", -16, 0)
    progressColorHelp:SetJustifyH("LEFT")
    progressColorHelp:SetText("Works best with plain/light-colored arrow art - tinting already-colorful art can look muddy.")

    local scaleHeader = CreateHeader(waypointPanel, progressColorHelp, "Scale", -22)

    -- Uniform scale only - no separate width/height. Non-uniform scaling would
    -- distort the art (stretched, not just resized) and adds a real class of
    -- bugs (aspect ratio drift, inconsistent hitboxes) for very little benefit
    -- over just picking a bigger or smaller arrow overall.
    local scaleSlider = CreateFrame("Slider", "XalsXRArrowScaleSlider", waypointPanel, "OptionsSliderTemplate")
    scaleSlider:SetPoint("TOPLEFT", scaleHeader, "BOTTOMLEFT", 6, -20)
    scaleSlider:SetWidth(220)
    scaleSlider:SetMinMaxValues(50, 150)
    scaleSlider:SetValueStep(5)
    scaleSlider:SetObeyStepOnDrag(true)
    _G[scaleSlider:GetName() .. "Low"]:SetText("50%")
    BumpFont(_G[scaleSlider:GetName() .. "Low"], PANEL_LABEL_FONT_SIZE)
    _G[scaleSlider:GetName() .. "High"]:SetText("150%")
    BumpFont(_G[scaleSlider:GetName() .. "High"], PANEL_LABEL_FONT_SIZE)
    _G[scaleSlider:GetName() .. "Text"]:SetText("Arrow scale")
    BumpFont(_G[scaleSlider:GetName() .. "Text"], PANEL_LABEL_FONT_SIZE)
    scaleSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / 5 + 0.5) * 5
        XalsXRDB.arrowScale = value / 100
        _G[self:GetName() .. "Text"]:SetText("Arrow scale: " .. value .. "%")
        BumpFont(_G[self:GetName() .. "Text"], PANEL_LABEL_FONT_SIZE)
        Beacon:ApplyArrowStyle()
    end)
    waypointPanel.scaleSlider = scaleSlider

    local scaleHelp = waypointPanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    BumpFont(scaleHelp, PANEL_DESC_FONT_SIZE)
    scaleHelp:SetPoint("TOPLEFT", scaleSlider, "BOTTOMLEFT", -6, -16)
    scaleHelp:SetPoint("RIGHT", waypointPanel, "RIGHT", -16, 0)
    scaleHelp:SetJustifyH("LEFT")
    scaleHelp:SetText("Resizes the arrow uniformly - same shape, just bigger or smaller.")

    local textScaleSlider = CreateFrame("Slider", "XalsXRArrowTextScaleSlider", waypointPanel, "OptionsSliderTemplate")
    textScaleSlider:SetPoint("TOPLEFT", scaleHelp, "BOTTOMLEFT", 6, -30)
    textScaleSlider:SetWidth(220)
    textScaleSlider:SetMinMaxValues(100, 250)
    textScaleSlider:SetValueStep(10)
    textScaleSlider:SetObeyStepOnDrag(true)
    _G[textScaleSlider:GetName() .. "Low"]:SetText("100%")
    BumpFont(_G[textScaleSlider:GetName() .. "Low"], PANEL_LABEL_FONT_SIZE)
    _G[textScaleSlider:GetName() .. "High"]:SetText("250%")
    BumpFont(_G[textScaleSlider:GetName() .. "High"], PANEL_LABEL_FONT_SIZE)
    _G[textScaleSlider:GetName() .. "Text"]:SetText("Text size")
    BumpFont(_G[textScaleSlider:GetName() .. "Text"], PANEL_LABEL_FONT_SIZE)
    textScaleSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / 10 + 0.5) * 10
        XalsXRDB.arrowTextScale = value / 100
        _G[self:GetName() .. "Text"]:SetText("Text size: " .. value .. "%")
        BumpFont(_G[self:GetName() .. "Text"], PANEL_LABEL_FONT_SIZE)
        Beacon:ApplyTextScale()
    end)
    waypointPanel.textScaleSlider = textScaleSlider

    local textScaleHelp = waypointPanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    BumpFont(textScaleHelp, PANEL_DESC_FONT_SIZE)
    textScaleHelp:SetPoint("TOPLEFT", textScaleSlider, "BOTTOMLEFT", -6, -16)
    textScaleHelp:SetPoint("RIGHT", waypointPanel, "RIGHT", -16, 0)
    textScaleHelp:SetJustifyH("LEFT")
    textScaleHelp:SetText("Enlarges the distance and node-name text under the arrow - handy if the default is hard to read.")

    local trailLineCheck = CreateFrame("CheckButton", nil, waypointPanel, "UICheckButtonTemplate")
    trailLineCheck:SetPoint("TOPLEFT", textScaleHelp, "BOTTOMLEFT", 2, -14)
    trailLineCheck.Text:SetText("Show a trail line on the minimap to your next stop")
    BumpFont(trailLineCheck.Text, PANEL_LABEL_FONT_SIZE)
    trailLineCheck.Text:SetWordWrap(true)
    trailLineCheck.Text:SetPoint("RIGHT", waypointPanel, "RIGHT", -16, 0)
    trailLineCheck:SetScript("OnClick", function(self)
        XalsXRDB.showTrailLine = self:GetChecked() and true or false
    end)
    waypointPanel.trailLineCheck = trailLineCheck

    local RefreshWaypointPanel = function()
        local currentArrowStyle = (XalsXRDB and XalsXRDB.compassArrowStyle) or "custom4"
        for styleKey, styleBtn in pairs(arrowStyleButtons) do
            styleBtn:SetSelected(styleKey == currentArrowStyle)
        end
        progressColorCheck:SetChecked(not (XalsXRDB and XalsXRDB.arrowProgressColor == false))
        local scalePct = math.floor(((XalsXRDB and XalsXRDB.arrowScale) or 1) * 100 + 0.5)
        scaleSlider:SetValue(scalePct)
        _G[scaleSlider:GetName() .. "Text"]:SetText("Arrow scale: " .. scalePct .. "%")
        BumpFont(_G[scaleSlider:GetName() .. "Text"], PANEL_LABEL_FONT_SIZE)
        local textScalePct = math.floor(((XalsXRDB and XalsXRDB.arrowTextScale) or 1) * 100 + 0.5)
        textScaleSlider:SetValue(textScalePct)
        _G[textScaleSlider:GetName() .. "Text"]:SetText("Text size: " .. textScalePct .. "%")
        BumpFont(_G[textScaleSlider:GetName() .. "Text"], PANEL_LABEL_FONT_SIZE)
        trailLineCheck:SetChecked(not (XalsXRDB and XalsXRDB.showTrailLine == false))
    end
    waypointPanel:SetScript("OnShow", RefreshWaypointPanel)
    waypointPanel.Refresh = RefreshWaypointPanel

    return waypointPanel
end

--------------------------------------------------------------------------------
-- Map Markers panel: marker style picker, size, opacity, proximity hide
local function BuildMarkersPanel()
    markersPanel = CreateFrame("Frame")
    markersPanel.name = "Map Markers"

    local title = markersPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Map Markers")

    local pinStyleHelp = markersPanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    BumpFont(pinStyleHelp, PANEL_DESC_FONT_SIZE)
    pinStyleHelp:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    -- Right edge anchored to the panel (not a fixed pixel width) so it
    -- wraps within whatever width the panel actually has - a hardcoded
    -- 460 overflowed off the right edge once reparented into the
    -- standalone window's narrower content area (~458px vs. the wider
    -- native Blizzard settings panel this was originally sized for).
    -- 16px matches the title's left inset, kept symmetric on the right.
    pinStyleHelp:SetPoint("RIGHT", markersPanel, "RIGHT", -16, 0)
    pinStyleHelp:SetJustifyH("LEFT")
    pinStyleHelp:SetText("How gathering nodes are drawn on the minimap and world map. Green = Herbalism, red = Mining. Your active route target gets a small dot at its center.")
    BumpFont(pinStyleHelp, PANEL_DESC_FONT_SIZE)

    local pinCols = 2
    local pinBtnWidth = 165
    local pinBtnHeight = 22
    local pinBtnGapX = 8
    local pinBtnGapY = 6

    pinStyleButtons = {}
    for i, key in ipairs(Markers.PIN_STYLES) do
        local col = (i - 1) % pinCols
        local row = math.floor((i - 1) / pinCols)
        local btn = CreateButton(markersPanel, pinStyleHelp, col * (pinBtnWidth + pinBtnGapX),
            -14 - row * (pinBtnHeight + pinBtnGapY), Markers.PIN_STYLE_LABELS[key], pinBtnWidth, function()
                XalsXRDB.pinStyle = key
                Markers:UpdatePins()
                for styleKey, styleBtn in pairs(pinStyleButtons) do
                    styleBtn:SetSelected(styleKey == key)
                end
            end)
        pinStyleButtons[key] = btn
    end

    local pinStyleRows = math.ceil(#Markers.PIN_STYLES / pinCols)
    local pinStyleBottom = CreateFrame("Frame", nil, markersPanel)
    pinStyleBottom:SetSize(1, 1)
    pinStyleBottom:SetPoint("TOPLEFT", pinStyleHelp, "BOTTOMLEFT", 0, -14 - pinStyleRows * (pinBtnHeight + pinBtnGapY))

    local pinSizeSlider = CreateFrame("Slider", "XalsXRPinSizeSlider", markersPanel, "OptionsSliderTemplate")
    pinSizeSlider:SetPoint("TOPLEFT", pinStyleBottom, "BOTTOMLEFT", 6, -30)
    pinSizeSlider:SetWidth(220)
    pinSizeSlider:SetMinMaxValues(8, 28)
    pinSizeSlider:SetValueStep(2)
    pinSizeSlider:SetObeyStepOnDrag(true)
    _G[pinSizeSlider:GetName() .. "Low"]:SetText("8px")
    BumpFont(_G[pinSizeSlider:GetName() .. "Low"], PANEL_LABEL_FONT_SIZE)
    _G[pinSizeSlider:GetName() .. "High"]:SetText("28px")
    BumpFont(_G[pinSizeSlider:GetName() .. "High"], PANEL_LABEL_FONT_SIZE)
    _G[pinSizeSlider:GetName() .. "Text"]:SetText("Marker size")
    BumpFont(_G[pinSizeSlider:GetName() .. "Text"], PANEL_LABEL_FONT_SIZE)
    BumpFont(_G[pinSizeSlider:GetName() .. "Low"], PANEL_LABEL_FONT_SIZE)
    BumpFont(_G[pinSizeSlider:GetName() .. "High"], PANEL_LABEL_FONT_SIZE)
    BumpFont(_G[pinSizeSlider:GetName() .. "Text"], PANEL_LABEL_FONT_SIZE)
    pinSizeSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / 2 + 0.5) * 2
        XalsXRDB.pinSize = value
        _G[self:GetName() .. "Text"]:SetText("Marker size: " .. value .. "px")
        BumpFont(_G[self:GetName() .. "Text"], PANEL_LABEL_FONT_SIZE)
        Markers:UpdatePins()
    end)
    markersPanel.pinSizeSlider = pinSizeSlider

    local pinSizeHelp = markersPanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    BumpFont(pinSizeHelp, PANEL_DESC_FONT_SIZE)
    pinSizeHelp:SetPoint("TOPLEFT", pinSizeSlider, "BOTTOMLEFT", -6, -16)
    pinSizeHelp:SetPoint("RIGHT", markersPanel, "RIGHT", -16, 0)
    pinSizeHelp:SetJustifyH("LEFT")
    pinSizeHelp:SetText("Size of a normal marker. The active route target is always drawn about 40% larger than this.")
    BumpFont(pinSizeHelp, PANEL_DESC_FONT_SIZE)

    local pinAlphaSlider = CreateFrame("Slider", "XalsXRPinAlphaSlider", markersPanel, "OptionsSliderTemplate")
    pinAlphaSlider:SetPoint("TOPLEFT", pinSizeHelp, "BOTTOMLEFT", 6, -30)
    pinAlphaSlider:SetWidth(220)
    pinAlphaSlider:SetMinMaxValues(30, 100)
    pinAlphaSlider:SetValueStep(5)
    pinAlphaSlider:SetObeyStepOnDrag(true)
    _G[pinAlphaSlider:GetName() .. "Low"]:SetText("30%")
    BumpFont(_G[pinAlphaSlider:GetName() .. "Low"], PANEL_LABEL_FONT_SIZE)
    _G[pinAlphaSlider:GetName() .. "High"]:SetText("100%")
    BumpFont(_G[pinAlphaSlider:GetName() .. "High"], PANEL_LABEL_FONT_SIZE)
    _G[pinAlphaSlider:GetName() .. "Text"]:SetText("Marker opacity")
    BumpFont(_G[pinAlphaSlider:GetName() .. "Text"], PANEL_LABEL_FONT_SIZE)
    BumpFont(_G[pinAlphaSlider:GetName() .. "Low"], PANEL_LABEL_FONT_SIZE)
    BumpFont(_G[pinAlphaSlider:GetName() .. "High"], PANEL_LABEL_FONT_SIZE)
    BumpFont(_G[pinAlphaSlider:GetName() .. "Text"], PANEL_LABEL_FONT_SIZE)
    pinAlphaSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / 5 + 0.5) * 5
        XalsXRDB.pinAlpha = value / 100
        _G[self:GetName() .. "Text"]:SetText("Marker opacity: " .. value .. "%")
        BumpFont(_G[self:GetName() .. "Text"], PANEL_LABEL_FONT_SIZE)
        Markers:UpdatePins()
    end)
    markersPanel.pinAlphaSlider = pinAlphaSlider

    local pinAlphaHelp = markersPanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    BumpFont(pinAlphaHelp, PANEL_DESC_FONT_SIZE)
    pinAlphaHelp:SetPoint("TOPLEFT", pinAlphaSlider, "BOTTOMLEFT", -6, -16)
    pinAlphaHelp:SetPoint("RIGHT", markersPanel, "RIGHT", -16, 0)
    pinAlphaHelp:SetJustifyH("LEFT")
    pinAlphaHelp:SetText("Overall transparency of every marker, applied globally.")
    BumpFont(pinAlphaHelp, PANEL_DESC_FONT_SIZE)

    -- Glow toggle
    local glowCheck = CreateFrame("CheckButton", nil, markersPanel, "UICheckButtonTemplate")
    glowCheck:SetPoint("TOPLEFT", pinAlphaHelp, "BOTTOMLEFT", 2, -14)
    glowCheck.Text:SetText("Show a colored glow behind markers (green/red)")
    BumpFont(glowCheck.Text, PANEL_LABEL_FONT_SIZE)
    glowCheck.Text:SetWordWrap(true)
    glowCheck.Text:SetPoint("RIGHT", markersPanel, "RIGHT", -16, 0)
    glowCheck:SetScript("OnClick", function(self)
        XalsXRDB.showGlow = self:GetChecked() and true or false
        Markers:UpdatePins()
    end)
    markersPanel.glowCheck = glowCheck

    -- Proximity hide - always on, distance is the only adjustable part
    local proximityHeader = CreateHeader(markersPanel, glowCheck, "Hide Markers When Close", -22)

    local proximityHelp = markersPanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    BumpFont(proximityHelp, PANEL_DESC_FONT_SIZE)
    proximityHelp:SetPoint("TOPLEFT", proximityHeader, "BOTTOMLEFT", 0, -6)
    proximityHelp:SetPoint("RIGHT", markersPanel, "RIGHT", -16, 0)
    proximityHelp:SetJustifyH("LEFT")
    proximityHelp:SetText("Once you're this close to a node, its marker disappears entirely - the actual node model in the world is what matters at that range. Always on. Applies to the minimap only.")
    BumpFont(proximityHelp, PANEL_DESC_FONT_SIZE)

    local proximitySlider = CreateFrame("Slider", "XalsXRProximitySlider", markersPanel, "OptionsSliderTemplate")
    proximitySlider:SetPoint("TOPLEFT", proximityHelp, "BOTTOMLEFT", 6, -30)
    proximitySlider:SetWidth(220)
    proximitySlider:SetMinMaxValues(20, 500)
    proximitySlider:SetValueStep(10)
    proximitySlider:SetObeyStepOnDrag(true)
    _G[proximitySlider:GetName() .. "Low"]:SetText("20 yd")
    BumpFont(_G[proximitySlider:GetName() .. "Low"], PANEL_LABEL_FONT_SIZE)
    _G[proximitySlider:GetName() .. "High"]:SetText("500 yd")
    BumpFont(_G[proximitySlider:GetName() .. "High"], PANEL_LABEL_FONT_SIZE)
    _G[proximitySlider:GetName() .. "Text"]:SetText("Hide distance")
    BumpFont(_G[proximitySlider:GetName() .. "Text"], PANEL_LABEL_FONT_SIZE)
    BumpFont(_G[proximitySlider:GetName() .. "Low"], PANEL_LABEL_FONT_SIZE)
    BumpFont(_G[proximitySlider:GetName() .. "High"], PANEL_LABEL_FONT_SIZE)
    BumpFont(_G[proximitySlider:GetName() .. "Text"], PANEL_LABEL_FONT_SIZE)
    proximitySlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / 10 + 0.5) * 10
        XalsXRDB.proximityDistanceYards = value
        _G[self:GetName() .. "Text"]:SetText("Hide distance: " .. value .. " yd")
        BumpFont(_G[self:GetName() .. "Text"], PANEL_LABEL_FONT_SIZE)
    end)
    markersPanel.proximitySlider = proximitySlider

    -- Node grouping - nearby nodes become one route stop instead of a separate
    -- stop for each one. On by default; only the distance is adjustable.
    local groupingHeader = CreateHeader(markersPanel, proximitySlider, "Node Grouping Distance", -22)

    local groupingHelp = markersPanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    BumpFont(groupingHelp, PANEL_DESC_FONT_SIZE)
    groupingHelp:SetPoint("TOPLEFT", groupingHeader, "BOTTOMLEFT", 0, -6)
    groupingHelp:SetPoint("RIGHT", markersPanel, "RIGHT", -16, 0)
    groupingHelp:SetJustifyH("LEFT")
    groupingHelp:SetText("Nearby nodes within this distance are treated as one stop on your route instead of a separate stop for each one, so routes flow instead of zig-zagging through a dense patch. Keep this a bit above your Hide Distance above.")
    BumpFont(groupingHelp, PANEL_DESC_FONT_SIZE)

    local groupingSlider = CreateFrame("Slider", "XalsXRGroupingSlider", markersPanel, "OptionsSliderTemplate")
    groupingSlider:SetPoint("TOPLEFT", groupingHelp, "BOTTOMLEFT", 6, -30)
    groupingSlider:SetWidth(220)
    groupingSlider:SetMinMaxValues(50, 500)
    groupingSlider:SetValueStep(10)
    groupingSlider:SetObeyStepOnDrag(true)
    _G[groupingSlider:GetName() .. "Low"]:SetText("50 yd")
    BumpFont(_G[groupingSlider:GetName() .. "Low"], PANEL_LABEL_FONT_SIZE)
    _G[groupingSlider:GetName() .. "High"]:SetText("500 yd")
    BumpFont(_G[groupingSlider:GetName() .. "High"], PANEL_LABEL_FONT_SIZE)
    _G[groupingSlider:GetName() .. "Text"]:SetText("Grouping distance")
    BumpFont(_G[groupingSlider:GetName() .. "Text"], PANEL_LABEL_FONT_SIZE)
    groupingSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / 10 + 0.5) * 10
        XalsXRDB.groupingDistanceYards = value
        _G[self:GetName() .. "Text"]:SetText("Grouping distance: " .. value .. " yd")
        BumpFont(_G[self:GetName() .. "Text"], PANEL_LABEL_FONT_SIZE)
    end)
    markersPanel.groupingSlider = groupingSlider

    local RefreshMarkersPanel = function()
        local currentStyle = (XalsXRDB and XalsXRDB.pinStyle) or "hollowx"
        for styleKey, styleBtn in pairs(pinStyleButtons) do
            styleBtn:SetSelected(styleKey == currentStyle)
        end
        local pinSize = (XalsXRDB and XalsXRDB.pinSize) or 14
        pinSizeSlider:SetValue(pinSize)
        _G[pinSizeSlider:GetName() .. "Text"]:SetText("Marker size: " .. pinSize .. "px")
        BumpFont(_G[pinSizeSlider:GetName() .. "Text"], PANEL_LABEL_FONT_SIZE)
        local pinAlphaPct = math.floor(((XalsXRDB and XalsXRDB.pinAlpha) or 1) * 100 + 0.5)
        pinAlphaSlider:SetValue(pinAlphaPct)
        _G[pinAlphaSlider:GetName() .. "Text"]:SetText("Marker opacity: " .. pinAlphaPct .. "%")
        BumpFont(_G[pinAlphaSlider:GetName() .. "Text"], PANEL_LABEL_FONT_SIZE)
        glowCheck:SetChecked(not (XalsXRDB and XalsXRDB.showGlow == false))
        local dist = (XalsXRDB and XalsXRDB.proximityDistanceYards) or 200
        proximitySlider:SetValue(dist)
        _G[proximitySlider:GetName() .. "Text"]:SetText("Hide distance: " .. dist .. " yd")
        BumpFont(_G[proximitySlider:GetName() .. "Text"], PANEL_LABEL_FONT_SIZE)
        local groupDist = (XalsXRDB and XalsXRDB.groupingDistanceYards) or 240
        groupingSlider:SetValue(groupDist)
        _G[groupingSlider:GetName() .. "Text"]:SetText("Grouping distance: " .. groupDist .. " yd")
        BumpFont(_G[groupingSlider:GetName() .. "Text"], PANEL_LABEL_FONT_SIZE)
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

    local title = dataPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Database")

    statsText = dataPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    statsText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -20)
    statsText:SetText(GetStatsString())

    local dupSlider = CreateFrame("Slider", "XalsXRDupSlider", dataPanel, "OptionsSliderTemplate")
    dupSlider:SetPoint("TOPLEFT", statsText, "BOTTOMLEFT", 6, -24)
    dupSlider:SetWidth(220)
    dupSlider:SetMinMaxValues(5, 50)
    dupSlider:SetValueStep(5)
    dupSlider:SetObeyStepOnDrag(true)
    _G[dupSlider:GetName() .. "Low"]:SetText("5 yd")
    BumpFont(_G[dupSlider:GetName() .. "Low"], PANEL_LABEL_FONT_SIZE)
    _G[dupSlider:GetName() .. "High"]:SetText("50 yd")
    BumpFont(_G[dupSlider:GetName() .. "High"], PANEL_LABEL_FONT_SIZE)
    _G[dupSlider:GetName() .. "Text"]:SetText("Duplicate detection distance")
    BumpFont(_G[dupSlider:GetName() .. "Text"], PANEL_LABEL_FONT_SIZE)
    dupSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / 5 + 0.5) * 5
        XalsXRDB.duplicateDistanceYards = value
        _G[self:GetName() .. "Text"]:SetText("Duplicate detection distance: " .. value .. " yd")
        BumpFont(_G[self:GetName() .. "Text"], PANEL_LABEL_FONT_SIZE)
    end)
    dataPanel.dupSlider = dupSlider

    local dupHelp = dataPanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    BumpFont(dupHelp, PANEL_DESC_FONT_SIZE)
    dupHelp:SetPoint("TOPLEFT", dupSlider, "BOTTOMLEFT", -6, -16)
    dupHelp:SetPoint("RIGHT", dataPanel, "RIGHT", -16, 0)
    dupHelp:SetJustifyH("LEFT")
    dupHelp:SetText("How close two saved nodes need to be to count as the same one. If \"already recorded\" fires with no marker nearby, try lowering this.")

    local freshnessSlider = CreateFrame("Slider", "XalsXRFreshnessSlider", dataPanel, "OptionsSliderTemplate")
    freshnessSlider:SetPoint("TOPLEFT", dupHelp, "BOTTOMLEFT", 6, -30)
    freshnessSlider:SetWidth(220)
    freshnessSlider:SetMinMaxValues(0, 60)
    freshnessSlider:SetValueStep(5)
    freshnessSlider:SetObeyStepOnDrag(true)
    _G[freshnessSlider:GetName() .. "Low"]:SetText("Off")
    BumpFont(_G[freshnessSlider:GetName() .. "Low"], PANEL_LABEL_FONT_SIZE)
    _G[freshnessSlider:GetName() .. "High"]:SetText("60 min")
    BumpFont(_G[freshnessSlider:GetName() .. "High"], PANEL_LABEL_FONT_SIZE)
    _G[freshnessSlider:GetName() .. "Text"]:SetText("Node freshness")
    BumpFont(_G[freshnessSlider:GetName() .. "Text"], PANEL_LABEL_FONT_SIZE)
    freshnessSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / 5 + 0.5) * 5
        XalsXRDB.freshnessMinutes = value
        _G[self:GetName() .. "Text"]:SetText(value == 0 and "Node freshness: Off" or ("Node freshness: " .. value .. " min"))
        BumpFont(_G[self:GetName() .. "Text"], PANEL_LABEL_FONT_SIZE)
    end)
    dataPanel.freshnessSlider = freshnessSlider

    local freshnessHelp = dataPanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    BumpFont(freshnessHelp, PANEL_DESC_FONT_SIZE)
    freshnessHelp:SetPoint("TOPLEFT", freshnessSlider, "BOTTOMLEFT", -6, -16)
    freshnessHelp:SetPoint("RIGHT", dataPanel, "RIGHT", -16, 0)
    freshnessHelp:SetJustifyH("LEFT")
    freshnessHelp:SetText("Skips nodes you gathered more recently than this when building a route, since they probably haven't respawned yet. Off routes to every saved node regardless of when it was last picked.")

    local cleanupBtn = CreateButton(dataPanel, freshnessHelp, 0, -12, "Cleanup Duplicates", 170, function()
        local removed = NodeLogger.RemoveDuplicates()
        print("|cff00ccffXal's XR:|r Cleanup complete. Removed |cffff9900" .. removed .. "|r duplicates.")
        Markers:UpdatePins()
        RefreshStats()
    end)
    -- Stacked vertically (CreateButton's own default: new button's TOP
    -- anchors to the given anchor's BOTTOM), not side by side. Confirmed
    -- 2026-08-09.
    local resetZoneBtn = CreateButton(dataPanel, cleanupBtn, 0, -8, "Reset Current Zone", 170, function()
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
        local dupYards = (XalsXRDB and XalsXRDB.duplicateDistanceYards) or 15
        dupSlider:SetValue(dupYards)
        _G[dupSlider:GetName() .. "Text"]:SetText("Duplicate detection distance: " .. dupYards .. " yd")
        BumpFont(_G[dupSlider:GetName() .. "Text"], PANEL_LABEL_FONT_SIZE)
        local freshnessMinutes = (XalsXRDB and XalsXRDB.freshnessMinutes) or Helpers.DEFAULT_FRESHNESS_MINUTES
        freshnessSlider:SetValue(freshnessMinutes)
        _G[freshnessSlider:GetName() .. "Text"]:SetText(freshnessMinutes == 0 and "Node freshness: Off" or ("Node freshness: " .. freshnessMinutes .. " min"))
        BumpFont(_G[freshnessSlider:GetName() .. "Text"], PANEL_LABEL_FONT_SIZE)
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

    local title = integrationsPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Integrations")

    local intro = integrationsPanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    BumpFont(intro, PANEL_DESC_FONT_SIZE)
    intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    intro:SetPoint("RIGHT", integrationsPanel, "RIGHT", -16, 0)
    intro:SetJustifyH("LEFT")
    intro:SetText("Optional hand-offs to other addons, if you have them installed. Nothing here is required for this addon's own features to work.")

    local tomtomHeader = CreateHeader(integrationsPanel, intro, "TomTom", -22)

    local tomtomCheck = CreateFrame("CheckButton", nil, integrationsPanel, "UICheckButtonTemplate")
    tomtomCheck:SetPoint("TOPLEFT", tomtomHeader, "BOTTOMLEFT", 2, -6)
    tomtomCheck.Text:SetText("Sync TomTom's crazy arrow to your current route stop")
    BumpFont(tomtomCheck.Text, PANEL_LABEL_FONT_SIZE)
    tomtomCheck.Text:SetWordWrap(true)
    tomtomCheck.Text:SetPoint("RIGHT", integrationsPanel, "RIGHT", -16, 0)
    tomtomCheck:SetScript("OnClick", function(self)
        XalsXRDB.tomtomSyncEnabled = self:GetChecked() and true or false
        if not XalsXRDB.tomtomSyncEnabled and addonTable.TomTomBridge.ClearWaypoints then
            addonTable.TomTomBridge:ClearWaypoints()
        end
    end)
    integrationsPanel.tomtomCheck = tomtomCheck

    local tomtomHelp = integrationsPanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    BumpFont(tomtomHelp, PANEL_DESC_FONT_SIZE)
    tomtomHelp:SetPoint("TOPLEFT", tomtomCheck, "BOTTOMLEFT", -2, -16)
    tomtomHelp:SetPoint("RIGHT", integrationsPanel, "RIGHT", -16, 0)
    tomtomHelp:SetJustifyH("LEFT")
    tomtomHelp:SetText("Off by default. Does nothing if TomTom isn't installed. When on, keeps TomTom's own arrow pointed at whatever stop this addon's route currently considers next.")

    local RefreshIntegrationsPanel = function()
        tomtomCheck:SetChecked(XalsXRDB and XalsXRDB.tomtomSyncEnabled == true)
    end
    integrationsPanel:SetScript("OnShow", RefreshIntegrationsPanel)
    integrationsPanel.Refresh = RefreshIntegrationsPanel

    return integrationsPanel
end

--------------------------------------------------------------------------------
-- Gather Tally panel: icons on/off (text mode), text size, and the two timers.
--------------------------------------------------------------------------------
local function BuildGatherTallyPanel()
    gatherPanel = CreateFrame("Frame")
    gatherPanel.name = "Gather Tally"

    local title = gatherPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Gather Tally")

    local intro = gatherPanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    BumpFont(intro, PANEL_DESC_FONT_SIZE)
    intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    intro:SetPoint("RIGHT", gatherPanel, "RIGHT", -16, 0)
    intro:SetJustifyH("LEFT")
    intro:SetText("The live window that tallies what you gather. Open it with the Gather button on the floating helper, or /xxr haul.")

    local displayHeader = CreateHeader(gatherPanel, intro, "Display", -18)

    local iconsCheck = CreateFrame("CheckButton", nil, gatherPanel, "UICheckButtonTemplate")
    iconsCheck:SetPoint("TOPLEFT", displayHeader, "BOTTOMLEFT", 2, -8)
    iconsCheck.Text:SetText("Show item icons (off = clean text-only list)")
    BumpFont(iconsCheck.Text, PANEL_LABEL_FONT_SIZE)
    iconsCheck.Text:SetWordWrap(true)
    iconsCheck.Text:SetPoint("RIGHT", gatherPanel, "RIGHT", -16, 0)
    iconsCheck:SetScript("OnClick", function(self)
        XalsXRDB.haulShowIcons = self:GetChecked() and true or false
        if addonTable.RunTracker and addonTable.RunTracker.Render then addonTable.RunTracker:Render() end
    end)
    gatherPanel.iconsCheck = iconsCheck

    local sizeSlider = CreateFrame("Slider", "XalsXRHaulFontSlider", gatherPanel, "OptionsSliderTemplate")
    sizeSlider:SetPoint("TOPLEFT", iconsCheck, "BOTTOMLEFT", 4, -30)
    sizeSlider:SetWidth(220)
    sizeSlider:SetMinMaxValues(100, 200)
    sizeSlider:SetValueStep(10)
    sizeSlider:SetObeyStepOnDrag(true)
    _G[sizeSlider:GetName() .. "Low"]:SetText("100%")
    BumpFont(_G[sizeSlider:GetName() .. "Low"], PANEL_LABEL_FONT_SIZE)
    _G[sizeSlider:GetName() .. "High"]:SetText("200%")
    BumpFont(_G[sizeSlider:GetName() .. "High"], PANEL_LABEL_FONT_SIZE)
    _G[sizeSlider:GetName() .. "Text"]:SetText("Text size")
    BumpFont(_G[sizeSlider:GetName() .. "Text"], PANEL_LABEL_FONT_SIZE)
    sizeSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / 10 + 0.5) * 10
        XalsXRDB.haulFontScale = value / 100
        _G[self:GetName() .. "Text"]:SetText("Text size: " .. value .. "%")
        BumpFont(_G[self:GetName() .. "Text"], PANEL_LABEL_FONT_SIZE)
        if addonTable.RunTracker and addonTable.RunTracker.Render then addonTable.RunTracker:Render() end
    end)
    gatherPanel.sizeSlider = sizeSlider

    local sizeHelp = gatherPanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    BumpFont(sizeHelp, PANEL_DESC_FONT_SIZE)
    sizeHelp:SetPoint("TOPLEFT", sizeSlider, "BOTTOMLEFT", -6, -16)
    sizeHelp:SetPoint("RIGHT", gatherPanel, "RIGHT", -16, 0)
    sizeHelp:SetJustifyH("LEFT")
    sizeHelp:SetText("Scales the text in the tally list up or down.")

    local timerHeader = CreateHeader(gatherPanel, sizeHelp, "Timers", -18)

    local gatherTimerCheck = CreateFrame("CheckButton", nil, gatherPanel, "UICheckButtonTemplate")
    gatherTimerCheck:SetPoint("TOPLEFT", timerHeader, "BOTTOMLEFT", 2, -8)
    gatherTimerCheck.Text:SetText("Gather timer - time your Gather-button sessions")
    BumpFont(gatherTimerCheck.Text, PANEL_LABEL_FONT_SIZE)
    gatherTimerCheck.Text:SetWordWrap(true)
    gatherTimerCheck.Text:SetPoint("RIGHT", gatherPanel, "RIGHT", -16, 0)
    gatherTimerCheck:SetScript("OnClick", function(self)
        XalsXRDB.haulGatherTimer = self:GetChecked() and true or false
        if addonTable.RunTracker and addonTable.RunTracker.Render then addonTable.RunTracker:Render() end
    end)
    gatherPanel.gatherTimerCheck = gatherTimerCheck

    local routeTimerCheck = CreateFrame("CheckButton", nil, gatherPanel, "UICheckButtonTemplate")
    routeTimerCheck:SetPoint("TOPLEFT", gatherTimerCheck, "BOTTOMLEFT", 0, -20)
    routeTimerCheck.Text:SetText("Route timer - time how long a route has run")
    BumpFont(routeTimerCheck.Text, PANEL_LABEL_FONT_SIZE)
    routeTimerCheck.Text:SetWordWrap(true)
    routeTimerCheck.Text:SetPoint("RIGHT", gatherPanel, "RIGHT", -16, 0)
    routeTimerCheck:SetScript("OnClick", function(self)
        XalsXRDB.haulRouteTimer = self:GetChecked() and true or false
        if addonTable.RunTracker and addonTable.RunTracker.Render then addonTable.RunTracker:Render() end
    end)
    gatherPanel.routeTimerCheck = routeTimerCheck

    local timerHelp = gatherPanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    BumpFont(timerHelp, PANEL_DESC_FONT_SIZE)
    timerHelp:SetPoint("TOPLEFT", routeTimerCheck, "BOTTOMLEFT", -2, -16)
    timerHelp:SetPoint("RIGHT", gatherPanel, "RIGHT", -16, 0)
    timerHelp:SetJustifyH("LEFT")
    timerHelp:SetText("Both off by default. When on, the tally shows elapsed time - the gather timer for sessions you open with the Gather button, the route timer while you're running a route.")

    local dungeonHeader = CreateHeader(gatherPanel, timerHelp, "Dungeon Nav (Xperimental)", -18)

    local dungeonEnableCheck = CreateFrame("CheckButton", nil, gatherPanel, "UICheckButtonTemplate")
    dungeonEnableCheck:SetPoint("TOPLEFT", dungeonHeader, "BOTTOMLEFT", 2, -8)
    dungeonEnableCheck.Text:SetText("Show a dungeon-waypoint button on the helper (retail only)")
    BumpFont(dungeonEnableCheck.Text, PANEL_LABEL_FONT_SIZE)
    dungeonEnableCheck.Text:SetWordWrap(true)
    dungeonEnableCheck.Text:SetPoint("RIGHT", gatherPanel, "RIGHT", -16, 0)
    dungeonEnableCheck:SetScript("OnClick", function(self)
        XalsXRDB.dungeonButtonEnabled = self:GetChecked() and true or false
        if QuickButton and QuickButton.Refresh then QuickButton:Refresh() end
    end)
    gatherPanel.dungeonEnableCheck = dungeonEnableCheck

    -- The old "put it on the left" side toggle was removed 2026-08-09 - the
    -- dungeon button no longer sits beside the Gather button at all, it's
    -- centered underneath it now, so dungeonButtonSide stopped doing
    -- anything visible the moment that positioning changed.
    local dungeonHelp = gatherPanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    BumpFont(dungeonHelp, PANEL_DESC_FONT_SIZE)
    dungeonHelp:SetPoint("TOPLEFT", dungeonEnableCheck, "BOTTOMLEFT", -2, -16)
    dungeonHelp:SetPoint("RIGHT", gatherPanel, "RIGHT", -16, 0)
    dungeonHelp:SetJustifyH("LEFT")
    dungeonHelp:SetText("Adds a small map icon next to the Gather button. Click it to pick a Season 2 dungeon and drop a waypoint at its entrance. Also available as /xxr dungeon.")

    local RefreshGatherPanel = function()
        iconsCheck:SetChecked(not (XalsXRDB and XalsXRDB.haulShowIcons == false))
        local pct = math.floor(((XalsXRDB and XalsXRDB.haulFontScale) or 1) * 100 + 0.5)
        sizeSlider:SetValue(pct)
        _G[sizeSlider:GetName() .. "Text"]:SetText("Text size: " .. pct .. "%")
        BumpFont(_G[sizeSlider:GetName() .. "Text"], PANEL_LABEL_FONT_SIZE)
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
local standaloneTabs = {}
local standalonePanels

local function ShowStandaloneTab(index)
    local entry = standalonePanels[index]
    for i, tab in ipairs(standaloneTabs) do
        tab:SetSelected(i == index)
    end
    for i, other in ipairs(standalonePanels) do
        if i ~= index then other.panel:Hide() end
    end
    local panel = entry.panel
    panel:SetParent(standaloneContent)
    panel:ClearAllPoints()
    panel:SetAllPoints(standaloneContent)
    panel:Show()
    if panel.Refresh then panel.Refresh() end
end

local function BuildStandaloneWindow()
    if standaloneFrame then return standaloneFrame end
    if not rootPanel then SettingsPanel:Init() end

    -- Tall enough to fit the biggest existing panel (Map Markers, since the
    -- 1.3.2 grouping-distance slider pushed it past Gather Tally) without
    -- needing scroll mechanics - deliberately generous rather than tight.
    local FW, FH = 640, 820
    local f = CreateFrame("Frame", "XalsXRStandaloneOptions", UIParent, "BackdropTemplate")
    tinsert(UISpecialFrames, "XalsXRStandaloneOptions") -- lets the Escape key close it, like any other UI panel
    f:SetSize(FW, FH)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)

    Brand.ApplyBackground(f)
    Brand.DrawBorder(f)
    -- Centered (not left-justified) and given real room below the border,
    -- per design feedback 2026-08-09.
    Brand.Title(f, "Xal's Xpedited Routes", 30, "TOP", f, "TOP", 0, -28)

    -- Branded flat button instead of Blizzard's default red-X close button
    -- template, which clashed with the rest of the panel's look.
    local closeBtn = Brand.MakeButton(f, "X", 24, 24, function() f:Hide() end)
    PixelUtil.SetPoint(closeBtn, "TOPRIGHT", f, "TOPRIGHT", -Brand.SAFE_MARGIN, -Brand.SAFE_MARGIN)

    -- Horizontal divider separating the title from the tabs/content below -
    -- same feedback pass. Pushed down 8px from its original 58 to give the
    -- larger (30pt, up from 20pt) title room to breathe without crowding it.
    local headerDivider = Brand.DrawDivider(f, Brand.SAFE_MARGIN, 66, FW - Brand.SAFE_MARGIN * 2)

    -- Left-side tab list, matching the established sidebar-tabs convention.
    local sidebar = CreateFrame("Frame", nil, f)
    sidebar:SetPoint("TOPLEFT", f, "TOPLEFT", Brand.SAFE_MARGIN, -78)
    sidebar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", Brand.SAFE_MARGIN, Brand.SAFE_MARGIN)
    sidebar:SetWidth(132)

    local vDivider = f:CreateTexture(nil, "ARTWORK")
    vDivider:SetWidth(Brand.LINE_THICKNESS)
    vDivider:SetColorTexture(Brand.ACCENT[1], Brand.ACCENT[2], Brand.ACCENT[3], 1)
    vDivider:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 10, 0)
    vDivider:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMRIGHT", 10, 0)

    standaloneContent = CreateFrame("Frame", nil, f)
    standaloneContent:SetPoint("TOPLEFT", vDivider, "TOPRIGHT", 12, 0)
    standaloneContent:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -Brand.SAFE_MARGIN, Brand.SAFE_MARGIN)

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
        tab:ClearAllPoints()
        if anchorTab then
            PixelUtil.SetPoint(tab, "TOPLEFT", anchorTab, "BOTTOMLEFT", 0, -4)
        else
            PixelUtil.SetPoint(tab, "TOPLEFT", sidebar, "TOPLEFT", TAB_SIDE_PAD, 0)
        end
        standaloneTabs[i] = tab
        anchorTab = tab
    end

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

function SettingsPanel:Init()
    if rootPanel then return end
    BuildRootPanel()
    BuildFloatingButtonPanel()
    BuildWaypointPanel()
    BuildMarkersPanel()
    BuildGatherTallyPanel()
    BuildDataPanel()
    BuildIntegrationsPanel()

    if Settings and Settings.RegisterCanvasLayoutCategory then
        -- Modern Settings API (retail 10.0+), with real sub-sections in the category tree
        local rootCategory = Settings.RegisterCanvasLayoutCategory(rootPanel, rootPanel.name)
        rootCategory.ID = rootPanel.name
        Settings.RegisterAddOnCategory(rootCategory)
        SettingsPanel.category = rootCategory

        if Settings.RegisterCanvasLayoutSubcategory then
            Settings.RegisterCanvasLayoutSubcategory(rootCategory, floatingPanel, floatingPanel.name)
            Settings.RegisterCanvasLayoutSubcategory(rootCategory, waypointPanel, waypointPanel.name)
            Settings.RegisterCanvasLayoutSubcategory(rootCategory, markersPanel, markersPanel.name)
            Settings.RegisterCanvasLayoutSubcategory(rootCategory, gatherPanel, gatherPanel.name)
            Settings.RegisterCanvasLayoutSubcategory(rootCategory, dataPanel, dataPanel.name)
            Settings.RegisterCanvasLayoutSubcategory(rootCategory, integrationsPanel, integrationsPanel.name)
        end
    elseif InterfaceOptions_AddCategory then
        -- Legacy fallback for older clients: nest sub-panels under the root by name
        InterfaceOptions_AddCategory(rootPanel)
        floatingPanel.parent = rootPanel.name
        InterfaceOptions_AddCategory(floatingPanel)
        waypointPanel.parent = rootPanel.name
        InterfaceOptions_AddCategory(waypointPanel)
        markersPanel.parent = rootPanel.name
        InterfaceOptions_AddCategory(markersPanel)
        gatherPanel.parent = rootPanel.name
        InterfaceOptions_AddCategory(gatherPanel)
        dataPanel.parent = rootPanel.name
        InterfaceOptions_AddCategory(dataPanel)
        integrationsPanel.parent = rootPanel.name
        InterfaceOptions_AddCategory(integrationsPanel)
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
