# Xal's Xpedited Routes - Changelog

## Release 1.1.1 - August 6, 2026

---

### 🆕 New
- **RunTracker.lua** - Added the gathering haul tracker: a live, movable window that tallies everything you gather during a route and stays open at the end so you can read or record it.
- **ChatCommands.lua** - Added the `/xxr haul` command (and `/xxr haul on` / `off`) to open and toggle the haul window.
- **SettingsPanel.lua** - Added an Options toggle for the live haul window.
- **PathPlanner.lua** - The haul window now opens when a route starts and finalizes when the route ends.
- **Engine.lua** - The haul tracker and its saved settings now load at startup.

### ⚙️ Under the hood
- **Bootstrap.lua** - Registered the new haul-tracker module.
- **NodeLogger.lua** - Kept the new haul settings out of the node-cleanup sweep.
- **XalsXpeditedRoutes.toc** - Loaded the new RunTracker file.
- **.pkgmeta** - Switched release packaging to a maintained changelog file.
