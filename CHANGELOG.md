# Xal's Xpedited Routes - Changelog

## Release 1.2.0 - August 6, 2026

---

### 🆕 New
- **RunTracker.lua** - Added the Gathering Haul tracker: a live, movable window that tallies everything you gather during a route and stays open at the end so you can read or record your haul. Summon it anytime with /xxr haul.
- **SettingsPanel.lua** - Added an Options toggle for the live haul window.

### 🧪 Xperimental
- **Node Freshness is now opt-in** *(off by default)* - The /xxr freshness <0-60> option (skips nodes you gathered too recently to have respawned yet) is now off unless you turn it on, while I re-tune it. Flip it on with /xxr freshness and let me know how it works for you.

### ⚙️ Under the hood
- **Bootstrap.lua** - Registered the new haul-tracker module.
- **Engine.lua** - Loads the haul tracker and its saved settings at startup.
- **PathPlanner.lua** - Opens the haul window when a route starts and finalizes it when the route ends.
- **NodeLogger.lua** - Keeps the haul settings out of the node-cleanup sweep.
- **ChatCommands.lua** - Added /xxr haul and /xxr freshness, and cleaned up duplicated command handling.
- **XalsXpeditedRoutes.toc** - Removed the redundant Bindings.xml listing that caused login Lua warnings.
- **discord_changelog.py** - Each release now auto-announces to the Discord server.
