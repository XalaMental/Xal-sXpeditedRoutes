-- BrandStyle.lua
-- Xal's Xpedited Routes
--
-- Xal's shared visual brand. Background/accent/title treatment are from Xal's
-- Craft Courier's splash panel; the button style is from Xal's Compendium
-- (Courier's beveled "steel" buttons looked visually off - inconsistent
-- highlight/shadow read - once placed in a horizontal row, so Compendium's
-- flat button replaced it as the standard, confirmed 2026-08-09). Every
-- border/divider line is at least 2px - a 1px line can fail to render
-- reliably depending on UI scale, which is why Courier's border was already
-- 2px; dividers are brought up to match here too.
--
-- Use these helpers for splash screens, settings panels, and any other
-- custom-drawn frame. Standard interactive controls that AREN'T part of this
-- brand spec (checkboxes, sliders, edit boxes) should still use Blizzard's
-- native templates (UICheckButtonTemplate etc.) - only buttons/borders/titles
-- get the custom treatment.
local addonName, addonTable = ...
addonTable.BrandStyle = {}
local Brand = addonTable.BrandStyle

-- ── Colours (r, g, b) ─────────────────────────────────────────
Brand.ACCENT = { 0.72, 0.55, 0.22 }   -- warm bronze-gold
Brand.GOLD   = { 0.60, 0.47, 0.30 }   -- secondary/body text tone
Brand.BG     = { 0.035, 0.035, 0.035, 1 } -- near-black, fully opaque
Brand.LINE_THICKNESS = 2 -- minimum for ANY border/divider - never go below this
-- Minimum gap between a panel's true outer edge and the nearest button/text
-- (close buttons especially). DrawBorder()'s line occupies out to 8px in
-- (6px inset + 2px thick) - the FIRST version of this constant was set to
-- exactly 8, which technically cleared the border but left ZERO actual
-- visual gap (content started precisely where the border line ended), so
-- it still read as crammed/touching. Bumped to 14 (a real ~6px of clear
-- space beyond the border) after seeing this live in-game - confirmed
-- 2026-08-09.
Brand.SAFE_MARGIN = 14

-- ── T()  ─ solid-colour texture rectangle.
-- x, y measured from the parent's TOP-LEFT corner (y increases downward).
-- Uses PixelUtil so every edge snaps to a whole physical screen pixel -
-- at a non-integer UI Scale (e.g. 71%), a plain SetPoint/SetSize can land
-- a 2px line on a fractional pixel, which the renderer then blurs/dims.
-- Confirmed 2026-08-09: this was making some sidebar tab borders look
-- randomly "less pronounced" than others, reproducibly, at 71% scale.
function Brand.T(parent, x, y, w, h, r, g, b, a, layer)
    local tex = parent:CreateTexture(nil, layer or "ARTWORK")
    PixelUtil.SetPoint(tex, "TOPLEFT", parent, "TOPLEFT", x, -y)
    PixelUtil.SetSize(tex, w, h)
    tex:SetColorTexture(r, g, b, a or 1)
    return tex
end

