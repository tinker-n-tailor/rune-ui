-- The things near the player: creatures, ore, herbs, rune essence and rare trees. One place finds them and decides
-- what each one is, so the map's icons (runemap.lua, resources.lua) and the compass's marks (compass.lua) agree.
-- The rules came from the map's own scans (playtest, 29-09-2026) and moved here as they were.
-- Creatures: group "Enemy" or "Calm" (neutral animals). Resources: group "Ore", "Herbs", "Essence" or "Trees".
-- main.lua loads this file with pcall and gives it to the map and to the compass.

local N = {}

N.CREATURE_RADIUS = 10000   -- 100 m; 300 m crowded the map (playtest, 29-09-2026)
N.RESOURCE_RADIUS = 6000    -- 60 m: 100 m showed 41 things at once and crowded the map (playtest, 29-09-2026)

-- the six wild herbs (wiki, 29-09-2026); the game also spells Kwuarm "Kuarm"
local HERBS = { "Marrentil", "Harralander", "Kwuarm", "Kuarm", "Snapdragon", "Toadflax", "Irit" }

-- ponytail: neutral by the creature's class name; switch to the game's own flag if one is found
local NEUTRAL = { "Deer", "Stag", "Rabbit", "Hare", "Chicken", "Sheep", "Cow", "Goat", "Frog", "Bird", "Fish", "Magpie", "Kebbit",
    "Critter", "Ambient", "Passive", "Squirrel" }

---------------------------------------------------------------- what a thing is, without the game (tools/test-nearby.js)

-- class name -> "Ore", "Herbs", "Essence", "Trees" or false. Names from the F7 probe in the game (29-09-2026); yew
-- and magic trees are not seen yet, so theirs are a guess
function N.Decide(cls)
    local ore = string.match(cls, "^BP_OreNode_(%a+)")
    if ore then return ore ~= "Stone" and "Ore" end   -- stone is everywhere (playtest)
    if string.find(cls, "RuneEssence", 1, true) then return "Essence" end
    for _, h in ipairs(HERBS) do if string.find(cls, h, 1, true) then return "Herbs" end end
    if string.find(cls, "AnimaInfusedBark", 1, true) then return "Trees" end
    -- the dead tree is the bare ash (the wiki: hollow bark and ash logs); yew and magic are late and rare
    if string.find(cls, "Tree", 1, true) and (string.find(cls, "Ash_Bare", 1, true) or string.find(cls, "Yew", 1, true)
        or string.find(cls, "Magic", 1, true)) then return "Trees" end
    return false
end

function N.IsNeutral(kind)
    for _, n in ipairs(NEUTRAL) do
        if string.find(kind, n, 1, true) then return true end
    end
    return false
end

---------------------------------------------------------------- the game

local function Obj(path) return StaticFindObject(path) end
local Kinds = {}   -- class name -> the resource group, or false: decided once per class

-- used up: an ore rock with no chunks left, or a plant with nothing to pick (the probe, 29-09-2026)
local function Empty(A)
    local ok, n = pcall(function() return A.PopulatedSpawnComponents:GetArrayNum() end)
    if ok and type(n) == "number" then return n == 0 end
    local ok2, left = pcall(function() return A.RespawnComponent.ResourcesAvailable end)
    return ok2 and left == 0
end

local function Dead(A)
    local ok, v = pcall(function() return A:IsDead() end)
    if ok and type(v) == "boolean" then return v end
    local ok2, v2 = pcall(function() return A.bIsDead end)
    return ok2 and v2 == true
end

