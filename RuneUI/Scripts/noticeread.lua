-- The read-only step of the notices: it logs what the shown warning looks like and writes nothing. noticestyle.lua
-- holds the writes; Install adds this step to it (S.Measure), and noticelook.lua calls Install before it builds its
-- recipes. main.lua loads this file with pcall: without it the step is left out.
-- A native read of a missing object is a crash that pcall cannot catch. So every object that came from a property
-- (the parent, a ring's icon, a brush's picture) is checked with IsValid before any call on it.

local M = {}

local Source, SrcKey   -- from noticestyle.lua, set by Install

local function Ok(w) return w and w:IsValid() end
local function Num(v) return type(v) == "number" and string.format("%.1f", v) or "?" end
local function TexName(t) return Ok(t) and t:GetFullName() or "none" end

-- the HUD rings' glyph textures, by index (a ring that did not build leaves a hole)
local function Rings(env)
    local rings, order, list = env.Hud and env.Hud() or {}, {}, {}
    for i in pairs(rings) do order[#order + 1] = i end
    table.sort(order)
    for _, i in ipairs(order) do
        local icon = rings[i].GameIcon
        list[#list + 1] = i .. " " .. (rings[i].Name or "?") .. " " .. (Ok(icon) and TexName(icon.Brush.ResourceObject) or "none")
    end
    return list
end

-- Logs, once for each warning entry, what the shown warning looks like: the band's brush size, what the band and its
-- Overlay want, and the glyph in the ring of this same warning (kept by S.Remember("Glyph", true)) next to the glyphs of
-- the HUD's own rings. A collapsed notice wants no size, so the check waits until the Overlay wants a positive width. It
-- returns true (done, noticelook.lua takes it out) after the line, or after one line that says the read failed.
local function Measure(env, W, info)
    local glyphKey, entry = SrcKey(env, "Glyph", true), env.Entry:GetFullName()
    return true, function()
        local ok, msg = pcall(function()
            local parent = W:GetParent()
            if not Ok(parent) then return end
            local box = parent:GetDesiredSize()
            if not (type(box.X) == "number" and box.X > 0) then return end
            local band, brush, ours = W:GetDesiredSize(), W.Brush, Source(env, glyphKey)
            local hud = Rings(env)
            return string.format("noticelook: %s shown: the band's brush %s x %s, it wants %s x %s, its Overlay wants %s x %s; the ring's glyph %s; the HUD rings' glyphs: %s",
                info.Name, Num(brush.ImageSize.X), Num(brush.ImageSize.Y), Num(band.X), Num(band.Y), Num(box.X), Num(box.Y),
                ours and TexName(ours.Brush.ResourceObject) or "not found", #hud > 0 and table.concat(hud, ", ") or "none built")
        end)
        if ok and not msg then return end
        env.Once("measure" .. entry, ok and msg or "noticelook: the warning could not be measured: " .. tostring(msg))
        return true
    end
end

function M.Install(S)
    Source, SrcKey = S.Source, S.SrcKey
    S.Measure = Measure
end

return M
