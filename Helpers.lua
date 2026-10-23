-- Helpers.lua
local addonName, addonTable = ...
local Helpers = addonTable.Helpers

-- True only on Retail (WOW_PROJECT_MAINLINE) - false on every Classic flavor
-- (Era, MoP, etc.). Used to pick between the exact retail item-ID allowlist
-- (KNOWN_MATERIAL_ITEMS in RunTracker.lua) and Classic's own item-subclass
-- detection, confirmed 2026-09-30 - Classic's Trade Goods subclass data is
-- still the original per-type categorization (Herb, Metal & Stone), unlike
-- retail's flattened subclass, so an ID list isn't needed there.
function Helpers.IsRetail()
    return WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
end

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

-- Lumberjacking is NOT a real profession skill line - it's an ability granted
-- through Midnight's Player Housing content (a Lumberjack Axe / "Find Lumber"
-- quest chain), not something GetProfessions()/C_TradeSkillUI knows about at
-- all. "Find Lumber" (spell 1256697) is the ability that actually gates
-- whether lumber nodes show up on the map/minimap at all - confirmed directly
-- in-game ("I couldn't see the nodes till it was activated"), and confirmed
-- live 2026-08-17 via C_SpellBook.IsSpellKnown against all three candidate
-- IDs: 1256697 (Find Lumber) = true, 1266232 (Lumberjack, the passive
-- originally assumed to be this one) = false, 1239682 (Woodchopping, the
-- gather cast itself) = false. So checking whether the player knows THIS
-- spell is the real equivalent of the skill-line check the other two
-- professions use. Distinct from the gather CAST itself (Woodchopping,
-- 1239682, confirmed live via UNIT_SPELLCAST_SUCCEEDED - see
-- KNOWN_GATHER_SPELLS below), which is what actually fires when a node is
-- harvested - a spell can be the thing that fires on cast without also being
-- "known" in the spellbook sense IsSpellKnown checks.
Helpers.LUMBERJACK_PASSIVE_SPELL_ID = 1256697

-- True if the character has the Find Lumber ability (can see/gather lumber
-- nodes at all). No skill-line/profession-name equivalent exists for this one
-- (see comment above) - IsSpellKnown is the only real signal. Checks the
-- modern C_SpellBook namespace first (Midnight's replacement for the old
-- global), falling back to the classic global for safety, same defensive
-- pattern used elsewhere in this file for other renamed APIs.
-- Manual opt-out, checked first: unlike Mining/Herbalism (an active choice to
-- level), Lumberjacking comes from Player Housing content, so someone could
-- have the passive without ever wanting to gather wood on purpose. Defaults
-- on (Engine.lua) - this only ever short-circuits to false once the player
-- explicitly turns it off in Settings.
function Helpers.HasLumberjacking()
    if XalsXRDB and XalsXRDB.lumberEnabled == false then
        return false
    end
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        return C_SpellBook.IsSpellKnown(Helpers.LUMBERJACK_PASSIVE_SPELL_ID) == true
    end
    if _G.IsSpellKnown then
        return _G.IsSpellKnown(Helpers.LUMBERJACK_PASSIVE_SPELL_ID) == true
    end
    return false
end

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

-- WoW doesn't expose real node respawn timers to addons, so this is a blunt
-- heuristic: a node gathered very recently almost certainly hasn't respawned
-- yet, so it's not worth routing to. 0 disables the check entirely.
-- Ships OFF by default (Xperimental / opt-in) - players enable it via /xxr freshness.
Helpers.DEFAULT_FRESHNESS_MINUTES = 0

function Helpers.GetFreshnessMinutes()
    return (XalsXRDB and XalsXRDB.freshnessMinutes) or Helpers.DEFAULT_FRESHNESS_MINUTES
end

-- True if `node` was gathered recently enough that it probably hasn't
-- respawned. Nodes saved before this feature existed (or never gathered a
-- second time) have no lastGathered value at all - treated as NOT recent,
-- since there's no evidence either way and excluding them by default would
-- silently drop nodes nobody actually just picked.
function Helpers.IsNodeRecentlyGathered(node, freshnessMinutes)
    if not node.lastGathered or freshnessMinutes <= 0 then return false end
    return (time() - node.lastGathered) < (freshnessMinutes * 60)
