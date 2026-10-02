-- RuneMap, the minimap (design sketch, 27-09-2026): the game's own minimap widget, fed by our own map view,
-- in a gold ring that is also the clock. The middle of the night is at the top and noon at the bottom; the
-- ring keeps the game's own share of night (about a fifth), so dawn sits near 1 o'clock and dusk near 11.
-- A gold arrow between the two gold rings points at the time of day, and a bigger arrow with an N shows north
-- (1.5; before, a needle across the ring and a round mark on the inner ring).
-- F8 (1.1, main.lua) turns the map on or off and sets faces north, the north mark, the creatures, the resources
-- (resources.lua), the zoom and how often the map draws.
-- main.lua loads this file with pcall, so an error here leaves the rest of the mod running.

-- Dirty, ResetWanted and PendingZoom are set by key handlers: kept in the table as false, never nil, so
-- setting them never grows the table on UE4SS's key thread
local M = { W = nil, Fails = 0, Dirty = false, ResetWanted = false, PendingZoom = false }

local D = 180                  -- map diameter; the art tool draws the band for the same size
local BOX = D + 44             -- the whole element: map, day band and gold rings
local C = BOX / 2
local R_DIAMOND, DIAMOND = D / 2 + 17, 16   -- the marks on the outer gold ring; 13 units before 1.5 ("a bit bigger")
-- The game's clock (first test, 27-09-2026): the day and night dial's material holds "Fill Amount", the share
-- of the day cycle gone (0 = dawn), and "Night Start", where night begins (0.795). The ring puts the middle of
-- the night at the top.
local NIGHT_START = 0.795

local MAP_CLASS = "/Game/UI/HUD/ModifiedMinimapPlugin/WBP_DominionMinimap.WBP_DominionMinimap_C"
local VIEW_CLASS = "/Script/MinimapPlugin.MapViewComponent"

-- the map settings, taken from the MiniMap addon (27-09-2026)
-- InitialMapSize: without the addon it stayed 0 and the map drew nothing, not even the arrow. IconScale: the
-- map icons (camps, boats) looked too big at 1, and 10% big at 0.6 (27-09-2026). 0.54 was still much too big for
-- the dungeons and the other game icons, and 0.3 super small (playtest, 29-09-2026). It scales our own icons too.
local ICON_SCALE = 0.4
local MAP_SETTINGS = { bIsCircular = true, AutoLocateMapView = 4, IconScale = ICON_SCALE, FloorDistance = 300,
    InitialMapSize = { X = D, Y = D } }
-- the addon's view settings: without them (test of 27-09-2026) the view kept RotationMode 0 and the map
-- stopped turning with the camera
local VIEW_SETTINGS = { bSupportZooming = true, RotationMode = 1, InheritedYawOffset = 90 }

-- Unreal takes widget colours as linear light; the sketch's colours are the screen kind (sRGB). Sent as they
-- are, they come out pale (first test, 27-09-2026), so every colour here goes through Lin first.
local function Lin1(c) if c <= 0.04045 then return c / 12.92 end return ((c + 0.055) / 1.055) ^ 2.4 end
local function Lin(r, g, b, a) return { R = Lin1(r), G = Lin1(g), B = Lin1(b), A = a or 1.0 } end

local GOLD  = Lin(0.72, 0.57, 0.31)
local DARK  = Lin(0.08, 0.05, 0.03, 0.92)
local NONE  = { R = 0, G = 0, B = 0, A = 0 }

-- ring angle (degrees clockwise from the top) for a point of the day cycle (0 = dawn); ns is where night starts
local function FillToDeg(f, ns) return ((f - (ns + 1) / 2) * 360) % 360 end

-- Zoom: the [ and ] keys (main.lua). It lives in main.lua's settings file with the F8 settings (Attach below).
-- 2 is the addon's ZoomScale.
local ZOOM_MIN, ZOOM_MAX = 0.5, 32   -- 8 was not far enough out (in-game test, 27-09-2026)
function M.ZoomLevel() return M.Zoom or 2 end
function M.ZoomBy(factor) M.PendingZoom = (M.PendingZoom or 1) * factor end   -- key handlers: applied in Tick

local function SaveZoom(z) M.Store.zoom = z M.Save() end
local function ApplyZoom(ctx)
    local z = math.max(ZOOM_MIN, math.min(ZOOM_MAX, M.ZoomLevel() * M.PendingZoom))
    M.PendingZoom = false
    M.Zoom = z
    pcall(function() M.View:SetZoomScale(z) end)
    SaveZoom(z)
end

-- The F8 settings (1.1). Map: off means the mod does not build the map at all, which hiding it in F9 still does
-- (playtest, 29-09-2026). North: the map faces north instead of turning with the camera. Mark: the north mark on
-- the ring. Smooth: the map draws every frame instead of every second one. Neutral: the green diamonds of neutral
-- creatures (hidden on request, 29-09-2026). Ore, Herbs, Essence, Trees: the resource icons (resources.lua).
-- The key handlers in main.lua only flip these and set Dirty; Tick applies and saves them. They and the zoom are kept
-- in main.lua's settings file: Store is its [map] section, Save writes the file (Attach, called once at start).
-- neutral creatures start hidden: they take room on the map (29-09-2026)
local SETTING_START = { Map = true, North = false, Mark = true, Smooth = false, Neutral = false, Ore = true, Herbs = true,
    Essence = true, Trees = true }
M.Set = {}
for k, v in pairs(SETTING_START) do M.Set[k] = v end
M.Store, M.Save = {}, function() end
function M.Attach(store, save)
    M.Store, M.Save = store, save
    for k in pairs(SETTING_START) do
        if store[k] ~= nil then M.Set[k] = (tonumber(store[k]) == 1) end
    end
    local z = tonumber(store.zoom)
    M.Zoom = z and math.max(ZOOM_MIN, math.min(ZOOM_MAX, z)) or 2   -- a hand-edited file stays in range
end
local function SaveSettings()
    for k in pairs(SETTING_START) do M.Store[k] = M.Set[k] and 1 or 0 end
    M.Save()
end
-- Backspace in F8, from a key handler: only a flag; Tick does the rest
function M.Reset() M.ResetWanted = true end

local Logged = {}
local function Once(ctx, key, msg)
    if Logged[key] then return end
    Logged[key] = true
    ctx.Log(msg)
end

local function Obj(path) return StaticFindObject(path) end

