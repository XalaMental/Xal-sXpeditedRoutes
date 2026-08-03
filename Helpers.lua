-- Helpers.lua
local addonName, addonTable = ...
local Helpers = addonTable.Helpers

-- Safe wrapper to get the spell name (compatible with WoW 11.0+ Midnight and earlier)
function Helpers.GetSpellName(spellID)
    if not spellID then return "" end
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        return info and info.name or ""
    elseif _G.GetSpellInfo then
        return _G.GetSpellInfo(spellID) or ""
    end
    return ""
end

-- Returns true only if `pos` looks like a usable SetPoint table: {point, x, y}.
-- Saved position tables can end up malformed (an interrupted drag, a stale/edited
-- SavedVariables file, etc.); SetPoint throws a hard Lua error on bad argument
-- types, so anything we pass to it needs to be checked first rather than trusted.
function Helpers.IsValidPoint(pos)
    return type(pos) == "table"
        and type(pos.point) == "string"
        and type(pos.x) == "number"
        and type(pos.y) == "number"
end

-- Returns `pos` if it's valid, otherwise a fresh copy of `default`.
function Helpers.SanitizePoint(pos, default)
    if Helpers.IsValidPoint(pos) then
        return pos
    end
    return { point = default.point, x = default.x, y = default.y }
end

