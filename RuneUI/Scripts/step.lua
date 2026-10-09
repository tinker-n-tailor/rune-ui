-- The main loop, on a timer (the game has no per-frame hook we can use): the step that scans for widgets, calls every
-- part, writes the layout and fills the panel. main.lua loads this file, gives it its own names (Init) and calls Start
-- once, where the timer is wanted.

local M = {}

-- From main.lua (Init): the log, the list of parts, the editor's state (Ed), the profile in use, the world watch, the
-- widget search (finder.lua) and the layout writer (apply.lua), the perf counter (perf.lua), the layout's saving
-- (profiles.lua), the F9 panel (overlay.lua), the held arrow (keys.lua), and the parts that the step reads itself.
local Log, Parts, Ed, Prof, World, Finder, Reports, Apply, Perf, Profiles, Overlay, Keys, Beds
local Buffs, Camera, Skin
function M.Init(ctx)
    Log, Parts, Ed, Prof, World = ctx.Log, ctx.Parts, ctx.Ed, ctx.Prof, ctx.World
    Finder, Apply, Perf, Profiles, Overlay, Keys, Beds = ctx.Finder, ctx.Apply, ctx.Perf, ctx.Profiles, ctx.Overlay, ctx.Keys, ctx.Beds
    Reports = Finder.Reports
    Buffs, Camera, Skin = ctx.Buffs, ctx.Camera, ctx.Skin
end

local LastScan = -100
local NextBuffCount = 0
local ApplyErrorLogged = false
local TickAlive = false

-- A scan on the next step: the map asks for it when the editor shows it (runemap.lua).
function M.ScanSoon() LastScan = 0 end

-- The collector, a little at every step. Lua's own pacing waits until the memory has doubled and then, inside
-- whichever part runs at that moment, does one piece of work that it cannot split: 20 to 40 ms for a pile of 40 to
-- 80 MB (measured 09-10-2026). So Lua's pacing is off (Start) and the step itself runs one small piece at its end.
-- After a finished cycle the next one waits for REST KB of new garbage, so the pile stays small and so does that
-- piece. A step that already took BUSY does not collect too, but never more than 8 steps in a row.
local REST, BUSY = 4096, 0.003
local RestUntil, Skipped = nil, 0
local function Collect(stepFrom)
    local t0, m0 = os.clock(), collectgarbage("count")
    if RestUntil and m0 < RestUntil then return end
    if t0 - stepFrom >= BUSY and Skipped < 8 then Skipped = Skipped + 1 return end
    Skipped = 0
    RestUntil = collectgarbage("step", 0) and collectgarbage("count") + REST or nil
    Perf.Add("collector", t0, m0)
end

