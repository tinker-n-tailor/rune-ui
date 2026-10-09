-- The perf lines in UE4SS.log, every 60 s: what the mod costs the game, the game's frame rate beside it, and what the
-- widget search did. main.lua loads this file and gives it its own names (Init). The table this file returns is the
-- counter of the step's times: main.lua's step adds to its fields (Ticks, Sum, Max, Watch, Scans, ScanSum, ScanMax;
-- Long: the steps of 8 ms or more), calls CountFrames on every step and Write when From is 60 s old. Write sets the fields back in place.

-- From main.lua (Init): the log, layout.lua's ById, the element list, the map (runemap.lua, nil when it did not load)
-- and the widget search (finder.lua), whose counters the third line reads and sets back. Reports: the finder's table.
-- Actors: main.lua's count of the game's reports of new actors (the bed names), read and set back here too.
local Log, ById, Elements, RuneMap, Finder, Reports, Actors

-- What the mod costs the game, logged every 60 s
local Perf = { From = os.clock(), Ticks = 0, Sum = 0, Max = 0, Watch = 0, Long = 0, Scans = 0, ScanSum = 0, ScanMax = 0 }

-- The cost by part: the time and the Lua memory each one made since the last perf line. main.lua's step and
-- chain.lua's calls take the clock and the count before a part runs and give them to Add after it. KB counts only
-- growth: a collection inside the part would make the count fall, and that is not the part's doing.
local By = {}
-- The runs of one part that took LONG or more, at most 12 a minute, as "name ms (KB)". The KB has its sign: a count
-- that fell inside the run says the collector freed memory in it.
local LONG = 0.008
local Long, LongN = {}, 0
function Perf.Add(name, t0, m0)
    local took, grew = os.clock() - t0, collectgarbage("count") - m0
    local s = By[name]
    if not s then s = { N = 0, Sum = 0, Max = 0, KB = 0 } By[name] = s end
    s.N, s.Sum, s.Max = s.N + 1, s.Sum + took, math.max(s.Max, took)
    if grew > 0 then s.KB = s.KB + grew end
    if took >= LONG then
        LongN = LongN + 1
        if #Long < 12 then Long[#Long + 1] = string.format("%s %.0f ms (%+.0f KB)", name, took * 1000, grew) end
    end
end

