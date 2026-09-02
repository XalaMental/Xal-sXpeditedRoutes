-- RunTracker.lua
-- Xal's Xpedited Routes
--
-- Shows a small, movable "haul window" that tallies what you gather during a
-- route. It opens when a route starts (if enabled in Options), updates live as
-- you gather, and - deliberately - stays open after the route ends so you can
-- read or copy the totals down. You close it yourself with its X button; it
-- never auto-closes. Also summonable anytime with /xxr haul.
--
-- A "run" is bounded by PathPlanner: PlotCourse() starts one and CancelPath()
-- ends one, so this module just gets told StartRun()/EndRun() from there.
--
-- Item counts come from loot: gathering fires UNIT_SPELLCAST_SUCCEEDED (the same
-- signal NodeLogger records nodes from), and the loot lands a beat later as
-- CHAT_MSG_LOOT lines. Each successful gather opens a short "attribution window",
-- and any of YOUR loot inside that window is counted - EXCEPT anything that isn't
-- actually a known gathering material for that type (see KNOWN_MATERIAL_ITEMS) -
-- mob loot (a killed critter, a fish catch) landing in the same few seconds as a
-- real gather doesn't get counted just because of timing. Loot outside a window
-- (a mob killed between nodes, a quest reward) or a group member's loot is
-- ignored regardless.
local addonName, addonTable = ...
local RunTracker = addonTable.RunTracker
local Helpers = addonTable.Helpers
local Brand = addonTable.BrandStyle
local MarkerRenderer = addonTable.MarkerRenderer

-- Seconds after a successful gather during which incoming loot is counted toward
-- the haul. Generous enough to cover auto-loot lag and multi-item nodes, short
-- enough that unrelated loot between nodes almost never lands inside it.
local GATHER_LOOT_WINDOW = 2.5

-- Runtime state for the current run. tally is keyed by itemID so the same item
-- gathered repeatedly just increments one entry.
RunTracker.active = false
RunTracker.tally = {}
RunTracker.startTime = 0
RunTracker.runDuration = nil -- set when a run ends, so the window can show the final time
RunTracker.lootWindowUntil = 0
RunTracker.sessionKind = nil -- "route" (started by PathPlanner) or "manual" (Gather button)
RunTracker.lastKind = nil    -- remembers the kind after a session ends, for the final timer

local frame -- the haul window, built lazily the first time it's shown

