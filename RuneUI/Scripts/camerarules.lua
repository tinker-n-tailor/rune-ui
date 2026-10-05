-- The immersive camera (1.8): its settings, its rules and its panel (F6). Pure Lua, no game calls, so
-- tools/test-camera.js runs it without the game. camera.lua reads the game and writes what Step gives back;
-- crosshair.lua asks HideCrosshair; main.lua draws the panel from View and saves through Attach.
-- The camera works only while the immersive mode is on: its line in F9, the switch, not the moment the HUD is faded
-- (the fade comes and goes with every hit, and the camera would jump with it). Out of it, the game's camera.
-- Ivan's picks from the live preview (04-10-2026 and 05-10-2026): walking close with the character on the left, a
-- sprint far (the game moves the camera in and out of a sprint itself), and a fight's distance held a while after it ends
-- (the game's combat switch drops the moment the enemy dies). His rule after the play test (05-10-2026): the walk distance with any weapon, tool or
-- empty hands; only a fight changes it, closer with a melee weapon, farther while a staff, a wand or a bow aims or casts.
-- Every distance is set at once: the game blends the camera to a new distance of the walking profile by itself, in
-- about 0.5 to 0.7 s (Ivan's play test, 05-10-2026). The mod's own glide looked choppy beside it and is gone.
local M = {}

-- the rows of the panel, of Mod Menu (camera_<Key>) and of the [camera] section of runeui.txt, in this order.
-- Distances in the game's units, which are cm.
M.ROWS = {
    { Key = "on", Label = "Immersive camera", Kind = "switch", Default = false },
    { Key = "walk", Label = "Walk distance", Kind = "number", Min = 100, Max = 1500, Step = 25, Unit = "cm", Default = 300 },
    { Key = "side", Label = "Side offset", Kind = "number", Min = 0, Max = 200, Step = 10, Unit = "cm", Default = 90 },
    { Key = "sprint", Label = "Sprint distance", Kind = "number", Min = 100, Max = 1500, Step = 25, Unit = "cm", Default = 900 },
    { Key = "melee", Label = "Melee zoom", Kind = "number", Min = 100, Max = 1500, Step = 25, Unit = "cm", Default = 200 },
    { Key = "ranged", Label = "Ranged zoom", Kind = "number", Min = 100, Max = 1500, Step = 25, Unit = "cm", Default = 500 },
    { Key = "hold", Label = "Hold after a fight", Kind = "number", Min = 0, Max = 30, Step = 1, Unit = "s", Default = 8 },
    -- "Aim only" was "Hide" in the 1.9 test builds: an old file or Mod Menu value reads as "Aim only" (Old)
    { Key = "crosshair", Label = "Crosshair in immersive mode", Kind = "choice", Options = { "Show", "Aim only" }, Default = "Show",
        Old = { hide = "Aim only" } },
}
local BY_KEY = {}
for i, r in ipairs(M.ROWS) do BY_KEY[r.Key] = r r.Index = i end

-- The panel's state and the key flags. Key handlers run on UE4SS's own thread: they only change these and the
-- numbers in Set, never add a key (false, never nil), and the step saves (Commit).
M.Open, M.Sel, M.Dirty, M.ResetWanted = false, 1, false, false
M.Set = {}
for _, r in ipairs(M.ROWS) do M.Set[r.Key] = r.Default end
M.Store, M.Save = {}, function() end

local function Snap(r, v)
    v = tonumber(v)
    if not v or v ~= v then return r.Default end
    v = math.max(r.Min, math.min(r.Max, v))
    return math.floor((v - r.Min) / r.Step + 0.5) * r.Step + r.Min
end

local function Choice(r, v)
    local low = string.lower(tostring(v))
    for _, o in ipairs(r.Options) do if low == string.lower(o) then return o end end
    if r.Old and r.Old[low] then return r.Old[low] end
    return r.Default
end

-- one value from the file or from Mod Menu, made right; a value that is missing or bad gives the default
local function Clean(r, v)
    if v == nil then return r.Default end
    if r.Kind == "switch" then return v == true or tonumber(v) == 1 end
    if r.Kind == "number" then return Snap(r, v) end
    return Choice(r, v)
end

-- store: the [camera] section of runeui.txt; save writes the file. Called once at start.
function M.Attach(store, save)
    M.Store, M.Save = store, save
    for _, r in ipairs(M.ROWS) do M.Set[r.Key] = Clean(r, store[r.Key]) end
end

-- the settings into the section, as the file writes them: a switch as 1 and 0, a choice as its word. A line of a row
-- that is gone (zoomease and returnease of the 1.9 test builds) leaves the file at the next save.
function M.Write(store)
    for k in pairs(store) do if not BY_KEY[k] then store[k] = nil end end
    for _, r in ipairs(M.ROWS) do
        local v = M.Set[r.Key]
        if r.Kind == "switch" then v = v and 1 or 0 end
        store[r.Key] = v
    end
end

-- on the game thread, once a step: the reset and the save asked for by the keys or by Mod Menu
function M.Commit()
    if M.ResetWanted then
        M.ResetWanted = false
        for _, r in ipairs(M.ROWS) do M.Set[r.Key] = r.Default end
        M.Dirty = true
    end
    if M.Dirty then
        M.Dirty = false
        M.Write(M.Store)
        M.Save()
    end
end

-- Mod Menu: a switch is true or false, a number a number, a choice its word
function M.MenuGet(key) return M.Set[key] end
function M.MenuSet(key, v)
    local r = BY_KEY[key]
    if not r then return end
    M.Set[key] = Clean(r, v)
    M.Dirty = true
end

---------------------------------------------------------------- the rules

-- What the player holds (class names of the actors in the hands, nil for an empty hand). A staff or a wand in the
-- right hand, a bow or a crossbow in the left: ranged. A tool in the right hand is not a weapon. Anything else in the
-- right hand is a melee weapon. A shield or a torch in the left hand changes nothing. Names from the game's files.
local RANGED_RIGHT = { "BP_Staff_", "BP_Wand_" }
local RANGED_LEFT = { "BP_Longbow_", "BP_Shortbow_", "BP_Crossbow_" }
local TOOLS = { "BP_Pickaxe_", "BP_Logging_Axe_", "BP_FishingRodV2_" }
local function Starts(name, list)
    for _, p in ipairs(list) do if string.sub(name, 1, #p) == p then return true end end
    return false
end
function M.Classify(right, left)
    right, left = right or "", left or ""
    if Starts(right, RANGED_RIGHT) or Starts(left, RANGED_LEFT) then return "ranged" end
    if Starts(right, TOOLS) then return "tool" end
    if right ~= "" then return "melee" end
    return "none"
end

-- The HUD reticle that shows while the player aims a bow or casts a staff: class names of the children of the reticle
-- switcher (WBP_HUD_ReticleWidget_C, probe of 29-09-2026). "RangedADS" is the bow's aim (WBP_ReticleRangedADS_C); "Magic" is the
-- staff's cast (WBP_ReticleMagic_C, seen active while casting, probe of 30-09-2026) and the aimed utility spell
-- (WBP_ReticleAimingUtilityMagic_C). The default, stealth, repair, fishing, container and turret reticles are not an aim.
local AIM_RETICLES = { "RangedADS", "Magic" }
function M.AimReticle(className)
    if type(className) ~= "string" then return false end
    for _, p in ipairs(AIM_RETICLES) do if string.find(className, p, 1, true) then return true end end
    return false
end

-- Whether a fight is on, for the kind of weapon in the hands. A tool or empty hands never fight. A melee weapon fights
-- while the combat switch (s.Combat) is on. A ranged weapon fights while it aims or casts (s.Aiming, the reticle) or
-- while the combat switch is on: the switch never went on with a staff or a bow in the play tests of 05-10-2026.
local function Fighting(kind, s)
    if kind == "melee" then return s.Combat == true end
    if kind == "ranged" then return s.Aiming == true or s.Combat == true end
    return false
end

-- A camera's memory: FightUntil the end of a fight's hold and FightView that fight's view. Out is reused every step.
function M.NewMemory() return { FightUntil = -1, FightView = nil, Out = {} } end

local MIN_DISTANCE, MAX_DISTANCE = BY_KEY.walk.Min, BY_KEY.walk.Max

-- s: Immersive (the switch), Combat (the combat switch), Aiming (an aim reticle shows), Right, Left (class names).
-- now: seconds. Gives back Active false (the game's camera: every value goes back), or Active with Walk (the walking
-- profile's distance, set at once: the game blends the camera there), Sprint (the sprinting profile's), Side (both
-- profiles' side offset), Lock (the lock-on camera's distance: the view the player is in, so the lock-on does not
-- jump), View ("walk", "melee", "ranged") and Kind (what is in the hands, as Classify).
function M.Step(mem, s, now)
    local set, out = M.Set, mem.Out
    if not (set.on and s.Immersive) then
        mem.FightUntil, mem.FightView = -1, nil
        out.Active = false
        return out
    end
    local kind = M.Classify(s.Right, s.Left)
    local fight = Fighting(kind, s)
    if fight then mem.FightUntil, mem.FightView = now + set.hold, kind end
    -- a fight's view holds after it ends, also when the weapon goes away or changes in that time
    local view = "walk"
    if fight then view = kind
    elseif now < mem.FightUntil then view = mem.FightView end
    local target = math.max(MIN_DISTANCE, math.min(MAX_DISTANCE, set[view]))
    out.Active, out.Walk, out.Sprint, out.Side, out.Lock, out.View, out.Kind = true, target, set.sprint, set.side, target, view, kind
    return out
end

-- the crosshair setting: Aim only hides the dot of the game's crosshair while the immersive mode is on, with or without
-- this camera, but not the dot of an aim (crosshair.lua names the marks, and keeps those of AimReticle)
function M.HideCrosshair(immersive) return M.Set.crosshair == "Aim only" and immersive == true end

---------------------------------------------------------------- the panel (F6)

local function Text(r, v)
    if r.Kind == "switch" then return v and "On" or "Off" end
    if r.Kind == "number" then return string.format("%d", v) .. (r.Unit and " " .. r.Unit or "") end
    return v
end
function M.Value(i) local r = M.ROWS[i] return Text(r, M.Set[r.Key]) end

local HINTS = {
    walk = "How far the camera is when you walk. The game's own camera is at 700 cm.",
    side = "How far right the camera sits, so you stand on the left. 0 is the middle.",
    sprint = "How far the camera goes out in a sprint. The game brings it back after you stop.",
    melee = "The distance in a fight with a melee weapon.",
    ranged = "The distance while you aim a bow or cast a staff. It holds for a few seconds.",
    hold = "How long the zoom stays after a fight or an aim. Then the camera goes back.",
}
-- keys: main.lua's key names (editor, camera); immersive: the immersive mode's switch
function M.Hint(i, keys, immersive)
    local r = M.ROWS[i]
    if r.Key == "on" then
        if not M.Set.on then return "The game's own camera. On: closer, your character on the left, in immersive mode." end
        if not immersive then return "On, but the immersive mode is off. Turn it on in " .. keys.editor .. "." end
        return "On while the immersive mode is on. Out of it, the game's camera is back."
    end
    if r.Key == "crosshair" then
        if M.Set.crosshair == "Aim only" then return "No crosshair dot, except while you aim a bow or cast a staff." end
        return "The game's crosshair, as always."
    end
    return HINTS[r.Key]
end

-- what the panel shows now, as one string: a new view only when it changed
function M.State(immersive)
    local parts = { "camera", M.Sel, tostring(immersive) }
    for i = 1, #M.ROWS do parts[#parts + 1] = M.Value(i) end
    return table.concat(parts, "|")
end

-- the view for editor.lua (see main.lua MapView): every row fits the panel's lines, so the list does not scroll
function M.View(keys, immersive, warn)
    local v = { Mode = "camera", Title = "RUNE CAMERA", SubA = "Layout on", SubB = keys.editor, Warn = warn,
        Keys = { { { "↑", "↓" }, "Select" }, { { "←", "→" }, "Change" }, { { "Backspace" }, "Reset" },
            { { keys.editor }, "Layout" }, { { keys.camera }, "Save, close" } },
        Name = M.ROWS[M.Sel].Label .. ":  " .. M.Value(M.Sel), Hint = M.Hint(M.Sel, keys, immersive), Rows = {} }
    for i, r in ipairs(M.ROWS) do
        local val = M.Value(i)
        -- a number has many values: "< 300 cm >", as the map settings show a row with more than two
        v.Rows[i] = { Text = r.Label, Note = r.Kind == "number" and ("< " .. val .. " >") or val, Sel = i == M.Sel }
    end
    return v
end

-- the keys (UE4SS's thread): up and down pick a row, left and right change it
function M.Pick(d) M.Sel = (M.Sel - 1 + d) % #M.ROWS + 1 end
function M.Change(d)
    local r = M.ROWS[M.Sel]
    local v = M.Set[r.Key]
    if r.Kind == "switch" then M.Set[r.Key] = not v
    elseif r.Kind == "number" then M.Set[r.Key] = Snap(r, v + (d > 0 and r.Step or -r.Step))
    else
        local at = 1
        for i, o in ipairs(r.Options) do if o == v then at = i end end
        M.Set[r.Key] = r.Options[(at - 1 + (d > 0 and 1 or -1)) % #r.Options + 1]
    end
    M.Dirty = true
end

return M
