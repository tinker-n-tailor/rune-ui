-- The game's day and night dial as an icon of the mod: half a sun rising at dawn, the sun by day, half a sun setting at
-- dusk, the moon at night (tools/make-runemap-art.js). It sits in the dial's own widget, so the F9 row "Day and night
-- dial" moves, sizes and fades it. The game's two images (the ring and the pointer) stay alive but unseen: runemap.lua
-- reads the time from the ring's material. The Rune Skin row "Day and night icon" turns it off and gives them back.
-- main.lua loads this file with pcall, so an error here leaves the rest of the mod running.

local M = {}

local ART_DIR = (RUNEUI_DIR or "ue4ss/Mods/RuneUI/") .. "Art/"
local DIAL = 66                                      -- the game's dial is 66 units
local PHASES = { "dawn", "day", "dusk", "night" }
local DAWN_END, DUSK_BEFORE = 0.08, 0.08             -- the share of the day that is dawn, and the share before night that is dusk
local LOOK = 0.5                                     -- seconds between two looks at the clock
local HIDDEN, SEEN = 1, 3                            -- ESlateVisibility: collapsed, hit-test invisible

local function Obj(path) return StaticFindObject(path) end
local function New(cls, outer, name) return StaticConstructObject(Obj("/Script/UMG." .. cls), outer, FName(name)) end

-- The phase for the share fill of the day gone (0 is dawn), the night starting at ns
function M.Phase(fill, ns)
    if fill >= ns then return "night" end
    if fill < DAWN_END then return "dawn" end
    if fill >= ns - DUSK_BEFORE then return "dusk" end
    return "day"
end

-- B: our icon in the dial now (Host the dial's full name, Stack, Imgs by phase, Phase the one shown). Hid: the game's
-- two images are unseen by us, with the opacity each had (Host the dial's full name). Hid outlives B in a player
-- restart: the game's dial stays, and its images are still unseen.
local B, Hid = nil, nil

-- The game's ring and pointer in the root of the dial, nil unless both are there under their names (probe of 09-10-2026)
local function Game(root)
    local ring, pointer = root:GetChildAt(0), root:GetChildAt(1)
    if ring and ring:IsValid() and ring:GetFName():ToString() == "Image" and pointer and pointer:IsValid()
        and pointer:GetFName():ToString() == "CursorImage" then return ring, pointer end
end

local function Build(ctx, DN, name)
    local root = DN.WidgetTree.RootWidget
    local ring = Game(root)
    local from = ring and ring.Slot
    if not (from and from:IsValid()) then error("the dial's images or their slot are not as in the probe") end
    local tree, tex = DN.WidgetTree, {}
    -- One Image per phase, one shown at a time. Each picture sits in an Image of its own: a texture that only Lua holds is
    -- freed by the engine, and the game crashed when Lua touched it later (the first clock, 01-10-2026; see survival.lua).
    local stack = New("Overlay", tree, ctx.Uniq("RU_DialStack"))
    local imgs = {}
    for _, p in ipairs(PHASES) do
        local img = New("Image", tree, ctx.Uniq("RU_Dial_" .. p))
        img:SetBrushFromTexture(ctx.CachedTex(tex, p, tree, ART_DIR .. "clock_" .. p .. ".png"), false)
        local b = img.Brush
        b.ImageSize = { X = DIAL, Y = DIAL }
        img:SetBrush(b)
        img:SetVisibility(HIDDEN)
        local s = stack:AddChildToOverlay(img)
        s:SetHorizontalAlignment(0) s:SetVerticalAlignment(0)   -- fill
        imgs[p] = img
    end
    -- ours from an earlier round (a player restart keeps the game's widget): out first
    ctx.ClearOurs(root, "RU_Dial")
    local slot = root:AddChildToCanvas(stack)
    slot:SetLayout(from.LayoutData)   -- the place and size of the game's ring
    slot:SetAutoSize(from.bAutoSize)
    B = { Host = name, Stack = stack, Imgs = imgs, Phase = nil }
    ctx.Log("dial: icon ready")
end

-- The game's images unseen, once ours shows. Their opacity is read first and kept for the way back.
local function HideGame(DN, name)
    local ring, pointer = Game(DN.WidgetTree.RootWidget)
    if not ring then return end
    Hid = { Host = name, Ring = ring:GetRenderOpacity(), Pointer = pointer:GetRenderOpacity() }
    ring:SetRenderOpacity(0.0)
    pointer:SetRenderOpacity(0.0)
end

-- Our icon out, the game's images as they were
local function Back(ctx, DN, name)
    local H = Hid
    Hid, B = nil, nil
    local root = DN.WidgetTree.RootWidget
    ctx.ClearOurs(root, "RU_Dial")
    if not (H and H.Host == name) then return end   -- the game made the dial again: its images are fresh
    local ring, pointer = Game(root)
    if not ring then return end
    ring:SetRenderOpacity(H.Ring)
    pointer:SetRenderOpacity(H.Pointer)
end

local function Show(ctx, DN, name)
    if not B then
        if not ctx.MayTry(M) then return end
        local ok, err = pcall(Build, ctx, DN, name)
        if not ok then
            ctx.Failed(M)
            if M.Fails == 1 then ctx.Log("dial: icon not built: " .. tostring(err)) end
            return
        end
    end
    local ok, fill, ns = pcall(ctx.ReadClock, ctx)
    if not (ok and fill) then
        -- the game's dial stays as it is until a time is read
        if not M.Said then M.Said = true ctx.Log("dial: no time read: " .. tostring(ok and "no dial" or fill)) end
        return
    end
    local p = M.Phase(fill, ns)
    if p ~= B.Phase then   -- a write only when the phase changes
        if B.Phase then B.Imgs[B.Phase]:SetVisibility(HIDDEN) end
        B.Imgs[p]:SetVisibility(SEEN)
        B.Phase = p
    end
    if not (Hid and Hid.Host == name) then HideGame(DN, name) end
end

-- A new world drops the handles with no call; a player restart keeps what the game's images were set to
function M.Forget(sameWorld)
    B, M.Fails, M.RetryAt, M.Said, M.Next = nil, 0, 0, nil, 0
    if not sameWorld then Hid = nil end
end

function M.Tick(ctx)
    if os.clock() < (M.Next or 0) then return end
    M.Next = os.clock() + LOOK
    local on = ctx.On()
    if not on and not (Hid or B) then return end   -- Off, and nothing of ours in the dial: no call
    local E = ctx.ById("daynight")
    -- hidden in F9 with the editor closed: the layout keeps the whole dial unseen, so there is nothing to change or read
    if not (E.Visible or ctx.Editing()) then return end
    local DN = E.Instances[1]
    if not (DN and DN:IsValid()) then return end
    local name = E.Keys[1]
    if B and (name ~= B.Host or not B.Stack:IsValid()) then B = nil end   -- the game made the dial again
    if on then Show(ctx, DN, name) else Back(ctx, DN, name) end
end

return M