local function LocalController()
    for _, P in pairs(FindAllOf("DominionPlayerController") or {}) do
        local ok, yes = pcall(function()
            return P:IsValid() and not string.find(P:GetFullName(), "Default__", 1, true) and P:IsLocalController()
        end)
        if ok and yes then return P end
    end
end

-- A round Image: filled disc and/or outline, drawn by the brush itself (RoundedBox), inside a SizeBox
local function Disc(tree, name, size, fill, outline, width)
    local img = StaticConstructObject(Obj("/Script/UMG.Image"), tree, FName(name))
    local b = img.Brush
    b.DrawAs = 4   -- RoundedBox
    b.ImageSize = { X = size, Y = size }
    b.TintColor = { SpecifiedColor = fill, ColorUseRule = 0 }
    b.OutlineSettings.RoundingType = 1   -- half height radius: a circle
    b.OutlineSettings.Width = width or 0
    b.OutlineSettings.Color = { SpecifiedColor = outline or NONE, ColorUseRule = 0 }
    img:SetBrush(b)
    local box = StaticConstructObject(Obj("/Script/UMG.SizeBox"), tree, FName(name .. "Box"))
    box:SetWidthOverride(size)
    box:SetHeightOverride(size)
    box:SetContent(img)
    return box, img
end

-- Pictures drawn by tools/make-runemap-art.js: the day band, the time arrow, the north arrow and the diamonds. Smooth, where
-- rings of small pieces came out jagged (in-game test, 27-09-2026). The band assumes the game's night
-- start of 0.795. The pictures ship with the mod; a missing one is logged and left out.
local ART_DIR = "ue4ss/Mods/RuneUI/Art/"
local ART_NIGHT_START = 0.795
-- The time arrow (1.5, sizes picked live in the game on 02-10-2026): 13 x 19 units seen, between the two gold rings
-- and a little over both; a smaller one that stayed inside the band was "super tiny". It points out.
local NEEDLE_W, NEEDLE_H = 14.3, 21.5
local R_NEEDLE = D / 2 + 9.5
-- The north arrow: from the inner gold ring out past the outer one, so it is the biggest mark on the ring.
local R_NORTH, NORTH_SIZE = D / 2 + 14, 26
-- The camera's yaw at which north is at the top of the ring. The view needs InheritedYawOffset 90 to put the
-- camera's forward at the top, so the map's own top (north on the big map) is yaw -90. Checked in game by
-- playtest, 29-09-2026: the mark and "Faces north" agree with the big map (M).
local NORTH_YAW = -90

local function LoadArt(ctx, name)
    local f = io.open(ART_DIR .. name, "rb")
    if not f then Once(ctx, "art" .. name, "runemap: picture missing: " .. ART_DIR .. name) return nil end
    f:close()
    local KRL = Obj("/Script/Engine.Default__KismetRenderingLibrary")
    local ok, tex = pcall(function() return KRL:ImportFileAsTexture2D(M.PC or FindFirstOf("GameInstance"), ART_DIR .. name) end)
    if ok and tex and tex:IsValid() then return tex end
    Once(ctx, "art" .. name, "runemap: picture not loaded: " .. name .. " " .. tostring(tex))
end

local function Picture(tree, name, tex, size)
    local img = StaticConstructObject(Obj("/Script/UMG.Image"), tree, FName(name))
    img:SetBrushFromTexture(tex, false)
    local b = img.Brush
    b.ImageSize = { X = size, Y = size }
    img:SetBrush(b)
    return img
end

local function AddCentred(ov, w)
    local s = ov:AddChildToOverlay(w)
    s:SetHorizontalAlignment(2)
    s:SetVerticalAlignment(2)
    return s
end

local function AddFilling(ov, w)
    local s = ov:AddChildToOverlay(w)
    s:SetHorizontalAlignment(0)
    s:SetVerticalAlignment(0)
    return s
end

local function Place(canvas, w, x, y, wd, ht)
    local s = canvas:AddChildToCanvas(w)
    s:SetAutoSize(false)
    s:SetSize({ X = wd, Y = ht })
    s:SetPosition({ X = x - wd / 2, Y = y - ht / 2 })
    return s
end

local function OnRing(r, deg)
    local a = math.rad(deg)
    return C + r * math.sin(a), C - r * math.cos(a)
end

---------------------------------------------------------------- the map itself

local function MakeView(ctx, pawn)
    local cls = Obj(VIEW_CLASS)
    if not (cls and cls:IsValid()) then error("no map view class") end
    -- made unattached, so this transform is in the world: it starts on the player's body
    local P = pawn:K2_GetActorLocation()
    local T = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = P.X, Y = P.Y, Z = P.Z }, Scale3D = { X = 1, Y = 1, Z = 1 } }
    local comp = pawn:AddComponentByClass(cls, true, T, false)
    if not (comp and comp:IsValid()) then error("AddComponentByClass gave nothing") end
    -- on the camera arm, so the map turns with the camera. The arm puts its children at its far end, by the
    -- camera: snapped there, the view sat 700 units from the player and the arrow was off the centre (test of
    -- 27-09-2026). So the place is kept (it stays on the body as the arm turns) and only the turn is taken.
    -- ponytail: the arm shortens near walls; the view is then off by that much until the next build.
    local okA, errA = pcall(function()
        comp:K2_AttachToComponent(pawn.CameraBoom, FName("None"), 1, 2, 2, false)
    end)
    if not okA then ctx.Log("runemap: attach failed: " .. tostring(errA)) end
    for k, v in pairs(VIEW_SETTINGS) do pcall(function() comp[k] = v end) end
    if M.Set.North then pcall(function() comp.RotationMode = 0 end) end   -- F8: faces north
    -- HeightProxy tells the view how high the player stands, which picks the floor of terrain to draw.
    -- Without it the terrain parts arrive (test of 27-09-2026) but nothing is drawn. It is the player's own
    -- body, but only if it is the kind the property holds (a wrong kind of object in an object property
    -- could crash the engine).
    pcall(function()
        if comp.HeightProxy and comp.HeightProxy:IsValid() then return end
        local want = nil
        comp:GetClass():ForEachProperty(function(p)
            pcall(function() if p:GetFName():ToString() == "HeightProxy" then want = p:GetPropertyClass() end end)
        end)
        if not want then return end
        for _, candidate in ipairs({ pawn.RootComponent, pawn }) do
            if candidate and candidate:IsValid() and candidate:IsA(want) then comp.HeightProxy = candidate break end
        end
    end)
    pcall(function() comp:SetZoomScale(M.ZoomLevel()) end)
    return comp
