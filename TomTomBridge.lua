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

local currentWaypointUID = nil

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

    local label = (node.type == "mine" and "Xal's Mining" or "Xal's Herbalism")
    local ok, uidOrErr = pcall(function()
        return TomTom:AddWaypoint(mapID, node.x, node.y, {
            title = label,
            persistent = false,
            minimap = true,
            world = true,
            silent = true,
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
