-- Engine.lua
-- Xal's Xpedited Routes
local addonName, addonTable = ...
local Engine = addonTable.Engine
local Helpers = addonTable.Helpers

Engine.HBD = nil
Engine.HBDPins = nil

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("ZONE_CHANGED")
eventFrame:RegisterEvent("ZONE_CHANGED_INDOORS")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
-- These fire once the client actually has profession/skill data loaded - which
-- doesn't always happen immediately at login. Re-checking on these lets any
-- earlier "assume known" guess (see Helpers.HasGatheringProfession) correct itself
-- automatically once real data is available, with no action needed from the player.
eventFrame:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
eventFrame:RegisterEvent("SKILL_LINES_CHANGED")
eventFrame:RegisterEvent("PLAYER_LOGIN")

local function RefreshProfessionDependentUI()
    if addonTable.Markers.UpdatePins then
        addonTable.Markers:UpdatePins()
    end
    if addonTable.QuickButton.Refresh then
        addonTable.QuickButton:Refresh()
    end
end

-- Runs a check, and once both professions have a CONFIRMED answer (see
-- Helpers.IsProfessionDetectionConfirmed), stops doing any further work - no more
-- point re-checking something that's already known for certain and can't change
-- mid-session. Unregisters the two "maybe the data's ready now" events too, so
-- they stop even reaching this function; the login-window rechecks below just
-- become instant no-ops via the confirmed check up front.
local function ProfessionCheckTick()
    if Helpers.IsProfessionDetectionConfirmed() then return end

    RefreshProfessionDependentUI()

    if Helpers.IsProfessionDetectionConfirmed() then
        eventFrame:UnregisterEvent("TRADE_SKILL_LIST_UPDATE")
        eventFrame:UnregisterEvent("SKILL_LINES_CHANGED")
    end
end

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == addonName then
            -- Initialize database
            XalsXRDB = XalsXRDB or {}
            if XalsXRDB.showPins == nil then
                XalsXRDB.showPins = true
            end
            if XalsXRDB.compassPosition == nil then
                XalsXRDB.compassPosition = { point = "CENTER", x = 0, y = 180 }
            end
            if XalsXRDB.autoAdvanceDistance == nil then
                XalsXRDB.autoAdvanceDistance = 30
            end
            if XalsXRDB.showHelperButton == nil then
                XalsXRDB.showHelperButton = true
            end
            if XalsXRDB.helperButtonPosition == nil then
                XalsXRDB.helperButtonPosition = { point = "CENTER", x = 100, y = 180 }
            end
            if XalsXRDB.pinStyle == nil then
                XalsXRDB.pinStyle = "hollowx"
            end
            if XalsXRDB.pinSize == nil then
                XalsXRDB.pinSize = 12
            end
            if XalsXRDB.pinAlpha == nil then
                XalsXRDB.pinAlpha = 1
            end
            if XalsXRDB.showGlow == nil then
                XalsXRDB.showGlow = false
            end
            if XalsXRDB.proximityDistanceYards == nil then
                XalsXRDB.proximityDistanceYards = 200
            end
            if XalsXRDB.arrowProgressColor == nil then
                XalsXRDB.arrowProgressColor = true
            end
            if XalsXRDB.duplicateDistanceYards == nil then
                XalsXRDB.duplicateDistanceYards = 15
            end
            if XalsXRDB.compassArrowStyle == nil then
                XalsXRDB.compassArrowStyle = "custom4"
            end
            if XalsXRDB.arrowScale == nil then
                XalsXRDB.arrowScale = 1
            end
            if XalsXRDB.tomtomSyncEnabled == nil then
                XalsXRDB.tomtomSyncEnabled = false
            end
            
            -- Per-character preferences (route filters etc. - these can differ per alt,
            -- e.g. a character with only Mining wants Herbalism nodes skipped)
            XalsXRCharDB = XalsXRCharDB or {}
            if XalsXRCharDB.ignoreMining == nil then
                XalsXRCharDB.ignoreMining = false
            end
            if XalsXRCharDB.ignoreHerbs == nil then
                XalsXRCharDB.ignoreHerbs = false
            end
            
            -- Try to load HereBeDragons (optional - only present if the user has the
            -- separate "HereBeDragons" addon installed). If it's missing, the addon
            -- still works: Compass/Routing fall back to straight-line distance within
            -- the current zone, and map/minimap pin rendering (which does need it)
            -- is simply skipped until it's available.
            Engine.HBD = LibStub("HereBeDragons-2.0", true)
            Engine.HBDPins = LibStub("HereBeDragons-Pins-2.0", true)
            
            print("|cff00ccffXal's XR|r loaded successfully.")
            if not (Engine.HBD and Engine.HBDPins) then
                print("|cffff9900Xal's XR:|r Optional library 'HereBeDragons' not found - map/minimap pins are disabled and cross-zone distances are approximate until it's installed. Recording, routing, and the compass still work normally.")
            end
            
            -- Initialize modules
            if addonTable.NodeLogger.Init then addonTable.NodeLogger:Init() end
            if addonTable.PathPlanner.Init then addonTable.PathPlanner:Init() end
            if addonTable.Beacon.Init then addonTable.Beacon:Init() end
            if addonTable.Markers.Init then addonTable.Markers:Init() end
            if addonTable.SettingsPanel.Init then addonTable.SettingsPanel:Init() end
            if addonTable.QuickButton.Init then addonTable.QuickButton:Init() end
            
            -- Nudge the client to populate profession data early rather than waiting
            -- for the player to open their Professions panel organically - the read
            -- itself can trigger population as a side effect. Discard the result;
            -- this call is just a prime, the real check happens in
            -- Helpers.HasGatheringProfession when something actually needs an answer.
            if C_TradeSkillUI and C_TradeSkillUI.GetAllProfessionTradeSkillLines then
                pcall(C_TradeSkillUI.GetAllProfessionTradeSkillLines)
            end
            -- Backstop: even without a specific event firing, re-check a few times
            -- over the first half-minute after login so any earlier "assume known"
            -- guess self-corrects once real data shows up, without relying on any
            -- single event being the one that reliably fires. Each of these becomes
            -- a no-op the moment detection is actually confirmed - see
            -- ProfessionCheckTick above.
            if C_Timer then
                for _, delay in ipairs({ 3, 8, 15, 30 }) do
                    C_Timer.After(delay, ProfessionCheckTick)
                end
            end
        end
    elseif event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" or event == "PLAYER_ENTERING_WORLD" then
        if addonTable.Markers.UpdatePins then
            addonTable.Markers:UpdatePins()
        end
        if addonTable.PathPlanner.OnZoneChanged then
            addonTable.PathPlanner:HandleZoneChange()
        end
        if addonTable.QuickButton.Refresh then
            addonTable.QuickButton:Refresh()
        end
    elseif event == "TRADE_SKILL_LIST_UPDATE" or event == "SKILL_LINES_CHANGED" or event == "PLAYER_LOGIN" then
        ProfessionCheckTick()
    end
end)