end

-- The terrain pictures. The level hands them to the maps that exist when it loads; ours comes later and got
-- none (first test: icons and labels, but a plain brown map). Later the plugin adds them itself; ours are added
-- only when the map still has none at its first set-up (SetUpAgain).
-- The kind of object AddMapBackground takes, read from the function itself (the second test showed that
-- /Script/MinimapPlugin.MapBackgroundComponent does not exist, so the name is not guessed any more).
local function BackgroundClass(ctx)
    local fn = Obj(MAP_CLASS .. ":AddMapBackground")
    if not (fn and fn:IsValid()) then ctx.Log("runemap: no AddMapBackground function") return nil end
    local want = nil
    fn:ForEachProperty(function(p)
        pcall(function()
            if p:GetClass():GetFName():ToString() == "ObjectProperty" then want = want or p:GetPropertyClass() end
        end)
    end)
    -- the read above failed once (test of 27-09-2026), and then nothing was added; an earlier test had read
    -- the kind as MapBackground, so look it up by that name
    if not want then
        local byName = Obj("/Script/MinimapPlugin.MapBackground")
        if byName and byName:IsValid() then want = byName end
    end
    return want
end

-- Everything that can hold background parts: the game's map tracker
local function BackgroundLists()
    local lists = {}
    pcall(function()
        local lib = Obj("/Script/MinimapPlugin.Default__MapFunctionLibrary")
        local tracker = lib:GetMapTracker(FindFirstOf("GameInstance"))
        tracker:GetClass():ForEachProperty(function(p)
            pcall(function()
                local name = p:GetFName():ToString()
                if string.find(string.lower(name), "background", 1, true) then
                    table.insert(lists, { "tracker " .. name, tracker[name] })
                end
            end)
        end)
    end)
    return lists
end

local function AddBackgrounds(ctx, map)
    local want = BackgroundClass(ctx)
    local seen, added, firstErr = {}, 0, nil
    -- the pieces the map already holds are skipped: every set-up added them again (2 pieces, 6 on the map after two
    -- set-ups, 29-09-2026), and the map worked through every copy
    local held = 0
    pcall(function()
        map.Backgrounds:ForEach(function(_, e)
            local b = e:get()
            if b and b:IsValid() then seen[b:GetFullName()] = true held = held + 1 end
        end)
    end)
    -- only a live object of exactly the kind the function takes goes in: a wrong one could crash the game
    local function Try(item)
        if not (item and item:IsValid()) then return end
        local n = item:GetFullName()
        if seen[n] or string.find(n, "_GEN_VARIABLE", 1, true) or string.find(n, "Default__", 1, true) then return end
        -- still no kind: the lists hold background parts (BP_MapBackground_C in the tracker), so take the kind of
        -- the first one whose class says so
        if not want and string.find(item:GetClass():GetFName():ToString(), "MapBackground", 1, true) then
            want = item:GetClass()
        end
        if not (want and item:IsA(want)) then return end
        seen[n] = true
        local ok, err = pcall(function() map:AddMapBackground(item) end)
        if ok then added = added + 1 elseif not firstErr then firstErr = tostring(err) end
    end
    for _, L in ipairs(BackgroundLists()) do
        -- not every property named "background" is a list; those fail here and are skipped
        pcall(function()
            L[2]:ForEach(function(a, b)
                for _, p in ipairs({ a, b }) do   -- an array gives index and item, a map gives key and value
                    if type(p) == "userdata" then
                        local item = nil
                        pcall(function() item = p:get() end)
                        pcall(Try, item)
                    end
                end
            end)
        end)
    end
    if not want then ctx.Log("runemap: no background kind found, nothing added") return end
    local wantName = want:GetFName():ToString()
    -- and every live one in the world
    for _, c in pairs(FindAllOf(wantName) or {}) do
        if string.find(c:GetFullName(), ":PersistentLevel.", 1, true) then pcall(Try, c) end
    end
    ctx.Log(string.format("runemap: backgrounds added %d, %d already on the map (%s)%s", added, held, wantName,
        firstErr and (", first error: " .. firstErr) or ""))
end

local function MakeMap(ctx, PC, view)
    local cls = ctx.Asset(MAP_CLASS)
    if not (cls and cls:IsValid()) then error("minimap class not loaded; open the M map once") end
    local WBL = Obj("/Script/UMG.Default__WidgetBlueprintLibrary")
    local map = WBL:Create(PC, cls, PC)
    if not (map and map:IsValid()) then error("Create gave nothing") end
    for k, v in pairs(MAP_SETTINGS) do pcall(function() map[k] = v end) end
    local okV, errV = pcall(function() map:SetMapView(view) end)
    if not okV then ctx.Log("runemap: SetMapView failed: " .. tostring(errV)) end
    -- no terrain of ours here: the map plugin adds the pieces itself within a second, and ours were a second copy
    -- (log of 29-09-2026). SetUpAgain adds ours only if the map still has none.
    -- the addon calls these after SetMapView; the first test (without them) stayed on "waiting for map view"
    local calls = {
        -- fog off: ours has no record of where the player has been, so the fog covered the whole map and it
        -- stayed grey (F7 test of 27-09-2026)
        { "ShowFog", function() map:ShowFog(false) end },
        { "ReinitShape", function() map:ReinitShape() end },
        { "RetryMapSize", function() map:RetryMapSize() end },
        { "BroadcastMapView", function() map:BroadcastMapView() end },
        { "ForceLayoutPrepass", function() map:ForceLayoutPrepass() end },
    }
    for _, c in ipairs(calls) do
        local ok, err = pcall(c[2])
        if not ok then ctx.Log("runemap: " .. c[1] .. " failed: " .. tostring(err)) end
    end
    return map
end

---------------------------------------------------------------- the ring

