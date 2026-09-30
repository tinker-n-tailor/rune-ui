-- Rune UI: move, resize and hide parts of the Dragonwilds HUD, with a new minimap, survival rings and bars.
-- F9 opens the editor, F8 the map settings. A timer applies the layout; the selected element blinks and a panel lists the keys.

local VERSION = "1.2"
local LayoutFile = "runeui_layout.txt"   -- X,Y of inside elements mean a move on screen
local OldLayoutFile = "hudeditor_layout_v2.txt"   -- the mod's file before 0.60 (named HudEditor); read if no new one

local function Log(msg) print("[RuneUI] " .. msg .. "\n") end
Log("starting " .. VERSION)

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

-- One entry per movable thing. A widget belongs to one entry only, so nothing moves twice.
-- All positions are in HUD units, as on a 16:9 screen: 1920x1080 units at any resolution (2560x1440 = 1.333 px per
-- unit). A wider or narrower screen, or the game's HUD scale, gives the HUD another size (see Hud below).
-- Center, Size: where the visible part sits in the game's default layout (measured 27-09-2026 from screenshots and slots).
--   The editor draws its placeholder there, and Full elements scale around it.
-- A: the edge the game ties that spot to, from the slots (0 left or top, 0.5 middle, 1 right or bottom; the HUD log
--   of 29-09-2026). On a screen of another shape the spot moves with that edge.
-- Full: the widget covers the whole screen, so its scale pivot must be moved onto its visible part.
-- Inside: the widget lives inside another element; its X,Y still mean "moved from its own default spot on screen".
-- PathEnds/UseParent: for shared classes, keep only widgets whose path matches, then climb N parents.
-- Child: move only this named child of the widget's root, not the whole widget.
local Elements = {
    { Id="vitals",   Name="Health, stamina and shield bars", Classes={"WBP_HUD_PlayerVitalsBars_C"},
      Full=true, A={0.5,1}, Center={X=952, Y=967}, Size={X=330, Y=75} },
    { Id="avatar",   Name="Level badge / avatar",                         Custom=true,
      Inside="vitals", A={0.5,1}, Center={X=744.5, Y=967}, Size={X=69, Y=69} },
    { Id="weapon",   Name="Weapon buff",                    Classes={"WBP_HUD_WeaponEnhancements_C"},
      Inside="vitals", A={0.5,1}, Center={X=1316, Y=911}, Size={X=44, Y=44} },
    -- the area effects (Scorch, Imarus' gaze) sit in the row above the bars; with the bars at the top of the
    -- screen that row is off screen, so they move on their own. Centre read from in-game screenshot, 27-09-2026.
    { Id="region",   Name="Area effects (Scorch, Imarus)",  Classes={"WBP_ImarusGazeRadial_C", "WBP_RegionEffectRadial_C"},
      Inside="vitals", A={0.5,1}, Center={X=952, Y=911}, Size={X=44, Y=44} },
    { Id="survival", Name="Food, water and rest",           Classes={"WBP_SurvivalCore_Upkeep_C"},
      Inside="vitals", A={0,1}, Center={X=158, Y=968}, Size={X=215, Y=95} },
    { Id="toolbar",  Name="Tool bar",                       Classes={"WBP_Inventory_QuickAccesBar_C"},
      A={0,0}, Center={X=330, Y=110}, Size={X=545, Y=62} },
    { Id="compass",  Name="Compass",                        Classes={"WBP_HUD_Compass_C"},
      Full=true, A={0.5,0}, Center={X=960, Y=86}, Size={X=600, Y=120} },
    -- no element for the MiniMap addon's map any more: RuneMap replaces it, and the big map (M) and RuneMap's
    -- own map are of the same class, so hiding that element hid them too (27-09-2026)
    { Id="runemap",  Name="RuneMap",                       Custom="map",
      A={1,0}, Center={X=1792, Y=128}, Size={X=224, Y=224} },
    -- no widget of its own: hiding it in the editor turns the creature diamonds on RuneMap off
    { Id="creatures", Name="Creatures on RuneMap",          Custom="creatures",
      A={1,0}, Center={X=1792, Y=128}, Size={X=40, Y=40} },
    -- no widget of its own either: showing it shows the game's icons beside the bars (hidden at first)
    { Id="baricons", Name="Icons beside the bars",          Custom="baricons",
      A={0,0}, Center={X=110, Y=60}, Size={X=30, Y=70} },
    -- no widget of its own either: shown, the HUD fades when nothing happens (immersive.lua; off at first)
    { Id="immersive", Name="Immersive mode (fades when idle)", Custom="immersive",
      A={0,0}, Center={X=960, Y=540}, Size={X=40, Y=40} },
    -- no widget of its own either: shown, the aim marks are gold and the lock-on orb is our diamond (aim.lua)
    { Id="aim",      Name="Gold aim and lock-on",           Custom="aim",
      A={0,0}, Center={X=960, Y=540}, Size={X=40, Y=40} },
    { Id="daynight", Name="Time of day (game dial)",       Classes={"WBP_HUD_DayAndNight_C"},
      NoClip=true, Opaque=true, A={1,0}, Center={X=1698, Y=80}, Size={X=52, Y=52} },
    { Id="buffs",    Name="Buffs",                          Classes={"WBP_HUD_EffectsDisplayLists_C"},
      Full=true, A={0,1}, Center={X=151, Y=871}, Size={X=200, Y=85} },
    { Id="notify",   Name="Notifications",                  Classes={"WBP_HUD_Notifications_C"},
      Full=true, A={0.5,0.5}, Center={X=960, Y=540}, Size={X=400, Y=200} },
    { Id="xp",       Name="XP popup",                       Classes={"WBP_Notifications_ExperienceProgressContainer_C"},
      Inside="notify", A={0.5,0}, Center={X=960, Y=130}, Size={X=120, Y=95} },
    { Id="xpfloat",  Name="Floating XP",                    Classes={"WBP_FloatingExperienceContainer_C"},
      Inside="notify", A={0.5,0}, Center={X=860, Y=551}, Size={X=110, Y=40} },
    { Id="levelup",  Name="Level up",                       Classes={"WBP_LevelUpNotification_C"},
      Inside="notify", A={0.5,0.5}, Center={X=960, Y=300}, Size={X=500, Y=150} },
    { Id="area",     Name="New area",                       Classes={"WBP_AreaUnlockNotification_C"},
      Inside="notify", A={0.5,0.5}, Center={X=960, Y=250}, Size={X=700, Y=160} },
    { Id="banner",   Name="Title banner",                   Classes={"WBP_TitleBannerWidget_C"},
      A={0.5,0.5}, Center={X=960, Y=300}, Size={X=600, Y=120} },
    { Id="saving",   Name="Saving animation",               Classes={"WBP_SavingSpinner_C"},
      A={1,0}, Center={X=1738, Y=156}, Size={X=64, Y=64} },
    { Id="quests",   Name="Quests",                         Classes={"WBP_QuestAndUnlocks_C"},
      Inside="notify", A={1,0.5}, Center={X=1800, Y=420}, Size={X=240, Y=160} },
    { Id="prompts",  Name="Center prompts",                 Classes={"WBP_HeldActionWidget_C", "WBP_HUD_InteractionPrompt_C", "WBP_CallToActionWidget_C"},
      A={0.5,0.5}, Center={X=960, Y=640}, Size={X=300, Y=60} },
    { Id="armor",    Name="Armor warning",                  Classes={"WBP_ArmourDurabilityDisplay_C"},
      A={0,0}, Center={X=960, Y=540}, Size={X=200, Y=60} },
    { Id="itembrk",  Name="Item break warning",             Classes={"WBP_Notification_ItemBreak_C"},
      Inside="notify", A={0.5,0.5}, Center={X=960, Y=580}, Size={X=100, Y=30} },
    { Id="menuico",  Name="Menu icons",                     Classes={"WBP_HUD_CompositeVariableMenu_C"},
      Full=true, A={1,1}, Center={X=1668, Y=975}, Size={X=380, Y=95} },
    -- Parts: hiding it hides only the prompts, not the menu buttons that live inside it (see ApplyOne)
    { Id="legend",   Name="Attack and block prompts",       Classes={"WBP_HUD_InputsLegend_C"},
      Parts=true, Full=true, A={1,1}, Center={X=1780, Y=760}, Size={X=280, Y=200} },
    -- chat, map, spell book, building and bag: the row under the prompts, in rings (menubuttons.lua; design sketch
    -- A, 29-09-2026). Deep: the row is three levels down the legend's world page (widget dump, 29-09-2026).
    { Id="menubtn",  Name="Menu buttons (chat, map, bag)",  Classes={"WBP_InputLegend_World_C"},
      Child="HorizontalBox_436", Deep=true, Inside="legend", A={1,1}, Center={X=1659, Y=953}, Size={X=395, Y=123} },
    -- our own tiles, one per recovering spell (cooldowns.lua; design sketch C, 29-09-2026): left, middle height.
    -- Size: cooldowns.lua's box of six tiles.
    { Id="cooldowns", Name="Spell cooldowns",               Custom="cooldowns",
      A={0,0.5}, Center={X=70, Y=540}, Size={X=60, Y=400} },
    { Id="wheel",    Name="Wheel, arrow and R",             Classes={"WBP_DomInputIconWidget_C"},
      PathEnds={"WBP_Inventory_MainPanel_C_%d+%.WidgetTree_%d+%.RadialKBM$"}, UseParent=3,
      A={0,0}, Center={X=638, Y=120}, Size={X=30, Y=60} },
    -- the rune and arrow count of the staff and the bow: only its box moves, the crosshair stays in the middle
    -- (the reticles' trees, read in game 27-09-2026: VerticalBox_0 holds the ammo name and the count)
    { Id="ammo",     Name="Ammo counter",                   Classes={"WBP_ReticleMagic_C", "WBP_ReticleRangedADS_C"},
      Child="VerticalBox_0", NoClip=true, A={0.5,0.5}, Center={X=840, Y=551}, Size={X=80, Y=60} },
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
    xp={Y=55},
    levelup={Y=60, Scale=0.9},
    area={Y=40, Scale=0.85},
    saving={X=130, Y=750, Scale=0.8},
    ammo={X=250, Y=420},   -- right of the food and water rings, above the tool bar
    prompts={X=0, Y=-10}, armor={X=0, Y=-10}, itembrk={X=0, Y=-10}, menuico={X=0, Y=-40},
    legend={Visible=false}, wheel={Visible=false}, baricons={Visible=false}, immersive={Visible=false, Wait=8},
}

-- The edge an element follows on a screen of another shape (1.2, wide screens): the third of the screen it sits in,
-- left, middle or right (and top, middle or bottom). v is where it ends up, size the screen's.
local function Third(v, size) return v < size / 3 and 0 or v > size * 2 / 3 and 1 or 0.5 end
local function TargetFromSpot(E)   -- from where it sits on a 16:9 screen: for the defaults and older layout files
    E.TX, E.TY = Third(E.Center.X + E.X, 1920), Third(E.Center.Y + E.Y, 1080)
end

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

-- The screen in units (1.2, wide screens; Nexus reports of 29-09-2026). The viewport is its pixels over the DPI scale,
-- which follows the short side: 2560x1440 and 2560x1080 are both 1080 units high, 1920 and 2560 wide. The HUD sits in
-- a scale box set by the game's HUD scale, so the HUD is the viewport over that scale. RuneMap is on the viewport.
-- Read on every scan (ReadHud); 1920x1080 until then.
local Hud = { W = 1920, H = 1080, S = 1, VW = 1920, VH = 1080 }
local function OnViewport(E) return E.Custom == "map" or E.Custom == "creatures" or E.Custom == "cooldowns" end
-- how much wider and taller than 16:9 the space of E is
local function Grow(E)
    if OnViewport(E) then return Hud.VW - 1920, Hud.VH - 1080 end
    return Hud.W - 1920, Hud.H - 1080
end
-- An element the player moved follows the edge of the third it now sits in. Its spot on this screen stays put.
local function Retarget(E)
    local dW, dH = Grow(E)
    local fx, fy = E.Center.X + E.X + E.TX * dW, E.Center.Y + E.Y + E.TY * dH
    local tx, ty = Third(fx, 1920 + dW), Third(fy, 1080 + dH)
    E.X, E.Y = E.X + (E.TX - tx) * dW, E.Y + (E.TY - ty) * dH
    E.TX, E.TY = tx, ty
end

-- Elements with no widget of their own: they only switch something on or off
local function IsSwitch(E) return E.Custom == "creatures" or E.Custom == "baricons" or E.Custom == "immersive" or E.Custom == "aim" end

local function ById(id)
    for _, E in ipairs(Elements) do if E.Id == id then return E end end
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

local function LoadLayout()
    local f = io.open(LayoutFile, "r") or io.open(OldLayoutFile, "r")
    if not f then Log("no layout file yet, using defaults") return end
    for line in f:lines() do
        local id, x, y, s, v = string.match(line, "^(%w+):(%-?[%d%.]+),(%-?[%d%.]+),([%d%.]+),([01])")
        x, y, s = tonumber(x), tonumber(y), tonumber(s)
        -- a hand-edited line with a bad number is skipped: one nil here stopped the whole layout
        for _, E in ipairs(Elements) do
            if E.Id == id and x and y and s then
                E.X, E.Y = math.max(-4000, math.min(4000, x)), math.max(-4000, math.min(4000, y))
                E.Scale, E.Visible = math.max(0.3, math.min(4.0, s)), (v == "1")
                -- the opacity came in 1.1 as a fifth value: a line without it (an older file) stays solid
                local o = tonumber(string.match(line, "^%w+:[^,]+,[^,]+,[^,]+,[01],([%d%.]+)"))
                E.Opacity = o and math.max(0.2, math.min(1.0, math.floor(o * 10 + 0.5) / 10)) or 1.0
                -- the edge it follows came in 1.2 as the sixth and seventh; without them, from where it sits
                local tx, ty = string.match(line, "^%w+:[^,]+,[^,]+,[^,]+,[01],[^,]+,([%d%.]+),([%d%.]+)")
                tx, ty = tonumber(tx), tonumber(ty)
                if tx and ty then E.TX, E.TY = Third(tx, 1), Third(ty, 1) else TargetFromSpot(E) end
                -- the immersive wait came in 1.2 as the eighth value (its line only); without it, the default
                local w = tonumber(string.match(line, "^%w+:[^,]+,[^,]+,[^,]+,[01],[^,]+,[^,]+,[^,]+,([%d%.]+)"))
                if E.Wait and w then E.Wait = math.max(3, math.min(30, math.floor(w + 0.5))) end
            end
        end
    end
    f:close()
    Log("layout loaded")
end

local function SaveLayout()
    local f = io.open(LayoutFile, "w")
    if not f then Log("could not write layout") return end
    for _, E in ipairs(Elements) do
        if E.Moved then E.Moved = false Retarget(E) end
        f:write(string.format("%s:%.1f,%.1f,%.2f,%d,%.1f,%.1f,%.1f%s\n", E.Id, E.X, E.Y, E.Scale, E.Visible and 1 or 0,
            E.Opacity, E.TX, E.TY, E.Wait and string.format(",%d", E.Wait) or ""))
    end
    f:close()
    Log("layout saved")
end

LoadLayout()

---------------------------------------------------------------- finding widgets

-- The avatar: character picture, placed inside the game's bars widget (so it hides with the HUD
-- and moves with the bars). avatar.png sits next to the Scripts folder.
local Avatar = { W = nil, HostName = nil, Tex = nil }
local RuneMap = nil   -- the minimap, from runemap.lua; loaded near the main loop
local Survival = nil  -- food, water and rest, from survival.lua; the buffs borrow its ring. Loaded there too.
local Immersive = nil -- the HUD fading when idle, from immersive.lua; loaded there too
local MenuButtons = nil -- the menu buttons in rings, from menubuttons.lua; loaded there too
local Aim = nil       -- the gold aim marks and lock-on diamond, from aim.lua; loaded there too
local Cooldowns = nil -- the spell cooldown tiles, from cooldowns.lua; loaded there too (its ctx is Cooldowns.Ctx)
local Prompt = nil    -- the pick-up prompt's gold letters, from prompt.lua; loaded there too (ctx Prompt.Ctx)

local function ClassName(obj)
    local ok, n = pcall(function() return obj:GetClass():GetFName():ToString() end)
    return ok and n or "?"
end

-- One search for every widget per scan, sorted by class. One search per class (about 30) took up to 1 s on UE4SS
-- builds without hash tables: the stutter reports of 28-09-2026. This one took 45 ms and found the same widgets.
local Found = {}   -- class name -> widgets, from the last scan
-- class address -> class name: the name is read once per class, not once per widget (5000 widgets, 19 ms a scan
-- on a UE4SS with hash tables, 28-09-2026). Emptied on a new world, in case a class is unloaded and its address reused.
local ClassNames = {}
local function ClassAddress(W) return W:GetClass():GetAddress() end
-- FindClass's answers since the last search, by class and path: the parts ask for the same classes up to 5 times a
-- second (the spell slices, the chat, the aim), and between two searches the answer only loses widgets (30-09-2026)
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

-- Returns the widgets and, as a second list, their full names (read here once, so no caller reads them again).
-- A cached answer is checked for widgets gone since; the lists are shared, so callers only read them.
local function FindClass(className, pathEnds, useParent)
    local ck = className .. "|" .. (useParent or 0) .. "|" .. (pathEnds and table.concat(pathEnds, "|") or "")
    local hit = FindCache[ck]
    if hit then
        for i = #hit.W, 1, -1 do
            local ok, v = pcall(Valid, hit.W[i])
            if not (ok and v) then table.remove(hit.W, i) table.remove(hit.K, i) end
        end
        return hit.W, hit.K
    end
    local out, keys = {}, {}
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
    FindCache[ck] = { W = out, K = keys }
    return out, keys
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
local NextSearch = 0
-- A freed widget's slot can go to a new object that still reads valid, so the name is compared too (review of
-- 29-09-2026); AddInstance adds each widget and its name together. Avatar and RuneMap are ours and re-added each pass.
local function AnyGone()
    for _, E in ipairs(Elements) do
        if not E.Custom then
            for n, W in ipairs(E.Instances) do
                local ok, k = pcall(function() return W:IsValid() and W:GetFullName() end)
                if not (ok and k == E.Keys[n]) then return true end
            end
        end
    end
    return false
