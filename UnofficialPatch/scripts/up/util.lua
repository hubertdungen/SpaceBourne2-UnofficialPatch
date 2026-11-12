--[[ Unofficial Patch helpers: logging, safe property access, positions. ]]

local U = {}

-- Mod folder (UE4SS may report the path as ...\Scripts\ or ...\scripts\).
do
    local src = debug.getinfo(1, "S").source:gsub("^@", "")
    local lower = src:lower()
    local cut
    for i in lower:gmatch("()[\\/]scripts[\\/]") do cut = i end
    U.Dir = cut and src:sub(1, cut) or ".\\Mods\\UnofficialPatch\\"
end
U.LogFile = U.Dir .. "unofficialpatch.log"
U.Verbose = false

local function write(tag, msg)
    local f = io.open(U.LogFile, "a")
    if f then f:write(os.date("%H:%M:%S "), tag, msg, "\n"); f:close() end
end

function U.log(...)
    if not U.Verbose then return end
    local t = {}
    for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
    write("", table.concat(t, " "))
end

-- Always printed (UE4SS.log) and logged.
function U.warn(...)
    local msg = table.concat({ ... }, " ")
    print("[Unofficial Patch] " .. msg .. "\n")
    write("WARN ", msg)
end

-- UE4SS 3.0.1 hands back a wrapper even for a null object, and a method call on it is an access
-- violation (not a Lua error). So every object is checked here before anything is called on it.
function U.valid(o)
    if o == nil then return false end
    local ok, v = pcall(function() return o:IsValid() end)
    return ok and v == true
end

function U.addr(o)
    local ok, a = pcall(function() return o:GetAddress() end)
    return ok and a or nil
end

-- A reference kept from an earlier tick is usable only if still valid AND the same object.
function U.alive(o, addr) return U.valid(o) and U.addr(o) == addr end

function U.get(o, prop, default)
    local ok, v = pcall(function() return o[prop] end)
    if ok and v ~= nil then return v end
    return default
end

function U.set(o, prop, v) return (pcall(function() o[prop] = v end)) end

-- Hook parameter -> value (RemoteUnrealParam:get()).
function U.param(p)
    local ok, v = pcall(function() return p:get() end)
    if ok then return v end
    return nil
end

function U.location(a)
    if not U.valid(a) then return nil end
    local ok, l = pcall(function() local v = a:K2_GetActorLocation(); return { X = v.X, Y = v.Y, Z = v.Z } end)
    return ok and l or nil
end

function U.yaw(a)
    local ok, y = pcall(function() return a:K2_GetActorRotation().Yaw end)
    return ok and y or 0
end

function U.dist(a, b)
    if not (a and b) then return 1e9 end
    return math.sqrt((a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2 + (a.Z - b.Z) ^ 2)
end

function U.dist2(a, b)
    if not (a and b) then return 1e9 end
    return math.sqrt((a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2)
end

function U.className(o)
    if not U.valid(o) then return nil end
    local ok, n = pcall(function() return o:GetClass():GetFName():ToString() end)
    return ok and n or nil
end

-- Capsule half height (cm) of a character, scale included.
function U.halfHeight(c)
    local ok, h = pcall(function() return c.CapsuleComponent:GetScaledCapsuleHalfHeight() end)
    if ok and type(h) == "number" and h > 10 then return h end
    return 90
end

local player, playerAddr, lookedAt = nil, nil, -1e9
function U.player()
    if U.alive(player, playerAddr) then return player end
    player = nil
    if os.clock() - lookedAt < 2 then return nil end -- an object search costs: at most every 2 s
    lookedAt = os.clock()
    local ok, p = pcall(function() return FindFirstOf("Q1_Character_C") end)
    if ok and U.valid(p) then player, playerAddr = p, U.addr(p) end
    return player
end
function U.setPlayer(p) if U.valid(p) then player, playerAddr = p, U.addr(p) end end

function U.now() return os.clock() end

return U
