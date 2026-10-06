-- Rune UI's page in the mod "Mod Menu": MODS in the pause menu, for a player who has that mod. The page is
-- RuneUI/modmenu.txt. Mod Menu shows it, keeps the values in its own file (config.txt in our folder; that cannot
-- be turned off) and gives them to other mods as shared variables: ModMenu.RuneUI.<key>, .rev (one more on each
-- change the player makes) and .action (the button the player clicked, with a count).
-- runeui.txt stays the only real settings file. This part takes a change from the menu into the mod, and keeps
-- config.txt equal to the mod's real values: Mod Menu reads that file again each time the menu opens, so a change
-- made in F8 or F9 shows there. Without Mod Menu there is no rev, and this part does nothing and writes nothing.
-- Pure Lua: main.lua gives the rows, the shared variables and the file through ctx, so tools/test-modmenu.js runs
-- it without the game.
local M = { Seen = {} }
M.FILE = (RUNEUI_DIR or "ue4ss/Mods/RuneUI/") .. "config.txt"
local HEADER = "# Mod Menu's copy of some Rune UI settings. Rune UI writes this file. The real settings are in runeui.txt.\n"

-- A key's name in runeui.txt (main.lua's VK) and Mod Menu's name for it: the engine's name in capitals with
-- underscores (fromUnrealKey in Mod Menu 1.0.13). A key that is not here (a mouse button, "none") is not taken.
local MENU = { Insert = "INSERT", Delete = "DELETE", Home = "HOME", End = "END", PgUp = "PAGE_UP", PgDn = "PAGE_DOWN",
    Backspace = "BACK_SPACE", Left = "LEFT", Up = "UP", Right = "RIGHT", Down = "DOWN", ["["] = "LEFT_BRACKET",
    ["]"] = "RIGHT_BRACKET", Comma = "COMMA", Period = "PERIOD", Dash = "HYPHEN", Equals = "EQUALS", Plus = "NUM_PLUS",
    Minus = "NUM_MINUS" }
for i, name in ipairs({ "ZERO", "ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE" }) do MENU[tostring(i - 1)] = name end
for i = 1, 12 do MENU["F" .. i] = "F" .. i end
for i = 65, 90 do MENU[string.char(i)] = string.char(i) end
local OURS = {}
for ours, menu in pairs(MENU) do OURS[menu] = ours end
-- like main.lua's KeyCode: the name as written, or in capitals (f9)
function M.KeyToMenu(name) name = tostring(name) return MENU[name] or MENU[string.upper(name)] end
function M.KeyFromMenu(name) return OURS[string.upper(tostring(name))] end

-- config.txt as Mod Menu itself writes it ("Key = value", true and false, whole numbers), so its own save with the
-- same values gives the same text
local function Value(v)
    if type(v) == "boolean" then return v and "true" or "false" end
    if type(v) == "number" then return tostring(math.floor(v + 0.5)) end   -- every number is whole: the waits in seconds, the camera's distances in cm
    return tostring(v)
end
function M.Text(rows)
    local out = { HEADER }
    for _, R in ipairs(rows) do out[#out + 1] = R.Key .. " = " .. Value(R.Get()) .. "\n" end
    return table.concat(out)
end

-- Mod Menu's file made equal to the mod's real values. Mod Menu saves the values it holds a second after a
-- change, also the ones this mod did not take (an unknown key, the other profile's immersive mode), so the file is
-- read every second and not only written after a change here.
local function Mirror(ctx)
    local text = M.Text(ctx.Rows)
    local old = ctx.ReadFile(M.FILE)
    if old and string.gsub(old, "\r", "") == text then return end
    if ctx.WriteFile(M.FILE, text) then ctx.Log("modmenu: config.txt written")
    elseif not M.WriteFailed then M.WriteFailed = true ctx.Log("modmenu: cannot write " .. M.FILE) end
end

-- Once a second. ctx: Rows (each Key, Get, Set), Read(name) a shared variable of our page, ReadFile, WriteFile,
-- OpenEditor, Log.
-- Only a value that changed together with rev is the player's change. The first values seen are not taken: with
-- no config.txt yet they are the page's defaults, and they would replace the player's own settings. Mod Menu
-- also gives the values again each time the menu opens, without a new rev: from a file that can be a second old.
function M.Tick(ctx, now)
    now = now or os.clock()
    if now < (M.Next or 0) then return end
    M.Next = now + 1
    local rev = ctx.Read("rev")
    if type(rev) ~= "number" then return end   -- no Mod Menu, or it loads after this mod
    local first = M.Rev == nil
    local changed = not first and rev ~= M.Rev
    M.Rev = rev
    if first then ctx.Log("modmenu: Mod Menu found") end
    for _, R in ipairs(ctx.Rows) do
        local v = ctx.Read(R.Key)
        if v ~= nil and v ~= M.Seen[R.Key] then
            M.Seen[R.Key] = v
            if changed and v ~= R.Get() then
                local ok, err = pcall(R.Set, v)
                ctx.Log("modmenu: " .. R.Key .. " = " .. tostring(v) .. (ok and "" or (" failed: " .. tostring(err))))
            end
        end
    end
    local action = ctx.Read("action")
    if action ~= M.Action then
        M.Action = action
        -- the one seen first is a click of before this mod started (a mod reload)
        if not first and string.match(tostring(action), "^open_editor#") then ctx.OpenEditor() end
    end
    Mirror(ctx)
end

return M
