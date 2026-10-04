<p align="center"><img src="docs/banner.png" alt="Rune UI"></p>

Move, resize and hide every part of the HUD, right in the game. With a new map, new rings and new bars in the game's own style.

Rune UI is a UE4SS Lua mod for RuneScape: Dragonwilds.

## Before and after

<p align="center"><img src="docs/before-after.gif" alt="A gold line slides across the same screenshot: the game's own HUD on the left, Rune UI on the right"></p>

Left of the line: the game's own HUD. Right of it: Rune UI.

## What it does

<table>
<tr>
<td width="33%" valign="top"><img src="docs/editor.jpg" alt="The Rune UI editor open in the game, with one part selected"><br><b>Edit your HUD in the game</b><br>Press F9. Move, resize, fade or hide 30 parts of the HUD with the keyboard. The mod saves your layout.</td>
<td width="33%" valign="top"><img src="docs/runemap.jpg" alt="RuneMap with red enemy diamonds around the player"><br><b>RuneMap</b><br>A round minimap that turns with the camera or faces north. Its gold ring is also a clock. Red diamonds are enemies, green diamonds are animals.</td>
<td width="33%" valign="top"><img src="docs/rings.jpg" alt="Food and water rings turned orange because they are low"><br><b>Food, water and rest</b><br>Three rings in the style of the map. When a value gets low, they turn orange and red, like the game's own.</td>
</tr>
<tr>
<td width="33%" valign="top"><img src="docs/bars.jpg" alt="Health, stamina and special bars with the level badge"><br><b>Clean bars</b><br>Health on top, stamina in green, a plain dark track behind each bar.</td>
<td width="33%" valign="top"><img src="docs/buffs.jpg" alt="Two round buffs under the bars, one with a ring of dashes"><br><b>Round buffs</b><br>Each buff is a round icon. A ring of dashes shows the time left, in the buff's own colour.</td>
<td width="33%" valign="top"><img src="docs/ammo.jpg" alt="Rune count of the staff beside the survival rings"><br><b>Arrow and rune count</b><br>The rune and arrow count of the staff and the bow moves away from the crosshair, to where you want it.</td>
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
| In immersive mode | What stays while the immersive mode is on. Nothing: the immersive mode hides the map and the compass. Map: the map stays, and the quest tracker with it. Compass: the game's compass stays, and the map is away. The compass always has a gold line, and it shows the marks of the map. Use the left and right arrows to change it. A compass that you hid in the editor stays hidden, also with Compass. |
| Zoom | the same zoom as the [ and ] keys |
| Drawing | Faster: the map draws every second frame. Smooth: every frame. Switching might decrease performance. |

Beside the bars, the mod shows your level in the game's green diamond. To show your own picture there, put an `avatar.png` in the `RuneUI` folder.

"Creatures on the minimap", "Icons beside the bars", "Rune XP (XP under the bars)", "Slim level up (under the bars)" and "Quest tracker: next steps" only switch a thing on or off. "Creatures on the minimap" is the same switch as "Creatures" in F8. Delete and Insert work on them. The arrows, + / - and , / . do nothing.

"Rune XP" shows the XP that you get under the bars. The gold line under the bars becomes the XP bar: it gets thick, and a bright fill moves from its left end to your progress in the level. Under the line you see the icon of the skill, its name and the XP. Then all of it fades, and the plain line is back. The XP moves and sizes with the bars. The name of the skill is in English in every language of the game. When two skills get XP in the same instant, Rune XP shows them one after the other. Hide "Rune XP" to get the XP circle of the game back.

"Slim level up" is on at first. When you reach a new level, the game's big banner in the middle of the screen does not show. In its place, the row of Rune XP shows the level up for as long as the game's notice is on screen. The row is bigger than an XP notice. It grows in with a short pop that slows softly into its rest, while it fades in. When the notice ends, it fades out at the same size. The gold line is bright and full. Under it you see the icon of the skill, its name in white capitals, and "Level N" in gold at the right end. The sparks of the banner do not show. The sound stays as the game makes it. A level up wins over an XP notice in the row, and the XP goes on after it. Hide "Slim level up" to get the game's banner back. It is also off while "Rune XP" is hidden.

