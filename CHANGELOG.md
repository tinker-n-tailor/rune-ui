# Changelog

All changes to Rune UI, newest first.

## 1.6 (03-10-2026)

### New

- Rune XP: the XP that you get shows under the bars. The gold line under the bars becomes the XP bar. It gets thick, and a bright fill moves from its left end to your progress in the level. Under the line you see the icon of the skill, its name and the XP. Then all of it fades, and the plain line is back. Rune XP moves and sizes with the bars. It is on at first. To get the XP circle of the game back, hide "Rune XP (XP under the bars)" in the editor, or turn "Rune XP" off on the page in Mod Menu. Each layout profile has its own. When two skills get XP in the same instant, Rune XP shows them one after the other.

### Changed

- The elements in the editor have clearer names. For example: "Menu buttons (chat, map, bag)" is "Menu shortcuts", "Item pick-ups" is "Picked-up items", "Center prompts" is "Interaction prompts", "Ammo counter" is "Arrow and rune count", "XP popup" is "XP circle", and "RuneMap" is "Minimap (RuneMap)". Your layout stays as it is: only the names changed.

### Fixed

- A gamepad moves between the bag and the tool bar again. The game puts the tool bar in the top row of the bag, and a gamepad goes from slot to slot by their places on the screen. Rune UI moved the bar away from the bag, so the gamepad found no way between the two. While the bag is open and a gamepad is in use, the tool bar now sits at its own place in the bag. It goes back to your place when you close the bag. With the mouse and the keyboard, the bar stays where you put it.
- The menu buttons (chat, map, spell book, building, bag) show the buttons of the gamepad when you play with one. Before, they showed the keyboard keys. With a gamepad the key box is the game's own.
- The bright edge of the tool bar is always on the slot of the item in your hand. Before, it stayed on the slot of the item before at times, when you changed the item with a key or with the tool wheel.
- The gold edges of the tool bar slots go away while the tool wheel is open. Before, they stayed on the screen without the bar. In the editor, the edges also dim with the tool bar.

## 1.5 (03-10-2026)

1.5 is a big patch of the HUD look: the item pick-ups, the quests, the tool bar, the buffs, the farm plots and RuneMap. It also adds a page in Mod Menu and two new elements in the editor.

### New

- Rune UI has a page in the mod Mod Menu, for players who have it: press Esc, then MODS. The page has the five keys that you can change, the immersive mode and its wait, the settings of RuneMap without the zoom, the layout profile, and a button that opens the editor. A key that you change works after you start the game again. `runeui.txt` stays the settings file of the mod. Without Mod Menu, nothing changes.
- The tool bar has the look of the cooldown tiles: see-through slots with a thin gold edge, the numbers in the HUD font, and a dark track behind the durability bar. The slot in use has a bright gold edge.
- Food and potion buffs are rings, as the drink buff is: green for a food, gold for a potion. The ring shows the time that is left, without the number. In the editor, "Drink buff" is now "Drink, food and potion buffs" and moves all of them.
- The editor has a new element, "Item pick-ups": the list of items that you picked up, at the right edge of the screen. Move, resize or hide it by itself. Before, it moved only with "Notifications", whose frame is in the middle of the screen, and a smaller "Notifications" pulled the list toward the middle.
- The rows of that list have the look of the HUD: no dark band and no gold lines, the HUD font, a shadow on the letters, and the count in gold.
- The row of a new item has the look of the other rows. It has no sparks. "NEW MATERIAL !" is light from the start, with a little room under the name of the item. It does not blink. The game showed it near black for about two seconds.
- The quests and unlocks have the HUD font, with a shadow on the letters, as the item pick-ups. The panel keeps the look, the slide-in and the sparks of the game.
- The farm plots: the water and compost icons over a plot are half their size. The clearing panel has no dark band and no frame. It has a smaller title with a shadow, and a brown bar in place of the red one.
- The editor has a new element, "Death screen": move it or make it smaller. You cannot hide it. The blur and the dark background still fill the screen.

### Fixed

- The editor panel and the map settings panel show the keys that you set in the `[keys]` part of `runeui.txt`. Before, they showed only F9, F8, F7, [ and ].
- The lock-on diamond is in the middle of the staff's target mark. It was a few pixels right and below.
- The sample tiles of the spell cooldowns show only in the editor (F9). They also showed while the map settings (F8) were open.
- A buff that ended does not stay on the screen. The game kept the poison in its list after the poison ended, with an empty bar. The mod hides a buff with an empty bar, also when the game shows it again.
- The drink, food and potion buffs stay whole when you move them far from the food, water and rest rings. The game cut them at the edge of their lists.
- A claimed bed roll shows its name with a space: "Ann's Bed Roll". The game shows "Ann'sBed Roll". The mod sets the same fix for a bed: "Ann's Bed".
- The F9 and F8 panel fills again after an error. After one error, the panel stayed empty until you changed something in it. `UE4SS.log` shows each different error of the panel once in each world, and 10 at most. Before, it showed only the first error after the mod started.

### Changed

- The frame of "Quests" in the editor has the width of the panel, 440. It was 240.
- The quests and unlocks (the panel with "Press J", and the perk panel with its video) stay at the right edge, at the size of the game. The game made the panel for that edge. In the editor, "Quests" moves only up and down. It starts above the middle, over the list of picked-up items. A layout that you saved before keeps its height.
- The line under the bars is the gold line of the loading screen, pointed at both ends. It was the line of the main menu, and the mod had to see the main menu once to save it. The `[menuart]` part of `runeui.txt` is not used any more. The mod removes it the next time it saves the file.
- Buffs are not rings any more. Each buff is its icon with a thin bar under it. The bar shows the time that is left, in the buff's colour from the game. A buff without a timer has no bar. The icon has a dark shadow, so you can read it over bright grass. As rings, the buffs looked like the food, water and rest rings, and a buff without a timer had a pink ring.
- RuneMap: the rare trees are a violet triangle. The gold one was hard to tell from the brown ore.
- RuneMap: the time of day is a gold arrow between the two gold rings. The needle reached out past the ring. The north mark is a bigger gold arrow with the N cut into it. The three diamonds on the ring are a little bigger.
- The mod does not search all widgets of the game every 10 seconds. One search took 10 to 50 ms, a hitch even when you stood still. Now UE4SS tells the mod about each new widget, and the mod keeps the ones that its parts use. A full search runs when the mod starts, when a world starts or ends, and after a respawn. A new buff and the open editor start no search.
- With an older UE4SS (the log shows "timed search"), the timed search stays. There, the search every 2 seconds after you enter a world or respawn stops when the HUD parts are all found. It ran for 30 seconds.
- The perf lines in UE4SS.log show the full searches and what started them, the new widgets that UE4SS reported with their time and how many the mod kept, and the time RuneMap needs after a menu.

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
