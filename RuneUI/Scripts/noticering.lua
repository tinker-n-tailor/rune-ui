-- The ring of the hunger, thirst and rest warning: the HUD ring of the same need, drawn again inside the warning's own
-- ring (the picture, the two halves, the centre and the glyph, all from survival.lua's M.Ring), and the game's thin arc
-- and glyph hidden while it shows. noticestyle.lua holds the other writes; Install adds these two steps to it, and
-- noticelook.lua calls Install before it builds its recipes. main.lua loads this file with pcall: without it the warning
-- keeps the game's look.
-- The warning is one entry for all three needs and the game changes its glyph on each show. So the ring is built once for
-- the entry, and a check (once a second, from the watch list of noticelook.lua) picks the need from the glyph's texture
-- and copies the fill and the colours from the HUD ring of that need. A glyph that is no known need, or no HUD ring,
-- gives the game's look back.
-- A native read of a missing object is a crash that pcall cannot catch: everything that came from a property is checked
-- with IsValid first, and a widget of ours is checked by its full name before a write.

local M = {}

local Source, SrcKey, Picture   -- from noticestyle.lua, set by Install

local FILES = { { "Back", "upkeep_back.png" }, { "Half", "upkeep_half.png" }, { "Centre", "upkeep_centre.png" } }
local SIZE = 68   -- the ring's size when the game's back gives none: the same as the rings on the HUD
local COLLAPSED, HIDDEN, UNTOUCHABLE = 1, 2, 3   -- ESlateVisibility; 3: seen, and the mouse goes through it
local CENTRE = 2   -- alignment of a slot in an Overlay
local LIFT = 10   -- units the ring sits above its place in the game, so it stands clear of the band and its top line. The value to tune.

local function Ok(w) return w and w:IsValid() end

local function Fail(env, key, msg)
    env.Src[key] = { Failed = true }
    env.Once(key, msg)
end

-- Is any ring of the HUD built? Hud() lists them by index; a ring that did not build leaves a hole.
local function HudBuilt(env)
    for _, b in pairs(env.Hud and env.Hud() or {}) do
        if Ok(b.Right) then return true end
    end
    return false
end

-- The HUD ring of the need that the glyph's texture shows; nil when the texture is no known need or the ring is not
-- built or has not read its value yet
local function HudRing(env, tex)
    local need = env.Survival.KindOf(tex:GetFullName())
    if not need then return end
    for _, b in pairs(env.Hud and env.Hud() or {}) do
        if b.Name == need and Ok(b.Right) and b.Value then return b end
    end
end

local function Alive(part) return Ok(part.W) and part.W:GetFullName() == part.Key end

-- The game's parts (GameRing) take rec.On at once, so there is no moment with both rings or with none
local function Sync(rec)
    for _, game in ipairs(rec.Game) do
        if Alive(game) then game.Apply() end
    end
end

local function Seen(rec, on)
    if rec.On == on then return end
    rec.On = on
    rec.Box:SetVisibility(on and UNTOUCHABLE or HIDDEN)
    Sync(rec)
end

-- Copies the HUD ring of the glyph's need onto the ring in the warning; writes only what changed. rec.On says whether
-- ours is the ring that shows: the game's parts follow it (GameRing).
local function Follow(env, rec)
    for _, part in ipairs(rec.Parts) do
        if not Alive(part) then
            rec.On = false
            Sync(rec)
            return
        end
    end
    local glyph = Source(env, rec.GlyphKey)
    local tex = glyph and glyph.Brush.ResourceObject
    local b = Ok(tex) and HudRing(env, tex)
    if not b then Seen(rec, false) return end
    local ring, icon, p = env.Survival.Look(b)
    local name = tex:GetFullName()
    local look = string.format("%s %.3f %.3f %.3f %.3f %.3f %.3f %.3f", name, p, ring.R, ring.G, ring.B, icon.R, icon.G, icon.B)
    if look ~= rec.Look then
        rec.Look = look
        if name ~= rec.Tex then
            rec.Tex = name
            rec.Glyph:SetBrushFromTexture(tex, false)
        end
        env.Survival.Turn(rec, p)
        rec.Right:SetColorAndOpacity(ring)
        rec.Left:SetColorAndOpacity(ring)
        rec.Glyph:SetColorAndOpacity(icon)
    end
    Seen(rec, true)
end

-- Makes the ring and puts it into the Overlay of the game's ring back. Nothing is in the tree until the last call.
local function Build(env, info, parent, size, key)
    local Sv, tree = env.Survival, info.Tree
    local art = {}
    for _, f in ipairs(FILES) do
        art[f[1]] = Picture(env, tree, f[2])
        if not art[f[1]] then return end
    end
    local n = env.Uniq and env.Uniq("RU_WarnRing") or ("RU_WarnRing" .. os.time())
    local ov, right, left = Sv.Ring(tree, n, size, art, Sv.ICON_TINT)
    local glyph = Sv.Picture(tree, n .. "Glyph", art.Centre, size)   -- the glyph's texture comes with the first look
    Sv.Add(ov, glyph, CENTRE, CENTRE)
    local box = Sv.Sized(tree, n, size, size, ov)
    box:SetVisibility(HIDDEN)
    Sv.Add(parent, box, CENTRE, CENTRE)
    box:SetRenderTranslation({ X = 0, Y = -LIFT })
    local rec = { W = box, Key = box:GetFullName(), Box = box, Right = right, Left = left, Glyph = glyph, GlyphKey = SrcKey(env, "Glyph", true), Game = {} }
    rec.Parts = { rec }
    for _, w in ipairs({ right, left, glyph }) do rec.Parts[#rec.Parts + 1] = { W = w, Key = w:GetFullName() } end
    return rec
end

-- On the ring's back: the warning's ring, in the same Overlay as the game's. Waits while the HUD has no ring.
local function WarnRing(env, W, info)
    local key = SrcKey(env, "Ring", true)
    if not (env.Survival and env.Survival.Ring and env.Survival.KindOf and env.Survival.Look) then
        Fail(env, key, "noticelook: no rings from survival.lua, the warning keeps the game's ring")
        return true
    end
    if not HudBuilt(env) then return false end
    local parent = W:GetParent()
    if not Ok(parent) then return false end
    local cls = parent:GetClass():GetFName():ToString()
    if cls ~= "Overlay" then
        Fail(env, key, "noticelook: the warning keeps the game's ring, its back sits in a " .. cls .. ", not an Overlay")
        return true
    end
    local size = W.Brush.ImageSize.X
    if not (type(size) == "number" and size > 0) then size = SIZE end
    local ok, rec = pcall(Build, env, info, parent, size, key)
    if not (ok and rec) then
        Fail(env, key, "noticelook: the warning keeps the game's ring, ours was not built: " .. (ok and "a picture did not load" or tostring(rec)))
        return true
    end
    env.Src[key] = rec
    -- A fault drops the check from the watch list: the game's ring comes back first, as nothing will move ours again
    local follow = function()
        local ok, err = pcall(Follow, env, rec)
        if not ok then
            pcall(Seen, rec, false)
            error(err, 0)
        end
    end
    pcall(follow)   -- the first look is the check's too, and the next one logs a fault
    return true, follow
end

-- On each part of the game's ring (its back, its arc, its glyph): collapsed while ours shows, put back when it does not.
-- It waits until ours is made, and is done at once when ours could not be.
local function GameRing(env, W)
    local rec = env.Src[SrcKey(env, "Ring", true)]
    if not rec then return false end
    if rec.Failed then return true end
    local was, held
    local function Apply()
        if rec.On then
            local vis = W:GetVisibility()
            if vis ~= COLLAPSED then
                if not held then was, held = vis, true end
                W:SetVisibility(COLLAPSED)
            end
        elseif held then
            held = false
            W:SetVisibility(was)
        end
    end
    rec.Game[#rec.Game + 1] = { W = W, Key = W:GetFullName(), Apply = Apply }
    Apply()
    return true, Apply
end

function M.Install(S)
    Source, SrcKey, Picture = S.Source, S.SrcKey, S.Picture
    S.WarnRing, S.GameRing = WarnRing, GameRing
    S.Once[WarnRing] = true
end

return M