-- CHAT_MSG_LOOT fires for everyone's loot, not just yours ("Xal receives loot:").
-- The self-only lines use the LOOT_ITEM_SELF* / LOOT_ITEM_PUSHED_SELF* global
-- format strings, which all start with a fixed literal prefix ("You receive
-- loot: " on enUS). Pulling that literal out of the format string keeps the
-- self-check locale-correct without hardcoding English. If none could be
-- resolved, IsSelfLoot falls back to accepting everything - better to slightly
-- over-count your own runs than to silently tally nothing.
local SELF_LOOT_PREFIXES = {}
do
    local formats = { "LOOT_ITEM_SELF", "LOOT_ITEM_SELF_MULTIPLE",
                      "LOOT_ITEM_PUSHED_SELF", "LOOT_ITEM_PUSHED_SELF_MULTIPLE" }
    for _, name in ipairs(formats) do
        local fmt = _G[name]
        local prefix = fmt and fmt:match("^(.-)%%s")
        if prefix and prefix ~= "" then
            SELF_LOOT_PREFIXES[#SELF_LOOT_PREFIXES + 1] = prefix
        end
    end
end

local function IsSelfLoot(msg)
    if #SELF_LOOT_PREFIXES == 0 then return true end
    for _, prefix in ipairs(SELF_LOOT_PREFIXES) do
        if msg:sub(1, #prefix) == prefix then return true end
    end
    return false
end

-- Version-safe item-info lookup: C_Item.* is the modern namespaced form (retail),
-- the bare global is what older Classic clients expose.
local function GetInstant(itemLink)
    if C_Item and C_Item.GetItemInfoInstant then
        return C_Item.GetItemInfoInstant(itemLink)
    elseif _G.GetItemInfoInstant then
        return _G.GetItemInfoInstant(itemLink)
    end
end

local function FormatDuration(seconds)
    seconds = math.max(0, math.floor(seconds + 0.5))
    if seconds >= 60 then
        return string.format("%dm %ds", math.floor(seconds / 60), seconds % 60)
    end
    return string.format("%ds", seconds)
end

--------------------------------------------------------------------------------
-- Tally capture
--------------------------------------------------------------------------------

-- Known gathering-material item IDs, keyed by type - the tally only counts a
-- gather-attributed item if it's actually in this list. Mob loot (a killed
-- critter, a fish catch) landing within the same attribution window as a
-- real gather was getting miscounted otherwise - confirmed live 2026-08-17
-- (a Fetid Eye and a fur, both real mob loot, ended up in the Lumberjacking
-- section). A GUID-based fix (matching the loot window's real source
-- against the gathered node) was tried first and didn't reliably solve it,
-- so this replaces that approach with an explicit allowlist instead - a fur
-- will never come from an ore node, full stop, regardless of any targeting/
-- timing ambiguity a GUID check depends on.
-- VERIFY BEFORE RELEASE / EXTEND AS NEEDED: only covers materials confirmed
-- in-game or via Wowhead so far (current Midnight tier). Add a new
-- material's item ID here the first time it's confirmed to actually be a
-- gather drop - same maintenance model as Helpers.lua's KNOWN_GATHER_SPELLS.
local KNOWN_MATERIAL_ITEMS = {
    mine = {
        [237359] = true, -- Refulgent Copper Ore
        [237362] = true, -- Umbral Tin Ore (lower-quality variant)
        [237363] = true, -- Umbral Tin Ore
        [237364] = true, -- Brilliant Silver Ore
        [237366] = true, -- Dazzling Thorium
        [236949] = true, -- Mote of Light (bonus proc, also obtainable via Herbalism/Skinning)
    },
    herb = {
        [236761] = true, -- Tranquility Bloom
        [236776] = true, -- Argentleaf
        [236774] = true, -- Azeroot
        [236778] = true, -- Mana Lily
        [236770] = true, -- Sanguithorn
        [236780] = true, -- Nocturnal Lotus (rare bonus proc)
        [236949] = true, -- Mote of Light (bonus proc)
    },
    lumber = {
        [256963] = true, -- Thalassian Lumber
    },
}

-- Pulls the item link and quantity out of a loot chat line and adds it to the
-- tally. The colored item link is stored verbatim so the window can show it with
-- its real quality color (and hover for a tooltip) for free. Quantity is read as
-- the first number after the link ("...|h|rx3."), locale-independently.
local function AddLoot(msg, gatherType)
    -- Retail switched item-link coloring from |cffRRGGBB to |cnIQ<quality>:, so
    -- match any color escape (|c.-) rather than assuming hex digits - the old
    -- hex-only pattern silently matched nothing on modern retail. Fall back to a
    -- bare hyperlink if there's somehow no color wrapper at all.
    local link = msg:match("(|c.-|Hitem:.-|h.-|h|r)")
        or msg:match("(|Hitem:.-|h.-|h)")
    if not link then return end

    local count = 1
    local _, linkEnd = msg:find(link, 1, true)
    if linkEnd then
        local trailing = msg:sub(linkEnd + 1)
        local n = tonumber(trailing:match("(%d+)"))
        if n then count = n end
    end

    local itemID, _, _, _, icon = GetInstant(link)

    -- Reject anything that isn't actually a known material for this gather
    -- type - mob loot (a killed critter, a fish catch) landing in the same
    -- attribution window as a real gather doesn't get counted just because
    -- of timing. Only rejects when we have a real allowlist for this type
    -- AND a resolved itemID to check - never blocks something we simply
    -- couldn't identify.
    if gatherType and KNOWN_MATERIAL_ITEMS[gatherType] and itemID
        and not KNOWN_MATERIAL_ITEMS[gatherType][itemID] then
        return
    end

    local key = itemID or link -- fall back to the link itself if the ID isn't resolvable

    local entry = RunTracker.tally[key]
    if entry then
        entry.count = entry.count + count
    else
        -- type is whichever gathering skill was active when the loot window
        -- opened (see OnGatherSucceeded) - "mine"/"herb"/nil, used to group
        -- the tally window's display. nil is a real possibility (loot from
        -- something Helpers.DetectGatherType doesn't recognize) and gets its
        -- own fallback section rather than being dropped.
        RunTracker.tally[key] = { link = link, icon = icon, count = count, type = gatherType }
    end
end

function RunTracker:OnGatherSucceeded(spellID)
    local gatherType = Helpers.DetectGatherType(spellID)
    if not gatherType then return end
    -- A successful, recognized gather always counts, even if nothing was
    -- already tracking (no active route, never clicked Gather) - see
    -- ResumeOrStartTracking above.
    if not self.active then
        self:ResumeOrStartTracking()
    end
    -- Open (or extend) the window during which loot counts toward the haul,
    -- and remember which profession triggered it so the loot that follows
    -- gets tagged with the right type for grouping.
    self.lootWindowUntil = GetTime() + GATHER_LOOT_WINDOW
    self.lootWindowType = gatherType
end

function RunTracker:OnLoot(msg)
    if not self.active then return end
    if GetTime() > self.lootWindowUntil then return end
    if not IsSelfLoot(msg) then return end
    AddLoot(msg, self.lootWindowType)
    if frame and frame:IsShown() then
        self:Render()
    end
end

--------------------------------------------------------------------------------
-- Run lifecycle (called from PathPlanner)
--------------------------------------------------------------------------------

-- PlotCourse can be called repeatedly within a single run (the helper button
-- re-plots when you toggle a profession on/off), so only a fresh start - one
-- where no run is currently active - resets the tally. A re-plot mid-run keeps
-- everything gathered so far.
function RunTracker:StartRun()
    if self.active then
        -- A manual (Gather-button) session may already be tallying; let the route
        -- take it over so route timing applies, but keep everything gathered so far.
        if self.sessionKind == "manual" then self.sessionKind = "route" end
        return
    end
    self.active = true
    self.sessionKind = "route"
    self.tally = {}
    self.startTime = time()
    self.runDuration = nil
    self.lootWindowUntil = 0
    if not XalsXRDB or XalsXRDB.showHaulSummary ~= false then
        self:ShowWindow()
    end
end

-- Started by the floating Gather button: begins tallying (and timing) outside of
-- a route. If something's already tracking, just surface the window instead.
function RunTracker:StartManualSession()
    if self.active then
        self:ShowWindow()
        return
    end
    self.active = true
    self.sessionKind = "manual"
    self.tally = {}
    self.startTime = time()
    self.runDuration = nil
    self.lootWindowUntil = 0
    self:ShowWindow()
end

-- Called from OnGatherSucceeded when nothing is currently active - resumes
-- tallying into whatever's already there (a route that just completed, a
-- manual session that already ended, or a genuinely fresh empty tally)
-- instead of requiring the player to already be mid-route or have
-- remembered to click Gather first. Deliberately does NOT clear self.tally
-- like StartRun/StartManualSession do - continuing the same haul, not
-- starting a new one. Confirmed 2026-08-17: gathering something should
-- always show up in the tally, not just gathering "on the clock" - mining/
-- herb rarely hit this gap since a route usually stays active the whole
-- session, but lumber nodes are sparse enough that gathering one with
-- nothing active is the common case, not an edge case.
function RunTracker:ResumeOrStartTracking()
    if self.active then return end
    self.active = true
    self.sessionKind = "manual"
    if not self.startTime then
        self.startTime = time()
    end
    self.runDuration = nil
    self.lootWindowUntil = 0
    if not XalsXRDB or XalsXRDB.showHaulSummary ~= false then
        self:ShowWindow()
    end
end

function RunTracker:EndRun()
    if not self.active then return end
    self.active = false
    self.runDuration = time() - self.startTime
    self.lastKind = self.sessionKind
    self.sessionKind = nil
    -- Deliberately do NOT hide the window - leave it up so the player can read or
    -- copy the totals, and close it themselves. Just refresh it to its final
    -- state if it happens to be open.
    if frame and frame:IsShown() then
        self:Render()
    end
end

--------------------------------------------------------------------------------
-- Haul window
--------------------------------------------------------------------------------

local FRAME_WIDTH = 260
local ROW_HEIGHT = 22
local HEADER_HEIGHT = 52
local SECTION_HEADER_HEIGHT = 20
local ROW_INDENT = 10 -- item rows sit slightly indented under their section header
local FOOTER_PAD = 12
local MAX_ROWS = 15 -- cap the list; anything past this collapses into a "+N more" line

-- Grouped display, per-profession - same colors used everywhere else in the
-- addon for mine/herb (MarkerRenderer.MINE_COLOR/HERB_COLOR), not a new
-- palette invented for this window. "other" catches loot whose gather type
-- couldn't be determined (only shown if it actually has anything in it).
local TALLY_GROUPS = {
    { key = "mine", label = "Mining", color = MarkerRenderer.MINE_COLOR },
    { key = "herb", label = "Herbalism", color = MarkerRenderer.HERB_COLOR },
    { key = "lumber", label = "Lumberjacking", color = MarkerRenderer.LUMBER_COLOR },
    { key = "other", label = "Other", color = { 0.6, 0.6, 0.6 } },
}

-- Collapse state per group - expanded by default (unlike Compendium's
-- collapsed-by-default sections): this window's whole purpose is showing
-- your live haul at a glance while gathering, so starting collapsed would
-- work against that. Still collapsible via clicking the header, for anyone
-- who wants to shrink it. Module-level, not persisted - resets each login,
-- same as Compendium's section state.
local sectionCollapsed = {}

-- Compact style: no background/border, orange header, flat borderless item
-- popups instead of grouped rows in a shared panel. Classic keeps today's
-- look exactly. Confirmed 2026-09-01, Compact is the default going forward.
local function IsCompactTally()
    return not (XalsXRDB and XalsXRDB.gatherTallyLayout == "classic")
end

-- Same orange as the floating helper button's "Gather" text link - one
-- color, used consistently across both redesigned pieces.
local TALLY_ORANGE = { 0.72, 0.30, 0.0 }

-- Whether the Compact header is collapsed to just its title bar (title,
-- total count, Close) - toggled by clicking the title. Module-level, not
-- persisted, same convention as sectionCollapsed above. Classic never reads
-- this; the title isn't clickable there.
local compactMinimized = false

-- Pulls the item-quality color out of a colored item link - either the
-- classic |cffRRGGBB hex form or the newer |cnIQ<n>: indexed form (looked
-- up against Blizzard's own ITEM_QUALITY_COLORS table). Falls back to
-- white if neither pattern is found rather than guessing.
local function GetLinkColor(link)
    if not link then return 1, 1, 1 end
    local hex = link:match("|cff(%x%x%x%x%x%x)")
    if hex then
        local r = tonumber(hex:sub(1, 2), 16) / 255
        local g = tonumber(hex:sub(3, 4), 16) / 255
        local b = tonumber(hex:sub(5, 6), 16) / 255
        return r, g, b
    end
    local qIndex = link:match("|cnIQ(%d+):")
    qIndex = qIndex and tonumber(qIndex)
    if qIndex and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[qIndex] then
        local c = ITEM_QUALITY_COLORS[qIndex]
        return c.r, c.g, c.b
    end
    return 1, 1, 1
end

-- Pulls the plain visible name out of a colored item link ("[Refulgent
-- Copper Ore]" -> "Refulgent Copper Ore"). Compact's rows color the whole
-- name via SetTextColor from GetLinkColor above instead of relying on the
-- link's own embedded |c color codes, so they need the bare text here.
local function GetItemNameFromLink(link)
    if not link then return nil end
    return link:match("%[(.-)%]")
end

local function BuildFrame()
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    frame = CreateFrame("Frame", "XalsXRHaulFrame", UIParent, template)
    frame:SetWidth(FRAME_WIDTH)
    frame:SetHeight(HEADER_HEIGHT + FOOTER_PAD)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)

    -- Brand background + border (anchor-based, so the border stays correct
    -- as this window grows/shrinks with the row count). Built unconditionally
    -- and toggled Show/Hide per-style in ApplyTallyStyle() below, rather than
    -- being skipped outright for Compact - keeps a style switch instant with
    -- no rebuild needed.
    frame.bg = Brand.ApplyBackground(frame)
    frame.bgImage = Brand.ApplyBackgroundImage(frame)
    frame.borderTop, frame.borderBottom, frame.borderLeft, frame.borderRight = Brand.DrawBorder(frame)

    -- Draggable, with the position remembered between runs (same approach as the
    -- helper button).
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        if Helpers.IsValidPoint({ point = point, x = x, y = y }) then
            XalsXRDB.haulFramePosition = { point = point, x = x, y = y }
        end
    end)

    local pos = Helpers.SanitizePoint(XalsXRDB and XalsXRDB.haulFramePosition,
        { point = "CENTER", x = 0, y = 60 })
    if XalsXRDB then XalsXRDB.haulFramePosition = pos end
    frame:ClearAllPoints()
    frame:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)

    -- Gather Tally's own top buffer, wider than the standard Brand.SAFE_MARGIN
    -- (14px) - this window runs smaller than the other custom panels, so the
    -- background art's own framing eats into that margin and reads cramped
    -- at the standard value. Flagged directly 2026-08-17.
    local TALLY_TOP_MARGIN = 20

    -- Same title treatment for both styles - only the color changes
    -- (ApplyTallyStyle). This is the addon's one shared branded title look;
    -- the floating helper's "Gather" text was changed to match THIS font
    -- and shadow, not the other way around. Confirmed 2026-09-02.
    local title = Brand.Title(frame, "Gather Tally", 15, "TOPLEFT", frame, "TOPLEFT", TALLY_TOP_MARGIN, -TALLY_TOP_MARGIN)
    title:SetJustifyH("LEFT")
    frame.title = title

    -- Compact-only: clicking the title toggles minimized/expanded. A plain
    -- FontString can't take clicks on its own, so a transparent Button sits
    -- over it instead - sized to the actual rendered text so the hit area
    -- doesn't cover the whole header row. Classic never toggles this (the
    -- click still registers but Render() ignores compactMinimized there).
    local titleClick = CreateFrame("Button", nil, frame)
    titleClick:SetPoint("TOPLEFT", title, "TOPLEFT", 0, 0)
    titleClick:SetSize(math.max(1, title:GetStringWidth()), 18)
    titleClick:SetScript("OnClick", function()
        if not IsCompactTally() then return end
        compactMinimized = not compactMinimized
        RunTracker:Render()
    end)
    frame.titleClick = titleClick

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    -- Bounded on the right too (unlike before) - a long timer+count string
    -- ("Route complete - 1:23:45 - 99 items") had nothing stopping it from
    -- drawing straight past the window's right edge. Found during the
    -- 2026-08-17 border audit, not yet seen live.
    subtitle:SetPoint("RIGHT", frame, "RIGHT", -TALLY_TOP_MARGIN, 0)
    subtitle:SetJustifyH("LEFT")
    -- WordWrap has to stay ON here - WoW only actually respects a
    -- FontString's anchor-derived width when wrap is enabled; with it off,
    -- text just draws straight past the bounds regardless of anchors.
    subtitle:SetWordWrap(true)
    subtitle:SetTextColor(Brand.GOLD[1], Brand.GOLD[2], Brand.GOLD[3])
    frame.subtitle = subtitle

    -- Text-link style close ("Close" in accent gold), not a boxed button -
    -- confirmed preference 2026-08-16, matches every other window now.
    local close = Brand.MakeCloseButton(frame, function()
        -- Closing a manual (Gather-button) session ends it - stops tallying/timing.
        -- A route session just hides; PathPlanner is what ends that one.
        if RunTracker.sessionKind == "manual" then RunTracker:EndRun() end
        frame:Hide()
    end)
    PixelUtil.SetPoint(close, "TOPRIGHT", frame, "TOPRIGHT", -TALLY_TOP_MARGIN, -TALLY_TOP_MARGIN)
    frame.close = close
    frame.TALLY_TOP_MARGIN = TALLY_TOP_MARGIN

    -- Ticks the live timer while a session is active and the window is open.
    frame:SetScript("OnUpdate", function(self, elapsed)
        self._timerTick = (self._timerTick or 0) + elapsed
        if self._timerTick >= 0.5 then
            self._timerTick = 0
            if RunTracker.active and self:IsShown() then
                RunTracker:Render()
            end
        end
    end)

    frame.rows = {}
    frame.headers = {}
    frame.compactRows = {}
    return frame
