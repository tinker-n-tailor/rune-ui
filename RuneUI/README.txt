Rune UI
A UE4SS Lua mod for RuneScape: Dragonwilds.
Move, resize, fade and hide every part of the HUD, right in the game. With a new map, new rings and new bars in the game's own style.

INSTALL

The CurseForge app installs UE4SS 3.0.1 for Dragonwilds. At the moment, that version does not start with the game, so no mod runs. Use the newer UE4SS build:

1. Go to the UE4SS experimental release on GitHub: https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/experimental-latest
2. Download the zip whose name starts with "UE4SS_v3.0.1-". Do not use the zDEV zip.
3. Open the game folder: Steam\steamapps\common\RSDragonwilds\RSDragonwilds\Binaries\Win64
4. Copy dwmapi.dll and the ue4ss folder from the zip into Win64. Replace the old files.
5. Copy the RuneUI folder into Win64\ue4ss\Mods. Keep the name RuneUI.
6. Start the game and press F9.

Other mods that change the HUD can conflict with Rune UI.

If you used HudEditor before version 0.60, remove the HudEditor folder and the "HudEditor : 1" line in mods.txt.

Rune UI does not show?

Open Win64\ue4ss\UE4SS.log. If it says "Fatal Error", UE4SS is the old version. Do steps 1 to 4 again.

When you install or remove a mod with the CurseForge app, the app can put the old UE4SS back. If your mods stop working after that, do steps 1 to 4 again.

KEYS

Press F9 in the game. The editor lists its keys, and gold corners mark the selected element.

PgUp / PgDn                   select an element
Arrows                        move the element
Home / End                    change the move step (1 to 100)
+ / -                         change the size, 5% per press
, / .                         change the opacity, 10% per press (100% to 20%)
Delete / Insert               hide / show the element
Backspace                     reset the element
F7                            save this layout and go to the next profile (1, 2, 3)
F8                            go to the map settings
F6                            go to the camera settings
F9                            save and close the editor
] / [                         zoom RuneMap in / out (also outside the editor)

Press F8 for the map settings. Each change shows on the map.

Up / Down                     select a setting
Left / Right                  change the setting
] / [                         zoom RuneMap in / out
Backspace                     reset the map settings
F8                            save and close

Faces north                   Off: the map turns with the camera. On: north stays at the top.
North mark                    On: a mark on the gold ring shows where north is.
Player name                   Off: your name does not show beside your arrow on the maps. Other names stay.
Creatures                     On: diamonds for the creatures near you.
In immersive mode             What stays in immersive mode: Nothing, Map (with the quest tracker) or Compass.
Zoom                          The same zoom as the [ and ] keys.
Drawing                       Faster: every second frame. Smooth: every frame, and it can cost performance.

Press F6 for the camera settings. Each change shows on the camera at once. The camera works only while the immersive mode is on. The game itself moves the camera between distances.

Up / Down                     select a setting
Left / Right                  change the setting
Backspace                     reset the camera settings
F9                            go to the editor
F6                            save and close

Immersive camera              Off at first. On: in immersive mode the camera is closer and your character stands on the left.
Walk distance                 The camera distance while you walk. 300 cm at first.
Side offset                   How far right the camera sits. 90 cm at first.
Sprint distance               The camera distance in a sprint. 900 cm at first.
Melee zoom                    The distance in a fight with a melee weapon. 200 cm at first.
Ranged zoom                   The distance while you aim a bow or cast a staff. 500 cm at first.
Hold after a fight            How long the zoom stays after a fight or your last aim. 8 s at first.
Crosshair in immersive mode   Show (at first) or Aim only: no crosshair dot, except while you aim a bow or cast a staff.

Some rows in the editor only switch a part on or off. Delete and Insert work on them. The arrows, + / - and , / . do nothing.

Rune XP                       The gold line under the bars becomes an XP bar, with the skill icon, its name and the XP under it.
Slim level up                 A level up shows as a row under the bars, not as the game's big banner. On at first.
Enemy and boss bars           One colour, in the style of your own bars. Always on.
Combat text                   Bigger, white damage numbers. A critical hit is gold. On at first.
Quest tracker                 Your main quest and your tracked quest, under the minimap.
Quest tracker: next steps     Off at first. On: a quest also shows up to three next steps, dimmed.
Spell cooldowns, horizontal   A tile for each spell that recovers, in a column on the left. The horizontal switch (off at first) puts the tiles in a row.
Party panel                   The name and health bar of up to five friends in a co-op world. On at first.
Arrow and rune count          Moves only the rune or arrow count of the staff and the bow. The crosshair stays.
Level badge and avatar.png    Your level shows in the game's green diamond. Put an avatar.png in the RuneUI folder to show your own picture.
Gamepad                       The menu shortcuts show the buttons of the gamepad.
Mod Menu page                 Press Esc, then MODS, then Rune UI. It holds the keys, the camera, the switches and the map settings. Rune UI does not need Mod Menu.

FILES THAT THE MOD WRITES (IN WIN64)

runeui.txt  Every setting of the mod, in plain text; delete a line to get its default back

In the [keys] part of runeui.txt you can change six keys: editor (F9), map (F8), camera (F6), profile (F7), zoomin (]) and zoomout ([).

With Mod Menu, the mod also writes ue4ss/Mods/RuneUI/config.txt, the copy of the page settings. Do not edit it.

The mod does not use the network and does not start other programs.

MORE

Rune UI is free to use, and its code is open to read. You may change it and send your change to the author. You may not upload it again, publish a changed version, or use parts of it in another mod without the written permission of the author. See LICENSE.txt.

Created using intellectual property belonging to Jagex Limited under the terms of Jagex's Fan Content Policy. This content is not endorsed by or affiliated with Jagex.
