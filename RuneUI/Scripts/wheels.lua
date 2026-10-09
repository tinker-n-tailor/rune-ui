-- The three radial wheels (Q spells, R quick access, H emotes) in the HUD's look: each slot a ring, nothing behind
-- the rings, a solid ring in the middle with its texts in the HUD font. The F9 row "wheels" turns it on and off.
-- wheelparts.lua: the tables and the writes that can be put back. wheelspells.lua: what only Q has.
-- wheelmeters.lua: the widgets that the mod makes itself. wheelbooks.lua: the four spellbook diamonds in the header of Q.

local M = {}

local OPEN, COLLAPSED = 4, 1      -- ESlateVisibility
local SLOW, FAST = 0.5, 0.1       -- seconds between two looks: the wheels closed, the Q or the R wheel open
local WAIT = 10                   -- seconds a found wheel waits for the others before the search of its parts
local MAX_SWEEPS = 3              -- searches of every image in one world: each costs some tens of ms
local GAP = 5                     -- seconds between two such searches at least
local MAX_MARKS = 8                  -- the most spellbook marks kept from a search: four are used, more are a find to log
local WHITE = { R = 1, G = 1, B = 1, A = 1 }
local FULL = { SpecifiedColor = WHITE, ColorUseRule = 0 }

-- Wheels: key -> { Def, W, Full, Path, PanelPath, Panel, Switch, Slice, Slot, Part, Border, Text, Cost, Head, Marks, Hand, Styled }. J: the journal of
-- the writes (wheelparts.lua). On: our look is on the widgets. First: when the first wheel of this world was found.
-- Tex: the pictures of this world's wheels, each read from the disk once (wheelparts.lua's Tex).
-- old: the state that goes. The count and the time of its searches stay, so lost wheels bring no search on every step.
local function Fresh(old)
    return { Wheels = {}, J = nil, Tex = {}, On = false, Next = 0, First = nil, Sweeps = old and old.Sweeps or 0, LastSweep = old and old.LastSweep or -math.huge }
end
local S = Fresh()
local Logged, Linked = {}, false
local function Once(ctx, key, msg) if not Logged[key] then Logged[key] = true ctx.Log("wheels: " .. msg) end end

local Ok   -- wheelparts.lua's, taken on the first step
local function Cls(o) return o:GetClass():GetFName():ToString() end

