-- Places.lua
-- Xal's Xpedited Routes
--
-- "Go to the nearest ..." for places you keep needing: forge, anvil, cooking fire, mailbox,
-- innkeeper, flight master, bank, auction house, repair vendor, your class trainer and the
-- profession trainers. A small floating icon of its own opens a list; picking a place points
-- your arrow at the nearest one in the zone you're standing in, the same way the Xperimental
-- dungeon waypoint does (Blizzard's map pin when the client has it, TomTom when its sync is
-- on, otherwise our own arrow).
--
-- Every place is a position in PlacesData.lua (zone, x, y, faction side, name). They are
-- facts only and NOT yet verified in the client. The nearest one anywhere on your continent
-- is found (not just in your zone), and a place that belongs to the other faction is skipped.
--
-- All settings live in one saved table, XalsXRDB.places:
--   hide = true        the floating icon is hidden
--   pos = {point,x,y}  where the icon sits
--   off = { [key]=true }  categories switched off (everything is on by default)
local addonName, addonTable = ...
local Places = {}
addonTable.Places = Places

local Helpers = addonTable.Helpers
local Engine = addonTable.Engine

-- WoW: Forever only: the position data covers Classic zones, and the rest of this module
-- (the icon, its settings, /xxr go) stays off everywhere else.
Places.supported = WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT

-- The categories, in menu order. kind is the key in PlacesData.lua ("class" and "prof" are
-- worked out from your class / the chosen profession).
Places.CATEGORIES = {
    { key = "forge",   label = "Forge",             kind = "forge" },
    { key = "anvil",   label = "Anvil",             kind = "anvil" },
    { key = "fire",    label = "Cooking fire",      kind = "fire" },
    { key = "mailbox", label = "Mailbox",           kind = "mailbox" },
    { key = "inn",     label = "Innkeeper",         kind = "inn" },
    { key = "flight",  label = "Flight master",     kind = "flight" },
    { key = "bank",    label = "Bank",              kind = "bank" },
    { key = "auction", label = "Auction house",     kind = "auction" },
    { key = "repair",  label = "Repair vendor",     kind = "repair" },
    { key = "class",   label = "Class trainer" },
    { key = "prof",    label = "Profession trainer" },
}

Places.PROFESSIONS = {
    "Alchemy", "Blacksmithing", "Cooking", "Enchanting", "Engineering", "First Aid",
    "Fishing", "Herbalism", "Leatherworking", "Mining", "Skinning", "Tailoring",
}

-- Words the /xxr go command understands, mapped to a category key.
local WORDS = {
    forge = "forge", smelt = "forge", smelting = "forge", anvil = "anvil",
    fire = "fire", cooking = "fire", campfire = "fire",
    mailbox = "mailbox", mail = "mailbox", post = "mailbox",
    inn = "inn", innkeeper = "inn", inkeeper = "inn",
    flight = "flight", flightmaster = "flight", taxi = "flight",
    bank = "bank", banker = "bank",
    auction = "auction", ah = "auction", auctioneer = "auction",
    repair = "repair", class = "class", trainer = "class",
}

local function Say(text)
    print("|cff00ccffXal's XR:|r " .. text)
end

--------------------------------------------------------------------------------
-- Settings (one table, defaults not stored until something changes)
--------------------------------------------------------------------------------
local function Saved()
    if not XalsXRDB then return nil end
    XalsXRDB.places = type(XalsXRDB.places) == "table" and XalsXRDB.places or {}
    return XalsXRDB.places
end

function Places:IsEnabled(key)
    local s = Saved()
    return not (s and s.off and s.off[key])
end

function Places:SetEnabled(key, on)
    local s = Saved()
    if not s then return end
    s.off = s.off or {}
    s.off[key] = (not on) or nil
end

function Places:ButtonShown()
    local s = Saved()
    return not (s and s.hide)
end

function Places:SetButtonShown(on)
    local s = Saved()
    if not s then return end
    s.hide = (not on) or nil
    if self.button then
        if on then self.button:Show() else self.button:Hide(); if self.menu then self.menu:Hide() end end
    elseif on then
        self:Init()
    end
end

--------------------------------------------------------------------------------
-- Finding the nearest place
--------------------------------------------------------------------------------
local function ZoneName(mapID)
    local ok, info = pcall(C_Map.GetMapInfo, mapID)
    if ok and type(info) == "table" and type(info.name) == "string" then return info.name end
    return "this zone"
