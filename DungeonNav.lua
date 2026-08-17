-- DungeonNav.lua
-- Xal's Xpedited Routes
--
-- Xperimental (WIP): sets a navigation waypoint to a Mythic+ dungeon's entrance.
-- Where the entrance has been *discovered*, it reads the game's own dungeon-entrance
-- data, so those coordinates are always exactly right. A small hand-kept table is
-- the fallback for entrances you haven't visited yet - and it is deliberately left
-- empty until each coordinate is verified in-game, because a wrong waypoint is worse
-- than none. Waypoints use Blizzard's built-in super-tracked map pin (the on-screen
-- distance indicator), and mirror to TomTom if that sync option is on.
--
-- Retail-only: Season 2 Mythic+ and the C_Map.SetUserWaypoint / C_EncounterJournal
-- APIs this leans on don't exist on the Classic clients. Everything here is guarded
-- and pcall-wrapped, so on any client where an API is missing it just prints a note
-- and does nothing - it can never error on load.
local addonName, addonTable = ...
local DungeonNav = addonTable.DungeonNav

-- Midnight Season 2 (patch 12.1) Mythic+ pool. `name` is matched against the live
-- dungeon-entrance data the game returns for discovered instances. uiMapID/x/y are
-- an optional fallback for undiscovered entrances - filled in only once verified.
-- Coords are normalized (0-1) map positions. Every uiMapID + coordinate below is
-- taken straight from Wowhead's own "/way #mapID x y" entrance data (authoritative).
-- The live discovered-entrance data still overrides these when available, and
-- "/xxr dungeon set" can pin any of them exactly in-game.
DungeonNav.SEASON2 = {
    { name = "Altar of Fangs",       uiMapID = 2509, x = 0.472, y = 0.676 }, -- The Coiled Isle (12.1)
    { name = "Murder Row",           uiMapID = 2393, x = 0.562, y = 0.611 }, -- Silvermoon City
    { name = "Den of Nalorakk",      uiMapID = 2437, x = 0.314, y = 0.839 }, -- Zul'Aman
    { name = "The Blinding Vale",    uiMapID = 2576, x = 0.278, y = 0.779 }, -- Harandar
    { name = "Voidscar Arena",       uiMapID = 2444, x = 0.536, y = 0.344 }, -- Voidstorm
    { name = "Ruby Life Pools",      uiMapID = 2022, x = 0.600, y = 0.758,
      portal = { uiMapID = 2266, x = 0.761, y = 0.616 } }, -- The Waking Shores / Millennia's Threshold
    { name = "Temple of Sethraliss", uiMapID = 864,  x = 0.519, y = 0.267,
      portal = { uiMapID = 2266, x = 0.701, y = 0.714 } }, -- Vol'dun / Millennia's Threshold
    { name = "King's Rest",          uiMapID = 862,  x = 0.376, y = 0.394,
      portal = { uiMapID = 2266, x = 0.733, y = 0.480 } }, -- Zuldazar / Millennia's Threshold
}

-- The instanced portal room in Silvermoon City ("Millennia's Threshold"), reached via
-- the Timeways portal, and the portal's own position in Silvermoon. Dungeons above
-- with a `.portal` field can be reached this way as an alternative to the real
-- open-world entrance: /xxr dungeon <name> points at the Silvermoon hub portal first,
-- then auto-switches to that dungeon's specific portal once you actually step inside
-- Millennia's Threshold (uiMapID 2266, confirmed via /run print(C_Map.GetBestMapForUnit).
DungeonNav.THRESHOLD_MAP_ID = 2266
DungeonNav.TIMEWAYS_HUB = { uiMapID = 2393, x = 0.421, y = 0.582 } -- Silvermoon City

-- The dungeon (by SEASON2 entry) we're waiting to auto-point at once the player steps
-- into Millennia's Threshold. Cleared once consumed or overwritten by a new /xxr
-- dungeon command.
DungeonNav.pendingPortalTarget = nil

