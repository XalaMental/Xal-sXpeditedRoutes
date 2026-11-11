-- ForeverImport.lua
-- Xal's Xpedited Routes
--
-- WoW: Forever only. The first time you log in on Forever, this adds the
-- built-in herb and ore positions (ForeverNodeData.lua) to your saved nodes,
-- so the map isn't empty on a fresh start. It goes through the same public
-- import every other source uses (API.ImportNodeData), so anything within
-- your duplicate distance of a node you already have is skipped, and your own
-- nodes are never changed or removed.
--
-- It runs in small batches a moment after login so the game never stalls, and
-- it's marked done only when every batch has finished - if you log out partway
-- it simply starts over next time (already-added nodes are skipped as
-- duplicates).
local addonName, addonTable = ...

local ForeverImport = {}
addonTable.ForeverImport = ForeverImport

local BATCH_SIZE = 300
local BATCH_SECONDS = 0.05
local START_DELAY = 6

local function IsForever()
    return WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT
end

-- Turns the compact text for every map into a flat list of
-- { mapID, x, y, type } entries.
local function BuildQueue(maps)
    local queue = {}
    for mapID, text in pairs(maps) do
        for xs, ys, kind in text:gmatch("(%d%d%d%d%d)(%d%d%d%d%d)([hm])") do
            queue[#queue + 1] = {
                mapID,
                tonumber(xs) / 10000,
                tonumber(ys) / 10000,
                kind == "h" and "herb" or "mine",
            }
        end
    end
    return queue
end

function ForeverImport:Run()
    local data = addonTable.ForeverNodeData
    local API = _G.XalsXpeditedRoutesAPI
    if not (data and data.maps and API and API.ImportNodeData and XalsXRDB) then return end
    if XalsXRDB.foreverDataImported == data.version then return end
    if self.running then return end
    self.running = true

    local queue = BuildQueue(data.maps)
    local index = 1
    local added, skipped, invalid = 0, 0, 0

    local function Step()
        local batch = {}
        local last = math.min(index + BATCH_SIZE - 1, #queue)
        for i = index, last do
            local entry = queue[i]
            local list = batch[entry[1]]
            if not list then
                list = {}
                batch[entry[1]] = list
            end
            list[#list + 1] = { x = entry[2], y = entry[3], type = entry[4] }
        end
        index = last + 1

        local result = API.ImportNodeData(batch, true)
        added = added + result.added
        skipped = skipped + result.skipped
        invalid = invalid + result.invalid

        if index <= #queue then
            C_Timer.After(BATCH_SECONDS, Step)
        else
            self.running = false
            XalsXRDB.foreverDataImported = data.version
            if addonTable.Markers and addonTable.Markers.UpdatePins then
                addonTable.Markers:UpdatePins()
            end
            print(string.format(
                "|cff00ccffXal's XR:|r Added %d built-in herb and ore nodes (%d skipped as duplicates of nodes you already had).",
                added, skipped))
        end
    end

    print("|cff00ccffXal's XR:|r Adding built-in herb and ore nodes for this game version - this takes a few seconds.")
    Step()
end

function ForeverImport:Init()
    if not IsForever() then return end
    C_Timer.After(START_DELAY, function() ForeverImport:Run() end)
end