end

-- Grabs (or lazily creates) the colored section header for group `key` -
-- pooled by key rather than by index (only ever 3 possible groups, and a
-- stable key means the same header frame keeps its own click handler across
-- renders instead of being reassigned one every time).
local function AcquireHeader(key, label, color)
    local header = frame.headers[key]
    if header then return header end

    header = CreateFrame("Button", nil, frame)
    header:SetSize(FRAME_WIDTH - 24, SECTION_HEADER_HEIGHT)

    header.bar = header:CreateTexture(nil, "ARTWORK")
    header.bar:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 2)
    header.bar:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 2)
    header.bar:SetWidth(3)
    header.bar:SetColorTexture(color[1], color[2], color[3], 1)

    header.label = Brand.BodyFS(header, label, 12, color[1], color[2], color[3])
    header.label:SetPoint("LEFT", header.bar, "RIGHT", 6, 0)
    header.label:SetJustifyH("LEFT")

    header.count = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    header.count:SetPoint("RIGHT", header, "RIGHT", -6, 0)
    header.count:SetJustifyH("RIGHT")

    header:SetScript("OnClick", function()
        sectionCollapsed[key] = not sectionCollapsed[key]
        RunTracker:Render()
    end)

    frame.headers[key] = header
    return header
end

local BASE_ROW_FONT = 12

