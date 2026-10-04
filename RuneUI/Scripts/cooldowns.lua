-- Spell cooldowns (design sketch C, playtest 29-09-2026): while a spell recovers, a see-through square tile on the left
-- of the screen with the spell's icon, a gold fill rising from the bottom and the seconds in the corner. It goes
-- when the spell is ready. The newest tile is at the bottom; when one finishes, the ones below move up (playtest,
-- 30-09-2026). Never faded by the immersive mode. main.lua moves and sizes it as the F9 element "cooldowns".
-- The data is the game's spell wheel, which counts on while it is closed (probe of 29-09-2026): 12 slices
-- (WBP_SurvivalSorcery_RadialSlice_C), each with SliceIcon (the spell's texture), CooldownWidget (visibility 3 while
-- the spell recovers), its TimerRing (material, FillBar rising 0 to 1) and CooldownText (the seconds).
-- main.lua loads this file with pcall, so an error here leaves the rest of the mod running.

local M = {}

local TILES = 6            -- tiles in the stack; a seventh recovering spell waits for a free one
local TILE = 60            -- a tool bar slot (probe: 60 x 60 units)
local GAP = 8
M.BOX_W, M.BOX_H = TILE, TILES * TILE + (TILES - 1) * GAP   -- the stack's fixed box: F9 scales around its middle
local ICON = 36
local RADIUS = 3

local function Lin1(c) if c <= 0.04045 then return c / 12.92 end return ((c + 0.055) / 1.055) ^ 2.4 end
local function Lin(r, g, b, a) return { R = Lin1(r), G = Lin1(g), B = Lin1(b), A = a or 1.0 } end
local DARK = Lin(0.086, 0.071, 0.051, 0.32)     -- #16120d at 32%: the sketch's see-through tile
local EDGE = Lin(0.72, 0.57, 0.31, 0.45)        -- #b8924f at 45%: the thin gold edge
local FILL = Lin(0.89, 0.72, 0.35, 0.38)        -- #e3b85a at 38%: the rising fill
local CREAM = Lin(0.945, 0.902, 0.784)          -- #f1e6c8, the seconds

local function Obj(path) return StaticFindObject(path) end
local function New(cls, outer, name) return StaticConstructObject(Obj("/Script/UMG." .. cls), outer, FName(name)) end
local Logged = {}
local function Once(ctx, key, msg) if not Logged[key] then Logged[key] = true ctx.Log(msg) end end

