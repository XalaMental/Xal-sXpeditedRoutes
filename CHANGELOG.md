# Xal's Xpedited Routes - Changelog

## 2.3.1 - September 2, 2026

---

Just added some screenshots of the new look to the CurseForge page, so you can actually see the Compact style before you update. Thanks for being part of the Xal family.

### 🆕 New
- Added screenshots of the new Compact-style floating helper, dungeon icon, Gather Tally, and Settings window to the CurseForge page.

## 2.3.0 - September 2, 2026

---

I've been sitting with the UI for a while now, and I finally sat back, took a real look at it, and realized I just didn't love how it had come together. So this one's a full overhaul, styling-wise - I went for something more minimalistic and cleaner across the whole addon, and honestly, I'm pretty happy with how it turned out. Took a lot of nitpicking to get here. I'm calling the new look "Compact" since that's basically what it is, and it's the new default - but if you're attached to the old look, it's still there, just relabeled "Classic" so you can switch back anytime. Found and fixed a handful of real bugs along the way too. Hope you like the cleaner look as much as I do.

### 🆕 New
- **Compact style (new default)** - a full visual overhaul across the whole addon: deep orange accents, dark indigo backgrounds, no boxed borders. Covers the floating helper button, Gather Tally, Settings window, and the What's New popup.
- **Floating helper redesign** - "Gather" is now a plain orange text link sitting above the profession X's instead of a boxed button, the dungeon-portal shortcut now floats independently with its own draggable position, and the active gathering type shows with a soft colored glow instead of a dot.
- **Gather Tally redesign** - items now pop up individually as icon + name + count, each with its own colored border, instead of one boxed list. Click the "Gather Tally" title to collapse it down to just a total count, click again to expand it back out.
- **Classic style preserved** - the original look for the floating helper, Gather Tally, and What's New popup is still there if you'd rather keep it - switch it back per-window in Settings.

### 🔧 Fixed
- Removed a leftover "glow behind the Gather text" setting that no longer did anything.

## 2.2.0 - August 20, 2026

---

Made two changes this time - swapped every button in the addon over to a cleaner text-link look instead of the boxed style, since that's what's been looking better across my other addons lately, and laid the groundwork for a companion addon (Xal's Routes Data) that'll let you import a big batch of pre-collected nodes instead of starting your own collection from scratch. Thanks for being part of the Xal family - hope you like the cleaner look.

### 🆕 New
- **Cleaner button style** - every button in the addon (settings tabs, action buttons) now shows as clean text instead of a boxed button.
- **Groundwork for node importing** - lays the plumbing for pulling in a big batch of pre-collected nodes from a companion addon (Xal's Routes Data, coming soon), instead of starting your own collection from scratch.

### 🔧 Fixed
- Fixed unrelated loot (a killed critter, a fish catch) still occasionally getting miscounted into the wrong Gather Tally section - last version's fix for this didn't reliably catch every case.
- Fixed the Gather button and the Settings "Defaults" button crashing when you hovered them, caused by the button style change above.

## 2.1.0 - August 17, 2026

---

Lumberjacking's been on my list for a while, and this is me finally getting it in - it's now a real third gathering type right alongside Mining and Herbalism, with its own icon, its own color, and its own spot in the Gather Tally. Wasn't as simple as just adding a color though - I had to actually track down the real spell IDs Lumberjacking uses (my first guess from research turned out wrong, so I double-checked everything live before trusting it), and along the way I found a couple of real bugs worth fixing regardless of Lumberjacking - gathering something wasn't always showing up in your tally if you weren't already mid-route, and loot from something unrelated could occasionally get miscounted into the wrong section. Both fixed. Thanks for being part of the Xal family - hope you enjoy chopping some wood.

### 🆕 New
- **Lumberjacking support** - a full third gathering type alongside Mining and Herbalism: its own map/minimap pins, its own icon on the floating helper button, and its own Gather Tally section. Routes and combines with Mining/Herbalism the same way those two already combine with each other. Retail only (Lumberjacking itself doesn't exist on Classic). Toggle it off in Options → General if you'd rather not see it.
- Lumber nodes don't group into a shared stop the way Mining/Herbalism can - they're spread out enough that grouping wasn't helping.

### 🔧 Fixed
- Fixed gathering something not showing up in the Gather Tally at all if you weren't already mid-route or hadn't clicked Gather first.
- Fixed unrelated loot (a killed critter, a fish catch) landing right after a gather sometimes getting miscounted into that gather's tally section.

## 2.0.0 - August 17, 2026

---

This one's mostly me catching a few things I realized weren't the best way to do them. TomTom's now the default way Routes navigates for you, made a handful of visual repairs, and fixed some dungeon navigation bugs that turned up along the way. Thanks for being part of the Xal family - hope this makes your routes a little smoother.

### 🆕 New
- **Dungeon portal routing** - routes you through the Timeways portal room in Silvermoon for King's Rest, Temple of Sethraliss, and Ruby Life Pools.
- **Dungeon nav has its own arrow now**, fully independent from the gathering-route compass.
- **TomTom sync defaults on** if TomTom's installed - our own arrow's still the fallback. Existing setups untouched; check/change it via the What's New popup.
- **TomTom's arrow no longer sits on top of the node** - nudged to the side.

### 🔧 Fixed
- Minimap button's right-click now opens the Gather Tally window.
- Gather Tally's item counts/status line no longer crowd the window's border.
- TomTom waypoints for dungeon nav no longer vanish before you arrive.
- Auto-advance distance now defaults to 50 yards (up from 20), slider goes to 150.

### ⚙️ Under the hood
- Fixed the gathering route's distance calc silently using an approximation instead of the real one.
- Dungeon nav and TomTom no longer fight over TomTom's one arrow.

## 1.3.2 - August 10, 2026

---

I realized the original routing system - point yourself at every single node, one after another - could get pretty overwhelming once you had a lot of nodes packed into one small area. So this update's focus is simplifying that: nearby nodes now group into a single stop instead of a separate detour for each one, so your route actually flows instead of zig-zagging. Along with that, I added a trail line on the minimap pointing straight to your next stop, and fixed a few routing bugs that turned up while testing all this.

### 🆕 New
- **Node grouping** - nearby nodes now group into a single route stop instead of a separate waypoint for each one, so routes flow through a dense patch instead of zig-zagging node to node. On by default; adjustable in Options -> Map Markers if you want it tighter or looser.
- **Minimap trail line** - a thin line on your minimap points straight from you to your next stop, alongside the usual arrow. On by default; toggle it in Options -> Waypoint.
- **Dual-profession routing, now explained** - if you gather both Mining and Herbalism, lighting up both profession icons on the floating button builds one combined route through every node of either type. This already worked, it just wasn't spelled out anywhere - now it is, both here and in a tooltip.

### ⚙️ Under the hood
- The waypoint arrow and the route-generated chat message both now show stop count separately from node count, so it's clear grouping combined nodes together rather than dropping any.
