-- PathPlanner.lua
local addonName, addonTable = ...
local PathPlanner = addonTable.PathPlanner
local Engine = addonTable.Engine
local Helpers = addonTable.Helpers

PathPlanner.currentPath = nil
PathPlanner.stopCursor = nil
PathPlanner.pathMapID = nil
PathPlanner.pathTypeFilter = nil -- "mine", "herb", or nil for an unfiltered/mixed route

-- Route construction: a greedy nearest-first build, then a 2-opt local-search
-- pass that tries to shorten the result further. Greedy-nearest alone can lock
-- in a bad early choice it can never undo (e.g. detouring to a close node that
-- strands you far from everything else); 2-opt fixes exactly that class of
-- mistake by testing whether reversing some stretch of the route shortens it,
-- and keeping the reversal when it does. This runs once at route generation,
-- not per-frame, so the extra pass is cheap relative to how it's used.
local MAX_TWO_OPT_NODES = 60 -- skip the improvement pass above this size to keep generation snappy
local MAX_TWO_OPT_PASSES = 8

local function DistanceBetween(mapID, ax, ay, bx, by)
    if Engine.HBD then
        local d = Engine.HBD:GetZoneDistance(mapID, ax, ay, bx, by)
        if d then return d end
    end
    local dx, dy = bx - ax, by - ay
    return math.sqrt(dx * dx + dy * dy) * Helpers.FALLBACK_YARDS_PER_UNIT
end

-- Builds an initial ordering by always stepping to whichever remaining stop is
-- closest to wherever the path currently is.
local function BuildGreedyOrder(mapID, startX, startY, stops)
    local pool = {}
    for i, stop in ipairs(stops) do pool[i] = stop end

    local order = {}
    local atX, atY = startX, startY

    while #pool > 0 do
        local nearestSlot, nearestDist = 1, math.huge
        for slot, candidate in ipairs(pool) do
            local d = DistanceBetween(mapID, atX, atY, candidate.x, candidate.y)
            if d < nearestDist then
                nearestDist, nearestSlot = d, slot
            end
        end
        local chosen = table.remove(pool, nearestSlot)
        table.insert(order, chosen)
        atX, atY = chosen.x, chosen.y
    end

    return order
end

-- Tries reversing every possible stretch order[i..j] and keeps the reversal
-- whenever it shortens the route. Only the two boundary edges of a reversal
-- actually change length (everything inside the reversed stretch is walked in
-- the opposite direction but covers the same ground), so each candidate swap is
-- checked with a handful of distance lookups rather than re-measuring the whole
-- route.
local function ImproveWithTwoOpt(mapID, startX, startY, order)
    local n = #order
    if n < 3 or n > MAX_TWO_OPT_NODES then return order end

    local function pointAt(index)
        if index == 0 then return startX, startY end
        return order[index].x, order[index].y
    end

    for pass = 1, MAX_TWO_OPT_PASSES do
        local changedThisPass = false

        for i = 1, n - 1 do
            local prevX, prevY = pointAt(i - 1)
            for j = i + 1, n do
                local nextIndex = j + 1
                if nextIndex <= n then
                    local ix, iy = pointAt(i)
                    local jx, jy = pointAt(j)
                    local afterX, afterY = pointAt(nextIndex)

                    local currentCost = DistanceBetween(mapID, prevX, prevY, ix, iy)
                        + DistanceBetween(mapID, jx, jy, afterX, afterY)
                    local swappedCost = DistanceBetween(mapID, prevX, prevY, jx, jy)
                        + DistanceBetween(mapID, ix, iy, afterX, afterY)

                    if swappedCost < currentCost - 0.01 then
                        local lo, hi = i, j
                        while lo < hi do
                            order[lo], order[hi] = order[hi], order[lo]
                            lo, hi = lo + 1, hi - 1
                        end
                        changedThisPass = true
                    end
                end
            end
        end

        if not changedThisPass then break end
    end

    return order
end

function PathPlanner:Init()
    -- No special initialization needed for now
end

function PathPlanner:InProgress()
    return self.currentPath ~= nil and self.stopCursor ~= nil and self.stopCursor <= #self.currentPath
end

function PathPlanner:CurrentStop()
    if self:InProgress() then
        return self.currentPath[self.stopCursor]
    end
    return nil
end

