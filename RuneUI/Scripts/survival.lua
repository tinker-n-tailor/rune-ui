-- Food, water and rest in the style of the map (design sketch, 27-09-2026): a gold rim, a coloured ring
-- that fills with the value, a dark centre with the game's icon and a diamond under it; no numbers.
-- The game's own ring stays alive but unseen; ours is drawn from pictures (tools/make-runemap-art.js).
-- The coloured ring is two half rings, each in a box that cuts it at the middle: turning a half shows as
-- much of it as the value, so the ring fills clockwise from the top like a clock hand.
-- main.lua loads this file with pcall, so an error here leaves the rest of the mod running.

local M = {}

local ART_DIR = "ue4ss/Mods/RuneUI/Art/"
local RING = 68        -- the game's radial bar is 68 units; the pictures cover exactly that
local ICON = 68        -- twice the 34 that looked too small; the picture has wide empty edges (27-09-2026)
local DIAMOND = 10

-- Unreal takes widget colours as linear light; these are the sketch's screen colours, converted
local function Lin1(c) if c <= 0.04045 then return c / 12.92 end return ((c + 0.055) / 1.055) ^ 2.4 end
local function Lin(r, g, b, a) return { R = Lin1(r), G = Lin1(g), B = Lin1(b), A = a or 1.0 } end

local KINDS = {
    { Prop = "WBP_SurvivalCore_Upkeep_Hydration",  Name = "water", Colour = Lin(0.373, 0.698, 0.863) },   -- #5fb2dc
    { Prop = "WBP_SurvivalCore_Upkeep_Sustenance", Name = "food",  Colour = Lin(0.471, 0.761, 0.396) },   -- #78c265
    { Prop = "WBP_SurvivalCore_Upkeep_Endurance",  Name = "rest",  Colour = Lin(0.914, 0.886, 0.800) },   -- #e9e2cc
}
local ICON_TINT = Lin(0.945, 0.902, 0.784)   -- #f1e6c8

local function Obj(path) return StaticFindObject(path) end
local function New(cls, outer, name) return StaticConstructObject(Obj("/Script/UMG." .. cls), outer, FName(name)) end

local Logged = {}
local function Once(ctx, key, msg) if not Logged[key] then Logged[key] = true ctx.Log(msg) end end

-- A picture from the Art folder. The widget that shows it holds it; nothing keeps it only in Lua (a texture
-- held only by Lua is thrown away by the engine, which crashed the game once).
local function LoadArt(ctx, outer, name)
    local f = io.open(ART_DIR .. name, "rb")
    if not f then Once(ctx, "art" .. name, "survival: picture missing: " .. ART_DIR .. name) return nil end
    f:close()
    local KRL = Obj("/Script/Engine.Default__KismetRenderingLibrary")
    local ok, tex = pcall(function() return KRL:ImportFileAsTexture2D(outer, ART_DIR .. name) end)
    if ok and tex and tex:IsValid() then return tex end
    Once(ctx, "art" .. name, "survival: picture not loaded: " .. name .. " " .. tostring(tex))
end

local function Picture(tree, name, tex, size)
    local img = New("Image", tree, name)
    img:SetBrushFromTexture(tex, false)
    local b = img.Brush
    b.ImageSize = { X = size, Y = size }
    img:SetBrush(b)
    return img
end

local function Sized(tree, name, w, h, content)
    local box = New("SizeBox", tree, name)
    box:SetWidthOverride(w)
    box:SetHeightOverride(h)
    if content then box:SetContent(content) end
    return box
end

local function Add(ov, w, h, v, pad)
    local s = ov:AddChildToOverlay(w)
    s:SetHorizontalAlignment(h)
    s:SetVerticalAlignment(v)
    if pad then s:SetPadding(pad) end
    return s
end

-- A widget by name, inside game widgets too
local function Find(W, name, depth)
    depth = depth or 0
    if not (W and W:IsValid()) or depth > 8 then return nil end
    if W:GetFName():ToString() == name then return W end
    if string.find(W:GetClass():GetFName():ToString(), "^WBP_") then
        local ok, r = pcall(function() return Find(W.WidgetTree.RootWidget, name, depth + 1) end)
        return ok and r or nil
    end
    local okN, n = pcall(function() return W:GetChildrenCount() end)
    if okN and n then
        for i = 0, n - 1 do
            local r = Find(W:GetChildAt(i), name, depth + 1)
            if r then return r end
        end
        return nil
    end
    local okC, c = pcall(function() return W:GetContent() end)
    if okC and c then return Find(c, name, depth + 1) end