local function BuildRing(ctx, tree, map)
    local ov = StaticConstructObject(Obj("/Script/UMG.Overlay"), tree, FName("RU_MapStack"))
    pcall(function()
        AddCentred(ov, (Disc(tree, "RU_MapBack", D + 34, DARK)))
    end)
    M.BandNS = nil
    local bandTex = LoadArt(ctx, "runemap_band_clear.png")   -- the day fades out (chosen 27-09-2026)
    if bandTex then
        local bb = StaticConstructObject(Obj("/Script/UMG.SizeBox"), tree, FName("RU_MapBandBox"))
        bb:SetWidthOverride(BOX)
        bb:SetHeightOverride(BOX)
        bb:SetContent(Picture(tree, "RU_MapBandArt", bandTex, BOX))
        AddCentred(ov, bb)
    end
    -- the rings are kept: their outline ignores the widget's opacity, so the F9 opacity is set on them too
    local okR, errR = pcall(function()
        local box
        box, M.RingOut = Disc(tree, "RU_MapRingOut", D + 34, NONE, GOLD, 2.5)
        AddCentred(ov, box)
        box, M.RingIn = Disc(tree, "RU_MapRingIn", D + 4, NONE, GOLD, 2)
        AddCentred(ov, box)
    end)
    if not okR then ctx.Log("runemap: gold rings not drawn: " .. tostring(errR)) end
    local mb = StaticConstructObject(Obj("/Script/UMG.SizeBox"), tree, FName("RU_MapBox"))
    mb:SetWidthOverride(D)
    mb:SetHeightOverride(D)
    -- The game's map widget cost about 20 FPS at any zoom (28-09-2026). A retainer box draws it into a picture
    -- every second frame and shows that picture in between: about 10 FPS back, a little less smooth (the chosen default).
    -- F8 "Smooth" turns the retainer off, so the map draws every frame again (see ApplySettings).
    local okRB, errRB = pcall(function()
        local rb = StaticConstructObject(Obj("/Script/UMG.RetainerBox"), tree, FName("RU_MapRetainer"))
        rb:SetRenderingPhase(0, 2)
        rb:SetContent(map)
        mb:SetContent(rb)
        M.Retainer = rb
    end)
    if okRB then ctx.Log("runemap: drawn every second frame") else
        ctx.Log("runemap: retainer box failed, drawn every frame: " .. tostring(errRB))
        mb:SetContent(map)
    end
    AddCentred(ov, mb)
    -- diamonds from the menu's trim on the left, right and bottom; the needle on top of everything
    local top = StaticConstructObject(Obj("/Script/UMG.CanvasPanel"), tree, FName("RU_MapMarks"))
    AddFilling(ov, top)
    local diaTex = LoadArt(ctx, "runemap_diamond.png")
    if diaTex then
        for _, deg in ipairs({ 90, 180, 270 }) do
            local x, y = OnRing(R_DIAMOND, deg)
            Place(top, Picture(tree, "RU_MapDiamond" .. deg, diaTex, DIAMOND), x, y, DIAMOND, DIAMOND)
        end
    end
    -- the creature diamonds: hidden pictures here hold them, so the engine keeps them while map icons use them
    M.EnemyTex, M.NeutralTex = LoadArt(ctx, "creature_enemy.png"), LoadArt(ctx, "creature_neutral.png")
    -- and the resource shapes (resources.lua), held the same way
    M.ResTex = { Ore = LoadArt(ctx, "resource_ore.png"), Herbs = LoadArt(ctx, "resource_herb.png"),
        Essence = LoadArt(ctx, "resource_essence.png"), Trees = LoadArt(ctx, "resource_tree.png") }
    for i, t in ipairs({ M.EnemyTex or false, M.NeutralTex or false, M.ResTex.Ore or false, M.ResTex.Herbs or false,
        M.ResTex.Essence or false, M.ResTex.Trees or false }) do
        if t then
            local keep = Picture(tree, "RU_MapKeep" .. i, t, 1)
            keep:SetVisibility(1)   -- collapsed
            AddCentred(ov, keep)
        end
    end
    -- the north mark (1.1; since 1.5 an arrow with the N cut into it); under the time arrow
    local northTex = LoadArt(ctx, "runemap_north.png")
    if northTex then
        local okM, errM = pcall(function()
            M.NorthImg = Picture(tree, "RU_MapNorth", northTex, NORTH_SIZE)
            M.NorthSlot = Place(top, M.NorthImg, C, C - R_NORTH, NORTH_SIZE, NORTH_SIZE)
        end)
        if not okM then ctx.Log("runemap: north mark not drawn: " .. tostring(errM)) end
    end
    -- the clock hand: a gold arrow on the day band that points out. Chosen over the sun and the moon twice
    -- (design sketch, 27-09-2026, and live in the game, 02-10-2026: a spark and a sun were tried, "arrow was better")
    local needleTex = LoadArt(ctx, "runemap_needle.png")
    if needleTex then
        local okN, errN = pcall(function()
            local img = StaticConstructObject(Obj("/Script/UMG.Image"), tree, FName("RU_MapNeedle"))
            img:SetBrushFromTexture(needleTex, false)
            local b = img.Brush
            b.ImageSize = { X = NEEDLE_W, Y = NEEDLE_H }
            img:SetBrush(b)
            M.NeedleImg = img
            M.NeedleSlot = Place(top, img, C, C - R_NEEDLE, NEEDLE_W, NEEDLE_H)
        end)
        if not okN then ctx.Log("runemap: needle not drawn: " .. tostring(errN)) end
    end
    return ov
end

---------------------------------------------------------------- the time of day, read from the game's own dial

function M.ReadClock(ctx)
    local DN = ctx.ById("daynight").Instances[1]   -- main.lua finds it every 2 s; no scan of our own
    if not (DN and DN:IsValid()) then return nil end
    local root = DN.WidgetTree.RootWidget
    local bar, cursor = root:GetChildAt(0), root:GetChildAt(1)
    local angle = cursor.RenderTransform.Angle
    local vals = {}
    pcall(function()
        bar.Brush.ResourceObject.ScalarParameterValues:ForEach(function(_, e)
            local p = e:get()
            vals[p.ParameterInfo.Name:ToString()] = p.ParameterValue
        end)
    end)
    -- the share of the day gone; the pointer's angle is the same share of 360 degrees (first test)
    local fill = vals["Fill Amount"] or (angle / 360)
    local ns = math.max(0.15, math.min(0.9, vals["Night Start"] or NIGHT_START))
    return fill % 1, ns
end

---------------------------------------------------------------- F8 settings, the north mark and the opacity

-- handles into the ring of the last build, dropped with it
local function DropParts()
    M.NorthSlot, M.NorthImg, M.RingOut, M.RingIn, M.Retainer = nil, nil, nil, nil, nil
    M.Applied, M.LastNorth, M.Op = nil, nil, nil
    M.TerrainAt = nil   -- a new map notes its own count (SetUpAgain)
    M.CreatureWay = nil -- and tries the first way to find creatures again: one failure must not hold for the world
end

