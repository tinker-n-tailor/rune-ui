-- The watch for a new world, and what the mod drops when one comes. main.lua loads this file and gives it its own
-- names (Init); the step calls Watch on every tick, and the hook of a player restart calls Forget.
-- Name, Player and SettleUntil are read by the step and by the panel. This file writes them, and the hook of a player
-- restart in main.lua sets Name.

local M = {}

-- From main.lua (Init): the log, the element list, the widget search (finder.lua), the layout writer (apply.lua),
-- the list of parts, the names of our widgets (engine.lua), the bed watch (beds.lua) and the panel (overlay.lua).
local Log, Elements, Finder, Apply, Parts, Engine, Beds, Overlay
function M.Init(ctx)
    Log, Elements, Finder, Apply, Parts = ctx.Log, ctx.Elements, ctx.Finder, ctx.Apply, ctx.Parts
    Engine, Beds, Overlay = ctx.Engine, ctx.Beds, ctx.Overlay
end

M.Name = nil         -- the local player controller's name; "" while a world is loading
M.Player = nil       -- the local player object lives as long as the game; the quest tracker reads its controller
M.SettleUntil = 0    -- no decorating or building until the new world has settled (os.clock)

-- the local controller, as its link from the local player (Player); nil while there is none
function M.Controller()
    local ok, pc = pcall(function()
        local c = M.Player and M.Player:IsValid() and M.Player.PlayerController
        if c and c:IsValid() and c:IsLocalController() then return c end
    end)
    return ok and pc or nil
end

-- A new world (quit to the main menu, entering a game): drop every handle the mod holds into the old one
-- before anything reads it. The engine frees the old world's objects while it loads the new one, and a
-- crash on quitting to the menu (27-09-2026) came from an old handle. The world is told apart by its player
-- controller; UE4SS's load-map hook crashed on its second call (27-09-2026), so it is not used.
-- sameWorld: a player restart inside a world that still stands, so our own map may be taken off the screen
function M.Forget(sameWorld)
    for _, E in ipairs(Elements) do E.Instances, E.Keys, E.PartsOp, E.PartsW, E.Last = {}, {}, {}, {}, {} end
    Finder.Forget(sameWorld)   -- the last widget search's handles, and the widgets reported since
    Apply.Forget(sameWorld)   -- the bag's widgets, and what it remembers of each widget's opacity and clipping
    Overlay.Forget(sameWorld)   -- the editor panel: new tries to build it, and with a new world a new panel
    for _, P in ipairs(Parts) do
        pcall(P.M.Forget, sameWorld)
        if not sameWorld then P.Error, P.M.ErrorLogged = nil, false end   -- a new world: say it again if it fails again
    end
    if not sameWorld then Beds.Forget() end   -- one look by path per class in the new world
    Engine.NextRound()
    M.SettleUntil = os.clock() + 3
    Log(sameWorld and "player restart: old handles dropped" or "new world: old handles dropped")
end

local function SearchController()
    -- the local player's controller only: in co-op a friend's controller joining or leaving must not look
    -- like a new world; one unreadable controller is skipped, not taken as a change
    for _, P in pairs(FindAllOf("PlayerController") or {}) do
        local ok, n = pcall(function()
            local full = P:GetFullName()
            if not string.find(full, "Default__", 1, true) and P:IsLocalController() then
                M.Player = P.Player
                return full
            end
        end)
        if ok and n then return n end
    end
    return ""
end

-- The local controller's name, read on every tick; "" while a world is loading. The controller goes away the
-- moment a travel starts, before the old world is torn down. Reading the viewport's world instead changed only
-- once the new world stood, and the game crashed on entering a world in between (27-09-2026).
-- A search of all controllers on every tick cost 36 ms a tick on UE4SS builds without hash tables (28-09-2026). So once the
-- local player is known, its link to the controller is read instead (it changed on the same tick as the search in every travel).
function M.ControllerName()
    if not (M.Player and M.Player:IsValid()) then return SearchController() end
    local ok, n = pcall(function()
        local pc = M.Player.PlayerController
        if pc and pc:IsValid() and pc:IsLocalController() then return pc:GetFullName() end
        return ""
    end)
    if ok then return n end
    M.Player = nil
    return SearchController()
end

function M.Watch()
    local name = M.ControllerName()
    if name ~= M.Name then M.Name = name M.Forget(false) end
end

return M