-- The base (parent) skill line IDs for the two gathering professions this addon
-- tracks. These have historically stayed constant across expansions, but aren't
-- treated as the only signal below - an expansion-wide profession revamp (like
-- Midnight's) could plausibly renumber them, so the profession's actual NAME is
-- checked too, since that's stable regardless of any internal ID changes.
Helpers.MINING_SKILL_LINE = 186
Helpers.HERBALISM_SKILL_LINE = 182
Helpers.MINING_NAMES = { "mining" }
Helpers.HERBALISM_NAMES = { "herbalism", "herb" }

-- Once we get a CONFIRMED answer for a profession (the API actually returned real
-- data, not just "unavailable so we're guessing"), there's no reason to keep
-- re-checking it - a character's known professions don't change mid-session in
-- any way that matters here. Cached results are checked first and short-circuit
-- everything below; only an unconfirmed ("assume known") result is left
-- uncached, so detection keeps trying until it actually gets a real answer.
local confirmedProfessionCache = {}

-- True once every profession this addon cares about has a confirmed (not
-- guessed) answer - lets callers know there's no more point re-checking.
function Helpers.IsProfessionDetectionConfirmed()
    return confirmedProfessionCache[Helpers.MINING_SKILL_LINE] ~= nil
        and confirmedProfessionCache[Helpers.HERBALISM_SKILL_LINE] ~= nil
end

-- Wipes the cached answers so the next check re-reads real profession data
-- instead of trusting an old cached result. Needed because a confirmed answer
-- isn't permanent - a player can learn (or drop) a profession mid-session,
-- which a one-time login-only cache can't account for.
function Helpers.ClearProfessionCache()
    confirmedProfessionCache[Helpers.MINING_SKILL_LINE] = nil
    confirmedProfessionCache[Helpers.HERBALISM_SKILL_LINE] = nil
end

local function NameMatches(name, matchNames)
    if not name or not matchNames then return false end
    local lowerName = name:lower()
    for _, pattern in ipairs(matchNames) do
        if lowerName:find(pattern, 1, true) then
            return true
        end
    end
    return false
end

-- matchNames (optional) is a list of lowercase substrings to check the
-- profession's actual name against - e.g. Helpers.MINING_NAMES. Matching by
-- either the ID or the name is enough; this way a stale/renumbered ID doesn't
-- silently break detection as long as the name still reads "Mining"/"Herbalism".
function Helpers.HasGatheringProfession(parentSkillLineID, matchNames)
    if confirmedProfessionCache[parentSkillLineID] ~= nil then
        return confirmedProfessionCache[parentSkillLineID]
    end

    -- Primary: the older GetProfessions()/GetProfessionInfo() globals. Despite
    -- being the "legacy" API, this is the one confirmed to work reliably without
    -- the Professions window ever having been opened - it reads from the
    -- character's core profession slots directly, not the trade-skill/recipe UI's
    -- own lazily-loaded cache. Verified directly: C_TradeSkillUI's modern
    -- equivalent, when called cold (Professions window never opened), returns
    -- its entire static reference list of every profession skill line in the
    -- game's history with every skillLevel reported as 0 - completely unusable
    -- for this purpose until that window has been opened. This is what most
    -- addons that need profession info at login actually rely on for that reason.
    if _G.GetProfessions and _G.GetProfessionInfo then
        local prof1, prof2 = GetProfessions()

        -- Neither profession slot has ANY data at all - this is much more
        -- likely a timing gap (profession data genuinely not populated yet on
        -- a truly fresh login) than a character with zero professions. Verified
        -- directly: this does happen on cold login even though the same check
        -- works correctly moments later after a /reload, meaning the earlier
        -- assumption that GetProfessions() always has real data immediately was
        -- wrong for this specific case. Don't cache anything here - leave it
        -- uncached so the backstop re-check timers (see Engine.lua) get another
        -- shot at it once the data's actually loaded, instead of permanently
        -- locking in a false "no professions" result for the whole session.
        if not prof1 and not prof2 then
            return true
        end

        -- Checked explicitly rather than via ipairs({prof1, prof2}) - ipairs stops
        -- at the first nil it sees, so if prof1 is nil and prof2 holds a real
        -- profession (entirely possible depending on which slot a profession
        -- landed in), ipairs would skip it and never check it at all.
        for _, idx in ipairs({ prof1 or false, prof2 or false }) do
            if idx then
                local name, icon, skillLevel, maxSkillLevel, numAbilities, spellOffset, skillLine = GetProfessionInfo(idx)
                local matches = (skillLine == parentSkillLineID) or NameMatches(name, matchNames)
                if matches and skillLevel and skillLevel > 0 then
                    confirmedProfessionCache[parentSkillLineID] = true
                    return true
                end
            end
        end
        -- At least one real profession slot WAS found above (we already ruled
        -- out "both empty" earlier), so a scan that found no match here is a
        -- confirmed, trustworthy "no" - this character has real profession
        -- data and it genuinely doesn't include this one.
        -- no match is a confirmed, trustworthy "no", not an inconclusive result.
        confirmedProfessionCache[parentSkillLineID] = false
        return false
    end

    -- Fallback: C_TradeSkillUI's modern API. Kept in case GetProfessions() is ever
    -- removed in a future client, but most C_TradeSkillUI functions only return
    -- real data once the Professions/trade-skill window has actually been opened
    -- this session, so this path is far less reliable at login than the one above.
    if C_TradeSkillUI and C_TradeSkillUI.GetAllProfessionTradeSkillLines and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
        local ok, lines = pcall(C_TradeSkillUI.GetAllProfessionTradeSkillLines)
        -- An empty result usually means the client hasn't populated profession data
        -- yet this session (it's lazily loaded, often not until the Professions
        -- window has been opened at least once) - NOT that the character has zero
        -- professions. Treat that as inconclusive rather than a confident "no".
        if ok and lines and next(lines) ~= nil then
            for _, skillLineID in pairs(lines) do
                local infoOk, info = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, skillLineID)
                if infoOk and info then
                    local parent = info.parentProfessionID or info.professionID
                    local matchesID = (parent == parentSkillLineID or skillLineID == parentSkillLineID)
                    local matchesName = NameMatches(info.professionName or info.name, matchNames)
                    if (matchesID or matchesName) and info.skillLevel and info.skillLevel > 0 then
                        confirmedProfessionCache[parentSkillLineID] = true
                        return true
                    end
                end
            end
            confirmedProfessionCache[parentSkillLineID] = false
            return false
        end
    end

    -- Neither detection method gave us usable data - don't guess, assume known,
    -- and don't cache it either, since this isn't a real answer yet.
    return true
