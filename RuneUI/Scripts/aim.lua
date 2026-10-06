-- The aim marks in the middle of the screen in our gold, and our gold diamond in place of the white lock-on orb.
-- The marks: the dot of every weapon, the staff's ring, the bow's aim ring and the bow's stamina arc. They live in WBP_HUD_ReticleWidget_C: one reticle per weapon kind in a switcher (probe of
-- 29-09-2026). The orb is WBP_LockOnTargetOrb_C, one Image named Orb (T_Reticule_Asset, 64 in a 32 box).
-- The staff's ring round a target (WBP_TargetIcon_C) becomes our gold diamond, set once in the ring's template.
-- Every colour and picture changed here is remembered, so the F9 line off puts the game's look back.
-- main.lua loads this file with pcall, so an error here leaves the rest of the mod running.

local M = {}

local ART_DIR = (RUNEUI_DIR or "ue4ss/Mods/RuneUI/") .. "Art/"
-- the orb's box is 32 units; the diamond is about 14
local DIAMOND_SCALE = 0.45
-- the game's orb sits right of and below the middle of the staff's target mark; this puts the diamond in it
-- (measured in game, 01-10-2026, 2560x1440)
local DIAMOND_MOVE = { X = -3.6, Y = -5.6 }
-- the marks by name; images are tinted, bars get a fill colour, the bow's ring has its colour in its material
-- The staff's ring (MagicIcon) stayed white with the image tint (in game 30-09-2026): its brush's own tint as well.
local MARKS = { Crosshair = "image", MagicIcon = "brush", StaminaProgressBar = "bar", SightRing = "material" }
local GLOW = "Glow Color and Opacity"   -- the bow ring's colour (MI_RangedAimRingReticle; white, 0.7)

local function Lin1(c) if c <= 0.04045 then return c / 12.92 end return ((c + 0.055) / 1.055) ^ 2.4 end
local GOLD = { R = Lin1(0.89), G = Lin1(0.72), B = Lin1(0.38) }   -- #e3b861

local function Obj(path) return StaticFindObject(path) end
local Logged = {}
local function Once(ctx, key, msg) if not Logged[key] then Logged[key] = true ctx.Log(msg) end end
local function Name(W) return W:GetFName():ToString() end
local function Copy(c) return { R = c.R, G = c.G, B = c.B, A = c.A } end
local function Gold(a) return { R = GOLD.R, G = GOLD.G, B = GOLD.B, A = a } end
local function IsGold(c) return math.abs(c.R - GOLD.R) < 0.01 and math.abs(c.G - GOLD.G) < 0.01 and math.abs(c.B - GOLD.B) < 0.01 end

-- The game's own colours and orb picture, by widget full name: plain values, no handles. Kept through a new world,
-- because a player restart keeps these widgets (they belong to the game instance, probe of 29-09-2026): taken
-- again there, the colour would already be our gold and the white could never come back.
local Saved = {}

