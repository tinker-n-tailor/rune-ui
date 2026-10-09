-- The hint about F9 for a new player: the game's own tutorial tip shows "Rune UI / Press F9 to move, resize and hide the
-- HUD" once, in the first world after a fresh install. notices.lua does the showing and the putting back, as it does for
-- the preview of the editor. The one-time flag is general.f9hint in runeui.txt (profiles.lua): 0 until the hint shows,
-- then 1. It is not part of a layout profile. Opening the editor means that the player knows, so it ends the hint and
-- sets the flag. main.lua loads this file with pcall, so an error here leaves the rest running.

local M = {}

local HUD_WAIT = 8      -- seconds after the HUD is up, so the hint stays clear of the game's own first notices
local AGAIN = 2         -- seconds between two tries while the tip's entry is busy or not found yet
local LENGTH = 10       -- seconds the hint stays

M.List = nil    -- what notices.lua wrote while the hint shows, with the old values
M.Close = nil   -- notices.lua's Close, kept for Forget, which gets no ctx
M.Until = 0     -- when the hint ends (os.clock)
M.At = nil      -- when the next try is due; nil until the HUD is up

local function End()
    M.Close(M.List)
    M.List, M.At = nil, nil
end

-- A step that costs nothing once the flag is 1 and no hint is on show: no engine call, no new table.
function M.Tick(ctx)
    local general = ctx.General
    if not M.List and general.f9hint ~= 0 then return end
    local now = os.clock()
    if M.List then
        if now >= M.Until or ctx.Editing() then End() end
        return
    end
    if ctx.Editing() then general.f9hint = 1 ctx.Save() return end   -- the player knows the key already
    if not M.At then
        if not ctx.HudUp() then return end
        M.At = now + HUD_WAIT
    end
    if now < M.At then return end
    M.At = now + AGAIN
    local list = {}
    ctx.Notices.Open(ctx, { Item = ctx.Notices.TipItem, Hide = ctx.Notices.TipHide, Texts = { TitleTextBlock = "Rune UI",
        BodyTextBlock = "Press " .. ctx.Key.editor .. " to move, resize and hide the HUD" } }, list)
    if #list == 0 then return end
    M.List, M.Close, M.Until = list, ctx.Notices.Close, now + LENGTH
    general.f9hint = 1   -- saved at once: a game that closes with the hint on show does not show it again
    ctx.Save()
end

-- A respawn keeps the widgets: put the tip back. A new world: its widgets are gone, so no call on them. A hint that
-- has not shown yet waits for the next world.
function M.Forget(sameWorld)
    if M.List and sameWorld then M.Close(M.List) end
    M.List, M.At = nil, nil
end

return M
