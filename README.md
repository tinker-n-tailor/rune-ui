<p align="center"><img src="docs/banner.png" alt="Rune UI"></p>

<p align="center"><a href="https://ko-fi.com/filchie"><img src="https://img.shields.io/badge/Ko--fi-Support%20me-FF5E5B?logo=ko-fi&logoColor=white" alt="Support me on Ko-fi"></a></p>

Move, resize and hide every part of the HUD, right in the game. With a new map, new rings and new bars in the game's own style.

Rune UI is a UE4SS Lua mod for RuneScape: Dragonwilds.

## Before and after

<p align="center"><img src="docs/before-after.gif" alt="A gold line slides across the same screenshot: the game's own HUD on the left, Rune UI on the right"></p>

Left of the line: the game's own HUD. Right of it: Rune UI.

## What it does

<table>
<tr>
<td width="33%" valign="top"><img src="docs/editor.jpg" alt="The Rune UI editor open in the game, with one part selected"><br><b>Edit your HUD in the game</b><br>Press F9. Move, resize, fade or hide 29 parts of the HUD with the keyboard. The mod saves your layout.</td>
<td width="33%" valign="top"><img src="docs/runemap.jpg" alt="RuneMap with red enemy diamonds around the player"><br><b>RuneMap</b><br>A round minimap that turns with the camera or faces north. Its gold ring is also a clock. Red diamonds are enemies, green diamonds are animals.</td>
<td width="33%" valign="top"><img src="docs/rings.jpg" alt="Food and water rings turned orange because they are low"><br><b>Food, water and rest</b><br>Three rings in the style of the map. When a value gets low, they turn orange and red, like the game's own.</td>
</tr>
<tr>
<td width="33%" valign="top"><img src="docs/bars.jpg" alt="Health, stamina and special bars with the level badge"><br><b>Clean bars</b><br>Health on top, stamina in green, a plain dark track behind each bar.</td>
<td width="33%" valign="top"><img src="docs/buffs.jpg" alt="Two round buffs under the bars, one with a ring of dashes"><br><b>Round buffs</b><br>Each buff is a round icon. A ring of dashes shows the time left, in the buff's own colour.</td>
<td width="33%" valign="top"><img src="docs/ammo.jpg" alt="Rune count of the staff beside the survival rings"><br><b>Ammo counter</b><br>The rune and arrow count of the staff and the bow moves away from the crosshair, to where you want it.</td>
</tr>
</table>

What changed in each version: [CHANGELOG.md](CHANGELOG.md).

## Install

Rune UI needs the experimental build of UE4SS. The CurseForge app installs UE4SS 3.0.1 for Dragonwilds. At the moment, that version does not start with the game, so no mod runs.