-- the F8 settings onto the live map: when one changed, and once after each build
local function ApplySettings(ctx)
    local S = M.Set
    local key = (S.North and 1 or 0) + (S.Mark and 2 or 0) + (S.Smooth and 4 or 0)
    if key == M.Applied then return end
    M.Applied = key
    local okV = pcall(function() M.View.RotationMode = S.North and 0 or 1 M.Map:BroadcastMapView() end)
    -- smooth: no retainer, the map draws every frame; the older call if this UE has no switch
    local okR = M.Retainer and pcall(function() M.Retainer:SetRetainRendering(not S.Smooth) end)
    if M.Retainer and not okR then pcall(function() M.Retainer:SetRenderingPhase(0, S.Smooth and 1 or 2) end) end
    if M.NorthImg then pcall(function() M.NorthImg:SetVisibility(S.Mark and 3 or 1) end) end
    M.LastNorth = nil
    ctx.Log(string.format("runemap: faces north %s%s, north mark %s, %s", tostring(S.North), okV and "" or " (not set)",
        tostring(S.Mark), S.Smooth and "drawn every frame" or "drawn every second frame"))
end

-- The mark slides round the ring as the camera turns, and turns with its place, so it points out: the view sits on the camera arm, so its yaw is the
-- camera's. Facing north, the map's top is north, so the mark stays at the top.
local function UpdateNorth()
    if not (M.NorthSlot and M.Set.Mark) then return end
    local deg = 0
    if not M.Set.North then
        local ok, yaw = pcall(function() return M.View:K2_GetComponentRotation().Yaw end)
        if not ok or type(yaw) ~= "number" then return end
        deg = (NORTH_YAW - yaw) % 360
    end
    if M.LastNorth and math.abs(deg - M.LastNorth) < 0.5 then return end
    M.LastNorth = deg
    local x, y = OnRing(R_NORTH, deg)
    M.NorthSlot:SetPosition({ X = x - NORTH_SIZE / 2, Y = y - NORTH_SIZE / 2 })
    M.NorthImg:SetRenderTransformAngle(deg)
end

-- The F9 opacity. The whole map through its user widget, which leaves the editor's blinking (render opacity)
-- alone; the gold rings by their own colour, since outlines ignore the widget's opacity (LEARNINGS, 28-09-2026).
-- The immersive mode's fade comes in here too (ctx.Fade), for the same reason.
local function ApplyOpacity(ctx)
    local op = (ctx.ById("runemap").Opacity or 1) * ctx.Fade()
    if op == M.Op then return end
    M.Op = op
    pcall(function() M.UW:SetColorAndOpacity({ R = 1, G = 1, B = 1, A = op }) end)
    for _, img in ipairs({ M.RingOut or false, M.RingIn or false }) do
        if img then
            pcall(function()
                local b = img.Brush
                b.OutlineSettings.Color = { SpecifiedColor = { R = GOLD.R, G = GOLD.G, B = GOLD.B, A = op }, ColorUseRule = 0 }
                img:SetBrush(b)
            end)
        end
    end
end

---------------------------------------------------------------- build and update

-- A second set-up once the map is on screen: the quest, bed and teleporter icons showed only after the
-- terrain was added again and the map set up again (second F7 test of 27-09-2026).
local function SetUpAgain(ctx)
    local map = M.Map
    local t0 = os.clock()
    -- ours only on a map with no terrain yet: every add made another copy of the same pieces (29-09-2026)
    local n = 0
    pcall(function() n = map.Backgrounds:GetArrayNum() end)
    if n == 0 then pcall(AddBackgrounds, ctx, map) end
    local t1 = os.clock()
    -- one call at a time, each timed (the log line below); they stop at the first that fails, as one call did
    local ok, err = pcall(function() map:ReinitShape() end)
    local t2 = os.clock()
    if ok then ok, err = pcall(function() map:RetryMapSize() end) end
    local t3 = os.clock()
    if ok then ok, err = pcall(function() map:ForceLayoutPrepass() end) end
    local t4 = os.clock()
    if not ok then ctx.Log("runemap: set up again failed: " .. tostring(err)) end
    -- The plugin adds the terrain pictures again each time the big map (M) opens: 2 more each visit, 12 after five
    -- (log of 29-09-2026), and the map draws every copy. The first set-up after a build notes how many there are;
    -- later ones take the extra copies (the newest, at the end) off the map's canvas. The plugin's Backgrounds array
    -- still grows by 2 a visit (small). ReinitShape and RetryMapSize ran on the trimmed canvas in game without a crash.
    pcall(function()
        local canvas = map.Canvas_Backgrounds
        local kids = canvas:GetChildrenCount()
        -- a count of 0 (terrain not there yet) is not noted: the next trim would take every picture off
        if not M.TerrainAt then if kids > 0 then M.TerrainAt = kids end return end
        for i = kids - 1, M.TerrainAt, -1 do canvas:GetChildAt(i):RemoveFromParent() end
        if kids > M.TerrainAt then Once(ctx, "terraincopies", "runemap: extra terrain copies taken off the map") end
    end)
    local ms = function(a, b) return (b - a) * 1000 end
    ctx.Log(string.format("runemap: set up again in %.1f ms (terrain %.1f, shape %.1f, size %.1f, layout %.1f, trim %.1f)",
        ms(t0, os.clock()), ms(t0, t1), ms(t1, t2), ms(t2, t3), ms(t3, t4), ms(t4, os.clock())))
end

