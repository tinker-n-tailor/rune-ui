-- Rune UI: move, resize and hide parts of the Dragonwilds HUD, with a new minimap, survival rings and bars.
-- F9 opens the editor, F8 the map settings, F6 the camera settings. A timer applies the layout; gold corners mark the selected element.

local VERSION = "1.9"

local function Log(msg) print("[RuneUI] " .. msg .. "\n") end
Log("starting " .. VERSION)

-- The mod's own folder, for its pictures and files. By the full path UE4SS loaded this file from, when a file
-- opens through it: the short path counts from the folder the game was started in, and on a player's machine
-- the pictures did not load through it (report of 03-10-2026). The short path stays as the fallback.
RUNEUI_DIR = "ue4ss/Mods/RuneUI/"
do
    local ok, dir = pcall(function() return string.match(debug.getinfo(1, "S").source, "^@(.*[/\\])[Ss]cripts[/\\]main%.lua$") end)
    local f = ok and dir and io.open(dir .. "Scripts/main.lua", "r")
    if f then f:close() RUNEUI_DIR = dir end
    Log("mod folder: " .. RUNEUI_DIR)
end

-- Every part lives in its own file: an error in one is logged and the rest of the mod still runs. UE4SS finds
-- them by module name; the path is the fallback.
-- Parts: each has Tick(ctx) and Forget(sameWorld). The step calls them in this order (AddPart), the world watch
-- their Forget. Early: its step runs before the 20 s start wait too.
local Parts = {}
local function AddPart(name, M, ctx, early)
    if M then Parts[#Parts + 1] = { Name = name, M = M, Ctx = ctx, Early = early } end
end
local function LoadPart(name)
    local ok, m = pcall(require, name)
    if not ok then
        local ok2, m2 = pcall(dofile, RUNEUI_DIR .. "Scripts/" .. name .. ".lua")
        if ok2 then ok, m = true, m2 else m = tostring(m) .. " | " .. tostring(m2) end
    end
    if ok and type(m) == "table" then Log(name .. " file loaded") return m end
    Log(name .. " file not loaded: " .. tostring(m))
end


-- The widgets the mod adds into the game's own widgets get a new name each round (a round ends when the
-- player restarts or the world changes): making an object with the name of a live one makes the engine
-- replace it in place, which crashed the game on entering a world (27-09-2026).
local Gen = 1
local NameCount = 0
-- Every call gives a new name, so a second try in the same round never reuses the name of a live object.
local function Uniq(name) NameCount = NameCount + 1 return name .. "_" .. Gen .. "_" .. NameCount end
local function G(name) return FName(Uniq(name)) end

-- A part that fails (the map, the avatar, the bars, the editor panel) is tried again 10 s later, 3 times at most
-- in one round. A new round (a new world or a respawn) gives it new tries.
local function MayTry(P) return (P.Fails or 0) < 3 and os.clock() >= (P.RetryAt or 0) end
local function Failed(P) P.Fails, P.RetryAt = (P.Fails or 0) + 1, os.clock() + 10 end

-- The world watch (near the main loop) fills these; they are declared here because the editor panel reads them too.
local LastController = nil   -- the local player controller's name; "" while a world is loading
local LocalPlayer = nil         -- the local player object lives as long as the game; the quest tracker reads its controller
local SettleUntil = 0        -- no decorating or building until the new world has settled (os.clock)

-- Our widgets from an earlier round, still inside a game widget: take them out before adding new ones. Only
-- called while that game widget is alive and on screen.
local function ClearOurs(panel, prefix)
    pcall(function()
        for i = panel:GetChildrenCount() - 1, 0, -1 do
            local c = panel:GetChildAt(i)
            if c and string.find(c:GetFName():ToString(), prefix, 1, true) == 1 then c:RemoveFromParent() end
        end
    end)
end