-- ── FS()  ─ a FontString with a specific font/size/colour.
function Brand.FS(parent, text, fontPath, size, flags, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(fontPath, size, flags or "")
    fs:SetText(text)
    fs:SetTextColor(r, g, b, 1)
    return fs
end

-- ── Title()  ─ the branded Morpheus-font title treatment, with its
-- drop-shadow layer, in one call. Returns the visible (front) fontstring.
function Brand.Title(parent, text, size, anchorPoint, relTo, relPoint, x, y)
    local shadow = Brand.FS(parent, text, "Fonts\\MORPHEUS.TTF", size, "OUTLINE", 0.05, 0.04, 0.02)
    PixelUtil.SetPoint(shadow, anchorPoint, relTo, relPoint, x + 2, y - 2)
    shadow:SetJustifyH("CENTER")

    local title = Brand.FS(parent, text, "Fonts\\MORPHEUS.TTF", size, "OUTLINE",
        Brand.ACCENT[1], Brand.ACCENT[2], Brand.ACCENT[3])
    PixelUtil.SetPoint(title, anchorPoint, relTo, relPoint, x, y)
    title:SetJustifyH("CENTER")
    return title
end

-- ── MakeButton()  ─ Xal's Compendium's flat button (the confirmed standard,
-- verified 2026-08-09 straight from Options.lua's MakeFlatButton): thin
-- border, semi-transparent dark fill, plain white label, no bevel/gradient -
-- reads cleanly even in a horizontal row, which is exactly what Courier's
-- beveled version didn't do. Border color changed 2026-08-09 from a plain
-- light grey to the same accent gold as the panel border, so buttons read
-- as part of the same branded frame instead of a mismatched grey outline;
-- label text stays white either way. Selected vs. normal state is now
-- carried entirely by fill brightness (see SetSelected below).
-- Call btn:SetSelected(true/false) for a brighter fill (tabs).
local BTN_BORDER = { Brand.ACCENT[1], Brand.ACCENT[2], Brand.ACCENT[3], 1 }
local BTN_BORDER_SELECTED = { Brand.ACCENT[1], Brand.ACCENT[2], Brand.ACCENT[3], 1 }
-- Unselected label color - a warm amber-orange (matched from a reference
-- screenshot of WoW's own "World Quests" header text, 2026-08-09). Not the
-- same as Brand.GOLD (that's the muted secondary body-text tone used
-- elsewhere) - this is deliberately more vivid/orange so an inactive
-- button label still pops against the dark fill.
local BTN_LABEL_UNSELECTED = { 0.95, 0.60, 0.10 }

function Brand.MakeButton(parent, text, w, h, onClick)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    PixelUtil.SetSize(btn, w, h)
    -- Fill only - no backdrop edge. Blizzard's backdrop-edge system computes
    -- each side's thickness independently and isn't guaranteed to come out
    -- symmetric at a non-integer UI Scale (confirmed 2026-08-09: it was
    -- rendering every button's left/right border at visibly different
    -- thickness, uniformly, at 71% scale). Border is hand-drawn below
    -- instead, using the same pixel-snapped technique as Brand.DrawBorder.
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    btn:SetBackdropColor(0.1, 0.1, 0.1, 0.6)

    local thick = Brand.LINE_THICKNESS
    local borderTop = btn:CreateTexture(nil, "ARTWORK")
    PixelUtil.SetPoint(borderTop, "TOPLEFT", btn, "TOPLEFT", 0, 0)
    PixelUtil.SetPoint(borderTop, "TOPRIGHT", btn, "TOPRIGHT", 0, 0)
    PixelUtil.SetHeight(borderTop, thick)

    local borderBottom = btn:CreateTexture(nil, "ARTWORK")
    PixelUtil.SetPoint(borderBottom, "BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    PixelUtil.SetPoint(borderBottom, "BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    PixelUtil.SetHeight(borderBottom, thick)

    local borderLeft = btn:CreateTexture(nil, "ARTWORK")
    PixelUtil.SetPoint(borderLeft, "TOPLEFT", btn, "TOPLEFT", 0, 0)
    PixelUtil.SetPoint(borderLeft, "BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    PixelUtil.SetWidth(borderLeft, thick)

    local borderRight = btn:CreateTexture(nil, "ARTWORK")
    PixelUtil.SetPoint(borderRight, "TOPRIGHT", btn, "TOPRIGHT", 0, 0)
    PixelUtil.SetPoint(borderRight, "BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    PixelUtil.SetWidth(borderRight, thick)

    local function SetBorderColor(r, g, b, a)
        borderTop:SetColorTexture(r, g, b, a)
        borderBottom:SetColorTexture(r, g, b, a)
        borderLeft:SetColorTexture(r, g, b, a)
        borderRight:SetColorTexture(r, g, b, a)
    end
    SetBorderColor(BTN_BORDER[1], BTN_BORDER[2], BTN_BORDER[3], BTN_BORDER[4])

    -- Label starts in the dim gold tone (not selected/pressed) and switches
    -- to white via SetSelected below - gives an at-a-glance read of which
    -- tab is active instead of relying on the subtle fill-brightness
    -- difference alone. Confirmed 2026-08-09.
    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER")
    label:SetText(text)
    label:SetTextColor(BTN_LABEL_UNSELECTED[1], BTN_LABEL_UNSELECTED[2], BTN_LABEL_UNSELECTED[3], 1)
    btn.label = label

    btn:SetScript("OnEnter", function(self)
        if not self.selected then self:SetBackdropColor(0.18, 0.18, 0.18, 0.75) end
    end)
    btn:SetScript("OnLeave", function(self)
        if not self.selected then self:SetBackdropColor(0.1, 0.1, 0.1, 0.6) end
    end)
    if onClick then btn:SetScript("OnClick", onClick) end

    function btn:SetSelected(selected)
        self.selected = selected
        if selected then
            self:SetBackdropColor(0.22, 0.22, 0.22, 0.85)
            SetBorderColor(BTN_BORDER_SELECTED[1], BTN_BORDER_SELECTED[2], BTN_BORDER_SELECTED[3], BTN_BORDER_SELECTED[4])
            label:SetTextColor(1, 1, 1, 1)
        else
            self:SetBackdropColor(0.1, 0.1, 0.1, 0.6)
            SetBorderColor(BTN_BORDER[1], BTN_BORDER[2], BTN_BORDER[3], BTN_BORDER[4])
            label:SetTextColor(BTN_LABEL_UNSELECTED[1], BTN_LABEL_UNSELECTED[2], BTN_LABEL_UNSELECTED[3], 1)
        end
    end

    -- Exposed so call sites that need a one-off custom border color (e.g. a
    -- destructive/danger-styled button) have a real hook, same idea as
    -- SetSelected above - there is only ONE button implementation in this
    -- addon; every call site drives it through these methods rather than
    -- hand-rolling its own border. Confirmed standard 2026-08-09.
    function btn:SetBorderColor(r, g, bC, a)
        SetBorderColor(r, g, bC, a)
    end

    return btn
end

-- ── DrawBorder()  ─ single clean accent-color line around a frame.
-- Deliberately simple - no corner ornaments or tick marks. Each side is
-- anchored to BOTH ends of that edge (not a fixed x/y/w/h), so it auto-
-- stretches if the frame resizes later - important for anything that grows
-- or shrinks at runtime (a list that adds/removes rows, etc.), not just
-- fixed-size splash screens.
function Brand.DrawBorder(f, inset)
    inset = inset or 6
    local thick = Brand.LINE_THICKNESS
    local r, g, b = Brand.ACCENT[1], Brand.ACCENT[2], Brand.ACCENT[3]

    local top = f:CreateTexture(nil, "ARTWORK")
    PixelUtil.SetPoint(top, "TOPLEFT", f, "TOPLEFT", inset, -inset)
    PixelUtil.SetPoint(top, "TOPRIGHT", f, "TOPRIGHT", -inset, -inset)
    PixelUtil.SetHeight(top, thick)
    top:SetColorTexture(r, g, b, 1)

    local bottom = f:CreateTexture(nil, "ARTWORK")
    PixelUtil.SetPoint(bottom, "BOTTOMLEFT", f, "BOTTOMLEFT", inset, inset)
    PixelUtil.SetPoint(bottom, "BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, inset)
    PixelUtil.SetHeight(bottom, thick)
    bottom:SetColorTexture(r, g, b, 1)

    local left = f:CreateTexture(nil, "ARTWORK")
    PixelUtil.SetPoint(left, "TOPLEFT", f, "TOPLEFT", inset, -inset)
    PixelUtil.SetPoint(left, "BOTTOMLEFT", f, "BOTTOMLEFT", inset, inset)
    PixelUtil.SetWidth(left, thick)
    left:SetColorTexture(r, g, b, 1)

    local right = f:CreateTexture(nil, "ARTWORK")
    PixelUtil.SetPoint(right, "TOPRIGHT", f, "TOPRIGHT", -inset, -inset)
    PixelUtil.SetPoint(right, "BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, inset)
    PixelUtil.SetWidth(right, thick)
    right:SetColorTexture(r, g, b, 1)

    return top, bottom, left, right
end

-- ── DrawDivider()  ─ the thin section-separator line used between content
-- blocks (feature lists, header bars, etc.)
function Brand.DrawDivider(parent, x, y, width)
    return Brand.T(parent, x, y, width, Brand.LINE_THICKNESS, 0.16, 0.12, 0.05, 1)
end

-- ── ApplyBackground()  ─ the standard opaque near-black frame background.
function Brand.ApplyBackground(f)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(Brand.BG[1], Brand.BG[2], Brand.BG[3], Brand.BG[4])
    return bg
end
