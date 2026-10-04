-- Ore, herbs, rune essence and rare trees on RuneMap (playtest, 29-09-2026). A shape for each group, since the
-- creatures are the diamonds: ore a brown square, herbs a green triangle, essence a blue circle, rare trees a violet
-- triangle pointing down (tools/make-runemap-art.js; gold before 1.5, too close to the brown ore). Common things stay off the map: stone, berries, flax, oak, ash.
-- An ore rock with no chunks left ("depleted" in the game) and a picked plant hide until they grow back. F8
-- (main.lua) has a switch for each group. runemap.lua calls Scan every few seconds while the map is on screen, the
-- same way as the creatures, and passes itself (M) for the player, the settings, the shapes and its helpers. What a
-- thing is, and which ones are near, nearby.lua decides (M.Near); the compass uses it too.

local R = {}
local Icons = {}   -- full name -> { Icon, Shown, Group }
local Scans = 0   -- the first scans of each world are logged, with their cost

local ADD_PER_SCAN = 12   -- a few new icons per scan, so a full valley does not stall one frame

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
    if not (S.Ore or S.Herbs or S.Essence or S.Trees) or not M.ResTex or not M.Near then
        if next(Icons) then R.Drop() end   -- all off: no icons and no search
        return
    end
    local t0 = os.clock()
    local list, queried = M.Near.Resources(ctx, M.Pawn)
    local t1 = os.clock()
    local seen, added = {}, 0
    for _, e in ipairs(list) do
        pcall(function()
            local group, n = e.Group, e.Name
            seen[n] = true
            local c = Icons[n]
            if c and not c.Icon:IsValid() then Icons[n], c = nil, nil end
            if not c then
                if not S[group] or not M.ResTex[group] or added >= ADD_PER_SCAN then return end
                added = added + 1
                local icon = AddIcon(M, e.A, group)
                if not icon then return end
                c = { Icon = icon, Shown = nil, Group = group }
                Icons[n] = c
            end
            local want = M.Shown == true and S[c.Group] == true and not e.Empty
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
        ctx.Log(string.format("resources: %d things in reach, %d to show, %d new icons; search %.1f ms, the rest %.1f ms",
            queried, #list, added, (t1 - t0) * 1000, (os.clock() - t1) * 1000))
    end
end

return R
