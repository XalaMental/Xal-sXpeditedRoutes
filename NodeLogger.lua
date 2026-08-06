-- NodeLogger.lua
local addonName, addonTable = ...
local NodeLogger = addonTable.NodeLogger
local Engine = addonTable.Engine
local Helpers = addonTable.Helpers

-- Midnight's corpse-based herbalism cast (looting a corpse, not a real plant) -
-- excluded up front so it never reaches type detection at all.
local EXCLUDED_SPELL_IDS = { [32605] = true }

local function SaveNode(uiMapID, x, y, gatherType)
    XalsXRDB[uiMapID] = XalsXRDB[uiMapID] or {}
    local zoneNodes = XalsXRDB[uiMapID]

    local duplicateYards = Helpers.GetDuplicateYards()
    local existingIndex = Helpers.FindNearbyNodeIndex(zoneNodes, Engine, uiMapID, x, y, duplicateYards)

    if existingIndex then
        -- Same spot gathered again - that's useful signal (it respawned and
        -- got picked), so refresh its freshness timestamp instead of just
        -- discarding the information.
        zoneNodes[existingIndex].lastGathered = time()
        print("|cffff9900Xal's XR:|r This node is already recorded.")
        return
    end

    table.insert(zoneNodes, { x = x, y = y, type = gatherType, lastGathered = time() })
    print("|cff00ff00Xal's XR:|r " .. (gatherType == "mine" and "Vein" or "Herb") .. " saved to your database.")
    if addonTable.Markers.UpdatePins then
        addonTable.Markers:UpdatePins()
    end
end

local function OnGatherSpellSucceeded(spellID)
    if EXCLUDED_SPELL_IDS[spellID] then return end

    local gatherType = Helpers.DetectGatherType(spellID)
    if not gatherType then return end

    local uiMapID = C_Map.GetBestMapForUnit("player")
    if not uiMapID then return end

    local position = C_Map.GetPlayerMapPosition(uiMapID, "player")
    if not position then return end

    local x, y = position:GetXY()
    if not x or not y then return end

    SaveNode(uiMapID, x, y, gatherType)
end

function NodeLogger:Init()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    frame:SetScript("OnEvent", function(self, event, unit, castGUID, spellID)
        if event == "UNIT_SPELLCAST_SUCCEEDED" and unit == "player" then
            OnGatherSpellSucceeded(spellID)
        end
    end)
end

-- Excluded from the sweep below - these are addon settings living in the same
-- top-level table as per-map node lists, not a map's node data.
local NON_MAP_KEYS = {
    showPins = true, compassPosition = true, autoAdvanceDistance = true,
    pinStyle = true, pinSize = true, showHelperButton = true,
    helperButtonPosition = true, showGlow = true, proximityDistanceYards = true,
    arrowProgressColor = true, pinAlpha = true,
    duplicateDistanceYards = true, compassArrowStyle = true, arrowScale = true, tomtomSyncEnabled = true,
    freshnessMinutes = true,
}

function NodeLogger.RemoveDuplicates()
    if not XalsXRDB then return 0 end

    local duplicateYards = Helpers.GetDuplicateYards()
    local removedCount = 0

    for mapID, nodes in pairs(XalsXRDB) do
        if not NON_MAP_KEYS[mapID] and type(nodes) == "table" then
            local kept = {}
            for _, node in ipairs(nodes) do
                if Helpers.FindNearbyNodeIndex(kept, Engine, mapID, node.x, node.y, duplicateYards) then
                    removedCount = removedCount + 1
                else
                    table.insert(kept, node)
                end
            end
            XalsXRDB[mapID] = kept
        end
    end

    return removedCount
end
