-- The menu buttons (chat, map, spell book, building, bag) in the ring style of food, water and rest: the gold rim and
-- dark centre of survival.lua's ring, the game's own icon in cream on top, and the key in a small dark box under it. The bag's ring fills with the bag's weight, gold, red past 90%.
-- The row is the game's (HorizontalBox_436 in the input legend's world page); apply.lua moves it as "menubtn".
-- What each button holds (widget dump, 29-09-2026): Overlay_371 with the grey circle (BackgroundImage) and the
-- icon (ContextualImage); the bag adds its weight ring (EncumbranceRadialImage, a material with FillBar 0..1),
-- the ring's track and a weight icon; the key is drawn by ContextualInput under it.
-- main.lua loads this file with pcall, so an error here leaves the rest of the mod running.

local M = {}

local ART_DIR = (RUNEUI_DIR or "ue4ss/Mods/RuneUI/") .. "Art/"
local RING = 64      -- the button's box is 75 units; the game's grey circle fills about 64 of it
local ICON = 62      -- the game's icon picture has wide empty edges; 75 (the whole box) overlapped the rim (in game 29-09-2026)
local GAME_PARTS = { BackgroundImage = true, EncumbranceBackgroundImage = true, EncumbranceRadialImage = true }
local ICON_PARTS = { ContextualImage = true, WeightImage = true }   -- copied in cream on top of our ring
local KEYS = { InputLegend_Contextual_OpenChat = "Enter", InputLegend_Contextual_MapQuest = "M",
    InputLegend_Contextual_SpellBook = "Q", InputLegend_Contextual_BuildMenu = "B", InputLegend_Contextual_InventoryEntry = "Tab" }
local FULL = 0.9     -- the bag ring turns red past this

local function Lin1(c) if c <= 0.04045 then return c / 12.92 end return ((c + 0.055) / 1.055) ^ 2.4 end
local function Lin(r, g, b) return { R = Lin1(r), G = Lin1(g), B = Lin1(b), A = 1.0 } end
local CREAM = Lin(0.945, 0.902, 0.784)                 -- #f1e6c8, the survival icons' tint
local GOLD = { R = 0.95, G = 0.77, B = 0.38, A = 1.0 } -- the game's own weight ring colour (dump)
local RED = Lin(0.85, 0.22, 0.16)
local WHITE = { R = 1, G = 1, B = 1, A = 1 }             -- the key letters

local function Obj(path) return StaticFindObject(path) end
local function New(cls, outer, name) return StaticConstructObject(Obj("/Script/UMG." .. cls), outer, FName(name)) end
local Logged = {}
local function Once(ctx, key, msg) if not Logged[key] then Logged[key] = true ctx.Log(msg) end end

local function LoadArt(ctx, outer, name)
    local KRL = Obj("/Script/Engine.Default__KismetRenderingLibrary")
    local ok, tex = pcall(function() return KRL:ImportFileAsTexture2D(outer, ART_DIR .. name) end)
    if ok and tex and tex:IsValid() then return tex end
    Once(ctx, "art" .. name, "menu buttons: picture not loaded: " .. name .. " " .. tostring(tex))
end

local Built = {}   -- one per button: { Right, Left (the ring's halves), Fill (the bag's material) }
M.Host, M.Builds, M.Chat = nil, 0, nil

-- the key's name from the game's key widget, else the default key
local function KeyName(ctx, entry)
    local name = entry:GetFName():ToString()
    local ok, s = pcall(function() return ctx.Find(entry, "DomActionWidget"):GetDisplayText():ToString() end)
    Once(ctx, "key" .. name, "menu buttons: " .. name .. " key text '" .. tostring(ok and s or "?") .. "'")
    if ok and s and s ~= "" then return s end
    return KEYS[name] or "?"
end

