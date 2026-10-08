-- Immersive mode: with nothing going on, the HUD fades away, and each part comes back when it matters. The bars
-- come back while health is not full, and a while after; the good buffs with them, and each one when it comes (a
-- debuff never fades). A food, water or rest ring shows while its need is in orange or red, and for a while when it
-- fills; only the ring of that need. The menu buttons come back
-- when a chat message comes, the quest tracker when a quest or its step changes, the party panel when a friend's
-- health goes down. The wheel stays away. RuneMap and the game's compass stay away too, unless the map setting
-- "In immersive mode" keeps one of them: Map keeps the map (and the quest tracker), Compass keeps the compass (M opens
-- the big map). The tool bar never fades, because what matters can sit on it. Prompts, notifications, the area
-- effects and warnings never fade either.
-- Off at first; the F6 panel turns it on and sets how long a part stays (the layout keeps both, main.lua).
-- apply.lua multiplies an element's opacity by Factor(E). The bars widget also holds the food rings and the area
-- effects, so it is not faded whole: its three rows and the trim line under them are faded here, and each ring too.
-- main.lua loads this file with pcall, so an error here leaves the rest of the mod running.

local M = {}

local FADE_OUT, FADE_IN = 2.5, 0.2   -- seconds from full to gone, and back (1.0 out is too quick to read the HUD)
local DRINK_LOW = 1 / 3   -- a drink, food or potion ring shows while its share is under this (the game has no low colour for it)
local SHOW_AT_START = 8   -- a new world shows the whole HUD this long first (main.lua waits 3 s of it before the steps)
-- seconds a part stays after the last reason to show it: the player's setting (F6, "Wait before the fade")
local function Hold(ctx) return ctx.Wait() end

-- the group each element follows; an element not listed never fades. "none": always away.
-- The buff row is not in it: its good buffs fade one by one (StepBuffs) and a debuff never fades.
-- "Menu icons" (menuico) is not in it: that widget is the game's full-screen menu, not the icons in the corner
-- (widget dump of 29-09-2026)
local GROUP = { avatar = "bars", weapon = "bars", compass = "compass", wheel = "none", runemap = "none",
    menubtn = "menu", questtracker = "quest", party = "party" }

M.ErrorLogged = false   -- main.lua logs one failed step
local Level = { bars = 1, menu = 1, quest = 1, party = 1, compass = 1, none = 1 }
local Until = {}
local RingLevel, RingUntil, RingLast = {}, {}, {}
local Applied = {}   -- the last opacity written to the rows and the rings, so a full HUD costs no calls
local Texts = {}     -- by bar: { W = bar widget, List = its text widgets }
local NextRead, LastTime, LastChat, LastQuest, LastHits = 0, nil, nil, nil, nil
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
    Texts, Applied, RingLevel, RingUntil, RingLast, LastChat, LastQuest, LastHits = {}, {}, {}, {}, {}, nil, nil, nil
    DrinkLevel, DrinkUntil, DrinkLast, DrinkApplied = {}, {}, {}, {}
    BuffUntil, BuffSeen, BuffLevel, BuffApplied = ByEntry(), ByEntry(), ByEntry(), ByEntry()
    for g in pairs(Level) do Level[g] = 1 end
    local t = os.clock() + SHOW_AT_START
    Until = { bars = t, buffs = t, menu = t, quest = t, party = t }
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
    -- Stamina does not bring the bars back: a run uses it too, and the bars are for a fight. The game still plays
    -- its sound and its flash when the stamina is gone.
    -- the menu buttons: a new chat message brings them back
    local chat = ctx.ChatCount()
    if chat and LastChat and chat > LastChat then Until.menu = now + Hold(ctx) end
    LastChat = chat
    -- the quest tracker: a new step (or quest) brings it back for a moment. The first read only sets the mark.
    local quest = ctx.QuestSig()
    if quest and LastQuest and quest ~= LastQuest then Until.quest = now + Hold(ctx) end
    LastQuest = quest
    -- the party panel: a friend whose health went down brings it back for a moment
    local hits = ctx.PartyHits()
    if hits and LastHits and hits > LastHits then Until.party = now + Hold(ctx) end
    LastHits = hits
    -- a survival ring: low (orange or red, as survival.lua reads it from the game) keeps it, and a share that goes up
    -- (eating, drinking, sleeping) brings it for the wait
    for i, b in pairs(ctx.Rings()) do
        local v = b.Value
        if b.Low or (v and RingLast[i] and v > RingLast[i] + 0.001) then RingUntil[i] = now + Hold(ctx) end
        RingLast[i] = v
    end
    -- a drink ring: a new entry or a new drink in it (the share jumps up) brings it, and it comes back when it runs
    -- low (DRINK_LOW)
    for k, d in pairs(ctx.Drinks()) do
        local v = d.Value
        if d.Root and v and (DrinkLast[k] == nil or v < DRINK_LOW or v > DrinkLast[k] + 0.001) then DrinkUntil[k] = now + Hold(ctx) end
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

-- The particles of a bar that fills do not take the opacity of its row, so they are hidden while the row is faded.
local PARTICLES = { "NS_UI_StaminaBarIncrease", "NS_UI_HealthBarIncrease", "NS_UI_SpecialChargeBarIncrease" }
local VISIBLE, HIDDEN = 0, 2
local function FadeParticles(bar, i, faded)
    local particles = bar[PARTICLES[i]]
    if particles and particles:IsValid() then particles:SetVisibility(faded and HIDDEN or VISIBLE) end
end

-- the row of bar i faded to level. The special bar has a row of its own in the game. If its parent is ever the column that
-- holds all the rows, it stays, or the rings and area effects would fade with it
local function FadeRow(bars, i, level)
    local row = bars[i]:GetParent()
    if i == 3 and row:GetAddress() == bars[1]:GetParent():GetParent():GetAddress() then return end
    Put("bars", row, level)
    FadeParticles(bars[i], i, level < 1)
end

-- The good buffs, each on its own: an entry shows for the wait after its buff arrives (buffs.lua counts the
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
    -- the tracker stays too: a tracker that shows only at a new step is never seen
    if on and ctx.MapStays() then Until.quest = now + 1 end
    -- the map setting "In immersive mode" at Compass: the game's compass stays, the map and the tracker do not. A
    -- compass hidden in F9 stays hidden: apply.lua's hide comes after this share.
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
        end
    end
    -- the drink ring sits beside them in the same widget, so it fades on its own.
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
