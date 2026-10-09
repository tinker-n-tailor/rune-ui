-- Readable letters: white words with a shadow on the letters in the pick-up prompt, the build panel and the repair
-- mode. White, not gold: gold reads worse over bright grass. The build title also loses the game's faint tapered
-- shadow (NameBorder, M_UI_TapperedBg).
-- Each panel is one widget for the whole game, refilled by the game (probes of 30-09 and 01-10-2026). Every text gets
-- the shadow, the key letters (KeyText) not. Only the panel's own words turn white: the red "inventory full" and the
-- cost rows keep the game's colours, they mean something.
-- main.lua moves the prompt as "prompts" and loads this file with pcall, so an error here leaves the rest running.
-- Every read of a game object makes a wrapper that Lua frees later, so the file reads little: a walk over a panel's
-- tree (about 20 ms in one go, 7 MB of garbage a minute at one walk per 5 s, measured 08-10-2026) runs only when
-- the panel is new, shows again or has another count of children at its root, and it runs in small steps.

local M = {}

local HOSTS = { "WBP_HUD_InteractionPrompt_C", "WBP_Building_WorldTooltip_C", "WBP_ReticleRepair_C" }
local WHITE = { TooltipTitle = true, InputDescription = true, GenericBuildModeText = true, CycleSnappingText = true, RepairModeText = true }
local OFFSET, SHADE = { X = 1.5, Y = 1.5 }, { R = 0, G = 0, B = 0, A = 0.85 }
local CHECK = 0.5       -- seconds between two looks at a panel
local RESCAN = 30       -- seconds: a row that the game adds deep in a panel does not change the count at its root, so
                        -- the slowest way to find it is a new walk (and a new search for the widget) at this pace
local WHITE_EVERY = 1   -- seconds between two reads of the colours of the white words while the panel stands
local STEP_NODES = 25   -- widgets one step of the timer (50 ms) may read: a walk of a big panel takes a few steps
local MAX_DEPTH = 24

M.Hosts = {}   -- class -> { Key (full name), W, Root, Count (children of the root), Shown, Slow (the next search), WhiteAt,
               --            Texts = { { W, Rich, Name } }, Whites (the Texts that turn white), Walk (a walk in progress) }

-- the game's text kinds: TextBlock, DomTextBlock, WBP_DomTextBlock_C, DomRichTextBlock (not the rows that hold one)
local function IsText(c) return string.find(c, "TextBlock$") or string.find(c, "TextBlock_C$") end

-- one function for each read that can fail, so pcall gets no closure
local function RootOf(W) return W.WidgetTree.RootWidget end
local function ChildCount(W) return W:GetChildrenCount() end
local function ContentOf(W) return W:GetContent() end
local function ClearBrush(W) W:SetBrushColor({ R = 1, G = 1, B = 1, A = 0 }) end
local function IsShown(W) return W:IsVisible() end
local function CountOf(root)
    local ok, n = pcall(ChildCount, root)
    return ok and n or -1
end

-- the widgets still to read: a stack of widgets (W) and their depths (D)
local function NewStack() return { n = 0, W = {}, D = {} } end
local function Push(S, W, depth)
    if W then local n = S.n + 1 S.n, S.W[n], S.D[n] = n, W, depth end
end

