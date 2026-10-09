-- Your name on the map: the map setting "Player name" (F8, key Name in runemap.lua) off hides the name that the game
-- prints beside your own marker, on RuneMap and on the big map (M).
-- The game draws a marker for each thing on a map, WBP_Dominion_MinimapInternal_Icon_C (the game's files, 1.0.0.5):
-- its IconLabel shows the text that its MapIconComp gives. Your marker is the one whose component has the picture of the
-- local player, T_NavIcons_Player_Self (other players get the friend arrow), so in co-op another player's name is never
-- touched, even under the same name. Seen in the game on 05-10-2026: 4 of 411 markers, size 40, the only ones with a name.
-- Not the owner of the component: it is not your body or your player state (matching on the owner found 0 of 775).
-- A marker whose component or picture cannot be read is not yours; one not set up yet is looked at again on the next scan.
-- Off: each scan finds your markers and gives their label render opacity 0, its own opacity kept (Orig). Opacity, not
-- visibility: the marker's blueprint sets the label's visibility itself (UpdateLabel, UpdateVisibility). On: nothing is
-- called; the switch back to on gives each label its opacity once.
-- The marker class comes from the mod's one widget search (finder.lua; ctx.Find is FindQuiet: runemap.lua adds markers
-- all the time, and a new one must not bring an early scan), and only while the switch is off.
-- A map that opens makes its markers new, and until the next scan (2 s at most) your name showed beside the arrow
-- (seen in the game, 05-10-2026). So the step also takes the markers that the game reports as made (ctx.Arrived, finder.lua's
-- Arrivals) and looks at them at once. The blueprint sets a marker's component after the widget is made, so one that
-- cannot be read yet is looked at again every LOOK_EVERY seconds, for LOOK_FOR seconds, MAX_LOOKS markers at a look
-- (a few small reads a marker, never the owner: see above). The ones not readable yet wait behind the ones not looked at
-- yet, so a crowd of them does not hold up a marker of yours. After that the scan has it.
-- main.lua loads this file with pcall and runs its Scan and its Tick.

local M = {}

local CLASS = "WBP_Dominion_MinimapInternal_Icon_C"
local SELF_PICTURE = "/Game/Art/UI/NavIcons/T_NavIcons_Player_Self.T_NavIcons_Player_Self"

local function Alive(o) return o and o:IsValid() end   -- a property or a call can give a wrapper of null: pcall does not catch it