end

-- Every text widget under W, the game's own kinds too (the first test found no plain TextBlock there)
local function TextsUnder(W, list, depth)
    list, depth = list or {}, depth or 0
    if not (W and W:IsValid()) or depth > 8 then return list end
    local cls = W:GetClass():GetFName():ToString()
    if string.find(cls, "Text", 1, true) then table.insert(list, W) return list end
    if string.find(cls, "^WBP_") then
        pcall(function() TextsUnder(W.WidgetTree.RootWidget, list, depth + 1) end)
        return list
    end
    local okN, n = pcall(function() return W:GetChildrenCount() end)
    if okN and n then
        for i = 0, n - 1 do TextsUnder(W:GetChildAt(i), list, depth + 1) end
    else
        pcall(function() TextsUnder(W:GetContent(), list, depth + 1) end)
    end
    return list
end

-- One half of the coloured ring in a box that shows only its own side of the ring
local function Half(tree, name, tex, colour, right)
    local cv = New("CanvasPanel", tree, name .. "Canvas")
    local img = Picture(tree, name .. "Img", tex, RING)
    img:SetColorAndOpacity(colour)
    local s = cv:AddChildToCanvas(img)
    s:SetAutoSize(false)
    s:SetSize({ X = RING, Y = RING })
    s:SetPosition({ X = right and -RING / 2 or 0, Y = 0 })
    local clip = Sized(tree, name, RING / 2, RING, cv)
    clip:SetClipping(1)   -- clip to its box
    return clip, img
end

local Built = {}       -- one entry per kind: { Right, Left, Texts, Value }
M.Host, M.Builds = nil, 0

