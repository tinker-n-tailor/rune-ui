-- The level badge, or the player's own picture, beside the bars: the green diamond of the inventory with the
-- level number, or avatar.png from the mod folder. It lives inside the game's bars widget, so it hides with the
-- HUD and moves with the bars. main.lua loads this file with pcall; its Scan runs once per widget scan.

local M = { W = nil, HostName = nil, Tex = nil }   -- W: the badge's box, the F9 element "avatar"
local Avatar = M
-- main.lua's helpers, bound once by Init (see Util in main.lua)
local Log, ById, Uniq, G, ClearOurs, ClassName, FindClass, Asset, SetColor, MayTry, Failed, CachedTex, Survival
function M.Init(ctx)
    Log, ById, Uniq, G, ClearOurs, ClassName, FindClass = ctx.Log, ctx.ById, ctx.Uniq, ctx.G, ctx.ClearOurs, ctx.ClassName, ctx.FindClass
    Asset, SetColor = ctx.Asset, ctx.SetColor
    MayTry, Failed, CachedTex, Survival = ctx.MayTry, ctx.Failed, ctx.CachedTex, ctx.Survival
end

local AVATAR_FILES = { "ue4ss/Mods/RuneUI/avatar.png" }

-- The player's power level, read from the level display of the inventory (it exists while the inventory is
-- closed too): SizeBox > Border > Overlay > [icon, text].
local function ReadPowerLevel()
    local D = FindClass("WBP_InventoryPowerLevelDisplay_C")[1]
    if not D then return nil end
    local ov = D.WidgetTree.RootWidget:GetContent():GetContent()
    local T = ov:GetChildAt(1)
    local icon = nil
    pcall(function() icon = ov:GetChildAt(0).Brush.ResourceObject end)
    return T:GetText():ToString(), T, icon
end

-- Level badge: the green diamond from the inventory with the level number, the default avatar.
local function BuildLevelBadge(tree)
    local ov = StaticConstructObject(StaticFindObject("/Script/UMG.Overlay"), tree, G("RU_LevelBadge"))
    local tex = Asset("/Game/Art/UI/PowerLevel/T_PowerLevel_AboveZone.T_PowerLevel_AboveZone", "/Script/Engine.Texture2D")
    if tex then
        local img = StaticConstructObject(StaticFindObject("/Script/UMG.Image"), tree, G("RU_LevelIcon"))
        img:SetBrushFromTexture(tex, false)
        Avatar.LevelIcon = img
        local s = ov:AddChildToOverlay(img)
        s:SetHorizontalAlignment(0) s:SetVerticalAlignment(0)
    end
    local txt = StaticConstructObject(StaticFindObject("/Script/UMG.TextBlock"), tree, G("RU_LevelText"))
    txt:SetText(FText("?"))
    SetColor(txt, { R = 1, G = 1, B = 1, A = 1 })
    pcall(function()
        txt:SetShadowOffset({ X = 1.5, Y = 1.5 })
        txt:SetShadowColorAndOpacity({ R = 0, G = 0, B = 0, A = 0.85 })
    end)
    pcall(function()
        local _, gameText = ReadPowerLevel()
        local fi = txt.Font
        if gameText then fi.FontObject = gameText.Font.FontObject end
        fi.Size = 26
        pcall(function() fi.OutlineSettings.OutlineSize = 2 fi.OutlineSettings.OutlineColor = { R = 0, G = 0, B = 0, A = 0.9 } end)
        txt:SetFont(fi)
    end)
    local ts = ov:AddChildToOverlay(txt)
    ts:SetHorizontalAlignment(2) ts:SetVerticalAlignment(2)   -- centre
    -- the menu font's line carries a deep descender, so its digits sit high. Only down, not sideways: at
    -- +2 a digit with a heavy right stroke (the 4) looked shifted right (in-game test, 27-09-2026)
    pcall(function() txt:SetRenderTranslation({ X = 0, Y = 2 }) end)
    Avatar.LevelText = txt
    return ov
end

