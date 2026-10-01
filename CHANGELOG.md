# Changelog

All changes to Rune UI, newest first.

## 1.4 (01-10-2026)

1.4 is the first release since 1.2. It also holds everything in 1.3, which was not released on its own. The changes of 1.4 itself are in how the mod is built, and in one settings file.

### New

- One settings file, `runeui.txt`, next to the game, with named values you can read and edit. It holds the three layout profiles, the profile in use, the map settings and the zoom, and the keys. The six files of older versions are read once when `runeui.txt` is missing, so no layout is lost. They are not deleted.
- Five keys can be changed in the `[keys]` part of `runeui.txt`: F9, F8, F7, ] and [.
- When a part of the mod fails, the F9 and F8 panel shows a line with its name and points at `UE4SS.log`.

### Changed

- The code is split into more files. `main.lua` had 2240 lines and was ten names short of a limit of Lua at which the mod would not load; it has about 1500 now. The bars, the level badge and the buff rings have their own files, like the other parts. The position math is in `layout.lua`, the settings file in `settings.lua`, and both have tests that run without the game.
- Every part is one line in a list. The step, the widget scan and the world reset go down that list.
- `npm test` runs every check: the Lua check, the picture check, the player README check, and the tests without the game. GitHub runs it on every push.
- The player README inside the zip is made from this repository's README, so the two cannot drift apart.

## 1.3 (released as part of 1.4)

### New

- A new F9 editor in the look of the game's bag panel. A small map of the screen shows where each part is, and the selected part is gold. The list groups the parts by the area of the screen. A gold diamond marks a part that you moved, resized or faded. X and Y show next to the size and the opacity.
- On the screen, gold corners and a dark tag with the name, X and Y mark the selected part. They replace the pale gold box and the blink.
- The panel stays on one side of the screen. It moves to the other side only when it would cover the selected part.
- Hold an arrow key to keep moving a part.
- Three layout profiles. While F9 is open, F7 saves the profile and goes to the next one. Profile 1 is your current layout. A profile that you open for the first time starts as a copy of the profile before it.
- A time of day icon right of the tool bar, while the immersive mode is on: half a sun that rises at dawn, the sun by day, half a sun that sets at dusk, and the moon at night. Move or hide it with "Time of day icon (immersive)" in F9.
- The staff's ring around a target is a gold diamond, every time.
- The rune and arrow count is a small dark disk with a gold rim. The game's rune or arrow icon fills the disk, and the count is right of it in white. The counter is one line as tall as the disk, so it can sit level with the tool bar. A rune icon has the colour of its rune: red for fire, blue for water, white for air, brown for earth.
- The name of the ammo is left of the count. For runes, it shows for 4 seconds after you change the ammo. For arrows, it stays, because all arrows have the same icon.
- The drink buff is a blue ring, the same size as the other buff rings and level with the food, water and rest rings. The ring shows the time that is left, without the number. Move, resize or hide it with "Drink buff" in F9. In the immersive mode, it shows when you drink, fades, and comes back when the drink runs low.

### Changed

- The pick-up prompt, the build panel and the repair mode have white words with a shadow on the letters. The gold words of 1.2 are gone, because gold was hard to read over grass and sky. The faint dark shape behind the title of the build panel is gone too.
- The keys under the menu buttons are white.
- F8, the map settings, uses the new panel.
- The overeating icon is in the middle of its ring.

## 1.2 (30-09-2026)

1.2 is the first release since 1.0.1. It also holds everything in 1.1, which was not released on its own.

### New

- Wide screens. On 21:9 and wider screens, every part of the HUD stays in its place. The level badge and the line under the bars stay with the bars. RuneMap stays in the top right corner. The food, water and rest rings, the tool bar and the compass stay in the middle.
- The HUD scale of the game. When you change the HUD scale in the game's settings, every part keeps its place.
- A layout keeps its shape on a screen of another shape. Each part follows the edge of the screen that it is nearest to. When you move a part in F9, it takes the edge that is nearest to its new place.
- Gold aim marks. The crosshair, the ring and the dot of the bow, the stamina bar of the bow, the ring around a staff target and the lock-on bracket are gold. A gold diamond replaces the lock-on orb. Switch "Gold aim and lock-on" off in F9 to get the white marks back.
- Spell cooldowns. While a spell recovers, a see-through tile shows its icon, a gold fill that rises from the bottom, and the seconds that are left. The newest tile is at the bottom. Move the tiles with "Spell cooldowns" in F9. While F9 is open, 3 sample tiles show. The immersive mode does not fade them.
- Immersive mode. When nothing goes on, the HUD fades away, and each part comes back when it matters: the bars when your health or stamina is not full, a food, water or rest ring when it runs low, the buffs when a new one comes, the menu buttons when a chat message comes. The tool bar and the prompts never fade. Switch "Immersive mode (fades when idle)" on in F9. On that line, + and - set how long a part stays, from 3 to 30 seconds.
- Ore, herbs, rune essence and rare trees on RuneMap, each with its own shape: ore a brown square, herbs a green triangle, essence a blue circle, rare trees a gold triangle. An empty rock or a picked plant hides until it grows back. F8 has a switch for each group.
- The menu buttons (chat, map, spell book, building, bag) are rings in the style of the food, water and rest rings, with the key in a small box under each one. The bag's ring fills with the weight of your bag, and turns red when the bag is almost full.
- Gold letters on the pick-up prompt. The name of the thing in front of you and the action, for example "Collect", are gold. The key stays as the game shows it.

### Changed

- Buffs are rings, like the food, water and rest rings, in the colour of the buff. There is room between two rings.
- The bars have one colour each and a stronger texture.
- The dark shadow behind the bars is gone.
- The health bar shows no numbers.
- Each step of the mod takes less time: 0.6 ms on average, down from 0.9 ms.
- Creatures on RuneMap: the mod looks for creatures only around you. When Creatures is off, the mod does not look for them at all. The Creatures switch in F8 has three steps: all, enemies only, and off. Enemies only is the new default, so animals do not fill the map.
- The perf line in UE4SS.log also shows the FPS of the game. This helps when you report a problem.

### Fixed

- RuneMap became slower during a play session. Each time you opened the big map (M), the game put another copy of the terrain on RuneMap, and RuneMap drew every copy.
- A small hitch every 2 seconds. The mod now searches for the parts of the HUD much less often.
- On a wide screen, the level badge and the line under the bars were far away from the bars.

A layout that you made on a wide screen with an older version can move a little once. Correct it in F9.

## 1.1 (released as part of 1.2)

### New

- F8 opens the settings of RuneMap, in a panel under the map. Each change shows on the map.
  - Faces north: the map stops turning with the camera, and north stays at the top.
  - North mark: a gold N on the ring of the map shows where north is.
  - Creatures: shows or hides the creature diamonds. This is the same switch as "Creatures on RuneMap" in F9.
  - Zoom: the same zoom as the ] and [ keys.
  - Drawing: Faster draws the map every second frame. Smooth draws it every frame.
- Opacity for each element in F9. Comma and period change it in steps of 10%, from 100% to 20%. The layout file keeps it. A layout from an older version loads at 100%.

### Changed

- The F9 and F8 panels have a dark background with a double gold line, like the inventory of the game. The text is easier to read.
- The key list of F9 shows F8. F8 in F9 opens the map settings, and F9 in F8 opens the editor.
- While F8 is open, RuneMap shows, also when it is hidden in F9.

## 1.0.1 (28-09-2026)

- Fixed heavy stutter, worst on older UE4SS builds.
- Fixed crashes after using the F9 editor for a while.
- Hiding RuneMap now also hides its gold rings, and gives back the FPS the map costs.
- RuneMap now draws every second frame, for about 10 FPS more.
- If UE4SS.log says "timer: old UE4SS", update UE4SS to the latest experimental build.

## 1.0 (28-09-2026)

The first release.

- F9 opens an editor in the game. It moves, resizes and hides 27 parts of the HUD, and saves the layout.
- RuneMap: a round minimap that turns with the camera. Its gold ring is also a clock. Red diamonds show enemies, green diamonds show animals.
- Food, water and rest: three rings in the style of the map. They turn orange and red when a value is low.
- Clean bars: health on top, stamina in green, and a plain dark track behind each bar.
- Round buffs: a ring of dashes shows the time that is left, in the colour of the buff.
- Ammo counter: the rune and arrow count of the staff and the bow moves away from the crosshair.
