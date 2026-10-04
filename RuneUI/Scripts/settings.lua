-- The settings file (1.4): one file, runeui.txt, next to the game, with named values a player can read and edit.
-- Pure Lua (string, table, io, os), no game calls, so tools/test-settings.js runs it without the game.
-- Before 1.4 the mod wrote six files; Legacy reads them once when runeui.txt is missing, so nobody loses a layout.
local M = {}
M.FILE = "runeui.txt"
local HEADER = "# Rune UI settings. The mod writes this file. Delete a line to get its default back.\n"
-- sections in the file's order; any other section is kept and written after these
local ORDER = { "general", "layout 1", "layout 2", "layout 3", "map", "keys" }
-- the fields of a layout row in the order of the old files, so a row reads like the line it replaced
local FIELDS = { "x", "y", "scale", "visible", "opacity", "edgex", "edgey", "wait" }

-- a number in a range, or the default: every value can come from a hand-edited file
function M.Num(v, lo, hi, d)
    v = tonumber(v)
    if not v or v ~= v then return d end
    if lo and v < lo then v = lo end
    if hi and v > hi then v = hi end
    return v
end

function M.Section(t, name) if type(t[name]) ~= "table" then t[name] = {} end return t[name] end

-- What stays in the immersive mode for direction (the map setting "In immersive mode", 1.7). The file holds the
-- number: 0 Nothing, 1 Map, 2 Compass. The first version of the setting was On or Off, saved as 1 and 0: 1 reads as Map
-- and 0 as Nothing. A name typed by hand reads too. Anything else is Nothing.
M.STAY = { "Nothing", "Map", "Compass" }
function M.StayFrom(v)
    local n = tonumber(v)
    if n and n == math.floor(n) and M.STAY[n + 1] then return M.STAY[n + 1] end
    if type(v) == "string" then
        for _, name in ipairs(M.STAY) do if string.lower(v) == string.lower(name) then return name end end
    end
    return M.STAY[1]
end
function M.StayTo(name)
    for i, s in ipairs(M.STAY) do if s == name then return i - 1 end end
    return 0
end

-- only plain decimal text is a number: tonumber also takes "0x1F", which would not come back the same
local function Value(s)
    if string.match(s, "^[-+]?%d*%.?%d+$") or string.match(s, "^[-+]?%d+%.$") or string.match(s, "^[-+]?%d*%.?%d+[eE][-+]?%d+$") then
        return tonumber(s) or s
    end
    return s
end

local function Text(v)
    if v == true then return "1" elseif v == false then return "0" end
    if type(v) ~= "number" then return tostring(v) end
    if v ~= v or v == math.huge or v == -math.huge then return "0" end
    local s = string.format("%.3f", v):gsub("0+$", ""):gsub("%.$", "")
    if s == "-0" then s = "0" end
    return s
end

local function Lines(text) return string.gmatch((text or "") .. "\n", "([^\n]*)\n") end

function M.Parse(text)
    local t, sec = {}, nil
    for line in Lines(text) do
        line = string.match(line, "^%s*(.-)%s*$")   -- also drops the \r of a file saved on Windows
        local name = string.match(line, "^%[%s*(.-)%s*%]$")
        if line == "" or string.sub(line, 1, 1) == "#" then
            -- a comment or a blank line
        elseif name then
            sec = name ~= "" and M.Section(t, name) or nil
        elseif sec then
            -- a scalar is checked first: "trim=a:b" is a value with a colon, not a row
            local k, v = string.match(line, "^([%w_]+)%s*=%s*(.*)$")
            local id, rest = string.match(line, "^([%w_]+)%s*:(.*)$")
            if k then
                sec[k] = Value(v)
            elseif id then
                local row = {}
                for rk, rv in string.gmatch(rest, "([%w_]+)=(%S+)") do row[rk] = Value(rv) end
                sec[id] = row
            end   -- anything else is a bad line, skipped
        end
    end
    return t
end