-- Grabs (or lazily creates) row `index`: an icon, the item's colored link, and a
-- right-aligned count. Rows are pooled on the frame and reused between renders.
local function AcquireRow(index)
    local row = frame.rows[index]
    if row then return row end

    row = CreateFrame("Frame", nil, frame)
    -- Rows sit ROW_INDENT further right than headers (see Render()), so their
    -- width has to shrink by the same amount or row.count (anchored flush to
    -- the row's own right edge) ends up almost touching the window border
    -- instead of matching the header row's buffer. Flagged directly 2026-08-17.
    row:SetSize(FRAME_WIDTH - 24 - ROW_INDENT, ROW_HEIGHT)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) -- trim the default icon border

    -- Fira Sans Medium for both - count gets an explicit bright warm-white
    -- (not the default GameFontHighlight color) so it doesn't blend into the
    -- background image, confirmed 2026-08-16 ("it blends too much"). Name
    -- keeps no explicit color of its own - the item link's own embedded
    -- quality-color escape codes drive its color, same as before.
    row.count = row:CreateFontString(nil, "OVERLAY")
    row.count:SetFont(Brand.BODY_FONT_PATH, BASE_ROW_FONT, "")
    row.count:SetTextColor(0.92, 0.88, 0.76, 1)
    row.count:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.count:SetJustifyH("RIGHT")

    row.name = row:CreateFontString(nil, "OVERLAY")
    row.name:SetFont(Brand.BODY_FONT_PATH, BASE_ROW_FONT, "")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    -- Hovering a row shows the normal item tooltip, since the link is stored.
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        if not self.link then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(self.link)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    frame.rows[index] = row
    return row
