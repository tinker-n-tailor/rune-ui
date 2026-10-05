-- The immersive camera (1.8): reads what the player does and writes the camera's distance and side. The rules and
-- the settings are in camerarules.lua (ctx.Rules); this file only talks to the game.
-- What the live game showed (05-10-2026): a write to the player's own camera arm is undone every frame, but the camera
-- follows the profile data assets, so the walking and the sprinting profile are written. The assets are shared in
-- memory and nothing goes to disk: the game's values are kept and put back when the camera goes off, when the immersive
-- mode goes off and on a new world. The lock-on view is its own actor with its own arm, and a write there stays.
-- A new distance is written once, as it is: the game blends the camera to it by itself in about 0.5 to 0.7 s, as it does
-- between its own profiles (Ivan's play test, 05-10-2026). The mod's own glide, a spring written on every frame, looked
-- choppy beside that and is gone.
-- The signals: the combat switch, the actors in the hands, and the HUD reticle (a bow's aim or a staff's cast: the
-- combat switch never went on with those). Fishing, swimming and the rest keep the game's own profiles. The sprint is
-- the game's own: its sprinting profile has the configured sprint distance, and the game moves the camera in and out of
-- a sprint itself.
-- Nothing runs while the camera is off. main.lua loads this file with pcall, so an error here leaves the rest of the mod running.

local M = {}

local WALK = "/Game/Gameplay/Character/Data/DA_DefaultLocomotionCameraProfile.DA_DefaultLocomotionCameraProfile"
local SPRINT = "/Game/Gameplay/Character/Data/DA_OnFootSprintingCameraProfile.DA_OnFootSprintingCameraProfile"
local CLASSES = { Combat = "/Script/Dominion.PlayerCombatModeComponent",
    Equip = "/Script/Dominion.PlayerEquipmentComponent", Lock = "/Script/Dominion.LockOnTargetingComponent" }
local NO_RETICLE = "camera: no reticle switcher, ranged zoom follows the combat switch"
local RETICLE_LINES = 40   -- "camera: reticle" lines a game start, at most

local Mem = nil          -- camerarules' memory, made on first use
local Comp = {}          -- the pawn's components: Combat, Equip, Lock; Pawn and its address
local Hands = {}         -- the last class name read for each hand's actor, by address: a name is not read every step
-- the HUD reticle's switcher: Switcher, Names (a child's class name by index: the children never change), Name (the
-- active one), and Fails and RetryAt for ctx.MayTry
local Ret = { Names = {} }
local ReticleLines = 0   -- not reset by a new world: the cap is per game start
local Orig = {}          -- the game's values by name (walk, sprint, lock): { Arm, X, Y, Z }
local State = { Immersive = true }   -- the readings of a step, one table for the whole session
local Logged = {}
local function Once(ctx, key, msg) if not Logged[key] then Logged[key] = true ctx.Log(msg) end end
local function Ok(o) return o ~= nil and o:IsValid() end

M.Applied = false
-- the perf line: the steps in its minute; From 0 until the camera runs
local function NewPerf(now) return { From = now, N = 0, Sum = 0, Max = 0 } end
M.Perf = NewPerf(0)

-- the two profile assets, found once and checked before each use; a new world finds them again (Forget)
local Assets = {}
local function Asset(path)
    local P = Assets[path]
    if Ok(P) then return P end
    P = StaticFindObject(path)
    if Ok(P) then Assets[path] = P return P end
end

-- the component of the class at path on the pawn; the list is a table or the game's array, as in the preview
local function Component(pawn, path)
    local cls = StaticFindObject(path)
    if not Ok(cls) then return nil end
    local list, found = pawn:K2_GetComponentsByClass(cls), nil
    local function Take(e)
        local C = e
        if not pcall(function() return e:GetFullName() end) then C = e:get() end
        if C and C:IsValid() then found = C end
    end
    if type(list) == "table" then for _, e in ipairs(list) do Take(e) end
    elseif list then list:ForEach(function(_, e) Take(e) end) end
    return found
end

-- the components again when the pawn changed or one went away; at most every 2 s while one is missing
local function Find(ctx, pawn, now)
    local addr = pawn:GetAddress()
    if Comp.Addr == addr and Ok(Comp.Combat) and Ok(Comp.Equip) and Ok(Comp.Lock) then return end
    if Comp.Addr == addr and now < (Comp.Next or 0) then return end
    Comp = { Addr = addr, Pawn = pawn, Next = now + 2 }
    for k, path in pairs(CLASSES) do
        local ok, c = pcall(Component, pawn, path)
        if ok then Comp[k] = c end
        if not (ok and c) then Once(ctx, "no" .. k, "camera: no " .. k .. " component on the pawn") end
    end
end

