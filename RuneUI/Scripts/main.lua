-- Rune UI: move, resize and hide parts of the Dragonwilds HUD, with a new minimap, survival rings and bars.
-- F9 opens the layout editor, F5 Rune Skin, F8 Rune Map, F6 the immersive mode. A timer applies the layout; gold corners mark the selected element.

local VERSION = "1.11"

local function Log(msg) print("[RuneUI] " .. msg .. "\n") end
Log("starting " .. VERSION .. " on " .. tostring(_VERSION))

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
-- A file the mod cannot run without: it stops here when the file does not load.
local function Need(name)
    local m = LoadPart(name)
    if not m then error(name .. ".lua is missing or broken, see the log") end
    return m
end

-- What the parts share to make and find things in the engine (engine.lua).
local Engine = Need("engine")
Engine.Init({ Log = Log })

-- A part that fails to build is tried again 10 s later, 3 times at most in one round. A new round (a new world
-- or a respawn) gives it new tries. A part gets the rule in its ctx (MayTry, Failed) and resets Fails and RetryAt
-- in its Forget.
local function MayTry(P) return (P.Fails or 0) < 3 and os.clock() >= (P.RetryAt or 0) end
local function Failed(P) P.Fails, P.RetryAt = (P.Fails or 0) + 1, os.clock() + 10 end

-- One entry per movable thing, and the starting layout: the list and what each field means are in elements.lua.
local Elements, Defaults, Groups
do
    local Data = Need("elements")
    Elements, Defaults, Groups = Data.List, Data.Defaults, Data.Groups
end

-- The position math lives in layout.lua (tested without the game); these are its names, used all over this file.
local Layout = Need("layout")
Layout.Init(Elements)
local ById, TargetFromSpot = Layout.ById, Layout.TargetFromSpot

for _, E in ipairs(Elements) do
    local d = Defaults[E.Id] or {}
    E.X, E.Y, E.Scale = d.X or 0, d.Y or 0, d.Scale or 1.0
    E.Visible = (d.Visible ~= false)
    E.Opacity = 1.0   -- every default is fully solid; F9 comma and period change it
    E.Wait = d.Wait   -- the immersive switch only: seconds a part stays before it fades (F6 sets it)
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

Engine.RemovePreviousRun()

-- The settings file and the three layout profiles live in profiles.lua; settings.lua reads and writes the file.
local Settings = Need("settings")
local Profiles = Need("profiles")
Profiles.Init({ Log = Log, VERSION = VERSION, Elements = Elements, Defaults = Defaults, Settings = Settings, Layout = Layout })
local Prof, Cfg, SaveCfg = Profiles.Prof, Profiles.Cfg, Profiles.SaveCfg
Profiles.LoadLayout()

-- What the panels share (panels.lua), and the panels with a list of settings: Rune Skin on F5 (skinpanel.lua) and
-- Rune Map on F8 (mappanel.lua). A list panel has Sel, State, View, Pick, Change and Reset; the camera rules are the third.
local Panels = Need("panels")
local Skin, MapPanel = LoadPart("skinpanel"), LoadPart("mappanel")
if Skin then Skin.Attach(ById, Defaults) end

-- The widget search lives in finder.lua (tested without the game), with its state: what its Forget drops and what the
-- perf line reads. The parts ask it through their ctx.
local Finder = Need("finder")
Finder.Init({ Elements = Elements, ById = ById, Hud = Layout.Hud, Log = Log })
local Beds = Need("beds")   -- the game's reports of new actors, for the bed names
Beds.Init({ Log = Log, Finder = Finder })

-- The editor's state. The key handlers write it on UE4SS's thread and the step reads it; the fields are all here from
-- the start (false, never nil, as with E.Moved), so a write there never grows the table while the step reads it.
-- Edit: F9 is open. Map: F8 is open. Selected: the element picked, an index of Elements. Step: how far an arrow moves
-- it. Save: a row of the layout changed in a panel or the Mod Menu, and the step saves the layout.
-- The layout is written into the widgets in apply.lua; the step gives it Edit, Map and Selected as plain values.
local Ed = { Edit = false, Map = false, Selected = 1, Step = 10, Save = false }
local Apply = Need("apply")
Apply.Init({ Elements = Elements, Layout = Layout, Log = Log })

