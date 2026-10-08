-- What only the spell wheel (Q) has: the texts in its middle, kept inside the ring, and the cooldown of a spell as
-- a gold arc on its slot. wheels.lua calls this file; every write goes through the journal of wheelparts.lua.
-- main.lua loads it with pcall. How it works is in tools/notes/wheels-q.md.

local M = {}

local NAME_BOX = 175                   -- units: the width of the game's box for the spell name
local NAME_ROOM, TEXT_ROOM = 158, 160  -- units of room inside the ring: for the spell name, for the requirement
local LABEL, TEXT_MOST = 0.75, 0.82    -- the render scale of the word "Requirements:"; the most for the requirement
local CENTRE = { X = 0.5, Y = 0.5 }
-- The room under the spell name (down to the requirement) is about 52 units, its middle about 5 units below the middle of
-- the visible cost row, which is about 62 units high (measured on pictures of real costs of 07-10-2026). COST_SCALE
-- makes the row about 45 high, COST_MOVE (units, a render translation) puts its middle in the middle of the room.
-- Not seen in the game: the two values to tune. The "-" gets 1 / COST_SCALE and minus COST_MOVE / COST_SCALE back.
local COST_SCALE = 0.72
local COST_MOVE = { X = 0, Y = 5 }
-- slot paddings of the middle, tighter than the game's 145 and 130
local PAD = { Name = { Bottom = 137 }, Requirement = { Top = 122 } }
-- The cooldown widget of a slot is 36 units at the slot's top left. Scale and Move put its timer ring just inside
-- the slot's ring, whose middle is at 68.75, 60 of the slice.
local ARC = { Scale = { X = 2.6, Y = 2.6 }, Move = { X = 35.75, Y = 32 }, Gold = { R = 0.76, G = 0.48, B = 0.10, A = 1 },
    Hide = { "BackgroundRing", "IconImage", "CooldownText" } }
local FONT_AGAIN, FONT_TRIES = 10, 6   -- the HUD font not found yet: seconds to the next try, and how many tries
local SKIP = { CostBox = true }        -- taken, but not entered: a walk into the rune cost widget crashed the game
-- Under the wheel, beside the spell's name: "Cooldown 0s" and the room around it go, as the slot shows the cooldown.
local UNDER = { "Cooldown", "CooldownText", "CooldownUnits", "Spacer_67", "Spacer_116" }
local COLLAPSED = 1

local Ok, Kid   -- wheelparts.lua's, given by wheels.lua before the first call
function M.Init(P) Ok, Kid = P.Ok, P.Kid end

-- Every widget under root by its name, and for each the child of root that it sits under. A widget of a game
-- class of its own (WBP_) is taken but not entered, and so is each name in SKIP.
local function Tree(root)
    local by, top = {}, {}
    local function Walk(W, under, depth)
        if not Ok(W) or depth > 6 then return end
        local name = W:GetFName():ToString()
        by[name], top[name] = W, under
        if SKIP[name] then return end
        if string.find(W:GetClass():GetFName():ToString(), "^WBP_") then return end
        local okN, n = pcall(function() return W:GetChildrenCount() end)
        if okN and type(n) == "number" then
            for i = 0, n - 1 do Walk(W:GetChildAt(i), under, depth + 1) end
        end
    end
    for i = 0, root:GetChildrenCount() - 1 do
        local c = root:GetChildAt(i)
        Walk(c, c, 1)
    end
    return by, top
end

-- The parts of the middle, found once for a wheel. The two requirement texts and CostBox are no variables of the
-- wheel, so they come from the tree under CenterBox, by name.
local function Middle(w)
    if w.Mid then return w.Mid end
    local name = Kid(w.W, "SpellName")
    if not name then return nil end
    local box = name:GetParent()
    local by, top = Tree(Kid(w.W, "CenterBox") or box:GetParent())
    w.Mid = { Name = name, Box = box, Label = by.RequirementDescription, Text = by.RequirementText, TextBox = top.RequirementText, CostBox = by.CostBox,
        NoCost = Kid(w.W, "NoCostTextBlock") }
    return w.Mid
end

-- One text made smaller when it is wider than its room (Fit in wheelparts.lua); box: the size box that would cut
-- it, made as wide as the text. Written only when the wanted width changes: the game writes a new text for each
-- picked spell.
local function FitOne(P, J, w, key, T, room, box, most)
    local want = P.Fit(J, w.Want, key, T, room, most)
    if want and Ok(box) then P.Set(J, key .. "Box", box, "Width", math.max(NAME_BOX, want + 2)) end
end

-- the cooldown words under the wheel collapsed; again when the game showed one
local function Under(P, J, w)
    for _, name in ipairs(UNDER) do
        local T = w.Text[name]
        if Ok(T) and T:GetVisibility() ~= COLLAPSED then P.Set(J, "Q/under/" .. name, T, "Visibility", COLLAPSED) end
    end
end

