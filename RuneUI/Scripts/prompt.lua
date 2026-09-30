-- The pick-up prompt ("Cabbage / Collect [E]") in gold letters, nothing else (Ivan, 30-09-2026: "just golden
-- letters", after a see-through tile was tried in game and dropped). main.lua moves it as "prompts".
-- What the prompt holds (probe, 30-09-2026): one WBP_HUD_InteractionPrompt_C for the whole game, kept and refilled.
-- CanvasPanel_0 > VerticalBox_0 with InventoryStateTextBlock (red, left red), HorizontalBox_0 (ItemNameTextBlock,
-- ItemAdditionalDescriptionTextBlock "(Dropped by Filch)", SkillRequirementSection), PromptInput and
-- SecondaryPromptInput (each a LabelRichText "Collect" and the game's key icon, which stays).
-- main.lua loads this file with pcall, so an error here leaves the rest of the mod running.

local M = {}

local function Lin1(c) if c <= 0.04045 then return c / 12.92 end return ((c + 0.055) / 1.055) ^ 2.4 end
local function Lin(r, g, b) return { R = Lin1(r), G = Lin1(g), B = Lin1(b), A = 1.0 } end
local GOLD = Lin(0.89, 0.722, 0.38)   -- #e3b861, aim.lua's gold
local TEXTS = { "ItemNameTextBlock", "ItemAdditionalDescriptionTextBlock" }
local INPUTS = { "PromptInput", "SecondaryPromptInput" }

M.Host, M.Texts, M.Said = nil, {}, nil

local function Build(ctx, W)
    M.Texts = {}
    for _, n in ipairs(TEXTS) do M.Texts[#M.Texts + 1] = ctx.Find(W, n) end
    -- the action words are rich text: one per input row
    for _, n in ipairs(INPUTS) do
        local row = ctx.Find(W, n)
        local label = row and ctx.Find(row, "LabelRichText")
        if label then M.Texts[#M.Texts + 1] = label end
    end
    M.Said = nil
    ctx.Log("prompt: " .. #M.Texts .. " texts in gold")
end

local function IsGold(c) return math.abs(c.R - GOLD.R) < 0.01 and math.abs(c.G - GOLD.G) < 0.01 and math.abs(c.B - GOLD.B) < 0.01 end

-- the game sets its words white again when it refills the prompt: gold again, keeping the game's alpha
local function Paint(T)
    if T:GetClass():GetFName():ToString() == "DomRichTextBlock" then
        T:SetDefaultColorAndOpacity({ SpecifiedColor = GOLD, ColorUseRule = 0 })
        return
    end
    local c = T.ColorAndOpacity.SpecifiedColor
    if not IsGold(c) then
        T:SetColorAndOpacity({ SpecifiedColor = { R = GOLD.R, G = GOLD.G, B = GOLD.B, A = c.A }, ColorUseRule = 0 })
    end
end

function M.Forget() M.Host, M.Texts, M.Said = nil, {}, nil end

function M.Tick(ctx)
    if os.clock() < (M.Next or 0) then return end
    M.Next = os.clock() + 0.1
    local list, names = ctx.Prompts()
    local W = list[1]
    if not (W and W:IsValid()) then return end
    if names[1] ~= M.Host then
        M.Host = names[1]
        local ok, err = pcall(Build, ctx, W)
        if not ok then M.Texts = {} ctx.Log("prompt: not found: " .. tostring(err)) end
    end
    -- gold again when the game refills the prompt (a new thing in front of the player), not on every step
    local words = {}
    for _, T in ipairs(M.Texts) do
        local ok, s = pcall(function() return T:GetText():ToString() end)
        words[#words + 1] = ok and s or ""
    end
    local said = table.concat(words, "|")
    -- the next cabbage in a row: the same words, written white again (review, 30-09-2026). One colour read a step.
    local first = M.Texts[1]
    if first and first:IsValid() then
        local ok, c = pcall(function() return first.ColorAndOpacity.SpecifiedColor end)
        if ok and c and not IsGold(c) then M.Said = nil end
    end
    if said ~= M.Said then
        M.Said = said
        for _, T in ipairs(M.Texts) do if T:IsValid() then pcall(Paint, T) end end
    end
end

return M