end

local function MySide()
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    if faction == "Alliance" then return "A" end
    if faction == "Horde" then return "H" end
    return nil
end

-- A point on a zone map as a point on the world (continent id, x, y in yards), through
-- Blizzard's own conversion. Nil when the client can't give it.
local function WorldPoint(mapID, x, y)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local ok, continent, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
    if not ok or not continent or not pos then return nil end
    local wx, wy = pos:GetXY()
    if not wx or not wy then return nil end
    return continent, wx, wy
end

-- mapID, x, y (0-1), yards, name of the nearest spot of `kind` ANYWHERE on the player's
-- continent (a town you pass through may not have one); or nil plus a short reason.
-- If the client can't turn map points into world points it falls back to the current zone.
function Places:Nearest(kind)
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then
        return nil, "this game version can't give your map position"
    end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return nil, "your position isn't known right now" end
    local position = C_Map.GetPlayerMapPosition(mapID, "player")
    if not position then return nil, "your position isn't known here" end
    local px, py = position:GetXY()
    if not px or not py or (px == 0 and py == 0) then return nil, "your position isn't known here" end
    if not addonTable.PLACES then return nil, "no place data loaded" end

    local side = MySide()
    local function Allowed(spot)
        return spot[3] == "N" or not side or spot[3] == side
    end

    local playerContinent, pwx, pwy = WorldPoint(mapID, px, py)
    local best, bestYards, bestMap

    if playerContinent then
        for zoneMap, zone in pairs(addonTable.PLACES) do
            local spots = zone[kind]
            if spots then
                for _, spot in ipairs(spots) do
                    if Allowed(spot) then
                        -- the world point of a spot never changes: worked out once and kept on the spot
                        if spot.wc == nil then
                            local c, wx, wy = WorldPoint(zoneMap, spot[1] / 100, spot[2] / 100)
                            spot.wc, spot.wx, spot.wy = c or false, wx, wy
                        end
                        if spot.wc == playerContinent then
                            local dx, dy = spot.wx - pwx, spot.wy - pwy
                            local yards = math.sqrt(dx * dx + dy * dy)
                            if not bestYards or yards < bestYards then
                                best, bestYards, bestMap = spot, yards, zoneMap
                            end
                        end
                    end
                end
            end
        end
    else
        -- no world conversion on this client: only the zone you are in
        local zone = addonTable.PLACES[mapID]
        local spots = zone and zone[kind]
        for _, spot in ipairs(spots or {}) do
            if Allowed(spot) then
                local yards = Helpers.NodeDistanceYards(Engine, mapID, px, py, spot[1] / 100, spot[2] / 100)
                if yards and (not bestYards or yards < bestYards) then
                    best, bestYards, bestMap = spot, yards, mapID
                end
            end
        end
    end

    if not best then
        return nil, "none known on this continent for your faction"
    end
    return bestMap, best[1] / 100, best[2] / 100, bestYards, best[4]
end

-- Shortest Path Forever (a separate addon, when installed) plans a walking route round
-- mountains and through gates, with flights and boats, and draws it itself. Its public
-- API (ShortestPathForever.API.Navigate) takes a destination; if it accepts, our straight
-- arrow stays off so there's only one guide.
function Places:UsesRouter()
    local s = Saved()
    if s and s.noRouter then return false end
    local spf = _G.ShortestPathForever
    return spf and type(spf.API) == "table" and type(spf.API.Navigate) == "function" or false
end

function Places:SetUseRouter(on)
    local s = Saved()
    if s then s.noRouter = (not on) or nil end
end

local ROUTER_OWNER = "XalsXpeditedRoutes"

-- Returns true when Shortest Path Forever took the destination; otherwise false plus a short
-- reason (shown in chat so a refusal can be seen, not guessed).
local function SetTargetViaRouter(mapID, x, y, label)
    local s = Saved()
    if s and s.noRouter then return false, nil end -- switched off: nothing to say
    local spf = _G.ShortestPathForever
    if type(spf) ~= "table" then return false, "Shortest Path Forever isn't loaded (is it enabled for this character?)" end
    if type(spf.API) ~= "table" or type(spf.API.Navigate) ~= "function" then
        return false, "Shortest Path Forever is loaded but has no route function (API missing)"
    end
    if InCombatLockdown() then return false, "it won't plan a route while you're in combat" end
    local ok, started, why = pcall(spf.API.Navigate, ROUTER_OWNER, mapID, x, y, label)
    if not ok then return false, "its route call errored: " .. tostring(started) end
    if started == true then return true end
    return false, "it refused the route (answer: " .. tostring(started) .. (why and (", " .. tostring(why)) or "") .. ")"