-- The line of the parts: the top ones by the field given, as "name ms (max ms, KB)"
local function TopLine(field, n)
    local list = {}
    for name, s in pairs(By) do list[#list + 1] = { Name = name, S = s } end
    table.sort(list, function(a, b) return a.S[field] > b.S[field] end)
    local out = {}
    for i = 1, math.min(n, #list) do
        local s = list[i].S
        out[i] = string.format("%s %.0f ms (max %.1f, %.0f KB)", list[i].Name, s.Sum * 1000, s.Max * 1000, s.KB)
    end
    return table.concat(out, "; ")
end
-- On: once a minute a full collection, and the memory left after it: what the mod holds, not what it has not
-- cleaned yet. A full collection of a big heap takes tens of ms, so this is for a measuring build only.
local FULL_COLLECT = false
-- The game's frame rate beside it, by what RuneMap does. The engine's frame counter
-- against the clock counts every frame, not a sample. Only while the HUD is on screen: menus and loading screens
-- are left out, and so is a step where the state changed.
local FPS_STATES = { "no map", "map every frame", "map every 2nd", "map every 4th" }
local Fps = { By = {} }   -- By: state -> { F = frames, T = seconds }. Frames, At, State: at the last read. Next: when the counter is read next. KSL, GPS: the engine's libraries.
local function FpsState()
    local V = ById("vitals").Instances[1]
    if not (V and V:IsValid() and V:IsVisible()) then return nil end
    if not (RuneMap and RuneMap.Visible) then return FPS_STATES[1] end
    return FPS_STATES[RuneMap.Set.Smooth and 2 or (RuneMap.Set.Fastest and 4 or 3)]
end
local function AddFrames(state, frames, seconds)
    local b = Fps.By[state]
    if not b then b = { F = 0, T = 0 } Fps.By[state] = b end
    b.F, b.T = b.F + frames, b.T + seconds
end
local function CountFrames(now)
    if not Fps.Sampled then
        -- the counter holds every frame since the last read, so twice a second is as exact as every step
        if now < (Fps.Next or 0) then return end
        Fps.Next = now + 0.5
    end
    local state = FpsState()
    if not Fps.Sampled then
        local ok, f = pcall(function()
            if not (Fps.KSL and Fps.KSL:IsValid()) then Fps.KSL = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary") end
            return Fps.KSL:GetFrameCount()
        end)
        if ok and type(f) == "number" then
            if state and state == Fps.State then AddFrames(state, f - Fps.Frames, now - Fps.At) end
            Fps.Frames, Fps.At, Fps.State = f, now, state
            return
        end
        Fps.Sampled = true
        Log("perf: no frame counter (" .. tostring(f) .. "), the FPS comes from one frame's length per step")
    end
    if not state then return end
    local ok, dt = pcall(function()
        if not (Fps.GPS and Fps.GPS:IsValid()) then Fps.GPS = StaticFindObject("/Script/Engine.Default__GameplayStatics") end
        return Fps.GPS:GetWorldDeltaSeconds(ById("vitals").Instances[1])
    end)
    if ok and type(dt) == "number" and dt > 0 then AddFrames(state, 1, dt) end
end

local function PerfLog(now)
    local P, widgets = Perf, 0
    for _, E in ipairs(Elements) do widgets = widgets + #E.Instances end
    Log(string.format("perf: %d ticks, avg %.1f ms, max %.0f ms; world watch avg %.2f ms; %d scans, avg %.0f ms, max %.0f ms; %d widgets; lua %.0f KB",
        P.Ticks, P.Sum / math.max(1, P.Ticks) * 1000, P.Max * 1000, P.Watch / math.max(1, P.Ticks) * 1000,
        P.Scans, P.ScanSum / math.max(1, P.Scans) * 1000, P.ScanMax * 1000, widgets,
        collectgarbage("count")))
    local parts = {}
    for _, s in ipairs(FPS_STATES) do
        local b = Fps.By[s]
        if b and b.T >= 1 and b.F > 0 then
            parts[#parts + 1] = string.format("%s %.0f fps (%.1f ms) for %.0f s", s, b.F / b.T, b.T / b.F * 1000, b.T)
        end
    end
    Log("perf: game " .. (#parts > 0 and table.concat(parts, "; ") or "HUD not on screen"))
    local why = {}
    for k, n in pairs(Finder.Searches.Why) do why[#why + 1] = k .. " " .. n end
    table.sort(why)
    Log(string.format("perf: %d full searches, avg %.0f ms, max %.0f ms (%s); %s", Finder.Searches.N,
        Finder.Searches.Sum / math.max(1, Finder.Searches.N) * 1000, Finder.Searches.Max * 1000, table.concat(why, ", "),
        string.format("%d new widgets reported in %.0f ms, max %.0f ms, %d kept; %d actors reported in %.0f ms", Reports.Seen,
            Reports.Time * 1000, Reports.Max * 1000, Reports.Kept, Actors.N, Actors.Time * 1000)))
    -- the kept lists, as FindClass reads a whole list when the parts are matched again: their size and the longest
    local n, top, topN = 0, "none", 0
    for c in pairs(Reports.Wanted) do
        local k = #(Finder.Found[c] or {})
        n = n + k
        if k > topN then top, topN = c, k end
    end
    Log(string.format("perf: %d widgets in the kept lists, the longest %s with %d; %d scans brought by a kept widget", n, top, topN, Reports.Quick))
    if next(By) then
        Log("perf: by time: " .. TopLine("Sum", 8))
        Log("perf: by memory made: " .. TopLine("KB", 6))
        -- a part that ran long once and little in all is in neither line above: the hitch of a world's start hid so
        Log("perf: by longest run: " .. TopLine("Max", 5))
        By = {}
    end
    Log(string.format("perf: %d steps of %d ms or more; %d long runs: %s", P.Long, LONG * 1000, LongN, table.concat(Long, "; ")))
    Long, LongN = {}, 0
    if FULL_COLLECT then
        local before, t0 = collectgarbage("count"), os.clock()
        collectgarbage("collect")
        Log(string.format("perf: full collection: %.0f KB before, %.0f KB after, %.0f ms", before, collectgarbage("count"), (os.clock() - t0) * 1000))
    end
    Finder.Searches = { N = 0, Sum = 0, Max = 0, Why = {} }
    Reports.Seen, Reports.Kept, Reports.Time, Reports.Max, Reports.Quick = 0, 0, 0, 0, 0
    Actors.N, Actors.Time = 0, 0
    -- in place: main.lua's step writes into this same table
    P.From, P.Ticks, P.Sum, P.Max, P.Watch, P.Long, P.Scans, P.ScanSum, P.ScanMax = now, 0, 0, 0, 0, 0, 0, 0, 0
    Fps.By = {}
end

function Perf.Init(ctx)
    Log, ById, Elements, RuneMap, Finder = ctx.Log, ctx.ById, ctx.Elements, ctx.RuneMap, ctx.Finder
    Reports, Actors = Finder.Reports, ctx.Actors or { N = 0, Time = 0 }
end
Perf.CountFrames, Perf.Write = CountFrames, PerfLog
return Perf
