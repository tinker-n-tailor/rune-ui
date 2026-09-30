# Changelog

All changes to Rune UI, newest first.

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