end

-- Distance and heading between two points on the SAME map, computed from
-- Blizzard's own map-to-world conversion instead of HereBeDragons (added
-- 2026-10-23). Another addon bundling a stale HereBeDragons copy was giving
-- Classic players a wrong-way arrow and a wrong distance, and nothing in this
-- addon can control which copy loads. The zone's real size in yards is
-- measured by converting a few map points to world coordinates (the same map
-- is flat and north-up, so size is all that's needed - no axis conventions to
-- get wrong). Returns distance, deltaX (east positive), deltaY (north
-- positive), or nil when the client can't supply it, in which case callers
-- fall back to HereBeDragons and then to the raw-coordinate approximation.
local zoneSizeCache = {}

local function MeasureZoneYards(mapID)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local function worldPoint(x, y)
        local _, pos = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
        if not pos then return nil, nil end
        return pos:GetXY()
    end
    local ok, w, h = pcall(function()
        local x1, y1 = worldPoint(0.4, 0.5)
        local x2, y2 = worldPoint(0.6, 0.5)
        local x3, y3 = worldPoint(0.5, 0.4)
        local x4, y4 = worldPoint(0.5, 0.6)
        if not (x1 and x2 and x3 and x4) then return nil end
        return math.sqrt((x2 - x1)^2 + (y2 - y1)^2) / 0.2,
               math.sqrt((x4 - x3)^2 + (y4 - y3)^2) / 0.2
    end)
    -- A real zone is somewhere in the hundreds-to-thousands of yards across;
    -- anything outside this range is a bad conversion, not a zone.
    if ok and w and h and w > 300 and w < 30000 and h > 300 and h < 30000 then
        return { w = w, h = h }
    end
    return nil
end

function Helpers.ZoneVector(mapID, ax, ay, bx, by)
    if not (mapID and ax and ay and bx and by) then return nil end
    local size = zoneSizeCache[mapID]
    if size == nil then
        size = MeasureZoneYards(mapID) or false
        zoneSizeCache[mapID] = size
    end
    if not size then return nil end
    local dx, dy = (bx - ax) * size.w, (ay - by) * size.h
    return math.sqrt(dx * dx + dy * dy), dx, dy
end

function Helpers.NodeDistanceYards(Core, mapID, x1, y1, x2, y2)
    local zd = Helpers.ZoneVector(mapID, x1, y1, x2, y2)
    if zd then return zd end
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
-- Retail collapsed each gathering profession into a single cast spell, so only a
-- couple of IDs are ever seen there. Classic clients (Era/Cata/MoP) instead fire
-- a RANK-SPECIFIC spell ID on UNIT_SPELLCAST_SUCCEEDED - an Apprentice miner and a
-- Zen Master miner cast different IDs - so every rank has to be listed or higher-
-- rank gatherers on Classic record nothing. IDs are globally unique and the old
-- rank IDs are never actually cast on retail, so one combined table safely serves
-- every flavor at once; the MoP ladder below also fully covers Cata and Era.
--
-- VERIFY BEFORE RELEASE: the Classic rank IDs are transcribed from the historical
-- rank ladder and still need confirming against Wowhead's MoP Classic build, since
-- these realms can't be quick-tested. Wrong/missing IDs = silently unrecorded nodes.
local KNOWN_GATHER_SPELLS = {
    -- Retail (confirmed live)
    [32606] = "mine", [471013] = "mine", -- 471013: Midnight mining. 372610 ruled out (mount-related)
    [471009] = "herb", -- 471009: Midnight herbalism gather spell
    [1239682] = "lumber", -- Woodchopping - confirmed live 2026-08-17 via a UNIT_SPELLCAST_SUCCEEDED watcher, printed right before the Thalassian Lumber loot message, twice
    [366252] = "herb", -- Herb Gathering, Dragonflight - confirmed live 2026-10-07 from a live spell trace: seen right before the Hochenblume loot (item 191460, Herb subclass)
    -- The War Within mining, from GatherMate2's own list of gather spell IDs
    -- (plain facts, not code). Resolves to the name "Khaz Algar Mining" on
    -- this client (seen in a live spell trace 2026-10-07) but not yet confirmed
    -- by actually mining. GatherMate2 also lists 195122, but on this client
    -- that ID is named "Typhoon" (a druid spell) - it would have saved a fake
    -- mining node every time a druid cast it, so it is deliberately NOT here.
    [423341] = "mine",

    -- Classic mining rank ladder: Apprentice -> Zen Master
    [2575] = "mine",  -- Apprentice
    [2576] = "mine",  -- Journeyman
    [3564] = "mine",  -- Expert
    [10248] = "mine", -- Artisan
    [29354] = "mine", -- Master (TBC)
    [50310] = "mine", -- Grand Master (WotLK)
    [88075] = "mine", -- Illustrious (Cata)
    [102161] = "mine", -- Zen Master (MoP)

    -- Classic herbalism rank ladder: Apprentice -> Zen Master
    [2366] = "herb",  -- Apprentice
    [2368] = "herb",  -- Journeyman
    [3570] = "herb",  -- Expert
    [11993] = "herb", -- Artisan
    [28695] = "herb", -- Master (TBC)
    [50300] = "herb", -- Grand Master (WotLK)
    [74519] = "herb", -- Illustrious (Cata)
    [110413] = "herb", -- Zen Master (MoP)
}

