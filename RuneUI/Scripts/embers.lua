-- The sparks of a new item and of an unlock ("New recipes unlocked", "New structure unlocked"): both rows hold a
-- Niagara widget (NS_UI_NewItemFound, in the SizeBox "SizeBox_2" of the row's Overlay) that draws the system
-- NS_UI_ItemPickup with four emitters: Embers_Box, Smoke, Fuse_Top, Fuse_Bottom. The two Fuse emitters are the two
-- horizontal streaks; Embers_Box is a box of loose sparks around the row. Here Embers_Box is switched off on the
-- row's NiagaraUIComponent (proven in the game on the pick-up rows, 07-10-2026), once for each row, by its full name.
-- The Overlay's children come in a different order in the two rows, so the box is found by name.
-- Render opacity, translation and clipping do not touch these sparks. The component can be missing at first: the
-- look tries again on each later look, every look for TRIES looks, then every SLOW seconds.
-- pickups.lua and quests.lua call Quiet; main.lua loads this file with pcall and hands it to both.

local M = {}

local BOX, EMITTER = "SizeBox_2", "Embers_Box"
local KIDS = 12    -- the most children of the Overlay that are looked at
local TRIES = 20   -- looks, one after the other, that try again
local SLOW = 5     -- seconds between two tries after that

local function Ok(w) return w and w:IsValid() end

-- the row's NiagaraUIComponent; nil and the reason while it is not there
local function Component(row)
    local tree = row.WidgetTree
    local root = Ok(tree) and tree.RootWidget
    if not Ok(root) then return nil, "the row has no tree yet" end
    local overlay = root:GetChildAt(0)
    if not Ok(overlay) then return nil, "the row has no Overlay yet" end
    for i = 0, math.min(overlay:GetChildrenCount(), KIDS) - 1 do
        local box = overlay:GetChildAt(i)
        if Ok(box) and box:GetFName():ToString() == BOX then
            local sparks = box:GetChildAt(0)
            if not Ok(sparks) then return nil, BOX .. " holds no widget yet" end
            local comp = sparks:GetNiagaraComponent()
            if Ok(comp) then return comp end
            return nil, "the sparks widget has no component yet"
        end
    end
    return nil, "no " .. BOX .. " in the row"
end

-- the state of one part (pickups.lua, quests.lua): its rows by full name, and what it logged (each reason once)
function M.New() return { Rows = {}, Logged = {} } end

local function Once(ctx, st, key, msg)
    if not st.Logged[key] then st.Logged[key] = true ctx.Log(msg) end
end

-- Embers_Box off on this row, once; it returns nothing and tries again at the next look while the component is not valid. The label starts the log lines. One line
-- per world says it was set, and one for each reason says why a try did not.
function M.Quiet(ctx, st, label, row, key)
    local r = st.Rows[key]
    if r and (r.Done or os.clock() < r.Next) then return end
    r = r or { Tries = 0 }
    st.Rows[key] = r
    r.Tries = r.Tries + 1
    r.Next = os.clock() + (r.Tries < TRIES and 0 or SLOW)
    local ok, comp, why = pcall(Component, row)
    if ok and comp then
        ok, why = pcall(function() comp:SetEmitterEnable(FName(EMITTER), false) end)
        if ok then
            r.Done = true
            Once(ctx, st, "set", label .. ": " .. EMITTER .. " (the loose sparks) is off, the streaks stay")
            return
        end
    elseif not ok then why = comp end
    Once(ctx, st, "failed " .. tostring(why), label .. ": " .. EMITTER .. " is not off yet: " .. tostring(why))
end

return M
