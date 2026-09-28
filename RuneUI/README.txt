Rune UI
A UE4SS Lua mod for RuneScape: Dragonwilds.
Move, resize and hide every part of the HUD, right in the game. With a new map, new rings and new bars in the game's own style.

INSTALL

Rune UI needs the experimental build of UE4SS. The CurseForge app installs UE4SS 3.0.1 for Dragonwilds. At the moment, that version does not start with the game, so no mod runs.

1. Download the zip whose name starts with "UE4SS_v3.0.1-" from the UE4SS experimental release: https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/experimental-latest
   Do not use the "zDEV" zip.
2. Copy dwmapi.dll and the ue4ss folder from the zip into RSDragonwilds\Binaries\Win64. Replace the old files.
3. Copy the RuneUI folder to Win64\ue4ss\Mods\. Keep the folder name RuneUI: the mod finds its pictures by that name.
4. Start the game. The enabled.txt file in the folder turns the mod on.

If Rune UI does not show, open Win64\ue4ss\UE4SS.log. If the log shows "Fatal Error", UE4SS is the old version. Do steps 1 and 2 again.

When the CurseForge app installs or removes a mod, it can put UE4SS 3.0.1 back. If your mods stop working after that, do steps 1 and 2 again.

Other mods that change the HUD can conflict with Rune UI. Two mods that move the same part of the HUD fight each other.

If you used this mod before version 0.60, when its name was HudEditor: remove the HudEditor folder and the "HudEditor : 1" line in mods.txt. Rune UI reads your saved layout and map zoom from the old files.

KEYS

Press F9 in the game. A panel on the left shows the keys and every element. The selected element blinks and gets a gold frame with its name.

PgUp / PgDn       select an element
Arrows            move the element
Home / End        change the move step (1 to 100)
+ / -             change the size, 5% per press
Delete / Insert   hide / show the element
Backspace         reset the element to the starting layout
F9                save and close the editor
] / [             zoom RuneMap in / out (this works outside the editor too)

Beside the bars, the mod shows your level in the game's green diamond. To show your own picture there, put an avatar.png in the RuneUI folder.

FILES THAT THE MOD WRITES (IN WIN64)

runeui_layout.txt    the saved layout
runeui_menuart.txt   the pictures and the font of the main menu, for the editor panel
runeui_mapzoom.txt   the zoom of RuneMap

When the game starts, the mod also writes its pictures into its own Art folder. It writes a picture only when it is missing or different.

The mod does not use the network and does not start other programs.

MORE

Pictures, details and the source code: https://github.com/jevticivan/rune-ui
The code of Rune UI is under the MIT licence. See LICENSE.txt.

Created using intellectual property belonging to Jagex Limited under the terms of Jagex's Fan Content Policy. This content is not endorsed by or affiliated with Jagex.
