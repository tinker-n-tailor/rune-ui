-- The tool bar as tiles (1.5; sketched live in the game, 02-10-2026: "Style is kinda not the same as everything
-- else"). Each slot looks like a spell cooldown tile: the game's black square see-through, a thin gold edge, the
-- slot number and the stack count in Poppins and cream, the durability bar on a see-through track. The slot in
-- use has a bright edge, 2 wide; the game's orange frame goes unseen.
-- The bar (probes 12 and 13, 02-10-2026): WBP_Inventory_QuickAccesBar_C > SlotGridContainer > 8 x
-- WBP_Inventory_QuickAccess_ItemSlot_C: SizeBox_0 > Overlay_31 [InventorySlot, HeaderText (the number)].
-- InventorySlot (WBP_Inventory_ItemSlot_C, the bag's slots are the same class and stay as they are): button >
-- SizeBox_0 > Overlay_31 [ItemImage, EquippedImage, .., DurabilityBar, StackSizeText, ..]. ItemImage's material
-- (MI_Item_Selected) draws the square and the item: "Background Opacity" and "Background Texture Opacity" are
-- its square. EquippedImage is seen (visibility 4) on the slot in use, else collapsed.
-- The game builds a slot new when its item changes, so each step looks at every slot again: a new one is painted
-- whole, a known one costs about twenty calls. main.lua moves the bar as "toolbar" and loads this file with pcall.
-- The edge is an outline, and an outline ignores the opacity of the widgets above it (see cooldowns.lua). While the
-- tool wheel is open, the game sets the bag's main panel, 8 widgets above the bar, to opacity 0 (probes of
-- 03-10-2026): the bar went and our edges stayed. So the edge takes the opacity of every widget from the bar up to
-- the top of the HUD by its own colour, and is hidden at opacity 0.
-- The game draws the edge again only when a call tells it to, and a brush written in place tells it nothing: the
-- bright edge stayed on the slot of the item before, and the edges stayed with the wheel open (play test and
-- probes 5 to 7, 03-10-2026). So each change of an edge ends with two changes of its visibility.

local M = {}

local BACK = 0.32    -- the square's opacity: the cooldown tiles' 32%
local INSET = 3.25   -- the game's square is this much smaller than the slot on each side (screenshot, 02-10-2026)
local TEXT = 11      -- the cooldown tiles' seconds; the game's number is 12
local EVERY = 0.15   -- seconds between two looks: the edge follows the item in hand without a wait to be seen

local function Lin1(c) if c <= 0.04045 then return c / 12.92 end return ((c + 0.055) / 1.055) ^ 2.4 end
local function Lin(r, g, b, a) return { R = Lin1(r), G = Lin1(g), B = Lin1(b), A = a or 1.0 } end
local EDGE = Lin(0.72, 0.57, 0.31, 0.45)    -- #b8924f at 45%, the cooldown tiles' edge
local GOLD = Lin(0.89, 0.72, 0.35, 1.0)     -- #e3b85a, the slot in use
local CREAM = Lin(0.945, 0.902, 0.784)      -- #f1e6c8, the numbers
local TRACK = Lin(0.086, 0.071, 0.051, 0.5) -- #16120d at 50%, behind the durability

M.Slots = {}   -- "instance:index" -> what Paint found in that slot
local Names = nil   -- the material's value names, made on first use
local Logged = {}
local function Once(ctx, key, msg) if not Logged[key] then Logged[key] = true ctx.Log(msg) end end

local function Nm(w) return w:GetFName():ToString() end
local function Ok(w) return w and w:IsValid() end
-- a child by its name; nil when there is none
local function Child(panel, name)
    for i = 0, panel:GetChildrenCount() - 1 do
        local c = panel:GetChildAt(i)
        if Ok(c) and Nm(c) == name then return c end
    end
end

-- a text of the game in the HUD's font, cream, with the soft shadow of our own texts
local function Style(ctx, T)
    if not Ok(T) then return end
    local fi = T.Font
    local font = ctx.Font()
    if font then fi.FontObject = font end
    fi.Size = TEXT
    T:SetFont(fi)
    T:SetColorAndOpacity({ SpecifiedColor = CREAM, ColorUseRule = 0 })
    T:SetShadowOffset({ X = 1, Y = 1 })
    T:SetShadowColorAndOpacity({ R = 0, G = 0, B = 0, A = 0.8 })
end

local function Edge(S, used, op)
    if S.Used == used and S.Op == op then return end
    S.Used, S.Op = used, op
    local c = used and GOLD or EDGE
    local b = S.Edge.Brush
    b.OutlineSettings.Width = used and 2 or 1
    b.OutlineSettings.Color = { SpecifiedColor = { R = c.R, G = c.G, B = c.B, A = c.A * op }, ColorUseRule = 0 }
    S.Edge:SetBrush(b)
    S.Edge:SetVisibility(1)                    -- collapsed and back in one step: the game draws the edge again
    S.Edge:SetVisibility(op > 0.01 and 3 or 2)   -- 3 seen, takes no clicks; 2 hidden
end

-- The opacity of the bar on the screen: its own times that of every widget above it. The widgets are found once
-- for each bar: the parents in a tree, then the widget that holds the tree, up to the top of the HUD.
local Above = {}
local function Opacity(n, bar)
    local C = Above[n]
    if not (C and C.Addr == bar:GetAddress()) then
        C = { Addr = bar:GetAddress() }
        local w = bar
        while Ok(w) and #C < 20 do
            C[#C + 1] = w
            local p = w:GetParent()
            if not Ok(p) then
                local tree = w:GetOuter()
                p = Ok(tree) and tree:GetClass():GetFName():ToString() == "WidgetTree" and tree:GetOuter() or nil
            end
            w = p
        end
        Above[n] = C
    end
    local op = 1
    for _, w in ipairs(C) do
        if not w:IsValid() then Above[n] = nil return 1 end   -- found again at the next look
        op = op * w:GetRenderOpacity()
    end
    return op
end

-- The durability bar keeps the game's colours: its pale tan, and its warning colours. A gold fill was in the
-- sketch; the tan was picked in the game (playtest, 02-10-2026: "They are fine as they are"). Only the track behind
-- the bar changes.

-- One slot, painted whole. W: the slot; ov: its overlay; inv: the game's inner slot. Returns what the steps
-- after it need, or nil while the game has not built the slot's parts yet.
local function Paint(ctx, W, ov, inv)
    local itree = inv.WidgetTree
    local iroot = Ok(itree) and itree.RootWidget
    local box = Ok(iroot) and iroot:GetChildAt(0)
    local iov = Ok(box) and box:GetChildAt(0)
    if not Ok(iov) then return nil end
    local S = { WAddr = W:GetAddress(), InvAddr = inv:GetAddress(), Ov = ov }
    local bar
    for i = iov:GetChildrenCount() - 1, 0, -1 do
        local c = iov:GetChildAt(i)
        if Ok(c) then
            local n = Nm(c)
            if n == "ItemImage" then S.Item = c
            elseif n == "EquippedImage" then S.Eq = c
            elseif n == "DurabilityBar" then bar = c
            elseif n == "StackSizeText" then
                local okT, errT = pcall(Style, ctx, c)
                if not okT then Once(ctx, "style", "tool bar: a text not styled: " .. tostring(errT)) end
            elseif string.find(n, "^RU_Tb") then c:RemoveFromParent() end   -- an edge of ours from an earlier paint
        end
    end
    if not S.Item then return nil end
    local okH, errH = pcall(Style, ctx, Child(ov, "HeaderText"))
    if not okH then Once(ctx, "style", "tool bar: a text not styled: " .. tostring(errH)) end
    if S.Eq then S.Eq:SetRenderOpacity(0.0) end   -- its visibility still says which slot is in use
    if bar then
        pcall(function()
            local dtree = bar.WidgetTree
            local droot = Ok(dtree) and dtree.RootWidget
            local border = Ok(droot) and droot:GetChildAt(0)
            local pb = Ok(border) and border:GetChildAt(0)
            if not Ok(pb) then return end
            -- the bar reads its style in place, so the track changes with no call (in game, 02-10-2026;
            -- this UE4SS has no SetWidgetStyle for it)
            pb.WidgetStyle.BackgroundImage.TintColor = { SpecifiedColor = TRACK, ColorUseRule = 0 }
        end)
    end
    local img = StaticConstructObject(StaticFindObject("/Script/UMG.Image"), itree, ctx.G("RU_TbEdge"))
    local b = img.Brush
    b.DrawAs = 4   -- RoundedBox: an outline with nothing inside, so it covers nothing
    b.TintColor = { SpecifiedColor = { R = 0, G = 0, B = 0, A = 0 }, ColorUseRule = 0 }
    b.OutlineSettings.RoundingType = 0
    b.OutlineSettings.CornerRadii = { X = 0, Y = 0, Z = 0, W = 0 }   -- square, as the game's square under it
    b.OutlineSettings.Width = 1
    b.OutlineSettings.Color = { SpecifiedColor = EDGE, ColorUseRule = 0 }
    img:SetBrush(b)
    img:SetVisibility(3)   -- seen, takes no clicks
    local s = iov:AddChildToOverlay(img)
    s:SetHorizontalAlignment(0)
    s:SetVerticalAlignment(0)
    s:SetPadding({ Left = INSET, Top = INSET, Right = INSET, Bottom = INSET })
    S.Edge, S.Used, S.Iov = img, false, iov
    return S
end

-- A known slot, on every look: the square and the edge of the slot in use. The square's
-- values are written when the material is a new one, and once a second in case the game wrote its own again.
local function Keep(S, now, op)
    local m = S.Item.Brush.ResourceObject
    if Ok(m) then
        local a = m:GetAddress()
        if a ~= S.MatAddr then S.MatAddr, S.MatAt, S.MatOk = a, 0, m:GetClass():GetFName():ToString() == "MaterialInstanceDynamic" end
        if S.MatOk and now >= S.MatAt then
            S.MatAt = now + 1
            m:SetScalarParameterValue(Names.Back, BACK)
            m:SetScalarParameterValue(Names.Tex, 0.0)
        end
    end
    local v = S.Eq and S.Eq:GetVisibility()
    Edge(S, v ~= nil and v ~= 1 and v ~= 2, op)   -- 1 collapsed, 2 hidden
end

-- Known: the same slot, the same inner slot in it, and every part Keep calls still there. A part that the game
-- took out of the slot reads valid until the engine frees it, so the edge is also asked for its parent: that
-- finds a slot whose inner parts the game cleared. A new inner overlay or a new ItemImage alone in a kept slot is
-- not found until the engine frees the old one, about a minute (which parts the game builds new is not known,
-- 02-10-2026).
local function Look(ctx, key, W, now, op)
    if not Ok(W) then M.Slots[key] = nil return end
    local S = M.Slots[key]
    local known = false
    if S and S.WAddr == W:GetAddress() and S.Ov:IsValid() then
        local inv = Child(S.Ov, "InventorySlot")
        if inv and inv:GetAddress() == S.InvAddr and S.Item:IsValid() and S.Edge:IsValid()
            and (not S.Eq or S.Eq:IsValid()) then
            local p = S.Edge:GetParent()
            known = Ok(p) and p:GetAddress() == S.Iov:GetAddress()
        end
    end
    if not known then
        local tree = W.WidgetTree
        local root = Ok(tree) and tree.RootWidget
        local ov = Ok(root) and root:GetChildAt(0)
        local inv = Ok(ov) and Child(ov, "InventorySlot")
        S = inv and Paint(ctx, W, ov, inv) or nil
        M.Slots[key] = S
        if S then M.Painted = (M.Painted or 0) + 1 end
    end
    if S then Keep(S, now, op) end
end

function M.Forget() M.Slots = {} Above = {} end

function M.Tick(ctx)
    local now = os.clock()
    if now < (M.Next or 0) then return end
    M.Next = now + EVERY
    if not Names then Names = { Back = FName("Background Opacity"), Tex = FName("Background Texture Opacity") } end
    for n, bar in ipairs(ctx.ById("toolbar").Instances) do
        if Ok(bar) then
            local tree = bar.WidgetTree
            local grid = Ok(tree) and tree.RootWidget
            if Ok(grid) then
                local okO, op = pcall(Opacity, n, bar)
                if not okO then Once(ctx, "opacity", "tool bar: opacity not read: " .. tostring(op)) op = 1 end
                for i = 0, grid:GetChildrenCount() - 1 do
                    local ok, err = pcall(Look, ctx, n .. ":" .. i, grid:GetChildAt(i), now, op)
                    if not ok then Once(ctx, "slot", "tool bar: a slot not painted: " .. tostring(err)) end
                end
            end
        end
    end
    if M.Painted and not Logged.ready then Once(ctx, "ready", "tool bar: tiles") end
end

return M