-- One search of every image and border for the parts of the wheels in found, kept by name. The parts are no
-- variables of the wheel, so its full name at the start of theirs is the only link. For Q also the texts and the
-- spacers: the line under the wheel and the numbers of the rune cost. Last, the switcher of the panel of Q and H.
local function Sweep(P, found)
    local function Take(I, kind)
        if not I:IsValid() then return end
        local full = I:GetFullName()
        for _, w in ipairs(found) do
            local _, e = string.find(full, w.Path, 1, true)
            if e then
                local part, i, name = P.Part(string.sub(full, e + 1))
                if part == "slice" or part == "slot" then
                    if kind == "Part" then
                        local t = part == "slice" and w.Slice or w.Slot
                        t[i] = t[i] or {}
                        t[i][name] = I
                    end
                elseif part == "cost" then w.Cost[#w.Cost + 1] = I
                elseif part == "wheel" then w[kind][name] = I
                elseif part == "book" and kind == "Part" then
                    if #w.Marks < MAX_MARKS then w.Marks[#w.Marks + 1] = { W = I, Full = full, Name = name } end
                elseif part == "head" and kind == "Border" then w.Head[name] = I end
                return
            end
        end
    end
    local texts = false
    for _, w in ipairs(found) do texts = texts or w.Def.Spells end
    for _, c in ipairs({ { "Image", "Part" }, { "Border", "Border" }, texts and { "TextBlock", "Text" } or nil, texts and { "Spacer", "Text" } or nil }) do
        for _, I in pairs(FindAllOf(c[1]) or {}) do pcall(Take, I, c[2]) end
    end
    -- the switcher of the panel that holds Q and H: it tells which of the two is open
    for _, I in pairs(FindAllOf("WidgetSwitcher") or {}) do
        pcall(function()
            if not I:IsValid() then return end
            local full = I:GetFullName()
            for _, w in ipairs(found) do
                if w.PanelPath and P.IsSwitcher(full, w.PanelPath) then w.Switch, w.SwitchFrom = P.Hold(I), "the search of the parts" end
            end
        end)
    end
end

-- The wheels not found yet, through the finder. Its first answer for a class can be empty, so this runs on every
-- slow step until all are found or the searches of this world are used up. A wheel with no slot found is not
-- built yet: it is not taken, and a later search looks again.
local function Look(ctx, P, now)
    local fresh, have = {}, 0
    for _, d in ipairs(P.WHEELS) do
        if S.Wheels[d.Key] then have = have + 1 else
            local list, keys = ctx.Find(d.Class, d.Path)
            if Ok(list[1]) then
                local full = list[1]:GetFullName()   -- read now: Alive compares with it
                local path = string.match(full, "^%S+%s+(.*)$") or full
                fresh[#fresh + 1] = { Def = d, W = list[1], Full = full, Path = path, PanelPath = d.Page and P.PanelOf(path),
                    Slice = {}, Slot = {}, Part = {}, Border = {}, Text = {}, Cost = {}, Head = {}, Marks = {}, Hand = {} }
            end
        end
    end
    if #fresh == 0 then return false end
    -- Not in the step that first sees a wheel: at the start of a world that step holds the first build of the other
    -- parts too, and with this search it was 164 ms long (the perf line by longest run, 09-10-2026).
    if not S.First then S.First, S.Next = now, now + FAST return false end
    if have + #fresh < #P.WHEELS and now - S.First < WAIT then return false end
    if now - S.LastSweep < GAP then return false end
    S.Sweeps, S.LastSweep = S.Sweeps + 1, now
    local t0 = os.clock()
    Sweep(P, fresh)
    local found = {}
    for _, w in ipairs(fresh) do
        local n = 0
        for _ in pairs(w.Slice) do n = n + 1 end
        if n > 0 then S.Wheels[w.Def.Key] = w end
        found[#found + 1] = w.Def.Key .. " " .. n .. " slots"
    end
    ctx.Log(string.format("wheels: %s; parts searched in %.0f ms", table.concat(found, ", "), (os.clock() - t0) * 1000))
    return true
end

-- A picture from the Art folder, read once for the world; nil and one log line when it does not load. The caller
-- puts it on a brush at once: a texture that only Lua holds is freed by the engine.
local function Load(ctx, outer, file)
    local ok, tex = pcall(ctx.Parts.Tex, ctx, S.Tex, outer, file)
    if ok then return tex end
    Once(ctx, file, tostring(tex))
end

-- the sparks of one wheel (wheelmeters.lua); the first failure of a wheel is logged, a later try is silent
local function Sparks(ctx, w, now)
    if not ctx.Meters then return end
    local ok, err = pcall(ctx.Meters.Sparks, ctx, w, now)
    if not ok then Once(ctx, "sparks" .. w.Def.Key, w.Def.Key .. ": no sparks: " .. tostring(err)) end
end

-- the diamonds of the four spellbooks in the header of Q (wheelbooks.lua); the first failure is logged, a later one is silent
local function Books(ctx, w)
    if not ctx.Books then return end
    local ok, err = pcall(ctx.Books.Step, ctx, w)
    if not ok then Once(ctx, "books", "Q: no spellbook diamonds: " .. tostring(err)) end
end

-- Our look on one wheel. tex: what Load gave for each file in this run, so a file that is missing is asked for once.
local function Style(ctx, P, w)
    local d, J, pre, tex = w.Def, S.J, w.Def.Key .. "/", {}
    local function Tex(file)
        if tex[file] == nil then tex[file] = Load(ctx, w.W, file) or false end
        return tex[file]
    end
    for i, parts in pairs(w.Slice) do
        local key = pre .. i .. "/"
        for name, file in pairs(d.Slice) do
            if parts[name] and Tex(file) then P.Set(J, key .. name, parts[name], "Picture", Tex(file)) end
        end
        local B = parts.Background
        if B then
            P.Set(J, key .. "Background", B, "Colour", WHITE)
            if d.Full then P.Set(J, key .. "Background", B, "Tint", FULL) end
        end
        if d.Icon and parts.SliceIcon then P.Set(J, key .. "SliceIcon", parts.SliceIcon, "Scale", { X = d.Icon, Y = d.Icon }) end
    end
    -- the game draws the middle name above the ring's middle: d.Name moves it down by that many units
    local okN, mid = pcall(function() return d.Name and w.W[d.Name[1]] end)
    if okN and mid and mid:IsValid() then P.Set(J, pre .. "name", mid, "Move", { X = 0, Y = d.Name[2] }) end
    local okW, long = pcall(function() return d.Wrap and w.W[d.Wrap[1]] end)
    if okW and long and long:IsValid() then P.Set(J, pre .. "wrap", long, "Wrap", d.Wrap[2]) end
    for name, I in pairs(w.Part) do
        if name == "CenterBg" then
            if Tex(d.Centre) then P.Set(J, pre .. name, I, "Picture", Tex(d.Centre)) end
            if d.Solid then P.Set(J, pre .. name, I, "Enabled", true) end
        else P.Set(J, pre .. name, I, "Colour", 0) end
    end
    local box = d.Shade and w.Border.BottomDescriptionBorder
    if box and Tex(d.Shade) and P.Set(J, pre .. "shade", box, "BorderPicture", Tex(d.Shade)) then
        P.Set(J, pre .. "shade", box, "BorderColour", WHITE)
    end
    if w.Head.CommonBorder_0 then P.Set(J, pre .. "head", w.Head.CommonBorder_0, "BorderColour", 0) end
    for i, slot in pairs(w.Slot) do
        if slot.EquippedImage then P.Set(J, pre .. i .. "/EquippedImage", slot.EquippedImage, "Colour", 0) end
    end
    w.Styled = true
    if d.Spells and ctx.Spells then
        local okM, note = pcall(ctx.Spells.Style, ctx, P, J, w, os.clock())
        if note then Once(ctx, "spells", (okM and "Q: not found: " or "Q: its own parts failed: ") .. tostring(note)) end
    end
    Sparks(ctx, w, os.clock())
end

-- The dark square behind the item of one slot: its material scalars to 0, when the first reads another value. The
-- game writes them again and can give the slot a new material, so both are read from the slot on every look.
local function Square(P, key, item)
    local mid = item.Brush.ResourceObject
    if not (Ok(mid) and Cls(mid) == "MaterialInstanceDynamic") then return end
    if mid:K2_GetScalarParameterValue(FName(P.SQUARE[1])) == 0 then return end
    P.Keep(S.J, key, function()
        local was, full = {}, item:GetFullName()
        for n, name in ipairs(P.SQUARE) do was[n] = mid:K2_GetScalarParameterValue(FName(name)) end
        return function()
            local now = P.Same(item, full) and item.Brush.ResourceObject
            if not (Ok(now) and Cls(now) == "MaterialInstanceDynamic") then return end
            for n, name in ipairs(P.SQUARE) do now:SetScalarParameterValue(FName(name), was[n]) end
        end
    end)
    for _, name in ipairs(P.SQUARE) do mid:SetScalarParameterValue(FName(name), 0.0) end
end

-- One slot of the R wheel while it is open: the ring at full strength again if the game made it faint, the ring
-- of the item in hand, no dark square, and the durability meter (wheelmeters.lua). The ring's picture is loaded
-- only when the slot's state changes, with the slot's own image as its owner.
local function Slot(ctx, P, w, i)
    local key, slot, back = w.Def.Key .. "/" .. i .. "/", w.Slot[i] or {}, w.Slice[i].Background
    if Ok(back) then
        if back.Brush.TintColor.SpecifiedColor.A < 0.99 then P.Set(S.J, key .. "Background", back, "Tint", FULL) end
        if back.ColorAndOpacity.A < 0.99 then P.Set(S.J, key .. "Background", back, "Colour", WHITE) end
        local hand = Ok(slot.EquippedImage) and slot.EquippedImage:GetVisibility() ~= COLLAPSED or false
        if hand ~= (w.Hand[i] or false) then
            w.Hand[i] = hand   -- also when the picture does not load: no read from disk on every look
            local tex = Load(ctx, back, hand and w.Def.Hand or w.Def.Slice.Background)
            if tex then P.Set(S.J, key .. "Background", back, "Picture", tex) end
        end
    end
    if Ok(slot.ItemImage) then Square(P, key .. "square", slot.ItemImage) end
    if ctx.Meters then ctx.Meters.Durability(ctx, P, S.J, w, i) end
end

-- the R wheel while it is open; an error on one slot does not stop the others
local function Quick(ctx, P, w)
    for i in pairs(w.Slice) do
        local ok, err = pcall(Slot, ctx, P, w, i)
        if not ok then Once(ctx, "slot", "a slot of the R wheel failed: " .. tostring(err)) end
    end
end

-- The game's look back on every wheel, and our own widgets out of sight. The parts found stay, so the row on
-- needs no new search. remove: the handles are dropped after this, so our widgets go out of the game's for good.
-- A wheel that is gone gets no call: its widgets and ours on it went with it.
local function Restore(ctx, P, remove)
    if S.J then pcall(P.Restore, S.J) end
    S.J, S.On = nil, false
    for _, w in pairs(S.Wheels) do
        w.Styled, w.Hand, w.Want = false, {}, nil
        local ok, same = pcall(P.Same, w.W, w.Full)
        if ctx.Meters and ok and same then ctx.Meters.Hide(w, remove) end
        if ctx.Books and ok and same then pcall(ctx.Books.Hide, w, remove) end
    end
end

-- Q and H keep visibility 4 closed or open. Their panel is collapsed while both are closed, and the page of its
-- switcher says which wheel shows (Def.Page); it keeps its last value when the wheel closes. So a wheel is open when
-- its panel reads 4 and its switcher is on its page. The opacity of the panel fades in, so it is not read. Panel and
-- switcher are kept with their full names. One that went to another object is found again: the panel as the outer of
-- the wheel's tree, the switcher as a variable of the panel. A wheel that cannot be told is closed, and the log says so once.
local function Opened(ctx, P, w)
    local key = w.Def.Key
    if not P.Mine(w.Panel) then
        local ok, panel = pcall(function() return w.W:GetOuter():GetOuter() end)
        w.Panel = ok and w.PanelPath and Ok(panel) and string.match(panel:GetFullName(), "^%S+%s+(.*)$") == w.PanelPath and P.Hold(panel) or nil
        if not w.Panel then Once(ctx, "panel" .. key, key .. ": the panel of the wheel was not found, so the wheel counts as closed") return false end
    end
    if not P.Mine(w.Switch) then
        local sw = P.Kid(w.Panel.W, "WidgetSwitcher")
        w.Switch, w.SwitchFrom = sw and P.IsSwitcher(sw:GetFullName(), w.PanelPath) and P.Hold(sw) or nil, "the panel's variable"
        if not w.Switch then Once(ctx, "switch" .. key, key .. ": the switcher of the panel was not found, so the wheel counts as closed") return false end
    end
    if w.SwitchSaid ~= w.Switch then
        w.SwitchSaid = w.Switch
        ctx.Log("wheels: " .. key .. ": the switcher of the panel comes from " .. w.SwitchFrom)
    end
    return w.Panel.W:GetVisibility() == OPEN and w.Switch.W:GetActiveWidgetIndex() == w.Def.Page
end

-- A wheel whose widget is gone, or whose slot went to another object, takes every handle of its world with it.
local function Alive()
    for _, w in pairs(S.Wheels) do
        if not (w.W:IsValid() and w.W:GetFullName() == w.Full) then return false end
    end
    return true
end

-- A new world: every handle is dropped and nothing is called on the old widgets. A respawn keeps the widgets and
-- our look on them; it only gives the searches of the parts back. Nothing else clears their count.
function M.Forget(sameWorld)
    if sameWorld then S.Sweeps = 0 return end
    S, Logged = Fresh(), {}
end

function M.Tick(ctx)
    local now = os.clock()
    if now < S.Next then return end
    S.Next = now + SLOW
    local P = ctx.Parts
    if not P then return end   -- wheelparts.lua did not load: main.lua logged it
    if not Linked then
        Linked = true
        Ok = P.Ok
        -- each file alone: one that did not load (main.lua logged it) must not stop the Init of the other
        if ctx.Spells then ctx.Spells.Init(P) end
        if ctx.Meters then ctx.Meters.Init(P, function(key, msg) Once(ctx, key, msg) end) end
        if ctx.Books then ctx.Books.Init(P) end
    end
    if not ctx.On() then
        if S.On then
            Restore(ctx, P)
            ctx.Log("wheels: the game's look is back")
        end
        return
    end
    local okA, alive = pcall(Alive)
    if not (okA and alive) then
        -- a wheel that lives on must not keep our values: found again, they would be read as the game's
        Restore(ctx, P, true)
        S = Fresh(S)
        S.Next = now + SLOW
    end
    -- The search of the parts and the look of one wheel each take some tens of ms (10 pictures are decoded for the
    -- three wheels). All in one step was a hitch of 164 ms at the start of a world (09-10-2026), so a step does one
    -- of them and the next comes after FAST.
    local busy = false
    if S.Sweeps < MAX_SWEEPS then
        local okL, swept = pcall(Look, ctx, P, now)
        if not okL then Once(ctx, "look", "search failed: " .. tostring(swept)) end
        busy = okL and swept
    end
    S.J = S.J or P.Journal(ctx.Log)
    for _, w in pairs(S.Wheels) do
        if not w.Styled then
            if busy then S.Next = now + FAST else
                busy, S.On = true, true
                local okS, errS = pcall(Style, ctx, P, w)
                if not okS then w.Styled = true Once(ctx, "style" .. w.Def.Key, "not styled: " .. tostring(errS)) end
            end
        elseif w.FontAt and now >= w.FontAt then
            pcall(ctx.Spells.Fonts, ctx, P, S.J, w, now)
        elseif w.SparksAt and now >= w.SparksAt then
            Sparks(ctx, w, now)
        end
    end
    local R, Q = S.Wheels.R, S.Wheels.Q
    local okR, errR = pcall(function()
        if not (R and R.Styled and R.W:GetVisibility() == OPEN) then return end
        S.Next = now + FAST
        Quick(ctx, P, R)
    end)
    if not okR then Once(ctx, "quick", "R wheel step failed: " .. tostring(errR)) end
    -- the texts in the middle of Q change with the picked spell: they are fitted again while the wheel is open
    local okQ, errQ = pcall(function()
        if not (Q and Q.Styled and Opened(ctx, P, Q)) then return end
        S.Next = now + FAST
        Once(ctx, "qopen", "the Q wheel reads open")
        Books(ctx, Q)
        if ctx.Spells then ctx.Spells.Fit(P, S.J, Q) end
    end)
    if not okQ then Once(ctx, "fit", "Q wheel step failed: " .. tostring(errQ)) end
end

return M