local function Build(ctx)
    -- a new name on every build: the old widget may still exist under GameInstance, and making an object
    -- with the name of a live one makes the engine replace it in place, which can crash the game
    M.Builds = (M.Builds or 0) + 1
    M.Shown, M.Visible, M.LastDeg, M.NeedleSlot, M.NeedleImg = nil, nil, nil, nil, nil
    DropParts()
    local step = "player"
    local view = nil
    local ok, err = pcall(function()
        local PC = LocalController()
        if not PC then error("no local player controller") end
        local pawn = PC.Pawn
        if not (pawn and pawn:IsValid()) then error("no pawn") end
        M.PC = PC
        step = "view"
        view = MakeView(ctx, pawn)
        step = "map"
        local map = MakeMap(ctx, PC, view)
        step = "widget"
        local uw = StaticConstructObject(Obj("/Script/UMG.UserWidget"), FindFirstOf("GameInstance"), FName("RuneUIMap" .. M.Builds))
        local tree = StaticConstructObject(Obj("/Script/UMG.WidgetTree"), uw, FName("RuneUIMapTree"))
        uw.WidgetTree = tree
        local canvas = StaticConstructObject(Obj("/Script/UMG.CanvasPanel"), tree, FName("RU_MapCanvas"))
        tree.RootWidget = canvas
        local size = StaticConstructObject(Obj("/Script/UMG.SizeBox"), tree, FName("RU_MapSize"))
        size:SetWidthOverride(BOX)
        size:SetHeightOverride(BOX)
        step = "ring"
        size:SetContent(BuildRing(ctx, tree, map))
        local E = ctx.ById("runemap")
        local slot = canvas:AddChildToCanvas(size)
        slot:SetAutoSize(true)
        -- tied to the top right corner, so it stays there on a wide screen (Nexus, 29-09-2026); the spot is measured
        -- on a 16:9 screen, 1920 units wide
        slot:SetAnchors({ Minimum = { X = 1, Y = 0 }, Maximum = { X = 1, Y = 0 } })
        slot:SetPosition({ X = E.Center.X - BOX / 2 - 1920, Y = E.Center.Y - BOX / 2 })
        step = "screen"
        uw:AddToViewport(40)
        uw:SetVisibility(3)
        M.W, M.UW, M.Map, M.Pawn, M.View = size, uw, map, pawn, view
        M.SetUpAt = os.clock() + 1
    end)
    if ok then
        ctx.Log("runemap ready")
        M.Fails = 0
    else
        -- tried again 10 s later, 3 times at most in one round (as main.lua does for its parts). The view on the
        -- body goes first, or the next try adds a second one.
        pcall(function() if view and view:IsValid() then view:K2_DestroyComponent(view) end end)
        M.Fails, M.NextBuild = (M.Fails or 0) + 1, os.clock() + 10
        ctx.Log("runemap failed at step '" .. step .. "': " .. tostring(err))
    end
end

---------------------------------------------------------------- creatures on the map

-- Red diamonds for enemies, green for neutral animals. Each creature gets the map plugin's own icon, so the
-- plugin draws it in the right place every frame; the mod only adds icons and hides dead ones, every 2 s while
-- the map is on screen. (The MiniMap addon draws its diamonds from a native hook, which breaks with every game patch.)
local ICON_CLASS = "/Script/MinimapPlugin.MapIconComponent"
local CREATURE_SIZE = 8       -- used only when the icon has no default size to scale from
-- of the default size, which looked far too big; 0.6 was right at an icon scale of 0.54 (27-09-2026), so our icons
-- keep that size when the scale changes (the resources use the same)
local CREATURE_SHARE = 0.6 * 0.54 / ICON_SCALE
-- ponytail: neutral by the creature's class name; switch to the game's own flag if one is found
local NEUTRAL = { "Deer", "Stag", "Rabbit", "Hare", "Chicken", "Sheep", "Cow", "Goat", "Frog", "Bird", "Fish", "Magpie", "Kebbit",
    "Critter", "Ambient", "Passive", "Squirrel" }
local Creatures = {}   -- full name -> { Icon, Shown }

local function IsNeutral(kind)
    for _, n in ipairs(NEUTRAL) do if string.find(kind, n, 1, true) then return true end end
    return false
end

local function Dead(A)
    local ok, v = pcall(function() return A:IsDead() end)
    if ok and type(v) == "boolean" then return v end
    local ok2, v2 = pcall(function() return A.bIsDead end)
    return ok2 and v2 == true
end

-- The creatures near the player (playtest, 29-09-2026: look only around the player). The walk through every object
-- the game holds (FindAllOf) took up to 30 ms (28-09-2026). The game's overlap query gives only the pawns within
-- CREATURE_RADIUS of the player. If UE4SS cannot make that call, the game's own list of creatures, then the walk.
-- The first way that works stays. Herbs and ore could be found the same way later.
local CREATURE_RADIUS = 10000   -- 100 m; 300 m crowded the map (playtest, 29-09-2026)
-- An out parameter from UE4SS 3.0.1: it fills the table passed in with the actors, 1 to n (log of 29-09-2026).
-- An element may come as the object or as a holder of it (e:get()).
local function OutActors(out)
    local list = {}
    for _, e in ipairs(out) do
        if pcall(function() return e:GetFullName() end) then list[#list + 1] = e
        else
            local ok, o = pcall(function() return e:get() end)
            if ok and o then list[#list + 1] = o end
        end
    end
    return list
end
local CREATURE_WAYS = {
    { "the overlap query", function(cls)
        local out = {}
        -- true when anything overlaps; then an empty table means UE4SS gave the list some other way
        local hit = Obj("/Script/Engine.Default__KismetSystemLibrary"):SphereOverlapActors(M.Pawn,
            M.Pawn:K2_GetActorLocation(), CREATURE_RADIUS, { 2 }, cls, {}, out)   -- 2: the pawn object type
        local list = OutActors(out)
        if hit == true and #list == 0 then error("an overlap, but no actors in the table") end
        return list
    end },
    { "the game's list", function(cls)
        local out = {}
        Obj("/Script/Engine.Default__GameplayStatics"):GetAllActorsOfClass(M.Pawn, cls, out)
        return OutActors(out)
    end },
    { "the walk", function() return FindAllOf("DominionAICharacter") or {} end },
}
local function NearCreatures(ctx)
    local cls = Obj("/Script/Dominion.DominionAICharacter")
    for i = M.CreatureWay or 1, #CREATURE_WAYS do
        local way = CREATURE_WAYS[i]
        local ok, list = pcall(function()
            if i < 3 and not (cls and cls:IsValid()) then error("no creature class") end
            return way[2](cls)
        end)
        if ok then
            if M.WayLogged ~= i then M.WayLogged = i ctx.Log("runemap: creatures found by " .. way[1]) end
            M.CreatureWay = i
            return list
        end
        ctx.Log("runemap: creatures by " .. way[1] .. " failed: " .. tostring(list))
        M.CreatureWay = i + 1
    end
    return {}
end

local function ScanCreatures(ctx)
    if not (M.EnemyTex and M.NeutralTex) then return end
    local cls = Obj(ICON_CLASS)
    if not (cls and cls:IsValid()) then Once(ctx, "iconclass", "runemap: no map icon class, no creatures") return end
    -- the editor's switch (they show at every zoom: wanted at the farthest one too, 27-09-2026). Hidden while
    -- the game's HUD is hidden: the big map (M) draws every map icon too, and there it showed every creature in
    -- the world, which reads like a radar (28-09-2026).
    local show = ctx.ById("creatures").Visible ~= false and M.Shown == true
    local seen, added = {}, 0
    for _, A in pairs(NearCreatures(ctx)) do
        pcall(function()
            local n = A:GetFullName()
            if not string.find(n, ":PersistentLevel.", 1, true) or string.find(n, "Default__", 1, true) then return end
            seen[n] = true
            local c = Creatures[n]
            if c and not c.Icon:IsValid() then Creatures[n], c = nil, nil end   -- its icon is gone: add a new one
            if not c then
                if added >= 8 then return end   -- a few per scan, so a crowd does not stall one frame
                added = added + 1
                local kind = A:GetClass():GetFName():ToString()
                local T = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = 0, Y = 0, Z = 0 }, Scale3D = { X = 1, Y = 1, Z = 1 } }
                local icon = A:AddComponentByClass(cls, false, T, false)
                -- no icon when the creature is being removed (log, 28-09-2026): try again on the next scan
                if not (icon and icon:IsValid()) then return end
                local neutral = IsNeutral(kind)
                local okT, errT = pcall(function() icon:SetIconTexture(neutral and M.NeutralTex or M.EnemyTex) end)
                if not okT then Once(ctx, "icontex", "runemap: creature icon picture failed: " .. tostring(errT)) end
                -- The plugin's own size unit is unknown: its default drew them far too big, 8 drew nothing
                -- (27-09-2026). So the size is a share of the icon's own default. SetIconSize takes two values
                -- ("expected 2 parameters"): width and height, or a size and a flag.
                local def = nil
                pcall(function() local s = icon.IconSize def = (type(s) == "number") and s or s.X end)
                local size = (def and def > 0) and def * CREATURE_SHARE or CREATURE_SIZE
                if not pcall(function() icon:SetIconSize(size, size) end) then
                    pcall(function() icon:SetIconSize(size, true) end)
                end
                c = { Icon = icon, Shown = nil, Neutral = neutral }
                Creatures[n] = c
            end
            local want = show and not Dead(A) and (M.Set.Neutral or not c.Neutral)   -- F8: enemies only
            if want ~= c.Shown and c.Icon:IsValid() then
                c.Shown = want
                pcall(function() c.Icon:SetIconVisible(want) end)
            end
        end)
    end
    -- out of reach or gone from the world: its icon goes too (a creature coming back would get a second one), and
    -- the handle is forgotten before the engine frees it
    for n, c in pairs(Creatures) do
        if not seen[n] then
            pcall(function() if c.Icon:IsValid() then c.Icon:K2_DestroyComponent(c.Icon) end end)
            Creatures[n] = nil
        end
    end
