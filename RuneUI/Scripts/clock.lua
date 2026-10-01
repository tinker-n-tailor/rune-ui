-- The time of day in immersive mode (playtest, 01-10-2026: "atleast some kind of indicator what time of the day is"):
-- one small icon right of the tool bar. Half a sun rising at dawn, the sun by day, half a sun setting at dusk, the
-- moon at night (design sketch, option 4). Shown only while immersive mode is on, and while the editor is open so
-- it can be moved; it is the "Time of day icon" line in F9. The time comes from the game's own dial (runemap.lua).
-- main.lua moves it like any element and loads this file with pcall.

local M = {}

local ART_DIR = "ue4ss/Mods/RuneUI/Art/"
M.SIZE = 40              -- the pictures' box in units: a sun of radius 9 with its rays and glow
local DAWN_END = 0.08    -- the sketch's phases of the game's day: 0 is dawn, night from the dial's night start
local DUSK_BEFORE = 0.08 -- dusk: this share of the day before night

local function Obj(path) return StaticFindObject(path) end
local function New(cls, outer, name) return StaticConstructObject(Obj("/Script/UMG." .. cls), outer, FName(name)) end

-- the phase for a share of the day gone, the night starting at ns
function M.Phase(fill, ns)
    if fill >= ns then return "night" end
    if fill < DAWN_END then return "dawn" end
    if fill >= ns - DUSK_BEFORE then return "dusk" end
    return "day"
end

local function Build(ctx)
    M.Builds = (M.Builds or 0) + 1   -- a new name on every build (see runemap.lua)
    local uw = New("UserWidget", FindFirstOf("GameInstance"), "RuneUIClock" .. M.Builds)
    local tree = New("WidgetTree", uw, "RuneUIClockTree")
    uw.WidgetTree = tree
    local canvas = New("CanvasPanel", tree, "RU_ClockCanvas")
    tree.RootWidget = canvas
    local size = New("SizeBox", tree, "RU_ClockSize")
    size:SetWidthOverride(M.SIZE)
    size:SetHeightOverride(M.SIZE)
    -- One Image per phase, one shown at a time. Each picture must sit in a widget: the first build kept three of
    -- the four only in Lua, the engine freed them, and Lua touching them later crashed the game about two minutes
    -- into a world (in game, 01-10-2026; the same lesson as 27-09-2026, see survival.lua).
    local stack = New("Overlay", tree, "RU_ClockStack")
    size:SetContent(stack)
    local KRL = Obj("/Script/Engine.Default__KismetRenderingLibrary")
    local imgs = {}
    for _, p in ipairs({ "dawn", "day", "dusk", "night" }) do
        local tex = KRL:ImportFileAsTexture2D(tree, ART_DIR .. "clock_" .. p .. ".png")
        if not (tex and tex:IsValid()) then error("picture clock_" .. p .. ".png not loaded") end
        local img = New("Image", tree, "RU_Clock_" .. p)
        img:SetBrushFromTexture(tex, false)
        img:SetVisibility(1)
        local s = stack:AddChildToOverlay(img)
        s:SetHorizontalAlignment(0) s:SetVerticalAlignment(0)
        imgs[p] = img
    end
    local E = ctx.ById("clock")
    local slot = canvas:AddChildToCanvas(size)
    slot:SetAutoSize(true)
    -- tied to the middle of the bottom edge, as the tool bar is on a wide screen; the spot is measured on a 16:9 screen
    slot:SetAnchors({ Minimum = { X = 0.5, Y = 1 }, Maximum = { X = 0.5, Y = 1 } })
    slot:SetPosition({ X = E.Center.X - 960 - M.SIZE / 2, Y = E.Center.Y - 1080 - M.SIZE / 2 })
    uw:AddToViewport(38)
    uw:SetVisibility(1)
    M.W, M.UW, M.Imgs, M.Shown, M.Phase_ = size, uw, imgs, false, nil
    ctx.Log("clock ready")
end

function M.Forget(sameWorld)
    -- as RuneMap: off the screen only in the same world; after a world change the engine has taken it away
    if sameWorld and M.UW then pcall(function() M.UW:RemoveFromParent() end) end
    M.W, M.UW, M.Imgs, M.Shown, M.Phase_, M.Fails, M.Said = nil, nil, nil, false, nil, 0, nil
end
M.Forget(false)

function M.Tick(ctx)
    if os.clock() < (M.Next or 0) then return end
    M.Next = os.clock() + 1   -- the day turns slowly: once a second is plenty
    if not (M.W and M.W:IsValid()) then
        if M.Fails >= 3 then return end
        local V = ctx.ById("vitals").Instances[1]
        if not (V and V:IsValid()) then return end   -- no world yet
        M.W = nil
        local ok, err = pcall(Build, ctx)
        if not ok then M.Fails = M.Fails + 1 ctx.Log("clock failed: " .. tostring(err)) end
        return
    end
    local show = ctx.On() or ctx.Editing()
    if show then
        local ok, fill, ns = pcall(ctx.ReadClock)
        if ok and fill then
            local p = M.Phase(fill, ns)
            if p ~= M.Phase_ then
                if M.Phase_ then M.Imgs[M.Phase_]:SetVisibility(1) end
                M.Phase_ = p
                M.Imgs[p]:SetVisibility(3)
                ctx.Log("clock: " .. p)
            end
        else
            -- once a world: why the dial could not be read (the icon stayed away all night in game, 01-10-2026)
            if not M.Said then M.Said = true ctx.Log("clock: no time read: " .. tostring(ok and "no dial" or fill)) end
            if not M.Phase_ then show = false end   -- no time read yet: nothing to show
        end
    end
    if show ~= M.Shown then
        M.Shown = show
        M.UW:SetVisibility(show and 3 or 1)
    end
end

return M