-- The waypoint we most recently set, kept around so OnZoneChanged() can
-- silently reassert it. Dungeon nav destinations are often far away and
-- necessarily cross several zone boundaries just to walk there - unlike a
-- gathering route, that's expected and fine, so nothing here should ever
-- drop on a normal zone change. Reported live 2026-08-17 ("totally drops
-- upon a zone change"); reasserting on every zone-change event is a robust
-- fix regardless of the exact underlying cause (native waypoints, TomTom,
-- and this addon's own compass can all lose track of a far-off target
-- independently - reapplying all three together sidesteps having to prove
-- which one actually dropped it). Cleared on arrival.
DungeonNav.activeTarget = nil

local function HasWaypointAPI()
    return C_Map and C_Map.SetUserWaypoint and CreateVector2D
end

local function HasEntranceAPI()
    return C_EncounterJournal and C_EncounterJournal.GetDungeonEntrancesForMap
        and C_Map and C_Map.GetMapInfo
end

-- Returns name -> {uiMapID, x, y} for every discovered dungeon/raid entrance on the
-- player's current continent. Fully guarded; returns an empty table on any client
-- that lacks the APIs, or if anything unexpected comes back.
local function CollectDiscoveredEntrances()
    local found = {}
    if not HasEntranceAPI() then return found end

    local ok = pcall(function()
        local here = C_Map.GetBestMapForUnit("player")
        if not here then return end

        -- Walk up to the continent (mapType 2), then scan it and its descendants.
        local continent = here
        local info = C_Map.GetMapInfo(here)
        while info and info.parentMapID and info.parentMapID > 0
            and info.mapType and info.mapType > 2 do
            continent = info.parentMapID
            info = C_Map.GetMapInfo(continent)
        end

        local maps = { continent, here }
        local children = C_Map.GetMapChildrenInfo(continent, nil, true)
        if children then
            for _, child in ipairs(children) do
                if child.mapID then maps[#maps + 1] = child.mapID end
            end
        end

        for _, mapID in ipairs(maps) do
            local entrances = C_EncounterJournal.GetDungeonEntrancesForMap(mapID)
            if entrances then
                for _, e in ipairs(entrances) do
                    if e.name and e.position and not found[e.name] then
                        local x, y = e.position:GetXY()
                        if x and y then
                            found[e.name] = { uiMapID = mapID, x = x, y = y }
                        end
                    end
                end
            end
        end
    end)
    if not ok then return {} end
    return found
end

-- Best available location for a Season 2 dungeon: the live discovered-entrance data
-- first (always accurate), then the verified fallback coords, else nil.
-- Resolves a zone's live uiMapID from its (localized enUS) name by scanning the
-- player's world-map tree. Cached on success; failures aren't cached, so it retries
-- once the player is somewhere the zone is in scope. No hardcoded ID = never wrong.
local mapIDCache = {}
local function ResolveMapIDByName(zoneName)
    if mapIDCache[zoneName] then return mapIDCache[zoneName] end
    if not (C_Map and C_Map.GetMapInfo and C_Map.GetMapChildrenInfo and C_Map.GetBestMapForUnit) then
        return nil
    end
    local result
    pcall(function()
        local top = C_Map.GetBestMapForUnit("player")
        if not top then return end
        local info = C_Map.GetMapInfo(top)
        while info and info.parentMapID and info.parentMapID > 0 and info.mapType and info.mapType > 1 do
            top = info.parentMapID
            info = C_Map.GetMapInfo(top)
        end
        local kids = C_Map.GetMapChildrenInfo(top, nil, true)
        if kids then
            for _, k in ipairs(kids) do
                if k.name == zoneName and k.mapID then result = k.mapID; return end
            end
        end
    end)
    if result then mapIDCache[zoneName] = result end
    return result
end

local function LocationFor(dungeon, discovered)
    if discovered[dungeon.name] then return discovered[dungeon.name] end
    if XalsXRDB and XalsXRDB.dungeonCoords and XalsXRDB.dungeonCoords[dungeon.name] then
        return XalsXRDB.dungeonCoords[dungeon.name]
    end
    if dungeon.uiMapID and dungeon.x and dungeon.y then
        return { uiMapID = dungeon.uiMapID, x = dungeon.x, y = dungeon.y }
    end
    if dungeon.zone and dungeon.x and dungeon.y then
        local mid = ResolveMapIDByName(dungeon.zone)
        if mid then return { uiMapID = mid, x = dungeon.x, y = dungeon.y } end
    end
    return nil
end

-- Sets the native super-tracked waypoint (Blizzard map pin + on-screen distance),
-- and mirrors to TomTom when the sync option is enabled. `silent` skips the chat
-- line and the activeTarget bookkeeping - used when OnZoneChanged reasserts an
-- already-active target rather than setting a genuinely new one.
function DungeonNav:SetWaypoint(uiMapID, x, y, label, silent)
    if not HasWaypointAPI() then
        print("|cffff9900Xal's XR:|r Dungeon waypoints need a modern (retail) client.")
        return false
    end
    local ok = pcall(function()
        C_Map.SetUserWaypoint({ uiMapID = uiMapID, position = CreateVector2D(x, y) })
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        end
    end)
    if not ok then
        print("|cffff9900Xal's XR:|r Couldn't set that waypoint (map data unavailable).")
        return false
    end
    -- Same rule as the gathering route (see PathPlanner.lua): TomTom is
    -- opt-in, so our own compass is the default. Only stand down for TomTom
    -- once it's actually been handed the waypoint successfully - otherwise
    -- (TomTom not installed, sync off, or the call itself fails) our arrow
    -- covers it, same as it always has.
    local tomtomActive = false
    if XalsXRDB and XalsXRDB.tomtomSyncEnabled and TomTom and TomTom.AddWaypoint then
        tomtomActive = pcall(function()
            TomTom:AddWaypoint(uiMapID, x, y,
                {
                    title = label, persistent = false, minimap = true, world = true, silent = true, crazy = true,
                    -- Explicit, small overrides - without these, TomTom falls
                    -- back to the player's own saved profile values for both,
                    -- which are tuned for gathering-route stops (a cluster of
                    -- nodes, fine to clear/arrive from further out) and were
                    -- clearing the ENTIRE waypoint - pin and arrow both -
                    -- well before actually reaching a precise dungeon portal.
                    -- cleardistance is the real culprit for "it just
                    -- disappeared" (confirmed against TomTom's real source,
                    -- TomTom_Config.lua) - it deletes the waypoint outright,
                    -- unlike arrivaldistance which only flips the arrow to
                    -- its "arrived" state.
                    cleardistance = 10,
                    arrivaldistance = 10,
                })
        end)
    end
    -- Own dedicated arrow (DungeonBeacon.lua) - fully independent from the
    -- gathering route's Beacon, so the two can never fight over one shared
    -- frame again. Clears itself (and DungeonNav.activeTarget) on arrival.
    if addonTable.DungeonBeacon and addonTable.DungeonBeacon.Show then
        if tomtomActive then
            if addonTable.DungeonBeacon.Clear then addonTable.DungeonBeacon:Clear() end
        else
            addonTable.DungeonBeacon:Show(uiMapID, x, y, label)
        end
    end
    if not silent then
        self.activeTarget = { uiMapID = uiMapID, x = x, y = y, label = label }
        print(string.format("|cff00ccffXal's XR:|r Waypoint set to |cff00ff00%s|r.", label or "the dungeon"))
    end
    return true
end

local function Slug(name)
    return name:lower():gsub("%s", "")
end

-- Backs "/xxr dungeon [name]". No name lists the pool + availability; a name (loose,
-- space-insensitive, partial ok) sets the waypoint.
function DungeonNav:Command(arg)
    if not HasWaypointAPI() then
        print("|cffff9900Xal's XR:|r Dungeon navigation is retail-only (the waypoint API isn't on this client).")
        return
    end
    arg = (arg or ""):gsub("^%s+", ""):gsub("%s+$", "")

    -- Capture mode: stand at a dungeon entrance and "/xxr dungeon set <name>" to
    -- record its exact map + position, so it waypoints for you from then on.
    local setName = arg:match("^set%s+(.+)$")
    if setName then
        self:CaptureHere(setName)
        return
    end

    local discovered = CollectDiscoveredEntrances()

    if arg == "" then
        print("|cff00ccffXal's Xpedited Routes - Dungeon nav |cff888888(Xperimental)|r|cff00ccff:|r")
        for _, d in ipairs(self.SEASON2) do
            local ready = LocationFor(d, discovered) ~= nil
            print(string.format("  |cff00ff00/xxr dungeon %s|r - %s|r",
                Slug(d.name), ready and "|cff00ff00ready|r" or "|cff888888not set - visit it, or use 'set'|r"))
        end
        print("|cff888888Tip: stand at an entrance and |r|cff00ff00/xxr dungeon set <name>|r|cff888888 to record it exactly.|r")
        return
    end

    local want = arg:lower():gsub("%s", "")
    for _, d in ipairs(self.SEASON2) do
        local slug = Slug(d.name)
        if slug == want or slug:find(want, 1, true) or d.name:lower():find(want, 1, true) then
            if d.portal then
                local here = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
                if here == self.THRESHOLD_MAP_ID then
                    self.pendingPortalTarget = nil
                    self:SetWaypoint(d.portal.uiMapID, d.portal.x, d.portal.y, d.name .. " Portal")
                else
                    self.pendingPortalTarget = d
                    self:SetWaypoint(self.TIMEWAYS_HUB.uiMapID, self.TIMEWAYS_HUB.x, self.TIMEWAYS_HUB.y,
                        "Timeways Portal (" .. d.name .. ")")
                end
                return
            end
            local loc = LocationFor(d, discovered)
            if loc then
                self:SetWaypoint(loc.uiMapID, loc.x, loc.y, d.name)
            else
                print(string.format("|cffff9900Xal's XR:|r No entrance data for %s yet - visit it once in-game and it'll work from then on.", d.name))
            end
            return
        end
    end
    print("|cffff9900Xal's XR:|r Unknown dungeon. Type |cff00ff00/xxr dungeon|r for the list.")
end

-- Called on zone change (see Engine.lua). If we sent the player to the Timeways hub
-- for a specific dungeon and they've now actually stepped into Millennia's Threshold,
-- swap the waypoint to that dungeon's own portal so the last stretch is covered too.
function DungeonNav:OnZoneChanged()
    if not (C_Map and C_Map.GetBestMapForUnit) then return end
    local here = C_Map.GetBestMapForUnit("player")

    if self.pendingPortalTarget and here == self.THRESHOLD_MAP_ID then
        local d = self.pendingPortalTarget
        self.pendingPortalTarget = nil
        self:SetWaypoint(d.portal.uiMapID, d.portal.x, d.portal.y, d.name .. " Portal")
        return
    end

    -- Reassert whatever's still active, silently, on every zone change - a
    -- dungeon trip normally crosses several zones just walking there, and
    -- nothing about that should ever drop the waypoint. See the
    -- activeTarget/HasFixedTarget comments above for the full story.
    if self.activeTarget then
        local t = self.activeTarget
        self:SetWaypoint(t.uiMapID, t.x, t.y, t.label, true)
    end
end

-- Records the player's current map + position as a dungeon's entrance (persisted in
-- saved variables), so undiscovered dungeons can be set exactly by standing at the
-- door - no guessed coordinates, and it survives to every character on the account.
function DungeonNav:CaptureHere(name)
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local pos = mapID and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
    if not mapID or not pos then
        print("|cffff9900Xal's XR:|r Couldn't read your position - stand out in the open zone (not inside the instance) and try again.")
        return
    end
    local x, y = pos:GetXY()
    if not x or not y then
        print("|cffff9900Xal's XR:|r Couldn't read your position - try again.")
        return
    end
    local want = name:lower():gsub("%s", "")
    local canonical = name
    for _, d in ipairs(self.SEASON2) do
        local slug = Slug(d.name)
        if slug == want or slug:find(want, 1, true) or d.name:lower():find(want, 1, true) then
            canonical = d.name
            break
        end
    end
    XalsXRDB.dungeonCoords = XalsXRDB.dungeonCoords or {}
    XalsXRDB.dungeonCoords[canonical] = { uiMapID = mapID, x = x, y = y }
    print(string.format("|cff00ccffXal's XR:|r Saved |cff00ff00%s|r at map %d (%.1f, %.1f) - it'll waypoint from now on.",
        canonical, mapID, x * 100, y * 100))
end

function DungeonNav:Init()
    -- Command-driven for now; nothing to wire up at startup.
end
