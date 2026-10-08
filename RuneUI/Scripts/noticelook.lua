-- The game's notices in a tidier look. This file walks each entry, styles each part once and re-checks the colours
-- it set. It never writes the visibility or the opacity of an entry or a page (notices.lua owns them).
-- noticestyle.lua holds the writes (ctx.Style).

local M = {}

M.PerkLook = true         -- false: the quest and unlock entry keeps the game's look
M.Sparkles = true         -- true: the Niagara widgets of the new area banner are collapsed, and again when the game shows them
M.NewSkillStrip = false   -- the name of the empty strip under "You have unlocked", when it is known

local GAP = 8        -- units between the warning's ring and its band
local PROGRESS = 2   -- height of the tip's progress line, in units
local PROGRESS_UNDER = 0   -- units the line hangs under the band: 0, its bottom edge is the band's; the band's edge is soft, so a line under it looks loose
local EVERY = 0.5    -- seconds between two looks for entries
local WATCH = 1      -- seconds between two checks of the colours that were set
local RETRY = 1      -- seconds until an entry with a part still waiting is walked again
local TRIES = 20     -- walks of an entry that finds nothing or waits for a part, before the walks slow down
local SLOW = 5       -- seconds between two walks after that
local DEPTH = 24
local IMAGES = 40   -- the most image names that a log line about a missing part lists
local COLLAPSED = 1   -- ESlateVisibility

local PRIMARY = "WBP_PrimaryNotificationQueue_Item_C"
-- the band of a quest or unlock row, on the master copy that the game makes each new row from
local ROWBAND = "/Game/UI/Notifications/QuestAndUnlocks/WBP_QuestAndUnlocks_Item_Slot.WBP_QuestAndUnlocks_Item_Slot_C:WidgetTree.CommonLazyImage_83"

M.Done = {}      -- full name of a part -> { step number -> true }
M.Scopes = {}    -- full name of an entry -> { Tries, Next } (Next false: finished)
M.Watch = {}     -- { W, Key (its full name), Check }
M.Src = {}       -- parts that steps keep for other steps (S.Remember): the new area banner's Bg and Lines, and "Glyph@" plus an entry's full name
M.Logged = {}
M.Pics = {}      -- file -> { W (the texture), Key (its full name) }: the mod's own pictures, decoded once (see Picture in noticestyle.lua)

local function Ok(w) return w and w:IsValid() end
local function NameOf(W) return W:GetFName():ToString() end
local function ClassOf(W) return W:GetClass():GetFName():ToString() end
local function IsText(c) return string.find(c, "TextBlock$") or string.find(c, "TextBlock_C$") end

local function Once(ctx, key, msg)
    if not M.Logged[key] then M.Logged[key] = true ctx.Log(msg) end
end

