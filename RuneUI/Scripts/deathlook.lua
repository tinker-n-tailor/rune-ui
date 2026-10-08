-- The death screen (WBP_HUD_Death_C) stays the game's own. Four changes, always on:
-- "You Died" is red and bigger, it sits above the banner, and the sparks on the two gold lines are off. The band, "Killed By",
-- the cause, the power level, the timer and the blur are not touched.
-- Sparks: the two Niagara widgets are collapsed, and again on a look when the game showed them. The effect has no colour
-- parameter (seen live, 08-10-2026), so the sparks cannot be red, and its component is there only during a show.
-- Red and size: the text's style is the class CUIS_Death_YouDiedTextStyle_C. The game applies it again on every show, so
-- a write to the class defaults (the way combattext.lua writes its styles) is read at the next death. A bigger font grows
-- the layout, so the flourishes make room by themselves. The game's own size is read once and kept (Own), and the
-- wanted size is always that times BIG, so a second run or a second world does not grow it. A style that is red already
-- while its own size is not known (an earlier run of the mod) is left alone.
-- Above the band: MainTextBox (the text and its two flourishes) gets a render translation. The game does not put it back
-- (seen live, 07-10-2026); the look at every EVERY seconds writes it again if it did. The lift is tuned for the big text, so
-- it follows the style: a show lifts only when the class defaults were already ours when the show began (the game styles the
-- text at the show, before a look can write them). The first death of a game run is the game's own screen, untouched; the
-- next death is red, big and lifted. A show is a change of the screen's visibility to shown, read on the look.
-- The parts are found by name in the widget's tree. A widget that was freed is not called: the full name is compared first.
-- combattext.lua gives Find, PathOf and Rgba (ctx.Combat).

local M = {}

local CLASS = "WBP_HUD_Death_C"
local STYLE = "CUIS_Death_YouDiedTextStyle_C"
local BOX, TEXT = "MainTextBox", "DeathText"
local SPARKS = { Niagara_TopLine = true, Niagara_BottomLine = true }
local COLLAPSED = 1    -- ESlateVisibility
local RED = { R = 0.64, G = 0.13, B = 0.10, A = 1 }
local BIG = 1.6        -- "You Died" is this much bigger (seen live as a render scale and accepted)
local LIFT = -100      -- units the text box moves up: the letters clear the top gold line (to tune by eye)
local EVERY = 0.5      -- seconds between two looks
local NODES, DEPTH = 80, 8   -- the most widgets the search by name visits, and its depth

local Own = {}   -- style path -> the game's own size; it outlives a world, as the class defaults may too
local S

local function Fresh(logged) return { Parts = {}, Logged = logged or {}, Step = {}, Next = 0 } end
S = Fresh()

local function Ok(w) return w and w:IsValid() end

local function Once(ctx, key, msg)
    if not S.Logged[key] then S.Logged[key] = true ctx.Log("death look: " .. msg) end
end

local function Near(a, b, eps) return math.abs(a - b) < eps end
local function IsRed(c) return Near(c.R, RED.R, 0.001) and Near(c.G, RED.G, 0.001) and Near(c.B, RED.B, 0.001) end

