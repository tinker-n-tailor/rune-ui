-- The compass: a gold line and a gold middle mark, always while the game's compass is shown, and the map's marks.
-- The gold line (goldline.lua) sits on the strip's white line. The letters stay white: they are part of the strip's picture.
-- The marks show while RuneMap is not on screen, for the groups that the F8 map settings switch on, in the map's
-- shapes: creatures (enemy red diamond, calm green diamond), ore, herbs, essence and rare trees.
-- nearby.lua finds the things and decides what each one is.
-- With the setting "In immersive mode" at Compass, this is the immersive mode; with the map turned off in F8 it is always.
-- A mark sits at the bearing of its thing, at the scale of the game's own marks, and fades out at the edge.
-- Far things are smaller and dimmer. The widgets are in the compass's own widget tree, so they fade, hide and move with it.
-- A texture that only Lua holds is freed by the engine, and the next touch crashes the game: each picture sits in a
-- hidden Image of the compass, next to the pool of marks.
-- Motion: the main loop runs about 16 times a second, too few for a smooth turn. While marks are wanted and a thing
-- is near, a chain of delayed calls on the game thread (chain.lua) paints about every frame, as xp.lua does for a level up.
-- The chain also runs while every thing is behind you: a mark must come in at the edge with no delay when you turn.
-- main.lua loads this file with pcall, so an error here leaves the rest of the mod running.

local M = {}

local UNITS = 5.33         -- compass units for one degree: the scale of the game's own marks (measured, 04-10-2026)
local EDGE, FADE = 300, 40 -- a mark past 300 units from the middle is not shown; it fades out over the last 40
local SIZE, SMALL = 34, 0.6   -- a near mark is 34 units, a far one 0.6 of that
local DIM, FAR = 0.5, 6000    -- a far mark is half as solid; "far" is 60 m
local DOWN = -18           -- the row of the game's lower marks
local POOL = 40            -- marks at most on show
local LINE_W, LINE_H, LINE_Y, LINE_TOP = 620, 22, -11.5, 21   -- the gold line on the strip's white line
local GOLD = { R = 1.0, G = 0.638, B = 0.168, A = 1.0 }       -- the pick-up count's gold (pickups.lua)
local STAMP = tostring(os.time())   -- in each name: a restart of the mod in the same world starts the counters of ctx.G again
local ART = (RUNEUI_DIR or "ue4ss/Mods/RuneUI/") .. "Art/"
-- the map's shapes without their dark outline: on the fine compass the outline was too heavy (in game, 04-10-2026)
local FILES = { Enemy = "compass_enemy.png", Calm = "compass_neutral.png", Ore = "compass_ore.png",
    Herbs = "compass_herb.png", Essence = "compass_essence.png", Trees = "compass_tree.png" }
local ORDER = { "Enemy", "Calm", "Ore", "Herbs", "Essence", "Trees" }   -- the groups, in a fixed order
local FAST = 8                  -- ms between two calls of the chain
local ALIVE = 0.1                -- seconds: a chain that called this lately paints; the step does not paint again
local GONE = "the marks are gone from the compass"   -- the error for a widget that the game freed
local CREATURES_EVERY, RESOURCES_EVERY = 2, 10   -- seconds, as on the map: ore and herbs stand still, and a scan costs a few ms

---------------------------------------------------------------- what to show, without the game (tools/test-compass.js)

-- Round x to a number of steps in each unit (10: a tenth), so equal values are equal numbers
local function Round(x, steps) return math.floor(x * steps + 0.5) / steps end

-- The offset of a thing in compass units: its bearing from the player (dx, dy: the thing minus the player, in game
-- units), minus the camera's yaw, wrapped to -180..180 degrees, times the scale. North is -Y, as the game has it.
function M.Offset(dx, dy, yaw)
    return ((math.deg(math.atan(dy, dx)) - yaw + 540) % 360 - 180) * UNITS
end

-- How a thing shows: its offset, its size and its opacity; nil past the edge. Rounded, so a tiny change is not written.
function M.Look(dx, dy, yaw)
    local px = M.Offset(dx, dy, yaw)
    if math.abs(px) >= EDGE then return nil end
    local far = math.min(1, math.sqrt(dx * dx + dy * dy) / FAR)
    local size = SIZE * (1 - (1 - SMALL) * far)
    local opacity = (1 - (1 - DIM) * far) * math.min(1, (EDGE - math.abs(px)) / FADE)
    return Round(px, 10), Round(size, 10), Round(opacity, 100)
