-- .luacheckrc
-- Xal's Xpedited Routes
--
-- Scoped to the actual WoW API calls and globals this addon uses (not a
-- copy-pasted full addon's config) - add to `globals`/`read_globals` as new
-- API calls get added, rather than pulling in a giant generic list.
std = "lua51"

-- This addon's own saved-variable global (declared via .toc SavedVariables,
-- read/written across every file).
globals = {
    "XalsXRDB",
    "StaticPopupDialogs", -- a real mutable table addons add popup entries to
    "SLASH_XALMORASXR1",
    "SLASH_XALMORASXR2",
    "SlashCmdList",
}

-- Read-only: real WoW client API/globals + the bundled libs' own globals.
read_globals = {
    "CreateFrame",
    "UIParent",
    "GameTooltip",
    "PixelUtil",
    "LibStub",
    "hooksecurefunc",
    "tinsert",
    "wipe",
    "UISpecialFrames",
    "UIFrameFadeOut",
    "BackdropTemplateMixin",
    "Settings",
    "C_AddOns",
    "C_Timer",
    "C_Map",
    "C_Minimap",
    "C_Item",
    "C_Spell",
    "C_SpellBook",
    "C_TradeSkillUI",
    "C_EncounterJournal",
    "C_SuperTrack",
    "Enum",
    "StaticPopup_Show",
    "StaticPopup_Hide",
    "ITEM_QUALITY_COLORS",
}

-- Textures/backdrop tables and long chained SetPoint calls read as "unused
-- variable"/line-length noise in generated UI code like this - not real bugs.
max_line_length = false
unused_args = false
