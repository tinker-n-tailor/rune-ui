-- The F9 editor's panel and the mark on the selected element (design sketch of 01-10-2026, playtest: "This looks nice
-- honestly"). The bag panel's look: its background with the double gold frame (MI_Menu_PanelBG_Shared), Poppins,
-- the menu buttons' key boxes (keycap.png). A small screen map shows where every element sits, the selected one
-- lit gold; the list is grouped by screen area; X and Y sit next to Size and Opacity. On the game screen, gold
-- corners with a slow pulse and a dark name tag replace the pale gold box. F8's map settings use the same panel.
-- main.lua builds a plain table of what to show (the view) and calls M.Update only when it changed; this file draws.
-- Built on the first F9 or F8, when a world exists. main.lua loads this file with pcall.

local M = {}

local ART_DIR = "ue4ss/Mods/RuneUI/Art/"
local PANEL_BG = "/Game/Art/UI/ShaderWork/MI_Menu_PanelBG_Shared.MI_Menu_PanelBG_Shared"   -- the bag's panel (probe)
local WIDTH, PAD = 460, 28   -- 420 left four key boxes and a long name no room (playtest, 01-10-2026)
local INNER = WIDTH - 2 * PAD
local MAP_W, MAP_H = INNER, math.floor(INNER * 9 / 16)   -- the screen map: a 16:9 screen
M.ROWS, M.BOXES, M.KEYS, M.CAPS = 10, 40, 8, 4            -- list lines (group titles too), map boxes, key cells, caps a cell

local function Lin1(c) if c <= 0.04045 then return c / 12.92 end return ((c + 0.055) / 1.055) ^ 2.4 end
local function Hex(h, a)
    local r, g, b = tonumber(h:sub(2, 3), 16) / 255, tonumber(h:sub(4, 5), 16) / 255, tonumber(h:sub(6, 7), 16) / 255
    return { R = Lin1(r), G = Lin1(g), B = Lin1(b), A = a or 1 }
end
-- the sketch's colours
local GOLD, TEXT, MUTED, DIM = Hex("#e3b861"), Hex("#f1ead9"), Hex("#a39a88"), Hex("#6e675b")
local LINE, MAPBG, MAPBOX = Hex("#6f5a34"), Hex("#12110e"), Hex("#4a4336")
local SELFILL, ROWSEL, TAGBG = Hex("#e3b861", 0.18), Hex("#e3b861", 0.14), Hex("#14120e", 0.88)
local WARN = Hex("#d98c6a")   -- the line that names a part that failed
local NONE = { R = 0, G = 0, B = 0, A = 0 }

local function Obj(path) return StaticFindObject(path) end
local function New(cls, outer, name) return StaticConstructObject(Obj("/Script/UMG." .. cls), outer, FName(name)) end

M.W = nil   -- the user widget; everything below lives in it and goes with it
local U = {}   -- the widgets Update writes to

