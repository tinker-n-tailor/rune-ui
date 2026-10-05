-- The bars: a plain dark track behind each fill, one colour per bar, stamina green, health on top, no health
-- numbers, the game's shadow and icons hidden; and the gold line of the loading screen under the bars. main.lua loads
-- this file with pcall; its Scan runs once per widget scan.

local M = {}
-- main.lua's helpers, bound once by Init (see Util in main.lua)
local Log, ById, Uniq, G, ClearOurs, ClassName, FindClass, Asset, SetColor, MayTry, Failed, CachedTex, Survival, GoldLine
function M.Init(ctx)
    Log, ById, Uniq, G, ClearOurs, ClassName, FindClass = ctx.Log, ctx.ById, ctx.Uniq, ctx.G, ctx.ClearOurs, ctx.ClassName, ctx.FindClass
    Asset, SetColor = ctx.Asset, ctx.SetColor
    MayTry, Failed, CachedTex, Survival, GoldLine = ctx.MayTry, ctx.Failed, ctx.CachedTex, ctx.Survival, ctx.GoldLine
end

-- The gold line of the loading screen under the bars (seen live, 02-10-2026; before: the main menu's trim line,
-- read from the menu and saved), drawn by goldline.lua. It lives in the bars widget like the badge, so it moves and
-- sizes with the bars.
local BarTrim = { HostName = nil }
local function EnsureBarTrim()
    if not MayTry(BarTrim) then return end
    local VE = ById("vitals")
    local V = VE.Instances[1]
    if not (V and V:IsValid()) or BarTrim.HostName == VE.Keys[1] then return end
    local ok, err = pcall(function()
        local tex = Asset(GoldLine.PATH, "/Script/Engine.Texture2D")
        if not tex then error("line picture not loaded") end
        local row = GoldLine.Row(function(cls, name)
            return StaticConstructObject(StaticFindObject("/Script/UMG." .. cls), V.WidgetTree, G(name))
        end, tex, "RU_BarTrim")
        local box = StaticConstructObject(StaticFindObject("/Script/UMG.SizeBox"), V.WidgetTree, G("RU_BarTrimBox"))
        box:SetWidthOverride(330)   -- the bars' width
        box:SetHeightOverride(10.7)
        box:SetContent(row)
        ClearOurs(V.WidgetTree.RootWidget, "RU_BarTrimBox")
        local slot = V.WidgetTree.RootWidget:AddChildToOverlay(box)
        -- just under the bars' bottom edge. Centred and at the bottom like the bars and the badge (see
        -- EnsureAvatar), so it stays under the bars on a wide screen too. Right = 960 - 952; Bottom as seen live.
        slot:SetHorizontalAlignment(2)
        slot:SetVerticalAlignment(3)
        slot:SetPadding({ Left = 0, Top = 0, Right = 8, Bottom = 63.3 })
        BarTrim.HostName, BarTrim.W = VE.Keys[1], box   -- the immersive mode fades it with the bars
    end)
    if ok then Log("bar trim ready") BarTrim.Fails = 0 else Failed(BarTrim) Log("bar trim failed: " .. tostring(err)) end
end

-- The bars (design sketch without its diamonds, in-game review 27-09-2026): plain boxes: a dark track
-- behind each bar's fill and nothing else, stamina in green, health on top, and the icons beside
-- the bars hidden unless the editor shows them. The fill is the game's, in one colour (see OneColorFill).
-- The track is a picture drawn in nine pieces, one pixel to one unit, in place of the game's gold frame: its
-- outer pieces fit the frame's padding and stay empty, so the track sits right behind the fill. There is one picture for each
-- padding from 8 to 12. Widgets hold every picture, so the engine keeps them (a texture only Lua holds is
-- thrown away).
local BLADE_FILE = (RUNEUI_DIR or "ue4ss/Mods/RuneUI/") .. "Art/bar_blade_"   -- then the padding and ".png"
local BLADE_W, BLADE_CORE = 80, 16   -- keep as in tools/make-runemap-art.js
-- The game's gold stamina fill times this shows green: red down to 0.35 and blue to 0.6 on screen, in the
-- linear values the engine takes.
local STAMINA_GREEN = { R = 0.10, G = 1.0, B = 0.32, A = 1.0 }
local BARS = {
    { Class = "WBP_HUD_Vitals_StaminaBar_C", Icon = "StaminaIcon" },
    { Class = "WBP_HUD_Vitals_HealthBar_C", Icon = "HealthImage" },
    { Class = "WBP_HUD_Vitals_SpecialChargeBar_C", Icon = "SpecialAttackImage" },
}
local Blades = { HostName = nil, Tex = {}, Bars = {}, Missed = {}, Count = 0, Swapped = nil }

