Rune UI
A UE4SS Lua mod for RuneScape: Dragonwilds.
Move, resize, fade and hide every part of the HUD, right in the game. With a new map, new rings and new bars in the game's own style.

INSTALL

Rune UI needs the experimental build of UE4SS. The CurseForge app installs UE4SS 3.0.1 for Dragonwilds. At the moment, that version does not start with the game, so no mod runs.

1. Download the zip whose name starts with "UE4SS_v3.0.1-" from the UE4SS experimental release: https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/experimental-latest
   Do not use the zDEV zip.
2. Copy dwmapi.dll and the ue4ss folder from the zip into RSDragonwilds\Binaries\Win64. Replace the old files.
3. Copy the RuneUI folder to Win64\ue4ss\Mods\. Keep the folder name RuneUI: the mod finds its pictures by that name.
4. Start the game. The enabled.txt file in the folder turns the mod on.

If Rune UI does not show, open Win64\ue4ss\UE4SS.log. If the log shows "Fatal Error", UE4SS is the old version. Do steps 1 and 2 again.

If the log shows "timer: old UE4SS", your UE4SS build is older than the mod needs. The game can stutter or crash. Do steps 1 and 2 again.

When the CurseForge app installs or removes a mod, it can put UE4SS 3.0.1 back. If your mods stop working after that, do steps 1 and 2 again.

Other mods that change the HUD can conflict with Rune UI. Two mods that move the same part of the HUD fight each other.

If you used this mod before version 0.60, when its name was HudEditor: remove the HudEditor folder and the "HudEditor : 1" line in mods.txt. Rune UI reads your saved layout and map zoom from the old files.

KEYS

Press F9 in the game. A panel shows a small map of the screen, the selected element, the list of elements by area of the screen, and the keys. The panel stays on one side of the screen. It moves to the other side only when it would cover the selected element. Gold corners and a tag with the name, X and Y mark the selected element on the screen.