The "Quest tracker" shows the quest that you do under the minimap, at the top right. It has no background. A thin gold line is on top, and the letters have the shadow of the HUD. The main quest comes first: a small label, the name of the quest in gold, and the step in white. Below it is the quest that you track in the journal, with the label "Tracked". A finished quest never shows. While the game shows its own quest or unlock notice under the map, the tracker goes away. It comes back after the notice. With no open quest, the tracker shows nothing. When the game has no text for a step, only the name of the quest shows. In the immersive mode the tracker goes with the map. While the map stays (the map setting "In immersive mode"), the tracker stays too. When the map is hidden, the tracker fades, and it comes back for a moment when a quest or a step changes. Move, size and hide it in the editor, like any other part.

"Quest tracker: next steps" is a switch, and it is off at first. When it is on, a quest also shows up to three steps after the current one, dimmed. It does this only for a quest whose list of steps is in a clear order. The mod does not trust a list when a step key has a dot or a letter in its number, when a text holds a count like 0/3, when a text starts with "[", or when two steps have the same text. Such a quest shows only its current step. The same switch is "Show next steps" on the page in Mod Menu.

With a gamepad, the menu shortcuts (chat, map, spell book, building, bag) show the buttons of the gamepad. While the bag is open and a gamepad is in use, the tool bar sits at its own place in the bag, because a gamepad goes from slot to slot by their places on the screen. The tool bar goes back to your place when you close the bag, or when you use the mouse or the keyboard.

When you hide RuneMap, the mod takes the map off the screen. The game then does not draw the map, and you get back the frames that it costs.

"Arrow and rune count" moves only the rune or arrow count of the staff and the bow. The crosshair stays in the middle. At first, the count is to the right of the food and water rings. The count shows as a dark disk with a gold rim. The game's rune or arrow icon fills the disk, and the number is right of it. A rune icon has the colour of its rune: red for fire, blue for water, white for air, brown for earth. The name of the ammo is left of the disk. For runes, the name shows for 4 seconds after you change the ammo. For arrows, the name stays, because all arrows have the same icon.

