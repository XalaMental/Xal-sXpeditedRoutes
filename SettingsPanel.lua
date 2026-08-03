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

local rootPanel, waypointPanel, markersPanel, dataPanel, integrationsPanel
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
                and mapID ~= "duplicateDistanceYards" and mapID ~= "compassArrowStyle" and mapID ~= "arrowScale" and mapID ~= "tomtomSyncEnabled" and type(nodes) == "table" then
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
                and key ~= "duplicateDistanceYards" and key ~= "compassArrowStyle" and key ~= "arrowScale" and key ~= "tomtomSyncEnabled" then
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

local function CreateHeader(parentPanel, anchorTo, text, yOffset)
    local header = parentPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, yOffset or -20)
    header:SetText(text)
    return header
end

-- Self-drawn button: not a UIPanelButtonTemplate, so it can't get caught by whatever
-- is reskinning that shared template. btn:SetSelected(bool) is used for toggle-style
-- selection (the marker style picker); plain buttons never call it.
local function CreateButton(parentPanel, anchorTo, xOffset, yOffset, label, width, onClick)
    local btn = CreateFrame("Button", nil, parentPanel, "BackdropTemplate")
    btn:SetSize(width or 160, 24)
    btn:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", xOffset, yOffset)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    btn:SetBackdropColor(0.08, 0.08, 0.1, 0.92)
    btn:SetBackdropBorderColor(0.72, 0.55, 0.14, 1)

    local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("CENTER")
    text:SetWidth((width or 160) - 12)
    text:SetWordWrap(false)
    text:SetText(label)
    text:SetTextColor(0.95, 0.82, 0.4)
    btn.text = text

    btn:SetScript("OnEnter", function(self)
        if not self.selected then
            self:SetBackdropColor(0.18, 0.18, 0.14, 0.95)
        end
    end)
    btn:SetScript("OnLeave", function(self)
        if not self.selected then
            self:SetBackdropColor(0.08, 0.08, 0.1, 0.92)
        end
    end)
    btn:SetScript("OnClick", onClick)

    function btn:SetSelected(selected)
        self.selected = selected
        if selected then
            self:SetBackdropColor(0.34, 0.25, 0.05, 1)
            self:SetBackdropBorderColor(1, 0.85, 0.2, 1)
            self.text:SetTextColor(1, 0.95, 0.6)
        else
            self:SetBackdropColor(0.08, 0.08, 0.1, 0.92)
            self:SetBackdropBorderColor(0.72, 0.55, 0.14, 1)
            self.text:SetTextColor(0.95, 0.82, 0.4)
        end
    end

    return btn
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
    credit:SetPoint("TOPLEFT", logo, "BOTTOMLEFT", 0, -10)
    credit:SetText("See the sub-sections in the list on the left for Map Markers and Database.")
    credit:SetWidth(500)
    credit:SetJustifyH("LEFT")

    local professionNote = rootPanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    professionNote:SetPoint("TOPLEFT", credit, "BOTTOMLEFT", -2, -18)
    professionNote:SetWidth(460)
    professionNote:SetJustifyH("LEFT")
    professionNote:SetText("Markers and routes automatically skip node types this character doesn't have the profession to gather - e.g. a pure-Herbalism character won't see Mining nodes another character on your account recorded.")

    local helperButtonCheck = CreateFrame("CheckButton", nil, rootPanel, "UICheckButtonTemplate")
    helperButtonCheck:SetPoint("TOPLEFT", professionNote, "BOTTOMLEFT", 2, -10)
    helperButtonCheck.Text:SetText("Show the floating helper button (click to route/unroute)")
    helperButtonCheck:SetScript("OnClick", function(self)
        if self:GetChecked() then
            QuickButton:Show()
        else
            QuickButton:Hide()
        end
    end)
    rootPanel.helperButtonCheck = helperButtonCheck

    local resetButtonPosBtn = CreateButton(rootPanel, helperButtonCheck, 2, -8, "Reset Button Position", 200, function()
        QuickButton:ResetPosition()
    end)

    local slider = CreateFrame("Slider", "XalsXRAdvanceSlider", rootPanel, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", resetButtonPosBtn, "BOTTOMLEFT", 4, -24)
    slider:SetWidth(220)
    slider:SetMinMaxValues(10, 60)
    slider:SetValueStep(5)
    slider:SetObeyStepOnDrag(true)
    _G[slider:GetName() .. "Low"]:SetText("10 yd")
    _G[slider:GetName() .. "High"]:SetText("60 yd")
    _G[slider:GetName() .. "Text"]:SetText("Auto-advance distance")
    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        XalsXRDB.autoAdvanceDistance = value
        _G[self:GetName() .. "Text"]:SetText("Auto-advance distance: " .. value .. " yd")
    end)
    rootPanel.slider = slider

    local sliderHelp = rootPanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    sliderHelp:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", -6, -8)
    sliderHelp:SetWidth(360)
    sliderHelp:SetJustifyH("LEFT")
    sliderHelp:SetText("How close you need to be to a node before the compass automatically advances to the next one.")

    local RefreshRootPanel = function()
        helperButtonCheck:SetChecked(not (XalsXRDB and XalsXRDB.showHelperButton == false))
        local dist = (XalsXRDB and XalsXRDB.autoAdvanceDistance) or 30
        slider:SetValue(dist)
        _G[slider:GetName() .. "Text"]:SetText("Auto-advance distance: " .. dist .. " yd")
    end
    rootPanel:SetScript("OnShow", RefreshRootPanel)
    rootPanel.Refresh = RefreshRootPanel

    return rootPanel
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
    intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    intro:SetWidth(460)
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
    progressColorCheck:SetScript("OnClick", function(self)
        XalsXRDB.arrowProgressColor = self:GetChecked() and true or false
    end)
    waypointPanel.progressColorCheck = progressColorCheck

    local progressColorHelp = waypointPanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    progressColorHelp:SetPoint("TOPLEFT", progressColorCheck, "BOTTOMLEFT", -2, -4)
    progressColorHelp:SetWidth(420)
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
    _G[scaleSlider:GetName() .. "High"]:SetText("150%")
    _G[scaleSlider:GetName() .. "Text"]:SetText("Arrow scale")
    scaleSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / 5 + 0.5) * 5
        XalsXRDB.arrowScale = value / 100
        _G[self:GetName() .. "Text"]:SetText("Arrow scale: " .. value .. "%")
        Beacon:ApplyArrowStyle()
    end)
    waypointPanel.scaleSlider = scaleSlider

    local scaleHelp = waypointPanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    scaleHelp:SetPoint("TOPLEFT", scaleSlider, "BOTTOMLEFT", -6, -8)
    scaleHelp:SetWidth(360)
    scaleHelp:SetJustifyH("LEFT")
    scaleHelp:SetText("Resizes the arrow uniformly - same shape, just bigger or smaller.")

    local RefreshWaypointPanel = function()
        local currentArrowStyle = (XalsXRDB and XalsXRDB.compassArrowStyle) or "custom4"
        for styleKey, styleBtn in pairs(arrowStyleButtons) do
            styleBtn:SetSelected(styleKey == currentArrowStyle)
        end
        progressColorCheck:SetChecked(not (XalsXRDB and XalsXRDB.arrowProgressColor == false))
        local scalePct = math.floor(((XalsXRDB and XalsXRDB.arrowScale) or 1) * 100 + 0.5)
        scaleSlider:SetValue(scalePct)
        _G[scaleSlider:GetName() .. "Text"]:SetText("Arrow scale: " .. scalePct .. "%")
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

    local title = markersPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Map Markers")

    local pinStyleHelp = markersPanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    pinStyleHelp:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    pinStyleHelp:SetWidth(460)
    pinStyleHelp:SetJustifyH("LEFT")
    pinStyleHelp:SetText("How gathering nodes are drawn on the minimap and world map. Green = Herbalism, red = Mining. Your active route target gets a small dot at its center.")

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
    pinSizeSlider:SetPoint("TOPLEFT", pinStyleBottom, "BOTTOMLEFT", 6, -20)
    pinSizeSlider:SetWidth(220)
    pinSizeSlider:SetMinMaxValues(8, 28)
    pinSizeSlider:SetValueStep(2)
    pinSizeSlider:SetObeyStepOnDrag(true)
    _G[pinSizeSlider:GetName() .. "Low"]:SetText("8px")
    _G[pinSizeSlider:GetName() .. "High"]:SetText("28px")
    _G[pinSizeSlider:GetName() .. "Text"]:SetText("Marker size")
    pinSizeSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / 2 + 0.5) * 2
        XalsXRDB.pinSize = value
        _G[self:GetName() .. "Text"]:SetText("Marker size: " .. value .. "px")
        Markers:UpdatePins()
    end)
    markersPanel.pinSizeSlider = pinSizeSlider

    local pinSizeHelp = markersPanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    pinSizeHelp:SetPoint("TOPLEFT", pinSizeSlider, "BOTTOMLEFT", -6, -8)
    pinSizeHelp:SetWidth(360)
    pinSizeHelp:SetJustifyH("LEFT")
    pinSizeHelp:SetText("Size of a normal marker. The active route target is always drawn about 40% larger than this.")

    local pinAlphaSlider = CreateFrame("Slider", "XalsXRPinAlphaSlider", markersPanel, "OptionsSliderTemplate")
    pinAlphaSlider:SetPoint("TOPLEFT", pinSizeHelp, "BOTTOMLEFT", 6, -20)
    pinAlphaSlider:SetWidth(220)
    pinAlphaSlider:SetMinMaxValues(30, 100)
    pinAlphaSlider:SetValueStep(5)
    pinAlphaSlider:SetObeyStepOnDrag(true)
    _G[pinAlphaSlider:GetName() .. "Low"]:SetText("30%")
    _G[pinAlphaSlider:GetName() .. "High"]:SetText("100%")
    _G[pinAlphaSlider:GetName() .. "Text"]:SetText("Marker opacity")
    pinAlphaSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / 5 + 0.5) * 5
        XalsXRDB.pinAlpha = value / 100
        _G[self:GetName() .. "Text"]:SetText("Marker opacity: " .. value .. "%")
        Markers:UpdatePins()
    end)
    markersPanel.pinAlphaSlider = pinAlphaSlider

    local pinAlphaHelp = markersPanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    pinAlphaHelp:SetPoint("TOPLEFT", pinAlphaSlider, "BOTTOMLEFT", -6, -8)
    pinAlphaHelp:SetWidth(360)
    pinAlphaHelp:SetJustifyH("LEFT")
    pinAlphaHelp:SetText("Overall transparency of every marker, applied globally.")

    -- Glow toggle
    local glowCheck = CreateFrame("CheckButton", nil, markersPanel, "UICheckButtonTemplate")
    glowCheck:SetPoint("TOPLEFT", pinAlphaHelp, "BOTTOMLEFT", 2, -14)
    glowCheck.Text:SetText("Show a colored glow behind markers (green/red)")
    glowCheck:SetScript("OnClick", function(self)
        XalsXRDB.showGlow = self:GetChecked() and true or false
        Markers:UpdatePins()
    end)
    markersPanel.glowCheck = glowCheck

    -- Proximity hide - always on, distance is the only adjustable part
    local proximityHeader = CreateHeader(markersPanel, glowCheck, "Hide Markers When Close", -22)

    local proximityHelp = markersPanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    proximityHelp:SetPoint("TOPLEFT", proximityHeader, "BOTTOMLEFT", 0, -6)
    proximityHelp:SetWidth(400)
    proximityHelp:SetJustifyH("LEFT")
    proximityHelp:SetText("Once you're this close to a node, its marker disappears entirely - the actual node model in the world is what matters at that range. Always on. Applies to the minimap only.")

    local proximitySlider = CreateFrame("Slider", "XalsXRProximitySlider", markersPanel, "OptionsSliderTemplate")
    proximitySlider:SetPoint("TOPLEFT", proximityHelp, "BOTTOMLEFT", 6, -20)
    proximitySlider:SetWidth(220)
    proximitySlider:SetMinMaxValues(20, 500)
    proximitySlider:SetValueStep(10)
    proximitySlider:SetObeyStepOnDrag(true)
    _G[proximitySlider:GetName() .. "Low"]:SetText("20 yd")
    _G[proximitySlider:GetName() .. "High"]:SetText("500 yd")
    _G[proximitySlider:GetName() .. "Text"]:SetText("Hide distance")
    proximitySlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / 10 + 0.5) * 10
        XalsXRDB.proximityDistanceYards = value
        _G[self:GetName() .. "Text"]:SetText("Hide distance: " .. value .. " yd")
    end)
    markersPanel.proximitySlider = proximitySlider

    local RefreshMarkersPanel = function()
        local currentStyle = (XalsXRDB and XalsXRDB.pinStyle) or "hollowx"
        for styleKey, styleBtn in pairs(pinStyleButtons) do
            styleBtn:SetSelected(styleKey == currentStyle)
        end
        local pinSize = (XalsXRDB and XalsXRDB.pinSize) or 14
        pinSizeSlider:SetValue(pinSize)
        _G[pinSizeSlider:GetName() .. "Text"]:SetText("Marker size: " .. pinSize .. "px")
        local pinAlphaPct = math.floor(((XalsXRDB and XalsXRDB.pinAlpha) or 1) * 100 + 0.5)
        pinAlphaSlider:SetValue(pinAlphaPct)
        _G[pinAlphaSlider:GetName() .. "Text"]:SetText("Marker opacity: " .. pinAlphaPct .. "%")
        glowCheck:SetChecked(not (XalsXRDB and XalsXRDB.showGlow == false))
        local dist = (XalsXRDB and XalsXRDB.proximityDistanceYards) or 200
        proximitySlider:SetValue(dist)
        _G[proximitySlider:GetName() .. "Text"]:SetText("Hide distance: " .. dist .. " yd")
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
    _G[dupSlider:GetName() .. "High"]:SetText("50 yd")
    _G[dupSlider:GetName() .. "Text"]:SetText("Duplicate detection distance")
    dupSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / 5 + 0.5) * 5
        XalsXRDB.duplicateDistanceYards = value
        _G[self:GetName() .. "Text"]:SetText("Duplicate detection distance: " .. value .. " yd")
    end)
    dataPanel.dupSlider = dupSlider

    local dupHelp = dataPanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    dupHelp:SetPoint("TOPLEFT", dupSlider, "BOTTOMLEFT", -6, -8)
    dupHelp:SetWidth(400)
    dupHelp:SetJustifyH("LEFT")
    dupHelp:SetText("How close two saved nodes need to be to count as the same one. If \"already recorded\" fires with no marker nearby, try lowering this.")

    local cleanupBtn = CreateButton(dataPanel, dupHelp, 0, -12, "Cleanup Duplicates", 170, function()
        local removed = NodeLogger.RemoveDuplicates()
        print("|cff00ccffXal's XR:|r Cleanup complete. Removed |cffff9900" .. removed .. "|r duplicates.")
        Markers:UpdatePins()
        RefreshStats()
    end)
    local resetZoneBtn = CreateButton(dataPanel, cleanupBtn, 180, 0, "Reset Current Zone", 170, function()
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
    local resetAllBtn = CreateButton(dataPanel, cleanupBtn, 0, -34, "Reset ALL Data", 170, function()
        StaticPopup_Show("XALMORASXR_RESET_ALL")
    end)
    -- Intentionally styled as a warning - this one's destructive
    resetAllBtn:SetBackdropBorderColor(0.75, 0.2, 0.2, 1)
    resetAllBtn.text:SetTextColor(1, 0.55, 0.5)

    local RefreshDataPanel = function()
        RefreshStats()
        local dupYards = (XalsXRDB and XalsXRDB.duplicateDistanceYards) or 15
        dupSlider:SetValue(dupYards)
        _G[dupSlider:GetName() .. "Text"]:SetText("Duplicate detection distance: " .. dupYards .. " yd")
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
    intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    intro:SetWidth(460)
    intro:SetJustifyH("LEFT")
    intro:SetText("Optional hand-offs to other addons, if you have them installed. Nothing here is required for this addon's own features to work.")

    local tomtomHeader = CreateHeader(integrationsPanel, intro, "TomTom", -22)

    local tomtomCheck = CreateFrame("CheckButton", nil, integrationsPanel, "UICheckButtonTemplate")
    tomtomCheck:SetPoint("TOPLEFT", tomtomHeader, "BOTTOMLEFT", 2, -6)
    tomtomCheck.Text:SetText("Sync TomTom's crazy arrow to your current route stop")
    tomtomCheck:SetScript("OnClick", function(self)
        XalsXRDB.tomtomSyncEnabled = self:GetChecked() and true or false
        if not XalsXRDB.tomtomSyncEnabled and addonTable.TomTomBridge.ClearWaypoints then
            addonTable.TomTomBridge:ClearWaypoints()
        end
    end)
    integrationsPanel.tomtomCheck = tomtomCheck

    local tomtomHelp = integrationsPanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    tomtomHelp:SetPoint("TOPLEFT", tomtomCheck, "BOTTOMLEFT", -2, -4)
    tomtomHelp:SetWidth(420)
    tomtomHelp:SetJustifyH("LEFT")
    tomtomHelp:SetText("Off by default. Does nothing if TomTom isn't installed. When on, keeps TomTom's own arrow pointed at whatever stop this addon's route currently considers next.")

    local RefreshIntegrationsPanel = function()
        tomtomCheck:SetChecked(XalsXRDB and XalsXRDB.tomtomSyncEnabled == true)
    end
    integrationsPanel:SetScript("OnShow", RefreshIntegrationsPanel)
    integrationsPanel.Refresh = RefreshIntegrationsPanel

    return integrationsPanel
end

function SettingsPanel:Init()
    if rootPanel then return end
    BuildRootPanel()
    BuildWaypointPanel()
    BuildMarkersPanel()
    BuildDataPanel()
    BuildIntegrationsPanel()

    if Settings and Settings.RegisterCanvasLayoutCategory then
        -- Modern Settings API (retail 10.0+), with real sub-sections in the category tree
        local rootCategory = Settings.RegisterCanvasLayoutCategory(rootPanel, rootPanel.name)
        rootCategory.ID = rootPanel.name
        Settings.RegisterAddOnCategory(rootCategory)
        SettingsPanel.category = rootCategory

        if Settings.RegisterCanvasLayoutSubcategory then
            Settings.RegisterCanvasLayoutSubcategory(rootCategory, waypointPanel, waypointPanel.name)
            Settings.RegisterCanvasLayoutSubcategory(rootCategory, markersPanel, markersPanel.name)
            Settings.RegisterCanvasLayoutSubcategory(rootCategory, dataPanel, dataPanel.name)
            Settings.RegisterCanvasLayoutSubcategory(rootCategory, integrationsPanel, integrationsPanel.name)
        end
    elseif InterfaceOptions_AddCategory then
        -- Legacy fallback for older clients: nest sub-panels under the root by name
        InterfaceOptions_AddCategory(rootPanel)
        waypointPanel.parent = rootPanel.name
        InterfaceOptions_AddCategory(waypointPanel)
        markersPanel.parent = rootPanel.name
        InterfaceOptions_AddCategory(markersPanel)
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
    local panels = { rootPanel, waypointPanel, markersPanel, dataPanel, integrationsPanel }
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
