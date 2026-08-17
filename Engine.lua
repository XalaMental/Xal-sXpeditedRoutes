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
-- TRADE_SKILL_LIST_UPDATE/PLAYER_LOGIN fire once the client actually has
-- profession/skill data loaded - which doesn't always happen immediately at
-- login. Re-checking on these lets any earlier "assume known" guess (see
-- Helpers.HasGatheringProfession) correct itself automatically once real data
-- is available, with no action needed from the player.
--
-- SKILL_LINES_CHANGED does that too, but ALSO fires for a genuine mid-session
-- change - learning a brand new profession, or replacing one at a trainer -
-- which is why it's never unregistered the way the other two are (see
-- HandleSkillLinesChanged below).
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
-- Helpers.IsProfessionDetectionConfirmed), stops doing any further work for
-- THIS specific pass - no point re-checking something already known for
-- certain in this moment. TRADE_SKILL_LIST_UPDATE gets unregistered once
-- confirmed, since that one's really just a "trade window data loaded" signal
-- with nothing further to tell us. SKILL_LINES_CHANGED deliberately stays
-- registered forever - see HandleSkillLinesChanged below for why.
local function ProfessionCheckTick()
    if Helpers.IsProfessionDetectionConfirmed() then return end

    RefreshProfessionDependentUI()

    if Helpers.IsProfessionDetectionConfirmed() then
        eventFrame:UnregisterEvent("TRADE_SKILL_LIST_UPDATE")
    end
end

-- SKILL_LINES_CHANGED fires both for the login "data isn't ready yet" case AND
-- for a genuine mid-session change (learning a brand new profession, or
-- replacing one at a trainer) - those look identical from this event alone.
-- If detection was already confirmed, the only reason this could be firing
-- again is a real change, so the stale cached answer has to be thrown out
-- first, or the next check would just trust the old (now wrong) result and
-- do nothing.
local function HandleSkillLinesChanged()
    if Helpers.IsProfessionDetectionConfirmed() then
        Helpers.ClearProfessionCache()
    end
    ProfessionCheckTick()
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
                XalsXRDB.autoAdvanceDistance = 50
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
            if XalsXRDB.groupingDistanceYards == nil then
                XalsXRDB.groupingDistanceYards = 240
            end
            if XalsXRDB.showTrailLine == nil then
                XalsXRDB.showTrailLine = true
            end
            if XalsXRDB.helperButtonFadeWhenIdle == nil then
                XalsXRDB.helperButtonFadeWhenIdle = false
            end
            if XalsXRDB.lumberEnabled == nil then
                XalsXRDB.lumberEnabled = true
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
            if XalsXRDB.arrowTextScale == nil then
                XalsXRDB.arrowTextScale = 1
            end
            -- Left unset here on purpose - TomTom (a separate addon) isn't
            -- guaranteed to have loaded yet by the time OUR ADDON_LOADED
            -- fires, so checking for it here would be unreliable. The real
            -- first-time default gets decided at PLAYER_LOGIN instead, once
            -- every addon is guaranteed loaded.
            if XalsXRDB.freshnessMinutes == nil then
                XalsXRDB.freshnessMinutes = Helpers.DEFAULT_FRESHNESS_MINUTES
            end
            if XalsXRDB.showHaulSummary == nil then
                XalsXRDB.showHaulSummary = true
            end
            if XalsXRDB.haulFramePosition == nil then
                XalsXRDB.haulFramePosition = { point = "CENTER", x = 0, y = 60 }
            end
            if XalsXRDB.haulShowIcons == nil then
                XalsXRDB.haulShowIcons = true
            end
            if XalsXRDB.haulFontScale == nil then
                XalsXRDB.haulFontScale = 1
            end
            if XalsXRDB.haulGatherTimer == nil then
                XalsXRDB.haulGatherTimer = false
            end
            if XalsXRDB.haulRouteTimer == nil then
                XalsXRDB.haulRouteTimer = false
            end
            if XalsXRDB.dungeonButtonEnabled == nil then
                XalsXRDB.dungeonButtonEnabled = false
            end

            -- ONE-TIME cleanup of orphaned keys from an abandoned earlier prototype
            -- (never referenced anywhere in the current codebase - found sitting in
            -- live SavedVariables 2026-08-10). Gated so this runs exactly once ever,
            -- NOT on every login - a future feature is free to reuse any of these
            -- exact key names (e.g. a real "route trail" feature) without this
            -- silently wiping it back out again after the first pass.
            if not XalsXRDB.clearedOrphanKeys2026 then
                XalsXRDB.showRouteTrail = nil
                XalsXRDB.routeTrailStyle = nil
                XalsXRDB.proximityHexagonEnabled = nil
                XalsXRDB.proximityHexagonDistance = nil
                XalsXRDB.proximityFadeAlpha = nil
                XalsXRDB.clearedOrphanKeys2026 = true
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
            print("|cff888888Xal's XR:|r Route keybinds available in Options -> Key Bindings (not set by default).")
            if not (Engine.HBD and Engine.HBDPins) then
                print("|cffff9900Xal's XR:|r Optional library 'HereBeDragons' not found - map/minimap pins are disabled and cross-zone distances are approximate until it's installed. Recording, routing, and the compass still work normally.")
            end
            
            -- Initialize modules
            if addonTable.NodeLogger.Init then addonTable.NodeLogger:Init() end
            if addonTable.PathPlanner.Init then addonTable.PathPlanner:Init() end
            if addonTable.Beacon.Init then addonTable.Beacon:Init() end
            if addonTable.DungeonBeacon.Init then addonTable.DungeonBeacon:Init() end
            if addonTable.Markers.Init then addonTable.Markers:Init() end
            if addonTable.SettingsPanel.Init then addonTable.SettingsPanel:Init() end
            if addonTable.QuickButton.Init then addonTable.QuickButton:Init() end
            if addonTable.RunTracker.Init then addonTable.RunTracker:Init() end
            if addonTable.MinimapButton and addonTable.MinimapButton.Register then addonTable.MinimapButton:Register() end
            if addonTable.WhatsNew and addonTable.WhatsNew.CheckAndShow then addonTable.WhatsNew:CheckAndShow() end

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
        if addonTable.PathPlanner.HandleZoneChange then
            addonTable.PathPlanner:HandleZoneChange()
        end
        if addonTable.QuickButton.Refresh then
            addonTable.QuickButton:Refresh()
        end
        if addonTable.DungeonNav.OnZoneChanged then
            addonTable.DungeonNav:OnZoneChanged()
        end
    elseif event == "SKILL_LINES_CHANGED" then
        HandleSkillLinesChanged()
    elseif event == "TRADE_SKILL_LIST_UPDATE" or event == "PLAYER_LOGIN" then
        if event == "PLAYER_LOGIN" and XalsXRDB and XalsXRDB.tomtomSyncEnabled == nil then
            -- First-time default, decided here (not ADDON_LOADED) so every
            -- addon is guaranteed loaded by now: if TomTom's actually
            -- installed, most players are going to be using it, so sync
            -- defaults ON instead of making them go find the checkbox.
            -- Never overrides a choice the player already made - this only
            -- ever fires once, the first time tomtomSyncEnabled is nil.
            -- Confirmed 2026-08-17.
            XalsXRDB.tomtomSyncEnabled = (TomTom ~= nil)
        end
        ProfessionCheckTick()
    end
end)