local function Decorate(ctx, U)
    M.Builds = M.Builds + 1
    -- a new name on every build: making an object with the name of a live one can crash the game
    local tag = "RU_Up" .. M.Builds .. "_" .. os.time()
    Built = {}
    -- the game's dark strip under the numbers: the sketch has none
    pcall(function() Find(U.WidgetTree.RootWidget, "TextBackground"):SetRenderOpacity(0.0) end)
    for i, K in ipairs(KINDS) do
        local ok, err = pcall(function()
            local base = U[K.Prop]
            local tree = base.WidgetTree
            local root = tree.RootWidget
            local bar = Find(root, "SegmentedRadialBar")
            local icon = Find(bar, "Icon")
            local texts = TextsUnder(Find(root, "SizeBox_1") or root)
            local back = LoadArt(ctx, tree, "upkeep_back.png")
            local half = LoadArt(ctx, tree, "upkeep_half.png")
            local centre = LoadArt(ctx, tree, "upkeep_centre.png")
            local dia = LoadArt(ctx, tree, "runemap_diamond.png")
            if not (bar and back and half and centre) then error("missing part: bar=" .. tostring(bar ~= nil)) end
            local n = tag .. "_" .. i
            local ov = New("Overlay", tree, n .. "Stack")
            Add(ov, Picture(tree, n .. "Back", back, RING), 2, 2)
            local right, rImg = Half(tree, n .. "R", half, K.Colour, true)
            local left, lImg = Half(tree, n .. "L", half, K.Colour, false)
            Add(ov, right, 3, 0)
            Add(ov, left, 1, 0)
            Add(ov, Picture(tree, n .. "Centre", centre, RING), 2, 2)
            local ourIcon
            if icon then
                pcall(function()
                    local tex = icon.Brush.ResourceObject
                    ourIcon = Picture(tree, n .. "Icon", tex, ICON)
                    ourIcon:SetColorAndOpacity(ICON_TINT)
                    Add(ov, ourIcon, 2, 2)
                end)
            end
            local box = Sized(tree, n, RING, RING, ov)
            -- our ring and diamond from an earlier round (a player restart keeps the game's widget): out first
            pcall(function()
                for c = root:GetChildrenCount() - 1, 0, -1 do
                    local w = root:GetChildAt(c)
                    if w and string.find(w:GetFName():ToString(), "RU_Up", 1, true) == 1 then w:RemoveFromParent() end
                end
            end)
            Add(root, box, 2, 1)        -- over the game's ring: centred, at the top of the element
            bar:SetRenderOpacity(0.0)   -- only once ours is in: the game's ring stays alive for the game, unseen
            if dia then Add(root, Picture(tree, n .. "Dia", dia, DIAMOND), 2, 1, { Left = 0, Top = RING - 2 - DIAMOND / 2, Right = 0, Bottom = 0 }) end
            -- no numbers: the ring shows how full it is (in-game review, 27-09-2026). The game still writes
            -- them, and the ring reads them.
            pcall(function() Find(root, "SizeBox_1"):SetRenderOpacity(0.0) end)
            Built[i] = { Right = rImg, Left = lImg, Icon = ourIcon, Texts = texts, Value = nil, Name = K.Name, Colour = K.Colour,
                GameRing = Find(bar, "RadialImage"), GameIcon = icon }
            local parts = {}
            for _, T in ipairs(texts) do pcall(function() table.insert(parts, "'" .. T:GetText():ToString() .. "'") end) end
            ctx.Log(string.format("survival: %s ring ready (numbers %s; low colours %s)", K.Name, table.concat(parts, " "), (icon and Built[i].GameRing) and "followed" or "not found"))
        end)
        if not ok then ctx.Log("survival: " .. K.Name .. " ring failed: " .. tostring(err)) end
    end
end

-- The share full, from the game's own numbers ("50" and "/100", or "50/100"); nil when there are none
local function Share(b)
    local s = ""
    for _, T in ipairs(b.Texts) do pcall(function() s = s .. " " .. T:GetText():ToString() end) end
    local nums = {}
    for d in string.gmatch(s, "%d+%.?%d*") do table.insert(nums, tonumber(d)) end
    if #nums == 0 then return nil end
    local max = (#nums >= 2 and nums[#nums] > 0) and nums[#nums] or 100
    return math.max(0, math.min(1, nums[1] / max))
end

-- Low water, food or rest: the game turns its icon red and its ring orange (25 or less) or dark red (10 or
-- less); read in game, 27-09-2026. Ours follows: while the game's icon is not white, our ring and icon take
-- the game's colours, lifted to at least half brightness so the dark red still reads on the dark ring.
local function Lift(c)
    local m = math.max(c.R, c.G, c.B)
    local k = (m > 0 and m < 0.5) and 0.5 / m or 1
    return { R = c.R * k, G = c.G * k, B = c.B * k, A = 1.0 }
end

local function Warn(b)
    local ring, icon = b.Colour, ICON_TINT
    local c = b.GameIcon.ColorAndOpacity
    if c.R < 0.99 or c.G < 0.99 or c.B < 0.99 then
        ring, icon = Lift(b.GameRing.ColorAndOpacity), Lift(c)
    end
    local key = string.format("%.2f %.2f %.2f %.2f %.2f %.2f", ring.R, ring.G, ring.B, icon.R, icon.G, icon.B)
    if key == b.Tint then return end
    b.Tint = key
    b.Right:SetColorAndOpacity(ring)
    b.Left:SetColorAndOpacity(ring)
    if b.Icon then b.Icon:SetColorAndOpacity(icon) end
end

local function Turn(b, p)
    local deg = p * 360
    if p <= 0.5 then
        b.Right:SetRenderTransformAngle(deg - 180)
        b.Left:SetRenderOpacity(0.0)
    else
        b.Right:SetRenderTransformAngle(0)
        b.Left:SetRenderTransformAngle(deg - 180)
        b.Left:SetRenderOpacity(1.0)
    end
end

-- Leaving the world: drop the handles into it before the engine frees them (see main.lua)
function M.Forget()
    Built = {}
    M.Host, M.Tried = nil, nil
end

function M.Tick(ctx)
    if os.clock() < (M.Next or 0) then return end
    M.Next = os.clock() + 0.5   -- the values change over minutes
    local U = ctx.ById("survival").Instances[1]
    if not (U and U:IsValid()) then return end
    local name = U:GetFullName()
    -- alive while any ring stands: one ring that failed must not stop the others from turning
    local function Alive()
        for _, b in pairs(Built) do if b.Right and b.Right:IsValid() then return true end end
        return false
    end
    if name ~= M.Host or not Alive() then
        -- rings that the game took away are built again; a build that makes no ring is not tried again for
        -- this host widget (every build uses new widget names, so a second one is safe)
        if name == M.Host and M.Tried then return end
        M.Host = name
        Decorate(ctx, U)
        M.Tried = not Alive()
    end
    for _, b in pairs(Built) do
        pcall(function()
            local p = Share(b)
            if p and p ~= b.Value then b.Value = p Turn(b, p) end
            if b.GameIcon and b.GameRing then Warn(b) end
        end)
    end
end

return M
