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
6. Start the game and press F9. After a fresh install, a hint about F9 shows once, in the first world.

Mods that change the HUD can conflict with Rune UI.

If you used HudEditor before version 0.60, remove the HudEditor folder and the "HudEditor : 1" line in mods.txt.

Rune UI does not show?

Open Win64\ue4ss\UE4SS.log. If it says "Fatal Error" or "timer: old UE4SS", do steps 1 to 4 again. The CurseForge app can put the old UE4SS back when it changes a mod.

KEYS

F9 opens the layout editor. It moves, resizes and hides the parts of the HUD.

PgUp, PgDn                        select an element
Arrows                            move it
Home, End                         change the move step (1 to 100)
+ / -                             change the size by 5%
, / .                             change the opacity by 10% (100% to 20%)
Delete, Insert                    hide, show it
Backspace                         reset it
F7                                save, go to the next profile (1, 2, 3)
F5                                Rune Skin
F8                                Rune Map settings
F6                                immersive mode settings
F9                                save and close
] / [                             zoom Rune Map in / out (also outside it)

A layout that hid the group of all notices in an older version has the row "All notices (group)". Press Insert on it to show the notices again.

Rune Skin (F5), Rune Map settings (F8) and immersive mode settings (F6):

Up, Down                          select a setting
Left, Right                       change it
Backspace                         reset the settings of the panel
] / [                             zoom Rune Map
F9                                go to the layout editor
F5, F8, F6                        save and close

Wheels                            Spell, item and emote wheels as rings. Off: the game's wheels. On at first.
Combat text                       Bigger damage numbers. On at first.
XP under the bars                 XP bar under the bars. Off: the game's XP circle. On at first.
Small level up notice             Level up under the bars. Off: the game's banner. On at first.
Gold crosshair and lock-on        Gold aim marks. On at first.
Day and night icon                The day and night dial as a sun and moon icon. Off: the game's dial. On at first.
Game icons beside the bars        Shows them. Off at first.
Spell cooldowns in a row          Tiles in a row. Off at first.
Next quest steps                  Up to three next steps in the quest tracker. Off at first.

Rune Map                          Off: no map.
Faces north                       On: north stays at the top.
North mark                        A mark shows north.
Player name                       Off: hides your name on the maps.
Creatures                         All, Enemies only (at first), Off.
Ore, Herbs, Essence, Rare trees   A map mark for each. On at first.
Keep in immersive mode            What stays: Nothing (at first), Map or Compass.
Zoom                              Same as [ and ].
Map refresh                       Every 2nd frame (at first). Every frame: smoother. Every 4th frame: lightest.

Immersive mode                    On: the HUD fades when nothing happens. Off at first.
Wait before the fade              3 to 30 s, 8 at first.
Crosshair in immersive mode       Show (at first) or Aim only: no dot except while you aim.
Immersive camera                  On: a closer camera, with or without immersive mode. Off at first.
Walk distance                     100 to 1500 cm, 300 at first.
Side offset                       0 to 200 cm, 90 at first.
Sprint distance                   100 to 1500 cm, 900 at first.
Melee distance                    100 to 1500 cm, 200 at first.
Ranged distance                   100 to 1500 cm, 500 at first.
Hold after a fight                0 to 30 s, 8 at first.

In immersive mode, a survival ring shows while its need is orange or red, and for a moment when it fills.

Other parts:

Enemy and boss bars               One colour. Always on.
Quest tracker                     Under Rune Map.
Day and night dial                Hidden at first, as the ring of Rune Map is the clock. Show it in F9 to see the time as an icon.
Party panel                       Friends in co-op. On at first.
Arrow and rune count              The count only. The crosshair stays.
Level badge and avatar.png        Put avatar.png in the RuneUI folder for your picture.
Gamepad                           Buttons in menus.

Mod Menu page: press Esc, MODS, Rune UI. It holds the keys and the settings of the four panels.

FILES THAT THE MOD WRITES (IN WIN64)

runeui.txt                    Every setting; delete a line to get its default
ue4ss/Mods/RuneUI/Art         The pictures, written when one is missing or changed
ue4ss/Mods/RuneUI/config.txt  With Mod Menu, the copy of the page settings; do not edit it

Change seven keys in the [keys] part of runeui.txt: editor (F9), skin (F5), map (F8), camera (F6), profile (F7), zoomin (]) and zoomout ([). A key is F1 to F12, a letter, a digit, Insert, Delete, Home, End, PgUp, PgDn, [ or ]. A changed key works after a restart.

The mod does not use the network and does not start other programs.

MORE

Rune UI is free to use, and its code is open to read. You may change it and send your change to the author. You may not upload it again, publish a changed version, or use parts of it in another mod without the written permission of the author. See LICENSE.txt.

Created using intellectual property belonging to Jagex Limited under the terms of Jagex's Fan Content Policy. This content is not endorsed by or affiliated with Jagex.
