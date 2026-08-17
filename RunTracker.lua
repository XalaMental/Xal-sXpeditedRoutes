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
-- and any of YOUR loot inside that window is counted - EXCEPT if a loot window
-- opens whose real source isn't the node you just gathered (a mob corpse, a
-- fish catch landing in the same few seconds), confirmed via GetLootSourceInfo
-- against the node's own GUID (see OnLootOpened) - that loot window closes the
-- attribution early so its items never get miscounted. Loot outside a window (a
-- mob killed between nodes, a quest reward) or a group member's loot is ignored.
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

-- True only for a real GameObject GUID (the type gathering nodes actually
-- are) - WoW GUIDs are type-prefixed strings ("GameObject-...", "Creature-
-- ...", "Player-...", etc.). Used to sanity-check that "target" really was
-- the node we just gathered before trusting it for loot-source matching -
-- if this ever comes back false (target changed, gathering doesn't set a
-- target in some edge case), the source-GUID check below just doesn't run
-- rather than risk falsely excluding a real gather.
local function IsGameObjectGUID(guid)
    return guid ~= nil and guid:match("^GameObject%-") ~= nil
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
    -- The node's own GUID (gathering targets the object you interact with) -
    -- used by OnLootOpened below to confirm a loot window opening inside
    -- this attribution window is actually THIS node, not unrelated loot
    -- (a mob corpse, a fish catch) that happened to land in the same few
    -- seconds. nil (not gated) if "target" doesn't look like a real object.
    local guid = UnitGUID("target")
    self.lootWindowSourceGUID = IsGameObjectGUID(guid) and guid or nil
end

-- Fires right when a loot window opens - before any CHAT_MSG_LOOT lines for
-- it arrive, so this can close the attribution window in time to stop
-- unrelated loot (see IsGameObjectGUID comment above) from being counted.
-- Confirmed live 2026-08-17: a Remora Fish's junk loot, killed right after
-- chopping wood, was getting miscounted into the Lumberjacking tally.
function RunTracker:OnLootOpened()
    if not self.lootWindowSourceGUID then return end
    if GetTime() > self.lootWindowUntil then return end
    if not (GetNumLootItems and GetLootSourceInfo) then return end

    local matched = false
    for i = 1, GetNumLootItems() do
        local sources = { GetLootSourceInfo(i) }
        for j = 1, #sources, 2 do
            if sources[j] == self.lootWindowSourceGUID then
                matched = true
                break
            end
        end
        if matched then break end
    end

    if not matched then
        self.lootWindowUntil = 0
    end
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

local function BuildFrame()
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    frame = CreateFrame("Frame", "XalsXRHaulFrame", UIParent, template)
    frame:SetWidth(FRAME_WIDTH)
    frame:SetHeight(HEADER_HEIGHT + FOOTER_PAD)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)

    -- Brand background + border (anchor-based, so the border stays correct
    -- as this window grows/shrinks with the row count).
    Brand.ApplyBackground(frame)
    Brand.ApplyBackgroundImage(frame)
    Brand.DrawBorder(frame)

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

    local title = Brand.Title(frame, "Gather Tally", 15, "TOPLEFT", frame, "TOPLEFT", TALLY_TOP_MARGIN, -TALLY_TOP_MARGIN)
    title:SetJustifyH("LEFT")
    frame.title = title

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

-- Repaints the window from the current tally. Called live on each gather, on a
-- half-second tick while active (so the timer moves), and once when a run ends.
function RunTracker:Render()
    if not frame then return end

    local showIcons = not (XalsXRDB and XalsXRDB.haulShowIcons == false)
    local fontScale = (XalsXRDB and XalsXRDB.haulFontScale) or 1
    local rowH = math.floor(ROW_HEIGHT * fontScale + 0.5)

    -- Split into the four fixed groups (mine/herb/lumber/other) instead of one
    -- flat list - "other" is whatever couldn't be typed at gather time (see
    -- OnGatherSucceeded/AddLoot).
    local buckets = { mine = {}, herb = {}, lumber = {}, other = {} }
    local totalItems = 0
    for _, entry in pairs(self.tally) do
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

    -- Timer line: shown only when the matching toggle is on for this session kind.
    -- Gather Timer covers manual (Gather-button) sessions; Route Timer covers routes.
    -- Both default off, so by default the subtitle is just the item count.
    local kind = (self.active and self.sessionKind) or self.lastKind
    local showTimer = (kind == "route" and XalsXRDB and XalsXRDB.haulRouteTimer)
        or (kind == "manual" and XalsXRDB and XalsXRDB.haulGatherTimer)
    local duration = self.active and (time() - self.startTime) or (self.runDuration or 0)

    local verb
    if self.active then
        verb = "Gathering"
    elseif kind == "manual" then
        verb = "Session ended"
    else
        verb = "Route complete"
    end

    local parts = { verb }
    if showTimer then parts[#parts + 1] = FormatDuration(duration) end
    parts[#parts + 1] = string.format("%d item%s", totalItems, totalItems == 1 and "" or "s")
    frame.subtitle:SetText(table.concat(parts, "  -  "))

    -- contentY already tracked the real accumulated height as headers and
    -- rows were laid out (they're no longer a uniform height, unlike the old
    -- flat list), so use that directly instead of re-deriving it.
    frame:SetHeight(contentY + FOOTER_PAD)
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
    eventFrame:RegisterEvent("LOOT_OPENED")
    eventFrame:SetScript("OnEvent", function(_, event, ...)
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            local unit, _, spellID = ...
            if unit == "player" then
                RunTracker:OnGatherSucceeded(spellID)
            end
        elseif event == "CHAT_MSG_LOOT" then
            local msg = ...
            RunTracker:OnLoot(msg)
        elseif event == "LOOT_OPENED" then
            RunTracker:OnLootOpened()
        end
    end)
end
