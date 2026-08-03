# Xal's Xpedited Routes

**Xal's Xpedited Routes** is a lightweight, modern World of Warcraft addon (fully ready for Midnight/TWW) that automatically records and displays mining veins and herbalism nodes you gather with your character on both the minimap and the world map, building a personal, local database.

Additionally, it features an intelligent navigation system that guides you through the optimal gathering route in your current zone.

> The idea behind this addon: combine gathering-node tracking and route optimization - concepts pioneered separately by GatherMate2/Gatherer (node recording) and Routes (route optimization) - into a single, beneficial tool instead of requiring multiple separate addons.

## Requirements

**Requires [HereBeDragons](https://www.curseforge.com/wow/addons/herebedragons) for minimap and world map markers to show at all** - not bundled, install it separately. Without it, recording, routing, the compass, and the floating helper button all still work fine, but no pins will be drawn on either map. See "HereBeDragons Dependency" further down for the full breakdown of what does and doesn't need it.

No other dependencies. [TomTom](https://www.curseforge.com/wow/addons/tomtom) is fully optional and only adds the automatic route hand-off described below.

## Key Features

*   **Automatic Recording:** Listens to your gathering spells cast in real-time and saves the exact coordinates.
*   **Local Database:** Data is stored in your personal `SavedVariables`, ensuring that your gathering database remains private and persistent.
*   **False Nodes Filtering:** Automatically excludes corpse-based herbalism (such as those in Midnight) to avoid registering invalid coordinates.
*   **Duplicate Cleanup:** Built-in algorithm to automatically detect and remove duplicate or extremely close node records.
*   **Route Optimization:** Builds an initial path with a greedy nearest-neighbor approach, then improves it with a 2-opt pass that un-crosses and shortens the route further, using real distances in yards when HereBeDragons is installed (an approximation otherwise).
*   **HUD Compass:** A floating, dynamic arrow that rotates based on the direction your character is facing and shows the exact distance to the next node.
*   **Simple Map Markers:** A hollow X (default) or hollow star, green for Herbalism and red for Mining, with a small dot marking your active route target. Fully hides itself once you're close to a node, since the real node model in the world is what matters at that range.
*   **In-Game Settings Panel:** No need to memorize chat commands — split into three sections (General, Map Markers, Database) instead of one long page.
*   **Floating Helper Button:** A small draggable button (like a minimap button) that generates or stops a route for your current zone in a single click — no chat commands required.
*   **Independent Mine/Herb Route Control on the Floater:** A dual-gathering character gets two buttons — click either to route just that type, click both to merge into one combined route. Recording new gathers happens unconditionally regardless of these buttons.
*   **TomTom Hand-off (optional, off by default):** Turn it on and, if TomTom is installed, its crazy arrow automatically follows your route stop by stop — no popup, no copy/paste, nothing to click.

## Settings Panel

Open it any of these ways:
*   `Escape` -> **Options** -> **AddOns** -> **Xal's Xpedited Routes**
*   `/xxr options` (or `/xxr config`)

It's split into five sections (shown as sub-items under Xal's Xpedited Routes in the AddOns category list) rather than one long page:

*   **General** — show/hide the floating helper button (+ reset its position), auto-advance distance
*   **Waypoint** — compass arrow style, arrow scale, progress coloring
*   **Map Markers** — marker style, size, opacity, glow, proximity hide distance
*   **Database** — stats, duplicate detection distance, cleanup/reset
*   **Integrations** — optional hand-offs to other addons (currently just TomTom); home for any future ones too

Route control itself (Generate/Stop/Skip) doesn't have its own settings page — that's what the floating helper button is for. `/xxr route`, `/xxr route stop`, and `/xxr route skip` still work from chat if you'd rather not use the floater. All three can also be bound to a real key — click the keybind buttons in Settings -> General, or set them the usual way at Escape -> Options -> Key Bindings -> AddOns -> Xal's Xpedited Routes (both stay in sync, since they're the same underlying binding). Unbound by default.

## Floating Helper Button

**Recording new gathers is always on, unconditionally, no matter what this button is doing.** The moment you successfully gather a mining or herb node, it's saved - that has nothing to do with this button or with routing at all. This button only controls navigation: which nodes you're actively being routed to.

A small draggable control, on by default, that puts route control one click away — and it adapts to what your current character can actually gather:

*   **Knows both Mining and Herbalism:** two buttons stacked vertically, Mine on top and Herb below.
*   **Knows only one:** a single button for that profession.
*   **Knows neither:** a single greyed placeholder with nothing to click (tooltip explains why).

Each button is drawn using whatever **Map Marker Style** you've selected in Settings — same shape, same green/red color logic — just larger, so the floater always visually matches your map pins instead of being a generic shape of its own.

*   **Click a button:** Starts (or updates) a route including that node type — the HUD compass appears, and if TomTom is installed, its crazy arrow follows along automatically. If both Mine and Herb are on, it's one combined route through everything this character can gather. If only one is on, the route is restricted to just that type.
*   **Click an already-on button again:** Removes that type from the route. If that was the only type included, the route stops entirely (compass disappears).
*   Whichever type(s) are currently included in the active route get a small dot marked at their center, matching how the map highlights your active target. A small number under each button shows how many of that node type are saved in your current zone.

The whole thing can be dragged from anywhere on it (buttons included) — position is saved. Show/hide the button itself from the Settings panel or with `/xxr button`. Reset its position with `/xxr button reset` or the Settings panel.

Profession detection is checked a few times right after login until it gets a confirmed answer, then it stops re-checking for the rest of the session (see "Markers/Routes Automatically Match Your Professions" below for why). If you train a new gathering profession mid-session, `/reload` to have the floater pick it up - it won't add the second button automatically without one.

## HUD Compass Interaction

*   **Move the HUD:** Hold **Left-Click** on the compass and drag it anywhere on your screen. Its position will be saved automatically for future sessions.
*   **Skip Node:** **Right-Click** on the compass to skip the current node and immediately point to the next one.
*   **Auto-Advance:** When you get within your configured distance (30 yards by default) of your current target node, the compass will automatically advance to the next node in the route.
*   **Arrow style:** Two custom arrows are bundled (`RoutesArrow.tga` - "Chevron", a chunky glossy 3D-style arrow, and the default; and `Arrow3.tga` - "Topdown 2D Arrow", plain white/gray), plus the original Blizzard arrow as a fallback option. Pick one in Settings → General → Compass Arrow, or with `/xxr arrowstyle <custom3|custom4|blizzard>`.
*   **Progress coloring:** The arrow turns **green** when your distance to the target is shrinking (checked every 0.5s, with a small deadband so it doesn't flicker on minor jitter) and **red** when it's growing, i.e. you've wandered off course. Toggle it in Settings → General or with `/xxr arrowprogress`. This works best with plain/light-colored arrow art — tinting already-colorful art can look muddy, since the tint multiplies the existing colors rather than replacing them.

Want different custom arrow art? Send it over (same spec as the marker icons: square-ish, transparent background, drawn pointing straight up) and it can be swapped into `Textures\RoutesArrow.tga` or `Textures\Arrow3.tga` the same way these were. If you want the green/red progress coloring to read cleanly, ask for the art in mostly white/light gray rather than richly colored — that's exactly what `Arrow3.tga` is.

## Map Marker Style

Node markers are plain colored outlines, not icon art — icon-based styles were tried and dropped, they didn't read well in practice. Two options, from the Settings panel's **Map Markers** section:

1. Hollow X *(default)*
2. Hollow star

Both use color coding: green = Herbalism, red = Mining. Your active route target doesn't change color or shape — it just gets a small dot marked at its center, so it's still clearly "this one" without needing a whole separate color scheme.

The X is built as a single continuous 12-point outline (a plus-sign shape rotated 45 degrees), not two crossing bars — that avoids a box-shaped artifact where the arms would otherwise overlap. Both shapes are made of straight lines only (rotated rectangle textures), which is why neither is a circle: WoW addons can't draw true curves, and a circle approximated with too few straight segments just looks like a lumpy polygon instead of a circle.

You can also set your style from chat with `/xxr pinstyle <name>` - `hollowx` or `star`.

### Marker size and opacity

A **Marker size** slider (8-28px) and a **Marker opacity** slider (30-100%) sit in Settings -> Map Markers, or set them from chat with `/xxr pinsize <8-28>` and `/xxr pinalpha <30-100>`. The active route target is always drawn about 40% larger than whatever size you pick.

### Glow

Every marker style can also get a soft colored glow behind it (green for Herbalism, red for Mining) so it stands out against busy terrain. **Off by default.** Toggle it in Settings -> Map Markers, or with `/xxr glow`.

### Hide markers when close

Once you're within a set distance of a node **on the minimap**, that marker disappears entirely - the actual node model in the game world is what matters at that range, not the addon's marker. **Always on** - this isn't a toggle, only the distance is adjustable.

Distance is measured as on-screen pixel distance on the minimap (marker position vs. minimap center), converted to real yards using the minimap's own *current* view radius (`C_Minimap.GetViewRadius()` - a Blizzard API that reports how many yards the minimap currently spans, live, accounting for zoom level and indoor/outdoor). This is deliberately not tied to HereBeDragons' distance calculations, which don't have calibration data for every zone (some newer/less common zones are missing it) - reading the minimap's own live view radius has no such gap.

Default hide distance is 200 yards (adjustable 20-500) in Settings -> Map Markers, or with `/xxr proximity <20-500>`.

This only applies to the minimap, not the world map - the zone you're viewing on the world map isn't necessarily the one you're standing in, so "distance to player" wouldn't mean anything there.

## Markers/Routes Automatically Match Your Professions

Since the node database is shared across your whole account, a character with only Herbalism would otherwise still see every Mining node another character on your account ever recorded. This addon automatically skips that: markers for a node type your current character can't gather are hidden on both maps, and route generation skips them too. There's nothing to turn on - it's just how it behaves.

This checks your character's actual known professions using WoW's profession-detection API, which needs the client to have loaded your profession data this session - that doesn't always happen right away on its own (often not until you've opened your Professions panel). Rather than leaving that to chance, the addon proactively nudges the client to load that data as soon as you log in, and re-checks a few times over the following half-minute and whenever WoW signals that skill/profession data has changed - so if the very first check happens to catch things too early, it corrects itself shortly after with no action needed from you. Once it gets a real, confirmed answer (not a guess), it stops checking entirely for the rest of the session - your professions aren't something that changes mid-session, so there's no reason to keep re-verifying something already known for certain.

## Duplicate Detection Distance

How close two saved nodes need to be before they're treated as "the same node" - used when recording a new gather and running Cleanup Duplicates. Distances are computed in actual yards via HereBeDragons when it's installed, rather than a raw fraction of the zone's coordinate space, which is why it could otherwise feel inconsistent - 1% of a zone's own coordinate space is a very different real distance in a small zone than a huge one. Default is 15 yards, adjustable 5-50 in Settings -> Database, or with `/xxr dupdistance <5-50>`.

If you were seeing "this node is already recorded" with no marker anywhere nearby, lowering this should fix it - then run Cleanup Duplicates (or `/xxr cleanup`) to reapply the new distance to nodes you've already saved.

## TomTom Hand-off (optional, off by default)

**Off by default.** Turn it on in Settings -> Integrations, or with `/xxr tomtom`. If [TomTom](https://www.curseforge.com/wow/addons/tomtom) is installed and this is switched on, its crazy arrow automatically follows your route, stop by stop, staying in sync as you advance through it - no popup, no copy/paste, nothing to click.

This works a specific way worth understanding: TomTom's crazy arrow is built around a single active target, not an internal list it steps through on its own (confirmed by reading TomTom's own source - its `SetCrazyArrow` function just replaces one active waypoint, it doesn't manage a queue). So rather than dumping the whole route into TomTom at once and hoping it sorts out the order, this addon keeps re-pointing TomTom's one active waypoint at whatever stop it currently considers "next" - updating it every time the route advances, the same moment its own compass does. The result looks and feels like TomTom is following your whole route, because it's being actively kept in sync with it the entire time.

This calls TomTom's real API (`AddWaypoint`/`RemoveWaypoint`) - a function it exposes specifically for other addons to use, the same category of thing as this addon calling HereBeDragons' API elsewhere. No code of TomTom's is used or bundled, just normal addon interoperability. It's still one-way: this addon only ever pushes to TomTom, it never reads anything back from it or reacts to its own state. If TomTom isn't installed, turning this on does nothing - no error, no popup, just a quiet no-op.

Turning it off (or stopping the route) clears the waypoint TomTom was given.

## Chat Commands

Use `/xxr` or `/xalmoras` in chat followed by an option:

*   `/xxr` (no arguments): Toggles the visibility of all gathering icons on the maps.
*   `/xxr route`: Generates and activates the gathering route for your current zone, showing the HUD compass on screen.
*   `/xxr route stop`: Stops the active route and hides the HUD compass.
*   `/xxr route skip`: Skips the current node in the route (equivalent to right-clicking the compass).
*   `/xxr stats`: Displays detailed statistics on the number of nodes saved in each map.
*   `/xxr cleanup`: Removes duplicate or extremely close nodes from the database to optimize performance.
*   `/xxr reset`: Deletes gathering records **only for the current map/zone**.
*   `/xxr reset all`: Deletes the **entire database** of the addon.
*   `/xxr pinstyle`: Lists the available map marker styles.
*   `/xxr pinstyle <name>`: Sets the map marker style (`hollowx` or `star`).
*   `/xxr pinsize <8-28>`: Sets the map marker size in pixels.
*   `/xxr pinalpha <30-100>`: Sets marker opacity as a percentage.
*   `/xxr glow`: Toggles the colored glow behind markers.
*   `/xxr proximity <20-500>`: Sets the distance (yards) at which markers hide when close - always on, this just sets the distance.
*   `/xxr dupdistance <5-50>`: Sets how close two nodes must be to count as the same one.
*   `/xxr arrowstyle <name>`: Sets the compass arrow style (`custom3`, `custom4`, `blizzard`).
*   `/xxr arrowprogress`: Toggles green/red arrow coloring based on whether you're closing in on the target.
*   `/xxr button`: Shows or hides the floating helper button.
*   `/xxr button reset`: Resets the helper button to its default position.
*   `/xxr options` (or `/xxr config` or `/xxr settings`): Opens the Settings panel.
*   `/xxr help`: Displays an interactive guide with the list of available commands in chat.

## License

The addon code is MIT-licensed - free to use, modify, and redistribute, with attribution. The custom art in `Textures/` is All Rights Reserved. See [LICENSE.md](LICENSE.md) for the full terms.

## Installation

1.  Download or clone the repository.
2.  Copy the folder into your World of Warcraft addons directory:
    `World of Warcraft\_retail_\Interface\AddOns\XalsXpeditedRoutes`
3.  Ensure the destination folder is named exactly `XalsXpeditedRoutes`.
4.  *Note*: After installing or updating, it's recommended to fully restart the game (or log out to the character selection screen) so the WoW client registers any changed files listed in the `.toc`.

## Modular Structure and Code

The addon is structured following the best WoW development practices, split into the following sequentially loaded modules:
*   `Bootstrap.lua`: Namespace initialization.
*   `Helpers.lua`: Safe and compatible wrappers for WoW API functions.
*   `Engine.lua`: Addon initialization, data persistence, and main event listening.
*   `NodeLogger.lua`: Recording and validation of gathering events.
*   `PathPlanner.lua`: Route construction (greedy nearest-first, then a 2-opt improvement pass) and route state.
*   `Beacon.lua`: Creation, animations, and behavior of the HUD compass.
*   `MarkerRenderer.lua`: Shared marker-shape drawing, used by both the map pins and the floating helper button.
*   `QuickButton.lua`: Floating draggable button for one-click route/unroute control.
*   `Markers.lua`: Pin pooling/placement on the minimap and world map via the optional `HereBeDragons-Pins-2.0` library, plus the proximity-hide.
*   `TomTomBridge.lua`: Keeps TomTom's crazy arrow synced to the current route stop via its API when TomTom is detected.
*   `SettingsPanel.lua`: In-game Settings panel.
*   `ChatCommands.lua`: Processing of console commands.

## HereBeDragons Dependency

This addon bundles `LibStub` and `CallbackHandler-1.0` (both public-domain/permissively-licensed libraries meant for embedding), but **does not bundle HereBeDragons** - that library is large and map-data-heavy, and is best kept up to date on its own. Install it separately.

*   **Without HereBeDragons installed:** recording, route generation, the compass, and the helper button all still work. Distance calculations fall back to an approximation within your current zone. **Map/minimap pins are not drawn at all** - there's no reliable fallback for pin placement without it.
*   **With HereBeDragons installed:** (search "HereBeDragons" by Nevcairiel on CurseForge/Wago) you get pins on the minimap/world map, plus more accurate cross-zone distances everywhere else.

No configuration needed either way - Xal's Xpedited Routes detects and uses it automatically if it's present.

## Credits

*   **The idea:** combining gathering-node tracking and route optimization into a single addon, in a way that's beneficial for the player - rather than requiring separate tools for recording and routing.
*   **Conceptual inspiration:** GatherMate2 (kagaro, xinhuan, Nevcairiel) and Gatherer established node recording/display years earlier, and Routes (Antiarc, Esamynn, currently Xurkon) established route optimization for gathering data specifically, including proper TSP-solver-based path planning. No code, data, or assets from any of them are used here; they're credited for pioneering the general concepts.
*   **LibStub** (public domain) and **CallbackHandler-1.0** (Ace3, permissively licensed for embedding) - bundled utility libraries.
*   **HereBeDragons** by Nevcairiel - optional external addon this one can use if installed; not bundled.
*   **Compass arrow artwork** - original art provided by the maintainer.
*   **Addon icon/logo** - original artwork provided by the maintainer.
*   **Xal's Xpedited Routes:** maintained by **XalaMental**.
