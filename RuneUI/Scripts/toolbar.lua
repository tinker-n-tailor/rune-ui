-- The tool bar as tiles. Each slot looks like a spell cooldown tile: the game's black square see-through, a thin gold
-- edge, the slot number and the stack count in Poppins and cream, the durability bar on a see-through track.
-- The slot in use has a bright edge, 2 wide; the game's orange frame goes unseen.
-- The bar (probes 12 and 13, 02-10-2026): WBP_Inventory_QuickAccesBar_C > SlotGridContainer > 8 x
-- WBP_Inventory_QuickAccess_ItemSlot_C: SizeBox_0 > Overlay_31 [InventorySlot, HeaderText (the number)].
-- InventorySlot (WBP_Inventory_ItemSlot_C, the bag's slots are the same class and stay as they are): button >
-- SizeBox_0 > Overlay_31 [ItemImage, EquippedImage, .., DurabilityBar, StackSizeText, ..]. ItemImage's material
-- (MI_Item_Selected) draws the square and the item: "Background Opacity" and "Background Texture Opacity" are
-- its square. EquippedImage is seen (visibility 4) on the slot in use, else collapsed.
-- The game builds a slot new when its item changes, so every slot is proved again about once a second (one slot in
-- each look): a new one is painted whole. A known slot costs the checks that its parts are still alive, and one
-- read of the equipped mark. main.lua moves the bar as "toolbar" and loads this file with pcall.
-- The edge is an outline, and an outline ignores the opacity of the widgets above it (see cooldowns.lua). While the
-- tool wheel is open, the game sets the bag's main panel, 8 widgets above the bar, to opacity 0 (probes of
-- 03-10-2026): the bar went and our edges stayed. So the edge takes the opacity of every widget from the bar up to
-- the top of the HUD by its own colour, and is hidden at opacity 0.
-- The game draws the edge again only when a call tells it to, and a brush written in place tells it nothing: the
-- bright edge stayed on the slot of the item before, and the edges stayed with the wheel open (probes of
-- 03-10-2026). So each change of an edge ends with two changes of its visibility.

local M = {}

local BACK = 0.32    -- the square's opacity: the cooldown tiles' 32%
local INSET = 3.25   -- the game's square is this much smaller than the slot on each side (screenshot, 02-10-2026)
local TEXT = 11      -- the cooldown tiles' seconds; the game's number is 12
local EVERY = 0.15   -- seconds between two looks: the edge follows the item in hand without a wait to be seen
local PROVE = 7      -- looks between two proofs of one slot, about a second: the structure, and the material's values
local OPACITY = 0.25 -- seconds between two reads of the opacity above the bar

local function Lin1(c) if c <= 0.04045 then return c / 12.92 end return ((c + 0.055) / 1.055) ^ 2.4 end
local function Lin(r, g, b, a) return { R = Lin1(r), G = Lin1(g), B = Lin1(b), A = a or 1.0 } end
local EDGE = Lin(0.72, 0.57, 0.31, 0.45)    -- #b8924f at 45%, the cooldown tiles' edge
local GOLD = Lin(0.89, 0.72, 0.35, 1.0)     -- #e3b85a, the slot in use
local CREAM = Lin(0.945, 0.902, 0.784)      -- #f1e6c8, the numbers
local TRACK = Lin(0.086, 0.071, 0.051, 0.5) -- #16120d at 50%, behind the durability

M.Slots = {}   -- bar number -> place in the bar (0 to 7) -> what Paint found in that slot
local Bars = {}      -- bar number -> what the bar keeps between looks (Refresh, Tick)
local Names = nil   -- the material's value names, made on first use
local Logged = {}
local function Once(ctx, key, msg) if not Logged[key] then Logged[key] = true ctx.Log(msg) end end

