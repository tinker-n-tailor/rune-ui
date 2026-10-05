-- The position math of the layout: where each element sits on this screen, and what to write into its widget.
-- No game calls here, only numbers, so tools/test-layout.js drives it without the game. main.lua gives it the
-- element list (Init) and keeps the screen fresh (Hud, from ReadHud).
--
-- All positions are in HUD units, as on a 16:9 screen: 1920x1080 units at any resolution (2560x1440 = 1.333 px per
-- unit). A wider or narrower screen, or the game's HUD scale, gives the HUD another size (see Hud).
-- Each element has: Center and Size, where its visible part sits in the game's default layout; A, the edge the game
-- ties that spot to (0 left or top, 0.5 middle, 1 right or bottom); X, Y, Scale, the player's move and size;
-- TX, TY, the edge of the screen the element follows on a screen of another shape (the third it sits in).
-- Full: the widget covers the whole screen, so its scale pivot must be moved onto its visible part.
-- Inside: the widget lives inside another element; its X,Y still mean "moved from its own default spot on screen".
-- Follows: the widget lives inside another element and moves and sizes with it; its X,Y and Scale come on top.

local M = {}

M.Elements = {}
-- The screen in units (1.2, wide screens). The viewport is its pixels over the DPI scale, which follows the short
-- side: 2560x1440 and 2560x1080 are both 1080 units high, 1920 and 2560 wide. The HUD sits in a scale box set by
-- the game's HUD scale, so the HUD is the viewport over that scale. RuneMap is on the viewport.
-- W, H: the HUD. VW, VH: the viewport. S: the HUD scale. 1920x1080 until main.lua reads the screen.
M.Hud = { W = 1920, H = 1080, S = 1, VW = 1920, VH = 1080 }
-- the ninths of the screen, for the F9 list: row by row
M.AREAS = { "Top left", "Top", "Top right", "Left", "Center", "Right", "Bottom left", "Bottom", "Bottom right" }

function M.Init(elements) M.Elements = elements end

function M.ById(id)
    for _, E in ipairs(M.Elements) do if E.Id == id then return E end end
end

-- Elements with no widget of their own: they only switch something on or off
function M.IsSwitch(E) return E.Custom == "creatures" or E.Custom == "baricons" or E.Custom == "immersive" or E.Custom == "aim" or E.Custom == "runexp" or E.Custom == "questnext" or E.Custom == "cdhoriz" or E.Custom == "slimlevel" or E.Custom == "combattext" end
-- The box of E: width and height swap while the switch named in E.Turn is on (the spell cooldowns, as a row). It
-- keeps its left edge and its middle height, see ScreenBox.
function M.Box(E)
    if E.Turn and M.ById(E.Turn).Visible then return E.Size.Y, E.Size.X end
    return E.Size.X, E.Size.Y
end
-- Elements the mod draws on the viewport, not inside the game's HUD scale box
function M.OnViewport(E) return E.Custom == "map" or E.Custom == "creatures" or E.Custom == "cooldowns" or E.Custom == "clock" or E.Custom == "questtracker" or E.Custom == "party" end

-- The edge an element follows on a screen of another shape: the third of the screen it sits in,
-- left, middle or right (and top, middle or bottom). v is where it ends up, size the screen's.
function M.Third(v, size) return v < size / 3 and 0 or v > size * 2 / 3 and 1 or 0.5 end
-- from where it sits on a 16:9 screen: for the defaults and older layout files
function M.TargetFromSpot(E)
    E.TX, E.TY = M.Third(E.Center.X + E.X, 1920), M.Third(E.Center.Y + E.Y, 1080)
end

-- how much wider and taller than 16:9 the space of E is
function M.Grow(E)
    local Hud = M.Hud
    if M.OnViewport(E) then return Hud.VW - 1920, Hud.VH - 1080 end
    return Hud.W - 1920, Hud.H - 1080
end

-- An element the player moved follows the edge of the third it now sits in. Its spot on this screen stays put.
function M.Retarget(E)
    local dW, dH = M.Grow(E)
    local fx, fy = E.Center.X + E.X + E.TX * dW, E.Center.Y + E.Y + E.TY * dH
    local tx, ty = M.Third(fx, 1920 + dW), M.Third(fy, 1080 + dH)
    E.X, E.Y = E.X + (E.TX - tx) * dW, E.Y + (E.TY - ty) * dH
    E.TX, E.TY = tx, ty