local function Sorted(tbl)
    local keys = {}
    for k in pairs(tbl) do if type(k) == "string" then keys[#keys + 1] = k end end
    table.sort(keys)
    return keys
end

local function Row(id, row)
    local out, done = { id .. ":" }, {}
    for _, k in ipairs(FIELDS) do
        if row[k] ~= nil then out[#out + 1] = k .. "=" .. Text(row[k]) done[k] = true end
    end
    for _, k in ipairs(Sorted(row)) do
        if not done[k] then out[#out + 1] = k .. "=" .. Text(row[k]) end
    end
    return table.concat(out, " ")
end

-- order: optional list of element ids; a layout section writes its rows in that order, the rest sorted after
function M.Format(t, order)
    local out, names, seen = { HEADER }, {}, {}
    for _, n in ipairs(ORDER) do if type(t[n]) == "table" then names[#names + 1] = n seen[n] = true end end
    for _, n in ipairs(Sorted(t)) do if not seen[n] and type(t[n]) == "table" then names[#names + 1] = n end end
    for i, n in ipairs(names) do
        local sec, keys, used = t[n], {}, {}
        if order and string.match(n, "^layout") then
            for _, id in ipairs(order) do
                if sec[id] ~= nil and not used[id] then keys[#keys + 1] = id used[id] = true end
            end
        end
        for _, k in ipairs(Sorted(sec)) do if not used[k] then keys[#keys + 1] = k end end
        out[#out + 1] = (i > 1 and "\n" or "") .. "[" .. n .. "]\n"
        for _, k in ipairs(keys) do
            local v = sec[k]
            out[#out + 1] = (type(v) == "table" and Row(k, v) or (k .. "=" .. Text(v))) .. "\n"
        end
    end
    return table.concat(out)
end

local function ReadFile(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("a")
    f:close()
    return s
end

-- a save cut off between the remove and the rename leaves only the .tmp file, so it is read too
function M.Load(path)
    path = path or M.FILE
    local s = ReadFile(path) or ReadFile(path .. ".tmp")
    return s and M.Parse(s) or nil
end

-- written to a .tmp file first, so a crash during the write never leaves half a file. On Windows os.rename
-- does not replace an existing file, hence the remove before the second try.
function M.Save(t, path, order)
    path = path or M.FILE
    local text, tmp = M.Format(t, order), path .. ".tmp"
    local f = io.open(tmp, "w")
    if f then
        local ok = f:write(text)
        f:close()
        if ok and (os.rename(tmp, path) or (os.remove(path) and os.rename(tmp, path))) then return true end
        os.remove(tmp)
    end
    f = io.open(path, "w")
    if not f then return false end
    local ok = f:write(text)
    f:close()
    return ok and true or false
end

-- The files before 1.4, in the same table. read(name) gives a file's text or nil. The rules are LoadLayout's
-- (main.lua 1.3) and runemap.lua's, so a layout comes out exactly as the old code read it.
local LAYOUT_FILES = { { "runeui_layout.txt", "hudeditor_layout_v2.txt" }, { "runeui_layout_2.txt" }, { "runeui_layout_3.txt" } }
local MAP_KEYS = { Map = true, North = true, Mark = true, Smooth = true, Neutral = true, Ore = true, Herbs = true,
    Essence = true, Trees = true }

local function LegacyRow(line)
    local id, x, y, s, v = string.match(line, "^(%w+):(%-?[%d%.]+),(%-?[%d%.]+),([%d%.]+),([01])")
    x, y, s = tonumber(x), tonumber(y), tonumber(s)
    if not (x and y and s) then return nil end   -- a hand-edited line with a bad number is skipped
    local row = { x = M.Num(x, -4000, 4000), y = M.Num(y, -4000, 4000), scale = M.Num(s, 0.3, 4.0), visible = v == "1" and 1 or 0 }
    local o = tonumber(string.match(line, "^%w+:[^,]+,[^,]+,[^,]+,[01],([%d%.]+)"))
    row.opacity = o and M.Num(math.floor(o * 10 + 0.5) / 10, 0.2, 1.0) or 1.0
    -- the edges stay as written; main.lua snaps them, and finds them from the spot when they are missing
    local tx, ty = string.match(line, "^%w+:[^,]+,[^,]+,[^,]+,[01],[^,]+,([%d%.]+),([%d%.]+)")
    if tonumber(tx) and tonumber(ty) then row.edgex, row.edgey = tonumber(tx), tonumber(ty) end
    local w = tonumber(string.match(line, "^%w+:[^,]+,[^,]+,[^,]+,[01],[^,]+,[^,]+,[^,]+,([%d%.]+)"))
    if w then row.wait = M.Num(math.floor(w + 0.5), 3, 30) end
    return id, row
end

function M.Legacy(read)
    local t, found = {}, false
    local function get(a, b)
        local s = read(a)
        if s == nil and b then s = read(b) end
        if s ~= nil then found = true end
        return s
    end
    for p, names in ipairs(LAYOUT_FILES) do
        local s = get(names[1], names[2])
        if s then
            local sec = M.Section(t, "layout " .. p)
            for line in Lines(s) do
                local id, row = LegacyRow(line)
                if id then sec[id] = row end
            end
        end
    end
    local s = get("runeui_profile.txt")
    local p = s and tonumber(string.match(s, "^%s*([^\r\n]*)"))
    M.Section(t, "general").profile = (p == 2 or p == 3) and p or 1
    s = get("runeui_mapzoom.txt", "hudeditor_mapzoom.txt")
    if s then M.Section(t, "map").zoom = M.Num(string.match(s, "^%s*([^\r\n]*)"), 0.5, 32, 2) end
    s = get("runeui_map.txt")
    for line in Lines(s) do
        local k, v = string.match(line, "^(%a+)=(%d)")
        if k and MAP_KEYS[k] then M.Section(t, "map")[k] = v == "1" and 1 or 0 end
    end
    return found and t or nil
end

return M
