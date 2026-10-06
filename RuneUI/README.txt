Rune UI
A UE4SS Lua mod for RuneScape: Dragonwilds.
Move, resize, fade and hide every part of the HUD, right in the game. With a new map, new rings and new bars in the game's own style.

INSTALL

The CurseForge app installs UE4SS 3.0.1, which does not start with the game. Use the newer build:

1. Go to the UE4SS experimental release on GitHub: https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/experimental-latest
2. Download the zip whose name starts with "UE4SS_v3.0.1-". Do not use the zDEV zip.
3. Open the game folder: Steam\steamapps\common\RSDragonwilds\RSDragonwilds\Binaries\Win64
4. Copy dwmapi.dll and the ue4ss folder from the zip into Win64. Replace the old files.
5. Copy the RuneUI folder into Win64\ue4ss\Mods. Keep the name RuneUI.
6. Start the game and press F9.

Mods that change the HUD can conflict with Rune UI.

If you used HudEditor before version 0.60, remove the HudEditor folder and the "HudEditor : 1" line in mods.txt.

Rune UI does not show?

Open Win64\ue4ss\UE4SS.log. If it says "Fatal Error" or "timer: old UE4SS", do steps 1 to 4 again. The CurseForge app can put the old UE4SS back when it changes a mod.

KEYS

F9 opens the editor.

PgUp, PgDn                        select an element
Arrows                            move it
Home, End                         change the move step (1 to 100)
+ / -                             change the size by 5%
, / .                             change the opacity by 10% (100% to 20%)
Delete, Insert                    hide, show it
Backspace                         reset it
F7                                save, go to the next profile (1, 2, 3)
F8                                map settings
F6                                camera settings
F9                                save and close
] / [                             zoom RuneMap in / out (also outside it)

Map settings (F8) and camera settings (F6):

Up, Down                          select a setting
Left, Right                       change it
Backspace                         reset the settings
] / [                             zoom RuneMap
F9                                go to the editor
F8, F6                            save and close

RuneMap                           Off: no map.
Faces north                       On: north stays at the top.
North mark                        A mark shows north.
Player name                       Off: hides your name on the maps.
Creatures                         All, Enemies only (at first), Off.
Ore, Herbs, Essence, Rare trees   A map mark for each. On at first.
In immersive mode                 What stays: Nothing (at first), Map or Compass.
Zoom                              Same as [ and ].
Drawing                           Faster (at first): every second frame. Smooth: every frame.

Immersive camera                  On: a closer camera, only in immersive mode. Off at first.
Walk distance                     100 to 1500 cm, 300 at first.
Side offset                       0 to 200 cm, 90 at first.
Sprint distance                   100 to 1500 cm, 900 at first.
Melee zoom                        100 to 1500 cm, 200 at first.
Ranged zoom                       100 to 1500 cm, 500 at first.
Hold after a fight                0 to 30 s, 8 at first.
Crosshair in immersive mode       Show (at first) or Aim only: no dot except while you aim.

These editor rows switch on or off (Delete, Insert):

Rune XP                           XP bar under the bars.
Slim level up                     Level up under the bars. On at first.
Enemy and boss bars               One colour. Always on.
Combat text                       Bigger damage numbers. On at first.
Quest tracker                     Under the minimap.
Quest tracker: next steps         Up to three next steps. Off at first.
Spell cooldowns, horizontal       Tiles in a row. Off at first.
Party panel                       Friends in co-op. On at first.
Arrow and rune count              The count only. The crosshair stays.
Level badge and avatar.png        Put avatar.png in the RuneUI folder for your picture.
Icons beside the bars             Show them. Hidden at first.
Gamepad                           Buttons in menus.

The row Immersive mode (fades when idle) is off at first. + / - set its wait: 3 to 30 s, 8 at first.

Mod Menu page: press Esc, MODS, Rune UI. It holds the keys, the switches, the camera and the map settings.

FILES THAT THE MOD WRITES (IN WIN64)

runeui.txt                    Every setting; delete a line to get its default
ue4ss/Mods/RuneUI/Art         The pictures, written when one is missing or changed
ue4ss/Mods/RuneUI/config.txt  With Mod Menu, the copy of the page settings; do not edit it

Change six keys in the [keys] part of runeui.txt: editor (F9), map (F8), camera (F6), profile (F7), zoomin (]) and zoomout ([). A key is F1 to F12, a letter, a digit, Insert, Delete, Home, End, PgUp, PgDn, [ or ]. A changed key works after a restart.

The mod does not use the network and does not start other programs.

MORE

Rune UI is free to use, and its code is open to read. You may change it and send your change to the author. You may not upload it again, publish a changed version, or use parts of it in another mod without the written permission of the author. See LICENSE.txt.

Created using intellectual property belonging to Jagex Limited under the terms of Jagex's Fan Content Policy. This content is not endorsed by or affiliated with Jagex.
