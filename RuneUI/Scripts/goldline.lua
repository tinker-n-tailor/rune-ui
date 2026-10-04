-- The gold line of the loading screen, pointed at both ends: the bars' line (bars.lua), the XP bar (xp.lua) and the
-- top of the quest tracker (questtracker.lua) all draw it here.
-- The picture, 1048x34, is pointed at its right end only: two copies, each squeezed into half of the box, in a
-- HorizontalBox, the left one mirrored, make a line pointed at both ends.
-- The picture has no glow in its first third, at the blunt end. With the whole picture, a thick line (a level up in
-- xp.lua) had its glow cut out in the middle, where the two blunt ends meet (in game, 04-10-2026). So each half draws
-- the picture from CUT on.

local M = {}

M.PATH = "/Game/Art/UI/Loading/T_Trim_Line_Gold.T_Trim_Line_Gold"
local CUT = 0.34   -- the share of the picture's width with no glow, measured on a screenshot

-- The row of the two halves; the caller puts it in a box of the size it wants. make(class, name) makes a UMG widget of
-- that class ("HorizontalBox", "Image") in the caller's tree. The row is named name .. "Row", the halves name.
function M.Row(make, tex, name)
    local row = make("HorizontalBox", name .. "Row")
    for half = 1, 2 do
        local img = make("Image", name)
        img:SetBrushFromTexture(tex, false)
        local b = img.Brush
        local uv = b.UVRegion
        uv.Min.X, uv.Min.Y, uv.Max.X, uv.Max.Y, uv.bIsValid = CUT, 0, 1, 1, 1
        if half == 1 then b.Mirroring = 1 end   -- the left half points left
        img:SetBrush(b)
        row:AddChildToHorizontalBox(img):SetSize({ SizeRule = 1, Value = 1 })   -- each half fills half the box
    end
    return row
end

return M