end
-- The buff lists' item count. Reading their entries straight from the lists gave nothing (in-game test,
-- 29-09-2026), but the count is a plain number.
local BuffItems, BuffsLogged = nil, false
local function BuffsChanged()
    local n = 0
    for _, W in ipairs(ById("buffs").Instances) do
        pcall(function()
            local root = W.WidgetTree.RootWidget
            for i = 0, root:GetChildrenCount() - 1 do
                local c = root:GetChildAt(i)
                local ok, k = pcall(function() return c:GetNumItems() end)
                if ok and type(k) == "number" then n = n + k end
            end
        end)
    end
    local changed = BuffItems ~= nil and n ~= BuffItems
    if changed and not BuffsLogged then BuffsLogged = true Log("buffs: " .. BuffItems .. " to " .. n .. ", searching at once") end
    BuffItems = n
    return changed
end

-- editing: F9 or F8 is open. Returns true when a search ran.
-- Without one, the game's widgets of the last pass are kept: AnyGone has just seen every one alive under its own
-- name, and the same answer cost a name read and a path check per widget, and a walk into the legend, every pass
-- (30-09-2026). Ours (the avatar, RuneMap, the cooldown tiles) are built after this in the same step, so they are
-- taken again on every pass.
local function FindAll(editing)
    local now = os.clock()
    local buffs = BuffsChanged()   -- read on every pass, so the count stays current
    local searched = false
    if now > NextSearch or now < SettleUntil + 30 or editing or buffs or AnyGone() then
        SearchWidgets()
        NextSearch = now + 10
        searched = true
    end
    for _, E in ipairs(Elements) do
        if E.Custom then
            E.Instances, E.Keys = {}, {}
            if E.Custom == true and Avatar.W and Avatar.W:IsValid() then AddInstance(E, Avatar.W) end
            if E.Custom == "map" and RuneMap and RuneMap.W and RuneMap.W:IsValid() then AddInstance(E, RuneMap.W) end
            if E.Custom == "cooldowns" and Cooldowns and Cooldowns.W and Cooldowns.W:IsValid() then AddInstance(E, Cooldowns.W) end
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
    pcall(ReadHud)
    return searched
end

---------------------------------------------------------------- applying the layout

local EditMode = false
local MapMode = false    -- F8: RuneMap's own settings, in the same panel as the editor (1.1)
local MapSel = 1         -- the selected line of the map settings
local Flash = true       -- the selected element blinks, so it is always clear what moves
local Selected = 1
local Step = 10
-- Keyed by the widget's full name: every rescan gives new Lua handles for the same widgets
local OrigOpacity = {}   -- opacity the game had before we touched a widget
local Touched = {}
local RestoreAllRequested = false

-- k: the widget's full name, read once per scan (FindAll)
local function SetOpacity(W, k, value)
    if OrigOpacity[k] == nil then
        local ok, o = pcall(function() return W:GetRenderOpacity() end)
        OrigOpacity[k] = ok and o or 1.0
    end
    W:SetRenderOpacity(value)
    Touched[k] = true
end

local function RestoreOpacity(W, k, force)
    if Touched[k] or force then
        W:SetRenderOpacity(OrigOpacity[k] or 1.0)
        Touched[k] = nil
    end
end

-- Where E's default spot is on this screen, in its own space: it moves with the edge the game ties it to (E.A)
local function Home(E)
    local dW, dH = Grow(E)
    return E.Center.X + E.A[1] * dW, E.Center.Y + E.A[2] * dH
end
-- E's move from there. X,Y are its move on a 16:9 screen; on another screen it follows its own edge (E.TX,TY)
local function Offset(E)
    local dW, dH = Grow(E)
    return E.X + (E.TX - E.A[1]) * dW, E.Y + (E.TY - E.A[2]) * dH
end
-- where E ends up, in viewport units: the editor's panel is on the viewport, a HUD unit is Hud.S of them
local function FinalCenter(E)
    local hx, hy = Home(E)
    local ox, oy = Offset(E)
    local u = OnViewport(E) and 1 or Hud.S
    return (hx + ox) * u, (hy + oy) * u
end

-- Move and size in the element's own space. For an element inside another one, undo the parent's move and
-- size, so X,Y and Scale still mean "where it ends up on screen": parent maps p to pivot + sP*(p - pivot) + tP.
local function LocalTransform(E)
    local ox, oy = Offset(E)
    if not E.Inside then return ox, oy, E.Scale end
    local P = ById(E.Inside)
    local sP = P.Scale
    local px, py = Offset(P)
    local vx, vy = Home(P)   -- the parent's scale pivot (every parent is Full)
    local cx, cy = Home(E)
    local tx = (cx + ox - px - vx) / sP + vx - cx
    local ty = (cy + oy - py - vy) / sP + vy - cy
    return tx, ty, E.Scale / sP
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
        local hx, hy = Home(E)
        local px, py = hx / Hud.W, hy / Hud.H
        if force or L.PX ~= px or L.PY ~= py then
            W:SetRenderTransformPivot({ X = px, Y = py })
            L.PX, L.PY = px, py
        end
    end
    if force or L.X ~= x or L.Y ~= y then W:SetRenderTranslation({ X = x, Y = y }) L.X, L.Y = x, y end
    if force or L.S ~= scale then W:SetRenderScale({ X = scale, Y = scale }) L.S = scale end
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
            if isSelected then o = E.Visible and (Flash and 1.0 or 0.35) or (Flash and 0.6 or 0.15) else o = E.Visible and 0.3 or 0.1 end
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
            if shown then SetOpacity(W, k, (Flash and 1.0 or 0.35) * fade) else SetOpacity(W, k, Flash and 0.6 or 0.15) end
        else
            SetOpacity(W, k, shown and 0.3 * fade or 0.1)
        end
    elseif not shown and not (MapMode and E.Custom == "map") then   -- F8 shows a hidden map
        SetOpacity(W, k, 0.0)
    elseif E.Opaque then
        W:SetRenderOpacity(fade)   -- the dial looked faded; keep it fully solid
    elseif fade * imm < 1.0 then
        SetOpacity(W, k, fade * imm)
    elseif RestoreAllRequested or next(Touched) ~= nil then
        RestoreOpacity(W, k, RestoreAllRequested)   -- leave the game's own fading alone when the element is shown
    end
end

local function ApplyAll(force)
    for i, E in ipairs(Elements) do
        local sel = EditMode and i == Selected
        local lx, ly, ls = LocalTransform(E)
        for n, W in ipairs(E.Instances) do ApplyOne(W, E.Keys[n], lx, ly, ls, E, sel, force) end
    end
    RestoreAllRequested = false
end

---------------------------------------------------------------- command panel, built from the game's own UI pieces

-- A dark panel with a thin gold frame, like the game's own panels. Built on the first F9, so a world exists.
local Overlay = { W = nil, Texts = {}, LastState = "", Open = false }
local LIST_ROWS = 10   -- also the F8 lines, 10 since the resource switches (29-09-2026)
local PANEL_AT = { X = 30, Y = 270 }   -- the editor: left side, under the avatar, bars and buffs