end

-- Points the arrow at a spot.
local function SetTarget(mapID, x, y, label)
    local viaRouter, reason = SetTargetViaRouter(mapID, x, y, label)
    if viaRouter then return true end
    if reason then Say("Straight arrow instead: " .. reason .. ".") end
    pcall(function()
        if C_Map.SetUserWaypoint and CreateVector2D then
            C_Map.SetUserWaypoint({ uiMapID = mapID, position = CreateVector2D(x, y) })
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
                C_SuperTrack.SetSuperTrackedUserWaypoint(true)
            end
        end
    end)

    local tomtomActive = false
    if XalsXRDB and XalsXRDB.tomtomSyncEnabled and TomTom and TomTom.AddWaypoint then
        tomtomActive = pcall(function()
            TomTom:AddWaypoint(mapID, x, y, {
                title = label, persistent = false, minimap = true, world = true, silent = true, crazy = true,
                cleardistance = 10, arrivaldistance = 10,
            })
        end)
    end

    local beacon = addonTable.DungeonBeacon
    if beacon and beacon.Show then
        if tomtomActive then
            if beacon.Clear then beacon:Clear() end
        else
            beacon:Show(mapID, x, y, label)
        end
    end
end

-- Goes to the nearest place of a data kind. label is what to call it in chat.
function Places:GoToKind(kind, label)
    local mapID, x, y, yards, name = self:Nearest(kind)
    if not mapID or type(x) ~= "number" then
        Say("No " .. label:lower() .. ": " .. tostring(x) .. ".")
        return false
    end
    -- Fixed objects (forge, anvil, fire, mailbox) are only named "Forge", "Campfire" and so on, which
    -- just repeats the label; only people (innkeepers, trainers ...) get their name added.
    local objectKind = kind == "forge" or kind == "anvil" or kind == "fire" or kind == "mailbox"
    local what = (name and not objectKind) and (label .. ", " .. name) or label
    local zone = ZoneName(mapID)
    SetTarget(mapID, x, y, what .. " (" .. zone .. ")")
    Say(string.format("Heading to the nearest %s in %s, about %d yards away.", what, zone, math.floor(yards + 0.5)))
    return true
end

-- Goes to the nearest place of a category (profession is only used by "prof").
function Places:GoToCategory(key, profession)
    if key == "class" then
        local token = select(2, UnitClass("player"))
        if not token then Say("Couldn't tell your class.") return false end
        return self:GoToKind("class_" .. token, "Class trainer")
    elseif key == "prof" then
        if not profession then Say("Say which profession, for example /xxr go mining.") return false end
        return self:GoToKind("prof_" .. profession, profession .. " trainer")
    end
    for _, cat in ipairs(self.CATEGORIES) do
        if cat.key == key and cat.kind then
            return self:GoToKind(cat.kind, cat.label)
        end
    end
    return false
end

-- Backs "/xxr go <word>": a place word (forge, mailbox, inn ...) or a profession name.
function Places:GoByWord(text)
    if not self.supported then
        Say("Places only works on WoW: Forever.")
        return false
    end
    text = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then
        Say("Say where: forge, anvil, fire, mailbox, inn, flight, bank, auction, repair, class, or a profession (for example /xxr go mining).")
        return false
    end
    local key = WORDS[text:gsub("%s+", "")]
    if key then return self:GoToCategory(key) end
    for _, name in ipairs(self.PROFESSIONS) do
        if name:lower() == text or name:lower():gsub("%s+", "") == text:gsub("%s+", "") then
            return self:GoToCategory("prof", name)
        end
    end
    Say("I don't know \"" .. text .. "\". Try forge, anvil, fire, mailbox, inn, flight, bank, auction, repair, class, or a profession.")
    return false
end

--------------------------------------------------------------------------------
-- The floating icon and its list
--------------------------------------------------------------------------------
local BUTTON_SIZE = 36
local ROW_H = 18
local MENU_W = 190

local function Template()
    return BackdropTemplateMixin and "BackdropTemplate" or nil
end

