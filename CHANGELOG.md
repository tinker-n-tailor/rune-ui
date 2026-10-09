# Changelog

All changes to Rune UI, newest first.

## [Unreleased]

## [1.11] - 2026-10-10

### Added

- A one-time notice after a fresh install: F9 moves, resizes and hides the HUD.
- A sun and moon icon for the day and night dial.

### Changed

- The mod is much lighter, and the hitches are gone.
- After a fresh install, the combat key hints and the tool wheel hint of the game show.
- Clearer names for some settings.

### Removed

- Support for an old UE4SS. The mod needs the UE4SS experimental build.

### Fixed

- A long item name in the tool wheel goes to a second line.
- In immersive mode, the ring of a need that is at 0 now shows.
- Small fixes.

## [1.10] - 2026-10-08

### Added

- Redesign of the spell, quick access and emote wheels.
- Rune Skin panel on F5: one switch for each redesigned part.

### Changed

- Redesign of the notices.
- Redesign of the death screen.
- The F9 list is shorter and sorted into groups.
- Immersive mode moved to the F6 panel, now named Immersion mode.
- The immersive camera works with or without the immersive mode.
- In immersive mode, a survival ring shows only when its need is critical.

## [1.9.2] - 2026-10-07

### Added

- Map setting "Drawing: Fastest".

### Changed

- RuneMap is more responsive with ore, herbs and other resources.

### Fixed

- The FPS no longer drops over time with RuneMap on.

## [1.9.1] - 2026-10-06

### Changed

- The tool bar now sits in the bag while the bag is open, also with a mouse and keyboard.

### Fixed

- In the immersive mode, a hidden bar no longer shows gold dust when it fills.
- The camera no longer turns round and round when a locked-on enemy comes very close: the lock-on view is the game's own again.
- The name of an enemy shows above its health bar again.
- The quest tracker, the party panel and the spell cooldown tiles now try again after a failed start.
- The marks on the compass now show also when the game starts from another folder.
- The Profile row in Mod Menu no longer changes the profile on a value that is not 1, 2 or 3.

## [1.9] - 2026-10-06

1.9 holds everything that 1.8 was to bring, and it adds a panel for the health of your friends. It also adds an immersive camera, new enemy health bars and clearer combat text.

### Added

- Immersive camera, off at first: in the immersive mode the camera sits closer, with your character on the left.
- Camera settings panel on F6.
- New setting "Crosshair in immersive mode", at Show at first, can hide the dot of the game's crosshair in the immersive mode, except while you aim.
- Enemy health bars have the look of your own bars: one colour, with the same texture.
- The boss bar is one colour too.
- Combat text: the damage numbers over enemies are white, bigger and in the HUD font, and a critical hit is gold with a pop.
- The status words (Poison, Burning, Bleed, Slowed, Immune) are in the HUD font, each in its own colour.
- The numbers for mining and cutting trees no longer have a band behind them.
- New editor element "Status notices (cosy, sheltered)": move, size and hide the notice for coming home or standing under a roof.
- Three new rows in the editor: "Other big notices", "Hunger, thirst and rest warning" and "Tutorial tips".
- The editor shows the notice of the selected row at its place, with a sample text.
- New map setting "Player name" (F8) hides your own name on RuneMap and the big map (M), from an idea and first code by Taylor Powell (tcpowell).
- New switch "Spell cooldowns: horizontal" in the editor (F9) puts the spell cooldown tiles in a row.
- Party panel: the health of your friends shows at the top left, under your bars, when you play with friends.

### Changed

- The editor (F9), map settings (F8) and camera settings (F6) panels now name the keys of the other panels at the top right.
- The spell cooldown tiles start lower on the left, to make room for the party panel.
- The licence now says how to send a change by pull request, and that a fork may not be published as a mod.

### Fixed

- Slim level up: the row for a finished level up no longer comes back under the bars after you open and close F9.
- Slim level up: the row now changes size softly, not in one jump, when a level up comes over an XP notice and when the XP notice returns.
- The editor panel (F9) no longer moves up and down while you go through the list.
- The pictures now load on computers where they did not, for example after an install with Vortex, and a lower case scripts folder works.

## [1.7] - 2026-10-04

1.7 adds a quest tracker, a slim level up under the bars and a gold compass. It also lets you pick what stays for direction in the immersive mode.

### Added

- Quest tracker under the minimap at the top right, showing the main quest and the quest that you track in the journal.
- Slim level up: a new level shows under the bars, in place of the game's big banner in the middle of the screen.
- "Show next steps" switch for the quest tracker: it shows up to three steps after the current one.
- New map setting "In immersive mode" (F8) picks what stays in the immersive mode: Nothing, Map or Compass.
- Compass, gold style: the game's compass gets the gold of the mod.
- Compass marks: while the map is hidden, the compass shows the creatures, ore, herbs, rune essence and rare trees switched on in the map settings (F8).

### Changed