local C_GOLD  = { R = 0.89, G = 0.72, B = 0.38, A = 1.0 }
local C_CREAM = { R = 0.96, G = 0.92, B = 0.82, A = 1.0 }
local C_GREY  = { R = 0.66, G = 0.62, B = 0.55, A = 1.0 }
local C_DIM   = { R = 0.45, G = 0.42, B = 0.38, A = 1.0 }

local KEY_ROWS = {
    { "PgUp / PgDn",     "Select element" },
    { "Arrow keys",      "Move" },
    { "Home / End",      "Move step" },
    { "+ / -",           "Size" },
    { ", / .",           "Opacity" },
    { "Delete / Insert", "Hide / show" },
    { "Backspace",       "Reset element" },
    { "F8",              "Map settings" },
    { "F9",              "Save and close" },
}
-- F8 uses the same panel under the map (design sketch, 28-09-2026): its own title, keys and list
local MAP_KEY_ROWS = {
    { "Up / Down",    "Select setting" },
    { "Left / Right", "Change" },
    { "[ / ]",        "Zoom" },
    { "Backspace",    "Reset map settings" },
    { "F8",           "Save and close" },
}
local function KeyColumns(rows)
    local keys, acts = {}, {}
    for _, k in ipairs(rows) do table.insert(keys, k[1]) table.insert(acts, k[2]) end
    return table.concat(keys, "\n"), table.concat(acts, "\n")
end
local MAP_ROWS = { "RuneMap", "Faces north", "North mark", "Creatures", "Ore", "Herbs", "Essence", "Rare trees", "Zoom", "Drawing" }
-- the lines that are a plain On / Off, and the setting in runemap.lua each one flips
local MAP_SWITCH = { RuneMap = "Map", ["Faces north"] = "North", ["North mark"] = "Mark", Ore = "Ore", Herbs = "Herbs",
    Essence = "Essence", ["Rare trees"] = "Trees" }

local function Cls(path) return StaticFindObject(path) end

-- A font from the game itself. Poppins (the game's body font) is skipped on purpose, so the first other game
-- font wins; Poppins is only the fallback.
local GameFont = nil
local TitleFont = nil   -- Jancient, the game's fantasy display font, for the panel title
local function FindGameFont()
    pcall(function()
        local poppins = nil
        for _, F in pairs(FindAllOf("Font") or {}) do
            local n = F:GetFullName()
            if string.find(n, "/Game/") and not string.find(n, "Default__") then
                if string.find(n, "Jancient") then TitleFont = F end
                if string.find(n, "Poppins") then
                    poppins = poppins or F
                elseif not GameFont then
                    GameFont = { Object = F }
                end
            end
        end
        if not GameFont and poppins then GameFont = { Object = poppins } end
        if GameFont then Log("panel font: " .. GameFont.Object:GetFullName()) end
    end)
end

local function SetColor(T, c)
    T:SetColorAndOpacity({ SpecifiedColor = c, ColorUseRule = 0 })
end

local FontErrorLogged = false
local function MakeText(tree, name, size, color, s, font)
    local T = StaticConstructObject(Cls("/Script/UMG.TextBlock"), tree, FName(name))
    T:SetText(FText(s or ""))
    SetColor(T, color)
    pcall(function()
        T:SetShadowOffset({ X = 1, Y = 1 })
        T:SetShadowColorAndOpacity({ R = 0, G = 0, B = 0, A = 0.8 })
    end)
    local ok, err = pcall(function()
        local fi = T.Font   -- our own text, so changing it touches nothing of the game
        if font then fi.FontObject = font
        elseif GameFont then fi.FontObject = GameFont.Object end
        fi.Size = size
        T:SetFont(fi)
    end)
    if not ok and not FontErrorLogged then FontErrorLogged = true Log("panel font not set: " .. tostring(err)) end
    return T
end

local function AddTo(box, child, padBottom)
    local slot = box:AddChildToVerticalBox(child)
    pcall(function() slot:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = padBottom or 0 }) end)
end

-- Decorations from the main menu, taken from the blueprint templates (read only, copied into our widgets):
-- the gold frame of the worlds list, the trim line with diamonds under the PLAY menu, the gold sparkles
-- around the worlds frame, and the font of the main menu buttons.
local function FindTemplate(cls, pattern)
    for _, W in pairs(FindAllOf(cls) or {}) do
        local ok, n = pcall(function() return W:GetFullName() end)
        if ok and string.find(n, pattern, 1, true) then return W end
    end
end

-- The menu templates exist only while the main menu is loaded; in the world the game has already unloaded
-- them. So the mod writes down what it needs (asset paths and brush settings, plain values) while the menu
-- is up, and loads the assets again by path when it builds the panel.
local MenuArt = nil
local SaveMenuArt   -- defined further down; declared here so CaptureMenuArt can call it

local function BrushInfo(B)
    local r = { Res = B.ResourceObject:GetFullName():match("^%S+%s+(.+)$"), DrawAs = B.DrawAs,
        Margin = { Left = B.Margin.Left, Top = B.Margin.Top, Right = B.Margin.Right, Bottom = B.Margin.Bottom },
        Size = { X = B.ImageSize.X, Y = B.ImageSize.Y }, Tiling = B.Tiling }
    pcall(function()
        local c = B.TintColor.SpecifiedColor
        r.Tint = { R = c.R, G = c.G, B = c.B, A = c.A }
    end)
    return r
end

local function CaptureMenuArt()
    if MenuArt then return true end
    -- the worlds list's frame is there only while the main menu is up. Its picture is no longer drawn (the
    -- panels have the inventory look since 1.1), so it only says the menu is loaded.
    if not FindTemplate("Image", "WBP_MainMenu_Worlds_C:WidgetTree.ListImage") then return false end
    local art = {}
    pcall(function() art.Trim = BrushInfo(FindTemplate("Image", "WBP_MainMenu_LandingMenu_C:WidgetTree.Trim01").Brush) end)
    pcall(function()
        local sp = FindTemplate("NiagaraSystemWidget", "WBP_MainMenu_Worlds_Recent_C:WidgetTree.NS_UI_FrameParticles")
        art.Sparkle = sp.NiagaraSystemReference:GetFullName():match("^%S+%s+(.+)$")
    end)
    pcall(function()
        local T = FindTemplate("TextBlock", "WBP_DomMainMenuButtonLandingMenu_C:WidgetTree.")
        art.Font = { Res = T.Font.FontObject:GetFullName():match("^%S+%s+(.+)$"), Spacing = T.Font.LetterSpacing }
        pcall(function() art.Font.Typeface = T.Font.TypefaceFontName:ToString() end)
    end)
    MenuArt = art
    pcall(SaveMenuArt, art)
    Log("menu art saved: trim=" .. tostring(art.Trim and art.Trim.Res)
        .. " sparkle=" .. tostring(art.Sparkle) .. " font=" .. tostring(art.Font and art.Font.Res))
    return true
end

-- The saved menu art also goes to runeui_menuart.txt, so a reload of the mod in the middle of the game
-- (when the main menu is long gone) still has it. Brushes are written as plain numbers.
local ART_FILE = "runeui_menuart.txt"

function SaveMenuArt(art)
    local f = io.open(ART_FILE, "w")
    if not f then return end
    local function brush(key, b)
        if not b then return end
        local t = b.Tint or { R = 1, G = 1, B = 1, A = 1 }
        f:write(string.format("%s=%s|%s|%s,%s,%s,%s|%s,%s|%s|%s,%s,%s,%s\n", key, b.Res, tostring(b.DrawAs),
            b.Margin.Left, b.Margin.Top, b.Margin.Right, b.Margin.Bottom, b.Size.X, b.Size.Y, tostring(b.Tiling),
            t.R, t.G, t.B, t.A))
    end
    brush("trim", art.Trim)
    if art.Sparkle then f:write("sparkle=" .. art.Sparkle .. "\n") end
    if art.Font then f:write("font=" .. art.Font.Res .. "|" .. tostring(art.Font.Spacing) .. "|" .. tostring(art.Font.Typeface) .. "\n") end
    f:close()
end

local function LoadMenuArtFile()
    local f = io.open(ART_FILE, "r") or io.open("hudeditor_menuart.txt", "r")   -- the file before 0.60
    if not f then return nil end
    local art = {}
    local function split(s) local out = {} for p in string.gmatch(s, "([^|]+)") do table.insert(out, p) end return out end
    local function nums(s) local out = {} for n in string.gmatch(s, "[^,]+") do table.insert(out, tonumber(n)) end return out end
    -- a number in a range, or the default: the brush settings come from a file
    local function num(v, lo, hi, d) v = tonumber(v) if not v or v ~= v then return d end return math.max(lo, math.min(hi, v)) end
    for line in f:lines() do
        pcall(function()   -- a malformed line is skipped
            local key, rest = string.match(line, "^(%w+)=(.*)$")
            if key == "trim" then   -- a "frame" line from before 1.1 is skipped
                local p = split(rest)
                local m, s, c = nums(p[3]), nums(p[4]), nums(p[6])
                local b = { Res = p[1], DrawAs = math.floor(num(p[2], 0, 4, 3)), Tiling = math.floor(num(p[5], 0, 3, 0)),
                    Margin = { Left = num(m[1], 0, 1, 0), Top = num(m[2], 0, 1, 0), Right = num(m[3], 0, 1, 0), Bottom = num(m[4], 0, 1, 0) },
                    Size = { X = num(s[1], 1, 2048, 64), Y = num(s[2], 1, 2048, 64) },
                    Tint = { R = num(c[1], 0, 1, 1), G = num(c[2], 0, 1, 1), B = num(c[3], 0, 1, 1), A = num(c[4], 0, 1, 1) } }
                art.Trim = b
            elseif key == "sparkle" then
                local p = split(rest)
                art.Sparkle = p[1]
            elseif key == "font" then
                local p = split(rest)
                art.Font = { Res = p[1], Spacing = tonumber(p[2]), Typeface = (p[3] ~= "nil") and p[3] or nil }
            end
        end)
    end
    f:close()
    if next(art) then Log("menu art read from " .. ART_FILE) return art end
end

-- kind: the class the object must be, for the typed calls it goes into. The menu art paths are read back from
-- a file, and after a game patch another kind of object can sit at a saved path; the wrong kind can crash.
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

-- An Image widget showing a saved brush, or nil
local function ImageFromArt(tree, name, info, sizeFactor)
    if not info then return nil end
    local tex = Asset(info.Res, "/Script/Engine.Texture2D")
    if not tex then return nil end
    local img = StaticConstructObject(Cls("/Script/UMG.Image"), tree, FName(name))
    img:SetBrushFromTexture(tex, false)
    local b = img.Brush
    pcall(function() b.DrawAs = info.DrawAs end)
    pcall(function() b.Margin = info.Margin end)
    pcall(function() local k = sizeFactor or 1 b.ImageSize = { X = info.Size.X * k, Y = info.Size.Y * k } end)
    pcall(function() b.Tiling = info.Tiling end)
    pcall(function() if info.Tint then b.TintColor = { SpecifiedColor = info.Tint, ColorUseRule = 0 } end end)
    img:SetBrush(b)
    return img
end

local function FindMenuArt()
    if not MenuArt then MenuArt = LoadMenuArtFile() end
    return MenuArt or {}