-- The order of the tiles: the recovering spells by the time they started, newest last. order: keys from the last
-- step; active: key -> true for the spells recovering now, and fresh: their keys in slice order. Returns the new order.
function M.Order(order, active, fresh)
    local out, seen = {}, {}
    for _, k in ipairs(order) do
        if active[k] then out[#out + 1] = k seen[k] = true end
    end
    for _, k in ipairs(fresh) do
        if not seen[k] then out[#out + 1] = k seen[k] = true end
    end
    return out
end

-- a rounded box drawn by the brush itself: filled, with an optional outline
local function Box(tree, name, fill, outline)
    local img = New("Image", tree, name)
    local b = img.Brush
    b.DrawAs = 4   -- RoundedBox
    b.TintColor = { SpecifiedColor = fill, ColorUseRule = 0 }
    b.OutlineSettings.RoundingType = 0   -- fixed radius
    b.OutlineSettings.CornerRadii = { X = RADIUS, Y = RADIUS, Z = RADIUS, W = RADIUS }
    b.OutlineSettings.Width = outline and 1 or 0
    b.OutlineSettings.Color = { SpecifiedColor = outline or { R = 0, G = 0, B = 0, A = 0 }, ColorUseRule = 0 }
    img:SetBrush(b)
    return img
end

local function Add(ov, w, h, v)
    local s = ov:AddChildToOverlay(w)
    s:SetHorizontalAlignment(h)
    s:SetVerticalAlignment(v)
    return s
end

local function Tile(ctx, tree, n)
    local box = New("SizeBox", tree, n)
    box:SetWidthOverride(TILE)
    box:SetHeightOverride(TILE)
    local ov = New("Overlay", tree, n .. "Ov")
    box:SetContent(ov)
    local back = Box(tree, n .. "Back", DARK, EDGE)
    Add(ov, back, 0, 0)
    local fillBox = New("SizeBox", tree, n .. "FillBox")
    fillBox:SetHeightOverride(0)
    fillBox:SetContent(Box(tree, n .. "Fill", FILL, nil))
    Add(ov, fillBox, 0, 3)   -- full width, at the bottom
    local icon = New("Image", tree, n .. "Icon")
    Add(ov, icon, 2, 2)
    icon:SetRenderOpacity(0.85)
    local text = ctx.Text(tree, n .. "Secs", 11, CREAM, "")
    local ts = Add(ov, text, 3, 3)
    ts:SetPadding({ Left = 0, Top = 0, Right = 4, Bottom = 1 })
    box:SetVisibility(1)
    return { Box = box, Back = back, FillBox = fillBox, Icon = icon, Text = text }
end

local function Build(ctx)
    M.Builds = (M.Builds or 0) + 1   -- a new name on every build (see runemap.lua)
    local uw = New("UserWidget", FindFirstOf("GameInstance"), "RuneUICooldowns" .. M.Builds)
    local tree = New("WidgetTree", uw, "RuneUICooldownsTree")
    uw.WidgetTree = tree
    local canvas = New("CanvasPanel", tree, "RU_CdCanvas")
    tree.RootWidget = canvas
    local size = New("SizeBox", tree, "RU_CdSize")
    size:SetWidthOverride(M.BOX_W)
    size:SetHeightOverride(M.BOX_H)
    local stack = New("VerticalBox", tree, "RU_CdStack")
    size:SetContent(stack)
    local tiles = {}
    for i = 1, TILES do
        local t = Tile(ctx, tree, "RU_Cd" .. M.Builds .. "_" .. i)
        local s = stack:AddChildToVerticalBox(t.Box)
        s:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = i < TILES and GAP or 0 })
        tiles[i] = t
    end
    local E = ctx.ById("cooldowns")
    local slot = canvas:AddChildToCanvas(size)
    slot:SetAutoSize(true)
    -- tied to the middle of the left edge, so it stays there on a wide screen; the spot is measured on a 16:9
    -- screen, 1920 x 1080 units
    slot:SetAnchors({ Minimum = { X = 0, Y = 0.5 }, Maximum = { X = 0, Y = 0.5 } })
    slot:SetPosition({ X = E.Center.X - M.BOX_W / 2, Y = E.Center.Y - M.BOX_H / 2 - 540 })
    uw:AddToViewport(39)
    uw:SetVisibility(1)
    M.W, M.UW, M.Tiles, M.Visible = size, uw, tiles, false
    ctx.Log("cooldowns ready")
end

-- the parts of one slice, found once per slice
local function PartsOf(ctx, slice, key)
    local p = M.Parts[key]
    if p and p.Cd:IsValid() and p.Ring:IsValid() and p.Secs:IsValid() and p.Icon:IsValid() then return p end
    local cd = ctx.Find(slice, "CooldownWidget")
    if not cd then return nil end
    p = { Cd = cd, Ring = ctx.Find(cd, "TimerRing"), Secs = ctx.Find(cd, "CooldownText"), Icon = ctx.Find(slice, "SliceIcon") }
    if not (p.Ring and p.Secs and p.Icon) then return nil end
    M.Parts[key] = p
    return p
end

local function FillOf(ring)
    local v = 0
    pcall(function()
        ring.Brush.ResourceObject.ScalarParameterValues:ForEach(function(_, e)
            local q = e:get()
            if q.ParameterInfo.Name:ToString() == "FillBar" then v = q.ParameterValue end
        end)
    end)
    return math.max(0, math.min(1, v))
end

