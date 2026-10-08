-- The Rune Map panel (F8): its rows, the value and the hint of each, and what the keys do.
-- runemap.lua holds the settings (Set) and saves them when Dirty is set. The Creatures row also uses the layout's
-- "creatures" switch, which each profile has for itself.
-- No game calls of its own, so tools/test-hints.js and tools/test-panels.js run it without the game. main.lua draws
-- the panel from View.
local M = {}

M.ROWS = { "Rune Map", "Faces north", "North mark", "Player name", "Creatures", "Ore", "Herbs", "Essence", "Rare trees",
    "In immersive mode", "Zoom", "Drawing" }
-- the group title above a row
local HEADS = { Creatures = "What the map shows", ["In immersive mode"] = "Behaviour" }
-- the rows that are a plain On / Off, and the setting in runemap.lua each one flips. "In immersive mode" steps
-- through Nothing, Map and Compass (settings.lua STAY), Creatures through three values: Value and Change have them.
local SWITCH = { ["Rune Map"] = "Map", ["Faces north"] = "North", ["North mark"] = "Mark", ["Player name"] = "Name", Ore = "Ore",
    Herbs = "Herbs", Essence = "Essence", ["Rare trees"] = "Trees" }
-- the rows with more than two values: the list shows "< value >", so a player sees that Left and Right give more
-- than what is shown
local CHOICE = { Creatures = true, ["In immersive mode"] = true, Zoom = true }

M.Sel = 1   -- the selected row; the key handlers write it on UE4SS's own thread
local RuneMap, Creatures, STAY = nil, { Visible = true }, { "Nothing" }

-- p: RuneMap (runemap.lua, nil when it did not load), Creatures (the layout's switch), Stay (settings.lua STAY)
function M.Attach(p) RuneMap, Creatures, STAY = p.RuneMap, p.Creatures, p.Stay end

function M.Value(i)
    local S = RuneMap and RuneMap.Set or {}
    local row = M.ROWS[i]
    if row == "Creatures" then
        if not Creatures.Visible then return "Off" end
        return S.Neutral and "All" or "Enemies only"
    end
    if row == "Zoom" then return RuneMap and string.format("%d%%", math.floor(200 / RuneMap.ZoomLevel() + 0.5)) or "-" end
    if row == "Drawing" then return S.Smooth and "Smooth" or (S.Fastest and "Fastest" or "Faster") end
    if row == "In immersive mode" then return S.Immersive or "Nothing" end
    return S[SWITCH[row]] and "On" or "Off"
end

local HINTS = {
    ["Rune Map"] = { Off = "The map is off. The mod does not build it at all." },   -- On names the Layout key: Hint
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
        Map = "The map and the quest tracker stay in the immersive mode. The compass is away." },   -- Compass: Hint
    Drawing = { Smooth = "The map draws every frame. Switching might decrease performance.",
        Faster = "The map draws every second frame. A bit choppy when you turn.", Fastest = "The map draws every fourth frame. The lightest, and the choppiest." },
}
-- the hint under the selected row i with the value v. keys: main.lua's key names.
function M.Hint(i, v, keys)
    local row = M.ROWS[i]
    if row == "Zoom" then return "Closer or farther. The " .. keys.zoomout .. " and " .. keys.zoomin .. " keys do the same at any time." end
    if row == "In immersive mode" and v == "Compass" then
        return "Only the compass stays, with the map marks. The map is away."
    end
    if row == "Rune Map" and v == "On" then return "The map is on. To only hide it, use Delete in " .. keys.editor .. "." end
    return HINTS[row] and HINTS[row][v] or ""
end

-- what the panel shows now, as one string: a new view only when it changed
function M.State()
    local parts = { "map", M.Sel }
    for i = 1, #M.ROWS do parts[#parts + 1] = M.Value(i) end
    return table.concat(parts, "|")
end

-- the view for editor.lua: every row, with the group titles. main.lua shows the lines that fit (panels.lua Window).
function M.View(keys, warn)
    local val = M.Value(M.Sel)
    local v = { Mode = "map", Title = "RUNE MAP", Warn = warn,
        Keys = { { { "↑", "↓" }, "Select" }, { { "←", "→" }, "Change" }, { { keys.zoomout, keys.zoomin }, "Zoom" },
            { { "Backspace" }, "Reset" }, { { keys.editor }, "Layout" }, { { keys.map }, "Save, close" } },
        Name = M.ROWS[M.Sel] .. ":  " .. val, Hint = M.Hint(M.Sel, val, keys), Rows = {} }
    for i, row in ipairs(M.ROWS) do
        if HEADS[row] then v.Rows[#v.Rows + 1] = { Head = true, Text = HEADS[row] } end
        val = M.Value(i)
        v.Rows[#v.Rows + 1] = { Text = row, Note = CHOICE[row] and ("< " .. val .. " >") or val, Sel = i == M.Sel }
    end
    return v
end

-- the keys: up and down pick a row
function M.Pick(d) M.Sel = (M.Sel - 1 + d) % #M.ROWS + 1 end

-- left and right: the zoom row zooms; Creatures, In immersive mode and Drawing step through their values; every
-- other row switches
function M.Change(d)
    if not RuneMap then return end
    local S = RuneMap.Set
    local row = M.ROWS[M.Sel]
    local step = d > 0 and 1 or -1
    if row == "Zoom" then RuneMap.ZoomBy(d > 0 and 1 / 1.25 or 1.25)
    elseif row == "Drawing" then   -- Smooth, Faster, Fastest
        local st = ((S.Smooth and 1 or (S.Fastest and 3 or 2)) - 1 + step) % 3 + 1
        S.Smooth, S.Fastest = st == 1, st == 3
    elseif row == "In immersive mode" then
        local st = 1   -- the place of the value in STAY
        for i, name in ipairs(STAY) do if name == S.Immersive then st = i end end
        S.Immersive = STAY[(st - 1 + step) % #STAY + 1]
    elseif row == "Creatures" then
        local st = (not Creatures.Visible) and 3 or (S.Neutral and 1 or 2)
        st = (st - 1 + step) % 3 + 1
        Creatures.Visible, S.Neutral = st ~= 3, st == 1
    else
        local k = SWITCH[row]
        S[k] = not S[k]
    end
    RuneMap.Dirty = true
end

-- Backspace: every row back to its starting value
function M.Reset()
    if not RuneMap then return end
    RuneMap.Reset()
    Creatures.Visible = true
end

return M
