-- A chain of single delayed calls on the game thread, for a part that must paint about every frame while it moves
-- (xp.lua, compass.lua). The mod's main loop runs about 16 times a second, which is too few for a smooth change. Each call
-- arms the next one and the chain ends by not arming. Not a loop: a loop on the game thread goes on after its function
-- returns true (probe T1, 04-10-2026).
-- A part keeps one table for its chain, { } to start with. Time is the time of the chain's last call. A chain that has not
-- called for LOST seconds is taken as lost (a world change, a long stall), and a new one may start. Each chain has a token:
-- a call that is still queued from a lost chain sees that its token is old and does nothing, so two chains never run.
-- main.lua loads this file with pcall and passes it to those parts as ctx.Chain.

local C = {}

local LOST = 1   -- seconds without a call

-- Start a chain if step should run and none is running. ctx.Soon(ms, fn) is the game thread's delayed call (nil in an old
-- UE4SS: no chain). step(ctx, t) paints; a false result ends the chain. more(ctx, t) says whether to go on.
function C.Run(chain, ctx, ms, step, more)
    local now = os.clock()
    if not (ctx.Soon and more(ctx, now)) or (chain.Time and now - chain.Time < LOST) then return end
    chain.Token = (chain.Token or 0) + 1
    local token = chain.Token
    local function Go()
        if token ~= chain.Token then return end
        local t = os.clock()
        chain.Time = t
        local ok, result = pcall(step, ctx, t)
        if not (ok and result ~= false and more(ctx, t) and pcall(ctx.Soon, ms, Go)) then chain.Time = nil end
    end
    chain.Time = now
    if not pcall(ctx.Soon, ms, Go) then chain.Time = nil end
end

-- true when the chain called within the last "within" seconds: its painting is fresher than the main loop's
function C.Alive(chain, within) return chain.Time ~= nil and os.clock() - chain.Time < within end

-- ends the chain: a call still queued does nothing (a new world)
function C.Stop(chain) chain.Token, chain.Time = (chain.Token or 0) + 1, nil end

return C
