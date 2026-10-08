-- What the four panels share: Layout (F9), Rune Skin (F5), Rune Map (F8) and Immersion mode (F6). The head of each
-- panel names the other three and their keys, the list shows the lines that fit, and the F9 list has its order.
-- Pure Lua, no game calls, so tools/test-panels.js runs it without the game. main.lua stops when this file is missing.
local M = {}

-- Mode: the Mode of the panel's view. Key: the name of its key in main.lua's KEY and in the [keys] part of runeui.txt.
M.LIST = { { Mode = "edit", Name = "Layout", Key = "editor" }, { Mode = "skin", Name = "Rune Skin", Key = "skin" },
    { Mode = "map", Name = "Rune Map", Key = "map" }, { Mode = "camera", Name = "Immersion mode", Key = "camera" } }

-- The other panels and their keys, as bound, into the view v. A panel that did not load has no key and is left out.
function M.Links(v, keys)
    v.Links = {}
    for _, p in ipairs(M.LIST) do
        if p.Mode ~= v.Mode and keys[p.Key] then v.Links[#v.Links + 1] = { p.Name, keys[p.Key] } end
    end
    return v
end

-- The lines of a list that show: max of them, group titles too, with the selected row in the middle when it can be.
function M.Window(lines, max)
    local at = 1
    for i, l in ipairs(lines) do if l.Sel then at = i end end
    local first = math.max(1, math.min(at - math.floor(max / 2), #lines - max + 1))
    local out = {}
    for n = first, math.min(#lines, first + max - 1) do out[#out + 1] = lines[n] end
    -- a group title on the last line has its rows cut off below: a title with nothing under it
    if #out > 0 and out[#out].Head then out[#out] = nil end
    return out
end

-- The F9 list: the indexes of the elements in the order of the groups (elements.lua), and the group of each index.
-- An element with NoRow has a row only while it is hidden, so a player who hid it can show it again.
function M.Order(elements, groups)
    local index, order, groupOf = {}, {}, {}
    for i, E in ipairs(elements) do index[E.Id] = i end
    for _, g in ipairs(groups) do
        for _, id in ipairs(g.Ids) do
            local i = index[id]
            if i and not (elements[i].NoRow and elements[i].Visible) then
                order[#order + 1] = i
                groupOf[i] = g.Name
            end
        end
    end
    return order, groupOf
end

return M
