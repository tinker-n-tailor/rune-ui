-- What the parts share to make and find things in the engine: the names of our widgets, assets and pictures, a text with
-- a shadow, the game's fonts, and the removal of our widgets. main.lua loads this file, gives it the log (Init) and
-- hands these functions to the parts in their ctx.

local M = {}

local Log
function M.Init(ctx) Log = ctx.Log end

-- The widgets the mod adds into the game's own widgets get a new name each round (a round ends when the
-- player restarts or the world changes): making an object with the name of a live one makes the engine
-- replace it in place, which crashed the game on entering a world (27-09-2026).
local Gen = 1
local NameCount = 0
-- The editor panel names its widgets by the round too.
function M.Round() return Gen end
-- A new round: the world watch calls it when it drops the old world's handles.
function M.NextRound() Gen = Gen + 1 end
-- Every call gives a new name, so a second try in the same round never reuses the name of a live object.
local function Uniq(name) NameCount = NameCount + 1 return name .. "_" .. Gen .. "_" .. NameCount end
local function G(name) return FName(Uniq(name)) end

-- Our widgets from an earlier round, still inside a game widget: take them out before adding new ones. Only
-- called while that game widget is alive and on screen.
local function ClearOurs(panel, prefix)
    pcall(function()
        for i = panel:GetChildrenCount() - 1, 0, -1 do
            local c = panel:GetChildAt(i)
            if c and string.find(c:GetFName():ToString(), prefix, 1, true) == 1 then c:RemoveFromParent() end
        end
    end)
end

-- When UE4SS reloads this mod while the game runs, the widgets of the previous run are still on screen.
-- Remove every widget the mod made (names start with RuneUI or RU_) before building new ones. Only once,
-- when the mod loads: on a player restart it pulled widgets out of a world that was being unloaded (the crash
-- on quitting to the menu, 27-09-2026).
function M.RemovePreviousRun()
    pcall(function()
        local removed = 0
        for _, cls in ipairs({ "UserWidget", "SizeBox", "Overlay", "CanvasPanel", "Image", "Border" }) do
            for _, W in pairs(FindAllOf(cls) or {}) do
                pcall(function()
                    local n = W:GetFName():ToString()
                    if string.find(n, "^RuneUI") or string.find(n, "^RU_") then
                        W:RemoveFromParent()
                        removed = removed + 1
                    end
                end)
            end
        end
        if removed > 0 then Log("reload: removed " .. removed .. " widgets of the previous run") end
    end)
end

local function Cls(path) return StaticFindObject(path) end

local function SetColor(T, c)
    T:SetColorAndOpacity({ SpecifiedColor = c, ColorUseRule = 0 })
end

-- a text of ours with a soft shadow, in the font given (the game's default font without one)
local function MakeText(tree, name, size, color, s, font)
    local T = StaticConstructObject(Cls("/Script/UMG.TextBlock"), tree, FName(name))
    T:SetText(FText(s or ""))
    SetColor(T, color)
    pcall(function()
        T:SetShadowOffset({ X = 1, Y = 1 })
        T:SetShadowColorAndOpacity({ R = 0, G = 0, B = 0, A = 0.8 })
    end)
    pcall(function()
        local fi = T.Font   -- our own text, so changing it touches nothing of the game
        if font then fi.FontObject = font end
        fi.Size = size
        T:SetFont(fi)
    end)
    return T
end

-- Poppins, the game's body font: the editor, the menu keys and the cooldowns write in it. Found once.
local Poppins = nil
local function FindPoppins()
    if Poppins and Poppins:IsValid() then return Poppins end
    for _, F in pairs(FindAllOf("Font") or {}) do
        local ok, n = pcall(function() return F:GetFullName() end)
        if ok and string.find(n, "/Game/") and string.find(n, "Poppins") and not string.find(n, "Default__") then Poppins = F break end
    end
    return Poppins
end

-- Poppins Medium, the heavier of the game's two weights: the quest tracker writes in it, because Regular is hard to
-- read when the tracker is scaled down. Found once; without it, the font above.
local PoppinsMedium = nil
local function FindPoppinsMedium()
    if PoppinsMedium and PoppinsMedium:IsValid() then return PoppinsMedium end
    local F = StaticFindObject("/Game/UI/Fonts/Poppins-Medium_Font.Poppins-Medium_Font")
    if F and F:IsValid() then PoppinsMedium = F return F end
    return FindPoppins()
end

-- kind: the class the object must be, for the typed calls it goes into. After a game patch another kind of object
-- can sit at a known path; the wrong kind can crash.
local function Asset(path, kind)
    if not path then return nil end
    if not string.match(path, "^/[%w_%./%-]+$") then Log("asset path not accepted: " .. path) return nil end
    local obj = StaticFindObject(path)
    if (not obj or not obj:IsValid()) and LoadAsset then
        pcall(function() obj = LoadAsset(path) end)
    end
    if not (obj and obj:IsValid()) then Log("asset not found: " .. path) return nil end
    if kind then
        local okA, isA = pcall(function() local K = StaticFindObject(kind) return K and K:IsValid() and obj:IsA(K) end)
        if not (okA and isA) then Log("asset is not a " .. kind .. ": " .. path) return nil end
    end
    return obj
end

-- A picture from a file, kept in cache[key] and reused while it is valid. Widgets must hold it: a texture that
-- only Lua holds is thrown away by the engine. The buffs and the bars use it.
local function CachedTex(cache, key, outer, file)
    local tex = cache[key]
    if tex and tex:IsValid() then return tex end
    tex = StaticFindObject("/Script/Engine.Default__KismetRenderingLibrary"):ImportFileAsTexture2D(outer, file)
    if not (tex and tex:IsValid()) then
        local f = io.open(file, "rb")   -- for the log: the file is not there, or the engine did not take it
        if f then f:close() end
        error((f and "picture not loaded: " or "picture missing: ") .. file, 0)
    end
    cache[key] = tex
    return tex
end

M.Uniq, M.G, M.ClearOurs, M.Cls, M.SetColor, M.MakeText = Uniq, G, ClearOurs, Cls, SetColor, MakeText
M.FindPoppins, M.FindPoppinsMedium, M.Asset, M.CachedTex = FindPoppins, FindPoppinsMedium, Asset, CachedTex
return M
