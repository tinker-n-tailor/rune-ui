-- The search for the game's widgets: which widgets of which class are alive, and which of them belong to which
-- element. No part searches on its own: they ask FindClass. main.lua loads this file, gives it its own names (Init) and
-- the parts that FindAll reads (Attach), registers NewWidget for the game's reports, and calls FindAll on every scan.
--
-- Found, FindCache, NextSearch, ClassNames, Searches and Settle get a new value from time to time (here, in Forget,
-- and Searches in perf.lua), so every read and write of them goes through the table, never through a local copy.
-- Reports and Arrivals stay the same two tables for the whole run; only their fields change.

local M = {}

-- From main.lua (Init): the element list, layout.lua's ById and Hud, the log, and the time until which a new world
-- settles. That time is a function, as main.lua gives it a new value in every world.
local Elements, ById, Hud, Log, SettleUntil
function M.Init(ctx)
    Elements, ById, Hud, Log, SettleUntil = ctx.Elements, ctx.ById, ctx.Hud, ctx.Log, ctx.SettleUntil
end
-- The parts that FindAll reads. main.lua loads them after this file, before the timer starts.
local Buffs, Survival, Avatar, RuneMap, Cooldowns, QuestTracker, Party
function M.Attach(P)
    Buffs, Survival = P.Buffs, P.Survival
    Avatar, RuneMap, Cooldowns, QuestTracker, Party = P.Avatar, P.RuneMap, P.Cooldowns, P.QuestTracker, P.Party
end

local function ClassName(obj)
    local ok, n = pcall(function() return obj:GetClass():GetFName():ToString() end)
    return ok and n or "?"
end

-- One search for every widget per scan, sorted by class. One search per class (about 30) took up to 1 s on UE4SS
-- builds without hash tables. This one took 45 ms and found the same widgets (probe of 28-09-2026).
M.Found = {}   -- class name -> widgets, from the last search and the game's reports (Reports)
-- class address -> class name: the name is read once per class, not once per widget (5000 widgets, 19 ms a scan
-- on a UE4SS with hash tables; probe of 28-09-2026). Emptied on a new world, as a class can be unloaded and its address reused.
M.ClassNames = {}
local function ClassAddress(W) return W:GetClass():GetAddress() end
local function ClassNameOf(W, a)
    local c = M.ClassNames[a]
    if not c then c = ClassName(W) M.ClassNames[a] = c end
    return c
