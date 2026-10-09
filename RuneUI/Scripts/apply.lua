-- Writing the layout into the game's widgets: the move, the size and the pivot of each element, its opacity (the
-- editor's dimming, a hidden element, the F9 opacity, the immersive mode's fade), and the tool bar's place while the
-- bag is open. main.lua loads this file, gives it its own names (Init) and the parts loaded later (Attach),
-- calls All on every step and Forget when a world or a round ends. tools/test-opacity.js drives the opacity memory
-- and tools/test-bag.js the bag rule, without the game.

local M = {}

-- From main.lua (Init): the element list, layout.lua and the log.
local Elements, Layout, ById, LocalTransform, Log
function M.Init(ctx)
    Elements, Layout, Log = ctx.Elements, ctx.Layout, ctx.Log
    ById, LocalTransform = Layout.ById, Layout.LocalTransform
end
-- The parts read here. main.lua loads them after this file and gives them here, before the timer starts.
local Immersive, Survival
function M.Attach(P) Immersive, Survival = P.Immersive, P.Survival end

-- Keyed by the widget's full name: every rescan gives new Lua handles for the same widgets.
-- Written: the opacity the editor or the immersive mode last wrote to a widget (nil: the widget is the game's).
-- OrigOpacity: the game's opacity of it before our first write, kept for the world. The game fades its
-- notices by its own animation of this opacity, so a value read later may be from the middle of a fade: the picked-up
-- items stayed pale when it was read again at every write (seen in the game, 05-10-2026). The one notice whose fade ends at the value
-- we write, the level up notice, has Idle in its element, and that comes back instead (RestoreOpacity).
local OrigOpacity = {}
local Written = {}
local SAME = 0.002   -- an opacity reads back as a 32-bit number

local function ReadOpacity(W) return W:GetRenderOpacity() end   -- named, so a pcall of it makes no closure

-- True when the widget does not hold `value` (read back as a 32-bit number). The game writes its own opacity over ours
-- (a notice's fade, a prompt that fades in), so a held value is read back, and written only when it is not there: a
-- write makes the engine draw the widget again. A write on a timer would show a hidden notice for a moment (seen for
-- the level up notice, which the game fades from 0 to 1 and back). When the read runs: see LOOK.
local function Differs(W, value) return math.abs(W:GetRenderOpacity() - value) > SAME end

-- k: the widget's full name, read once per scan (FindAll). Written only when it is not what we wrote last, or the game
-- changed it since. Returns true when the game had written over the value that we hold.
local function SetOpacity(W, k, value)
    if OrigOpacity[k] == nil then
        local ok, o = pcall(ReadOpacity, W)
        OrigOpacity[k] = ok and o or 1.0
    end
    local held = Written[k] == value
    if held and not Differs(W, value) then return false end
    W:SetRenderOpacity(value)
    Written[k] = value
    return held
end

-- Back to the game's opacity, but only a widget that still holds what we wrote: when the game has written since, its
-- own value stands (a notice that is still fading). idle: the element's own word for what the game leaves it at when
-- nothing shows (E.Idle). The first opacity read of the notice can be a point of its fade, or the designer's sample that
-- sits at 1 in a fresh world, so the level up notice does not use it.
local function RestoreOpacity(W, k, idle)
    local w = Written[k]
    if w == nil then return end
    Written[k] = nil
    if math.abs(W:GetRenderOpacity() - w) <= SAME then W:SetRenderOpacity(idle or OrigOpacity[k]) end
end

-- The F9 opacity. A user widget gets it as its colour, which multiplies with the render opacity: the
-- game's own fades (render opacity) and the editor's blinking still work on top of it. Other widgets (the ammo
-- box, the avatar) have no such colour and take it as render opacity. An element inside another one would
-- also take its parent's opacity; it gets its own divided by the parent's, so the two do not multiply (a child
-- cannot be more solid than its parent).
local IsUW, Tint = {}, {}   -- by the widget's full name: user widget or not, and the colour's alpha last set
local UWClass = nil
local function TestUserWidget(W)
    if not (UWClass and UWClass:IsValid()) then UWClass = StaticFindObject("/Script/UMG.UserWidget") end
    return W:IsA(UWClass)
end
local function IsUserWidget(W, k)
    local v = IsUW[k]
    if v == nil then
        local ok, is = pcall(TestUserWidget, W)
        v = ok and is == true
        IsUW[k] = v
    end
    return v
end
-- the colour's write, named for the same reason as ReadOpacity; the table is what the call needs
local function SetTint(W, a) W:SetColorAndOpacity({ R = 1, G = 1, B = 1, A = a }) end
local function OwnOpacity(E)
    local P = E.Inside and ById(E.Inside)
    if not P then return E.Opacity end
    return math.min(1.0, E.Opacity / P.Opacity)
end

-- The parts of a Parts element, found once per widget (E.PartsW, by the widget's full name). The legend's: every
-- page of its switcher but the world page, and the world page's prompt list (widget dump, 29-09-2026).
local function CollectParts(W, parts)
    local sw = Survival.Find(W, "Switcher")
    for i = 0, sw:GetChildrenCount() - 1 do
        local page = sw:GetChildAt(i)
        if page:GetFName():ToString() == "InputLegendWidgetWorld" then page = Survival.Find(page, "SizeBox_0") end
        if page then parts[#parts + 1] = page end
    end
end
local function PartsOf(E, W, k)
    local parts = E.PartsW[k]
    if parts then return parts end
    parts = {}
    local ok, err = pcall(CollectParts, W, parts)
    if ok and #parts > 0 then E.PartsW[k] = parts   -- none yet (a HUD still being built): tried again next step
    elseif not E.PartsLogged then E.PartsLogged = true Log(E.Id .. ": parts not found, hidden whole: " .. tostring(err)) end
    return parts
end

local Unclipped = {}
-- The pieces of ApplyOne that run in a pcall. Each is a named function that takes what it needs: a function made inside
-- the step is garbage at every run.
local function Unclip(W)
    local P = W
    for _ = 1, 3 do
        if not (P and P:IsValid()) then break end
        P:SetClipping(0)   -- inherit: do not cut children at this box's edge
        P = P:GetParent()
    end
end
local function PlaceKeepFull(W, E, x, y, scale)
    local px, py = Layout.Pivot(E)   -- the element's own pivot: the child fills the same box
    for i = 0, W:GetChildrenCount() - 1 do
        local c = W:GetChildAt(i)
        if c:GetFName():ToString() == E.KeepFull then
            c:SetRenderTransformPivot({ X = px, Y = py })
            c:SetRenderScale({ X = 1 / scale, Y = 1 / scale })
            c:SetRenderTranslation({ X = -x / scale, Y = -y / scale })
        end
    end
end
-- A part of a Parts element held at o. Read first, written only when it is not at o (see Differs): true then.
local function HoldPart(P, o)
    if P:IsValid() and Differs(P, o) then P:SetRenderOpacity(o) return true end
    return false
end
local function RedrawAt(W, E, L)
    local op = W:GetRenderOpacity()
    if op > 0 and op ~= L.Drawn then
        local R = W[E.Redraw]
        if R and R:IsValid() then R:RequestRender() end
    end
    L.Drawn = op
end

-- Every call into the engine makes garbage, a read too (about 100 bytes; 43 widgets with two calls each at every step
-- were 7 MB a minute, 09-10-2026). So a step whose values are the ones of the step before calls nothing for a widget,
-- not even IsValid. A value that is held against the game (a hidden element, a fade, hidden parts) is read back every
-- LOOK seconds. The first time the game is found to have written over one, the element is read at every step from
-- then on (E.Fought, for the whole session): its first fade can show for LOOK seconds, no later one does.
-- A scan step (force) does not count: it can bring a new widget under an old name, which holds the game's value.
local LOOK = 0.25
local HELD, EVERY = 1, 2   -- L.Watch: the widget needs a look at the LOOK rate, or at every step
local function Fought(E)
    if E.Fought then return end
    E.Fought = true
    Log(E.Id .. ": the game writes its opacity over ours, so it is read at every step")
end

-- EditMode, MapMode: the editor (F9) or the map settings (F8) are open, as ApplyAll got them for this step.
-- force: write the move, size and pivot even when they are the values last written. Otherwise they are written
-- only when they change: every step wrote three calls per widget (about 80 calls a step, 30-09-2026). Every scan
-- forces them, as the bars' colours are set again on every scan in case the game set them back.
-- look: this step reads the held values back (see LOOK).
local function ApplyOne(W, k, x, y, scale, E, isSelected, force, EditMode, MapMode, look)
    local map = E.Custom == "map"
    -- the immersive mode's share, exactly 1 when shown; RuneMap takes it in its own opacity (see MapCtx)
    local imm = (Immersive and not map) and Immersive.Factor(E) or 1.0
    local op = map and 1.0 or OwnOpacity(E)
    local px, py
    if E.Full and E.Center then px, py = Layout.Pivot(E) end
    local L = E.Last[k]
    if L and not force and L.X == x and L.Y == y and L.S == scale and L.PX == px and L.PY == py and L.Vis == E.Visible
        and L.Op == op and L.Imm == imm and L.Edit == EditMode and L.Map == MapMode and L.Sel == isSelected
        and (not L.Watch or (L.Watch == HELD and not look and not E.Fought)) then return end
    if not (W and W:IsValid()) then return end
    if E.NoClip then
        if not Unclipped[k] then
            Unclipped[k] = true
            pcall(Unclip, W)
        end
    end
    if not L then L = {} E.Last[k] = L end
    local wasSolid = L.Solid   -- the step before held the widget solid (E.Opaque), so a faded one is the game's doing
    L.Vis, L.Op, L.Imm, L.Edit, L.Map, L.Sel, L.Watch, L.Solid = E.Visible, op, imm, EditMode, MapMode, isSelected, nil, nil
    if px then
        if force or L.PX ~= px or L.PY ~= py then
            W:SetRenderTransformPivot({ X = px, Y = py })
            L.PX, L.PY = px, py
        end
    end
    local moved = force or L.X ~= x or L.Y ~= y or L.S ~= scale
    if force or L.X ~= x or L.Y ~= y then W:SetRenderTranslation({ X = x, Y = y }) L.X, L.Y = x, y end
    if force or L.S ~= scale then W:SetRenderScale({ X = scale, Y = scale }) L.S = scale end
    -- KeepFull: a child that fills the element and must still fill the screen. It gets the inverse of the element's
    -- move and size, about the same middle: the element maps p to c + s*(p - c) + t, the child q to c + (q - c)/s - t/s.
    if E.KeepFull and moved then pcall(PlaceKeepFull, W, E, x, y, scale) end
    -- fade: the share of the opacity that goes into the render opacity. RuneMap sets its own (runemap.lua): its
    -- gold rings need it too.
    local fade = 1.0
    if not map then
        if not IsUserWidget(W, k) then
            fade = op
        elseif (Tint[k] or 1.0) ~= op then
            pcall(SetTint, W, op)
            Tint[k] = op
        end
    end
    -- An element with Parts is hidden part by part: the widget itself stays shown, so what lives inside it and is
    -- an element of its own (the menu buttons in the legend) can still show. Its parts are found once per widget;
    -- none found (no survival.lua, a changed game): the whole widget hides as before.
    local parts = E.Parts and PartsOf(E, W, k)
    if parts and #parts == 0 then L.Watch = HELD end   -- a HUD still being built: PartsOf tries again at the next look
    local shown = E.Visible or (parts and #parts > 0)
    if shown and parts and #parts > 0 then
        local o = E.Visible and 1.0 or 0.0
        if EditMode then   -- the editor's dimming goes on the parts; the widget stays whole for what lives inside it
            if isSelected then o = E.Visible and 1.0 or 0.6 else o = E.Visible and 0.3 or 0.1 end
        end
        -- while hidden, each part is looked at and written only if it is not at o: the game may fade a prompt back
        -- in (HoldPart). Shown, a part is written once, when o changes back to 1.
        if o < 1 or E.PartsOp[k] ~= o then
            local held = E.PartsOp[k] == o
            for _, P in ipairs(parts) do
                local okP, wrote = pcall(HoldPart, P, o)
                if okP and wrote and held and not force then Fought(E) end
            end
            E.PartsOp[k] = o
            if o < 1 then L.Watch = HELD end
        end
    end
    local hold   -- the opacity that the widget is held at; nil: the game's own stands
    if EditMode and parts and #parts > 0 then
        hold = 1.0
    elseif EditMode then
        if isSelected then
            -- solid, the gold corners round it pulse instead; dim when hidden
            hold = shown and fade or 0.6
        else
            hold = shown and 0.3 * fade or 0.1
        end
    elseif not shown and not (MapMode and map) then   -- F8 shows a hidden map
        hold = 0.0
    elseif E.Opaque then
        -- the dial looked faded; keep it fully solid
        if Differs(W, fade) then
            W:SetRenderOpacity(fade)
            if wasSolid and not force then Fought(E) end
        end
        Written[k] = nil   -- the editor's dimming is over: the solid value is the one that stands
        L.Solid, L.Watch = true, HELD
    elseif fade * imm < 1.0 then
        hold = fade * imm
    elseif next(Written) ~= nil then
        RestoreOpacity(W, k, E.Idle)   -- leave the game's own fading alone when the element is shown
    end
    if hold then
        if SetOpacity(W, k, hold) and not force then Fought(E) end
        L.Watch = HELD
    end
    -- the part drawn on request (E.Redraw) is asked to draw again at every opacity the element has while it is seen:
    -- when it comes back, and at each step of a fade. The game fades it too, so its opacity is read at every step.
    if E.Redraw then
        pcall(RedrawAt, W, E, L)
        L.Watch = EVERY
    end
end

-- The bar in the bag. The game's tool bar is the top row of the bag's panel, and a gamepad goes from slot to slot by
-- their places on the screen. With the bar moved away from the panel, a gamepad finds no way between the bar and the
-- bag (probes of 03-10-2026), and a mouse drags each item across the whole screen. So the bar sits at the game's place
-- while the bag is open, with any input.
-- Open: the bag's tab row, next to the bar in the same box, is seen. It is hidden (2) from the entry into a world
-- until the bag was open once, seen while the bag is open (4 with a mouse, 3 with a gamepad) and collapsed (1) after
-- that; the tool wheel and a change of the input leave it alone (probes of 06-10-2026, with a mouse and a gamepad).
local Bag = { Tabs = nil, Open = false }
local function BagOpen()
    local bar = ById("toolbar").Instances[1]
    if not (bar and bar:IsValid()) then Bag.Tabs = nil return false end
    local T = Bag.Tabs
    if not (T and T:IsValid()) then
        T = nil
        local box = bar:GetParent()
        if not box:IsValid() then Bag.Tabs = nil return false end
        for i = 0, box:GetChildrenCount() - 1 do
            local c = box:GetChildAt(i)
            if c:IsValid() and c:GetFName():ToString() == "TabGroupOverlay" then T = c break end
        end
        if not T then return false end
        Bag.Tabs = T
    end
    local v = T:GetVisibility()
    return v ~= 1 and v ~= 2
end
-- A gamepad is the input in use (the game's input subsystem: 0 mouse and keyboard, 1 gamepad, 2 touch).
local Pad = { Input = nil, At = 0 }
local function PadInUse()
    local S = Pad.Input
    if not (S and S:IsValid()) then
        if os.clock() < Pad.At then return false end
        Pad.At = os.clock() + 5   -- none found: the search walks every object, so not at every call
        S = nil
        for _, o in pairs(FindAllOf("CommonInputSubsystem") or {}) do
            if o:IsValid() and not string.find(o:GetFullName(), "Default__", 1, true) then S = o break end
        end
        Pad.Input = S
    end
    return S ~= nil and S:GetCurrentInputType() == 1
end

-- EditMode, MapMode, Selected: the editor's state at this step. They are main.lua's own values, which the keys write on
-- UE4SS's thread, so they come as plain values and are not read from a table here.
local NextLook = 0
local ApplyLogged = {}   -- by element id: its first error is logged, the others are not
local function ApplyAll(force, EditMode, MapMode, Selected)
    local now = os.clock()
    local look = now >= NextLook
    if look then NextLook = now + LOOK end
    if now >= (Bag.Next or 0) then   -- ten looks a second are enough: the bar moves within a blink of the bag
        Bag.Next = now + 0.1
        local okBag, open = pcall(BagOpen)
        Bag.Open = okBag and open or false
    end
    for i, E in ipairs(Elements) do
        -- with the group "notify" picked, the notices inside it are solid, not dimmed: its preview shows them all
        local sel = EditMode and (i == Selected or (E.Inside == "notify" and Elements[Selected].Id == "notify"))
        local lx, ly, ls = LocalTransform(E)
        if Bag.Open and E.Id == "toolbar" and not EditMode then lx, ly, ls = 0, 0, 1 end   -- the editor shows the saved place
        for n, W in ipairs(E.Instances) do
            -- one widget that throws must not stop the elements after it
            local ok, err = pcall(ApplyOne, W, E.Keys[n], lx, ly, ls, E, sel, force, EditMode, MapMode, look)
            if not ok and not ApplyLogged[E.Id] then ApplyLogged[E.Id] = true Log(E.Id .. ": apply failed: " .. tostring(err)) end
        end
    end
end

-- A new round (a new world, or a player restart in a world that still stands: sameWorld). Called by main.lua's ForgetWorld.
function M.Forget(sameWorld)
    Bag.Tabs, Pad.Input, Pad.At = nil, nil, 0
    Tint = {}   -- a HUD made again may reuse a name: set the opacity colour again, it costs one call per widget
    if not sameWorld then
        -- these remember widgets by full name; the old world's widgets are gone
        OrigOpacity, Written, Unclipped, IsUW = {}, {}, {}, {}
    end
end

M.All, M.PadInUse = ApplyAll, PadInUse
return M
