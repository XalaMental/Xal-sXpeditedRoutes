# Xal's Xpedited Routes - Changelog

## 1.3.2 - August 10, 2026

---

Smarter routing: nearby nodes now group into one stop instead of a separate waypoint for each, plus a couple of small fixes and clarifications.

### 🆕 New
- **Node grouping** - nearby nodes now group into a single route stop instead of a separate waypoint for each one, so routes flow through a dense patch instead of zig-zagging node to node. On by default; adjustable in Options -> Map Markers if you want it tighter or looser.
- **Minimap trail line** - a thin line on your minimap points straight from you to your next stop, alongside the usual arrow. On by default; toggle it in Options -> Waypoint.
- **Dual-profession routing, now explained** - if you gather both Mining and Herbalism, lighting up both profession icons on the floating button builds one combined route through every node of either type. This already worked, it just wasn't spelled out anywhere - now it is, both here and in a tooltip.

### ⚙️ Under the hood
- The waypoint arrow and the route-generated chat message both now show stop count separately from node count, so it's clear grouping combined nodes together rather than dropping any.