-- The spell name and the requirement text inside the ring, and the line under the wheel; wheels.lua calls it
-- while the wheel is open.
function M.Fit(P, J, w)
    Under(P, J, w)
    local m = w.Mid
    if not m then return end
    w.Want = w.Want or {}
    FitOne(P, J, w, "Q/SpellName", m.Name, NAME_ROOM, m.Box)
    FitOne(P, J, w, "Q/RequirementText", m.Text, TEXT_ROOM, nil, TEXT_MOST)
end

-- The small texts of the middle and the numbers of the rune cost in the HUD font; the spell name keeps the game's
-- title font. While the font is not found, FontAt is the time of the next try.
function M.Fonts(ctx, P, J, w, now)
    local m, font = w.Mid, ctx.Font()
    if m and font then
        for _, part in ipairs({ "NoCost", "Label", "Text" }) do
            if m[part] then P.Set(J, "Q/" .. part, m[part], "Font", font) end
        end
    end
    if font then
        for n, T in ipairs(w.Cost) do P.Set(J, "Q/cost" .. n, T, "Font", font) end
    end
    w.FontTries = (w.FontTries or 0) + 1
    w.FontAt = not font and w.FontTries < FONT_TRIES and now + FONT_AGAIN or false
end

-- The cooldown of each slot as a gold arc on the slot's ring: the game's small counter made big, only its timer
-- ring left to see. The game shows and hides the widget and fills the ring; this is written once.
local function Arc(P, J, w)
    local missing = 0
    for i in pairs(w.Slice) do
        local slice = Kid(w.W, "RadialSlice_" .. i)
        local cd = slice and Kid(slice, "CooldownWidget")
        local ring = cd and Kid(cd, "TimerRing")
        if ring then
            local key = "Q/" .. i .. "/Cooldown"
            P.Set(J, key, cd, "Pivot", CENTRE)
            P.Set(J, key, cd, "Scale", ARC.Scale)
            P.Set(J, key, cd, "Move", ARC.Move)
            for _, name in ipairs(ARC.Hide) do
                local part = Kid(cd, name)
                if part then P.Set(J, key .. name, part, "Opacity", 0) end
            end
            P.Set(J, key .. "TimerRing", ring, "Colour", ARC.Gold)
        else missing = missing + 1 end
    end
    return missing
end

-- Our look on what only Q has. Returns nil, or the names of the parts that were not found, for the log.
function M.Style(ctx, P, J, w, now)
    local gone = {}
    local m = Middle(w)
    if m then
        P.Set(J, "Q/SpellName", m.Name, "Scroll", false)
        P.Set(J, "Q/SpellName", m.Name, "Pivot", CENTRE)
        if Ok(m.Box) then P.Set(J, "Q/SpellNameBox", m.Box, "Padding", PAD.Name) end
        if m.TextBox then P.Set(J, "Q/RequirementBox", m.TextBox, "Padding", PAD.Requirement) end
        if m.Label then
            P.Set(J, "Q/Label", m.Label, "Pivot", CENTRE)
            P.Set(J, "Q/Label", m.Label, "Scale", { X = LABEL, Y = LABEL })
        else gone[#gone + 1] = "RequirementDescription" end
        if m.Text then P.Set(J, "Q/RequirementText", m.Text, "Pivot", CENTRE) else gone[#gone + 1] = "RequirementText" end
        if Ok(m.CostBox) then
            P.Set(J, "Q/CostBox", m.CostBox, "Pivot", CENTRE)
            local smaller = P.Set(J, "Q/CostBox", m.CostBox, "Scale", { X = COST_SCALE, Y = COST_SCALE })
            local moved = P.Set(J, "Q/CostBox", m.CostBox, "Move", COST_MOVE)
            if not m.NoCost then gone[#gone + 1] = "NoCostTextBlock"
            else   -- the "-" sits in CostBox: each of its counter writes follows the write it undoes
                local k = smaller and COST_SCALE or 1   -- the box's scale now; a child's move is in the box's scaled space
                if smaller then
                    P.Set(J, "Q/NoCost", m.NoCost, "Pivot", CENTRE)
                    P.Set(J, "Q/NoCost", m.NoCost, "Scale", { X = 1 / COST_SCALE, Y = 1 / COST_SCALE })
                end
                if moved then P.Set(J, "Q/NoCost", m.NoCost, "Move", { X = -COST_MOVE.X / k, Y = -COST_MOVE.Y / k }) end
            end
        else gone[#gone + 1] = "CostBox" end
    else gone[#gone + 1] = "SpellName" end
    w.FontTries, w.Want = 0, {}
    M.Fonts(ctx, P, J, w, now)
    M.Fit(P, J, w)
    local missing = Arc(P, J, w)
    if missing > 0 then gone[#gone + 1] = "the cooldown parts of " .. missing .. " slots" end
    return #gone > 0 and table.concat(gone, ", ") or nil
end

return M