1. Download the zip whose name starts with `UE4SS_v3.0.1-` from the [UE4SS experimental release](https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/experimental-latest). Do not use the `zDEV` zip.
2. Copy `dwmapi.dll` and the `ue4ss` folder from the zip into `RSDragonwilds\Binaries\Win64`. Replace the old files.
3. Copy the `RuneUI` folder to `Win64\ue4ss\Mods\`. Keep the folder name `RuneUI`: the mod finds its pictures by that name.
4. Start the game. The `enabled.txt` file in the folder turns the mod on.

If Rune UI does not show, open `Win64\ue4ss\UE4SS.log`. If the log shows "Fatal Error", UE4SS is the old version. Do steps 1 and 2 again.

If the log shows "timer: old UE4SS", your UE4SS build is older than the mod needs. The game can stutter or crash. Do steps 1 and 2 again.

When the CurseForge app installs or removes a mod, it can put UE4SS 3.0.1 back. If your mods stop working after that, do steps 1 and 2 again.

Other mods that change the HUD can conflict with Rune UI. Two mods that move the same part of the HUD fight each other.

If you used this mod before version 0.60, when its name was HudEditor: remove the `HudEditor` folder and the `HudEditor : 1` line in `mods.txt`. Rune UI reads your saved layout and map zoom from the old files.

## Keys

Press F9 in the game. A panel shows a small map of the screen, the selected element, the list of elements by area of the screen, and the keys. The panel stays on one side of the screen. It moves to the other side only when it would cover the selected element. Gold corners and a tag with the name, X and Y mark the selected element on the screen.

| Key | Action |
| --- | --- |
| PgUp / PgDn | select an element |
| Arrows | move the element; hold an arrow to keep moving |
| Home / End | change the move step (1 to 100) |
| + / - | change the size, 5% per press |
| , / . | make the element more or less see-through, 10% per press (100% to 20%) |
| Delete / Insert | hide / show the element |
| Backspace | reset the element to the starting layout |
| F7 | save this layout profile and go to the next one (1, 2, 3) |
| F8 | go to the map settings |
| F9 | save and close the editor |
| ] / [ | zoom RuneMap in / out (this works outside the editor too) |

Press F8 in the game for the settings of RuneMap. The panel opens under the map. Each change shows on the map.

| Key | Action |
| --- | --- |
| Up / Down | select a setting |
| Left / Right | change the setting |
| ] / [ | zoom RuneMap in / out |
| Backspace | reset the map settings |
| F8 | save and close the map settings |

| Setting | Values |
| --- | --- |
| Faces north | Off: the map turns with the camera. On: north stays at the top. |
| North mark | On: a mark on the gold ring shows where north is. |
| Creatures | On: diamonds for the creatures near you. |
| Zoom | the same zoom as the [ and ] keys |
| Drawing | Faster: the map draws every second frame. Smooth: every frame. Switching might decrease performance. |

Beside the bars, the mod shows your level in the game's green diamond. To show your own picture there, put an `avatar.png` in the `RuneUI` folder.

"Creatures on RuneMap" and "Icons beside the bars" only switch a thing on or off. "Creatures on RuneMap" is the same switch as "Creatures" in F8. Delete and Insert work on them. The arrows, + / - and , / . do nothing.

When you hide RuneMap, the mod takes the map off the screen. The game then does not draw the map, and you get back the frames that it costs.

"Ammo counter" moves only the rune or arrow count of the staff and the bow. The crosshair stays in the middle. At first, the count is to the right of the food and water rings. The count shows as a dark disk with a gold rim. The game's rune or arrow icon fills the disk, and the number is right of it. A rune icon has the colour of its rune: red for fire, blue for water, white for air, brown for earth. The name of the ammo is left of the disk. For runes, the name shows for 4 seconds after you change the ammo. For arrows, the name stays, because all arrows have the same icon.

## Gallery

<table>
<tr>
<td width="33%"><img src="docs/gallery-1.jpg" alt="A staff spell calls fire down on two burning zombies"></td>
<td width="33%"><img src="docs/gallery-2.jpg" alt="The player in flames, fighting at dusk"></td>
<td width="33%"><img src="docs/gallery-3.jpg" alt="A close fight with one enemy in a misty forest"></td>
</tr>
<tr>
<td width="33%"><img src="docs/gallery-4.jpg" alt="The level up banner in the middle of a fight"></td>
<td width="33%"><img src="docs/gallery-5.jpg" alt="Lightning strikes near the player on a cliff in the rain"></td>
<td width="33%"><img src="docs/gallery-6.jpg" alt="The Bleakfields Valley banner as the player enters the area at night"></td>
</tr>
</table>

## How it works

### RuneMap

`Scripts/runemap.lua` builds a round minimap in the top right corner. It uses the game's own minimap widget, with its own map view on the player. The map turns with the camera. When "Faces north" is on, the map does not turn. A gold ring around the map is also a clock: the middle of the night is at the top, and noon is at the bottom. The ring keeps the game's own share of night, about a fifth of the day. A gold needle on the ring shows the time of day. A round mark with an N on the inner gold ring shows where north is. It moves along the ring when the camera turns.

The map shows no fog, because it has no record of the places that you visited. It shows the terrain around you as it is.

The game's minimap widget is heavy to draw, at every zoom. So by default, the mod draws the map every second frame. This takes away about half of the cost, but the map moves a little less smoothly when the camera turns. To draw the map every frame, set "Drawing" to Smooth in F8.

Creatures show as small diamonds: red for enemies, green for neutral animals. Every 2 s, the mod asks the game for the creatures within 300 m of you, also behind hills and walls. The diamonds are not shown on the big map (M). To hide them, set "Creatures" to Off in F8. Then the mod does not look for creatures at all. A list of animal names in `runemap.lua` decides which creatures are neutral.

The game's map plugin puts the terrain on the map again each time the big map (M) opens. The mod takes the extra copies off RuneMap after each visit, because the map draws every copy.

The mod reads the time from the material of the game's day and night dial: `Fill Amount` is the part of the day that is gone, and `Night Start` is where the night begins. An error in the map does not stop the rest of the mod. The log shows when the map is ready, or the step that failed, with the prefix `runemap`.

### Food, water and rest

`Scripts/survival.lua` draws the three survival values in the map's style: a gold rim, a coloured ring that fills with the value, the game's icon in a dark centre and a diamond under it. The game's own rings stay in place but are not visible. The mod reads the values from the game's numbers. When a value is low, the game turns its icon red and its ring orange (25 or less) or dark red (10 or less). The mod's ring and icon take the same colours, a little brighter so they still show.

### Bars

Each bar is a plain box: a dark track behind the fill. The health bar is on top and the stamina bar under it. The stamina fill is green; the other fills keep the game's colours. The health bar shows no numbers. The mod hides them but still reads them, so the immersive mode knows when you are hurt. The icons beside the bars are hidden. To show them, show "Icons beside the bars" in the editor.

### Buffs

Each buff is a ring, like the food, water and rest rings. The ring shows the time that is left, in the buff's colour from the game, for example green for poison.

The drink buff sits right of the food, water and rest rings. The game's line between them is hidden. It is a blue ring of the same size as the other buff rings, level with the food rings. The ring shows the time that is left; the number of seconds is hidden. Move, resize or hide it with "Drink buff" in the editor. In the immersive mode, the drink ring shows when you drink, fades, and comes back when the drink runs low.

### Aim, cooldowns and prompts

`Scripts/aim.lua` makes the aim marks gold: the crosshair, the bow's ring, dot and stamina bar, and the lock-on bracket. A gold diamond replaces the lock-on orb. The game makes a new ring for each staff target from one template. The mod puts a gold diamond into that template once, so each new ring has it. When "Gold aim and lock-on" is off in F9, the marks are white again, also after a restart of the player.

`Scripts/cooldowns.lua` reads the 12 slices of the game's spell wheel. The wheel counts on while it is closed. For each spell that recovers, the mod shows a tile with the spell's icon, a gold fill and the game's own seconds.

`Scripts/letters.lua` puts a shadow on the letters of the pick-up prompt, the build panel and the repair mode. It keeps the words of the build and repair panels white, and it removes the faint dark shape behind the title of the build panel. The key letters, the red "inventory full" line and the cost rows keep the game's colours.

`Scripts/clock.lua` shows the time of day right of the tool bar while the immersive mode is on. It reads the time from the game's day and night dial, as RuneMap does. Each of its four pictures sits in its own Image widget. The engine frees a picture that only Lua holds, and Lua then crashes the game when it touches it.

`Scripts/ammo.lua` puts the disk of the ammo counter in the game's ammo box. It copies the game's count, icon and name into its own widgets. The mod takes the game's own name, count and icon out of the box, because the game shows them again on a weapon switch and they pushed the disk down. The game still writes them, and the mod reads them.

`Scripts/editor.lua` draws the F9 and F8 panel and the mark on the selected element. `main.lua` gives it a plain table of what to show. When a part of the mod failed, the panel shows a line with its name, so you can look in `UE4SS.log` for it.

`Scripts/layout.lua` holds the position math: where each part sits on this screen, and what to write into its widget. `Scripts/settings.lua` reads and writes `runeui.txt`. Neither of them talks to the game, so both have tests that run without it. `Scripts/bars.lua`, `Scripts/avatar.lua` and `Scripts/buffs.lua` build on the game's bars, the level badge and the buff list. `main.lua` holds the list of parts, finds the game's widgets, applies the layout, and runs the keys and the editor.

### Speed

The mod finds the parts of the HUD with one search of all widgets. The time of a search depends on the UE4SS build. In a test, a search took about 15 ms with a recent experimental build. An older build reads every object in the game, and a search took 50 ms or more. So the search runs every 2 s only for the first half minute of a world and while F9 or F8 is open. Then it runs every 10 s, and at once when a part that it found is gone or the number of buffs changes.

To see a world change, the mod reads the controller of the local player on every step. It does not search for it.

The timer of the mod runs on the game thread, with `LoopInGameThreadWithDelay`. An older UE4SS does not have this function. Then the log shows "timer: old UE4SS", and the timer uses two threads. Two threads in one Lua state can crash the game.

Once a minute, the log gets two lines that start with `perf:`. The first shows the time of the mod's steps and searches, the number of widgets that the mod moves, and the memory that Lua uses. The second shows the FPS of the game: with RuneMap shown, and with RuneMap hidden. Menus and loading screens are not counted.

### Screens

The mod reads the size of the screen and the HUD scale of the game every 2 s. A 16:9 screen is 1920 by 1080 units. A wider screen is wider in units, and a larger HUD scale makes the HUD smaller in units. Each part of the HUD knows the edge of the screen that the game ties it to. A layout keeps its moves in 16:9 units, and each part follows the edge of the third of the screen that it is in.

### Files that the mod writes (in `Win64`)

- `runeui.txt`: every setting of the mod, in plain text with named values. The three layout profiles (one line per element: `vitals: x=-699 y=-907 scale=0.9 visible=1 opacity=1 edgex=0.5 edgey=1`), the profile in use, the map settings and the zoom of F8, the trim line of the main menu for the line under the bars, and the keys. Delete a line to get its default back. A value the mod does not know stays in the file.
- `runeui.txt.tmp`: the file while the mod writes it. It is renamed to `runeui.txt` when the write is done, so a crash never leaves half a file.

A mod older than 1.4 wrote six files instead: `runeui_layout.txt`, `runeui_layout_2.txt`, `runeui_layout_3.txt`, `runeui_profile.txt`, `runeui_mapzoom.txt`, `runeui_map.txt` and `runeui_menuart.txt`. When `runeui.txt` is missing, the mod reads them once and writes `runeui.txt` from them. It does not delete them.

In the `[keys]` part of `runeui.txt` you can change five keys: `editor` (F9), `map` (F8), `profile` (F7), `zoomin` (]) and `zoomout` ([). A key is a name: `F1` to `F12`, a letter, a digit, `Insert`, `Delete`, `Home`, `End`, `PgUp`, `PgDn`, `[` or `]`. The mod reads the keys when the game starts.

When the game starts, the mod also writes its pictures into `ue4ss/Mods/RuneUI/Art`. It writes a picture only when it is missing or different.

The mod does not use the network and does not start other programs.

## For developers

The pictures are in `RuneUI/Art`: the day band, the needle, the north mark, the diamonds, the creature diamonds, the survival rings, the bar tracks, the dash of the buff rings, the staff's target mark, the four time of day icons, and the editor's corners and box line. `tools/make-runemap-art.js` draws them. Run `node tools/make-runemap-art.js` again after you change a colour or a size in it. The band is drawn for the game's night start of 0.795. If the game changes that value, the log says so.

CurseForge does not accept `.png` files in a Dragonwilds mod. So the tool also writes all the pictures into `RuneUI/Scripts/art.lua` as base64 text. When the game starts, the mod writes them back into `RuneUI/Art`. `RuneUI/Art/readme.txt` keeps the `Art` folder in the zip. `node tools/check-art.js` checks that the mod writes the pictures back byte for byte.

`node tools/make-zip.js` builds the release zip, `RuneUI-<version>.zip`, in the repo root. The same zip goes to CurseForge and Nexus Mods. It adds `LICENSE` as `LICENSE.txt` and leaves out the `.png` files. It stops if the zip would hold a file type that CurseForge does not accept. `RuneUI/README.txt` is the short README for players inside the zip. `tools/make-readme-txt.js` makes it from the Install and Keys parts of this README and the list of files that the mod writes. Run `node tools/make-readme-txt.js` after you change them here.

`tools/live-link` holds the live link, a small development mod that changes code while the game runs. Copy `RuneUIProbe` into the game's `Mods` folder and put an empty `enabled.txt` in it. Rename that file to `enabled.txt.off` to switch the link off. Each second it reads `Mods/RuneUIProbe/live.lua`, and it runs the file once when its text changes. Lines in `UE4SS.log` start with `[Probe]`. `probe-example.lua` shows a safe check of widgets. `shot.lua` takes a game screenshot with the HUD. `crop.ps1` cuts a part of a screenshot and enlarges it. Players do not get the live link: `tools/make-zip.js` packs only `RuneUI`.

`node tools/read-dump.js <file.dmp>` reads a UE4SS crash dump: the exception, the module, and the module addresses on the stack.

`node tools/check-lua.js` checks the Lua files without the game: the syntax, that every global name is a Lua or UE4SS one, and that no top-level local name is declared twice. It also counts the top-level locals of each file. Lua allows 200, and a file with more does not load.

`node tools/test-aim.js`, `test-immersive.js`, `test-cooldowns.js`, `test-find.js`, `test-letters.js` and `test-clock.js` run parts of the Lua against fake widgets, without the game. `test-layout.js` drives the position math on a 16:9 screen, a 21:9 screen and with the game's HUD scale. `test-settings.js` covers `runeui.txt` and the reading of the old files. `node tools/run-tests.js` runs all the `tools/test-*.js` files.

Each part of the mod is one file in `RuneUI/Scripts` with a `Tick(ctx)` or a `Scan(ctx)` and a `Forget(sameWorld)`. `main.lua` keeps them in one list (`AddPart`): the step calls each `Tick` in that order, each widget scan calls `Scan`, and a new world calls `Forget`. A new part is one file and one `AddPart` line.

Run `npm install` once. Then `npm test` runs all the checks: the Lua check, the picture check, the check that `RuneUI/README.txt` matches this README, and the tests without the game. GitHub runs `npm test` on every push.

The pictures of this README are in `docs`.

## Thanks

To Eravex for [Move it Move it](https://www.nexusmods.com/runescapedragonwilds/mods/208), and to Mathayus for [Mini Map](https://www.curseforge.com/runescape-dragonwilds/ue4ss-mods/mini-map). Their mods got me started, and gave me the idea to build a HUD I could move and shape myself.

## Licence

The code of Rune UI is under the MIT licence. See `LICENSE`.

Created using intellectual property belonging to Jagex Limited under the terms of Jagex's Fan Content Policy. This content is not endorsed by or affiliated with Jagex.