end

-- Compact's item row: icon on the left, name + count on the right, no shared
-- background - each is its own standalone popup rather than a row in a
-- list box. The item-quality color runs across the top, cuts across the
-- corner at an angle (a chamfer - WoW can't draw an actual rounded curve on
-- a flat-color texture the way the mockup's CSS could), then continues
-- halfway down the right edge. The icon also gets a thin colored square
-- behind it as a border. Confirmed 2026-09-01.
local COMPACT_ROW_HEIGHT = 34
local COMPACT_ICON_SIZE = 22
local COMPACT_ROW_WIDTH = FRAME_WIDTH - 24
local COMPACT_CHAMFER = 8
local COMPACT_BORDER_THICKNESS = 2

-- Positions+rotates a texture to form a line from (x1,y1) to (x2,y2), offsets
-- in WoW's own y-up space, relative to row's TOPLEFT corner - same technique
-- QuickButton.lua's hollow-X icons use, just anchored from a corner instead
-- of a center.
local function PlaceRowBar(row, tex, x1, y1, x2, y2, thickness, color)
    local dx, dy = x2 - x1, y2 - y1
    local length = math.max(math.sqrt(dx * dx + dy * dy), 0.1)
    local angle = math.atan2(dy, dx)
    tex:ClearAllPoints()
    tex:SetSize(length, thickness)
    tex:SetPoint("CENTER", row, "TOPLEFT", (x1 + x2) / 2, (y1 + y2) / 2)
    tex:SetRotation(angle)
    tex:SetColorTexture(color[1], color[2], color[3], 1)
    tex:Show()
end

local function AcquireCompactRow(index)
    local row = frame.compactRows[index]
    if row then return row end

    row = CreateFrame("Frame", nil, frame)
    row:SetHeight(COMPACT_ROW_HEIGHT)

    row.topBar = row:CreateTexture(nil, "ARTWORK")
    row.diagonalBar = row:CreateTexture(nil, "ARTWORK")
    row.rightBar = row:CreateTexture(nil, "ARTWORK")

    row.iconBorder = row:CreateTexture(nil, "BACKGROUND")
    row.iconBorder:SetSize(COMPACT_ICON_SIZE + 4, COMPACT_ICON_SIZE + 4)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(COMPACT_ICON_SIZE, COMPACT_ICON_SIZE)
    row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -8)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.iconBorder:SetPoint("CENTER", row.icon, "CENTER", 0, 0)

    row.count = row:CreateFontString(nil, "OVERLAY")
    row.count:SetFont(Brand.BODY_FONT_PATH, 12, "")
    row.count:SetTextColor(0.92, 0.88, 0.76, 1)
    row.count:SetShadowColor(0, 0, 0, 1)
    row.count:SetShadowOffset(2, -2)
    row.count:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, -10)
    row.count:SetJustifyH("RIGHT")

    row.name = row:CreateFontString(nil, "OVERLAY")
    row.name:SetFont(Brand.BODY_FONT_PATH, 13, "")
    row.name:SetShadowColor(0, 0, 0, 1)
    row.name:SetShadowOffset(2, -2)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.name:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        if not self.link then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(self.link)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    frame.compactRows[index] = row
    return row
