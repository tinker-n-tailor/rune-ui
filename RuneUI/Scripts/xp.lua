-- Rune XP: the XP under the bars, in place of the game's circle.
-- The gold line under the bars (bars.lua) becomes the XP bar: while an XP notice shows, the line is thick and dim,
-- and a bright fill sweeps in from its left end to the progress of the skill's level. Under the line: the skill's
-- icon, its name in white and the XP in gold. Then all of it fades, and the plain line is back.
-- The game's notices (probe 7, 03-10-2026): WBP_Notifications_ExperienceProgressContainer_C (main.lua's "xp") holds
-- a grid of slots, each with one WBP_ExperienceProgress_Item_C. The item on show is not collapsed. In it: SkillIcon
-- (T_Notification_Skill_<skill>), XP_Text ("+ 13 XP") and Ring_Fill, whose material has the progress as "FillBar".
-- The game animates the opacity of each item, so its circles are hidden by the grid's size, 0, and not by an
-- opacity. Our parts live in the bars widget, so they move and size with the bars.
-- With two skills at the same instant the game shows two circles. Ours show one after the other, TURN seconds each.
-- The skill's name comes from the name of its icon, so it is English in every language: the game's notice has no name.
-- "XP under the bars" in Rune Skin (F5) turns it off: the game's circle is back. main.lua loads this file with pcall.

local M = {}

local WIDTH, HIGH, BOTTOM, RIGHT = 330, 10.7, 63.3, 8   -- the line under the bars: its box and its place (bars.lua)
local THICK = 22      -- the XP bar's height; the line picture is stretched, so it is about twice as thick
local ROW = 18        -- the row under the line, and its icon
local TEXT = 10
local TRACK = 0.45    -- the opacity of the line under the fill
local IN, OUT = 6.0, 1.8   -- opacity per second: in fast, out soft
local GLIDE = 2.2     -- the fill closes this share of its way per second, as 1 - e^(-GLIDE * t)
local EVERY = 0.15    -- seconds between two looks at the game's notices
local TURN = 1.5      -- seconds one skill shows while the game shows more than one
local GOLD = { R = 1.0, G = 0.638, B = 0.168, A = 1.0 }   -- the pick-up count's gold
local WHITE = { R = 1, G = 1, B = 1, A = 1 }
-- A level up is bigger than an XP notice: at the XP row's size nobody saw it (in game, 04-10-2026). The line and the
-- row grow from their left end, and the line under the fill is bright. One soft motion (M.SizeNow, M.LevelFade): the
-- size eases out from BIG + POP to BIG (fast at first, slow into its rest) while the row fades in. The row keeps its
-- size while it fades out: letters that change size slowly snap from pixel to pixel and look jagged.
-- A level up mostly comes over an XP notice that is on show, and an XP notice mostly takes the row back after it.
-- There the size goes from the size it has to the new one in RESIZE seconds, soft at both ends, and the line under
-- the fill gets bright and dim with it.
local BIG, POP, POP_TIME = 1.6, 0.3, 0.3
local FADE_IN = 0.22                 -- seconds for a level up to come in
local RESIZE = 0.4                   -- seconds for a row on show to change size

---------------------------------------------------------------- the state, without the game (tools/test-xp.js)

function M.New() return { Alpha = 0, Want = 0, Cur = 0, Target = 0, Skill = nil, Seen = {} } end

-- A notice the game shows: the skill and its progress, 0..1.
function M.Take(S, skill, pct)
    pct = math.max(0, math.min(1, pct))
    if skill ~= S.Skill then
        -- another skill while the bar shows: from where that skill stood, or a little before the new value
        S.Skill = skill
        S.Cur = S.Seen[skill] or math.max(0, pct - 0.08)
    end
    if S.Alpha == 0 then S.Cur = 0 end        -- from unseen: the fill sweeps in from the left end
    if pct < S.Cur then S.Cur = 0 end         -- a new level: the bar starts again from empty
    S.Seen[skill] = pct
    S.Target, S.Want = pct, 1
end

function M.Rest(S) S.Want = 0 end

-- Which of n notices shows, after so many seconds with more than one: each has its turn, then round again.
function M.Pick(n, seconds)
    if n < 2 then return n end
    return math.floor(seconds / TURN) % n + 1
