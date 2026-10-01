-- The buffs: the buff list turned into a row, each buff a ring in its own colour, and the drink buff a ring beside
-- the food, water and rest rings. main.lua loads this file with pcall. Its Scan runs once per widget scan; its
-- Tick turns the rings every half second, and at once when a new buff came (NextRings).

local M = {}
-- main.lua's helpers, bound once by Init (see Util in main.lua)
local Log, ById, Uniq, G, ClearOurs, ClassName, FindClass, Asset, SetColor, ImageFromArt, FindMenuArt, MayTry, Failed, CachedTex, Survival
function M.Init(ctx)
    Log, ById, Uniq, G, ClearOurs, ClassName, FindClass = ctx.Log, ctx.ById, ctx.Uniq, ctx.G, ctx.ClearOurs, ctx.ClassName, ctx.FindClass
    Asset, SetColor, ImageFromArt, FindMenuArt = ctx.Asset, ctx.SetColor, ctx.ImageFromArt, ctx.FindMenuArt
    MayTry, Failed, CachedTex, Survival = ctx.MayTry, ctx.Failed, ctx.CachedTex, ctx.Survival
end

---------------------------------------------------------------- the buff count

-- The drink ring (see "the drink buff" below). Declared here: the buff count reads its lists.
local Drinks = { Lists = {}, ListsKey = nil }