end
-- FindClass's answers since the last search, by class and path: the parts ask for the same classes up to 5 times a
-- second (the spell slices, the chat, the aim), and between two searches the answer only loses widgets.
-- With the game's reports a class can gain a widget between two searches: FindAll empties this when it matches again.
M.FindCache = {}
local function Valid(W) return W and W:IsValid() end
local function SearchWidgets()
    M.Found, M.FindCache = {}, {}
    for _, W in pairs(FindAllOf("UserWidget") or {}) do
        local ok, a = pcall(ClassAddress, W)   -- one object that cannot be read must not stop the scan
        if ok and a then
            local c = ClassNameOf(W, a)
            local t = M.Found[c]
            if t then t[#t + 1] = W else M.Found[c] = { W } end
        end
    end
end

-- The game reports every new widget, so the search above runs once per world, not every 10 s. It walked
-- 7000 to 10000 widgets in 10 to 50 ms (probe of 01-10-2026). UE4SS calls NewWidget on the game
-- thread, as it does the step (its source at 44afb36d: a widget made on a loading thread waits for the next engine
-- tick). On: the report is registered, where the timer starts; an old UE4SS keeps the timed search.
-- Wanted: the classes FindClass was asked for; a widget of another class is not kept. Dropped: the classes not kept
-- since the last search. Walk: why the next scan must search (false: no search). Retry: the scans that still match
-- the parts again after a kept widget, as a new widget has no tree and no parent yet. Seen, Kept, Time, Max: for
-- the perf line; the reports run outside the step, so its times do not count them.
-- Fresh: a widget was kept since the last scan, so the step scans soon (TickBody).
-- Quiet: the classes wanted with FindQuiet.
local Reports = { On = false, Wanted = {}, Quiet = {}, Dropped = {}, Walk = "start", Retry = 0, Fresh = false, Quick = 0, Seen = 0, Kept = 0, Time = 0, Max = 0 }
-- Arrivals: for a class that a part asks about with TakeArrivals, the widgets reported since it last asked.
-- The 2 s scan is too late for the map name: a map makes new markers, and the player name shows beside the arrow
-- until the scan (probe of 05-10-2026). Only handles are kept, nothing is read here. Forget empties them.
-- A list that nobody takes does not grow past ARRIVALS_MAX.
local Arrivals = {}
local ARRIVALS_MAX = 2000
local function TakeArrivals(className)
    local list = Arrivals[className]
    Arrivals[className] = {}
    if list and #list > 0 then return list end
end
-- It returns nothing: a report that returns true is taken out, and in this UE4SS that can free the Lua thread all
-- hooks of the mod run on (UE4SS issue 1345). The mod's own widgets come through here too, from inside the step.
local function NewWidget(W)
    local t0 = os.clock()
    Reports.Seen = Reports.Seen + 1
    local ok, a = pcall(ClassAddress, W)
    if ok and a then
        local c = ClassNameOf(W, a)
        local taken = Arrivals[c]
        if taken and #taken < ARRIVALS_MAX then taken[#taken + 1] = W end
        if Reports.Wanted[c] then
            local t = M.Found[c]
            if t then t[#t + 1] = W else M.Found[c] = { W } end
            Reports.Kept = Reports.Kept + 1
            if not Reports.Quiet[c] then Reports.Retry, Reports.Fresh = 3, true end
        else
            Reports.Dropped[c] = true
        end
    end
    local took = os.clock() - t0
    Reports.Time, Reports.Max = Reports.Time + took, math.max(Reports.Max, took)
end
-- Without the timed search a class's list only grows. Before FindClass reads it, drop the widgets that are gone, a
-- freed slot that now holds an object of another class, and a widget listed twice (reported, and found by a search).
local function StillOf(W, className) return W:IsValid() and M.ClassNames[ClassAddress(W)] == className and W:GetAddress() end
local function Compact(className)
    local keep, seen = {}, {}
    for _, W in ipairs(M.Found[className] or {}) do
        local ok, a = pcall(StillOf, W, className)
        if ok and a and not seen[a] then seen[a] = true keep[#keep + 1] = W end
    end
    M.Found[className] = keep
end

-- Returns the widgets and, as a second list, their full names (read here once, so no caller reads them again).
-- A cached answer is checked for widgets gone since; the lists are shared, so callers only read them.
local function FindClass(className, pathEnds, useParent)
    if Reports.On and not Reports.Wanted[className] then
        Reports.Wanted[className] = true
        -- the last search has every widget of the class, unless one was made since and not kept
        if Reports.Dropped[className] and not Reports.Walk then Reports.Walk = "new class" end
    end
    local ck = className .. "|" .. (useParent or 0) .. "|" .. (pathEnds and table.concat(pathEnds, "|") or "")
    local hit = not Reports.Quiet[className] and M.FindCache[ck]
    if hit then
        for i = #hit.W, 1, -1 do
            local ok, v = pcall(Valid, hit.W[i])
            if not (ok and v) then table.remove(hit.W, i) table.remove(hit.K, i) end
        end
        return hit.W, hit.K
    end
    local out, keys = {}, {}
    if Reports.On then Compact(className) end
    for _, W in ipairs(M.Found[className] or {}) do
        -- one object that cannot be read (a world being unloaded) must not stop the whole scan
        pcall(function()
            if not (W and W:IsValid()) then return end
            local full = W:GetFullName()
            local ok = not pathEnds
            if pathEnds then
                for _, p in ipairs(pathEnds) do if string.find(full, p) then ok = true end end
            end
            if ok and string.find(full, "/Engine/Transient%.") then   -- live widgets only; /Game paths are templates
                local climbed = false
                for _ = 1, (useParent or 0) do
                    local okp, P = pcall(function() return W:GetParent() end)
                    if okp and P and P:IsValid() then W, climbed = P, true end
                end
                if climbed then full = W:GetFullName() end
                out[#out + 1], keys[#keys + 1] = W, full
            end
        end)
    end
    if not Reports.Quiet[className] then M.FindCache[ck] = { W = out, K = keys } end
    return out, keys
end
-- A class wanted quietly: the enemy bar, which the game makes for each creature, all the time. Its new widgets are kept,
-- but they bring no early scan and no matching of the parts again, and its answer is not cached, so the next regular
-- scan has them. For a part that dresses a widget once and does not mind a second or two (enemybars.lua).
local function FindQuiet(className)
    Reports.Quiet[className] = true
    return FindClass(className)
end

-- A found widget and its full name, which keys the opacity and clipping memory. k: the name when already read.
local function AddInstance(E, W, k)
    local ok, key = pcall(function() return k or W:GetFullName() end)
    if ok and key then table.insert(E.Instances, W) table.insert(E.Keys, key) end
end

-- The screen's size in units and the game's HUD scale (see Hud), from the bars' widget: the canvas it fills sits in
-- a size box inside the HUD's scale box. Rounded, so a 16:9 screen gives exactly 1920x1080.
local function ReadHud()
    local V = ById("vitals").Instances[1]
    if not (V and V:IsValid()) then return end
    local WLL = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
    local v, dpi = WLL:GetViewportSize(V), WLL:GetViewportScale(V)
    if not (dpi and dpi > 0 and v.X > 0 and v.Y > 0) then return end
    local s = 1
    pcall(function()
        local box = V:GetParent():GetParent():GetParent()
        if ClassName(box) ~= "ScaleBox" or not (box.Stretch == 7 or box.Stretch == 8) then return end
        local u = box.UserSpecifiedScale   -- 7 and 8: the scale is set by hand, here the game's HUD scale
        if u > 0.2 and u < 5 then s = math.floor(u * 100 + 0.5) / 100 end
    end)
    local vw, vh = math.floor(v.X / dpi + 0.5), math.floor(v.Y / dpi + 0.5)
    if vw ~= Hud.VW or vh ~= Hud.VH or s ~= Hud.S then
        Log(string.format("screen: %d x %d units, HUD scale %.2f, so the HUD is %.0f x %.0f", vw, vh, s, vw / s, vh / s))
    end
    Hud.VW, Hud.VH, Hud.S, Hud.W, Hud.H = vw, vh, s, vw / s, vh / s
end

-- The search for every widget costs 14 ms (probe of 29-09-2026). Once a world has settled, the game makes almost no
-- new HUD widgets (buff entries, maybe a held-action prompt). So the search runs every 2 s for the first half minute
-- of a world and while F9 or F8 is open, else every 10 s. It runs at once when a widget it found is gone, or when
-- the number of buffs changes (a new buff can bring a new entry widget, and its ring should not wait).
-- A widget the game makes new waits 10 s at most for its place. Between searches the widgets of the last one are used.
-- Forget drops them. This is the way of an old UE4SS only: with the game's reports (Reports) the search runs
-- once per world, and NextSearch times the matching of the parts to the widgets kept.
M.NextSearch = 0
-- the full searches since the last perf line: how many, their time, and what set each off (PerfLog)
M.Searches = { N = 0, Sum = 0, Max = 0, Why = {} }
-- After a new world or a respawn the HUD is searched on every scan, up to 30 s, so its parts are found as the game
-- builds them. Three searches in a row that find the same number of parts end that early: the rest cost 10 to
-- 50 ms each for nothing (hitches of 90 to 110 ms after a teleport and a respawn; probe of 01-10-2026). A part
-- the game builds later waits for the 10 s search. Forget starts it again. An old UE4SS only, as the timer is.
M.Settle = { Last = -1, Same = 0, Done = false }
-- A freed widget's slot can go to a new object that still reads valid, so the name is compared too.
-- AddInstance adds each widget and its name together. Avatar and RuneMap are ours and re-added each pass.
local function AnyGone()
    for _, E in ipairs(Elements) do
        if not E.Custom then
            for n, W in ipairs(E.Instances) do
                local ok, k = pcall(function() return W:IsValid() and W:GetFullName() end)
                if not (ok and k == E.Keys[n]) then return E.Id end
            end
        end
    end
    return false
end
-- editing: F9 or F8 is open. buffsNew: the step saw the buff count change. Returns true when a search ran.
-- Without one, the game's widgets of the last pass are kept: AnyGone has just seen every one alive under its own
-- name, and the same answer costs a name read and a path check per widget, and a walk into the legend, every pass.
-- Ours (the avatar, RuneMap, the cooldown tiles) are built after this in the same step, so they are
-- taken again on every pass.
local function FindAll(editing, buffsNew)
    local now = os.clock()
    local buffs = (Buffs and Buffs.Changed()) or buffsNew   -- read on every pass, so the count stays current
    local searched = false
    local why
    if Reports.On then
        -- The game reports new widgets (Reports): a full search only when one is owed. The parts are matched again,
        -- from the widgets kept, on what set off a search before; that reads some tens of widgets, not all of them.
        why = Reports.Walk
        searched = Reports.Retry > 0 or now > M.NextSearch or buffs or AnyGone()
        if searched and not why then M.FindCache, M.NextSearch = {}, now + 10 end
        if Reports.Retry > 0 then Reports.Retry = Reports.Retry - 1 end
    else
        why = (now > M.NextSearch and "timer") or (now < SettleUntil() + 30 and not M.Settle.Done and "settle") or (editing and "editor")
            or (buffs and "buffs") or AnyGone()
    end
    if why then
        local t0 = os.clock()
        SearchWidgets()
        local t = os.clock() - t0
        M.Searches.N, M.Searches.Sum, M.Searches.Max = M.Searches.N + 1, M.Searches.Sum + t, math.max(M.Searches.Max, t)
        M.Searches.Why[why] = (M.Searches.Why[why] or 0) + 1
        M.NextSearch = now + 10
        Reports.Walk, Reports.Dropped = false, {}
        searched = true
    end
    -- the parts that draw an element of their own: the element is the box they built
    local drawn = { avatar = Avatar, map = RuneMap, cooldowns = Cooldowns, questtracker = QuestTracker, party = Party }
    for _, E in ipairs(Elements) do
        if E.Custom then
            E.Instances, E.Keys = {}, {}
            local Part = drawn[E.Custom]
            if Part and Part.W and Part.W:IsValid() then AddInstance(E, Part.W) end
        elseif searched then
            E.Instances, E.Keys = {}, {}
            for _, c in ipairs(E.Classes or {}) do
                local list, keys = FindClass(c, E.PathEnds, E.UseParent)
                for n, W in ipairs(list) do
                    local k = keys[n]
                    if E.Deep then
                        W, k = Survival and Survival.Find(W, E.Child), nil
                    elseif E.Child then
                        local found
                        pcall(function()
                            local root = W.WidgetTree.RootWidget
                            for i = 0, root:GetChildrenCount() - 1 do
                                local ch = root:GetChildAt(i)
                                if ch:GetFName():ToString() == E.Child then found = ch break end
                            end
                        end)
                        W, k = found, nil
                    end
                    if W then AddInstance(E, W, k) end
                end
            end
        end
    end
    if why == "settle" then
        local n = 0
        for _, E in ipairs(Elements) do if not E.Custom then n = n + #E.Instances end end
        M.Settle.Same = (n > 0 and n == M.Settle.Last) and M.Settle.Same + 1 or 0
        M.Settle.Last = n
        if M.Settle.Same >= 2 then
            M.Settle.Done = true
            Log(string.format("settled: %d HUD parts found, back to the 10 s search", n))
        end
    end
    pcall(ReadHud)
    return searched
end

-- A new round (a new world, or a player restart in a world that still stands: sameWorld). Called by main.lua's ForgetWorld.
function M.Forget(sameWorld)
    M.Found, M.FindCache, M.NextSearch = {}, {}, 0   -- search again at once
    for c in pairs(Arrivals) do Arrivals[c] = {} end
    Reports.Walk = sameWorld and "restart" or "new world"
    if not sameWorld then M.ClassNames = {} end   -- a class of the old world may be unloaded, and its address reused
    M.Settle = { Last = -1, Same = 0, Done = false }
end

M.Reports, M.Arrivals, M.ARRIVALS_MAX = Reports, Arrivals, ARRIVALS_MAX
M.ClassName, M.SearchWidgets, M.TakeArrivals, M.NewWidget = ClassName, SearchWidgets, TakeArrivals, NewWidget
M.FindClass, M.FindQuiet, M.AddInstance, M.FindAll = FindClass, FindQuiet, AddInstance, FindAll
return M