local function Nm(w) return w:GetFName():ToString() end
local function Ok(w) return w and w:IsValid() end
-- a child by its name, and its index; nil when there is none
local function Child(panel, name)
    for i = 0, panel:GetChildrenCount() - 1 do
        local c = panel:GetChildAt(i)
        if Ok(c) and Nm(c) == name then return c, i end
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
    local c = used and GOLD or EDGE
    local b = S.Edge.Brush
    b.OutlineSettings.Width = used and 2 or 1
    b.OutlineSettings.Color = { SpecifiedColor = { R = c.R, G = c.G, B = c.B, A = c.A * op }, ColorUseRule = 0 }
    S.Edge:SetBrush(b)
    S.Edge:SetVisibility(1)                    -- collapsed and back in one step: the game draws the edge again
    S.Edge:SetVisibility(op > 0.01 and 3 or 2)   -- 3 seen, takes no clicks; 2 hidden
    S.Used, S.Op = used, op   -- stored last: after a call that failed, the next look does the change again
end

-- The opacity of the bar on the screen: its own times that of every widget above it. The widgets are found once
-- for each bar: the parents in a tree, then the widget that holds the tree, up to the top of the HUD. Returns nil
-- when one of them is gone: the chain is found again at the next read.
local function Opacity(B, bar)
    local C = B.Above
    if not C then
        C = {}
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
        B.Above = C
    end
    local op = 1
    for j = 1, #C do
        local w = C[j]
        if not w:IsValid() then B.Above = nil return nil end
        op = op * w:GetRenderOpacity()
    end
    return op
end

-- The durability bar keeps the game's colours: its pale tan, and its warning colours. Only the track behind
-- the bar changes.

-- One slot, painted whole. W: the slot; ov: its overlay; inv: the game's inner slot, idx its place in ov. Returns
-- what the steps after it need, or nil while the game has not built the slot's parts yet.
local function Paint(ctx, W, ov, inv, idx)
    local itree = inv.WidgetTree
    local iroot = Ok(itree) and itree.RootWidget
    local box = Ok(iroot) and iroot:GetChildAt(0)
    local iov = Ok(box) and box:GetChildAt(0)
    if not Ok(iov) then return nil end
    local S = { WAddr = W:GetAddress(), InvAddr = inv:GetAddress(), InvIdx = idx, Ov = ov }
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
    S.Edge, S.Used, S.Iov, S.IovAddr = img, false, iov, iov:GetAddress()
    return S
end

-- A known slot, on every look: the edge of the slot in use, and the material of the square. The material is read at
-- every look (a struct and an object made for each read): a new item brings a new material, and with a read once a
-- second the game's dark square showed for up to a second (seen in the game, 09-10-2026). Its values are written
-- when the material is a new one, and once a second in case the game wrote its own again. turn: this look is the
-- slot's turn.
local function Keep(S, turn, op)
    local m = S.Item.Brush.ResourceObject
    if Ok(m) then
        local a = m:GetAddress()
        local new = a ~= S.MatAddr
        if new then S.MatAddr, S.MatOk = a, m:GetClass():GetFName():ToString() == "MaterialInstanceDynamic" end
        if S.MatOk and (new or turn) then
            m:SetScalarParameterValue(Names.Back, BACK)
            m:SetScalarParameterValue(Names.Tex, 0.0)
        end
    end
    local v = S.Eq and S.Eq:GetVisibility()
    Edge(S, v ~= nil and v ~= 1 and v ~= 2, op)   -- 1 collapsed, 2 hidden
end

-- Held: every part that Keep calls is alive. This is the check of each look, and it costs one call per part.
local function Held(S)
    return S.Ov:IsValid() and S.Item:IsValid() and S.Edge:IsValid() and (not S.Eq or S.Eq:IsValid())
end

