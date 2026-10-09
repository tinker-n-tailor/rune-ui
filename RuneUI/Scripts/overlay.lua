-- The panel on the screen: which view it shows (the F9 view here, the other three from their own files), where it sits,
-- and the step that fills and places it. editor.lua draws it. main.lua loads this file and gives it its own names
-- (Init); the step calls SortOrder when the editor opens and Update on every step, and the world watch calls Forget.

local M = {}

-- From main.lua (Init): the log, the element list, the starting layout and the groups (elements.lua), the editor's
-- state (Ed), the profile in use, the names of the keys, the list of parts, the open list panel, what the panels share
-- (panels.lua), layout.lua, the helpers of engine.lua, the world watch, the retry rule (MayTry, Failed) and the
-- drawing of the panel (editor.lua, nil when it did not load).
local Log, Elements, Defaults, Groups, Ed, Prof, KEY, Parts, ListPanel, Panels, Layout, Engine, World, MayTry, Failed, Editor
local Hud, ById, IsSwitch, FinalCenter, ScreenBox, Spot
function M.Init(ctx)
    Log, Elements, Defaults, Groups, Ed, Prof = ctx.Log, ctx.Elements, ctx.Defaults, ctx.Groups, ctx.Ed, ctx.Prof
    KEY, Parts, ListPanel, Panels, Layout = ctx.KEY, ctx.Parts, ctx.ListPanel, ctx.Panels, ctx.Layout
    Engine, World, MayTry, Failed, Editor = ctx.Engine, ctx.World, ctx.MayTry, ctx.Failed, ctx.Editor
    Hud, ById, IsSwitch, FinalCenter, ScreenBox, Spot = Layout.Hud, Layout.ById, Layout.IsSwitch, Layout.FinalCenter, Layout.ScreenBox, Layout.Spot
end

-- The F9 list by what the part is: the groups of elements.lua, in their order (Panels.Order). Read when the editor
-- opens: the group of all notices has a row only while it is hidden. PgUp and PgDn go down this list.
M.Order = {}   -- element indexes in list order
local GroupOf = {}   -- element index -> the name of its group, from the last SortOrder
function M.SortOrder()
    M.Order, GroupOf = Panels.Order(Elements, Groups)
    if not GroupOf[Ed.Selected] then Ed.Selected = M.Order[1] end   -- the selected element has no row any more
end

-- moved, resized or faded from its default: a gold diamond on its row
local function Changed(E)
    local d = Defaults[E.Id] or {}
    return math.abs(E.X - (d.X or 0)) > 0.5 or math.abs(E.Y - (d.Y or 0)) > 0.5 or math.abs(E.Scale - (d.Scale or 1)) > 0.001
        or E.Opacity < 1
end

-- The keys the editor lists. KEY: the names of the seven keys a player can change, as bound
-- (KeyCode, in keys.lua, writes them at load). So the list is made when the panel is filled, not at load.
local function EditKeys()
    return { { { "PgUp", "PgDn" }, "Select" }, { { "←", "→", "↑", "↓" }, "Move" }, { { "+", "-" }, "Size" },
        { { ",", "." }, "Opacity" }, { { "Home", "End" }, "Step" }, { { "Del", "Ins" }, "Hide, show" },
        { { "Backspace" }, "Reset" }, { { KEY.editor }, "Save, close" } }