-- full name -> { W, Addr, Own, Label, Orig }: each marker is looked at once; Orig is the label's opacity before ours
local Marks = {}
local WasOn = true
local LOOK_EVERY, LOOK_FOR, MAX_LOOKS = 0.1, 1.5, 100
local Waiting = {}   -- { W, At }: markers that the game made and that are not looked at yet, or cannot be read yet
local NextLook = 0
local Looks = 0      -- the first looks that did something are logged, with their cost
-- the first scans of a round are logged, with their cost: the first one can see only the markers of the last full
-- search, as the class is wanted from then on (finder.lua's FindClass)
local Scans = 0

-- the address of the player's own picture; nil while the game has not loaded it
local SelfAddr
local function SelfPicture()
    if SelfAddr then return SelfAddr end
    local ok, a = pcall(function()
        local t = StaticFindObject(SELF_PICTURE)
        if Alive(t) then return t:GetAddress() end
    end)
    if ok and a then SelfAddr = a end
    return SelfAddr
end

-- the verdict on one marker, or nil while its component or picture cannot be read yet
local function Look(W, selfAddr)
    local comp = W.MapIconComp
    if not Alive(comp) then return nil end
    local tex = comp.IconTexture
    if not Alive(tex) then return nil end
    local e = { W = W, Addr = W:GetAddress(), Own = tex:GetAddress() == selfAddr }
    if e.Own then
        e.Label = W.IconLabel
        if not Alive(e.Label) then e.Own, e.Label = false, nil end
    end
    return e
end

-- A label that reads 0 holds what we wrote, whose record was lost: the game's own opacity is 1.
local function Hide(e)
    if not Alive(e.Label) then return end
    local op = e.Label:GetRenderOpacity()
    if e.Orig == nil then e.Orig = op > 0 and op or 1 end
    if op ~= 0 then e.Label:SetRenderOpacity(0) end
end

-- one marker of the scan: its record, kept or made new, and whether it is yours. No closure: the scan reads some
-- hundred markers every 2 s, and a closure for each was garbage.
local function One(e, W, selfAddr)
    if e and not (Alive(e.W) and e.W:GetAddress() == W:GetAddress()) then e = nil end   -- a freed slot, another widget
    if not e then e = Look(W, selfAddr) end
    if e and e.Own then Hide(e) return e, true end
    return e, false
end

local function Scan(ctx)
    local selfAddr = SelfPicture()
    if not selfAddr then return end
    local t0 = os.clock()
    local list, keys = ctx.Find(CLASS)
    local kept, own = {}, 0
    for i, W in ipairs(list) do
        local key = keys[i]
        local ok, e, mine = pcall(One, Marks[key], W, selfAddr)
        if ok then
            kept[key] = e
            if mine then own = own + 1 end
        else
            kept[key] = Marks[key]   -- a read that failed: the record stays, with the opacity the switch puts back
        end
    end
    Marks = kept
    Scans = Scans + 1
    if Scans <= 3 then ctx.Log(string.format("map name: off, %d of %d markers are yours; %.1f ms", own, #list, (os.clock() - t0) * 1000)) end
end

-- The new markers (see the head of this file). Your own one is hidden and kept in Marks, as the scan does it.
local function Newcomers(ctx, arrived)
    local selfAddr = SelfPicture()
    if not selfAddr then return end
    local now = os.clock()
    for _, W in ipairs(arrived or {}) do Waiting[#Waiting + 1] = { W = W, At = now } end
    if #Waiting == 0 or now < NextLook then return end
    NextLook = now + LOOK_EVERY
    local t0, left, later, looked, hidden = os.clock(), {}, {}, 0, 0
    for i, w in ipairs(Waiting) do
        if i > MAX_LOOKS then
            left[#left + 1] = w
        else
            looked = looked + 1
            local again = false
            pcall(function()
                if not Alive(w.W) then return end
                local e = Look(w.W, selfAddr)
                if not e then again = now - w.At < LOOK_FOR return end
                if e.Own then
                    Hide(e)
                    hidden = hidden + 1
                    if Looks <= 5 then ctx.Log(string.format("map name: a new marker of yours hidden %.0f ms after the game made it", (now - w.At) * 1000)) end
                    Marks[w.W:GetFullName()] = e
                end
            end)
            if again then later[#later + 1] = w end   -- not readable yet: behind the ones never looked at
        end
    end
    for _, w in ipairs(later) do left[#left + 1] = w end
    Waiting = left
    if hidden > 0 or Looks < 3 then
        Looks = Looks + 1
        if Looks <= 5 then ctx.Log(string.format("map name: looked at %d new markers, %d yours; %.1f ms, %d still waiting", looked, hidden, (os.clock() - t0) * 1000, #Waiting)) end
    end
end

-- each label we hid gets its own opacity back
local function Restore(ctx)
    local n = 0
    for _, e in pairs(Marks) do
        if e.Orig ~= nil then
            pcall(function() if Alive(e.Label) then e.Label:SetRenderOpacity(e.Orig) n = n + 1 end end)
        end
    end
    Marks, Scans, Waiting = {}, 0, {}
    if n > 0 then ctx.Log("map name: on, your player name is back on " .. n .. " markers") end
end

-- The scan of every marker reads some hundred full names (finder.lua) and took up to 28 ms (measured 09-10-2026).
-- The new markers come through Newcomers at once, so the scan is the net under them and runs every SCAN_EVERY seconds,
-- not at every scan of the mod. The switch going off scans at once (Tick).
local SCAN_EVERY = 10
local NextScan = 0
function M.Scan(ctx)
    local now = os.clock()
    if ctx.On() or now < NextScan then return end
    NextScan = now + SCAN_EVERY
    Scan(ctx)
end

-- only the change of the switch: off looks at once (no wait for the scan), on puts the labels back once
function M.Tick(ctx)
    local on = ctx.On()
    local arrived = ctx.Arrived(CLASS)   -- taken at every step, whatever the switch says: finder.lua keeps no list for us
    if on ~= WasOn then
        WasOn = on
        if on then Restore(ctx) else Scan(ctx) end
    end
    if not on then Newcomers(ctx, arrived) end
end

-- A new world: the old markers are gone, so nothing is called on them, and the picture is found again. A player restart:
-- the markers may still stand, and the records are what the switch puts back (each is checked by its address on the next scan).
function M.Forget(sameWorld)
    if not sameWorld then Marks, SelfAddr = {}, nil end
    Waiting, Scans, Looks, NextScan = {}, 0, 0, 0
end

return M