end

-- Take our icons off the creatures while the world still stands (a respawn, a new body): otherwise each
-- creature gets a second icon on the next scan, and the old ones stay, on dead creatures too.
local function DropCreatureIcons()
    for _, c in pairs(Creatures) do
        pcall(function() if c.Icon:IsValid() then c.Icon:K2_DestroyComponent(c.Icon) end end)
    end
    Creatures = {}
end

-- Leaving the world (quit to the main menu, a level change): drop every handle into it before the engine
-- frees the objects. A crash on quitting to the menu (27-09-2026) came from an old handle.
function M.Forget(sameWorld)
    -- a new world: no RemoveFromParent, the engine has already taken the old world's widgets off the screen,
    -- and touching ours then crashed the game (quit to the menu, 27-09-2026). A player restart in the same
    -- world: take our map off, or the next build puts a second one on top of it.
    if sameWorld and M.UW then pcall(function() M.UW:RemoveFromParent() end) end
    M.W, M.UW, M.Map, M.Pawn, M.View, M.PC = nil, nil, nil, nil, nil, nil
    M.Fails = 0
    M.EnemyTex, M.NeutralTex, M.ResTex = nil, nil, nil
    M.SetUpAt, M.NeedleSlot, M.NeedleImg, M.NextRes = nil, nil, nil, 0   -- a new world scans for resources at once
    DropParts()
    if sameWorld then DropCreatureIcons() else Creatures = {} end
    if M.Res then pcall(sameWorld and M.Res.Drop or M.Res.Forget) end
    M.CreatureWay, M.WayLogged = nil, nil   -- a way that failed while a world loaded gets a new try
end

-- Build only once the world is up: the HUD bars exist and the player has a body. Before that (main menu,
-- loading) it waits quietly instead of failing.
local function Ready(ctx)
    local V = ctx.ById("vitals").Instances[1]
    if not (V and V:IsValid()) then return false end
    -- the minimap class: loaded by the game once the M map was open, or by the mod (every 10 s at most)
    local cls = Obj(MAP_CLASS)
    if not (cls and cls:IsValid()) and os.clock() > (M.NextClassLoad or 0) then
        M.NextClassLoad = os.clock() + 10
        ctx.Log("runemap: loading the minimap class")
        cls = ctx.Asset(MAP_CLASS)
        ctx.Log("runemap: minimap class " .. (cls and "loaded" or "not loaded"))
    end
    if not (cls and cls:IsValid()) then
        Once(ctx, "class", "runemap: waiting for the minimap class; open the M map once")
        return false
    end
    local PC = LocalController()
    local pawn = PC and PC.Pawn
    return pawn and pawn:IsValid()
end

-- true when the player now has another body than the one our map view sits on
local function PawnChanged()
    -- a dead controller or body (quit to menu, level load) is never read, only checked
    if not (M.PC and M.PC:IsValid() and M.Pawn and M.Pawn:IsValid()) then return true end
    local ok, changed = pcall(function()
        local p = M.PC.Pawn
        return not (p and p:IsValid()) or p:GetFullName() ~= M.Pawn:GetFullName()
    end)
    return ok and changed
end

-- The map off the screen, with its view and the creature icons. Only while its world still stands (a new body in
-- the same world, or the map turned off); after a world change the engine has already taken it away.
local function TakeOff()
    if M.UW and M.PC and M.PC:IsValid() then
        pcall(function() M.UW:RemoveFromParent() end)
        -- the old body may stay (another body possessed): its map view goes too, or it keeps a second one.
        -- Not while the HUD is hidden: the big map (M) may be using our view then.
        if M.Shown ~= false then
            pcall(function() if M.View and M.View:IsValid() then M.View:K2_DestroyComponent(M.View) end end)
        end
        M.View = nil
        DropCreatureIcons()
        if M.Res then pcall(M.Res.Drop) end
    end
    M.UW, M.W = nil, nil