PgUp / PgDn         select an element
Arrows              move the element; hold an arrow to keep moving
Home / End          change the move step (1 to 100)
+ / -               change the size, 5% per press
, / .               make the element more or less see-through, 10% per press (100% to 20%)
Delete / Insert     hide / show the element
Backspace           reset the element to the starting layout
F7                  save this layout profile and go to the next one (1, 2, 3)
F8                  go to the map settings
F9                  save and close the editor
] / [               zoom RuneMap in / out (this works outside the editor too)

Press F8 in the game for the settings of RuneMap. The panel opens under the map. Each change shows on the map.

Up / Down           select a setting
Left / Right        change the setting
] / [               zoom RuneMap in / out
Backspace           reset the map settings
F8                  save and close the map settings

Faces north         Off: the map turns with the camera. On: north stays at the top.
North mark          On: a mark on the gold ring shows where north is.
Creatures           On: diamonds for the creatures near you.
In immersive mode   What stays while the immersive mode is on. Nothing: the immersive mode hides the map and the compass. Map: the map stays, and the quest tracker with it. Compass: the game's compass stays, and the map is away. The compass always has a gold line, and it shows the marks of the map. Use the left and right arrows to change it. A compass that you hid in the editor stays hidden, also with Compass.
Zoom                the same zoom as the [ and ] keys
Drawing             Faster: the map draws every second frame. Smooth: every frame. Switching might decrease performance.

Beside the bars, the mod shows your level in the game's green diamond. To show your own picture there, put an avatar.png in the RuneUI folder.

"Creatures on the minimap", "Icons beside the bars", "Rune XP (XP under the bars)", "Slim level up (under the bars)" and "Quest tracker: next steps" only switch a thing on or off. "Creatures on the minimap" is the same switch as "Creatures" in F8. Delete and Insert work on them. The arrows, + / - and , / . do nothing.

"Rune XP" shows the XP that you get under the bars. The gold line under the bars becomes the XP bar: it gets thick, and a bright fill moves from its left end to your progress in the level. Under the line you see the icon of the skill, its name and the XP. Then all of it fades, and the plain line is back. The XP moves and sizes with the bars. The name of the skill is in English in every language of the game. When two skills get XP in the same instant, Rune XP shows them one after the other. Hide "Rune XP" to get the XP circle of the game back.

"Slim level up" is on at first. When you reach a new level, the game's big banner in the middle of the screen does not show. In its place, the row of Rune XP shows the level up for as long as the game's notice is on screen. The row is bigger than an XP notice. It grows in with a short pop that slows softly into its rest, while it fades in. When the notice ends, it fades out at the same size. The gold line is bright and full. Under it you see the icon of the skill, its name in white capitals, and "Level N" in gold at the right end. The sparks of the banner do not show. The sound stays as the game makes it. A level up wins over an XP notice in the row, and the XP goes on after it. Hide "Slim level up" to get the game's banner back. It is also off while "Rune XP" is hidden.

The "Quest tracker" shows the quest that you do under the minimap, at the top right. It has no background. A thin gold line is on top, and the letters have the shadow of the HUD. The main quest comes first: a small label, the name of the quest in gold, and the step in white. Below it is the quest that you track in the journal, with the label "Tracked". A finished quest never shows. While the game shows its own quest or unlock notice under the map, the tracker goes away. It comes back after the notice. With no open quest, the tracker shows nothing. When the game has no text for a step, only the name of the quest shows. In the immersive mode the tracker goes with the map. While the map stays (the map setting "In immersive mode"), the tracker stays too. When the map is hidden, the tracker fades, and it comes back for a moment when a quest or a step changes. Move, size and hide it in the editor, like any other part.

"Quest tracker: next steps" is a switch, and it is off at first. When it is on, a quest also shows up to three steps after the current one, dimmed. It does this only for a quest whose list of steps is in a clear order. The mod does not trust a list when a step key has a dot or a letter in its number, when a text holds a count like 0/3, when a text starts with "[", or when two steps have the same text. Such a quest shows only its current step. The same switch is "Show next steps" on the page in Mod Menu.

With a gamepad, the menu shortcuts (chat, map, spell book, building, bag) show the buttons of the gamepad. While the bag is open and a gamepad is in use, the tool bar sits at its own place in the bag, because a gamepad goes from slot to slot by their places on the screen. The tool bar goes back to your place when you close the bag, or when you use the mouse or the keyboard.

When you hide RuneMap, the mod takes the map off the screen. The game then does not draw the map, and you get back the frames that it costs.

"Arrow and rune count" moves only the rune or arrow count of the staff and the bow. The crosshair stays in the middle. At first, the count is to the right of the food and water rings. The count shows as a dark disk with a gold rim. The game's rune or arrow icon fills the disk, and the number is right of it. A rune icon has the colour of its rune: red for fire, blue for water, white for air, brown for earth. The name of the ammo is left of the disk. For runes, the name shows for 4 seconds after you change the ammo. For arrows, the name stays, because all arrows have the same icon.

Rune UI has a page in the mod Mod Menu: https://www.nexusmods.com/runescapedragonwilds/mods/548
To open the page, press Esc, then MODS, then Rune UI. The page has the five keys that you can change, the immersive mode and its wait, the Rune XP and slim level up switches, the quest tracker's "Show next steps" switch, and the settings of RuneMap without the zoom. It also has the layout profile and a button that opens the editor. A key that you change works after you start the game again. A change that you make in F8 or F9 shows on the page when you open the menu again. So do the immersive mode, Rune XP, the slim level up, the next steps and the creatures of a profile that you change to on the page. Rune UI does not need Mod Menu.

FILES THAT THE MOD WRITES (IN WIN64)

runeui.txt      every setting of the mod, in plain text with named values
runeui.txt.tmp  the file while the mod writes it

A mod older than 1.4 wrote six files instead: runeui_layout.txt, runeui_layout_2.txt, runeui_layout_3.txt, runeui_profile.txt, runeui_mapzoom.txt and runeui_map.txt. When runeui.txt is missing, the mod reads them once and writes runeui.txt from them. It does not delete them.

In the [keys] part of runeui.txt you can change five keys: editor (F9), map (F8), profile (F7), zoomin (]) and zoomout ([). A key is a name: F1 to F12, a letter, a digit, Insert, Delete, Home, End, PgUp, PgDn, [ or ]. The mod reads the keys when the game starts.

When the game starts, the mod also writes its pictures into ue4ss/Mods/RuneUI/Art. It writes a picture only when it is missing or different.

With Mod Menu, the mod also writes ue4ss/Mods/RuneUI/config.txt. That file is the copy of the page's settings that Mod Menu keeps. Do not edit it: the mod makes it equal to its own settings again, and Mod Menu reads it each time the menu opens.

The mod does not use the network and does not start other programs.

MORE

Rune UI is free to use, and its code is open to read. You may not upload it again, publish a changed version, or use parts of it in another mod without the permission of the author. See LICENSE.txt.

Created using intellectual property belonging to Jagex Limited under the terms of Jagex's Fan Content Policy. This content is not endorsed by or affiliated with Jagex.
