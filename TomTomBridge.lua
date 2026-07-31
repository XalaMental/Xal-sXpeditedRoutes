-- TomTomBridge.lua
-- Xal's Xpedited Routes
--
-- If TomTom is installed, generating a route automatically opens a window with
-- that route's nodes as a list of TomTom-compatible /way commands, ready to
-- paste into TomTom's own /ttpaste bulk-import window. This is intentionally
-- simple: no TomTom API calls, no checking what TomTom does with it - just a
-- plain-text list you copy and paste, exactly like handing someone directions.
-- The only thing checked is whether the global `TomTom` table exists at all, to
-- decide whether it's worth showing the window in the first place.
local addonName, addonTable = ...
local TomTomBridge = addonTable.TomTomBridge

local exportFrame = nil
local exportEditBox = nil

local function BuildWayList(nodes, mapID)
    if not nodes or #nodes == 0 then return nil, 0 end

    local mapInfo = C_Map.GetMapInfo(mapID)
    local zoneName = (mapInfo and mapInfo.name) or ""

    local lines = {}
    for _, node in ipairs(nodes) do
        local label = node.type == "mine" and "Mine" or "Herb"
        table.insert(lines, string.format("/way %s %.2f %.2f %s", zoneName, node.x * 100, node.y * 100, label))
    end
    return table.concat(lines, "\n"), #lines
end

local function EnsureExportFrame()
    if exportFrame then return end

    exportFrame = CreateFrame("Frame", "XalsXRExportFrame", UIParent, "BackdropTemplate")
    exportFrame:SetSize(500, 400)
    exportFrame:SetPoint("CENTER")
    exportFrame:SetFrameStrata("DIALOG")
    exportFrame:SetMovable(true)
    exportFrame:EnableMouse(true)
    exportFrame:RegisterForDrag("LeftButton")
    exportFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    exportFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    exportFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    exportFrame:SetBackdropColor(0.06, 0.06, 0.08, 0.97)
    exportFrame:SetBackdropBorderColor(0.72, 0.55, 0.14, 1)
    exportFrame:Hide()

    local title = exportFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText("Route -> TomTom")

    local help = exportFrame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    help:SetWidth(460)
    help:SetJustifyH("LEFT")
    help:SetText("Text is already selected - press Ctrl+C to copy, then type /ttpaste in-game and paste it in there.")

    local closeBtn = CreateFrame("Button", nil, exportFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() exportFrame:Hide() end)

    local scrollFrame = CreateFrame("ScrollFrame", nil, exportFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", help, "BOTTOMLEFT", 0, -10)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 16)

    exportEditBox = CreateFrame("EditBox", nil, scrollFrame)
    exportEditBox:SetMultiLine(true)
    exportEditBox:SetFontObject(ChatFontNormal)
    exportEditBox:SetWidth(430)
    exportEditBox:SetAutoFocus(false)
    exportEditBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        exportFrame:Hide()
    end)
    scrollFrame:SetScrollChild(exportEditBox)
end

-- Called automatically from Routing:PlotCourse() right after a route is
-- built. Does nothing if TomTom isn't installed - just a plain existence check
-- on the global table, no function calls into TomTom itself.
function TomTomBridge:ShowRouteExport(routeNodes, mapID)
    if not TomTom then return end

    EnsureExportFrame()

    local text, count = BuildWayList(routeNodes, mapID)
    if not text then return end

    exportEditBox:SetText(text)
    exportEditBox:HighlightText()
    exportEditBox:SetFocus()
    exportFrame:Show()

    print("|cff00ccffXal's XR:|r TomTom detected - " .. count .. " nodes ready to paste (Ctrl+C, then /ttpaste in TomTom).")
end