local function Held(A, hand)
    if not Ok(A) then Hands[hand .. "A"], Hands[hand] = nil, nil return nil end   -- an empty hand: a new actor may take the old address
    local addr = A:GetAddress()
    if Hands[hand .. "A"] ~= addr then Hands[hand .. "A"], Hands[hand] = addr, A:GetClass():GetFName():ToString() end
    return Hands[hand]
end

-- The switcher of the HUD reticle (WBP_HUD_ReticleWidget_C, its child ReticleSwitcher), found once and checked before
-- each use. A search that finds nothing tries again 10 s later, 3 times a world (ctx.MayTry); then the ranged zoom
-- follows the combat switch alone, and the log says so once.
local function Switcher(ctx)
    if Ok(Ret.Switcher) then return Ret.Switcher end
    Ret.Switcher, Ret.Names, Ret.Name = nil, {}, nil
    if (Ret.Fails or 0) >= 3 or not (ctx.Reticle and ctx.Find) then Once(ctx, "noreticle", NO_RETICLE) return nil end
    if not ctx.MayTry(Ret) then return nil end
    local ok, S = pcall(function() return ctx.Find(ctx.Reticle(), "ReticleSwitcher") end)
    if ok and Ok(S) then Ret.Switcher = S return S end
    ctx.Failed(Ret)
    if Ret.Fails >= 3 then Once(ctx, "noreticle", NO_RETICLE) end
end

-- True while the reticle of a bow's aim or a staff's cast shows: one call a step for the active index, and the class
-- name of a child read once. A line in the log when the active reticle changes.
local function Aiming(ctx)
    local S = Switcher(ctx)
    if not S then return false end
    local i = S:GetActiveWidgetIndex()
    local name = Ret.Names[i]
    if not name then
        local W = S:GetChildAt(i)
        name = Ok(W) and W:GetClass():GetFName():ToString() or "none"
        Ret.Names[i] = name
    end
    if name ~= Ret.Name then
        Ret.Name = name
        if ReticleLines < RETICLE_LINES then ReticleLines = ReticleLines + 1 ctx.Log("camera: reticle " .. name) end
    end
    return ctx.Rules.AimReticle(name)
end

-- one step's readings into State; false when there is no pawn yet
local function Read(ctx, now)
    local pc = ctx.Controller()
    local pawn = pc and pc.Pawn
    if not Ok(pawn) then return false end
    Find(ctx, pawn, now)
    local s = State
    s.Combat = Ok(Comp.Combat) and Comp.Combat.bIsInCombatMode == true
    s.Right, s.Left = nil, nil
    if Ok(Comp.Equip) then
        s.Right = Held(Comp.Equip.HeldEquipmentActorRight, "R")
        s.Left = Held(Comp.Equip.HeldEquipmentActorLeft, "L")
    end
    -- its own pcall: a reticle that cannot be read must not stop the camera. It counts as a failed search.
    local ok, aim = pcall(Aiming, ctx)
    if not ok then
        Once(ctx, "reticle", "camera: reading the reticle failed: " .. tostring(aim))
        Ret.Switcher = nil
        ctx.Failed(Ret)
    end
    s.Aiming = ok and aim == true
    return true
end

-- The game's values, once per session. Kept in a shared variable of UE4SS too: a restart of the mods while the game
-- runs starts this file again with the assets still as the old run left them, and those must not pass as the game's.
local function Saved(ctx, name)
    local saved = ctx.Shared and ctx.Shared(name)
    local a, x, y, z = string.match(tostring(saved), "^(%-?[%d%.]+),(%-?[%d%.]+),(%-?[%d%.]+),(%-?[%d%.]+)$")
    if a then return { Arm = tonumber(a), X = tonumber(x), Y = tonumber(y), Z = tonumber(z) } end
end

local function Keep(ctx, name, arm, so)
    if Orig[name] then return Orig[name] end
    local saved = Saved(ctx, name)
    if saved then Orig[name] = saved
    else
        Orig[name] = { Arm = arm, X = so.X, Y = so.Y, Z = so.Z }
        if ctx.Shared then ctx.Shared(name, string.format("%.3f,%.3f,%.3f,%.3f", arm, so.X, so.Y, so.Z)) end
        ctx.Log(string.format("camera: the game's %s camera kept, distance %.0f, side %.0f", name, arm, so.Y))
    end
    return Orig[name]
end

-- a profile asset to distance arm and side; a value is written only when it changed
local function Profile(ctx, name, path, arm, side)
    local P = Asset(path)
    if not P then Once(ctx, "asset" .. name, "camera: no " .. name .. " camera profile") return end
    if not Orig[name] then Keep(ctx, name, P.ArmLength, P.SocketOffset) end
    if math.abs(P.ArmLength - arm) > 0.05 then P.ArmLength = arm end
    local so = P.SocketOffset
    if math.abs(so.Y - side) > 0.05 then P.SocketOffset = { X = so.X, Y = side, Z = so.Z } end
