-- API.lua
-- Xal's Xpedited Routes
--
-- Public surface for other addons to hand node data to Routes - built
-- specifically for Xal's Routes Data (a companion addon that ships a big
-- table of Jason's own pre-collected nodes for players to import), but not
-- restricted to it; any addon could call this the same way.
--
-- Exposed as a real global (_G.XalsXpeditedRoutesAPI), not tucked inside
-- addonTable, since another addon has no access to this addon's private
-- namespace - that's the whole point of a public API surface.
local addonName, addonTable = ...
local Helpers = addonTable.Helpers
local Engine = addonTable.Engine

_G.XalsXpeditedRoutesAPI = _G.XalsXpeditedRoutesAPI or {}
local API = _G.XalsXpeditedRoutesAPI

-- nodesByMapID shape: { [uiMapID] = { {x=0.0-1.0, y=0.0-1.0, type="mine"/"herb"/"lumber"}, ... }, ... }
-- Runs every incoming node through the SAME duplicate-check this addon
-- already uses for live gathering (Helpers.FindNearbyNodeIndex, same
-- distance threshold from Options -> Database) before inserting - an
-- import doesn't get to skip the check just because it came in bulk.
-- Returns {added = N, skipped = N, invalid = N} so the caller can report
-- real numbers back to the player instead of just "done."
function API.ImportNodeData(nodesByMapID)
    local added, skipped, invalid = 0, 0, 0

    if type(nodesByMapID) ~= "table" then
        return { added = 0, skipped = 0, invalid = 0 }
    end

    local duplicateYards = Helpers.GetDuplicateYards()

    for uiMapID, nodes in pairs(nodesByMapID) do
        if type(uiMapID) == "number" and type(nodes) == "table" then
            XalsXRDB[uiMapID] = XalsXRDB[uiMapID] or {}
            local zoneNodes = XalsXRDB[uiMapID]

            for _, node in ipairs(nodes) do
                if type(node) == "table" and type(node.x) == "number" and type(node.y) == "number"
                    and (node.type == "mine" or node.type == "herb" or node.type == "lumber")
                    and node.x >= 0 and node.x <= 1 and node.y >= 0 and node.y <= 1 then
                    local existingIndex = Helpers.FindNearbyNodeIndex(zoneNodes, Engine, uiMapID, node.x, node.y, duplicateYards)
                    if existingIndex then
                        skipped = skipped + 1
                    else
                        -- No lastGathered - this wasn't actually just picked, so it
                        -- shouldn't count as "recently gathered" for freshness
                        -- filtering (see Helpers.IsNodeRecentlyGathered).
                        table.insert(zoneNodes, { x = node.x, y = node.y, type = node.type })
                        added = added + 1
                    end
                else
                    invalid = invalid + 1
                end
            end
        else
            invalid = invalid + 1
        end
    end

    if added > 0 and addonTable.Markers and addonTable.Markers.UpdatePins then
        addonTable.Markers:UpdatePins()
    end

    return { added = added, skipped = skipped, invalid = invalid }
end