-- The buff lists' item count. Reading their entries straight from the lists gave nothing (in-game test,
-- 29-09-2026), but the count is a plain number.
local BuffItems, BuffsLogged = nil, false
local function BuffsChanged()
    local n = 0
    for _, W in ipairs(ById("buffs").Instances) do
        pcall(function()
            local root = W.WidgetTree.RootWidget
            for i = 0, root:GetChildrenCount() - 1 do
                local c = root:GetChildAt(i)
                local ok, k = pcall(function() return c:GetNumItems() end)
                if ok and type(k) == "number" then n = n + k end
            end
        end)
    end
    -- the drink, food and potion buffs beside the food rings sit in lists of their own (probe, 01-10-2026): a
    -- new drink is found at once, not at the next 10 s search (playtest: "it should be transformed instantly")
    -- counted on their own: BuffItems is also the immersive mode's "a new buff came" for the buff row, and eating
    -- or drinking must not bring that row back
    local m = 0
    pcall(function()
        local E = ById("survival")
        local U, k = E.Instances[1], E.Keys[1]
        if not (Survival and U and U:IsValid()) then return end
        if Drinks.ListsKey ~= k then
            Drinks.ListsKey, Drinks.Lists = k, {}
            for _, name in ipairs({ "HydrationBuffListView", "SustenanceBuffListView", "PotionBuffListView" }) do
                local Lv = Survival.Find(U, name)
                if Lv then Drinks.Lists[#Drinks.Lists + 1] = Lv end
            end
            if #Drinks.Lists < 3 then Log("buffs: " .. #Drinks.Lists .. " of the 3 lists by the food rings found") end
        end
        for _, Lv in ipairs(Drinks.Lists) do
            local ok, c = pcall(function() return Lv:GetNumItems() end)
            if ok and type(c) == "number" then m = m + c end
        end
    end)
    local changed = (BuffItems ~= nil and n ~= BuffItems) or (Drinks.Items ~= nil and m ~= Drinks.Items)
    Drinks.Items = m
    if changed and not BuffsLogged then BuffsLogged = true Log("buffs: " .. BuffItems .. " to " .. n .. ", searching at once") end
    BuffItems = n
    return changed
end


---------------------------------------------------------------- buffs in a row

-- The buff list is a ListView. Its direction is fixed when the list is built, so the mod sets it to
-- horizontal and puts the list back into its box, which makes the game build it again sideways.
local BuffRowDone = {}
local function EnsureBuffRow()
    local B = ById("buffs")
    for n, W in ipairs(B.Instances) do
        local k = B.Keys[n]
        if not BuffRowDone[k] then
            BuffRowDone[k] = true
            local ok, err = pcall(function()
                local ov = W.WidgetTree.RootWidget
                local LV = ov:GetChildAt(0)
                local oldSlot = LV.Slot
                local p0 = oldSlot.Padding   -- copied to plain numbers: the old slot goes away with RemoveFromParent
                local h, v = oldSlot.HorizontalAlignment, oldSlot.VerticalAlignment
                local pad = { Left = p0.Left, Top = p0.Top, Right = p0.Right, Bottom = p0.Bottom }
                LV.Orientation = 0   -- horizontal
                pcall(function() LV:SetClipping(0) ov:SetClipping(0) end)
                LV:RemoveFromParent()
                local s = ov:AddChildToOverlay(LV)
                pcall(function() s:SetHorizontalAlignment(h) s:SetVerticalAlignment(v) s:SetPadding(pad) end)
                pcall(function() LV:RegenerateAllEntries() end)
            end)
            if ok then Log("buffs turned into a row") else Log("buff row failed: " .. tostring(err)) end
        end
    end
end

---------------------------------------------------------------- round buffs

-- Each buff entry is: SizeBox > Overlay > [icon, Overlay > [straight bar, title]]. The mod hides the bar
-- and the title, makes the entry square, and puts the ring of food, water and rest under the icon (the pick,
-- 29-09-2026, in place of the ring of dashes): dark back, coloured ring, dark centre. The bar's material holds
-- the time left; the ring shows that share. A buff without a timer (its bar is hidden by the game) gets a full ring.
-- The game's XP ring was tried first (27-09-2026): the row squashed it into an oval and the game drew it white.
local RING_BOX = 50    -- the ring; the row keeps the size of the dashes' box
local BUFF_GAP = 10    -- room between two rings (playtest, 29-09-2026: they nearly touched)
local BUFF_ICON = 28   -- the game's icon in the ring's centre; its picture has an empty edge
-- Centred by the numbers, some of the game's pictures look high: their art sits high in its square (in-game test,
-- 27-09-2026: 3.5 at 32). Others are centred and sat 1.5 units low at 3.5 (the overeating face and the house,
-- a screenshot of 29-09-2026): 2 favours the centred ones. Optical, by picture; units at an icon of 32.
-- The new character's half sun (Fresh Start) is heavy at the bottom and looked low at 2 (playtest, 29-09-2026).
-- The overeating face sat 2 units left and 0.5 low at 2 (measured on a screenshot, 01-10-2026): { X, Y }.
local BUFF_NUDGE = { Default = 2, T_Icon_Sml_FreshStart = 0.5, T_Icon_Sml_Overeating = { X = 2.3, Y = 1.4 } }
local BuffPics = {}   -- the icon pictures already named in the log, once each
local BUFF_ART = { Back = "upkeep_back.png", Half = "upkeep_half.png", Centre = "upkeep_centre.png" }
-- the three pictures: the rings hold them; these handles are only reused while valid, and dropped with the world
local BuffArt = {}
local BuffDeco = {}          -- entry full name -> { W, Right, Left (the ring's halves), Bar, Lit }
local BuffParamLogged = false
-- a buff with no colour of its own: the sketch's #ffd173, as linear light
local C_RING_GOLD = { R = 1.0, G = 0.638, B = 0.168, A = 1.0 }

local function BuffTextures(outer)
    for k, file in pairs(BUFF_ART) do CachedTex(BuffArt, k, outer, "ue4ss/Mods/RuneUI/Art/" .. file) end
    return BuffArt
end

local function DecorateBuff(E)
    local k = E:GetFullName()
    if BuffDeco[k] then return end
    BuffDeco[k] = { W = E }
    if not Survival then return end   -- no ring to borrow: the buff keeps the game's look
    local ok, err = pcall(function()
        local tree = E.WidgetTree
        local box = tree.RootWidget
        local ov = box:GetContent()
        ClearOurs(ov, "RU_RingBox")   -- a ring of ours from an earlier round
        -- the game's two: the bar's Overlay and the icon. Found by class, not place: a decorated entry has
        -- the icon moved to the end.
        local icon, barBox
        for i = 0, ov:GetChildrenCount() - 1 do
            local c = ov:GetChildAt(i)
            if ClassName(c) == "Overlay" then barBox = c else icon = c end
        end
        if not (icon and barBox) then error("icon or bar not found") end
        local bar = barBox:GetChildAt(0)
        local art = BuffTextures(E)
        box:SetWidthOverride(RING_BOX + BUFF_GAP)   -- the ring stays in the middle: half the gap on each side
        box:SetHeightOverride(RING_BOX)
        barBox:SetRenderOpacity(0.0)   -- the straight bar and the title stay alive for the game, just unseen
        pcall(function() E:SetClipping(0) box:SetClipping(0) ov:SetClipping(0) end)   -- the list must not cut the ring
        local ring, right, left = Survival.Ring(tree, Uniq("RU_Ring"), RING_BOX, art, C_RING_GOLD)
        -- the list can give the entry less height than the ring: after leaving a house (in-game test,
        -- 29-09-2026) the dark pictures were squashed and the coloured ring cut. On a canvas the ring keeps its
        -- own size, centred on the entry like the icon.
        local canvas = StaticConstructObject(StaticFindObject("/Script/UMG.CanvasPanel"), tree, G("RU_RingCanvas"))
        local rs = canvas:AddChildToCanvas(ring)
        rs:SetAutoSize(false)
        rs:SetAnchors({ Minimum = { X = 0.5, Y = 0.5 }, Maximum = { X = 0.5, Y = 0.5 } })
        rs:SetAlignment({ X = 0.5, Y = 0.5 })
        rs:SetPosition({ X = 0, Y = 0 })
        rs:SetSize({ X = RING_BOX, Y = RING_BOX })
        local ringBox = StaticConstructObject(StaticFindObject("/Script/UMG.SizeBox"), tree, G("RU_RingBox"))
        ringBox:SetWidthOverride(RING_BOX)
        ringBox:SetHeightOverride(RING_BOX)
        ringBox:SetContent(canvas)
        local cs = ov:AddChildToOverlay(ringBox)
        cs:SetHorizontalAlignment(2) cs:SetVerticalAlignment(2)
        -- the icon goes on top of the ring: an Overlay draws its last child last. Icon and ring both sit on the
        -- entry's centre; top-left with padding put the icon ~4 units high (test of 27-09-2026).
        icon:RemoveFromParent()
        local is = ov:AddChildToOverlay(icon)
        is:SetHorizontalAlignment(2) is:SetVerticalAlignment(2)
        pcall(function() icon:SetDesiredSizeOverride({ X = BUFF_ICON, Y = BUFF_ICON }) end)
        pcall(function() icon:SetRenderTranslation({ X = 0, Y = BUFF_NUDGE.Default * BUFF_ICON / 32 }) end)   -- by picture: UpdateBuffRings
        BuffDeco[k].Right, BuffDeco[k].Left, BuffDeco[k].Bar, BuffDeco[k].Lit = right, left, bar, ""
        BuffDeco[k].Icon = icon
    end)
    if not ok then Log("round buff failed: " .. tostring(err)) end
end

-- Share of time left, 0..1, from the straight bar's material; nil when the buff has no timer
local BuffParam = nil
local function BuffShare(bar)
    local v = bar:GetVisibility()
    if v == 1 or v == 2 then return nil end
    local mid = bar.Brush.ResourceObject
    local vals = {}
    mid.ScalarParameterValues:ForEach(function(_, e)
        local p = e:get()
        vals[p.ParameterInfo.Name:ToString()] = p.ParameterValue
    end)
    if not BuffParamLogged then
        BuffParamLogged = true
        local names = {}
        for n, v in pairs(vals) do table.insert(names, n .. "=" .. string.format("%.2f", v)) end
        Log("buff bar material values: " .. table.concat(names, ", "))
        for n in pairs(vals) do
            local l = string.lower(n)
            if string.find(l, "progress") or string.find(l, "percent") or string.find(l, "fill") then BuffParam = n end
        end
        if not BuffParam then for n in pairs(vals) do BuffParam = BuffParam or n end end
        Log("buff ring reads " .. tostring(BuffParam))
    end
    local v = BuffParam and vals[BuffParam]
    if v == nil then return nil end
    return math.max(0, math.min(1, v))
end

---------------------------------------------------------------- the drink buff

-- The drink buff is not in the buff row: it sits beside the food, water and rest rings, inside their widget.
-- VerticalBox_0 > Overlay_0 [Background, ItemImage, ProgressBarImageBackground, ProgressBarImage] and Overlay_1
-- [TextBackground, DurationText] (probe, 01-10-2026). It gets the buff ring; the game's round pictures and the
-- seconds under it go unseen (playtest, 01-10-2026: the ring shows the time). The icon stays on top.
-- RING: the buff rings' size, as it is a buff (playtest, 01-10-2026). ICON: the drink pictures have wider empty edges
-- than the buffs' (at the buffs' share the art looked small); 36 matches the house's art. LIFT: the game sets
-- the drink 6.5 units below the food rings' centre (measured in game, 01-10-2026); the game's hidden 61-unit
-- pictures still size the entry, so the ring stays centred where the game's was.
-- COLOUR: the water ring's #5fb2dc. Deco: entry full name -> { W, Root, Right, Left, Text, Value, Lit, Most, Last }.
-- One table: main.lua is near Lua's limit of 200 locals.
Drinks.RING, Drinks.ICON, Drinks.LIFT = RING_BOX, 36, 6.5
Drinks.COLOUR, Drinks.Deco = { R = 0.115, G = 0.445, B = 0.716, A = 1.0 }, {}

function Drinks.Decorate(E, k)
    if Drinks.Deco[k] then return end
    Drinks.Deco[k] = { W = E }
    if not Survival then return end
    local ok, err = pcall(function()
        local tree = E.WidgetTree
        local root = tree.RootWidget
        local ov, under = root:GetChildAt(0), root:GetChildAt(1)
        ClearOurs(ov, "RU_Drink")   -- a ring of ours from an earlier round
        local icon, rings = nil, {}
        for i = 0, ov:GetChildrenCount() - 1 do
            local c = ov:GetChildAt(i)
            if c:GetFName():ToString() == "ItemImage" then icon = c else rings[#rings + 1] = c end
        end
        local text = Survival.Find(under, "DurationText")
        if not (icon and text) then error("icon or seconds not found") end
        local ring, right, left = Survival.Ring(tree, Uniq("RU_DrinkRing"), Drinks.RING, BuffTextures(E), Drinks.COLOUR)
        -- the game's rings and seconds go unseen only once ours stands; the seconds are still written, and read
        for _, c in ipairs(rings) do c:SetRenderOpacity(0.0) end
        under:SetRenderOpacity(0.0)
        local ringBox = StaticConstructObject(StaticFindObject("/Script/UMG.SizeBox"), tree, G("RU_DrinkBox"))
        ringBox:SetWidthOverride(Drinks.RING)
        ringBox:SetHeightOverride(Drinks.RING)
        ringBox:SetContent(ring)
        local cs = ov:AddChildToOverlay(ringBox)
        cs:SetHorizontalAlignment(2) cs:SetVerticalAlignment(2)
        -- the icon on top of the ring, as the buffs: an Overlay draws its last child last
        icon:RemoveFromParent()
        local is = ov:AddChildToOverlay(icon)
        is:SetHorizontalAlignment(2) is:SetVerticalAlignment(2)
        pcall(function() icon:SetDesiredSizeOverride({ X = Drinks.ICON, Y = Drinks.ICON }) end)
        root:SetRenderTranslation({ X = 0, Y = -Drinks.LIFT })   -- level with the food rings
        local d = Drinks.Deco[k]
        -- Root: the immersive mode fades it; the entry itself is the F9 element, whose hide and fade use its opacity
        d.Right, d.Left, d.Text, d.Lit, d.Root = right, left, text, "", root
    end)
    if not ok then Log("drink ring failed: " .. tostring(err)) end
end

-- Share of time left, 0..1: the seconds under the ring ("255" or "4:15") over the most seen for this entry.
-- ponytail: a world loaded mid-drink starts at a full ring; the game's ring material may hold the true share.
function Drinks.Share(d)
    local s = d.Text:GetText():ToString()
    local m, sec = string.match(s, "(%d+):(%d+)")
    local left = m and tonumber(m) * 60 + tonumber(sec) or tonumber(string.match(s, "%d+"))
    if not left then return 1 end
    -- a new drink in the same entry (the seconds jump up) starts a full ring, a shorter one too
    if not d.Most or left > (d.Last or 0) + 1 then d.Most = left end
    d.Last = left
    return d.Most > 0 and left / d.Most or 1
end

function Drinks.Update()
    for k, d in pairs(Drinks.Deco) do
        if not (d.W and d.W:IsValid()) then
            Drinks.Deco[k] = nil
        elseif d.Right and not (d.Text:IsValid() and d.Right:IsValid() and d.Left:IsValid()) then
            Drinks.Deco[k] = nil   -- the game rebuilt this entry; it is decorated again on the next scan
        elseif d.Right then
            local okS, share = pcall(Drinks.Share, d)
            d.Value = okS and share or 1
            local key = string.format("%.3f", d.Value)
            if key ~= d.Lit then
                d.Lit = key
                Survival.Turn(d, d.Value)
            end
        end
    end
end


-- from the last widget search, which runs at once when the number of buffs changes (FindAll)
local function FindBuffEntries()
    for _, E in ipairs(FindClass("WBP_HUD_StatusEffectListEntry_C")) do DecorateBuff(E) end
    local list, keys = FindClass("WBP_HUD_DrinkBuffListEntry_C")
    for i, E in ipairs(list) do Drinks.Decorate(E, keys[i]) end
end

local function UpdateBuffRings()
    for k, d in pairs(BuffDeco) do
        if not (d.W and d.W:IsValid()) then
            BuffDeco[k] = nil
        elseif d.Right and not (d.Bar and d.Bar:IsValid() and d.Right:IsValid() and d.Left:IsValid()) then
            BuffDeco[k] = nil   -- the game rebuilt this entry; it is decorated again on the next scan
        elseif d.Right then
            local okS, share = pcall(BuffShare, d.Bar)
            if not okS or not share then share = 1 end   -- no timer: a full ring
            -- the buff's own colour from its bar ("Bar Color 1": poison green, slow yellow, 27-09-2026), already
            -- linear light; a list entry is reused for another buff, so it is read every time. Gold when there is none.
            local on = C_RING_GOLD
            pcall(function()
                d.Bar.Brush.ResourceObject.VectorParameterValues:ForEach(function(_, e)
                    local p = e:get()
                    if p.ParameterInfo.Name:ToString() == "Bar Color 1" then
                        local c = p.ParameterValue
                        on = { R = c.R, G = c.G, B = c.B, A = 1.0 }
                    end
                end)
            end)
            -- the icon's nudge by its picture (BUFF_NUDGE); an entry is reused for another buff, so it is read every time
            pcall(function()
                local pic = d.Icon.Brush.ResourceObject:GetFName():ToString()
                if pic == d.Pic then return end
                d.Pic = pic
                local n = BUFF_NUDGE[pic] or BUFF_NUDGE.Default
                if type(n) ~= "table" then n = { X = 0, Y = n } end
                d.Icon:SetRenderTranslation({ X = n.X * BUFF_ICON / 32, Y = n.Y * BUFF_ICON / 32 })
                if not BuffPics[pic] then BuffPics[pic] = true Log("buff icon: " .. pic) end
            end)
            local key = string.format("%.3f %.2f %.2f %.2f", share, on.R, on.G, on.B)
            if key ~= d.Lit then
                d.Lit = key
                d.Right:SetColorAndOpacity(on)
                d.Left:SetColorAndOpacity(on)
                Survival.Turn(d, share)
            end
        end
    end
end


-- once per widget scan (main.lua)
function M.Scan() EnsureBuffRow() FindBuffEntries() end

M.NextRings = 0
function M.Tick()
    local now = os.clock()
    if now > M.NextRings then M.NextRings = now + 0.5 UpdateBuffRings() Drinks.Update() end
end

-- a new world or a player restart: every handle into the old HUD is dropped
function M.Forget(sameWorld)
    BuffItems = nil
    BuffDeco, BuffArt, Drinks.Deco, Drinks.Lists, Drinks.ListsKey, Drinks.Items = {}, {}, {}, {}, nil, nil
    if not sameWorld then BuffRowDone = {} end   -- the old world's lists are gone; a restart keeps the row
    M.Items = nil
end

-- read by main.lua: the count changed since the last call, the count, and the drink rings (the immersive mode)
function M.Changed() local c = BuffsChanged() M.Items = BuffItems return c end
M.Drinks = Drinks

return M
