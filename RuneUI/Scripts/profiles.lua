-- The settings file in memory (Cfg), the three layout profiles, and the loading and saving of the layout of the profile
-- in use. settings.lua reads and writes the file itself. main.lua loads this file, calls Init once, then LoadLayout, and
-- the step and the Mod Menu rows call SaveLayout and Prof.Next.

local M = {}

-- From main.lua (Init): the log, the version for the file, the element list and its starting layout, settings.lua and layout.lua's names.
local Log, VERSION, Elements, Defaults, Settings, Third, Retarget, TargetFromSpot
local Cfg
local ElementIds = {}   -- the order of the rows in the file: the element list

-- The profiles: three layouts, F7 goes to the next while the editor is open. Profile 1 is the layout every
-- older version wrote, so no player loses a layout. N: the profile in use. Wanted: F7 sets it on UE4SS's thread,
-- and the step switches.
local Prof = { N = 1, Wanted = false }
M.Prof = Prof

-- One file, runeui.txt, next to the game: the three layout profiles, the profile in use, the map settings and
-- the zoom, the camera settings, and the keys. Named values, so a player can read and edit it, and a new
-- version never breaks an old file. The files of older versions are read once, when runeui.txt is missing, and are
-- left in place.
function M.Init(ctx)
    Log, VERSION, Elements, Defaults, Settings = ctx.Log, ctx.VERSION, ctx.Elements, ctx.Defaults, ctx.Settings
    Third, Retarget, TargetFromSpot = ctx.Layout.Third, ctx.Layout.Retarget, ctx.Layout.TargetFromSpot
    local fresh = false
    Cfg = Settings.Load()
    if not Cfg then
        Cfg = Settings.Legacy(Settings.ReadFile)
        if Cfg then Log("settings: read from the files of an older version") else Cfg = {} fresh = true Log("no settings file yet, using defaults") end
    end
    Cfg.menuart = nil   -- the main menu's line under the bars, no longer used: dropped from old files
    M.Cfg = Cfg
    for _, E in ipairs(Elements) do ElementIds[#ElementIds + 1] = E.Id end
    local general = Settings.Section(Cfg, "general")
    Prof.N = math.floor(Settings.Num(general.profile, 1, 3, 1))
    -- f9hint: 0 until hint.lua has shown the F9 hint, then 1. A player who has the mod from before it never sees the hint,
    -- so a file without the line is marked at once; a fresh install keeps the 0 in memory, and the first save writes it.
    if general.f9hint == nil then
        general.f9hint = fresh and 0 or 1
        if not fresh then M.SaveCfg() end
    end
end

function M.SaveCfg()
    Settings.Section(Cfg, "general").version = VERSION
    if not Settings.Save(Cfg, nil, ElementIds) then Log("could not write " .. Settings.FILE) end
end

-- the layout of the profile in use, from the file; an element without a row (a part newer than the profile) gets its starting layout
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
        else
            local d = Defaults[E.Id] or {}
            E.X, E.Y, E.Scale, E.Visible, E.Opacity, E.Wait = d.X or 0, d.Y or 0, d.Scale or 1.0, d.Visible ~= false, 1.0, d.Wait
            TargetFromSpot(E)
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
    M.SaveCfg()
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

M.LoadLayout, M.SaveLayout = LoadLayout, SaveLayout
return M
