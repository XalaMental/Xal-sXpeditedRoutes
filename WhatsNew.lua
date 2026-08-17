-- WhatsNew.lua
-- Xal's Xpedited Routes
--
-- Shows a "what's new" splash automatically the FIRST time a player logs in
-- after the addon has been updated to a new version - never during normal,
-- unchanged play. Compares the addon's real installed version (read from the
-- .toc at runtime) against the last version this player actually saw, and
-- only pops up when they differ.
--
-- Claude already writes CHANGELOG.md by hand before every release, in Dev,
-- before Jason ever commits/pushes anything - same moment, update WHATS_NEW
-- below (the "date" field and the intro/sections content) to match. It's
-- one more file touched during normal release prep, nothing extra for Jason
-- to remember or do - same as Routes Changelog.md / routes_changelog_dev.md
-- already get updated every release. A WoW addon can't read the external
-- CHANGELOG.md file live at runtime (Blizzard's addon sandbox has no file
-- access) - which is exactly why this gets written by hand at prep time
-- instead, not because it's some separate manual chore layered on top.
-- The version NUMBER shown on the splash does NOT need updating here - it's
-- read live from the real installed .toc version, same value used for the
-- update-check itself, so there's only ever one place that can go stale.
local addonName, addonTable = ...
addonTable.WhatsNew = {}
local W = addonTable.WhatsNew
local Brand = addonTable.BrandStyle

-- ── Update this block every release to match CHANGELOG.md ──────
-- (no "version" field here on purpose - see note above)
W.WHATS_NEW = {
    date = "August 17, 2026",
    intro = "",
    sections = {
        { heading = "TomTom Integration", items = {
            "Sync now defaults on if TomTom's installed, since most players already navigate with it - our own arrow is still there as the fallback either way.",
            "And if you're already part of the family here, nothing changes for you automatically - but if you'd like the new default too, just hit the button below and you're set.",
        } },
    },
    -- One-time upgrade notice - remove this whole block once this has
    -- shipped and aged out. Same splash for every player, new installs
    -- included; harmless either way, so no conditional needed.
    actionButton = {
        label = "Open TomTom Settings",
        onClick = function()
            if addonTable.SettingsPanel and addonTable.SettingsPanel.OpenIntegrations then
                addonTable.SettingsPanel:OpenIntegrations()
            end
        end,
    },
}

-- ── Version check ────────────────────────────────────────────
-- C_AddOns.GetAddOnMetadata is the current namespaced API (available on
-- Retail, MoP Classic, and Classic Era alike since Dragonflight); the bare
-- global is kept as a fallback only, same defensive pattern used elsewhere
-- in Jason's addons for other C_* namespaces.
local function GetInstalledVersion()
    local v
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        v = C_AddOns.GetAddOnMetadata(addonName, "Version")
    elseif _G.GetAddOnMetadata then
        v = _G.GetAddOnMetadata(addonName, "Version")
    end
    -- The .toc's "@project-version@" token only gets replaced with a real
    -- number by the packager, which only runs on an actual tagged release.
    -- Testing straight from local files (no tag pushed) leaves it as this
    -- literal, unsubstituted text - show a friendly fallback instead of the
    -- broken-looking placeholder string.
    if v == "@project-version@" then
        return "dev"
    end
    return v
end

local FW = 500
local MAX_FH = 560 -- clamp so an unusually long release note can't run off-screen