end

-- One step of dt seconds. Returns: the opacity changed, the fill changed.
function M.Step(S, dt)
    local a, c = S.Alpha, S.Cur
    if a < S.Want then a = math.min(S.Want, a + IN * dt)
    elseif a > S.Want then a = math.max(S.Want, a - OUT * dt) end
    if c ~= S.Target then
        if math.abs(S.Target - c) < 0.002 then c = S.Target
        else c = c + (S.Target - c) * (1 - math.exp(-GLIDE * dt)) end
    end
    local fade, fill = a ~= S.Alpha, c ~= S.Cur
    S.Alpha, S.Cur = a, c
    return fade, fill
end

-- "T_Notification_Skill_Woodcutting" or "T_Icon_Tag_Skill_Woodcutting" (the level up notice's) -> "WOODCUTTING"
function M.SkillName(texture)
    local name = string.gsub(texture, "^T_Notification_Skill_", "")
    name = string.gsub(name, "^T_Icon_Tag_Skill_", "")
    return string.upper((string.gsub(name, "_", " ")))
end

-- The game's level up notice is on show while its own render opacity is above zero (probes of 04-10-2026: 0.00 idle,
-- up to 1.00 for about 3 s, fading, 0.00 again; about 5 s in all).
local SHOWN = 0.02
function M.LevelShown(opacity) return type(opacity) == "number" and opacity > SHOWN end
-- In a fresh world the notice sits at opacity 1.00 with the designer's sample in it (Attack, level 6; probe L3,
-- 04-10-2026), and nothing is on the screen. So the opacity counts only after it was seen below full once: every real
-- notice starts from 0.
local FULL = 0.98
function M.LevelArmed(armed, opacity) return armed or (type(opacity) == "number" and opacity < FULL) end
-- That is not enough after a way out to the menu and back into the world: the sample ("ATTACK Level 6") can show on the
-- row again (04-10-2026). The sample's icon is an XP notice's picture, T_Notification_Skill_Attack; a real level up has
-- the skill's tag, T_Icon_Tag_Skill_<skill> (probes L4 and L5). Only that one is shown.
function M.LevelIcon(texture) return string.find(texture or "", "^T_Icon_Tag_Skill_") ~= nil end

local function Clamp01(x) return math.max(0, math.min(1, x)) end
local function Smooth(x) x = Clamp01(x) return x * x * (3 - 2 * x) end   -- soft at both ends

-- The size of the row: it goes from S.SizeFrom to S.SizeTo, from S.SizeAt. The pop (S.SizePop) is fast at first and
-- has no visible stop (a cubic ease-out); a row on show changes size soft at both ends. Without a move the size is 1.
local function SizeTime(S) return S.SizePop and POP_TIME or RESIZE end
function M.SizeNow(S, now)
    if not S.SizeTo then return 1 end
    local x = Clamp01((now - S.SizeAt) / SizeTime(S))
    local done = S.SizePop and 1 - (1 - x) ^ 3 or Smooth(x)
    return S.SizeFrom + (S.SizeTo - S.SizeFrom) * done
end

-- A new size to go to: a pop from the size given, or softly from the size the row has now.
local function Aim(S, to, now, pop)
    if (S.SizeTo or 1) == to then return end
    S.SizeFrom, S.SizePop = pop or M.SizeNow(S, now), pop ~= nil
    S.SizeTo, S.SizeAt = to, now
end

-- A level up takes the row. From unseen it pops in from above the big size; a row on show grows to it.
function M.LevelIn(S, now)
    if S.LevelAt then return end
    S.LevelAt, S.LevelFrom = now, S.Alpha
    Aim(S, BIG, now, S.Alpha == 0 and BIG + POP or nil)
end

-- An XP notice takes the row, also from a level up that is not over: back to the plain size.
function M.LevelOut(S, now)
    S.LevelAt, S.LevelFrom, S.LevelEnd = nil, nil, nil
    Aim(S, 1, now)
end

-- The row is unseen: the next notice starts at the plain size.
function M.LevelGone(S)
    S.LevelAt, S.LevelFrom, S.LevelEnd = nil, nil, nil
    S.SizeFrom, S.SizeTo, S.SizeAt, S.SizePop = nil, nil, nil, nil
