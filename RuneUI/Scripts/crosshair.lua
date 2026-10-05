-- The setting "Crosshair in immersive mode" (1.8, F6 and Mod Menu): at Aim only ("Hide" in the 1.9 test builds), the
-- dot of the game's crosshair is unseen while the immersive mode is on (its line in F9), with or without the immersive camera. Out of the immersive mode, and
-- at Show, the game's crosshair as it always is. Ivan's pick: no rule of its own, only the player's setting. After the
-- play test (05-10-2026), the dot only: "if you target something you need a crosshair, even in immersive mode", so
-- the bow's ring and stamina arc, the staff's ring and the lock-on mark stay. After the next play test (05-10-2026), the dot
-- of an aim stays too: without the lock-on, the dot is the only aim of a cast or a bow shot, and Hide took it away.
-- So the value is "Aim only": the dot shows only while you aim a bow or cast a staff.
-- The marks are the ones aim.lua paints gold, found with its Collect (ctx.Collect), and of those the ones named in DOT
-- that are not inside an aim's reticle (Aim).
-- Each is made fully see-through, not collapsed: the game shows and hides them by their visibility, and the arrow and
-- rune count in the same widget stays. The game's own opacity is kept and put back.
-- Nothing runs while the setting is Show. main.lua loads this file with pcall, so an error here leaves the rest of the mod running.

local M = {}

-- the marks that Aim only hides, by widget name. "Crosshair" is the dot: aim.lua names it the dot of every weapon, and the
-- aim widget has one in each weapon's reticle (10 of the 14 marks in the log of 05-10-2026). The rings are SightRing
-- (bow), StaminaProgressBar (bow) and MagicIcon (staff).
local DOT = { Crosshair = true }

-- Whether a mark sits in the reticle of an aim: the bow's aim, the staff's cast or the aimed utility spell. The full
-- name of a mark holds the reticle child of the aim widget, as in
-- "...WBP_HUD_ReticleWidget_C_2147471152.WidgetTree_1.ReticleMagic.WidgetTree_2.Crosshair" (the ammo log line). The child's
-- name is checked with the camera's rule (camerarules AimReticle: "RangedADS", "Magic"), so the zoom and the dot agree.
-- A mark with no reticle child in its name is kept: an unknown reticle never loses its aim.
local function Aim(ctx, key)
    local child = string.match(key, "WBP_HUD_ReticleWidget_C[%w_]*%.WidgetTree[%w_]*%.([%w_]+)%.")
    return child == nil or ctx.Rules.AimReticle(child)
end

-- the game's opacity of each mark, by the mark's full name: plain numbers, no handles. Kept through a new world, as
-- the aim widget belongs to the game instance and outlives a world (aim.lua, probe of 29-09-2026).
local Saved = {}
M.Marks, M.Host, M.Hidden = {}, nil, false
local Logged = {}
local function Once(ctx, key, msg) if not Logged[key] then Logged[key] = true ctx.Log(msg) end end

-- the dots of the aim widget R, found again when it is another widget
local function Marks(ctx, R)
    local host = R:GetAddress()
    if host == M.Host then return end
    local all = {}
    ctx.Collect(R, all, 0)
    M.Host, M.Marks = host, {}
    local kept = 0
    for _, m in ipairs(all) do
        if DOT[m.Name] then
            if Aim(ctx, m.Key) then
                kept = kept + 1
                -- a restart of the mods after a 1.9 test build, which hid the aim dots too, left them at 0: shown again
                pcall(function() if m.W:GetRenderOpacity() == 0 then m.W:SetRenderOpacity(1) end end)
            else M.Marks[#M.Marks + 1] = m end
        end
    end
    Once(ctx, "marks" .. #M.Marks .. "/" .. kept, "crosshair: " .. #M.Marks .. " dots hidden, " .. kept .. " kept for aiming of " .. #all .. " aim marks")
end

local function Hide(m)
    if not m.W:IsValid() then return end
    local o = m.W:GetRenderOpacity()
    if o > 0 then
        if Saved[m.Key] == nil then Saved[m.Key] = o end
        m.W:SetRenderOpacity(0)
    end
end

-- the game's opacity back; false while the aim widget is not found (tried again on the next step)
local function Restore(ctx)
    local R = ctx.Reticle()
    if not (R and R:IsValid()) then return false end
    Marks(ctx, R)
    for _, m in ipairs(M.Marks) do
        pcall(function() if m.W:IsValid() then m.W:SetRenderOpacity(Saved[m.Key] or 1) end end)
    end
    Saved = {}
    return true
end

function M.Forget() M.Marks, M.Host, Logged = {}, nil, {} end

function M.Tick(ctx)
    if not ctx.Rules.HideCrosshair(ctx.Immersive()) then
        if M.Hidden then
            local ok, done = pcall(Restore, ctx)
            if ok and done then M.Hidden = false ctx.Log("crosshair: the game's crosshair back") end
            if not ok then Once(ctx, "restore", "crosshair: not put back: " .. tostring(done)) end
        end
        return
    end
    if not M.Hidden then ctx.Log("crosshair: the dot hidden in the immersive mode, kept while you aim") end
    M.Hidden = true
    local R = ctx.Reticle()
    if not (R and R:IsValid()) then return end
    Marks(ctx, R)
    -- every step: the game may show a mark again
    for _, m in ipairs(M.Marks) do pcall(Hide, m) end
end

return M
