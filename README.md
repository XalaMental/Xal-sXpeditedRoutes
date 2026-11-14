# Xal's Xpedited Routes

**Xal's Xpedited Routes** records the herbs, ore and lumber you gather, draws them on your map and minimap, and builds the fastest route through them with an on-screen compass. On **WoW: Forever** it also glows the herb or ore in front of you, plays a sound when you get to one, and starts you off with a full set of Classic nodes.

Works on Retail, WoW: Forever, MoP Classic and Classic Era. Lumberjacking is Retail only; the node highlight, live node scan (currently not working) and built-in nodes are Forever only.

> The idea: combine gathering-node tracking and route optimization - concepts pioneered separately by GatherMate2/Gatherer (node recording) and Routes (route optimization) - into one tool instead of several separate addons.

## Requirements

**Requires [HereBeDragons](https://www.curseforge.com/wow/addons/herebedragons) for minimap and world map markers to show at all** - not bundled, install it separately. Without it, recording, routing, the compass and the floating helper button still work, but no pins are drawn. See "HereBeDragons Dependency" below.

[TomTom](https://www.curseforge.com/wow/addons/tomtom) is optional and only adds the route hand-off described below. The live node scan also works best alone: other addons that scan the minimap the same way (Lueur, NodeSight, GatherCompass) fight over it if more than one runs at once.

## Key features

*   **Automatic recording** of every herb, ore and lumber node you gather, saved to your own `SavedVariables`. Re-gathering a saved node nudges its marker onto the real spot.
*   **Route optimization:** a greedy nearest-first route improved with a 2-opt pass, using real distances in yards when HereBeDragons is installed. Nearby nodes group into one stop.
*   **Compass and trail line:** a movable arrow with the distance to your next stop, auto-advance, skip, and a line on the minimap pointing at your next stop.
*   **Map and minimap markers:** hollow X or star, adjustable size and opacity, with your route target marked. Markers for node types your character can't gather are hidden.
*   **Floating helper button:** one click starts or updates a route; Mining, Herbalism and Lumberjacking each get an icon and combine into one route.
*   **Gather Tally:** a live window tallying what you gather on a run, with optional timers.
*   **TomTom hand-off:** if TomTom is installed its arrow follows your route (on by default when TomTom is present).
*   **Dungeon Nav (Xperimental):** waypoints to Season 2 Mythic+ entrances, with portal routing through Silvermoon for three of them.
*   **Skins:** six color skins (Crimson original, Ember, Bronze ledger, Midnight, Indigo slate, Parchment) that switch right away.
*   **Node sharing (off by default):** swap newly found nodes with other players running the addon.

### WoW: Forever

*   **Node Highlight:** the herb or ore the game has picked for your Interact key glows as you approach (green for herbs, orange for ore), and quest objects and chests glow too, in violet-blue. Nine looks: Fire, Beam, Pulse, Sparkle, Spotlight, Rune Circle, Storm Cloud, Target Lock, Halo and Rays. Only the one object in front of you glows - that's the game's limit - and it reaches about 15 yards.
*   **Live node scan (off by default) - not working right now:** it was built to find which of your saved herb and ore nodes are really there by asking the game's own minimap dots. Blizzard's November 2026 WoW Forever update stopped addons from reading those dots, so the scan can't see any live nodes. It stays in, with a note on the Live Nodes page, until a workaround is found. Live nodes no longer glow or pulse.
*   **Route from live nodes:** after a scan, a route through the live nodes, nearest first. This depends on the scan, so it's on hold with it.
*   **Sounds:** an optional sound when you get to a herb or ore (once its glow is fully up) and another when you finish a route. Each can be switched off and set to any of about twenty of the game's own sounds on the Waypoint page.
*   **Built-in Classic nodes:** about 22,600 herb and ore nodes across 46 Classic zones are added the first time you log in on Forever. They never replace or remove your own.

## Settings

Open them with `/xxr options`, the minimap button, or Escape -> Options -> AddOns -> Xal's Xpedited Routes. The window has a sidebar with these pages:

*   **General** - the skin, minimap button, Lumberjacking (Retail), auto-advance distance
*   **Floating** - the helper button
*   **Waypoint** - compass arrow style, scale, progress coloring, trail line, the arrival and finish sounds
*   **Map Markers** - switches to show or hide the markers on the minimap and on the world map, marker style, size, opacity, glow, the distance at which markers hide when you're close (15 yards by default; on Forever they dim there instead of disappearing)
*   **Gather Tally** - the live window and timers, the dungeon button
*   **Node Highlight** (Forever) - on/off, quest and chest glows, look, range
*   **Live Nodes** (Forever) - the scanner, its key, timer and distance, and what it shows
*   **Database** - stats, duplicate distance, node freshness, sharing, duplicate cleanup
*   **Integrations** - TomTom

Route start, stop and skip, and "Scan for live nodes", can also be bound to keys at Escape -> Options -> Key Bindings -> AddOns -> Xal's Xpedited Routes. The scan key can be set right on the Live Nodes page.

## Live node scan (Forever)

**Not working right now.** Blizzard's November 2026 WoW Forever update (build 70862) means the game only names a minimap dot while the real mouse cursor is over it, and a scan that moves the minimap under the cursor no longer gets an answer. The scan stays in, and says so, until a workaround is found. The rest of this section describes how it was built to work.

The game never tells an addon where its Find Herbs / Find Minerals dots are, but it does name the dot under the real mouse. A scan slides your minimap under the mouse so each saved node's spot lands under it, one spot at a time, and reads the name the game gives back. Because it only checks the spots where you have saved nodes, it's short. While it runs the minimap is blank for a moment and the buttons on it can't be clicked; combat, a mouse press or a zone change cancels it and puts everything back at once. If the mouse is over a window the scan waits for you to move it onto the world (the Scan now button hides the settings window for you). Turn on Find Herbs or Find Minerals first.

## Floating helper button

Recording new gathers is always on, no matter what this button is doing; it only controls navigation. It adapts to your character: one icon per gathering type you can use, each drawn in your chosen marker style. Click an icon to start or update a route with that type, click a lit icon to remove it, light several for one combined route. A route built from live nodes isn't "on" for any type, so clicking an icon starts a normal route. Drag it anywhere; `/xxr button` shows or hides it and `/xxr button reset` puts it back.

## Compass

Drag it with Left-Click, right-click to skip the current node. When you get within your auto-advance distance (50 yards by default, adjustable to 150) it moves to the next node. Pick an arrow style and scale in the settings; the arrow turns green while you're closing in and red when you drift away.

## Duplicates and freshness

*   **Duplicate distance** (default 5 yards, 5-50): how close two saved nodes of the same kind (ore, herb or lumber) must be to count as the same one. **Cleanup Duplicates** merges nodes already saved closer than that.
*   **Node freshness** (off by default, up to 60 minutes): skips nodes you gathered recently when building a route, since they probably haven't respawned.

Resetting saved nodes isn't offered any more: the live node features rely on your saved nodes.

## TomTom hand-off

If TomTom is installed, its crazy arrow follows your route stop by stop. TomTom's arrow tracks one active waypoint, so Routes keeps re-pointing it at the stop it currently considers next. Dungeon Nav waypoints use TomTom the same way and clear on arrival. Turn it off in Settings -> Integrations.

## Chat commands

Use `/xxr` or `/xalmoras`:

*   `/xxr` - show or hide the gathering markers
*   `/xxr route`, `/xxr route stop`, `/xxr route skip`
*   `/xxr haul` - open the Gather Tally
*   `/xxr scan` - run a live node scan (Forever; not working right now, see above); `/xxr scan debug` prints what each check found
*   `/xxr sound` - play the arrival and finish sounds and show what each is set to
*   `/xxr share` - show node sharing status
*   `/xxr dungeon` - waypoint a Season 2 Mythic+ dungeon entrance
*   `/xxr stats`, `/xxr cleanup`
*   `/xxr options` (also `config`, `settings`), `/xxr button`, `/xxr button reset`
*   Marker and arrow tuning: `pinstyle`, `pinsize`, `pinalpha`, `glow`, `proximity`, `dupdistance`, `freshness`, `arrowstyle`, `arrowscale`, `arrowprogress`
*   `/xxr help` - the full list

## License

All Rights Reserved. The addon code and custom art are covered by the first section of [LICENSE.md](LICENSE.md), which also lists the parts that carry their own terms (bundled fonts and libraries).

## Installation

1.  Download or clone the repository.
2.  Copy the folder into your World of Warcraft addons directory (`...\_retail_\Interface\AddOns\`, `_forever_`, `_classic_` or `_classic_era_` as appropriate).
3.  Make sure the folder is named exactly `XalsXpeditedRoutes`.
4.  After installing or updating, fully restart the game so the client registers any changed files listed in the `.toc`.

## Structure

Modules load in this order (see the `.toc` files):

*   `Bootstrap.lua` - namespace; `BrandStyle.lua` and `XalsSkins.lua` - colors, widgets and the shared skins; `WhatsNew.lua` - the once-per-update splash
*   `Helpers.lua`, `Engine.lua` - safe API wrappers, startup, saved settings; `API.lua` - the public node-import API used by Xal's Routes Data
*   `NodeLogger.lua` - recording and position fine-tuning; `PathPlanner.lua` - routes, including routes from live nodes
*   `Sounds.lua` - the arrival and finish sounds
*   `Beacon.lua`, `DungeonBeacon.lua` - the two compasses; `MarkerRenderer.lua`, `Markers.lua` - marker drawing, pooling and the live look
*   `QuickButton.lua`, `TomTomBridge.lua`, `SettingsPanel.lua`, `RunTracker.lua`, `DungeonNav.lua`, `MinimapButton.lua`
*   Forever only: `NodeHighlight.lua`, `ForeverNodeData.lua` and `ForeverImport.lua` (the built-in nodes), `LiveScan.lua`
*   `Sync.lua` - node sharing; `ChatCommands.lua` - slash commands

## HereBeDragons dependency

This addon bundles `LibStub`, `CallbackHandler-1.0`, `LibDataBroker-1.1` and `LibDBIcon-1.0` but **not HereBeDragons**, which is large and map-data-heavy and best kept up to date on its own.

*   **Without it:** recording, routing, the compass and the helper button work; distances fall back to an approximation; map and minimap pins are not drawn.
*   **With it:** pins on both maps and more accurate distances everywhere.

No configuration needed - it's detected automatically.

## Credits

*   **The idea:** combining node tracking and route optimization in one addon.
*   **Conceptual inspiration:** GatherMate2 and Gatherer (node recording) and Routes (route optimization). No code, data or assets from them are used here.
*   **LibStub**, **CallbackHandler-1.0**, **LibDataBroker-1.1**, **LibDBIcon-1.0** - bundled utility libraries. **HereBeDragons** by Nevcairiel - optional, not bundled.
*   Maintained by **XalaMental**.