- Map settings (F8): a row with more than two values shows its value between < and >.
- Immersive mode: stamina that is not full no longer brings the bars back.
- Immersive mode: a debuff shows for as long as it lasts, and a good buff (Cosiness, Sheltered, Well Rested, Prayer) shows when you get it, then fades.
- The time of day icon of the immersive mode is off and gone from the editor list.
- New licence: still free to use and open to read, but reuploads, published changed versions and reuse in other mods need permission; versions 1.0 to 1.6 stay MIT.

### Fixed

- The compass no longer loses its strip with the letters when it is hidden at the start of a world and shown later.
- A thin pale line no longer shows in the buff row between two buffs after one ends.
- A buff without a timer, for example the weight icon after a death, no longer stays in the buff row after it ends.

## [1.6] - 2026-10-03

### Added

- Rune XP: the XP that you get shows under the bars, with the icon and the name of the skill.

### Changed

- Elements in the editor have clearer names, for example "Menu shortcuts", "Picked-up items", "Interaction prompts", "Arrow and rune count", "XP circle" and "Minimap (RuneMap)".

### Fixed

- A gamepad moves between the bag and the tool bar again.
- The menu buttons (chat, map, spell book, building, bag) now show the gamepad buttons, not the keyboard keys, when you play with a gamepad.
- The bright edge of the tool bar now stays on the slot of the item in your hand when you change the item with a key or the tool wheel.
- The gold edges of the tool bar slots no longer stay on the screen while the tool wheel is open.
- In the editor, the gold edges of the tool bar slots now dim with the tool bar.

## [1.5] - 2026-10-03

1.5 is a big patch of the HUD look: the item pick-ups, the quests, the tool bar, the buffs, the farm plots and RuneMap. It also adds a page in Mod Menu and two new elements in the editor.

### Added

- Rune UI has a page in Mod Menu, for players who have it: press Esc, then MODS.
- The tool bar has the look of the cooldown tiles: see-through slots with a thin gold edge.
- Food and potion buffs are rings like the drink buff: green for a food, gold for a potion.
- In the editor, "Drink buff" is now "Drink, food and potion buffs" and moves all of them.
- New editor element "Item pick-ups": move, resize or hide the list of picked-up items on its own, apart from "Notifications".
- The rows of the pick-up list have the look of the HUD: no dark band, no gold lines, the HUD font and the count in gold.
- The row of a new item has the look of the other rows with no sparks, and "NEW MATERIAL !" is light from the start and does not blink.
- The quests and unlocks have the HUD font, with a shadow on the letters, as the item pick-ups.
- The farm plots: the water and compost icons over a plot are half their size.
- The clearing panel of a farm plot has no dark band or frame, a smaller title with a shadow, and a brown bar in place of the red one.
- New editor element "Death screen": move it or make it smaller.

### Fixed

- The editor panel and the map settings panel now show the keys that you set in `runeui.txt`.
- The lock-on diamond now sits in the middle of the staff's target mark, not a few pixels right and below.
- The sample tiles of the spell cooldowns no longer show while the map settings (F8) are open.
- A buff that ended, such as poison, no longer stays on the screen with an empty bar.
- The drink, food and potion buffs are no longer cut at the edge of their lists when you move them far from the food, water and rest rings.
- A claimed bed roll now shows its name with a space: "Ann's Bed Roll", and a bed shows "Ann's Bed".
- The F9 and F8 panel no longer stays empty after an error, and `UE4SS.log` shows each different error once in each world.

### Changed

- The frame of "Quests" in the editor now has the width of the panel, 440, not 240.
- The quests and unlocks now stay at the right edge, at the size of the game, and "Quests" in the editor moves only up and down.
- The line under the bars is now the pointed gold line of the loading screen, and the `[menuart]` part of `runeui.txt` is no longer used.
- Buffs are no longer rings: each buff is its icon with a thin bar under it that shows the time that is left.
- RuneMap: the rare trees are now a violet triangle, not a gold one.
- RuneMap: the time of day is now a gold arrow between the two gold rings.
- RuneMap: the north mark is a bigger gold arrow with the N cut into it, and the three diamonds on the ring are a little bigger.
- The mod no longer searches all widgets of the game every 10 seconds, which caused a hitch even when you stood still.
- With an older UE4SS ("timed search" in the log), the search after you enter a world or respawn now stops when all HUD parts are found.

## [1.4] - 2026-10-01

1.4 is the first release since 1.2 and also holds everything in 1.3. Its own changes are one settings file, keys that you can change and an error line in the panels.

### Added

