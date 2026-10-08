-- The Rune Skin panel (F5): one switch for each look of Rune UI that a player can turn off.
-- A row is a switch of the layout (elements.lua): its name is the element's name and its value is the element's
-- Visible. So each profile has its own switches, and a file of an older version keeps its values.
-- Pure Lua, no game calls, so tools/test-panels.js runs it without the game. main.lua draws the panel from View and
-- saves the layout when LayoutDirty is set.
local M = {}

-- Id: the element. On, Off: the hint under the selected row for each value.
M.ROWS = {
    { Id = "wheels", On = "The spell, item and emote wheels have the look of Rune UI.", Off = "The game's own wheels." },
    { Id = "combattext", On = "Bigger damage numbers. A critical hit is gold and pops.", Off = "The game's own damage numbers." },
    { Id = "runexp", On = "The XP shows under the bars.", Off = "The game's XP circle." },
    { Id = "slimlevel", On = "A level up shows under the bars. It needs XP under the bars.", Off = "The game's level up banner." },
    { Id = "aim", On = "The aim marks are gold, and the lock-on mark is a gold diamond.", Off = "The game's own crosshair and lock-on mark." },
    { Id = "baricons", On = "The game's icons show beside the bars.", Off = "No icons beside the bars." },
    { Id = "cdhoriz", On = "The cooldown tiles are in a row. Move them in Layout.", Off = "The cooldown tiles are in a column. Move them in Layout." },
    { Id = "questnext", On = "The quest tracker also lists up to 3 next steps.", Off = "The quest tracker shows the current step only." },
}

-- The key handlers run on UE4SS's own thread: they change these fields and an element's Visible, and add no key.
M.Open, M.Sel, M.LayoutDirty = false, 1, false

-- byId: layout.lua's ById. defaults: the starting layout of elements.lua. Called once at the start.
function M.Attach(byId, defaults)
    for _, r in ipairs(M.ROWS) do
        r.E = byId(r.Id)
        r.Default = (defaults[r.Id] or {}).Visible ~= false
    end
end

local function Value(r) return r.E.Visible and "On" or "Off" end

-- what the panel shows now, as one string: a new view only when it changed
function M.State()
    local parts = { "skin", M.Sel }
    for _, r in ipairs(M.ROWS) do parts[#parts + 1] = Value(r) end
    return table.concat(parts, "|")
end

-- the view for editor.lua. keys: main.lua's key names.
function M.View(keys, warn)
    local sel = M.ROWS[M.Sel]
    local v = { Mode = "skin", Title = "RUNE SKIN", Warn = warn,
        Keys = { { { "↑", "↓" }, "Select" }, { { "←", "→" }, "Change" }, { { "Backspace" }, "Reset" },
            { { keys.editor }, "Layout" }, { { keys.skin }, "Save, close" } },
        Name = sel.E.Name .. ":  " .. Value(sel), Hint = sel.E.Visible and sel.On or sel.Off, Rows = {} }
    for i, r in ipairs(M.ROWS) do v.Rows[i] = { Text = r.E.Name, Note = Value(r), Sel = i == M.Sel } end
    return v
end

-- the keys: up and down pick a row, left and right switch it, Backspace gives every row its starting value
function M.Pick(d) M.Sel = (M.Sel - 1 + d) % #M.ROWS + 1 end
function M.Change()
    local E = M.ROWS[M.Sel].E
    E.Visible = not E.Visible
    M.LayoutDirty = true
end
function M.Reset()
    for _, r in ipairs(M.ROWS) do r.E.Visible = r.Default end
    M.LayoutDirty = true
end

return M
