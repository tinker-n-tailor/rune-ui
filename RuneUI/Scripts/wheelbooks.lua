-- The four diamonds in the header of the Q wheel, one for each spellbook, in a row under the thin line below the
-- name of the book: the book in use is a bigger gold diamond, the other three are small and dark. wheels.lua calls
-- this file. main.lua loads it with pcall. How it works is in tools/notes/wheels-books.md.

local M = {}

local BOOKS = true    -- false: no diamonds in the header

local COLLAPSED, HIDDEN, UNTOUCHABLE = 1, 2, 3   -- ESlateVisibility; 3: seen, and the mouse goes through it
local FILES = { On = "wheel_book_on.png", Off = "wheel_book_off.png" }   -- the book in use, and the others
local COUNT = 4          -- spellbooks
local GAP, BOX = 22, 16  -- units: from the middle of one diamond to the next, and the canvas of each picture
-- The row sits in the header's overlay, and its render translation moves it down. At 78 units its middle is about
-- 14 units under the header's gold line (seen in the game, 07-10-2026). ROW_MOVE is the value to tune.
local ROW_ALIGN = { 2, 2 }              -- EHorizontalAlignment, EVerticalAlignment: centre, centre
local ROW_MOVE = { X = 0, Y = 78 }      -- units: down from the middle of the header

local Ok, Same, Hold, Mine, Out, New, Add, Image   -- wheelparts.lua's, given by wheels.lua before the first call
function M.Init(P) Ok, Same, Hold, Mine, Out, New, Add, Image = P.Ok, P.Same, P.Hold, P.Mine, P.Out, P.New, P.Add, P.Image end

-- The number at the end of a button's name; wheelparts.lua takes only names that end in one. Book 1 has the highest
-- number, book 4 the lowest (probe of 07-10-2026).
local function Suffix(name) return tonumber(string.match(name, "(%d+)$")) end

-- A line for the log, once for a wheel: its search and its marks do not change within a world.
local function Say(ctx, w, key, msg)
    w.Said = w.Said or {}
    if w.Said[key] then return end
    w.Said[key] = true
    ctx.Log("wheels: Q: " .. msg)
end

-- The row, made once for a wheel: a diamond in use and a diamond not in use at each of the four places, one of
-- the two seen. The marks are the Foreground images of the header's buttons (wheelparts.lua Part), ordered by the
-- number in the name of their button, highest first: that is book 1. The row goes into the overlay that holds the
-- header bar, over it.
local function Build(ctx, w)
    local bar = w.Head.CommonBorder_0
    if not Ok(bar) then error("no header bar to take the header's overlay from", 0) end
    local tree, parent = bar:GetOuter(), bar:GetParent()
    if not Ok(tree) then error("the header bar has no widget tree to hold the row", 0) end
    if not (Ok(parent) and parent:GetClass():GetFName():ToString() == "Overlay") then error("the header bar is not in an overlay", 0) end
    local marks, names = {}, {}
    for n, m in ipairs(w.Marks) do marks[n] = m end
    table.sort(marks, function(a, b)
        local x, y = Suffix(a.Name), Suffix(b.Name)
        if x ~= y then return x > y end
        return a.Full < b.Full
    end)
    for n, m in ipairs(marks) do names[n] = m.Name end
    local list = table.concat(names, ", ")
    if #marks ~= COUNT then error(#marks .. " spellbook marks found, not " .. COUNT .. ": " .. list, 0) end
    for _, m in ipairs(marks) do
        if not Same(m.W, m.Full) then error("a spellbook mark is another object now: " .. m.Name, 0) end
    end
    local row, tex, b = New(ctx, "Overlay", tree, "RU_BookRow"), {}, { Marks = marks, On = {}, Off = {} }
    for k = 1, COUNT do
        local pad = { Left = (k - 1) * GAP, Top = 0, Right = 0, Bottom = 0 }
        for _, set in ipairs({ { b.Off, "Off" }, { b.On, "On" } }) do
            local img = Image(ctx, tree, "RU_Book" .. set[2], FILES[set[2]], BOX, tex)
            img:SetVisibility(COLLAPSED)
            Add(row, img, 1, 2, pad)
            set[1][k] = Hold(img)
        end
    end
    local box = New(ctx, "SizeBox", tree, "RU_BookRowBox")
    box:SetWidthOverride((COUNT - 1) * GAP + BOX)
    box:SetHeightOverride(BOX)
    box:SetContent(row)
    box:SetVisibility(COLLAPSED)
    box:SetRenderTranslation(ROW_MOVE)
    Add(parent, box, ROW_ALIGN[1], ROW_ALIGN[2])
    b.Row = Hold(box)
    Say(ctx, w, "order", COUNT .. " spellbook marks, in the order of their names, highest number first: " .. list)
    return b
end

-- The row and its eight diamonds are all still ours.
local function Alive(b)
    if not Mine(b.Row) then return false end
    for k = 1, COUNT do
        if not (Mine(b.On[k]) and Mine(b.Off[k])) then return false end
    end
    return true
end

-- The book in use: the first mark that shows, and how many show. false: none shows. nil: a mark is no longer the
-- game's widget, so nothing is read from it.
local function InUse(marks)
    local use, shown = false, 0
    for k, m in ipairs(marks) do
        if not Same(m.W, m.Full) then return nil end
        local v = m.W:GetVisibility()
        if v ~= COLLAPSED and v ~= HIDDEN then
            shown = shown + 1
            if use == false then use = k end
        end
    end
    return use, shown
end

-- One look while Q is open. Builds the row on the first look, then writes only when the book in use changes.
-- A build that fails is not tried again for the wheel, and the error goes to wheels.lua's log. A mark that went to
-- another object takes the row with it: the next look builds it from the same marks, which fails the same way.
function M.Step(ctx, w)
    if not BOOKS or w.Books == false then return end
    local b = w.Books
    if b and not Alive(b) then
        -- the place of one of ours went to another object: it gets no write, the rest goes, a new row is made
        Out(b.Row, true)
        b = nil
    end
    if not b then
        w.Books = false
        b = Build(ctx, w)
        w.Books = b
    end
    local use, shown = InUse(b.Marks)
    if use == nil then
        Out(b.Row, true)
        w.Books = nil
        error("a spellbook mark is another object now, the row is taken out", 0)
    end
    -- The book in use has a mark with visibility 0; the others have 1 or 2 (probe of 07-10-2026). Any other count is logged.
    if shown ~= 1 then Say(ctx, w, "count", shown .. " spellbook marks show") end
    if shown == 1 then Say(ctx, w, "first", "the spellbook mark " .. use .. " of " .. COUNT .. " shows, " .. b.Marks[use].Name) end
    if use == b.Use then return end   -- b.Use is nil before the first write and while the row is off
    b.Row.W:SetVisibility(UNTOUCHABLE)
    for k = 1, COUNT do
        b.On[k].W:SetVisibility(k == use and UNTOUCHABLE or COLLAPSED)
        b.Off[k].W:SetVisibility(k == use and COLLAPSED or UNTOUCHABLE)
    end
    b.Use = use   -- only after every write went through: a failed one is tried again on the next look
end

-- The row out of sight, as the F9 row is off; the next look shows it again. remove: out of the game's widgets for
-- good, as the wheel's handles are dropped and a new row would be made.
function M.Hide(w, remove)
    local b = w.Books
    if not b then return end
    Out(b.Row, remove)
    b.Use = nil
    if remove then w.Books = nil end
end

return M
