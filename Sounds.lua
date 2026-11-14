-- Sounds.lua
-- Optional sounds for two moments on a route: arriving at a node, and finishing the
-- route. Each can be turned off and given its own sound (Waypoint settings page).
local addonName, addonTable = ...

local Sounds = addonTable.Sounds or {}
addonTable.Sounds = Sounds

-- To add a sound, add one line here: { "Label shown in the settings", "SOUNDKIT name" }.
-- Every name below is one the game's own SOUNDKIT table has and that other addons on this
-- client already play. A name the client doesn't have is simply left out of the list.
local CANDIDATES = {
    { "Map ping", "MAP_PING" },
    { "Waypoint set", "UI_MAP_WAYPOINT_SUPER_TRACK_ON" },
    { "Waypoint click", "UI_MAP_WAYPOINT_CONTROL_CLICK" },
    { "Waypoint share", "UI_MAP_WAYPOINT_CHAT_SHARE" },
    { "Quest list complete", "IG_QUEST_LIST_COMPLETE" },
    { "Quest turn-in", "IG_QUEST_COMPLETE" },
    { "Auto quest complete", "UI_AUTO_QUEST_COMPLETE" },
    { "Ready check", "READY_CHECK" },
    { "Raid warning", "RAID_WARNING" },
    { "Whisper", "TELL_MESSAGE" },
    { "Coins", "LOOT_WINDOW_COIN_SOUND" },
    { "Fishing reel", "FISHING_REEL_IN" },
    { "Toast", "UI_BNET_TOAST" },
    { "Alarm", "ALARM_CLOCK_WARNING_3" },
    { "Rewards", "LFG_REWARDS" },
    { "Epic loot", "UI_EPICLOOT_TOAST" },
    { "Legendary loot", "UI_LEGENDARY_LOOT_TOAST" },
    { "Recipe learned", "UI_PROFESSIONS_NEW_RECIPE_LEARNED_TOAST" },
    { "Auction bell", "AUCTION_WINDOW_OPEN" },
    { "Soft click", "IG_MAINMENU_OPTION_CHECKBOX_ON" },
    { "Tutorial pop", "TUTORIAL_POPUP_SHOW" },
}

-- The sounds this client really has, in order: keys (the SOUNDKIT names), labels by key,
-- ids by key.
Sounds.KEYS, Sounds.LABELS, Sounds.IDS = {}, {}, {}
for _, entry in ipairs(CANDIDATES) do
    local label, name = entry[1], entry[2]
    local id = SOUNDKIT and SOUNDKIT[name]
    if type(id) == "number" then
        Sounds.KEYS[#Sounds.KEYS + 1] = name
        Sounds.LABELS[name] = label
        Sounds.IDS[name] = id
    end
end

-- Per event: the saved setting names and the defaults. Settings live in one table,
-- XalsXRDB.sounds, written only once the player changes something.
local EVENTS = {
    arrive = { on = true, key = "MAP_PING" },
    finish = { on = true, key = "IG_QUEST_LIST_COMPLETE" },
}

local function Saved()
    return XalsXRDB and XalsXRDB.sounds or nil
end

function Sounds:IsEnabled(event)
    local saved = Saved()
    local value = saved and saved[event .. "On"]
    if value == nil then return EVENTS[event].on end
    return value
end

function Sounds:GetKey(event)
    local saved = Saved()
    local key = saved and saved[event .. "Key"] or EVENTS[event].key
    if self.IDS[key] then return key end
    return self.KEYS[1] -- the chosen sound isn't on this client: fall back to the first one
end

function Sounds:SetEnabled(event, on)
    XalsXRDB.sounds = XalsXRDB.sounds or {}
    XalsXRDB.sounds[event .. "On"] = on and true or false
end

function Sounds:SetKey(event, key)
    XalsXRDB.sounds = XalsXRDB.sounds or {}
    XalsXRDB.sounds[event .. "Key"] = key
end

-- Plays one sound by key (used by the settings page to let you hear a pick).
function Sounds:Preview(key)
    local id = self.IDS[key]
    if id then pcall(PlaySound, id, "Master") end
end

-- Plays the sound set for an event ("arrive" or "finish"), if it's switched on.
function Sounds:Play(event)
    if not EVENTS[event] or not self:IsEnabled(event) then return end
    local key = self:GetKey(event)
    if key then self:Preview(key) end
end