Rune UI has a page in the mod [Mod Menu](https://www.nexusmods.com/runescapedragonwilds/mods/548). To open the page, press Esc, then MODS, then Rune UI. The page has the five keys that you can change, the immersive mode and its wait, the Rune XP and slim level up switches, the quest tracker's "Show next steps" switch, and the settings of RuneMap without the zoom. It also has the layout profile and a button that opens the editor. A key that you change works after you start the game again. A change that you make in F8 or F9 shows on the page when you open the menu again. So do the immersive mode, Rune XP, the slim level up, the next steps and the creatures of a profile that you change to on the page. Rune UI does not need Mod Menu.

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

`Scripts/runemap.lua` builds a round minimap in the top right corner. It uses the game's own minimap widget, with its own map view on the player. The map turns with the camera. When "Faces north" is on, the map does not turn. A gold ring around the map is also a clock: the middle of the night is at the top, and noon is at the bottom. The ring keeps the game's own share of night, about a fifth of the day. A gold arrow between the two gold rings shows the time of day. A bigger gold arrow with an N shows where north is. It moves along the ring when the camera turns.

The immersive mode hides the map and the compass. The map setting "In immersive mode" picks what stays for direction: Nothing, the map (with the quest tracker), or the game's compass. The compass choice shows the game's own compass, with the gold line and the marks of the map (see Compass below): the editor's hide still wins, so a compass that you hid in the editor stays hidden. The old setting was On or Off. A saved On reads as Map, and a saved Off reads as Nothing. A lighter look of the map for that mode was tried on 04-10-2026 and dropped: the game gives a mod no soft round mask, and two looks of one map are hard to explain.

The map shows no fog, because it has no record of the places that you visited. It shows the terrain around you as it is.

The game's minimap widget is heavy to draw, at every zoom. So by default, the mod draws the map every second frame. This takes away about half of the cost, but the map moves a little less smoothly when the camera turns. To draw the map every frame, set "Drawing" to Smooth in F8.

Creatures show as small diamonds: red for enemies, green for neutral animals. Every 2 s, the mod asks the game for the creatures within 100 m of you, also behind hills and walls. The diamonds are not shown on the big map (M). To hide them, set "Creatures" to Off in F8. Then the mod does not look for creatures at all. A list of animal names in `nearby.lua` decides which creatures are neutral.

The game's map plugin puts the terrain on the map again each time the big map (M) opens. The mod takes the extra copies off RuneMap after each visit, because the map draws every copy.

The mod reads the time from the material of the game's day and night dial: `Fill Amount` is the part of the day that is gone, and `Night Start` is where the night begins. An error in the map does not stop the rest of the mod. The log shows when the map is ready, or the step that failed, with the prefix `runemap`.

### Compass

`Scripts/compass.lua` gives the game's compass the gold style of the mod. This is always on while the compass shows, and it has no switch. A gold line sits on the white line of the strip, and the game's middle mark is gold. The letters stay white, because they are part of the strip's picture. A compass that you hid in the editor shows none of this.

While the compass shows and the map does not, the compass also shows the marks of the map. These are the groups that you switched on in F8: creatures, ore, herbs, rune essence and rare trees. A red diamond is an enemy, and a green diamond is a neutral animal. "Creatures" has the same three values as on the map. The marks use the pictures of the map, and they add no setting. You see them in the immersive mode with "In immersive mode" at Compass. You also see them when you turn RuneMap off in F8.

A mark sits at the bearing of its thing, at the scale of the game's own marks: 5.33 units for one degree. A mark more than 300 units from the middle is not shown, and it fades out over the last 40 units. A far thing is smaller and dimmer. At 60 m, a mark has 0.6 of its size and half of its opacity. The compass shows 40 marks at most.

`Scripts/nearby.lua` finds the things near you and decides what each one is. The icons of RuneMap and the marks of the compass both use it, so the two always agree. It searches for creatures within 100 m every 2 s. It searches for ore, herbs, rune essence and rare trees within 60 m every 10 s.

The main loop of the mod runs about 16 times a second. That is too few for a smooth turn. While marks are wanted and a thing is near, a chain of delayed calls on the game thread (`Scripts/chain.lua`, shared with Rune XP) moves them about every frame. The chain ends when no mark is wanted or no thing is near. It also runs while every thing is behind you, so that a mark comes in at the edge with no delay when you turn. A chain that stalls for a second is replaced, and the old one does nothing. The mod writes a widget only when its value changed. Each picture sits in a hidden image of the compass, because the engine frees a picture that only Lua holds.

### Food, water and rest

`Scripts/survival.lua` draws the three survival values in the map's style: a gold rim, a coloured ring that fills with the value, the game's icon in a dark centre and a diamond under it. The game's own rings stay in place but are not visible. The mod reads the values from the game's numbers. When a value is low, the game turns its icon red and its ring orange (25 or less) or dark red (10 or less). The mod's ring and icon take the same colours, a little brighter so they still show.

### Bars

Each bar is a plain box: a dark track behind the fill. The health bar is on top and the stamina bar under it. The stamina fill is green; the other fills keep the game's colours. The health bar shows no numbers. The mod hides them but still reads them, so the immersive mode knows when you are hurt. The icons beside the bars are hidden. To show them, show "Icons beside the bars" in the editor.

### Buffs

In the immersive mode a debuff in the buff row shows for the whole time that it lasts. A good buff shows when it arrives, stays for the wait of the immersive mode, and fades. A new buff does not bring the other good buffs back. The bars bring all of them back. The game does not mark a buff as good or bad. `buffs.lua` holds the names of the good ones (Cosiness, Sheltered, Well Rested and Prayer), read from the data object of each entry. Every other name, an unknown name and an unreadable entry count as a debuff. The row itself never fades. A good buff arrives when its name was not on at the last look of the mod: a new buff, an entry that the game uses for another buff, or a buff that was over and is on again (the game keeps the entry of Sheltered and changes its fill from 0 to 1). `buffs.lua` counts the arrivals of each entry. `immersive.lua` keeps the wait and the fade of each good entry in its step, and gives the level to `buffs.lua` (`SetLevel`) only when it changes. `PlaceBuff` is the one place that sets the opacity and the width of an entry. A good buff that has faded, like a buff that is over, is 1 unit wide, and its icon, bar and shadow are unseen too, so the row closes and no thin line stays. The drink, food and potion rings fade on their own.

Each buff is its icon with a thin bar under it, so it looks like a small copy of the bars above it. The bar shows the time that is left, in the buff's colour from the game, for example green for poison. A buff without a timer has no bar. The icon has a dark shadow, so you can read it over bright grass.

The game can keep a buff in its list after the buff ended, for example the poison after you died from it. Its bar is then empty. The mod hides a buff with an empty bar and closes the row. When the bar fills again, the buff is back.

The drink, food and potion buffs sit right of the food, water and rest rings. The game's line between them is hidden. Each one is a small ring, level with the food rings: blue for a drink, green for a food, gold for a potion. The ring shows the time that is left; the number of seconds is hidden. Move, resize or hide them together with "Buff rings (drink, food, potion)" in the editor. In the immersive mode, each of these rings shows when its buff starts, fades, and comes back when the buff runs low.

The game can leave the icon of a buff in the buff row after the buff ends. The mod reads the number on the bar of each buff: the game writes 0 there when the buff is over, also on the hidden bar of a buff without a timer. The mod then hides the icon and closes the row.

### Aim, cooldowns and prompts

`Scripts/aim.lua` makes the aim marks gold: the crosshair, the bow's ring, dot and stamina bar, and the lock-on bracket. A gold diamond replaces the lock-on orb. The game makes a new ring for each staff target from one template. The mod puts a gold diamond into that template once, so each new ring has it. When "Crosshair and lock-on" is off in F9, the marks are white again, also after a restart of the player.

`Scripts/cooldowns.lua` reads the 12 slices of the game's spell wheel. The wheel counts on while it is closed. For each spell that recovers, the mod shows a tile with the spell's icon, a gold fill and the game's own seconds.

`Scripts/toolbar.lua` gives the tool bar the look of the cooldown tiles. The black square of each slot is see-through, with a thin gold edge. The slot number and the stack count are in the HUD font. The durability bar keeps the colours of the game, on a dark track. The slot in use has a bright gold edge in place of the orange frame of the game. The game builds a slot new when its item changes, so the mod looks at the eight slots about 7 times a second and paints a new slot again. The slots of the bag window stay as they are.

`Scripts/letters.lua` puts a shadow on the letters of the pick-up prompt, the build panel and the repair mode. It keeps the words of the build and repair panels white, and it removes the faint dark shape behind the title of the build panel. The key letters, the red "inventory full" line and the cost rows keep the game's colours.

`Scripts/xp.lua` is Rune XP. It reads the XP notice that the game shows (the icon, the text, and the progress from the material of the ring), and it draws the row and the fill in the bars widget. It makes the circles of the game unseen by the size of their grid, because the game animates their opacity.

The slim level up is in the same file. The game keeps one `WBP_LevelUpNotification_C` per world in its notification queue, and it shows it by the render opacity of that widget: 0 when idle, up to 1 for about 3 seconds. The mod reads that opacity: above zero means the notice is on show. Then it reads the level text and the skill icon (`T_Icon_Tag_Skill_<skill>`), which keep the last level up while idle, and it shows them in the XP row. The mod never writes the opacity of that widget. `main.lua` writes it only for a hidden element and while the editor is open, and the slim level up is off in both. The mod hides the banner by the render scale 0 of its parts (the overlays, the three text backgrounds, the game's own key hint, the level text and the icon), and it writes them again every half second in case the game scales them back. The two spark effects of the banner draw inside a part at scale 0, and inside a box at opacity 0. So the mod collapses them, and it makes them visible again when it puts the parts back. The sound is not touched, and the mod calls no function of the game's widget. The mod puts the parts back when the switch goes off, when Rune XP goes off, and on a restart of the player. The size and the opacity of the row are functions of time (`Grow` and `LevelFade` in `xp.lua`), written at every step of the mod. The pop is a cubic ease-out from 1.9 to 1.6 in 0.3 s. The level up fades in over 0.22 s. The row keeps the size 1.6 while it fades out. The mod steps about 16 times a second, which is too slow for a change of size. So while a level up comes in and while it fades out, a chain of delayed calls on the game thread (`Fast` in `xp.lua`) also paints it about every frame, and the chain ends by itself.

`Scripts/questtracker.lua` is the quest tracker. It reads the quest component of the local player controller (the property `BP_Components_QuestProgress`). It reads properties only and calls no function of the component. `Quests` holds the state (0 not started, 1 open, 2 finished; read from one save) and the current step key of each quest. `TrackedSecondaryQuest` is the quest tracked in the journal. The quest's data holds its name, `bIsMainQuest`, `bHideInQuestList` and `ObjectiveTexts`, a map of step key to step text in the order held. The mod reads the game once a second, and it writes new text only when a quest, a state or a step changes. The tracker is its own widget on the viewport, as the cooldowns are. `Scripts/goldline.lua` draws the pointed gold line for the bars, the XP bar and the tracker.

`Scripts/pickups.lua` gives the list of picked-up items the same look. The dark band and the gold lines of each row are hidden. The texts are in the HUD font, with the shadow of the letters. The count is gold. The row of a new item has no sparks. The game tints "NEW MATERIAL !" near black for about two seconds. The mod changes the colour of that animation once, so the words are light from the start. The list is the element "Picked-up items" in the editor.

`Scripts/bednames.lua` puts a space into the name of a claimed bed roll: "Ann's Bed Roll". The game joins the owner and the name without a space. The mod changes the name that the bed roll gives to the game, so the prompt shows it with the space. The mod sets the same hook for a bed.

`Scripts/quests.lua` gives the quests and unlocks the HUD font, with the shadow of the letters. The key letters keep the font of the game. A row of the panel is new for each notice, so the master copy of the row gets the font, and a new row has it from the start. The mod also looks at every text of the panel and changes each one once. The game made the panel for the right edge, so the element "Quests and unlocks" moves only up and down in the editor, and it keeps its size.

`Scripts/farmplot.lua` changes the panel over each farm plot. The water and compost icons are half their size. The clearing panel loses its dark band, its frame and the gloss of its bar. Its title is smaller, with the shadow of the letters, and its bar is brown. Each plot has its own panel, so the mod changes each panel once.

The death screen is the element "Death screen" in the editor: move it or make it smaller there. You cannot hide it. Only the words and the bars change their size and place: the blur and the dark background still fill the screen.

`Scripts/clock.lua` is off: `main.lua` does not load it, and its element is not in the editor list. The lines that load it are comments in `main.lua`. When it is on, it shows the time of day right of the tool bar while the immersive mode is on. It reads the time from the game's day and night dial, as RuneMap does. Each of its four pictures sits in its own Image widget. The engine frees a picture that only Lua holds, and Lua then crashes the game when it touches it.

`Scripts/ammo.lua` puts the disk of the ammo counter in the game's ammo box. It copies the game's count, icon and name into its own widgets. The mod takes the game's own name, count and icon out of the box, because the game shows them again on a weapon switch and they pushed the disk down. The game still writes them, and the mod reads them.

`Scripts/editor.lua` draws the F9 and F8 panel and the mark on the selected element. `main.lua` gives it a plain table of what to show. When a part of the mod failed, the panel shows a line with its name, so you can look in `UE4SS.log` for it.

`Scripts/layout.lua` holds the position math: where each part sits on this screen, and what to write into its widget. `Scripts/settings.lua` reads and writes `runeui.txt`. `Scripts/modmenu.lua` is the page in Mod Menu: `modmenu.txt` lists the settings, Mod Menu gives their values as shared variables of UE4SS, and the script takes a value that the player changed there. It does not take the first values that it sees: without a `config.txt` they are the defaults of the page. None of them talks to the game, so all three have tests that run without it. `Scripts/bars.lua`, `Scripts/avatar.lua` and `Scripts/buffs.lua` build on the game's bars, the level badge and the buff list. `main.lua` holds the list of parts, finds the game's widgets, applies the layout, and runs the keys and the editor.

### Speed

The mod finds the parts of the HUD with one search of all widgets. The game holds 7000 to 10000 widgets, and one search took 10 to 50 ms in a test. So the search runs when the mod starts, when a world starts or ends, and after a respawn. After that, UE4SS tells the mod about each new widget (`NotifyOnNewObject`). The mod keeps the widgets of the classes that its parts use. When a part asks for a class for the first time, and the mod did not keep a widget of that class, one more search runs.

The mod matches its parts to the kept widgets again in four cases: a new widget came, a part that it found is gone, the number of buffs changed, or 10 s went by. This reads only the kept widgets, not all widgets of the game.

An older UE4SS runs the timer on two threads (see below), or has no `NotifyOnNewObject`. There the mod does not use the reports, and the log shows "timed search". It searches every 2 s until all HUD parts are found (30 s at most) and while F9 or F8 is open. Then it searches every 10 s, and at once when a part is gone or the number of buffs changes. An older build also reads every object in the game for a search, which took 50 ms or more.

To see a world change, the mod reads the controller of the local player on every step. It does not search for it.

The timer of the mod runs on the game thread, with `LoopInGameThreadWithDelay`. An older UE4SS does not have this function. Then the log shows "timer: old UE4SS", and the timer uses two threads. Two threads in one Lua state can crash the game.

Once a minute, the log gets three or four lines that start with `perf:`. The first shows the time of the mod's steps and searches, the number of widgets that the mod moves, and the memory that Lua uses. The second shows the FPS of the game: with RuneMap shown, and with RuneMap hidden. Menus and loading screens are not counted. The third shows the full searches for the game's widgets: how many ran, their time, and what started each one (the start of the mod, a new world, a respawn, or a class that a part asked for late). It also shows how many new widgets UE4SS reported, the time that the mod needed for them, and how many it kept. A fourth line shows the size of the kept lists, and how many scans a kept widget brought. With an older UE4SS, the searches start from the 10 s timer, the first seconds of a world, the editor, a new buff, or a part that the game took away. After a menu or the big map, the log also shows the time that RuneMap needs to get its view back.

### Screens

The mod reads the size of the screen and the HUD scale of the game every 2 s. A 16:9 screen is 1920 by 1080 units. A wider screen is wider in units, and a larger HUD scale makes the HUD smaller in units. Each part of the HUD knows the edge of the screen that the game ties it to. A layout keeps its moves in 16:9 units, and each part follows the edge of the third of the screen that it is in.

### Files that the mod writes (in `Win64`)

- `runeui.txt`: every setting of the mod, in plain text with named values. The three layout profiles (one line per element: `vitals: x=-699 y=-907 scale=0.9 visible=1 opacity=1 edgex=0.5 edgey=1`), the profile in use, the map settings and the zoom of F8, and the keys. Delete a line to get its default back. A value the mod does not know stays in the file.
- `runeui.txt.tmp`: the file while the mod writes it. It is renamed to `runeui.txt` when the write is done, so a crash never leaves half a file.

A mod older than 1.4 wrote six files instead: `runeui_layout.txt`, `runeui_layout_2.txt`, `runeui_layout_3.txt`, `runeui_profile.txt`, `runeui_mapzoom.txt` and `runeui_map.txt`. When `runeui.txt` is missing, the mod reads them once and writes `runeui.txt` from them. It does not delete them.

In the `[keys]` part of `runeui.txt` you can change five keys: `editor` (F9), `map` (F8), `profile` (F7), `zoomin` (]) and `zoomout` ([). A key is a name: `F1` to `F12`, a letter, a digit, `Insert`, `Delete`, `Home`, `End`, `PgUp`, `PgDn`, `[` or `]`. The mod reads the keys when the game starts.

When the game starts, the mod also writes its pictures into `ue4ss/Mods/RuneUI/Art`. It writes a picture only when it is missing or different.

With Mod Menu, the mod also writes `ue4ss/Mods/RuneUI/config.txt`. That file is the copy of the page's settings that Mod Menu keeps. Do not edit it: the mod makes it equal to its own settings again, and Mod Menu reads it each time the menu opens.

The mod does not use the network and does not start other programs.

## Thanks

To Eravex for [Move it Move it](https://www.nexusmods.com/runescapedragonwilds/mods/208), and to Mathayus for [Mini Map](https://www.curseforge.com/runescape-dragonwilds/ue4ss-mods/mini-map). Their mods got me started, and gave me the idea to build a HUD I could move and shape myself.

## Licence

Rune UI is free to use, and its code is open to read. You may not upload it again, publish a changed version, or use parts of it in another mod without the permission of the author. Versions 1.0 to 1.6 stay under the MIT licence. See `LICENSE`.

Created using intellectual property belonging to Jagex Limited under the terms of Jagex's Fan Content Policy. This content is not endorsed by or affiliated with Jagex.
