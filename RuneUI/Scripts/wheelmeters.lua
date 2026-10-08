-- The widgets that the mod makes itself on the wheels: the durability of an item as a thin half ring inside its
-- slot of the R wheel, and sparks around the middle ring of R and H as Q has them. wheels.lua calls this file.
-- main.lua loads it with pcall. How it works is in tools/notes/wheels-meters.md.

local M = {}

local METERS = true    -- false: no durability meter, the game's flat bar shows as before
local SPARKS = true    -- false: no sparks on the R and the H wheel

local COLLAPSED, UNTOUCHABLE, SHOWN = 1, 3, 4   -- ESlateVisibility; 3: seen, and the mouse goes through it
local CENTRE = { X = 0.5, Y = 0.5 }
local SIZE, CX, CY = 76, 70, 89        -- units: the meter's pictures, and the middle of the ring in an R slice
local LOW = 0.25                       -- under this share the meter is red
local GOLD = { R = 0.767, G = 0.479, B = 0.102, A = 1 }   -- #e3b85a, as linear light
local RED = { R = 0.693, G = 0.040, B = 0.022, A = 1 }    -- the red of the menu buttons' warning

local Ok, Kid, Same, Hold, Mine, Out, New, Add, Image, MakeSparks, SparkTry   -- wheelparts.lua's, given by wheels.lua before the first call
local Say   -- wheels.lua's log line that is said once for a world: function(key, message)
function M.Init(P, once)
    Ok, Kid, Same, Hold, Mine, Out, New, Add, Image, MakeSparks, SparkTry = P.Ok, P.Kid, P.Same, P.Hold, P.Mine, P.Out, P.New, P.Add, P.Image, P.Sparks, P.SparkTry
    Say = once
end

-- The meter of one slot: the faint track, and the fill in a box that shows only the lower half of the ring.
-- Turning the fill around the ring's middle moves its right end along the track. The slice is turned around the
-- wheel, so the whole meter is turned back by the slice's angle and stands upright.
local function Build(ctx, w, slice)
    local tree = slice.WidgetTree
    local ov = New(ctx, "Overlay", tree, "RU_WheelMeterStack")
    -- the two pictures are read from the disk once for the wheel: w.MeterTex keeps their textures
    Add(ov, Image(ctx, tree, "RU_WheelMeterTrack", "wheel_meter_track.png", SIZE, w.MeterTex), 2, 2)
    local fill = Image(ctx, tree, "RU_WheelMeterFill", "wheel_meter_fill.png", SIZE, w.MeterTex)
    local cv = New(ctx, "CanvasPanel", tree, "RU_WheelMeterCanvas")
    local s = cv:AddChildToCanvas(fill)
    s:SetAutoSize(false)
    s:SetSize({ X = SIZE, Y = SIZE })
    s:SetPosition({ X = 0, Y = -SIZE / 2 })
    local cut = New(ctx, "SizeBox", tree, "RU_WheelMeterCut")
    cut:SetWidthOverride(SIZE)
    cut:SetHeightOverride(SIZE / 2)
    cut:SetContent(cv)
    cut:SetClipping(1)   -- clip to its box
    Add(ov, cut, 2, 3)   -- centred, at the bottom
    local box = New(ctx, "SizeBox", tree, "RU_WheelMeter")
    box:SetWidthOverride(SIZE)
    box:SetHeightOverride(SIZE)
    box:SetContent(ov)
    box:SetVisibility(COLLAPSED)
    Add(tree.RootWidget, box, 1, 1, { Left = CX - SIZE / 2, Top = CY - SIZE / 2, Right = 0, Bottom = 0 })
    box:SetRenderTransformPivot(CENTRE)
    box:SetRenderTransformAngle(-slice.RenderTransform.Angle)
    return Hold(box), Hold(fill)
end

-- The game's parts of one slot, found again when one went to another object: its flat durability bar and the
-- progress bar that holds the value, each with its full name. Key names the bar in the journal, new for each find: a
-- new bar can have the name of the old one, and the journal keeps the first value of a key only.
local function Parts(w, i)
    local slice = Kid(w.W, "RadialSlice" .. i)
    local slot = slice and Kid(slice, "QuickAccessSlot")
    local bar = slot and Kid(slot, "DurabilityBar")
    local prog = bar and Kid(bar, "ProgressBar")
    if not prog then return false end
    w.Found = (w.Found or 0) + 1
    return { Slice = slice, SliceFull = slice:GetFullName(), Bar = bar, BarFull = bar:GetFullName(), Prog = prog, ProgFull = prog:GetFullName(),
        Key = "R/" .. i .. "/DurabilityBar#" .. w.Found }
