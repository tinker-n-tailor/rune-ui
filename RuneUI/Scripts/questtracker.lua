-- Quest tracker under the minimap, at the top right: the main quest and the side quest tracked in the journal.
-- Each has a small label, the name in gold and the step in white. With "Show next steps" on, a quest with a clean
-- list of steps also shows up to 3 steps after the current one, dimmed.
-- No background panel: the thin gold line of the XP bar on top, and the letters with the HUD's shadow.
-- While the game's quest and unlock notice plays under the map, the tracker is off the screen (ctx.Popup).
-- The data is read only (probe of 04-10-2026); a UFunction of the quest component is never called. The local
-- controller has the property BP_Components_QuestProgress. In it, Quests is a list of { Data, State, CurrentObjective }
-- and TrackedSecondaryQuest is the quest tracked in the journal. State: 0 not started, 1 open, 2 finished (read from
-- one save). Data (QuestData) has QuestName, bIsMainQuest, bHideInQuestList and ObjectiveTexts, a map of step key to
-- step text, in the order held. The step is ObjectiveTexts[CurrentObjective]. "None" is a real key. A key with no
-- text gives the name only.
-- main.lua moves and sizes it as the F9 element "questtracker" and loads this file with pcall, so an error here leaves
-- the rest of the mod running.

local M = {}

local NEXT_MAX = 3                     -- next steps shown under the current one
M.BOX_W, M.BOX_H = 300, 110            -- the box F9 moves and sizes; the text is right-aligned in it, from the top
local LINE_H = 9                       -- the gold line, as thick as the line under the bars
local GAP = 10                         -- units between the line and a block, and between the blocks

local GOLD = { R = 1.0, G = 0.638, B = 0.168, A = 1.0 }      -- the pick-up count's gold (pickups.lua)
local WHITE = { R = 1, G = 1, B = 1, A = 1 }
local DIM = { R = 1, G = 1, B = 1, A = 0.55 }
local OFFSET, SHADE = { X = 1.5, Y = 1.5 }, { R = 0, G = 0, B = 0, A = 0.85 }   -- the letters' shadow (letters.lua)
local SIZE = { Label = 9, Name = 14, Step = 12, Next = 10 }
local LABEL = { Main = "Main quest", Tracked = "Tracked" }

---------------------------------------------------------------- what to show, without the game (tools/test-questtracker.js)

local function Trim(s) return (string.match(s or "", "^%s*(.-)%s*$")) end

-- quests: { Id, Title, State, Step, Main, Hidden }, in the order of the game's list; trackedId: the name of the quest
-- tracked in the journal, or nil. The main quest: the first open one that the journal does not hide. The tracked one:
-- open, not hidden, and not the main one.
function M.Pick(quests, trackedId)
    local main
    for _, q in ipairs(quests) do
        if q.Main and q.State == 1 and not q.Hidden then main = q break end
    end
    local tracked
    if trackedId then
        for _, q in ipairs(quests) do
            if q.Id == trackedId then
                if q.State == 1 and not q.Hidden and q ~= main then tracked = q end
                break
            end
        end
    end
    return main, tracked
end

-- steps: { Key, Text } in the order held. The text of one step; nil when the key is not there or its text is empty.
function M.StepText(steps, key)
    for _, s in ipairs(steps) do
        if s.Key == key then
            local t = Trim(s.Text)
            return t ~= "" and t or nil
        end
    end
end

-- A list of steps is clean when its order can be trusted: no key with a dot, the keys "ObjectiveN" are Objective1,
-- Objective2 ... in order with no letter, no text holds a count ("0/3": the game has one step for each count), no text
-- starts with "[" ("[TEMP]"), and no two steps have the same text. A guess from one save: a list can pass and still
-- be in the wrong order.
function M.IsClean(steps)
    local seen, n = {}, 0
    for _, s in ipairs(steps) do
        local text = Trim(s.Text)
        if string.find(s.Key, ".", 1, true) or string.find(text, "%d+/%d+") or string.sub(text, 1, 1) == "[" or seen[text] then
            return false
        end
        seen[text] = true
        local num = string.match(s.Key, "^Objective(.*)$")
        if num then
            n = n + 1
            if num ~= tostring(n) then return false end
        end
    end
    return true
