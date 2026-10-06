-- The element list of the mod and its starting layout: plain data, no game calls. main.lua loads this file, gives the
-- list to layout.lua and adds the working fields of each element (its move, its size, its widgets).
-- List: the elements, in the order of the rows in the settings file. Defaults: the starting layout, by element id.

-- One entry per movable thing. A widget belongs to one entry only, so nothing moves twice. The position math and
-- the meaning of Center, Size, A, Full, Inside and Follows are in layout.lua. Positions are in HUD units, as on a
-- 16:9 screen (1920x1080 units at any resolution).
-- Center, Size: measured 27-09-2026 from screenshots and slots. A: from the slots (probe of 29-09-2026).
-- Custom: an element the mod draws itself ("avatar", "map", "cooldowns", "questtracker", "party") or a plain switch (IsSwitch).
-- PathEnds/UseParent: for shared classes, keep only widgets whose path matches, then climb N parents.
-- Child: move only this named child of the widget's root, not the whole widget.
local Elements = {
    { Id="vitals",   Name="Health, stamina and shield bars", Classes={"WBP_HUD_PlayerVitalsBars_C"},
      Full=true, A={0.5,1}, Center={X=952, Y=967}, Size={X=330, Y=75}, Below=36 },   -- Below: the line and Rune XP's row
    { Id="avatar",   Name="Level badge",                     Custom="avatar",
      Inside="vitals", A={0.5,1}, Center={X=744.5, Y=967}, Size={X=69, Y=69} },
    { Id="weapon",   Name="Weapon effect",                   Classes={"WBP_HUD_WeaponEnhancements_C"},
      Inside="vitals", A={0.5,1}, Center={X=1316, Y=911}, Size={X=44, Y=44} },
    -- the area effects (Scorch, Imarus' gaze) sit in the row above the bars; with the bars at the top of the
    -- screen that row is off screen, so they move on their own. Centre read from in-game screenshot, 27-09-2026.
    { Id="region",   Name="Area effects (Scorch, Imarus)",  Classes={"WBP_ImarusGazeRadial_C", "WBP_RegionEffectRadial_C"},
      Inside="vitals", A={0.5,1}, Center={X=952, Y=911}, Size={X=44, Y=44} },
    { Id="survival", Name="Food, water and rest rings",          Classes={"WBP_SurvivalCore_Upkeep_C"},
      Inside="vitals", A={0,1}, Center={X=158, Y=968}, Size={X=215, Y=95} },
    -- the drink ring, inside the food rings' widget. Follows: it stays beside the rings wherever they go (with Inside
    -- it stayed at its own default spot, far from moved rings; seen 01-10-2026). Centre: right of the rest ring, level
    -- with the rings (243 units right of the water ring).
    -- It also holds the food and potion buffs: the same kind of entry, in lists beside the drink's (buffs.lua).
    { Id="drink",    Name="Buff rings (drink, food, potion)",  Classes={"WBP_HUD_DrinkBuffListEntry_C", "WBP_HUD_FoodBuffListEntry_C", "WBP_HUD_PotionBuffListEntry_C"},
      Follows="survival", A={0,1}, Center={X=328, Y=958}, Size={X=50, Y=50} },
    { Id="toolbar",  Name="Tool bar",                       Classes={"WBP_Inventory_QuickAccesBar_C"},
      A={0,0}, Center={X=330, Y=110}, Size={X=545, Y=62} },
    -- Redraw: the strip with the letters is in a box that the game draws once and then only on request (probe of
    -- 04-10-2026). Drawn while the compass was unseen, it stayed empty: the marks showed, the strip did not.
    { Id="compass",  Name="Compass",                        Classes={"WBP_HUD_Compass_C"},
      Full=true, A={0.5,0}, Center={X=960, Y=86}, Size={X=600, Y=120}, Redraw="CompassRetainerBox" },
    -- no element for the MiniMap addon's map: the big map (M) and RuneMap's own map are of the same class,
    -- so hiding that element would hide both
    { Id="runemap",  Name="Minimap (RuneMap)",                      Custom="map",
      A={1,0}, Center={X=1792, Y=128}, Size={X=224, Y=224} },
    -- no widget of its own: hiding it in the editor turns the creature diamonds on RuneMap off
    { Id="creatures", Name="Creatures on the minimap",         Custom="creatures",
      A={1,0}, Center={X=1792, Y=128}, Size={X=40, Y=40} },
    -- no widget of its own either: showing it shows the game's icons beside the bars (hidden at first)
    { Id="baricons", Name="Icons beside the bars",          Custom="baricons",
      A={0,0}, Center={X=110, Y=60}, Size={X=30, Y=70} },
    -- no widget of its own either: shown, the HUD fades when nothing happens (immersive.lua; off at first)
    { Id="immersive", Name="Immersive mode (fades when idle)", Custom="immersive",
      A={0,0}, Center={X=960, Y=540}, Size={X=40, Y=40} },
    -- no widget of its own either: shown, the aim marks are gold and the lock-on orb is our diamond (aim.lua)
    { Id="aim",      Name="Crosshair and lock-on",          Custom="aim",
      A={0,0}, Center={X=960, Y=540}, Size={X=40, Y=40} },
    { Id="daynight", Name="Day and night dial",          Classes={"WBP_HUD_DayAndNight_C"},
      NoClip=true, Opaque=true, A={1,0}, Center={X=1698, Y=80}, Size={X=52, Y=52} },
    { Id="buffs",    Name="Buffs and debuffs",                         Classes={"WBP_HUD_EffectsDisplayLists_C"},
      Full=true, A={0,1}, Center={X=151, Y=871}, Size={X=200, Y=85}, Sample="Buffs and debuffs" },
    { Id="notify",   Name="All notices (group)",                 Classes={"WBP_HUD_Notifications_C"},
      Full=true, A={0.5,0.5}, Center={X=960, Y=540}, Size={X=400, Y=200} },
    { Id="xp",       Name="XP circle",                      Classes={"WBP_Notifications_ExperienceProgressContainer_C"},
      Inside="notify", A={0.5,0}, Center={X=960, Y=130}, Size={X=120, Y=95} },
    -- no widget of its own: shown, the XP is under the bars (xp.lua); hidden, the game's circle is back
    { Id="runexp",   Name="Rune XP (XP under the bars)",    Custom="runexp",
      A={0,0}, Center={X=265, Y=125}, Size={X=330, Y=18} },
    -- no widget of its own: shown, a level up shows under the bars in Rune XP's row and the game's banner is unseen
    -- (xp.lua); hidden, the game's banner is back. On at first. Off too while "Rune XP" is hidden.
    -- Sample: a text that the editor draws inside the mark of an element that shows nothing while F9 is open
    { Id="slimlevel", Name="Slim level up (under the bars)", Custom="slimlevel",
      A={0,0}, Center={X=265, Y=125}, Size={X=330, Y=18}, Sample="Level up" },
    -- no widget of its own: shown, the damage numbers over enemies have the mod's look and a critical hit pops (combattext.lua);
    -- hidden, the game's numbers are back. On at first.
    { Id="combattext", Name="Combat text (damage numbers)", Custom="combattext",
      A={0,0}, Center={X=960, Y=540}, Size={X=40, Y=40} },
    { Id="xpfloat",  Name="XP numbers",                    Classes={"WBP_FloatingExperienceContainer_C"},
      Inside="notify", A={0.5,0}, Center={X=860, Y=551}, Size={X=110, Y=40} },
    -- Idle: its render opacity when no notice shows, 0 (README, the slim level up). The slim row reads any opacity above 0.02 as a notice.
    { Id="levelup",  Name="Level up notice",                      Classes={"WBP_LevelUpNotification_C"}, Idle=0,
      Inside="notify", A={0.5,0.5}, Center={X=960, Y=300}, Size={X=500, Y=150} },
    { Id="area",     Name="New area notice",                      Classes={"WBP_AreaUnlockNotification_C"},
      Inside="notify", A={0.5,0.5}, Center={X=960, Y=250}, Size={X=700, Y=160} },
    -- The other banners of the same queue (probe of 05-10-2026): they come at the place of the level up notice, one
    -- at a time, so one row moves them all.
    { Id="banners",  Name="Other big notices",                    Classes={"WBP_NewSkillNotification_C", "WBP_MilestoneMaterialNotification_C",
        "WBP_ArenaNotification_C", "WBP_LevelUpVendorNotification_C", "WBP_FishCaughtNotification_C",
        "WBP_FinalBoss_DefeatedNotification_C", "WBP_FinalBoss_ExtractionPointUnlockNotification_C"},
      Inside="notify", A={0.5,0.5}, Center={X=960, Y=390}, Size={X=520, Y=200} },
    -- Two more queues of the notices widget. The warning: 70 above the middle in a box of 775 x 152 (the game's
    -- files). The tip: its centre and size come from a screenshot of the shown tip, not from the slot.
    { Id="upkeep",   Name="Hunger, thirst and rest warning",      Classes={"WBP_PlayerUpkeepNotification_C"},
      Inside="notify", A={0.5,0.5}, Center={X=960, Y=470}, Size={X=775, Y=152} },
    { Id="tips",     Name="Tutorial tips",                        Classes={"WBP_TutorialNotifications_C"},
      Inside="notify", A={0,0.6}, Center={X=405, Y=600}, Size={X=700, Y=150} },
    { Id="banner",   Name="Title banner",                  Classes={"WBP_TitleBannerWidget_C"},
      A={0.5,0.5}, Center={X=960, Y=300}, Size={X=600, Y=120} },
    { Id="saving",   Name="Saving icon",                    Classes={"WBP_SavingSpinner_C"},
      A={1,0}, Center={X=1738, Y=156}, Size={X=64, Y=64} },
    -- Size: one entry is 440 wide (its header and its boxes, the game's files). OnlyY: the panel is made for the
    -- right edge, so it stays there at its own size and moves only up and down (seen in the game, 02-10-2026).
    { Id="quests",   Name="Quests and unlocks",                        Classes={"WBP_QuestAndUnlocks_C"},
      Inside="notify", OnlyY=true, A={1,0.5}, Center={X=1700, Y=420}, Size={X=440, Y=160} },
    -- The list of picked-up items hangs at the right edge, its top right corner at the middle of the screen's height
    -- (anchors 1, 0.5; top -40; alignment 1, 0; probe of 02-10-2026), right under the quests' box. Its own frame is in
    -- the middle of the screen, and a smaller "notify" pulled it there (seen in the game, 02-10-2026).
    -- Size: one notice is about 350 wide and 43 high (screenshot of 02-10-2026), three in the box.
    { Id="pickups",  Name="Picked-up items",                 Classes={"WBP_ItemPickups_C"},
      Inside="notify", A={1,0.5}, Center={X=1740, Y=565}, Size={X=360, Y=130} },
    -- The death screen (probe of 02-10-2026), made by the game at the first death: BackgroundBlur > Overlay_0
    -- > [Background, the bar, "You Died", "Killed By", the cause, the timer, ..], all in the middle. The element is
    -- Overlay_0, not the widget: the blur keeps the whole screen. KeepFull: the dark Background still fills it.
    -- It starts at the game's size; the player can make it smaller in F9. NoHide: it cannot
    -- be hidden, as the blur would stay over the screen with nothing on it.
    { Id="death",    Name="Death screen",                   Classes={"WBP_HUD_Death_C"},
      Child="Overlay_0", Deep=true, KeepFull="Background", NoHide=true, Full=true, A={0.5,0.5}, Center={X=960, Y=540}, Size={X=700, Y=320} },
    { Id="prompts",  Name="Interaction prompts",                Classes={"WBP_HeldActionWidget_C", "WBP_HUD_InteractionPrompt_C", "WBP_CallToActionWidget_C"},
      A={0.5,0.5}, Center={X=960, Y=640}, Size={X=300, Y=60} },
    { Id="armor",    Name="Armor damage warning",                 Classes={"WBP_ArmourDurabilityDisplay_C"},
      A={0,0}, Center={X=960, Y=540}, Size={X=200, Y=60} },
    { Id="itembrk",  Name="Broken item warning",            Classes={"WBP_Notification_ItemBreak_C"},
      Inside="notify", A={0.5,0.5}, Center={X=960, Y=580}, Size={X=100, Y=30} },
    -- The notice for where you are and how you are (Cosy at home, Sheltered): in the game's notice box it is tied to the
    -- middle of the screen, 135 units up (the game's widget tree, 05-10-2026). Its band is 775 by 57 units in the game's files.
    { Id="status",   Name="Status notices (cosy, sheltered)", Classes={"WBP_EnvAndPlayerStatus_C"},
      Inside="notify", A={0.5,0.5}, Center={X=960, Y=405}, Size={X=775, Y=57} },
    { Id="menuico",  Name="Menu icons",                     Classes={"WBP_HUD_CompositeVariableMenu_C"},
      Full=true, A={1,1}, Center={X=1668, Y=975}, Size={X=380, Y=95} },
    -- Parts: hiding it hides only the prompts, not the menu buttons that live inside it (see ApplyOne)
    { Id="legend",   Name="Combat key hints",               Classes={"WBP_HUD_InputsLegend_C"},
      Parts=true, Full=true, A={1,1}, Center={X=1780, Y=760}, Size={X=280, Y=200} },
    -- chat, map, spell book, building and bag: the row under the prompts, in rings (menubuttons.lua).
    -- Deep: the row is three levels down the legend's world page (probe of 29-09-2026).
    { Id="menubtn",  Name="Menu shortcuts",                 Classes={"WBP_InputLegend_World_C"},
      Child="HorizontalBox_436", Deep=true, Inside="legend", A={1,1}, Center={X=1659, Y=953}, Size={X=395, Y=123} },
    -- our own tiles, one per recovering spell (cooldowns.lua): left, middle height.
    -- Size: cooldowns.lua's box of six tiles. Turn: the box swaps width and height while the next switch is on.
    { Id="cooldowns", Name="Spell cooldowns",               Custom="cooldowns", Turn="cdhoriz",
      A={0,0.5}, Center={X=70, Y=540}, Size={X=60, Y=400} },
    -- no widget of its own: shown, the cooldown tiles are in a row, the newest at the right end (cooldowns.lua; off at
    -- first). It sits in the same list group as the tiles.
    { Id="cdhoriz",  Name="Spell cooldowns: horizontal",   Custom="cdhoriz",
      Hint="Ins and Del turn it on and off. To move or resize the tiles, select Spell cooldowns.",
      A={0,0.5}, Center={X=70, Y=540}, Size={X=40, Y=40} },
    -- our own text under the minimap, at the top right (questtracker.lua): the main quest and the tracked one. Size:
    -- its box. Centre: its right edge on the minimap's right edge (1904), its top 12 units under the minimap's box.
    { Id="questtracker", Name="Quest tracker",              Custom="questtracker",
      A={1,0}, Center={X=1754, Y=307}, Size={X=300, Y=110} },
    -- no widget of its own: shown, the tracker also lists the next steps of a quest with a clean list (off at first)
    { Id="questnext", Name="Quest tracker: next steps",     Custom="questnext",
      A={0,0}, Center={X=960, Y=540}, Size={X=40, Y=40} },
    -- our own rows for the other players of a co-op world, top left under the bars (party.lua): the name and a health
    -- bar for each. Size: its box of five rows. Centre: its left edge at 42 units, its top at 146, under the bars and
    -- clear of the row of Rune XP (a level up grows that row to about 145).
    { Id="party",    Name="Party panel (friends' health)",  Custom="party",
      A={0,0}, Center={X=154.5, Y=301}, Size={X=225, Y=310} },
    { Id="wheel",    Name="Tool wheel hint",                Classes={"WBP_DomInputIconWidget_C"},
      PathEnds={"WBP_Inventory_MainPanel_C_%d+%.WidgetTree_%d+%.RadialKBM$"}, UseParent=3,
      A={0,0}, Center={X=638, Y=120}, Size={X=30, Y=60} },
    -- the rune and arrow count of the staff and the bow: only its box moves, the crosshair stays in the middle
    -- (the reticles' trees, read in game 27-09-2026: VerticalBox_0 holds the ammo name and the count)
    { Id="ammo",     Name="Arrow and rune count",                  Classes={"WBP_ReticleMagic_C", "WBP_ReticleRangedADS_C"},
      Child="VerticalBox_0", NoClip=true, A={0.5,0.5}, Center={X=840, Y=551}, Size={X=262, Y=34} },   -- name, disk, count
}

-- Starting layout: bars and buffs top left, compass 85%, food and water centred above the tool bar, saving animation bottom right.
local Defaults = {
    vitals={X=-699, Y=-907, Scale=0.9},
    avatar={X=-678, Y=-907, Scale=0.9},   -- left of the bars, same height as the three bars
    weapon={X=-771, Y=-851, Scale=0.9},   -- right after the end of the bars
    region={X=-359, Y=-851, Scale=0.9},   -- next to the weapon buff
    survival={X=802, Y=3, Scale=0.72},
    buffs={X=0, Y=-735},
    compass={Scale=0.85},
    daynight={X=42, Y=-29, Visible=false},   -- RuneMap's ring is the clock; the dial stays alive, unseen
    toolbar={X=628, Y=925},
    notify={X=0, Y=-20},
    -- at the right edge, above the middle, over the list of picked-up items
    quests={Y=-60},
    xp={Y=55},
    levelup={Y=60, Scale=0.9},
    area={Y=40, Scale=0.85},
    saving={X=130, Y=750, Scale=0.8},
    ammo={X=250, Y=420},   -- right of the food and water rings, above the tool bar
    prompts={X=0, Y=-10}, armor={X=0, Y=-10}, itembrk={X=0, Y=-10}, status={X=0, Y=-20}, menuico={X=0, Y=-40},
    -- the same Y as "notify"
    banners={Y=-20}, upkeep={Y=-20}, tips={Y=-20},
    legend={Visible=false}, wheel={Visible=false}, baricons={Visible=false}, immersive={Visible=false, Wait=8},
    -- 140 under the middle, clear of the party panel; a saved layout keeps its own place
    cooldowns={Y=140},
    questnext={Visible=false}, cdhoriz={Visible=false},
}

return { List = Elements, Defaults = Defaults }
