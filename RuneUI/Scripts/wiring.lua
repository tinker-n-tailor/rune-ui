-- Which parts the mod has, in which order the step calls them, and what each one is handed (its ctx). main.lua loads this
-- file and calls Build once, before the timer starts; it gets back the parts that it reads itself. The order of the
-- AddPart calls is the order of the step: the buffs run before the map, and the immersive mode is the last that draws.
-- A part that does not load is only logged, and its AddPart does nothing.

local M = {}

-- H is what main.lua gives: the loading and the list of parts (LoadPart, AddPart), the log, the element list and its
-- starting layout, layout.lua's ById, the settings file (Settings, Cfg, SaveCfg), the names of the bound keys (Key), the editor's state (Ed), the helpers of
-- engine.lua, the retry rule (MayTry, Failed), the widget search (Finder), the layout writer (Apply), the F8 and F5
-- panels (MapPanel), the world watch (World), the bed watch (Beds) and the step (Step).
function M.Build(H)
    local LoadPart, AddPart, Log, Elements, ById, Defaults, Ed = H.LoadPart, H.AddPart, H.Log, H.Elements, H.ById, H.Defaults, H.Ed
    local Settings, Cfg, SaveCfg, MapPanel, Apply, Finder, World, Beds, Step = H.Settings, H.Cfg, H.SaveCfg, H.MapPanel, H.Apply, H.Finder, H.World, H.Beds, H.Step
    local Engine, MayTry, Failed = H.Engine, H.MayTry, H.Failed
    local Uniq, G, ClearOurs, Asset, SetColor, MakeText, CachedTex = Engine.Uniq, Engine.G, Engine.ClearOurs, Engine.Asset, Engine.SetColor, Engine.MakeText, Engine.CachedTex
    local FindPoppins, FindPoppinsMedium = Engine.FindPoppins, Engine.FindPoppinsMedium
    local ClassName, FindClass, FindQuiet = Finder.ClassName, Finder.FindClass, Finder.FindQuiet
    local Controller = World.Controller

    -- the parts, by their names here; loaded below, where the order of the list needs them
    local Avatar = nil    -- the level badge or character picture beside the bars, from avatar.lua
    local Bars = nil      -- the bars' look and the line under them, from bars.lua
    local Buffs = nil     -- the buffs under the bars, the buff row and the drink ring, from buffs.lua
    local RuneMap = nil   -- the minimap, from runemap.lua
    local Survival = nil  -- food, water and rest, from survival.lua; the buffs borrow its ring.
    local Immersive = nil -- the HUD fading when idle, from immersive.lua
    local MenuButtons = nil -- the menu buttons in rings, from menubuttons.lua
    local Aim = nil       -- the gold aim marks and lock-on diamond, from aim.lua
    local Cooldowns = nil -- the spell cooldown tiles, from cooldowns.lua
    local QuestTracker = nil -- the main and tracked quest under the minimap, from questtracker.lua
    local Party = nil     -- the health of the other players, from party.lua
    local Letters = nil   -- white letters with a shadow, from letters.lua
    local Ammo = nil      -- the ammo counter in a ring, from ammo.lua
    local Toolbar = nil   -- the tool bar as tiles, from toolbar.lua
    -- the immersive camera's settings, rules and F6 panel, from camerarules.lua. camera.lua and
    -- crosshair.lua use it. Its Open is the F6 panel, as Ed.Map is F8.
    local Camera = nil

    -- The pictures: each one that is missing or different is written into Art from Scripts/art.lua (pictures.lua).
    do
        local Pictures = LoadPart("pictures")   -- not loaded: the log says so, and the pictures in Art are used as they are
        if Pictures then Pictures.Write(LoadPart, Log, RUNEUI_DIR) end
    end
    Survival = LoadPart("survival")
    -- The parts that build on the game's widgets: the avatar, the bars and the buffs. They share the helpers
    -- through one table, and survival.lua's ring and Find. Listed first: their Scan runs in this order, and
    -- the buffs' step runs before the map's.
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
    if Camera then
        Camera.Attach(Settings.Section(Cfg, "camera"), SaveCfg)
        Camera.AttachMode(ById("immersive"), Defaults.immersive)   -- the two rows of the immersive mode in F6 are the layout's
    end
    if MapPanel then MapPanel.Attach({ RuneMap = RuneMap, Creatures = ById("creatures"), Stay = Settings.STAY, Drawing = Settings.DRAWING }) end
    -- Editing: the map shows while F9 or F8 is open, even when it is hidden
    local MapCtx = { Log = Log, ById = ById, Asset = Asset, Editing = function() return Ed.Edit or Ed.Map end, Scan = Step.ScanSoon,
        -- the immersive mode's share: the map fades itself, its gold rings too (runemap.lua ApplyOpacity)
        -- with the map setting "Keep in immersive mode" at Map, the map stays
        Fade = function()
            if RuneMap and RuneMap.Set.Immersive == "Map" then return 1 end
            return Immersive and Immersive.Factor(ById("runemap")) or 1
        end }
    AddPart("runemap", RuneMap, MapCtx)
    AddPart("survival", Survival, { Log = Log, ById = ById, ClearOurs = ClearOurs })
    if RuneMap then   -- the icon reads the time through the map's reader: one read serves both (runemap.lua ReadClock)
        AddPart("day and night icon", LoadPart("dial"), { Log = Log, ById = ById, Uniq = Uniq, ClearOurs = ClearOurs, CachedTex = CachedTex,
            MayTry = MayTry, Failed = Failed, ReadClock = RuneMap.ReadClock,
            On = function() return ById("dialskin").Visible end,
            -- F9 only: a hidden dial shows dimmed there, so it can be found and moved
            Editing = function() return Ed.Edit end })
    end
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
        Turn = Survival and Survival.Turn, Survival = Survival, ClearOurs = ClearOurs,
        -- the keys in Poppins, the game's own key font; found once and kept on the menu buttons table
        Text = function(tree, name, size, color, s)
            return MakeText(tree, name, size, color, s, FindPoppins())
        end,
        Chat = function() return FindClass("WBP_ClosedChat_C")[1] end, Pad = Apply.PadInUse }
    AddPart("menu buttons", MenuButtons, MenuCtx)
    do   -- Rune XP: the XP under the bars (xp.lua)
        local Xp = Survival and LoadPart("xp")   -- it finds the game's parts with survival.lua's Find
        AddPart("rune xp", Xp, { Log = Log, ById = ById, G = G, ClearOurs = ClearOurs, Asset = Asset, Font = FindPoppins,
            Find = Survival and Survival.Find, GoldLine = Util.GoldLine, Chain = Util.Chain,
            -- the slim level up (xp.lua): its switch, the level up element shown, and the editor closed (the editor writes the
            -- banner's opacity, which is the signal that it is on show)
            Slim = function() return ById("slimlevel").Visible and ById("levelup").Visible and not Ed.Edit end,
            MayTry = MayTry, Failed = Failed, Trim = function() return Bars and Bars.Trim.W end,
            Soon = ExecuteInGameThreadWithDelay,   -- one call on the game thread, a few ms from now
            On = function() return ById("runexp").Visible end })
    end
    Aim = LoadPart("aim")
    local AimCtx = { Log = Log, On = function() return ById("aim").Visible end,
        Reticle = function() return FindClass("WBP_HUD_ReticleWidget_C")[1] end,
        Orb = function() return FindClass("WBP_LockOnTargetOrb_C")[1] end }
    AddPart("aim", Aim, AimCtx)
    Cooldowns = LoadPart("cooldowns")
    if Cooldowns and Survival then   -- without survival.lua it has no Find
        -- the spell wheel's slices only: the spell book has a second wheel of the same slices (probe, 29-09-2026).
        -- With their names, as FindClass gives them.
        local SlicePath = { "WBP_Spellcasting_MainPanel_C_%d+%.WidgetTree_%d+%.SpellRadialWidget%.WidgetTree_%d+%.RadialSlice_%d+$" }
        AddPart("cooldowns", Cooldowns, { Log = Log, ById = ById, Find = Survival.Find, Survival = Survival, MayTry = MayTry, Failed = Failed,
            -- Editing: F9 only: with the map settings (F8) open the sample tiles would show too.
            On = function() return ById("cooldowns").Visible end, Editing = function() return Ed.Edit end,
            Horizontal = function() return ById("cdhoriz").Visible end,
            Slices = function() return FindClass("WBP_SurvivalSorcery_RadialSlice_C", SlicePath) end,
            Text = function(...) if MenuButtons then return MenuCtx.Text(...) end return MakeText(...) end })
    end
    if Survival then Ammo = LoadPart("ammo") end   -- it finds its parts with survival.lua's Find
    if Ammo then
        AddPart("ammo", Ammo, { Log = Log, ById = ById, Find = Survival.Find, TextsUnder = Survival.TextsUnder,
            Survival = Survival, ClearOurs = ClearOurs, MayTry = MayTry, Failed = Failed, Text = MenuCtx.Text })
    end
    Letters = LoadPart("letters")
    AddPart("letters", Letters, { Log = Log, Find = FindClass })
    Toolbar = LoadPart("toolbar")
    AddPart("toolbar", Toolbar, { Log = Log, ById = ById, G = G, Font = FindPoppins })
    do   -- a block: its names are not top-level locals
        local P, Embers = LoadPart("pickups"), LoadPart("embers")   -- embers.lua: the new item sparks, for the pick-ups and the unlock rows
        if P then AddPart("pickups", P, { Log = Log, Find = FindClass, Font = FindPoppins, Embers = Embers }) end
        P = LoadPart("farmplot") if P then AddPart("farm plots", P, { Log = Log, Find = FindClass }) end
        -- the enemy bars take the look of the player's bars; no switch, like the player's bars (enemybars.lua)
        P = LoadPart("enemybars")
        if P then
            AddPart("enemy bars", P, { Log = Log, Find = FindQuiet, MayTry = MayTry, Failed = Failed, Noise = Bars and Bars.OneColorNoise,
                InWorld = function() local V = ById("vitals").Instances[1] return V ~= nil and V:IsValid() end })
        end
        P = LoadPart("combattext")
        if P then AddPart("combat text", P, { Log = Log, Find = FindClass, MayTry = MayTry, Failed = Failed, Chain = Util.Chain,
            Soon = ExecuteInGameThreadWithDelay,
            On = function() return ById("combattext").Visible end }) end
        AddPart("death look", LoadPart("deathlook"), { Log = Log, Find = FindClass, MayTry = MayTry, Failed = Failed, Combat = P })   -- "You Died": red, bigger, above the band
        P = LoadPart("noticelook")   -- the look of the game's notices; noticestyle.lua holds its writes
        if P then AddPart("notice look", P, { Log = Log, Find = FindClass, Font = FindPoppinsMedium, Uniq = Uniq, CachedTex = CachedTex, Style = LoadPart("noticestyle"), Reads = LoadPart("noticeread"), Hud = ImmersiveCtx.Rings, Survival = Survival, Ring = LoadPart("noticering") }) end
        P = LoadPart("quests") if P then AddPart("quests", P, { Log = Log, Find = FindClass, Font = FindPoppins, Collect = Letters and Letters.Collect, Embers = Embers }) end
        local WP = LoadPart("wheelparts")   -- the writes that can be put back: the wheels
        P = LoadPart("wheels") if P then AddPart("wheels", P, { Log = Log, Find = FindClass, Font = FindPoppinsMedium, CachedTex = CachedTex, Parts = WP, Spells = LoadPart("wheelspells"), Meters = LoadPart("wheelmeters"), Books = LoadPart("wheelbooks"), G = G, On = function() return ById("wheels").Visible end }) end
        -- the id of the selected row while F9 is open; nil with the editor closed or F8 open
        local function SelectedId()
            local E = Ed.Edit and not Ed.Map and Elements[Ed.Selected]
            return E and E.Id or nil
        end
        P = LoadPart("notices")
        if P then
            -- before the preview: the editor opening ends the hint first, so the preview finds the tip's entry back at rest
            local Hint = LoadPart("hint")
            if Hint then
                AddPart("f9 hint", Hint, { Log = Log, Find = FindClass, Notices = P, Key = H.Key, General = Settings.Section(Cfg, "general"),
                    Save = SaveCfg, Editing = function() return Ed.Edit end,
                    -- the HUD is up: a live instance of the vitals element, as enemybars.lua waits for it
                    HudUp = function() local V = ById("vitals").Instances[1] return V ~= nil and V:IsValid() end })
            end
            AddPart("notices", P, { Log = Log, Find = FindClass, Selected = SelectedId })
        end
        QuestTracker = LoadPart("questtracker")
        if QuestTracker and Util.GoldLine then
            AddPart("quest tracker", QuestTracker, { Log = Log, ById = ById, Asset = Asset, GoldLine = Util.GoldLine, MayTry = MayTry, Failed = Failed,
                Text = function(tree, name, size, color, s)
                    return MakeText(tree, name, size, color, s, FindPoppinsMedium())
                end,
                -- F9 only, as the cooldowns: with the map settings (F8) open the made-up sample would show too
                Editing = function() return Ed.Edit end,
                On = function() return ById("questtracker").Visible end,
                ShowNext = function() return ById("questnext").Visible end,
                -- the game's quest and unlock notice is on show: its entry, made once in a world, is collapsed (1) at rest
                -- and not collapsed (3) while a notice plays (probe of 04-10-2026)
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
            AddPart("party panel", Party, { Log = Log, ById = ById, Controller = Controller, MayTry = MayTry, Failed = Failed,
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
                Soon = ExecuteInGameThreadWithDelay,   -- one call on the game thread, a few ms from now
                -- the game's compass on the screen: shown in the editor's list, the game's HUD up, and not faded out (by the
                -- immersive mode or by the editor's opacity); nil when not. Then its full name too, as the scan read it.
                Compass = function()
                    local E = ById("compass")
                    local W, V = E.Instances[1], ById("vitals").Instances[1]
                    if not (E.Visible and W and W:IsValid() and V and V:IsValid()) then return nil end
                    local ok, seen = pcall(function() return V:IsVisible() and W:IsVisible() and W:GetRenderOpacity() > 0 end)
                    if ok and seen then return W, E.Keys[1] end
                    return nil
                end,
                -- what is on the map screen: RuneMap is drawn (its own switch, the HUD, the immersive mode's fade)
                MapShown = function() return RuneMap ~= nil and RuneMap.Visible == true end,
                Set = function() return RuneMap and RuneMap.Set or {} end })
        end
        P = LoadPart("mapname")   -- the map setting "Player name": off hides your own player name beside your marker on the maps
        if P then
            AddPart("map name", P, { Log = Log, Find = FindQuiet, Arrived = Finder.TakeArrivals,
                On = function() return not RuneMap or RuneMap.Set.Name ~= false end })
        end
        P = LoadPart("bednames")
        if P then AddPart("bed names", P, { Log = Log, Hook = RegisterHook, Text = FText, Find = Beds.Find }) end
        -- the crosshair setting: "immersive mode on" is its row in F6, the switch
        local function ImmersiveOn() return ById("immersive").Visible end
        P = Camera and LoadPart("camera")
        if P then
            AddPart("camera", P, { Log = Log, Rules = Camera, Controller = Controller,
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
    -- the parts that the widget search and the layout's writing read: all loaded by now, and the first step comes with the timer
    Finder.Attach({ Buffs = Buffs, Survival = Survival, Avatar = Avatar, RuneMap = RuneMap, Cooldowns = Cooldowns,
        QuestTracker = QuestTracker, Party = Party })
    Apply.Attach({ Immersive = Immersive, Survival = Survival })
    return { Util = Util, Buffs = Buffs, Camera = Camera, RuneMap = RuneMap }
end

return M