-- One entry per movable thing. A widget belongs to one entry only, so nothing moves twice. The position math and
-- the meaning of Center, Size, A, Full, Inside and Follows are in layout.lua. Positions are in HUD units, as on a
-- 16:9 screen (1920x1080 units at any resolution).
-- Center, Size: measured 27-09-2026 from screenshots and slots. A: from the slots (the HUD log of 29-09-2026).
-- Custom: an element the mod draws itself ("avatar", "map", "cooldowns", "clock", "questtracker", "party") or a plain switch (IsSwitch).
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
    -- the drink ring, inside the food rings' widget (1.3, playtest: "make it movable and scalable"). Follows: it stays
    -- beside the rings wherever they go (as Inside it stayed at its own default spot, far from rings he had moved:
    -- in game 01-10-2026). Centre: right of the rest ring, level with the rings (measured in game: 243 units right
    -- of the water ring).
    -- Since 1.5 also the food and potion buffs: the same kind of entry, in lists beside the drink's (buffs.lua).
    { Id="drink",    Name="Buff rings (drink, food, potion)",  Classes={"WBP_HUD_DrinkBuffListEntry_C", "WBP_HUD_FoodBuffListEntry_C", "WBP_HUD_PotionBuffListEntry_C"},
      Follows="survival", A={0,1}, Center={X=328, Y=958}, Size={X=50, Y=50} },
    { Id="toolbar",  Name="Tool bar",                       Classes={"WBP_Inventory_QuickAccesBar_C"},
      A={0,0}, Center={X=330, Y=110}, Size={X=545, Y=62} },
    -- Redraw: the strip with the letters is in a box that the game draws once and then only on request (probe K2,
    -- 04-10-2026). Drawn while the compass was unseen, it stayed empty: the marks showed, the strip did not.
    { Id="compass",  Name="Compass",                        Classes={"WBP_HUD_Compass_C"},
      Full=true, A={0.5,0}, Center={X=960, Y=86}, Size={X=600, Y=120}, Redraw="CompassRetainerBox" },
    -- no element for the MiniMap addon's map any more: RuneMap replaces it, and the big map (M) and RuneMap's
    -- own map are of the same class, so hiding that element hid them too (27-09-2026)
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
    -- our own icon, right of the tool bar: the time of day while immersive mode is on (clock.lua; sketch of 01-10-2026)
    -- Off (playtest, 03-10-2026: the sun and moon icon goes; the code stays for a later look). Its part is off below too.
    -- { Id="clock",    Name="Day and night icon",            Custom="clock",
    --   A={0.5,1}, Center={X=1286, Y=1035}, Size={X=40, Y=40} },
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
    -- The other banners of the same queue (probe N1, 05-10-2026): they come at the place of the level up notice, one
    -- at a time, so one row moves them all.
    { Id="banners",  Name="Other big notices",                    Classes={"WBP_NewSkillNotification_C", "WBP_MilestoneMaterialNotification_C",
        "WBP_ArenaNotification_C", "WBP_LevelUpVendorNotification_C", "WBP_FishCaughtNotification_C",
        "WBP_FinalBoss_DefeatedNotification_C", "WBP_FinalBoss_ExtractionPointUnlockNotification_C"},
      Inside="notify", A={0.5,0.5}, Center={X=960, Y=390}, Size={X=520, Y=200} },
    -- Two more queues of the notices widget (1.8). The warning: 70 above the middle in a box of 775 x 152 (the game's
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
    -- right edge, so it stays there at its own size and moves only up and down (playtest, 02-10-2026).
    { Id="quests",   Name="Quests and unlocks",                        Classes={"WBP_QuestAndUnlocks_C"},
      Inside="notify", OnlyY=true, A={1,0.5}, Center={X=1700, Y=420}, Size={X=440, Y=160} },
    -- The list of picked-up items hangs at the right edge, its top right corner at the middle of the screen's height
    -- (probe 20, 02-10-2026: anchors 1, 0.5; top -40; alignment 1, 0), right under the quests' box. As a part of
    -- "notify" only, its frame was in the middle of the screen and a smaller "notify" pulled it there (playtest,
    -- 02-10-2026). Size: one notice is about 350 wide and 43 high (a screenshot of that day), three in the box.
    { Id="pickups",  Name="Picked-up items",                 Classes={"WBP_ItemPickups_C"},
      Inside="notify", A={1,0.5}, Center={X=1740, Y=565}, Size={X=360, Y=130} },
    -- The death screen (probes 24 and 25, 02-10-2026), made by the game at the first death: BackgroundBlur > Overlay_0
    -- > [Background, the bar, "You Died", "Killed By", the cause, the timer, ..], all in the middle. The element is
    -- Overlay_0, not the widget: the blur keeps the whole screen. KeepFull: the dark Background still fills it.
    -- It starts at the game's size; the player makes it smaller in F9 (playtest, 02-10-2026). NoHide: it cannot
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
    -- chat, map, spell book, building and bag: the row under the prompts, in rings (menubuttons.lua; design sketch
    -- A, 29-09-2026). Deep: the row is three levels down the legend's world page (widget dump, 29-09-2026).
    { Id="menubtn",  Name="Menu shortcuts",                 Classes={"WBP_InputLegend_World_C"},
      Child="HorizontalBox_436", Deep=true, Inside="legend", A={1,1}, Center={X=1659, Y=953}, Size={X=395, Y=123} },
    -- our own tiles, one per recovering spell (cooldowns.lua; design sketch C, 29-09-2026): left, middle height.
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

-- Starting layout: the design sketch of 27-09-2026.
-- Bars and buffs top left, compass 85%, food and water centred above the tool bar, saving animation bottom right.
local Defaults = {
    vitals={X=-699, Y=-907, Scale=0.9},
    avatar={X=-678, Y=-907, Scale=0.9},   -- left of the bars, same height as the three bars
    weapon={X=-771, Y=-851, Scale=0.9},   -- right after the end of the bars (27-09-2026: +120, it sat on the health bar)
    region={X=-359, Y=-851, Scale=0.9},   -- next to the weapon buff
    survival={X=802, Y=3, Scale=0.72},
    buffs={X=0, Y=-735},
    compass={Scale=0.85},
    daynight={X=42, Y=-29, Visible=false},   -- RuneMap's ring is the clock; the dial stays alive, unseen
    toolbar={X=628, Y=925},
    notify={X=0, Y=-20},
    -- at the right edge, above the middle, over the list of picked-up items (playtest, 02-10-2026)
    quests={Y=-60},
    xp={Y=55},
    levelup={Y=60, Scale=0.9},
    area={Y=40, Scale=0.85},
    saving={X=130, Y=750, Scale=0.8},
    ammo={X=250, Y=420},   -- right of the food and water rings, above the tool bar
    prompts={X=0, Y=-10}, armor={X=0, Y=-10}, itembrk={X=0, Y=-10}, status={X=0, Y=-20}, menuico={X=0, Y=-40},
    -- as "notify", so they start where 1.7 drew them
    banners={Y=-20}, upkeep={Y=-20}, tips={Y=-20},
    legend={Visible=false}, wheel={Visible=false}, baricons={Visible=false}, immersive={Visible=false, Wait=8},
    -- 140 under the middle, clear of the party panel; a saved layout keeps its own place
    cooldowns={Y=140},
    questnext={Visible=false}, cdhoriz={Visible=false},
}

-- The position math lives in layout.lua (tested without the game); these are its names, used all over this file.
local Layout = LoadPart("layout")
if not Layout then error("layout.lua is missing or broken, see the log") end
Layout.Init(Elements)
local Hud, ById, Third, IsSwitch, OnViewport = Layout.Hud, Layout.ById, Layout.Third, Layout.IsSwitch, Layout.OnViewport
local Home, Offset, FinalCenter, LocalTransform = Layout.Home, Layout.Offset, Layout.FinalCenter, Layout.LocalTransform
local Retarget, TargetFromSpot, ScreenBox, Spot, Area = Layout.Retarget, Layout.TargetFromSpot, Layout.ScreenBox, Layout.Spot, Layout.Area
local AREAS = Layout.AREAS

for _, E in ipairs(Elements) do
    local d = Defaults[E.Id] or {}
    E.X, E.Y, E.Scale = d.X or 0, d.Y or 0, d.Scale or 1.0
    E.Visible = (d.Visible ~= false)
    E.Opacity = 1.0   -- F9 comma and period (1.1); every default is fully solid
    E.Wait = d.Wait   -- the immersive line only: seconds a part stays before it fades (+ / - there, 1.2)
    E.Instances, E.Keys = {}, {}
    E.PartsOp, E.PartsW = {}, {}   -- by widget name: its parts and the opacity last given to them (Parts elements)
    E.Last = {}                    -- by widget name: the move, size and pivot last written to it (ApplyOne)
    E.PartsLogged = false          -- false, never nil: the keys write this table on UE4SS's thread (see Moved)
    E.A = E.A or { 0, 0 }   -- a switch (no widget) needs none; the placement reads it for every element
    -- false, never nil: the arrow keys set it on UE4SS's own thread, and a new key there could grow the table
    -- while the step reads it (as runemap.lua does with its key flags)
    E.Moved = false
    TargetFromSpot(E)
end

---------------------------------------------------------------- layout file

-- When UE4SS reloads this mod while the game runs, the widgets of the previous run are still on screen.
-- Remove every widget the mod made (names start with RuneUI or RU_) before building new ones. Only once,
-- when this file loads: it used to run on every player restart too, and there it pulled widgets out of a
-- world that was being unloaded (the crash on quitting to the menu, 27-09-2026).
pcall(function()
    local removed = 0
    for _, cls in ipairs({ "UserWidget", "SizeBox", "Overlay", "CanvasPanel", "Image", "Border" }) do
        for _, W in pairs(FindAllOf(cls) or {}) do
            pcall(function()
                local n = W:GetFName():ToString()
                if string.find(n, "^RuneUI") or string.find(n, "^RU_") then
                    W:RemoveFromParent()
                    removed = removed + 1
                end
            end)
        end
    end
    if removed > 0 then Log("reload: removed " .. removed .. " widgets of the previous run") end
end)

-- One file, runeui.txt, next to the game (1.4): the three layout profiles, the profile in use, the map settings and
-- the zoom, the camera settings (1.8), and the keys. Named values, so a player can read and edit it, and a new
-- version never breaks an old file. The files of 1.3 and before are read once, when runeui.txt is missing, and are
-- left in place. settings.lua reads and writes the file (tested without the game).
local Settings = LoadPart("settings")
if not Settings then error("settings.lua is missing or broken, see the log") end
local function ReadText(name)
    local f = io.open(name, "r")
    if not f then return nil end
    local t = f:read("a")
    f:close()
    return t
end
local Cfg = Settings.Load()
if not Cfg then
    Cfg = Settings.Legacy(ReadText)
    if Cfg then Log("settings: read from the files of an older version") else Cfg = {} Log("no settings file yet, using defaults") end
end
Cfg.menuart = nil   -- the main menu's line under the bars, saved up to 1.4: the bars use a line of the game since 1.5
local ElementIds = {}   -- the order of the rows in the file: the element list
for _, E in ipairs(Elements) do ElementIds[#ElementIds + 1] = E.Id end
local function SaveCfg()
    Settings.Section(Cfg, "general").version = VERSION
    if not Settings.Save(Cfg, nil, ElementIds) then Log("could not write " .. Settings.FILE) end
end

-- The profiles (1.3): three layouts, F7 goes to the next while the editor is open. Profile 1 is the layout every
-- earlier version wrote, so no player loses a layout. N: the profile in use. Wanted: F7 sets it on UE4SS's thread,
-- and the step switches.
local Prof = { N = 1, Wanted = false }
Prof.N = math.floor(Settings.Num(Settings.Section(Cfg, "general").profile, 1, 3, 1))

-- the layout of the profile in use, from the file; an element without a row keeps what it has
local function LoadLayout()
    local rows = Cfg["layout " .. Prof.N]
    if not rows then Log("profile " .. Prof.N .. ": no saved layout, using defaults") return end
    local N = Settings.Num
    for _, E in ipairs(Elements) do
        local r = rows[E.Id]
        if type(r) == "table" then
            E.X, E.Y = N(r.x, -4000, 4000, 0), N(r.y, -4000, 4000, 0)
            E.Scale = N(r.scale, 0.3, 4.0, 1.0)
            E.Visible = E.NoHide or N(r.visible, 0, 1, 1) == 1
            E.Opacity = math.floor(N(r.opacity, 0.2, 1.0, 1.0) * 10 + 0.5) / 10
            -- the edge it follows; a row without it (a file of 1.1 or older): from where it sits
            if r.edgex ~= nil and r.edgey ~= nil then E.TX, E.TY = Third(N(r.edgex, 0, 1, 0.5), 1), Third(N(r.edgey, 0, 1, 0.5), 1)
            else TargetFromSpot(E) end
            if E.Wait and r.wait ~= nil then E.Wait = math.floor(N(r.wait, 3, 30, E.Wait) + 0.5) end
            if E.OnlyY then E.X, E.Scale, E.TX = 0, 1.0, 1 end   -- a layout saved before it was OnlyY
        end
    end
    Log("layout loaded, profile " .. Prof.N)
end

local function SaveLayout()
    local rows = Settings.Section(Cfg, "layout " .. Prof.N)
    for _, E in ipairs(Elements) do
        if E.Moved then E.Moved = false if not E.Follows then Retarget(E) end end   -- a Follows element keeps its parent's edge
        rows[E.Id] = { x = E.X, y = E.Y, scale = E.Scale, visible = E.Visible and 1 or 0, opacity = E.Opacity,
            edgex = E.TX, edgey = E.TY, wait = E.Wait }
    end
    SaveCfg()
    Log("layout saved, profile " .. Prof.N)
end

-- the layout saved into the profile it came from, the next one loaded; a profile never used starts as a copy
function Prof.Next()
    SaveLayout()
    Prof.N = Prof.N % 3 + 1
    Settings.Section(Cfg, "general").profile = Prof.N
    if Cfg["layout " .. Prof.N] then LoadLayout() else SaveLayout() end
    Log("profile " .. Prof.N)
end

LoadLayout()

---------------------------------------------------------------- finding widgets

local Avatar = nil    -- the level badge or character picture beside the bars, from avatar.lua; loaded near the main loop
local Bars = nil      -- the bars' look and the line under them, from bars.lua; loaded there too
local Buffs = nil     -- the buffs under the bars, the buff row and the drink ring, from buffs.lua; loaded there too
local RuneMap = nil   -- the minimap, from runemap.lua; loaded near the main loop
local Survival = nil  -- food, water and rest, from survival.lua; the buffs borrow its ring. Loaded there too.
local Immersive = nil -- the HUD fading when idle, from immersive.lua; loaded there too
local MenuButtons = nil -- the menu buttons in rings, from menubuttons.lua; loaded there too
local Aim = nil       -- the gold aim marks and lock-on diamond, from aim.lua; loaded there too
local Cooldowns = nil -- the spell cooldown tiles, from cooldowns.lua; loaded there too (its ctx is Cooldowns.Ctx)
local QuestTracker = nil -- the main and tracked quest under the minimap, from questtracker.lua; loaded there too
local Party = nil     -- the health of the other players, from party.lua; loaded there too
local Letters = nil   -- white letters with a shadow, from letters.lua; loaded there too (ctx Letters.Ctx)
local Clock = nil     -- the time of day icon, from clock.lua; off since 03-10-2026 (its load lines are comments)
local Ammo = nil      -- the ammo counter in a ring, from ammo.lua; loaded there too (ctx Ammo.Ctx)
local Toolbar = nil   -- the tool bar as tiles, from toolbar.lua; loaded there too (ctx Toolbar.Ctx)
-- the immersive camera's settings, rules and F6 panel, from camerarules.lua; loaded there too. camera.lua and
-- crosshair.lua use it. Its Open is the F6 panel, as MapMode is F8.
local Camera = nil

local function ClassName(obj)
    local ok, n = pcall(function() return obj:GetClass():GetFName():ToString() end)
    return ok and n or "?"
end

-- One search for every widget per scan, sorted by class. One search per class (about 30) took up to 1 s on UE4SS
-- builds without hash tables: the stutter reports of 28-09-2026. This one took 45 ms and found the same widgets.
local Found = {}   -- class name -> widgets, from the last search and, since 1.5, the game's reports (Reports)
-- class address -> class name: the name is read once per class, not once per widget (5000 widgets, 19 ms a scan
-- on a UE4SS with hash tables, 28-09-2026). Emptied on a new world, in case a class is unloaded and its address reused.
local ClassNames = {}
local function ClassAddress(W) return W:GetClass():GetAddress() end
-- FindClass's answers since the last search, by class and path: the parts ask for the same classes up to 5 times a
-- second (the spell slices, the chat, the aim), and between two searches the answer only loses widgets (30-09-2026).
-- With the game's reports a class can gain a widget between two searches: FindAll empties this when it matches again.
local FindCache = {}
local function Valid(W) return W and W:IsValid() end
local function SearchWidgets()
    Found, FindCache = {}, {}
    for _, W in pairs(FindAllOf("UserWidget") or {}) do
        local ok, a = pcall(ClassAddress, W)   -- one object that cannot be read must not stop the scan
        if ok and a then
            local c = ClassNames[a]
            if not c then c = ClassName(W) ClassNames[a] = c end
            local t = Found[c]
            if t then t[#t + 1] = W else Found[c] = { W } end
        end
    end
end

-- The game reports every new widget (1.5), so the search above runs once per world, not every 10 s: it walked
-- 7000 to 10000 widgets in 10 to 50 ms, the hitches of the playtest of 01-10-2026. UE4SS calls NewWidget on the game
-- thread, as it does the step (its source at 44afb36d: a widget made on a loading thread waits for the next engine
-- tick). On: the report is registered, where the timer starts; an old UE4SS keeps the timed search.
-- Wanted: the classes FindClass was asked for; a widget of another class is not kept. Dropped: the classes not kept
-- since the last search. Walk: why the next scan must search (false: no search). Retry: the scans that still match
-- the parts again after a kept widget, as a new widget has no tree and no parent yet. Seen, Kept, Time, Max: for
-- the perf line; the reports run outside the step, so its times do not count them.
-- Fresh: a widget was kept since the last scan, so the step scans soon (TickBody).
-- Quiet: the classes wanted with FindQuiet.
local Reports = { On = false, Wanted = {}, Quiet = {}, Dropped = {}, Walk = "start", Retry = 0, Fresh = false, Quick = 0, Seen = 0, Kept = 0, Time = 0, Max = 0 }
-- Arrivals: for a class that a part asks about with TakeArrivals, the widgets reported since it last asked. The 2 s
-- scan came too late for the map name: a map made new markers, and the player name showed beside the arrow until the
-- scan (playtest, 05-10-2026). Only handles are kept, nothing is read here. ForgetWorld empties them. A list that
-- nobody takes does not grow past ARRIVALS_MAX.
local Arrivals = {}
local ARRIVALS_MAX = 2000
local function TakeArrivals(className)
    local list = Arrivals[className]
    Arrivals[className] = {}
    if list and #list > 0 then return list end
end
-- It returns nothing: a report that returns true is taken out, and in this UE4SS that can free the Lua thread all
-- hooks of the mod run on (UE4SS issue 1345). The mod's own widgets come through here too, from inside the step.
local function NewWidget(W)
    local t0 = os.clock()
    Reports.Seen = Reports.Seen + 1
    local ok, a = pcall(ClassAddress, W)
    if ok and a then
        local c = ClassNames[a]
        if not c then c = ClassName(W) ClassNames[a] = c end
        local taken = Arrivals[c]
        if taken and #taken < ARRIVALS_MAX then taken[#taken + 1] = W end
        if Reports.Wanted[c] then
            local t = Found[c]
            if t then t[#t + 1] = W else Found[c] = { W } end
            Reports.Kept = Reports.Kept + 1
            if not Reports.Quiet[c] then Reports.Retry, Reports.Fresh = 3, true end
        else
            Reports.Dropped[c] = true
        end
    end
    local took = os.clock() - t0
    Reports.Time, Reports.Max = Reports.Time + took, math.max(Reports.Max, took)
end
-- Without the timed search a class's list only grows. Before FindClass reads it, drop the widgets that are gone, a
-- freed slot that now holds an object of another class, and a widget listed twice (reported, and found by a search).
local function StillOf(W, className) return W:IsValid() and ClassNames[ClassAddress(W)] == className and W:GetAddress() end
local function Compact(className)
    local keep, seen = {}, {}
    for _, W in ipairs(Found[className] or {}) do
        local ok, a = pcall(StillOf, W, className)
        if ok and a and not seen[a] then seen[a] = true keep[#keep + 1] = W end
    end
    Found[className] = keep
end

-- Returns the widgets and, as a second list, their full names (read here once, so no caller reads them again).
-- A cached answer is checked for widgets gone since; the lists are shared, so callers only read them.
local function FindClass(className, pathEnds, useParent)
    if Reports.On and not Reports.Wanted[className] then
        Reports.Wanted[className] = true
        -- the last search has every widget of the class, unless one was made since and not kept
        if Reports.Dropped[className] and not Reports.Walk then Reports.Walk = "new class" end
    end
    local ck = className .. "|" .. (useParent or 0) .. "|" .. (pathEnds and table.concat(pathEnds, "|") or "")
    local hit = not Reports.Quiet[className] and FindCache[ck]
    if hit then
        for i = #hit.W, 1, -1 do
            local ok, v = pcall(Valid, hit.W[i])
            if not (ok and v) then table.remove(hit.W, i) table.remove(hit.K, i) end
        end
        return hit.W, hit.K
    end
    local out, keys = {}, {}
    if Reports.On then Compact(className) end
    for _, W in ipairs(Found[className] or {}) do
        -- one object that cannot be read (a world being unloaded) must not stop the whole scan (27-09-2026)
        pcall(function()
            if not (W and W:IsValid()) then return end
            local full = W:GetFullName()
            local ok = not pathEnds
            if pathEnds then
                for _, p in ipairs(pathEnds) do if string.find(full, p) then ok = true end end
            end
            if ok and string.find(full, "/Engine/Transient%.") then   -- live widgets only; /Game paths are templates
                local climbed = false
                for _ = 1, (useParent or 0) do
                    local okp, P = pcall(function() return W:GetParent() end)
                    if okp and P and P:IsValid() then W, climbed = P, true end
                end
                if climbed then full = W:GetFullName() end
                out[#out + 1], keys[#keys + 1] = W, full
            end
        end)
    end
    if not Reports.Quiet[className] then FindCache[ck] = { W = out, K = keys } end
    return out, keys
end
-- A class wanted quietly: the enemy bar, which the game makes for each creature, all the time. Its new widgets are kept,
-- but they bring no early scan and no matching of the parts again, and its answer is not cached, so the next regular
-- scan has them. For a part that dresses a widget once and does not mind a second or two (enemybars.lua).
local function FindQuiet(className)
    Reports.Quiet[className] = true
    return FindClass(className)
end

-- A found widget and its full name, which keys the opacity and clipping memory. k: the name when already read.
local function AddInstance(E, W, k)
    local ok, key = pcall(function() return k or W:GetFullName() end)
    if ok and key then table.insert(E.Instances, W) table.insert(E.Keys, key) end
end

-- The screen's size in units and the game's HUD scale (see Hud), from the bars' widget: the canvas it fills sits in
-- a size box inside the HUD's scale box. Rounded, so a 16:9 screen gives exactly 1920x1080.
local function ReadHud()
    local V = ById("vitals").Instances[1]
    if not (V and V:IsValid()) then return end
    local WLL = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
    local v, dpi = WLL:GetViewportSize(V), WLL:GetViewportScale(V)
    if not (dpi and dpi > 0 and v.X > 0 and v.Y > 0) then return end
    local s = 1
    pcall(function()
        local box = V:GetParent():GetParent():GetParent()
        if ClassName(box) ~= "ScaleBox" or not (box.Stretch == 7 or box.Stretch == 8) then return end
        local u = box.UserSpecifiedScale   -- 7 and 8: the scale is set by hand, here the game's HUD scale
        if u > 0.2 and u < 5 then s = math.floor(u * 100 + 0.5) / 100 end
    end)
    local vw, vh = math.floor(v.X / dpi + 0.5), math.floor(v.Y / dpi + 0.5)
    if vw ~= Hud.VW or vh ~= Hud.VH or s ~= Hud.S then
        Log(string.format("screen: %d x %d units, HUD scale %.2f, so the HUD is %.0f x %.0f", vw, vh, s, vw / s, vh / s))
    end
    Hud.VW, Hud.VH, Hud.S, Hud.W, Hud.H = vw, vh, s, vw / s, vh / s
end

-- The search for every widget cost 14 ms every 2 s, a small hitch (FPS test of 29-09-2026). Once a world has
-- settled, the game makes almost no new HUD widgets (the widget log of that test: buff entries, maybe a held-action
-- prompt). So it runs every 2 s for the first half minute of a world and while F9 or F8 is open, else every 10 s; and at
-- once when a widget it found is gone, or when the number of buffs changes (a new buff can bring a new entry
-- widget, and its ring should not wait). A widget the game makes new waits 10 s at most for its place (review of
-- 29-09-2026: 20 s was too long). Between searches the widgets of the last one are used. ForgetWorld drops them.
-- Since 1.5 this is the way of an old UE4SS only: with the game's reports (Reports) the search runs once per world,
-- and NextSearch times the matching of the parts to the widgets kept.
local NextSearch = 0
-- the full searches since the last perf line: how many, their time, and what set each off (PerfLog)
local Searches = { N = 0, Sum = 0, Max = 0, Why = {} }
-- After a new world or a respawn the HUD is searched on every scan, up to 30 s, so its parts are found as the game
-- builds them. Three searches in a row that find the same number of parts end that early: the rest cost 10 to
-- 50 ms each for nothing (playtest, 01-10-2026: hitches of 90 to 110 ms after a teleport and a respawn). A part
-- the game builds later waits for the 10 s search. ForgetWorld starts it again. An old UE4SS only, as the timer is.
local Settle = { Last = -1, Same = 0, Done = false }
-- A freed widget's slot can go to a new object that still reads valid, so the name is compared too (review of
-- 29-09-2026); AddInstance adds each widget and its name together. Avatar and RuneMap are ours and re-added each pass.
local function AnyGone()
    for _, E in ipairs(Elements) do
        if not E.Custom then
            for n, W in ipairs(E.Instances) do
                local ok, k = pcall(function() return W:IsValid() and W:GetFullName() end)
                if not (ok and k == E.Keys[n]) then return E.Id end
            end
        end
    end
    return false
end
-- editing: F9 or F8 is open. buffsNew: the step saw the buff count change. Returns true when a search ran.
-- Without one, the game's widgets of the last pass are kept: AnyGone has just seen every one alive under its own
-- name, and the same answer cost a name read and a path check per widget, and a walk into the legend, every pass
-- (30-09-2026). Ours (the avatar, RuneMap, the cooldown tiles) are built after this in the same step, so they are
-- taken again on every pass.
local function FindAll(editing, buffsNew)
    local now = os.clock()
    local buffs = (Buffs and Buffs.Changed()) or buffsNew   -- read on every pass, so the count stays current
    local searched = false
    local why
    if Reports.On then
        -- The game reports new widgets (Reports): a full search only when one is owed. The parts are matched again,
        -- from the widgets kept, on what set off a search before; that reads some tens of widgets, not all of them.
        why = Reports.Walk
        searched = Reports.Retry > 0 or now > NextSearch or buffs or AnyGone()
        if searched and not why then FindCache, NextSearch = {}, now + 10 end
        if Reports.Retry > 0 then Reports.Retry = Reports.Retry - 1 end
    else
        why = (now > NextSearch and "timer") or (now < SettleUntil + 30 and not Settle.Done and "settle") or (editing and "editor")
            or (buffs and "buffs") or AnyGone()
    end
    if why then
        local t0 = os.clock()
        SearchWidgets()
        local t = os.clock() - t0
        Searches.N, Searches.Sum, Searches.Max = Searches.N + 1, Searches.Sum + t, math.max(Searches.Max, t)
        Searches.Why[why] = (Searches.Why[why] or 0) + 1
        NextSearch = now + 10
        Reports.Walk, Reports.Dropped = false, {}
        searched = true
    end
    for _, E in ipairs(Elements) do
        if E.Custom then
            E.Instances, E.Keys = {}, {}
            if E.Custom == "avatar" and Avatar and Avatar.W and Avatar.W:IsValid() then AddInstance(E, Avatar.W) end
            if E.Custom == "map" and RuneMap and RuneMap.W and RuneMap.W:IsValid() then AddInstance(E, RuneMap.W) end
            if E.Custom == "cooldowns" and Cooldowns and Cooldowns.W and Cooldowns.W:IsValid() then AddInstance(E, Cooldowns.W) end
            if E.Custom == "questtracker" and QuestTracker and QuestTracker.W and QuestTracker.W:IsValid() then AddInstance(E, QuestTracker.W) end
            if E.Custom == "party" and Party and Party.W and Party.W:IsValid() then AddInstance(E, Party.W) end
            if E.Custom == "clock" and Clock and Clock.W and Clock.W:IsValid() then AddInstance(E, Clock.W) end
        elseif searched then
            E.Instances, E.Keys = {}, {}
            for _, c in ipairs(E.Classes or {}) do
                local list, keys = FindClass(c, E.PathEnds, E.UseParent)
                for n, W in ipairs(list) do
                    local k = keys[n]
                    if E.Deep then
                        W, k = Survival and Survival.Find(W, E.Child), nil
                    elseif E.Child then
                        local found
                        pcall(function()
                            local root = W.WidgetTree.RootWidget
                            for i = 0, root:GetChildrenCount() - 1 do
                                local ch = root:GetChildAt(i)
                                if ch:GetFName():ToString() == E.Child then found = ch break end
                            end
                        end)
                        W, k = found, nil
                    end
                    if W then AddInstance(E, W, k) end
                end
            end
        end
    end
    if why == "settle" then
        local n = 0
        for _, E in ipairs(Elements) do if not E.Custom then n = n + #E.Instances end end
        Settle.Same = (n > 0 and n == Settle.Last) and Settle.Same + 1 or 0
        Settle.Last = n
        if Settle.Same >= 2 then
            Settle.Done = true
            Log(string.format("settled: %d HUD parts found, back to the 10 s search", n))
        end
    end
    pcall(ReadHud)
    return searched
end

---------------------------------------------------------------- applying the layout

local EditMode = false
local MapMode = false    -- F8: RuneMap's own settings, in the same panel as the editor (1.1)
local MapSel = 1         -- the selected line of the map settings
local Selected = 1
local Step = 10
-- Keyed by the widget's full name: every rescan gives new Lua handles for the same widgets.
-- Written: the opacity the editor or the immersive mode last wrote to a widget (nil: the widget is the game's).
-- OrigOpacity: the game's opacity of it before our first write, kept for the world (the RC's rule). The game fades its
-- notices by its own animation of this opacity, so a value read later may be from the middle of a fade: the picked-up
-- items stayed pale when it was read again at every write (playtest, 05-10-2026). The one notice whose fade ends at the value
-- we write, the level up notice, has Idle in its element, and that comes back instead (RestoreOpacity).
local OrigOpacity = {}
local Written = {}
local SAME = 0.002   -- an opacity reads back as a 32-bit number

-- k: the widget's full name, read once per scan (FindAll)
local function SetOpacity(W, k, value)
    if OrigOpacity[k] == nil then
        local ok, o = pcall(function() return W:GetRenderOpacity() end)
        OrigOpacity[k] = ok and o or 1.0
    end
    W:SetRenderOpacity(value)
    Written[k] = value
end

-- Back to the game's opacity, but only a widget that still holds what we wrote: when the game has written since, its
-- own value stands (a notice that is still fading). idle: the element's own word for what the game leaves it at when
-- nothing shows (E.Idle). The first opacity read of the notice can be a point of its fade, or the designer's sample that
-- sits at 1 in a fresh world, so the level up notice does not use it.
local function RestoreOpacity(W, k, idle)
    local w = Written[k]
    if w == nil then return end
    Written[k] = nil
    if math.abs(W:GetRenderOpacity() - w) <= SAME then W:SetRenderOpacity(idle or OrigOpacity[k]) end
end

-- The F9 opacity (1.1). A user widget gets it as its colour, which multiplies with the render opacity: the
-- game's own fades (render opacity) and the editor's blinking still work on top of it. Other widgets (the ammo
-- box, the avatar) have no such colour and take it as render opacity. An element inside another one would
-- also take its parent's opacity; it gets its own divided by the parent's, so the two do not multiply (a child
-- cannot be more solid than its parent).
local IsUW, Tint = {}, {}   -- by the widget's full name: user widget or not, and the colour's alpha last set
local UWClass = nil
local function IsUserWidget(W, k)
    local v = IsUW[k]
    if v == nil then
        v = false
        pcall(function()
            if not (UWClass and UWClass:IsValid()) then UWClass = StaticFindObject("/Script/UMG.UserWidget") end
            v = W:IsA(UWClass)
        end)
        IsUW[k] = v
    end
    return v
end
local function OwnOpacity(E)
    local P = E.Inside and ById(E.Inside)
    if not P then return E.Opacity end
    return math.min(1.0, E.Opacity / P.Opacity)
end

-- The parts of a Parts element, found once per widget (E.PartsW, by the widget's full name). The legend's: every
-- page of its switcher but the world page, and the world page's prompt list (widget dump, 29-09-2026).
local function PartsOf(E, W, k)
    local parts = E.PartsW[k]
    if parts then return parts end
    parts = {}
    local ok, err = pcall(function()
        local sw = Survival.Find(W, "Switcher")
        for i = 0, sw:GetChildrenCount() - 1 do
            local page = sw:GetChildAt(i)
            if page:GetFName():ToString() == "InputLegendWidgetWorld" then page = Survival.Find(page, "SizeBox_0") end
            if page then parts[#parts + 1] = page end
        end
    end)
    if ok and #parts > 0 then E.PartsW[k] = parts   -- none yet (a HUD still being built): tried again next step
    elseif not E.PartsLogged then E.PartsLogged = true Log(E.Id .. ": parts not found, hidden whole: " .. tostring(err)) end
    return parts
end

local Unclipped = {}
-- force: write the move, size and pivot even when they are the values last written. Otherwise they are written
-- only when they change: every step wrote three calls per widget (about 80 calls a step, 30-09-2026). Every scan
-- forces them, as the bars' colours are set again on every scan in case the game set them back.
local function ApplyOne(W, k, x, y, scale, E, isSelected, force)
    if not (W and W:IsValid()) then return end
    if E.NoClip then
        if not Unclipped[k] then
            Unclipped[k] = true
            pcall(function()
                local P = W
                for _ = 1, 3 do
                    if not (P and P:IsValid()) then break end
                    P:SetClipping(0)   -- inherit: do not cut children at this box's edge
                    P = P:GetParent()
                end
            end)
        end
    end
    local L = E.Last[k]
    if not L then L = {} E.Last[k] = L end
    if E.Full and E.Center then
        local px, py = Layout.Pivot(E)
        if force or L.PX ~= px or L.PY ~= py then
            W:SetRenderTransformPivot({ X = px, Y = py })
            L.PX, L.PY = px, py
        end
    end
    local moved = force or L.X ~= x or L.Y ~= y or L.S ~= scale
    if force or L.X ~= x or L.Y ~= y then W:SetRenderTranslation({ X = x, Y = y }) L.X, L.Y = x, y end
    if force or L.S ~= scale then W:SetRenderScale({ X = scale, Y = scale }) L.S = scale end
    -- KeepFull: a child that fills the element and must still fill the screen. It gets the inverse of the element's
    -- move and size, about the same middle: the element maps p to c + s*(p - c) + t, the child q to c + (q - c)/s - t/s.
    if E.KeepFull and moved then
        pcall(function()
            local px, py = Layout.Pivot(E)   -- the element's own pivot: the child fills the same box
            for i = 0, W:GetChildrenCount() - 1 do
                local c = W:GetChildAt(i)
                if c:GetFName():ToString() == E.KeepFull then
                    c:SetRenderTransformPivot({ X = px, Y = py })
                    c:SetRenderScale({ X = 1 / scale, Y = 1 / scale })
                    c:SetRenderTranslation({ X = -x / scale, Y = -y / scale })
                end
            end
        end)
    end
    -- fade: the share of the opacity that goes into the render opacity. RuneMap sets its own (runemap.lua): its
    -- gold rings need it too.
    local fade = 1.0
    -- the immersive mode's share, exactly 1 when shown; RuneMap takes it in its own opacity (see MapCtx)
    local imm = (Immersive and E.Custom ~= "map") and Immersive.Factor(E) or 1.0
    if E.Custom ~= "map" then
        local op = OwnOpacity(E)
        if not IsUserWidget(W, k) then
            fade = op
        elseif (Tint[k] or 1.0) ~= op then
            pcall(function() W:SetColorAndOpacity({ R = 1, G = 1, B = 1, A = op }) end)
            Tint[k] = op
        end
    end
    -- An element with Parts is hidden part by part: the widget itself stays shown, so what lives inside it and is
    -- an element of its own (the menu buttons in the legend) can still show. Its parts are found once per widget;
    -- none found (no survival.lua, a changed game): the whole widget hides as before.
    local parts = E.Parts and PartsOf(E, W, k)
    local shown = E.Visible or (parts and #parts > 0)
    if shown and parts and #parts > 0 then
        local o = E.Visible and 1.0 or 0.0
        if EditMode then   -- the editor's dimming goes on the parts; the widget stays whole for what lives inside it
            if isSelected then o = E.Visible and 1.0 or 0.6 else o = E.Visible and 0.3 or 0.1 end
        end
        -- every step while hidden, as immersive.lua does with the bars: the game may fade a prompt back in
        if o < 1 or E.PartsOp[k] ~= o then
            for _, P in ipairs(parts) do pcall(function() if P:IsValid() then P:SetRenderOpacity(o) end end) end
            E.PartsOp[k] = o
        end
    end
    if EditMode and parts and #parts > 0 then
        SetOpacity(W, k, 1.0)
    elseif EditMode then
        if isSelected then
            -- solid, the gold corners round it pulse instead (the design sketch); dim when hidden
            if shown then SetOpacity(W, k, fade) else SetOpacity(W, k, 0.6) end
        else
            SetOpacity(W, k, shown and 0.3 * fade or 0.1)
        end
    elseif not shown and not (MapMode and E.Custom == "map") then   -- F8 shows a hidden map
        SetOpacity(W, k, 0.0)
    elseif E.Opaque then
        W:SetRenderOpacity(fade)   -- the dial looked faded; keep it fully solid
    elseif fade * imm < 1.0 then
        SetOpacity(W, k, fade * imm)
    elseif next(Written) ~= nil then
        RestoreOpacity(W, k, E.Idle)   -- leave the game's own fading alone when the element is shown
    end
    -- the part drawn on request (E.Redraw) is asked to draw again at every opacity the element has while it is seen:
    -- when it comes back, and at each step of a fade
    if E.Redraw then
        pcall(function()
            local op = W:GetRenderOpacity()
            if op > 0 and op ~= L.Drawn then
                local R = W[E.Redraw]
                if R and R:IsValid() then R:RequestRender() end
            end
            L.Drawn = op
        end)
    end
end

-- The bag and the gamepad (1.6; play test and probes, 03-10-2026). The game's tool bar is the top row of the bag's
-- panel, and a gamepad goes from slot to slot by their places on the screen. With the bar moved away from the panel,
-- the gamepad found no way between the bar and the bag. So while the bag is open and a gamepad is in use, the bar
-- sits at its own place. With the mouse nothing was wrong, so the bar stays where the player put it; the mod reads
-- the input in use and changes with it (Ivan, 03-10-2026: "prepoznas input pa menja").
-- Open: the bag's tab row, next to the bar in the same box, is shown (it is collapsed, 1, while the bag is closed),
-- and the focus is inside the bag's content. The tab row alone is not enough: after the entry into a world it is
-- shown until the bag was open once, and the bar sat in the bag all that time (play test, 03-10-2026). The focus is
-- in the content exactly while a gamepad moves in the bag (probe 3, 03-10-2026).
local Bag = { Tabs = nil, Content = nil, Input = nil, Open = false }
local PadInUse
local function BagOpen()
    local bar = ById("toolbar").Instances[1]
    if not (bar and bar:IsValid()) then Bag.Tabs, Bag.Content = nil, nil return false end
    local T, C = Bag.Tabs, Bag.Content
    if not (T and T:IsValid() and C and C:IsValid()) then
        T = nil
        local box, tree = bar:GetParent(), bar:GetOuter()
        if not (box:IsValid() and tree:IsValid()) then Bag.Tabs, Bag.Content = nil, nil return false end
        for i = 0, box:GetChildrenCount() - 1 do
            local c = box:GetChildAt(i)
            if c:IsValid() and c:GetFName():ToString() == "TabGroupOverlay" then T = c break end
        end
        C = tree:GetOuter()   -- the widget whose tree holds the bar: the bag's content (InventoryContent)
        if not (T and C and C:IsValid()) then Bag.Tabs, Bag.Content = nil, nil return false end
        Bag.Tabs, Bag.Content = T, C
    end
    return T:GetVisibility() ~= 1 and C:HasFocusedDescendants()
end
-- A gamepad is the input in use (the game's input subsystem: 0 mouse and keyboard, 1 gamepad, 2 touch).
function PadInUse()
    local S = Bag.Input
    if not (S and S:IsValid()) then
        if os.clock() < (Bag.InputAt or 0) then return false end
        Bag.InputAt = os.clock() + 5   -- none found: the search walks every object, so not at every call
        S = nil
        for _, o in pairs(FindAllOf("CommonInputSubsystem") or {}) do
            if o:IsValid() and not string.find(o:GetFullName(), "Default__", 1, true) then S = o break end
        end
        Bag.Input = S
    end
    return S ~= nil and S:GetCurrentInputType() == 1
end

local function ApplyAll(force)
    local now = os.clock()
    if now >= (Bag.Next or 0) then   -- ten looks a second are enough: the bar moves within a blink of the bag
        Bag.Next = now + 0.1
        local okBag, open = pcall(function() return BagOpen() and PadInUse() end)
        Bag.Open = okBag and open or false   -- the bag is open and a gamepad is in use
    end
    for i, E in ipairs(Elements) do
        -- with the group "notify" picked, the notices inside it are solid, not dimmed: its preview shows them all
        local sel = EditMode and (i == Selected or (E.Inside == "notify" and Elements[Selected].Id == "notify"))
        local lx, ly, ls = LocalTransform(E)
        if Bag.Open and E.Id == "toolbar" and not EditMode then lx, ly, ls = 0, 0, 1 end   -- the editor shows the saved place
        for n, W in ipairs(E.Instances) do ApplyOne(W, E.Keys[n], lx, ly, ls, E, sel, force) end
    end
end

---------------------------------------------------------------- the editor panel (editor.lua draws it)

local Editor = nil   -- the F9 and F8 panel, from editor.lua; loaded near the main loop

local function Cls(path) return StaticFindObject(path) end

local function SetColor(T, c)
    T:SetColorAndOpacity({ SpecifiedColor = c, ColorUseRule = 0 })
end

-- a text of ours with a soft shadow, in the font given (the game's default font without one)
local function MakeText(tree, name, size, color, s, font)
    local T = StaticConstructObject(Cls("/Script/UMG.TextBlock"), tree, FName(name))
    T:SetText(FText(s or ""))
    SetColor(T, color)
    pcall(function()
        T:SetShadowOffset({ X = 1, Y = 1 })
        T:SetShadowColorAndOpacity({ R = 0, G = 0, B = 0, A = 0.8 })
    end)
    pcall(function()
        local fi = T.Font   -- our own text, so changing it touches nothing of the game
        if font then fi.FontObject = font end
        fi.Size = size
        T:SetFont(fi)
    end)
    return T
end

-- Poppins, the game's body font: the editor, the menu keys and the cooldowns write in it. Found once.
local Poppins = nil
local function FindPoppins()
    if Poppins and Poppins:IsValid() then return Poppins end
    for _, F in pairs(FindAllOf("Font") or {}) do
        local ok, n = pcall(function() return F:GetFullName() end)
        if ok and string.find(n, "/Game/") and string.find(n, "Poppins") and not string.find(n, "Default__") then Poppins = F break end
    end
    return Poppins
end

-- Poppins Medium, the heavier of the game's two weights: the quest tracker writes in it, because Regular is hard to
-- read when the tracker is scaled down (in game, 04-10-2026). Found once; without it, the font above.
local PoppinsMedium = nil
local function FindPoppinsMedium()
    if PoppinsMedium and PoppinsMedium:IsValid() then return PoppinsMedium end
    local F = StaticFindObject("/Game/UI/Fonts/Poppins-Medium_Font.Poppins-Medium_Font")
    if F and F:IsValid() then PoppinsMedium = F return F end
    return FindPoppins()
end

-- kind: the class the object must be, for the typed calls it goes into. After a game patch another kind of object
-- can sit at a known path; the wrong kind can crash.
local function Asset(path, kind)
    if not path then return nil end
    if not string.match(path, "^/[%w_%./%-]+$") then Log("asset path not accepted: " .. path) return nil end
    local obj = StaticFindObject(path)
    if (not obj or not obj:IsValid()) and LoadAsset then
        pcall(function() obj = LoadAsset(path) end)
    end
    if not (obj and obj:IsValid()) then Log("asset not found: " .. path) return nil end
    if kind then
        local okA, isA = pcall(function() local K = StaticFindObject(kind) return K and K:IsValid() and obj:IsA(K) end)
        if not (okA and isA) then Log("asset is not a " .. kind .. ": " .. path) return nil end
    end
    return obj
end

-- A picture from a file, kept in cache[key] and reused while it is valid. Widgets must hold it: a texture that
-- only Lua holds is thrown away by the engine. The buffs and the bars use it.
local function CachedTex(cache, key, outer, file)
    local tex = cache[key]
    if tex and tex:IsValid() then return tex end
    tex = StaticFindObject("/Script/Engine.Default__KismetRenderingLibrary"):ImportFileAsTexture2D(outer, file)
    if not (tex and tex:IsValid()) then
        local f = io.open(file, "rb")   -- for the log: the file is not there, or the engine did not take it
        if f then f:close() end
        error((f and "picture not loaded: " or "picture missing: ") .. file)
    end
    cache[key] = tex
    return tex
end

-- The F9 list by screen area (design sketch): the ninth of the screen an element sits in (Layout.Area). Read when
-- the editor opens, so a row does not jump to another group while it moves; PgUp and PgDn go down this list.
local Order = {}   -- element indexes in list order
local AreaOf = {}   -- element index -> its area, from the last SortOrder
local function SortOrder()
    local byArea = {}
    for i, E in ipairs(Elements) do
        local a = Area(E)
        AreaOf[i] = a
        byArea[a] = byArea[a] or {}
        table.insert(byArea[a], i)
    end
    Order = {}
    for _, a in ipairs(AREAS) do for _, i in ipairs(byArea[a] or {}) do Order[#Order + 1] = i end end
end

-- moved, resized or faded from its default: a gold diamond on its row
local function Changed(E)
    local d = Defaults[E.Id] or {}
    return math.abs(E.X - (d.X or 0)) > 0.5 or math.abs(E.Y - (d.Y or 0)) > 0.5 or math.abs(E.Scale - (d.Scale or 1)) > 0.001
        or E.Opacity < 1
end

-- The keys each panel lists (the design sketch). KEY: the names of the six keys a player can change, as bound
-- (KeyCode, at the keys below, writes them at load). So the lists are made when a panel is filled, not at load.
local KEY = {}
local function EditKeys()
    return { { { "PgUp", "PgDn" }, "Select" }, { { "←", "→", "↑", "↓" }, "Move" }, { { "+", "-" }, "Size" },
        { { ",", "." }, "Opacity" }, { { "Home", "End" }, "Step" }, { { "Del", "Ins" }, "Hide, show" },
        { { "Backspace" }, "Reset" }, { { KEY.editor }, "Save, close" } }
end
local function MapKeys()
    return { { { "↑", "↓" }, "Select" }, { { "←", "→" }, "Change" }, { { KEY.zoomout, KEY.zoomin }, "Zoom" },
        { { "Backspace" }, "Reset" }, { { KEY.editor }, "Layout" }, { { KEY.map }, "Save, close" } }
end
local MAP_ROWS = { "RuneMap", "Faces north", "North mark", "Player name", "Creatures", "Ore", "Herbs", "Essence", "Rare trees",
    "In immersive mode", "Zoom", "Drawing" }
-- the lines that are a plain On / Off, and the setting in runemap.lua each one flips. "In immersive mode" steps
-- through Nothing, Map and Compass (Settings.STAY), Creatures through three values: MapValue and MapChange have them.
local MAP_SWITCH = { RuneMap = "Map", ["Faces north"] = "North", ["North mark"] = "Mark", ["Player name"] = "Name", Ore = "Ore",
    Herbs = "Herbs", Essence = "Essence", ["Rare trees"] = "Trees" }
-- the lines with more than two values: the list shows "< value >", so a player sees that Left and Right give more
-- than what is shown (Ivan, 04-10-2026: nobody knew that "In immersive mode" has Compass too)
local MAP_CHOICE = { Creatures = true, ["In immersive mode"] = true, Zoom = true }

-- The F8 lines: the value of each, and a hint for the selected one
local function MapValue(i)
    local S = RuneMap and RuneMap.Set or {}
    local row = MAP_ROWS[i]
    if row == "Creatures" then
        if not ById("creatures").Visible then return "Off" end
        return S.Neutral and "All" or "Enemies only"
    end
    if row == "Zoom" then return RuneMap and string.format("%d%%", math.floor(200 / RuneMap.ZoomLevel() + 0.5)) or "-" end
    if row == "Drawing" then return S.Smooth and "Smooth" or "Faster" end
    if row == "In immersive mode" then return S.Immersive or "Nothing" end
    return S[MAP_SWITCH[row]] and "On" or "Off"
end
local MAP_HINTS = {
    RuneMap = { Off = "The map is off. The mod does not build it at all." },   -- On names the editor's key: MapHint
    ["Faces north"] = { On = "North stays at the top of the map.", Off = "The map turns with the camera." },
    ["North mark"] = { On = "The mark on the gold ring shows where north is.", Off = "No north mark on the ring." },
    ["Player name"] = { On = "Your player name shows beside your arrow on the map.", Off = "Your player name does not show on the map. The names of other players stay." },
    Creatures = { All = "Red diamonds for enemies, green for neutral animals.", ["Enemies only"] = "Only enemies. Neutral animals are not shown.",
        Off = "No creature diamonds on the map." },
    Ore = { On = "Ore rocks near you. Empty rocks hide until they grow back.", Off = "No ore on the map." },
    Herbs = { On = "Wild herbs near you. A picked herb goes off the map.", Off = "No herbs on the map." },
    Essence = { On = "Rune essence near you.", Off = "No rune essence on the map." },
    ["Rare trees"] = { On = "Dead trees, yew, magic trees and anima bark near you.", Off = "No rare trees on the map." },
    ["In immersive mode"] = { Nothing = "The immersive mode hides the map and the compass.",
        Map = "The map and the quest tracker stay in the immersive mode. The compass is away." },   -- Compass: MapHint
    Drawing = { Smooth = "The map draws every frame. Switching might decrease performance.",
        Faster = "The map draws every second frame. A bit choppy when you turn." },
}
local function MapHint(i, v)
    local row = MAP_ROWS[i]
    if row == "Zoom" then return "Closer or farther. The " .. KEY.zoomout .. " and " .. KEY.zoomin .. " keys do the same at any time." end
    if row == "In immersive mode" and v == "Compass" then
        return "Only the compass stays, with the map marks. The map is away."
    end
    if row == "RuneMap" and v == "On" then return "The map is on. To only hide it, use Delete in " .. KEY.editor .. "." end
    return MAP_HINTS[row] and MAP_HINTS[row][v] or ""
end

-- The parts that failed, for a line on the F9 and F8 panel: a part whose step or scan threw (Parts), or that gave
-- up building (Fails, see MayTry; a part with several builds says so itself with Problem).
local function Problems()
    local out = {}
    for _, P in ipairs(Parts) do
        if P.Error or (P.M.Fails or 0) >= 3 or (P.M.Problem and P.M.Problem()) then out[#out + 1] = P.Name end
    end
    if #out == 0 then return nil end
    return "Failed: " .. table.concat(out, ", ") .. ". See UE4SS.log in Win64."
end

-- the second line of the panel's head: the camera settings' key, where the camera settings exist
local function CameraLink(v)
    if KEY.camera then v.SubC, v.SubD = "Camera settings on", KEY.camera end
    return v
end

local function EditView()
    local E = Elements[Selected]
    local v = { Mode = "edit", Title = "RUNE UI", SubA = "Map settings on", SubB = KEY.map, Profile = Prof.N,
        Keys = EditKeys(), Name = E.Name, Map = {}, Warn = Problems() }
    local cx, cy = Spot(E)
    local sx, sy = math.floor(cx + 0.5), math.floor(cy + 0.5)   -- on a 1920 x 1080 screen
    if E.Wait then   -- the immersive line: + and - set the wait
        v.Facts = { { "State", E.Visible and "On" or "Off" }, { "Waits", E.Wait .. " s" } }
        v.Hint = "+ and - set the wait before the HUD fades. Ins and Del turn it on and off."
    elseif IsSwitch(E) then
        v.Facts = { { "State", E.Visible and "On" or "Off" } }
        v.Hint = E.Hint or "Ins and Del turn it on and off."
    else
        v.Facts = { { "X", tostring(sx) }, { "Y", tostring(sy) }, { "Size", math.floor(E.Scale * 100 + 0.5) .. "%" },
            { "Opacity", math.floor(E.Opacity * 100 + 0.5) .. "%" }, { "Step", tostring(Step) } }
        if not E.Visible then v.Hint = "Hidden. Ins shows it again."
        elseif #E.Instances == 0 then v.Hint = "Not on the screen right now. It still moves." end
        local x, y, w, h = ScreenBox(E)
        v.Mark = { X = x, Y = y, W = w, H = h, Name = E.Name, XY = "X " .. sx .. "   Y " .. sy, Sample = E.Visible and E.Sample or nil }
    end
    -- the screen map: every element with a place, in 1920 x 1080 units
    for i, El in ipairs(Elements) do
        if not IsSwitch(El) and #v.Map < Editor.BOXES then
            local x, y, s = Spot(El)
            local bw, bh = Layout.Box(El)
            local w, h = bw * s, bh * s
            v.Map[#v.Map + 1] = { X = x - El.Size.X * s / 2, Y = y - h / 2, W = w, H = h,
                Sel = i == Selected, Hidden = not El.Visible, Name = El.Name }
        end
    end
    -- the list: Editor.ROWS lines of group titles and rows, the selected row in the middle when it can be
    local lines, at = {}, 1
    local last
    for _, i in ipairs(Order) do
        local El = Elements[i]
        local a = AreaOf[i]
        if a ~= last then lines[#lines + 1] = { Head = true, Text = a } last = a end
        local gone = #El.Instances == 0 and not IsSwitch(El)
        lines[#lines + 1] = { Text = El.Name, Sel = i == Selected, Moved = Changed(El), Dim = gone or not El.Visible,
            Note = not El.Visible and "hidden" or gone and "not on screen" or nil }
        if i == Selected then at = #lines end
    end
    local first = math.max(1, math.min(at - math.floor(Editor.ROWS / 2), #lines - Editor.ROWS + 1))
    v.Rows = {}
    for n = first, math.min(#lines, first + Editor.ROWS - 1) do v.Rows[#v.Rows + 1] = lines[n] end
    -- a group title on the last line has its rows cut off below: "CENTER" with nothing under it (01-10-2026)
    if v.Rows[#v.Rows].Head then v.Rows[#v.Rows] = nil end
    return CameraLink(v)
end

local function MapView()
    local vals = {}
    for i = 1, #MAP_ROWS do vals[i] = MapValue(i) end
    local v = { Mode = "map", Title = "RUNE MAP", SubA = "Layout on", SubB = KEY.editor, Keys = MapKeys(), Warn = Problems(),
        Name = MAP_ROWS[MapSel] .. ":  " .. vals[MapSel], Hint = MapHint(MapSel, vals[MapSel]), Rows = {} }
    -- the panel has Editor.ROWS lines: a longer list moves with the selected row, as the F9 list does (11 rows since
    -- "In immersive mode"; the last row was not drawn: review of 04-10-2026)
    local first = math.max(1, math.min(MapSel - math.floor(Editor.ROWS / 2), #MAP_ROWS - Editor.ROWS + 1))
    for r = first, math.min(#MAP_ROWS, first + Editor.ROWS - 1) do
        v.Rows[#v.Rows + 1] = { Text = MAP_ROWS[r], Note = MAP_CHOICE[MAP_ROWS[r]] and ("< " .. vals[r] .. " >") or vals[r], Sel = r == MapSel }
    end
    return CameraLink(v)
end

-- F9: the panel stays on its side of the screen and moves to the other only when it would cover the selected
-- element. Going away from every selected element made it jump from side to side while going down the list
-- ("it really bothers me", 01-10-2026). Its side is kept in Editor.Left.
-- F8: under the map, its right edge on the map's right edge; above the map when there is no room below.
local function PanelAt(v)
    local w, h = Editor.Size()
    if v.Mode == "map" then
        local E = ById("runemap")
        local cx, cy = FinalCenter(E)
        local half = E.Size.X / 2 * E.Scale
        local x = math.max(10, math.min(Hud.VW - 10 - w, cx + half - w))
        local y = cy + half + 12
        if y + h > Hud.VH - 10 then y = math.max(10, cy - half - 12 - h) end
        return { X = math.floor(x + 0.5), Y = math.floor(y + 0.5) }
    end
    local y = math.max(10, math.min(30, Hud.VH - 10 - h))   -- the top stays at 30: the panel changes height from part to part, so a centred one moved up and down
    local function X(left) return left and 30 or math.floor(Hud.VW - 30 - w) end
    local function Covers(left)
        local m, x = v.Mark, X(left)
        return m.X < x + w and m.X + m.W > x and m.Y < y + h and m.Y + m.H > y
    end
    if Editor.Left == nil then Editor.Left = true end
    if v.Mark and Covers(Editor.Left) and not Covers(not Editor.Left) then Editor.Left = not Editor.Left end
    return { X = X(Editor.Left), Y = y }
end

-- State: what the panel shows now, as one string. View: the last view, placed again on every step, as the panel
-- knows its new size one frame after its content changed. Both are set after the fill: a fill that failed is
-- tried again on the next step (State was set first, and the panel stayed empty: playtest, 02-10-2026).
-- Logged: the error texts of a step that are in the log, Lines: how many. A step that failed can fail again every
-- 50 ms: each text is logged once, and 10 texts at most in a world, as a text may change from step to step.
local Panel = { State = "", View = nil, Logged = {}, Lines = 0 }
local function UpdateOverlay(now)
    local cam = Camera ~= nil and Camera.Open   -- F6: the camera settings, in the same panel
    local open = EditMode or MapMode or cam
    if not Editor then return end
    if open and not Editor.Ready() and MayTry(Editor) and os.clock() > SettleUntil and LastController ~= "" then
        local ok, err = Editor.Build({ Log = Log, Gen = function() return Gen end, Font = FindPoppins(), FontMedium = FindPoppinsMedium(), Asset = Asset,
            ProfileKey = KEY.profile })
        if ok then Log("panel ready") Editor.Fails, Panel.State = 0, "" else Failed(Editor) Log("panel failed: " .. tostring(err)) end
    end
    if not Editor.Ready() then return end
    local ok, err = pcall(function()
        if not open then
            if Editor.Shown then Editor.Open(false) Editor.Shown = false end
            return
        end
        -- a new view only when something it shows changed: the numbers of every element, the step, the screen
        local state
        if cam then
            state = Camera.State(ById("immersive").Visible) .. "|" .. Hud.VW .. "|" .. Hud.VH .. "|" .. (Problems() or "")
        elseif MapMode then
            local vals = {}
            for i = 1, #MAP_ROWS do vals[i] = MapValue(i) end
            state = "map|" .. MapSel .. "|" .. table.concat(vals, "|") .. "|" .. Hud.VW .. "|" .. Hud.VH .. "|" .. (Problems() or "")
        else
            local parts = { "edit", Selected, Step, Prof.N, Hud.VW, Hud.VH, Hud.S, Problems() or "" }
            for _, El in ipairs(Elements) do
                parts[#parts + 1] = string.format("%.1f,%.1f,%.2f,%.1f,%s,%d,%s", El.X, El.Y, El.Scale, El.Opacity,
                    El.Visible and "1" or "0", #El.Instances, tostring(El.Wait))
            end
            state = table.concat(parts, "|")
        end
        -- opened before the fill: while the fill fails, the player sees the panel as it was last filled (empty
        -- on the first open), not no panel
        if not Editor.Shown then Editor.Open(true) Editor.Shown = true end
        if state ~= Panel.State then
            local v
            if cam then
                v = Camera.View(KEY, ById("immersive").Visible, Problems())
                v.SubC, v.SubD = "Map settings on", KEY.map
            else
                v = MapMode and MapView() or EditView()
            end
            Editor.Update(v)
            Panel.State, Panel.View = state, v
        end
        -- placed every step: the panel knows its new size one frame after its content changed
        if Panel.View then Editor.Place(PanelAt(Panel.View)) end
        Editor.Pulse(now)
    end)
    if not ok then
        err = tostring(err)
        if not Panel.Logged[err] and Panel.Lines < 10 then
            Panel.Logged[err], Panel.Lines = true, Panel.Lines + 1
            Log("panel update failed: " .. err)
        end
    end
end

-- the arrows move the selected element by the step; a held arrow keeps moving it (see HoldMove)
local function Move(dx, dy)
    local E = Elements[Selected]
    if not EditMode or IsSwitch(E) then return end
    if E.OnlyY then dx = 0 end
    E.X, E.Y = E.X + dx * Step, E.Y + dy * Step
    E.Moved = true   -- on saving, it follows the edge nearest to where it now sits (Retarget)
end
---------------------------------------------------------------- main loop, on a timer (the game has no per-frame hook we can use)

local LastScan = -100
local NextBuffCount = 0
local ApplyErrorLogged = false
local TickAlive = false
local SaveRequested = false

-- CurseForge takes no .png files in a Dragonwilds mod zip, so the pictures also travel inside Scripts/art.lua as
-- base64 text (tools/make-runemap-art.js writes it). At start, each picture that is missing or different is
-- written into Art; the parts then load them from there as before.
local B64 = {}
for i = 1, 64 do B64[string.byte("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/", i)] = i - 1 end
local function Unbase64(s)
    local out = {}
    for i = 1, #s, 4 do
        local a, b, c, d = string.byte(s, i, i + 3)
        local v = B64[a] * 262144 + B64[b] * 4096 + (B64[c] or 0) * 64 + (B64[d] or 0)   -- "=" counts as 0
        out[#out + 1] = string.char(math.floor(v / 65536), math.floor(v / 256) % 256, v % 256)
    end
    local _, pad = string.gsub(string.sub(s, -2), "=", "")
    return string.sub(table.concat(out), 1, -1 - pad)
end
local function WriteArt()
    local art = LoadPart("art")
    if not art then return end
    local written = 0
    for name, text in pairs(art) do
        local file = RUNEUI_DIR .. "Art/" .. name
        local data = Unbase64(text)
        local f = io.open(file, "rb")
        local old = f and f:read("*a")
        if f then f:close() end
        if old ~= data then
            f = io.open(file, "wb")
            if f then f:write(data) f:close() written = written + 1 else Log("cannot write " .. file) end
        end
    end
    Log("pictures written: " .. written)
    -- the base64 text (about 400 KB) is not read again: let Lua free it
    if package and package.loaded then package.loaded.art = nil end
end
do
    local ok, err = pcall(WriteArt)
    if not ok then Log("pictures not written: " .. tostring(err)) end
end
Survival = LoadPart("survival")
-- The parts that build on the game's widgets: the avatar, the bars and the buffs. They share main.lua's
-- helpers through one table, and survival.lua's ring and Find. Listed first: their Scan runs in this order, and
-- the buffs' step runs before the map's, as it always did.
local Util = { Log = Log, ById = ById, Uniq = Uniq, G = G, ClearOurs = ClearOurs, ClassName = ClassName,
    FindClass = FindClass, Asset = Asset, SetColor = SetColor,
    MayTry = MayTry, Failed = Failed, CachedTex = CachedTex, Survival = Survival,
    GoldLine = LoadPart("goldline"),   -- the line under the bars, the XP bar and the quest tracker's top (goldline.lua)
    Chain = LoadPart("chain"),   -- the chain of delayed calls that paints about every frame (xp.lua, compass.lua)
    Near = LoadPart("nearby") }   -- which creatures, ore, herbs, essence and rare trees are near (the map and the compass)
Avatar = LoadPart("avatar")
if Avatar then Avatar.Init(Util) AddPart("avatar", Avatar, Util) end
Bars = LoadPart("bars")
if Bars then Bars.Init(Util) AddPart("bars", Bars, Util) end
Buffs = LoadPart("buffs")
if Buffs then Buffs.Init(Util) AddPart("buffs", Buffs, Util) end
RuneMap = LoadPart("runemap")
if RuneMap then
    RuneMap.Attach(Settings.Section(Cfg, "map"), SaveCfg, Settings)   -- the F8 settings and the zoom live in the settings file
    RuneMap.Near = Util.Near
    RuneMap.Res = LoadPart("resources")   -- ore, herbs, essence and rare trees on the map
end
Camera = LoadPart("camerarules")
if Camera then Camera.Attach(Settings.Section(Cfg, "camera"), SaveCfg) end
-- Editing: the map shows while F9 or F8 is open, even when it is hidden
local MapCtx = { Log = Log, ById = ById, Asset = Asset, Editing = function() return EditMode or MapMode end,
    -- the immersive mode's share: the map fades itself, its gold rings too (runemap.lua ApplyOpacity)
    -- with the map setting "In immersive mode" at Map, the map stays
    Fade = function()
        if RuneMap and RuneMap.Set.Immersive == "Map" then return 1 end
        return Immersive and Immersive.Factor(ById("runemap")) or 1
    end }
AddPart("runemap", RuneMap, MapCtx)
local SurvivalCtx = { Log = Log, ById = ById }
AddPart("survival", Survival, SurvivalCtx)
Immersive = LoadPart("immersive")
-- read fresh on every step: these handles change with the world
local ImmersiveCtx = { Log = Log, On = function() return ById("immersive").Visible end,
    Editing = MapCtx.Editing, Bars = function() return Bars and Bars.Blades.Bars or {} end,
    Trim = function() return Bars and Bars.Trim.W end,
    Rings = function() return Survival and Survival.Rings and Survival.Rings() or {} end,
    Drinks = function() return Buffs and Buffs.Drinks.Deco or {} end,
    Wait = function() return ById("immersive").Wait or 8 end,
    BuffEntries = function() return Buffs and Buffs.Entries() or {} end,
    BuffLevel = function(d, level) if Buffs then Buffs.SetLevel(d, level) end end,
    TextsUnder = function(W) return Survival and Survival.TextsUnder(W) or {} end,
    ChatCount = function() return MenuButtons and MenuButtons.Chat end,
    MapStays = function() return RuneMap ~= nil and RuneMap.Set.Immersive == "Map" end,
    CompassStays = function() return RuneMap ~= nil and RuneMap.Set.Immersive == "Compass" end,
    -- the quest and step on show: a change brings the quest tracker back
    QuestSig = function() return QuestTracker and QuestTracker.Sig end,
    -- how many times a friend's health went down: a new one brings the party panel back
    PartyHits = function() return Party and Party.Hits end }
if Survival then MenuButtons = LoadPart("menubuttons") end   -- it draws with survival.lua's ring
-- the survival ring and its turn, a text in the game's font, the chat widget
local MenuCtx = { Log = Log, ById = ById, Find = Survival and Survival.Find, Ring = Survival and Survival.Ring,
    Turn = Survival and Survival.Turn,
    -- the keys in Poppins, the game's own key font (sketch A); found once and kept on the menu buttons table
    Text = function(tree, name, size, color, s)
        return MakeText(tree, name, size, color, s, FindPoppins())
    end,
    Chat = function() return FindClass("WBP_ClosedChat_C")[1] end, Pad = PadInUse }
AddPart("menu buttons", MenuButtons, MenuCtx)
do   -- Rune XP: the XP under the bars (xp.lua)
    local Xp = Survival and LoadPart("xp")   -- it finds the game's parts with survival.lua's Find
    AddPart("rune xp", Xp, { Log = Log, ById = ById, G = G, ClearOurs = ClearOurs, Asset = Asset, Font = FindPoppins,
        Find = Survival and Survival.Find, GoldLine = Util.GoldLine, Chain = Util.Chain,
        -- the slim level up (xp.lua): its switch, the level up element shown, and the editor closed (the editor writes the
        -- banner's opacity, which is the signal that it is on show)
        Slim = function() return ById("slimlevel").Visible and ById("levelup").Visible and not EditMode end,
        MayTry = MayTry, Failed = Failed, Trim = function() return Bars and Bars.Trim.W end,
        Soon = ExecuteInGameThreadWithDelay,   -- one call on the game thread, a few ms from now; nil in an old UE4SS
        On = function() return ById("runexp").Visible end })
end
Aim = LoadPart("aim")
local AimCtx = { Log = Log, On = function() return ById("aim").Visible end,
    Reticle = function() return FindClass("WBP_HUD_ReticleWidget_C")[1] end,
    Orb = function() return FindClass("WBP_LockOnTargetOrb_C")[1] end }
AddPart("aim", Aim, AimCtx)
Cooldowns = LoadPart("cooldowns")
if Cooldowns then
    Cooldowns.Ctx = { Log = Log, ById = ById, Find = Survival and Survival.Find,
        -- Editing: F9 only. With MapCtx.Editing the sample tiles also showed with the map settings (F8) open.
        On = function() return ById("cooldowns").Visible end, Editing = function() return EditMode end,
        Horizontal = function() return ById("cdhoriz").Visible end,
        -- the spell wheel's slices only: the spell book has a second wheel of the same slices (probe, 29-09-2026).
        -- With their names, as FindClass gives them.
        Slices = function() return FindClass("WBP_SurvivalSorcery_RadialSlice_C", Cooldowns.Ctx.SlicePath) end,
        SlicePath = { "WBP_Spellcasting_MainPanel_C_%d+%.WidgetTree_%d+%.SpellRadialWidget%.WidgetTree_%d+%.RadialSlice_%d+$" },
        Text = function(...) if MenuButtons then return MenuCtx.Text(...) end return MakeText(...) end }
    if Survival then AddPart("cooldowns", Cooldowns, Cooldowns.Ctx) end   -- without survival.lua it has no Find
end
if Survival then Ammo = LoadPart("ammo") end   -- it finds its parts with survival.lua's Find
if Ammo then
    Ammo.Ctx = { Log = Log, ById = ById, Find = Survival.Find, TextsUnder = Survival.TextsUnder,
        Text = MenuCtx.Text }
    AddPart("ammo", Ammo, Ammo.Ctx)
end
-- the time of day icon is off (03-10-2026); Clock stays nil, and every use of it checks for that
-- Clock = LoadPart("clock")
-- local ClockCtx = { Log = Log, ById = ById, On = function() return ById("immersive").Visible end,
--     Editing = function() return EditMode end, ReadClock = function() return RuneMap.ReadClock(MapCtx) end }
-- AddPart("clock", Clock, ClockCtx)
Letters = LoadPart("letters")
if Letters then Letters.Ctx = { Log = Log, Find = FindClass } AddPart("letters", Letters, Letters.Ctx) end
Toolbar = LoadPart("toolbar")
if Toolbar then Toolbar.Ctx = { Log = Log, ById = ById, G = G, Font = FindPoppins } AddPart("toolbar", Toolbar, Toolbar.Ctx) end
do   -- no name of its own: main.lua is near Lua's limit of 200 locals
    local P = LoadPart("pickups")
    if P then AddPart("pickups", P, { Log = Log, Find = FindClass, Font = FindPoppins }) end
    P = LoadPart("farmplot")
    if P then AddPart("farm plots", P, { Log = Log, Find = FindClass }) end
    -- the enemy bars take the look of the player's bars; no switch, like the player's bars (enemybars.lua)
    P = LoadPart("enemybars")
    if P then AddPart("enemy bars", P, { Log = Log, Find = FindQuiet, MayTry = MayTry, Failed = Failed, Noise = Bars and Bars.OneColorNoise }) end
    P = LoadPart("combattext")
    if P then
        AddPart("combat text", P, { Log = Log, Find = FindClass, MayTry = MayTry, Failed = Failed, Chain = Util.Chain,
            Soon = ExecuteInGameThreadWithDelay,   -- nil in an old UE4SS: no pop, the look still works
            On = function() return ById("combattext").Visible end })
    end
    P = LoadPart("quests")
    if P then
        AddPart("quests", P, { Log = Log, Find = FindClass, Font = FindPoppins, Collect = Letters and Letters.Collect })
    end
    -- the id of the selected row while F9 is open; nil with the editor closed or F8 open
    local function SelectedId()
        local E = EditMode and not MapMode and Elements[Selected]
        return E and E.Id or nil
    end
    P = LoadPart("notices")
    if P then AddPart("notices", P, { Log = Log, Find = FindClass, Selected = SelectedId }) end
    -- the local controller, as its link from the local player (ControllerName); nil while there is none
    local function Controller()
        local ok, pc = pcall(function()
            local c = LocalPlayer and LocalPlayer:IsValid() and LocalPlayer.PlayerController
            if c and c:IsValid() and c:IsLocalController() then return c end
        end)
        return ok and pc or nil
    end
    QuestTracker = LoadPart("questtracker")
    if QuestTracker and Util.GoldLine then
        AddPart("quest tracker", QuestTracker, { Log = Log, ById = ById, Asset = Asset, GoldLine = Util.GoldLine,
            Text = function(tree, name, size, color, s)
                return MakeText(tree, name, size, color, s, FindPoppinsMedium())
            end,
            -- F9 only, as the cooldowns: with the map settings (F8) open the made-up sample would show too
            Editing = function() return EditMode end,
            On = function() return ById("questtracker").Visible end,
            ShowNext = function() return ById("questnext").Visible end,
            -- the game's quest and unlock notice is on show: its entry, made once in a world, is collapsed (1) at rest
            -- and not collapsed (3) while a notice plays (probe Q1, 04-10-2026)
            Popup = function()
                for _, W in ipairs((FindClass("WBP_QuestAndUnlocks_Item_C"))) do
                    local ok, shown = pcall(function() return W:GetVisibility() ~= 1 end)
                    if ok and shown then return true end
                end
                return false
            end,
            Controller = Controller })
    end
    Party = LoadPart("party")
    if Party then
        AddPart("party panel", Party, { Log = Log, ById = ById, Controller = Controller,
            Text = function(tree, name, size, color, s)
                return MakeText(tree, name, size, color, s, FindPoppinsMedium())
            end,
            On = function() return ById("party").Visible end,
            -- the three made-up rows show in F9 while the element's row is selected, also when playing alone
            Preview = function() return SelectedId() == "party" end })
    end
    P = LoadPart("compass")   -- the gold style of the compass, and the map's marks on it (compass.lua)
    if P and Util.GoldLine then
        AddPart("compass", P, { Log = Log, ById = ById, G = G, Asset = Asset, CachedTex = CachedTex, GoldLine = Util.GoldLine,
            Controller = Controller, Near = Util.Near, Chain = Util.Chain,
            Soon = ExecuteInGameThreadWithDelay,   -- one call on the game thread, a few ms from now; nil in an old UE4SS
            -- the game's compass on the screen: shown in the editor's list, the game's HUD up, and not faded out (by the
            -- immersive mode or by the editor's opacity); nil when not
            Compass = function()
                local E = ById("compass")
                local W, V = E.Instances[1], ById("vitals").Instances[1]
                if not (E.Visible and W and W:IsValid() and V and V:IsValid()) then return nil end
                local ok, seen = pcall(function() return V:IsVisible() and W:IsVisible() and W:GetRenderOpacity() > 0 end)
                return ok and seen and W or nil
            end,
            -- what is on the map screen: RuneMap is drawn (its own switch, the HUD, the immersive mode's fade)
            MapShown = function() return RuneMap ~= nil and RuneMap.Visible == true end,
            Set = function() return RuneMap and RuneMap.Set or {} end })
    end
    P = LoadPart("mapname")   -- the map setting "Player name": off hides your own player name beside your marker on the maps
    if P then
        AddPart("map name", P, { Log = Log, Find = FindQuiet, Arrived = TakeArrivals,
            On = function() return not RuneMap or RuneMap.Set.Name ~= false end })
    end
    P = LoadPart("bednames")
    if P then
        AddPart("bed names", P, { Log = Log, Hook = RegisterHook, Text = FText,
            Find = function(path) local o = Cls(path) if o ~= nil and o:IsValid() then return o:GetAddress() end end })
    end
    -- the immersive camera and the crosshair setting (1.8): "immersive mode on" is its line in F9, the switch
    local function ImmersiveOn() return ById("immersive").Visible end
    P = Camera and LoadPart("camera")
    if P then
        AddPart("camera", P, { Log = Log, Rules = Camera, Controller = Controller, Immersive = ImmersiveOn,
            -- the HUD reticle: a bow's aim or a staff's cast starts the ranged zoom (camera.lua Aiming)
            Reticle = AimCtx.Reticle, Find = Survival and Survival.Find, MayTry = MayTry, Failed = Failed,
            -- the game's camera values, kept where a restart of the mods does not lose them (camera.lua Keep)
            Shared = function(name, v)
                local ok, r = pcall(function()
                    if v == nil then return ModRef:GetSharedVariable("RuneUI.Camera." .. name) end
                    ModRef:SetSharedVariable("RuneUI.Camera." .. name, v)
                end)
                if ok then return r end
            end })
    end
    P = Camera and Aim and Aim.Collect and LoadPart("crosshair")
    if P then AddPart("crosshair", P, { Log = Log, Rules = Camera, Immersive = ImmersiveOn, Reticle = AimCtx.Reticle, Collect = Aim.Collect }) end
end
-- last of the parts that draw: the parts above may change what it fades, and ApplyAll reads its opacity after it
-- (the Mod Menu part, added at the keys, comes after it and draws nothing)
AddPart("immersive", Immersive, ImmersiveCtx, true)
Editor = LoadPart("editor")

-- A new world (quit to the main menu, entering a game): drop every handle the mod holds into the old one
-- before anything reads it. The engine frees the old world's objects while it loads the new one, and a
-- crash on quitting to the menu (27-09-2026) came from an old handle. The world is told apart by its player
-- controller; UE4SS's load-map hook crashed on its second call (27-09-2026), so it is not used.
-- sameWorld: a player restart inside a world that still stands, so our own map may be taken off the screen
local function ForgetWorld(sameWorld)
    for _, E in ipairs(Elements) do E.Instances, E.Keys, E.PartsOp, E.PartsW, E.Last = {}, {}, {}, {}, {} end
    Found, FindCache, NextSearch = {}, {}, 0   -- the last widget search's handles; search again at once
    for c in pairs(Arrivals) do Arrivals[c] = {} end   -- the reported widgets of the old world too
    Reports.Walk = sameWorld and "restart" or "new world"
    if Editor then Editor.Fails, Editor.RetryAt = 0, 0 end   -- new tries (see MayTry); the parts reset their own in Forget
    Bag.Tabs, Bag.Content, Bag.Input = nil, nil, nil
    Tint = {}   -- a HUD made again may reuse a name: set the opacity colour again, it costs one call per widget
    if not sameWorld then
        -- the editor panel of the old world is off the screen: build a new one on the next F9, and say its
        -- errors again if it fails again
        if Editor then Editor.Forget() Editor.Shown, Panel.State, Panel.Logged, Panel.Lines = false, "", {}, 0 end
        -- these remember widgets by full name; the old world's widgets are gone
        OrigOpacity, Written, Unclipped, ClassNames, IsUW = {}, {}, {}, {}, {}
    end
    for _, P in ipairs(Parts) do
        pcall(P.M.Forget, sameWorld)
        if not sameWorld then P.Error, P.M.ErrorLogged = nil, false end   -- a new world: say it again if it fails again
    end
    Gen = Gen + 1
    SettleUntil = os.clock() + 3
    Settle = { Last = -1, Same = 0, Done = false }
    Log(sameWorld and "player restart: old handles dropped" or "new world: old handles dropped")
end
local function SearchController()
    -- the local player's controller only: in co-op a friend's controller joining or leaving must not look
    -- like a new world; one unreadable controller is skipped, not taken as a change
    for _, P in pairs(FindAllOf("PlayerController") or {}) do
        local ok, n = pcall(function()
            local full = P:GetFullName()
            if not string.find(full, "Default__", 1, true) and P:IsLocalController() then
                LocalPlayer = P.Player
                return full
            end
        end)
        if ok and n then return n end
    end
    return ""
end
-- The local controller's name, read on every tick; "" while a world is loading. The controller goes away the
-- moment a travel starts, before the old world is torn down. Reading the viewport's world instead changed only
-- once the new world stood, and the game crashed on entering a world in between (27-09-2026, 0.49).
-- A search of all controllers on every tick cost 36 ms a tick on UE4SS builds without hash tables (the stutter
-- of 28-09-2026). So once the local player is known, its link to the controller is read instead: in the test
-- build of 28-09-2026 the link and the search changed on the same tick in every travel.
local function ControllerName()
    if not (LocalPlayer and LocalPlayer:IsValid()) then return SearchController() end
    local ok, n = pcall(function()
        local pc = LocalPlayer.PlayerController
        if pc and pc:IsValid() and pc:IsLocalController() then return pc:GetFullName() end
        return ""
    end)
    if ok then return n end
    LocalPlayer = nil
    return SearchController()
end
local function WatchWorld()
    local name = ControllerName()
    if name ~= LastController then LastController = name ForgetWorld(false) end
end

-- One line in UE4SS.log every 60 s: what the mod costs the game (stutter reports, 28-09-2026)
local Perf = { From = os.clock(), Ticks = 0, Sum = 0, Max = 0, Watch = 0, Scans = 0, ScanSum = 0, ScanMax = 0 }
-- The game's frame rate beside it, by what RuneMap does (FPS reports, 29-09-2026). The engine's frame counter
-- against the clock counts every frame, not a sample. Only while the HUD is on screen: menus and loading screens
-- are left out, and so is a step where the state changed.
local FPS_STATES = { "no map", "map every frame", "map every 2nd" }
local Fps = { By = {} }   -- By: state -> { F = frames, T = seconds }. Frames, At, State: at the last step. KSL, GPS: the engine's libraries.
local function FpsState()
    local V = ById("vitals").Instances[1]
    if not (V and V:IsValid() and V:IsVisible()) then return nil end
    if not (RuneMap and RuneMap.Visible) then return FPS_STATES[1] end
    return FPS_STATES[RuneMap.Set.Smooth and 2 or 3]
end
local function AddFrames(state, frames, seconds)
    local b = Fps.By[state]
    if not b then b = { F = 0, T = 0 } Fps.By[state] = b end
    b.F, b.T = b.F + frames, b.T + seconds
end
local function CountFrames(now)
    local state = FpsState()
    if not Fps.Sampled then
        local ok, f = pcall(function()
            if not (Fps.KSL and Fps.KSL:IsValid()) then Fps.KSL = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary") end
            return Fps.KSL:GetFrameCount()
        end)
        if ok and type(f) == "number" then
            if state and state == Fps.State then AddFrames(state, f - Fps.Frames, now - Fps.At) end
            Fps.Frames, Fps.At, Fps.State = f, now, state
            return
        end
        Fps.Sampled = true
        Log("perf: no frame counter (" .. tostring(f) .. "), the FPS comes from one frame's length per step")
    end
    if not state then return end
    local ok, dt = pcall(function()
        if not (Fps.GPS and Fps.GPS:IsValid()) then Fps.GPS = StaticFindObject("/Script/Engine.Default__GameplayStatics") end
        return Fps.GPS:GetWorldDeltaSeconds(ById("vitals").Instances[1])
    end)
    if ok and type(dt) == "number" and dt > 0 then AddFrames(state, 1, dt) end
end

local function PerfLog(now)
    local P, widgets = Perf, 0
    for _, E in ipairs(Elements) do widgets = widgets + #E.Instances end
    Log(string.format("perf: %d ticks, avg %.1f ms, max %.0f ms; world watch avg %.2f ms; %d scans, avg %.0f ms, max %.0f ms; %d widgets; lua %.0f KB",
        P.Ticks, P.Sum / math.max(1, P.Ticks) * 1000, P.Max * 1000, P.Watch / math.max(1, P.Ticks) * 1000,
        P.Scans, P.ScanSum / math.max(1, P.Scans) * 1000, P.ScanMax * 1000, widgets,
        collectgarbage("count")))
    local parts = {}
    for _, s in ipairs(FPS_STATES) do
        local b = Fps.By[s]
        if b and b.T >= 1 and b.F > 0 then
            parts[#parts + 1] = string.format("%s %.0f fps (%.1f ms) for %.0f s", s, b.F / b.T, b.T / b.F * 1000, b.T)
        end
    end
    Log("perf: game " .. (#parts > 0 and table.concat(parts, "; ") or "HUD not on screen"))
    local why = {}
    for k, n in pairs(Searches.Why) do why[#why + 1] = k .. " " .. n end
    table.sort(why)
    Log(string.format("perf: %d full searches, avg %.0f ms, max %.0f ms (%s); %s", Searches.N,
        Searches.Sum / math.max(1, Searches.N) * 1000, Searches.Max * 1000, table.concat(why, ", "),
        Reports.On and string.format("%d new widgets reported in %.0f ms, max %.0f ms, %d kept", Reports.Seen,
            Reports.Time * 1000, Reports.Max * 1000, Reports.Kept) or "no reports, timed search"))
    if Reports.On then
        -- the kept lists, as FindClass reads a whole list when the parts are matched again: their size and the longest
        local n, top, topN = 0, "none", 0
        for c in pairs(Reports.Wanted) do
            local k = #(Found[c] or {})
            n = n + k
            if k > topN then top, topN = c, k end
        end
        Log(string.format("perf: %d widgets in the kept lists, the longest %s with %d; %d scans brought by a kept widget", n, top, topN, Reports.Quick))
    end
    Searches = { N = 0, Sum = 0, Max = 0, Why = {} }
    Reports.Seen, Reports.Kept, Reports.Time, Reports.Max, Reports.Quick = 0, 0, 0, 0, 0
    Perf = { From = now, Ticks = 0, Sum = 0, Max = 0, Watch = 0, Scans = 0, ScanSum = 0, ScanMax = 0 }
    Fps.By = {}
end

-- The key bind moves once on the press. The engine says which keys are down (a test in game, 01-10-2026): an arrow
-- held past Hold.After moves again on every step (50 ms), so a step of 10 goes 200 units a second.
local Hold = { After = 0.35, Keys = nil, Since = nil }   -- Keys: { key, dx, dy }, made on first use
local function HoldMove(now)
    if not EditMode or MapMode then Hold.Since = nil return end
    local pc = LocalPlayer and LocalPlayer:IsValid() and LocalPlayer.PlayerController
    if not (pc and pc:IsValid()) then return end
    if not Hold.Keys then
        Hold.Keys = { { { KeyName = FName("Left") }, -1, 0 }, { { KeyName = FName("Right") }, 1, 0 },
            { { KeyName = FName("Up") }, 0, -1 }, { { KeyName = FName("Down") }, 0, 1 } }
    end
    local dx, dy = 0, 0
    for _, k in ipairs(Hold.Keys) do
        if pc:IsInputKeyDown(k[1]) then dx, dy = dx + k[2], dy + k[3] end
    end
    if dx == 0 and dy == 0 then Hold.Since = nil return end
    if not Hold.Since then Hold.Since = now return end
    if now - Hold.Since >= Hold.After then Move(dx, dy) end
end

local LoggedEditMode = false
local function TickBody()
    local now = os.clock()
    if not TickAlive then
        TickAlive = true
        Log("timer running" .. (IsInGameThread and (IsInGameThread() and " on the game thread" or " off the game thread") or ""))
    end
    if EditMode ~= LoggedEditMode then
        LoggedEditMode = EditMode
        Log(EditMode and "edit mode on" or "edit mode off")
        if EditMode then pcall(SortOrder) end   -- the list by screen area, as the elements sit now
    end
    WatchWorld()   -- first: nothing below may read a handle into a world that is gone
    Perf.Watch = Perf.Watch + (os.clock() - now)
    CountFrames(now)

    -- the widgets every 2 s, in the editor too: faster scans stuttered when each held a full search (27-09 and
    -- 28-09-2026). The full search inside runs less often (FindAll); sooner scans come from the two cases below.
    -- Sooner when the buff count changes: a new drink took up to 2 s to become its ring (playtest, 01-10-2026). The
    -- count is a few plain numbers; the search it brings runs once per new buff.
    local buffsNew = false
    if now > NextBuffCount then   -- 4 times a second; its own clock, so not every step between scans
        NextBuffCount = now + 0.25
        local okB, b = Buffs and pcall(Buffs.Changed)
        buffsNew = okB and b or false
    end
    -- Sooner too when the game reported a widget that a part uses: the drink's entry can come after its count
    -- changed, and the ring then waited for the 2 s scan (playtest, 01-10-2026). 4 scans a second at most, as a
    -- new HUD comes as some hundred widgets over a few seconds.
    local quick = Reports.Fresh and now - LastScan > 0.25
    local scanned = now - LastScan > 2.0 or buffsNew or quick
    if scanned then
        if quick then Reports.Quick = Reports.Quick + 1 end   -- for the perf line: a class the game makes all the time would show here
        LastScan, Reports.Fresh = now, false
        local scanFrom = os.clock()
        local okFind, errFind = pcall(FindAll, EditMode or MapMode, buffsNew)
        if not okFind and not ApplyErrorLogged then ApplyErrorLogged = true Log("finding widgets failed: " .. tostring(errFind)) end
        if now > SettleUntil then
            -- the parts that build on the game's widgets (the avatar, the bars, the buffs), once per scan
            for _, P in ipairs(Parts) do
                if P.M.Scan then
                    local okS, errS = pcall(P.M.Scan, P.Ctx)
                    if not okS and not P.M.ErrorLogged then P.M.ErrorLogged = true P.Error = tostring(errS) Log(P.Name .. " scan failed: " .. P.Error) end
                end
            end
            if buffsNew and Buffs then Buffs.NextRings = 0 end   -- a new buff or drink ring is right in this step too
        end
        local scan = os.clock() - scanFrom
        Perf.Scans, Perf.ScanSum, Perf.ScanMax = Perf.Scans + 1, Perf.ScanSum + scan, math.max(Perf.ScanMax, scan)
    end

    -- every part's step, in the order of the list; the immersive mode is the last that draws, before ApplyAll reads its opacity
    for _, P in ipairs(Parts) do
        if now > SettleUntil and (P.Early or now > 20) then
            local okP, errP = P.M.Tick and pcall(P.M.Tick, P.Ctx)
            if P.M.Tick and not okP and not P.M.ErrorLogged then P.M.ErrorLogged = true P.Error = tostring(errP) Log(P.Name .. " step failed: " .. P.Error) end
        end
    end
    pcall(HoldMove, now)
    local okApply, errApply = pcall(ApplyAll, scanned)   -- a scan step writes every move and size again (ApplyOne)
    if not okApply and not ApplyErrorLogged then ApplyErrorLogged = true Log("apply failed: " .. tostring(errApply)) end

    if SaveRequested then SaveRequested = false SaveLayout() end
    if Camera then pcall(Camera.Commit) end   -- the camera settings are saved here, whatever camera.lua's step does
    if Prof.Wanted then Prof.Wanted = false pcall(Prof.Next) end

    UpdateOverlay(now)

    local took = os.clock() - now
    Perf.Ticks, Perf.Sum, Perf.Max = Perf.Ticks + 1, Perf.Sum + took, math.max(Perf.Max, took)
    if now - Perf.From > 60 then PerfLog(now) end
end

local TickErrorLogged = false
local function TimerStep()   -- not "Step": that is the editor's move step
    local ok, err = pcall(TickBody)
    if not ok and not TickErrorLogged then TickErrorLogged = true Log("timer step failed: " .. tostring(err)) end
end
-- The whole step on the game thread. The older timer below runs part of it on UE4SS's own thread, at the same
-- moment as the game thread's part: Lua cannot do that, and it crashed the game inside UE4SS.dll (27-09 and
-- 28-09-2026, with "Ref was not function" errors in the log). The call throws when UE4SS has no game thread hook.
-- The game's reports of new widgets (Reports) only with this timer: its step and the reports both run on the game
-- thread, one after the other. Registered from the game thread too: UE4SS adds it to a list its hook reads there.
if LoopInGameThreadWithDelay and ExecuteInGameThreadWithDelay
    and pcall(ExecuteInGameThreadWithDelay, 2000, function()
        Reports.On = NotifyOnNewObject ~= nil and pcall(NotifyOnNewObject, "/Script/UMG.UserWidget", NewWidget)
        Log(Reports.On and "widgets: the game reports new ones, no timed search" or "widgets: no reports from this UE4SS, timed search")
        LoopInGameThreadWithDelay(50, TimerStep)
    end) then
    Log("timer: on the game thread")
else
    Log("timer: old UE4SS, the timer runs on two threads; a newer UE4SS experimental build is more stable")
    -- While the game thread is busy (a world loading), the timer keeps firing. Only one step waits in the queue at a
    -- time, so hundreds of them do not run at once when the world is up. A step that waited 5 s is taken as lost.
    local QueuedAt = nil
    local function Tick()
        local run = function() QueuedAt = nil TimerStep() end
        ExecuteWithDelay(50, Tick)   -- first: an error below must not stop the timer
        if not ExecuteInGameThread then
            run()
        elseif not QueuedAt or os.clock() - QueuedAt > 5 then
            QueuedAt = os.clock()
            ExecuteInGameThread(run)
        end
    end
    ExecuteWithDelay(2000, Tick)
end

-- A player restart (entering a world, respawning) can rebuild the game's HUD: drop every handle into it
-- first. Widgets added before the restart and read after it crashed the game on entering (27-09-2026).
RegisterHook("/Script/Engine.PlayerController:ClientRestart", function()
    local name = ControllerName()
    ForgetWorld(name == LastController)   -- the same controller: the same world, still standing
    LastController = name
    if not (EditMode or MapMode) then LoadLayout() end   -- dying with the editor open keeps the unsaved changes
end)
---------------------------------------------------------------- keys (Windows key codes; they only change state, the loop above does the work)

-- Key binds run on UE4SS's own thread, beside the game thread's step: they only change numbers and flags, and
-- make nothing new (no text, no tables), so they cannot start Lua's memory cleanup under the step (28-09-2026).
-- The step logs the editor opening and closing.
-- Windows key codes by name. The six keys in KEY_DEFAULT can be changed in the [keys] section of runeui.txt (1.4);
-- the others are fixed, as the F9 panel lists them.
local VK = { Backspace = 8, PgUp = 33, PgDn = 34, End = 35, Home = 36, Left = 37, Up = 38, Right = 39, Down = 40,
    Insert = 45, Delete = 46, Plus = 107, Minus = 109, Equals = 187, Dash = 189, Comma = 188, Period = 190,
    ["["] = 219, ["]"] = 221 }
for i = 1, 12 do VK["F" .. i] = 111 + i end
for i = 0, 9 do VK[tostring(i)] = 48 + i end
for i = 0, 25 do VK[string.char(65 + i)] = 65 + i end
local KEY_DEFAULT = { editor = "F9", map = "F8", profile = "F7", zoomin = "]", zoomout = "[", camera = "F6" }
local function KeyCode(what)
    local keys = Settings.Section(Cfg, "keys")
    if keys[what] == nil then keys[what] = KEY_DEFAULT[what] end   -- written on the next save, so the player sees the line
    local name = tostring(keys[what])
    local shown = VK[name] and name or string.upper(name)   -- f9 in the file is the F9 key
    local code = VK[shown]
    if not code then
        Log("keys: " .. what .. "=" .. name .. " is not a key the mod knows, using " .. KEY_DEFAULT[what])
        shown = KEY_DEFAULT[what]
        code = VK[shown]
    end
    KEY[what] = shown   -- the name the panels show
    return code
end

-- Rune UI's page in the mod "Mod Menu" (1.5, modmenu.lua): the rows of RuneUI/modmenu.txt, each with the mod's
-- real value and the way to change it, as F8 and F9 do it. A key works after a restart, as from runeui.txt.
do   -- no name of its own: main.lua is near Lua's limit of 200 locals
    local MM = LoadPart("modmenu")
    if MM then
        local rows = {}
        local function Row(key, get, set) rows[#rows + 1] = { Key = key, Get = get, Set = set } end
        -- first: Mod Menu's "reset" gives every row at once, and the rows below belong to the profile in use
        Row("profile", function() return tostring(Prof.N) end,
            function(v) for _ = 1, 2 do if Prof.N ~= tonumber(v) then Prof.Next() end end end)
        local keys = Settings.Section(Cfg, "keys")
        for _, what in ipairs({ "editor", "map", "camera", "profile", "zoomin", "zoomout" }) do
            Row("key_" .. what, function() return MM.KeyToMenu(keys[what]) or MM.KeyToMenu(KEY_DEFAULT[what]) end,
                function(v)
                    local name = MM.KeyFromMenu(v)
                    if not name then Log("keys: " .. tostring(v) .. " from Mod Menu is not a key the mod knows, " .. what .. " stays") return end
                    keys[what] = name
                    SaveCfg()
                end)
        end
        -- the immersive mode and the creatures are rows of the layout: the step's save writes them (SaveRequested)
        local I, C = ById("immersive"), ById("creatures")
        Row("immersive", function() return I.Visible end, function(v) I.Visible = v == true SaveRequested = true end)
        local X = ById("runexp")
        Row("rune_xp", function() return X.Visible end, function(v) X.Visible = v == true SaveRequested = true end)
        local SL = ById("slimlevel")
        Row("slim_level_up", function() return SL.Visible end, function(v) SL.Visible = v == true SaveRequested = true end)
        local CT = ById("combattext")
        Row("combat_text", function() return CT.Visible end, function(v) CT.Visible = v == true SaveRequested = true end)
        local N = ById("questnext")
        Row("quest_next", function() return N.Visible end, function(v) N.Visible = v == true SaveRequested = true end)
        local CH = ById("cdhoriz")
        Row("horizontal_cooldowns", function() return CH.Visible end, function(v) CH.Visible = v == true SaveRequested = true end)
        local PP = ById("party")
        Row("party_panel", function() return PP.Visible end, function(v) PP.Visible = v == true SaveRequested = true end)
        Row("immersive_wait", function() return I.Wait or 8 end,
            function(v) I.Wait = math.floor(Settings.Num(v, 3, 30, 8) + 0.5) SaveRequested = true end)
        if RuneMap then
            local S = RuneMap.Set
            for _, k in ipairs({ "Map", "North", "Mark", "Name", "Ore", "Herbs", "Essence", "Trees" }) do
                Row("map_" .. k, function() return S[k] end, function(v) S[k] = v == true RuneMap.Dirty = true end)
            end
            Row("map_immersive", function() return S.Immersive end,
                function(v) S.Immersive = Settings.StayFrom(v) RuneMap.Dirty = true end)
            Row("map_creatures", function() return (not C.Visible) and "Off" or (S.Neutral and "All" or "Enemies only") end,
                function(v) C.Visible, S.Neutral = v ~= "Off", v == "All" RuneMap.Dirty = true SaveRequested = true end)
            Row("map_drawing", function() return S.Smooth and "Smooth" or "Faster" end,
                function(v) S.Smooth = v == "Smooth" RuneMap.Dirty = true end)
        end
        if Camera then   -- the camera rows, one per row of the F6 panel (camerarules.lua ROWS)
            for _, r in ipairs(Camera.ROWS) do
                Row("camera_" .. r.Key, function() return Camera.MenuGet(r.Key) end, function(v) Camera.MenuSet(r.Key, v) end)
            end
        end
        AddPart("mod menu", MM, { Log = Log, Rows = rows, ReadFile = ReadText,
            Read = function(name)
                local ok, v = pcall(function() return ModRef:GetSharedVariable("ModMenu.RuneUI." .. name) end)
                if ok then return v end
            end,
            WriteFile = function(path, text)
                local f = io.open(path, "w")
                if not f then return false end
                local ok = f:write(text)
                f:close()
                return ok and true or false
            end,
            -- The step sorts the editor's list when it sees the editor open at its start. This opens it in the middle
            -- of a step, and the panel is filled at the end of the same step: with no list yet, the first fill
            -- failed and the panel stayed blank (playtest, 02-10-2026).
            OpenEditor = function() MapMode = false EditMode = true if Camera then Camera.Open = false end pcall(SortOrder) end }, true)
    end
end

RegisterKeyBind(KeyCode("editor"), function()
    MapMode = false   -- F9 inside F8: from the map settings into the editor
    if Camera then Camera.Open = false end   -- and from the camera settings
    EditMode = not EditMode
    if not EditMode then
        SaveRequested = true
    end
end)

-- F8: RuneMap's own settings (1.1). F8 inside F9 goes from the editor to the map settings. Closing saves the
-- layout, which holds the creatures switch; runemap.lua saves the other settings as they change.
RegisterKeyBind(KeyCode("map"), function()
    if EditMode then EditMode = false end
    if Camera then Camera.Open = false end
    MapMode = not MapMode
    SaveRequested = true
end)
-- F6: the camera settings (1.8), in the same panel; from F9 or F8 it goes there. camerarules.lua saves as they change.
if Camera then
    RegisterKeyBind(KeyCode("camera"), function()
        if EditMode then EditMode = false SaveRequested = true end
        if MapMode then MapMode = false SaveRequested = true end
        Camera.Open = not Camera.Open
    end)
end
local function MapPick(d)
    MapSel = MapSel + d
    if MapSel < 1 then MapSel = #MAP_ROWS end
    if MapSel > #MAP_ROWS then MapSel = 1 end
end
-- left and right: the zoom row zooms, Creatures steps through All, Enemies only and Off, In immersive mode through
-- Nothing, Map and Compass, every other row switches
local function MapChange(d)
    if not RuneMap then return end
    local S = RuneMap.Set
    local row = MAP_ROWS[MapSel]
    if row == "Zoom" then RuneMap.ZoomBy(d > 0 and 1 / 1.25 or 1.25)
    elseif row == "Drawing" then S.Smooth = not S.Smooth
    elseif row == "In immersive mode" then
        local st = 1   -- the place of the value in Settings.STAY
        for i, name in ipairs(Settings.STAY) do if name == S.Immersive then st = i end end
        S.Immersive = Settings.STAY[(st - 1 + (d > 0 and 1 or -1)) % #Settings.STAY + 1]
    elseif row == "Creatures" then
        local C = ById("creatures")
        local st = (not C.Visible) and 3 or (S.Neutral and 1 or 2)
        st = (st - 1 + (d > 0 and 1 or -1)) % 3 + 1
        C.Visible, S.Neutral = st ~= 3, st == 1
    else local k = MAP_SWITCH[row] S[k] = not S[k] end
    RuneMap.Dirty = true
end

-- RuneMap zoom, any time: ] closer, [ farther (Windows codes 221 and 219). The game has no buttons to click.
RegisterKeyBind(KeyCode("zoomin"), function() if RuneMap then RuneMap.ZoomBy(1 / 1.25) end end)
RegisterKeyBind(KeyCode("zoomout"), function() if RuneMap then RuneMap.ZoomBy(1.25) end end)

-- PgUp and PgDn go up and down the list as the panel shows it, by screen area (Order)
local function Sel(d)
    if not EditMode or #Order == 0 then return end
    local at = 1
    for n, i in ipairs(Order) do if i == Selected then at = n end end
    Selected = Order[(at - 1 + d) % #Order + 1]
end
RegisterKeyBind(VK.PgUp, function() Sel(-1) end)
RegisterKeyBind(VK.PgDn, function() Sel(1) end)

local function CamOpen() return Camera ~= nil and Camera.Open end
RegisterKeyBind(VK.Up, function() if CamOpen() then Camera.Pick(-1) elseif MapMode then MapPick(-1) else Move(0, -1) end end)
RegisterKeyBind(VK.Down, function() if CamOpen() then Camera.Pick(1) elseif MapMode then MapPick(1) else Move(0, 1) end end)
RegisterKeyBind(VK.Left, function() if CamOpen() then Camera.Change(-1) elseif MapMode then MapChange(-1) else Move(-1, 0) end end)
RegisterKeyBind(VK.Right, function() if CamOpen() then Camera.Change(1) elseif MapMode then MapChange(1) else Move(1, 0) end end)

local Steps = { 1, 5, 10, 25, 50, 100 }
local function ChangeStep(d)
    if not EditMode then return end
    local idx = 3
    for i, s in ipairs(Steps) do if s == Step then idx = i end end
    idx = math.max(1, math.min(#Steps, idx + d))
    Step = Steps[idx]
end
RegisterKeyBind(VK.Home, function() ChangeStep(1) end)
RegisterKeyBind(VK.End, function() ChangeStep(-1) end)

local function Resize(d)
    local E = Elements[Selected]
    if not EditMode then return end
    -- on the immersive line + / - set the wait before fading, 3 to 30 s (playtest, 29-09-2026); numbers only here
    if E.Wait then E.Wait = math.max(3, math.min(30, E.Wait + (d > 0 and 1 or -1))) return end
    if IsSwitch(E) or E.OnlyY then return end
    E.Scale = math.max(0.3, math.min(4.0, math.floor((E.Scale + d) * 100 + 0.5) / 100))   -- up to 400%
end
RegisterKeyBind(VK.Plus, function() Resize(0.05) end)     -- the number pad
RegisterKeyBind(VK.Minus, function() Resize(-0.05) end)
RegisterKeyBind(VK.Equals, function() Resize(0.05) end)   -- the main keys: = is + without Shift
RegisterKeyBind(VK.Dash, function() Resize(-0.05) end)

-- comma and period: less or more solid, in steps of 10%, down to 20% (1.1); hiding is Delete
local function Fade(d)
    local E = Elements[Selected]
    if not EditMode or IsSwitch(E) then return end
    E.Opacity = math.max(0.2, math.min(1.0, math.floor((E.Opacity + d) * 10 + 0.5) / 10))
end
RegisterKeyBind(VK.Comma, function() Fade(-0.1) end)
RegisterKeyBind(VK.Period, function() Fade(0.1) end)

-- F7: the next layout profile, only while the editor is open (the step saves this one and loads the next)
RegisterKeyBind(KeyCode("profile"), function() if EditMode then Prof.Wanted = true end end)

RegisterKeyBind(VK.Delete, function() if EditMode and not Elements[Selected].NoHide then Elements[Selected].Visible = false end end)
RegisterKeyBind(VK.Insert, function() if EditMode then Elements[Selected].Visible = true end end)
local NoDefaults = {}
RegisterKeyBind(VK.Backspace, function()
    if CamOpen() then Camera.ResetWanted = true return end   -- every camera row back to its default
    if MapMode and RuneMap then RuneMap.Reset() ById("creatures").Visible = true return end
    if not EditMode then return end
    local E = Elements[Selected]
    local d = Defaults[E.Id] or NoDefaults
    E.X, E.Y, E.Scale, E.Visible, E.Opacity = d.X or 0, d.Y or 0, d.Scale or 1.0, (d.Visible ~= false), 1.0
    if E.Wait then E.Wait = d.Wait end
    E.Moved = false
    TargetFromSpot(E)
end)

Log("loaded, press " .. KEY.editor .. " in game for the layout, " .. KEY.map .. " for the map" .. (KEY.camera and (", " .. KEY.camera .. " for the camera") or ""))