end

-- The texts of up to limit steps after the step with this key. None when the list is not clean or has no such key.
function M.NextSteps(steps, key, limit)
    local out = {}
    if not M.IsClean(steps) then return out end
    local at
    for i, s in ipairs(steps) do if s.Key == key then at = i break end end
    if not at then return out end
    for i = at + 1, #steps do
        if #out >= limit then break end
        local t = Trim(steps[i].Text)
        if t ~= "" then out[#out + 1] = t end
    end
    return out
end

-- One quest as it shows: { Title, Step, Next }. Step is nil when the game has no text for the step; the name stays.
function M.Describe(q, steps, showNext)
    local step = M.StepText(steps, q.Step)
    return { Title = q.Title ~= "" and q.Title or q.Id, Step = step,
        Next = showNext and step and M.NextSteps(steps, q.Step, NEXT_MAX) or {} }
end

-- What changes the tracker: the quest, its state and its step, for both blocks. The immersive mode wakes on a change.
function M.SigOf(main, tracked)
    local function part(q) return q and (q.Id .. ":" .. q.State .. ":" .. q.Step) or "-" end
    return part(main) .. "|" .. part(tracked)
end

---------------------------------------------------------------- the game

local function Obj(path) return StaticFindObject(path) end
local function New(cls, outer, name) return StaticConstructObject(Obj("/Script/UMG." .. cls), outer, FName(name)) end
local Logged = {}
local function Once(ctx, key, msg) if not Logged[key] then Logged[key] = true ctx.Log(msg) end end

-- One block's texts: a label, the name, the step and the next steps, right-aligned and wrapping at the box's width.
local function Block(ctx, tree, i)
    local n = "RU_Qt" .. i
    local box = New("VerticalBox", tree, n)
    local function Line(name, size, color, top)
        local T = ctx.Text(tree, n .. name, size, color, "")
        pcall(function() T:SetShadowOffset(OFFSET) end)
        pcall(function() T:SetShadowColorAndOpacity(SHADE) end)
        pcall(function() T:SetJustification(2) end)   -- right
        pcall(function() T:SetAutoWrapText(true) end)
        T:SetVisibility(1)
        local s = box:AddChildToVerticalBox(T)
        s:SetHorizontalAlignment(0)   -- fill: the text is right-aligned inside it
        s:SetPadding({ Left = 0, Top = top, Right = 0, Bottom = 0 })
        return { W = T }
    end
    local b = { Box = box, Label = Line("Label", SIZE.Label, DIM, 0), Name = Line("Name", SIZE.Name, GOLD, 2),
        Step = Line("Step", SIZE.Step, WHITE, 2), Next = {} }
    for k = 1, NEXT_MAX do b.Next[k] = Line("Next" .. k, SIZE.Next, DIM, 3) end
    box:SetVisibility(1)
    return b
end

local function Build(ctx)
    M.Builds = (M.Builds or 0) + 1   -- a new name on every build (see runemap.lua)
    local tex = ctx.Asset(ctx.GoldLine.PATH, "/Script/Engine.Texture2D")
    if not tex then error("line picture not loaded") end
    local uw = New("UserWidget", FindFirstOf("GameInstance"), "RuneUIQuests" .. M.Builds)
    local tree = New("WidgetTree", uw, "RuneUIQuestsTree")
    uw.WidgetTree = tree
    local canvas = New("CanvasPanel", tree, "RU_QtCanvas")
    tree.RootWidget = canvas
    local size = New("SizeBox", tree, "RU_QtSize")
    size:SetWidthOverride(M.BOX_W)
    size:SetHeightOverride(M.BOX_H)
    local col = New("VerticalBox", tree, "RU_QtColumn")
    size:SetContent(col)
    local line = New("SizeBox", tree, "RU_QtLineBox")
    line:SetWidthOverride(M.BOX_W)
    line:SetHeightOverride(LINE_H)
    -- each part of the line gets its own name: the two halves have one name from GoldLine, and a second object of
    -- the same name takes the place of the first (in game, 04-10-2026: the line had its right half only)
    local parts = 0
    line:SetContent(ctx.GoldLine.Row(function(cls, name)
        parts = parts + 1
        return New(cls, tree, name .. parts)
    end, tex, "RU_QtLine"))
    col:AddChildToVerticalBox(line)
    local blocks = {}
    for i = 1, 2 do
        blocks[i] = Block(ctx, tree, i)
        col:AddChildToVerticalBox(blocks[i].Box):SetPadding({ Left = 0, Top = GAP, Right = 0, Bottom = 0 })
    end
    local E = ctx.ById("questtracker")
    local slot = canvas:AddChildToCanvas(size)
    slot:SetAutoSize(true)
    -- tied to the top right corner, so it stays under the minimap on a wide screen; the spot is measured on a 16:9
    -- screen, 1920 x 1080 units (as runemap.lua)
    slot:SetAnchors({ Minimum = { X = 1, Y = 0 }, Maximum = { X = 1, Y = 0 } })
    slot:SetPosition({ X = E.Center.X - M.BOX_W / 2 - 1920, Y = E.Center.Y - M.BOX_H / 2 })
    uw:AddToViewport(37)
    uw:SetVisibility(1)
    M.W, M.UW, M.Blocks, M.Visible = size, uw, blocks, false
    ctx.Log("quest tracker ready")
end

-- the quest component of the local controller, found once and kept; nil while there is none
local function Component(ctx)
    if M.Comp and M.Comp:IsValid() then return M.Comp end
    M.Comp = nil
    local pc = ctx.Controller()
    if not (pc and pc:IsValid()) then return nil end
    local c = pc.BP_Components_QuestProgress
    if c and c:IsValid() then M.Comp = c return c end
    Once(ctx, "nocomp", "quest tracker: the controller has no quest component")
end

-- The game's quests, light: the open ones for Pick, the QuestData by name (only for this step of the tick), and the
-- name of the tracked quest. Each element is read in a pcall, so one that cannot be read does not stop the rest.
local function ReadQuests(comp)
    local quests, datas = {}, {}
    comp.Quests:ForEach(function(_, e)
        pcall(function()
            local s = e:get()
            if s.State ~= 1 then return end   -- Pick only takes open quests: the rest are not read
            local d = s.Data
            if not (d and d:IsValid()) then return end
            local id = d:GetFName():ToString()
            quests[#quests + 1] = { Id = id, Title = Trim(d.QuestName:ToString()), State = s.State,
                Step = s.CurrentObjective:ToString(), Main = d.bIsMainQuest == true, Hidden = d.bHideInQuestList == true }
            datas[id] = d
        end)
    end)
    local trackedId
    local t = comp.TrackedSecondaryQuest
    if t and t:IsValid() then trackedId = t:GetFName():ToString() end
    return quests, datas, trackedId
end

local function ReadSteps(d)
    local steps = {}
    d.ObjectiveTexts:ForEach(function(k, v)
        pcall(function() steps[#steps + 1] = { Key = k:get():ToString(), Text = v:get():ToString() } end)
    end)
    return steps
end

-- Once a second: pick the two quests; the texts are read again only when the quest, its step or the setting changed.
local function Look(ctx)
    local comp = Component(ctx)
    if not comp then M.Main, M.Tracked, M.Sig, M.Key = nil, nil, "", nil return end
    local quests, datas, trackedId = ReadQuests(comp)
    local main, tracked = M.Pick(quests, trackedId)
    local showNext = ctx.ShowNext()
    M.Sig = M.SigOf(main, tracked)
    local key = M.Sig .. (showNext and "+" or "-")
    if key == M.Key then return end
    M.Key = key
    local function Make(q) return q and M.Describe(q, ReadSteps(datas[q.Id]), showNext) or nil end
    M.Main, M.Tracked = Make(main), Make(tracked)
end

-- a line of text, written only when it changed; an empty line is collapsed
local function SetLine(t, s)
    if s == t.S then return end
    t.S = s
    if s and s ~= "" then
        t.W:SetText(FText(s))
        t.W:SetVisibility(4)
    else
        t.W:SetVisibility(1)
    end
end

local function Show(b, d, label)
    local on = d ~= nil
    if on ~= b.On then b.On = on b.Box:SetVisibility(on and 4 or 1) end
    if not d then return end
    SetLine(b.Label, string.upper(label))
    SetLine(b.Name, d.Title)
    SetLine(b.Step, d.Step)
    for i = 1, NEXT_MAX do SetLine(b.Next[i], d.Next[i]) end
end

-- what F9 shows when no quest is open: words made up to show the look while the player moves the tracker
local function Sample(ctx)
    local later = ctx.ShowNext() and { "A step after this one", "Then this one" } or {}
    return { Title = "Quest name", Step = "What to do now", Next = later }
end

function M.Forget(sameWorld)
    -- as RuneMap: off the screen only in the same world; after a world change the engine has taken it away
    if sameWorld and M.UW then pcall(function() M.UW:RemoveFromParent() end) end
    M.W, M.UW, M.Blocks, M.Visible = nil, nil, nil, false
    M.Comp, M.Main, M.Tracked, M.Key, M.Sig, M.NextRead, M.Fails, M.RetryAt, Logged = nil, nil, nil, nil, "", 0, 0, 0, {}
end
M.Forget(false)

function M.Tick(ctx)
    local now = os.clock()
    if now < (M.Next or 0) then return end
    M.Next = now + 0.25
    if not (M.W and M.W:IsValid()) then
        if not ctx.MayTry(M) then return end   -- 3 tries at most, 10 s apart
        local V = ctx.ById("vitals").Instances[1]
        if not (V and V:IsValid()) then return end   -- no world yet
        M.W = nil
        local ok, err = pcall(Build, ctx)
        if not ok then ctx.Failed(M) ctx.Log("quest tracker failed: " .. tostring(err)) end
        return
    end
    local editing = ctx.Editing()
    local on = ctx.On() or editing
    if on and now >= M.NextRead then
        M.NextRead = now + 1
        local ok, err = pcall(Look, ctx)
        if not ok then
            M.Comp = nil   -- the handle may be the cause: found again at the next read
            Once(ctx, "look", "quest tracker not read: " .. tostring(err))
        end
    end
    local main, tracked = M.Main, M.Tracked
    if editing and not main and not tracked then main = Sample(ctx) end
    if not on then main, tracked = nil, nil end
    Show(M.Blocks[1], main, LABEL.Main)
    Show(M.Blocks[2], tracked, LABEL.Tracked)
    -- with the game's HUD (menus, the big map); off the screen when empty. The game's quest and unlock notice plays in
    -- the same place under the map, so the tracker steps aside while one is on show (not in the editor, where the
    -- player places the tracker). The notice is asked only when its answer can change the result.
    local V = ctx.ById("vitals").Instances[1]
    local hud = V and V:IsValid() and V:IsVisible()
    local notice = hud and (main ~= nil or tracked ~= nil) and not editing and ctx.Popup() == true
    local visible = (hud and not notice and (main ~= nil or tracked ~= nil)) and true or false
    if visible ~= M.Visible then
        M.Visible = visible
        M.UW:SetVisibility(visible and 3 or 1)
    end
end

return M