end

-- Applies the current icon/font-size options to a pooled row before it's filled.
-- Font size is set absolutely (BASE * scale) so repeated renders never compound.
-- Sets the font PATH directly (Brand.BODY_FONT_PATH) instead of reading it
-- back via row.name:GetFont() first - if the font file ever fails to load
-- for any reason (confirmed live 2026-08-16: threw "bad argument #1 to
-- SetFont" because GetFont() returned nil, meaning the very first SetFont
-- in AcquireRow silently failed and left the fontstring with no font at
-- all), the old round-trip pattern would just keep re-feeding that nil
-- back into SetFont forever. Setting the known-good path directly every
-- time means a failed load only ever costs one render, never a hard error.
local function StyleRow(row, showIcons, fontScale, rowH)
    row:SetHeight(rowH)
    local size = BASE_ROW_FONT * fontScale
    row.name:SetFont(Brand.BODY_FONT_PATH, size, "")
    row.count:SetFont(Brand.BODY_FONT_PATH, size, "")
    row.name:ClearAllPoints()
    if showIcons then
        row.icon:Show()
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    else
        row.icon:Hide()
        row.name:SetPoint("LEFT", row, "LEFT", 0, 0)
    end
    row.name:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
end

-- Shows/hides the background+border and recolors the header for whichever
-- style is currently selected. Cheap enough to call on every render rather
-- than only on a style change - always leaves the frame in a correct state
-- regardless of what it looked like before.
local function ApplyTallyStyle()
    local compact = IsCompactTally()
    frame.bg:SetShown(not compact)
    frame.bgImage:SetShown(not compact)
    frame.borderTop:SetShown(not compact)
    frame.borderBottom:SetShown(not compact)
    frame.borderLeft:SetShown(not compact)
    frame.borderRight:SetShown(not compact)

    if compact then
        frame.title:SetTextColor(TALLY_ORANGE[1], TALLY_ORANGE[2], TALLY_ORANGE[3])
        frame.subtitle:SetTextColor(TALLY_ORANGE[1], TALLY_ORANGE[2], TALLY_ORANGE[3])
    else
        frame.title:SetTextColor(Brand.ACCENT[1], Brand.ACCENT[2], Brand.ACCENT[3])
        frame.subtitle:SetTextColor(Brand.GOLD[1], Brand.GOLD[2], Brand.GOLD[3])
    end
end

