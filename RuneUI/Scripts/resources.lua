-- Ore, herbs, rune essence and rare trees on RuneMap (playtest, 29-09-2026). A shape for each group, since the
-- creatures are the diamonds: ore a brown square, herbs a green triangle, essence a blue circle, rare trees a violet
-- triangle pointing down (tools/make-runemap-art.js; gold before 1.5, too close to the brown ore). Common things stay off the map: stone, berries, flax, oak, ash.
-- An ore rock with no chunks left ("depleted" in the game) and a picked plant hide until they grow back. F8
-- (main.lua) has a switch for each group. runemap.lua calls Scan every few seconds while the map is on screen, the
-- same way as the creatures, and passes itself (M) for the player, the settings, the shapes and its helpers.

local R = {}
local Icons = {}   -- full name -> { Icon, Shown, Group }
local Kinds = {}   -- class name -> the group, or false: decided once per class
local Scans, Warned = 0, false   -- the first scans of each world are logged, with their cost

local RADIUS = 6000   -- 60 m: 100 m showed 41 things at once and crowded the map (playtest, 29-09-2026)
local ADD_PER_SCAN = 12   -- a few new icons per scan, so a full valley does not stall one frame

-- the six wild herbs (wiki, 29-09-2026); the game also spells Kwuarm "Kuarm"
local HERBS = { "Marrentil", "Harralander", "Kwuarm", "Kuarm", "Snapdragon", "Toadflax", "Irit" }

-- class name -> "Ore", "Herbs", "Essence", "Trees" or false. Names from the F7 probe in the game (29-09-2026); yew
-- and magic trees are not seen yet, so theirs are a guess
local function Decide(cls)
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

-- used up: an ore rock with no chunks left, or a plant with nothing to pick (the probe, 29-09-2026)
local function Empty(A)
    local ok, n = pcall(function() return A.PopulatedSpawnComponents:GetArrayNum() end)
    if ok and type(n) == "number" then return n == 0 end
    local ok2, left = pcall(function() return A.RespawnComponent.ResourcesAvailable end)
    return ok2 and left == 0
end

local function AddIcon(M, A, group)
    local T = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = 0, Y = 0, Z = 0 }, Scale3D = { X = 1, Y = 1, Z = 1 } }
    local icon = A:AddComponentByClass(M.H.Obj(M.H.IconClass), false, T, false)
    if not (icon and icon:IsValid()) then return nil end
    pcall(function() icon:SetIconTexture(M.ResTex[group]) end)
    local def = nil
    pcall(function() local s = icon.IconSize def = (type(s) == "number") and s or s.X end)
    local size = (def and def > 0) and def * M.H.Share or 8   -- the creatures' size
    if not pcall(function() icon:SetIconSize(size, size) end) then pcall(function() icon:SetIconSize(size, true) end) end
    return icon
end

function R.Drop()
    for _, c in pairs(Icons) do
        pcall(function() if c.Icon:IsValid() then c.Icon:K2_DestroyComponent(c.Icon) end end)
    end
    Icons = {}
end
-- a new world: the engine has already freed the old icons; only the handles go
function R.Forget() Icons, Scans = {}, 0 end
-- the game's HUD went away (the big map, a menu): hide at once; the next scan decides again
function R.HideAll()
    for _, c in pairs(Icons) do
        c.Shown = nil
        pcall(function() if c.Icon:IsValid() then c.Icon:SetIconVisible(false) end end)
    end
end

function R.Scan(ctx, M)
    local S = M.Set
    if not (S.Ore or S.Herbs or S.Essence or S.Trees) or not M.ResTex then
        if next(Icons) then R.Drop() end   -- all off: no icons and no search
        return
    end
    local t0 = os.clock()
    -- the game's own base class of ore, plants and trees keeps the query small; Actor (everything) if it is not found
    local world = M.H.Obj("/Script/Dominion.WorldActor")
    if not (world and world:IsValid()) then
        world = M.H.Obj("/Script/Engine.Actor")
        if not Warned then Warned = true ctx.Log("resources: no WorldActor class, searching every actor") end
    end
    local types, out = {}, {}
    for t = 0, 15 do types[#types + 1] = t end
    M.H.Obj("/Script/Engine.Default__KismetSystemLibrary"):SphereOverlapActors(M.Pawn, M.Pawn:K2_GetActorLocation(),
        RADIUS, types, world, {}, out)
    local list = M.H.OutActors(out)
    local t1 = os.clock()
    local seen, added, found = {}, 0, 0
    for _, A in ipairs(list) do
        pcall(function()
            local cls = A:GetClass():GetFName():ToString()
            local group = Kinds[cls]
            if group == nil then group = Decide(cls) Kinds[cls] = group end
            if not group then return end
            found = found + 1
            local n = A:GetFullName()
            seen[n] = true
            local c = Icons[n]
            if c and not c.Icon:IsValid() then Icons[n], c = nil, nil end
            if not c then
                if not S[group] or not M.ResTex[group] or added >= ADD_PER_SCAN then return end
                added = added + 1
                local icon = AddIcon(M, A, group)
                if not icon then return end
                c = { Icon = icon, Shown = nil, Group = group }
                Icons[n] = c
            end
            local want = M.Shown == true and S[c.Group] == true and not Empty(A)
            if want ~= c.Shown then
                c.Shown = want
                pcall(function() c.Icon:SetIconVisible(want) end)
            end
        end)
    end
    -- out of reach or gone (a picked herb): its icon goes, and the handle is forgotten before the engine frees it
    for n, c in pairs(Icons) do
        if not seen[n] then
            pcall(function() if c.Icon:IsValid() then c.Icon:K2_DestroyComponent(c.Icon) end end)
            Icons[n] = nil
        end
    end
    Scans = Scans + 1
    if Scans <= 3 then
        ctx.Log(string.format("resources: %d things in reach, %d to show, %d new icons; query %.1f ms, the rest %.1f ms",
            #list, found, added, (t1 - t0) * 1000, (os.clock() - t1) * 1000))
    end
end

return R