end

function M.Tick(ctx)
    if M.ResetWanted then
        M.ResetWanted = false
        for k, v in pairs(SETTING_START) do M.Set[k] = v end
        M.Zoom, M.PendingZoom, M.Dirty = 2, 1, true   -- the starting zoom; the map applies it
        SaveZoom(2)   -- saved now, also when the map cannot build
    end
    -- a switch in F8 shows at once; a held arrow key scans at most every 0.3 s (a scan costs a few ms)
    if M.Dirty then M.Dirty = false SaveSettings() M.NextRes = math.min(M.NextRes or 0, os.clock() + 0.3) end
    if not M.Set.Map then
        -- off in F8: nothing built, nothing searched. Turned on again, the build below runs as after a world change.
        if M.UW or M.W then TakeOff() M.Pawn, M.Map, M.Visible = nil, nil, nil ctx.Log("runemap: off") end
        if M.PendingZoom then ApplyZoom(ctx) end   -- the zoom keys still change the saved zoom
        M.Fails = 0
        return
    end
    if (M.Fails or 0) >= 3 then return end   -- three failed builds in this round
    if M.W and os.clock() > (M.NextPawnCheck or 0) then
        M.NextPawnCheck = os.clock() + 2
        if PawnChanged() then ctx.Log("runemap: the player has a new body, building again") M.Pawn = nil end
    end
    if not (M.W and M.W:IsValid() and M.Pawn and M.Pawn:IsValid()) then
        if os.clock() < (M.NextBuild or 0) then return end
        M.NextBuild = os.clock() + 2
        TakeOff()
        local okR, ready = pcall(Ready, ctx)
        if okR and ready then Build(ctx) end
        return
    end
    if M.PendingZoom then ApplyZoom(ctx) end
    ApplySettings(ctx)
    ApplyOpacity(ctx)
    if M.SetUpAt and os.clock() > M.SetUpAt then M.SetUpAt = nil SetUpAgain(ctx) end
    if M.Visible and os.clock() > (M.NextCreatures or 0) then
        -- every 2 s, around the player (NearCreatures); the plugin moves the icons itself
        M.NextCreatures = os.clock() + 2.0
        if ctx.ById("creatures").Visible == false then
            -- off: no icons and no search at all (the search ran with Creatures off too, 29-09-2026)
            if next(Creatures) then DropCreatureIcons() end
        else
            local okC, errC = pcall(ScanCreatures, ctx)
            if not okC then Once(ctx, "creatures", "runemap: creatures failed: " .. tostring(errC)) end
        end
    end
    -- ore, herbs, essence and rare trees (resources.lua): every 10 s; they do not move, only get used up. A scan
    -- cost 4 to 5 ms in the game (29-09-2026), too much every 3 s.
    if M.Res and M.Visible and os.clock() > (M.NextRes or 0) then
        M.NextRes = os.clock() + 10.0
        local okR, errR = pcall(M.Res.Scan, ctx, M)
        if not okR then Once(ctx, "resources", "runemap: resources failed: " .. tostring(errR)) end
    end
    -- hide with the game's HUD (menus, the big map)
    pcall(function()
        local V = ctx.ById("vitals").Instances[1]
        local shown = V and V:IsValid() and V:IsVisible()
        if shown ~= M.Shown then
            -- back from the big map: it had taken the map view over, and ours stayed empty (27-09-2026).
            -- Give our view back and set the map up again.
            if shown and M.Shown == false then
                local t0 = os.clock()
                pcall(function() M.Map:SetMapView(M.View) M.Map:BroadcastMapView() end)
                M.SetUpAt = os.clock() + 0.3
                ctx.Log(string.format("runemap: back from a menu, view given back in %.1f ms", (os.clock() - t0) * 1000))
            end
            M.Shown = shown
            -- the creature icons at once, not at the next scan: the big map must never show them
            if not shown then
                for _, c in pairs(Creatures) do
                    c.Shown = nil   -- the next scan decides again
                    pcall(function() if c.Icon:IsValid() then c.Icon:SetIconVisible(false) end end)
                end
                if M.Res then pcall(M.Res.HideAll) end
            end
        end
    end)
    -- Hidden in the editor: off the screen, not only see-through. The gold rings are outlines, and the game draws
    -- outlines at full strength inside a see-through parent: the rings stayed on screen (28-09-2026).
    -- Fully faded by the immersive mode: off the screen too, so the map costs no drawing and no scans (review of
    -- 29-09-2026); it fades through its colour only on the way out and back in.
    local visible = M.Shown == true and (ctx.ById("runemap").Visible or ctx.Editing()) and ctx.Fade() > 0
    if visible ~= M.Visible then
        -- shown again after a hidden stretch: set the map up again, as after the big map (the set-up needs a map on
        -- screen, and a collapsed one is not)
        if visible and M.Visible == false then M.SetUpAt = os.clock() + 0.3 end
        M.Visible = visible
        pcall(function() M.UW:SetVisibility(visible and 3 or 1) end)
    end
    if M.Visible then UpdateNorth() end   -- every step, not at the clock's 2 per second: it follows the camera
    if os.clock() < (M.NextClock or 0) then return end
    M.NextClock = os.clock() + 0.5
    local okC, fill, ns = pcall(M.ReadClock, ctx)
    if not okC then Once(ctx, "clock", "runemap: reading the clock failed: " .. tostring(fill)) return end
    if not fill then return end
    if ns ~= M.BandNS then
        if math.abs(ns - ART_NIGHT_START) > 0.01 then
            Once(ctx, "artns", "runemap: the game's night starts at " .. ns .. ", the band picture was drawn for " .. ART_NIGHT_START)
        end
        M.BandNS = ns
    end
    if not M.NeedleSlot then return end
    local deg = FillToDeg(fill, ns)
    if M.LastDeg and math.abs(deg - M.LastDeg) < 0.2 then return end
    M.LastDeg = deg
    local x, y = OnRing(R_NEEDLE, deg)
    M.NeedleSlot:SetPosition({ X = x - NEEDLE_W / 2, Y = y - NEEDLE_H / 2 })
    M.NeedleImg:SetRenderTransformAngle(deg)   -- the picture points up: out, when on top
end

-- for resources.lua (main.lua sets M.Res): the helpers it shares with the creatures
M.H = { Obj = Obj, OutActors = OutActors, IconClass = ICON_CLASS, Share = CREATURE_SHARE }

return M