local function Decorate(ctx, row)
    M.Builds = M.Builds + 1
    local tag = "RU_Mb" .. M.Builds .. "_" .. os.time()   -- a new name each build (see survival.lua)
    Built = {}
    local Picture, Sized, Add = ctx.Survival.Picture, ctx.Survival.Sized, ctx.Survival.Add
    for i = 0, row:GetChildrenCount() - 1 do
        local entry = row:GetChildAt(i)
        local ename = entry:GetFName():ToString()
        local ok, err = pcall(function()
            local tree = entry.WidgetTree
            local ov = ctx.Find(entry, "Overlay_371")
            local outer = ctx.Find(entry, "Overlay_41")
            if not (ov and outer) then error("no button box") end
            local art = { Back = LoadArt(ctx, tree, "upkeep_back.png"), Half = LoadArt(ctx, tree, "upkeep_half.png"),
                Centre = LoadArt(ctx, tree, "upkeep_centre.png") }
            local cap = LoadArt(ctx, tree, "keycap.png")
            if not (art.Back and art.Half and art.Centre and cap) then error("pictures missing") end
            -- ours from an earlier round first (a player restart keeps the game's widgets)
            ctx.ClearOurs(ov, "RU_Mb")
            ctx.ClearOurs(outer, "RU_Mb")
            local n = tag .. "_" .. i
            local stack, rImg, lImg = ctx.Ring(tree, n, RING, art, GOLD)
            -- the game's icons, copied in cream; the game's circle, ring and icons stay alive but unseen
            local icons = {}
            for c = 0, ov:GetChildrenCount() - 1 do
                local w = ov:GetChildAt(c)
                local wn = w:GetFName():ToString()
                if ICON_PARTS[wn] then
                    local tex = w.Brush.ResourceObject
                    local pic = Picture(tree, n .. wn, tex, ICON)
                    pic:SetColorAndOpacity(CREAM)
                    icons[#icons + 1] = pic
                end
                if GAME_PARTS[wn] or ICON_PARTS[wn] then w:SetRenderOpacity(0.0) end
            end
            Add(ov, Sized(tree, n, RING, RING, stack), 2, 2)
            for _, pic in ipairs(icons) do Add(ov, pic, 2, 2) end
            -- the key: the game's key box unseen, ours at the bottom of the button (Tick swaps the two for a gamepad)
            local gameKey
            pcall(function() gameKey = ctx.Find(entry, "ScaleBox_0") gameKey:SetRenderOpacity(0.0) end)
            local border = New("Border", tree, n .. "Key")
            border:SetBrushFromTexture(cap)
            local b = border.Background
            b.DrawAs = 1   -- box: nine pieces
            b.Margin = { Left = 0.5, Top = 0.5, Right = 0.5, Bottom = 0.5 }
            b.ImageSize = { X = 8, Y = 8 }
            border:SetBrush(b)
            border:SetPadding({ Left = 8, Top = 3, Right = 8, Bottom = 3 })
            border:SetContent(ctx.Text(tree, n .. "KeyText", 9, WHITE, KeyName(ctx, entry)))
            Add(outer, border, 2, 3, { Left = 0, Top = 0, Right = 0, Bottom = 6 })   -- bottom
            local fill
            pcall(function() fill = ctx.Find(entry, "EncumbranceRadialImage").Brush.ResourceObject end)
            Built[#Built + 1] = { Right = rImg, Left = lImg, Fill = fill, GameKey = gameKey, Key = border }
        end)
        if not ok then ctx.Log("menu buttons: " .. ename .. " failed: " .. tostring(err)) end
    end
    M.Pad = nil   -- new key boxes: Tick sets them for the input in use
    ctx.Log("menu buttons: " .. #Built .. " rings")
end

-- the bag's weight, 0..1, from the game's ring material
local function Weight(fill)
    local v
    fill.ScalarParameterValues:ForEach(function(_, e)
        local p = e:get()
        if p.ParameterInfo.Name:ToString() == "FillBar" then v = p.ParameterValue end
    end)
    return v
end

function M.Forget()
    Built = {}
    M.Host, M.Tried, M.Chat, M.List, M.Pad = nil, nil, nil, nil, nil
end

function M.Tick(ctx)
    if os.clock() < (M.Next or 0) then return end
    M.Next = os.clock() + 0.5
    -- the chat's message count: the immersive mode shows the row when it grows
    local okC, errC = pcall(function()
        local chat = ctx.Chat()
        if not (chat and chat:IsValid()) then M.List = nil return end   -- the main menu has no chat: nothing to read
        -- the list is found once per chat widget: the walk to it cost dozens of calls, twice a second (30-09-2026)
        local L = M.List
        if not (L and L.Addr == chat:GetAddress() and L.W:IsValid()) then
            L = { Addr = chat:GetAddress(), W = ctx.Find(chat, "MessageListView") }
            M.List = L
        end
        local n = L.W:GetNumItems()
        if n ~= M.Chat and (M.ChatLogs or 0) < 5 then M.ChatLogs = (M.ChatLogs or 0) + 1 ctx.Log("menu buttons: chat messages " .. tostring(n)) end
        M.Chat = n
    end)
    if not okC then M.List = nil Once(ctx, "chat", "menu buttons: chat not read: " .. tostring(errC)) end
    local E = ctx.ById("menubtn")
    local row = E.Instances[1]
    if not (row and row:IsValid()) then return end
    local name = E.Keys[1]   -- its full name, read by finder.lua's search
    local function Alive()
        for _, b in ipairs(Built) do if b.Right and b.Right:IsValid() then return true end end
        return false
    end
    if name ~= M.Host or not Alive() then
        if name == M.Host and M.Tried then return end
        M.Host = name
        Decorate(ctx, row)
        M.Tried = not Alive()
    end
    -- With a gamepad our key box would hold a keyboard key (Enter, M, Q, B, Tab, seen on 03-10-2026), so the game's own
    -- key box shows: it draws the gamepad's button.
    local okPad, pad = pcall(ctx.Pad)
    pad = okPad and pad or false
    if pad ~= M.Pad then
        M.Pad = pad
        for _, b in ipairs(Built) do
            pcall(function()
                b.Key:SetRenderOpacity(pad and 0.0 or 1.0)
                if b.GameKey and b.GameKey:IsValid() then b.GameKey:SetRenderOpacity(pad and 1.0 or 0.0) end
            end)
        end
        ctx.Log("menu buttons: keys for " .. (pad and "a gamepad" or "the keyboard"))
    end
    for _, b in ipairs(Built) do
        pcall(function()
            local p = 0
            if b.Fill and b.Fill:IsValid() then p = Weight(b.Fill) or 0 end
            if p ~= b.Value then b.Value = p ctx.Turn(b, math.max(0, math.min(1, p))) end
            local red = p > FULL
            if red ~= b.Red then
                b.Red = red
                b.Right:SetColorAndOpacity(red and RED or GOLD)
                b.Left:SetColorAndOpacity(red and RED or GOLD)
            end
        end)
    end
end

return M
