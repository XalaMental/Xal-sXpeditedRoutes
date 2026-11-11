-- LiveScan.lua
-- Xal's Xpedited Routes
--
-- WoW: Forever only, OFF by default (Options -> Live Nodes).
--
-- Finds out which of YOUR SAVED nodes are actually live right now, by asking
-- the game's own minimap. With Find Herbs / Find Minerals on, the game draws a
-- dot on the minimap for every real node, but it never tells an addon where
-- those dots are. What it does do is name the dot under the real mouse
-- (C_TooltipInfo.GetMinimapMouseover). So a scan slides the minimap under the
-- mouse so that each saved node's spot sits right under it, one spot per frame,
-- and reads the name the game gives back the next frame: a name means the node
-- is there. (Minimap:AdjustPointsOffset is what moves it; the move is undone by
-- the exact opposite at the end of the scan.)
--
-- Because we already know where the nodes should be, a scan only checks those
-- few spots - not a sweep of the whole minimap - so it is short.
--
-- While it runs the minimap is drawn blank (an empty mask, put back after), the
-- addon buttons riding on it are made invisible and click-proof (so none of
-- them slide under your mouse and eat a click), and tooltips are suppressed.
-- Anything that goes wrong - combat starting, a mouse button pressed, a zone
-- change, an error, or just taking too long - puts everything back at once.
--
-- Results go to Markers.lua (live nodes pulse, checked-and-empty ones fade) and
-- to the arrow at the bottom of this file (points at the nearest live node).
--
-- Ways to start a scan, all only when the scanner is enabled:
--   * the "Scan for live nodes" key binding (Options -> Keybindings -> AddOns)
--   * /xxr scan
--   * optionally on a timer (adjustable seconds)
--   * optionally each time you've walked a set distance (adjustable yards)
--   * optionally once after a fight ends, a landing or dismount, or a loading screen
-- Automatic scans never run while you're casting, gathering, aiming a spell, have
-- a loot window open or something is under the mouse.
local addonName, addonTable = ...
local LiveScan = addonTable.LiveScan
local Markers = addonTable.Markers
local Helpers = addonTable.Helpers
local Engine = addonTable.Engine
local Brand = addonTable.BrandStyle

LiveScan.supported = WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT
    and Minimap ~= nil and Minimap.AdjustPointsOffset ~= nil
    and C_TooltipInfo ~= nil and C_TooltipInfo.GetMinimapMouseover ~= nil

local MAX_PROBES = 40          -- spots checked per scan (nearest nodes first)
local WATCHDOG_SECONDS = 5     -- a scan running longer than this is cut off
local AUTO_TICK = 0.5
local EMPTY_MASK = "Interface\\AddOns\\" .. addonName .. "\\Textures\\EmptyMask"
local GAME_MASK_ATLAS = "ui-hud-minimap-frame-generic-mask"
local FIND_HERBS_SPELL, FIND_MINERALS_SPELL = 2383, 2580

-- Key binding text. It sits in the same "Xal's Xpedited Routes" group as the
-- route keybinds (BINDING_HEADER_XALSXPEDITEDROUTES, set in ChatCommands.lua).
BINDING_NAME_XALSXR_LIVESCAN = "Scan for live nodes"

local function Secret(value)
    return issecretvalue ~= nil and issecretvalue(value) == true
end

local function Enabled()
    return XalsXRDB and XalsXRDB.liveScanEnabled == true
end

local function Say(text)
    print("|cff00ccffXal's XR:|r " .. text)
end

local scan             -- the scan in progress, or nil
local quietUntil = 0   -- tooltips stay suppressed until this time
local lastScanAt = 0
local lastScanPos      -- { x, y, instance } where the last scan started
LiveScan.debug = false

--------------------------------------------------------------------------------
-- The minimap's own mask, so it can be put back exactly
--------------------------------------------------------------------------------
local maskSet, ourMask
if Minimap and Minimap.SetMaskTexture then
    hooksecurefunc(Minimap, "SetMaskTexture", function(_, mask)
        if not ourMask then maskSet = mask end
    end)
end

local function OriginalMask()
    if maskSet ~= nil then return maskSet end
    if GetMinimapShape then
        local ok, shape = pcall(GetMinimapShape)
        if ok and shape == "SQUARE" then return "Interface\\BUTTONS\\WHITE8X8" end
    end
    if C_Texture and C_Texture.GetAtlasExists and C_Texture.GetAtlasExists(GAME_MASK_ATLAS) then
        return GAME_MASK_ATLAS
    end
    return "Textures\\MinimapMask"
end

local function SetMask(mask)
    if not Minimap.SetMaskTexture then return end
    ourMask = true
    pcall(Minimap.SetMaskTexture, Minimap, mask)
    ourMask = false