function PathPlanner:PlotCourse(typeFilter)
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID or not XalsXRDB or not XalsXRDB[mapID] or #XalsXRDB[mapID] == 0 then
        print("|cff00ccffXal's XR:|r No nodes saved for this map to build a route.")
        return
    end

    local startX, startY
    if Engine.HBD then
        startX, startY = Engine.HBD:GetPlayerZonePosition()
    end
    if not startX or not startY then
        local position = C_Map.GetPlayerMapPosition(mapID, "player")
        if position then
            startX, startY = position:GetXY()
        end
    end
    if not startX or not startY then
        print("|cffcc0000Xal's XR: Could not get the player's position to start the route.|r")
        return
    end

    -- Restrict to node types this character can actually gather, plus (if
    -- given) a hard restriction to a single type - used by the floating
    -- helper button's per-profession buttons.
    local knowsMining = Helpers.HasGatheringProfession(Helpers.MINING_SKILL_LINE, Helpers.MINING_NAMES)
    local knowsHerbs = Helpers.HasGatheringProfession(Helpers.HERBALISM_SKILL_LINE, Helpers.HERBALISM_NAMES)

    -- Safety net: same detection-glitch guard as Markers.lua - a "knows neither"
    -- reading is far more likely stale/uncached profession data than reality, so
    -- don't let it alone block routing (typeFilter still applies below).
    if not knowsMining and not knowsHerbs then
        knowsMining, knowsHerbs = true, true
    end

    local excludeMining = not knowsMining or typeFilter == "herb"
    local excludeHerbs = not knowsHerbs or typeFilter == "mine"

    if excludeMining and excludeHerbs then
        print("|cffcc0000Xal's XR:|r No routable node types for this character right now (check your known professions).|r")
        return
    end

    local stops = {}
    for _, node in ipairs(XalsXRDB[mapID]) do
        local excluded = (node.type == "mine" and excludeMining) or (node.type == "herb" and excludeHerbs)
        if not excluded then
            table.insert(stops, { x = node.x, y = node.y, type = node.type })
        end
    end

    if #stops == 0 then
        print("|cff00ccffXal's XR:|r No nodes left to route to in this zone after applying your route filters.")
        return
    end

    local route = BuildGreedyOrder(mapID, startX, startY, stops)
    route = ImproveWithTwoOpt(mapID, startX, startY, route)

    self.currentPath = route
    self.stopCursor = 1
    self.pathMapID = mapID
    self.pathTypeFilter = typeFilter

    local typeLabel = (typeFilter == "mine" and "Mining ") or (typeFilter == "herb" and "Herbalism ") or ""
    print("|cff00ccffXal's XR:|r " .. typeLabel .. "gathering route generated with |cff00ff00" .. #route .. "|r nodes.")

    if addonTable.Beacon.Show then
        addonTable.Beacon:Show()
    end

    if addonTable.Markers.UpdatePins then
        addonTable.Markers:UpdatePins()
    end

    -- If TomTom is installed, point its crazy arrow at our current stop - kept
    -- in sync as the route advances (see TomTomBridge.lua).
    if addonTable.TomTomBridge.SyncCurrentStop then
        addonTable.TomTomBridge:SyncCurrentStop(self:CurrentStop())
    end
end

function PathPlanner:StepForward()
    if not self:InProgress() then return end
    
    self.stopCursor = self.stopCursor + 1
    if self.stopCursor > #self.currentPath then
        print("|cff00ccffXal's XR:|r You have completed the gathering route!")
        self:CancelPath()
    else
        print("|cff00ccffXal's XR:|r Next node: |cff00ff00" .. self.stopCursor .. "/" .. #self.currentPath .. "|r")
        if addonTable.Beacon.UpdateTarget then
            addonTable.Beacon:Retarget()
        end
        if addonTable.Markers.UpdatePins then
            addonTable.Markers:UpdatePins()
        end
        if addonTable.TomTomBridge.SyncCurrentStop then
            addonTable.TomTomBridge:SyncCurrentStop(self:CurrentStop())
        end
    end
end

function PathPlanner:SkipPin()
    if not self:InProgress() then return end
    print("|cff00ccffXal's XR:|r Node skipped.")
    self:StepForward()
end

function PathPlanner:CancelPath()
    self.currentPath = nil
    self.stopCursor = nil
    self.pathMapID = nil
    self.pathTypeFilter = nil
    
    if addonTable.Beacon.Hide then
        addonTable.Beacon:Hide()
    end
    if addonTable.Markers.UpdatePins then
        addonTable.Markers:UpdatePins()
    end
    if addonTable.TomTomBridge.ClearWaypoints then
        addonTable.TomTomBridge:ClearWaypoints()
    end
end

function PathPlanner:HandleZoneChange()
    -- If we changed zones, cancel the route to avoid pointing at incorrect coordinates
    if self:InProgress() then
        local currentMapID = C_Map.GetBestMapForUnit("player")
        if currentMapID ~= self.pathMapID then
            print("|cff00ccffXal's XR:|r Zone change detected. Route deactivated.")
            self:CancelPath()
        end
    end
end