end

-- One slot of the R wheel while it is open. The game's bar is unseen but alive: its visibility says whether the
-- item has a durability, and its value is ours. Written only when the value or the state changes.
function M.Durability(ctx, P, J, w, i)
    if not METERS then return end
    w.Meter, w.MeterTex, w.Had = w.Meter or {}, w.MeterTex or {}, w.Had or {}
    local m = w.Meter[i]
    -- The place of our meter, or of one of the game's parts of the slot, went to another object: it gets no write.
    -- Our meter goes, the game's bar shows again if it is still the game's, and the parts are found again from the
    -- live slot below; the build after that makes a new meter, and only that one hides the bar again.
    if m and not (Same(m.Slice, m.SliceFull) and Same(m.Bar, m.BarFull) and Same(m.Prog, m.ProgFull) and (not m.Box or Mine(m.Box) and Mine(m.Fill))) then
        Out(m.Box, true)
        if m.Hid and Same(m.Bar, m.BarFull) then P.Set(J, m.Key, m.Bar, "Opacity", m.Was) end
        m, w.Meter[i] = nil, nil
    end
    if m == nil then
        m = Parts(w, i)
        -- A slot whose parts were never found keeps false: no search on every look. A slot that had them and lost
        -- them keeps nil, so the next look tries again. That is a few property reads for the slot on each look.
        if m then w.Had[i] = true
        elseif not w.Had[i] then Say("meter" .. i, "R: slot " .. i .. " has no durability bar to find, so it gets no meter") end
        if m or not w.Had[i] then w.Meter[i] = m end
    end
    if not m then return end
    local key = m.Key
    local has = m.Bar:GetVisibility() ~= COLLAPSED
    if has and m.Box == nil then
        m.Box = false   -- a build that fails is not tried on every look
        m.Box, m.Fill = Build(ctx, w, m.Slice)
    end
    if not m.Box then return end
    -- only now that ours is there: a slot whose meter could not be made keeps the game's bar on show
    if not m.Hid then
        m.Was = m.Bar:GetRenderOpacity()
        m.Hid = P.Set(J, key, m.Bar, "Opacity", 0)
    end
    if has ~= (m.Shown or false) then
        m.Shown = has
        m.Box.W:SetVisibility(has and UNTOUCHABLE or COLLAPSED)
    end
    if not has then return end
    local v = math.max(0, math.min(1, m.Prog.Percent))
    if math.abs(v - (m.Value or -1)) < 0.004 then return end
    m.Value = v
    m.Fill.W:SetRenderTransformAngle((1 - v) * 180)
    if (v < LOW) ~= m.Low then
        m.Low = v < LOW
        m.Fill.W:SetColorAndOpacity(m.Low and RED or GOLD)
    end
end

-- Sparks around the middle ring, made once for a wheel and scaled to its ring; Def.Sparks is that scale. They go
-- into the overlay that holds the middle ring, over it (wheelparts.lua makes them). Two sparks or none. While something they need is not there
-- yet, SparksAt is the time of the next try, and wheels.lua calls again then. A call before that time makes no try,
-- so the tries of SparkTry in wheelparts.lua are all there are: a row on and off does not use them up.
function M.Sparks(ctx, w, now)
    local k = SPARKS and w.Def.Sparks
    if not k then return end
    if w.Sparks then
        local live = true
        for _, N in ipairs(w.Sparks) do live = live and Mine(N) end
        if live then
            for _, N in ipairs(w.Sparks) do N.W:SetVisibility(SHOWN) end
            return
        end
        -- the place of one went to another object: the pair goes, and a new one is made now
        for _, N in ipairs(w.Sparks) do Out(N, true) end
        w.Sparks, w.SparkTries, w.SparksAt = nil, nil, nil
    end
    if not SparkTry(w, now) then return end
    local centre = w.Part.CenterBg
    if not Ok(centre) then error("no middle ring") end
    w.Sparks, w.SparksAt = MakeSparks(ctx, centre:GetOuter(), centre:GetParent(), k, SHOWN, "RU_WheelSparks"), false
end

-- Everything of ours on one wheel that still lives. remove false: out of sight, as the row is off; the game's bar
-- gets its opacity back from the journal, so it is taken again on the next look. remove true: out of the game's
-- widgets for good, as the wheel's handles are dropped and ours would be made a second time.
function M.Hide(w, remove)
    for _, m in pairs(w.Meter or {}) do
        if m then
            Out(m.Box, remove)
            m.Shown, m.Hid = false, false
        end
    end
    for _, N in ipairs(w.Sparks or {}) do Out(N, remove) end
end

return M