end

--------------------------------------------------------------------------------
-- Making the scan invisible and click-proof, and undoing it
--------------------------------------------------------------------------------
local function QuietTree(s, parent, depth)
    for _, child in ipairs({ parent:GetChildren() }) do
        if not Secret(child) then
            if child.IsMouseClickEnabled and child:IsMouseClickEnabled() then
                s.noClicks[#s.noClicks + 1] = child
                pcall(child.SetMouseClickEnabled, child, false)
            end
            if child.IsMouseMotionEnabled and child:IsMouseMotionEnabled() then
                s.noMotion[#s.noMotion + 1] = child
                pcall(child.SetMouseMotionEnabled, child, false)
            end
            if depth < 4 then QuietTree(s, child, depth + 1) end
        end
    end
end

local function Disguise(s)
    SetMask(EMPTY_MASK)

    -- Everything riding on the minimap (addon buttons, pins) becomes invisible
    -- while it slides, so nothing is seen moving across the screen.
    s.faded = {}
    for _, child in ipairs({ Minimap:GetChildren() }) do
        if not Secret(child) then
            local ok, alpha = pcall(child.GetAlpha, child)
            if ok and not Secret(alpha) then
                s.faded[#s.faded + 1] = { child, alpha }
                pcall(child.SetAlpha, child, 0)
            end
        end
    end

    -- The minimap keeps hover (the game reads the dot under the mouse through
    -- it) but loses clicks and the wheel; everything on it loses both.
    s.noClicks, s.noMotion = {}, {}
    s.wheel = Minimap.IsMouseWheelEnabled and Minimap:IsMouseWheelEnabled()
    if s.wheel then Minimap:EnableMouseWheel(false) end
    if Minimap.IsMouseClickEnabled and Minimap:IsMouseClickEnabled() then
        s.minimapClicks = true
        Minimap:SetMouseClickEnabled(false)
    end
    QuietTree(s, Minimap, 1)
end

local function Restore(s)
    if s.ox and (s.ox ~= 0 or s.oy ~= 0) then
        Minimap:AdjustPointsOffset(-s.ox, -s.oy)
        s.ox, s.oy = 0, 0
    end
    if s.disguised then
        SetMask(OriginalMask())
        for _, entry in ipairs(s.faded or {}) do pcall(entry[1].SetAlpha, entry[1], entry[2]) end
        for _, frame in ipairs(s.noClicks or {}) do pcall(frame.SetMouseClickEnabled, frame, true) end
        for _, frame in ipairs(s.noMotion or {}) do pcall(frame.SetMouseMotionEnabled, frame, true) end
        if s.minimapClicks then Minimap:SetMouseClickEnabled(true) end
        if s.wheel then Minimap:EnableMouseWheel(true) end
        s.disguised = false
    end
end

-- The frame that has the mouse right now (the game only names a minimap dot while
-- the MINIMAP itself has it), as text for the report.
local function MouseFocus()
    local foci = GetMouseFoci and GetMouseFoci()
    local focus = type(foci) == "table" and foci[1] or nil
    if focus == nil or Secret(focus) then return nil, "nothing" end
    if focus == Minimap then return focus, "Minimap" end
    if focus == WorldFrame then return focus, "the world" end
    local name
    if focus.GetDebugName then
        local ok, result = pcall(focus.GetDebugName, focus)
        if ok and type(result) == "string" and not Secret(result) then name = result end
    end
    if not name and focus.GetName then
        local ok, result = pcall(focus.GetName, focus)
        if ok and type(result) == "string" and not Secret(result) then name = result end
    end
    return focus, name or tostring(focus)
end

-- Is this frame part of the minimap: a child of it, or anchored to it?
local function TiedToMinimap(frame)
    local walk = frame
    for _ = 1, 20 do
        if walk == Minimap then return true end
        local ok, parent = pcall(walk.GetParent, walk)
        if not ok or not parent then break end
        walk = parent
    end
    local ok, count = pcall(frame.GetNumPoints, frame)
    if ok and type(count) == "number" then
        for i = 1, count do
            local fine, _, relativeTo = pcall(frame.GetPoint, frame, i)
            if fine and relativeTo == Minimap then return true end
        end
    end
    return false
end

-- Anything on the minimap, or riding with it, that has the mouse gets its hover
-- switched off for the scan (given back after), so the minimap itself has the mouse.
local function Unhover(s)
    local focus = MouseFocus()
    if not focus or focus == Minimap or focus == WorldFrame then return end
    if not TiedToMinimap(focus) then return end
    if focus.IsMouseMotionEnabled and focus:IsMouseMotionEnabled() then
        s.noMotion[#s.noMotion + 1] = focus
        pcall(focus.SetMouseMotionEnabled, focus, false)
    end
    if focus.IsMouseClickEnabled and focus:IsMouseClickEnabled() then
        s.noClicks[#s.noClicks + 1] = focus
        pcall(focus.SetMouseClickEnabled, focus, false)
    end
end

-- Tooltips the minimap and the things riding on it open while sliding under the
-- mouse are closed. (A window's own tooltip, like a bag item, is left alone.)
GameTooltip:HookScript("OnShow", function(tip)
    if scan or GetTime() < quietUntil then tip:Hide() end
end)
local iconTooltip = _G["LibDBIconTooltip"]
if type(iconTooltip) == "table" and iconTooltip.HookScript then
    iconTooltip:HookScript("OnShow", function(tip)
        if scan or GetTime() < quietUntil then tip:Hide() end
    end)
end

--------------------------------------------------------------------------------
-- Reading the game's answer
--------------------------------------------------------------------------------
-- Rare herbs and ore in Classic, by the node's English name (the game's own
-- name for the dot). On a client in another language the names differ, so a
-- rare there is simply shown as an ordinary live node.
local RARE_NAMES = {
    "black lotus", "silver vein", "gold vein", "truesilver deposit",
    "dark iron deposit", "rich thorium vein",
}

local function IsRareName(text)
    local lower = text:lower()
    for _, name in ipairs(RARE_NAMES) do
        if lower:find(name, 1, true) then return true end
    end
    return false
end

-- The text the minimap gives for the spot under the mouse right now, or nil.
local function ReadMouseover()
    local data = C_TooltipInfo.GetMinimapMouseover()
    if Secret(data) or type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
    local text
    for _, line in ipairs(data.lines) do
        local leftText = line and line.leftText
        if type(leftText) == "string" and not Secret(leftText) and leftText ~= "" then
            text = text and (text .. " / " .. leftText) or leftText
        end
    end
    return text
end

--------------------------------------------------------------------------------
-- Whether a scan can start
--------------------------------------------------------------------------------
local function MouseOnWorld()
    local foci = GetMouseFoci and GetMouseFoci()
    local focus = type(foci) == "table" and foci[1] or nil
    return focus == nil or focus == WorldFrame
end

local function MouseBusy()
    return (IsMouselooking and IsMouselooking())
        or (IsMouseButtonDown and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")))
end

-- Something the player is in the middle of that an automatic scan must not
-- interrupt: a cast or channel (gathering is a cast), aiming a spell, a loot
-- window, or a creature/player under the mouse (the next click is probably a loot
-- or target click, and a scan makes the minimap click-proof for a moment).
-- Manual scans (key, button, /xxr scan) ignore this: you asked for them.
local function BusyReason()
    local ok, reason = pcall(function()
        if UnitCastingInfo and UnitCastingInfo("player") then return "you're casting or gathering" end
        if UnitChannelInfo and UnitChannelInfo("player") then return "you're channeling a spell" end
        if SpellIsTargeting and SpellIsTargeting() then return "you're aiming a spell" end
        if LootFrame and LootFrame:IsShown() then return "a loot window is open" end
        if UnitExists and UnitExists("mouseover") then return "something is under the mouse" end
        return nil
    end)
    if ok then return reason end
    return nil
end

-- Is Find Herbs or Find Minerals tracking on? (If the game won't say, assume yes.)
local function TrackingOn()
    if not (C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingInfo) then return true end
    local herb = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(FIND_HERBS_SPELL)
    local mineral = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(FIND_MINERALS_SPELL)
    local sawNames = false
    for i = 1, C_Minimap.GetNumTrackingTypes() do
        local info = C_Minimap.GetTrackingInfo(i)
        if type(info) == "table" and not Secret(info) and type(info.name) == "string" then
            sawNames = true
            if info.active then
                local name = info.name
                if name == herb or name == mineral then return true end
                local lower = name:lower()
                if lower:find("herb", 1, true) or lower:find("mineral", 1, true) then return true end
            end
        end
    end
    return not sawNames
end

-- Returns nil if a scan can start now, or a short reason.
local function WhyNot(auto)
    if not LiveScan.supported then return "not supported on this game version" end
    if scan then return "already scanning" end
    if not Enabled() then return "the scanner is turned off in Options -> Live Nodes" end
    if not Minimap:IsVisible() or not Minimap:GetLeft() then return "the minimap isn't visible" end
    if InCombatLockdown() then return "in combat" end
    local inside = IsInInstance()
    if Secret(inside) or inside then return "not in dungeons or raids" end
    if auto and (not MouseOnWorld() or MouseBusy()) then return "mouse busy" end
    if auto then
        local busy = BusyReason()
        if busy then return busy end
    end
    if not TrackingOn() then return "turn on Find Herbs or Find Minerals first" end
    return nil
end

-- The reason a scan can't start right now (as a short sentence), or nil if one
-- could. Shown on the Live Nodes page so people aren't left guessing.
function LiveScan:WhyNot()
    return WhyNot(false)
end

--------------------------------------------------------------------------------
-- The scan
--------------------------------------------------------------------------------
local driver = CreateFrame("Frame")
driver:Hide()

local function Finish(s, aborted, reason)
    driver:Hide()
    scan = nil
    Restore(s)
    quietUntil = GetTime() + 0.5

    -- Bring back the settings window the Scan now button hid.
    if s.window then
        local window = s.window
        C_Timer.After(0.1, function() window:Show() end)
    end

    if aborted then
        if reason and s.source ~= "auto" then Say("Live scan stopped: " .. reason .. ".") end
        return
    end

    local live, checked = 0, 0
    for _, isLive in pairs(s.results) do
        checked = checked + 1
        if isLive then live = live + 1 end
    end

    if live == 0 then
        -- Nothing answered at all. That can be a real empty patch - but it is
        -- also exactly what a scan that isn't reading the minimap looks like, so
        -- don't fade every marker on the strength of it.
        if s.source ~= "auto" then
            -- Say what had the mouse: the game names a dot only while the minimap has it.
            local parts = {}
            for name, count in pairs(s.focusCounts) do parts[#parts + 1] = name .. " x" .. count end
            table.sort(parts)
            Say(string.format("Live scan checked %d node(s) and none answered. The mouse was over: %s.",
                checked, #parts > 0 and table.concat(parts, ", ") or "(not read)"))
        end
        return
    end

    Markers:SetLiveResults(s.mapID, s.results, s.rare)

    -- Turn what the scan found into a route (or queue it on the end of the one
    -- already going - an existing route is never replaced).
    local PathPlanner = addonTable.PathPlanner
    if PathPlanner and XalsXRDB.liveScanRoute ~= false then
        local liveNodes = {}
        for _, node in ipairs(Markers:GetLiveNodes()) do
            if node.mapID == s.mapID then liveNodes[#liveNodes + 1] = node end
        end
        PathPlanner:AddLiveNodes(s.mapID, liveNodes)
    end

    if s.source ~= "auto" then
        local rareCount = 0
        for _ in pairs(s.rare) do rareCount = rareCount + 1 end
        Say(string.format("Live scan: %d of %d node(s) are live%s.", live, checked,
            rareCount > 0 and (" (" .. rareCount .. " rare)") or ""))
    end
end

local function Step()
    local s = scan
    if not s then return end

    if InCombatLockdown() then return Finish(s, true, "combat started") end
    if GetTime() - s.started > WATCHDOG_SECONDS then return Finish(s, true, "it took too long") end
    if MouseBusy() then return Finish(s, true, "a mouse button was pressed") end

    -- Read what the game said about the spot placed last frame.
    if s.at then
        local target = s.targets[s.at]
        local text = ReadMouseover()
        s.results[target.key] = text ~= nil
        if text and IsRareName(text) then s.rare[target.key] = true end
        local _, focusName = MouseFocus()
        s.lastFocus = focusName
        s.focusCounts[focusName] = (s.focusCounts[focusName] or 0) + 1
        if LiveScan.debug and s.at <= 8 then
            Say(string.format("probe %d %s -> %s   (mouse was over: %s)", s.at, target.key, text or "(nothing)", focusName))
        end
    end

    -- Keep anything tied to the minimap from holding the mouse.
    Unhover(s)

    s.i = s.i + 1
    local target = s.targets[s.i]
    if not target then return Finish(s, false) end

    -- Place this node's spot under the mouse, as it will be next frame when the
    -- game looks (the mouse position is extrapolated one frame ahead).
    local sx, sy = Markers.SpotOf(target.pin)
    if not sx then
        s.at = nil
        return
    end
    local scale = Minimap:GetEffectiveScale()
    local nowX, nowY = GetCursorPosition()
    local cx, cy = 2 * nowX - (s.lastX or nowX), 2 * nowY - (s.lastY or nowY)
    s.lastX, s.lastY = nowX, nowY
    local wantX = cx / scale - sx - s.left
    local wantY = cy / scale - sy - s.bottom
    Minimap:AdjustPointsOffset(wantX - s.ox, wantY - s.oy)
    s.ox, s.oy, s.at = wantX, wantY, s.i
end

local function SafeStep()
    local ok, err = pcall(Step)
    if not ok then
        local s = scan
        if s then Finish(s, true, "an error stopped it") end
        if not LiveScan.errorShown then
            LiveScan.errorShown = true
            Say("Live scan error (the minimap was put back): " .. tostring(err))
        end
    end
end

driver:SetScript("OnUpdate", SafeStep)

local function PlayerWorldPosition()
    if not Engine.HBD then return nil end
    local x, y, instance = Engine.HBD:GetPlayerWorldPosition()
    if x and y then return { x = x, y = y, instance = instance } end
    return nil
end

-- A scan asked for by hand (the Scan now button, /xxr scan, the key) needs the
-- mouse over the game world, since a window under the mouse stops the game from
-- naming any dot. If it isn't there yet - the usual case when you press the
-- button in the settings window - wait a few seconds for you to move it there.
local WAIT_FOR_MOUSE_SECONDS = 10
local waiter = CreateFrame("Frame")
waiter:Hide()
local waitingSource, waitUntil

waiter:SetScript("OnUpdate", function(self)
    if GetTime() > waitUntil then
        self:Hide()
        Say("Live scan cancelled: your mouse never reached the game world.")
        return
    end
    if MouseOnWorld() and not MouseBusy() then
        self:Hide()
        LiveScan:Start(waitingSource, true)
    end
end)

-- The "Scan now" button in the settings window: the window sits on top of the
-- world, so it is hidden for the moment the scan takes and brought back after.
function LiveScan:ScanFromButton(window)
    if not (window and window.IsShown and window:IsShown()) then
        return self:Start("chat")
    end
    window:Hide()
    -- A moment for the mouse button to come up and the world to have the mouse.
    C_Timer.After(0.15, function()
        if not self:Start("button", true, window) then window:Show() end
    end)
end

function LiveScan:Start(source, noWait, window)
    local reason = WhyNot(source == "auto")
    if reason then
        if source ~= "auto" then Say("Live scan not started: " .. reason .. ".") end
        return false
    end

    if source ~= "auto" and not noWait and (not MouseOnWorld() or MouseBusy()) then
        waitingSource, waitUntil = source, GetTime() + WAIT_FOR_MOUSE_SECONDS
        waiter:Show()
        Say("Move your mouse over the game world - the scan starts as soon as it's there.")
        return false
    end

    local targets, mapID = Markers:GetScanTargets()
    if #targets == 0 then
        if source ~= "auto" then Say("Live scan: no saved herb or ore nodes on your minimap right now.") end
        return false
    end
    for i = #targets, MAX_PROBES + 1, -1 do targets[i] = nil end

    lastScanAt = GetTime()
    lastScanPos = PlayerWorldPosition()

    scan = {
        source = source, targets = targets, mapID = mapID, i = 0, results = {}, rare = {}, focusCounts = {},
        ox = 0, oy = 0, left = Minimap:GetLeft(), bottom = Minimap:GetBottom(),
        started = GetTime(), disguised = true, window = window,
    }
    local ok, err = pcall(Disguise, scan)
    if not ok then
        Finish(scan, true, "could not prepare the minimap")
        if not LiveScan.errorShown then
            LiveScan.errorShown = true
            Say("Live scan error (the minimap was put back): " .. tostring(err))
        end
        return false
    end
    driver:Show()
    return true
end

-- Called when you gather a node: the distance walked for "scan by distance"
-- starts counting again from where you're standing now.
function LiveScan:ResetDistance()
    lastScanPos = PlayerWorldPosition()
end

function LiveScan:Stop(reason)
    if scan then Finish(scan, true, reason) end
end

function LiveScan:ToggleDebug()
    self.debug = not self.debug
    Say("Live scan debug " .. (self.debug and "|cff00ff00ON|r" or "|cffff9900OFF|r") .. ".")
end

-- The key binding (the entry in Options > Keybindings).
function XalsXR_LiveScan()
    LiveScan:Start("key")
end

--------------------------------------------------------------------------------
-- The scan key, set right on our settings page: click the button, press a key.
--
-- The key is bound to a small invisible button of ours (a "click" binding), so it
-- works the moment it is set - it doesn't wait for the game to re-read
-- Bindings.xml. The "Scan for live nodes" entry in Options > Keybindings is
-- still there; this page shows and clears whichever of the two is bound.
--------------------------------------------------------------------------------
local KEY_BUTTON_NAME = "XalsXRLiveScanButton"
local KEY_COMMAND = "CLICK " .. KEY_BUTTON_NAME .. ":LeftButton"
local MODIFIER_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true }

local function BoundKeys()
    local keys = {}
    for _, command in ipairs({ KEY_COMMAND, "XALSXR_LIVESCAN" }) do
        for _, key in ipairs({ GetBindingKey(command) }) do keys[#keys + 1] = key end
    end
    return keys
end

function LiveScan:GetKeyText()
    local key = BoundKeys()[1]
    if key then return GetBindingText(key) end
    return NOT_BOUND or "Not bound"
end

function LiveScan:ClearKey()
    if InCombatLockdown() then return false end
    for _, key in ipairs(BoundKeys()) do SetBinding(key) end
    SaveBindings(GetCurrentBindingSet())
    return true
end

local listener, listenerDone
local function StopListening()
    if listener then listener:Hide() end
    local done = listenerDone
    listenerDone = nil
    if done then done() end
end

-- Waits for the next key press and binds it. onDone runs afterwards (also if
-- cancelled with Escape) so the settings button can show the result.
function LiveScan:CaptureKey(onDone)
    if InCombatLockdown() then
        Say("Keys can't be changed in combat.")
        return
    end
    if not listener then
        listener = CreateFrame("Frame")
        listener:SetParent(UIParent)
        listener:SetFrameStrata("FULLSCREEN_DIALOG") -- keys reach it before the options window
        listener:EnableKeyboard(true)
        listener:Hide()
        listener:SetScript("OnKeyDown", function(_, key)
            if key == "ESCAPE" then return StopListening() end
            local ignored = IsKeyPressIgnoredForBinding and IsKeyPressIgnoredForBinding(key) or MODIFIER_KEYS[key]
            if ignored then return end -- a modifier alone: wait for the real key
            if not InCombatLockdown() then
                local chord
                if CreateKeyChordStringUsingMetaKeyState then
                    chord = CreateKeyChordStringUsingMetaKeyState(key)
                else
                    chord = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
                        .. (IsShiftKeyDown() and "SHIFT-" or "") .. key
                end
                LiveScan:ClearKey()
                SetBindingClick(chord, KEY_BUTTON_NAME)
                SaveBindings(GetCurrentBindingSet())
            end
            StopListening()
        end)
        -- Leaving the window or entering combat cancels the wait.
        listener:SetScript("OnUpdate", function()
            if InCombatLockdown() then StopListening() end
        end)
    end
    if listenerDone then StopListening() end
    listenerDone = onDone
    listener:Show()
end

local lastKeyAt = 0
local function BuildKeyButton()
    if _G[KEY_BUTTON_NAME] then return end
    local button = CreateFrame("Button", KEY_BUTTON_NAME, UIParent)
    button:SetSize(1, 1)
    button:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -10, -10)
    button:EnableMouse(false)
    button:RegisterForClicks("AnyDown", "AnyUp")
    button:SetScript("OnClick", function()
        -- A key press can arrive as both a down and an up click.
        if GetTime() - lastKeyAt < 0.3 then return end
        lastKeyAt = GetTime()
        LiveScan:Start("key")
    end)
end

--------------------------------------------------------------------------------
-- Automatic scans: a timer and/or distance walked
--------------------------------------------------------------------------------
local function Walked()
    local now = PlayerWorldPosition()
    if not (now and lastScanPos) then return 0 end
    if now.instance ~= lastScanPos.instance then return math.huge end
    local dx, dy = now.x - lastScanPos.x, now.y - lastScanPos.y
    return math.sqrt(dx * dx + dy * dy)
end

local autoElapsed = 0
local STILL_SECONDS = 1.5   -- standing still this long restarts the distance count
local stillSince, stillReset

-- Optional (Live Nodes -> "Scan after you stop"): one scan shortly after a fight
-- ends, after landing or dismounting, and after a loading screen - the moments
-- the surroundings have just changed. It waits (up to 15 seconds) while an
-- automatic scan isn't allowed, e.g. a loot window is open.
local pendingEventScan
local wasFlying = false
local function RequestEventScan(delay)
    if not (Enabled() and XalsXRDB.liveScanAfterEvents) then return end
    local now = GetTime()
    pendingEventScan = { due = now + delay, giveUp = now + delay + 15 }
end

local function AutoTick(_, elapsed)
    autoElapsed = autoElapsed + elapsed
    if autoElapsed < AUTO_TICK then return end
    autoElapsed = 0
    if scan or not Enabled() then return end

    -- Landing: flying a moment ago, not now.
    if XalsXRDB.liveScanAfterEvents and IsFlying then
        local flying = IsFlying()
        if not Secret(flying) then
            flying = flying and true or false
            if wasFlying and not flying then RequestEventScan(1.5) end
            wasFlying = flying
        end
    else
        wasFlying = false
    end
    local pending = pendingEventScan
    if pending and GetTime() >= pending.due then
        if GetTime() > pending.giveUp then
            pendingEventScan = nil
        elseif not WhyNot(true) then
            pendingEventScan = nil
            LiveScan:Start("auto")
            return
        end
    end

    -- Scan by distance counts walking: when you stop, it starts counting again
    -- from where you stopped (once per stop, until you move off again).
    if XalsXRDB.liveScanDistance then
        local speed = GetUnitSpeed("player")
        if not Secret(speed) and speed == 0 then
            stillSince = stillSince or GetTime()
            if not stillReset and GetTime() - stillSince >= STILL_SECONDS then
                LiveScan:ResetDistance()
                stillReset = true
            end
        else
            stillSince, stillReset = nil, nil
        end
    end

    local due = false
    if XalsXRDB.liveScanTimer and GetTime() - lastScanAt >= (XalsXRDB.liveScanTimerSeconds or 20) then
        due = true
    end
    if XalsXRDB.liveScanDistance and Walked() >= (XalsXRDB.liveScanDistanceYards or 30) then
        due = true
    end
    -- Not due, or not allowed right now (mouse over a window, in combat...):
    -- try again at the next tick instead of skipping a whole interval.
    if due and not WhyNot(true) then
        LiveScan:Start("auto")
    end
end

--------------------------------------------------------------------------------
-- Arrow to the nearest live node
--------------------------------------------------------------------------------
local ARROW_TEXTURE = "Interface\\AddOns\\" .. addonName .. "\\Textures\\RoutesArrow"
local ARRIVAL_YARDS = 15 -- the node highlight's reach: closer than this, you've arrived
local arrowFrame, arrowTexture, arrowDistance, arrowLabel
local arrowTarget
local arrowHiddenByPlayer = false

local function BuildArrow()
    arrowFrame = CreateFrame("Frame", "XalsXRLiveArrowFrame", UIParent)
    arrowFrame:SetSize(70, 70)
    arrowFrame:SetMovable(true)
    arrowFrame:EnableMouse(true)
    arrowFrame:RegisterForDrag("LeftButton")

    local pos = Helpers.SanitizePoint(XalsXRDB and XalsXRDB.liveArrowPosition,
        { point = "CENTER", x = 0, y = 40 })
    if XalsXRDB then XalsXRDB.liveArrowPosition = pos end
    arrowFrame:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)

    arrowFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    arrowFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        if Helpers.IsValidPoint({ point = point, x = x, y = y }) then
            XalsXRDB.liveArrowPosition = { point = point, x = x, y = y }
        end
    end)
    arrowFrame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            arrowHiddenByPlayer = true
            arrowFrame:Hide()
        end
    end)
    arrowFrame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("|cff00ccffXal's XR: Nearest live node|r")
        GameTooltip:AddLine("Drag with |cff00ff00Left-Click|r to move.")
        GameTooltip:AddLine("|cffff9900Right-Click|r to hide until the next scan.")
        GameTooltip:Show()
    end)
    arrowFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    arrowTexture = arrowFrame:CreateTexture(nil, "ARTWORK")
    arrowTexture:SetPoint("CENTER")
    arrowTexture:SetTexture(ARROW_TEXTURE)
    arrowTexture:SetSize(52, 52)

    arrowDistance = arrowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    arrowDistance:SetFont(Brand.BODY_FONT_PATH, 15, "OUTLINE")
    arrowDistance:SetPoint("BOTTOM", arrowFrame, "BOTTOM", 0, -18)
    arrowDistance:SetTextColor(1, 1, 1, 1)

    arrowLabel = arrowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    arrowLabel:SetFont(Brand.BODY_FONT_PATH, 11, "OUTLINE")
    arrowLabel:SetPoint("TOP", arrowFrame, "TOP", 0, 14)
    arrowLabel:SetTextColor(1, 1, 1, 1)
    arrowFrame:Hide()
end

local function PlayerZonePosition(mapID)
    local px, py
    if Engine.HBD then px, py = Engine.HBD:GetPlayerZonePosition() end
    if not (px and py) then
        local position = C_Map.GetPlayerMapPosition(mapID, "player")
        if position then px, py = position:GetXY() end
    end
    return px, py
end

-- Distance and direction from the player to a point on the same map, trying
-- Blizzard's own conversion first, then HereBeDragons, then a plain coordinate
-- estimate - Helpers.ZoneVector alone gives nothing for a zone it can't measure,
-- which would leave the arrow with no target at all. Returns distance in yards,
-- then east and north offsets (north positive), same as the dungeon arrow.
local function VectorTo(mapID, px, py, tx, ty)
    local distance, dx, dy = Helpers.ZoneVector(mapID, px, py, tx, ty)
    if distance then return distance, dx, dy end
    if Engine.HBD then
        distance, dx, dy = Engine.HBD:GetZoneDistance(mapID, px, py, mapID, tx, ty)
        if distance and dx and dy then return distance, dx, dy end
    end
    local rawDx, rawDy = tx - px, py - ty
    local yards = Helpers.FALLBACK_YARDS_PER_UNIT or 1000
    return math.sqrt(rawDx * rawDx + rawDy * rawDy) * yards, rawDx * yards, rawDy * yards
end

local pickElapsed, arrowElapsed = 1, 0
local lastResultsKey

local function ArrowTick(_, elapsed)
    -- With "Build a route from live nodes" on (the default) and a route made from
    -- live nodes going, the route's own arrow does this job. In every other case -
    -- the option is off, no route is going, or an older route is going and the live
    -- nodes are only queued behind it - this separate arrow points at the nearest
    -- live node.
    local PathPlanner = addonTable.PathPlanner
    local routeOwnsArrow = XalsXRDB and XalsXRDB.liveScanRoute ~= false and PathPlanner
        and PathPlanner:InProgress() and PathPlanner.pathTypeFilter and PathPlanner.pathTypeFilter.live
    if not (XalsXRDB and Enabled()) or XalsXRDB.liveScanArrow == false or routeOwnsArrow then
        if arrowFrame and arrowFrame:IsShown() then arrowFrame:Hide() end
        return
    end
    arrowElapsed = arrowElapsed + elapsed
    if arrowElapsed < 0.05 then return end
    arrowElapsed = 0

    local mapID = C_Map.GetBestMapForUnit("player")
    local px, py
    if mapID then px, py = PlayerZonePosition(mapID) end

    -- Re-pick the nearest live node about twice a second.
    pickElapsed = pickElapsed + 0.05
    if pickElapsed >= 0.5 then
        pickElapsed = 0
        local best, bestDistance
        if mapID and px then
            for _, node in ipairs(Markers:GetLiveNodes()) do
                if node.mapID == mapID then
                    local distance = VectorTo(mapID, px, py, node.x, node.y)
                    -- A node you're already within reach of isn't a target any more:
                    -- the arrow moves on to the next nearest one.
                    if distance and distance > ARRIVAL_YARDS and (not bestDistance or distance < bestDistance) then
                        best, bestDistance = node, distance
                    end
                end
            end
        end
        local key = best and Markers.NodeKey(best.mapID, best.x, best.y) or nil
        if key ~= lastResultsKey then
            lastResultsKey = key
            arrowHiddenByPlayer = false -- a new target: show again
        end
        arrowTarget = best
    end

    if not arrowTarget or not mapID or not px or arrowTarget.mapID ~= mapID or arrowHiddenByPlayer then
        if arrowFrame and arrowFrame:IsShown() then arrowFrame:Hide() end
        return
    end

    local distance, dx, dy = VectorTo(mapID, px, py, arrowTarget.x, arrowTarget.y)
    if not distance or distance <= ARRIVAL_YARDS then
        if arrowFrame and arrowFrame:IsShown() then arrowFrame:Hide() end
        return
    end

    if not arrowFrame then BuildArrow() end
    if not arrowFrame:IsShown() then arrowFrame:Show() end
    arrowDistance:SetText(string.format("%.0f yd", distance))
    arrowLabel:SetText(arrowTarget.type == "mine" and "Live ore" or "Live herb")

    local facing = GetPlayerFacing()
    if facing then
        arrowTexture:SetRotation(-(facing + math.atan2(dx, dy)))
    end
end

--------------------------------------------------------------------------------
-- Wiring
--------------------------------------------------------------------------------
function LiveScan:Init()
    if self.inited or not self.supported then return end
    self.inited = true
    BuildKeyButton()

    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
    watcher:RegisterEvent("PLAYER_LOGOUT")
    watcher:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    watcher:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    watcher:SetScript("OnEvent", function(_, event)
        -- These two never cancel a scan in progress; they only ask for one later.
        if event == "PLAYER_REGEN_ENABLED" then return RequestEventScan(1.5) end
        if event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
            if IsMounted and not IsMounted() then RequestEventScan(1.5) end
            return
        end
        if scan then Finish(scan, true, event == "PLAYER_REGEN_DISABLED" and "combat started" or "the zone changed") end
        if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
            lastScanPos = PlayerWorldPosition()
            lastScanAt = GetTime()
        end
        if event == "PLAYER_ENTERING_WORLD" then RequestEventScan(3) end
    end)

    local autoFrame = CreateFrame("Frame")
    autoFrame:SetScript("OnUpdate", AutoTick)
    local arrowDriver = CreateFrame("Frame")
    arrowDriver:SetScript("OnUpdate", ArrowTick)
end
