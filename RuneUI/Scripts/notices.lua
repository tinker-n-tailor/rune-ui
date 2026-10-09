-- The preview of the notices in the editor (probes N1 and N2, 05-10-2026): while F9 is open and a row of a notice
-- is selected, the game's notice of that row shows at its place, so the player sees what the row moves. The game
-- keeps one entry ("Item") for each notice queue, made at the start of a world and collapsed at rest, so this file
-- makes nothing: it shows the entry that is there, with the content it kept or a sample text, and writes the old
-- values back when another row is selected or the editor closes. An entry that is not collapsed is a real notice
-- playing: it is not touched. The big notices share one entry (WBP_PrimaryNotificationQueue_Item_C) with a page for
-- each kind of notice, and its WidgetSwitcher picks the page. The "banners" row goes through its pages, one every
-- CYCLE seconds. This file never writes the render opacity of a banner widget: apply.lua does it for the editor.
-- main.lua loads this file with pcall, so an error here leaves the rest running.

local M = {}

local PRIMARY = "WBP_PrimaryNotificationQueue_Item_C"
local COLLAPSED, SHOWN = 1, 4   -- ESlateVisibility
local CYCLE = 2                 -- seconds a page of the "banners" row stays
local AGAIN = 1                 -- seconds between two looks for an entry of the row that does not show yet

