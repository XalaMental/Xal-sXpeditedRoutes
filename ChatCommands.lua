-- ChatCommands.lua
local addonName, addonTable = ...
local PathPlanner = addonTable.PathPlanner
local NodeLogger = addonTable.NodeLogger
local Markers = addonTable.Markers
local SettingsPanel = addonTable.SettingsPanel
local QuickButton = addonTable.QuickButton
local Beacon = addonTable.Beacon
local TomTomBridge = addonTable.TomTomBridge
local Helpers = addonTable.Helpers
local RunTracker = addonTable.RunTracker
local DungeonNav = addonTable.DungeonNav

-- Keybind support (see Bindings.xml). These have to be plain globals, not
-- addonTable-scoped or local - Bindings.xml calls them by exact global name,
-- and WoW's Key Bindings UI reads the BINDING_HEADER_*/BINDING_NAME_* globals
-- to build the labels shown in that menu.
BINDING_HEADER_XALSXPEDITEDROUTES = "Xal's Xpedited Routes"
BINDING_NAME_XALSXR_ROUTE_START = "Start/Update Route"
BINDING_NAME_XALSXR_ROUTE_STOP = "Stop Route"
BINDING_NAME_XALSXR_ROUTE_SKIP = "Skip Current Node"

function XalsXR_KeybindStartRoute()
    PathPlanner:PlotCourse()
end

function XalsXR_KeybindStopRoute()
    PathPlanner:CancelPath()
end

function XalsXR_KeybindSkipNode()
    PathPlanner:SkipPin()
end

SLASH_XALMORASXR1 = "/xxr"
SLASH_XALMORASXR2 = "/xalmoras"

local EXCLUDED_KEYS = {
    showPins = true, compassPosition = true, autoAdvanceDistance = true,
    pinStyle = true, pinSize = true, showHelperButton = true,
    helperButtonPosition = true, showGlow = true, proximityDistanceYards = true,
    arrowProgressColor = true, pinAlpha = true,
    duplicateDistanceYards = true, compassArrowStyle = true, arrowScale = true, tomtomSyncEnabled = true,
    freshnessMinutes = true, showHaulSummary = true, haulFramePosition = true,
    haulShowIcons = true, haulFontScale = true, haulGatherTimer = true, haulRouteTimer = true,
    arrowTextScale = true, dungeonCoords = true, dungeonButtonEnabled = true, dungeonButtonSide = true,
}

