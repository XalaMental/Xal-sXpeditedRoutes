# Xal's Xpedited Routes - Changelog

## Release 1.1.2 - August 6, 2026

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
- **release.yml** - Added a step that announces each release in Discord.
- **discord_changelog.py** - Added the script that posts the release changelog to a Discord webhook.
- **CHANGELOG.md** - Bumped to Release 1.1.2.
- **Helpers.lua** - Re-synced for the 1.1.2 refresh (Classic gather-rank support, no functional change).
- **Markers.lua** - Re-synced for the 1.1.2 refresh (Classic marker fix, no functional change).
- **XalsXpeditedRoutes_Mists.toc** - Re-synced for the 1.1.2 refresh (MoP Classic build).
- **XalsXpeditedRoutes_Vanilla.toc** - Re-synced for the 1.1.2 refresh (Classic Era build).
- **Bindings.xml** - Re-synced for the 1.1.2 refresh (keybind registration).
- **README.md** - Refreshed for the 1.1.2 release; addon refresh to get the repo current, no functional change.
