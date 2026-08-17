-- TomTomBridge.lua
-- Xal's Xpedited Routes
--
-- If TomTom is installed, this keeps TomTom's crazy arrow pointed at whatever
-- stop our own route considers "current" - updating it automatically every
-- time our route advances, so TomTom's arrow steps through the whole route in
-- order, the same way this addon's own compass does.
--
-- This isn't TomTom "queueing" our stops on its own - its crazy arrow is built
-- around a single active target (see TomTom_CrazyArrow.lua's SetCrazyArrow),
-- not an internal ordered list it steps through by itself. So getting genuine
-- multi-stop behavior out of it means we drive the sequence ourselves and just
-- keep re-pointing TomTom's one active waypoint at our current stop, rather
-- than dumping every stop in at once and hoping TomTom sorts out the order.
--
-- Calls TomTom's own public API (AddWaypoint/RemoveWaypoint) - a function it
-- exposes specifically for other addons to use, same category as this addon
-- calling HereBeDragons' API elsewhere. No code of TomTom's is used or bundled.
-- One-way: only ever pushes to TomTom, never reads anything back from it.
local addonName, addonTable = ...
local TomTomBridge = addonTable.TomTomBridge
local Engine = addonTable.Engine

local currentWaypointUID = nil

-- How far (in real yards) to nudge the coordinate handed to TomTom away from
-- the node's actual position, purely so its arrow doesn't render on top of
-- the node model. Our own route logic (auto-advance, clustering, everything
-- else) never sees this - it's applied only to what TomTom gets told.
local TOMTOM_OFFSET_YARDS = 15

-- Converts that yard offset into this zone's actual map-fraction scale via
-- HereBeDragons' real per-zone size (GetZoneSize) - a flat fraction offset
-- would be a wildly different real distance in a huge zone vs a small one,
-- so it has to go through the zone's own scale, not a guessed constant.
local function OffsetForTomTom(mapID, x, y)
    if not (Engine.HBD and Engine.HBD.GetZoneSize) then return x, y end
    local widthYards, heightYards = Engine.HBD:GetZoneSize(mapID)
    if not widthYards or widthYards <= 0 or not heightYards or heightYards <= 0 then
        return x, y
    end
    local dx = TOMTOM_OFFSET_YARDS / widthYards
    local dy = TOMTOM_OFFSET_YARDS / heightYards
    return math.min(x + dx, 1), math.min(y + dy, 1)
end

-- Shown every time TomTom sync gets turned on (settings checkbox or /xxr
-- tomtom) - not just once ever, per direct request 2026-08-17. We can't set
-- either of these ourselves: TomTom's arrow scale and "Arrival Distance"
-- (when it switches to the downward "arrived" arrow) both come straight off
-- the player's own TomTom profile with no per-addon override in its public
-- API (confirmed directly from TomTom's real source, TomTom_CrazyArrow.lua
-- and TomTom_Config.lua) - so the only thing we can do is point at TomTom's
-- own options and suggest the values that keep its arrow from sitting on
-- top of / hiding the actual node once you arrive.
StaticPopupDialogs["XALXR_TOMTOM_TIP"] = {
    text = "TomTom sync is on. Its arrow is TomTom's own, so this addon can't size it for you - but two tweaks in TomTom's own options (|cff00ff00/tomtom|r) help keep it from covering up the node when you arrive:\n\n|cffffcc00Scale|r - a smaller arrow overshadows less.\n|cffffcc00Arrival Distance|r - raise it a bit so the arrow switches away before you're standing right on top of the node.",
    button1 = "Got it",
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function TomTomBridge:ShowIntegrationTip()
    StaticPopup_Show("XALXR_TOMTOM_TIP")
end

-- True once this addon has successfully handed TomTom an active waypoint.
-- Used to decide whether our own compass should show itself, so the two
-- arrows don't both display for the same destination at once.
function TomTomBridge:IsActive()
    return currentWaypointUID ~= nil
end

-- Removes whatever waypoint this addon currently has active in TomTom. Safe to
-- call even if TomTom isn't installed or nothing was ever set.
function TomTomBridge:ClearWaypoints()
    if currentWaypointUID and TomTom and TomTom.RemoveWaypoint then
        pcall(function() TomTom:RemoveWaypoint(currentWaypointUID) end)
    end
    currentWaypointUID = nil
end

-- Called whenever our own route's current target changes - on generating a
-- route, advancing to the next stop, or skipping one. Points TomTom's crazy
-- arrow at that same stop. Does nothing if TomTom isn't installed.
function TomTomBridge:SyncCurrentStop(node, mapID)
    self:ClearWaypoints()

    -- TomTom only has one arrow, period - unlike our own two now-independent
    -- Beacon/DungeonBeacon widgets, there's nothing to split here. Dungeon
    -- nav supersedes while it has an active destination, same rule as
    -- everywhere else; ClearWaypoints() above already dropped our own
    -- gathering waypoint, so TomTomBridge:IsActive() correctly reports
    -- false and PathPlanner falls back to showing its own gathering arrow
    -- instead. Flagged live 2026-08-17.
    if addonTable.DungeonNav and addonTable.DungeonNav.activeTarget then
        return
    end

    if not TomTom then
        print("|cff888888Xal's XR:|r (TomTom not detected - global TomTom table doesn't exist)")
        return
    end
    if not TomTom.AddWaypoint then
        print("|cffff9900Xal's XR:|r TomTom detected, but TomTom.AddWaypoint doesn't exist - its API may have changed.")
        return
    end
    if not node or not mapID then
        print("|cffff9900Xal's XR:|r TomTom sync called with no current stop/map to point at.")
        return
    end

    local TOMTOM_LABELS = { mine = "Xal's Mining", herb = "Xal's Herbalism", lumber = "Xal's Lumberjacking", mixed = "Xal's Gathering" }
    local label = TOMTOM_LABELS[node.type] or "Xal's Gathering"
    local tx, ty = OffsetForTomTom(mapID, node.x, node.y)
    local ok, uidOrErr = pcall(function()
        return TomTom:AddWaypoint(mapID, tx, ty, {
            title = label,
            persistent = false,
            minimap = true,
            world = true,
            silent = true,
            crazy = true,
        })
    end)
    if ok and uidOrErr then
        currentWaypointUID = uidOrErr
        print("|cff00ccffXal's XR:|r TomTom waypoint set: " .. label)
    elseif ok then
        print("|cffff9900Xal's XR:|r TomTom:AddWaypoint() ran without error but returned nothing.")
    else
        print("|cffcc0000Xal's XR:|r TomTom:AddWaypoint() errored: " .. tostring(uidOrErr))
    end
end
