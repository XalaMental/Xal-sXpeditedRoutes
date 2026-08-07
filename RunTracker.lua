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
-- and any of YOUR loot inside that window is counted. Loot outside a window (a
-- mob killed between nodes, a quest reward) or a group member's loot is ignored.
local addonName, addonTable = ...
local RunTracker = addonTable.RunTracker
local Helpers = addonTable.Helpers

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
local function AddLoot(msg)
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
        RunTracker.tally[key] = { link = link, icon = icon, count = count }
    end
end

function RunTracker:OnGatherSucceeded(spellID)
    if not self.active then return end
    if not Helpers.DetectGatherType(spellID) then return end
    -- Open (or extend) the window during which loot counts toward the haul.
    self.lootWindowUntil = GetTime() + GATHER_LOOT_WINDOW
end

function RunTracker:OnLoot(msg)
    if not self.active then return end
    if GetTime() > self.lootWindowUntil then return end
    if not IsSelfLoot(msg) then return end
    AddLoot(msg)
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
local FOOTER_PAD = 12
local MAX_ROWS = 15 -- cap the list; anything past this collapses into a "+N more" line

local function BuildFrame()
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    frame = CreateFrame("Frame", "XalsXRHaulFrame", UIParent, template)
    frame:SetWidth(FRAME_WIDTH)
    frame:SetHeight(HEADER_HEIGHT + FOOTER_PAD)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)

    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        frame:SetBackdropColor(0, 0, 0, 0.92)
        frame:SetBackdropBorderColor(0.25, 0.55, 0.75, 1)
    end

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

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -12)
    title:SetTextColor(0, 0.8, 1) -- the addon's blue
    title:SetText("Gather Tally")
    frame.title = title

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    subtitle:SetTextColor(0.7, 0.7, 0.7)
    frame.subtitle = subtitle

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function()
        -- Closing a manual (Gather-button) session ends it - stops tallying/timing.
        -- A route session just hides; PathPlanner is what ends that one.
        if RunTracker.sessionKind == "manual" then RunTracker:EndRun() end
        frame:Hide()
    end)

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
    return frame
end

-- Grabs (or lazily creates) row `index`: an icon, the item's colored link, and a
-- right-aligned count. Rows are pooled on the frame and reused between renders.
local function AcquireRow(index)
    local row = frame.rows[index]
    if row then return row end

    row = CreateFrame("Frame", nil, frame)
    row:SetSize(FRAME_WIDTH - 24, ROW_HEIGHT)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) -- trim the default icon border

    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.count:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.count:SetJustifyH("RIGHT")

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
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

local BASE_ROW_FONT = 12
-- Applies the current icon/font-size options to a pooled row before it's filled.
-- Font size is set absolutely (BASE * scale) so repeated renders never compound.
local function StyleRow(row, showIcons, fontScale, rowH)
    row:SetHeight(rowH)
    local size = BASE_ROW_FONT * fontScale
    local nFont, _, nFlags = row.name:GetFont()
    row.name:SetFont(nFont, size, nFlags)
    local cFont, _, cFlags = row.count:GetFont()
    row.count:SetFont(cFont, size, cFlags)
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

    local list = {}
    local totalItems = 0
    for _, entry in pairs(self.tally) do
        list[#list + 1] = entry
        totalItems = totalItems + entry.count
    end
    table.sort(list, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return (a.link or "") < (b.link or "")
    end)

    local shown = math.min(#list, MAX_ROWS)
    for i = 1, shown do
        local entry = list[i]
        local row = AcquireRow(i)
        StyleRow(row, showIcons, fontScale, rowH)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -(HEADER_HEIGHT + (i - 1) * rowH))
        row.icon:SetTexture(entry.icon or 134400) -- 134400 = generic "question mark" fallback icon
        row.name:SetText(entry.link or "?")
        row.count:SetText("x" .. entry.count)
        row.link = entry.link
        row:Show()
    end

    local usedRows = shown
    if #list > MAX_ROWS then
        usedRows = shown + 1
        local row = AcquireRow(usedRows)
        StyleRow(row, showIcons, fontScale, rowH)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -(HEADER_HEIGHT + shown * rowH))
        row.icon:Hide()
        row.name:SetText("|cff888888+" .. (#list - MAX_ROWS) .. " more types|r")
        row.count:SetText("")
        row.link = nil
        row:Show()
    end

    for i = usedRows + 1, #frame.rows do
        frame.rows[i]:Hide()
    end

    -- Empty state so a freshly-opened window (or a run with nothing yet) isn't blank.
    if #list == 0 then
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

    frame:SetHeight(HEADER_HEIGHT + usedRows * rowH + FOOTER_PAD)
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
