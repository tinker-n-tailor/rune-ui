-- The writes of the notices' look, one part of a notice at a time. noticelook.lua says which part gets which step. A step is
-- function(env, W, info): false to try again later, else true and, as a second value, a check that puts the value back when
-- the game wrote its own. env: Font (a function), Src (parts that other notices copy), Uniq (a name maker, may be nil), Once,
-- CachedTex (main.lua's picture loader, may be nil), Pics (file -> the texture and its full name, shared by all notices).

local S = {}

-- The steps that must run once for a part, as they add up (Move) or make a widget (Lines). An entry with OnShow runs its
-- steps again on each show, so noticelook.lua keeps these out of it.
S.Once = {}

local ART_DIR = (RUNEUI_DIR or "ue4ss/Mods/RuneUI/") .. "Art/"
local GOLD = { R = 0.76, G = 0.48, B = 0.10 }   -- linear light
local BAND_TOP, BAND_BOTTOM = 0.426, 0.574   -- the brown band is the middle strip of the 816 x 422 picture
-- The strip of the lines picture that is drawn: its lower half. The picture's bottom gold line sits at about 0.574 of the height,
-- on the lower edge of the band's strip (measured on Steam screenshots of 07-10-2026); the strip ends a hair below it. The
-- bottom line was seen in the game. The top line is the same half turned over, so both lines are one picture.
local LINES_FROM, LINES_TO = 0.499, 0.578
local GAP = 0   -- units between the band's edge and the line's image, top and bottom. 0: the lines sit on the edges (the owner's word, 08-10-2026).
local ALIGN_FILL, ALIGN_CENTRE = 0, 2   -- the alignments of a slot in an Overlay (the same numbers on both axes)
local COLLAPSED, UNTOUCHABLE = 1, 3   -- ESlateVisibility; 3: seen, and the mouse goes through it

local Made = 0
local function Ok(w) return w and w:IsValid() end

-- A colour whose four fields are numbers. The game's own colour structs have given objects that are not numbers.
local function IsNum(c)
    return c ~= nil and type(c.R) == "number" and type(c.G) == "number" and type(c.B) == "number" and type(c.A) == "number"
end

local function IsColour(c, want)
    return math.abs(c.R - want.R) < 0.01 and math.abs(c.G - want.G) < 0.01 and math.abs(c.B - want.B) < 0.01
end

-- Writes the colour want and returns a check that writes it again when the game wrote its own colour. The first write has
-- full alpha, a later one keeps the game's alpha. A colour that cannot be read as numbers is written once and not watched.
local function Keep(want, read, write)
    local function Paint(a) return { R = want.R, G = want.G, B = want.B, A = a } end
    local ok, c = pcall(read)
    if not (ok and IsNum(c)) then
        write(Paint(1))
        return true
    end
    local first = true
    local function Apply()
        local now = read()
        if not IsNum(now) then return end
        if not IsColour(now, want) then write(Paint(first and 1 or now.A)) end
        first = false
    end
    Apply()
    return true, Apply
end

local function KeepGold(read, write) return Keep(GOLD, read, write) end

function S.GoldImage(env, W)
    return KeepGold(function() return W.ColorAndOpacity end, function(c) W:SetColorAndOpacity(c) end)
end

function S.GoldText(env, W)
    return KeepGold(function() return W.ColorAndOpacity.SpecifiedColor end,
        function(c) W:SetColorAndOpacity({ SpecifiedColor = c, ColorUseRule = 0 }) end)
end

-- The fill of a progress bar: a plain linear colour, not a specified one
function S.GoldFill(env, W)
    return KeepGold(function() return W.FillColorAndOpacity end, function(c) W:SetFillColorAndOpacity(c) end)
end

-- A size box made as high as given
function S.Height(h)
    return function(env, W)
        W:SetHeightOverride(h)
        return true
    end
end

-- A part at the bottom edge of its Overlay, bottom-aligned: its slot's bottom padding is -h, so it hangs h units under that
-- edge (0: its bottom edge is the Overlay's). The game hangs the tip's progress line 3 units under the band in a box 5 high;
-- made 2 high with the same padding it leaves a gap under the band's soft edge. A written value, the same on each show.
function S.Hang(h)
    return function(env, W, info)
        local slot = W.Slot
        if not Ok(slot) then return false end
        local p = slot.Padding
        if type(p.Left) ~= "number" or type(p.Top) ~= "number" or type(p.Right) ~= "number" or type(p.Bottom) ~= "number" then
            env.Once("hang" .. info.Name, "noticelook: " .. info.Name .. " not hung under its band, its padding is not a number")
            return true
        end
        if p.Bottom ~= -h then slot:SetPadding({ Left = p.Left, Top = p.Top, Right = p.Right, Bottom = -h }) end
        return true
    end
end

-- A rich text has its own colour setter
local function RichColour(want)
    return function(env, W)
        return Keep(want, function() return W.DefaultColorAndOpacity.SpecifiedColor end,
            function(c) W:SetDefaultColorAndOpacity({ SpecifiedColor = c, ColorUseRule = 0 }) end)
    end
end
S.GoldRich = RichColour(GOLD)

-- The style that a rich text draws with when no tag says otherwise: its own, when it has one
local function RichStyle(W) return W.bOverrideDefaultStyle and W.DefaultTextStyleOverride or W.DefaultTextStyle end

-- A colour made see-through, its red, green and blue kept. One that cannot be read as numbers becomes see-through white,
-- written once and not watched. The check writes again when the game made the colour visible.
local function Fade(read, write)
    local ok, c = pcall(read)
    if not (ok and IsNum(c)) then
        write({ R = 1, G = 1, B = 1, A = 0 })
        return true
    end
    local function Apply()
        local now = read()
        if IsNum(now) and now.A >= 0.01 then write({ R = now.R, G = now.G, B = now.B, A = 0 }) end
    end
    Apply()
    return true, Apply
end

-- An image or a border made see-through by its colour
function S.Hide(env, W, info)
    local border = string.find(info.Class, "Border")
    return Fade(function() return border and W.BrushColor or W.ColorAndOpacity end,
        function(v) if border then W:SetBrushColor(v) else W:SetColorAndOpacity(v) end end)
end

-- An image made see-through also by the tint of its brush, for a game that writes the image's colour again each
-- frame. Only for images: a border has no tint of this kind.
function S.Unseen(env, W)
    return Fade(function() return W.Brush.TintColor.SpecifiedColor end,
        function(v) W:SetBrushTintColor({ SpecifiedColor = v, ColorUseRule = 0 }) end)
end

-- The page of the master copy: its image is hidden, so a row that the game makes from it is born without the band
function S.Master(env, path)
    local I = StaticFindObject(path)
    if not Ok(I) then return false end
    S.Hide(env, I, { Class = "CommonLazyImage" })
    return true
end

-- The HUD font, the size kept; rich text keeps its font in the default style (as quests.lua)
function S.Font(env, W, info)
    local font = env.Font()
    if not font then return false end
    if string.find(info.Class, "Rich") then
        local fi = RichStyle(W).Font
        fi.FontObject = font
        W:SetDefaultFont(fi)
    else
        local fi = W.Font
        fi.FontObject = font
        W:SetFont(fi)
    end
    return true
end

-- Moves a part from where it is now: written once, as a second write would move it again
function S.Move(x, y)
    local step = function(env, W, info)
        local t = W.RenderTransform.Translation
        if type(t.X) ~= "number" or type(t.Y) ~= "number" then
            env.Once("move" .. info.Name, "noticelook: " .. info.Name .. " not moved, its place is not a number")
            return true
        end
        W:SetRenderTranslation({ X = t.X + x, Y = t.Y + y })
        return true
    end
    S.Once[step] = true
    return step
end

-- A Niagara widget hides only by its own visibility. The check collapses it again when the game showed it.
function S.Collapse(env, W)
    W:SetVisibility(COLLAPSED)
    return true, function()
        if W:GetVisibility() ~= COLLAPSED then W:SetVisibility(COLLAPSED) end
    end
end

-- Keeps the part for other steps (the band picture is the new area banner's BgImage), with its full name, as a freed slot can
-- hold a new valid object. Own: the part belongs to the entry being walked (env.Entry); a second entry keeps its own (SrcKey).
local function SrcKey(env, key, own) return own and (key .. "@" .. env.Entry:GetFullName()) or key end

function S.Remember(key, own)
    return function(env, W) env.Src[SrcKey(env, key, own)] = { W = W, Key = W:GetFullName() } return true end
end

local function Source(env, key)
    local s = env.Src[key]
    if s and Ok(s.W) and s.W:GetFullName() == s.Key then return s.W end
end
S.Source, S.SrcKey = Source, SrcKey   -- for noticeread.lua

-- The step runs only for a part of the entry itself (owner nil) or of one nested widget of the given name
function S.Only(owner, step)
    local only = function(env, W, info)
        if info.Owner ~= owner then return true end
        return step(env, W, info)
    end
    S.Once[only] = S.Once[step]
    return only
end

local function Strip(b, top, bottom)
    local uv = b.UVRegion
    uv.Min.X, uv.Min.Y, uv.Max.X, uv.Max.Y, uv.bIsValid = 0, top, 1, bottom, 1
end

-- The game's brown band on an image: the band's strip of the banner picture. With a width, the image gets that
-- width and its own height (the event's panel); without, it keeps its size and draws as a plain picture.
-- The check puts the band back when the game has set another picture on the image (the tip does that on each show).
function S.Band(width)
    return function(env, W)
        local want
        local function Put()
            local bg = Source(env, "Bg")
            local tex = bg and bg.Brush.ResourceObject
            if not Ok(tex) then return false end
            want = tex:GetFullName()
            local h = W.Brush.ImageSize.Y
            W:SetBrushFromTexture(tex, false)
            local b = W.Brush
            if width then b.ImageSize = { X = width, Y = h } else b.DrawAs = 3 end
            Strip(b, BAND_TOP, BAND_BOTTOM)
            W:SetBrush(b)
            return true
        end
        if not Put() then return false end
        return true, function()
            local r = W.Brush.ResourceObject
            if not (Ok(r) and r:GetFullName() == want) then Put() end
        end
    end
end

-- The lines picture of the new area banner, kept by S.Remember on its HighlightImage
local function LinesPicture(env)
    local src = Source(env, "Lines")
    local tex = src and src.Brush.ResourceObject
    if Ok(tex) then return tex end
end

-- The Overlay that holds the band, or nil with one log line. A parent that is not valid is an error (logged once by the walk).
local function OverlayParent(env, W)
    local parent = W:GetParent()
    if not Ok(parent) then error("the band has no valid parent", 0) end
    local cls = parent:GetClass():GetFName():ToString()
    if cls == "Overlay" then return parent end
    env.Once("overlay" .. cls, "noticelook: no gold lines, the band sits in a " .. cls .. ", not an Overlay")
end

-- A new image of ours in the notice's tree. The name comes from ctx.Uniq, or from a count when there is none.
local function NewImage(env, info, prefix)
    Made = Made + 1
    local name = env.Uniq and env.Uniq(prefix) or (prefix .. Made .. "_" .. os.time())
    return StaticConstructObject(StaticFindObject("/Script/UMG.Image"), info.Tree, FName(name))
end

-- One of the mod's own pictures from the Art folder, decoded once for all notices (env.Pics); nil with one log line when it
-- does not load. The caller puts it on a brush at once: the engine frees a texture that only Lua holds. A kept texture is
-- reused only while it is valid and still has its name.
local function Picture(env, tree, file)
    if not env.CachedTex then env.Once("notex", "noticelook: no picture loader, the mod's own pictures are not added") return end
    local have = env.Pics[file]
    if have and Ok(have.W) and have.W:GetFullName() == have.Key then return have.W end
    local ok, tex = pcall(env.CachedTex, {}, file, tree, ART_DIR .. file)
    if not ok then env.Once("art" .. file, "noticelook: " .. tostring(tex)) return end
    env.Pics[file] = { W = tex, Key = tex:GetFullName() }
    return tex
end

-- Two gold lines outside the band, as on the new area banner: images of ours with that banner's lines picture, in the Overlay
-- that holds the band. Both draw the same half of the picture's strip, the top one turned over (a render scale of -1 down,
-- about its centre), so the two lines are alike and run the whole width of the Overlay. A part is { Name, Out (-1 up, 1 down) }.
-- Each image is half the band image's height, centred and moved a quarter of that height plus GAP out. So each line sits about
-- GAP units outside the band's edge.
local TWO = {
    { Name = "RU_NoticeLinesTop", Out = -1 },
    { Name = "RU_NoticeLinesBottom", Out = 1 },
}

-- One of the lines, made and set but not in the tree yet
local function LineImage(env, info, tex, size, part)
    local img = NewImage(env, info, part.Name)
    img:SetBrushFromTexture(tex, false)
    local b = img.Brush
    b.ImageSize = { X = size.X, Y = size.Y / 2 }
    b.DrawAs = 3
    Strip(b, LINES_FROM, LINES_TO)
    img:SetBrush(b)
    img:SetColorAndOpacity({ R = GOLD.R, G = GOLD.G, B = GOLD.B, A = 1 })
    img:SetVisibility(UNTOUCHABLE)
    img:SetRenderTranslation({ X = 0, Y = part.Out * (size.Y / 4 + GAP) })
    if part.Out < 0 then
        img:SetRenderTransformPivot({ X = 0.5, Y = 0.5 })
        img:SetRenderScale({ X = 1, Y = -1 })
    end
    return img
end

-- The lines wait, with one log line for each kind of notice (env.Label), while the band's image has no size. Both images are made
-- before either is added; an added one is taken out when the other fails: no lone line.
function S.Lines(env, W, info)
    local tex = LinesPicture(env)
    if not tex then return false end
    local parent = OverlayParent(env, W)
    if not parent then return true end
    local size = W.Brush.ImageSize
    if not (type(size.X) == "number" and type(size.Y) == "number" and size.X > 0 and size.Y > 0) then
        env.Once("lineheight" .. env.Label, "noticelook: the gold lines of " .. env.Label .. " wait, the band's image has no size yet")
        return false
    end
    local images, added = {}, {}
    for i, part in ipairs(TWO) do images[i] = LineImage(env, info, tex, size, part) end
    local ok, err = pcall(function()
        for _, img in ipairs(images) do
            local slot = parent:AddChildToOverlay(img)
            added[#added + 1] = img
            slot:SetHorizontalAlignment(ALIGN_FILL)
            slot:SetVerticalAlignment(ALIGN_CENTRE)
        end
    end)
    if not ok then
        for _, img in ipairs(added) do pcall(function() parent:RemoveChild(img) end) end   -- no lone line
        error(err, 0)
    end
    return true
end
S.Once[S.Lines] = true

S.Picture = Picture   -- for noticering.lua

return S
