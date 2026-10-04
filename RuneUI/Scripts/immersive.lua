-- Immersive mode (1.2, the idea of 29-09-2026): with nothing going on, the HUD fades away, and each part comes
-- back when it matters. The bars while health is not full, and a while after; the good buffs with them,
-- and each one when it comes (a debuff never fades); a food, water or rest ring when it runs low or fills; the menu buttons when a chat
-- message comes; the quest tracker when a quest or its step changes. The wheel stays away. RuneMap and the game's compass stay away too, unless the map setting "In immersive mode" keeps
-- one of them: Map keeps the map (and the quest tracker), Compass keeps the compass (M opens the big map). The tool bar never fades:
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
-- The buff row is not in it: its good buffs fade one by one (StepBuffs) and a debuff never fades.
-- "Menu icons" (menuico) is not in it: that widget is the game's full-screen menu, not the icons in the corner
-- (widget dump, 29-09-2026)
local GROUP = { avatar = "bars", weapon = "bars", compass = "compass", wheel = "none", runemap = "none",
    menubtn = "menu", questtracker = "quest" }

M.ErrorLogged = false   -- main.lua logs one failed step
local Level = { bars = 1, menu = 1, quest = 1, compass = 1, none = 1 }
local Until = {}
local RingLevel, RingUntil, RingLast = {}, {}, {}
local Applied = {}   -- the last opacity written to the rows and the rings, so a full HUD costs no calls
local Texts = {}     -- by bar: { W = bar widget, List = its text widgets }
local NextRead, LastTime, LastChat, LastQuest = 0, nil, nil, nil
-- the drink rings, by entry name: the game keeps spare drink entries and reuses them, so each one fades on its own
-- (one watched entry left the shown one unseen, in game 01-10-2026)
local DrinkLevel, DrinkUntil, DrinkLast, DrinkApplied = {}, {}, {}, {}
-- the good buffs, by entry: the time it shows until, the arrival it has seen, its own level, and the level last given
local function ByEntry() return setmetatable({}, { __mode = "k" }) end
local BuffUntil, BuffSeen, BuffLevel, BuffApplied = ByEntry(), ByEntry(), ByEntry(), ByEntry()
local Logged = {}
local function Once(ctx, key, msg) if not Logged[key] then Logged[key] = true ctx.Log(msg) end end

function M.Factor(E)
    local g = GROUP[E.Id]
    return g and Level[g] or 1.0
end

-- Leaving the world: drop the handles into it, and show everything for a moment in the new one
function M.Forget()
    Texts, Applied, RingLevel, RingUntil, RingLast, LastChat, LastQuest = {}, {}, {}, {}, {}, nil, nil
    DrinkLevel, DrinkUntil, DrinkLast, DrinkApplied = {}, {}, {}, {}
    BuffUntil, BuffSeen, BuffLevel, BuffApplied = ByEntry(), ByEntry(), ByEntry(), ByEntry()
    for g in pairs(Level) do Level[g] = 1 end
    local t = os.clock() + SHOW_AT_START
    Until = { bars = t, buffs = t, menu = t, quest = t }
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
    -- Stamina does not bring the bars back (04-10-2026): a run uses it too, and the bars are for a fight. The game
    -- still plays its sound and its flash when the stamina is gone.
    -- the menu buttons: a new chat message brings them back
    local chat = ctx.ChatCount()
    if chat and LastChat and chat > LastChat then Until.menu = now + Hold(ctx) end
    LastChat = chat
    -- the quest tracker: a new step (or quest) brings it back for a moment. The first read only sets the mark.
    local quest = ctx.QuestSig()
    if quest and LastQuest and quest ~= LastQuest then Until.quest = now + Hold(ctx) end
    LastQuest = quest
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

-- The good buffs, each on its own (1.7): an entry shows for the wait after its buff arrives (buffs.lua counts the
-- arrivals) and at the start of a world, and fades after. The bars bring all of them back: a fight brings its
-- effects. A debuff has no level here. An entry seen for the first time takes its target at once: one built again
-- for a buff that is on must not fade in front of the player. The call goes out only when the level changed.
local function StepBuffs(ctx, on, now, dt)
    for _, d in pairs(ctx.BuffEntries()) do
        if d.Positive then
            local arrivals = d.Arrivals or 0
            if arrivals ~= (BuffSeen[d] or 0) then
                BuffSeen[d] = arrivals
                BuffUntil[d] = now + Hold(ctx)
            end
            local target = (not on or now < (BuffUntil[d] or 0) or now < Until.buffs) and 1 or 0
            local level = BuffLevel[d] and Ease(BuffLevel[d], target, dt) or target
            BuffLevel[d] = level
            local shown = math.max(level, Level.bars)
            if BuffApplied[d] ~= shown then
                BuffApplied[d] = shown
                ctx.BuffLevel(d, shown)
            end
        end
    end
end

function M.Tick(ctx)
    local now = os.clock()
    local dt = math.min(0.5, now - (LastTime or now))   -- a long wait (a world loading) is not a jump
    LastTime = now
    local on = ctx.On() and not ctx.Editing()
    if on and now > NextRead then NextRead = now + 0.25 Read(ctx, now) end
    -- the quest tracker sits under the map and goes with it: while the map stays (its setting "In immersive mode"),
    -- the tracker stays too (playtest, 04-10-2026: a tracker that shows only at a new step is never seen)
    if on and ctx.MapStays() then Until.quest = now + 1 end
    -- the map setting "In immersive mode" at Compass: the game's compass stays, the map and the tracker do not. A
    -- compass hidden in F9 stays hidden: main.lua's hide comes after this share.
    if on and ctx.CompassStays() then Until.compass = now + 1 end
    for g in pairs(Level) do Level[g] = Ease(Level[g], Target(g, on, now), dt) end
    StepBuffs(ctx, on, now, dt)

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
