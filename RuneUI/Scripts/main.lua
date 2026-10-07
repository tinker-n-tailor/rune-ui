-- Rune UI: move, resize and hide parts of the Dragonwilds HUD, with a new minimap, survival rings and bars.
-- F9 opens the editor, F8 the map settings, F6 the camera settings. A timer applies the layout; gold corners mark the selected element.

local VERSION = "1.9.2"

local function Log(msg) print("[RuneUI] " .. msg .. "\n") end
Log("starting " .. VERSION)

-- The mod's own folder, for its pictures and files. It comes from the full path UE4SS loaded this file from, when a file
-- opens through it. The short path counts from the folder the game was started in, and the pictures did not load
-- through it on a player's machine (03-10-2026). It stays as the fallback.
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

-- A part that fails to build is tried again 10 s later, 3 times at most in one round. A new round (a new world
-- or a respawn) gives it new tries. A part gets the rule in its ctx (MayTry, Failed) and resets Fails and RetryAt
-- in its Forget.
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

-- One entry per movable thing, and the starting layout: the list and what each field means are in elements.lua.
local Elements, Defaults
do
    local Data = LoadPart("elements")
    if not Data then error("elements.lua is missing or broken, see the log") end
    Elements, Defaults = Data.List, Data.Defaults
end

-- The position math lives in layout.lua (tested without the game); these are its names, used all over this file.
local Layout = LoadPart("layout")
if not Layout then error("layout.lua is missing or broken, see the log") end
Layout.Init(Elements)
local Hud, ById, Third, IsSwitch = Layout.Hud, Layout.ById, Layout.Third, Layout.IsSwitch
local FinalCenter = Layout.FinalCenter
local Retarget, TargetFromSpot, ScreenBox, Spot, Area = Layout.Retarget, Layout.TargetFromSpot, Layout.ScreenBox, Layout.Spot, Layout.Area
local AREAS = Layout.AREAS

for _, E in ipairs(Elements) do
    local d = Defaults[E.Id] or {}
    E.X, E.Y, E.Scale = d.X or 0, d.Y or 0, d.Scale or 1.0
    E.Visible = (d.Visible ~= false)
    E.Opacity = 1.0   -- every default is fully solid; F9 comma and period change it
    E.Wait = d.Wait   -- the immersive line only: seconds a part stays before it fades (+ / - there)
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
-- when this file loads: on a player restart it pulled widgets out of a world that was being unloaded (the crash
-- on quitting to the menu, 27-09-2026).
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

-- One file, runeui.txt, next to the game: the three layout profiles, the profile in use, the map settings and
-- the zoom, the camera settings, and the keys. Named values, so a player can read and edit it, and a new
-- version never breaks an old file. The files of older versions are read once, when runeui.txt is missing, and are
-- left in place. settings.lua reads and writes the file.
local Settings = LoadPart("settings")
if not Settings then error("settings.lua is missing or broken, see the log") end
local ReadText = Settings.ReadFile
local Cfg = Settings.Load()
if not Cfg then
    Cfg = Settings.Legacy(ReadText)
    if Cfg then Log("settings: read from the files of an older version") else Cfg = {} Log("no settings file yet, using defaults") end
