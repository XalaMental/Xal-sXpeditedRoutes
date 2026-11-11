-- XalsSkins.lua
-- Xal's addon family - shared skin palettes
--
-- MASTER COPY: D:\WoW_Addons\Dev\Assets\Skins\XalsSkins.lua
-- A WoW addon can't read another addon's files, so every addon ships its OWN
-- copy of this file (loaded right after its BrandStyle.lua in the .toc). Edit
-- the master here, then copy it into each addon - never edit an addon's copy
-- on its own, or the family drifts apart.
--
-- A skin is only a PALETTE: same layout, same fonts, different colors. Applying
-- one copies its colors, IN PLACE, into the addon's Brand color tables
-- (BrandStyle.lua), so every widget built afterwards picks them up. Call
-- Skins.Apply(Brand, key) once at load, before any window is built; changing the
-- skin later needs a reload, since widgets keep the color they were built with.
--
-- Palette fields (all "#RRGGBB"):
--   window       the window's own background (and the sidebar)
--   panel        the content area's background
--   header       titles, section headers, checkbox boxes, the one accent line
--   text         checkbox / slider labels
--   body         plain reading text (What's New, long notes); same as text except in the original look
--   desc         dim description text
--   line         dividers and borders
--   tab          sidebar tabs, not selected
--   tabSelected  sidebar tab, selected
--   hover        what a text-link button turns to under the mouse
--   light        true for a light skin (a few details flip)
--   image        0-1, how much of the old swirl background image to show
--
-- The first skin, "current", is the original deep-crimson-on-black look, kept
-- exactly as it was; the rest are readable alternatives (every header and label
-- color here measures at least 4.9 to 1 against its panel).
local addonName, addonTable = ...

local Skins = {}
addonTable.Skins = Skins

Skins.ORDER = { "current", "ember", "bronze", "midnight", "indigo", "parchment" }

Skins.LABELS = {
    current = "Crimson (original)",
    ember = "Ember",
    bronze = "Bronze ledger",
    midnight = "Midnight",
    indigo = "Indigo slate",
    parchment = "Parchment (light)",
}

Skins.PALETTES = {
    current = {
        window = "#08070F", panel = "#08070F", header = "#681417", text = "#681417",
        body = "#D9D9D9",
        desc = "#9E9E9E", line = "#101020", tab = "#9696D2", tabSelected = "#CC3036",
        hover = "#FFFFFF", light = false, image = 1,
    },
    ember = {
        window = "#0E0B10", panel = "#17121A", header = "#E2553F", text = "#F1E6D8",
        body = "#F1E6D8",
        desc = "#A79F98", line = "#3A1F24", tab = "#A79F98", tabSelected = "#E2553F",
        hover = "#FFFFFF", light = false, image = 0,
    },
    bronze = {
        window = "#1A1714", panel = "#231F1B", header = "#FFCC4C", text = "#EDE3D0",
        body = "#EDE3D0",
        desc = "#A89F8E", line = "#807361", tab = "#A89F8E", tabSelected = "#FFCC4C",
        hover = "#FFFFFF", light = false, image = 0,
    },
    midnight = {
        window = "#0A0D14", panel = "#111827", header = "#8CB2F2", text = "#E6EDF7",
        body = "#E6EDF7",
        desc = "#9AA7BA", line = "#2A3A55", tab = "#9AA7BA", tabSelected = "#FF8C40",
        hover = "#FFFFFF", light = false, image = 0,
    },
    indigo = {
        window = "#14141A", panel = "#1C1C29", header = "#B9B9F5", text = "#ECECFA",
        body = "#ECECFA",
        desc = "#9C9CB8", line = "#4C4C80", tab = "#9C9CB8", tabSelected = "#E8A24A",
        hover = "#FFFFFF", light = false, image = 0,
    },
    parchment = {
        window = "#C9B98F", panel = "#D8C8A3", header = "#7A1F24", text = "#2B2118",
        body = "#2B2118",
        desc = "#5C5040", line = "#8C7A52", tab = "#4F4434", tabSelected = "#7A1F24",
        hover = "#2B2118", light = true, image = 0,
    },
}

local function Rgb(hex)
    local h = hex:gsub("#", "")
    return tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255
end

-- Copies a hex color into an existing { r, g, b[, a] } table in place, so
-- everything already holding a reference to that table sees the new color.
local function Into(target, hex)
    if type(target) ~= "table" then return end
    target[1], target[2], target[3] = Rgb(hex)
end

function Skins.Get(key)
    return Skins.PALETTES[key] or Skins.PALETTES.current
end

-- Brand is the addon's BrandStyle table. Returns the key actually applied.
function Skins.Apply(Brand, key)
    if not Skins.PALETTES[key] then key = "current" end
    local p = Skins.PALETTES[key]

    Into(Brand.HEADER_COLOR, p.header)   -- ACCENT and GOLD are the same table
    Into(Brand.BG, p.window)
    Into(Brand.WINDOW_BG, p.window)
    Into(Brand.PANEL_COLOR, p.panel)
    Into(Brand.TEXT_COLOR, p.text)
    Into(Brand.BODY_COLOR, p.body)
    Into(Brand.DESC_COLOR, p.desc)
    Into(Brand.DIVIDER_COLOR, p.line)
    Into(Brand.TAB_COLOR, p.tab)
    Into(Brand.TAB_SELECTED_COLOR, p.tabSelected)
    Into(Brand.HOVER_COLOR, p.hover)
    Brand.IS_LIGHT = p.light and true or false
    Brand.IMAGE_ALPHA = p.image
    Brand.skinKey = key
    return key
end