local LoggedEditMode = false
local function TickBody()
    local now = os.clock()
    if not TickAlive then
        TickAlive = true
        Log("timer running" .. (IsInGameThread and (IsInGameThread() and " on the game thread" or " off the game thread") or ""))
    end
    if Ed.Edit ~= LoggedEditMode then
        LoggedEditMode = Ed.Edit
        Log(Ed.Edit and "edit mode on" or "edit mode off")
        if Ed.Edit then pcall(Overlay.SortOrder) end   -- the list by screen area, as the elements sit now
    end
    World.Watch()   -- first: nothing below may read a handle into a world that is gone
    Perf.Watch = Perf.Watch + (os.clock() - now)
    Perf.CountFrames(now)

    -- the widgets every 2 s, in the editor too: faster scans stuttered when each held a full search (27-09 and
    -- 28-09-2026). The full search inside runs less often (FindAll); sooner scans come from the two cases below.
    -- Sooner when the buff count changes: a new drink took up to 2 s to become its ring. The
    -- count is a few plain numbers; the search it brings runs once per new buff.
    local buffsNew = false
    if now > NextBuffCount then   -- 4 times a second; its own clock, so not every step between scans
        NextBuffCount = now + 0.25
        local okB, b = Buffs and pcall(Buffs.Changed)
        buffsNew = okB and b or false
    end
    -- Sooner too when the game reported a widget that a part uses: the drink's entry can come after its count
    -- changed, and the ring then waited for the 2 s scan. 4 scans a second at most, as a
    -- new HUD comes as some hundred widgets over a few seconds.
    local quick = Reports.Fresh and now - LastScan > 0.25
    local scanned = now - LastScan > 2.0 or buffsNew or quick
    if scanned then
        if quick then Reports.Quick = Reports.Quick + 1 end   -- for the perf line: a class the game makes all the time would show here
        LastScan, Reports.Fresh = now, false
        local scanFrom, m0 = os.clock(), collectgarbage("count")
        local okFind, errFind = pcall(Finder.FindAll, buffsNew)
        Perf.Add("find", scanFrom, m0)
        if not okFind and not ApplyErrorLogged then ApplyErrorLogged = true Log("finding widgets failed: " .. tostring(errFind)) end
        if now > World.SettleUntil then
            -- the parts that build on the game's widgets (the avatar, the bars, the buffs), once per scan
            for _, P in ipairs(Parts) do
                if P.M.Scan then
                    local t0, m1 = os.clock(), collectgarbage("count")
                    local okS, errS = pcall(P.M.Scan, P.Ctx)
                    Perf.Add(P.Name .. " scan", t0, m1)
                    if not okS and not P.M.ErrorLogged then P.M.ErrorLogged = true P.Error = tostring(errS) Log(P.Name .. " scan failed: " .. P.Error) end
                end
            end
            if buffsNew and Buffs then Buffs.NextRings = 0 end   -- a new buff or drink ring is right in this step too
        end
        local scan = os.clock() - scanFrom
        Perf.Scans, Perf.ScanSum, Perf.ScanMax = Perf.Scans + 1, Perf.ScanSum + scan, math.max(Perf.ScanMax, scan)
    end

    -- every part's step, in the order of the list; the immersive mode is the last that draws, before ApplyAll reads its opacity
    for _, P in ipairs(Parts) do
        if P.M.Tick and now > World.SettleUntil and (P.Early or now > 20) then
            local t0, m0 = os.clock(), collectgarbage("count")
            local okP, errP = pcall(P.M.Tick, P.Ctx)
            Perf.Add(P.Name, t0, m0)
            if not okP and not P.M.ErrorLogged then P.M.ErrorLogged = true P.Error = tostring(errP) Log(P.Name .. " step failed: " .. P.Error) end
        end
    end
    pcall(Keys.HoldMove, now)
    local applyFrom, applyM = os.clock(), collectgarbage("count")
    local okApply, errApply = pcall(Apply.All, scanned, Ed.Edit, Ed.Map, Ed.Selected)   -- a scan step writes every move and size again (ApplyOne)
    Perf.Add("apply", applyFrom, applyM)
    if not okApply and not ApplyErrorLogged then ApplyErrorLogged = true Log("apply failed: " .. tostring(errApply)) end

    if Camera then pcall(Camera.Commit) end   -- the camera settings are saved here, whatever camera.lua's step does
    -- a row of F6 or F5 that the layout holds was changed: the flag goes down first, so a change during the save is saved next
    if Camera and Camera.LayoutDirty then Camera.LayoutDirty = false Ed.Save = true end
    if Skin and Skin.LayoutDirty then Skin.LayoutDirty = false Ed.Save = true end
    if Ed.Save then Ed.Save = false Profiles.SaveLayout() end
    if Prof.Wanted then Prof.Wanted = false pcall(Prof.Next) end

    local overlayFrom, overlayM = os.clock(), collectgarbage("count")
    Overlay.Update(now)
    Perf.Add("overlay", overlayFrom, overlayM)

    Collect(now)
    local took = os.clock() - now
    Perf.Ticks, Perf.Sum, Perf.Max = Perf.Ticks + 1, Perf.Sum + took, math.max(Perf.Max, took)
    if took >= 0.008 then Perf.Long = Perf.Long + 1 end
    if now - Perf.From > 60 then Perf.Write(now) end
end

local TickErrorLogged = false
local function TimerStep()   -- not "Step": that is the editor's move step
    local ok, err = pcall(TickBody)
    if not ok and not TickErrorLogged then TickErrorLogged = true Log("timer step failed: " .. tostring(err)) end
end

-- The whole step on the game thread, and the game's reports of new widgets (Reports) with it: the step and the
-- reports run on the game thread, one after the other. A timer on UE4SS's own thread ran Lua at the same moment as
-- the game thread and crashed the game inside UE4SS.dll (27-09 and 28-09-2026, "Ref was not function" in the log).
-- The three functions come with the UE4SS experimental build that the README asks for. Without them the mod does not
-- start: the log says why, and the player updates UE4SS.
function M.Start()
    if LoopInGameThreadWithDelay and ExecuteInGameThreadWithDelay and NotifyOnNewObject
        and pcall(ExecuteInGameThreadWithDelay, 2000, function()
            if not pcall(NotifyOnNewObject, "/Script/UMG.UserWidget", Finder.NewWidget) then
                Log("widgets: this UE4SS gives no reports of new widgets; Rune UI did not start. Install the latest UE4SS experimental build")
                return
            end
            Beds.Watch()
            collectgarbage("stop")   -- from here the step collects (Collect)
            LoopInGameThreadWithDelay(50, TimerStep)
            Log("timer: on the game thread")
        end) then
        -- the log line comes from the call above, after the reports took
    else
        Log("timer: old UE4SS; Rune UI did not start. Install the latest UE4SS experimental build (see README.txt)")
    end
end

return M