-- read one widget: a text goes to out, the others give their children to the stack. The game's own widgets (WBP_)
-- have a tree of their own. The tapered shadow behind the title goes on the way. A name is read only for a text and
-- for a border, the kind NameBorder is.
local function Visit(W, depth, out, S)
    if depth > MAX_DEPTH or not W:IsValid() then return end
    local c = W:GetClass():GetFName():ToString()
    if IsText(c) then
        local n = W:GetFName():ToString()
        if n ~= "KeyText" then out[#out + 1] = { W = W, Rich = c == "DomRichTextBlock", Name = n } end
        return
    end
    if string.find(c, "Border$") and W:GetFName():ToString() == "NameBorder" then pcall(ClearBrush, W) end
    if string.find(c, "^WBP_") then
        local ok, root = pcall(RootOf, W)
        if ok then Push(S, root, depth + 1) end
        return
    end
    local ok, cnt = pcall(ChildCount, W)
    if ok and cnt then
        for i = 0, cnt - 1 do Push(S, W:GetChildAt(i), depth + 1) end
    else
        local okC, content = pcall(ContentOf, W)
        if okC then Push(S, content, depth + 1) end
    end
end

-- read up to budget widgets; returns how many were read
local function Drain(S, out, budget)
    local used = 0
    while S.n > 0 and used < budget do
        local n = S.n
        local W, d = S.W[n], S.D[n]
        S.W[n], S.D[n], S.n = nil, nil, n - 1
        Visit(W, d, out, S)
        used = used + 1
    end
    return used
end

-- every text under W, all at once (quests.lua walks its panel with it)
function M.Collect(W, out, depth)
    local S = NewStack()
    Push(S, W, depth)
    Drain(S, out, math.huge)
end

local function Shadow(t)
    if t.Rich then
        t.W:SetDefaultShadowOffset(OFFSET)
        t.W:SetDefaultShadowColorAndOpacity(SHADE)
    else
        t.W:SetShadowOffset(OFFSET)
        t.W:SetShadowColorAndOpacity(SHADE)
    end
end

-- white again when the game wrote its own colour, the game's alpha kept. The game writes the colour when it refills
-- the panel, so this is read when a walk starts and ends and once a WHITE_EVERY second, not at each look.
local function White(t)
    if not t.W:IsValid() then return end
    local c = t.W.ColorAndOpacity.SpecifiedColor
    if c.R < 0.99 or c.G < 0.99 or c.B < 0.99 then
        t.W:SetColorAndOpacity({ SpecifiedColor = { R = 1, G = 1, B = 1, A = c.A }, ColorUseRule = 0 })
    end
end

local function WhiteAll(H)
    for _, t in ipairs(H.Whites) do pcall(White, t) end
end

-- start a walk: it reads the panel's tree in steps (Advance); the old texts stay in use until it ends
local function Begin(H)
    local root = RootOf(H.W)
    H.Root, H.Count = root, CountOf(root)
    local S = NewStack()
    Push(S, root, 1)
    H.Walk = { S = S, Out = {}, Shaded = 0, Bad = 0 }
end

-- one step of a walk: read some widgets, give the new texts their shadow, and at the end swap the texts in
local function Advance(ctx, H, budget)
    local K = H.Walk
    local ok, used = pcall(Drain, K.S, K.Out, budget)
    if not ok then
        H.Walk = nil
        ctx.Log("letters: " .. H.Class .. " not read: " .. tostring(used))
        return budget
    end
    for i = K.Shaded + 1, #K.Out do
        if not pcall(Shadow, K.Out[i]) then K.Bad = K.Bad + 1 end
    end
    K.Shaded = #K.Out
    if K.S.n == 0 then
        H.Walk, H.Texts, H.Whites = nil, K.Out, {}
        for _, t in ipairs(K.Out) do if WHITE[t.Name] then H.Whites[#H.Whites + 1] = t end end
        WhiteAll(H)
        if not H.Logged then
            H.Logged = true
            ctx.Log("letters: " .. #K.Out .. " texts with a shadow in " .. H.Class .. (K.Bad > 0 and (", " .. K.Bad .. " without the setting") or ""))
        end
    end
    return used
end

function M.Forget() M.Hosts = {} end

-- one look at a panel. The widget search runs when no panel is held, when the held one is gone and at the slow
-- rescan; between those, the held handle is checked with IsValid. A walk starts for a new widget, for a panel that
-- shows again, for another count of children at its root, and at the slow rescan.
local function Check(ctx, class, now)
    local H = M.Hosts[class]
    if H and not H.W:IsValid() then H, M.Hosts[class] = nil, nil end
    local go = false
    if not H or now >= H.Slow then
        local list, keys = ctx.Find(class)
        local W = list[1]
        if not (W and W:IsValid()) then M.Hosts[class] = nil return end
        if not H or H.Key ~= keys[1] then
            H = { Class = class, Key = keys[1], Texts = {}, Whites = {}, Shown = false, WhiteAt = 0 }
            M.Hosts[class] = H
        end
        H.W, H.Slow, go = W, now + RESCAN, true
    end
    local ok, shown = pcall(IsShown, H.W)
    shown = ok and shown
    -- the root is a handle from a property: freed by the engine, it is not read, the panel is walked again
    if not go and H.Root and not H.Walk and (not H.Root:IsValid() or (shown and not H.Shown) or CountOf(H.Root) ~= H.Count) then go = true end
    H.Shown = shown
    if go and not H.Walk then
        local okB, err = pcall(Begin, H)
        if not okB then ctx.Log("letters: " .. class .. " not read: " .. tostring(err)) end
        H.WhiteAt = 0
    end
    if now >= H.WhiteAt then
        H.WhiteAt = now + WHITE_EVERY
        WhiteAll(H)
    end
end

function M.Tick(ctx)
    local now = os.clock()
    local left = STEP_NODES
    for _, class in ipairs(HOSTS) do
        local H = M.Hosts[class]
        if H and H.Walk and left > 0 then left = left - Advance(ctx, H, left) end
    end
    if now < (M.Next or 0) then return end
    M.Next = now + CHECK
    for _, class in ipairs(HOSTS) do Check(ctx, class, now) end
end

return M