end
Cfg.menuart = nil   -- the main menu's line under the bars, no longer used: dropped from old files
local ElementIds = {}   -- the order of the rows in the file: the element list
for _, E in ipairs(Elements) do ElementIds[#ElementIds + 1] = E.Id end
local function SaveCfg()
    Settings.Section(Cfg, "general").version = VERSION
    if not Settings.Save(Cfg, nil, ElementIds) then Log("could not write " .. Settings.FILE) end
end

-- The profiles: three layouts, F7 goes to the next while the editor is open. Profile 1 is the layout every
-- older version wrote, so no player loses a layout. N: the profile in use. Wanted: F7 sets it on UE4SS's thread,
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
            -- the edge it follows; a row without it (an old file): from where it sits
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
local Bars = nil      -- the bars' look and the line under them, from bars.lua
local Buffs = nil     -- the buffs under the bars, the buff row and the drink ring, from buffs.lua
local RuneMap = nil   -- the minimap, from runemap.lua; loaded near the main loop
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
-- crosshair.lua use it. Its Open is the F6 panel, as MapMode is F8.
local Camera = nil

-- The widget search lives in finder.lua (tested without the game), with its state: what its Forget drops and what the
-- perf line reads. These are its names, used all over this file.
local Finder = LoadPart("finder")
if not Finder then error("finder.lua is missing or broken, see the log") end
Finder.Init({ Elements = Elements, ById = ById, Hud = Hud, Log = Log, SettleUntil = function() return SettleUntil end })
local ClassName, FindClass, FindQuiet, Reports = Finder.ClassName, Finder.FindClass, Finder.FindQuiet, Finder.Reports

---------------------------------------------------------------- applying the layout

local EditMode = false
local MapMode = false    -- F8: RuneMap's own settings, in the same panel as the editor
local MapSel = 1         -- the selected line of the map settings
local Selected = 1
local Step = 10
-- The layout is written into the widgets in apply.lua. The editor's state above stays here: the keys write it on
-- UE4SS's thread, and the step gives it to Apply.All as plain values.
local Apply = LoadPart("apply")
if not Apply then error("apply.lua is missing or broken, see the log") end
Apply.Init({ Elements = Elements, Layout = Layout, Log = Log })

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
-- read when the tracker is scaled down. Found once; without it, the font above.
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

-- The F9 list by screen area: the ninth of the screen an element sits in (Layout.Area). Read when
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

-- The keys each panel lists. KEY: the names of the six keys a player can change, as bound
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
-- than what is shown
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
    if row == "Drawing" then return S.Smooth and "Smooth" or (S.Fastest and "Fastest" or "Faster") end
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
        Faster = "The map draws every second frame. A bit choppy when you turn.", Fastest = "The map draws every fourth frame. The lightest, and the choppiest." },
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
    -- a group title on the last line has its rows cut off below: "CENTER" with nothing under it
    if v.Rows[#v.Rows].Head then v.Rows[#v.Rows] = nil end
    return CameraLink(v)
end

local function MapView()
    local vals = {}
    for i = 1, #MAP_ROWS do vals[i] = MapValue(i) end
    local v = { Mode = "map", Title = "RUNE MAP", SubA = "Layout on", SubB = KEY.editor, Keys = MapKeys(), Warn = Problems(),
        Name = MAP_ROWS[MapSel] .. ":  " .. vals[MapSel], Hint = MapHint(MapSel, vals[MapSel]), Rows = {} }
    -- the panel has Editor.ROWS lines: a longer list moves with the selected row, as the F9 list does
    local first = math.max(1, math.min(MapSel - math.floor(Editor.ROWS / 2), #MAP_ROWS - Editor.ROWS + 1))
    for r = first, math.min(#MAP_ROWS, first + Editor.ROWS - 1) do
        v.Rows[#v.Rows + 1] = { Text = MAP_ROWS[r], Note = MAP_CHOICE[MAP_ROWS[r]] and ("< " .. vals[r] .. " >") or vals[r], Sel = r == MapSel }
    end
    return CameraLink(v)
end

-- F9: the panel stays on its side of the screen and moves to the other only when it would cover the selected
-- element. Going away from every selected element made it jump from side to side while going down the list.
-- Its side is kept in Editor.Left.
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
-- tried again on the next step (State set first left the panel empty).
-- Logged: the error texts of a step that are in the log, Lines: how many. A step that failed can fail again every
-- 50 ms: each text is logged once, and 10 texts at most in a world, as a text may change from step to step.
local Panel = { State = "", View = nil, Logged = {}, Lines = 0 }
local function UpdateOverlay(now)
    local cam = Camera ~= nil and Camera.Open   -- F6: the camera settings, in the same panel
    local open = EditMode or MapMode or cam
    if not Editor then return end
    if not open and not Editor.Shown then return end   -- closed, and nothing of the panel on screen to take away
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

-- The pictures: each one that is missing or different is written into Art from Scripts/art.lua (pictures.lua).
do
    local Pictures = LoadPart("pictures")   -- not loaded: the log says so, and the pictures in Art are used as they are
    if Pictures then Pictures.Write(LoadPart, Log, RUNEUI_DIR) end
end
Survival = LoadPart("survival")
-- The parts that build on the game's widgets: the avatar, the bars and the buffs. They share main.lua's
-- helpers through one table, and survival.lua's ring and Find. Listed first: their Scan runs in this order, and
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
if Camera then Camera.Attach(Settings.Section(Cfg, "camera"), SaveCfg) end
-- Editing: the map shows while F9 or F8 is open, even when it is hidden
local MapCtx = { Log = Log, ById = ById, Asset = Asset, Editing = function() return EditMode or MapMode end, Scan = function() LastScan = 0 end,
    -- the immersive mode's share: the map fades itself, its gold rings too (runemap.lua ApplyOpacity)
    -- with the map setting "In immersive mode" at Map, the map stays
    Fade = function()
        if RuneMap and RuneMap.Set.Immersive == "Map" then return 1 end
        return Immersive and Immersive.Factor(ById("runemap")) or 1
    end }
AddPart("runemap", RuneMap, MapCtx)
AddPart("survival", Survival, { Log = Log, ById = ById, ClearOurs = ClearOurs })
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
if Cooldowns and Survival then   -- without survival.lua it has no Find
    -- the spell wheel's slices only: the spell book has a second wheel of the same slices (probe, 29-09-2026).
    -- With their names, as FindClass gives them.
    local SlicePath = { "WBP_Spellcasting_MainPanel_C_%d+%.WidgetTree_%d+%.SpellRadialWidget%.WidgetTree_%d+%.RadialSlice_%d+$" }
    AddPart("cooldowns", Cooldowns, { Log = Log, ById = ById, Find = Survival.Find, Survival = Survival, MayTry = MayTry, Failed = Failed,
        -- Editing: F9 only: with the map settings (F8) open the sample tiles would show too.
        On = function() return ById("cooldowns").Visible end, Editing = function() return EditMode end,
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
        AddPart("quest tracker", QuestTracker, { Log = Log, ById = ById, Asset = Asset, GoldLine = Util.GoldLine, MayTry = MayTry, Failed = Failed,
            Text = function(tree, name, size, color, s)
                return MakeText(tree, name, size, color, s, FindPoppinsMedium())
            end,
            -- F9 only, as the cooldowns: with the map settings (F8) open the made-up sample would show too
            Editing = function() return EditMode end,
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
            Soon = ExecuteInGameThreadWithDelay,   -- one call on the game thread, a few ms from now; nil in an old UE4SS
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
    if P then
        AddPart("bed names", P, { Log = Log, Hook = RegisterHook, Text = FText,
            Find = function(path) local o = Cls(path) if o ~= nil and o:IsValid() then return o:GetAddress() end end })
    end
    -- the immersive camera and the crosshair setting: "immersive mode on" is its line in F9, the switch
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
-- the parts that the widget search and the layout's writing read: all loaded by now, and the first step comes with the timer
Finder.Attach({ Buffs = Buffs, Survival = Survival, Avatar = Avatar, RuneMap = RuneMap, Cooldowns = Cooldowns,
    QuestTracker = QuestTracker, Party = Party })
Apply.Attach({ Immersive = Immersive, Survival = Survival })

-- A new world (quit to the main menu, entering a game): drop every handle the mod holds into the old one
-- before anything reads it. The engine frees the old world's objects while it loads the new one, and a
-- crash on quitting to the menu (27-09-2026) came from an old handle. The world is told apart by its player
-- controller; UE4SS's load-map hook crashed on its second call (27-09-2026), so it is not used.
-- sameWorld: a player restart inside a world that still stands, so our own map may be taken off the screen
local function ForgetWorld(sameWorld)
    for _, E in ipairs(Elements) do E.Instances, E.Keys, E.PartsOp, E.PartsW, E.Last = {}, {}, {}, {}, {} end
    Finder.Forget(sameWorld)   -- the last widget search's handles, and the widgets reported since
    if Editor then Editor.Fails, Editor.RetryAt = 0, 0 end   -- new tries (see MayTry); the parts reset their own in Forget
    Apply.Forget(sameWorld)   -- the bag's widgets, and what it remembers of each widget's opacity and clipping
    if not sameWorld then
        -- the editor panel of the old world is off the screen: build a new one on the next F9, and say its
        -- errors again if it fails again
        if Editor then Editor.Forget() Editor.Shown, Panel.State, Panel.Logged, Panel.Lines = false, "", {}, 0 end
    end
    for _, P in ipairs(Parts) do
        pcall(P.M.Forget, sameWorld)
        if not sameWorld then P.Error, P.M.ErrorLogged = nil, false end   -- a new world: say it again if it fails again
    end
    Gen = Gen + 1
    SettleUntil = os.clock() + 3
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
-- once the new world stood, and the game crashed on entering a world in between (27-09-2026).
-- A search of all controllers on every tick cost 36 ms a tick on UE4SS builds without hash tables (28-09-2026). So once the
-- local player is known, its link to the controller is read instead (it changed on the same tick as the search in every travel).
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

-- The perf lines in UE4SS.log, every 60 s, are made in perf.lua. Perf is its counter: the step adds its times to it.
local Perf = LoadPart("perf")
if not Perf then error("perf.lua is missing or broken, see the log") end
Perf.Init({ Log = Log, ById = ById, Elements = Elements, RuneMap = RuneMap, Finder = Finder })

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
    Perf.CountFrames(now)

    -- the widgets every 2 s, in the editor too: faster scans stuttered when each held a full search (27-09 and
    -- 28-09-2026). The full search inside runs less often (FindAll); sooner scans come from the two cases below.
    -- Sooner when the buff count changes: a new drink took up to 2 s to become its ring. The
    -- count is a few plain numbers; the search it brings runs once per new buff.
    local buffsNew = false
    if now > NextBuffCount then   -- 4 times a second; its own clock, so not every step between scans
        NextBuffCount = now + 0.25
        local okB, b = Buffs and pcall(Buffs.Changed)
        buffsNew = okB and b or false
    end
    -- Sooner too when the game reported a widget that a part uses: the drink's entry can come after its count
    -- changed, and the ring then waited for the 2 s scan. 4 scans a second at most, as a
    -- new HUD comes as some hundred widgets over a few seconds.
    local quick = Reports.Fresh and now - LastScan > 0.25
    local scanned = now - LastScan > 2.0 or buffsNew or quick
    if scanned then
        if quick then Reports.Quick = Reports.Quick + 1 end   -- for the perf line: a class the game makes all the time would show here
        LastScan, Reports.Fresh = now, false
        local scanFrom = os.clock()
        local okFind, errFind = pcall(Finder.FindAll, EditMode or MapMode, buffsNew)
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
    local okApply, errApply = pcall(Apply.All, scanned, EditMode, MapMode, Selected)   -- a scan step writes every move and size again (ApplyOne)
    if not okApply and not ApplyErrorLogged then ApplyErrorLogged = true Log("apply failed: " .. tostring(errApply)) end

    if SaveRequested then SaveRequested = false SaveLayout() end
    if Camera then pcall(Camera.Commit) end   -- the camera settings are saved here, whatever camera.lua's step does
    if Prof.Wanted then Prof.Wanted = false pcall(Prof.Next) end

    UpdateOverlay(now)

    local took = os.clock() - now
    Perf.Ticks, Perf.Sum, Perf.Max = Perf.Ticks + 1, Perf.Sum + took, math.max(Perf.Max, took)
    if now - Perf.From > 60 then Perf.Write(now) end
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
        Reports.On = NotifyOnNewObject ~= nil and pcall(NotifyOnNewObject, "/Script/UMG.UserWidget", Finder.NewWidget)
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
-- Windows key codes by name. The six keys in KEY_DEFAULT can be changed in the [keys] section of runeui.txt;
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

-- Rune UI's page in the mod "Mod Menu" (modmenu.lua): the rows of RuneUI/modmenu.txt, each with the mod's
-- real value and the way to change it, as F8 and F9 do it. A key works after a restart, as from runeui.txt.
do   -- a block: its names are not top-level locals
    local MM = LoadPart("modmenu")
    if MM then
        local rows = {}
        local function Row(key, get, set) rows[#rows + 1] = { Key = key, Get = get, Set = set } end
        -- first: Mod Menu's "reset" gives every row at once, and the rows below belong to the profile in use
        Row("profile", function() return tostring(Prof.N) end,
            function(v)
                local n = tonumber(v)
                if n ~= 1 and n ~= 2 and n ~= 3 then Log("profile: " .. tostring(v) .. " from Mod Menu is not a profile (1, 2 or 3), the profile stays") return end
                for _ = 1, 2 do if Prof.N ~= n then Prof.Next() end end
            end)
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
        for _, r in ipairs({ { "immersive", "immersive" }, { "rune_xp", "runexp" }, { "slim_level_up", "slimlevel" },
            { "combat_text", "combattext" }, { "quest_next", "questnext" }, { "horizontal_cooldowns", "cdhoriz" },
            { "party_panel", "party" } }) do
            local El = ById(r[2])
            Row(r[1], function() return El.Visible end, function(v) El.Visible = v == true SaveRequested = true end)
        end
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
            Row("map_drawing", function() return S.Smooth and "Smooth" or (S.Fastest and "Fastest" or "Faster") end,
                function(v) S.Smooth, S.Fastest = v == "Smooth", v == "Fastest" RuneMap.Dirty = true end)
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
            -- failed and the panel stayed blank.
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

-- F8: RuneMap's own settings. F8 inside F9 goes from the editor to the map settings. Closing saves the
-- layout, which holds the creatures switch; runemap.lua saves the other settings as they change.
RegisterKeyBind(KeyCode("map"), function()
    if EditMode then EditMode = false end
    if Camera then Camera.Open = false end
    MapMode = not MapMode
    SaveRequested = true
end)
-- F6: the camera settings, in the same panel; from F9 or F8 it goes there. camerarules.lua saves as they change.
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
-- left and right: the zoom row zooms; Creatures, In immersive mode and Drawing step through their values; every other row switches
local function MapChange(d)
    if not RuneMap then return end
    local S = RuneMap.Set
    local row = MAP_ROWS[MapSel]
    if row == "Zoom" then RuneMap.ZoomBy(d > 0 and 1 / 1.25 or 1.25)
    elseif row == "Drawing" then   -- Smooth, Faster, Fastest
        local st = ((S.Smooth and 1 or (S.Fastest and 3 or 2)) - 1 + (d > 0 and 1 or -1)) % 3 + 1 S.Smooth, S.Fastest = st == 1, st == 3
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
    -- on the immersive line + / - set the wait before fading, 3 to 30 s; numbers only here
    if E.Wait then E.Wait = math.max(3, math.min(30, E.Wait + (d > 0 and 1 or -1))) return end
    if IsSwitch(E) or E.OnlyY then return end
    E.Scale = math.max(0.3, math.min(4.0, math.floor((E.Scale + d) * 100 + 0.5) / 100))   -- up to 400%
end
RegisterKeyBind(VK.Plus, function() Resize(0.05) end)     -- the number pad
RegisterKeyBind(VK.Minus, function() Resize(-0.05) end)
RegisterKeyBind(VK.Equals, function() Resize(0.05) end)   -- the main keys: = is + without Shift
RegisterKeyBind(VK.Dash, function() Resize(-0.05) end)

-- comma and period: less or more solid, in steps of 10%, down to 20%; hiding is Delete
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