end

-- How bright the line under the fill is at a size: TRACK at the plain size, full at the big one.
function M.Bright(size) return TRACK + (1 - TRACK) * Clamp01((size - 1) / (BIG - 1)) end

-- The most opacity a level up may have so many seconds in: from what the row had when it took over (from, 0 when
-- it was unseen) to 1 in FADE_IN seconds, soft at both ends. An XP notice does not use it: it keeps IN.
function M.LevelFade(seconds, from)
    from = from or 0
    return from + (1 - from) * Smooth(seconds / FADE_IN)
end

-- The row is moving while it changes size, and while a level up fades out (S.LevelEnd is set).
function M.Moving(S, now)
    return (S.SizeTo ~= nil and now - S.SizeAt < SizeTime(S)) or (S.LevelAt ~= nil and S.LevelEnd ~= nil)
end

-- Who has the row: a level up wins over an XP notice, and the XP row goes on after it. Returns "level", "xp" or nil.
function M.Owner(levelShown, xpShown)
    if levelShown then return "level" end
    if xpShown then return "xp" end
    return nil
end

-- "Level 21" from the plain number of the game's text; nil when it holds no number
function M.LevelLabel(text)
    local n = string.match(text or "", "%d+")
    return n and ("Level " .. n) or nil
end

---------------------------------------------------------------- the widgets

local S = M.New()
local W = nil     -- ours, in the bars widget: Host, Row, Fill, FillSlot, Track, Icon, Name, Gain
local Q = nil     -- the game's: Addr (the container), Grid, Items
local Logged = {}
local function Once(ctx, key, msg) if not Logged[key] then Logged[key] = true ctx.Log(msg) end end

local function Ok(w) return w and w:IsValid() end
local function Nm(w) return w:GetFName():ToString() end
local function New(ctx, cls, tree, name) return StaticConstructObject(StaticFindObject("/Script/UMG." .. cls), tree, ctx.G(name)) end

local function Text(ctx, tree, name, color)
    local T = New(ctx, "TextBlock", tree, name)
    T:SetText(FText(""))
    T:SetColorAndOpacity({ SpecifiedColor = color, ColorUseRule = 0 })
    T:SetShadowOffset({ X = 1, Y = 1 })
    T:SetShadowColorAndOpacity({ R = 0, G = 0, B = 0, A = 0.8 })
    local fi = T.Font
    local font = ctx.Font()
    if font then fi.FontObject = font end
    fi.Size = TEXT
    T:SetFont(fi)
    return T
end

-- The fill's box is centred like the line's; half the missing width puts its left end on the line's left end.
-- The whole missing width put the fill at the screen's edge (03-10-2026).
local function Place(slot, width, bottom)
    slot:SetPadding({ Left = 0, Top = 0, Right = RIGHT + (WIDTH - width) / 2, Bottom = bottom })
end