-- The steps of an OnShow entry without those that must run once
local function Refuse(ctx, S, E)
    local function Clean(steps)
        local keep = {}
        for _, step in ipairs(steps) do
            if S.Once[step] then
                Once(ctx, "once" .. E.Class, "noticelook: a step that must run once is not run on each show of " .. E.Class)
            else
                keep[#keep + 1] = step
            end
        end
        return keep
    end
    local function Group(G)   -- an entry, or one of its pages
        for name, steps in pairs(G.Parts) do G.Parts[name] = Clean(steps) end
        if G.Texts then G.Texts = Clean(G.Texts) end
        if G.Sparks then G.Sparks = Clean(G.Sparks) end
    end
    Group(E)
    for _, page in pairs(E.Pages or {}) do Group(page) end
end
M.Refuse = Refuse   -- for tools/test-noticelook.js

-- What each notice gets. Parts: part name -> steps. Texts: steps for every other text. Sparks: steps for Niagara widgets.
-- Expect: part names that the walk must find (not proven yet); one that is not found is logged once, with the names of the images seen.
-- Pages: the pages of the big banners' entry, by name; each has Parts and Texts. OnShow: the steps run again each
-- time the entry goes from collapsed to shown, as the game sets its own picture and colour then. A step that must run
-- once (S.Once: Move adds up, Lines makes new images) is dropped from such an entry, with one log line.
local function Recipes(ctx, S)
    local font, hide, gold, goldImage = S.Font, S.Hide, S.GoldText, S.GoldImage
    local band, lines, unseen = S.Band(), S.Lines, S.Unseen
    local own = function(step) return S.Only(nil, step) end
    local noop = function() return true end   -- the read-only step and the warning's ring are left out when noticeread.lua or noticering.lua did not load
    local measure = own(S.Measure or noop)
    local ring, game = S.Only("SegmentedRadialBar", S.WarnRing or noop), S.Only("SegmentedRadialBar", S.GameRing or noop)
    local function Fonts(...)
        local parts = {}
        for _, n in ipairs({ ... }) do parts[n] = { font } end
        return parts
    end
    local skill = { Texts = { font }, Parts = {} }
    if M.NewSkillStrip then skill.Parts[M.NewSkillStrip] = { hide } end
    local vendor = Fonts("NameTextBlock", "LevelTextBlock")
    vendor.LevelTextBlock = { font, S.Move(-6, -3) }
    vendor.ReputationCircle, vendor.VendorStationReputationProgressBar = { S.Move(-6, 0) }, { S.Move(-6, 0) }
    local arena = Fonts("StartedTextBlock", "TimerTextBlock", "CompletedTextBlock", "CountdownTextBlock")
    arena.Panel = { S.Band(600) }
    local list = {
        { Class = PRIMARY, Pages = {
            AchievementNotificationItem = {
                Parts = {
                    NotificationTextBlock = { gold }, HighlightImage = { own(S.Remember("Lines")), goldImage },
                    BgImage = { own(S.Remember("Bg")) }, PowerLevelDisplay = { S.Move(0, -20) },
                    SymbolImage = { hide, unseen }, FXImage = { hide, unseen }, TopTextureImage = { hide, unseen },
                    ShadowImage = { hide, unseen },
                },
                Expect = { "ShadowImage" },
                Sparks = M.Sparkles and { S.Collapse } or false },
            ArenaNotificationItem = { Parts = arena },
            LevelUpVendorNotificationItem = { Parts = vendor },
            NewSkillNotificationItem = skill,
            MilestoneMaterialNotificationItem = { Texts = { font }, Parts = {} },
            FishCaughtNotificationItem = { Texts = { font }, Parts = {} },
        } },
        { Class = "WBP_TutorialNotifications_Item_C", OnShow = true, Parts = {
            IconImage = { goldImage }, TitleTextBlock = { S.GoldRich }, BackgroundImage = { band }, BackgroundShadowImage = { hide },
            ProgressBar = { S.GoldFill }, ProgressBarSizeBox = { S.Height(PROGRESS), S.Hang(PROGRESS_UNDER) } } },
        { Class = "WBP_PlayerUpkeepNotification_Item_C", Texts = { font }, Expect = { "RadialImage" }, Parts = {
            RadialGlow = { own(hide) }, SegmentedRadialBar = { own(S.Move(-GAP, 0)) },
            Background = { own(band), own(lines), measure, ring, game },
            RadialImage = { game },
            Icon = { S.Only("SegmentedRadialBar", S.Remember("Glyph", true)), game } } },
        { Class = "WBP_EnvAndPlayerStatus_Item_C", Texts = { font }, Parts = { Background = { band, S.Lines } } },
        { Class = "WBP_Notification_ItemBreak_Item_C", Texts = { font }, Parts = {} },
    }
    if M.PerkLook then
        list[#list + 1] = { Class = "WBP_QuestAndUnlocks_Item_C", Parts = {
            CommonLazyImage_6 = { hide }, CommonLazyImage_8 = { hide }, CommonLazyImage_9 = { hide }, CommonLazyImage_83 = { hide },
            SymbolImage_2 = { hide }, Border_3 = { hide } } }
    end
    for _, E in ipairs(list) do
        E.Parts = E.Parts or {}
        for _, page in pairs(E.Pages or {}) do page.Parts = page.Parts or {} end
        if E.OnShow then Refuse(ctx, S, E) end
    end
    return list
