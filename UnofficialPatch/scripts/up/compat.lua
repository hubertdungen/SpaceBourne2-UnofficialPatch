--[[
  No double fixing. Some of the game's bugs are already fixed by other mods of the SpaceBourne 2
  realism set. At start the patch reads Mods\mods.txt (and each mod's enabled.txt), the owner's
  VERSION in its scripts\main.lua and, where the owner has a switch for the fix, its config.lua.
  When the owner is on, new enough and has the fix switched on, the patch leaves that fix to it.

  The patch also tells the other mods what it does, in the UE4SS shared variable SB2R_GameFixes:
  "<version>;<fix>,<fix>,...". A future version of an owner mod can read it and hand a fix over.
]]

local U = require("up.util")

local C = { on = {}, versions = {}, skipped = {}, applied = {} }

-- fix -> mods that already have it (first version with the fix, the switch that turns it off there)
C.OWNERS = {
    EndBulletsAfterHit = { { mod = "HardcoreTacticalRealism", name = "HTR", min = "0.4.11", off = "EndBulletsAfterHit%s*=%s*false" } },
    CompanionBullets   = { { mod = "HardcoreTacticalRealism", name = "HTR", min = "0.4.0", off = "CompanionFixes%s*=%s*false" } },
    SquadKeepUp        = { { mod = "HardcoreTacticalRealism", name = "HTR", min = "0.4.2", off = "KeepUp%s*=%s*false" } },
    AmmoHudRefresh     = { { mod = "AmmoDiscipline", name = "Ammo Discipline", min = "0.1.1" } },
}

local function readAll(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function exists(path)
    local f = io.open(path, "r")
    if f then f:close(); return true end
    return false
end

-- "0.4.16" >= "0.4.2" ?
local function atLeast(v, min)
    local a, b = {}, {}
    for n in tostring(v):gmatch("%d+") do a[#a + 1] = tonumber(n) end
    for n in tostring(min):gmatch("%d+") do b[#b + 1] = tonumber(n) end
    for i = 1, math.max(#a, #b) do
        local x, y = a[i] or 0, b[i] or 0
        if x ~= y then return x > y end
    end
    return true
end
C.atLeast = atLeast

function C.scan()
    local mods = U.Dir:match("^(.*[\\/])[^\\/]+[\\/]$") or (U.Dir .. "..\\")
    C.modsDir = mods
    local list = readAll(mods .. "mods.txt") or ""
    local listed = {}
    for line in list:gmatch("[^\r\n]+") do
        local name, v = line:match("^%s*([%w_%-]+)%s*:%s*(%d)")
        if name then listed[name] = (v == "1") end
    end
    local wanted = {}
    for _, owners in pairs(C.OWNERS) do for _, o in ipairs(owners) do wanted[o.mod] = true end end
    for name in pairs(wanted) do
        local main = readAll(mods .. name .. "\\scripts\\main.lua")
        if main then
            local on = listed[name] == true or exists(mods .. name .. "\\enabled.txt")
            C.on[name] = on
            C.versions[name] = main:match("local%s+VERSION%s*=%s*\"([%d%.]+)\"") or "?"
        end
    end
end

-- true when the patch should apply this fix itself
function C.mine(fix)
    for _, o in ipairs(C.OWNERS[fix] or {}) do
        if C.on[o.mod] and C.versions[o.mod] ~= "?" and atLeast(C.versions[o.mod], o.min) then
            local cfg = o.off and readAll(C.modsDir .. o.mod .. "\\scripts\\config.lua")
            if not (cfg and cfg:find(o.off)) then
                C.skipped[fix] = o.name .. " " .. C.versions[o.mod]
                return false
            end
        end
    end
    return true
end

function C.publish(version)
    local ids = {}
    for fix in pairs(C.applied) do ids[#ids + 1] = fix end
    table.sort(ids)
    local s = version .. ";" .. table.concat(ids, ",")
    if ModRef then pcall(function() ModRef:SetSharedVariable("SB2R_GameFixes", s) end) end
    return s
end

function C.report()
    local parts = {}
    for fix, by in pairs(C.skipped) do parts[#parts + 1] = fix .. " (" .. by .. " has it)" end
    table.sort(parts)
    return #parts > 0 and table.concat(parts, ", ") or "none"
end

return C
