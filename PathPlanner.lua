-- PathPlanner.lua
local addonName, addonTable = ...
local PathPlanner = addonTable.PathPlanner
local Engine = addonTable.Engine
local Helpers = addonTable.Helpers

PathPlanner.currentPath = nil
PathPlanner.stopCursor = nil
PathPlanner.pathMapID = nil
PathPlanner.pathTypeFilter = nil -- nil for an unfiltered/mixed route, or a set table like {mine=true, herb=true} to restrict to specific types
PathPlanner.paused = false -- true while outside the route's zone (see CheckZone)

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

-- Sanity cap on the RAW normalized map-coordinate distance between two
-- nodes, checked BEFORE trusting HereBeDragons' yard-converted distance.
-- HBD's per-zone calibration is missing or off for some zones - if it ever
-- misreports two nodes that are actually far apart as "within grouping
-- radius," clustering would silently merge a real, distant node into
-- another cluster so it's never separately routed to again (confirmed live
-- 2026-08-10: a route claimed a 4-node stop 2000+ yards away with nothing
-- actually there). Two nodes more than 15% of the map's width/height apart
-- being genuinely within a couple hundred real yards of each other would
-- require an implausibly huge zone, so this cap can only ever make grouping
-- LESS aggressive than intended (nodes that should group don't, in an
-- oversized zone) - never merge nodes that shouldn't be (nodes vanish).
local MAX_CLUSTER_COORD_DELTA = 0.15