local function EnsureAvatar()
    if not MayTry(Avatar) then return end
    local VE = ById("vitals")
    local V = VE.Instances[1]
    if not (V and V:IsValid()) then return end
    local hostName = VE.Keys[1]   -- its full name, read by the search
    if Avatar.W and Avatar.W:IsValid() and Avatar.HostName == hostName then
        -- keep the level number fresh
        if Avatar.LevelText then
            pcall(function()
                local lv, _, icon = ReadPowerLevel()
                if lv and lv ~= Avatar.LastLevel then Avatar.LastLevel = lv Avatar.LevelText:SetText(FText(lv)) end
                -- the game swaps the diamond's picture (colour) by your level against the area; follow it
                local iconName = icon and icon:GetFullName()
                if iconName and Avatar.LevelIcon and iconName ~= Avatar.LastIcon then
                    Avatar.LastIcon = iconName
                    Avatar.LevelIcon:SetBrushFromTexture(icon, false)
                end
            end)
        end
        return
    end
    local step = "texture"
    local ok, err = pcall(function()
        -- a picture only when the player put avatar.png in the mod folder; otherwise the level badge
        if not (Avatar.Tex and Avatar.Tex:IsValid()) and not Avatar.NoPicture then
            local KRL = StaticFindObject("/Script/Engine.Default__KismetRenderingLibrary")
            for _, file in ipairs(AVATAR_FILES) do
                local fh = io.open(file, "rb")
                if fh then
                    fh:close()
                    local okT, tex = pcall(function() return KRL:ImportFileAsTexture2D(V, file) end)
                    if okT and tex and tex:IsValid() then Avatar.Tex = tex Log("avatar picture loaded from " .. file) break end
                end
            end
            if not Avatar.Tex then Avatar.NoPicture = true Log("no avatar.png, showing the level badge") end
        end
        step = "image"
        local root = V.WidgetTree.RootWidget
        local img
        if Avatar.Tex then
            img = StaticConstructObject(StaticFindObject("/Script/UMG.Image"), V.WidgetTree, G("RU_Avatar"))
            img:SetBrushFromTexture(Avatar.Tex, false)
        else
            img = BuildLevelBadge(V.WidgetTree)
            Avatar.LastLevel = nil
        end
        step = "place"
        -- The bars widget's root is a full-screen Overlay. The bars sit in it centred and at the bottom, so the
        -- badge does too, next to the bars' left end: its box at 710,932 on a 16:9 screen. Pinned to the top left, it
        -- slid off the bars on a wide screen (Nexus, 29-09-2026). A centred child's middle is at half the width
        -- plus Left minus Right (not the middle of the room between the paddings: in-game test, 29-09-2026), and a
        -- bottom one's bottom edge is Bottom above the bottom. So Right = 960 - 744.5 and Bottom = 1080 - 1001.
        local box = StaticConstructObject(StaticFindObject("/Script/UMG.SizeBox"), V.WidgetTree, G("RU_AvatarBox"))
        box:SetWidthOverride(69)
        box:SetHeightOverride(69)
        box:SetContent(img)
        ClearOurs(root, "RU_AvatarBox")
        local slot = root:AddChildToOverlay(box)
        slot:SetHorizontalAlignment(2)   -- centre
        slot:SetVerticalAlignment(3)     -- bottom
        slot:SetPadding({ Left = 0, Top = 0, Right = 215.5, Bottom = 79 })
        Avatar.W, Avatar.HostName = box, hostName
    end)
    if ok then Log("avatar ready") Avatar.Fails = 0 else Failed(Avatar) Log("avatar failed at step '" .. step .. "': " .. tostring(err)) end
end


-- once per widget scan (main.lua)
function M.Scan() EnsureAvatar() end

-- a new world or a player restart: every handle into the old HUD is dropped
function M.Forget()
    M.W, M.HostName, M.Tex, M.LevelText, M.LevelIcon = nil, nil, nil, nil, nil
    M.LastLevel, M.LastIcon = nil, nil
    M.Fails, M.RetryAt = 0, 0
end

return M
