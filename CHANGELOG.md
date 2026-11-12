# Xal's Xpedited Routes - Changelog

## 2.7.3 - November 12, 2026

---

A clean-up release after the last one. Out in the field I found the live scan still lighting up nodes that weren't there, so a scan that finds nothing now actually clears them, and a node you walk up to without gathering turns itself off. The map was also still showing herb and ore markers on characters with no gathering skills, which was a real bug and is fixed. And since I was in the settings anyway, the arrow picker now shows you the arrows instead of just their names, with a new orange arrow in place of the old top-down one. Thanks for being part of the Xal family - hope it makes your farming a lot easier.

### 🔧 Fixed
- **Markers on characters with no gathering skills** - a character with no Mining or Herbalism now sees no herb or ore markers.
- **Glow that wouldn't go away (Forever)** - a scan that finds nothing live now clears the glow and removes those stops from your route, and a glowing node you stand at for a few seconds without gathering stops glowing.

### 🆕 New
- **Arrow previews** - the Arrow style picker shows each arrow, and the Topdown 2D Arrow is now a new orange arrowhead.
## 2.7.2 - November 11, 2026

---

Out on the road I kept getting to a node only to find someone had already picked it, and my live route still had it on the list. I wanted to be able to just hit the scan button again and have the route reaffirm itself, so now a second scan takes the stops that are gone out of your live route and moves the compass on if it was pointing at one. Thanks for being part of the Xal family - hope it makes your farming a lot easier.

### 🆕 New
- **Scan again to tidy your route** - a new scan removes stops ahead of you that it finds empty from a route built from live nodes. A route you plotted yourself is never changed.
## 2.7.1 - November 11, 2026

---

A small one right behind 2.7.0. While testing the live scan I realized the automatic scans could fire at the worst possible moment, right in the middle of a gather or a loot click, so they now wait until you're done casting, looting or hovering something. I also got tired of guessing why a scan wouldn't start, so the Live Nodes page now just tells you, and there's an optional scan right after a fight, a landing or a loading screen. Thanks for being part of the Xal family - hope it makes your farming a lot easier.

### 🆕 New
- **Scans wait for you** - automatic scans hold off while you're casting or gathering, aiming a spell, have a loot window open, or have something under your mouse. Scans you start yourself still run.
- **Why a scan won't start** - the Live Nodes page shows whether a scan can start right now and, if not, the reason.
- **Scan after you stop** - one scan after a fight, a landing or dismount, or a loading screen. Off by default.
## 2.7.0 - November 11, 2026

---

This is a big update, and most of it comes from one frustration: with so many people farming the same spots, I could never tell which of my saved nodes were actually still there. So on Forever there's now a live scan that makes the real ones pulse and can build you a route through them. Forever players also start with a full set of Classic nodes instead of an empty map, quest objects and chests glow like herbs and ore, there are three new glows (the storm cloud throwing lightning is my favorite), and I finally got out of my own dark, brooding styling: the settings now come in six skins. Thanks for being part of the Xal family - hope it makes your farming a lot easier.

### 🆕 New
- **Live node scan (Forever)** - finds which saved nodes are really there: live ones pulse yellow (rare ones violet), empty ones fade. Off by default; start it with a key, a timer, or every time you walk a set distance.
- **Route from live nodes** - after a scan, a route through the live nodes, nearest first. A route you already have is never replaced; new live nodes go on the end.
- **Built-in Classic nodes (Forever)** - about 22,000 herb and ore nodes added at first login, without touching your own.
- **Quest objects and chests glow (Forever)**, plus three new Node Highlight looks: Storm Cloud, Target Lock, and Halo and Rays.
- **Six skins** under General, switching right away, with new settings artwork.
- **Share nodes with other players** - off by default.
- **Steadier markers** - re-gathering a node nudges its marker onto the real spot.

### 🔧 Fixed
- Fixed the floating button's route icons misfiring when your character can't gather every type.
- Removed the database reset options; the live features rely on your saved nodes.
## 2.6.1 - November 6, 2026

---

A quick fix right after the last one. Once I got the Node Highlight into the game I found a beam of light showing up in every look instead of only in Beam, which made them all look the same. That's fixed, so Fire, Pulse, Sparkle, Spotlight and Rune Circle each look like themselves now. I also rebuilt Spotlight so it's a soft column of light pouring onto the ground instead of an oval outline, and Sparkle is now a bunch of separate twinkling sparkles instead of one big bright blob. Thanks for being part of the Xal family.

