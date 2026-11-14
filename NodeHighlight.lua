-- NodeHighlight.lua
-- Makes the herb or ore you're about to pick glow. WoW: Forever only.
--
-- How it works: with a few game settings turned on, the game gives whatever
-- your Interact key would pick (its "soft interact" target) a nameplate, even
-- for a game object like a herb or ore vein. The game also reports that
-- object's cursor icon, and herbs and ore each have their own (Mine and
-- GatherHerbs) - so no name tables are needed, in any language. This puts an
-- animated glow on that nameplate when the object is a herb or ore. Addons
-- can't highlight every node around you at once; only the one the game has
-- picked.
--
-- The game settings this changes are saved first and put back when the option
-- is turned off, and again at logout, so nothing is left behind if the addon
-- is removed. Written from what the game itself exposes (the unit token,
-- the PLAYER_SOFT_INTERACT_CHANGED event, the cursor icon names, the console
-- variables) - the names were confirmed against the Warcraft Wiki and a
-- working Forever client. The glow art (Textures\NodeGlow) is our own.

local addonName, addonTable = ...
local NodeHighlight = addonTable.NodeHighlight

local SOFT = "softinteract"
local DEFAULT_RANGE = 15
local TICK_SECONDS = 0.1
local ART = "Interface\\AddOns\\" .. addonName .. "\\Textures\\NodeGlow\\"
local GLOW_SIZE = 150

-- Glow color per node type.
local COLORS = {
    herb = { 0.35, 1.0, 0.45 },
    ore = { 1.0, 0.7, 0.25 },
    quest = { 0.55, 0.5, 1.0 },
    chest = { 0.55, 0.5, 1.0 },
}

-- Forever is the only client this runs on (WOW_PROJECT_CAMELOT is nil
-- everywhere else, so this is false on Retail and Classic).
NodeHighlight.supported = WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT

function NodeHighlight:IsSupported()
    return self.supported
end

-- The looks the settings page offers.
NodeHighlight.STYLES = { "fire", "beam", "pulse", "sparkle", "spotlight", "rune", "storm", "reticle", "halo" }
NodeHighlight.STYLE_LABELS = {
    fire = "Fire", beam = "Beam", pulse = "Pulse",
    sparkle = "Sparkle", spotlight = "Spotlight", rune = "Rune Circle", storm = "Storm Cloud",
    reticle = "Target Lock", halo = "Halo and Rays",
}

local function Secret(value)
    return issecretvalue ~= nil and issecretvalue(value) == true
end

--------------------------------------------------------------------------------
-- Game settings
--------------------------------------------------------------------------------
local function GetCV(name)
    local ok, value = pcall(C_CVar and C_CVar.GetCVar or GetCVar, name)
    if ok then return value end
    return nil
end

local function SetCV(name, value)
    if GetCV(name) == nil then return end -- this client doesn't have that setting
    pcall(C_CVar and C_CVar.SetCVar or SetCVar, name, tostring(value))
end