local World, Step = Need("world"), Need("step")   -- the watch for a new world, and the main loop on the timer

-- The parts, and what each is handed (wiring.lua). It gives back the ones that this file reads itself. Keys.KEY is
-- filled at the bind below; the hint reads it when it shows.
local Keys = Need("keys")
local Wired = Need("wiring").Build({ LoadPart = LoadPart, AddPart = AddPart, Log = Log, Elements = Elements, ById = ById,
    Defaults = Defaults, Settings = Settings, Cfg = Cfg, SaveCfg = SaveCfg, Key = Keys.KEY, Ed = Ed, Engine = Engine, MayTry = MayTry,
    Failed = Failed, Finder = Finder, Apply = Apply, MapPanel = MapPanel, World = World, Beds = Beds, Step = Step })
local Camera, RuneMap, Buffs = Wired.Camera, Wired.RuneMap, Wired.Buffs

-- The list panel that is open (F6, F8 or F5), nil for none. The arrows and Backspace go to it, and the step draws it.
local function ListPanel()
    if Camera and Camera.Open then return Camera end
    if Ed.Map then return MapPanel end
    if Skin and Skin.Open then return Skin end
end

local Overlay = Need("overlay")
Keys.Init({ Log = Log, Ed = Ed, Elements = Elements, Defaults = Defaults, Prof = Prof, Layout = Layout, Settings = Settings,
    Cfg = Cfg, ListPanel = ListPanel, Overlay = Overlay, World = World, Panels = Panels, Camera = Camera, Skin = Skin,
    MapPanel = MapPanel, RuneMap = RuneMap })
-- the F9 and F8 panel, drawn by editor.lua; the step fills it (overlay.lua)
Overlay.Init({ Log = Log, Elements = Elements, Defaults = Defaults, Groups = Groups, Ed = Ed, Prof = Prof, KEY = Keys.KEY,
    Parts = Parts, ListPanel = ListPanel, Panels = Panels, Layout = Layout, Engine = Engine, World = World,
    MayTry = MayTry, Failed = Failed, Editor = LoadPart("editor") })
World.Init({ Log = Log, Elements = Elements, Finder = Finder, Apply = Apply, Parts = Parts, Engine = Engine, Beds = Beds,
    Overlay = Overlay })

-- The perf lines in UE4SS.log, every 60 s, are made in perf.lua. Perf is its counter: the step adds its times to it.
local Perf = Need("perf")
Perf.Init({ Log = Log, ById = ById, Elements = Elements, RuneMap = RuneMap, Finder = Finder, Actors = Beds.Actors })
if Wired.Util.Chain then Wired.Util.Chain.Add = Perf.Add end   -- the chains count their calls by part too

Step.Init({ Log = Log, Parts = Parts, Ed = Ed, Prof = Prof, World = World, Finder = Finder, Apply = Apply, Perf = Perf,
    Profiles = Profiles, Overlay = Overlay, Keys = Keys, Beds = Beds, Buffs = Buffs, Camera = Camera, Skin = Skin })
Step.Start()

-- A player restart (entering a world, respawning) can rebuild the game's HUD: drop every handle into it
-- first. Widgets added before the restart and read after it crashed the game on entering (27-09-2026).
RegisterHook("/Script/Engine.PlayerController:ClientRestart", function()
    local name = World.ControllerName()
    World.Forget(name == World.Name)   -- the same controller: the same world, still standing
    World.Name = name
    if not (Ed.Edit or Ed.Map) then Profiles.LoadLayout() end   -- dying with the editor open keeps the unsaved changes
end)

-- The Mod Menu page is an extra: without its rows the keys below are still bound.
local MenuRows = LoadPart("menurows")
if MenuRows then
    MenuRows.Add({ LoadPart = LoadPart, AddPart = AddPart, Log = Log, Prof = Prof, Settings = Settings, Cfg = Cfg,
        SaveCfg = SaveCfg, ReadText = Settings.ReadFile, KEY_DEFAULT = Keys.DEFAULT, Ed = Ed, ById = ById, RuneMap = RuneMap,
        Camera = Camera, Skin = Skin, Overlay = Overlay })
end
Keys.Bind()
