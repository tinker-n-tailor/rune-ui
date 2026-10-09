-- The game's reports of new actors, for the bed names (bednames.lua). main.lua loads this file, gives it the widget
-- search (Init), hands Find to the bed names, and the step's start calls Watch where the timer starts.
--
-- The bed classes (bednames.lua) load late or never in a session, and a look for a class the game has not loaded
-- walks every object, by path or by name: about 15 ms, twice every 5 s (measured 09-10-2026). So the look by path
-- runs once per world for each class (BedTried), and after that only when the game's reports of new actors say it
-- made a bed (NotifyOnNewObject, registered where the timer starts; BedWatch: it took). The beds of a world come
-- before the world watch sees it, so BedSeen stays across worlds: a look by path that fails drops the entry.
-- Actors: the reports' count and time, for the perf line.

local M = {}

local Log, Finder
function M.Init(ctx) Log, Finder = ctx.Log, ctx.Finder end

local BED_CLASSES = { BP_BaseBuilding_BedRoll_C = true, BP_BaseBuilding_Bed_C = true }
local BedSeen, BedTried, BedWatch = {}, {}, false   -- class name -> true once the game made an actor of it; once looked for by path
M.Actors = { N = 0, Time = 0 }

local function NewActor(A)
    local t0 = os.clock()
    local ok, a = pcall(Finder.ClassAddress, A)
    if ok and a then
        local c = Finder.ClassNameOf(A, a)
        if BED_CLASSES[c] then BedSeen[c] = true end
    end
    M.Actors.N, M.Actors.Time = M.Actors.N + 1, M.Actors.Time + (os.clock() - t0)
end

-- The look by path runs once per world, then waits for the game's report of a bed (BedSeen); without the reports it
-- runs as before.
function M.Find(path)
    local c = string.match(path, "%.([%w_]+):")
    if BedWatch and BedTried[c] and not BedSeen[c] then return end
    BedTried[c] = true
    local o = StaticFindObject(path)
    if o ~= nil and o:IsValid() then return o:GetAddress() end
    BedSeen[c] = nil
end

function M.Watch()
    BedWatch = pcall(NotifyOnNewObject, "/Script/Engine.Actor", NewActor)
    if not BedWatch then Log("actors: no reports; the bed names look for their classes by path") end
end

-- A new world: one look by path per class again.
function M.Forget() BedTried = {} end

return M
