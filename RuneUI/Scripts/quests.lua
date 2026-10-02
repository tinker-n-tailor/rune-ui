-- The quests and unlocks (1.5; playtest, 02-10-2026): the game's panel at the right edge, as the game made it, in
-- the HUD's font with the letters' shadow (letters.lua), as the item pick-ups. A mirror of the panel for the left
-- edge was tried and dropped: the game made the panel for the right edge, and after four fixes the mirror still cost
-- the game's slide-in and sparks. The editor moves the panel only up and down (OnlyY in main.lua).
-- The entry (WBP_QuestAndUnlocks_Item_C) is made once in a world and filled again for each notice. A row
-- (WBP_QuestAndUnlocks_Item_Slot_C) is made new for each notice, from its master copy: the master copy's text gets
-- the font, so a new row has it from the start. Every 5 s, every text under the panel is also styled, once each, so
-- the entry, its key rows and anything the master copy missed get it too: the walk of letters.lua (ctx.Collect),
-- which leaves out the key letters (KeyText).
-- main.lua moves the panel as "quests" and loads this file with pcall, so an error here leaves the rest running.

local M = {}

local ROWTEXT = "/Game/UI/Notifications/QuestAndUnlocks/WBP_QuestAndUnlocks_Item_Slot.WBP_QuestAndUnlocks_Item_Slot_C:WidgetTree.SlotText"
local OFFSET, SHADE = { X = 1.5, Y = 1.5 }, { R = 0, G = 0, B = 0, A = 0.85 }   -- as letters.lua
local EVERY = 0.5   -- seconds between two looks for the master copy
local REWALK = 5    -- seconds between two walks of the panel (as letters.lua)

M.Done = {}   -- full name of a text already styled -> true (an address can come back for a new object)

local function Ok(w) return w and w:IsValid() end

-- the HUD font and the shadow on one text, its size kept; rich text has its own setters, and its font is in the
-- override only while the override is on
local function Style(W, rich, font)
    if rich then
        local fi = (W.bOverrideDefaultStyle and W.DefaultTextStyleOverride or W.DefaultTextStyle).Font
        fi.FontObject = font
        W:SetDefaultFont(fi)
        W:SetDefaultShadowOffset(OFFSET)
        W:SetDefaultShadowColorAndOpacity(SHADE)
    else
        local fi = W.Font
        fi.FontObject = font
        W:SetFont(fi)
        W:SetShadowOffset(OFFSET)
        W:SetShadowColorAndOpacity(SHADE)
    end
end

-- a new world: everything is styled again, and its first error is logged again
function M.Forget() M.Done, M.Master, M.Logged, M.Walk = {}, nil, nil, nil end

function M.Tick(ctx)
    local now = os.clock()
    if now < (M.Next or 0) then return end
    M.Next = now + EVERY
    local font = ctx.Font()
    if not font then return end
    if not M.Master then
        local T = StaticFindObject(ROWTEXT)
        if Ok(T) then
            local ok, err = pcall(Style, T, false, font)
            M.Master = true
            if not ok and not M.Logged then M.Logged = true ctx.Log("quests: the row's master copy not styled: " .. tostring(err)) end
        end
    end
    if not ctx.Collect or now < (M.Walk or 0) then return end
    M.Walk = now + REWALK
    for _, Q in ipairs((ctx.Find("WBP_QuestAndUnlocks_C"))) do
        local texts = {}
        pcall(ctx.Collect, Q.WidgetTree.RootWidget, texts, 1)
        for _, t in ipairs(texts) do
            local okA, a = pcall(function() return t.W:GetFullName() end)
            if okA and a and not M.Done[a] then
                M.Done[a] = true
                local ok, err = pcall(Style, t.W, t.Rich, font)
                if not ok and not M.Logged then M.Logged = true ctx.Log("quests: a text not styled: " .. tostring(err)) end
            end
        end
    end
end

return M