end

-- Where E's default spot is on this screen, in its own space: it moves with the edge the game ties it to (E.A)
function M.Home(E)
    local dW, dH = M.Grow(E)
    return E.Center.X + E.A[1] * dW, E.Center.Y + E.A[2] * dH
end
-- E's move from there. X,Y are its move on a 16:9 screen; on another screen it follows its own edge (E.TX,TY)
function M.Offset(E)
    local dW, dH = M.Grow(E)
    return E.X + (E.TX - E.A[1]) * dW, E.Y + (E.TY - E.A[2]) * dH
end
-- where E ends up, in viewport units: the editor's panel is on the viewport, a HUD unit is Hud.S of them
function M.FinalCenter(E)
    local hx, hy = M.Home(E)
    local ox, oy = M.Offset(E)
    local u = M.OnViewport(E) and 1 or M.Hud.S
    if E.Follows then   -- its default spot goes where the parent takes it: p to pivot + sP*(p - pivot) + tP
        local P = M.ById(E.Follows)
        local vx, vy = M.Home(P)
        local px, py = M.Offset(P)
        hx, hy = vx + P.Scale * (hx - vx) + px, vy + P.Scale * (hy - vy) + py
    end
    return (hx + ox) * u, (hy + oy) * u
end

-- Move and size in the element's own space: what goes into the widget's render transform. For an element inside
-- another one, undo the parent's move and size, so X,Y and Scale still mean "where it ends up on screen":
-- parent maps p to pivot + sP*(p - pivot) + tP.
function M.LocalTransform(E)
    local ox, oy = M.Offset(E)
    -- a Follows element is moved and sized by its parent already; its own move is drawn in the parent's size
    if E.Follows then return ox / M.ById(E.Follows).Scale, oy / M.ById(E.Follows).Scale, E.Scale end
    if not E.Inside then return ox, oy, E.Scale end
    local P = M.ById(E.Inside)
    local sP = P.Scale
    local px, py = M.Offset(P)
    local vx, vy = M.Home(P)   -- the parent's scale pivot (every parent is Full)
    local cx, cy = M.Home(E)
    local tx = (cx + ox - px - vx) / sP + vx - cx
    local ty = (cy + oy - py - vy) / sP + vy - cy
    return tx, ty, E.Scale / sP
end

-- the scale pivot of a Full element: its default spot as a share of the HUD
function M.Pivot(E)
    local hx, hy = M.Home(E)
    return hx / M.Hud.W, hy / M.Hud.H
end

-- where E sits on this screen, in viewport units: its box (x, y, width, height). A turned box (Box) keeps the left
-- edge that its unturned box has: the point it is moved and sized about is the same in both.
function M.ScreenBox(E)
    local cx, cy = M.FinalCenter(E)
    local sz = E.Scale * (M.OnViewport(E) and 1 or M.Hud.S) * (E.Follows and M.ById(E.Follows).Scale or 1)
    local bw, bh = M.Box(E)
    local w, h = bw * sz, bh * sz
    -- Below: room under the element's own box that belongs to it (the XP row under the bars). Only the frame grows;
    -- the centre, and so every saved layout, stays as it is.
    return cx - E.Size.X * sz / 2, cy - h / 2, w, h + (E.Below or 0) * sz
end

-- E's centre and size on a 1920 x 1080 screen, for the F9 readouts; a Follows element is carried by its parent
function M.Spot(E)
    if not E.Follows then return E.Center.X + E.X, E.Center.Y + E.Y, E.Scale end
    local P = M.ById(E.Follows)
    return P.Center.X + P.X + P.Scale * (E.Center.X - P.Center.X) + E.X,
        P.Center.Y + P.Y + P.Scale * (E.Center.Y - P.Center.Y) + E.Y, E.Scale * P.Scale
end

-- The F9 list by screen area: the ninth of the screen an element sits in
function M.Area(E)
    if E.Follows then return M.Area(M.ById(E.Follows)) end   -- listed with the part it follows
    local hx, hy = M.Home(E)
    local ox, oy = M.Offset(E)
    local dW, dH = M.Grow(E)
    return M.AREAS[M.Third(hy + oy, 1080 + dH) * 6 + M.Third(hx + ox, 1920 + dW) * 2 + 1]
end

return M