SlashCmdList["XALMORASXR"] = function(msg)
    if not XalsXRDB then return end
    
    local parts = {}
    for word in msg:gmatch("%S+") do
        table.insert(parts, word:lower())
    end
    
    local command = parts[1] or ""
    local subcommand = parts[2] or ""
    
    if command == "route" then
        if subcommand == "stop" or subcommand == "clear" then
            PathPlanner:CancelPath()
        elseif subcommand == "skip" then
            PathPlanner:SkipPin()
        elseif subcommand == "" then
            PathPlanner:PlotCourse()
        else
            print("|cff00ccffXal's XR: Unknown route command.|r")
            print("  |cff00ff00/xxr route|r - Starts/generates the optimal route.")
            print("  |cff00ff00/xxr route stop|r - Stops the active route.")
            print("  |cff00ff00/xxr route skip|r - Skips the current node.")
        end
    elseif command == "reset" then
        if subcommand == "all" then
            for key in pairs(XalsXRDB) do
                if not EXCLUDED_KEYS[key] then
                    XalsXRDB[key] = nil
                end
            end
            print("|cff00ccffXal's XR:|r All records have been deleted.")
            PathPlanner:CancelPath()
        else
            local currentMapID = C_Map.GetBestMapForUnit("player")
            if currentMapID and XalsXRDB[currentMapID] then
                XalsXRDB[currentMapID] = nil
                print("|cff00ccffXal's XR:|r Records for the current map have been deleted.")
                PathPlanner:CancelPath()
            else
                print("|cff00ccffXal's XR:|r There are no records for this map.")
            end
        end
        Markers:UpdatePins()
    elseif command == "cleanup" then
        local duplicatesRemoved = NodeLogger.RemoveDuplicates()
        print("|cff00ccffXal's XR:|r Cleanup complete. Removed |cffff9900" .. duplicatesRemoved .. "|r duplicates.")
        Markers:UpdatePins()
    elseif command == "stats" then
        local totalNodes = 0
        local mapCount = 0
        for mapID, nodes in pairs(XalsXRDB) do
            if not EXCLUDED_KEYS[mapID] and type(nodes) == "table" then
                mapCount = mapCount + 1
                totalNodes = totalNodes + #nodes
            end
        end
        print("|cff00ccffXal's XR:|r Stats: |cff00ff00" .. totalNodes .. "|r nodes across |cff00ff00" .. mapCount .. "|r maps.")
    elseif command == "arrowprogress" then
        XalsXRDB.arrowProgressColor = not (XalsXRDB.arrowProgressColor ~= false)
        print("|cff00ccffXal's XR:|r Arrow progress coloring is now " .. (XalsXRDB.arrowProgressColor and "|cff00ff00ON|r" or "|cffff9900OFF|r") .. ".")
    elseif command == "arrowstyle" then
        if Beacon.ARROW_STYLE_LABELS[subcommand] then
            XalsXRDB.compassArrowStyle = subcommand
            Beacon:ApplyArrowStyle()
            print("|cff00ccffXal's XR:|r Waypoint arrow style set to |cff00ff00" .. Beacon.ARROW_STYLE_LABELS[subcommand] .. "|r.")
        else
            print("|cff00ccffXal's XR:|r Current arrow style: |cff00ff00" .. (Beacon.ARROW_STYLE_LABELS[XalsXRDB.compassArrowStyle] or "Custom Arrow (default)") .. "|r")
            for _, key in ipairs(Beacon.ARROW_STYLES) do
                print("  |cff00ff00" .. key .. "|r - " .. Beacon.ARROW_STYLE_LABELS[key])
            end
        end
    elseif command == "arrowscale" then
        local n = tonumber(subcommand)
        if n and n >= 50 and n <= 150 then
            XalsXRDB.arrowScale = n / 100
            Beacon:ApplyArrowStyle()
            print("|cff00ccffXal's XR:|r Arrow scale set to |cff00ff00" .. n .. "%|r.")
        else
            print("|cff00ccffXal's XR:|r Current arrow scale: |cff00ff00" .. math.floor(((XalsXRDB.arrowScale or 1) * 100) + 0.5) .. "%|r")
            print("|cff888888/xxr arrowscale <50-150>|r - Sets the arrow's size as a percentage.")
        end
    elseif command == "tomtom" then
        XalsXRDB.tomtomSyncEnabled = not (XalsXRDB.tomtomSyncEnabled == true)
        if not XalsXRDB.tomtomSyncEnabled and TomTomBridge.ClearWaypoints then
            TomTomBridge:ClearWaypoints()
        end
        print("|cff00ccffXal's XR:|r TomTom sync is now " .. (XalsXRDB.tomtomSyncEnabled and "|cff00ff00ON|r" or "|cffff9900OFF|r") .. ". Does nothing if TomTom isn't installed.")
    elseif command == "dupdistance" then
        local n = tonumber(subcommand)
        if n and n >= 5 and n <= 50 then
            XalsXRDB.duplicateDistanceYards = n
            print("|cff00ccffXal's XR:|r Duplicate detection distance set to |cff00ff00" .. n .. " yd|r. Run /xxr cleanup to apply it to already-saved nodes.")
        else
            print("|cff00ccffXal's XR:|r Current duplicate detection distance: |cff00ff00" .. (XalsXRDB.duplicateDistanceYards or 15) .. " yd|r")
            print("|cff888888/xxr dupdistance <5-50>|r - Sets the distance in yards.")
        end
    elseif command == "freshness" then
        local n = tonumber(subcommand)
        if n and n >= 0 and n <= 60 then
            XalsXRDB.freshnessMinutes = n
            print("|cff00ccffXal's XR:|r Node freshness set to |cff00ff00" .. (n == 0 and "Off" or (n .. " min")) .. "|r.")
        else
            local current = XalsXRDB.freshnessMinutes or Helpers.DEFAULT_FRESHNESS_MINUTES
            print("|cff00ccffXal's XR:|r Current node freshness: |cff00ff00" .. (current == 0 and "Off" or (current .. " min")) .. "|r")
            print("|cff888888/xxr freshness <0-60>|r - Skips nodes gathered within this many minutes when building a route (0 = off).")
        end
    elseif command == "pinalpha" then
        local n = tonumber(subcommand)
        if n and n >= 30 and n <= 100 then
            XalsXRDB.pinAlpha = n / 100
            Markers:UpdatePins()
            print("|cff00ccffXal's XR:|r Marker opacity set to |cff00ff00" .. n .. "%|r.")
        else
            print("|cff00ccffXal's XR:|r Current marker opacity: |cff00ff00" .. math.floor(((XalsXRDB.pinAlpha or 1) * 100) + 0.5) .. "%|r")
            print("|cff888888/xxr pinalpha <30-100>|r - Sets marker opacity as a percentage.")
        end
    elseif command == "glow" then
        XalsXRDB.showGlow = not (XalsXRDB.showGlow ~= false)
        Markers:UpdatePins()
        print("|cff00ccffXal's XR:|r Marker glow is now " .. (XalsXRDB.showGlow and "|cff00ff00ON|r" or "|cffff9900OFF|r") .. ".")
    elseif command == "proximity" then
        -- Always on - this just sets the hide distance, doesn't toggle anything
        local n = tonumber(subcommand)
        if n and n >= 20 and n <= 500 then
            XalsXRDB.proximityDistanceYards = n
            print("|cff00ccffXal's XR:|r Marker hide distance set to |cff00ff00" .. n .. " yd|r.")
        else
            print("|cff00ccffXal's XR:|r Current marker hide distance: |cff00ff00" .. (XalsXRDB.proximityDistanceYards or 200) .. " yd|r")
            print("|cff888888/xxr proximity <20-500>|r - Sets the distance in yards.")
        end
    elseif command == "pinsize" then
        local n = tonumber(subcommand)
        if n and n >= 8 and n <= 28 then
            n = math.floor(n / 2 + 0.5) * 2
            XalsXRDB.pinSize = n
            Markers:UpdatePins()
            print("|cff00ccffXal's XR:|r Marker size set to |cff00ff00" .. n .. "px|r.")
        else
            print("|cff00ccffXal's XR:|r Current marker size: |cff00ff00" .. (XalsXRDB.pinSize or 14) .. "px|r")
            print("|cff888888/xxr pinsize <8-28>|r - Sets the marker size in pixels (even numbers).")
        end
    elseif command == "pinstyle" then
        if subcommand == "" then
            print("|cff00ccffXal's XR:|r Current marker style: |cff00ff00" .. (Markers.PIN_STYLE_LABELS[XalsXRDB.pinStyle] or "Hollow X") .. "|r")
            print("|cff888888Available styles:|r")
            for _, key in ipairs(Markers.PIN_STYLES) do
                print("  |cff00ff00" .. key .. "|r - " .. Markers.PIN_STYLE_LABELS[key])
            end
        elseif Markers.PIN_STYLE_LABELS[subcommand] then
            XalsXRDB.pinStyle = subcommand
            Markers:UpdatePins()
            print("|cff00ccffXal's XR:|r Marker style set to |cff00ff00" .. Markers.PIN_STYLE_LABELS[subcommand] .. "|r.")
        else
            print("|cff00ccffXal's XR: Unknown marker style '" .. subcommand .. "'. Type /xxr pinstyle to see available styles.|r")
        end
    elseif command == "button" then
        if subcommand == "reset" then
            if QuickButton and QuickButton.ResetPosition then
                QuickButton:ResetPosition()
                print("|cff00ccffXal's XR:|r Helper button position reset.")
            end
        else
            if QuickButton and QuickButton.Toggle then
                QuickButton:Toggle()
            end
        end
    elseif command == "options" or command == "config" or command == "settings" then
        if SettingsPanel and SettingsPanel.Open then
            SettingsPanel:Open()
        end
    elseif command == "haul" then
        if subcommand == "off" then
            XalsXRDB.showHaulSummary = false
            print("|cff00ccffXal's XR:|r Haul summary popup is now |cffff9900OFF|r.")
        elseif subcommand == "on" then
            XalsXRDB.showHaulSummary = true
            print("|cff00ccffXal's XR:|r Haul summary popup is now |cff00ff00ON|r.")
        elseif RunTracker and RunTracker.ShowHaulCommand then
            RunTracker:ShowHaulCommand()
        end
    elseif command == "dungeon" then
        if DungeonNav and DungeonNav.Command then
            DungeonNav:Command(table.concat(parts, " ", 2))
        end
    elseif command == "help" then
        print("|cff00ccffXal's Xpedited Routes - Chat commands:|r")
        print("  |cff00ff00/xxr|r - Shows or hides the gathering icons on the maps.")
        print("  |cff00ff00/xxr route|r - Starts/generates the optimal gathering route for the zone.")
        print("  |cff00ff00/xxr route stop|r - Stops the active route and hides the compass.")
        print("  |cff00ff00/xxr route skip|r - Skips the current node and moves to the next.")
        print("  |cff00ff00/xxr stats|r - Shows the total number of saved nodes.")
        print("  |cff00ff00/xxr cleanup|r - Cleans up duplicate nodes in the database.")
        print("  |cff00ff00/xxr reset|r - Removes recorded nodes for the current zone.")
        print("  |cff00ff00/xxr reset all|r - Removes all nodes from the addon.")
        print("  |cff00ff00/xxr pinstyle|r - Lists available map marker styles.")
        print("  |cff00ff00/xxr pinstyle <name>|r - Sets the map marker style (hollowx or star).")
        print("  |cff00ff00/xxr pinsize <8-28>|r - Sets the map marker size in pixels.")
        print("  |cff00ff00/xxr pinalpha <30-100>|r - Sets marker opacity as a percentage.")
        print("  |cff00ff00/xxr glow|r - Toggles the colored glow behind markers.")
        print("  |cff00ff00/xxr proximity <20-500>|r - Sets the distance (yards) at which markers hide - always on.")
        print("  |cff00ff00/xxr dupdistance <5-50>|r - Sets how close two nodes must be to count as the same one.")
        print("  |cff00ff00/xxr freshness <0-60>|r - Skips nodes gathered within this many minutes when building a route (0 = off).")
        print("  |cff00ff00/xxr arrowstyle <name>|r - Sets the compass arrow style (custom3, custom4, blizzard).")
        print("  |cff00ff00/xxr arrowscale <50-150>|r - Sets the arrow's size as a percentage.")
        print("  |cff00ff00/xxr tomtom|r - Toggles syncing TomTom's arrow to your route (off by default, does nothing without TomTom installed).")
        print("  |cff00ff00/xxr arrowprogress|r - Toggles green/red arrow coloring based on whether you're closing in.")
        print("  |cff00ff00/xxr button|r - Shows or hides the floating helper button.")
        print("  |cff00ff00/xxr button reset|r - Resets the helper button to its default position.")
        print("  |cff00ff00/xxr haul|r - Opens the Gather Tally window (also on the Gather button).")
        print("  |cff00ff00/xxr haul on|r / |cff00ff00off|r - Toggles the live Gather Tally during routes (also in Options).")
        print("  |cff00ff00/xxr dungeon|r - |cff888888(Xperimental)|r Waypoints to a Season 2 dungeon entrance. Type it for the list.")
        print("  |cff00ff00/xxr options|r - Opens the settings panel.")
        print("|cff888888(You can also type /xalmoras instead of /xxr. If TomTom is installed, generating a route automatically pops up a copy-paste /way list for it - no separate command needed.)|r")
    else
        -- Toggle visibility
        XalsXRDB.showPins = not XalsXRDB.showPins
        if XalsXRDB.showPins then
            print("|cff00ccffXal's XR:|r Icons SHOWN.")
        else
            print("|cff00ccffXal's XR:|r Icons HIDDEN.")
        end
        Markers:UpdatePins()
    end
end