-- An out parameter from UE4SS 3.0.1: it fills the table passed in with the actors, 1 to n (log of 29-09-2026).
-- An element may come as the object or as a holder of it (e:get()).
local function OutActors(out)
    local list = {}
    for _, e in ipairs(out) do
        if pcall(function() return e:GetFullName() end) then list[#list + 1] = e
        else
            local ok, o = pcall(function() return e:get() end)
            if ok and o then list[#list + 1] = o end
        end
    end
    return list
end

-- The creatures near the player (playtest, 29-09-2026: look only around the player). The walk through every object
-- the game holds (FindAllOf) took up to 30 ms (28-09-2026). The game's overlap query gives only the pawns within
-- CREATURE_RADIUS of the player. If UE4SS cannot make that call, the game's own list of creatures, then the walk.
-- The first way that works stays.
local CREATURE_WAYS = {
    { "the overlap query", function(cls, pawn)
        local out = {}
        -- true when anything overlaps; then an empty table means UE4SS gave the list some other way
        local hit = Obj("/Script/Engine.Default__KismetSystemLibrary"):SphereOverlapActors(pawn,
            pawn:K2_GetActorLocation(), N.CREATURE_RADIUS, { 2 }, cls, {}, out)   -- 2: the pawn object type
        local list = OutActors(out)
        if hit == true and #list == 0 then error("an overlap, but no actors in the table") end
        return list
    end },
    { "the game's list", function(cls, pawn)
        local out = {}
        Obj("/Script/Engine.Default__GameplayStatics"):GetAllActorsOfClass(pawn, cls, out)
        return OutActors(out)
    end },
    { "the walk", function() return FindAllOf("DominionAICharacter") or {} end },
}
local Way, WayLogged = nil, nil

local function Actors(ctx, pawn)
    local cls = Obj("/Script/Dominion.DominionAICharacter")
    for i = Way or 1, #CREATURE_WAYS do
        local way = CREATURE_WAYS[i]
        local ok, list = pcall(function()
            if i < 3 and not (cls and cls:IsValid()) then error("no creature class") end
            return way[2](cls, pawn)
        end)
        if ok then
            if WayLogged ~= i then WayLogged = i ctx.Log("nearby: creatures found by " .. way[1]) end
            Way = i
            return list
        end
        ctx.Log("nearby: creatures by " .. way[1] .. " failed: " .. tostring(list))
        Way = i + 1
    end
    return {}
end

-- The creatures within CREATURE_RADIUS of the pawn: { A, Name, Group, Dead }, a dead one included. Only creatures of
-- the world's own level (the class default objects are left out).
function N.Creatures(ctx, pawn)
    local out = {}
    for _, A in pairs(Actors(ctx, pawn)) do
        pcall(function()
            local name = A:GetFullName()
            if not string.find(name, ":PersistentLevel.", 1, true) or string.find(name, "Default__", 1, true) then return end
            local group = N.IsNeutral(A:GetClass():GetFName():ToString()) and "Calm" or "Enemy"
            out[#out + 1] = { A = A, Name = name, Group = group, Dead = Dead(A) }
        end)
    end
    return out
end

local Warned = false

-- The ore, plants and trees within RESOURCE_RADIUS of the pawn, that belong to a group: { A, Name, Group, Empty }. The
-- second value is how many actors the query found, of any kind.
function N.Resources(ctx, pawn)
    -- the game's own base class of ore, plants and trees keeps the query small; Actor (everything) if it is not found
    local world = Obj("/Script/Dominion.WorldActor")
    if not (world and world:IsValid()) then
        world = Obj("/Script/Engine.Actor")
        if not Warned then Warned = true ctx.Log("nearby: no WorldActor class, searching every actor") end
    end
    local types, found = {}, {}
    for t = 0, 15 do types[#types + 1] = t end
    Obj("/Script/Engine.Default__KismetSystemLibrary"):SphereOverlapActors(pawn, pawn:K2_GetActorLocation(),
        N.RESOURCE_RADIUS, types, world, {}, found)
    local list, out = OutActors(found), {}
    for _, A in ipairs(list) do
        pcall(function()
            local cls = A:GetClass():GetFName():ToString()
            local group = Kinds[cls]
            if group == nil then group = N.Decide(cls) Kinds[cls] = group end
            if group then out[#out + 1] = { A = A, Name = A:GetFullName(), Group = group, Empty = Empty(A) } end
        end)
    end
    return out, #list
end

-- a new world: a way that failed while it loaded gets a new try
function N.Forget() Way, WayLogged = nil, nil end

return N