-- Proved: the same slot, the same inner slot in it, and every part Keep calls still there. A part that the game
-- took out of the slot reads valid until the engine frees it, so the edge is also asked for its parent: that
-- finds a slot whose inner parts the game cleared. A new inner overlay or a new ItemImage alone in a kept slot is
-- not found until the engine frees the old one, about a minute (which parts the game builds new is not known,
-- 02-10-2026). This runs once a second for each slot, and at once for a slot that Held does not pass.
-- The inner slot is first looked for where it was; only when it is not there does the walk by name run.
local function Look(ctx, grid, slots, i)
    local W = grid:GetChildAt(i)
    if not Ok(W) then slots[i] = nil return end
    local S = slots[i]
    local known = false
    if S and S.WAddr == W:GetAddress() and S.Ov:IsValid() then
        local inv, idx = S.Ov:GetChildAt(S.InvIdx), S.InvIdx
        if not (Ok(inv) and inv:GetAddress() == S.InvAddr) then inv, idx = Child(S.Ov, "InventorySlot") end
        if inv and inv:GetAddress() == S.InvAddr and S.Item:IsValid() and S.Edge:IsValid()
            and (not S.Eq or S.Eq:IsValid()) then
            S.InvIdx = idx
            local p = S.Edge:GetParent()
            known = Ok(p) and p:GetAddress() == S.IovAddr
        end
    end
    if not known then
        local tree = W.WidgetTree
        local root = Ok(tree) and tree.RootWidget
        local ov = Ok(root) and root:GetChildAt(0)
        local inv, idx
        if Ok(ov) then inv, idx = Child(ov, "InventorySlot") end
        S = inv and Paint(ctx, W, ov, inv, idx) or nil
        slots[i] = S
        if S then M.Painted = (M.Painted or 0) + 1 end
    end
end

-- One slot of a bar, on one look. turn: the slot is proved on this look.
local function Visit(ctx, B, i, turn)
    local slots = B.Slots
    local S = slots[i]
    if turn or (S and not Held(S)) then
        Look(ctx, B.Grid, slots, i)
        S = slots[i]
    end
    if S then Keep(S, turn, B.Op) end
end

-- The grid of the bar, how many slots it has, and whether it is the bar of the last look. A new bar is proved whole.
local function Refresh(B, bar)
    local addr = bar:GetAddress()
    if addr ~= B.Addr then B.Addr, B.Above, B.OpAt, B.Fresh = addr, nil, 0, true end
    local tree = bar.WidgetTree
    local grid = Ok(tree) and tree.RootWidget
    B.Grid = Ok(grid) and grid or nil
    B.Count = B.Grid and B.Grid:GetChildrenCount() or 0
end

function M.Forget() M.Slots = {} Bars = {} end

-- The slot's turn comes once in PROVE looks, and a slot is proved at once only when a part of it stopped being alive.
-- The grid is a handle from a property: it is read again when the engine freed it (Ok), not only on the bar's turn.
-- The bar is looked at in the bag too: it sits in the bag while the bag is open (apply.lua), and a slot the game
-- builds there gets its look at once.
function M.Tick(ctx)
    local now = os.clock()
    if now < (M.Next or 0) then return end
    M.Next = now + EVERY
    if not Names then Names = { Back = FName("Background Opacity"), Tex = FName("Background Texture Opacity") } end
    for n, bar in ipairs(ctx.ById("toolbar").Instances) do
        if Ok(bar) then
            local B = Bars[n]
            if not B then
                B = { Slots = {}, K = 0, OpAt = 0, Op = 1, Count = 0, Fresh = true }
                Bars[n], M.Slots[n] = B, B.Slots
            end
            local k = B.K
            B.K = (k + 1) % PROVE
            if k == 0 or not Ok(B.Grid) then
                local okR, errR = pcall(Refresh, B, bar)
                if not okR then Once(ctx, "bar", "tool bar: the bar not read: " .. tostring(errR)) B.Grid = nil end
            end
            if now >= B.OpAt then
                B.OpAt = now + OPACITY
                local okO, op = pcall(Opacity, B, bar)
                if not okO then Once(ctx, "opacity", "tool bar: opacity not read: " .. tostring(op)) B.Op = 1
                elseif op then B.Op = op
                else B.OpAt = 0 end
            end
            if Ok(B.Grid) then
                local fresh = B.Fresh
                for i = 0, B.Count - 1 do
                    local ok, err = pcall(Visit, ctx, B, i, fresh or i % PROVE == k)
                    if not ok then Once(ctx, "slot", "tool bar: a slot not painted: " .. tostring(err)) end
                end
                if B.Count > 0 then B.Fresh = nil end
            end
        end
    end
    if M.Painted then Once(ctx, "ready", "tool bar: tiles") end
end

return M