local function DressBar(B, W)
    local frame = W.ProgressBarImage:GetParent():GetParent()
    if ClassName(frame) ~= "Border" then error(B.Class .. ": the fill's frame is a " .. ClassName(frame)) end
    -- read before anything changes: the picture is chosen by the padding under the fill
    local p = frame.Padding
    Log(string.format("bar %s: frame padding %.1f %.1f %.1f %.1f", B.Class, p.Left, p.Top, p.Right, p.Bottom))
    local pad = math.floor(p.Bottom + 0.5)
    if pad < 8 or pad > 12 then error(B.Class .. ": no picture for a padding of " .. pad) end
    local h = pad * 2 + BLADE_CORE
    local file = BLADE_FILE .. pad .. ".png"
    frame:SetBrushFromTexture(CachedTex(Blades.Tex, file, W, file))
    local b = frame.Background
    b.DrawAs = 1   -- box: nine pieces
    b.Tiling = 0
    b.Margin = { Left = p.Left / BLADE_W, Top = pad / h, Right = p.Right / BLADE_W, Bottom = pad / h }
    b.ImageSize = { X = BLADE_W, Y = h }
    b.TintColor = { SpecifiedColor = { R = 1, G = 1, B = 1, A = 1 }, ColorUseRule = 0 }
    frame:SetBrush(b)
    frame:SetBrushColor({ R = 1, G = 1, B = 1, A = 1 })
end

-- Health on top: the stamina row and the health row swap places on screen. Only their drawn place moves
-- (render translation); the game's layout stays as it is. Checked on every scan: a row grows when the game
-- shows its regen number, and a size read before the first layout is 0.
local function SwapRows()
    local rs, rh = Blades.Bars[1]:GetParent(), Blades.Bars[2]:GetParent()
    local gap = 0
    pcall(function() gap = rs.Slot.Padding.Bottom + rh.Slot.Padding.Top end)
    local hs, hh = rs:GetDesiredSize().Y, rh:GetDesiredSize().Y
    if hs < 1 or hh < 1 then return end
    local key = string.format("%.1f %.1f %.1f", hs, hh, gap)
    if key == Blades.Swapped then return end
    rs:SetRenderTranslation({ X = 0, Y = hh + gap })
    rh:SetRenderTranslation({ X = 0, Y = -(hs + gap) })
    if not Blades.Swapped then Log(string.format("bars: health on top (rows %.0f and %.0f high, gap %.0f)", hs, hh, gap)) end
    Blades.Swapped = key
end

-- One color bars (1.2, the pick from the F7 tests of 29-09-2026, for everyone and with no switch): each bar's
-- shadow colour takes its main colour, so the fill shows one colour, and the texture is stronger. The texture's
-- setting is a power: the game's is 5, a lower one shows more, and 1.5 was his pick. The bubbles stay the game's.
-- The colours live on the fill's parent material, so the main colour is read there.
local ONE_COLOR_NOISE = 1.5
M.OneColorNoise = ONE_COLOR_NOISE   -- enemybars.lua gives the enemy bars the same texture
local OneColor = {}   -- by bar: the full name of the fill last given the look; the game may give a bar a new fill
local function OneColorFill(mat)
    local main
    mat.Parent.VectorParameterValues:ForEach(function(_, e)
        local p = e:get()
        if p.ParameterInfo.Name:ToString() == "Health Bar Main Color" then
            local c = p.ParameterValue
            main = { R = c.R, G = c.G, B = c.B, A = c.A }
        end
    end)
    if not main then error("no main colour on " .. mat:GetFullName()) end
    mat:SetVectorParameterValue(FName("Health Bar Shadows Color"), main)
    mat:SetScalarParameterValue(FName("Bar Noise Power"), ONE_COLOR_NOISE)
    return main