end

-- The groups the map settings switch on: set is RuneMap's settings, creatures the editor's switch for the creatures.
-- "Creatures" has three values: Off, Enemies only (set.Neutral false) and All.
function M.Groups(set, creatures)
    return { Enemy = creatures, Calm = creatures and set.Neutral == true, Ore = set.Ore == true, Herbs = set.Herbs == true,
        Essence = set.Essence == true, Trees = set.Trees == true }
end

-- The marks show while the compass is shown, the map is not, and a group is on.
function M.MarksOn(compassShown, mapShown, groups)
    if not compassShown or mapShown then return false end
    for _, on in pairs(groups) do if on then return true end end
    return false
end

-- The chain of calls runs while marks are on show and there is a thing to place.
function M.Runs(on, things) return on and things > 0 end

---------------------------------------------------------------- the game

local function Obj(path) return StaticFindObject(path) end
local Logged = {}
local function Once(ctx, key, msg) if not Logged[key] then Logged[key] = true ctx.Log(msg) end end

-- the widgets of the mod in the compass, and what changed in it; all dropped by Forget
M.TexCache = {}   -- group -> the picture; reused while valid (main.lua's CachedTex)
M.Chain = {}      -- the state of the chain of calls (chain.lua)

local function Reset()
    M.Comp, M.Name, M.Made, M.Pool, M.Tex, M.Dia, M.DiaWas = nil, nil, {}, {}, {}, nil, nil
    M.Creatures, M.Resources, M.NextCreatures, M.NextResources, M.Key = {}, {}, 0, 0, nil
    M.Want, M.Lit, M.Dirty = false, 0, false
    if M.Ctx and M.Ctx.Chain then M.Ctx.Chain.Stop(M.Chain) end   -- a call still queued does nothing
end

-- Our widgets off the compass, and the middle mark in its own colour again. Only while its world stands.
local function TakeOff()
    for _, w in ipairs(M.Made) do pcall(function() if w:IsValid() then w:RemoveFromParent() end end) end
    pcall(function() if M.Dia and M.DiaWas and M.Dia:IsValid() then M.Dia:SetColorAndOpacity(M.DiaWas) end end)
end

local function Valid(w, what)
    if not (w and w:IsValid()) then error("no " .. what) end
    return w
end

-- the widgets, built once for a compass: the gold line, a hidden Image that holds each picture, the pool of marks and
-- the gold middle mark. Each part gets a new name (ctx.G), also the two halves of the line.
local function Build(ctx, comp, pc)
    local tree = Valid(comp.WidgetTree, "widget tree")
    local strip = Valid(comp.CompassRetainerBox, "compass strip")
    local host = Valid(strip:GetParent(), "compass overlay")
    local icons = Valid(comp.CompassBottomIconOverlay, "compass icon overlay")
    local lineTex = ctx.Asset(ctx.GoldLine.PATH, "/Script/Engine.Texture2D")
    if not lineTex then error("line picture not loaded") end
    local function New(cls, name) return StaticConstructObject(Obj("/Script/UMG." .. cls), tree, ctx.G("RU_Cm" .. STAMP .. name)) end
    local function Add(overlay, widget)
        local slot = overlay:AddChildToOverlay(widget)
        M.Made[#M.Made + 1] = widget
        slot:SetHorizontalAlignment(2)
        slot:SetVerticalAlignment(2)
        return slot
    end
    local box = New("SizeBox", "LineBox")
    box:SetWidthOverride(LINE_W)
    box:SetHeightOverride(LINE_H)
    -- the line's picture is a pale gold: over the strip's white line it read as white (in game, 04-10-2026), so its
    -- two halves get the gold of the middle mark
    box:SetContent(ctx.GoldLine.Row(function(cls, name)
        local w = New(cls, name)
        if cls == "Image" then w:SetColorAndOpacity(GOLD) end
        return w
    end, lineTex, "Line"))
    Add(host, box):SetPadding({ Left = 0, Top = LINE_TOP, Right = 0, Bottom = 0 })
    box:SetRenderTranslation({ X = 0, Y = LINE_Y })
    box:SetVisibility(3)
    for group, file in pairs(FILES) do
        local ok, tex = pcall(ctx.CachedTex, M.TexCache, group, pc, ART .. file)
        if ok then
            local holder = New("Image", "Hold" .. group)
            holder:SetBrushFromTexture(tex, false)
            holder:SetVisibility(1)
            Add(icons, holder)
            M.Tex[group] = tex
        else
            Once(ctx, "art" .. group, "compass: picture not loaded: " .. file .. " " .. tostring(tex))
        end
    end
    for i = 1, POOL do
        local img = New("Image", "Mark" .. i)
        Add(icons, img)
        img:SetVisibility(1)
        M.Pool[i] = { W = img }
    end
    local dia = Valid(comp.DirectionalDiamond, "middle mark")
    local c = dia.ColorAndOpacity
    M.DiaWas, M.Dia = { R = c.R, G = c.G, B = c.B, A = c.A }, dia
    dia:SetColorAndOpacity(GOLD)
    M.Comp, M.Name, M.Icons = comp, comp:GetFullName(), icons
end

-- one mark of the pool, written only where its value changed
local function Put(m, group, px, size, opacity)
    if not m.W:IsValid() then error(GONE) end   -- freed by the game: a write would be a native write to a freed object
    if m.Group ~= group then
        local tex = M.Tex[group]
        if not tex:IsValid() then error(GONE) end
        m.Group, m.Size = group, nil
        m.W:SetBrushFromTexture(tex, false)
    end
    if m.Size ~= size then
        m.Size = size
        local b = m.W.Brush
        b.ImageSize = { X = size, Y = size }
        m.W:SetBrush(b)
    end
    if m.Px ~= px then m.Px = px m.W:SetRenderTranslation({ X = px, Y = DOWN }) end
    if m.Opacity ~= opacity then m.Opacity = opacity m.W:SetRenderOpacity(opacity) end
    if not m.On then m.On = true m.W:SetVisibility(3) end
end

-- the next free mark of the pool for a thing; the number used so far comes back. A creature moves: its place is read
-- now, and a creature that is gone is skipped. A resource stands still: its place was read at the scan.
local function Draw(t, at, yaw, used)
    if used >= POOL then return used end
    local x, y = t.X, t.Y
    if t.Moves then
        local A = t.A
        if not (A and A:IsValid()) then return used end
        local p = A:K2_GetActorLocation()
        x, y = p.X, p.Y
    end
    local px, size, opacity = M.Look(x - at.X, y - at.Y, yaw)
    if not px then return used end
    Put(M.Pool[used + 1], t.Group, px, size, opacity)
    return used + 1
end

-- marks that were on show and are not now
local function Hide(from)
    for i = from, M.Lit do
        local m = M.Pool[i]
        if m.On then
            if not m.W:IsValid() then error(GONE) end
            m.On = false
            m.W:SetVisibility(1)
        end
    end
    M.Lit = from - 1
end

local function Paint(ctx)
    local comp = M.Comp
    if not (comp and comp:IsValid()) then return end
    -- the marks sit in the game's own row of icons: when the game clears it, the engine frees them
    if not (M.Icons:IsValid() and M.Pool[1].W:IsValid()) then error(GONE) end
    if not M.Want then if M.Lit > 0 then Hide(1) end return end
    local pc = ctx.Controller()
    local pawn = pc and pc.Pawn
    if not (pawn and pawn:IsValid()) then return end
    local at = pawn:K2_GetActorLocation()
    local yaw = pc.ControlRotation.Yaw
    local used = 0
    for _, t in ipairs(M.Creatures) do used = Draw(t, at, yaw, used) end
    for _, t in ipairs(M.Resources) do used = Draw(t, at, yaw, used) end
    Hide(used + 1)
end

-- The game freed our widgets: let go of them, take off what is left and build again after 10 s (3 times at most, as for
-- a failed build). Nothing of the freed ones is touched.
local function Lost(ctx)
    TakeOff()
    Reset()
    M.Fails, M.RetryAt = M.Fails + 1, os.clock() + 10
    ctx.Log("compass: the marks were taken out of the compass, building again")
end

-- Paint, a failure logged once; true when it went through
local function Safe(ctx)
    local ok, err = pcall(Paint, ctx)
    if ok then return true end
    if string.find(tostring(err), GONE, 1, true) then Lost(ctx)
    else Once(ctx, "paint", "compass: marks not painted: " .. tostring(err)) end
    return false
end

-- The things near the player, as the map has them: creatures every 2 s, resources every 10 s. The ones of a group that
-- is off, a dead creature, an empty rock and a group with no picture are left out.
local function Scan(ctx, now, groups, pawn)
    if now >= M.NextCreatures then
        M.NextCreatures = now + CREATURES_EVERY
        local list = {}
        if groups.Enemy or groups.Calm then
            for _, e in ipairs(ctx.Near.Creatures(ctx, pawn)) do
                if not e.Dead and groups[e.Group] and M.Tex[e.Group] then list[#list + 1] = { A = e.A, Group = e.Group, Moves = true } end
            end
        end
        M.Creatures, M.Dirty = list, true
    end
    if now >= M.NextResources then
        M.NextResources = now + RESOURCES_EVERY
        local list = {}
        if groups.Ore or groups.Herbs or groups.Essence or groups.Trees then
            for _, e in ipairs(ctx.Near.Resources(ctx, pawn)) do
                if not e.Empty and groups[e.Group] and M.Tex[e.Group] then
                    local ok, p = pcall(function() return e.A:K2_GetActorLocation() end)
                    if ok and p then list[#list + 1] = { Group = e.Group, X = p.X, Y = p.Y } end
                end
            end
        end
        M.Resources, M.Dirty = list, true
    end
end

local function More() return M.Runs(M.Want, #M.Creatures + #M.Resources) end

-- The compass of a new build: the old one is let go without a touch (the game made another, or freed it). key: the
-- full name of comp, which finder.lua read when it found the widget.
local function Compass(ctx, comp, key, now)
    if M.Comp and not (M.Comp:IsValid() and M.Name == key) then
        Reset()
    end
    if M.Comp or M.Fails >= 3 or now < M.RetryAt then return end
    local pc = ctx.Controller()
    if not pc then return end
    local ok, err = pcall(Build, ctx, comp, pc)
    if ok then
        M.Fails = 0
        ctx.Log("compass ready")
    else
        TakeOff()
        Reset()
        M.Fails, M.RetryAt = M.Fails + 1, now + 10
        ctx.Log("compass failed: " .. tostring(err))
    end
end

-- Leaving the world, or a restart in it: in the same world our widgets come off the compass and the middle mark has its
-- colour back; after a world change the engine has freed them, and nothing is touched.
function M.Forget(sameWorld)
    if sameWorld then TakeOff() end
    Reset()
    if M.Ctx and M.Ctx.Near then M.Ctx.Near.Forget() end
    M.Fails, M.RetryAt = 0, 0
    Logged = {}
end
M.Forget(false)

function M.Tick(ctx)
    M.Ctx = ctx
    local now = os.clock()
    local comp, key = ctx.Compass()
    if comp then Compass(ctx, comp, key, now) end
    local groups = M.Groups(ctx.Set(), ctx.ById("creatures").Visible ~= false)
    local want = M.Comp ~= nil and M.MarksOn(comp ~= nil, ctx.MapShown(), groups)
    if want then
        local pc = ctx.Controller()
        local pawn = pc and pc.Pawn
        -- a group switched on or off shows at once, as on the map; the scan then runs again
        local sig = 0
        for _, g in ipairs(ORDER) do sig = sig * 2 + (groups[g] and 1 or 0) end
        if sig ~= M.Key then M.Key, M.NextCreatures, M.NextResources = sig, 0, 0 end
        if pawn and pawn:IsValid() and ctx.Near then
            local ok, err = pcall(Scan, ctx, now, groups, pawn)
            if not ok then
                M.NextCreatures, M.NextResources = now + CREATURES_EVERY, now + RESOURCES_EVERY
                Once(ctx, "scan", "compass: scan failed: " .. tostring(err))
            end
        end
    elseif M.Want then
        M.Creatures, M.Resources, M.NextCreatures, M.NextResources, M.Key = {}, {}, 0, 0, nil
    end
    -- the chain paints between two steps; the step paints at once when the state or the things changed, and when there is no chain
    local moved = want ~= M.Want or M.Dirty
    M.Want, M.Dirty = want, false
    if moved or not (ctx.Chain and ctx.Chain.Alive(M.Chain, ALIVE)) then Safe(ctx) end
    if ctx.Chain then ctx.Chain.Run(M.Chain, ctx, FAST, Safe, More) end
end

return M