-- The game stops picking an interact target at about 15 yards on Forever
-- 1.60.1, even if more is asked for (measured on that client by another
-- addon's author and confirmed there), so asking for more can't reach further.
NodeHighlight.MIN_RANGE = 5
NodeHighlight.MAX_RANGE = 15

function NodeHighlight:GetRange()
    local range = (XalsXRDB and XalsXRDB.nodeHighlightRange) or DEFAULT_RANGE
    return math.max(self.MIN_RANGE, math.min(self.MAX_RANGE, range))
end

local function Range()
    return NodeHighlight:GetRange()
end

-- The settings the game needs for a game object to become the interact
-- target and get a nameplate.
local function WantedSettings(savedOriginals)
    local range = Range()
    local plateDistance = tonumber(savedOriginals and savedOriginals.nameplateGameObjectMaxDistance) or 0
    return {
        SoftTargetInteract = 3,
        SoftTargetNameplateInteract = 1,
        SoftTargetIconGameObject = 1,
        SoftTargetInteractArc = 2,
        SoftTargetInteractRange = range,
        SoftTargetInteractOnlyInRange = 0,
        SoftTargetInteractRangeIsHard = 0,
        nameplateGameObjectMaxDistance = math.max(plateDistance, range + 5),
    }
end

local pendingApply = false

-- Turns the game settings on (saving the originals first) or puts the
-- originals back, depending on the option.
function NodeHighlight:Apply()
    if not self.supported or not XalsXRDB then return end
    if InCombatLockdown() then
        pendingApply = true
        return
    end
    pendingApply = false

    if XalsXRDB.nodeHighlightEnabled then
        XalsXRDB.nodeHighlightSaved = XalsXRDB.nodeHighlightSaved or {}
        local saved = XalsXRDB.nodeHighlightSaved
        -- Capture the current values of everything we're about to change, once.
        for name in pairs(WantedSettings(nil)) do
            if saved[name] == nil then saved[name] = GetCV(name) or false end
        end
        for name, value in pairs(WantedSettings(saved)) do
            SetCV(name, value)
        end
    else
        self:RestoreSettings(true)
    end
end

-- Puts the player's original values back. forgetThem = true also clears the
-- saved copy (turning the option off); false keeps it so the next login can
-- apply again (logout).
function NodeHighlight:RestoreSettings(forgetThem)
    local saved = XalsXRDB and XalsXRDB.nodeHighlightSaved
    if not saved then return end
    for name, value in pairs(saved) do
        if value ~= false then SetCV(name, value) end
    end
    if forgetThem then XalsXRDB.nodeHighlightSaved = nil end
end

--------------------------------------------------------------------------------
-- Telling a herb or ore from anything else the game might pick
--------------------------------------------------------------------------------
local probe
local cursorLookup = {} -- file ID -> { kind, unable }

local function BuildCursorLookup()
    if not GetFileIDFromPath then return end
    local cursors = { Mine = "ore", GatherHerbs = "herb" }
    for name, kind in pairs(cursors) do
        for _, prefix in ipairs({ "", "Unable" }) do
            local path = "Interface\\Cursor\\" .. prefix .. name
            local ok, id = pcall(GetFileIDFromPath, path)
            if not (ok and id) then
                ok, id = pcall(GetFileIDFromPath, path .. ".blp")
            end
            if ok and id then cursorLookup[id] = { kind, prefix ~= "" } end
        end
    end
end

-- Cursor-name keywords for the non-gathering kinds. The first match wins, and
-- herb/ore are always checked before these.
local EXTRA_CURSOR_WORDS = {
    { "quest", "quest" }, { "important", "quest" }, { "recurring", "quest" }, { "wrapper", "quest" },
    { "lootall", "chest" }, { "pickup", "chest" }, { "picklock", "chest" },
}

-- Chests have no cursor of their own (the game gives them a generic one), so
-- they're recognized two ways: the object is one the player has looted from
-- before (learned below), or its name contains a chest-type word.
local CHEST_WORDS = {
    "chest", "crate", "barrel", "coffer", "strongbox", "lockbox", "footlocker", "trunk", "cache",
    "truhe", "kiste", "fass", "coffre", "caisse", "tonneau", "cofre", "caja", "barril",
    "сундук", "ящик", "бочк",
}

local function ObjectID(unit)
    local ok, guid = pcall(UnitGUID, unit)
    if not ok or Secret(guid) or type(guid) ~= "string" then return nil end
    return tonumber(guid:match("^GameObject%-%d+%-%d+%-%d+%-%d+%-(%d+)"))
end

local function LooksLikeChestByName(unit)
    local ok, name = pcall(UnitName, unit)
    if not ok or Secret(name) or type(name) ~= "string" then return false end
    local lower = name:lower()
    for _, word in ipairs(CHEST_WORDS) do
        if lower:find(word, 1, true) or name:find(word, 1, true) then return true end
    end
    return false
end

local function IsGameObject(unit)
    if not UnitIsGameObject then return true end -- can't tell; don't block
    local ok, isObject = pcall(UnitIsGameObject, unit)
    return ok and isObject == true
end

-- Returns "herb", "ore", "quest" or "chest" (and whether the game says it
-- can't be used right now) for the unit, or nil for anything else.
local function Classify(unit)
    if not probe then
        probe = UIParent:CreateTexture(nil, "BACKGROUND")
        probe:Hide()
    end
    local ok, hasCursor = pcall(SetUnitCursorTexture, probe, unit, nil, true)
    if not ok then hasCursor = false end

    local texture, atlas
    if hasCursor then
        texture = probe:GetTexture()
        atlas = probe.GetAtlas and probe:GetAtlas()
        if Secret(texture) then texture = nil end
        if Secret(atlas) then atlas = nil end

        local known = type(texture) == "number" and cursorLookup[texture]
        if known then return known[1], known[2] end

        -- The client gives a file ID, a path, or an atlas name depending on the
        -- case, so fall back to looking for the cursor's name in the text.
        for _, text in ipairs({ texture, atlas }) do
            if type(text) == "string" then
                local lower = text:lower()
                local unable = lower:find("unable", 1, true) ~= nil
                if lower:find("gatherherb", 1, true) then return "herb", unable end
                if lower:find("mine", 1, true) then return "ore", unable end
            end
        end
    end

    -- Quest objects and chests are game objects only (not NPCs).
    if not IsGameObject(unit) then return nil end

    local unable = false
    for _, text in ipairs({ texture, atlas }) do
        if type(text) == "string" and text:lower():find("unable", 1, true) then unable = true end
    end

    if C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest then
        local okQ, related = pcall(C_QuestLog.UnitIsRelatedToActiveQuest, unit)
        if okQ and not Secret(related) and related == true then return "quest", unable end
    end

    for _, text in ipairs({ texture, atlas }) do
        if type(text) == "string" then
            local lower = text:lower()
            for _, entry in ipairs(EXTRA_CURSOR_WORDS) do
                if lower:find(entry[1], 1, true) then return entry[2], unable end
            end
        end
    end

    local id = ObjectID(unit)
    local learned = XalsXRDB and XalsXRDB.nodeHighlightContainers
    if (id and learned and learned[id]) or LooksLikeChestByName(unit) then
        return "chest", unable
    end
    return nil
end

-- When a loot window opens, remember which kind of object it came from, so
-- that kind is recognized as a chest from then on. Fishing and gathering
-- (herb/ore) loot is left out.
local function LearnContainers()
    if not (XalsXRDB and GetNumLootItems and GetLootSourceInfo) then return end
    if IsFishingLoot and IsFishingLoot() then return end
    XalsXRDB.nodeHighlightContainers = XalsXRDB.nodeHighlightContainers or {}
    for slot = 1, GetNumLootItems() do
        local ok, guid = pcall(GetLootSourceInfo, slot)
        if ok and not Secret(guid) and type(guid) == "string" then
            local id = tonumber(guid:match("^GameObject%-%d+%-%d+%-%d+%-%d+%-(%d+)"))
            if id and not (NodeHighlight.gatheredIDs and NodeHighlight.gatheredIDs[id]) then
                XalsXRDB.nodeHighlightContainers[id] = true
            end
        end
    end
end

--------------------------------------------------------------------------------
-- The glow: a soft halo, a ring, a star flare, small lights orbiting the ring,
-- and rings that ripple outward every few seconds, over a faint dark shadow so
-- it still shows on snow and sand. It swells in when a node is picked, glows
-- brighter and livelier while the node is within reach, and dims to gray while
-- it isn't (too far, or your skill is too low).
--------------------------------------------------------------------------------
local sin, cos, min, max, pi, random = math.sin, math.cos, math.min, math.max, math.pi, math.random
local TWO_PI = 2 * pi
local MOTE_COUNT = 4
local PING_SECONDS = 1.2
local FIRE_ASPECT = 627 / 750 -- width / height of the flame art
local EMBER_ASPECT = 504 / 1254 -- height / width of the ember art
local DOME_HEIGHT = 0.42 -- height of a pulse dome as a fraction of its width (a half circle would be 0.5)
local RUNE_ASPECT = 256 / 1024 -- height / width of the rune art (a wide oval, drawn in perspective)
local GROUND = 0.36 -- how flat a circle on the ground looks from the usual camera angle
local FOOT = 0.12 -- how far below the object's middle its base is, as a fraction of the glow size
-- How far below the game's nameplate (which floats above the object) the
-- object's middle is, in screen pixels. A starting estimate - adjust after
-- seeing it in game.
local OBJECT_DROP = 70

local glow

local function Lerp(a, b, t)
    return a + (b - a) * t
end

local function Approach(value, target, step)
    if value < target then return min(value + step, target) end
    return max(value - step, target)
end

local function Layer(parent, file, drawLayer, subLevel, blend)
    local texture = parent:CreateTexture(nil, drawLayer, nil, subLevel)
    texture:SetTexture(ART .. file .. ".tga")
    texture:SetBlendMode(blend or "ADD")
    texture:SetPoint("CENTER")
    texture:SetVertexColor(1, 1, 1, 0)
    return texture
end

local function Tint(texture, r, g, b, a)
    texture:SetVertexColor(r, g, b, a <= 0 and 0 or (a >= 1 and 1 or a))
end

-- Which looks send ripples across the ground, how often (seconds), and how
-- far they travel (as a fraction of the glow size).
local PINGS = {
    fire = { interval = 2.8, from = 0.5, to = 1.5, strength = 0.5 },
    beam = { interval = 3.0, from = 0.5, to = 1.5, strength = 0.5 },
    -- Pulse is a dome: each pulse is a half-circle arch standing on a ground
    -- ellipse at its base, and the whole bubble grows outward and fades, again
    -- and again.
    pulse = { interval = 0.8, duration = 1.5, from = 0.2, to = 1.3, strength = 0.9, dome = true },
    rune = { interval = 3.6, from = 0.6, to = 1.5, strength = 0.4 },
    reticle = { interval = 3.2, from = 0.5, to = 1.4, strength = 0.35 },
}
local SPARKLE_COUNT = 16

local function Off(texture)
    texture:SetVertexColor(1, 1, 1, 0)
end

-- Gives one sparkle a new random life: where it starts, how far it rises,
-- how big it gets and how fast it twirls.
local function RespawnSparkle(sparkle, size, footY)
    sparkle.age = 0
    sparkle.life = 0.7 + random() * 0.9
    sparkle.x = (random() - 0.5) * size * 0.62
    sparkle.y = footY + random() * size * 0.3
    sparkle.rise = size * (0.3 + random() * 0.5)
    sparkle.size = size * (0.16 + random() * 0.2)
    sparkle.seed = random() * TWO_PI
    sparkle.twirl = (random() - 0.5) * 5
end

local function Animate(self, elapsed)
    if elapsed > 0.1 then elapsed = 0.1 end -- no jump after a frame hitch

    self.appear = min(self.appear + elapsed / 0.35, 1)
    local arrive = 1 - (1 - self.appear) ^ 3 -- 0 -> 1, slowing down
    self.ready = Approach(self.ready, self.unable and 0 or 1, elapsed / 0.25)
    local ready = self.ready
    local locked = 1 - ready

    -- The arrival sound waits for the glow's final, full-bright form: the swell-in is
    -- finished and the node is one you can gather (ready, not grayed out).
    if self.soundPending and self.appear >= 1 and ready >= 0.99 then
        self.soundPending = false
        if addonTable.Sounds then addonTable.Sounds:Play("arrive") end
    end

    self.phase = self.phase + elapsed * TWO_PI / Lerp(3.6, 1.8, ready)
    self.spin = self.spin + elapsed * Lerp(0.5, 1.4, ready)
    local breath = 0.5 + 0.5 * sin(self.phase)
    local twinkle = 0.5 + 0.5 * sin(self.phase * 2.3 + 1.3)

    -- Color: the node's color, washed toward gray when it can't be gathered,
    -- and lifted toward white for the fine lines and the star's center.
    local r = Lerp(self.r, 0.6, 0.75 * locked)
    local g = Lerp(self.g, 0.6, 0.75 * locked)
    local b = Lerp(self.b, 0.6, 0.75 * locked)
    local lr, lg, lb = Lerp(r, 1, 0.5), Lerp(g, 1, 0.5), Lerp(b, 1, 0.5)
    local wr, wg, wb = Lerp(r, 1, 0.8), Lerp(g, 1, 0.8), Lerp(b, 1, 0.8)

    local alpha = arrive * (1 - 0.5 * locked)
    local size = GLOW_SIZE * (1 + 0.4 * (1 - arrive)) -- tightens in as it arrives
    local footY = -size * FOOT
    local style = (XalsXRDB and XalsXRDB.nodeHighlightStyle) or "fire"

    -- Start every layer off; the chosen look switches on only what it uses.
    Off(self.band); Off(self.ring); Off(self.flare); Off(self.flame); Off(self.flameBack)
    Off(self.spotShaft); Off(self.rune); Off(self.domeFill); Off(self.stormCloud); Off(self.stormBolt)
    Off(self.reticle); Off(self.rays); Off(self.haloRing)
    self.beam:Hide() -- only the Beam look shows it (hiding it outright; zero alpha didn't hide it on Forever)
    for _, mote in ipairs(self.motes) do Off(mote) end
    for _, ember in ipairs(self.embers) do Off(ember) end
    for _, sparkle in ipairs(self.sparkles) do Off(sparkle.star); Off(sparkle.halo) end

    -- A faint dark pool under every look so it still shows on snow and sand.
    self.shade:SetSize(size * 1.05, size * 1.05 * GROUND)
    self.shade:ClearAllPoints()
    self.shade:SetPoint("CENTER", self, "CENTER", 0, footY)
    Tint(self.shade, 0, 0, 0, alpha * (style == "sparkle" and 0.15 or 0.3))

    -- Flat ring on the ground (fire, beam).
    if style == "fire" or style == "beam" then
        self.ring:SetSize(size, size * GROUND)
        self.ring:ClearAllPoints()
        self.ring:SetPoint("CENTER", self, "CENTER", 0, footY)
        Tint(self.ring, lr, lg, lb, alpha * Lerp(0.3, 0.9, ready))
    end

    if style == "beam" then
        -- Column of light rising from the base; grows up as the glow arrives.
        local beamHeight = size * 1.7 * arrive
        self.beam:SetSize(size * 0.05, max(beamHeight, 1))
        self.beam:ClearAllPoints()
        self.beam:SetPoint("BOTTOM", self, "CENTER", 0, footY)
        self.beam:SetAlpha(alpha * Lerp(0.5, 1, ready) * (0.8 + 0.2 * breath))
        self.beam:Show()

        local bandSize = size * (0.94 + 0.08 * breath)
        self.band:SetSize(bandSize, bandSize)
        Tint(self.band, r, g, b, alpha * Lerp(0.08, 0.16, ready) * (0.8 + 0.2 * breath))

        -- A small bright spark where the column meets the ring.
        local flareSize = size * (0.2 + 0.05 * ready + 0.04 * twinkle + 0.35 * (1 - arrive))
        self.flare:SetSize(flareSize, flareSize)
        self.flare:ClearAllPoints()
        self.flare:SetPoint("CENTER", self, "CENTER", 0, footY)
        self.flare:SetRotation(0.12 * sin(self.phase * 0.5))
        Tint(self.flare, wr, wg, wb, alpha * Lerp(0.3, 0.9, ready) * (0.7 + 0.3 * twinkle))

        -- Small lights drifting around the object, only while it's within reach.
        for i, mote in ipairs(self.motes) do
            local angle = self.spin + i * TWO_PI / MOTE_COUNT
            local glint = 0.5 + 0.5 * sin(self.phase * 3 + i * 1.9)
            local lift = 0.5 + 0.5 * sin(self.phase * 0.8 + i * 1.7)
            mote:ClearAllPoints()
            mote:SetPoint("CENTER", self, "CENTER", cos(angle) * size * 0.3, footY + (0.12 + 0.34 * lift) * size)
            local moteSize = size * (0.08 + 0.05 * glint)
            mote:SetSize(moteSize, moteSize)
            Tint(mote, lr, lg, lb, alpha * ready * (0.15 + 0.35 * glint))
        end

    elseif style == "fire" then
        -- Flames burning from the base. They keep their own colors (the type
        -- color stays on the ground ring), flicker and sway, and embers drift
        -- up off them.
        local flicker = 1 + 0.05 * sin(self.phase * 7.3) + 0.03 * sin(self.phase * 11.1 + 1)
        local sway = 0.05 * sin(self.phase * 2.1)
        local fireAlpha = alpha * Lerp(0.5, 1, ready)
        local height = size * 1.25 * Lerp(0.7, 1, ready) * flicker * max(arrive, 0.05)

        self.flameBack:SetSize(height * 0.7 * 1.15 * FIRE_ASPECT * (1 + 0.06 * sin(self.phase * 5.3 + 2)), height * 0.7)
        self.flameBack:ClearAllPoints()
        self.flameBack:SetPoint("BOTTOM", self, "CENTER", 0, footY - 0.02 * size)
        self.flameBack:SetRotation(-sway)
        Tint(self.flameBack, 1, 1, 1, fireAlpha * 0.8)

        self.flame:SetSize(height * FIRE_ASPECT, height)
        self.flame:ClearAllPoints()
        self.flame:SetPoint("BOTTOM", self, "CENTER", 0, footY - 0.02 * size)
        self.flame:SetRotation(sway)
        Tint(self.flame, 1, 1, 1, fireAlpha)

        -- Embers rise and fade, staggered so there's always some.
        for k, ember in ipairs(self.embers) do
            local t = (self.phase / TWO_PI * 0.5 + k / #self.embers) % 1
            local width = size * 1.0
            ember:SetSize(width, width * EMBER_ASPECT)
            ember:ClearAllPoints()
            ember:SetPoint("CENTER", self, "CENTER", sway * size, footY + 0.2 * size + t * size * 1.2)
            Tint(ember, 1, 1, 1, fireAlpha * ready * sin(pi * t))
        end

    elseif style == "pulse" then
        -- A bright core at the base and a soft dome of light over it; the
        -- expanding dome outlines are drawn below, on a steady beat.
        local coreSize = size * (0.24 + 0.07 * breath + 0.3 * (1 - arrive))
        self.flare:SetSize(coreSize, coreSize)
        self.flare:ClearAllPoints()
        self.flare:SetPoint("CENTER", self, "CENTER", 0, footY)
        self.flare:SetRotation(0)
        Tint(self.flare, wr, wg, wb, alpha * Lerp(0.5, 1, ready) * (0.75 + 0.25 * breath))

        local fillWidth = size * (0.7 + 0.06 * breath)
        self.domeFill:SetSize(fillWidth, fillWidth * DOME_HEIGHT)
        self.domeFill:ClearAllPoints()
        self.domeFill:SetPoint("BOTTOM", self, "CENTER", 0, footY)
        Tint(self.domeFill, r, g, b, alpha * Lerp(0.2, 0.45, ready))

        -- The same flat ring as the other looks, as the base the domes grow from.
        self.ring:SetSize(size * 0.8, size * 0.8 * GROUND)
        self.ring:ClearAllPoints()
        self.ring:SetPoint("CENTER", self, "CENTER", 0, footY)
        Tint(self.ring, lr, lg, lb, alpha * Lerp(0.2, 0.6, ready))

    elseif style == "sparkle" then
        -- A soft aura with lots of bright, twirling sparkles popping up around
        -- the node, plus one big twinkling star hovering over it.
        local auraSize = size * (0.95 + 0.08 * breath)
        self.band:SetSize(auraSize, auraSize)
        self.band:ClearAllPoints()
        self.band:SetPoint("CENTER", self, "CENTER", 0, footY + size * 0.28)
        Tint(self.band, r, g, b, alpha * Lerp(0.05, 0.12, ready) * (0.8 + 0.2 * breath))

        local bigSize = size * (0.2 + 0.07 * twinkle + 0.2 * (1 - arrive))
        self.flare:SetSize(bigSize, bigSize)
        self.flare:ClearAllPoints()
        self.flare:SetPoint("CENTER", self, "CENTER", 0, footY + size * 0.42)
        self.flare:SetRotation(self.spin * 0.35)
        Tint(self.flare, wr, wg, wb, alpha * Lerp(0.4, 0.85, ready) * (0.6 + 0.4 * twinkle))

        local pace = Lerp(0.55, 1, ready) -- slower while out of reach
        for _, sparkle in ipairs(self.sparkles) do
            if not sparkle.age then
                RespawnSparkle(sparkle, size, footY)
                sparkle.age = -random() * 1.2 -- stagger the first ones
            end
            sparkle.age = sparkle.age + elapsed * pace
            if sparkle.age >= sparkle.life then
                RespawnSparkle(sparkle, size, footY)
            elseif sparkle.age > 0 then
                local t = sparkle.age / sparkle.life
                local envelope = sin(pi * t) ^ 0.6
                local flash = 0.7 + 0.3 * sin(t * 18 + sparkle.seed) -- quick glitter
                local px = sparkle.x + sin(sparkle.seed + t * 3) * size * 0.03
                local py = sparkle.y + t * sparkle.rise
                local starSize = sparkle.size * (0.5 + 0.9 * envelope)
                sparkle.star:ClearAllPoints()
                sparkle.star:SetPoint("CENTER", self, "CENTER", px, py)
                sparkle.star:SetSize(starSize, starSize)
                sparkle.star:SetRotation(sparkle.seed + t * sparkle.twirl)
                Tint(sparkle.star, wr, wg, wb, alpha * envelope * flash)

                sparkle.halo:ClearAllPoints()
                sparkle.halo:SetPoint("CENTER", self, "CENTER", px, py)
                -- A small, dim halo so each sparkle stays a distinct star; big
                -- bright halos overlap into one white blob.
                sparkle.halo:SetSize(starSize * 1.4, starSize * 1.4)
                Tint(sparkle.halo, r, g, b, alpha * envelope * 0.3)
            end
        end

    elseif style == "spotlight" then
        -- A wide soft shaft of light from above landing in a bright pool on
        -- the ground, with a little dust drifting up through it.
        local shaftWidth = size * 0.75 * (0.97 + 0.05 * breath)
        local shaftHeight = size * 2.0 * arrive
        self.spotShaft:SetSize(shaftWidth, max(shaftHeight, 1))
        self.spotShaft:ClearAllPoints()
        self.spotShaft:SetPoint("BOTTOM", self, "CENTER", 0, footY - size * 0.02)
        Tint(self.spotShaft, lr, lg, lb, alpha * Lerp(0.35, 0.7, ready) * (0.85 + 0.15 * breath))

        self.band:SetSize(size * 1.05, size * 1.05 * GROUND * 1.3)
        self.band:ClearAllPoints()
        self.band:SetPoint("CENTER", self, "CENTER", 0, footY)
        Tint(self.band, r, g, b, alpha * Lerp(0.35, 0.8, ready) * (0.85 + 0.15 * breath))

        for i, mote in ipairs(self.motes) do
            local t = (self.phase / TWO_PI * 0.4 + i / MOTE_COUNT) % 1
            local sway = sin(self.phase * 0.7 + i * 2.2) * size * 0.1
            mote:ClearAllPoints()
            mote:SetPoint("CENTER", self, "CENTER", sway, footY + 0.08 * size + t * size * 1.1)
            local moteSize = size * 0.09
            mote:SetSize(moteSize, moteSize)
            Tint(mote, wr, wg, wb, alpha * ready * sin(pi * t) * 0.8)
        end

    elseif style == "rune" then
        -- A glowing magic circle lying on the ground, breathing slowly, with
        -- motes rising off it. Uses Textures\NodeGlow\rune.tga (falls back to
        -- the plain ring until that art exists).
        local runeSize = size * (1.15 + 0.04 * breath)
        self.rune:SetSize(runeSize, runeSize * RUNE_ASPECT) -- the art is already drawn lying on the ground, so it isn't squashed any further
        self.rune:ClearAllPoints()
        self.rune:SetPoint("CENTER", self, "CENTER", 0, footY)
        Tint(self.rune, lr, lg, lb, alpha * Lerp(0.45, 1, ready) * (0.78 + 0.22 * breath))

        for i, mote in ipairs(self.motes) do
            local t = (self.phase / TWO_PI * 0.5 + i / MOTE_COUNT) % 1
            local angle = self.spin * 0.6 + i * TWO_PI / MOTE_COUNT
            mote:ClearAllPoints()
            mote:SetPoint("CENTER", self, "CENTER", cos(angle) * size * 0.3, footY + 0.05 * size + t * size * 0.7)
            local moteSize = size * 0.09
            mote:SetSize(moteSize, moteSize)
            Tint(mote, lr, lg, lb, alpha * ready * sin(pi * t) * 0.9)
        end

    elseif style == "storm" then
        -- A dark storm cloud hangs over the node and lightning strikes down from it
        -- every second or two: the bolt flickers on, the cloud flashes brighter, and
        -- a bright flare bursts on the ground where it lands. Out of reach it's a
        -- quiet gray cloud with no strikes. Art: Textures\NodeGlow\storm_cloud.tga
        -- (the cloud, shading kept) and storm_bolts.tga (four bolts, one per quarter
        -- of the sheet, white so they take the node's color).
        local cloudWidth = size * 1.05
        local cloudHeight = cloudWidth * 0.5
        local cloudY = footY + size * 0.98
        local drift = sin(self.phase * 0.6) * size * 0.06

        -- When the next strike happens, and which of the four bolts it uses.
        self.strikeIn = (self.strikeIn or 0.8) - elapsed
        if self.strikeIn <= 0 and ready > 0.5 then
            self.strikeIn = 0.9 + random() * 1.7
            self.strikeAge = 0
            self.strikeBolt = random(0, 3)
        end
        local flash = 0
        if self.strikeAge then
            self.strikeAge = self.strikeAge + elapsed
            local t = self.strikeAge / 0.34
            if t >= 1 then
                self.strikeAge = nil
            elseif t < 0.14 or (t > 0.28 and t < 0.5) then
                flash = 1                         -- the two bright beats of the flicker
            else
                flash = 0.35 * (1 - t)            -- dim between them
            end
        end

        -- The cloud: a dull slate tinted a touch toward the node's color, lit up
        -- toward white by each strike.
        local base = 0.55
        local cr = Lerp(Lerp(base, r, 0.25), 1, flash * 0.85)
        local cg = Lerp(Lerp(base, g, 0.25), 1, flash * 0.85)
        local cb = Lerp(Lerp(base + 0.08, b, 0.25), 1, flash * 0.85)
        self.stormCloud:SetSize(cloudWidth, cloudHeight)
        self.stormCloud:ClearAllPoints()
        self.stormCloud:SetPoint("CENTER", self, "CENTER", drift, cloudY)
        Tint(self.stormCloud, cr, cg, cb, alpha * Lerp(0.55, 0.95, ready))

        -- The bolt, from the cloud's underside down to the ground.
        if flash > 0 then
            local top = cloudY - cloudHeight * 0.3
            local boltHeight = math.max(top - footY, 1)
            local boltWidth = boltHeight * 0.34
            local cell = self.strikeBolt or 0
            self.stormBolt:SetTexCoord(cell * 0.25, cell * 0.25 + 0.25, 0, 1)
            self.stormBolt:SetSize(boltWidth, boltHeight)
            self.stormBolt:ClearAllPoints()
            self.stormBolt:SetPoint("BOTTOM", self, "CENTER", drift * 0.4, footY)
            Tint(self.stormBolt, Lerp(r, 1, 0.7), Lerp(g, 1, 0.7), Lerp(b, 1, 0.7), alpha * flash)

            -- The burst where it lands.
            local burst = size * (0.28 + 0.34 * flash)
            self.flare:SetSize(burst, burst)
            self.flare:ClearAllPoints()
            self.flare:SetPoint("CENTER", self, "CENTER", drift * 0.4, footY)
            self.flare:SetRotation(0)
            Tint(self.flare, wr, wg, wb, alpha * flash * 0.9)
        end

        -- A faint ring on the ground under the strike point, like the other looks.
        self.ring:SetSize(size * 0.8, size * 0.8 * GROUND)
        self.ring:ClearAllPoints()
        self.ring:SetPoint("CENTER", self, "CENTER", 0, footY)
        Tint(self.ring, lr, lg, lb, alpha * Lerp(0.2, 0.55, ready))

    elseif style == "reticle" then
        -- Target lock: a targeting reticle (ring, ticks, corner brackets, crosshair)
        -- lying on the ground around the node. It starts a little wide and tightens
        -- in when the node is picked, then breathes slowly; a small bright core sits
        -- on the node itself. Art: Textures\NodeGlow\reticle.tga (drawn top-down,
        -- flattened here to lie on the ground).
        local reticleSize = size * 1.1 * (1 + 0.18 * (1 - arrive)) * (1 - 0.05 * breath)
        self.reticle:SetSize(reticleSize, reticleSize * GROUND)
        self.reticle:ClearAllPoints()
        self.reticle:SetPoint("CENTER", self, "CENTER", 0, footY)
        Tint(self.reticle, lr, lg, lb, alpha * Lerp(0.5, 1, ready) * (0.8 + 0.2 * breath))

        local core = size * (0.16 + 0.04 * breath)
        self.flare:SetSize(core, core)
        self.flare:ClearAllPoints()
        self.flare:SetPoint("CENTER", self, "CENTER", 0, footY)
        self.flare:SetRotation(0)
        Tint(self.flare, wr, wg, wb, alpha * Lerp(0.3, 0.9, ready))

    elseif style == "halo" then
        -- Halo and rays: a halo floats above the node, bobbing gently, with soft
        -- shafts of light falling from it to a glowing pool on the ground and dust
        -- drifting up through them. Art: Textures\NodeGlow\rays.tga (a fan of rays,
        -- apex at the top) and ring.tga for the halo itself.
        local haloY = footY + size * 1.05 + size * 0.025 * sin(self.phase * 0.9)
        local haloWidth = size * 0.6 * (1 + 0.03 * breath)
        self.haloRing:SetSize(haloWidth, haloWidth * 0.34)
        self.haloRing:ClearAllPoints()
        self.haloRing:SetPoint("CENTER", self, "CENTER", 0, haloY)
        Tint(self.haloRing, wr, wg, wb, alpha * Lerp(0.6, 1, ready))

        self.rays:SetSize(size * 0.95, max(haloY - footY, 1))
        self.rays:ClearAllPoints()
        self.rays:SetPoint("TOP", self, "CENTER", 0, haloY)
        Tint(self.rays, lr, lg, lb, alpha * Lerp(0.3, 0.65, ready) * (0.85 + 0.15 * breath))

        self.band:SetSize(size * 1.0, size * GROUND * 1.2)
        self.band:ClearAllPoints()
        self.band:SetPoint("CENTER", self, "CENTER", 0, footY)
        Tint(self.band, r, g, b, alpha * Lerp(0.3, 0.7, ready) * (0.85 + 0.15 * breath))

        for i, mote in ipairs(self.motes) do
            local t = (self.phase / TWO_PI * 0.4 + i / MOTE_COUNT) % 1
            local sway = sin(self.phase * 0.7 + i * 2.2) * size * 0.1
            mote:ClearAllPoints()
            mote:SetPoint("CENTER", self, "CENTER", sway, footY + 0.08 * size + t * size * 0.95)
            local moteSize = size * 0.08
            mote:SetSize(moteSize, moteSize)
            Tint(mote, wr, wg, wb, alpha * ready * sin(pi * t) * 0.8)
        end
    end

    -- Rings that ripple outward across the ground, on the beat this look uses.
    local ping = PINGS[style]
    self.nextPing = self.nextPing - elapsed
    if self.nextPing <= 0 then
        self.nextPing = ping and ping.interval or 3
        if ping and locked < 0.5 then
            for _, wave in ipairs(self.waves) do
                if not wave.age then wave.age = 0 break end
            end
        end
    end
    for _, wave in ipairs(self.waves) do
        if wave.age then
            wave.age = wave.age + elapsed
            local progress = wave.age / ((ping and ping.duration) or PING_SECONDS)
            if progress >= 1 or not ping then
                wave.age = nil
                Off(wave.texture)
                Off(wave.dome)
            else
                -- Every ripple is a ring lying on the ground at the base. The pulse
                -- look also stands a half-circle arch on top of it, so the whole
                -- ripple reads as a dome growing outward.
                local width = size * Lerp(ping.from, ping.to, 1 - (1 - progress) ^ 2)
                local fade = alpha * ping.strength * (1 - progress) ^ 1.5
                wave.texture:SetSize(width, width * GROUND)
                wave.texture:ClearAllPoints()
                wave.texture:SetPoint("CENTER", self, "CENTER", 0, footY)
                Tint(wave.texture, lr, lg, lb, fade)
                if ping.dome then
                    wave.dome:SetSize(width, width * DOME_HEIGHT)
                    wave.dome:ClearAllPoints()
                    wave.dome:SetPoint("BOTTOM", self, "CENTER", 0, footY)
                    Tint(wave.dome, lr, lg, lb, fade)
                else
                    Off(wave.dome)
                end
            end
        else
            Off(wave.texture)
            Off(wave.dome)
        end
    end
end

-- Bright at the base, fading to nothing at the top.
local function ApplyBeamColor(texture, r, g, b)
    if texture.SetGradient and CreateColor then
        texture:SetGradient("VERTICAL", CreateColor(r, g, b, 1), CreateColor(r, g, b, 0))
    else
        texture:SetColorTexture(r, g, b, 0.4)
    end
end

local function BuildGlow()
    glow = CreateFrame("Frame", nil, UIParent)
    glow:SetSize(1, 1)
    glow:SetFrameStrata("HIGH")
    glow:Hide()

    glow.shade = Layer(glow, "halo", "BACKGROUND", -1, "BLEND")
    glow.band = Layer(glow, "halo", "BACKGROUND", 0)
    glow.ring = Layer(glow, "ring", "ARTWORK", 0)
    -- Each ripple is a flat ring on the ground plus (in the pulse look) a
    -- half-circle arch standing on it: the ring image showing only its top half.
    glow.waves = {}
    for i = 1, 3 do
        local dome = Layer(glow, "ring", "BORDER", 1)
        dome:SetTexCoord(0, 1, 0, 0.5)
        glow.waves[i] = { texture = Layer(glow, "ring", "BORDER", 0), dome = dome }
    end
    -- Soft dome of light for the pulse look: the halo image showing only its top half.
    glow.domeFill = Layer(glow, "glow", "BACKGROUND", 1)
    glow.domeFill:SetTexCoord(0, 1, 0, 0.5)
    glow.flare = Layer(glow, "flare", "OVERLAY", 1)
    -- The column of light is a plain white strip that fades out toward the top
    -- (a gradient, no image needed); its color is set in ApplyBeamColor.
    glow.beam = glow:CreateTexture(nil, "ARTWORK", nil, -1)
    glow.beam:SetColorTexture(1, 1, 1, 1)
    glow.beam:SetBlendMode("ADD")
    glow.beam:Hide()
    glow.motes = {}
    for i = 1, MOTE_COUNT do glow.motes[i] = Layer(glow, "glow", "OVERLAY", 0) end

    -- Fire look layers.
    glow.flameBack = Layer(glow, "fire_cluster", "ARTWORK", -2)
    glow.flame = Layer(glow, "fire_flame", "ARTWORK", -1)
    glow.embers = { Layer(glow, "fire_embers", "OVERLAY", 2), Layer(glow, "fire_embers", "OVERLAY", 2) }

    -- Sparkle look: a star and a soft halo behind it for each sparkle.
    glow.sparkles = {}
    for i = 1, SPARKLE_COUNT do
        glow.sparkles[i] = {
            halo = Layer(glow, "glow", "OVERLAY", 2),
            star = Layer(glow, "flare", "OVERLAY", 3),
        }
    end

    -- Spotlight look: the shaft of light from above (the soft halo image
    -- stretched tall, so it fades out at the top and sides).
    -- The soft round glow's top half (bright at the bottom edge, fading up and
    -- out), so it reads as light pouring down onto the ground, not an outline.
    glow.spotShaft = Layer(glow, "glow", "ARTWORK", -3)
    glow.spotShaft:SetTexCoord(0, 1, 0, 0.5)

    -- Rune circle look: our own rune art, once it exists; the plain ring
    -- until then.
    glow.rune = Layer(glow, "ring", "ARTWORK", 1)
    if glow.rune:SetTexture(ART .. "rune.tga") == false then
        glow.rune:SetTexture(ART .. "ring.tga")
    end

    -- Storm cloud look: the cloud (drawn normally, its own shading kept) and the
    -- lightning (added on top so it glows).
    glow.stormCloud = Layer(glow, "storm_cloud", "OVERLAY", 3, "BLEND")
    glow.stormBolt = Layer(glow, "storm_bolts", "OVERLAY", 4, "ADD")

    -- Target lock look: the reticle lying on the ground.
    glow.reticle = Layer(glow, "reticle", "ARTWORK", 1, "ADD")

    -- Halo and rays look: the fan of light behind everything, and the halo ring.
    glow.rays = Layer(glow, "rays", "ARTWORK", -2, "ADD")
    glow.haloRing = Layer(glow, "ring", "OVERLAY", 2, "ADD")

    glow.appear, glow.ready, glow.phase, glow.spin, glow.nextPing = 0, 0, 0, 0, 0.5
    glow.r, glow.g, glow.b = 1, 1, 1
    glow:SetScript("OnUpdate", Animate)
end

local function HideGlow()
    NodeHighlight.soundFor = nil -- the next node you come to plays its sound again
    if glow then glow.soundPending = false end
    if glow and glow:IsShown() then glow:Hide() end
end

local function SoftTargetExists()
    local okUnit, isUnit = pcall(UnitExists, SOFT)
    if okUnit and isUnit == true then return true end
    if UnitIsGameObject then
        local okObj, isObject = pcall(UnitIsGameObject, SOFT)
        if okObj and isObject == true then return true end
    end
    return false
end

local function Refresh()
    if not (XalsXRDB and XalsXRDB.nodeHighlightEnabled) or not SoftTargetExists() then
        HideGlow()
        return
    end

    local kind, unable = Classify(SOFT)
    if kind == "herb" or kind == "ore" then
        -- Remember gathered objects so looting one never teaches "chest".
        local id = ObjectID(SOFT)
        if id then
            NodeHighlight.gatheredIDs = NodeHighlight.gatheredIDs or {}
            NodeHighlight.gatheredIDs[id] = true
            if XalsXRDB.nodeHighlightContainers then XalsXRDB.nodeHighlightContainers[id] = nil end
        end
    elseif kind == "quest" then
        if XalsXRDB.nodeHighlightQuest == false then HideGlow() return end
    elseif kind == "chest" then
        if XalsXRDB.nodeHighlightChest == false then HideGlow() return end
    else
        HideGlow()
        return
    end

    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, SOFT)
    if not ok or not plate then
        HideGlow()
        return
    end

    if not glow then BuildGlow() end
    local color = COLORS[kind]
    glow.r, glow.g, glow.b = color[1], color[2], color[3]
    glow.unable = unable == true
    -- Herbs burn green, ore burns the natural orange, and everything else (quest
    -- objects, chests) burns violet-blue. The flame art comes in all three hues,
    -- so swap the textures only when the node type changes.
    if glow.fireKind ~= kind then
        glow.fireKind = kind
        local suffix = (kind == "herb" and "_green") or ((kind == "quest" or kind == "chest") and "_blue") or ""
        glow.flame:SetTexture(ART .. "fire_flame" .. suffix .. ".tga")
        glow.flameBack:SetTexture(ART .. "fire_cluster" .. suffix .. ".tga")
        for _, ember in ipairs(glow.embers) do
            ember:SetTexture(ART .. "fire_embers" .. suffix .. ".tga")
        end
    end
    -- Beam color only needs setting when the node type or its state changes.
    local beamKey = kind .. (glow.unable and "-unable" or "")
    if glow.beamKey ~= beamKey then
        glow.beamKey = beamKey
        if glow.unable then
            ApplyBeamColor(glow.beam, 0.6, 0.6, 0.6)
        else
            ApplyBeamColor(glow.beam, Lerp(color[1], 1, 0.35), Lerp(color[2], 1, 0.35), Lerp(color[3], 1, 0.35))
        end
    end
    glow:ClearAllPoints()
    glow:SetPoint("CENTER", plate, "CENTER", 0, -OBJECT_DROP)
    if not glow:IsShown() then
        glow.appear = 0 -- swell in again for a newly picked node
        glow.ready = glow.unable and 0 or 1
        glow:Show()
    end

    -- Arrival sound: the game has picked a real herb or ore you can gather, i.e. the
    -- moment its glow comes up. Once per node (a different node plays it again).
    if (kind == "herb" or kind == "ore") and not glow.unable and addonTable.Sounds then
        local okGuid, guid = pcall(UnitGUID, SOFT)
        if not okGuid or Secret(guid) or type(guid) ~= "string" then guid = "?" end
        if NodeHighlight.soundFor ~= guid then
            NodeHighlight.soundFor = guid
            glow.soundPending = true -- played by Animate once the glow is fully bright
        end
    end
end

--------------------------------------------------------------------------------
-- Wiring
--------------------------------------------------------------------------------
local eventFrame
local elapsedSinceTick = 0

local function OnUpdate(_, elapsed)
    elapsedSinceTick = elapsedSinceTick + elapsed
    if elapsedSinceTick < TICK_SECONDS then return end
    elapsedSinceTick = 0
    Refresh()
end

-- Starts or stops the per-tick check to match the option.
local function SyncRunning()
    if not eventFrame then return end
    if XalsXRDB and XalsXRDB.nodeHighlightEnabled then
        eventFrame:SetScript("OnUpdate", OnUpdate)
    else
        eventFrame:SetScript("OnUpdate", nil)
        HideGlow()
    end
end

-- Called from the settings checkbox.
function NodeHighlight:SetEnabled(enabled)
    if not self.supported or not XalsXRDB then return end
    XalsXRDB.nodeHighlightEnabled = enabled and true or false
    self:Apply()
    SyncRunning()
end

function NodeHighlight:Init()
    if not self.supported or eventFrame then return end

    BuildCursorLookup()

    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("PLAYER_LOGOUT")
    eventFrame:RegisterEvent("PLAYER_SOFT_INTERACT_CHANGED")
    eventFrame:RegisterEvent("LOOT_OPENED")
    eventFrame:SetScript("OnEvent", function(_, event)
        if event == "LOOT_OPENED" then
            LearnContainers()
        elseif event == "PLAYER_ENTERING_WORLD" then
            -- The client resets some of these settings right after loading in,
            -- so apply again a moment later.
            NodeHighlight:Apply()
            C_Timer.After(1, function() NodeHighlight:Apply() end)
        elseif event == "PLAYER_REGEN_ENABLED" then
            if pendingApply then NodeHighlight:Apply() end
        elseif event == "PLAYER_LOGOUT" then
            -- Give the game its own settings back so nothing is left behind if
            -- the addon is disabled or removed; the option stays on and is
            -- applied again at the next login.
            if XalsXRDB and XalsXRDB.nodeHighlightEnabled then
                NodeHighlight:RestoreSettings(false)
            end
        elseif event == "PLAYER_SOFT_INTERACT_CHANGED" then
            Refresh()
        end
    end)

    SyncRunning()
    self:Apply()
end
