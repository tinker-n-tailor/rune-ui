-- The item pick-ups: the rows of the list at the right edge in the HUD's look. The game's row is a dark band with
-- a gold line above and below, in the game's title font, the count in red. Here: no band, the HUD font, the
-- letters' shadow (letters.lua), the count in gold.
-- A row (probe of 02-10-2026), WBP_ItemPickups_Item_C: SizeBox > Overlay > [SizeBox > the "new item" sparks,
-- CommonLazyImage (the band), Overlay > [the icon, its highlight, InventoryCount], VerticalBox > [HorizontalBox >
-- [ItemText, Spacer, ItemCountText], NewItemText]]. The texts are WBP_DomTextBlock_C.
-- The game keeps a few rows and uses them again, so a row is styled once, by its full name. The count's colour is
-- looked at on every step: the game may write its red again.
-- A new item: its row matches the others. The sparks (SizeBox_2) keep only the two streaks: embers.lua switches the
-- loose sparks off on the row's Niagara component; render opacity does not touch them (proven in the game). The
-- row is tried on each look until that is done. "NEW MATERIAL !" gets a little room under the name. The game's animation for a new item
-- (InAnimationNewMaterial) tints that word near black for 2.4 s, then light (the game's files). Its colour keys all
-- get the last one, once, in the animation itself (probe 54), so the word is light from the start. Its alpha keys
-- too: the word does not fade in late and does not blink.
-- main.lua moves the list as "pickups" and loads this file with pcall, so an error here leaves the rest running.

local M = {}

local OFFSET, SHADE = { X = 1.5, Y = 1.5 }, { R = 0, G = 0, B = 0, A = 0.85 }   -- as letters.lua
local GOLD = { R = 1.0, G = 0.638, B = 0.168 }   -- #ffd173, as linear light
local EVERY = 0.5   -- seconds between two looks
local GAP = 3       -- units of room above "NEW MATERIAL !"
local NEWCOLOUR = "/Game/UI/Notifications/ItemPickups/WBP_ItemPickups_Item.WBP_ItemPickups_Item_C:InAnimationNewMaterial_INST"
    .. ".InAnimationNewMaterial.MovieSceneColorTrack_1.MovieSceneColorSection_0"

M.Rows = {}   -- full name -> { W, Count }

local function Ok(w) return w and w:IsValid() end

-- the row's band unseen, its texts in the HUD font with the shadow; returns the count's text
local function Style(ctx, W)
    local ov = W.WidgetTree.RootWidget:GetChildAt(0)
    local count
    local function Text(T)
        local fi = T.Font
        local font = ctx.Font()
        if font then fi.FontObject = font T:SetFont(fi) end
        T:SetShadowOffset(OFFSET)
        T:SetShadowColorAndOpacity(SHADE)
        local n = T:GetFName():ToString()
        if n == "ItemCountText" then count = T end
        if n == "NewItemText" then
            local p = T.Slot.Padding
            T.Slot:SetPadding({ Left = p.Left, Top = GAP, Right = p.Right, Bottom = p.Bottom })
        end
    end
    local function Walk(P, depth)
        if depth > 6 or not Ok(P) then return end
        local c = P:GetClass():GetFName():ToString()
        if c == "WBP_DomTextBlock_C" then Text(P) return end
        if string.find(c, "^WBP_") then return end   -- the icon's own widget
        local ok, n = pcall(function() return P:GetChildrenCount() end)
        if ok and type(n) == "number" then for i = 0, n - 1 do Walk(P:GetChildAt(i), depth + 1) end end
    end
    for i = 0, ov:GetChildrenCount() - 1 do
        local c = ov:GetChildAt(i)
        if Ok(c) and c:GetClass():GetFName():ToString() == "CommonLazyImage" then
            c:SetRenderOpacity(0.0)
        else Walk(c, 1) end
    end
    return count
end

-- the colour keys of the new item's animation, each set to the last one; true when done
local function LightNewWord()
    local sec = StaticFindObject(NEWCOLOUR)
    if not Ok(sec) then return false end
    for _, c in ipairs({ "RedCurve", "GreenCurve", "BlueCurve", "AlphaCurve" }) do
        local v = sec[c].Values
        for i = 1, #v - 1 do v[i].Value = v[#v].Value end
    end
    return true
end

-- gold again when the game wrote its own colour, the game's alpha kept
local function Gold(T)
    local c = T.ColorAndOpacity.SpecifiedColor
    if math.abs(c.R - GOLD.R) > 0.01 or math.abs(c.G - GOLD.G) > 0.01 or math.abs(c.B - GOLD.B) > 0.01 then
        T:SetColorAndOpacity({ SpecifiedColor = { R = GOLD.R, G = GOLD.G, B = GOLD.B, A = c.A }, ColorUseRule = 0 })
    end
end

-- a new world can load the animation anew; its first error is logged again
function M.Forget() M.Rows, M.Lit, M.Logged, M.Embers = {}, nil, nil, nil end

function M.Tick(ctx)
    local now = os.clock()
    if now < (M.Next or 0) then return end
    M.Next = now + EVERY
    local list, keys = ctx.Find("WBP_ItemPickups_Item_C")
    for i, W in ipairs(list) do
        local k = keys[i]
        local r = M.Rows[k]
        if not r and Ok(W) then
            local ok, res = pcall(Style, ctx, W)
            if ok then r = { W = W, Count = res } M.Rows[k] = r  -- only a styled row is kept: one that failed is tried again at the next look
            elseif not M.Logged then M.Logged = true ctx.Log("pick-ups: row not styled: " .. tostring(res)) end
        end
        if not M.Lit then
            local okL, lit = pcall(LightNewWord)
            if okL then M.Lit = lit elseif not M.Logged then M.Logged = true ctx.Log("pick-ups: new word not lit: " .. tostring(lit)) end
        end
        if Ok(W) and ctx.Embers then
            M.Embers = M.Embers or ctx.Embers.New()
            ctx.Embers.Quiet(ctx, M.Embers, "pick-ups", W, k)
        end
        if r and Ok(r.Count) then pcall(Gold, r.Count) end
    end
end

return M
