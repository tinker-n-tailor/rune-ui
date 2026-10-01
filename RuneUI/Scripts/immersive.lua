-- Immersive mode (1.2, the idea of 29-09-2026): with nothing going on, the HUD fades away, and each part comes
-- back when it matters. The bars while health or stamina is not full, and a while after; the buffs with them,
-- and when a new buff comes; a food, water or rest ring when it runs low or fills; the menu buttons when a chat
-- message comes. The compass, the wheel and RuneMap stay away (M opens the big map). The tool bar never fades:
-- what matters can sit on it (playtest, 29-09-2026); nor do prompts, notifications, the area effects and warnings.
-- Off at first; its line in F9 turns it on, and + / - there set how long a part stays (main.lua keeps the number).
-- main.lua multiplies an element's opacity by Factor(E). The bars widget also holds the food rings and the area
-- effects, so it is not faded whole: its three rows and the trim line under them are faded here, and each ring too.
-- main.lua loads this file with pcall, so an error here leaves the rest of the mod running.

local M = {}

local FADE_OUT, FADE_IN = 2.5, 0.2   -- seconds from full to gone, and back (out 1.0 was too quick: playtest, 29-09-2026)
local LOW = 1 / 3                                            -- a ring shows while its share is under this
local SHOW_AT_START = 8   -- a new world shows the whole HUD this long first (main.lua waits 3 s of it before the steps)
-- seconds a part stays after the last reason to show it: the player's setting (F9, + / - on the immersive line)
local function Hold(ctx) return ctx.Wait() end

-- the group each element follows; an element not listed never fades. "none": always away.
-- "Menu icons" (menuico) is not in it: that widget is the game's full-screen menu, not the icons in the corner
-- (widget dump, 29-09-2026)
local GROUP = { avatar = "bars", weapon = "bars", buffs = "buffs", compass = "none", wheel = "none", runemap = "none",
    menubtn = "menu" }

M.ErrorLogged = false   -- main.lua logs one failed step
local Level = { bars = 1, buffs = 1, menu = 1, none = 1 }
local Until = {}
local RingLevel, RingUntil, RingLast = {}, {}, {}
local Applied = {}   -- the last opacity written to the rows and the rings, so a full HUD costs no calls
local Texts = {}     -- by bar: { W = bar widget, List = its text widgets }
local NextRead, LastTime, LastBuffs, LastChat = 0, nil, nil, nil
-- the drink rings, by entry name: the game keeps spare drink entries and reuses them, so each one fades on its own
-- (one watched entry left the shown one unseen, in game 01-10-2026)
local DrinkLevel, DrinkUntil, DrinkLast, DrinkApplied = {}, {}, {}, {}
local Logged = {}
local function Once(ctx, key, msg) if not Logged[key] then Logged[key] = true ctx.Log(msg) end end

function M.Factor(E)
    local g = GROUP[E.Id]
    return g and Level[g] or 1.0
end

-- Leaving the world: drop the handles into it, and show everything for a moment in the new one
function M.Forget()
    Texts, Applied, RingLevel, RingUntil, RingLast, LastBuffs, LastChat = {}, {}, {}, {}, {}, nil, nil
    DrinkLevel, DrinkUntil, DrinkLast, DrinkApplied = {}, {}, {}, {}
    for g in pairs(Level) do Level[g] = 1 end
    local t = os.clock() + SHOW_AT_START
    Until = { bars = t, buffs = t, menu = t }
    for i = 1, 3 do RingUntil[i] = t end
end
M.Forget()

-- the text of every visible text widget under a bar, joined; the list is found once per bar widget
local function BarText(ctx, i, W)
    local c = Texts[i]
    if not (c and c.W == W) then
        c = { W = W, List = ctx.TextsUnder(W) }
        Texts[i] = c
    end
    local s = ""
    for _, T in ipairs(c.List) do
        pcall(function() if T:IsVisible() then s = s .. " " .. T:GetText():ToString() end end)
    end
    return s
end