end

-- the lock-on view's own arm: the same distance and side as the view the player is in
local function LockOn(ctx, arm, side)
    if not Ok(Comp.Lock) then return end
    local A = Comp.Lock.LockOnCameraActor
    if not Ok(A) then return end
    local S = A.SpringArm
    if not Ok(S) then return end
    if not Orig.lock then Keep(ctx, "lock", S.TargetArmLength, S.SocketOffset) end
    M.Arm = S
    local so = S.SocketOffset
    if math.abs(S.TargetArmLength - arm) > 0.5 or math.abs(so.Y - side) > 0.5 then
        S.TargetArmLength = arm
        S.SocketOffset = { X = so.X, Y = side, Z = so.Z }
    end
end

local function Back(P, o)
    if not (P and o) then return end
    P.ArmLength = o.Arm
    P.SocketOffset = { X = o.X, Y = o.Y, Z = o.Z }
end

-- the game's camera back. lockToo: the lock-on arm too, only while its world still stands.
local function Restore(ctx, lockToo)
    pcall(Back, Asset(WALK), Orig.walk)
    pcall(Back, Asset(SPRINT), Orig.sprint)
    if lockToo and Ok(M.Arm) and Orig.lock then
        pcall(function()
            local so = M.Arm.SocketOffset
            M.Arm.TargetArmLength = Orig.lock.Arm
            M.Arm.SocketOffset = { X = so.X, Y = Orig.lock.Y, Z = so.Z }
        end)
    end
    M.Arm, M.Applied, M.View, M.Perf, M.Checked = nil, false, nil, NewPerf(0), true
    if Mem then ctx.Rules.Step(Mem, { Immersive = false }, os.clock()) end   -- forgets the fight
    ctx.Log("camera: the game's camera back")
end

-- A run that started while the assets still held the values of an earlier run (a restart of the mods) and does not
-- apply (camera or immersive mode off): the game's values saved by that run are written back, once. True when done.
local function Leftover(ctx)
    local done = true
    for name, path in pairs({ walk = WALK, sprint = SPRINT }) do
        local o = Saved(ctx, name)
        local P = o and Asset(path)
        if P then pcall(Back, P, o) ctx.Log("camera: the game's " .. name .. " camera put back after a restart of the mods")
        elseif o then done = false end   -- the asset is not there yet: looked for again
    end
    return done
end

function M.Forget(sameWorld)
    M.Arm = nil
    Comp, Hands, Ret = {}, {}, { Names = {} }
    if not sameWorld then
        Assets = {}
        -- the assets are not the world's: they are put back now, and given again once the new world runs
        if M.Applied and M.Ctx then Restore(M.Ctx, false) end
        Logged = {}
    end
end

function M.Tick(ctx)
    M.Ctx = ctx
    local R = ctx.Rules
    local immersive = ctx.Immersive()
    if not (R.Set.on and immersive) then
        if M.Applied then Restore(ctx, true)
        elseif not M.Checked then M.Checked = Leftover(ctx) end
        return
    end
    local now = os.clock()
    Mem = Mem or R.NewMemory()
    if M.Perf.From == 0 then M.Perf.From = now end   -- the minute of the perf line starts with the camera
    local ok, got = pcall(Read, ctx, now)
    if not ok then Once(ctx, "read", "camera: reading the player failed: " .. tostring(got)) return end
    if not got then return end   -- no pawn yet
    local out = R.Step(Mem, State, now)
    if not out.Active then return end
    M.Applied = true
    Profile(ctx, "walk", WALK, out.Walk, out.Side)
    Profile(ctx, "sprint", SPRINT, out.Sprint, out.Side)
    local okL, errL = pcall(LockOn, ctx, out.Lock, out.Side)
    if not okL then Once(ctx, "lock", "camera: lock-on view failed: " .. tostring(errL)) end
    -- a line when the view changes, for the play test: with the reticle lines it shows that an aim or a cast starts
    -- the ranged view
    local view = out.View
    if view ~= M.View then
        M.View = view
        ctx.Log(string.format("camera: %s, distance %.0f (right hand %s, left hand %s)", view, out.Lock, tostring(State.Right), tostring(State.Left)))
    end
    local P, took = M.Perf, os.clock() - now
    P.N, P.Sum, P.Max = P.N + 1, P.Sum + took, math.max(P.Max, took)
    if now - P.From > 60 then
        ctx.Log(string.format("perf: camera %d steps, avg %.3f ms, max %.2f ms", P.N, P.Sum / math.max(1, P.N) * 1000, P.Max * 1000))
        M.Perf = NewPerf(now)
    end
end

return M
