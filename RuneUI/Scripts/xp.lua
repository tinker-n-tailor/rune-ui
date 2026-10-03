-- Rune XP (1.6; made live in the game with Ivan, 03-10-2026): the XP under the bars, in place of the game's circle.
-- The gold line under the bars (bars.lua) becomes the XP bar: while an XP notice shows, the line is thick, dim, and a
-- bright fill sweeps in from its left end to the progress of the skill's level. Under the line: the skill's own
-- icon, its name in white and the XP in gold. Then all of it fades, and the plain line is back.
-- The game's notices (probe 7, 03-10-2026): WBP_Notifications_ExperienceProgressContainer_C (main.lua's "xp") holds
-- a grid of slots, each with one WBP_ExperienceProgress_Item_C. The item on show is not collapsed. In it: SkillIcon
-- (T_Notification_Skill_<skill>), XP_Text ("+ 13 XP") and Ring_Fill, whose material has the progress as "FillBar".
-- The game animates the opacity of each item, so its circles are made unseen by the grid's size, 0, and not by an
-- opacity. Our parts live in the bars widget, so they move and size with the bars.
-- Two skills in the same instant (the game shows two circles): one after the other, TURN seconds each, and round again
-- while the game shows them.
-- The skill's name comes from the name of its icon, so it is English in every language of the game: the game's notice
-- has no name to copy.
-- "Rune XP" in F9 turns it off: the game's circle is back. main.lua loads this file with pcall.

local M = {}

local LINE = "/Game/Art/UI/Loading/T_Trim_Line_Gold.T_Trim_Line_Gold"
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

-- "T_Notification_Skill_Woodcutting" -> "WOODCUTTING"
function M.SkillName(texture)
    return string.upper((string.gsub((string.gsub(texture, "^T_Notification_Skill_", "")), "_", " ")))
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

-- The fill's box is centred like the line's; half the missing width puts its left end on the line's left end
-- (the whole of it put the fill at the screen's edge: in game, 03-10-2026).
local function Place(slot, width, bottom)
    slot:SetPadding({ Left = 0, Top = 0, Right = RIGHT + (WIDTH - width) / 2, Bottom = bottom })
end

local function Build(ctx, bars, host)
    local tree = bars.WidgetTree
    local root = tree.RootWidget
    local tex = ctx.Asset(LINE, "/Script/Engine.Texture2D")
    if not tex then error("line picture not loaded") end
    ctx.ClearOurs(root, "RU_Xp")
    -- a pointed line of our own: two halves of the picture, the left one mirrored (as bars.lua makes its line)
    local function Line(name, width)
        local row = New(ctx, "HorizontalBox", tree, "RU_Xp" .. name .. "Row")
        for half = 1, 2 do
            local img = New(ctx, "Image", tree, "RU_Xp" .. name)
            img:SetBrushFromTexture(tex, false)
            if half == 1 then local b = img.Brush b.Mirroring = 1 img:SetBrush(b) end
            row:AddChildToHorizontalBox(img):SetSize({ SizeRule = 1, Value = 1 })
        end
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
    -- the row under the line: the icon, the skill, the XP
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
    local box = New(ctx, "SizeBox", tree, "RU_XpRowBox")
    box:SetWidthOverride(WIDTH)
    box:SetHeightOverride(ROW)
    box:SetContent(line)
    box:SetRenderOpacity(0.0)
    local rs = root:AddChildToOverlay(box)
    rs:SetHorizontalAlignment(2)
    rs:SetVerticalAlignment(3)
    Place(rs, WIDTH, BOTTOM - ROW - 3)
    w.Row = box
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
    local key = tname .. txt
    if key ~= W.Key then
        W.Key = key
        if Ok(tex) then
            W.Icon:SetBrushFromTexture(tex, false)
            local b = W.Icon.Brush
            b.ImageSize = { X = ROW, Y = ROW }
            W.Icon:SetBrush(b)
        end
        W.Name:SetText(FText(M.SkillName(tname)))
        W.Gain:SetText(FText((string.gsub(txt, "^%+%s+", "+"))))
    end
    M.Take(S, tname, pct)
end

-- The thin line of bars.lua, unseen while ours shows. Its row, not its box: the immersive mode fades the box.
local function BaseLine(ctx)
    if Ok(W.Base) then return W.Base end
    local trim = ctx.Trim()
    W.Base = Ok(trim) and trim:GetContent() or nil
    return W.Base
end

local function Draw(ctx, fade, fill)
    if fade then
        local a = S.Alpha
        W.Row:SetRenderOpacity(a)
        W.Fill:SetRenderOpacity(a)
        W.Track:SetRenderOpacity(TRACK * a)
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

function M.Forget()
    W, Q = nil, nil
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
    if not on and Q and Q.Scale == 1 and not W then return end   -- off, and the game's circles are back: nothing to do
    local q = Notices(ctx)
    -- the game's circles are unseen only while ours can show: a build that failed, or no notice found, leaves the game's
    if q then Circles(q, not (on and W and #q.Items > 0)) end
    if not W then return end
    if on and q then Read(q, now) else M.Rest(S) end
end

function M.Tick(ctx)
    local now = os.clock()
    local dt = math.min(0.1, now - (M.Last or now))
    M.Last = now
    local on = ctx.On()
    if now >= (M.Next or 0) or on ~= M.On then   -- at once when the player turns it on or off
        M.Next, M.On = now + EVERY, on
        Look(ctx, on, now)
    end
    if not W or (S.Alpha == 0 and S.Want == 0 and W.Width) then return end   -- at rest: nothing to draw
    if not W.Row:IsValid() then W, M.Restore = nil, true return end   -- the HUD went between two looks
    local fade, fill = M.Step(S, dt)
    Draw(ctx, fade, fill)
end

return M