### 🔧 Fixed
- **Every Node Highlight look showed a beam of light** - the beam now only shows in the Beam look.
- **Spotlight look rebuilt** - it's now a soft column of light pouring down onto the ground, and the Pulse look's inner glow is softer.
- **Sparkle look was one big bright blob** - it now shows separate twinkling sparkles around the node.

## 2.6.0 - November 6, 2026

---

This is the start of merging my addons into Forever, after a short break because I was sick, and I'm glad to be back at it. Routes is the first one set up for Forever, so it won't show up as out of date there. I also saw how a couple of the new Forever addons make herbs and ore glow as you walk up to them, and I decided Routes should do that too. So there's a new Node Highlight: the herb or ore the game has picked for your Interact key lights up with fire by default - green for herbs, orange for ore - or with a beam, a pulsing dome, sparkles, a spotlight or a rune circle if you'd rather. It's on by default and reaches as far as the game allows, about 15 yards, and your own interact settings go back when you turn it off or log out. The settings got a cleanup too: Node Highlight has its own page, the Gather Tally switch moved to the Gather Tally page so it's in one place, and the sidebar text is lighter so it's easier to read. Thanks for being part of the Xal family - go find some herbs.

### 🆕 New
- **Node highlight (WoW: Forever)** - the herb or ore in front of you glows as you approach, as fire by default, or as a beam of light, ripples, sparkles, a spotlight or a rune circle. It's on by default. The new Node Highlight settings page lets you turn it off, pick the look, and set how far away it glows (up to 15 yards, the farthest the game will pick a node).
- **Easier-to-read settings sidebar** - the sidebar text in the settings window is lighter.
- **Gather Tally switch moved** - the on/off switch for the live Gather Tally window now sits on the Gather Tally page instead of General.
- **WoW: Forever support** - Routes now lists Forever as a supported version.

## 2.5.0 - October 23, 2026

---

Routes got a big refresh this time. The whole addon now shares the look of the rest of my addons - new fonts, new settings pages, and a settings window that scrolls so nothing gets cut off. The Gather Tally and the compass got most of the attention on the working side. The tally now counts herbs and ore from older expansions on Retail, which it had been missing, and it works on Classic Era, where the game files herbs and ore differently than everywhere else. Then a Classic player told me the compass was pointing the wrong way with certain other addons installed, so the compass and the dungeon arrow now work out distance and direction from the game's own map data instead of relying on a shared library that another addon can break. Thank you to everyone who keeps reporting these - I can't test every version of the game myself, and your reports are how it keeps getting better.

### 🆕 New
- **New fonts and settings layout** - titles use Cinzel Bold and text uses Inter, and every settings page has titled sections with divider lines and the new checkboxes and sliders.
- **Scrolling settings pages** - tall settings pages now scroll with the mouse wheel instead of getting cut off, in both the floating settings window and the Esc menu's options list.

### 🔧 Fixed
- **Gather Tally missed herbs from older expansions on Retail** - Dragonflight herbs and their bonus drops now count.
- **Gather Tally didn't count anything on Classic Era** - herbs and ore are now recognized there.
- **The compass and dungeon arrow could point the wrong way or show the wrong distance when other addons were installed** - they now use the game's own map data.

## 2.4.5 - September 30, 2026

---

Had a player on Classic Hardcore flag that things weren't working right - digging in, they were right. I'd missed some major pieces when I pushed Classic support out, and the Gather Tally wasn't counting anything you actually picked up. Should be fixed now. Really appreciate the report - that's exactly the kind of thing that's easy to miss without someone actually playing it.

### 🔧 Fixed
- **Gather Tally wasn't counting anything on Classic (Era or MoP)** - nodes still recorded fine, but items you picked up never showed up in the tally.
- **The gathering compass could point the wrong direction, or show a distance that didn't count down right** on certain zones - sometimes pointing far off toward nothing at all.

## 2.4.0 - September 30, 2026

---

Brought Routes into the current family look - the same dark, clean style the rest of my addons have been moving to. Also decided it was finally time to drop Classic entirely; Compact's been the better version this whole time, and keeping two styles around was just extra weight for no real benefit. Nothing you actually use is going anywhere - every feature's still here, just wearing the new look.

### 🆕 New
- **Full visual refresh** - every title, header, divider, button, and slider across the whole addon now uses one consistent dark red accent, no more orange or gold anywhere.
- **Discord link moved to the Settings sidebar** - a small logo link at the bottom of the Settings window's sidebar, replacing the text link that used to sit on the General page.

### 🔧 Fixed
- **Classic style removed** - the older alternate look for the floating helper and Gather Tally is gone. Compact (the default since 2.2.0) is now the only style - nothing to pick between anymore, and every feature that was in Classic still works the same way in Compact.

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