-- Known IDs resolve instantly. For any OTHER spell ID, the spell's exact
-- localized name is compared against the names of the known gather spells
-- above - the same technique GatherMate2 uses (resolve a known ID to its
-- localized name once, then match casts by name), added 2026-10-07 after a
-- player leveling through Dragonflight found Dragon Isles herbs weren't
-- recorded: every expansion's herb gather is a DIFFERENT spell ID, so an ID
-- list alone only ever covers the current expansion. Exact name equality
-- against names taken from known gather spells is deliberately NOT the old
-- substring match that was removed earlier (something as generic as "gather"
-- appearing anywhere in an unrelated spell/buff/proc name misfired as a
-- gather and spammed "already recorded") - a name only counts if it is
-- exactly the name of a spell already known to be a gather cast. Names that
-- would map to two different gather types are dropped as ambiguous.
-- Names are resolved incrementally, not once: spell data isn't always
-- available the instant the first spell is cast after login, and an earlier
-- version that built this table a single time (and only rebuilt it when
-- completely empty) never matched the Dragonflight herb cast in a real test
-- on 2026-10-07 - it very likely locked in a partly-filled table at the
-- first cast. Now every known ID whose name hasn't resolved yet is retried,
-- at most once every few seconds, until it does.
local gatherNames = {}     -- localized spell name -> "mine"/"herb"/"lumber", or false if ambiguous
local resolvedGatherIDs = {} -- known IDs whose name has been added to gatherNames
local lastNameRetry = nil
local NAME_RETRY_SECONDS = 5

local function ResolveGatherNames()
    for id, kind in pairs(KNOWN_GATHER_SPELLS) do
        if not resolvedGatherIDs[id] then
            local name = Helpers.GetSpellName(id)
            if name and name ~= "" then
                resolvedGatherIDs[id] = true
                local existing = gatherNames[name]
                if existing == nil then
                    gatherNames[name] = kind
                elseif existing ~= kind then
                    gatherNames[name] = false
                end
            end
        end
    end
end

function Helpers.DetectGatherType(spellID)
    local exact = KNOWN_GATHER_SPELLS[spellID]
    if exact then return exact end
    if not spellID then return nil end

    local now = GetTime()
    if not lastNameRetry or now - lastNameRetry >= NAME_RETRY_SECONDS then
        lastNameRetry = now
        ResolveGatherNames()
    end

    local name = Helpers.GetSpellName(spellID)
    if name and name ~= "" then
        return gatherNames[name] or nil
    end
    return nil
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
