-- Party panel (1.9; the data came from the probe of 05-10-2026): the other players of a co-op world, one row for each at
-- the top left under the bars: the name, and under it a flat health bar. No numbers. A friend whose character is not
-- loaded on this machine (the game stops sending a character that is about 160 m away) shows a dimmed name and a grey
-- bar. The game has no party frames, so the widgets are ours. With no friend there is nothing on the screen, and the
-- widgets are not even made; F9 shows three made-up rows while the element's row is selected.
-- The data (read only, four times a second at most, each step in a pcall and behind IsValid): the local controller
-- (main.lua's Controller), its world's GameState, PlayerArray (a list of player states, from 1), and for each friend
-- GetPlayerName, GetPawn, and from the pawn GetHealthComponent and GetNormalizedHealth. The game state of the main menu
-- and of the lobby is another class, and their pawns are DefaultPawn: so only a local pawn of the class
-- BP_PlayerCharacter_C counts as a world, and a friend's pawn of another class is not shown. A friend's power level is
-- -1 for us, so it is not read. A game blueprint is never searched for and never changed.
-- main.lua moves and sizes it as the F9 element "party" and loads this file with pcall, so an error here leaves the
-- rest of the mod running.

local M = {}

local MAX = 5                            -- a world holds 4 or 6 players: at most 5 friends
local NAME_SIZE, EDGE_SIZE = 14, 1       -- the quest tracker's name size; the black edge of the letters
M.BOX_W = 225                            -- the width of a row and of its bar; the box F9 moves and sizes holds MAX rows
local BAR_H, ROW_H = 10, 62              -- the bar, and the distance from one row to the next
M.BOX_H = MAX * ROW_H
local PAWN = "BP_PlayerCharacter_C"
local EVERY, ALONE = 0.25, 1             -- seconds between two reads: with a friend, and alone

local function Lin1(c) if c <= 0.04045 then return c / 12.92 end return ((c + 0.055) / 1.055) ^ 2.4 end
local function Lin(r, g, b, a) return { R = Lin1(r / 255), G = Lin1(g / 255), B = Lin1(b / 255), A = a or 1.0 } end
local RED = Lin(239, 45, 54)         -- the player's health bar, measured on a screenshot of the game (05-10-2026)
local GREY = Lin(139, 139, 135)      -- the bar of a friend that is far away
local TRACK = { R = 0, G = 0, B = 0, A = 0.62 }
local WHITE = { R = 1, G = 1, B = 1, A = 1 }
local DIM = { R = 1, G = 1, B = 1, A = 0.55 }
local EDGE = { R = 0, G = 0, B = 0, A = 0.9 }
local SAMPLE = { { Name = "Aldric", Health = 1 }, { Name = "Wren", Health = 0.34 }, { Name = "Tamsin" } }

local function Obj(path) return StaticFindObject(path) end
local function New(cls, outer, name) return StaticConstructObject(Obj("/Script/UMG." .. cls), outer, FName(name)) end
local Logged = {}
local function Once(ctx, key, msg) if not Logged[key] then Logged[key] = true ctx.Log(msg) end end

---------------------------------------------------------------- the data

local function Valid(o) return o ~= nil and o:IsValid() end
local function ClassOf(o) return o:GetClass():GetFName():ToString() end

-- One friend as { Name, Health }: Health is 0 to 1, and nil while the pawn is not loaded here. Nil when the friend has no
-- name yet or the pawn is not a player's.
local function ReadFriend(ps)
    local name = ps:GetPlayerName():ToString()
    if name == "" then return nil end
    local pawn = ps:GetPawn()
    if not Valid(pawn) then return { Name = name } end
    if ClassOf(pawn) ~= PAWN then return nil end
    local hc = pawn:GetHealthComponent()
    if not Valid(hc) then return { Name = name } end
    local h = hc:GetNormalizedHealth()
    if type(h) ~= "number" or h ~= h then return { Name = name } end
    return { Name = name, Health = math.max(0, math.min(1, h)) }
end

-- The other players of the world, in the game's order, MAX at most. Nothing while the local player is not a character
-- in a world (the menu, the lobby, loading, dead).
local function Friends(ctx)
    local pc = ctx.Controller()
    if not Valid(pc) then return {} end
    local me, mine = pc.Pawn, pc.PlayerState
    if not (Valid(me) and ClassOf(me) == PAWN and Valid(mine)) then return {} end
    local world = pc:GetWorld()
    if not Valid(world) then return {} end
    local gs = world.GameState
    if not Valid(gs) then return {} end
    local arr = gs.PlayerArray
    local list = {}
    for i = 1, math.min(arr:GetArrayNum(), MAX + 1) do   -- the local player is one of them
        local ps = arr[i]
        if Valid(ps) and ps:GetAddress() ~= mine:GetAddress() then
            local f = ReadFriend(ps)
            if f then list[#list + 1] = f end
        end
    end
    return list
end

-- Counts the reads in which a friend's health went down (M.Hits): the immersive mode brings the panel back on a change.
-- A friend is told by the name; one that was far, or is new, has nothing to be lower than.
local function Track(list)
    local now = {}
    for _, f in ipairs(list) do
        if f.Health then
            local was = M.Seen[f.Name]
            if was and f.Health < was - 0.001 then M.Hits = M.Hits + 1 end
            now[f.Name] = f.Health
        end
    end
    M.Seen = now
end

---------------------------------------------------------------- the widgets

-- a flat rectangle drawn by the brush (as cooldowns.lua draws its tiles, with no rounding), white, so the colour is the tint
local function Flat(tree, name, color)
    local img = New("Image", tree, name)
    local b = img.Brush
    b.DrawAs = 4   -- RoundedBox
    b.TintColor = { SpecifiedColor = WHITE, ColorUseRule = 0 }
    b.OutlineSettings.RoundingType = 0
    b.OutlineSettings.CornerRadii = { X = 0, Y = 0, Z = 0, W = 0 }
    b.OutlineSettings.Width = 0
    b.OutlineSettings.Color = { SpecifiedColor = { R = 0, G = 0, B = 0, A = 0 }, ColorUseRule = 0 }
    img:SetBrush(b)
    img:SetColorAndOpacity(color)
    return img
end

local function Row(ctx, tree, i)
    local n = "RU_Pt" .. i
    local box = New("SizeBox", tree, n)
    box:SetWidthOverride(M.BOX_W)
    box:SetHeightOverride(ROW_H)
    local col = New("VerticalBox", tree, n .. "Col")
    box:SetContent(col)
    local text = ctx.Text(tree, n .. "Name", NAME_SIZE, WHITE, "")
    pcall(function()
        local fi = text.Font   -- our own text, so the edge touches nothing of the game
        fi.OutlineSettings.OutlineSize = EDGE_SIZE
        fi.OutlineSettings.OutlineColor = EDGE
        text:SetFont(fi)
    end)
    col:AddChildToVerticalBox(text)
    local bar = New("SizeBox", tree, n .. "Bar")
    bar:SetWidthOverride(M.BOX_W)
    bar:SetHeightOverride(BAR_H)
    local ov = New("Overlay", tree, n .. "Ov")
    bar:SetContent(ov)
    ov:AddChildToOverlay(Flat(tree, n .. "Track", TRACK))   -- fills the box
    local fillBox = New("SizeBox", tree, n .. "FillBox")
    fillBox:SetWidthOverride(M.BOX_W)
    local fill = Flat(tree, n .. "Fill", RED)
    fillBox:SetContent(fill)
    ov:AddChildToOverlay(fillBox):SetHorizontalAlignment(1)   -- left
    col:AddChildToVerticalBox(bar):SetPadding({ Left = 0, Top = 3, Right = 0, Bottom = 0 })
    box:SetVisibility(1)
    return { Box = box, Text = text, FillBox = fillBox, Fill = fill, W = M.BOX_W }
end

local function Build(ctx)
    M.Builds = (M.Builds or 0) + 1   -- a new name on every build (see runemap.lua)
    local uw = New("UserWidget", FindFirstOf("GameInstance"), "RuneUIParty" .. M.Builds)
    local tree = New("WidgetTree", uw, "RuneUIPartyTree")
    uw.WidgetTree = tree
    local canvas = New("CanvasPanel", tree, "RU_PtCanvas")
    tree.RootWidget = canvas
    local size = New("SizeBox", tree, "RU_PtSize")
    size:SetWidthOverride(M.BOX_W)
    size:SetHeightOverride(M.BOX_H)
    local col = New("VerticalBox", tree, "RU_PtColumn")
    size:SetContent(col)
    local rows = {}
    for i = 1, MAX do
        rows[i] = Row(ctx, tree, i)
        col:AddChildToVerticalBox(rows[i].Box)
    end
    local E = ctx.ById("party")
    local slot = canvas:AddChildToCanvas(size)
    slot:SetAutoSize(true)
    -- tied to the top left corner, so it stays under the bars on a wide screen; the spot is measured on a 16:9 screen,
    -- 1920 x 1080 units (as cooldowns.lua)
    slot:SetAnchors({ Minimum = { X = 0, Y = 0 }, Maximum = { X = 0, Y = 0 } })
    slot:SetPosition({ X = E.Center.X - M.BOX_W / 2, Y = E.Center.Y - M.BOX_H / 2 })
    uw:AddToViewport(36)
    uw:SetVisibility(1)
    M.W, M.UW, M.Rows, M.Visible = size, uw, rows, false
    ctx.Log("party panel ready")
end

-- one row, written only where it changed; no friend: the row is collapsed
local function Show(r, f)
    local on = f ~= nil
    if on ~= r.On then r.On = on r.Box:SetVisibility(on and 4 or 1) end
    if not f then return end
    if f.Name ~= r.Name then r.Name = f.Name r.Text:SetText(FText(f.Name)) end
    local far = f.Health == nil
    if far ~= r.Far then
        r.Far = far
        r.Text:SetColorAndOpacity({ SpecifiedColor = far and DIM or WHITE, ColorUseRule = 0 })
        r.Fill:SetColorAndOpacity(far and GREY or RED)
    end
    local w = math.floor(M.BOX_W * (f.Health or 1) + 0.5)
    if w ~= r.W then r.W = w r.FillBox:SetWidthOverride(w) end
end

function M.Forget(sameWorld)
    -- as RuneMap: off the screen only in the same world; after a world change the engine has taken it away
    if sameWorld and M.UW then pcall(function() M.UW:RemoveFromParent() end) end
    M.W, M.UW, M.Rows, M.Visible = nil, nil, nil, false
    M.List, M.Seen, M.Hits, M.NextRead, M.Fails, Logged = {}, {}, 0, 0, 0, {}
end
M.Forget(false)

function M.Tick(ctx)
    local now = os.clock()
    if now < (M.Next or 0) then return end
    M.Next = now + EVERY
    local on = ctx.On()
    if on and now >= M.NextRead then
        local ok, err = pcall(function() M.List = Friends(ctx) end)
        if ok then
            Track(M.List)
            if #M.List > 0 then Once(ctx, "first", "party panel: " .. #M.List .. " friend(s) in the world") end
        else
            M.List = {}
            Once(ctx, "look", "party panel not read: " .. tostring(err))
        end
        M.NextRead = now + (#M.List > 0 and EVERY or ALONE)
    end
    local list = on and M.List or {}
    if #list == 0 and ctx.Preview() then list = SAMPLE end
    if #list == 0 and not M.W then return end   -- alone: no widget is made
    if not (M.W and M.W:IsValid()) then
        if M.Fails >= 3 then return end
        local V = ctx.ById("vitals").Instances[1]
        if not (V and V:IsValid()) then return end   -- no world yet
        M.W = nil
        local ok, err = pcall(Build, ctx)
        if not ok then M.Fails = M.Fails + 1 ctx.Log("party panel failed: " .. tostring(err)) end
        return
    end
    for i, r in ipairs(M.Rows) do Show(r, list[i]) end
    -- with the game's HUD (menus, the big map); off the screen when empty
    local V = ctx.ById("vitals").Instances[1]
    local visible = (V and V:IsValid() and V:IsVisible() and #list > 0) and true or false
    if visible ~= M.Visible then
        M.Visible = visible
        M.UW:SetVisibility(visible and 3 or 1)
    end
end

return M