-- the recovering spells now: key -> { Tex, Fill, Secs }, and their keys in slice order. ctx.Slices gives the
-- slices and their full names (read once by main.lua's search, not again here five times a second).
local function Read(ctx)
    local now, fresh = {}, {}
    local slices, keys = ctx.Slices()
    for i, slice in ipairs(slices) do
        pcall(function()
            local key = keys[i]
            local p = PartsOf(ctx, slice, key)
            if not p then Once(ctx, "noparts", "cooldowns: a slice without its cooldown parts") return end
            local v = p.Cd:GetVisibility()
            if v == 1 or v == 2 then return end   -- collapsed or hidden: the spell is ready
            local s = ""
            pcall(function() s = p.Secs:GetText():ToString() end)
            now[key] = { Tex = p.Icon.Brush.ResourceObject, Fill = FillOf(p.Ring), Secs = s }
            fresh[#fresh + 1] = key
        end)
    end
    return now, fresh
end

-- three tiles to see while F9 is open: the first spells' icons, made-up times
local function Samples(ctx)
    local list, fills, secs = {}, { 0.25, 0.6, 0.9 }, { "18", "7", "2" }
    local slices, keys = ctx.Slices()
    for i, slice in ipairs(slices) do
        if #list >= 3 then break end
        pcall(function()
            local p = PartsOf(ctx, slice, keys[i])
            local tex = p and p.Icon.Brush.ResourceObject
            if tex and tex:IsValid() then list[#list + 1] = { Tex = tex, Fill = fills[#list + 1], Secs = secs[#list + 1] } end
        end)
    end
    return list
end

local function Show(t, item)
    if not item then
        if t.Key then t.Key = nil t.Box:SetVisibility(1) end
        return
    end
    if not t.Key then t.Box:SetVisibility(4) end
    t.Key = true
    local tex = item.Tex
    if tex and tex:IsValid() and tex:GetAddress() ~= t.TexAddr then
        t.TexAddr = tex:GetAddress()
        t.Icon:SetBrushFromTexture(tex, false)
        local b = t.Icon.Brush
        b.ImageSize = { X = ICON, Y = ICON }
        t.Icon:SetBrush(b)
    end
    local h = math.floor(TILE * item.Fill + 0.5)
    if h ~= t.H then t.H = h t.FillBox:SetHeightOverride(h) end
    if item.Secs ~= t.Secs then t.Secs = item.Secs t.Text:SetText(FText(item.Secs)) end
end

function M.Forget(sameWorld)
    -- as RuneMap: off the screen only in the same world; after a world change the engine has taken it away
    if sameWorld and M.UW then pcall(function() M.UW:RemoveFromParent() end) end
    M.W, M.UW, M.Tiles, M.Visible, M.Op = nil, nil, nil, false, nil
    M.Parts, M.Keys, M.Fails, Logged = {}, {}, 0, {}
end
M.Forget(false)

function M.Tick(ctx)
    if os.clock() < (M.Next or 0) then return end
    M.Next = os.clock() + 0.2
    if not (M.W and M.W:IsValid()) then
        if (M.Fails or 0) >= 3 then return end
        local V = ctx.ById("vitals").Instances[1]
        if not (V and V:IsValid()) then return end   -- no world yet
        M.W = nil
        local ok, err = pcall(Build, ctx)
        if not ok then M.Fails = M.Fails + 1 ctx.Log("cooldowns failed: " .. tostring(err)) end
        return
    end
    local items = {}
    local editing = ctx.Editing()
    if ctx.On() or editing then
        local now, fresh = Read(ctx)
        M.Keys = M.Order(M.Keys, now, fresh)
        for _, k in ipairs(M.Keys) do items[#items + 1] = now[k] end
        if #items == 0 and editing then items = Samples(ctx) end
    end
    for i, t in ipairs(M.Tiles) do Show(t, items[i]) end
    -- the gold edge is an outline, which ignores the opacity main.lua sets (F9 dimming, the opacity keys): it takes
    -- that opacity by its own colour, as runemap.lua ApplyOpacity does.
    -- In the play test of 03-10-2026 the edge followed the opacity keys at once, with no change of visibility after
    -- SetBrush. The tool bar's edges were not drawn again after SetBrush alone (see toolbar.lua). The reason for
    -- the difference is not known.
    local op = M.W:GetRenderOpacity()
    if op ~= M.Op then
        M.Op = op
        for _, t in ipairs(M.Tiles) do
            local b = t.Back.Brush
            b.OutlineSettings.Color = { SpecifiedColor = { R = EDGE.R, G = EDGE.G, B = EDGE.B, A = EDGE.A * op }, ColorUseRule = 0 }
            t.Back:SetBrush(b)
        end
    end
    -- with the game's HUD (menus, the big map); off the screen when empty, not only see-through: the gold edge is an
    -- outline, and outlines stay at full strength inside a see-through parent (see runemap.lua)
    local V = ctx.ById("vitals").Instances[1]
    local hud = V and V:IsValid() and V:IsVisible()
    local visible = hud and #items > 0 and (ctx.On() or editing)
    if visible ~= M.Visible then
        M.Visible = visible
        M.UW:SetVisibility(visible and 3 or 1)
    end
end

return M