end

local function EnsureBlades()
    if not MayTry(Blades) then return end
    local VE = ById("vitals")
    local V = VE.Instances[1]
    if not (V and V:IsValid()) then return end
    local host = VE.Keys[1]   -- its full name, read by the search
    if Blades.HostName ~= host then
        Blades.HostName, Blades.Bars, Blades.Missed, Blades.Count, Blades.Swapped, Blades.NoNumbers = host, {}, {}, 0, nil, nil
        OneColor = {}   -- new bars: a fill of theirs may reuse an old name
    end
    local ok, err = pcall(function()
        -- a bar the game made again: forget the dead handle, find the new widget and swap the rows again
        for i = 1, #BARS do
            if Blades.Bars[i] and not Blades.Bars[i]:IsValid() then
                Blades.Bars[i], Blades.Count, Blades.Swapped, Blades.NoNumbers = nil, Blades.Count - 1, nil, nil
            end
        end
        if Blades.Count < #BARS then
            -- a full name is "Class /Path": a bar's path starts with the path of the bars widget
            local hostPath = (string.match(host, "^%S+%s+(.*)$") or host) .. "."
            for i, B in ipairs(BARS) do
                if not Blades.Bars[i] then
                    for _, W in ipairs(FindClass(B.Class)) do
                        if string.find(W:GetFullName(), hostPath, 1, true) then
                            local okD, errD = pcall(DressBar, B, W)
                            if not okD then Log("bars: " .. B.Class .. " keeps the game's frame: " .. tostring(errD)) end
                            Blades.Bars[i] = W
                            Blades.Count = Blades.Count + 1
                            break
                        end
                    end
                    if not Blades.Bars[i] and not Blades.Missed[i] then Blades.Missed[i] = true Log("bars: no " .. B.Class .. " yet") end
                end
            end
        end
        -- each part as soon as its bars are there: a missing special bar must not stop the others
        if Blades.Bars[1] and Blades.Bars[2] then SwapRows() end
        -- no numbers on the health bar (playtest, 30-09-2026): unseen, not collapsed, so the immersive mode still reads them
        if Blades.Bars[2] and Survival and not Blades.NoNumbers then
            local texts = Survival.TextsUnder(Blades.Bars[2])
            for _, T in ipairs(texts) do pcall(function() T:SetRenderOpacity(0.0) end) end
            if #texts > 0 then   -- none yet: the bar is still being built, try on the next scan
                Blades.NoNumbers = true
                Log("bars: health numbers hidden (" .. #texts .. " texts)")
            end
        end
        if Blades.Bars[1] then
            -- stamina green, set again whenever the game resets it (taking a tool did, 27-09-2026)
            local fill = Blades.Bars[1].ProgressBarImage
            local c = fill.ColorAndOpacity
            if math.abs(c.R - STAMINA_GREEN.R) > 0.01 or math.abs(c.B - STAMINA_GREEN.B) > 0.01 then fill:SetColorAndOpacity(STAMINA_GREEN) end
        end
        -- one color: for each fill, again when the game gives a bar a new fill, and again when the game sets the
        -- fill's own look back (a new character, 29-09-2026: the bars went two-tone), read on every scan
        for i = 1, #BARS do
            local W = Blades.Bars[i]
            if W then
                local okC, errC = pcall(function()
                    local mat = W.ProgressBarImage.Brush.ResourceObject
                    local name = mat:GetFullName()
                    if OneColor["x" .. i] == name then return end   -- this fill failed once: not tried on every scan
                    if OneColor[i] == name then
                        local noise, shade
                        mat.ScalarParameterValues:ForEach(function(_, e)
                            local p = e:get()
                            if p.ParameterInfo.Name:ToString() == "Bar Noise Power" then noise = p.ParameterValue end
                        end)
                        mat.VectorParameterValues:ForEach(function(_, e)
                            local p = e:get()
                            if p.ParameterInfo.Name:ToString() == "Health Bar Shadows Color" then shade = p.ParameterValue end
                        end)
                        local was = OneColor["c" .. i]
                        if noise and math.abs(noise - ONE_COLOR_NOISE) < 0.01 and shade and was and math.abs(shade.R - was.R) < 0.01
                            and math.abs(shade.G - was.G) < 0.01 and math.abs(shade.B - was.B) < 0.01 then return end
                        if not OneColor.Reset then OneColor.Reset = true Log("bars: the game set the fill's look back; one color again") end
                    end
                    OneColor[i], OneColor["x" .. i] = name, name
                    OneColor["c" .. i] = OneColorFill(mat)
                    OneColor["x" .. i] = nil
                end)
                if not okC and not OneColor.Logged then OneColor.Logged = true Log("bars: one color failed: " .. tostring(errC)) end
            end
        end
        -- the icons: hidden, not collapsed, so the bars keep their place; checked on every scan in case the
        -- game sets them again
        local want = ById("baricons").Visible ~= false and 4 or 2
        for i, B in ipairs(BARS) do
            local W = Blades.Bars[i]
            if W then
                local icon = W[B.Icon]
                if icon:GetVisibility() ~= want then icon:SetVisibility(want) end
            end
        end
        -- the dark gradient behind the bars (T_Bars_Shadow; playtest, 29-09-2026: it looks ugly): unseen, alive for the
        -- game. Hidden, not collapsed, so nothing moves. On a new character the game showed it again (29-09-2026),
        -- so both the visibility and the opacity are checked on every scan. Found by its name in the bars' widget
        -- tree, once per bars widget: GetWidgetFromName is not open to Lua in UE4SS 3.0.1 (log of 29-09-2026).
        local okS, errS = pcall(function()   -- on its own: a failure here must not count against the bars
            local shadow = Blades.ShadowW
            if Blades.ShadowHost ~= host or (shadow and not shadow:IsValid()) then
                shadow = Survival and Survival.Find(V, "ShadowBackgroundImage")
                -- none found while the bars are still coming: searched again on the next scan
                Blades.ShadowW = shadow
                if shadow or Blades.Count == #BARS then Blades.ShadowHost = host end
            end
            if not (shadow and shadow:IsValid()) then
                if Blades.ShadowHost == host then error("ShadowBackgroundImage not found") end
                return
            end
            if shadow:GetVisibility() ~= 2 or shadow:GetRenderOpacity() > 0 then
                if Blades.Shadow == host and not Blades.ShadowBack then Blades.ShadowBack = true Log("bars: the game showed the shadow again; hidden again") end
                shadow:SetVisibility(2)
                shadow:SetRenderOpacity(0.0)
                Blades.Shadow = host
            end
        end)
        if not okS and not Blades.ShadowLogged then Blades.ShadowLogged = true Log("bars: shadow not hidden: " .. tostring(errS)) end
    end)
    if ok then Blades.Fails = 0 else Failed(Blades) Log("bars failed: " .. tostring(err)) end
end


-- once per widget scan (main.lua): the line under the bars, then the bars
function M.Scan() EnsureBarTrim() EnsureBlades() end

-- a new world or a player restart: every handle into the old HUD is dropped
function M.Forget()
    BarTrim.HostName, BarTrim.W = nil, nil
    Blades.HostName, Blades.Tex, Blades.Bars, Blades.ShadowW, Blades.ShadowHost = nil, {}, {}, nil, nil
    for _, P in ipairs({ BarTrim, Blades }) do P.Fails, P.RetryAt = 0, 0 end   -- new tries (see MayTry)
end

-- the immersive mode fades the bars and the trim line
M.Blades, M.Trim = Blades, BarTrim
-- for the F9 panel's warning line: one of the two builds gave up (see MayTry)
function M.Problem() return (Blades.Fails or 0) >= 3 or (BarTrim.Fails or 0) >= 3 end

return M
