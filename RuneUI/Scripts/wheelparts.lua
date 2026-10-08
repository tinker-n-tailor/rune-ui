-- The data of the three radial wheels and the writes that remember the game's value (wheels.lua uses both).
-- Every write to a game widget goes through Set or Keep, so the row off can put each old value back. The last part
-- holds what wheelmeters.lua and wheelbooks.lua share for the widgets that the mod makes itself.
-- main.lua loads this file with pcall and gives it to wheels.lua.

local M = {}

local ART_DIR = (RUNEUI_DIR or "ue4ss/Mods/RuneUI/") .. "Art/"
M.ART_DIR = ART_DIR   -- wheels.lua loads its pictures from the same folder
local COLLAPSED = 1   -- ESlateVisibility
local CENTRE = { X = 0.5, Y = 0.5 }
-- the two spark effects of the game around the middle ring of Q
local SYSTEMS = { "/Game/Art/VFX/UI/NS_UI_RadialLoop.NS_UI_RadialLoop", "/Game/Art/VFX/UI/NS_UI_RadialLoop_Upper.NS_UI_RadialLoop_Upper" }
local SPARKS_AGAIN, SPARKS_TRIES = 10, 5   -- the game's own sparks not there yet: seconds to the next try, and the tries
local PANEL_NAME = "WBP_Spellcasting_MainPanel_C_%d+"
local PANEL = PANEL_NAME .. "%.WidgetTree_%d+%."
-- Slice: the picture for each image of a slot. Full: unpicked rings at full strength.
-- Solid: the game draws the middle ring faint until it is enabled. Icon: the render scale of a slot's icon.
-- Spells: the wheel also gets what wheelspells.lua does. Hand: the picture for the slot of the item in hand.
-- Sparks: the wheel gets sparks around its middle ring (wheelmeters.lua), at this scale of the ones on Q.
-- Page: Q and H keep visibility 4 closed or open. Their panel is collapsed while both are closed, and the page of its
-- switcher (this number) says which of the two is open (probe of 07-10-2026). R tells by its own visibility.
M.WHEELS = {
    -- Path: the spell book holds a second wheel of the same class, so only the one of the HUD panel is taken
    { Key = "Q", Class = "WBP_SurvivalSorcery_RadialSelector_C", Path = { PANEL .. "SpellRadialWidget$" },
      Slice = { Background = "wheel_q_ring.png", Highlight = "wheel_q_on.png", HighlightDisabled = "wheel_q_on.png" },
      Centre = "wheel_c_q.png", Solid = true, Shade = "wheel_q_shade.png", Spells = true, Page = 0 },
    { Key = "R", Class = "WBP_QuickAccess_RadialSelector_C",
      Slice = { Background = "wheel_r_ring.png", Highlight = "wheel_r_on.png" }, Hand = "wheel_r_hand.png",
      Centre = "wheel_c_r.png", Full = true, Sparks = 0.82 },
    { Key = "H", Class = "WBP_Emotes_RadialSelector_C", Path = { PANEL .. "EmoteRadialWidget$" },
      Slice = { Background = "wheel_h_ring.png", Highlight = "wheel_h_on.png" }, Icon = 0.58, Name = { "EmoteName", 14 },
      Centre = "wheel_c_h.png", Full = true, Sparks = 0.70, Page = 1 },
}
-- the material scalars that draw the dark square behind an item of the R wheel
M.SQUARE = { "Background Opacity", "BackGround Shadows Opacity", "Background Grain Noise Opacity",
    "Background Texture Opacity", "Tint Opacity" }