-- the reasons to show, read 4 times a second
local function Read(ctx, now)
    local bars = ctx.Bars()
    local health = bars[2] and bars[2]:IsValid() and BarText(ctx, 2, bars[2])
    if health then
        Once(ctx, "health", "immersive: health bar text '" .. health .. "'")
        local cur, max = string.match(health, "(%d+)%s*/%s*(%d+)")
        if cur and tonumber(cur) < tonumber(max) then Until.bars = now + Hold(ctx) end
    end
    -- the stamina bar shows no number; its fill is a number on the fill's material (read in game, 29-09-2026):
    -- "Fill from Avaliable" drops while you run or swing and refills to 1 minus "Blocked from avaliable" (the part
    -- that hunger or rest takes away). A swing costs stamina, so this also brings the bars back in a fight.
    local okS, notFull = pcall(function()
        if not (bars[1] and bars[1]:IsValid()) then return false end
        local fill, blocked
        bars[1].ProgressBarImage.Brush.ResourceObject.ScalarParameterValues:ForEach(function(_, e)
            local p = e:get()
            local n = p.ParameterInfo.Name:ToString()
            if n == "Fill from Avaliable" then fill = p.ParameterValue elseif n == "Blocked from avaliable" then blocked = p.ParameterValue end
        end)
        return fill and fill < 1 - (blocked or 0) - 0.005
    end)
    if not okS then Once(ctx, "stamina", "immersive: stamina not read: " .. tostring(notFull)) end
    if okS and notFull then Until.bars = now + Hold(ctx) end
    -- the menu buttons: a new chat message brings them back
    local chat = ctx.ChatCount()
    if chat and LastChat and chat > LastChat then Until.menu = now + Hold(ctx) end
    LastChat = chat
    local n = ctx.BuffCount()
    if n and LastBuffs and n > LastBuffs then Until.buffs = now + Hold(ctx) end
    LastBuffs = n
    for i, b in pairs(ctx.Rings()) do
        local v = b.Value
        if v and (v < LOW or (RingLast[i] and v > RingLast[i] + 0.001)) then RingUntil[i] = now + Hold(ctx) end
        RingLast[i] = v
    end
    -- a drink ring: a new entry or a new drink in it (the share jumps up) brings it, and it comes back when it runs
    -- low, like a food ring
    for k, d in pairs(ctx.Drinks()) do
        local v = d.Value
        if d.Root and v and (DrinkLast[k] == nil or v < LOW or v > DrinkLast[k] + 0.001) then DrinkUntil[k] = now + Hold(ctx) end
        DrinkLast[k] = v
    end
end

-- one step from level toward target, at the fade speed for dt seconds; lands on exactly 0 or 1
local function Ease(level, target, dt)
    if target > level then return math.min(target, level + dt / FADE_IN) end
    return math.max(target, level - dt / FADE_OUT)
end

local function Put(key, W, o)
    if W and W:IsValid() then W:SetRenderOpacity(o) end
    Applied[key] = o
end

local function Fade(W, o) if W:IsValid() then W:SetRenderOpacity(o) end end   -- no closure per step

-- 1 while the group g has a reason to show (or the mode is off), else 0
local function Target(g, on, now) return (not on or (g ~= "none" and now < (Until[g] or 0))) and 1 or 0 end

-- the row of bar i faded to level. The special bar's parent might be the column that holds all the rows (only the
-- first two are proven rows, by SwapRows): then it stays, or the rings and area effects would fade with it
local function FadeRow(bars, i, level)
    local row = bars[i]:GetParent()
    if i == 3 and row:GetAddress() == bars[1]:GetParent():GetParent():GetAddress() then return end
    Put("bars", row, level)
end

function M.Tick(ctx)
    local now = os.clock()
    local dt = math.min(0.5, now - (LastTime or now))   -- a long wait (a world loading) is not a jump
    LastTime = now
    local on = ctx.On() and not ctx.Editing()
    if on and now > NextRead then NextRead = now + 0.25 Read(ctx, now) end
    for g in pairs(Level) do Level[g] = Ease(Level[g], Target(g, on, now), dt) end
    -- the buffs also come with the bars: a fight brings its effects
    Level.buffs = math.max(Level.buffs, Level.bars)

    -- the bars' rows and the trim line: every step while faded, so a row the game makes again is faded too
    local bars = ctx.Bars()
    if Level.bars < 1 or Applied.bars ~= 1 then
        for i = 1, 3 do pcall(FadeRow, bars, i, Level.bars) end
        pcall(Put, "bars", ctx.Trim(), Level.bars)
        Applied.bars = Level.bars
    end
    for i, b in pairs(ctx.Rings()) do
        local target = (not on or now < (RingUntil[i] or 0)) and 1 or 0
        RingLevel[i] = Ease(RingLevel[i] or 1, target, dt)
        local o = RingLevel[i]
        if o < 1 or Applied[i] ~= 1 then
            pcall(Put, i, b.Box, o)
            pcall(Put, i, b.Dia, o)
        end
    end
    -- the drink ring sits beside them in the same widget, so it fades on its own (playtest, 01-10-2026: it stayed alone).
    -- Its root, not the entry: the entry is an F9 element, and hiding it there sets the entry's opacity.
    for k, d in pairs(ctx.Drinks()) do
        if d.Root then
            DrinkLevel[k] = Ease(DrinkLevel[k] or 1, (not on or now < (DrinkUntil[k] or 0)) and 1 or 0, dt)
            local o = DrinkLevel[k]
            if o < 1 or DrinkApplied[k] ~= 1 then
                pcall(Fade, d.Root, o)
                DrinkApplied[k] = o
            end
        end
    end
end

return M