- One settings file, `runeui.txt`, next to the game, with named values you can read and edit; older settings files are read once.
- Five keys can be changed in the `[keys]` part of `runeui.txt`: F9, F8, F7, ] and [.
- When a part of the mod fails, the F9 and F8 panel shows a line with its name and points at `UE4SS.log`.

## [1.3] - released as part of 1.4

### Added

- A new F9 editor in the look of the game's bag panel, with a small map of the screen and a list that groups the parts by area.
- A gold diamond marks a part that you moved, resized or faded, and X and Y show next to the size and the opacity.
- Gold corners and a dark tag with the name, X and Y mark the selected part, in place of the pale gold box and the blink.
- The panel stays on one side of the screen and moves only when it would cover the selected part.
- Hold an arrow key to keep moving a part.
- Three layout profiles: while F9 is open, F7 saves the profile and goes to the next one.
- A time of day icon right of the tool bar in the immersive mode: a sun by day, half a sun at dawn and dusk, the moon at night.
- The staff's ring around a target is now a gold diamond, every time.
- The rune and arrow count is a small dark disk with a gold rim, with the game's icon inside and the count in white right of it.
- A rune icon has the colour of its rune: red for fire, blue for water, white for air, brown for earth.
- The name of the ammo shows left of the count: for runes for 4 seconds after you change the ammo, for arrows all the time.
- The drink buff is a blue ring, the same size as the other buff rings and level with the food, water and rest rings.

### Changed

- The pick-up prompt, the build panel and the repair mode have white words with a shadow on the letters, in place of the gold words of 1.2.
- The faint dark shape behind the title of the build panel is gone.
- The keys under the menu buttons are white.
- F8, the map settings, uses the new panel.
- The overeating icon is in the middle of its ring.

## [1.2] - 2026-09-30

1.2 is the first release since 1.0.1. It also holds everything in 1.1, which was not released on its own.

### Added

- Wide screens: on 21:9 and wider screens, every part of the HUD stays in its place.
- The HUD scale of the game: every part keeps its place when you change the HUD scale in the game's settings.
- A layout keeps its shape on a screen of another shape, and each part follows the screen edge that it is nearest to.
- Gold aim marks for the bow, the staff and the lock-on, which "Gold aim and lock-on" in F9 switches off.
- A gold diamond replaces the lock-on orb.
- Spell cooldowns: while a spell recovers, a see-through tile shows its icon, a rising gold fill and the seconds that are left.
- Immersive mode, switched on in F9 with "Immersive mode (fades when idle)": the HUD fades when nothing goes on, and each part returns when it matters.
- Ore, herbs, rune essence and rare trees on RuneMap, each with its own shape.
- The menu buttons (chat, map, spell book, building, bag) are rings in the style of the food, water and rest rings, with the key under each one.
- The bag's ring fills with the weight of your bag and turns red when the bag is almost full.
- Gold letters on the pick-up prompt: the name of the thing in front of you and the action, for example "Collect".

### Changed

- Buffs are rings, like the food, water and rest rings, in the colour of the buff.
- The bars have one colour each and a stronger texture.
- The dark shadow behind the bars is gone.
- The health bar shows no numbers.
- Each step of the mod takes less time: 0.6 ms on average, down from 0.9 ms.
- Creatures on RuneMap: the mod looks for creatures only around you, and not at all when Creatures is off.
- The Creatures switch in F8 has three steps: all, enemies only (the new default) and off.

### Fixed

- RuneMap no longer gets slower each time you open the big map (M).
- A small hitch every 2 seconds is gone, because the mod now searches for the parts of the HUD much less often.
- On a wide screen, the level badge and the line under the bars are no longer far away from the bars.

A layout that you made on a wide screen with an older version can move a little once. Correct it in F9.

## [1.1] - released as part of 1.2

### Added

- F8 opens the RuneMap settings in a panel under the map: "Faces north", "North mark", "Creatures", "Zoom" and "Drawing".
- Opacity for each element in F9, in steps of 10% from 100% to 20%, set with comma and period.

### Changed

- The F9 and F8 panels have a dark background with a double gold line, like the inventory of the game.
- The key list of F9 shows F8, and F9 and F8 each open the other panel.
- While F8 is open, RuneMap shows, also when it is hidden in F9.

## [1.0.1] - 2026-09-28

- Fixed heavy stutter, worst on older UE4SS builds.
- Fixed crashes after using the F9 editor for a while.
- Hiding RuneMap now also hides its gold rings, and gives back the FPS the map costs.
- RuneMap now draws every second frame, for about 10 FPS more.
- If UE4SS.log says "timer: old UE4SS", update UE4SS to the latest experimental build.

## [1.0] - 2026-09-28

The first release.

- F9 opens an editor that moves, resizes and hides 27 parts of the HUD and saves the layout.
- RuneMap: a round minimap that turns with the camera, with a gold ring that is also a clock and diamonds for enemies and animals.
- Food, water and rest: three rings in the style of the map that turn orange and red when a value is low.
- Clean bars: health on top, stamina in green, and a plain dark track behind each bar.
- Round buffs: a ring of dashes shows the time that is left, in the colour of the buff.
- Ammo counter: the rune and arrow count of the staff and the bow moves away from the crosshair.
