-- The keys: their names, what each one does, and the held arrow. main.lua loads this file, gives it its own names (Init),
-- and calls Bind once, where the keys are bound. Windows key codes; the handlers only change state, the step does the work.
--
-- Key binds run on UE4SS's own thread, beside the game thread's step: they only change numbers and flags, and
-- make nothing new (no text, no tables), so they cannot start Lua's memory cleanup under the step (28-09-2026).
-- The step logs the editor opening and closing.

local M = {}

-- From main.lua (Init): the log, the editor's state (Ed), the element list and starting layout, the profile in use,
-- layout.lua's names, the settings file (settings.lua and Cfg), the open list panel, the F9 list (overlay.lua), the
-- world watch, what the panels share (panels.lua), and the panels and the map that a key goes to.
local Log, Ed, Elements, Defaults, Prof, IsSwitch, TargetFromSpot, Settings, Cfg, ListPanel, Overlay, World, Panels
local Camera, Skin, MapPanel, RuneMap
function M.Init(ctx)
    Log, Ed, Elements, Defaults, Prof = ctx.Log, ctx.Ed, ctx.Elements, ctx.Defaults, ctx.Prof
    IsSwitch, TargetFromSpot = ctx.Layout.IsSwitch, ctx.Layout.TargetFromSpot
    Settings, Cfg, ListPanel, Overlay, World, Panels = ctx.Settings, ctx.Cfg, ctx.ListPanel, ctx.Overlay, ctx.World, ctx.Panels
    Camera, Skin, MapPanel, RuneMap = ctx.Camera, ctx.Skin, ctx.MapPanel, ctx.RuneMap
end

-- Windows key codes by name. The seven keys in KEY_DEFAULT can be changed in the [keys] section of runeui.txt;
-- the others are fixed, as the F9 panel lists them. skin: no use of F5 by the game was found (08-10-2026), but its
-- own key list is packed and could not be read.
local VK = { Backspace = 8, PgUp = 33, PgDn = 34, End = 35, Home = 36, Left = 37, Up = 38, Right = 39, Down = 40,
    Insert = 45, Delete = 46, Plus = 107, Minus = 109, Equals = 187, Dash = 189, Comma = 188, Period = 190,
    ["["] = 219, ["]"] = 221 }
for i = 1, 12 do VK["F" .. i] = 111 + i end
for i = 0, 9 do VK[tostring(i)] = 48 + i end
for i = 0, 25 do VK[string.char(65 + i)] = 65 + i end
local KEY_DEFAULT = { editor = "F9", map = "F8", profile = "F7", zoomin = "]", zoomout = "[", camera = "F6", skin = "F5" }
M.DEFAULT = KEY_DEFAULT
-- The names as bound (KeyCode writes them), for the panels to show.
local KEY = {}
M.KEY = KEY
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

-- the arrows move the selected element by the step; a held arrow keeps moving it (see HoldMove)
local function Move(dx, dy)
    local E = Elements[Ed.Selected]
    if not Ed.Edit or IsSwitch(E) then return end
    if E.OnlyY then dx = 0 end
    E.X, E.Y = E.X + dx * Ed.Step, E.Y + dy * Ed.Step
    E.Moved = true   -- on saving, it follows the edge nearest to where it now sits (Retarget)
end

-- The key bind moves once on the press. The engine says which keys are down (a test in game, 01-10-2026): an arrow
-- held past Hold.After moves again on every step (50 ms), so a step of 10 goes 200 units a second.
local Hold = { After = 0.35, Keys = nil, Since = nil }   -- Keys: { key, dx, dy }, made on first use
function M.HoldMove(now)
    if not Ed.Edit or Ed.Map then Hold.Since = nil return end
    local pc = World.Player and World.Player:IsValid() and World.Player.PlayerController
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

-- One panel at a time: the key of a panel closes it, or opens it and closes the one that was open. Leaving the editor
-- or the map settings saves the layout, which holds the creatures switch. The other two panels save as they change.
local function Toggle(which)
    local P = which == "camera" and Camera or which == "skin" and Skin   -- a panel that holds its own Open
    local was = (which == "edit" and Ed.Edit) or (which == "map" and Ed.Map) or (P and P.Open)
    if Ed.Edit or Ed.Map then Ed.Save = true end
    Ed.Edit, Ed.Map = which == "edit" and not was, which == "map" and not was
    if Camera then Camera.Open = which == "camera" and not was end
    if Skin then Skin.Open = which == "skin" and not was end
end

