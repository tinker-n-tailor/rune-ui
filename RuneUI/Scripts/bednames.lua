-- The name of a claimed bed roll or bed. The game shows "Ann'sBed Roll": its text for the owner,
-- "{Owner}'s", goes before "Bed Roll" with no space (the game's string table ST_WorldInteractions: Bed.OwnerFormat,
-- Bed.BedrollOwner, Bed.BedOwner). The prompt on the screen only shows what the bed roll's GetDisplayName gives, and
-- the game writes it again all the time: a new text in the prompt was gone 2 s later (02-10-2026).
-- So the mod hooks GetDisplayName. The hook runs after the game's function. UE4SS gives it no return value, so the
-- hook asks the bed roll for its name again, and gives back the name with the space. UE4SS puts that in place of
-- the game's name (probe of 02-10-2026: the prompt showed the name with the space).
-- The game loads a bed's class with a world: Tick looks for the function until it is there. After a leave to the
-- main menu and a new entry into the world, the function sat at a new address (02-10-2026): after a new world
-- Tick looks again, and hooks a function at a new address. Only the newest hook of a function does the work, as
-- UE4SS may still call the older ones.
-- Pure Lua: main.lua gives the game's calls through ctx, so tools/test-bednames.js runs it without the game.

local M = { Hooked = {}, Newest = {}, Next = 0 }   -- Hooked: path -> the address of the function that has the hook

local DIR = "/Game/Gameplay/BaseBuilding/Actors/Props/Cosiness/"
local FUNCS = { DIR .. "BP_BaseBuilding_BedRoll.BP_BaseBuilding_BedRoll_C:GetDisplayName",
    DIR .. "BP_BaseBuilding_Bed.BP_BaseBuilding_Bed_C:GetDisplayName" }
local EVERY = 5   -- seconds between two looks for a function that the game did not load yet

-- A space after the last "'s" when a letter comes right after it: the owner's part ends there, so an owner with
-- "'s" inside the name ("It'sMe") keeps the name. A name without an owner ("Bed Roll") stays as it is, and so does
-- a name that has the space.
-- ponytail: a pattern, not the game's string table. Wrong in a game language whose bed name has no "'s", for an
-- owner with "'s" inside the name; read the owner's name from the bed (GetClaimingCharacterName) if that shows.
function M.Fix(name)
    local _, e = string.find(name, ".*'s")
    if e and string.find(name, "^%S", e + 1) then return string.sub(name, 1, e) .. " " .. string.sub(name, e + 1) end
    return name
end

-- mine: this hook's number. Tick writes it to M.Newest when UE4SS took the hook.
local function Hook(ctx, path, mine)
    return function(self)
        if M.In or M.Newest[path] ~= mine then return end   -- In: the call from inside this hook, the game's own name goes through
        M.In = true
        local ok, name = pcall(function() return self:get():GetDisplayName():ToString() end)
        M.In = false
        if not ok or type(name) ~= "string" then return end
        local fixed = M.Fix(name)
        if fixed == name then return end
        local okT, text = pcall(ctx.Text, fixed)
        if okT then return text end
    end
end

-- ctx: Log, Find(path) the address of that object when the game has loaded it, Hook (UE4SS's RegisterHook), Text
-- (FText). An error of Hook goes up to main.lua after both functions had their turn: main.lua logs it once in each
-- world and shows it in the F9 panel. Tick tries that function again 5 s later.
function M.Tick(ctx)
    local now = os.clock()
    if M.Done or now < M.Next then return end
    M.Next = now + EVERY
    local left, err = 0, nil
    for _, path in ipairs(FUNCS) do
        local at = ctx.Find(path)
        if at and M.Hooked[path] ~= at then
            local mine = (M.Newest[path] or 0) + 1
            local ok, e = pcall(ctx.Hook, path, Hook(ctx, path, mine))
            if ok then
                M.Hooked[path], M.Newest[path] = at, mine
                ctx.Log("bed names: hook on " .. string.match(path, "([%w_]+):"))
            else
                at, err = nil, e
            end
        end
        if not at then left = left + 1 end
    end
    M.Done = left == 0
    if err then error(err, 0) end
end

-- A new world: look again. A function at the address that has the hook gets no second one.
function M.Forget(sameWorld) if not sameWorld then M.Done = false end end

return M
