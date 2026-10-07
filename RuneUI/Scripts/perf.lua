-- The perf lines in UE4SS.log, every 60 s: what the mod costs the game, the game's frame rate beside it, and what the
-- widget search did. main.lua loads this file and gives it its own names (Init). The table this file returns is the
-- counter of the step's times: main.lua's step adds to its fields (Ticks, Sum, Max, Watch, Scans, ScanSum, ScanMax),
-- calls CountFrames on every step and Write when From is 60 s old. Write sets the fields back in place.

-- From main.lua (Init): the log, layout.lua's ById, the element list, the map (runemap.lua, nil when it did not load)
-- and the widget search (finder.lua), whose counters the third line reads and sets back. Reports: the finder's table.
local Log, ById, Elements, RuneMap, Finder, Reports

-- What the mod costs the game, logged every 60 s
local Perf = { From = os.clock(), Ticks = 0, Sum = 0, Max = 0, Watch = 0, Scans = 0, ScanSum = 0, ScanMax = 0 }
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
        Reports.On and string.format("%d new widgets reported in %.0f ms, max %.0f ms, %d kept", Reports.Seen,
            Reports.Time * 1000, Reports.Max * 1000, Reports.Kept) or "no reports, timed search"))
    if Reports.On then
        -- the kept lists, as FindClass reads a whole list when the parts are matched again: their size and the longest
        local n, top, topN = 0, "none", 0
        for c in pairs(Reports.Wanted) do
            local k = #(Finder.Found[c] or {})
            n = n + k
            if k > topN then top, topN = c, k end
        end
        Log(string.format("perf: %d widgets in the kept lists, the longest %s with %d; %d scans brought by a kept widget", n, top, topN, Reports.Quick))
    end
    Finder.Searches = { N = 0, Sum = 0, Max = 0, Why = {} }
    Reports.Seen, Reports.Kept, Reports.Time, Reports.Max, Reports.Quick = 0, 0, 0, 0, 0
    -- in place: main.lua's step writes into this same table
    P.From, P.Ticks, P.Sum, P.Max, P.Watch, P.Scans, P.ScanSum, P.ScanMax = now, 0, 0, 0, 0, 0, 0, 0
    Fps.By = {}
end

function Perf.Init(ctx)
    Log, ById, Elements, RuneMap, Finder = ctx.Log, ctx.ById, ctx.Elements, ctx.RuneMap, ctx.Finder
    Reports = Finder.Reports
end
Perf.CountFrames, Perf.Write = CountFrames, PerfLog
return Perf
