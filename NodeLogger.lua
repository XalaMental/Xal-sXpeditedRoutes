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

    -- Whatever live node (from the live scan) was just picked is gone now: its
    -- pulse stops. Done before the position fine-tuning below moves the node.
    if addonTable.Markers.MarkGathered then
        addonTable.Markers:MarkGathered(uiMapID, x, y)
    end
    -- Scan by distance counts again from here.
    if addonTable.LiveScan and addonTable.LiveScan.ResetDistance then
        addonTable.LiveScan:ResetDistance()
    end

    if existingIndex then
        -- Same spot gathered again - that's useful signal (it respawned and
        -- got picked), so refresh its freshness timestamp instead of just
        -- discarding the information.
        local existing = zoneNodes[existingIndex]
        existing.lastGathered = time()
        -- Fine-tune the saved position: move it partway toward where this
        -- gather happened, weighted by how many gathers it already has, so a
        -- marker that started a bit off settles onto the real spot after a few
        -- visits and one sloppy gather can't throw it far. Capped so it still
        -- adapts instead of freezing.
        local seen = existing.n or 1
        existing.x = math.floor((existing.x + (x - existing.x) / (seen + 1)) * 10000 + 0.5) / 10000
        existing.y = math.floor((existing.y + (y - existing.y) / (seen + 1)) * 10000 + 0.5) / 10000
        existing.n = math.min(seen + 1, 8)
        if addonTable.Markers.UpdatePins then
            addonTable.Markers:UpdatePins()
        end
        print("|cffff9900Xal's XR:|r This node is already recorded - its position was fine-tuned.")
        return
    end

    local newNode = { x = x, y = y, type = gatherType, lastGathered = time() }
    table.insert(zoneNodes, newNode)
    if addonTable.Sync and addonTable.Sync.Share then
        addonTable.Sync:Share(uiMapID, newNode)
    end
    local NODE_LABELS = { mine = "Vein", herb = "Herb", lumber = "Tree" }
    print("|cff00ff00Xal's XR:|r " .. (NODE_LABELS[gatherType] or "Node") .. " saved to your database.")
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
    freshnessMinutes = true, showHaulSummary = true, haulFramePosition = true,
    haulShowIcons = true, haulFontScale = true, haulGatherTimer = true, haulRouteTimer = true,
    arrowTextScale = true, dungeonCoords = true, dungeonButtonEnabled = true, dungeonButtonSide = true,
    minimap = true, helperButtonScale = true, groupingDistanceYards = true, showTrailLine = true,
    boundaryNodes = true, helperButtonFadeWhenIdle = true, optionsWindowPoint = true,
    dungeonCompassPosition = true, lumberEnabled = true,
    dungeonButtonPosition = true,
    nodeHighlightEnabled = true, nodeHighlightRange = true, nodeHighlightSaved = true, nodeHighlightStyle = true,
    nodeHighlightQuest = true, nodeHighlightChest = true, nodeHighlightContainers = true,
    foreverDataImported = true, shareEnabled = true,
    liveScanEnabled = true, liveScanTimer = true, liveScanTimerSeconds = true, liveScanDistance = true,
    liveScanDistanceYards = true, liveScanDim = true, liveScanArrow = true, liveArrowPosition = true, liveScanRare = true, liveScanRoute = true, skin = true,
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