local function Build(ctx)
    local n = 0
    local tree
    -- a new name on every build: a retry after a failed build must not reuse a live name under the same outer
    -- (that crashed the game on 27-09-2026, see main.lua Uniq)
    M.Builds = (M.Builds or 0) + 1
    local function Name(s) n = n + 1 return "RU_Ed" .. s .. "_" .. ctx.Gen() .. "_" .. M.Builds .. "_" .. n end
    local function W(cls) return New(cls, tree, Name(cls)) end
    local function Text(size, color, s, spacing)
        local T = W("TextBlock")
        T:SetText(FText(s or ""))
        T:SetColorAndOpacity({ SpecifiedColor = color, ColorUseRule = 0 })
        pcall(function()
            local fi = T.Font
            if ctx.Font then fi.FontObject = ctx.Font end
            fi.Size = size
            if spacing then fi.LetterSpacing = spacing end
            T:SetFont(fi)
        end)
        return T
    end
    local KRL = Obj("/Script/Engine.Default__KismetRenderingLibrary")
    local function Art(file) return KRL:ImportFileAsTexture2D(tree, ART_DIR .. file) end
    -- a picture drawn in nine pieces: its corners keep their size, the rest stretches
    local function Nine(tex, size, margin, tint)
        local I = W("Image")
        I:SetBrushFromTexture(tex, false)
        local b = I.Brush
        b.DrawAs = 1
        b.Margin = { Left = margin, Top = margin, Right = margin, Bottom = margin }
        b.ImageSize = { X = size, Y = size }
        I:SetBrush(b)
        I:SetColorAndOpacity(tint)
        return I
    end
    local function Sized(child, w, h)
        local S = W("SizeBox")
        if w then S:SetWidthOverride(w) end
        if h then S:SetHeightOverride(h) end
        S:SetContent(child)
        return S
    end
    local function AddV(box, child, top, bottom)
        local s = box:AddChildToVerticalBox(child)
        s:SetPadding({ Left = 0, Top = top or 0, Right = 0, Bottom = bottom or 0 })
        return s
    end
    local function AddH(box, child, right, fill)
        local s = box:AddChildToHorizontalBox(child)
        s:SetPadding({ Left = 0, Top = 0, Right = right or 0, Bottom = 0 })
        s:SetVerticalAlignment(2)
        if fill then s:SetSize({ SizeRule = 1, Value = 1 }) end
        return s
    end
    local function Fill(ov, child)
        local s = ov:AddChildToOverlay(child)
        s:SetHorizontalAlignment(0) s:SetVerticalAlignment(0)
        return s
    end

    local uw = New("UserWidget", FindFirstOf("GameInstance"), Name("Editor"))
    tree = New("WidgetTree", uw, Name("Tree"))
    uw.WidgetTree = tree
    local canvas = W("CanvasPanel")
    tree.RootWidget = canvas

    -- the mark on the selected element: the corners, and the name tag above them
    local corners = Nine(Art("edit_corners.png"), 64, 0.45, GOLD)
    U.Mark = canvas:AddChildToCanvas(corners)
    U.Mark:SetAutoSize(false)
    U.MarkW = corners
    local tag = W("Border")
    tag:SetBrushColor(TAGBG)
    tag:SetPadding({ Left = 8, Top = 2, Right = 8, Bottom = 3 })
    local tagRow = W("HorizontalBox")
    U.TagName, U.TagXY = Text(12, TEXT), Text(12, GOLD)
    AddH(tagRow, U.TagName, 8) AddH(tagRow, U.TagXY)
    tag:SetContent(tagRow)
    U.Tag = canvas:AddChildToCanvas(tag)
    U.Tag:SetAutoSize(true)
    U.TagW = tag

    -- the panel: the bag's background, then the body
    local stack = W("Overlay")
    local bg = W("Image")
    local mat = ctx.Asset(PANEL_BG, "/Script/Engine.MaterialInterface")
    if mat then bg:SetBrushFromMaterial(mat) else bg:SetColorAndOpacity(Hex("#1c1915", 0.96)) end
    Fill(stack, bg)
    local body = W("VerticalBox")
    Fill(stack, body):SetPadding({ Left = PAD, Top = PAD - 4, Right = PAD, Bottom = PAD - 4 })
    local panel = Sized(stack, WIDTH, nil)
    U.Panel = canvas:AddChildToCanvas(panel)
    U.Panel:SetAutoSize(true)
    U.PanelW = panel

    local function Divider(top, bottom)   -- a thin gold line with a diamond in the middle
        local row = W("HorizontalBox")
        local function Line() local L = W("Border") L:SetBrushColor(LINE) return Sized(L, nil, 1) end
        AddH(row, Line(), 8, true)
        local d = W("Border") d:SetBrushColor(LINE)
        local ds = Sized(d, 7, 7) ds:SetRenderTransformAngle(45)
        AddH(row, ds, 8)
        AddH(row, Line(), 0, true)
        AddV(body, row, top, bottom)
        return row
    end
    local function Cap(tex, s)   -- a key box of the game with a key's name in it
        local B = W("Border")
        B:SetBrushFromTexture(tex)
        local br = B.Background
        br.DrawAs = 1
        br.Margin = { Left = 0.5, Top = 0.5, Right = 0.5, Bottom = 0.5 }
        br.ImageSize = { X = 8, Y = 8 }
        B:SetBrush(br)
        B:SetPadding({ Left = 8, Top = 3, Right = 8, Bottom = 4 })
        B:SetHorizontalAlignment(2)
        local T = Text(11, TEXT, s)
        B:SetContent(T)
        local S = W("SizeBox")   -- one-letter keys as wide as tall
        S:SetMinDesiredWidth(26)
        S:SetContent(B)
        return S, T
    end
    -- our key box, as under the menu buttons. The game's (T_Keys-Standard-Blank) is drawn at its own size whatever
    -- ImageSize says, so its thick corners ran over the key names (a screenshot, 01-10-2026)
    local keyTex = Art("keycap.png")

    -- the head: title, and what the panel is
    local head = W("HorizontalBox")
    U.Title = Text(17, TEXT, "RUNE UI", 180)
    AddH(head, U.Title, 12, true)
    U.SubA, U.SubB = Text(12, MUTED), Text(12, GOLD)
    AddH(head, U.SubA, 4) AddH(head, U.SubB)
    AddV(body, head)
    Divider(14, 14)

    -- the profiles (F9 only)
    local prof = W("HorizontalBox")
    AddH(prof, Text(12, MUTED, "Profile"), 10)
    U.Slots = {}
    for i = 1, 3 do
        local B = W("Border")
        B:SetPadding({ Left = 9, Top = 1, Right = 9, Bottom = 2 })
        local T = Text(12, MUTED, tostring(i))
        B:SetContent(T)
        local frame = W("Overlay")
        Fill(frame, Nine(Art("edit_frame.png"), 8, 0.25, MAPBOX))
        Fill(frame, B)
        AddH(prof, frame, 4)
        U.Slots[i] = { B = B, T = T, F = frame }
    end
    AddH(prof, W("Spacer"), 0, true)
    if keyTex then AddH(prof, (Cap(keyTex, "F7")), 8) end
    -- F7 saves before it switches; "Next profile" alone left the player unsure how a profile is saved (01-10-2026)
    AddH(prof, Text(12, MUTED, "Save, next profile"))
    U.Profile = prof
    AddV(body, prof, 0, 12)

    -- the screen map
    local map = W("Overlay")
    local mapBg = W("Border") mapBg:SetBrushColor(MAPBG)
    Fill(map, mapBg)
    Fill(map, Nine(Art("edit_frame.png"), 8, 0.25, Hex("#3a3226")))
    local mc = W("CanvasPanel")
    mc:SetClipping(1)   -- nothing drawn past the map's edge, the label included
    Fill(map, mc)
    U.SelFill = mc:AddChildToCanvas((function() local B = W("Border") B:SetBrushColor(SELFILL) U.SelFillW = B return B end)())
    U.SelFill:SetAutoSize(false)
    U.Boxes = {}
    local frameTex = Art("edit_frame.png")
    for i = 1, M.BOXES do
        local I = Nine(frameTex, 8, 0.25, MAPBOX)
        local s = mc:AddChildToCanvas(I)
        s:SetAutoSize(false)
        I:SetVisibility(1)
        U.Boxes[i] = { I = I, S = s }
    end
    U.MapLabel = Text(11, GOLD)
    U.MapLabelS = mc:AddChildToCanvas(U.MapLabel)
    U.MapLabelS:SetAutoSize(true)
    U.Map = Sized(map, MAP_W, MAP_H)
    AddV(body, U.Map, 0, 14)

    -- the selected element: its name, then X, Y, size, opacity and step
    U.Name = Text(16, TEXT)
    AddV(body, U.Name, 0, 6)
    local facts = W("HorizontalBox")
    U.Facts = {}
    for i = 1, 5 do
        local L, V = Text(12, MUTED), Text(12, TEXT)
        AddH(facts, L, 4) AddH(facts, V, 11)
        U.Facts[i] = { L = L, V = V }
    end
    AddV(body, facts)
    U.Hint = Text(12, MUTED)
    pcall(function() U.Hint:SetAutoWrapText(true) end)
    AddV(body, U.Hint, 6)
    -- a part that failed is named here, so a player learns it without the log (1.4)
    U.Warn = Text(12, WARN)
    pcall(function() U.Warn:SetAutoWrapText(true) end)
    AddV(body, U.Warn, 6)
    Divider(14, 10)

    -- the list: group titles and rows share the lines
    U.Rows = {}
    for i = 1, M.ROWS do
        local B = W("Border")
        B:SetPadding({ Left = 8, Top = 3, Right = 8, Bottom = 3 })
        local row = W("HorizontalBox")
        local d = W("Border") d:SetBrushColor(GOLD)
        local ds = Sized(d, 6, 6) ds:SetRenderTransformAngle(45)
        local dbox = Sized(ds, 14, nil)
        -- centred in its box: stretched to the box's width, the turned square drew as a slanted bar (in game)
        pcall(function() local s = ds.Slot s:SetHorizontalAlignment(2) s:SetVerticalAlignment(2) end)
        AddH(row, dbox)
        local T, note = Text(13, TEXT), Text(11, MUTED)   -- F8's values live here: readable, not dim
        AddH(row, T, 8, true) AddH(row, note)
        pcall(function() T:SetClipping(1) end)
        pcall(function() T:SetTextOverflowPolicy(1) end)   -- ellipsis, where the engine has it
        B:SetContent(row)
        local head = Text(11, MUTED, "", 120)
        local cell = W("Overlay")
        Fill(cell, B)
        local hs = cell:AddChildToOverlay(head) hs:SetVerticalAlignment(3) hs:SetPadding({ Left = 0, Top = 8, Right = 0, Bottom = 1 })
        AddV(body, cell)
        U.Rows[i] = { B = B, T = T, Note = note, Diamond = ds, Head = head, Row = row }
    end
    Divider(10, 12)

    -- the keys, two to a line
    U.Keys = {}
    local grid = W("VerticalBox")
    local line
    for i = 1, M.KEYS do
        if i % 2 == 1 then line = W("HorizontalBox") AddV(grid, line, 0, 6) end
        local cell = W("HorizontalBox")
        local caps = {}
        for c = 1, M.CAPS do
            if keyTex then
                local B, T = Cap(keyTex, "")
                AddH(cell, B, 6)
                caps[c] = { B = B, T = T }
            end
        end
        local act = Text(12, MUTED)
        AddH(cell, act, 0):SetPadding({ Left = 4, Top = 0, Right = 0, Bottom = 0 })   -- room between the keys and the word
        AddH(line, Sized(cell, INNER / 2, nil))
        U.Keys[i] = { Caps = caps, Act = act, Cell = cell }
    end
    AddV(body, grid)

    uw:AddToViewport(20000)   -- above the game's HUD: at 1000 the moved bars drew over the panel (in game)
    uw:SetVisibility(1)   -- collapsed until the editor opens
    M.W = uw