end

-- the steps of one part, each once; a step that waits for something is tried again at the next walk
local function Apply(env, W, info, steps)
    local key = W:GetFullName()
    local done = M.Done[key]
    if not done then done = {} M.Done[key] = done end
    env.Hits = env.Hits + 1
    for i, step in ipairs(steps) do
        local was = done[i]
        if not was or env.Redo then
            local ok, res, check = pcall(step, env, W, info)
            if not ok then
                done[i] = true
                env.Once(info.Name, "noticelook: " .. info.Name .. " not styled: " .. tostring(res))
            elseif res == false then
                env.Pending = true
            else
                done[i] = true
                if check and not was then M.Watch[#M.Watch + 1] = { W = W, Key = key, Check = check } end
            end
        end
    end
end

-- Owner: the name of the nested widget that holds W (nil: the entry or its page); Tree: that widget's tree.
local function Visit(env, W, rule, owner, tree, depth)
    if depth > DEPTH or not Ok(W) then return end
    env.Met = env.Met + 1
    local c, n = ClassOf(W), NameOf(W)
    local text = IsText(c)
    if rule.Parts[n] then env.Seen[n] = true end
    if string.find(c, "Image") and #env.Images < IMAGES then env.Images[#env.Images + 1] = n end
    local steps = rule.Parts[n] or (text and rule.Texts) or (rule.Sparks and string.find(c, "Niagara") and rule.Sparks)
    if steps then
        local ok, err = pcall(Apply, env, W, { Name = n, Class = c, Owner = owner, Tree = tree }, steps)
        if not ok then env.Once(n, "noticelook: " .. n .. " not read: " .. tostring(err)) end
    end
    if text then return end
    if string.find(c, "^WBP_") then
        local ok, t = pcall(function() return W.WidgetTree end)
        if ok and Ok(t) then Visit(env, t.RootWidget, rule, n, t, depth + 1) end
        return
    end
    local okN, count = pcall(function() return W:GetChildrenCount() end)
    if okN and count then
        for i = 0, count - 1 do Visit(env, W:GetChildAt(i), rule, owner, tree, depth + 1) end
    else
        pcall(function() Visit(env, W:GetContent(), rule, owner, tree, depth + 1) end)
    end
end

-- One entry or page; a name in rule.Expect that the walk did not meet is logged once, but not when the walk met no
-- widget at all (the tree is not built yet: the log would be wrong, and its once key spent); that walk waits and comes again
local function WalkRule(env, rule, root, tree, label)
    env.Seen, env.Images, env.Met, env.Label = {}, {}, 0, label
    Visit(env, root, rule, nil, tree, 1)
    if env.Met == 0 then env.Pending = true return end
    for _, name in ipairs(rule.Expect or {}) do
        if not env.Seen[name] then
            env.Once("part" .. name, "noticelook: part " .. name .. " not found in " .. label .. ", images seen: " .. table.concat(env.Images, ", "))
        end
    end
end

local function WalkEntry(env, E, W)
    local tree = W.WidgetTree
    if not (Ok(tree) and Ok(tree.RootWidget)) then env.Pending = true return end   -- the tree is not built yet: wait, log nothing
    if not E.Pages then WalkRule(env, E, tree.RootWidget, tree, E.Class) return end
    local switcher, seen = tree.RootWidget, {}
    for i = 0, switcher:GetChildrenCount() - 1 do
        local P = switcher:GetChildAt(i)
        local name = Ok(P) and NameOf(P)
        local page = name and E.Pages[name]
        if page then
            seen[name] = true
            local ptree = P.WidgetTree
            WalkRule(env, page, ptree.RootWidget, ptree, name)
        end
    end
    for name in pairs(E.Pages) do
        if not seen[name] then env.Once("page" .. name, "noticelook: page " .. name .. " not found") end
    end
end

local function Look(ctx, env, E, W, key, now)
    local sc = M.Scopes[key]
    if not sc then sc = { Tries = 0, Next = 0 } M.Scopes[key] = sc end
    local redo = false
    if E.OnShow then   -- read only: a change from collapsed to shown, seen on this step (a write within 0.5 s of the show is late)
        local ok, vis = pcall(function() return W:GetVisibility() end)
        if ok then
            redo = sc.Vis == COLLAPSED and vis ~= COLLAPSED
            sc.Vis = vis
        end
    end
    if not redo and (not sc.Next or now < sc.Next) then return end
    if redo then sc.Tries = 0 end
    sc.Tries = sc.Tries + 1
    env.Pending, env.Hits, env.Redo, env.Entry = false, 0, redo, W
    local ok, err = pcall(WalkEntry, env, E, W)
    if not ok then
        env.Pending = true
        Once(ctx, E.Class, "noticelook: " .. E.Class .. " not walked: " .. tostring(err))
    end
    local waiting = env.Pending or env.Hits == 0
    if waiting then
        sc.Next = now + (sc.Tries < TRIES and RETRY or SLOW)
        if sc.Tries == TRIES then Once(ctx, "slow" .. E.Class, "noticelook: " .. E.Class .. " is not fully styled yet") end
    else
        sc.Next = false
    end
end

-- the colours that were set, looked at again: a check writes only when the game wrote its own value. A check that
-- returns true is done and is taken out (the read of S.Measure).
local function Watch(ctx)
    local list = M.Watch
    for i = #list, 1, -1 do
        local e = list[i]
        local okV, alive = pcall(function() return Ok(e.W) and e.W:GetFullName() == e.Key end)
        if not (okV and alive) then
            table.remove(list, i)
        else
            local ok, res = pcall(e.Check)
            if not ok then
                table.remove(list, i)
                Once(ctx, "watch", "noticelook: a colour is not kept: " .. tostring(res))
            elseif res == true then
                table.remove(list, i)
            end
        end
    end
end

-- a new world: its widgets are new, so nothing is called on the old ones. A respawn keeps them and their look.
function M.Forget(sameWorld)
    if not sameWorld then M.Done, M.Scopes, M.Watch, M.Src, M.Logged, M.Pics, M.Master = {}, {}, {}, {}, {}, {}, nil end
    M.Next, M.NextWatch = nil, nil
end

function M.Tick(ctx)
    local now = os.clock()
    if now >= (M.NextWatch or 0) then
        M.NextWatch = now + WATCH
        Watch(ctx)
    end
    if now < (M.Next or 0) then return end
    M.Next = now + EVERY
    if not ctx.Style then Once(ctx, "style", "noticelook: no style file, the notices keep the game's look") return end
    if ctx.Reads and not ctx.Style.Measure then ctx.Reads.Install(ctx.Style) end
    if ctx.Ring and not ctx.Style.WarnRing then ctx.Ring.Install(ctx.Style) end
    M.Recipes = M.Recipes or Recipes(ctx, ctx.Style)
    local font, read = nil, false   -- the font is looked for once in a step, and only when a part needs it
    local env = { Src = M.Src, Uniq = ctx.Uniq, CachedTex = ctx.CachedTex, Hud = ctx.Hud, Survival = ctx.Survival, Pics = M.Pics, Once = function(key, msg) Once(ctx, key, msg) end,
        Font = function() if not read then read, font = true, ctx.Font() end return font end }
    if M.PerkLook and not M.Master then
        local ok, done = pcall(ctx.Style.Master, env, ROWBAND)
        if ok then M.Master = done else M.Master = true Once(ctx, "master", "noticelook: the row's band not hidden: " .. tostring(done)) end
    end
    for _, E in ipairs(M.Recipes) do
        local list, keys = ctx.Find(E.Class)
        for i, W in ipairs(list) do
            if Ok(W) then Look(ctx, env, E, W, keys[i], now) end
        end
    end
end

return M