end
-- The parts that failed, for a line on every panel: a part whose step or scan threw (Parts), or that gave
-- up building (Fails, see MayTry; a part with several builds says so itself with Problem).
local function Problems()
    local out = {}
    for _, P in ipairs(Parts) do
        if P.Error or (P.M.Fails or 0) >= 3 or (P.M.Problem and P.M.Problem()) then out[#out + 1] = P.Name end
    end
    if #out == 0 then return nil end
    return "Failed: " .. table.concat(out, ", ") .. ". See UE4SS.log in Win64."
end

-- The F9 view. Rows holds every line of the list; Update shows the lines that fit.
local function EditView()
    local E = Elements[Ed.Selected]
    local v = { Mode = "edit", Title = "LAYOUT", Profile = Prof.N, Keys = EditKeys(), Name = E.Name, Map = {}, Warn = Problems(), Rows = {} }
    local cx, cy = Spot(E)
    local sx, sy = math.floor(cx + 0.5), math.floor(cy + 0.5)   -- on a 1920 x 1080 screen
    v.Facts = { { "X", tostring(sx) }, { "Y", tostring(sy) }, { "Size", math.floor(E.Scale * 100 + 0.5) .. "%" },
        { "Opacity", math.floor(E.Opacity * 100 + 0.5) .. "%" }, { "Step", tostring(Ed.Step) } }
    if not E.Visible then v.Hint = "Hidden. Ins shows it again."
    elseif #E.Instances == 0 then v.Hint = "Not on the screen right now. It still moves." end
    local x, y, w, h = ScreenBox(E)
    v.Mark = { X = x, Y = y, W = w, H = h, Name = E.Name, XY = "X " .. sx .. "   Y " .. sy, Sample = E.Visible and E.Sample or nil }
    -- the screen map: every element with a place, in 1920 x 1080 units
    for i, El in ipairs(Elements) do
        if not IsSwitch(El) and #v.Map < Editor.BOXES then
            local ex, ey, s = Spot(El)
            local bw, bh = Layout.Box(El)
            v.Map[#v.Map + 1] = { X = ex - El.Size.X * s / 2, Y = ey - bh * s / 2, W = bw * s, H = bh * s,
                Sel = i == Ed.Selected, Hidden = not El.Visible, Name = El.Name }
        end
    end
    local last
    for _, i in ipairs(M.Order) do
        local El = Elements[i]
        if GroupOf[i] ~= last then last = GroupOf[i] v.Rows[#v.Rows + 1] = { Head = true, Text = last } end
        local gone = #El.Instances == 0
        v.Rows[#v.Rows + 1] = { Text = El.Name, Sel = i == Ed.Selected, Moved = Changed(El), Dim = gone or not El.Visible,
            Note = not El.Visible and "hidden" or gone and "not on screen" or nil }
    end
    return v
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
function M.Update(now)
    local P = ListPanel()   -- F6, F8 or F5: a list of settings, in the same panel
    local open = Ed.Edit or P ~= nil
    if not Editor then return end
    if not open and not Editor.Shown then return end   -- closed, and nothing of the panel on screen to take away
    if open and not Editor.Ready() and MayTry(Editor) and os.clock() > World.SettleUntil and World.Name ~= "" then
        local ok, err = Editor.Build({ Log = Log, Gen = Engine.Round, Font = Engine.FindPoppins(), FontMedium = Engine.FindPoppinsMedium(), Asset = Engine.Asset,
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
        if P then
            state = P.State() .. "|" .. Hud.VW .. "|" .. Hud.VH .. "|" .. (Problems() or "")
        else
            local parts = { "edit", Ed.Selected, Ed.Step, Prof.N, Hud.VW, Hud.VH, Hud.S, Problems() or "" }
            for _, El in ipairs(Elements) do
                parts[#parts + 1] = string.format("%.1f,%.1f,%.2f,%.1f,%s,%d", El.X, El.Y, El.Scale, El.Opacity,
                    El.Visible and "1" or "0", #El.Instances)
            end
            state = table.concat(parts, "|")
        end
        -- opened before the fill: while the fill fails, the player sees the panel as it was last filled (empty
        -- on the first open), not no panel
        if not Editor.Shown then Editor.Open(true) Editor.Shown = true end
        if state ~= Panel.State then
            local v = P and P.View(KEY, Problems()) or EditView()
            v.Rows = Panels.Window(v.Rows, Editor.ROWS)
            Editor.Update(Panels.Links(v, KEY))
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

-- A new world or a player restart: new tries to build the panel (see MayTry). With a new world the panel of the old one is
-- off the screen: build a new one on the next F9, and say its errors again if it fails again.
function M.Forget(sameWorld)
    if not Editor then return end
    Editor.Fails, Editor.RetryAt = 0, 0
    if not sameWorld then Editor.Forget() Editor.Shown, Panel.State, Panel.Logged, Panel.Lines = false, "", {}, 0 end
end

return M