end

local function Show(w, on) w:SetVisibility(on and 3 or 1) end
local function Color(T, c) T:SetColorAndOpacity({ SpecifiedColor = c, ColorUseRule = 0 }) end

-- the whole view: see main.lua EditView and MapView for its fields
function M.Update(v)
    local edit = v.Mode == "edit"
    U.Title:SetText(FText(v.Title))
    U.SubA:SetText(FText(v.SubA or ""))
    U.SubB:SetText(FText(v.SubB or ""))
    Show(U.Profile, edit)
    if edit then
        for i, s in ipairs(U.Slots) do
            local on = v.Profile == i
            s.B:SetBrushColor(on and ROWSEL or NONE)
            Color(s.T, on and GOLD or MUTED)
        end
    end
    Show(U.Map, edit and v.Map ~= nil)
    if edit and v.Map then
        local k = MAP_W / 1920
        local sel
        for i, b in ipairs(U.Boxes) do
            local e = v.Map[i]
            if e then
                b.S:SetPosition({ X = e.X * k, Y = e.Y * k })
                b.S:SetSize({ X = math.max(3, e.W * k), Y = math.max(3, e.H * k) })
                b.I:SetColorAndOpacity(e.Sel and GOLD or e.Hidden and Hex("#4a4336", 0.45) or MAPBOX)
                b.S:SetZOrder(e.Sel and 2 or 1)
                b.I:SetVisibility(3)
                if e.Sel then sel = e end
            else
                b.I:SetVisibility(1)
            end
        end
        Show(U.SelFillW, sel ~= nil)
        Show(U.MapLabel, sel ~= nil)
        if sel then
            U.SelFill:SetPosition({ X = sel.X * k, Y = sel.Y * k })
            U.SelFill:SetSize({ X = math.max(3, sel.W * k), Y = math.max(3, sel.H * k) })
            U.MapLabel:SetText(FText(sel.Name))
            -- under the box, or above it near the bottom; right-aligned near the right edge
            local ly = (sel.Y + sel.H) * k + 3
            if ly > MAP_H - 16 then ly = sel.Y * k - 17 end
            -- 7 units a letter at 11 (6 let "Time of day icon (immersive)" run past the edge: playtest, 01-10-2026)
            local tw = #sel.Name * 7
            local lx = sel.X * k
            if lx > MAP_W * 0.55 then lx = (sel.X + sel.W) * k - tw end
            lx = math.max(2, math.min(lx, MAP_W - tw - 2))
            U.MapLabelS:SetPosition({ X = lx, Y = ly })
        end
    end
    U.Name:SetText(FText(v.Name or ""))
    for i, f in ipairs(U.Facts) do
        local p = v.Facts and v.Facts[i]
        Show(f.L, p ~= nil) Show(f.V, p ~= nil)
        if p then f.L:SetText(FText(p[1])) f.V:SetText(FText(p[2])) end
    end
    U.Hint:SetText(FText(v.Hint or ""))
    Show(U.Hint, (v.Hint or "") ~= "")
    U.Warn:SetText(FText(v.Warn or ""))
    Show(U.Warn, (v.Warn or "") ~= "")
    for i, r in ipairs(U.Rows) do
        local row = v.Rows[i]
        if not row then
            Show(r.B, false) Show(r.Head, false)
        elseif row.Head then
            Show(r.B, false) Show(r.Head, true)
            r.Head:SetText(FText(string.upper(row.Text)))
        else
            Show(r.B, true) Show(r.Head, false)
            r.T:SetText(FText(row.Text))
            r.Note:SetText(FText(row.Note or ""))
            r.B:SetBrushColor(row.Sel and ROWSEL or NONE)
            Color(r.T, row.Sel and GOLD or row.Dim and DIM or TEXT)
            r.Diamond:SetVisibility(row.Moved and 3 or 2)   -- hidden, not collapsed: the names stay in line
        end
    end
    for i, k in ipairs(U.Keys) do
        local e = v.Keys[i]
        Show(k.Cell, e ~= nil)
        if e then
            for c, cap in ipairs(k.Caps) do
                local s = e[1][c]
                Show(cap.B, s ~= nil)
                if s then cap.T:SetText(FText(s)) end
            end
            k.Act:SetText(FText(e[2]))
        end
    end
    -- the mark on the game screen
    local m = v.Mark
    Show(U.MarkW, m ~= nil)
    Show(U.TagW, m ~= nil)
    if m then
        local g = 8   -- the corners sit a little outside the element
        U.Mark:SetPosition({ X = m.X - g, Y = m.Y - g })
        U.Mark:SetSize({ X = m.W + 2 * g, Y = m.H + 2 * g })
        U.TagName:SetText(FText(m.Name))
        U.TagXY:SetText(FText(m.XY or ""))
        U.Tag:SetPosition({ X = m.X - g, Y = (m.Y - g - 30 >= 4) and (m.Y - g - 30) or (m.Y + m.H + g + 6) })
    end
