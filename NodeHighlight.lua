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
}

-- Forever is the only client this runs on (WOW_PROJECT_CAMELOT is nil
-- everywhere else, so this is false on Retail and Classic).
NodeHighlight.supported = WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT

function NodeHighlight:IsSupported()
    return self.supported
end

-- The looks the settings page offers.
NodeHighlight.STYLES = { "fire", "beam", "pulse", "sparkle", "spotlight", "rune" }
NodeHighlight.STYLE_LABELS = {
    fire = "Fire", beam = "Beam", pulse = "Pulse",
    sparkle = "Sparkle", spotlight = "Spotlight", rune = "Rune Circle",
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

-- Returns "herb" or "ore" (and whether the game says it can't be gathered
-- right now) for the unit, or nil for anything else.
local function Classify(unit)
    if not probe then
        probe = UIParent:CreateTexture(nil, "BACKGROUND")
        probe:Hide()
    end
    local ok, hasCursor = pcall(SetUnitCursorTexture, probe, unit, nil, true)
    if not ok or not hasCursor then return nil end

    local texture = probe:GetTexture()
    local atlas = probe.GetAtlas and probe:GetAtlas()
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
    return nil
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
    Off(self.spotShaft); Off(self.rune); Off(self.domeFill)
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

    glow.appear, glow.ready, glow.phase, glow.spin, glow.nextPing = 0, 0, 0, 0, 0.5
    glow.r, glow.g, glow.b = 1, 1, 1
    glow:SetScript("OnUpdate", Animate)
end

local function HideGlow()
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
    if kind ~= "herb" and kind ~= "ore" then
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
    -- Herbs burn green, ore burns the natural orange. The flame art comes in
    -- both hues, so swap the textures only when the node type changes.
    if glow.fireKind ~= kind then
        glow.fireKind = kind
        local suffix = kind == "herb" and "_green" or ""
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
    eventFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_ENTERING_WORLD" then
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
