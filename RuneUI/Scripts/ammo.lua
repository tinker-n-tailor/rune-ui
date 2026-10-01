-- The ammo counter in look A (sketch of 01-10-2026, picked by its letter): a small dark disk with a gold rim
-- holding the game's own rune or arrow icon, and the count under it in white with a shadow on the letters.
-- After his playtest (01-10-2026): no coloured ring ("the golden ring means nothing"), a bigger icon tinted by its
-- rune, a smaller count right of the disk, and the ammo's name left of it. The game showed the name above and only for a
-- moment; a rune's colour tells it, so its name shows a few seconds after a switch, but the arrows share one icon,
-- so the bow's name stays.
-- The game's ammo box is VerticalBox_0 of WBP_ReticleMagic_C (the staff) and WBP_ReticleRangedADS_C (the bow);
-- main.lua moves it as "ammo". It holds AmmoItemName ("Fire Rune"), then CounterBox with the count and Icon
-- (probe of 01-10-2026; the staff's count sits inside Overlay_0). Ours goes at the end of the box; the game's name
-- and counter are taken out of the box (see Build), and the count and icon are read from them.
-- main.lua loads this file with pcall, so an error here leaves the rest of the mod running.

local M = {}

local ART_DIR = "ue4ss/Mods/RuneUI/Art/"
local RING, ICON, ICON_BOW, COUNT = 30, 42, 26, 11   -- units; the sketch at 1440p: a disk of 40. Icon 17, count 13 before the playtest;
-- the rune pictures have wide empty edges: at 24 the flame sat small in the disk ("icon should fill whole circle").
-- The arrow's has none: at 42 it ran over the rim (a screenshot, 01-10-2026).
local NAME, NAME_W, NAME_HOLD = 11, 110, 4   -- the name's size, the room for it left of the disk, seconds it stays
local function Lin1(c) if c <= 0.04045 then return c / 12.92 end return ((c + 0.055) / 1.055) ^ 2.4 end
local WHITE = { R = 1, G = 1, B = 1, A = 1 }
local function Hex(h) return { R = Lin1(tonumber(h:sub(2, 3), 16) / 255), G = Lin1(tonumber(h:sub(4, 5), 16) / 255),
    B = Lin1(tonumber(h:sub(6, 7), 16) / 255), A = 1 } end
-- the icon's tint by the rune in its picture's name (T_Icons_Rune_Fire); the pick: red fire, blue water, white wind.
-- Earth is a guess. Anything else (the arrows) keeps the game's colours.
local RUNE = { Fire = Hex("#e0583c"), Water = Hex("#5fb2dc"), Air = Hex("#f1ead9"), Wind = Hex("#f1ead9"), Earth = Hex("#b98a52") }

local function Obj(path) return StaticFindObject(path) end
local function New(cls, outer, name) return StaticConstructObject(Obj("/Script/UMG." .. cls), outer, FName(name)) end

M.Built, M.Builds = {}, 0   -- box full name -> { Box, Count (game's text), Icon (game's image), Img, Text, Said, Tex }
-- box full name -> the game's counter, icon and name, once taken out of the box: a player restart keeps the box, and a
-- build after it finds them here. Not emptied with the world: a new world's boxes have new names.
M.Parts = {}

-- the widgets hold every picture: one held only by Lua gets freed by the engine and crashes the game later
local function LoadArt(tree, name)
    local tex = Obj("/Script/Engine.Default__KismetRenderingLibrary"):ImportFileAsTexture2D(tree, ART_DIR .. name)
    if not (tex and tex:IsValid()) then error("picture not loaded: " .. name) end
    return tex
end

local function Build(ctx, box, key)
    local counter, icon = ctx.Find(box, "CounterBox"), ctx.Find(box, "Icon")
    local p = M.Parts[key]
    if not counter and p and p.Counter:IsValid() and p.Icon:IsValid() then counter, icon = p.Counter, p.Icon end
    local name = ctx.Find(box, "AmmoItemName")
    if not name and p and p.Name and p.Name:IsValid() then name = p.Name end
    local count = counter and ctx.TextsUnder(counter)[1]
    if not (counter and icon and count) then error("no counter, icon or count in the ammo box") end
    local tree = box:GetOuter()
    M.Builds = M.Builds + 1
    local n = "RU_Am" .. M.Builds .. "_" .. os.time()   -- a new name each build (see survival.lua)
    -- ours from an earlier round first (a player restart keeps the game's widgets)
    for c = box:GetChildrenCount() - 1, 0, -1 do
        local w = box:GetChildAt(c)
        if string.find(w:GetFName():ToString(), "RU_Am", 1, true) == 1 then w:RemoveFromParent() end
    end
    -- the disk: the ring's back alone (dark, the gold rim), no coloured ring
    local stack = New("Overlay", tree, n .. "Stack")
    local back = New("Image", tree, n .. "Back")
    back:SetBrushFromTexture(LoadArt(tree, "upkeep_back.png"), false)
    local bb = back.Brush
    bb.ImageSize = { X = RING, Y = RING }
    back:SetBrush(bb)
    local bs = stack:AddChildToOverlay(back)
    bs:SetHorizontalAlignment(2) bs:SetVerticalAlignment(2)
    local img = New("Image", tree, n .. "Icon")
    local s = stack:AddChildToOverlay(img)
    s:SetHorizontalAlignment(2) s:SetVerticalAlignment(2)
    local disk = New("SizeBox", tree, n .. "Disk")
    disk:SetWidthOverride(RING) disk:SetHeightOverride(RING)
    disk:SetContent(stack)
    local text = ctx.Text(tree, n .. "Count", COUNT, WHITE, "")
    pcall(function()
        text:SetShadowOffset({ X = 1.5, Y = 1.5 })
        text:SetShadowColorAndOpacity({ R = 0, G = 0, B = 0, A = 0.85 })
    end)
    -- One line as tall as the disk: the name left of it, the count right of it (playtest, 01-10-2026: under the disk,
    -- the count left the screen when he set the disk level with the tool bar). Each text sits in a box of fixed
    -- width, so the disk stays where it was whatever the lengths, and every part is centred on the disk's middle.
    local label = ctx.Text(tree, n .. "Name", NAME, WHITE, "")
    pcall(function() label:SetJustification(2) end)   -- right, against the disk
    local function Side(w, name)
        local b = New("SizeBox", tree, n .. name)
        b:SetWidthOverride(NAME_W)
        b:SetContent(w)
        return b
    end
    local row = New("HorizontalBox", tree, n)
    local ns = row:AddChildToHorizontalBox(Side(label, "NameBox"))
    ns:SetVerticalAlignment(2)
    ns:SetPadding({ Left = 0, Top = 0, Right = 6, Bottom = 0 })
    row:AddChildToHorizontalBox(disk):SetVerticalAlignment(2)
    local cs = row:AddChildToHorizontalBox(Side(text, "CountBox"))
    cs:SetVerticalAlignment(2)
    cs:SetPadding({ Left = 6, Top = 0, Right = 0, Bottom = 0 })
    -- added at the end (UE4SS has no InsertChildAt on the box, in game 01-10-2026); the game's name and counter
    -- leave the box below, so ours is all it holds
    local slot = box:AddChildToVerticalBox(row)
    slot:SetHorizontalAlignment(2)
    -- the game's counter out of the box: the bow's is made visible again on every frame (probe, 01-10-2026), and
    -- even unseen it took room above ours. Its count and icon stay alive (the reticle holds them), the game still
    -- writes them, and they are read from there
    counter:SetRenderOpacity(0.0) counter:SetVisibility(1) counter:RemoveFromParent()
    -- the name too: the game shows it again on every switch (a faint second name), and folding it again each
    -- step still let it push ours down for a moment ("it drops, then rises", playtest, 01-10-2026)
    if name then name:SetRenderOpacity(0.0) name:SetVisibility(1) name:RemoveFromParent() end
    M.Parts[key] = { Counter = counter, Icon = icon, Name = name }
    M.Built[key] = { Box = row, Count = count, Icon = icon, Img = img, Text = text, Name = name, Label = label,
        Bow = string.find(key, "RangedADS", 1, true) ~= nil, Until = os.clock() + NAME_HOLD }
    ctx.Log("ammo: ring look on " .. (key:match("(WBP_Reticle[%w_]-_C)") or key))
end

-- the count and the picture of the game's own, into ours when they change
local function Update(b)
    local ok, s = pcall(function() return b.Count:GetText():ToString() end)
    -- an empty count is the game loading a weapon's ammo: the last one stays, or the icon showed alone (playtest, 01-10-2026)
    if ok and s ~= "" and s ~= b.Said then b.Said = s b.Text:SetText(FText(s)) end
    local tex = b.Icon.Brush.ResourceObject
    if tex and tex:IsValid() and tex:GetAddress() ~= b.Tex then
        b.Tex = tex:GetAddress()
        b.Img:SetBrushFromTexture(tex, false)
        local br = b.Img.Brush
        local size = b.Bow and ICON_BOW or ICON
        br.ImageSize = { X = size, Y = size }
        b.Img:SetBrush(br)
        local pic, tint = tex:GetFName():ToString(), WHITE
        for rune, c in pairs(RUNE) do if string.find(pic, rune, 1, true) then tint = c end end
        b.Img:SetColorAndOpacity(tint)
    end
    -- the name: ours left of the disk, read from the game's (out of the box, see Build)
    if b.Name then
        local okN, nm = pcall(function() return b.Name:GetText():ToString() end)
        if okN and nm ~= b.NameSaid then
            b.NameSaid, b.Until = nm, os.clock() + NAME_HOLD
            b.Label:SetText(FText(nm))
        end
    end
    local show = (b.Bow or os.clock() < b.Until) and 1 or 0
    if show ~= b.Shown then b.Shown = show b.Label:SetRenderOpacity(show) end
end

function M.Forget() M.Built, M.Fails, M.RetryAt = {}, 0, 0 end

function M.Tick(ctx)
    if os.clock() < (M.Next or 0) then return end
    M.Next = os.clock() + 0.2
    local E = ctx.ById("ammo")
    for i, box in ipairs(E.Instances) do
        if box:IsValid() then
            local key = E.Keys[i]
            local b = M.Built[key]
            if not (b and b.Box:IsValid()) then
                -- 3 tries at most, 10 s apart, as main.lua's parts (MayTry)
                if (M.Fails or 0) < 3 and os.clock() >= (M.RetryAt or 0) then
                    local ok, err = pcall(Build, ctx, box, key)
                    if not ok then
                        M.Fails, M.RetryAt = (M.Fails or 0) + 1, os.clock() + 10
                        ctx.Log("ammo: ring look not built: " .. tostring(err))
                    end
                end
            else
                pcall(Update, b)
            end
        end
    end
end

return M