M.Marks, M.Host = {}, nil   -- { W, Key (full name), Name, Kind, Mid (the ring's own material) }
M.Orb = nil                 -- { W (the Orb image), Host, Tex (ours) }
M.Ring = nil                -- the target ring template's Image, once the diamond is in it

-- every widget under W with a name in MARKS, through the reticles' own trees
local function Collect(W, out, depth)
    if not (W and W:IsValid()) or depth > 12 then return end
    local name = Name(W)
    local kind = MARKS[name]
    if kind then out[#out + 1] = { W = W, Key = W:GetFullName(), Name = name, Kind = kind } end
    local okT, root = pcall(function() return W.WidgetTree.RootWidget end)
    if okT and root and root:IsValid() then Collect(root, out, depth + 1) return end
    local okN, n = pcall(function() return W:GetChildrenCount() end)
    if okN and n then
        for i = 0, n - 1 do Collect(W:GetChildAt(i), out, depth + 1) end
    else
        pcall(function() Collect(W:GetContent(), out, depth + 1) end)
    end
end
M.Collect = Collect   -- crosshair.lua hides the same marks

-- the value of a vector parameter in a material's own list (a constant instance keeps its values there)
local function VectorParam(mat, name)
    local v
    pcall(function()
        mat.VectorParameterValues:ForEach(function(_, e)
            local p = e:get()
            if p.ParameterInfo.Name:ToString() == name then v = Copy(p.ParameterValue) end
        end)
    end)
    return v
end

-- one mark in gold, the game's own see-through level kept; again on the next check if the game made it white
local function Paint(m)
    if m.Kind == "brush" then
        local t = m.W.Brush.TintColor.SpecifiedColor
        if not IsGold(t) then
            Saved[m.Key .. "#brush"] = Saved[m.Key .. "#brush"] or Copy(t)
            m.W:SetBrushTintColor({ SpecifiedColor = Gold(t.A), ColorUseRule = 0 })
        end
    end
    if m.Kind == "image" then   -- not "brush" as well: gold on gold reads darker
        local c = m.W.ColorAndOpacity
        if not IsGold(c) then
            Saved[m.Key] = Saved[m.Key] or Copy(c)
            m.W:SetColorAndOpacity(Gold(c.A))
        end
    elseif m.Kind == "bar" then
        local c = m.W.FillColorAndOpacity
        if not IsGold(c) then
            Saved[m.Key] = Saved[m.Key] or Copy(c)
            m.W:SetFillColorAndOpacity(Gold(c.A))
        end
    elseif m.Kind == "material" and not m.Mid then
        -- the ring is drawn by its material, so a tint on the image would not reach it: its own copy of the
        -- material gets the gold. The white is read first, from the game's material.
        local c = VectorParam(m.W.Brush.ResourceObject, GLOW)
        if c and not IsGold(c) then Saved[m.Key] = Saved[m.Key] or c end
        m.Mid = m.W:GetDynamicMaterial()
        m.Mid:SetVectorParameterValue(FName(GLOW), Gold((Saved[m.Key] or { A = 0.7 }).A))
    end
    if m.Kind == "material" then
        -- the glow alone left the ring white (in game 30-09-2026): the image's tint as well
        local c = m.W.ColorAndOpacity
        if not IsGold(c) then
            Saved[m.Key .. "#tint"] = Saved[m.Key .. "#tint"] or Copy(c)
            m.W:SetColorAndOpacity(Gold(c.A))
        end
    end
end

-- the game's colour back; white at the present see-through level if it was never read
local function Unpaint(m)
    local o = Saved[m.Key]
    Saved[m.Key] = nil
    if not (m.W and m.W:IsValid()) then return end
    if m.Kind == "brush" then
        local t = Saved[m.Key .. "#brush"]
        Saved[m.Key .. "#brush"] = nil
        m.W:SetBrushTintColor({ SpecifiedColor = t or { R = 1, G = 1, B = 1, A = 1 }, ColorUseRule = 0 })
    end
    if m.Kind == "image" then m.W:SetColorAndOpacity(o or { R = 1, G = 1, B = 1, A = m.W.ColorAndOpacity.A })
    elseif m.Kind == "bar" then m.W:SetFillColorAndOpacity(o or { R = 1, G = 1, B = 1, A = m.W.FillColorAndOpacity.A })
    elseif m.Kind == "material" then
        local mid = m.Mid or m.W:GetDynamicMaterial()
        mid:SetVectorParameterValue(FName(GLOW), o or { R = 1, G = 1, B = 1, A = 0.7 })
        local t = Saved[m.Key .. "#tint"]
        Saved[m.Key .. "#tint"] = nil
        m.W:SetColorAndOpacity(t or { R = 1, G = 1, B = 1, A = m.W.ColorAndOpacity.A })
    end
    m.Mid = nil
end

local function Marks(ctx)
    local R = ctx.Reticle()
    if not (R and R:IsValid()) then return end
    local host = R:GetFullName()
    if host ~= M.Host then
        M.Host, M.Marks = host, {}
        Collect(R, M.Marks, 0)
        local names = {}
        for _, m in ipairs(M.Marks) do names[#names + 1] = m.Name end
        ctx.Log("aim: " .. #M.Marks .. " marks gold (" .. table.concat(names, ", ") .. ")")
    end
    for _, m in ipairs(M.Marks) do
        local ok, err = pcall(Paint, m)
        if not ok then Once(ctx, "paint" .. m.Name, "aim: " .. m.Name .. " not gold: " .. tostring(err)) end
    end
end

-- The staff's ring round a target is our gold diamond. The game builds a new WBP_TargetIcon_C for every target from
-- its class template, so a ring tinted after the widget search shows white half the time. The diamond goes into the template's one Image instead, once: every ring built after
-- has it. The template's full name holds "WBP_TargetIcon_C:WidgetTree." under /Game, never /Engine/Transient.
local function Template()
    for _, I in pairs(FindAllOf("Image") or {}) do
        local ok, full = pcall(function() return I:GetFullName() end)
        if ok and string.find(full, "WBP_TargetIcon_C:WidgetTree.", 1, true) and not string.find(full, "/Engine/Transient", 1, true) then return I end
    end
end

local function Ring(ctx)
    if M.Ring and M.Ring:IsValid() then return end
    -- a search of every image: 3 tries a world, 30 s apart, so a player without a staff does not pay for it all session
    if os.clock() < (M.NextRing or 0) or (M.RingTries or 0) >= 3 then return end
    M.NextRing, M.RingTries = os.clock() + 30, (M.RingTries or 0) + 1
    local t0 = os.clock()
    local I = Template()
    if not I then Once(ctx, "noring", "aim: no target ring template yet") return end
    local tex = Obj("/Script/Engine.Default__KismetRenderingLibrary"):ImportFileAsTexture2D(I, ART_DIR .. "mark_diamond.png")
    if not (tex and tex:IsValid()) then Once(ctx, "ringtex", "aim: mark picture not loaded") return end
    local b = I.Brush
    if not Saved.Ring then   -- the game's picture by its path, and its colours; the template outlives a world
        local full = b.ResourceObject:GetFullName()
        Saved.Ring = { Tex = string.match(full, "^%S+%s+(.*)$") or full, Tint = Copy(b.TintColor.SpecifiedColor), Color = Copy(I.ColorAndOpacity) }
    end
    b.ResourceObject = tex
    b.TintColor = { SpecifiedColor = { R = 1, G = 1, B = 1, A = 1 }, ColorUseRule = 0 }
    I.ColorAndOpacity = Gold(1)
    M.Ring = I
    ctx.Log(string.format("aim: gold diamond in the target ring template (search %.0f ms)", (os.clock() - t0) * 1000))
end

-- the game's ring back in the template; rings on screen now keep the diamond until their target changes
local function Unring()
    local s, I = Saved.Ring, M.Ring
    M.Ring, M.NextRing, M.RingTries = nil, 0, 0
    local tex = s and Obj(s.Tex)
    -- the game's picture not found: Saved.Ring stays, so the next "on" never saves our diamond as the game's
    if not (I and I:IsValid() and tex and tex:IsValid()) then return end
    Saved.Ring = nil
    local b = I.Brush
    b.ResourceObject = tex
    b.TintColor = { SpecifiedColor = s.Tint, ColorUseRule = 0 }
    I.ColorAndOpacity = s.Color
end

local function Diamond(ctx)
    local O = ctx.Orb()
    if not (O and O:IsValid()) then return end
    local host = O:GetFullName()
    local o = M.Orb
    if not (o and o.Host == host and o.W:IsValid()) then
        if M.NoPicture then return end   -- the picture did not load once: not read from disk every half second
        local img
        local tree = O.WidgetTree
        pcall(function() img = tree.RootWidget:GetContent() end)   -- SizeBox_1 holds the Orb image
        if not (img and img:IsValid() and Name(img) == "Orb") then Once(ctx, "orb", "aim: no Orb image in the lock-on orb") return end
        local b = img.Brush
        -- the full path of the game's picture, found again by it when put back; only a game picture (under /Game/),
        -- never our diamond left on the orb by a put-back that failed
        local full = b.ResourceObject:GetFullName()
        if not Saved[host] and string.find(full, " /Game/", 1, true) then
            Saved[host] = { Tex = string.match(full, "^%S+%s+(.*)$") or full, Size = { X = b.ImageSize.X, Y = b.ImageSize.Y } }
        end
        -- the widget holds the texture: one held only by Lua gets freed by the engine (see survival.lua)
        local KRL = Obj("/Script/Engine.Default__KismetRenderingLibrary")
        local okT, tex = pcall(function() return KRL:ImportFileAsTexture2D(tree, ART_DIR .. "runemap_diamond.png") end)
        if not (okT and tex and tex:IsValid()) then M.NoPicture = true Once(ctx, "tex", "aim: diamond picture not loaded") return end
        o = { W = img, Host = host, Tex = tex }
        M.Orb = o
    end
    -- the first time, or the game put its own picture back (two Lua handles of one object are not ==)
    local now = o.W.Brush.ResourceObject
    if not (now and now:IsValid() and now:GetAddress() == o.Tex:GetAddress()) then
        o.W:SetBrushFromTexture(o.Tex, false)
        local b = o.W.Brush
        b.ImageSize = Saved[host] and Saved[host].Size or { X = 64, Y = 64 }   -- 64: the game's orb (probe)
        o.W:SetBrush(b)
        o.W:SetRenderScale({ X = DIAMOND_SCALE, Y = DIAMOND_SCALE })
        o.W:SetRenderTranslation(DIAMOND_MOVE)
        Once(ctx, "diamond", "aim: gold diamond on the lock-on")
    end
end

local function Undiamond()
    local o = M.Orb
    M.Orb = nil
    if not (o and o.W:IsValid()) then return end
    local s = Saved[o.Host]
    Saved[o.Host] = nil
    local tex = s and Obj(s.Tex)
    if not (tex and tex:IsValid()) then return end
    o.W:SetBrushFromTexture(tex, false)
    local b = o.W.Brush
    b.ImageSize = s.Size
    o.W:SetBrush(b)
    o.W:SetRenderScale({ X = 1, Y = 1 })
    o.W:SetRenderTranslation({ X = 0, Y = 0 })
end

-- the F9 line off: the game's colours and orb back. The widgets are looked up again, as after a player restart the
-- handles are gone but the widgets are still gold. False while the aim widget is not found yet: tried again.
local function Restore(ctx)
    pcall(Unring)
    local R = ctx.Reticle()
    if not (R and R:IsValid()) then return false end
    local host = R:GetFullName()
    if host ~= M.Host then M.Host, M.Marks = host, {} Collect(R, M.Marks, 0) end
    for _, m in ipairs(M.Marks) do pcall(Unpaint, m) end
    local O = ctx.Orb()
    if O and O:IsValid() then
        if not (M.Orb and M.Orb.W:IsValid()) then
            pcall(function()
                local img = O.WidgetTree.RootWidget:GetContent()
                if img and img:IsValid() and Name(img) == "Orb" then M.Orb = { W = img, Host = O:GetFullName() } end
            end)
        end
        pcall(Undiamond)
    end
    Saved = {}   -- anything left belonged to the widgets of an old world
    M.Marks, M.Host, M.Orb = {}, nil, nil
    return true
end

-- a new world: the handles go; Saved stays (see there). The ring template is not the world's: it stays too.
function M.Forget()
    M.Marks, M.Host, M.Orb, M.NoPicture, M.RingTries = {}, nil, nil, nil, 0
    Logged = {}
end

function M.Tick(ctx)
    if os.clock() < (M.Next or 0) then return end
    M.Next = os.clock() + 0.5
    if not ctx.On() then
        if M.Applied then
            local okR, done = pcall(Restore, ctx)
            if okR and done then M.Applied = false ctx.Log("aim: the game's white marks back") end
            if not okR then Once(ctx, "restore", "aim: white not put back: " .. tostring(done)) end
        end
        return
    end
    M.Applied = true
    local okM, errM = pcall(Marks, ctx)
    if not okM then Once(ctx, "marks", "aim: marks failed: " .. tostring(errM)) end
    local okI, errI = pcall(Ring, ctx)
    if not okI then Once(ctx, "ring", "aim: target ring failed: " .. tostring(errI)) end
    local okD, errD = pcall(Diamond, ctx)
    if not okD then Once(ctx, "orbfail", "aim: diamond failed: " .. tostring(errD)) end
end

return M
