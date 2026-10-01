-- Readable letters (picked live in the game, 01-10-2026): white words with a shadow on the letters in the
-- pick-up prompt, the build panel and the repair mode. Gold read worse than white over bright grass, and the letter
-- shadow beat every background tried (dark stripes, the game's tapered shadow, a soft oval). So the build title also
-- loses the game's faint tapered shadow (NameBorder, M_UI_TapperedBg).
-- Each panel is one widget for the whole game, refilled by the game (probes of 30-09 and 01-10-2026). Every text gets
-- the shadow, the key letters (KeyText) not. Only the panel's own words turn white: the red "inventory full" and the
-- cost rows keep the game's colours, they mean something.
-- main.lua moves the prompt as "prompts" and loads this file with pcall, so an error here leaves the rest running.

local M = {}

local HOSTS = { "WBP_HUD_InteractionPrompt_C", "WBP_Building_WorldTooltip_C", "WBP_ReticleRepair_C" }
local WHITE = { TooltipTitle = true, InputDescription = true, GenericBuildModeText = true, CycleSnappingText = true, RepairModeText = true }
local OFFSET, SHADE = { X = 1.5, Y = 1.5 }, { R = 0, G = 0, B = 0, A = 0.85 }
local REWALK = 5   -- seconds: rows the game adds to a panel later get the shadow within this

M.Hosts = {}   -- class -> { Key (full name), Texts = { { W, Rich, Name } }, Next (the next walk) }

-- the game's text kinds: TextBlock, DomTextBlock, WBP_DomTextBlock_C, DomRichTextBlock (not the rows that hold one)
local function IsText(c) return string.find(c, "TextBlock$") or string.find(c, "TextBlock_C$") end

-- every text under W, through the trees of the game's own widgets; the tapered shadow behind the title goes on the way
local function Collect(W, out, depth)
    if depth > 24 or not (W and W:IsValid()) then return end
    local c, n = W:GetClass():GetFName():ToString(), W:GetFName():ToString()
    if IsText(c) then
        if n ~= "KeyText" then out[#out + 1] = { W = W, Rich = c == "DomRichTextBlock", Name = n } end
        return
    end
    if n == "NameBorder" then pcall(function() W:SetBrushColor({ R = 1, G = 1, B = 1, A = 0 }) end) end
    if string.find(c, "^WBP_") then pcall(function() Collect(W.WidgetTree.RootWidget, out, depth + 1) end) return end
    local ok, cnt = pcall(function() return W:GetChildrenCount() end)
    if ok and cnt then for i = 0, cnt - 1 do Collect(W:GetChildAt(i), out, depth + 1) end
    else pcall(function() Collect(W:GetContent(), out, depth + 1) end) end
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

-- white again when the game wrote its own colour, the game's alpha kept
local function White(t)
    local c = t.W.ColorAndOpacity.SpecifiedColor
    if c.R < 0.99 or c.G < 0.99 or c.B < 0.99 then
        t.W:SetColorAndOpacity({ SpecifiedColor = { R = 1, G = 1, B = 1, A = c.A }, ColorUseRule = 0 })
    end
end

local function Walk(ctx, H, W)
    H.Texts = {}
    Collect(W.WidgetTree.RootWidget, H.Texts, 1)
    local bad = 0
    for _, t in ipairs(H.Texts) do if not pcall(Shadow, t) then bad = bad + 1 end end
    if not H.Logged then
        H.Logged = true
        ctx.Log("letters: " .. #H.Texts .. " texts with a shadow in " .. H.Class .. (bad > 0 and (", " .. bad .. " without the setting") or ""))
    end
end

function M.Forget() M.Hosts = {} end

function M.Tick(ctx)
    local now = os.clock()
    if now < (M.Next or 0) then return end
    M.Next = now + 0.5
    for i, class in ipairs(HOSTS) do
        local list, keys = ctx.Find(class)
        local W = list[1]
        if W and W:IsValid() then
            local H = M.Hosts[class]
            if not H or H.Key ~= keys[1] then
                H = { Class = class, Key = keys[1], Texts = {}, Next = 0 }
                M.Hosts[class] = H
            end
            if now >= H.Next then
                H.Next = now + REWALK + i * 0.5   -- the three walks fall on different steps
                local ok, err = pcall(Walk, ctx, H, W)
                if not ok then ctx.Log("letters: " .. class .. " not read: " .. tostring(err)) end
            end
            for _, t in ipairs(H.Texts) do
                if WHITE[t.Name] and t.W:IsValid() then pcall(White, t) end
            end
        end
    end
end

return M
