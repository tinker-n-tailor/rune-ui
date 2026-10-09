-- Rune UI's page in the mod "Mod Menu" (modmenu.lua): the rows of RuneUI/modmenu.txt, each with the mod's
-- real value and the way to change it, as F8 and F9 do it. A key works after a restart, as from runeui.txt.
-- main.lua loads this file and calls Add once, where the keys are bound. H is what main.lua gives it: the log, the
-- loading and the list of parts, the profile in use, the settings file, the keys' defaults, the editor's state (Ed),
-- the F9 list (overlay.lua), and the map, the camera and the skin panel.

local M = {}

function M.Add(H)
    local Log, Prof, Settings, Cfg, KEY_DEFAULT, Ed, ById = H.Log, H.Prof, H.Settings, H.Cfg, H.KEY_DEFAULT, H.Ed, H.ById
    local RuneMap, Camera, Skin = H.RuneMap, H.Camera, H.Skin
    local MM = H.LoadPart("modmenu")
    if MM then
        local rows = {}
        local function Row(key, get, set) rows[#rows + 1] = { Key = key, Get = get, Set = set } end
        -- first: Mod Menu's "reset" gives every row at once, and the rows below belong to the profile in use
        Row("profile", function() return tostring(Prof.N) end,
            function(v)
                local n = tonumber(v)
                if n ~= 1 and n ~= 2 and n ~= 3 then Log("profile: " .. tostring(v) .. " from Mod Menu is not a profile (1, 2 or 3), the profile stays") return end
                for _ = 1, 2 do if Prof.N ~= n then Prof.Next() end end
            end)
        local keys = Settings.Section(Cfg, "keys")
        for _, what in ipairs({ "editor", "skin", "map", "camera", "profile", "zoomin", "zoomout" }) do
            Row("key_" .. what, function() return MM.KeyToMenu(keys[what]) or MM.KeyToMenu(KEY_DEFAULT[what]) end,
                function(v)
                    local name = MM.KeyFromMenu(v)
                    if not name then Log("keys: " .. tostring(v) .. " from Mod Menu is not a key the mod knows, " .. what .. " stays") return end
                    keys[what] = name
                    H.SaveCfg()
                end)
        end
        -- the immersive mode and the creatures are rows of the layout: the step's save writes them (Ed.Save)
        local I, C = ById("immersive"), ById("creatures")
        for _, r in ipairs({ { "immersive", "immersive" }, { "rune_xp", "runexp" }, { "slim_level_up", "slimlevel" },
            { "combat_text", "combattext" }, { "quest_next", "questnext" }, { "horizontal_cooldowns", "cdhoriz" },
            { "party_panel", "party" }, { "wheels", "wheels" }, { "gold_crosshair", "aim" }, { "day_night_icon", "dialskin" }, { "bar_icons", "baricons" } }) do
            local El = ById(r[2])
            Row(r[1], function() return El.Visible end, function(v) El.Visible = v == true Ed.Save = true end)
        end
        Row("immersive_wait", function() return I.Wait or 8 end,
            function(v) I.Wait = math.floor(Settings.Num(v, 3, 30, 8) + 0.5) Ed.Save = true end)
        if RuneMap then
            local S = RuneMap.Set
            for _, k in ipairs({ "Map", "North", "Mark", "Name", "Ore", "Herbs", "Essence", "Trees" }) do
                Row("map_" .. k, function() return S[k] end, function(v) S[k] = v == true RuneMap.Dirty = true end)
            end
            Row("map_immersive", function() return S.Immersive end,
                function(v) S.Immersive = Settings.StayFrom(v) RuneMap.Dirty = true end)
            Row("map_creatures", function() return (not C.Visible) and "Off" or (S.Neutral and "All" or "Enemies only") end,
                function(v) C.Visible, S.Neutral = v ~= "Off", v == "All" RuneMap.Dirty = true Ed.Save = true end)
            Row("map_drawing", function() return Settings.DRAWING[S.Smooth and 1 or (S.Fastest and 3 or 2)] end,
                function(v) local st = Settings.DrawingFrom(v) S.Smooth, S.Fastest = st == 1, st == 3 RuneMap.Dirty = true end)
        end
        if Camera then   -- the camera rows of the F6 panel (camerarules.lua ROWS)
            for _, r in ipairs(Camera.ROWS) do
                Row("camera_" .. r.Key, function() return Camera.MenuGet(r.Key) end, function(v) Camera.MenuSet(r.Key, v) end)
            end
        end
        H.AddPart("mod menu", MM, { Log = Log, Rows = rows, ReadFile = H.ReadText,
            Read = function(name)
                local ok, v = pcall(function() return ModRef:GetSharedVariable("ModMenu.RuneUI." .. name) end)
                if ok then return v end
            end,
            WriteFile = function(path, text)
                local f = io.open(path, "w")
                if not f then return false end
                local ok = f:write(text)
                f:close()
                return ok and true or false
            end,
            -- The step sorts the editor's list when it sees the editor open at its start. This opens it in the middle
            -- of a step, and the panel is filled at the end of the same step: with no list yet, the first fill
            -- failed and the panel stayed blank.
            OpenEditor = function()
                Ed.Map, Ed.Edit = false, true
                if Camera then Camera.Open = false end
                if Skin then Skin.Open = false end
                pcall(H.Overlay.SortOrder)
            end }, true)
    end
end

return M
