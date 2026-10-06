-- The buffs: the buff list turned into a row, each buff its icon with the game's thin bar under it, and the drink,
-- food and potion buffs as rings beside the food, water and rest rings. main.lua loads this file with pcall.
-- Scan runs once per widget scan. Tick turns the drink rings and gives each buff's shadow its picture every half
-- second, and at once when a new buff came (NextRings).

local M = {}
-- main.lua's helpers, bound once by Init (see Util in main.lua)
local Log, ById, Uniq, G, ClearOurs, ClassName, FindClass, CachedTex, Survival
function M.Init(ctx)
    Log, ById, Uniq, G, ClearOurs, ClassName, FindClass = ctx.Log, ctx.ById, ctx.Uniq, ctx.G, ctx.ClearOurs, ctx.ClassName, ctx.FindClass
    CachedTex, Survival = ctx.CachedTex, ctx.Survival
end

---------------------------------------------------------------- the buff count

-- The drink ring (see "the drink buff" below). Declared here: the buff count reads its lists.
local Drinks = { Lists = {}, ListsKey = nil }

-- The buff lists' item count. Reading their entries straight from the lists gave nothing (29-09-2026), but the
-- count is a plain number.
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
    -- the drink, food and potion buffs beside the food rings sit in lists of their own (probe, 01-10-2026). They are
    -- counted on their own: BuffItems is the count of the buff row, and eating or drinking must not change it. A new
    -- drink is found at once, not at the next 10 s search.
    local m = 0
    pcall(function()
        local E = ById("survival")
        local U, k = E.Instances[1], E.Keys[1]
        if not (Survival and U and U:IsValid()) then return end
        if Drinks.ListsKey ~= k then
            Drinks.ListsKey, Drinks.Lists = k, {}
            for _, name in ipairs({ "HydrationBuffListView", "SustenanceBuffListView", "PotionBuffListView" }) do
                local Lv = Survival.Find(U, name)
                if Lv then
                    Drinks.Lists[#Drinks.Lists + 1] = Lv
                    -- each list cuts at its own box (clipping 1, probe 12): a ring moved far in F9 was cut (02-10-2026)
                    local okC, errC = pcall(function() Lv:SetClipping(0) end)
                    if not okC then Log("buffs: " .. name .. " still cuts: " .. tostring(errC)) end
                end
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

---------------------------------------------------------------- buffs under the bars

-- Each buff entry is: SizeBox > Overlay > [icon, Overlay > [ProgressBarImage, TitleText]]. The buff is its icon with
-- the game's thin bar close under it, and no title: it sits under the bars and looks like one of them. The game fills
-- the bar, gives it the buff's colour, and hides it for a buff without a timer, so the mod only places it (and reads
-- its number: BuffFill). The hidden bar holds a test pink (probe 13, 02-10-2026).
-- The icon stands bare on the world, and on grass by day it was hard to read: a dark copy of it sits behind it, as
-- the letters' shadow (letters.lua).
local BUFF_BOX = { W = 46, H = 50 }     -- one entry of the row
local BUFF_ICON = 42                    -- the game's icon; its picture has a wide empty edge
local BUFF_BAR = { W = 26, H = 4 }      -- as wide as the icon's art
local BUFF_LIFT, BUFF_BAR_UP = -4, -6   -- the icon and the bar, both moved up: a small gap between the two
local BuffPics = {}   -- the icon pictures already named in the log, once each
local BUFF_SHADE, BUFF_SHADE_OFF = { R = 0, G = 0, B = 0, A = 0.85 }, 1.5
local BuffDeco = {}   -- entry full name -> { W, Box, Icon, Bar, Shade, Pic, Over, Positive, Closed }
local NO_PAD = { Left = 0, Top = 0, Right = 0, Bottom = 0 }

-- The shadow takes the icon's picture. An entry is reused for another buff, so the picture is read every time. The
-- game loads it late: while the icon has none, the shadow is unseen. Pic is written last: a set that fails is tried again.
local function ShadeBuff(d)
    local tex = d.Icon.Brush.ResourceObject
    if not (tex and tex:IsValid()) then
        if d.Pic then d.Pic = nil d.Shade:SetRenderOpacity(0.0) end
        return
    end
    local pic = tex:GetFName():ToString()
    if pic == d.Pic then return end
    d.Shade:SetRenderOpacity(0.0)   -- a set that fails must not leave the last buff's shadow under this icon
    d.Shade:SetBrushFromTexture(tex, false)
    d.Shade:SetRenderOpacity(d.Closed and 0.0 or 1.0)   -- PlaceBuff decides while the entry is closed
    d.Pic = pic
    if not BuffPics[pic] then BuffPics[pic] = true Log("buff icon: " .. pic) end
end

-- The share of time left, from the bar's material. A buff without a timer has its bar hidden, and the game still
-- writes the number: 1 while the buff is on, 0 when it is over (Encumbered and Sheltered, watched in game,
-- 03-10-2026). So the hidden bar is read too: the weight icon stayed after a death with an empty bag.
local function BuffFill(bar)
    local mid = bar.Brush.ResourceObject
    if not (mid and mid:IsValid()) then return nil end
    local f
    mid.ScalarParameterValues:ForEach(function(_, e)
        local p = e:get()
        if p.ParameterInfo.Name:ToString() == "Fill" then f = p.ParameterValue end
    end)
    return f
end

-- The game keeps a buff that is over in its list: the poison's entry stayed, its bar shown and empty, long after the
-- poison ended (probes 29 to 32, 02-10-2026). An empty bar means the buff is over, also the hidden bar of a buff
-- without a timer (BuffFill): the entry goes unseen and 1 unit wide, so the row closes. It stays shown for the game,
-- which fills the bar again when the buff comes back; then the entry is back. An entry is reused for another buff, so
-- the bar is read every time.
-- One read is enough: with two, the old poison showed for a second each time the game built its list again.
-- The game can show the entry again while the buff is still over (the old poison squeezed into its 1 unit, a thin
-- mark between two buffs, 02-10-2026), so an entry that is over is made unseen on every look.
-- The immersive mode: a debuff is a warning and shows the whole time it lasts. A good buff shows when IT
-- arrives, stays for the wait, and fades; it comes back with the bars. immersive.lua keeps the time and the fade and
-- tells each good entry its level (SetLevel). The game does not mark a buff as good or bad (probe, 04-10-2026), so
-- the mod holds the names of the good ones. Everything else counts as a debuff, also an effect the mod does not know
-- and an entry whose data cannot be read: one icon too many is better than a missed warning.
-- A good buff arrives when its name was not on at the last look: a new buff, an entry the game reuses for another
-- buff, or a buff that comes back after it was over (the game keeps Sheltered's entry and flips its fill from 0 to 1,
-- with no change of the count). A buff that stays on, or an entry built again for it, does not arrive again.
local POSITIVE = { STATUS_EFFECT_Cosiness = true, STATUS_EFFECT_Sheltered = true, STATUS_EFFECT_WellRested = true,
    STATUS_EFFECT_Prayer = true }
local OverPics = {}
local Present, Next = {}, {}   -- the names of the buffs that are on: at the last full look, and in this one
local ClosedLogged = false

-- The name of the buff in the entry, or nil. An entry is reused for another buff, so the name is read every look. A
-- call on an object that wraps null crashes the game and pcall does not catch it: IsValid comes first.
local function BuffName(d)
    local ok, name = pcall(function()
        local data = d.W.StatusEffectData
        if data and data:IsValid() then return data:GetFName():ToString() end
    end)
    return ok and name or nil
end

-- Whether every widget of the entry is still there. The game can free an entry between two looks, and a call on a
-- freed object crashes the game: whatever writes outside the look checks this first.
local function Alive(d)
    return d.W:IsValid() and (not d.Icon or (d.Box:IsValid() and d.Icon:IsValid() and d.Bar:IsValid() and d.Shade:IsValid()))
end

-- The one place that decides how an entry shows, from what the look found (Over, Positive) and the level that
-- immersive.lua gave (Share, 1 when none). An entry that is over, or a good buff that is gone, is closed: 1 unit
-- wide, and its icon, bar and shadow unseen as well, as the game can show the entry again by its own animation
-- and the icon would stand in the 1 unit as a thin line (clipping is off). What is decided is written once; the
-- flag comes after the call, so a call that fails is tried again. A closed entry is also read every look.
local function PlaceBuff(d)
    local closed = d.Over or (d.Positive and (d.Share or 1) <= 0)
    if closed ~= (d.Closed or false) then
        d.Box:SetWidthOverride(closed and 1 or BUFF_BOX.W)
        local part = closed and 0.0 or 1.0
        d.Icon:SetRenderOpacity(part)
        d.Bar:SetRenderOpacity(part)
        d.Shade:SetRenderOpacity((not closed and d.Pic) and 1.0 or 0.0)
        d.Closed = closed
    end
    local o = d.Over and 0.0 or (d.Positive and (d.Share or 1) or 1.0)
    if o ~= d.Op then
        d.W:SetRenderOpacity(o)
        d.Op = o
    end
    if closed and d.W:GetRenderOpacity() > 0 then
        if not ClosedLogged then ClosedLogged = true Log("buff entry shown again by the game while closed") end
        d.W:SetRenderOpacity(0.0)
    end
end

-- the look, twice a second: what the entry holds now, then where it stands
local function LookAtBuff(d)
    local f = BuffFill(d.Bar)
    local over = f ~= nil and f <= 0.0005
    if over ~= (d.Over or false) then
        d.Over = over
        -- once per picture: a buff that the game never fills would stay unseen, and this line names it
        if over and d.Pic and not OverPics[d.Pic] then OverPics[d.Pic] = true Log("buff over, icon unseen: " .. d.Pic) end
    end
    local name = BuffName(d)
    d.Positive = POSITIVE[name] == true
    d.Name = name
    if name and not over then
        if d.Positive and not Present[name] then d.Arrivals = (d.Arrivals or 0) + 1 end
        Next[name] = true
    end
    PlaceBuff(d)
end

local function DecorateBuff(E)
    local k = E:GetFullName()
    if BuffDeco[k] then return end
    BuffDeco[k] = { W = E }
    local ok, err = pcall(function()
        local box = E.WidgetTree.RootWidget
        local ov = box:GetContent()
        ClearOurs(ov, "RU_BuffShade")   -- a shadow of ours from an earlier round
        -- the game's two: the bar's Overlay and the icon, by class
        local icon, barBox
        for i = 0, ov:GetChildrenCount() - 1 do
            local c = ov:GetChildAt(i)
            if ClassName(c) == "Overlay" then barBox = c else icon = c end
        end
        local bar, title
        for i = 0, (barBox and barBox:GetChildrenCount() or 0) - 1 do
            local c = barBox:GetChildAt(i)
            local n = c:GetFName():ToString()
            if n == "ProgressBarImage" then bar = c elseif n == "TitleText" then title = c end
        end
        if not (icon and bar and title) then error("icon, bar or title not found") end
        box:SetWidthOverride(BUFF_BOX.W)
        box:SetHeightOverride(BUFF_BOX.H)
        E:SetRenderOpacity(1.0)   -- an entry that LookAtBuff left unseen in an earlier round, with its parts
        icon:SetRenderOpacity(1.0)
        bar:SetRenderOpacity(1.0)
        -- the list can give the entry less height than its box (after leaving a house, 29-09-2026): nothing cuts it
        pcall(function() E:SetClipping(0) box:SetClipping(0) ov:SetClipping(0) end)
        title:SetRenderOpacity(0.0)   -- alive for the game, just unseen
        local function Place(W, v)    -- centred; at the middle (2) or the bottom (3) of its box
            local s = W.Slot
            s:SetHorizontalAlignment(2) s:SetVerticalAlignment(v) s:SetPadding(NO_PAD)
        end
        Place(barBox, 3) Place(bar, 3)
        local shade = StaticConstructObject(StaticFindObject("/Script/UMG.Image"), E.WidgetTree, G("RU_BuffShade"))
        shade:SetColorAndOpacity(BUFF_SHADE)
        shade:SetRenderOpacity(0.0)   -- an Image without a picture is a plain box
        -- the shadow, then the icon on top of it: an Overlay draws its last child last
        ov:AddChildToOverlay(shade)
        icon:RemoveFromParent()
        ov:AddChildToOverlay(icon)
        Place(shade, 2) Place(icon, 2)
        shade:SetDesiredSizeOverride({ X = BUFF_ICON, Y = BUFF_ICON })
        shade:SetRenderTranslation({ X = BUFF_SHADE_OFF, Y = BUFF_LIFT + BUFF_SHADE_OFF })
        icon:SetDesiredSizeOverride({ X = BUFF_ICON, Y = BUFF_ICON })
        icon:SetRenderTranslation({ X = 0, Y = BUFF_LIFT })
        bar:SetDesiredSizeOverride({ X = BUFF_BAR.W, Y = BUFF_BAR.H })
        bar:SetRenderTranslation({ X = 0, Y = BUFF_BAR_UP })
        local d = BuffDeco[k]
        d.Box, d.Icon, d.Bar, d.Shade = box, icon, bar, shade
        pcall(ShadeBuff, d)
        pcall(LookAtBuff, d)   -- at once: after a respawn the poison that ended must not show until the next look
    end)
    if not ok then Log("buff under the bars failed: " .. tostring(err)) end
end

---------------------------------------------------------------- the drink buff

-- The drink buff is not in the buff row: it sits beside the food, water and rest rings, inside their widget.
-- VerticalBox_0 > Overlay_0 [Background, ItemImage, ProgressBarImageBackground, ProgressBarImage] and Overlay_1
-- [TextBackground, DurationText] (probe, 01-10-2026). It gets the ring of food, water and rest, smaller: dark back,
-- coloured ring, dark centre. The game's round pictures and the seconds under it go unseen, as the ring shows the
-- time. The icon stays on top.
-- ICON: the drink pictures have wide empty edges. LIFT: the game sets
-- the drink 6.5 units below the food rings' centre (measured in game, 01-10-2026); the game's hidden 61-unit
-- pictures still size the entry, so the ring stays centred where the game's was.
-- Deco: entry full name -> { W, Root, Right, Left, Text, Value, Lit, Most, Last }.
-- The food and potion buffs sit in the same place, in lists of their own, and their entries have the same tree
-- (probe 11, 01-10-2026), so they get the same ring. COLOURS, by the entry's class: a drink in the water
-- ring's #5fb2dc, a food in the food ring's #78c265, a potion in gold #ffd173, as it has no ring of its
-- own. All as linear light. At most 2 drinks, 3 foods and 1 potion at once (the game's wiki, 01-10-2026).
Drinks.RING, Drinks.ICON, Drinks.LIFT = 50, 36, 6.5
Drinks.Deco = {}
Drinks.COLOURS = {
    WBP_HUD_DrinkBuffListEntry_C = { R = 0.115, G = 0.445, B = 0.716, A = 1.0 },
    WBP_HUD_FoodBuffListEntry_C = { R = 0.188, G = 0.540, B = 0.130, A = 1.0 },
    WBP_HUD_PotionBuffListEntry_C = { R = 1.0, G = 0.638, B = 0.168, A = 1.0 } }
-- the ring's three pictures: the rings hold them; these handles are only reused while valid, and dropped with the world
local RING_ART = { Back = "upkeep_back.png", Half = "upkeep_half.png", Centre = "upkeep_centre.png" }
local RingArt = {}
local function RingTextures(outer)
    for k, file in pairs(RING_ART) do CachedTex(RingArt, k, outer, (RUNEUI_DIR or "ue4ss/Mods/RuneUI/") .. "Art/" .. file) end
    return RingArt
end

function Drinks.Decorate(E, k, colour)
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
        local ring, right, left = Survival.Ring(tree, Uniq("RU_DrinkRing"), Drinks.RING, RingTextures(E), colour)
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
    for class, colour in pairs(Drinks.COLOURS) do
        local list, keys = FindClass(class)
        for i, E in ipairs(list) do Drinks.Decorate(E, keys[i], colour) end
    end
end

-- An entry the game built again is placed again on the next scan. A buff that is on keeps its name for one more look
-- after its entry is gone, so the entry built again for it does not arrive.
local function UpdateBuffs()
    Next = {}
    for k, d in pairs(BuffDeco) do
        if not Alive(d) then
            if d.Name and not d.Over then Next[d.Name] = true end
            BuffDeco[k] = nil
        elseif d.Icon then
            pcall(ShadeBuff, d)
            pcall(LookAtBuff, d)
        end
    end
    Present = Next
end

-- Read by immersive.lua: the entries, to give each good one its level
function M.Entries() return BuffDeco end

-- The level of a good buff (immersive.lua, at each step in which it changes); a debuff does not take one
function M.SetLevel(d, level)
    if not (d.Icon and Alive(d)) then return end
    d.Share = level
    pcall(PlaceBuff, d)
end

-- once per widget scan (main.lua)
function M.Scan() EnsureBuffRow() FindBuffEntries() end

M.NextRings = 0
function M.Tick()
    local now = os.clock()
    if now > M.NextRings then M.NextRings = now + 0.5 UpdateBuffs() Drinks.Update() end
end

-- a new world or a player restart: every handle into the old HUD is dropped
function M.Forget(sameWorld)
    BuffItems = nil
    Present, Next = {}, {}
    BuffDeco, RingArt, Drinks.Deco, Drinks.Lists, Drinks.ListsKey, Drinks.Items = {}, {}, {}, {}, nil, nil
    if not sameWorld then BuffRowDone = {} end   -- the old world's lists are gone; a restart keeps the row
end

-- read by main.lua: the count changed since the last call, and the drink rings
M.Changed = BuffsChanged
M.Drinks = Drinks

return M