end

-- where the panel sits on the screen, in viewport units; written only when it changes
function M.Place(at)
    if U.At and U.At.X == at.X and U.At.Y == at.Y then return end
    U.At = at
    U.Panel:SetPosition(at)
end

-- the panel's size on screen, once drawn: main.lua places it clear of the selected element
function M.Size()
    local ok, s = pcall(function() return U.PanelW:GetDesiredSize() end)
    if ok and s and s.X > 1 then return s.X, s.Y end
    return WIDTH, 760
end

-- the corners breathe: solid, then a little under half, 1.6 s a breath (the sketch)
function M.Pulse(now)
    if U.MarkW then U.MarkW:SetRenderOpacity(0.72 + 0.28 * math.cos(now * math.pi * 2 / 1.6)) end
end

function M.Open(on)
    if not (M.W and M.W:IsValid()) then return end
    M.W:SetVisibility(on and 3 or 1)   -- shown, clicks go through it; or collapsed
end

function M.Ready() return M.W ~= nil and M.W:IsValid() end

function M.Build(ctx)
    local ok, err = pcall(Build, ctx)
    if not ok then
        pcall(function() if M.W then M.W:RemoveFromParent() end end)
        M.W, U = nil, {}
    end
    return ok, err
end

-- a new world: the old panel went with it
function M.Forget() M.W, U = nil, {} end

return M
