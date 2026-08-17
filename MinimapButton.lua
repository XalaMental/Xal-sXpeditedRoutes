-- MinimapButton.lua
-- Xal's Xpedited Routes
--
-- The minimap launcher icon, via LibDataBroker + LibDBIcon - the same
-- combination almost every WoW addon with a minimap button uses (already
-- proven working in Xal's Compendium).
--
-- Left-click opens the standalone Options window (the primary way into
-- settings, see SettingsPanel.lua). Right-click opens the Gather Tally -
-- same behavior as /xxr haul (shows the current/last tally, or a "nothing
-- tracked yet" message), NOT a new manual session - that's what the
-- dedicated Gather button on the floating helper is for.
local addonName, addonTable = ...
local MinimapButton = addonTable.MinimapButton

-- TEST, 2026-08-09: dropping the standard circular border/mask in favor of
-- a full custom-shaped icon, same technique MidnightRoutine uses (verified
-- straight from its real MinimapButton.lua) - LibDBIcon has SetButtonSize/
-- RemoveButtonBorder/RemoveButtonBackground/SetButtonIcon built in as of
-- library revision 56 (ours was 55; updated the bundled copy to match).
-- Not a custom rebuild - same library, just the newer methods.
-- Explicit .png extension - a leftover stale .tga sitting in the live test
-- folder alongside a newer .png (same base name) caused WoW to keep loading
-- the OLD file, since an extensionless path left it ambiguous which one to
-- resolve to. Confirmed 2026-08-09.
local MINIMAP_ICON = "Interface\\AddOns\\XalsXpeditedRoutes\\Textures\\BundleIcon_Minimap_v1.png"
local MINIMAP_ICON_SIZE = 34

function MinimapButton:Register()
    local ldb = LibStub("LibDataBroker-1.1"):NewDataObject("XalsXpeditedRoutes", {
        type = "launcher",
        text = "Xal's Xpedited Routes",
        icon = MINIMAP_ICON,
        OnClick = function(_, button)
            if button == "RightButton" then
                if addonTable.RunTracker and addonTable.RunTracker.ShowWindow then
                    addonTable.RunTracker:ShowWindow()
                end
            else
                if addonTable.SettingsPanel and addonTable.SettingsPanel.ToggleStandalone then
                    addonTable.SettingsPanel:ToggleStandalone()
                end
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine("Xal's Xpedited Routes")
            tooltip:AddLine("|cff999999Left-click|r to open Options")
            tooltip:AddLine("|cff999999Right-click|r to open the Gather Tally")
        end,
    })

    XalsXRDB.minimap = XalsXRDB.minimap or { hide = false }
    local icon = LibStub("LibDBIcon-1.0")
    icon:Register("XalsXpeditedRoutes", ldb, XalsXRDB.minimap)

    if icon.SetButtonSize then
        icon:SetButtonSize("XalsXpeditedRoutes", MINIMAP_ICON_SIZE)
        icon:RemoveButtonBorder("XalsXpeditedRoutes")
        icon:RemoveButtonBackground("XalsXpeditedRoutes")
        icon:SetButtonIcon("XalsXpeditedRoutes", MINIMAP_ICON, MINIMAP_ICON_SIZE, "CENTER", 0, 0)
    end
end

-- Backing the Options checkbox - LibDBIcon's own Show/Hide API, not a
-- manual texture toggle, so it stays consistent with how the library
-- expects its icon's visibility to be controlled.
function MinimapButton:SetShown(shown)
    XalsXRDB.minimap = XalsXRDB.minimap or { hide = false }
    XalsXRDB.minimap.hide = not shown
    local icon = LibStub("LibDBIcon-1.0", true)
    if not icon then return end
    if shown then
        icon:Show("XalsXpeditedRoutes")
    else
        icon:Hide("XalsXpeditedRoutes")
    end
end