local function Build(ctx, bars, host)
    local tree = bars.WidgetTree
    local root = tree.RootWidget
    local tex = ctx.Asset(ctx.GoldLine.PATH, "/Script/Engine.Texture2D")
    if not tex then error("line picture not loaded") end
    ctx.ClearOurs(root, "RU_Xp")
    -- a pointed line of our own, as bars.lua makes its line
    local function Line(name, width)
        local row = ctx.GoldLine.Row(function(cls, n) return New(ctx, cls, tree, n) end, tex, "RU_Xp" .. name)
        local box = New(ctx, "SizeBox", tree, "RU_Xp" .. name .. "Box")
        box:SetWidthOverride(width)
        box:SetHeightOverride(THICK)
        box:SetContent(row)
        box:SetRenderOpacity(0.0)
        local slot = root:AddChildToOverlay(box)
        slot:SetHorizontalAlignment(2)
        slot:SetVerticalAlignment(3)
        Place(slot, width, BOTTOM - (THICK - HIGH) / 2)   -- its middle on the middle of the thin line
        return box, slot
    end
    local w = { Host = host }
    w.Track = Line("Track", WIDTH)
    w.Fill, w.FillSlot = Line("Fill", 1)
    local line = New(ctx, "HorizontalBox", tree, "RU_XpLine")
    local ibox = New(ctx, "SizeBox", tree, "RU_XpIconBox")
    ibox:SetWidthOverride(ROW)
    ibox:SetHeightOverride(ROW)
    w.Icon = New(ctx, "Image", tree, "RU_XpIcon")
    ibox:SetContent(w.Icon)
    line:AddChildToHorizontalBox(ibox):SetVerticalAlignment(2)
    w.Name = Text(ctx, tree, "RU_XpName", WHITE)
    local s2 = line:AddChildToHorizontalBox(w.Name)
    s2:SetVerticalAlignment(2)
    s2:SetPadding({ Left = 6, Top = 0, Right = 0, Bottom = 0 })
    w.Gain = Text(ctx, tree, "RU_XpGain", GOLD)
    local s3 = line:AddChildToHorizontalBox(w.Gain)
    s3:SetVerticalAlignment(2)
    s3:SetPadding({ Left = 8, Top = 0, Right = 0, Bottom = 0 })
    -- the row holds the line and, at its right end, "Level N" (a level up only)
    local ov = New(ctx, "Overlay", tree, "RU_XpRowOv")
    local ls = ov:AddChildToOverlay(line)
    ls:SetHorizontalAlignment(0)
    ls:SetVerticalAlignment(0)
    w.Level = Text(ctx, tree, "RU_XpLevel", GOLD)
    local lv = ov:AddChildToOverlay(w.Level)
    lv:SetHorizontalAlignment(3)
    lv:SetVerticalAlignment(2)
    local box = New(ctx, "SizeBox", tree, "RU_XpRowBox")
    box:SetWidthOverride(WIDTH)
    box:SetHeightOverride(ROW)
    box:SetContent(ov)
    box:SetRenderOpacity(0.0)
    local rs = root:AddChildToOverlay(box)
    rs:SetHorizontalAlignment(2)
    rs:SetVerticalAlignment(3)
    Place(rs, WIDTH, BOTTOM - ROW - 3)
    w.Row = box
    -- a level up grows them from the left end: the lines from their middle line, the row from its top
    w.Track:SetRenderTransformPivot({ X = 0, Y = 0.5 })
    w.Fill:SetRenderTransformPivot({ X = 0, Y = 0.5 })
    box:SetRenderTransformPivot({ X = 0, Y = 0 })
    return w
end