-- PgUp and PgDn go up and down the list as the panel shows it, group by group (Order)
local function Sel(d)
    local Order = Overlay.Order
    if not Ed.Edit or #Order == 0 then return end
    local at = 1
    for n, i in ipairs(Order) do if i == Ed.Selected then at = n end end
    Ed.Selected = Order[(at - 1 + d) % #Order + 1]
end

-- the arrows: in a list panel up and down pick a row and left and right change it; in the editor they move the element
local function Arrow(dx, dy)
    local P = ListPanel()
    if not P then Move(dx, dy) elseif dy ~= 0 then P.Pick(dy) else P.Change(dx) end
end

local Steps = { 1, 5, 10, 25, 50, 100 }
local function ChangeStep(d)
    if not Ed.Edit then return end
    local idx = 3
    for i, s in ipairs(Steps) do if s == Ed.Step then idx = i end end
    idx = math.max(1, math.min(#Steps, idx + d))
    Ed.Step = Steps[idx]
end

local function Resize(d)
    local E = Elements[Ed.Selected]
    if not Ed.Edit or IsSwitch(E) or E.OnlyY then return end
    E.Scale = math.max(0.3, math.min(4.0, math.floor((E.Scale + d) * 100 + 0.5) / 100))   -- up to 400%
end

-- comma and period: less or more solid, in steps of 10%, down to 20%; hiding is Delete
local function Fade(d)
    local E = Elements[Ed.Selected]
    if not Ed.Edit or IsSwitch(E) then return end
    E.Opacity = math.max(0.2, math.min(1.0, math.floor((E.Opacity + d) * 10 + 0.5) / 10))
end

local NoDefaults = {}
function M.Bind()
    RegisterKeyBind(KeyCode("editor"), function() Toggle("edit") end)
    if Skin then RegisterKeyBind(KeyCode("skin"), function() Toggle("skin") end) end
    if MapPanel then RegisterKeyBind(KeyCode("map"), function() Toggle("map") end) end
    if Camera then RegisterKeyBind(KeyCode("camera"), function() Toggle("camera") end) end

    -- The map's zoom, any time: ] closer, [ farther (Windows codes 221 and 219). The game has no buttons to click.
    RegisterKeyBind(KeyCode("zoomin"), function() if RuneMap then RuneMap.ZoomBy(1 / 1.25) end end)
    RegisterKeyBind(KeyCode("zoomout"), function() if RuneMap then RuneMap.ZoomBy(1.25) end end)

    RegisterKeyBind(VK.PgUp, function() Sel(-1) end)
    RegisterKeyBind(VK.PgDn, function() Sel(1) end)

    RegisterKeyBind(VK.Up, function() Arrow(0, -1) end)
    RegisterKeyBind(VK.Down, function() Arrow(0, 1) end)
    RegisterKeyBind(VK.Left, function() Arrow(-1, 0) end)
    RegisterKeyBind(VK.Right, function() Arrow(1, 0) end)

    RegisterKeyBind(VK.Home, function() ChangeStep(1) end)
    RegisterKeyBind(VK.End, function() ChangeStep(-1) end)

    RegisterKeyBind(VK.Plus, function() Resize(0.05) end)     -- the number pad
    RegisterKeyBind(VK.Minus, function() Resize(-0.05) end)
    RegisterKeyBind(VK.Equals, function() Resize(0.05) end)   -- the main keys: = is + without Shift
    RegisterKeyBind(VK.Dash, function() Resize(-0.05) end)

    RegisterKeyBind(VK.Comma, function() Fade(-0.1) end)
    RegisterKeyBind(VK.Period, function() Fade(0.1) end)

    -- F7: the next layout profile, only while the editor is open (the step saves this one and loads the next)
    RegisterKeyBind(KeyCode("profile"), function() if Ed.Edit then Prof.Wanted = true end end)

    RegisterKeyBind(VK.Delete, function() if Ed.Edit and not Elements[Ed.Selected].NoHide then Elements[Ed.Selected].Visible = false end end)
    RegisterKeyBind(VK.Insert, function() if Ed.Edit then Elements[Ed.Selected].Visible = true end end)
    RegisterKeyBind(VK.Backspace, function()
        local P = ListPanel()
        if P then P.Reset() return end   -- every row of that panel back to its starting value
        if not Ed.Edit then return end
        local E = Elements[Ed.Selected]
        local d = Defaults[E.Id] or NoDefaults
        E.X, E.Y, E.Scale, E.Visible, E.Opacity = d.X or 0, d.Y or 0, d.Scale or 1.0, (d.Visible ~= false), 1.0
        E.Moved = false
        TargetFromSpot(E)
    end)

    local keys = {}
    for _, p in ipairs(Panels.LIST) do if KEY[p.Key] then keys[#keys + 1] = p.Name .. " " .. KEY[p.Key] end end
    Log("loaded, the panels in game: " .. table.concat(keys, ", "))
end

return M
