-- The farm plots (1.5; picked live in the game, probes 58 to 60, 02-10-2026): the panel over each plot,
-- WBP_FarmPlot_InformationWidget_C. Its need icons (water, compost) are half their size. The clearing panel has no
-- dark band and no frame: a smaller title with the letters' shadow (letters.lua) over a brown fill on the game's
-- dark track. The game's fill was red with a gloss.
-- The panel (the game's files): VerticalBox > [TillingProgressAssembly (Overlay) > [TillingPanelBackground,
-- TillingTitle, TillingBarBackground, TillingBarBackgroundSurrounding, TillingBarOutline, TillingProgressBarContainer >
-- Overlay > [TillingBarProgress (a Border), TillingBarGradient]], NeedsAssembly (HorizontalBox) > [the water need,
-- the compost need]].
-- Each plot has its own panel, made when the plot loads, so a panel is styled once, by its full name.
-- main.lua loads this file with pcall, so an error here leaves the rest running.

local M = {}

local HIDE = { "TillingPanelBackground", "TillingBarBackgroundSurrounding", "TillingBarOutline", "TillingBarGradient" }
local BROWN = { R = 0.332, G = 0.147, B = 0.045, A = 1 }   -- #9c6b3c, as linear light
local OFFSET, SHADE = { X = 1.5, Y = 1.5 }, { R = 0, G = 0, B = 0, A = 0.85 }   -- as letters.lua
local EVERY = 0.5   -- seconds between two looks

M.Done = {}   -- full name -> true

local function Ok(w) return w and w:IsValid() end

-- every named widget of the panel, or an error that names the first one missing: nothing is written before all
-- are found
local function Style(W)
    local tree = W.WidgetTree:GetFullName():gsub("^%S+ ", "") .. "."
    local w = {}
    for _, n in ipairs({ "NeedsAssembly", "TillingBarProgress", "TillingTitle", table.unpack(HIDE) }) do
        w[n] = StaticFindObject(tree .. n)
        if not Ok(w[n]) then error(n .. " not found") end
    end
    w.NeedsAssembly:SetRenderScale({ X = 0.5, Y = 0.5 })
    for _, n in ipairs(HIDE) do w[n]:SetRenderOpacity(0.0) end
    w.TillingBarProgress:SetBrushColor(BROWN)
    w.TillingTitle:SetRenderScale({ X = 0.7, Y = 0.7 })
    w.TillingTitle:SetShadowOffset(OFFSET)
    w.TillingTitle:SetShadowColorAndOpacity(SHADE)
end

-- a new world loads the plots anew; its first error is logged again
function M.Forget() M.Done, M.Logged = {}, nil end

function M.Tick(ctx)
    local now = os.clock()
    if now < (M.Next or 0) then return end
    M.Next = now + EVERY
    local list, keys = ctx.Find("WBP_FarmPlot_InformationWidget_C")
    for i, W in ipairs(list) do
        local k = keys[i]
        if not M.Done[k] and Ok(W) then
            M.Done[k] = true
            local ok, err = pcall(Style, W)
            if not ok and not M.Logged then M.Logged = true ctx.Log("farm plots: panel not styled: " .. tostring(err)) end
        end
    end
end

return M
