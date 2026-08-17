# Xal's Xpedited Routes - Changelog

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