-- Builds the subtitle text shared by both styles: Classic keeps the full
-- "Gathering - 1:23 - 6 items" phrasing; Compact drops the verb entirely
-- (the "Gather Tally" title already says what this is - confirmed
-- 2026-09-01, "it already says gather tally, gathered is redundant") and
-- just shows the timer (if enabled) and the count.
local function BuildSubtitleText(compact, totalItems)
    local kind = (RunTracker.active and RunTracker.sessionKind) or RunTracker.lastKind
    local showTimer = (kind == "route" and XalsXRDB and XalsXRDB.haulRouteTimer)
        or (kind == "manual" and XalsXRDB and XalsXRDB.haulGatherTimer)
    local duration = RunTracker.active and (time() - RunTracker.startTime) or (RunTracker.runDuration or 0)
    local countText = string.format("%d item%s", totalItems, totalItems == 1 and "" or "s")

    if compact then
        local parts = {}
        if showTimer then parts[#parts + 1] = FormatDuration(duration) end
        parts[#parts + 1] = countText
        return table.concat(parts, "  -  ")
    end

    local verb
    if RunTracker.active then
        verb = "Gathering"
    elseif kind == "manual" then
        verb = "Session ended"
    else
        verb = "Route complete"
    end
    local parts = { verb }
    if showTimer then parts[#parts + 1] = FormatDuration(duration) end
    parts[#parts + 1] = countText
    return table.concat(parts, "  -  ")
end

-- Classic rendering - unchanged from the original grouped-panel layout.
local function RenderClassic()
    local showIcons = not (XalsXRDB and XalsXRDB.haulShowIcons == false)
    local fontScale = (XalsXRDB and XalsXRDB.haulFontScale) or 1
    local rowH = math.floor(ROW_HEIGHT * fontScale + 0.5)

    -- Split into the four fixed groups (mine/herb/lumber/other) instead of one
    -- flat list - "other" is whatever couldn't be typed at gather time (see
    -- OnGatherSucceeded/AddLoot).
    local buckets = { mine = {}, herb = {}, lumber = {}, other = {} }
    local totalItems = 0
    for _, entry in pairs(RunTracker.tally) do
        local bucketKey = buckets[entry.type] and entry.type or "other"
        table.insert(buckets[bucketKey], entry)
        totalItems = totalItems + entry.count
    end
    local sortFn = function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return (a.link or "") < (b.link or "")
    end
    for _, group in ipairs(TALLY_GROUPS) do
        table.sort(buckets[group.key], sortFn)
    end

    local totalKinds = 0
    for _, group in ipairs(TALLY_GROUPS) do
        totalKinds = totalKinds + #buckets[group.key]
    end

    -- MAX_ROWS is a GLOBAL cap across every group combined, not per-group -
    -- a header still shows (with its real "N kinds" count) even if the cap
    -- was already hit by an earlier group and none of its own rows fit; the
    -- "+N more types" line below covers the overall shortfall either way.
    local usedRows = 0
    local rowIndex = 0
    local contentY = HEADER_HEIGHT
    local rowsShownSoFar = 0

    for _, group in ipairs(TALLY_GROUPS) do
        local entries = buckets[group.key]
        if #entries > 0 then
            local header = AcquireHeader(group.key, group.label, group.color)
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -contentY)
            header.count:SetText(string.format("%d kind%s", #entries, #entries == 1 and "" or "s"))
            header:Show()
            contentY = contentY + SECTION_HEADER_HEIGHT

            if not sectionCollapsed[group.key] then
                for _, entry in ipairs(entries) do
                    if rowsShownSoFar < MAX_ROWS then
                        rowIndex = rowIndex + 1
                        rowsShownSoFar = rowsShownSoFar + 1
                        local row = AcquireRow(rowIndex)
                        StyleRow(row, showIcons, fontScale, rowH)
                        row:ClearAllPoints()
                        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 12 + ROW_INDENT, -contentY)
                        row.icon:SetTexture(entry.icon or 134400) -- 134400 = generic "question mark" fallback icon
                        row.name:SetText(entry.link or "?")
                        row.count:SetText("x" .. entry.count)
                        row.link = entry.link
                        row:Show()
                        contentY = contentY + rowH
                    end
                end
            end
        end
    end
    usedRows = rowIndex

    if totalKinds > MAX_ROWS then
        rowIndex = rowIndex + 1
        local row = AcquireRow(rowIndex)
        StyleRow(row, showIcons, fontScale, rowH)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 12 + ROW_INDENT, -contentY)
        row.icon:Hide()
        row.name:SetText("|cff888888+" .. (totalKinds - MAX_ROWS) .. " more types|r")
        row.count:SetText("")
        row.link = nil
        row:Show()
        contentY = contentY + rowH
        usedRows = rowIndex
    end

    for i = usedRows + 1, #frame.rows do
        frame.rows[i]:Hide()
    end
    for _, group in ipairs(TALLY_GROUPS) do
        if #buckets[group.key] == 0 and frame.headers[group.key] then
            frame.headers[group.key]:Hide()
        end
    end

    -- Empty state so a freshly-opened window (or a run with nothing yet) isn't blank.
    if totalKinds == 0 then
        local row = AcquireRow(1)
        StyleRow(row, showIcons, fontScale, rowH)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -HEADER_HEIGHT)
        row.icon:Hide()
        row.name:SetText("|cff888888Nothing gathered yet...|r")
        row.count:SetText("")
        row.link = nil
        row:Show()
        usedRows = 1
        contentY = HEADER_HEIGHT + rowH
    end

    frame.subtitle:SetText(BuildSubtitleText(false, totalItems))

    -- contentY already tracked the real accumulated height as headers and
    -- rows were laid out (they're no longer a uniform height, unlike the old
    -- flat list), so use that directly instead of re-deriving it.
    frame:SetHeight(contentY + FOOTER_PAD)
end

-- Compact rendering - flat list (no per-profession headers/grouping), each
-- item its own standalone borderless popup. Collapses to just the header
-- bar when compactMinimized is set (toggled by clicking the title).
local function RenderCompact()
    -- Hide every Classic-only pooled frame - Compact never uses them.
    for _, row in ipairs(frame.rows) do row:Hide() end
    for _, header in pairs(frame.headers) do header:Hide() end

    local flat = {}
    local totalItems = 0
    for _, entry in pairs(RunTracker.tally) do
        table.insert(flat, entry)
        totalItems = totalItems + entry.count
    end
    table.sort(flat, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return (a.link or "") < (b.link or "")
    end)

    frame.subtitle:SetText(BuildSubtitleText(true, totalItems))

    if compactMinimized then
        for _, row in ipairs(frame.compactRows) do row:Hide() end

        frame.subtitle:ClearAllPoints()
        frame.subtitle:SetPoint("LEFT", frame.title, "RIGHT", 10, 0)
        frame.close:ClearAllPoints()
        frame.close:SetPoint("LEFT", frame.subtitle, "RIGHT", 14, 0)

        frame:SetHeight(frame.TALLY_TOP_MARGIN * 2 + 16)
        return
    end

    -- Expanded: header stays in its normal two-line spot, item popups drop
    -- down below it.
    frame.subtitle:ClearAllPoints()
    frame.subtitle:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -4)
    frame.subtitle:SetPoint("RIGHT", frame, "RIGHT", -frame.TALLY_TOP_MARGIN, 0)
    frame.close:ClearAllPoints()
    PixelUtil.SetPoint(frame.close, "TOPRIGHT", frame, "TOPRIGHT", -frame.TALLY_TOP_MARGIN, -frame.TALLY_TOP_MARGIN)

    local contentY = HEADER_HEIGHT
    local rowIndex = 0
    local shown = 0

    -- Plain single-line top bar for the two utility rows (empty state, "+N
    -- more") - no chamfer, no icon border, they're not real items.
    local function ShowUtilityRow(row, text)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -contentY)
        row:SetWidth(COMPACT_ROW_WIDTH)
        PlaceRowBar(row, row.topBar, 0, -1, COMPACT_ROW_WIDTH, -1, COMPACT_BORDER_THICKNESS, { 0.5, 0.5, 0.5 })
        row.diagonalBar:Hide()
        row.rightBar:Hide()
        row.iconBorder:Hide()
        row.icon:Hide()
        row.name:ClearAllPoints()
        row.name:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.name:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.name:SetText(text)
        row.count:SetText("")
        row.link = nil
        row:Show()
        contentY = contentY + COMPACT_ROW_HEIGHT
    end

    if #flat == 0 then
        ShowUtilityRow(AcquireCompactRow(1), "|cff888888Nothing gathered yet...|r")
        rowIndex = 1
    else
        local half = COMPACT_ROW_HEIGHT / 2
        for _, entry in ipairs(flat) do
            if shown < MAX_ROWS then
                rowIndex = rowIndex + 1
                shown = shown + 1
                local row = AcquireCompactRow(rowIndex)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -contentY)
                row:SetWidth(COMPACT_ROW_WIDTH)

                local r, g, b = GetLinkColor(entry.link)
                local color = { r, g, b }
                -- Top edge, chamfered corner, then halfway down the right
                -- edge - one continuous line built from three rotated bars,
                -- same technique the floating button's icons use.
                PlaceRowBar(row, row.topBar, 0, -1, COMPACT_ROW_WIDTH - COMPACT_CHAMFER, -1,
                    COMPACT_BORDER_THICKNESS, color)
                PlaceRowBar(row, row.diagonalBar, COMPACT_ROW_WIDTH - COMPACT_CHAMFER, -1,
                    COMPACT_ROW_WIDTH, -(1 + COMPACT_CHAMFER), COMPACT_BORDER_THICKNESS, color)
                PlaceRowBar(row, row.rightBar, COMPACT_ROW_WIDTH, -(1 + COMPACT_CHAMFER),
                    COMPACT_ROW_WIDTH, -half, COMPACT_BORDER_THICKNESS, color)

                row.iconBorder:SetColorTexture(r, g, b, 1)
                row.iconBorder:Show()
                row.icon:Show()
                row.icon:SetTexture(entry.icon or 134400)
                row.name:ClearAllPoints()
                row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
                row.name:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
                row.name:SetTextColor(r, g, b)
                row.name:SetText(GetItemNameFromLink(entry.link) or "?")
                row.count:SetText("x" .. entry.count)
                row.link = entry.link
                row:Show()
                contentY = contentY + COMPACT_ROW_HEIGHT
            end
        end

        if #flat > MAX_ROWS then
            rowIndex = rowIndex + 1
            ShowUtilityRow(AcquireCompactRow(rowIndex), "|cff888888+" .. (#flat - MAX_ROWS) .. " more|r")
        end
    end

    for i = rowIndex + 1, #frame.compactRows do
        frame.compactRows[i]:Hide()
    end

    frame:SetHeight(contentY + FOOTER_PAD)
end

-- Repaints the window from the current tally. Called live on each gather, on a
-- half-second tick while active (so the timer moves), and once when a run ends.
function RunTracker:Render()
    if not frame then return end
    ApplyTallyStyle()
    if IsCompactTally() then
        RenderCompact()
    else
        RenderClassic()
    end
end

function RunTracker:ShowWindow()
    if not frame then BuildFrame() end
    frame:Show()
    self:Render()
end

-- Called by the Options checkbox: hide immediately when turned off; if turned on
-- mid-route, pop the window up right away.
function RunTracker:OnSettingChanged()
    if XalsXRDB and XalsXRDB.showHaulSummary == false then
        if frame then frame:Hide() end
    elseif self.active then
        self:ShowWindow()
    end
end

-- Backing "/xxr haul": show the window for the current run, or the last one that
-- hasn't been overwritten yet; otherwise say there's nothing.
function RunTracker:ShowHaulCommand()
    if self.active or next(self.tally) ~= nil then
        self:ShowWindow()
    else
        print("|cff00ccffXal's XR:|r Nothing tracked yet - hit the Gather button or start a route.")
    end
end

--------------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------------

function RunTracker:Init()
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    eventFrame:RegisterEvent("CHAT_MSG_LOOT")
    eventFrame:SetScript("OnEvent", function(_, event, ...)
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            local unit, _, spellID = ...
            if unit == "player" then
                RunTracker:OnGatherSucceeded(spellID)
            end
        elseif event == "CHAT_MSG_LOOT" then
            local msg = ...
            RunTracker:OnLoot(msg)
        end
    end)
end