-- What each row shows: a list of entries. Item is the class of the entry; Page and Pages are names of children of
-- the entry's switcher; Texts is name of a text of the entry -> sample text. Hide: parts of the entry that are
-- collapsed while it shows (the tip keeps the key line of the game's last tip, "View In Map", seen 09-10-2026). Colour: the entry's own colour has
-- alpha 0 at rest, so it is set to 1. Home: the entry rests pushed aside by its render translation, so it is set to 0.
-- Of the entries of one class (the pick-ups have five) the first collapsed one shows. A pick-up row shows without
-- its dark band: pickups.lua takes the band away, and the preview shows the row as it is in play.
local SHOW = {
    upkeep  = { { Item = "WBP_PlayerUpkeepNotification_Item_C" } },
    tips    = { { Item = "WBP_TutorialNotifications_Item_C", Hide = { "InputEntryWidget" },
                  Texts = { TitleTextBlock = "Tutorial tip", BodyTextBlock = "A tip of the game shows here." } } },
    itembrk = { { Item = "WBP_Notification_ItemBreak_Item_C", Texts = { BrokenTextBlock = "Bronze Pickaxe broke!" } } },
    quests  = { { Item = "WBP_QuestAndUnlocks_Item_C" } },
    status  = { { Item = "WBP_EnvAndPlayerStatus_Item_C", Colour = true } },
    pickups = { { Item = "WBP_ItemPickups_Item_C", Home = true, Texts = { ItemText = "Bronze Pickaxe", ItemCountText = "x1" } } },
    levelup = { { Item = PRIMARY, Page = "LevelUpNotificationItem" } },
    area    = { { Item = PRIMARY, Page = "AchievementNotificationItem" } },
    banners = { { Item = PRIMARY, Pages = { "NewSkillNotificationItem", "MilestoneMaterialNotificationItem",
        "FishCaughtNotificationItem", "ArenaNotificationItem", "LevelUpVendorNotificationItem",
        "FinalBossExtractionPointUnlockNotificationItem", "FinalBossDefeatedNotificationItem" } } },
}
-- the group row: all queues at once, built from the single rows
SHOW.notify = {}
for _, id in ipairs({ "upkeep", "tips", "itembrk", "quests", "levelup", "status", "pickups" }) do
    for _, shot in ipairs(SHOW[id]) do SHOW.notify[#SHOW.notify + 1] = shot end
end

M.Id = nil      -- the row shown now
M.Shown = {}    -- what was written, with the old values: { Shot, Item, Vis, Opacity, Colour, Home, Switcher, Index, Texts, Pages, At, Next }

local function Ok(w) return w and w:IsValid() end

local function Try(what, fn)
    local ok, err = pcall(fn)
    if not ok and not M.Logged and M.Log then M.Logged = true M.Log("notices: " .. what .. ": " .. tostring(err)) end
    return ok
end

-- the index of each named child of a switcher; a name that is not there is left out
local function PageIndexes(sw, names)
    local at, found = {}, {}
    for i = 0, sw:GetChildrenCount() - 1 do
        local c = sw:GetChildAt(i)
        if Ok(c) then at[c:GetFName():ToString()] = i end
    end
    for _, name in ipairs(names) do
        if at[name] then found[#found + 1] = at[name] end
    end
    return found
end

-- remember the old values of one entry in the list into, then show it
local function Show(shot, item, into)
    local e = { Shot = shot, Item = item, Texts = {}, Hidden = {} }
    e.Vis, e.Opacity = item:GetVisibility(), item:GetRenderOpacity()
    local names = shot.Pages or (shot.Page and { shot.Page })
    if names then
        local tree = item.WidgetTree
        local sw = Ok(tree) and tree.RootWidget
        if not Ok(sw) then error("no switcher in " .. shot.Item) end
        e.Switcher, e.Index, e.Pages = sw, sw:GetActiveWidgetIndex(), PageIndexes(sw, names)
        if #e.Pages == 0 then error("no page of " .. table.concat(names, ", ")) end
        e.At, e.Next = 1, os.clock() + CYCLE
    end
    for name, text in pairs(shot.Texts or {}) do
        local w = item[name]
        if Ok(w) then e.Texts[#e.Texts + 1] = { W = w, Was = w:GetText():ToString(), Text = text } end
    end
    for _, name in ipairs(shot.Hide or {}) do
        local w = item[name]
        if Ok(w) then e.Hidden[#e.Hidden + 1] = { W = w, Was = w:GetVisibility() } end
    end
    if shot.Colour then
        local c = item.ColorAndOpacity
        e.Colour = { R = c.R, G = c.G, B = c.B, A = c.A }
    end
    if shot.Home then
        local t = item.RenderTransform.Translation
        e.Home = { X = t.X, Y = t.Y }
    end
    into[#into + 1] = e   -- remembered before the first write, so a failed write is still undone
    item:SetVisibility(SHOWN)
    item:SetRenderOpacity(1.0)
    if e.Pages then e.Switcher:SetActiveWidgetIndex(e.Pages[1]) end
    for _, t in ipairs(e.Texts) do t.W:SetText(FText(t.Text)) end
    for _, h in ipairs(e.Hidden) do h.W:SetVisibility(COLLAPSED) end
    if e.Colour then item:SetColorAndOpacity({ R = e.Colour.R, G = e.Colour.G, B = e.Colour.B, A = 1.0 }) end
    if e.Home then item:SetRenderTranslation({ X = 0, Y = 0 }) end
end

-- Shows the first collapsed entry of a shot and remembers it in the list into; with none collapsed, nothing shows.
-- hint.lua calls this too, with a list of its own.
local function Open(ctx, shot, into)
    M.Log = ctx.Log
    Try("find " .. shot.Item, function()
        for _, item in ipairs((ctx.Find(shot.Item))) do
            -- a notice that plays is not collapsed, and it is not ours
            if Ok(item) and item:GetVisibility() == COLLAPSED then
                Try("show " .. shot.Item, function() Show(shot, item, into) end)
                return
            end
        end
    end)
end

-- An entry of the row that does not show yet is looked for again every AGAIN seconds: the first answer of ctx.Find
-- for a class can be empty (finder.lua keeps a class only after it was asked for), and an entry that a real notice
-- used is collapsed again when that notice ends.
local function ShowRow(ctx, id)
    M.Again = os.clock() + AGAIN
    local on = {}
    for _, e in ipairs(M.Shown) do on[e.Shot] = true end
    for _, shot in ipairs(SHOW[id] or {}) do
        if not on[shot] then Open(ctx, shot, M.Shown) end
    end
end

-- the entry is still as this file left it; another visibility means that the game took it for a real notice
local function Ours(e) return Ok(e.Item) and e.Item:GetVisibility() == SHOWN end

-- every write behind its own check and its own pcall, so one dead widget does not block the rest. An entry that
-- the game took is left as the game has it.
local function Undo(e)
    local okO, ours = pcall(Ours, e)
    if not (okO and ours) then return end
    Try("hide", function() e.Item:SetVisibility(e.Vis) end)
    Try("hide", function() e.Item:SetRenderOpacity(e.Opacity) end)
    if e.Switcher then
        Try("hide", function() if Ok(e.Switcher) then e.Switcher:SetActiveWidgetIndex(e.Index) end end)
    end
    for _, t in ipairs(e.Texts) do
        Try("hide", function() if Ok(t.W) then t.W:SetText(FText(t.Was)) end end)
    end
    for _, h in ipairs(e.Hidden) do
        Try("hide", function() if Ok(h.W) then h.W:SetVisibility(h.Was) end end)
    end
    if e.Colour then Try("hide", function() e.Item:SetColorAndOpacity(e.Colour) end) end
    if e.Home then Try("hide", function() e.Item:SetRenderTranslation(e.Home) end) end
end

-- puts back what Open wrote into a list
local function Close(list)
    for _, e in ipairs(list) do Undo(e) end
end

local function Restore()
    Close(M.Shown)
    M.Shown = {}
end

M.Open, M.Close = Open, Close
M.TipItem, M.TipHide = SHOW.tips[1].Item, SHOW.tips[1].Hide   -- the game's tutorial tip, which hint.lua shows too

-- a respawn keeps the widgets: put everything back. A new world: its widgets are gone, so no call on them
function M.Forget(sameWorld)
    if sameWorld then Restore() else M.Logged = nil end
    M.Shown, M.Id = {}, nil
end

function M.Tick(ctx)
    local sel = ctx.Selected()
    if sel == nil and M.Id == nil then return end
    M.Log = ctx.Log
    if sel ~= M.Id then
        Restore()
        M.Id = sel
        if sel ~= nil then ShowRow(ctx, sel) end
        return
    end
    local now = os.clock()
    for i = #M.Shown, 1, -1 do
        local e = M.Shown[i]
        local okO, ours = pcall(Ours, e)
        if not (okO and ours) then
            table.remove(M.Shown, i)   -- gone, or the game's now: forgotten without a call
        elseif e.Pages and #e.Pages > 1 and now >= e.Next then
            e.At, e.Next = e.At % #e.Pages + 1, now + CYCLE
            Try("page", function() if Ok(e.Switcher) then e.Switcher:SetActiveWidgetIndex(e.Pages[e.At]) end end)
        end
    end
    if now >= (M.Again or 0) then ShowRow(ctx, sel) end
end

return M