end

-- Shared "is this the same node" distance logic, used by NodeLogger.lua (live
-- recording + cleanup), so both agree on what counts as a duplicate.
--
-- Distances are computed in actual yards via HereBeDragons when it's installed,
-- rather than comparing raw normalized map coordinates against a flat threshold -
-- 0.01 of a zone's coordinate space is a very different real distance in a small
-- zone than a huge one, which made the old fixed threshold feel inconsistent.
Helpers.DEFAULT_DUPLICATE_YARDS = 15
Helpers.FALLBACK_YARDS_PER_UNIT = 4000 -- rough approximation used only without HereBeDragons, shared across every fallback distance calc in the addon

function Helpers.GetDuplicateYards()
    return (XalsXRDB and XalsXRDB.duplicateDistanceYards) or Helpers.DEFAULT_DUPLICATE_YARDS
end

function Helpers.NodeDistanceYards(Core, mapID, x1, y1, x2, y2)
    if Core.HBD then
        local dist = Core.HBD:GetZoneDistance(mapID, x1, y1, x2, y2)
        if dist then return dist end
    end
    local dx, dy = x2 - x1, y2 - y1
    return math.sqrt(dx * dx + dy * dy) * Helpers.FALLBACK_YARDS_PER_UNIT
end

-- Maps a spell ID successfully cast to the gathering type it represents, or nil
-- if it isn't one we track. Built as a direct lookup table for the handful of
-- known fixed spell IDs, with a name-substring scan as a secondary pass only for
-- IDs the table doesn't recognize - this way the common case (a known ID) never
-- touches string matching at all.
local KNOWN_GATHER_SPELLS = {
    [32606] = "mine", [2575] = "mine", [471013] = "mine", -- 471013 confirmed live: Midnight mining. 372610 was tested and ruled out - it's mount-related, not a gather spell
    [2366] = "herb", [471009] = "herb", -- 471009 confirmed live: Midnight's herbalism gather spell, a new ID not present in older expansions
}

-- Spell ID is the only thing checked here - deliberately not falling back to
-- matching on the spell's name. A name-substring match sounds harmless but
-- isn't: something as generic as "gather" appearing anywhere in an unrelated
-- spell/buff/proc name would misfire as a gather action every time it
-- triggered, which in practice meant chat getting spammed with "already
-- recorded" every time some unrelated ability fired near a node you'd already
-- picked up. The known spell IDs above are stable and precise; if a real
-- gathering spell turns out to be missing, add its exact ID rather than a
-- name pattern.
function Helpers.DetectGatherType(spellID)
    return KNOWN_GATHER_SPELLS[spellID]
end

-- Searches `nodeList` for an entry within `thresholdYards` of (x, y), returning
-- its index (or nil if none qualify). Runs a cheap, single rough pre-filter on
-- the raw normalized coordinates before paying for the more expensive real-yard
-- distance calculation - most non-matches get rejected on that first, cheap
-- check alone, so the (typically much rarer) real distance call only runs for
-- candidates that are already in the right neighborhood.
local ROUGH_REJECT_RADIUS = 0.05 -- generous normalized-coordinate radius; a genuine match is always well inside this at any sane zone scale

function Helpers.FindNearbyNodeIndex(nodeList, Core, mapID, x, y, thresholdYards)
    for i, entry in ipairs(nodeList) do
        if math.abs(entry.x - x) <= ROUGH_REJECT_RADIUS and math.abs(entry.y - y) <= ROUGH_REJECT_RADIUS then
            if Helpers.NodeDistanceYards(Core, mapID, x, y, entry.x, entry.y) < thresholdYards then
                return i
            end
        end
    end
    return nil
end