-- The text box, the text and the spark widgets, by name; a user widget inside (the power level display) is not entered.
local function Named(root)
    local found, sparks, seen = {}, {}, 0
    local function Visit(W, depth)
        if seen >= NODES or depth > DEPTH or not Ok(W) then return end
        seen = seen + 1
        local name = W:GetFName():ToString()
        if name == BOX or name == TEXT then found[name] = found[name] or W end
        if SPARKS[name] then sparks[#sparks + 1] = { W = W, Key = W:GetFullName() } return end
        if name == TEXT or string.find(W:GetClass():GetFName():ToString(), "^WBP_") then return end
        local ok, count = pcall(function() return W:GetChildrenCount() end)
        if ok and count then
            for i = 0, count - 1 do Visit(W:GetChildAt(i), depth + 1) end
        else
            pcall(function() Visit(W:GetContent(), depth + 1) end)
        end
    end
    Visit(root, 1)
    return found[BOX], found[TEXT], sparks
end

-- The parts of one death screen, found once and checked on every look (a freed slot can hold a new object).
-- Nothing when the tree is not built yet; an error when it is built and the names are not in it.
local function Parts(W, key)
    local p = S.Parts[key]
    if p and Ok(p.Box) and Ok(p.Text) and p.Box:GetFullName() == p.BoxKey and p.Text:GetFullName() == p.TextKey then return p end
    S.Parts[key] = nil
    local tree = W.WidgetTree
    if not (Ok(tree) and Ok(tree.RootWidget)) then return end
    local box, text, sparks = Named(tree.RootWidget)
    if not (box and text) then error("no " .. BOX .. " or no " .. TEXT .. " in the death screen") end
    p = { Box = box, BoxKey = box:GetFullName(), Text = text, TextKey = text:GetFullName(), Sparks = sparks }
    S.Parts[key] = p
    return p
end

-- The sparks on the two gold lines are off: a Niagara widget hides only by its own visibility.
local function Quiet(ctx, p)
    if #p.Sparks == 0 then Once(ctx, "sparks", "no spark widgets in the death screen, left alone") return end
    for _, s in ipairs(p.Sparks) do
        if Ok(s.W) and s.W:GetFullName() == s.Key and s.W:GetVisibility() ~= COLLAPSED then s.W:SetVisibility(COLLAPSED) end
    end
    Once(ctx, "quiet", "the sparks on the two gold lines are off")
end

-- The style class defaults of the text: red, and BIG times the game's own size.
-- Returns whether the defaults are ours now, and whether they were ours before this look (red).
local function Dress(ctx, p)
    local Combat = ctx.Combat
    local cdo = p.Cdo
    if not (Ok(cdo) and cdo:GetFullName() == p.CdoKey) then
        local class = p.Text.Style
        if not Ok(class) then Once(ctx, "style", "the text holds no style class, left alone") return false, false end
        local path = Combat.PathOf(class)
        local pkg, name = string.match(path or "", "^(.*)%.([^.]+)$")
        if name ~= STYLE then Once(ctx, "style", "the text holds the style " .. tostring(name) .. ", not " .. STYLE .. ", left alone") return false, false end
        cdo = Combat.Find(pkg .. ".Default__" .. name)
        if not cdo then Once(ctx, "defaults", "no class defaults of " .. STYLE .. ", left alone") return false, false end
        p.Cdo, p.CdoKey, p.Path = cdo, cdo:GetFullName(), path
    end
    local fi = cdo.Font
    local size = fi.Size
    if type(size) ~= "number" or size <= 0 then Once(ctx, "size", "the size of the style is not a number, left alone") return false, false end
    local red = IsRed(cdo.Color)
    local own = Own[p.Path]
    -- not red and not our size: these are the game's values (again), as a class that loaded again holds them
    if not red and not (own and Near(size, own * BIG, 0.01)) then own = size Own[p.Path] = size end
    if not own then Once(ctx, "own", "the style is red and its own size is not known, left alone") return false, red end
    local want = own * BIG
    if not red then cdo.Color = Combat.Rgba(RED) end   -- first: a failed size write is made good at the next look, from Own
    if not Near(size, want, 0.01) then fi.Size = want end
    return true, red
end

-- Is the screen on show: visible, or seen with the mouse going through (ESlateVisibility 0, 3, 4)? nil when it cannot be read.
local function IsShown(W)
    local ok, vis = pcall(function() return W:GetVisibility() end)
    if ok and type(vis) == "number" then return vis == 0 or vis >= 3 end
end

local function Lift(ctx, p)
    local t = p.Box.RenderTransform.Translation
    if type(t.X) ~= "number" or type(t.Y) ~= "number" then Once(ctx, "lift", "the place of " .. BOX .. " is not a number, left alone") return end
    if not Near(t.Y, LIFT, 0.01) then p.Box:SetRenderTranslation({ X = t.X, Y = LIFT }) end
end

local function Look(ctx, W, key)
    local p = Parts(W, key)
    if not p then return end
    Quiet(ctx, p)
    local dressed, ours = Dress(ctx, p)
    local shown = IsShown(W)
    if shown == nil then p.Lift = ours or dressed   -- a visibility that cannot be read: lift as soon as the style is ours
    elseif p.Shown == nil or (shown and not p.Shown) then p.Lift = ours end   -- the first look, or a new show
    p.Shown = shown
    if p.Lift then Lift(ctx, p) end
    if dressed then Once(ctx, "set", "'You Died' is red and " .. BIG .. " times its size, the text box is " .. -LIFT .. " units up on a show that starts with it") end
end

function M.Tick(ctx)
    local now = os.clock()
    if now < S.Next then return end
    S.Next = now + EVERY
    if not ctx.Combat then Once(ctx, "share", "combattext.lua did not load, the death screen keeps the game's look") return end
    local list, keys = ctx.Find(CLASS)
    for i, W in ipairs(list) do
        if Ok(W) and ctx.MayTry(S.Step) then
            local ok, err = pcall(Look, ctx, W, keys[i])
            if not ok then ctx.Failed(S.Step) ctx.Log("death look: failed: " .. tostring(err)) end
        end
    end
end

-- A new world: the handles are dropped. The game's own sizes stay (Own); the class defaults may hold ours still.
function M.Forget(sameWorld) S = Fresh(sameWorld and S.Logged) end

-- for the F9 panel's warning line: the look gave up (see MayTry)
function M.Problem() return (S.Step.Fails or 0) >= 3 end

return M