-- The game's notices, found once per container: each item's icon, text and ring. A box with no whole item yet is
-- looked at again at the next look, and its circles stay seen (see Look): never no XP at all.
local function Notices(ctx)
    local box = ctx.ById("xp").Instances[1]
    if not Ok(box) then Q = nil return nil end
    if Q and Q.Addr == box:GetAddress() and #Q.Items > 0 and Q.Grid:IsValid() then return Q end
    local grid = box.WidgetTree.RootWidget
    if not Ok(grid) then Q = nil return nil end
    local items = {}
    for i = 0, grid:GetChildrenCount() - 1 do
        local slot = grid:GetChildAt(i)
        local item = Ok(slot) and slot:GetContent()
        if Ok(item) then
            local icon, text, ring = ctx.Find(item, "SkillIcon"), ctx.Find(item, "XP_Text"), ctx.Find(item, "Ring_Fill")
            if icon and text and ring then items[#items + 1] = { W = item, Icon = icon, Text = text, Ring = ring } end
        end
    end
    local addr = box:GetAddress()
    Q = { Addr = addr, Grid = grid, Items = items, Scale = Q and Q.Addr == addr and Q.Grid:IsValid() and Q.Scale or nil }
    if #items == 0 then Once(ctx, "items", "rune xp: no XP notices in the game's box yet") end
    return Q
end

-- The game's circles seen or unseen: the grid at its own size, or at size 0.
local function Circles(q, seen)
    local s = seen and 1 or 0
    if q.Scale == s then return end
    q.Scale = s
    q.Grid:SetRenderScale({ X = s, Y = s })
end

local function Progress(ring)
    local m = ring.Brush.ResourceObject
    if not Ok(m) or m:GetClass():GetFName():ToString() ~= "MaterialInstanceDynamic" then return nil end
    local v
    m.ScalarParameterValues:ForEach(function(_, e)
        local p = e:get()
        if p.ParameterInfo.Name:ToString() == "FillBar" then v = p.ParameterValue end
    end)
    return v
end

-- Our row shows a notice: the icon, the skill's name, the gain and the level. Written only when the key is another one.
local function Show(key, tex, name, gain, level)
    if key == W.Key then return end
    W.Key = key
    if Ok(tex) then
        W.Icon:SetBrushFromTexture(tex, false)
        local b = W.Icon.Brush
        b.ImageSize = { X = ROW, Y = ROW }
        W.Icon:SetBrush(b)
    end
    W.Name:SetText(FText(name))
    W.Gain:SetText(FText(gain))
    W.Level:SetText(FText(level))
end

-- The notices on show; the one whose turn it is goes into the state and into our row.
local function Read(q, now)
    local shown = {}
    for _, P in ipairs(q.Items) do
        if not P.W:IsValid() then Q = nil return end   -- the game made its notices new: found again at the next look
        if P.W:GetVisibility() ~= 1 then shown[#shown + 1] = P end
    end
    if #shown == 0 then q.Since = nil M.Rest(S) return end
    if #shown < 2 then q.Since = nil elseif not q.Since then q.Since = now end
    local P = shown[M.Pick(#shown, now - (q.Since or now))]
    if not (P.Icon:IsValid() and P.Text:IsValid() and P.Ring:IsValid()) then Q = nil return end
    local tex = P.Icon.Brush.ResourceObject
    local txt = P.Text:GetText():ToString()
    local tname = Ok(tex) and Nm(tex) or ""
    local pct = Progress(P.Ring)
    if not pct then return end   -- the game has not set the ring yet: the next look has it
    Show(tname .. txt, tex, M.SkillName(tname), (string.gsub(txt, "^%+%s+", "+")), "")
    M.LevelOut(S, now)   -- an XP notice has the row: a level up before it is over
    M.Take(S, tname, pct)
end

---------------------------------------------------------------- the slim level up
-- The game's level up notice, WBP_LevelUpNotification_C (probes L1 and L2, 04-10-2026): one live widget per world in
-- the notification queue, always visible; the game shows it by its own render opacity (M.LevelShown). Its named parts:
-- LevelTextBlock (the number), SkillIconImage (the skill's texture, T_Icon_Tag_Skill_<skill>), LevelUpOverlay,
-- IconOverlay, the three LevelUpTextBackground pictures, InputEntryWidget (the game's own key hint, a picture) and two
-- Niagara widgets, the sparks (NS_UI_LevelUpUpper, NS_UI_LevelUpLower). The level text and the icon keep the last
-- level up while idle, so they are read only while it is on show.
-- Hidden: the banner's parts, by render scale 0, as the XP circles are (the game animates opacity). The root's
-- render opacity is never written here: it is the signal that the notice is on show, and apply.lua's ApplyOne writes it
-- only for a hidden element or while the editor is open (this part is off in both). The sparks are hidden too: alone
-- they were two gold lines in the middle of the screen. A spark effect draws inside a part at scale 0, and also
-- inside a box at opacity 0 (both seen in game, 04-10-2026), so each one is collapsed: then it is not drawn.
-- The sound stays as the game makes it; no function of the game's widget is called.
local PARTS = { "LevelUpOverlay", "IconOverlay", "LevelUpTextBackground", "LevelUpTextBackgroundFrame",
    "LevelUpTextBackgroundShadow", "InputEntryWidget", "LevelTextBlock", "SkillIconImage" }
local SPARKS = { "NS_UI_LevelUpUpper", "NS_UI_LevelUpLower" }
local VISIBLE, COLLAPSED = 0, 1   -- ESlateVisibility
local REASSERT = 0.5   -- seconds: the hidden parts are written again, in case the game scales them back
local Lv = nil         -- the game's level up widget
local H = {}           -- Hidden (the parts are unseen now), At (when to write them again), Orig (their scale by name)

local function LevelWidget(ctx)
    if Ok(Lv) then return Lv end
    local E = ctx.ById("levelup")
    local found
    for n, X in ipairs(E.Instances) do
        local k = E.Keys[n]
        if k and string.find(k, "PrimaryNotificationQueue_Item", 1, true) and Ok(X) then found = X break end
    end
    if found ~= Lv then H = {} end   -- another widget: its parts are not hidden yet
    Lv = found
    if not Lv then Once(ctx, "nolevel", "slim level up: the game's level up widget is not in the queue") end
    return Lv
end

-- The parts unseen (hide) or at the scale they had, and the sparks collapsed or visible. Each by its name, behind IsValid.
local function SetParts(lv, hide)
    H.Orig = H.Orig or {}
    for _, name in ipairs(PARTS) do
        pcall(function()
            local P = lv[name]
            if not Ok(P) then return end
            if hide then
                if not H.Orig[name] then
                    local okS, s = pcall(function() return P.RenderTransform.Scale end)
                    H.Orig[name] = okS and s and s.X ~= 0 and { X = s.X, Y = s.Y } or { X = 1, Y = 1 }
                end
                P:SetRenderScale({ X = 0, Y = 0 })
            else
                P:SetRenderScale(H.Orig[name] or { X = 1, Y = 1 })
            end
        end)
    end
    for _, name in ipairs(SPARKS) do
        pcall(function()
            local S = lv[name]
            if Ok(S) then S:SetVisibility(hide and COLLAPSED or VISIBLE) end
        end)
    end
end

-- Hides or restores the game's banner as wanted, and returns what the slim notice shows while the game's is on show.
local function Level(ctx, wanted, now)
    local lv = LevelWidget(ctx)
    if not lv then return nil end
    if wanted ~= (H.Hidden or false) or (wanted and now >= (H.At or 0)) then
        SetParts(lv, wanted)
        H.Hidden, H.At = wanted, now + REASSERT
    end
    local opacity = lv:GetRenderOpacity()
    H.Armed = M.LevelArmed(H.Armed or false, opacity)
    if not (wanted and H.Armed and M.LevelShown(opacity)) then return nil end
    local icon, text = lv.SkillIconImage, lv.LevelTextBlock
    if not (Ok(icon) and Ok(text)) then return nil end
    local tex = icon.Brush.ResourceObject
    local label = M.LevelLabel(text:GetText():ToString())
    if not (Ok(tex) and label) then return nil end   -- the game has not set them yet: the next look has them
    local skill = Nm(tex)
    if not M.LevelIcon(skill) then return nil end    -- the designer's sample
    return { Tex = tex, Skill = skill, Label = label }
end

local function ShowLevel(info)
    Show("level:" .. info.Skill .. info.Label, info.Tex, M.SkillName(info.Skill), "", info.Label)
    M.Take(S, "level:" .. info.Skill, 1)
end

-- The thin line of bars.lua, unseen while ours shows. Its row, not its box: the immersive mode fades the box.
local function BaseLine(ctx)
    if Ok(W.Base) then return W.Base end
    local trim = ctx.Trim()
    W.Base = Ok(trim) and trim:GetContent() or nil
    return W.Base
end

-- The line and the row at size k (see M.SizeNow)
local function Size(k)
    if k == W.Scale then return false end
    W.Scale = k
    local s = { X = k, Y = k }
    W.Track:SetRenderScale(s)
    W.Fill:SetRenderScale(s)
    W.Row:SetRenderScale(s)
    return true
end

local function Draw(ctx, fade, fill)
    if fade then
        local a = S.Alpha
        W.Row:SetRenderOpacity(a)
        W.Fill:SetRenderOpacity(a)
        W.Track:SetRenderOpacity(M.Bright(W.Scale) * a)
        local base = BaseLine(ctx)
        if base then base:SetRenderOpacity(1.0 - a) end
    end
    if fill or W.Width == nil then
        local w = math.max(1, WIDTH * S.Cur)
        W.Width = w
        W.Fill:SetWidthOverride(w)
        Place(W.FillSlot, w, BOTTOM - (THICK - HIGH) / 2)
    end
end

function M.Forget(sameWorld)
    -- the game's banner back, only in the same world: after a world change its widget is gone
    if sameWorld and Ok(Lv) and H.Hidden then pcall(SetParts, Lv, false) end
    W, Q, Lv, H = nil, nil, nil, {}
    S = M.New()
    M.Fails, M.RetryAt, M.Last, M.Next = 0, 0, nil, 0
    M.Restore = true   -- the thin line may be unseen from a notice that was on show: Look sets it back
end

-- The widgets, a few times a second: ours built, the game's notices found and read.
local function Look(ctx, on, now)
    local VE = ctx.ById("vitals")
    local bars = VE.Instances[1]
    if not (W and W.Host == VE.Keys[1] and W.Row:IsValid()) then
        if W then M.Restore = true end   -- ours went while it may have been on show: the thin line back to full
        W = nil
        if on and Ok(bars) and ctx.MayTry(M) then
            local ok, w = pcall(Build, ctx, bars, VE.Keys[1])
            if ok then W, S = w, M.New() M.Fails = 0 ctx.Log("rune xp ready")
            else ctx.Failed(M) ctx.Log("rune xp failed: " .. tostring(w)) end
        end
    end
    if M.Restore then
        local trim = ctx.Trim()
        local row = Ok(trim) and trim:GetContent()
        if Ok(row) then row:SetRenderOpacity(1.0) M.Restore = nil end
    end
    -- the game's level up banner is unseen only while ours is built and Rune XP, the slim level up and the element are on
    local okL, level = pcall(Level, ctx, (on and W ~= nil and ctx.Slim()) and true or false, now)
    if not okL then Once(ctx, "level", "slim level up: not read: " .. tostring(level)) level = nil end
    if not on and Q and Q.Scale == 1 and not W then return end   -- off, and the game's circles are back: nothing to do
    local q = Notices(ctx)
    -- the game's circles are unseen only while ours can show: a build that failed, or no notice found, leaves the game's
    if q then Circles(q, not (on and W and #q.Items > 0)) end
    if not W then return end
    local owner = M.Owner(level ~= nil, on and q ~= nil)
    -- S.LevelAt: when the level up took the row, and S.LevelFrom the opacity the row had then. They stay through the
    -- fade after it. An XP notice that is on show ends them (Read): the game's XP box is always there, so "the level
    -- up is over" must not end them, or the row snaps to the plain size while it can still be seen.
    if owner == "level" then
        M.LevelIn(S, now)
        ShowLevel(level)
    elseif owner == "xp" then Read(q, now)
    else M.Rest(S) end
end

local function Paint(ctx, now)
    local dt = math.min(0.1, now - (M.Last or now))
    M.Last = now
    if not W or (S.Alpha == 0 and S.Want == 0 and W.Width) then return end   -- at rest: nothing to draw
    if not W.Row:IsValid() then W, M.Restore = nil, true return end   -- the HUD went between two looks
    local before = S.Alpha
    local _, fill = M.Step(S, dt)
    if S.LevelAt then
        -- a level up comes in softer than an XP notice, with the pop; the way out is the same fade as always
        if S.Want == 1 then
            S.LevelEnd = nil
            S.Alpha = math.min(S.Alpha, M.LevelFade(now - S.LevelAt, S.LevelFrom))
        elseif not S.LevelEnd then
            S.LevelEnd = now
        end
    end
    local fade = S.Alpha ~= before
    if S.Alpha == 0 and S.Want == 0 then M.LevelGone(S) end   -- faded out
    local sized = Size(M.SizeNow(S, now))
    Draw(ctx, fade or sized, fill)
end

-- A level up changes size, and the 16 steps a second of the mod are not smooth for that (in game, 04-10-2026). While
-- the size changes and while a level up goes out, it is also painted about every frame, by a chain of delayed calls
-- (chain.lua).
local FAST = 8   -- ms between two calls of the chain
local Chain = { Name = "xp chain" }
local function Moving(_, t) return W ~= nil and M.Moving(S, t) end
local function Fast(ctx)
    if ctx.Chain then ctx.Chain.Run(Chain, ctx, FAST, Paint, Moving) end
end

function M.Tick(ctx)
    local now = os.clock()
    local on = ctx.On()
    if now >= (M.Next or 0) or on ~= M.On then   -- at once when the player turns it on or off
        M.Next, M.On = now + EVERY, on
        Look(ctx, on, now)
    end
    Paint(ctx, now)
    Fast(ctx)
end

return M