local function BuildFrame(installedVersion)
    local f = CreateFrame("Frame", "XalsXRWhatsNewFrame", UIParent)
    f:SetSize(FW, 360) -- placeholder height; set for real below once content is laid out
    -- Staggered off dead-center - see the "Default window position" rule
    -- in the shared brand-style memory.
    f:SetPoint("CENTER", UIParent, "CENTER", 180, 160)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)

    Brand.ApplyBackground(f)
    Brand.ApplyBackgroundImage(f)
    Brand.DrawBorder(f)

    local data = W.WHATS_NEW
    Brand.Title(f, "What's New", 26, "TOP", f, "TOP", 0, -24)

    -- "installedVersion" is the REAL live version (from CheckAndShow), not a
    -- hand-typed field - it always matches whatever actually got tagged.
    local verLine = Brand.FS(f, "Version " .. installedVersion .. (data.date and ("  ·  " .. data.date) or ""),
        "Fonts\\ARIALN.TTF", 15, "", Brand.GOLD[1], Brand.GOLD[2], Brand.GOLD[3])
    verLine:SetPoint("TOP", f, "TOP", 0, -58)
    verLine:SetJustifyH("CENTER")

    Brand.DrawDivider(f, 30, 78, FW - 60)

    -- Standing link, every splash regardless of that version's content -
    -- not part of the release notes themselves.
    local discordLink = Brand.MakeDiscordLink(f)
    discordLink:SetPoint("TOPRIGHT", f, "TOPRIGHT", -20, -20)

    local y = 92
    if data.intro and data.intro ~= "" then
        local intro = Brand.FS(f, data.intro, "Fonts\\ARIALN.TTF", 16, "", 0.9, 0.9, 0.9)
        intro:SetPoint("TOPLEFT", f, "TOPLEFT", 30, -y)
        intro:SetWidth(FW - 60)
        intro:SetJustifyH("LEFT")
        intro:SetWordWrap(true)
        y = y + (intro:GetStringHeight() or 18) + 14
    end

    for _, section in ipairs(data.sections or {}) do
        -- Genuinely bold - Brand.TITLE_FONT_PATH (Simply Sans Bold) with the
        -- same drop-shadow treatment as the "What's New" title itself, not
        -- ARIALN.TTF (a regular-weight font; the "OUTLINE" flag draws a
        -- stroke, it doesn't make a font bold). Called out directly
        -- 2026-08-17 - the previous version LOOKED like styled text, not an
        -- actual bold heading.
        Brand.Title(f, section.heading, 18, "TOPLEFT", f, "TOPLEFT", 30, -y)
        y = y + 26
        Brand.DrawDivider(f, 30, y, FW - 60)
        y = y + 12

        for _, item in ipairs(section.items or {}) do
            local bullet = Brand.FS(f, "-  " .. item, "Fonts\\ARIALN.TTF", 15, "",
                Brand.GOLD[1], Brand.GOLD[2], Brand.GOLD[3])
            bullet:SetPoint("TOPLEFT", f, "TOPLEFT", 36, -y)
            bullet:SetWidth(FW - 76)
            bullet:SetJustifyH("LEFT")
            bullet:SetWordWrap(true)
            y = y + (bullet:GetStringHeight() or 18) + 6
        end
        y = y + 10
    end

    -- Optional second button for a version that needs the player to actually
    -- do something, not just read about it (e.g. the TomTom-default change).
    -- Same splash for everyone, new installs included - it's harmless for a
    -- new player to see "open TomTom Settings" even though they were
    -- already auto-defaulted, the checkbox is just already checked.
    -- Simplified 2026-08-17 - was conditional on tomtomSyncEnabled, cut
    -- because it doesn't need to be.
    local action = data.actionButton

    if action then
        local actionBtn = Brand.MakeButton(f, action.label, 190, 28, function()
            f:Hide()
            if action.onClick then action.onClick() end
        end)
        actionBtn:SetPoint("BOTTOM", f, "BOTTOM", -100, 18)

        local closeBtn = Brand.MakeButton(f, "Got it", 110, 28, function()
            f:Hide()
        end)
        closeBtn:SetPoint("BOTTOM", f, "BOTTOM", 100, 18)
    else
        local closeBtn = Brand.MakeButton(f, "Got it", 110, 28, function()
            f:Hide()
        end)
        closeBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 18)
    end

    -- Size the frame to its ACTUAL content (y = how far the layout got, plus
    -- room for the close button + bottom padding) instead of a guessed fixed
    -- height - a longer release's content would otherwise clip or overlap
    -- the button. BOTTOM-anchored elements (the button, the border/background,
    -- both resize-safe) re-settle automatically once the frame's real size
    -- is set.
    f:SetHeight(math.min(y + 56, MAX_FH))

    return f
end

-- Call this from Engine's Init - checks the version and shows the splash
-- only when it's genuinely changed since this player last saw it.
function W:CheckAndShow()
    local installed = GetInstalledVersion()
    if not installed then return end -- metadata unavailable, don't error, just skip

    -- Uses the addon's account-wide DB - XalsXRDB - same table every other
    -- saved setting lives in, so no extra SavedVariables entry needs
    -- registering in the .toc.
    local db = _G["XalsXRDB"]
    if not db then return end

    if db.lastSeenVersion ~= installed then
        db.lastSeenVersion = installed
        -- pcall so a bad edit to WHATS_NEW (typo, missing field) can never
        -- break the rest of the addon's login - worst case, the splash just
        -- silently doesn't show that one time.
        local ok, frame = pcall(BuildFrame, installed)
        if ok and frame then frame:Show() end
    end
end