-- Groups nearby nodes into clusters before the route is built, so a dense
-- patch of nodes becomes ONE stop on the route instead of a separate stop
-- for each individual node. Anchor-based (not chained): a node only joins a
-- cluster if it's within `radius` of that cluster's ORIGINAL node, never a
-- later member. Chaining (A links to B, B links to C) would let a cluster
-- stretch across a large area if nodes happen to line up like a trail -
-- anchoring keeps every cluster visually tight, matching what the player
-- would actually see together on screen. The tradeoff: two clusters that
-- are close to each other but whose anchors are just outside `radius` stay
-- separate - an acceptable, predictable edge case.
local function BuildClusters(mapID, stops, radius)
    local clusters = {}
    for _, stop in ipairs(stops) do
        local joined = nil
        -- Lumber nodes never join (or get joined into) a cluster - they're
        -- spread out enough in practice that grouping doesn't help yet,
        -- unlike mine/herb which are often genuinely dense. Each lumber
        -- node always gets its own stop. Confirmed 2026-08-17; revisit if
        -- lumber node density ever changes.
        if stop.type ~= "lumber" then
            for _, cluster in ipairs(clusters) do
                if cluster.type ~= "lumber" then
                    local coordDeltaX, coordDeltaY = cluster.anchor.x - stop.x, cluster.anchor.y - stop.y
                    local coordDelta = math.sqrt(coordDeltaX * coordDeltaX + coordDeltaY * coordDeltaY)
                    if coordDelta <= MAX_CLUSTER_COORD_DELTA
                        and DistanceBetween(mapID, cluster.anchor.x, cluster.anchor.y, stop.x, stop.y) <= radius then
                        joined = cluster
                        break
                    end
                end
            end
        end
        if joined then
            table.insert(joined.members, stop)
            if stop.type ~= joined.type then
                joined.type = "mixed"
            end
        else
            table.insert(clusters, { anchor = stop, x = stop.x, y = stop.y, type = stop.type, members = { stop } })
        end
    end
    return clusters
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
    -- given) a hard restriction to a specific set of types - used by the
    -- floating helper button's per-profession buttons. typeFilter is either
    -- nil (no restriction beyond known professions) or a set table like
    -- {mine=true, herb=true} naming exactly which types are allowed.
    local knowsMining = Helpers.HasGatheringProfession(Helpers.MINING_SKILL_LINE, Helpers.MINING_NAMES)
    local knowsHerbs = Helpers.HasGatheringProfession(Helpers.HERBALISM_SKILL_LINE, Helpers.HERBALISM_NAMES)
    local knowsLumber = Helpers.HasLumberjacking()

    -- Safety net: same detection-glitch guard as Markers.lua - "knows none of
    -- the three" is far more likely stale/uncached detection than reality, so
    -- don't let it alone block routing (typeFilter still applies below).
    if not knowsMining and not knowsHerbs and not knowsLumber then
        knowsMining, knowsHerbs, knowsLumber = true, true, true
    end

    local excludeMining = not knowsMining or (typeFilter and not typeFilter.mine)
    local excludeHerbs = not knowsHerbs or (typeFilter and not typeFilter.herb)
    local excludeLumber = not knowsLumber or (typeFilter and not typeFilter.lumber)

    if excludeMining and excludeHerbs and excludeLumber then
        print("|cffcc0000Xal's XR:|r No routable node types for this character right now (check your known professions).|r")
        return
    end

    -- Nodes previously flagged by CheckZone as requiring you to leave this
    -- zone to reach (a real boundary node, or just a bad/unreachable
    -- coordinate - either way, permanently excluded from routing).
    local boundaryList = XalsXRDB.boundaryNodes and XalsXRDB.boundaryNodes[mapID]
    local function IsBoundaryNode(node)
        if not boundaryList then return false end
        for _, bad in ipairs(boundaryList) do
            if bad.x == node.x and bad.y == node.y then
                return true
            end
        end
        return false
    end

    local stops = {}
    for _, node in ipairs(XalsXRDB[mapID]) do
        local excluded = (node.type == "mine" and excludeMining) or (node.type == "herb" and excludeHerbs)
            or (node.type == "lumber" and excludeLumber)
        if not excluded and not IsBoundaryNode(node) then
            table.insert(stops, { x = node.x, y = node.y, type = node.type, lastGathered = node.lastGathered })
        end
    end

    if #stops == 0 then
        print("|cff00ccffXal's XR:|r No nodes left to route to in this zone after applying your route filters.")
        return
    end

    -- Skip nodes gathered too recently to have plausibly respawned yet (see
    -- Helpers.IsNodeRecentlyGathered). Same safety-net shape as the profession
    -- filter above: if that would leave nothing to route to, fall back to
    -- routing everything rather than returning an empty route.
    local freshnessMinutes = Helpers.GetFreshnessMinutes()
    local freshStops = {}
    for _, stop in ipairs(stops) do
        if not Helpers.IsNodeRecentlyGathered(stop, freshnessMinutes) then
            table.insert(freshStops, stop)
        end
    end
    if #freshStops > 0 then
        stops = freshStops
    end

    local groupingRadius = (XalsXRDB and XalsXRDB.groupingDistanceYards) or 240
    local clusters = BuildClusters(mapID, stops, groupingRadius)

    local route = BuildGreedyOrder(mapID, startX, startY, clusters)
    route = ImproveWithTwoOpt(mapID, startX, startY, route)

    self.currentPath = route
    self.stopCursor = 1
    self.pathMapID = mapID
    self.pathTypeFilter = typeFilter

    -- A successfully generated route is the start of a "run" - begin the
    -- gathering haul tally (a no-op if a run is already active from a re-plot).
    if addonTable.RunTracker and addonTable.RunTracker.StartRun then
        addonTable.RunTracker:StartRun()
    end

    local typeLabel = ""
    if typeFilter then
        local names = {}
        if typeFilter.mine then table.insert(names, "Mining") end
        if typeFilter.herb then table.insert(names, "Herbalism") end
        if typeFilter.lumber then table.insert(names, "Lumberjacking") end
        if #names > 0 then typeLabel = table.concat(names, " + ") .. " " end
    end
    print("|cff00ccffXal's XR:|r " .. typeLabel .. "gathering route generated with |cff00ff00" .. #route .. "|r stops (|cff00ff00" .. #stops .. "|r nodes).")

    if addonTable.Markers.UpdatePins then
        addonTable.Markers:UpdatePins()
    end

    -- If TomTom is installed AND you've opted into this in Settings ->
    -- Integrations, point its crazy arrow at our current stop - kept in sync as
    -- the route advances (see TomTomBridge.lua). Off by default. Checked BEFORE
    -- showing our own compass, since if TomTom is handling it, showing our own
    -- arrow too would just be a second arrow pointing at the same thing.
    if XalsXRDB and XalsXRDB.tomtomSyncEnabled and addonTable.TomTomBridge.SyncCurrentStop then
        addonTable.TomTomBridge:SyncCurrentStop(self:CurrentStop(), self.pathMapID)
    end

    if addonTable.Beacon.Show then
        if not (addonTable.TomTomBridge.IsActive and addonTable.TomTomBridge:IsActive()) then
            addonTable.Beacon:Show()
        else
            addonTable.Beacon:Hide()
        end
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
        if XalsXRDB and XalsXRDB.tomtomSyncEnabled and addonTable.TomTomBridge.SyncCurrentStop then
            addonTable.TomTomBridge:SyncCurrentStop(self:CurrentStop(), self.pathMapID)
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
    self.paused = false
    
    if addonTable.Beacon.Hide then
        addonTable.Beacon:Hide()
    end
    if addonTable.Markers.UpdatePins then
        addonTable.Markers:UpdatePins()
    end
    if addonTable.TomTomBridge.ClearWaypoints then
        addonTable.TomTomBridge:ClearWaypoints()
    end

    -- Ending a run: show the gathering haul summary (if anything was gathered).
    if addonTable.RunTracker and addonTable.RunTracker.EndRun then
        addonTable.RunTracker:EndRun()
    end
end

-- Pauses/resumes the route depending on whether the player is currently in
-- the zone it was plotted for - rather than cancelling outright, since
-- briefly clipping a zone boundary (flying along a coastline, a dip near a
-- capital city, etc. - none of which show up as a visible line anywhere in
-- the game's own UI) shouldn't force a full replot. currentPath/stopCursor/
-- pathMapID all stay intact while paused; the gathering haul tally (started
-- by RunTracker) is untouched too, since the run hasn't actually ended.
-- Called every tick from Beacon:RunUpdateLoop() AND from the zone-change
-- event in Engine.lua - either one catches it, whichever fires first.
function PathPlanner:CheckZone()
    if not self:InProgress() and not self.paused then return end

    local currentMapID = C_Map.GetBestMapForUnit("player")
    if not currentMapID then return end

    if currentMapID ~= self.pathMapID then
        if not self.paused then
            self.paused = true

            -- The stop you were actually approaching when this triggered
            -- requires physically crossing the zone boundary to reach - mark
            -- every node in it as excluded so it's never offered as a route
            -- stop again, then skip past it immediately instead of leaving
            -- you stuck bouncing pause/resume against the same stop forever.
            local target = self:CurrentStop()
            if target and self.pathMapID then
                XalsXRDB.boundaryNodes = XalsXRDB.boundaryNodes or {}
                XalsXRDB.boundaryNodes[self.pathMapID] = XalsXRDB.boundaryNodes[self.pathMapID] or {}
                local excluded = XalsXRDB.boundaryNodes[self.pathMapID]
                local members = target.members or { target }
                for _, member in ipairs(members) do
                    table.insert(excluded, { x = member.x, y = member.y })
                end
                print("|cffff9900Xal's XR:|r That stop requires crossing the zone boundary to reach - excluding it from future routes and skipping it now.")
            end

            if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
                RaidNotice_AddMessage(RaidWarningFrame, "Xal's XR: Route paused - outside route zone", ChatTypeInfo["RAID_WARNING"])
            end
            if addonTable.Beacon and addonTable.Beacon.Hide then
                addonTable.Beacon:Hide()
            end
            self:SkipPin()
        end
    else
        if self.paused then
            self.paused = false
            print("|cff00ff00Xal's XR:|r Back in the route's zone - resuming.")
            if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
                RaidNotice_AddMessage(RaidWarningFrame, "Xal's XR: Route resumed", ChatTypeInfo["RAID_WARNING"])
            end
            if addonTable.Beacon and addonTable.Beacon.Show then
                addonTable.Beacon:Show()
            end
        end
    end
end

-- Old name kept as an alias - Engine.lua's zone-change event dispatcher
-- calls this directly.
function PathPlanner:HandleZoneChange()
    self:CheckZone()
end