local function BuildMenu()
    local menu = CreateFrame("Frame", "XalsXRPlacesMenu", UIParent, Template())
    menu:SetFrameStrata("DIALOG")
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu:Hide()
    if menu.SetBackdrop then
        menu:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        menu:SetBackdropColor(0, 0, 0, 0.95)
        menu:SetBackdropBorderColor(0.25, 0.55, 0.75, 1)
    end
    menu.header = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    menu.header:SetPoint("TOPLEFT", 8, -8)
    menu.header:SetText("|cff00ccffGo to the nearest:|r")
    menu.rows = {}
    if UISpecialFrames then table.insert(UISpecialFrames, "XalsXRPlacesMenu") end
    return menu
end

local function Row(menu, index)
    local row = menu.rows[index]
    if row then return row end
    row = CreateFrame("Button", nil, menu)
    row:SetSize(MENU_W - 16, ROW_H)
    row.fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.fs:SetPoint("LEFT", 2, 0)
    row:SetScript("OnEnter", function(self) self.fs:SetTextColor(1, 0.82, 0) end)
    row:SetScript("OnLeave", function(self) self.fs:SetTextColor(1, 1, 1) end)
    menu.rows[index] = row
    return row
end

-- Rebuilds the list from the current switches (cheap: a dozen rows).
function Places:FillMenu()
    local menu = self.menu
    if not menu then return end
    for _, row in ipairs(menu.rows) do row:Hide() end

    local index, y = 0, -8 - ROW_H
    local function Add(text, indent, onClick)
        index = index + 1
        local row = Row(menu, index)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 8 + (indent or 0), y)
        row:SetWidth(MENU_W - 16 - (indent or 0))
        row.fs:SetText(text)
        row.fs:SetTextColor(1, 1, 1)
        row:SetScript("OnClick", onClick)
        row:Show()
        y = y - ROW_H
    end

    for _, cat in ipairs(self.CATEGORIES) do
        if self:IsEnabled(cat.key) then
            if cat.key == "prof" then
                Add((menu.profOpen and "- " or "+ ") .. cat.label, 0, function()
                    menu.profOpen = not menu.profOpen
                    self:FillMenu()
                end)
                if menu.profOpen then
                    for _, name in ipairs(self.PROFESSIONS) do
                        Add(name, 12, function()
                            self:GoToCategory("prof", name)
                            menu:Hide()
                        end)
                    end
                end
            else
                Add(cat.label, 0, function()
                    self:GoToCategory(cat.key)
                    menu:Hide()
                end)
            end
        end
    end
    if index == 0 then
        Add("|cff888888Nothing switched on|r", 0, function() menu:Hide() end)
    end
    menu:SetSize(MENU_W, 8 + ROW_H + index * ROW_H + 6)
end

local function SavePosition(button)
    local s = Saved()
    if not s then return end
    local point, _, _, x, y = button:GetPoint()
    if Helpers.IsValidPoint({ point = point, x = x, y = y }) then
        s.pos = { point = point, x = x, y = y }
    end
end

local DEFAULT_POS = { point = "CENTER", x = 140, y = 120 }

function Places:ResetButtonPosition()
    local s = Saved()
    if s then s.pos = nil end
    if self.button then
        self.button:ClearAllPoints()
        self.button:SetPoint(DEFAULT_POS.point, UIParent, DEFAULT_POS.point, DEFAULT_POS.x, DEFAULT_POS.y)
    end
end

function Places:Init()
    if not self.supported or self.button or not XalsXRDB then return end
    if not self:ButtonShown() then return end

    local button = CreateFrame("Button", "XalsXRPlacesButton", UIParent)
    button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    button:SetMovable(true)
    button:SetClampedToScreen(true)
    button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")

    local s = Saved()
    local pos = Helpers.SanitizePoint(s and s.pos, DEFAULT_POS)
    button:ClearAllPoints()
    button:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
    local hl = button:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.25)

    button:SetScript("OnDragStart", function(self) self:StartMoving() end)
    button:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition(self)
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("|cff00ccffXal's XR: Places|r")
        GameTooltip:AddLine("|cff00ff00Click|r: Point your arrow at the nearest forge, mailbox, trainer and more.")
        GameTooltip:AddLine("|cff888888Drag|r: Move this")
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnClick", function(self)
        if not Places.menu then Places.menu = BuildMenu() end
        local menu = Places.menu
        if menu:IsShown() then
            menu:Hide()
        else
            Places:FillMenu()
            menu:ClearAllPoints()
            menu:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
            menu:Show()
        end
    end)

    self.button = button
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    Places:Init()
end)
