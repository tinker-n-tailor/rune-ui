-- Combat text: the damage numbers over enemies in the look of the HUD, and a critical hit that pops.
-- The switch "Combat text" (main.lua's "combattext") turns it off and the game's look is back.
-- main.lua loads this file with pcall and runs its Tick (about 16 times a second).
-- The look is in style classes, /Game/UI/Styles/Texts/CUIS_DamageFloatie_*. A number reads its style again on every hit,
-- so a write to the class defaults (cdo) is enough.
-- Numbers are white, bigger, with a black edge and a shadow, in Poppins Medium. The critical number is gold.
-- The game's gradient on the number's font stays.
-- The word "Critical" reads its style once, so each pooled widget gets SetStyle once after the defaults changed.
-- Its gradient goes (FontMaterial nil) and it is gold, in the same font.
-- The game keeps a pool of 16 WBP_FloatingDamage_C, made once and used for every hit. The pool may grow.
-- In each, the type icon and the glow behind the word are unseen (render opacity 0).
-- The pop: while a critical number's animation FlyUpCritical plays, the widget's render scale starts at 1 + BIG
-- and settles to 1 in POP seconds, one pop for each play. The game's animation does not fight the scale.
-- A chain of 16 ms calls (chain.lua) paints it. The chain starts only when a number plays an animation
-- and ends 5 s after the last one played, so it costs nothing in a calm world (0.09 ms a step for 16 numbers).
-- A calm world costs only the poll: one IsAnyAnimationPlaying for each number on every step of the main loop, 16 calls.
-- The step that starts the chain paints the first size itself.
-- A hit in a calm world is seen only by that poll, so its pop can start up to one step of the main loop (50 ms) late.
-- A critical hit with a staff (fire, 05-10-2026) showed a white number beside the gold word, in two fights.
-- With a sword the number is gold. The white number has our edge, so it holds one of our three white styles.
-- The game seems to choose the number's style by the kind of damage, not by the critical flag (not proven).
-- So the step that starts a pop also looks at the style the number holds, and gives it the critical style (Gild).
-- The game gives a number its style again on the next hit, so nothing stays.
-- A failure in Gild is not logged: it must not stop the pop.
-- The status words (Poison, Burn, Bleed, Slowed, Immune) are WBP_FloatingText_C, a second pool of 16 (probe of 05-10-2026).
-- They get the look of the numbers, each in its own colour: the same style changes at size 18.
-- In each pooled word the soft band behind it (TextBackground) and its faint bigger copy (FloatieShadowText) are unseen.
-- The game shows and hides the band by its visibility, so that is left alone.
-- It is not proven that a word reads its style again on every show, so each pooled word also gets SetStyle once.
-- The resource numbers this widget shows use the number styles.
-- No pop and no poll for the words. One list of styles (LIST), one record of the opacities (Record) and one Undo serve both pools (KINDS).
-- The values before the first write are kept (Orig, by style, as paths for the game's own objects) so the switch can put them back.
-- A style class can load again at a new address in a new world, and then it holds the game's values again.
-- One that still holds ours (Ours) keeps the originals read the first time.
-- The switch puts back from what the game holds now (Undo), so it works after a new world or a player restart too.

local M = {}

local STYLES = "/Game/UI/Styles/Texts/CUIS_DamageFloatie_"
local FONT = "/Game/UI/Fonts/Poppins-Medium_Font.Poppins-Medium_Font"
local WHITE = { R = 1, G = 1, B = 1, A = 1 }
local GOLD = { R = 1.0, G = 0.638, B = 0.168, A = 1.0 }   -- the pick-up count's gold
local EDGE = { R = 0, G = 0, B = 0, A = 0.9 }
local SHADE, SHADE_OFFSET = { R = 0, G = 0, B = 0, A = 0.6 }, { X = 1, Y = 1 }
local EDGE_SIZE = 2
-- Word: the font material goes (no gradient). Shadow: the drop shadow is switched on; the word "Critical" has no drop
-- shadow switch of its own to set. Status: one of the five status words; their colours are linear values.
local LIST = {
    { Name = "NumberSmallTextStyle", Size = 18, Color = WHITE, Shadow = true },
    { Name = "NumberNormalTextStyle", Size = 22, Color = WHITE, Shadow = true },
    { Name = "NumberLargeTextStyle", Size = 26, Color = WHITE, Shadow = true },
    { Name = "NumberCriticalTextStyle", Size = 30, Color = GOLD, Shadow = true },
    { Name = "CriticalTextStyle", Size = 16, Color = GOLD, Word = true },
    { Name = "PoisonTextStyle", Size = 18, Color = { R = 0.30, G = 0.85, B = 0.15, A = 1 }, Word = true, Shadow = true, Status = true },
    { Name = "BurnTextStyle", Size = 18, Color = { R = 1.00, G = 0.35, B = 0.05, A = 1 }, Word = true, Shadow = true, Status = true },
    { Name = "BleedTextStyle", Size = 18, Color = { R = 0.90, G = 0.05, B = 0.05, A = 1 }, Word = true, Shadow = true, Status = true },
    { Name = "SlowedTextStyle", Size = 18, Color = { R = 0.30, G = 0.70, B = 1.00, A = 1 }, Word = true, Shadow = true, Status = true },
    { Name = "ImmuneTextStyle", Size = 18, Color = { R = 0.75, G = 0.75, B = 0.75, A = 1 }, Word = true, Shadow = true, Status = true },
}
local CRIT, WORD = LIST[4], LIST[5]
local POP, BIG = 0.35, 1.5     -- seconds, and how much bigger than 1 a pop starts
local STOP_AFTER = 5           -- seconds after the last number played that the chain goes on
local EVERY = 1                -- seconds between two looks at the styles and the pool

local function Alive(o) return o and o:IsValid() end   -- a property or a call can give a wrapper of null: pcall does not catch it

local S
local Lib   -- chain.lua, given by main.lua

-- Orig and Seen are kept over a world change (see Forget and Record); the rest starts again
local function Fresh(keep)
    return { Orig = keep and keep.Orig or {}, Seen = keep and keep.Seen or {}, Done = {}, List = {}, Chain = {},
        Defaults = {}, Widgets = {}, Pool = {}, Next = 0, Played = -STOP_AFTER }
end
S = Fresh()

local function Find(path) local o = StaticFindObject(path) if o and o:IsValid() then return o end end
local function CdoPath(name) return STYLES .. name .. ".Default__CUIS_DamageFloatie_" .. name .. "_C" end
local function ClassPath(name) return STYLES .. name .. ".CUIS_DamageFloatie_" .. name .. "_C" end

-- an object as the path StaticFindObject takes ("Class /Path.Name" is what GetFullName gives), nil for none
local function PathOf(o)
    if o and o:IsValid() then return string.match(o:GetFullName(), "^%S+%s+(.*)$") end
end
local function Rgba(c) return { R = c.R, G = c.G, B = c.B, A = c.A } end
local function Xy(v) return { X = v.X, Y = v.Y } end
M.Find, M.PathOf, M.Rgba = Find, PathOf, Rgba   -- deathlook.lua writes a style the same way

-- the pop's size after elapsed seconds: 1 + BIG at the start, exactly 1 from POP on, an ease-out in between
function M.Scale(elapsed)
    local k = elapsed / POP
    if k >= 1 then return 1 end
    return 1 + BIG * (1 - k) * (1 - k)
end

---------------------------------------------------------------- the style classes

-- Still our values: the sizes of the game's styles are others, and so is their edge
local function Ours(cdo, style)
    local fi = cdo.Font
    return fi.Size == style.Size and fi.OutlineSettings.OutlineSize == EDGE_SIZE
end

local function Read(cdo)
    local fi = cdo.Font
    return { Size = fi.Size, Font = PathOf(fi.FontObject), Material = PathOf(fi.FontMaterial), Edge = fi.OutlineSettings.OutlineSize,
        EdgeColor = Rgba(fi.OutlineSettings.OutlineColor), Color = Rgba(cdo.Color), Drop = cdo.bUsesDropShadow,
        Offset = Xy(cdo.ShadowOffset), Shade = Rgba(cdo.ShadowColor) }
end

local function WriteStyle(cdo, style, font)
    local fi = cdo.Font
    fi.Size = style.Size
    fi.FontObject = font
    fi.OutlineSettings.OutlineSize = EDGE_SIZE
    fi.OutlineSettings.OutlineColor = EDGE
    if style.Word then fi.FontMaterial = nil end   -- no gradient (proven)
    cdo.Color = style.Color
    if style.Shadow then cdo.bUsesDropShadow = true end
    cdo.ShadowOffset = SHADE_OFFSET
    cdo.ShadowColor = SHADE
end

-- an object the game had that cannot be found any more stays as it is: nil would break the font
local function Restore(cdo, o, style)
    local fi = cdo.Font
    fi.Size = o.Size
    local font = o.Font and Find(o.Font)
    if font then fi.FontObject = font end
    fi.OutlineSettings.OutlineSize = o.Edge
    fi.OutlineSettings.OutlineColor = o.EdgeColor
    if style.Word then
        local material = o.Material and Find(o.Material)
        if material or not o.Material then fi.FontMaterial = material or nil end
    end
    cdo.Color = o.Color
    if style.Shadow then cdo.bUsesDropShadow = o.Drop end
    cdo.ShadowOffset = o.Offset
    cdo.ShadowColor = o.Shade
end

-- each style on its own: one that is not loaded yet (false) is asked for again on the next look and costs no try
local function Defaults(ctx)
    local step = S.Defaults
    if not ctx.MayTry(step) then return end
    for _, style in ipairs(LIST) do
        if not S.Done[style.Name] then
            local ok, result = pcall(function()
                local cdo, font = Find(CdoPath(style.Name)), Find(FONT)
                local class = not style.Word or Find(ClassPath(style.Name))
                if not (cdo and font and class) then return false end
                if not Ours(cdo, style) then S.Orig[style.Name] = Read(cdo) end
                WriteStyle(cdo, style, font)
                if style == WORD then S.WordClass = class end
            end)
            if ok and result ~= false then
                S.Done[style.Name] = true
            elseif not ok then
                ctx.Failed(step)
                ctx.Log("combat text: " .. style.Name .. " failed: " .. tostring(result))
            end
        end
    end
    S.Statuses = true
    for _, style in ipairs(LIST) do if style.Status and not S.Done[style.Name] then S.Statuses = false end end
    local written = 0
    for _ in pairs(S.Done) do written = written + 1 end
    if not step.Logged and written == #LIST then
        step.Logged = true
        ctx.Log("combat text: the " .. written .. " styles written")
    end
end

---------------------------------------------------------------- the numbers

local function Child(overlay, name)
    if not (overlay and overlay:IsValid()) then return end
    for i = 0, overlay:GetChildrenCount() - 1 do
        local t = overlay:GetChildAt(i)
        if t and t:IsValid() and t:GetFName():ToString() == name then return t end
    end
end
local function WordOf(W) return Child(W.CriticalTextOverlay, "CriticalText") end   -- not a property of the widget

-- The opacities a number had before we wrote, by its name and the address of the widget. The pooled numbers belong to the
-- game instance and can outlive a world change, so a record is kept over one; one for another object under the same
-- name is dropped.
local function Record(key, W)
    local seen = S.Seen[key]
    if seen and seen.Addr ~= W:GetAddress() then seen = nil S.Seen[key] = nil end
    return seen
end

-- A number that reads 0 holds what we wrote, whose record was lost: the game's own opacity is 1, so it is not taken as one.
local function Original(part) local o = part:GetRenderOpacity() return o > 0 and o or 1 end

local function Restyle(W)
    local text = W.FloatieText
    local class = Alive(text) and text.Style
    if Alive(class) then text:SetStyle(class) end
end

-- The two pools of the game. Parts: the two widgets of each that go unseen (render opacity 0).
-- Style(e) gives the pooled widget its word style once, when the defaults are written: true when done, nothing when it must wait.
-- Reread(W) makes a word read its style class again, after the switch put the game's values back.
-- Pop: the numbers' pop and poll.
local KINDS = {
    { Class = "WBP_FloatingDamage_C", Parts = { "FloatiesIcon", "BackgroundGlow" }, Pop = true,
      Style = function(e)
          if not (S.Done[WORD.Name] and Alive(S.WordClass)) then return end
          local word = e.Word
          if not Alive(word) then word = WordOf(e.W) e.Word = word end
          if not word then error("no CriticalText in " .. e.Key) end
          word:SetStyle(S.WordClass)
          return true
      end,
      Reread = function(W)
          local class = Find(ClassPath(WORD.Name))
          local word = class and WordOf(W)
          if word then word:SetStyle(class) end
      end },
    { Class = "WBP_FloatingText_C", Parts = { "TextBackground", "FloatieShadowText" },
      Style = function(e)
          if not S.Statuses then return end
          Restyle(e.W)
          return true
      end,
      Reread = Restyle },
}

-- Once for each pooled widget: its two opacities, and its word's style when the defaults are written.
local function Dress(e)
    local kind = e.Kind
    if not e.Faded then
        local first, second = e.W[kind.Parts[1]], e.W[kind.Parts[2]]
        if not (Alive(first) and Alive(second)) then error("no " .. kind.Parts[1] .. " or " .. kind.Parts[2] .. " in " .. e.Key) end
        if not Record(e.Key, e.W) then S.Seen[e.Key] = { Addr = e.W:GetAddress(), Original(first), Original(second) } end
        first:SetRenderOpacity(0)
        second:SetRenderOpacity(0)
        local rt = kind.Pop and e.W.RenderTransform   -- a pop cut short by a new world left the number big
        if rt and rt.Scale.X ~= 1 then e.W:SetRenderScale({ X = 1, Y = 1 }) end
        e.Faded = true
    end
    if not e.Styled and kind.Style(e) then e.Styled = true end
end

local function Pool(ctx)
    local step = S.Widgets
    local kept, numbers, count = {}, {}, 0
    for _, kind in ipairs(KINDS) do
        local list, keys = ctx.Find(kind.Class)
        for i, W in ipairs(list) do
            local key = keys[i]
            local e = S.Pool[key]
            -- the same name can come back on another widget (a freed slot): it is the same widget only at the same address
            if e and not (e.W:IsValid() and e.W:GetAddress() == W:GetAddress()) then e = nil end
            if not e then
                local crit = kind.Pop and W.FlyUpCritical
                e = { W = W, Key = key, Kind = kind, Crit = Alive(crit) and crit or nil }
            end
            kept[key] = e
            count = count + 1
            if kind.Pop then numbers[#numbers + 1] = e end
            if ctx.MayTry(step) and not (e.Faded and e.Styled) then
                local ok, err = pcall(Dress, e)
                if not ok then ctx.Failed(step) ctx.Log("combat text: a " .. kind.Class .. " not dressed: " .. tostring(err)) end
            end
        end
    end
    S.Pool, S.List = kept, numbers
    if count > 0 then for key in pairs(S.Seen) do if not kept[key] then S.Seen[key] = nil end end end
    if not step.Logged and count > 0 then step.Logged = true ctx.Log("combat text: " .. #numbers .. " numbers and " .. (count - #numbers) .. " words watched") end
end

---------------------------------------------------------------- the pop

-- every number back at scale 1
local function Rest()
    for _, e in ipairs(S.List) do
        e.At, e.Done = nil, nil
        if e.Scaled then
            e.Scaled = false
            pcall(function() if e.W:IsValid() then e.W:SetRenderScale({ X = 1, Y = 1 }) end end)
        end
    end
end

local function More(_, t) return t - S.Played < STOP_AFTER end

-- The number of a critical hit in the critical style, when the game gave it another (see the head of the file).
local function Gild(e)
    if not S.Done[CRIT.Name] then return end
    local class, text = S.CritClass, e.Number
    if not Alive(class) then class = Find(ClassPath(CRIT.Name)) S.CritClass = class end
    if not Alive(text) then
        text = e.W.FloatiesText
        if not Alive(text) then text = Child(e.W.FloatieOverlay, "FloatiesText") end
        e.Number = text
    end
    if not (class and text) then return end
    local style = text.Style
    if not Alive(style) or style:GetAddress() ~= class:GetAddress() then text:SetStyle(class) end
end

local function Pop(e, t)
    local W = e.W
    if not (e.Crit and W:IsValid()) then return end
    local playing = W:IsAnimationPlaying(e.Crit)
    if playing and not e.At and not e.Done then
        e.At = t
        pcall(Gild, e)   -- on its own: a failure here must not stop the pop
    end
    if e.At then
        local s = M.Scale(t - e.At)
        W:SetRenderScale({ X = s, Y = s })
        e.Scaled = true
        if s == 1 then e.At, e.Done, e.Scaled = nil, true, false end
    end
    if not playing then e.Done = nil end
end

local function Step(ctx, t)
    for _, e in ipairs(S.List) do pcall(Pop, e, t) end
    if not More(ctx, t) then Rest() return false end
end

---------------------------------------------------------------- off, a new world, the step

-- The game's look back, from what the game holds now: each style class that still holds our values gets its originals
-- back, each number and word we dressed gets its opacities, and its word reads the class again.
-- No pop, every number at scale 1. It needs no state of the round, so it works after a restart or a new world too.
local function Undo(ctx)
    if Lib then Lib.Stop(S.Chain) end
    Rest()
    for _, style in ipairs(LIST) do
        local o = S.Orig[style.Name]
        local ok, err = pcall(function()
            local cdo = o and Find(CdoPath(style.Name))
            if cdo and Ours(cdo, style) then Restore(cdo, o, style) end
        end)
        if not ok then ctx.Log("combat text: " .. style.Name .. " not put back: " .. tostring(err)) end
    end
    for _, kind in ipairs(KINDS) do
        local list, keys = ctx.Find(kind.Class)
        for i, W in ipairs(list) do
            pcall(function()
                if not Alive(W) then return end
                if kind.Pop then W:SetRenderScale({ X = 1, Y = 1 }) end   -- a pop cut short by a new world
                local seen = Record(keys[i], W)
                if not seen then return end
                for n, name in ipairs(kind.Parts) do
                    local part = W[name]
                    if Alive(part) then part:SetRenderOpacity(seen[n]) end
                end
                -- a word reads its style class once: the class has the game's values again, so it reads them
                kind.Reread(W)
            end)
        end
    end
    ctx.Log("combat text: off, the game's look is back")
    S = Fresh(S)   -- on again later: written and dressed again
    S.Off = true
end

function M.Tick(ctx)
    local now = os.clock()
    Lib = ctx.Chain
    if not ctx.On() then
        -- once for each round, and only when there is something of ours to take back
        if not S.Off and (next(S.Orig) or next(S.Seen)) then Undo(ctx) end
        S.Off = true
        return
    end
    S.Off = nil
    if now >= S.Next then
        S.Next = now + EVERY
        Defaults(ctx)
        Pool(ctx)
    end
    -- one call for each number, no closure: a handle that went invalid since the last look is skipped
    for _, e in ipairs(S.List) do
        local W = e.W
        if Alive(W) and W:IsAnyAnimationPlaying() then S.Played = now break end
    end
    -- the step that starts the chain paints too, or the first pop after a calm stretch would start one chain call late
    if Lib and Lib.Run(S.Chain, ctx, 16, Step, More) then Step(ctx, now) end
end

-- A new world or a player restart: every handle is dropped. The values read before the first write stay: the style
-- class may hold ours still, and they are what the switch puts back. A player restart leaves the numbers standing, so
-- their scale goes back to 1; a new world may keep them too (they belong to the game instance), so nothing is called on
-- them, and the records of their opacities stay (Record).
function M.Forget(sameWorld)
    if sameWorld then Rest() end
    if Lib then Lib.Stop(S.Chain) end
    S = Fresh(S)
end

-- for the F9 panel's warning line: a build gave up (see MayTry)
function M.Problem() return (S.Defaults.Fails or 0) >= 3 or (S.Widgets.Fails or 0) >= 3 end

return M