end
local function BuildOverlay()
    local step = "user widget"
    local ok, err = pcall(function()
        FindGameFont()
        local outer = FindFirstOf("GameInstance")
        local uw = StaticConstructObject(Cls("/Script/UMG.UserWidget"), outer, G("RuneUIOverlay"))
        step = "widget tree"
        local tree = StaticConstructObject(Cls("/Script/UMG.WidgetTree"), uw, FName("RuneUITree"))
        uw.WidgetTree = tree
        step = "canvas"
        local canvas = StaticConstructObject(Cls("/Script/UMG.CanvasPanel"), tree, FName("RuneUICanvas"))
        tree.RootWidget = canvas
        step = "frame"
        -- The look of the game's inventory (Ivan, 29-09-2026): a dark, nearly solid panel inside a thin double
        -- gold line. Plain boxes, one inside the other: gold line, dark gap, gold line, dark panel. They fit any
        -- height, where the main menu's frame picture stretched with the panel (its title strip moved in F8) and
        -- let the world show through the text. Colours are linear light.
        local function Box(name, color, pad)
            local b = StaticConstructObject(Cls("/Script/UMG.Border"), tree, FName(name))
            b:SetBrushColor(color)
            b:SetPadding({ Left = pad, Top = pad, Right = pad, Bottom = pad })
            return b
        end
        local LINE, DARK = { R = 0.40, G = 0.26, B = 0.10, A = 0.9 }, { R = 0.011, G = 0.010, B = 0.009, A = 0.94 }
        local frame = Box("RuneUIFrame", LINE, 1)
        local gap = Box("RU_FrameGap", DARK, 3)
        local inner = Box("RU_FrameInner", LINE, 1)
        local panel = Box("RuneUIPanel", DARK, 0)
        panel:SetPadding({ Left = 22, Top = 18, Right = 22, Bottom = 20 })
        frame:SetContent(gap)
        gap:SetContent(inner)
        inner:SetContent(panel)
        step = "menu art"
        local art = FindMenuArt()   -- the trim lines, the sparkles and the title font
        local box = StaticConstructObject(Cls("/Script/UMG.VerticalBox"), tree, FName("RuneUIBox"))
        panel:SetContent(box)

        step = "texts"
        local title = MakeText(tree, "RU_Title", 17, C_GOLD, "RUNE UI", TitleFont)
        if art.Font then
            local okT, errT = pcall(function()
                local fi = title.Font
                local fo = Asset(art.Font.Res, "/Script/Engine.Font")
                if not fo then error("menu font not loaded") end
                fi.FontObject = fo
                pcall(function() if art.Font.Typeface then fi.TypefaceFontName = FName(art.Font.Typeface) end end)
                pcall(function() fi.LetterSpacing = art.Font.Spacing end)
                fi.Size = 17
                title:SetFont(fi)
            end)
            if not okT then Log("menu font not used: " .. tostring(errT)) end
        end
        AddTo(box, title, 4)
        -- the menu's trim line: under the title, and between the sections (chosen 27-09-2026)
        local function Divider(name, padTop, padBottom)
            if not art.Trim then return end
            local okL, errL = pcall(function()
                local line = ImageFromArt(tree, name, art.Trim)
                if not line then error("trim picture not loaded") end
                local lb = StaticConstructObject(Cls("/Script/UMG.SizeBox"), tree, FName(name .. "Box"))
                lb:SetHeightOverride(12)
                lb:SetContent(line)
                local slot = box:AddChildToVerticalBox(lb)
                pcall(function() slot:SetPadding({ Left = 0, Top = padTop, Right = 0, Bottom = padBottom }) end)
            end)
            if not okL then Log("menu trim not used: " .. tostring(errL)) end
        end
        Divider("RU_TitleTrim", 0, 10)
        Overlay.Texts.Selected = MakeText(tree, "RU_Selected", 13, C_CREAM, "")
        AddTo(box, Overlay.Texts.Selected, 2)
        Overlay.Texts.Info = MakeText(tree, "RU_Info", 11, C_GREY, "")
        AddTo(box, Overlay.Texts.Info, 0)
        Divider("RU_InfoTrim", 6, 8)

        pcall(function() Overlay.Texts.Info:SetAutoWrapText(true) end)   -- the F8 hints run to two lines
        Overlay.Texts.Title = title

        step = "keys"
        local row = StaticConstructObject(Cls("/Script/UMG.HorizontalBox"), tree, FName("RU_KeyRow"))
        local keys, acts = KeyColumns(KEY_ROWS)
        local keyText = MakeText(tree, "RU_Keys", 11, C_GOLD, keys)
        local actText = MakeText(tree, "RU_Actions", 11, C_CREAM, acts)
        Overlay.Texts.Keys, Overlay.Texts.Acts = keyText, actText
        local ks = row:AddChildToHorizontalBox(keyText)
        pcall(function() ks:SetPadding({ Left = 0, Top = 0, Right = 18, Bottom = 0 }) end)
        row:AddChildToHorizontalBox(actText)
        AddTo(box, row, 0)
        Divider("RU_KeysTrim", 6, 8)

        step = "element list"
        Overlay.Texts.ListTitle = MakeText(tree, "RU_ListTitle", 11, C_GOLD, "ELEMENTS")
        AddTo(box, Overlay.Texts.ListTitle, 4)
        Overlay.Texts.List = {}
        for r = 1, LIST_ROWS do
            local T = MakeText(tree, "RU_Row" .. r, 11, C_GREY, "")
            AddTo(box, T, 1)
            Overlay.Texts.List[r] = T
        end

        step = "placeholder"
        -- a see-through gold box with the name, on the selected element: shows where it is even when the
        -- element itself is not on screen (XP popup, level up, saving animation)
        local ph = StaticConstructObject(Cls("/Script/UMG.Border"), tree, FName("RU_Placeholder"))
        ph:SetBrushColor({ R = 0.95, G = 0.75, B = 0.35, A = 0.28 })
        ph:SetPadding({ Left = 4, Top = 2, Right = 4, Bottom = 2 })
        Overlay.PhText = MakeText(tree, "RU_PlaceholderText", 12, C_CREAM, "")
        ph:SetContent(Overlay.PhText)
        Overlay.PhSlot = canvas:AddChildToCanvas(ph)   -- added first, so the panel stays on top
        Overlay.PhSlot:SetAutoSize(false)
        Overlay.Ph = ph

        step = "position"
        -- fixed width, so the panel does not jump when a longer name is selected
        local sizer = StaticConstructObject(Cls("/Script/UMG.SizeBox"), tree, FName("RU_PanelWidth"))
        sizer:SetWidthOverride(400)
        local stack = StaticConstructObject(Cls("/Script/UMG.Overlay"), tree, FName("RU_PanelStack"))
        stack:AddChildToOverlay(frame)
        if art.Sparkle then
            local okS, errS = pcall(function()
                local sys = Asset(art.Sparkle, "/Script/Niagara.NiagaraSystem")
                local cls = Asset("/Script/NiagaraUIRenderer.NiagaraSystemWidget")
                if not (sys and cls) then error("sparkle effect not loaded") end
                local sp = StaticConstructObject(cls, tree, FName("RU_Sparkle"))
                sp.NiagaraSystemReference = sys
                pcall(function() sp.AutoActivate = true end)
                local s = stack:AddChildToOverlay(sp)
                s:SetHorizontalAlignment(0)   -- fill the whole panel
                s:SetVerticalAlignment(0)
                sp:SetVisibility(3)
                pcall(function() sp:UpdateNiagaraSystemReference(sys) end)
                pcall(function() sp:ActivateSystem(true) end)
            end)
            if okS then Log("menu sparkles on") else Log("menu sparkles not used: " .. tostring(errS)) end
        end
        sizer:SetContent(stack)
        local slot = canvas:AddChildToCanvas(sizer)
        slot:SetAutoSize(true)
        slot:SetPosition(PANEL_AT)
        step = "add to screen"
        uw:AddToViewport(1000)
        uw:SetVisibility(1)   -- collapsed until the editor opens
        Overlay.W, Overlay.Sizer, Overlay.Slot, Overlay.Mode = uw, sizer, slot, nil
    end)
    if ok then
        Log("panel ready")
        Overlay.Fails = 0
    else
        Failed(Overlay)
        Log("panel failed at step '" .. step .. "': " .. tostring(err))
    end
end

local PanelErrorLogged = false

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
    return S[MAP_SWITCH[row]] and "On" or "Off"
end
local MAP_HINTS = {
    RuneMap = { On = "The map is on. To only hide it, use Delete in F9.", Off = "The map is off. The mod does not build it at all." },
    ["Faces north"] = { On = "North stays at the top of the map.", Off = "The map turns with the camera." },
    ["North mark"] = { On = "The mark on the gold ring shows where north is.", Off = "No north mark on the ring." },
    Creatures = { All = "Red diamonds for enemies, green for neutral animals.", ["Enemies only"] = "Only enemies. Neutral animals are not shown.",
        Off = "No creature diamonds on the map." },
    Ore = { On = "Ore rocks near you. Empty rocks hide until they grow back.", Off = "No ore on the map." },
    Herbs = { On = "Wild herbs near you. A picked herb goes off the map.", Off = "No herbs on the map." },
    Essence = { On = "Rune essence near you.", Off = "No rune essence on the map." },
    ["Rare trees"] = { On = "Dead trees, yew, magic trees and anima bark near you.", Off = "No rare trees on the map." },
    Drawing = { Smooth = "The map draws every frame. Switching might decrease performance.",
        Faster = "The map draws every second frame. A bit choppy when you turn." },
}
local function MapHint(i, v)
    local row = MAP_ROWS[i]
    if row == "Zoom" then return "Closer or farther. The [ and ] keys do the same at any time." end
    return MAP_HINTS[row] and MAP_HINTS[row][v] or ""
end

