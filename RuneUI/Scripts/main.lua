-- Rune UI: move, resize and hide parts of the Dragonwilds HUD, with a new minimap, survival rings and bars.
-- F9 opens the editor. A timer applies the layout; the selected element blinks and a panel lists the keys.

local VERSION = "1.0"
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
-- All positions are in HUD units: the screen is 1920x1080 units at any resolution (2560x1440 = 1.333 px per unit).
-- Center, Size: where the visible part sits in the game's default layout (measured 27-09-2026 from screenshots and slots).
--   The editor draws its placeholder there, and Full elements scale around it.
-- Full: the widget covers the whole screen, so its scale pivot must be moved onto its visible part.
-- Inside: the widget lives inside another element; its X,Y still mean "moved from its own default spot on screen".
-- PathEnds/UseParent: for shared classes, keep only widgets whose path matches, then climb N parents.
-- Child: move only this named child of the widget's root, not the whole widget.
local Elements = {
    { Id="vitals",   Name="Health, stamina and shield bars", Classes={"WBP_HUD_PlayerVitalsBars_C"},
      Full=true, Center={X=952, Y=967}, Size={X=330, Y=75} },
    { Id="avatar",   Name="Level badge / avatar",                         Custom=true,
      Inside="vitals", Center={X=744.5, Y=967}, Size={X=69, Y=69} },
    { Id="weapon",   Name="Weapon buff",                    Classes={"WBP_HUD_WeaponEnhancements_C"},
      Inside="vitals", Center={X=1316, Y=911}, Size={X=44, Y=44} },
    -- the area effects (Scorch, Imarus' gaze) sit in the row above the bars; with the bars at the top of the
    -- screen that row is off screen, so they move on their own. Centre read from in-game screenshot, 27-09-2026.
    { Id="region",   Name="Area effects (Scorch, Imarus)",  Classes={"WBP_ImarusGazeRadial_C", "WBP_RegionEffectRadial_C"},
      Inside="vitals", Center={X=952, Y=911}, Size={X=44, Y=44} },
    { Id="survival", Name="Food, water and rest",           Classes={"WBP_SurvivalCore_Upkeep_C"},
      Inside="vitals", Center={X=158, Y=968}, Size={X=215, Y=95} },
    { Id="toolbar",  Name="Tool bar",                       Classes={"WBP_Inventory_QuickAccesBar_C"},
      Center={X=330, Y=110}, Size={X=545, Y=62} },
    { Id="compass",  Name="Compass",                        Classes={"WBP_HUD_Compass_C"},
      Full=true, Center={X=960, Y=86}, Size={X=600, Y=120} },
    -- no element for the MiniMap addon's map any more: RuneMap replaces it, and the big map (M) and RuneMap's
    -- own map are of the same class, so hiding that element hid them too (27-09-2026)
    { Id="runemap",  Name="RuneMap",                       Custom="map",
      Center={X=1792, Y=128}, Size={X=224, Y=224} },
    -- no widget of its own: hiding it in the editor turns the creature diamonds on RuneMap off
    { Id="creatures", Name="Creatures on RuneMap",          Custom="creatures",
      Center={X=1792, Y=128}, Size={X=40, Y=40} },
    -- no widget of its own either: showing it shows the game's icons beside the bars (hidden at first)
    { Id="baricons", Name="Icons beside the bars",          Custom="baricons",
      Center={X=110, Y=60}, Size={X=30, Y=70} },
    { Id="daynight", Name="Time of day (game dial)",        Classes={"WBP_HUD_DayAndNight_C"},
      NoClip=true, Opaque=true, Center={X=1698, Y=80}, Size={X=52, Y=52} },
    { Id="buffs",    Name="Buffs",                          Classes={"WBP_HUD_EffectsDisplayLists_C"},
      Full=true, Center={X=151, Y=871}, Size={X=200, Y=85} },
    { Id="notify",   Name="Notifications",                  Classes={"WBP_HUD_Notifications_C"},
      Full=true, Center={X=960, Y=540}, Size={X=400, Y=200} },
    { Id="xp",       Name="XP popup",                       Classes={"WBP_Notifications_ExperienceProgressContainer_C"},
      Inside="notify", Center={X=960, Y=130}, Size={X=120, Y=95} },
    { Id="xpfloat",  Name="Floating XP",                    Classes={"WBP_FloatingExperienceContainer_C"},
      Inside="notify", Center={X=860, Y=551}, Size={X=110, Y=40} },
    { Id="levelup",  Name="Level up",                       Classes={"WBP_LevelUpNotification_C"},
      Inside="notify", Center={X=960, Y=300}, Size={X=500, Y=150} },
    { Id="area",     Name="New area",                       Classes={"WBP_AreaUnlockNotification_C"},
      Inside="notify", Center={X=960, Y=250}, Size={X=700, Y=160} },
    { Id="banner",   Name="Title banner",                   Classes={"WBP_TitleBannerWidget_C"},
      Center={X=960, Y=300}, Size={X=600, Y=120} },
    { Id="saving",   Name="Saving animation",               Classes={"WBP_SavingSpinner_C"},
      Center={X=1738, Y=156}, Size={X=64, Y=64} },
    { Id="quests",   Name="Quests",                         Classes={"WBP_QuestAndUnlocks_C"},
      Inside="notify", Center={X=1800, Y=420}, Size={X=240, Y=160} },
    { Id="prompts",  Name="Center prompts",                 Classes={"WBP_HeldActionWidget_C", "WBP_HUD_InteractionPrompt_C", "WBP_CallToActionWidget_C"},
      Center={X=960, Y=640}, Size={X=300, Y=60} },
    { Id="armor",    Name="Armor warning",                  Classes={"WBP_ArmourDurabilityDisplay_C"},
      Center={X=960, Y=540}, Size={X=200, Y=60} },
    { Id="itembrk",  Name="Item break warning",             Classes={"WBP_Notification_ItemBreak_C"},
      Inside="notify", Center={X=960, Y=580}, Size={X=100, Y=30} },
    { Id="menuico",  Name="Menu icons",                     Classes={"WBP_HUD_CompositeVariableMenu_C"},
      Full=true, Center={X=1668, Y=975}, Size={X=380, Y=95} },
    { Id="legend",   Name="Attack and block prompts",       Classes={"WBP_HUD_InputsLegend_C"},
      Full=true, Center={X=1780, Y=760}, Size={X=280, Y=200} },
    { Id="wheel",    Name="Wheel, arrow and R",             Classes={"WBP_DomInputIconWidget_C"},
      PathEnds={"WBP_Inventory_MainPanel_C_%d+%.WidgetTree_%d+%.RadialKBM$"}, UseParent=3,
      Center={X=638, Y=120}, Size={X=30, Y=60} },
    -- the rune and arrow count of the staff and the bow: only its box moves, the crosshair stays in the middle
    -- (the reticles' trees, read in game 27-09-2026: VerticalBox_0 holds the ammo name and the count)
    { Id="ammo",     Name="Ammo counter",                   Classes={"WBP_ReticleMagic_C", "WBP_ReticleRangedADS_C"},
      Child="VerticalBox_0", NoClip=true, Center={X=840, Y=551}, Size={X=80, Y=60} },
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
    legend={Visible=false}, wheel={Visible=false}, baricons={Visible=false},
}

for _, E in ipairs(Elements) do
    local d = Defaults[E.Id] or {}
    E.X, E.Y, E.Scale = d.X or 0, d.Y or 0, d.Scale or 1.0
    E.Visible = (d.Visible ~= false)
    E.Instances, E.Keys = {}, {}
end

-- Elements with no widget of their own: they only switch something on or off
local function IsSwitch(E) return E.Custom == "creatures" or E.Custom == "baricons" end

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
        f:write(string.format("%s:%.1f,%.1f,%.2f,%d\n", E.Id, E.X, E.Y, E.Scale, E.Visible and 1 or 0))
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

local function ClassName(obj)
    local ok, n = pcall(function() return obj:GetClass():GetFName():ToString() end)
    return ok and n or "?"
end

local function FindClass(className, pathEnds, useParent)
    local out = {}
    local found = FindAllOf(className)
    if not found then return out end
    for _, W in pairs(found) do
        -- one object that cannot be read (a world being unloaded) must not stop the whole scan (27-09-2026)
        pcall(function()
            if not (W and W:IsValid()) then return end
            local full = W:GetFullName()
            local ok = not pathEnds
            if pathEnds then
                for _, p in ipairs(pathEnds) do if string.find(full, p) then ok = true end end
            end
            if ok and string.find(full, "/Engine/Transient%.") then   -- live widgets only; /Game paths are templates
                for _ = 1, (useParent or 0) do
                    local okp, P = pcall(function() return W:GetParent() end)
                    if okp and P and P:IsValid() then W = P end
                end
                table.insert(out, W)
            end
        end)
    end
    return out
end

-- A found widget and its full name, which keys the opacity and clipping memory
local function AddInstance(E, W)
    local ok, k = pcall(function() return W:GetFullName() end)
    if ok and k then table.insert(E.Instances, W) table.insert(E.Keys, k) end
end

local function FindAll()
    for _, E in ipairs(Elements) do
        E.Instances, E.Keys = {}, {}
        if E.Custom == true and Avatar.W and Avatar.W:IsValid() then AddInstance(E, Avatar.W) end
        if E.Custom == "map" and RuneMap and RuneMap.W and RuneMap.W:IsValid() then AddInstance(E, RuneMap.W) end
        for _, c in ipairs(E.Classes or {}) do
            for _, W in ipairs(FindClass(c, E.PathEnds, E.UseParent)) do
                if E.Child then
                    local found
                    pcall(function()
                        local root = W.WidgetTree.RootWidget
                        for i = 0, root:GetChildrenCount() - 1 do
                            local ch = root:GetChildAt(i)
                            if ch:GetFName():ToString() == E.Child then found = ch break end
                        end
                    end)
                    W = found
                end
                if W then AddInstance(E, W) end
            end
        end
    end
end

---------------------------------------------------------------- applying the layout

local EditMode = false
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

-- Move and size in the element's own space. For an element inside another one, undo the parent's move and
-- size, so X,Y and Scale still mean "where it ends up on screen": parent maps p to pivot + sP*(p - pivot) + tP.
local function FinalCenter(E)
    return E.Center.X + E.X, E.Center.Y + E.Y
end

local function LocalTransform(E)
    if not E.Inside then return E.X, E.Y, E.Scale end
    local P = ById(E.Inside)
    local sP, pv, c = P.Scale, P.Center, E.Center
    local tx = (c.X + E.X - P.X - pv.X) / sP + pv.X - c.X
    local ty = (c.Y + E.Y - P.Y - pv.Y) / sP + pv.Y - c.Y
    return tx, ty, E.Scale / sP
end

local Unclipped = {}
local function ApplyOne(W, k, x, y, scale, E, isSelected)
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
    if E.Full and E.Center then
        W:SetRenderTransformPivot({ X = E.Center.X / 1920, Y = E.Center.Y / 1080 })
    end
    W:SetRenderTranslation({ X = x, Y = y })
    W:SetRenderScale({ X = scale, Y = scale })
    if EditMode then
        if isSelected then
            if E.Visible then SetOpacity(W, k, Flash and 1.0 or 0.35) else SetOpacity(W, k, Flash and 0.6 or 0.15) end
        else
            SetOpacity(W, k, E.Visible and 0.3 or 0.1)
        end
    elseif not E.Visible then
        SetOpacity(W, k, 0.0)
    elseif E.Opaque then
        W:SetRenderOpacity(1.0)   -- the dial looked faded; keep it fully solid
    elseif RestoreAllRequested or next(Touched) ~= nil then
        RestoreOpacity(W, k, RestoreAllRequested)   -- leave the game's own fading alone when the element is shown
    end
end

local function ApplyAll()
    for i, E in ipairs(Elements) do
        local sel = EditMode and i == Selected
        local lx, ly, ls = LocalTransform(E)
        for n, W in ipairs(E.Instances) do ApplyOne(W, E.Keys[n], lx, ly, ls, E, sel) end
    end
    RestoreAllRequested = false
end

---------------------------------------------------------------- command panel, built from the game's own UI pieces

-- A dark panel with a thin gold frame, like the game's own panels. Built on the first F9, so a world exists.
local Overlay = { W = nil, Texts = {}, LastState = "", Open = false }
local LIST_ROWS = 9

local C_GOLD  = { R = 0.89, G = 0.72, B = 0.38, A = 1.0 }
local C_CREAM = { R = 0.96, G = 0.92, B = 0.82, A = 1.0 }
local C_GREY  = { R = 0.66, G = 0.62, B = 0.55, A = 1.0 }
local C_DIM   = { R = 0.45, G = 0.42, B = 0.38, A = 1.0 }

local KEY_ROWS = {
    { "PgUp / PgDn",     "Select element" },
    { "Arrow keys",      "Move" },
    { "Home / End",      "Move step" },
    { "+ / -",           "Size" },
    { "Delete / Insert", "Hide / show" },
    { "Backspace",       "Reset element" },
    { "F9",              "Save and close" },
}

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
-- The background of a game panel (tooltip or lore popup), so the editor looks like the game's own windows.
-- Read from the blueprint templates, which always exist; SetBrush copies it, the game's brush is not touched.
local function FindGameBrush()
    local pick = nil
    pcall(function()
        for _, cls in ipairs({ "Border", "Image" }) do
            for _, B in pairs(FindAllOf(cls) or {}) do
                local n = B:GetFullName()
                if string.find(n, "WBP_Panel_Tooltip") or string.find(n, "WBP_Panel_LorePopup") then
                    local okR, res = pcall(function()
                        return cls == "Border" and B.Background.ResourceObject or B.Brush.ResourceObject
                    end)
                    if okR and res and res:IsValid() and not pick then pick = { Widget = B, Kind = cls } end
                end
            end
        end
    end)
    return pick
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
    local frame = FindTemplate("Image", "WBP_MainMenu_Worlds_C:WidgetTree.ListImage")
    if not frame then return false end
    local art = {}
    pcall(function() art.Frame = BrushInfo(frame.Brush) end)
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
    Log("menu art saved: frame=" .. tostring(art.Frame and art.Frame.Res) .. " trim=" .. tostring(art.Trim and art.Trim.Res)
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
    brush("frame", art.Frame)
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
            if key == "frame" or key == "trim" then
                local p = split(rest)
                local m, s, c = nums(p[3]), nums(p[4]), nums(p[6])
                local b = { Res = p[1], DrawAs = math.floor(num(p[2], 0, 4, 3)), Tiling = math.floor(num(p[5], 0, 3, 0)),
                    Margin = { Left = num(m[1], 0, 1, 0), Top = num(m[2], 0, 1, 0), Right = num(m[3], 0, 1, 0), Bottom = num(m[4], 0, 1, 0) },
                    Size = { X = num(s[1], 1, 2048, 64), Y = num(s[2], 1, 2048, 64) },
                    Tint = { R = num(c[1], 0, 1, 1), G = num(c[2], 0, 1, 1), B = num(c[3], 0, 1, 1), A = num(c[4], 0, 1, 1) } }
                if key == "frame" then art.Frame = b else art.Trim = b end
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
    if art.Frame then Log("menu art read from " .. ART_FILE) return art end
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
        local frame = StaticConstructObject(Cls("/Script/UMG.Border"), tree, FName("RuneUIFrame"))
        frame:SetBrushColor({ R = 0.72, G = 0.57, B = 0.30, A = 0.95 })
        frame:SetPadding({ Left = 1, Top = 1, Right = 1, Bottom = 1 })
        local panel = StaticConstructObject(Cls("/Script/UMG.Border"), tree, FName("RuneUIPanel"))
        panel:SetBrushColor({ R = 0.055, G = 0.042, B = 0.03, A = 0.93 })
        panel:SetPadding({ Left = 16, Top = 12, Right = 18, Bottom = 14 })
        frame:SetContent(panel)
        step = "menu art"
        local art = FindMenuArt()
        local gb = nil
        if art.Frame then
            local okF, errF = pcall(function()
                local fimg = ImageFromArt(tree, "RU_FrameArt", art.Frame)
                if not fimg then error("frame picture not loaded") end
                panel:SetBrush(fimg.Brush)
                panel:SetBrushColor({ R = 1, G = 1, B = 1, A = 1 })
                panel:SetPadding({ Left = 34, Top = 30, Right = 34, Bottom = 52 })   -- inside the ornate edge; more at the bottom, where the ornament sits
                frame:SetBrushColor({ R = 0, G = 0, B = 0, A = 0 })
            end)
            if not okF then Log("menu frame not used: " .. tostring(errF)) art.Frame = nil end
        end
        if not art.Frame then gb = FindGameBrush() end
        if gb then
            local okB, errB = pcall(function()
                panel:SetBrush(gb.Kind == "Border" and gb.Widget.Background or gb.Widget.Brush)
                panel:SetBrushColor({ R = 1, G = 1, B = 1, A = 1 })
                panel:SetPadding({ Left = 30, Top = 28, Right = 30, Bottom = 26 })   -- the tooltip art has its edge drawn inside the image
                frame:SetBrushColor({ R = 0, G = 0, B = 0, A = 0 })   -- the game's brush brings its own edge
            end)
            if not okB then Log("game background not used: " .. tostring(errB)) end
        end
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

        step = "keys"
        local row = StaticConstructObject(Cls("/Script/UMG.HorizontalBox"), tree, FName("RU_KeyRow"))
        local keys, acts = {}, {}
        for _, k in ipairs(KEY_ROWS) do table.insert(keys, k[1]) table.insert(acts, k[2]) end
        local keyText = MakeText(tree, "RU_Keys", 11, C_GOLD, table.concat(keys, "\n"))
        local actText = MakeText(tree, "RU_Actions", 11, C_CREAM, table.concat(acts, "\n"))
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
        slot:SetPosition({ X = 30, Y = 270 })   -- left side, under the avatar, bars and buffs
        step = "add to screen"
        uw:AddToViewport(1000)
        uw:SetVisibility(1)   -- collapsed until the editor opens
        Overlay.W = uw
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
local function UpdateOverlay()
    if Overlay.W and not Overlay.W:IsValid() then Overlay.W, Overlay.LastState, Overlay.Open = nil, "", false end
    -- like every other build: never into a world that is loading or not settled yet
    if EditMode and not Overlay.W and MayTry(Overlay) and os.clock() > SettleUntil and LastController ~= "" then BuildOverlay() end
    if not Overlay.W then return end
    local ok, err = pcall(function()
        if not EditMode then
            if Overlay.Open then Overlay.W:SetVisibility(1) Overlay.Open = false end   -- collapsed
            return
        end
        local E = Elements[Selected]
        local state = table.concat({ Selected, E.X, E.Y, E.Scale, Step, tostring(E.Visible) }, "|")
        for i, El in ipairs(Elements) do state = state .. (El.Visible and "1" or "0") .. (#El.Instances > 0 and "f" or "n") end
        if state ~= Overlay.LastState then
            Overlay.LastState = state
            Overlay.Texts.Selected:SetText(FText("Selected:  " .. E.Name))
            Overlay.Texts.ListTitle:SetText(FText(string.format("ELEMENTS   %d / %d", Selected, #Elements)))
            if Overlay.PhSlot and E.Center then
                local sz = E.Scale
                local w, h = E.Size.X * sz, E.Size.Y * sz
                local cx, cy = FinalCenter(E)
                Overlay.PhSlot:SetPosition({ X = cx - w / 2, Y = cy - h / 2 })
                Overlay.PhSlot:SetSize({ X = w, Y = h })
                Overlay.PhText:SetText(FText(E.Name))
            end
            Overlay.Texts.Info:SetText(FText(string.format("Size %d%%     Move step %d%s",
                math.floor(E.Scale * 100 + 0.5), Step, E.Visible and "" or "     HIDDEN")))
            -- 9 rows with the selected element in the middle; the list wraps around at both ends
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
        if not Overlay.Open then Overlay.W:SetVisibility(3) Overlay.Open = true end   -- shown, but clicks go through it
    end)
    if not ok and not PanelErrorLogged then PanelErrorLogged = true Log("panel update failed: " .. tostring(err)) end
end
---------------------------------------------------------------- buffs in a row

-- The buff list is a ListView. Its direction is fixed when the list is built, so the mod sets it to
-- horizontal and puts the list back into its box, which makes the game build it again sideways.
local BuffRowDone = {}
local function EnsureBuffRow()
    for _, W in ipairs(ById("buffs").Instances) do
        local k = W:GetFullName()
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
-- and the title, makes the entry square, and draws a gold ring around the icon. The bar's material holds the
-- time left; the ring shows that share. A buff without a timer (its bar is hidden by the game) gets a full ring.
-- The game's XP ring was tried first (27-09-2026): the row squashed it into an oval and the game drew it white.
local RING_SEGS = 20   -- dashes on the ring
local RING_BOX = 50    -- icon 32 + room for the ring
local RING_INSET = 6   -- the dashes' centres sit 6 units inside the edge
local BuffDeco = {}          -- entry full name -> { W, Ring = {dash images}, Bar, Lit }
-- one dash, drawn smooth by tools/make-runemap-art.js; 8 x 8 units with the 2 x 5 dash in the middle. The
-- dashes hold the texture; this handle is only reused while it is valid, and dropped with the world.
local DASH_FILE = "ue4ss/Mods/RuneUI/Art/buff_dash.png"
local DashTex = nil
local BuffParamLogged = false
-- Unreal takes these colours as linear light: the sketch's #ffd173 and #e3b861 converted, so they match it
local C_RING_GOLD = { R = 1.0, G = 0.638, B = 0.168, A = 1.0 }   -- time left; no timer = all lit
local C_RING_OFF  = { R = 0.768, G = 0.479, B = 0.120, A = 0.2 }   -- spent time: the same gold, faint

local function DecorateBuff(E)
    local k = E:GetFullName()
    if BuffDeco[k] then return end
    BuffDeco[k] = { W = E }
    local ok, err = pcall(function()
        local tree = E.WidgetTree
        local box = tree.RootWidget
        local ov = box:GetContent()
        local icon = ov:GetChildAt(0)
        local barBox = ov:GetChildAt(1)
        local bar = barBox:GetChildAt(0)
        box:SetWidthOverride(RING_BOX)
        box:SetHeightOverride(RING_BOX)
        barBox:SetRenderOpacity(0.0)   -- the straight bar and the title stay alive for the game, just unseen
        pcall(function() E:SetClipping(0) box:SetClipping(0) ov:SetClipping(0) end)   -- the list must not cut the ring
        -- icon and ring both sit on the entry's centre: top-left with padding put the icon ~4 units high
        -- (test of 27-09-2026), since its own height is not 32
        pcall(function()
            local s = icon.Slot
            s:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 0 })
            s:SetHorizontalAlignment(2) s:SetVerticalAlignment(2)
        end)
        pcall(function() icon:SetDesiredSizeOverride({ X = 32, Y = 32 }) end)
        -- centred by the numbers, the game's pictures still look 3.5 high: the art sits high in its square
        -- (in-game test, 27-09-2026). Optical, like the level number.
        pcall(function() icon:SetRenderTranslation({ X = 0, Y = 3.5 }) end)
        local canvas = StaticConstructObject(StaticFindObject("/Script/UMG.CanvasPanel"), tree, G("RU_Ring"))
        local ringBox = StaticConstructObject(StaticFindObject("/Script/UMG.SizeBox"), tree, G("RU_RingBox"))
        ringBox:SetWidthOverride(RING_BOX)
        ringBox:SetHeightOverride(RING_BOX)
        ringBox:SetContent(canvas)
        ClearOurs(ov, "RU_RingBox")
        local cs = ov:AddChildToOverlay(ringBox)
        cs:SetHorizontalAlignment(2) cs:SetVerticalAlignment(2)
        -- a ring of short dashes, clockwise from the top: the first version, kept after the
        -- square, the continuous line and the game's XP ring were tried (27-09-2026)
        local dashes = {}
        local r, c = RING_BOX / 2 - RING_INSET, RING_BOX / 2
        if not (DashTex and DashTex:IsValid()) then
            DashTex = nil
            pcall(function() DashTex = StaticFindObject("/Script/Engine.Default__KismetRenderingLibrary"):ImportFileAsTexture2D(E, DASH_FILE) end)
            if not (DashTex and DashTex:IsValid()) then DashTex = nil end
        end
        for i = 0, RING_SEGS - 1 do
            local img = StaticConstructObject(StaticFindObject("/Script/UMG.Image"), tree, G("RU_Dash" .. i))
            local a = (i + 0.5) / RING_SEGS * 2 * math.pi
            local s = canvas:AddChildToCanvas(img)
            s:SetAutoSize(false)
            if DashTex then
                img:SetBrushFromTexture(DashTex, false)
                s:SetSize({ X = 8, Y = 8 })
                s:SetPosition({ X = c + r * math.sin(a) - 4, Y = c - r * math.cos(a) - 4 })
            else   -- no picture: a plain box, jagged when turned
                s:SetSize({ X = 2, Y = 5 })
                s:SetPosition({ X = c + r * math.sin(a) - 1, Y = c - r * math.cos(a) - 2.5 })
            end
            img:SetRenderTransformAngle(math.deg(a))
            img:SetColorAndOpacity(C_RING_OFF)
            dashes[i + 1] = img
        end
        BuffDeco[k].Ring, BuffDeco[k].Bar, BuffDeco[k].Lit = dashes, bar, -1
    end)
    if not ok then Log("round buff failed: " .. tostring(err)) end
end

-- Share of time left, 0..1, from the straight bar's material; nil when the buff has no timer
local BuffParam = nil
local function BuffShare(bar)
    if bar:GetVisibility() == 1 or bar:GetVisibility() == 2 then return nil end
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

local function FindBuffEntries()
    for _, E in ipairs(FindClass("WBP_HUD_StatusEffectListEntry_C")) do DecorateBuff(E) end
end

local function UpdateBuffRings()
    for k, d in pairs(BuffDeco) do
        if not (d.W and d.W:IsValid()) then
            BuffDeco[k] = nil
        elseif d.Ring and not (d.Bar and d.Bar:IsValid() and d.Ring[1] and d.Ring[1]:IsValid()) then
            BuffDeco[k] = nil   -- the game rebuilt this entry; it is decorated again on the next scan
        elseif d.Ring then
            local okS, share = pcall(BuffShare, d.Bar)
            if not okS then share = nil end
            local lit = share and math.floor(share * RING_SEGS + 0.5) or RING_SEGS + 1   -- RING_SEGS + 1: no timer, all lit
            -- the buff's own colour from its bar ("Bar Color 1": poison green, slow yellow, 27-09-2026); a list
            -- entry is reused for another buff, so it is read every time. Gold when there is none.
            local on, off = C_RING_GOLD, C_RING_OFF
            pcall(function()
                d.Bar.Brush.ResourceObject.VectorParameterValues:ForEach(function(_, e)
                    local p = e:get()
                    if p.ParameterInfo.Name:ToString() == "Bar Color 1" then
                        local c = p.ParameterValue
                        on = { R = c.R, G = c.G, B = c.B, A = 1.0 }
                        off = { R = c.R, G = c.G, B = c.B, A = 0.2 }
                    end
                end)
            end)
            local key = string.format("%d %.2f %.2f %.2f", lit, on.R, on.G, on.B)
            if key ~= d.Lit then
                d.Lit = key
                for i, img in ipairs(d.Ring) do
                    img:SetColorAndOpacity(i <= lit and on or off)
                end
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
    local V = ById("vitals").Instances[1]
    if not (V and V:IsValid()) then return end
    local hostName = V:GetFullName()
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
        -- The bars widget's root is a full-screen Overlay: a size box pinned to the top left, pushed by padding
        -- to its spot in the default layout, next to the bars' left end.
        local box = StaticConstructObject(StaticFindObject("/Script/UMG.SizeBox"), V.WidgetTree, G("RU_AvatarBox"))
        box:SetWidthOverride(69)
        box:SetHeightOverride(69)
        box:SetContent(img)
        ClearOurs(root, "RU_AvatarBox")
        local slot = root:AddChildToOverlay(box)
        slot:SetHorizontalAlignment(1)   -- left
        slot:SetVerticalAlignment(1)     -- top
        slot:SetPadding({ Left = 710, Top = 932, Right = 0, Bottom = 0 })
        Avatar.W, Avatar.HostName = box, hostName
    end)
    if ok then Log("avatar ready") Avatar.Fails = 0 else Failed(Avatar) Log("avatar failed at step '" .. step .. "': " .. tostring(err)) end
end

-- The trim line with the diamond from under the main menu's PLAY list, under the bars (design sketch,
-- 27-09-2026). It lives in the bars widget like the badge, so it moves and sizes with the bars.
local BarTrim = { HostName = nil }
local function EnsureBarTrim()
    if not MayTry(BarTrim) then return end
    local V = ById("vitals").Instances[1]
    if not (V and V:IsValid()) or BarTrim.HostName == V:GetFullName() then return end
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
        slot:SetHorizontalAlignment(1)
        slot:SetVerticalAlignment(1)
        -- just under the bars' bottom edge. The bars' root is only 779x1001, so the negative right and bottom
        -- padding give the line room past that edge; without it the line gets no size at all.
        slot:SetPadding({ Left = 787, Top = 1006, Right = -400, Bottom = -40 })
        BarTrim.HostName = V:GetFullName()
    end)
    if ok then Log("bar trim ready") BarTrim.Fails = 0 else Failed(BarTrim) Log("bar trim failed: " .. tostring(err)) end
end

-- The bars (design sketch without its diamonds, in-game review 27-09-2026): plain boxes: a dark track
-- behind each bar's fill and nothing else, stamina in green, health on top, and the icons beside
-- the bars hidden unless the editor shows them. The fill stays the game's.
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

local function BarTex(outer, file)
    local tex = Blades.Tex[file]
    if tex and tex:IsValid() then return tex end
    tex = StaticFindObject("/Script/Engine.Default__KismetRenderingLibrary"):ImportFileAsTexture2D(outer, file)
    if not (tex and tex:IsValid()) then error("picture not loaded: " .. file) end
    Blades.Tex[file] = tex
    return tex
end

local function DressBar(B, W)
    local frame = W.ProgressBarImage:GetParent():GetParent()
    if ClassName(frame) ~= "Border" then error(B.Class .. ": the fill's frame is a " .. ClassName(frame)) end
    -- read before anything changes: the picture is chosen by the padding under the fill
    local p = frame.Padding
    Log(string.format("bar %s: frame padding %.1f %.1f %.1f %.1f", B.Class, p.Left, p.Top, p.Right, p.Bottom))
    local pad = math.floor(p.Bottom + 0.5)
    if pad < 8 or pad > 12 then error(B.Class .. ": no picture for a padding of " .. pad) end
    local h = pad * 2 + BLADE_CORE
    frame:SetBrushFromTexture(BarTex(W, string.format(BLADE_FILE, pad)))
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

local function EnsureBlades()
    if not MayTry(Blades) then return end
    local V = ById("vitals").Instances[1]
    if not (V and V:IsValid()) then return end
    local host = V:GetFullName()
    if Blades.HostName ~= host then
        Blades.HostName, Blades.Bars, Blades.Missed, Blades.Count, Blades.Swapped = host, {}, {}, 0, nil
    end
    local ok, err = pcall(function()
        -- a bar the game made again: forget the dead handle, find the new widget and swap the rows again
        for i = 1, #BARS do
            if Blades.Bars[i] and not Blades.Bars[i]:IsValid() then
                Blades.Bars[i], Blades.Count, Blades.Swapped = nil, Blades.Count - 1, nil
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
        if Blades.Bars[1] then
            -- stamina green, set again whenever the game resets it (taking a tool did, 27-09-2026)
            local fill = Blades.Bars[1].ProgressBarImage
            local c = fill.ColorAndOpacity
            if math.abs(c.R - STAMINA_GREEN.R) > 0.01 or math.abs(c.B - STAMINA_GREEN.B) > 0.01 then fill:SetColorAndOpacity(STAMINA_GREEN) end
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
end
do
    local ok, err = pcall(WriteArt)
    if not ok then Log("pictures not written: " .. tostring(err)) end
end
RuneMap = LoadPart("runemap")
local Survival = LoadPart("survival")
local MapCtx = { Log = Log, ById = ById, Asset = Asset }
local SurvivalCtx = { Log = Log, ById = ById }
local MapErrorLogged, SurvivalErrorLogged = false, false

-- A new world (quit to the main menu, entering a game): drop every handle the mod holds into the old one
-- before anything reads it. The engine frees the old world's objects while it loads the new one, and a
-- crash on quitting to the menu (27-09-2026) came from an old handle. The world is told apart by its player
-- controller; UE4SS's load-map hook crashed on its second call (27-09-2026), so it is not used.
-- sameWorld: a player restart inside a world that still stands, so our own map may be taken off the screen
local function ForgetWorld(sameWorld)
    for _, E in ipairs(Elements) do E.Instances, E.Keys = {}, {} end
    BuffDeco, DashTex = {}, nil
    Avatar.W, Avatar.HostName, Avatar.Tex, Avatar.LevelText, Avatar.LevelIcon = nil, nil, nil, nil, nil
    Avatar.LastLevel, Avatar.LastIcon = nil, nil
    BarTrim.HostName = nil
    Blades.HostName, Blades.Tex, Blades.Bars = nil, {}, {}
    for _, P in ipairs({ Avatar, BarTrim, Blades, Overlay }) do P.Fails, P.RetryAt = 0, 0 end   -- new tries (see MayTry)
    if not sameWorld then
        -- the editor panel of the old world is off the screen: build a new one on the next F9
        Overlay.W, Overlay.LastState, Overlay.Open = nil, "", false
        -- these remember widgets by full name; the old world's widgets are gone
        OrigOpacity, Touched, Unclipped, BuffRowDone = {}, {}, {}, {}
    end
    if RuneMap then pcall(RuneMap.Forget, sameWorld) end
    if Survival then pcall(Survival.Forget) end
    Gen = Gen + 1
    SettleUntil = os.clock() + 3
    Log(sameWorld and "player restart: old handles dropped" or "new world: old handles dropped")
end
local function ControllerName()
    -- the local player's controller only: in co-op a friend's controller joining or leaving must not look
    -- like a new world; one unreadable controller is skipped, not taken as a change
    local name = ""
    for _, P in pairs(FindAllOf("PlayerController") or {}) do
        local ok, n = pcall(function()
            local full = P:GetFullName()
            if not string.find(full, "Default__", 1, true) and P:IsLocalController() then return full end
        end)
        if ok and n then name = n break end
    end
    return name
end
-- The local controller is searched on every tick. It goes away the moment a travel starts, before the old
-- world is torn down. Reading the viewport's world instead was lighter, but it changes only once the new world
-- stands, and the game crashed on entering a world in between (27-09-2026, 0.49). Keep this search.
local function WatchWorld()
    local name = ControllerName()
    if name ~= LastController then LastController = name ForgetWorld(false) end
end

local function TickBody()
    local now = os.clock()
    if not TickAlive then TickAlive = true Log("timer running") end
    WatchWorld()   -- first: nothing below may read a handle into a world that is gone

    -- each scan searches all objects once per element class; every 2 s is enough outside the editor (lag, 27-09-2026)
    if now - LastScan > (EditMode and 0.5 or 2.0) then
        LastScan = now
        local okFind, errFind = pcall(FindAll)
        if not okFind and not ApplyErrorLogged then ApplyErrorLogged = true Log("finding widgets failed: " .. tostring(errFind)) end
        if now > SettleUntil then
            pcall(EnsureAvatar)
            pcall(EnsureBarTrim)
            pcall(EnsureBlades)
            pcall(EnsureBuffRow)
            pcall(FindBuffEntries)
        end
    end
    -- try every 3 s for the first 3 minutes (the main menu); a full scan of images is too heavy to repeat forever
    if not MenuArt and now < 180 and now > (NextArtTry or 0) then NextArtTry = now + 3 pcall(CaptureMenuArt) end

    if now > NextRings then NextRings = now + 0.5 pcall(UpdateBuffRings) end
    if RuneMap and now > 20 and now > SettleUntil then
        local okM, errM = pcall(RuneMap.Tick, MapCtx)
        if not okM and not MapErrorLogged then MapErrorLogged = true Log("runemap step failed: " .. tostring(errM)) end
    end
    if Survival and now > 20 and now > SettleUntil then
        local okS, errS = pcall(Survival.Tick, SurvivalCtx)
        if not okS and not SurvivalErrorLogged then SurvivalErrorLogged = true Log("survival step failed: " .. tostring(errS)) end
    end
    Flash = (math.floor(now * 2.5) % 2 == 0)
    local okApply, errApply = pcall(ApplyAll)
    if not okApply and not ApplyErrorLogged then ApplyErrorLogged = true Log("apply failed: " .. tostring(errApply)) end

    if SaveRequested then SaveRequested = false SaveLayout() end

    UpdateOverlay()
end

local TickErrorLogged = false
-- While the game thread is busy (a world loading), the timer keeps firing. Only one step waits in the queue at a
-- time, so hundreds of them do not run at once when the world is up. A step that waited 5 s is taken as lost.
local QueuedAt = nil
local function Tick()
    local run = function()
        QueuedAt = nil
        local ok, err = pcall(TickBody)
        if not ok and not TickErrorLogged then TickErrorLogged = true Log("timer step failed: " .. tostring(err)) end
    end
    ExecuteWithDelay(50, Tick)   -- first: an error below must not stop the timer
    if not ExecuteInGameThread then
        run()
    elseif not QueuedAt or os.clock() - QueuedAt > 5 then
        QueuedAt = os.clock()
        ExecuteInGameThread(run)
    end
end
ExecuteWithDelay(2000, Tick)

-- A player restart (entering a world, respawning) can rebuild the game's HUD: drop every handle into it
-- first. Widgets added before the restart and read after it crashed the game on entering (27-09-2026).
RegisterHook("/Script/Engine.PlayerController:ClientRestart", function()
    local name = ControllerName()
    ForgetWorld(name == LastController)   -- the same controller: the same world, still standing
    LastController = name
    if not EditMode then LoadLayout() end   -- dying with the editor open keeps the unsaved changes
end)
---------------------------------------------------------------- keys (Windows key codes; they only change state, the loop above does the work)

RegisterKeyBind(120, function()
    EditMode = not EditMode
    if EditMode then
        Log("edit mode on")
    else
        SaveRequested = true
        RestoreAllRequested = true
        Log("edit mode off")
    end
end)

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
end
RegisterKeyBind(38, function() Move(0, -1) end)
RegisterKeyBind(40, function() Move(0, 1) end)
RegisterKeyBind(37, function() Move(-1, 0) end)
RegisterKeyBind(39, function() Move(1, 0) end)

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
    if not EditMode or IsSwitch(E) then return end
    E.Scale = math.max(0.3, math.min(4.0, math.floor((E.Scale + d) * 100 + 0.5) / 100))   -- up to 400%
end
RegisterKeyBind(107, function() Resize(0.05) end)
RegisterKeyBind(109, function() Resize(-0.05) end)
RegisterKeyBind(187, function() Resize(0.05) end)
RegisterKeyBind(189, function() Resize(-0.05) end)

RegisterKeyBind(46, function() if EditMode then Elements[Selected].Visible = false end end)
RegisterKeyBind(45, function() if EditMode then Elements[Selected].Visible = true end end)
RegisterKeyBind(8, function()
    if not EditMode then return end
    local E = Elements[Selected]
    local d = Defaults[E.Id] or {}
    E.X, E.Y, E.Scale, E.Visible = d.X or 0, d.Y or 0, d.Scale or 1.0, (d.Visible ~= false)
end)

Log("loaded, press F9 in game")