local TREE = "^%.WidgetTree_%d+%."
local SLICE = TREE .. "RadialSlice_?(%d+)%.WidgetTree_%d+%."
-- What a widget under a wheel is, from the rest of its full name after the wheel's own: "slice" (an image of slot
-- i), "slot" (of the item box of slot i), "wheel" (of the wheel itself), "head" (of the spellbook header) or
-- "cost" (the number of one rune in the cost of a spell; that widget is read by name only, never walked) or
-- "book" (the Foreground image of one of the four spellbook buttons in the header; the name that comes back is the
-- button's).
function M.Part(rest)
    local i, name = string.match(rest, SLICE .. "([%w_]+)$")
    if i then return "slice", tonumber(i), name end
    i, name = string.match(rest, SLICE .. "QuickAccessSlot%.WidgetTree_%d+%.([%w_]+)$")
    if i then return "slot", tonumber(i), name end
    name = string.match(rest, TREE .. "([%w_]+)$")
    if name then return "wheel", nil, name end
    name = string.match(rest, TREE .. "SpellbookSelector%.WidgetTree_%d+%.([%w_]+)$")
    if name then return "head", nil, name end
    if string.find(rest, TREE .. "ResourceCostWidget%.WidgetTree_%d+%.[%w_]+%.WidgetTree_%d+%.AmountText$") then return "cost" end
    name = string.match(rest, TREE .. "SpellbookSelector%.WidgetTree_%d+%.(WBP_DomSpellWheelNavButton_C_%d+)%.WidgetTree_%d+%.Foreground$")
    if name then return "book", nil, name end
end

-- The path of the panel that holds a wheel of Q or H, from the wheel's own path; nil for any other path.
function M.PanelOf(path) return string.match(path, "^(.-" .. PANEL_NAME .. ")%.WidgetTree_%d+%.[%w_]+$") end
-- full is a WidgetSwitcher in the widget tree of the panel with that path (the panel's own, the one that holds the
-- wheels of Q and H)
function M.IsSwitcher(full, panel)
    local path = string.match(full, "^WidgetSwitcher%s+(.*)$")
    return path ~= nil and string.sub(path, 1, #panel) == panel and string.find(path, "^%.WidgetTree_%d+%.WidgetSwitcher$", #panel + 1) ~= nil
end

local function Ok(w) return w and w:IsValid() end
local function Copy(c) return { R = c.R, G = c.G, B = c.B, A = c.A } end
local function Point(p) return { X = p.X, Y = p.Y } end
M.Ok = Ok
-- a variable of game widget W by its name; nil when W has none
function M.Kid(W, name)
    local ok, c = pcall(function() return W[name] end)
    return ok and Ok(c) and c or nil
end

-- A picture of a brush. The game's own is kept as its path and found again by it: a handle kept for a whole
-- session can point at a freed object. A texture is our picture, a text is the path of the game's, and false
-- says that the game had no picture there.
local function Picture(field, set)
    return {
        Read = function(W)
            local r = W[field].ResourceObject
            if not Ok(r) then return false end
            local full = r:GetFullName()
            return string.match(full, "^%S+%s+(.*)$") or full
        end,
        Write = function(W, v)
            if v and type(v) ~= "string" then set(W, v) return end
            local old = v and StaticFindObject(v) or nil
            if v and not Ok(old) then error("the game's picture is gone: " .. v) end
            local b = W[field]
            b.ResourceObject = old   -- nil: a brush with no picture again, so ours does not stay
            W:SetBrush(b)
        end }
end
-- W is still the widget of that full name: a freed widget's place can go to a new object that reads valid
function M.Same(W, full) return Ok(W) and W:GetFullName() == full end
-- a colour; a number writes only the alpha
local function Colour(field, set)
    return {
        Read = function(W) return Copy(W[field]) end,
        Write = function(W, v)
            if type(v) == "number" then
                local c = Copy(W[field])
                c.A = v
                v = c
            end
            set(W, v)
        end }
end

-- Each kind of value: how to read the game's and how to write one.
local PROPS = {
    -- false: the slice takes its size from the picture's box, which must stay the game's
    Picture = Picture("Brush", function(W, tex) W:SetBrushFromTexture(tex, false) end),
    BorderPicture = Picture("Background", function(W, tex) W:SetBrushFromTexture(tex) end),
    Colour = Colour("ColorAndOpacity", function(W, c) W:SetColorAndOpacity(c) end),
    BorderColour = Colour("BrushColor", function(W, c) W:SetBrushColor(c) end),
    Tint = {
        Read = function(W) local t = W.Brush.TintColor return { SpecifiedColor = Copy(t.SpecifiedColor), ColorUseRule = t.ColorUseRule } end,
        Write = function(W, v) W:SetBrushTintColor(v) end },
    Enabled = { Read = function(W) return W:GetIsEnabled() end, Write = function(W, v) W:SetIsEnabled(v) end },
    Visibility = { Read = function(W) return W:GetVisibility() end, Write = function(W, v) W:SetVisibility(v) end },
    Opacity = { Read = function(W) return W:GetRenderOpacity() end, Write = function(W, v) W:SetRenderOpacity(v) end },
    Scale = { Read = function(W) return Point(W.RenderTransform.Scale) end, Write = function(W, v) W:SetRenderScale(v) end },
    Move = { Read = function(W) return Point(W.RenderTransform.Translation) end, Write = function(W, v) W:SetRenderTranslation(v) end },
    Pivot = { Read = function(W) return Point(W.RenderTransformPivot) end, Write = function(W, v) W:SetRenderTransformPivot(v) end },
    -- the width of a size box; false: no width of its own, so the box is as wide as what it holds
    Width = {
        Read = function(W) return W.bOverride_WidthOverride == true and W.WidthOverride end,
        Write = function(W, v) if v then W:SetWidthOverride(v) else W:ClearWidthOverride() end end },
    -- the padding of the widget's slot; v names only the sides that change. A slot that is gone is an error, also
    -- on the way back: nothing is read from it or called on it.
    Padding = {
        Read = function(W)
            local s = W.Slot
            if not Ok(s) then error("no slot") end
            local p = s.Padding
            return { Left = p.Left, Top = p.Top, Right = p.Right, Bottom = p.Bottom }
        end,
        Write = function(W, v)
            local s = W.Slot
            if not Ok(s) then error("no slot") end
            local p = s.Padding
            s:SetPadding({ Left = v.Left or p.Left, Top = v.Top or p.Top, Right = v.Right or p.Right, Bottom = v.Bottom or p.Bottom })
        end },
    -- the font of a text, its size kept
    Font = {
        Read = function(W) return W.Font.FontObject end,
        Write = function(W, v)
            if not Ok(v) then return end
            local f = W.Font
            f.FontObject = v
            W:SetFont(f)
        end },
    Scroll = {
        Read = function(W)
            local v = W.bIsScrollingEnabled
            if type(v) ~= "boolean" then error("the text has no bIsScrollingEnabled") end
            return v
        end,
        Write = function(W, v) W:SetScrollingEnabled(v) end },
}

-- A journal: the undo of every value written, the first value of a key only. Log: for the first error of a kind.
function M.Journal(log) return { List = {}, Seen = {}, Logged = {}, Log = log } end

local function Fail(J, kind, what, err)
    if J.Logged[kind] then return end
    J.Logged[kind] = true
    J.Log("wheels: " .. what .. ": " .. tostring(err))
end

-- make() reads the game's value and returns the function that writes it back. It runs once for a key, before the
-- first write, so a write that fails halfway is still undone. A read that fails stops the write too.
function M.Keep(J, key, make)
    if J.Seen[key] then return end
    J.List[#J.List + 1] = make()
    J.Seen[key] = true
end

-- Writes one value of widget W and remembers the game's. key names the widget; true when written.
function M.Set(J, key, W, prop, value)
    local p = PROPS[prop]
    local ok, err = pcall(function()
        M.Keep(J, key .. "#" .. prop, function()
            local old, full = p.Read(W), W:GetFullName()
            return function() if M.Same(W, full) then p.Write(W, old) end end
        end)
        p.Write(W, value)
    end)
    if not ok then Fail(J, prop, prop .. " of " .. key, err) end
    return ok
end

-- One text made smaller by its render scale when it is wider than its room. most: the largest scale (1 without
-- one). least: the smallest; a text that is still too wide then stays too wide. seen[key] keeps the width that the
-- text wanted at the last write, so a write is made only when the text changed. Returns that width after a write.
function M.Fit(J, seen, key, T, room, most, least)
    if not Ok(T) then return end
    local want = T:GetDesiredSize().X
    if want <= 0 or math.abs(want - (seen[key] or 0)) < 0.5 then return end
    seen[key] = want
    local k = math.max(least or 0, math.min(most or 1, room / want))
    M.Set(J, key, T, "Scale", { X = k, Y = k })
    return want
end

-- A widget that the mod made, held with its full name. Mine says that the handle is still that widget: the place of
-- a freed widget can go to a new object that reads valid, and it must get no write of ours.
function M.Hold(W) return { W = W, Full = W:GetFullName() } end
function M.Mine(o) return o and M.Same(o.W, o.Full) end
-- ours out of the game's widgets (remove) or out of sight; nothing is called on an object that is not ours
function M.Out(o, remove)
    if not M.Mine(o) then return end
    pcall(function() if remove then o.W:RemoveFromParent() else o.W:SetVisibility(COLLAPSED) end end)
end
-- a widget of ours; ctx.G gives a name that no live object has
function M.New(ctx, cls, tree, name) return StaticConstructObject(StaticFindObject("/Script/UMG." .. cls), tree, ctx.G(name)) end
function M.Add(ov, w, h, v, pad)
    local s = ov:AddChildToOverlay(w)
    s:SetHorizontalAlignment(h)
    s:SetVerticalAlignment(v)
    if pad then s:SetPadding(pad) end
end
-- A try to make sparks may run now: SPARKS_TRIES tries in all, SPARKS_AGAIN seconds apart. t keeps the count in
-- SparkTries and the time of the next try in SparksAt (false after the last one). A call before that time is no try.
function M.SparkTry(t, now)
    if t.SparkTries and now < (t.SparksAt or math.huge) then return false end
    t.SparkTries = (t.SparkTries or 0) + 1
    t.SparksAt = t.SparkTries < SPARKS_TRIES and now + SPARKS_AGAIN or false
    return true
end
-- The game's own widget of each spark effect, by the full name of the effect. One search of every spark widget;
-- ours, named RU_, are left out. kept: the caller's table for the Hold of each one found. While the widget of each
-- name in names still lives there, no search runs.
local function SparkSources(kept, names)
    local source, have = {}, 0
    for _, name in ipairs(kept and names or {}) do
        if M.Mine(kept[name]) then source[name], have = kept[name].W, have + 1 end
    end
    if kept and have == #names then return source end
    source = {}
    for _, W in pairs(FindAllOf("NiagaraSystemWidget") or {}) do
        pcall(function()
            if Ok(W) and string.find(W:GetFullName(), "/Engine/Transient.", 1, true) and not string.find(W:GetFName():ToString(), "^RU_") then
                local s = W.NiagaraSystemReference
                if Ok(s) then
                    source[s:GetFullName()] = W
                    if kept then kept[s:GetFullName()] = M.Hold(W) end
                end
            end
        end)
    end
    return source
end
-- The game's two spark effects as widgets of ours in tree, in the middle of the overlay parent, at render scale k and
-- with visibility vis. Returns the Hold of each: two sparks, or an error and none.
-- A spark widget draws nothing without its list of materials for the HUD. The game's own widget of the same
-- effect (on the Q wheel) has that list, so ours copy it. Both effects are checked before one widget is made.
-- kept: see SparkSources; without it each call searches.
function M.Sparks(ctx, tree, parent, k, vis, name, kept)
    local cls = StaticFindObject("/Script/NiagaraUIRenderer.NiagaraSystemWidget")
    if not Ok(cls) then error("no spark widget class") end
    local todo, names = {}, {}
    for n, path in ipairs(SYSTEMS) do
        local system = StaticFindObject(path)
        if not Ok(system) then error("spark effect not loaded: " .. path) end
        todo[n], names[n] = { System = system, Path = path }, system:GetFullName()
    end
    local source = SparkSources(kept, names)
    for n, t in ipairs(todo) do
        t.From = source[names[n]]
        if not t.From then error("no game spark widget to copy the materials from: " .. t.Path) end
    end
    local made = {}
    local ok, err = pcall(function()
        for _, t in ipairs(todo) do
            local N = StaticConstructObject(cls, tree, ctx.G(name))
            made[#made + 1] = M.Hold(N)
            N.NiagaraSystemReference = t.System
            N.AutoActivate = true
            t.From.MaterialRemapList:ForEach(function(key, value) N.MaterialRemapList:Add(key:get(), value:get()) end)
            M.Add(parent, N, 2, 2)
            N:SetRenderTransformPivot(CENTRE)
            N:SetRenderScale({ X = k, Y = k })
            N:SetVisibility(vis)
            N:ActivateSystem(true)
        end
    end)
    if not ok then
        for _, N in ipairs(made) do M.Out(N, true) end   -- no half pair: the next try makes both
        error(err, 0)
    end
    return made
end
-- One of our pictures, size units square, from the Art folder. The statement that loads the texture puts it on a
-- brush, with tree as its owner: the engine frees a texture that only Lua holds. kept (file -> Hold of its texture)
-- gives a later picture the same texture, only while the first one still holds it.
function M.Image(ctx, tree, name, file, size, kept)
    local img = M.New(ctx, "Image", tree, name)
    local have = kept[file]
    if M.Mine(have) then
        img:SetBrushFromTexture(have.W, false)
    else
        img:SetBrushFromTexture(ctx.CachedTex({}, file, tree, ART_DIR .. file), false)
        kept[file] = M.Hold(img.Brush.ResourceObject)
    end
    local b = img.Brush
    b.ImageSize = { X = size, Y = size }
    img:SetBrush(b)
    return img
end

-- Every value back, the last write first. A widget that is gone is skipped.
function M.Restore(J)
    for i = #J.List, 1, -1 do
        local ok, err = pcall(J.List[i])
        if not ok then Fail(J, "restore", "a value not put back", err) end
    end
    J.List, J.Seen = {}, {}
end

return M