-- The panel's title, keys and list when it switches between F9 and F8
local function SetPanelMode(mode)
    Overlay.Mode, Overlay.LastState, Overlay.PX, Overlay.PY = mode, "", nil, nil
    local keys, acts = KeyColumns(mode == "map" and MAP_KEY_ROWS or KEY_ROWS)
    Overlay.Texts.Title:SetText(FText(mode == "map" and "RUNE MAP" or "RUNE UI"))
    Overlay.Texts.Keys:SetText(FText(keys))
    Overlay.Texts.Acts:SetText(FText(acts))
    Overlay.Texts.ListTitle:SetText(FText(mode == "map" and "SETTINGS" or "ELEMENTS"))
    for r = 1, LIST_ROWS do
        Overlay.Texts.List[r]:SetVisibility((mode == "map" and r > #MAP_ROWS) and 1 or 4)
    end
    pcall(function() Overlay.Ph:SetVisibility(mode == "map" and 1 or 3) end)   -- the gold box is the editor's
    if mode ~= "map" then Overlay.Slot:SetPosition(PANEL_AT) end
end

-- F8: under the map, its right edge on the map's right edge; above the map when there is no room below
local function PlaceMapPanel()
    local E = ById("runemap")
    local cx, cy = FinalCenter(E)
    local half = E.Size.X / 2 * E.Scale
    local w, h = 400, 420
    pcall(function() local s = Overlay.Sizer:GetDesiredSize() if s.X > 1 and s.Y > 1 then w, h = s.X, s.Y end end)
    local x = math.max(10, math.min(Hud.VW - 10 - w, cx + half - w))
    local y = cy + half + 12
    if y + h > Hud.VH - 10 then y = math.max(10, cy - half - 12 - h) end
    x, y = math.floor(x + 0.5), math.floor(y + 0.5)
    if x ~= Overlay.PX or y ~= Overlay.PY then
        Overlay.PX, Overlay.PY = x, y
        Overlay.Slot:SetPosition({ X = x, Y = y })
    end
end

local function UpdateMapPanel()
    local vals = {}
    for i = 1, #MAP_ROWS do vals[i] = MapValue(i) end
    local state = MapSel .. "|" .. table.concat(vals, "|")
    if state ~= Overlay.LastState then
        Overlay.LastState = state
        Overlay.Texts.Selected:SetText(FText("Selected:  " .. MAP_ROWS[MapSel]))
        Overlay.Texts.Info:SetText(FText(MapHint(MapSel, vals[MapSel])))
        for r = 1, #MAP_ROWS do
            local T = Overlay.Texts.List[r]
            T:SetText(FText(((r == MapSel) and ">  " or "    ") .. MAP_ROWS[r] .. ":  " .. vals[r]))
            SetColor(T, r == MapSel and C_GOLD or C_GREY)
        end
    end
    PlaceMapPanel()   -- every step: the panel's height changes with the hint, and the map can move
end

local function UpdateEditPanel()
    local E = Elements[Selected]
    local state = table.concat({ Selected, E.X, E.Y, E.Scale, E.Opacity, Step, tostring(E.Visible), Hud.VW, Hud.VH, Hud.S,
        E.Wait or 0 }, "|")
    for i, El in ipairs(Elements) do state = state .. (El.Visible and "1" or "0") .. (#El.Instances > 0 and "f" or "n") end
    if state == Overlay.LastState then return end
    Overlay.LastState = state
    Overlay.Texts.Selected:SetText(FText("Selected:  " .. E.Name))
    Overlay.Texts.ListTitle:SetText(FText(string.format("ELEMENTS   %d / %d", Selected, #Elements)))
    if Overlay.PhSlot and E.Center then
        local sz = E.Scale * (OnViewport(E) and 1 or Hud.S)
        local w, h = E.Size.X * sz, E.Size.Y * sz
        local cx, cy = FinalCenter(E)
        Overlay.PhSlot:SetPosition({ X = cx - w / 2, Y = cy - h / 2 })
        Overlay.PhSlot:SetSize({ X = w, Y = h })
        Overlay.PhText:SetText(FText(E.Name))
    end
    if E.Wait then   -- the immersive line: + / - set the wait, not a size
        Overlay.Texts.Info:SetText(FText(string.format("Waits %d s before fading   (+ / - to change)%s", E.Wait,
            E.Visible and "" or "     OFF")))
    else
        Overlay.Texts.Info:SetText(FText(string.format("Size %d%%     Opacity %d%%     Move step %d%s",
            math.floor(E.Scale * 100 + 0.5), math.floor(E.Opacity * 100 + 0.5), Step, E.Visible and "" or "     HIDDEN")))
    end
    -- LIST_ROWS rows with the selected element near the middle; the list wraps around at both ends
    for r = 1, LIST_ROWS do
        local i = ((Selected - 1 + r - math.ceil(LIST_ROWS / 2)) % #Elements) + 1
        local El = Elements[i]
        local T = Overlay.Texts.List[r]
        local extra = ""
        if #El.Instances == 0 and not IsSwitch(El) then extra = "   (not on screen)" end
        if not El.Visible then extra = extra .. "   (hidden)" end
        T:SetText(FText(((i == Selected) and ">  " or "    ") .. El.Name .. extra))
        if i == Selected then SetColor(T, C_GOLD)
        elseif not El.Visible or (#El.Instances == 0 and not IsSwitch(El)) then SetColor(T, C_DIM)
        else SetColor(T, C_GREY) end
    end
end

local function UpdateOverlay()
    if Overlay.W and not Overlay.W:IsValid() then Overlay.W, Overlay.LastState, Overlay.Open = nil, "", false end
    local open = EditMode or MapMode
    -- like every other build: never into a world that is loading or not settled yet
    if open and not Overlay.W and MayTry(Overlay) and os.clock() > SettleUntil and LastController ~= "" then BuildOverlay() end
    if not Overlay.W then return end
    local ok, err = pcall(function()
        if not open then
            if Overlay.Open then Overlay.W:SetVisibility(1) Overlay.Open = false end   -- collapsed
            return
        end
        local mode = MapMode and "map" or "edit"
        if mode ~= Overlay.Mode then SetPanelMode(mode) end
        if MapMode then UpdateMapPanel() else UpdateEditPanel() end
        if not Overlay.Open then Overlay.W:SetVisibility(3) Overlay.Open = true end   -- shown, but clicks go through it
    end)
    if not ok and not PanelErrorLogged then PanelErrorLogged = true Log("panel update failed: " .. tostring(err)) end
end
---------------------------------------------------------------- buffs in a row

-- The buff list is a ListView. Its direction is fixed when the list is built, so the mod sets it to
-- horizontal and puts the list back into its box, which makes the game build it again sideways.
local BuffRowDone = {}
local function EnsureBuffRow()
    local B = ById("buffs")
    for n, W in ipairs(B.Instances) do
        local k = B.Keys[n]
        if not BuffRowDone[k] then
            BuffRowDone[k] = true
            local ok, err = pcall(function()
                local ov = W.WidgetTree.RootWidget
                local LV = ov:GetChildAt(0)
                local oldSlot = LV.Slot
                local p0 = oldSlot.Padding   -- copied to plain numbers: the old slot goes away with RemoveFromParent
                local h, v = oldSlot.HorizontalAlignment, oldSlot.VerticalAlignment
                local pad = { Left = p0.Left, Top = p0.Top, Right = p0.Right, Bottom = p0.Bottom }
                LV.Orientation = 0   -- horizontal
                pcall(function() LV:SetClipping(0) ov:SetClipping(0) end)
                LV:RemoveFromParent()
                local s = ov:AddChildToOverlay(LV)
                pcall(function() s:SetHorizontalAlignment(h) s:SetVerticalAlignment(v) s:SetPadding(pad) end)
                pcall(function() LV:RegenerateAllEntries() end)
            end)
            if ok then Log("buffs turned into a row") else Log("buff row failed: " .. tostring(err)) end
        end
    end
end

---------------------------------------------------------------- round buffs

-- Each buff entry is: SizeBox > Overlay > [icon, Overlay > [straight bar, title]]. The mod hides the bar
-- and the title, makes the entry square, and puts the ring of food, water and rest under the icon (Ivan's pick,
-- 29-09-2026, in place of the ring of dashes): dark back, coloured ring, dark centre. The bar's material holds
-- the time left; the ring shows that share. A buff without a timer (its bar is hidden by the game) gets a full ring.
-- The game's XP ring was tried first (27-09-2026): the row squashed it into an oval and the game drew it white.
local RING_BOX = 50    -- the ring; the row keeps the size of the dashes' box
local BUFF_GAP = 10    -- room between two rings (Ivan, 29-09-2026: they nearly touched)
local BUFF_ICON = 28   -- the game's icon in the ring's centre; its picture has an empty edge
-- Centred by the numbers, some of the game's pictures look high: their art sits high in its square (in-game test,
-- 27-09-2026: 3.5 at 32). Others are centred and sat 1.5 units low at 3.5 (the overeating face and the house,
-- Ivan's screenshot of 29-09-2026): 2 favours the centred ones. Optical, by picture; units at an icon of 32.
-- The new character's half sun (Fresh Start) is heavy at the bottom and looked low at 2 (Ivan, 29-09-2026).
local BUFF_NUDGE = { Default = 2, T_Icon_Sml_FreshStart = 0.5 }
local BuffPics = {}   -- the icon pictures already named in the log, once each
local BUFF_ART = { Back = "upkeep_back.png", Half = "upkeep_half.png", Centre = "upkeep_centre.png" }
-- the three pictures: the rings hold them; these handles are only reused while valid, and dropped with the world
local BuffArt = {}
local BuffDeco = {}          -- entry full name -> { W, Right, Left (the ring's halves), Bar, Lit }
local BuffParamLogged = false
-- a buff with no colour of its own: the sketch's #ffd173, as linear light
local C_RING_GOLD = { R = 1.0, G = 0.638, B = 0.168, A = 1.0 }

-- A picture from a file, kept in cache[key] and reused while it is valid. Widgets must hold it: a texture that
-- only Lua holds is thrown away by the engine. The buffs and the bars use it.
local function CachedTex(cache, key, outer, file)
    local tex = cache[key]
    if tex and tex:IsValid() then return tex end
    tex = StaticFindObject("/Script/Engine.Default__KismetRenderingLibrary"):ImportFileAsTexture2D(outer, file)
    if not (tex and tex:IsValid()) then error("picture not loaded: " .. file) end
    cache[key] = tex
    return tex
end

local function BuffTextures(outer)
    for k, file in pairs(BUFF_ART) do CachedTex(BuffArt, k, outer, "ue4ss/Mods/RuneUI/Art/" .. file) end
    return BuffArt
end

local function DecorateBuff(E)
    local k = E:GetFullName()
    if BuffDeco[k] then return end
    BuffDeco[k] = { W = E }
    if not Survival then return end   -- no ring to borrow: the buff keeps the game's look
    local ok, err = pcall(function()
        local tree = E.WidgetTree
        local box = tree.RootWidget
        local ov = box:GetContent()
        ClearOurs(ov, "RU_RingBox")   -- a ring of ours from an earlier round
        -- the game's two: the bar's Overlay and the icon. Found by class, not place: a decorated entry has
        -- the icon moved to the end.
        local icon, barBox
        for i = 0, ov:GetChildrenCount() - 1 do
            local c = ov:GetChildAt(i)
            if ClassName(c) == "Overlay" then barBox = c else icon = c end
        end
        if not (icon and barBox) then error("icon or bar not found") end
        local bar = barBox:GetChildAt(0)
        local art = BuffTextures(E)
        box:SetWidthOverride(RING_BOX + BUFF_GAP)   -- the ring stays in the middle: half the gap on each side
        box:SetHeightOverride(RING_BOX)
        barBox:SetRenderOpacity(0.0)   -- the straight bar and the title stay alive for the game, just unseen
        pcall(function() E:SetClipping(0) box:SetClipping(0) ov:SetClipping(0) end)   -- the list must not cut the ring
        local ring, right, left = Survival.Ring(tree, Uniq("RU_Ring"), RING_BOX, art, C_RING_GOLD)
        -- the list can give the entry less height than the ring: after leaving a house (in-game test,
        -- 29-09-2026) the dark pictures were squashed and the coloured ring cut. On a canvas the ring keeps its
        -- own size, centred on the entry like the icon.
        local canvas = StaticConstructObject(StaticFindObject("/Script/UMG.CanvasPanel"), tree, G("RU_RingCanvas"))
        local rs = canvas:AddChildToCanvas(ring)
        rs:SetAutoSize(false)
        rs:SetAnchors({ Minimum = { X = 0.5, Y = 0.5 }, Maximum = { X = 0.5, Y = 0.5 } })
        rs:SetAlignment({ X = 0.5, Y = 0.5 })
        rs:SetPosition({ X = 0, Y = 0 })
        rs:SetSize({ X = RING_BOX, Y = RING_BOX })
        local ringBox = StaticConstructObject(StaticFindObject("/Script/UMG.SizeBox"), tree, G("RU_RingBox"))
        ringBox:SetWidthOverride(RING_BOX)
        ringBox:SetHeightOverride(RING_BOX)
        ringBox:SetContent(canvas)
        local cs = ov:AddChildToOverlay(ringBox)
        cs:SetHorizontalAlignment(2) cs:SetVerticalAlignment(2)
        -- the icon goes on top of the ring: an Overlay draws its last child last. Icon and ring both sit on the
        -- entry's centre; top-left with padding put the icon ~4 units high (test of 27-09-2026).
        icon:RemoveFromParent()
        local is = ov:AddChildToOverlay(icon)
        is:SetHorizontalAlignment(2) is:SetVerticalAlignment(2)
        pcall(function() icon:SetDesiredSizeOverride({ X = BUFF_ICON, Y = BUFF_ICON }) end)
        pcall(function() icon:SetRenderTranslation({ X = 0, Y = BUFF_NUDGE.Default * BUFF_ICON / 32 }) end)   -- by picture: UpdateBuffRings
        BuffDeco[k].Right, BuffDeco[k].Left, BuffDeco[k].Bar, BuffDeco[k].Lit = right, left, bar, ""
        BuffDeco[k].Icon = icon
    end)
    if not ok then Log("round buff failed: " .. tostring(err)) end
end

-- Share of time left, 0..1, from the straight bar's material; nil when the buff has no timer
local BuffParam = nil
local function BuffShare(bar)
    local v = bar:GetVisibility()
    if v == 1 or v == 2 then return nil end
    local mid = bar.Brush.ResourceObject
    local vals = {}
    mid.ScalarParameterValues:ForEach(function(_, e)
        local p = e:get()
        vals[p.ParameterInfo.Name:ToString()] = p.ParameterValue
    end)
    if not BuffParamLogged then
        BuffParamLogged = true
        local names = {}
        for n, v in pairs(vals) do table.insert(names, n .. "=" .. string.format("%.2f", v)) end
        Log("buff bar material values: " .. table.concat(names, ", "))
        for n in pairs(vals) do
            local l = string.lower(n)
            if string.find(l, "progress") or string.find(l, "percent") or string.find(l, "fill") then BuffParam = n end
        end
        if not BuffParam then for n in pairs(vals) do BuffParam = BuffParam or n end end
        Log("buff ring reads " .. tostring(BuffParam))
    end
    local v = BuffParam and vals[BuffParam]
    if v == nil then return nil end
    return math.max(0, math.min(1, v))
end

-- from the last widget search, which runs at once when the number of buffs changes (FindAll)
local function FindBuffEntries()
    for _, E in ipairs(FindClass("WBP_HUD_StatusEffectListEntry_C")) do DecorateBuff(E) end
end

local function UpdateBuffRings()
    for k, d in pairs(BuffDeco) do
        if not (d.W and d.W:IsValid()) then
            BuffDeco[k] = nil
        elseif d.Right and not (d.Bar and d.Bar:IsValid() and d.Right:IsValid() and d.Left:IsValid()) then
            BuffDeco[k] = nil   -- the game rebuilt this entry; it is decorated again on the next scan
        elseif d.Right then
            local okS, share = pcall(BuffShare, d.Bar)
            if not okS or not share then share = 1 end   -- no timer: a full ring
            -- the buff's own colour from its bar ("Bar Color 1": poison green, slow yellow, 27-09-2026), already
            -- linear light; a list entry is reused for another buff, so it is read every time. Gold when there is none.
            local on = C_RING_GOLD
            pcall(function()
                d.Bar.Brush.ResourceObject.VectorParameterValues:ForEach(function(_, e)
                    local p = e:get()
                    if p.ParameterInfo.Name:ToString() == "Bar Color 1" then
                        local c = p.ParameterValue
                        on = { R = c.R, G = c.G, B = c.B, A = 1.0 }
                    end
                end)
            end)
            -- the icon's nudge by its picture (BUFF_NUDGE); an entry is reused for another buff, so it is read every time
            pcall(function()
                local pic = d.Icon.Brush.ResourceObject:GetFName():ToString()
                if pic == d.Pic then return end
                d.Pic = pic
                d.Icon:SetRenderTranslation({ X = 0, Y = (BUFF_NUDGE[pic] or BUFF_NUDGE.Default) * BUFF_ICON / 32 })
                if not BuffPics[pic] then BuffPics[pic] = true Log("buff icon: " .. pic) end
            end)
            local key = string.format("%.3f %.2f %.2f %.2f", share, on.R, on.G, on.B)
            if key ~= d.Lit then
                d.Lit = key
                d.Right:SetColorAndOpacity(on)
                d.Left:SetColorAndOpacity(on)
                Survival.Turn(d, share)
            end
        end
    end
end

---------------------------------------------------------------- avatar

local AVATAR_FILES = { "ue4ss/Mods/RuneUI/avatar.png" }

-- The player's power level, read from the level display of the inventory (it exists while the inventory is
-- closed too): SizeBox > Border > Overlay > [icon, text].
local function ReadPowerLevel()
    local D = FindClass("WBP_InventoryPowerLevelDisplay_C")[1]
    if not D then return nil end
    local ov = D.WidgetTree.RootWidget:GetContent():GetContent()
    local T = ov:GetChildAt(1)
    local icon = nil
    pcall(function() icon = ov:GetChildAt(0).Brush.ResourceObject end)
    return T:GetText():ToString(), T, icon
end

-- Level badge: the green diamond from the inventory with the level number, the default avatar.
local function BuildLevelBadge(tree)
    local ov = StaticConstructObject(StaticFindObject("/Script/UMG.Overlay"), tree, G("RU_LevelBadge"))
    local tex = Asset("/Game/Art/UI/PowerLevel/T_PowerLevel_AboveZone.T_PowerLevel_AboveZone", "/Script/Engine.Texture2D")
    if tex then
        local img = StaticConstructObject(StaticFindObject("/Script/UMG.Image"), tree, G("RU_LevelIcon"))
        img:SetBrushFromTexture(tex, false)
        Avatar.LevelIcon = img
        local s = ov:AddChildToOverlay(img)
        s:SetHorizontalAlignment(0) s:SetVerticalAlignment(0)
    end
    local txt = StaticConstructObject(StaticFindObject("/Script/UMG.TextBlock"), tree, G("RU_LevelText"))
    txt:SetText(FText("?"))
    SetColor(txt, { R = 1, G = 1, B = 1, A = 1 })
    pcall(function()
        txt:SetShadowOffset({ X = 1.5, Y = 1.5 })
        txt:SetShadowColorAndOpacity({ R = 0, G = 0, B = 0, A = 0.85 })
    end)
    pcall(function()
        local _, gameText = ReadPowerLevel()
        local fi = txt.Font
        if gameText then fi.FontObject = gameText.Font.FontObject end
        -- the editor title's font, from the main menu buttons (chosen 27-09-2026); the inventory font is the fallback
        pcall(function()
            local mf = FindMenuArt().Font
            local fo = mf and Asset(mf.Res, "/Script/Engine.Font")
            if not fo then return end
            fi.FontObject = fo
            if mf.Typeface then fi.TypefaceFontName = FName(mf.Typeface) end
        end)
        fi.Size = 26
        pcall(function() fi.OutlineSettings.OutlineSize = 2 fi.OutlineSettings.OutlineColor = { R = 0, G = 0, B = 0, A = 0.9 } end)
        txt:SetFont(fi)
    end)
    local ts = ov:AddChildToOverlay(txt)
    ts:SetHorizontalAlignment(2) ts:SetVerticalAlignment(2)   -- centre
    -- the menu font's line carries a deep descender, so its digits sit high. Only down, not sideways: at
    -- +2 a digit with a heavy right stroke (the 4) looked shifted right (in-game test, 27-09-2026)
    pcall(function() txt:SetRenderTranslation({ X = 0, Y = 2 }) end)
    Avatar.LevelText = txt
    return ov
end

local function EnsureAvatar()
    if not MayTry(Avatar) then return end
    local VE = ById("vitals")
    local V = VE.Instances[1]
    if not (V and V:IsValid()) then return end
    local hostName = VE.Keys[1]   -- its full name, read by the search
    if Avatar.W and Avatar.W:IsValid() and Avatar.HostName == hostName then
        -- keep the level number fresh
        if Avatar.LevelText then
            pcall(function()
                local lv, _, icon = ReadPowerLevel()
                if lv and lv ~= Avatar.LastLevel then Avatar.LastLevel = lv Avatar.LevelText:SetText(FText(lv)) end
                -- the game swaps the diamond's picture (colour) by your level against the area; follow it
                local iconName = icon and icon:GetFullName()
                if iconName and Avatar.LevelIcon and iconName ~= Avatar.LastIcon then
                    Avatar.LastIcon = iconName
                    Avatar.LevelIcon:SetBrushFromTexture(icon, false)
                end
            end)
        end
        return
    end
    local step = "texture"
    local ok, err = pcall(function()
        -- a picture only when the player put avatar.png in the mod folder; otherwise the level badge
        if not (Avatar.Tex and Avatar.Tex:IsValid()) and not Avatar.NoPicture then
            local KRL = StaticFindObject("/Script/Engine.Default__KismetRenderingLibrary")
            for _, file in ipairs(AVATAR_FILES) do
                local fh = io.open(file, "rb")
                if fh then
                    fh:close()
                    local okT, tex = pcall(function() return KRL:ImportFileAsTexture2D(V, file) end)
                    if okT and tex and tex:IsValid() then Avatar.Tex = tex Log("avatar picture loaded from " .. file) break end
                end
            end
            if not Avatar.Tex then Avatar.NoPicture = true Log("no avatar.png, showing the level badge") end
        end
        step = "image"
        local root = V.WidgetTree.RootWidget
        local img
        if Avatar.Tex then
            img = StaticConstructObject(StaticFindObject("/Script/UMG.Image"), V.WidgetTree, G("RU_Avatar"))
            img:SetBrushFromTexture(Avatar.Tex, false)
        else
            img = BuildLevelBadge(V.WidgetTree)
            Avatar.LastLevel = nil
        end
        step = "place"
        -- The bars widget's root is a full-screen Overlay. The bars sit in it centred and at the bottom, so the
        -- badge does too, next to the bars' left end: its box at 710,932 on a 16:9 screen. Pinned to the top left, it
        -- slid off the bars on a wide screen (Nexus, 29-09-2026). A centred child's middle is at half the width
        -- plus Left minus Right (not the middle of the room between the paddings: in-game test, 29-09-2026), and a
        -- bottom one's bottom edge is Bottom above the bottom. So Right = 960 - 744.5 and Bottom = 1080 - 1001.
        local box = StaticConstructObject(StaticFindObject("/Script/UMG.SizeBox"), V.WidgetTree, G("RU_AvatarBox"))
        box:SetWidthOverride(69)
        box:SetHeightOverride(69)
        box:SetContent(img)
        ClearOurs(root, "RU_AvatarBox")
        local slot = root:AddChildToOverlay(box)
        slot:SetHorizontalAlignment(2)   -- centre
        slot:SetVerticalAlignment(3)     -- bottom
        slot:SetPadding({ Left = 0, Top = 0, Right = 215.5, Bottom = 79 })
        Avatar.W, Avatar.HostName = box, hostName
    end)
    if ok then Log("avatar ready") Avatar.Fails = 0 else Failed(Avatar) Log("avatar failed at step '" .. step .. "': " .. tostring(err)) end
end

-- The trim line with the diamond from under the main menu's PLAY list, under the bars (design sketch,
-- 27-09-2026). It lives in the bars widget like the badge, so it moves and sizes with the bars.
local BarTrim = { HostName = nil }
local function EnsureBarTrim()
    if not MayTry(BarTrim) then return end
    local VE = ById("vitals")
    local V = VE.Instances[1]
    if not (V and V:IsValid()) or BarTrim.HostName == VE.Keys[1] then return end
    if not FindMenuArt().Trim then return end   -- not saved from the main menu yet; try again later
    local ok, err = pcall(function()
        local line = ImageFromArt(V.WidgetTree, Uniq("RU_BarTrim"), FindMenuArt().Trim)
        if not line then error("trim picture not loaded") end
        local box = StaticConstructObject(StaticFindObject("/Script/UMG.SizeBox"), V.WidgetTree, G("RU_BarTrimBox"))
        box:SetWidthOverride(330)   -- the bars' width; the picture is 335x17
        box:SetHeightOverride(17)
        box:SetContent(line)
        ClearOurs(V.WidgetTree.RootWidget, "RU_BarTrimBox")
        local slot = V.WidgetTree.RootWidget:AddChildToOverlay(box)
        -- just under the bars' bottom edge: its box at 787,1006 on a 16:9 screen. Centred and at the bottom like
        -- the bars and the badge (see EnsureAvatar), so it stays under the bars on a wide screen too:
        -- Right = 960 - 952 and Bottom = 1080 - 1023.
        slot:SetHorizontalAlignment(2)
        slot:SetVerticalAlignment(3)
        slot:SetPadding({ Left = 0, Top = 0, Right = 8, Bottom = 57 })
        BarTrim.HostName, BarTrim.W = VE.Keys[1], box   -- the immersive mode fades it with the bars
    end)
    if ok then Log("bar trim ready") BarTrim.Fails = 0 else Failed(BarTrim) Log("bar trim failed: " .. tostring(err)) end
end

-- The bars (design sketch without its diamonds, in-game review 27-09-2026): plain boxes: a dark track
-- behind each bar's fill and nothing else, stamina in green, health on top, and the icons beside
-- the bars hidden unless the editor shows them. The fill is the game's, in one colour (see OneColorFill).
-- The track is a picture drawn in nine pieces, one pixel to one unit, in place of the game's gold frame: its
-- outer pieces fit the frame's padding and stay empty, so the track sits right behind the fill. There is one picture for each
-- padding from 8 to 12. Widgets hold every picture, so the engine keeps them (a texture only Lua holds is
-- thrown away).
local BLADE_FILE = "ue4ss/Mods/RuneUI/Art/bar_blade_%d.png"
local BLADE_W, BLADE_CORE = 80, 16   -- keep as in tools/make-runemap-art.js
-- The game's gold stamina fill times this shows green: red down to 0.35 and blue to 0.6 on screen, in the
-- linear values the engine takes.
local STAMINA_GREEN = { R = 0.10, G = 1.0, B = 0.32, A = 1.0 }
local BARS = {
    { Class = "WBP_HUD_Vitals_StaminaBar_C", Icon = "StaminaIcon" },
    { Class = "WBP_HUD_Vitals_HealthBar_C", Icon = "HealthImage" },
    { Class = "WBP_HUD_Vitals_SpecialChargeBar_C", Icon = "SpecialAttackImage" },
}
local Blades = { HostName = nil, Tex = {}, Bars = {}, Missed = {}, Count = 0, Swapped = nil }

local function DressBar(B, W)
    local frame = W.ProgressBarImage:GetParent():GetParent()
    if ClassName(frame) ~= "Border" then error(B.Class .. ": the fill's frame is a " .. ClassName(frame)) end
    -- read before anything changes: the picture is chosen by the padding under the fill
    local p = frame.Padding
    Log(string.format("bar %s: frame padding %.1f %.1f %.1f %.1f", B.Class, p.Left, p.Top, p.Right, p.Bottom))
    local pad = math.floor(p.Bottom + 0.5)
    if pad < 8 or pad > 12 then error(B.Class .. ": no picture for a padding of " .. pad) end
    local h = pad * 2 + BLADE_CORE
    local file = string.format(BLADE_FILE, pad)
    frame:SetBrushFromTexture(CachedTex(Blades.Tex, file, W, file))
    local b = frame.Background
    b.DrawAs = 1   -- box: nine pieces
    b.Tiling = 0
    b.Margin = { Left = p.Left / BLADE_W, Top = pad / h, Right = p.Right / BLADE_W, Bottom = pad / h }
    b.ImageSize = { X = BLADE_W, Y = h }
    b.TintColor = { SpecifiedColor = { R = 1, G = 1, B = 1, A = 1 }, ColorUseRule = 0 }
    frame:SetBrush(b)
    frame:SetBrushColor({ R = 1, G = 1, B = 1, A = 1 })
end

-- Health on top: the stamina row and the health row swap places on screen. Only their drawn place moves
-- (render translation); the game's layout stays as it is. Checked on every scan: a row grows when the game
-- shows its regen number, and a size read before the first layout is 0.
local function SwapRows()
    local rs, rh = Blades.Bars[1]:GetParent(), Blades.Bars[2]:GetParent()
    local gap = 0
    pcall(function() gap = rs.Slot.Padding.Bottom + rh.Slot.Padding.Top end)
    local hs, hh = rs:GetDesiredSize().Y, rh:GetDesiredSize().Y
    if hs < 1 or hh < 1 then return end
    local key = string.format("%.1f %.1f %.1f", hs, hh, gap)
    if key == Blades.Swapped then return end
    rs:SetRenderTranslation({ X = 0, Y = hh + gap })
    rh:SetRenderTranslation({ X = 0, Y = -(hs + gap) })
    if not Blades.Swapped then Log(string.format("bars: health on top (rows %.0f and %.0f high, gap %.0f)", hs, hh, gap)) end
    Blades.Swapped = key
end

-- One color bars (1.2, Ivan's pick from the F7 tests of 29-09-2026, for everyone and with no switch): each bar's
-- shadow colour takes its main colour, so the fill shows one colour, and the texture is stronger. The texture's
-- setting is a power: the game's is 5, a lower one shows more, and 1.5 was his pick. The bubbles stay the game's.
-- The colours live on the fill's parent material, so the main colour is read there.
local ONE_COLOR_NOISE = 1.5
local OneColor = {}   -- by bar: the full name of the fill last given the look; the game may give a bar a new fill
local function OneColorFill(mat)
    local main
    mat.Parent.VectorParameterValues:ForEach(function(_, e)
        local p = e:get()
        if p.ParameterInfo.Name:ToString() == "Health Bar Main Color" then
            local c = p.ParameterValue
            main = { R = c.R, G = c.G, B = c.B, A = c.A }
        end
    end)
    if not main then error("no main colour on " .. mat:GetFullName()) end
    mat:SetVectorParameterValue(FName("Health Bar Shadows Color"), main)
    mat:SetScalarParameterValue(FName("Bar Noise Power"), ONE_COLOR_NOISE)
    return main
end

local function EnsureBlades()
    if not MayTry(Blades) then return end
    local VE = ById("vitals")
    local V = VE.Instances[1]
    if not (V and V:IsValid()) then return end
    local host = VE.Keys[1]   -- its full name, read by the search
    if Blades.HostName ~= host then
        Blades.HostName, Blades.Bars, Blades.Missed, Blades.Count, Blades.Swapped, Blades.NoNumbers = host, {}, {}, 0, nil, nil
        OneColor = {}   -- new bars: a fill of theirs may reuse an old name
    end
    local ok, err = pcall(function()
        -- a bar the game made again: forget the dead handle, find the new widget and swap the rows again
        for i = 1, #BARS do
            if Blades.Bars[i] and not Blades.Bars[i]:IsValid() then
                Blades.Bars[i], Blades.Count, Blades.Swapped, Blades.NoNumbers = nil, Blades.Count - 1, nil, nil
            end
        end
        if Blades.Count < #BARS then
            -- a full name is "Class /Path": a bar's path starts with the path of the bars widget
            local hostPath = (string.match(host, "^%S+%s+(.*)$") or host) .. "."
            for i, B in ipairs(BARS) do
                if not Blades.Bars[i] then
                    for _, W in ipairs(FindClass(B.Class)) do
                        if string.find(W:GetFullName(), hostPath, 1, true) then
                            local okD, errD = pcall(DressBar, B, W)
                            if not okD then Log("bars: " .. B.Class .. " keeps the game's frame: " .. tostring(errD)) end
                            Blades.Bars[i] = W
                            Blades.Count = Blades.Count + 1
                            break
                        end
                    end
                    if not Blades.Bars[i] and not Blades.Missed[i] then Blades.Missed[i] = true Log("bars: no " .. B.Class .. " yet") end
                end
            end
        end
        -- each part as soon as its bars are there: a missing special bar must not stop the others
        if Blades.Bars[1] and Blades.Bars[2] then SwapRows() end
        -- no numbers on the health bar (Ivan, 30-09-2026): unseen, not collapsed, so the immersive mode still reads them
        if Blades.Bars[2] and Survival and not Blades.NoNumbers then
            local texts = Survival.TextsUnder(Blades.Bars[2])
            for _, T in ipairs(texts) do pcall(function() T:SetRenderOpacity(0.0) end) end
            if #texts > 0 then   -- none yet: the bar is still being built, try on the next scan
                Blades.NoNumbers = true
                Log("bars: health numbers hidden (" .. #texts .. " texts)")
            end
        end
        if Blades.Bars[1] then
            -- stamina green, set again whenever the game resets it (taking a tool did, 27-09-2026)
            local fill = Blades.Bars[1].ProgressBarImage
            local c = fill.ColorAndOpacity
            if math.abs(c.R - STAMINA_GREEN.R) > 0.01 or math.abs(c.B - STAMINA_GREEN.B) > 0.01 then fill:SetColorAndOpacity(STAMINA_GREEN) end
        end
        -- one color: for each fill, again when the game gives a bar a new fill, and again when the game sets the
        -- fill's own look back (a new character, 29-09-2026: the bars went two-tone), read on every scan
        for i = 1, #BARS do
            local W = Blades.Bars[i]
            if W then
                local okC, errC = pcall(function()
                    local mat = W.ProgressBarImage.Brush.ResourceObject
                    local name = mat:GetFullName()
                    if OneColor["x" .. i] == name then return end   -- this fill failed once: not tried on every scan
                    if OneColor[i] == name then
                        local noise, shade
                        mat.ScalarParameterValues:ForEach(function(_, e)
                            local p = e:get()
                            if p.ParameterInfo.Name:ToString() == "Bar Noise Power" then noise = p.ParameterValue end
                        end)
                        mat.VectorParameterValues:ForEach(function(_, e)
                            local p = e:get()
                            if p.ParameterInfo.Name:ToString() == "Health Bar Shadows Color" then shade = p.ParameterValue end
                        end)
                        local was = OneColor["c" .. i]
                        if noise and math.abs(noise - ONE_COLOR_NOISE) < 0.01 and shade and was and math.abs(shade.R - was.R) < 0.01
                            and math.abs(shade.G - was.G) < 0.01 and math.abs(shade.B - was.B) < 0.01 then return end
                        if not OneColor.Reset then OneColor.Reset = true Log("bars: the game set the fill's look back; one color again") end
                    end
                    OneColor[i], OneColor["x" .. i] = name, name
                    OneColor["c" .. i] = OneColorFill(mat)
                    OneColor["x" .. i] = nil
                end)
                if not okC and not OneColor.Logged then OneColor.Logged = true Log("bars: one color failed: " .. tostring(errC)) end
            end
        end
        -- the icons: hidden, not collapsed, so the bars keep their place; checked on every scan in case the
        -- game sets them again
        local want = ById("baricons").Visible ~= false and 4 or 2
        for i, B in ipairs(BARS) do
            local W = Blades.Bars[i]
            if W then
                local icon = W[B.Icon]
                if icon:GetVisibility() ~= want then icon:SetVisibility(want) end
            end
        end
        -- the dark gradient behind the bars (T_Bars_Shadow; Ivan, 29-09-2026: it looks ugly): unseen, alive for the
        -- game. Hidden, not collapsed, so nothing moves. On a new character the game showed it again (29-09-2026),
        -- so both the visibility and the opacity are checked on every scan. Found by its name in the bars' widget
        -- tree, once per bars widget: GetWidgetFromName is not open to Lua in UE4SS 3.0.1 (log of 29-09-2026).
        local okS, errS = pcall(function()   -- on its own: a failure here must not count against the bars
            local shadow = Blades.ShadowW
            if Blades.ShadowHost ~= host or (shadow and not shadow:IsValid()) then
                shadow = Survival and Survival.Find(V, "ShadowBackgroundImage")
                -- none found while the bars are still coming: searched again on the next scan
                Blades.ShadowW = shadow
                if shadow or Blades.Count == #BARS then Blades.ShadowHost = host end
            end
            if not (shadow and shadow:IsValid()) then
                if Blades.ShadowHost == host then error("ShadowBackgroundImage not found") end
                return
            end
            if shadow:GetVisibility() ~= 2 or shadow:GetRenderOpacity() > 0 then
                if Blades.Shadow == host and not Blades.ShadowBack then Blades.ShadowBack = true Log("bars: the game showed the shadow again; hidden again") end
                shadow:SetVisibility(2)
                shadow:SetRenderOpacity(0.0)
                Blades.Shadow = host
            end
        end)
        if not okS and not Blades.ShadowLogged then Blades.ShadowLogged = true Log("bars: shadow not hidden: " .. tostring(errS)) end
    end)
    if ok then Blades.Fails = 0 else Failed(Blades) Log("bars failed: " .. tostring(err)) end
end

---------------------------------------------------------------- main loop, on a timer (the game has no per-frame hook we can use)

local LastScan = -100
local NextRings = 0
local NextArtTry = 0
local ApplyErrorLogged = false
local TickAlive = false
local SaveRequested = false

-- RuneMap and the survival rings live in their own files: an error in one is logged and the rest of the mod
-- still runs. UE4SS finds them by module name; the path is the
-- fallback.
local function LoadPart(name)
    local ok, m = pcall(require, name)
    if not ok then
        local ok2, m2 = pcall(dofile, "ue4ss/Mods/RuneUI/Scripts/" .. name .. ".lua")
        if ok2 then ok, m = true, m2 else m = tostring(m) .. " | " .. tostring(m2) end
    end
    if ok and type(m) == "table" then Log(name .. " file loaded") return m end
    Log(name .. " file not loaded: " .. tostring(m))
end

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
        local file = "ue4ss/Mods/RuneUI/Art/" .. name
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
RuneMap = LoadPart("runemap")
if RuneMap then RuneMap.Res = LoadPart("resources") end   -- ore, herbs, essence and rare trees on the map
Survival = LoadPart("survival")
-- Editing: the map shows while F9 or F8 is open, even when it is hidden
local MapCtx = { Log = Log, ById = ById, Asset = Asset, Editing = function() return EditMode or MapMode end,
    -- the immersive mode's share: the map fades itself, its gold rings too (runemap.lua ApplyOpacity)
    Fade = function() return Immersive and Immersive.Factor(ById("runemap")) or 1 end }
local SurvivalCtx = { Log = Log, ById = ById }
Immersive = LoadPart("immersive")
-- read fresh on every step: these handles change with the world
local ImmersiveCtx = { Log = Log, On = function() return ById("immersive").Visible end,
    Editing = MapCtx.Editing, Bars = function() return Blades.Bars end, Trim = function() return BarTrim.W end,
    BuffCount = function() return BuffItems end,
    Rings = function() return Survival and Survival.Rings and Survival.Rings() or {} end,
    Wait = function() return ById("immersive").Wait or 8 end,
    TextsUnder = function(W) return Survival and Survival.TextsUnder(W) or {} end,
    ChatCount = function() return MenuButtons and MenuButtons.Chat end }
if Survival then MenuButtons = LoadPart("menubuttons") end   -- it draws with survival.lua's ring
-- the survival ring and its turn, a text in the game's font, the chat widget
local MenuCtx = { Log = Log, ById = ById, Find = Survival and Survival.Find, Ring = Survival and Survival.Ring,
    Turn = Survival and Survival.Turn,
    -- the keys in Poppins, the game's own key font (sketch A); found once and kept on the menu buttons table
    Text = function(tree, name, size, color, s)
        if not MenuButtons.Poppins then   -- not found yet: looked for again on the next build
            for _, F in pairs(FindAllOf("Font") or {}) do
                local ok, n = pcall(function() return F:GetFullName() end)
                if ok and string.find(n, "/Game/") and string.find(n, "Poppins") and not string.find(n, "Default__") then MenuButtons.Poppins = F break end
            end
        end
        return MakeText(tree, name, size, color, s, MenuButtons.Poppins)
    end,
    Chat = function() return FindClass("WBP_ClosedChat_C")[1] end }
Aim = LoadPart("aim")
local AimCtx = { Log = Log, On = function() return ById("aim").Visible end,
    Reticle = function() return FindClass("WBP_HUD_ReticleWidget_C")[1] end,
    Orb = function() return FindClass("WBP_LockOnTargetOrb_C")[1] end,
    TargetIcons = function() return FindClass("WBP_TargetIcon_C") end }
Cooldowns = LoadPart("cooldowns")
if Cooldowns then
    Cooldowns.Ctx = { Log = Log, ById = ById, Find = Survival and Survival.Find,
        On = function() return ById("cooldowns").Visible end, Editing = MapCtx.Editing,
        -- the spell wheel's slices only: the spell book has a second wheel of the same slices (probe, 29-09-2026).
        -- With their names, as FindClass gives them.
        Slices = function() return FindClass("WBP_SurvivalSorcery_RadialSlice_C", Cooldowns.Ctx.SlicePath) end,
        SlicePath = { "WBP_Spellcasting_MainPanel_C_%d+%.WidgetTree_%d+%.SpellRadialWidget%.WidgetTree_%d+%.RadialSlice_%d+$" },
        Text = function(...) if MenuButtons then return MenuCtx.Text(...) end return MakeText(...) end }
end
Prompt = LoadPart("prompt")
if Prompt then
    Prompt.Ctx = { Log = Log, Find = Survival and Survival.Find,
        Prompts = function() return FindClass("WBP_HUD_InteractionPrompt_C") end }
end

-- A new world (quit to the main menu, entering a game): drop every handle the mod holds into the old one
-- before anything reads it. The engine frees the old world's objects while it loads the new one, and a
-- crash on quitting to the menu (27-09-2026) came from an old handle. The world is told apart by its player
-- controller; UE4SS's load-map hook crashed on its second call (27-09-2026), so it is not used.
-- sameWorld: a player restart inside a world that still stands, so our own map may be taken off the screen
local function ForgetWorld(sameWorld)
    for _, E in ipairs(Elements) do E.Instances, E.Keys, E.PartsOp, E.PartsW, E.Last = {}, {}, {}, {}, {} end
    Found, FindCache, NextSearch, BuffItems = {}, {}, 0, nil   -- the last widget search's handles; search again at once
    BuffDeco, BuffArt = {}, {}
    Avatar.W, Avatar.HostName, Avatar.Tex, Avatar.LevelText, Avatar.LevelIcon = nil, nil, nil, nil, nil
    Avatar.LastLevel, Avatar.LastIcon = nil, nil
    BarTrim.HostName, BarTrim.W = nil, nil
    Blades.HostName, Blades.Tex, Blades.Bars, Blades.ShadowW, Blades.ShadowHost = nil, {}, {}, nil, nil
    for _, P in ipairs({ Avatar, BarTrim, Blades, Overlay }) do P.Fails, P.RetryAt = 0, 0 end   -- new tries (see MayTry)
    Tint = {}   -- a HUD made again may reuse a name: set the opacity colour again, it costs one call per widget
    if not sameWorld then
        -- the editor panel of the old world is off the screen: build a new one on the next F9
        Overlay.W, Overlay.LastState, Overlay.Open, Overlay.Mode = nil, "", false, nil
        -- these remember widgets by full name; the old world's widgets are gone
        OrigOpacity, Touched, Unclipped, BuffRowDone, ClassNames, IsUW = {}, {}, {}, {}, {}, {}
    end
    if RuneMap then pcall(RuneMap.Forget, sameWorld) end
    if Survival then pcall(Survival.Forget) end
    if Immersive then pcall(Immersive.Forget) end
    if MenuButtons then pcall(MenuButtons.Forget) end
    if Aim then pcall(Aim.Forget) end
    if Cooldowns then pcall(Cooldowns.Forget, sameWorld) end
    if Prompt then pcall(Prompt.Forget) end
    Gen = Gen + 1
    SettleUntil = os.clock() + 3
    Log(sameWorld and "player restart: old handles dropped" or "new world: old handles dropped")
end
local LocalPlayer = nil   -- the local player object lives as long as the game
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
    Perf = { From = now, Ticks = 0, Sum = 0, Max = 0, Watch = 0, Scans = 0, ScanSum = 0, ScanMax = 0 }
    Fps.By = {}
end

local LoggedEditMode = false
local function TickBody()
    local now = os.clock()
    if not TickAlive then
        TickAlive = true
        Log("timer running" .. (IsInGameThread and (IsInGameThread() and " on the game thread" or " off the game thread") or ""))
    end
    if EditMode ~= LoggedEditMode then LoggedEditMode = EditMode Log(EditMode and "edit mode on" or "edit mode off") end
    WatchWorld()   -- first: nothing below may read a handle into a world that is gone
    Perf.Watch = Perf.Watch + (os.clock() - now)
    CountFrames(now)

    -- the widgets every 2 s, in the editor too: faster scans stuttered (27-09 and 28-09-2026). The full search
    -- inside runs less often (FindAll).
    local scanned = now - LastScan > 2.0
    if scanned then
        LastScan = now
        local scanFrom = os.clock()
        local okFind, errFind = pcall(FindAll, EditMode or MapMode)
        if not okFind and not ApplyErrorLogged then ApplyErrorLogged = true Log("finding widgets failed: " .. tostring(errFind)) end
        if now > SettleUntil then
            pcall(EnsureAvatar)
            pcall(EnsureBarTrim)
            pcall(EnsureBlades)
            pcall(EnsureBuffRow)
            pcall(FindBuffEntries)
        end
        local scan = os.clock() - scanFrom
        Perf.Scans, Perf.ScanSum, Perf.ScanMax = Perf.Scans + 1, Perf.ScanSum + scan, math.max(Perf.ScanMax, scan)
    end
    -- try every 3 s for the first 3 minutes (the main menu); a full scan of images is too heavy to repeat forever
    if not MenuArt and now < 180 and now > (NextArtTry or 0) then NextArtTry = now + 3 pcall(CaptureMenuArt) end

    if now > NextRings then NextRings = now + 0.5 pcall(UpdateBuffRings) end
    if RuneMap and now > 20 and now > SettleUntil then
        local okM, errM = pcall(RuneMap.Tick, MapCtx)
        if not okM and not RuneMap.ErrorLogged then RuneMap.ErrorLogged = true Log("runemap step failed: " .. tostring(errM)) end
    end
    if Survival and now > 20 and now > SettleUntil then
        local okS, errS = pcall(Survival.Tick, SurvivalCtx)
        if not okS and not Survival.ErrorLogged then Survival.ErrorLogged = true Log("survival step failed: " .. tostring(errS)) end
    end
    if MenuButtons and now > 20 and now > SettleUntil then
        local okB, errB = pcall(MenuButtons.Tick, MenuCtx)
        if not okB and not MenuButtons.ErrorLogged then MenuButtons.ErrorLogged = true Log("menu buttons step failed: " .. tostring(errB)) end
    end
    if Aim and now > 20 and now > SettleUntil then
        local okA, errA = pcall(Aim.Tick, AimCtx)
        if not okA and not Aim.ErrorLogged then Aim.ErrorLogged = true Log("aim step failed: " .. tostring(errA)) end
    end
    if Cooldowns and Cooldowns.Ctx.Find and now > 20 and now > SettleUntil then
        local okC, errC = pcall(Cooldowns.Tick, Cooldowns.Ctx)
        if not okC and not Cooldowns.ErrorLogged then Cooldowns.ErrorLogged = true Log("cooldowns step failed: " .. tostring(errC)) end
    end
    if Prompt and Prompt.Ctx.Find and now > 20 and now > SettleUntil then
        local okP, errP = pcall(Prompt.Tick, Prompt.Ctx)
        if not okP and not Prompt.ErrorLogged then Prompt.ErrorLogged = true Log("prompt step failed: " .. tostring(errP)) end
    end
    if Immersive and now > SettleUntil then   -- before ApplyAll, which reads its opacity
        local okI, errI = pcall(Immersive.Tick, ImmersiveCtx)
        if not okI and not Immersive.ErrorLogged then Immersive.ErrorLogged = true Log("immersive step failed: " .. tostring(errI)) end
    end
    Flash = (math.floor(now * 2.5) % 2 == 0)
    local okApply, errApply = pcall(ApplyAll, scanned)   -- a scan step writes every move and size again (ApplyOne)
    if not okApply and not ApplyErrorLogged then ApplyErrorLogged = true Log("apply failed: " .. tostring(errApply)) end

    if SaveRequested then SaveRequested = false SaveLayout() end

    UpdateOverlay()

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
if LoopInGameThreadWithDelay and ExecuteInGameThreadWithDelay
    and pcall(ExecuteInGameThreadWithDelay, 2000, function() LoopInGameThreadWithDelay(50, TimerStep) end) then
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
RegisterKeyBind(120, function()
    MapMode = false   -- F9 inside F8: from the map settings into the editor
    EditMode = not EditMode
    if not EditMode then
        SaveRequested = true
        RestoreAllRequested = true
    end
end)

-- F8: RuneMap's own settings (1.1). F8 inside F9 goes from the editor to the map settings. Closing saves the
-- layout, which holds the creatures switch; runemap.lua saves the other settings as they change.
RegisterKeyBind(119, function()
    if EditMode then EditMode = false RestoreAllRequested = true end
    MapMode = not MapMode
    SaveRequested = true
end)
local function MapPick(d)
    MapSel = MapSel + d
    if MapSel < 1 then MapSel = #MAP_ROWS end
    if MapSel > #MAP_ROWS then MapSel = 1 end
end
-- left and right: the zoom row zooms, Creatures steps through All, Enemies only and Off, every other row switches
local function MapChange(d)
    if not RuneMap then return end
    local S = RuneMap.Set
    local row = MAP_ROWS[MapSel]
    if row == "Zoom" then RuneMap.ZoomBy(d > 0 and 1 / 1.25 or 1.25)
    elseif row == "Drawing" then S.Smooth = not S.Smooth
    elseif row == "Creatures" then
        local C = ById("creatures")
        local st = (not C.Visible) and 3 or (S.Neutral and 1 or 2)
        st = (st - 1 + (d > 0 and 1 or -1)) % 3 + 1
        C.Visible, S.Neutral = st ~= 3, st == 1
    else local k = MAP_SWITCH[row] S[k] = not S[k] end
    RuneMap.Dirty = true
end

-- RuneMap zoom, any time: ] closer, [ farther (Windows codes 221 and 219). The game has no buttons to click.
RegisterKeyBind(221, function() if RuneMap then RuneMap.ZoomBy(1 / 1.25) end end)
RegisterKeyBind(219, function() if RuneMap then RuneMap.ZoomBy(1.25) end end)

local function Sel(d)
    if not EditMode then return end
    Selected = Selected + d
    if Selected < 1 then Selected = #Elements end
    if Selected > #Elements then Selected = 1 end
end
RegisterKeyBind(33, function() Sel(-1) end)
RegisterKeyBind(34, function() Sel(1) end)

local function Move(dx, dy)
    local E = Elements[Selected]
    if not EditMode or IsSwitch(E) then return end
    E.X, E.Y = E.X + dx * Step, E.Y + dy * Step
    E.Moved = true   -- on saving, it follows the edge nearest to where it now sits (Retarget)
end
RegisterKeyBind(38, function() if MapMode then MapPick(-1) else Move(0, -1) end end)
RegisterKeyBind(40, function() if MapMode then MapPick(1) else Move(0, 1) end end)
RegisterKeyBind(37, function() if MapMode then MapChange(-1) else Move(-1, 0) end end)
RegisterKeyBind(39, function() if MapMode then MapChange(1) else Move(1, 0) end end)

local Steps = { 1, 5, 10, 25, 50, 100 }
local function ChangeStep(d)
    if not EditMode then return end
    local idx = 3
    for i, s in ipairs(Steps) do if s == Step then idx = i end end
    idx = math.max(1, math.min(#Steps, idx + d))
    Step = Steps[idx]
end
RegisterKeyBind(36, function() ChangeStep(1) end)
RegisterKeyBind(35, function() ChangeStep(-1) end)

local function Resize(d)
    local E = Elements[Selected]
    if not EditMode then return end
    -- on the immersive line + / - set the wait before fading, 3 to 30 s (Ivan, 29-09-2026); numbers only here
    if E.Wait then E.Wait = math.max(3, math.min(30, E.Wait + (d > 0 and 1 or -1))) return end
    if IsSwitch(E) then return end
    E.Scale = math.max(0.3, math.min(4.0, math.floor((E.Scale + d) * 100 + 0.5) / 100))   -- up to 400%
end
RegisterKeyBind(107, function() Resize(0.05) end)
RegisterKeyBind(109, function() Resize(-0.05) end)
RegisterKeyBind(187, function() Resize(0.05) end)
RegisterKeyBind(189, function() Resize(-0.05) end)

-- comma and period: less or more solid, in steps of 10%, down to 20% (1.1); hiding is Delete
local function Fade(d)
    local E = Elements[Selected]
    if not EditMode or IsSwitch(E) then return end
    E.Opacity = math.max(0.2, math.min(1.0, math.floor((E.Opacity + d) * 10 + 0.5) / 10))
end
RegisterKeyBind(188, function() Fade(-0.1) end)
RegisterKeyBind(190, function() Fade(0.1) end)

RegisterKeyBind(46, function() if EditMode then Elements[Selected].Visible = false end end)
RegisterKeyBind(45, function() if EditMode then Elements[Selected].Visible = true end end)
local NoDefaults = {}
RegisterKeyBind(8, function()
    if MapMode and RuneMap then RuneMap.Reset() ById("creatures").Visible = true return end
    if not EditMode then return end
    local E = Elements[Selected]
    local d = Defaults[E.Id] or NoDefaults
    E.X, E.Y, E.Scale, E.Visible, E.Opacity = d.X or 0, d.Y or 0, d.Scale or 1.0, (d.Visible ~= false), 1.0
    if E.Wait then E.Wait = d.Wait end
    E.Moved = false
    TargetFromSpot(E)
end)

Log("loaded, press F9 in game for the layout, F8 for the map")
