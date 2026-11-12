--[[
  Allies and lifts (fixes LiftLineUp, SafeCatchUp, ArrivalHoldFire).

  What the game does (decompiled Blueprints, build 2026-10-26):
  - Station lifts (BP_Elevator): 0.2 s after you pick a floor, TeleportAlly puts every companion
    tagged "Ally" on Exit1 or Exit2 by index: two points for any number of allies (the third one on
    gets no valid point), K2_SetActorLocation without sweep, at floor-level points: allies stand in
    each other, half in the floor, or outside the cabin.
  - Squad soldiers (Master_Soldier SetWalkSpeed): more than 30 m from their slot, they are put on a
    random point 2-5 m around you at the height of your capsule, without sweep, navmesh, wall or
    floor check: behind a wall, outside the lift, in the floor. Dungeon floors and lift rides
    always trigger it (you are moved, they are not).

  What the patch does: after a lift ride, a dungeon floor change, any jump of yours over 15 m, and
  after each of those game teleports, it checks every ally that follows you. One that is left
  behind, sunk in the floor, outside the lift you are in or behind a wall is put on a free spot
  next to you that was checked first: a clear line from you, a floor at your height under it, not
  on anyone else, inside the lift cabin when you are in one. K2_TeleportTo also refuses a spot
  where the body would be inside something. Out-parameter calls (traces) run only on those events,
  with one reused hit table.
]]

local U = require("up.util")
local G = require("up.gamedefs")
local P = G.P

local L = { allies = {}, lift = nil, liftAddr = nil, liftT = -1e9, stats = { checks = 0, placed = 0, traces = 0, failed = 0 } }
local GT, SF -- set by main.lua (gametick, squad fire)
function L.init(gt, sf) GT, SF = gt, sf end
local function cfg() return UNOFFICIAL_PATCH.cfg end
local function fixOn(name) return UNOFFICIAL_PATCH.fixes[name] == true end

-- Ally registry ------------------------------------------------------------------------------
local classOf = {} -- addr -> short class name (cached)
local function shortClass(o, a)
    local c = classOf[a]
    if c == nil then c = U.className(o) or false; classOf[a] = c end
    return c
end

local function note(o, kind)
    local a = U.addr(o)
    if not a then return nil end
    local r = L.allies[a]
    if not r then
        local n = 0
        for _ in pairs(L.allies) do n = n + 1 end
        if n > 60 then L.allies, classOf = {}, {} end -- stale entries from older levels
        r = { obj = o, a = a, kind = kind }
        L.allies[a] = r
    end
    r.obj, r.seen = o, os.clock()
    return r
end

-- Master_Soldier hooks: only your own squad (Q1_GroundSquad, your side)
function L.noteSoldier(sol)
    local a = U.addr(sol)
    if not a or shortClass(sol, a) ~= G.SquadClass then return nil end
    if U.get(sol, P.Side, 1) ~= G.AIType.Ally then return nil end
    return note(sol, "squad")
end

-- Shooter think hook: companions that follow you
function L.noteShooter(npc)
    if U.get(npc, P.IsCompanion, false) ~= true and U.get(npc, P.CivilCompanion, false) ~= true then return end
    note(npc, "companion")
end

local function usable(r)
    if not U.alive(r.obj, r.a) then return false end
    if U.get(r.obj, P.Dead, false) or U.get(r.obj, P.Injured, false) then return false end
    return os.clock() - (r.seen or 0) < 30 -- not heard from for 30 s: another level
end

-- Quest companions the station lifts teleport ("Ally" tag): looked up on lift events only.
local function noteQuestAllies()
    local ok, list = pcall(function() return FindAllOf(G.CompanianClass) end)
    if not ok or type(list) ~= "table" then return end
    local tag = FName("Ally")
    for _, o in ipairs(list) do
        if U.valid(o) then
            local okT, has = pcall(function() return o:ActorHasTag(tag) end)
            if okT and has then note(o, "quest") end
        end
    end
end

-- Traces ----------------------------------------------------------------------------------------
local KSL
local HIT = {}
local WHITE = { R = 1, G = 1, B = 1, A = 1 }
local function ksl()
    if not U.valid(KSL) then KSL = StaticFindObject(G.KismetSystem) end
    return U.valid(KSL) and KSL or nil
end
-- Visibility trace a -> b. Returns hit (bool) and the distance to the hit, or nil if it failed.
local function trace(ctx, a, b)
    local lib = ksl()
    if not lib then return nil end
    for k in pairs(HIT) do HIT[k] = nil end
    local out = HIT
    local ok, hit = pcall(function() return lib:LineTraceSingle(ctx, a, b, 0, false, {}, 0, out, true, WHITE, WHITE, 0.0) end)
    if not ok then -- a reused table can be refused: one fresh table then
        out = {}
        ok, hit = pcall(function() return lib:LineTraceSingle(ctx, a, b, 0, false, {}, 0, out, true, WHITE, WHITE, 0.0) end)
    end
    if not ok then return nil end
    L.stats.traces = L.stats.traces + 1
    if hit ~= true then return false, nil end
    local d
    pcall(function() d = out.Distance end)
    return true, (type(d) == "number") and d or 0
end

-- Lift cabin -------------------------------------------------------------------------------------
-- The cabin's OverlapBox (the box that tells the lift you are inside) as centre, half size, yaw.
local function liftBox()
    if not (L.lift and U.alive(L.lift, L.liftAddr)) then return nil end
    local box = U.get(L.lift, P.LiftBox, nil)
    if not U.valid(box) then return nil end
    local ok, b = pcall(function()
        local c = box:K2_GetComponentLocation()
        local e = box:GetScaledBoxExtent()
        local y = box:K2_GetComponentRotation().Yaw
        return { X = c.X, Y = c.Y, Z = c.Z, EX = e.X, EY = e.Y, EZ = e.Z, yaw = y }
    end)
    if not ok or b.EX < 50 or b.EY < 50 then return nil end
    return b
end

local function inBox(b, p, margin)
    local r = math.rad(-b.yaw)
    local dx, dy = p.X - b.X, p.Y - b.Y
    local lx = dx * math.cos(r) - dy * math.sin(r)
    local ly = dx * math.sin(r) + dy * math.cos(r)
    return math.abs(lx) <= b.EX - margin and math.abs(ly) <= b.EY - margin and math.abs(p.Z - b.Z) <= b.EZ + 120
end

-- Spots --------------------------------------------------------------------------------------
-- Around you (forward, right in cm): beside and behind you first.
local RING = { { -100, -60 }, { -100, 60 }, { -180, -60 }, { -180, 60 }, { -20, -110 }, { -20, 110 },
    { -260, 0 }, { -100, -150 }, { -100, 150 }, { 70, -110 }, { 70, 110 }, { -180, -150 }, { -180, 150 },
    { -260, -100 }, { -260, 100 }, { 140, 0 } }

local function spots(pl, yaw, box)
    local out = {}
    if box then -- a grid over the cabin floor, nearest to you first: they line up inside the lift
        local r = math.rad(box.yaw)
        local c, s = math.cos(r), math.sin(r)
        local step = 80
        local x = -box.EX + 45
        while x <= box.EX - 45 do
            local y = -box.EY + 45
            while y <= box.EY - 45 do
                out[#out + 1] = { X = box.X + x * c - y * s, Y = box.Y + x * s + y * c }
                y = y + step
            end
            x = x + step
        end
        table.sort(out, function(a, b) return U.dist2(a, pl) < U.dist2(b, pl) end)
    else
        local r = math.rad(yaw)
        local c, s = math.cos(r), math.sin(r)
        for _, o in ipairs(RING) do
            out[#out + 1] = { X = pl.X + o[1] * c - o[2] * s, Y = pl.Y + o[1] * s + o[2] * c }
        end
    end
    return out
end

local function freeOf(p, taken, gap)
    for _, t in ipairs(taken) do
        if U.dist2(p, t) < gap then return false end
    end
    return true
end

-- Puts each ally of `list` on a checked spot. taken: positions already used (you, the others).
local function place(list, player, pl, feet, yaw, box, taken, why)
    if #list == 0 then return 0 end
    local chest = { X = pl.X, Y = pl.Y, Z = feet + 130 }
    local placed, i = 0, 1
    for pass = 1, 2 do
        local gap = (pass == 1) and 75 or 60
        for _, sp in ipairs(spots(pl, yaw, box)) do
            if i > #list then break end
            if U.dist2(sp, pl) >= 70 and freeOf(sp, taken, gap) then
                -- a clear line from you to the spot (no wall, no lift door between)
                local blocked = trace(player, chest, { X = sp.X, Y = sp.Y, Z = feet + 130 })
                if blocked == false then
                    -- a floor at your height under it
                    local hit, d = trace(player, { X = sp.X, Y = sp.Y, Z = feet + 100 }, { X = sp.X, Y = sp.Y, Z = feet - 150 })
                    local fz = hit and (feet + 100 - d) or nil
                    if fz and d > 1 and math.abs(fz - feet) <= 45 then
                        local r = list[i]
                        local loc = { X = sp.X, Y = sp.Y, Z = fz + U.halfHeight(r.obj) + 4 }
                        local okT, moved = pcall(function() return r.obj:K2_TeleportTo(loc, { Pitch = 0, Yaw = yaw, Roll = 0 }) end)
                        if okT and moved ~= false then
                            pcall(function() r.obj.CharacterMovement:StopMovementImmediately() end)
                            pcall(function() r.obj.Controller:StopMovement() end)
                            taken[#taken + 1] = loc
                            placed, i = placed + 1, i + 1
                            r.placedAt = os.clock()
                            if fixOn("ArrivalHoldFire") and SF then SF.hold(r.a, cfg().Allies.HoldFireSeconds) end
                            U.log(string.format("placed %s %s (%s) at %.0f %.0f %.0f", r.kind, U.className(r.obj) or "?", why,
                                loc.X, loc.Y, loc.Z))
                        end
                    end
                end
            end
        end
        if i > #list then break end
    end
    L.stats.placed = L.stats.placed + placed
    if i <= #list then
        L.stats.failed = L.stats.failed + (#list - i + 1)
        U.log(string.format("no free spot for %d ally(ies) (%s)", #list - i + 1, why))
    end
    return placed
end

-- What is wrong with where this ally stands (nil = fine).
-- arrival: "squad" = only your squad is brought from far away, "all" = every ally (lift, new floor).
local function wrong(r, loc, pl, feet, box, player, arrival)
    local d2 = U.dist2(loc, pl)
    if d2 > cfg().Allies.LeftBehind then
        return (arrival == "all" or (arrival == "squad" and r.kind == "squad")) and "left behind" or nil
    end
    local aFeet = loc.Z - U.halfHeight(r.obj)
    if d2 < 600 and math.abs(aFeet - feet) > 60 then return "in or above the floor" end
    if box then
        if not inBox(box, loc, 0) then return "outside the lift" end
        return nil
    end
    if d2 < 800 then
        -- the trace may stop on the ally itself: a wall only if it stops well before it
        local hit, d = trace(player, { X = pl.X, Y = pl.Y, Z = feet + 130 }, { X = loc.X, Y = loc.Y, Z = aFeet + 130 })
        if hit == true and d and d < U.dist2(pl, loc) - 60 then return "behind a wall" end
    end
    return nil
end

-- Check all allies (arrival = after a ride / floor change: allies far away are brought too;
-- inLift = a lift event: only when you are inside that lift's cabin).
function L.check(why, arrival, inLift)
    if not fixOn("LiftLineUp") and not fixOn("SafeCatchUp") then return end
    local player = U.player()
    if not U.valid(player) or U.get(player, "Flying?", false) then return end
    local pl = U.location(player)
    if not pl then return end
    local feet = pl.Z - U.halfHeight(player)
    local box = liftBox()
    if box and not inBox(box, pl, 0) then box = nil end -- you are not in that lift
    if inLift and not box then return end
    L.stats.checks = L.stats.checks + 1
    if arrival == "all" then noteQuestAllies() end
    local bad, taken = {}, { pl }
    for _, r in pairs(L.allies) do
        if usable(r) then
            local loc = U.location(r.obj)
            if loc then
                local w = wrong(r, loc, pl, feet, box, player, arrival)
                if w then bad[#bad + 1] = r; U.log(string.format("%s %s: %s (%.0f m)", why, r.kind, w, U.dist(loc, pl) / 100))
                else taken[#taken + 1] = loc end
            end
        end
    end
    if #bad > 0 then place(bad, player, pl, feet, U.yaw(player), box, taken, why) end
end

-- One ally the game just teleported next to you (SafeCatchUp).
function L.checkOne(r, why)
    if not fixOn("SafeCatchUp") then return end
    local player = U.player()
    if not U.valid(player) or not usable(r) then return end
    local pl, loc = U.location(player), U.location(r.obj)
    if not (pl and loc) then return end
    local feet = pl.Z - U.halfHeight(player)
    local box = liftBox()
    if box and not inBox(box, pl, 0) then box = nil end
    local w = wrong(r, loc, pl, feet, box, player, false)
    if not w then return end
    U.log(string.format("%s %s: %s", why, r.kind, w))
    local taken = { pl }
    for _, o in pairs(L.allies) do
        if o ~= r and usable(o) then local l = U.location(o.obj); if l then taken[#taken + 1] = l end end
    end
    place({ r }, player, pl, feet, U.yaw(player), box, taken, why)
end

-- Events -----------------------------------------------------------------------------------------
-- A few looks over the next seconds: the game's own teleports and level streaming come late.
-- who: "all" after a lift ride or a new floor, "squad" after any other jump of yours.
local function arrival(why, inLift, who)
    if not fixOn("LiftLineUp") then return end
    for _, t in ipairs(cfg().Allies.CheckAfter) do
        GT.after(t, function() L.check(why, who or "all", inLift) end)
    end
end
L.arrival = arrival

-- BP_Elevator:TeleportAlly (post): the game has just put its "Ally" companions on Exit1 / Exit2.
function L.onTeleportAlly(self)
    local lift = U.param(self)
    if U.valid(lift) then L.lift, L.liftAddr, L.liftT = lift, U.addr(lift), os.clock() end
    noteQuestAllies()
    arrival("lift ride", true)
end

-- BP_Elevator:UpdateNPCPoints(Moveing) (post): a ride starts (true) or ends (false).
function L.onLiftPoints(self, movingP)
    local lift = U.param(self)
    if U.valid(lift) then L.lift, L.liftAddr, L.liftT = lift, U.addr(lift), os.clock() end
    arrival(U.param(movingP) and "lift start" or "lift stop", true)
end

-- Q1_DungeonManager:MovedToFloor (post)
function L.onFloor() arrival("new floor") end

-- Master_Soldier:SetWalkSpeed(_Guarded) (post): the game may have just teleported it next to you.
function L.onSoldierWalk(sol)
    local r = L.noteSoldier(sol)
    if not r then return end
    local now, loc = os.clock(), U.location(sol)
    local prev, prevT = r.lastLoc, r.lastT
    r.lastLoc, r.lastT = loc, now
    if prev and loc and now - (prevT or now) < 5 and U.dist(prev, loc) > 2000 then
        L.checkOne(r, "catch-up teleport")
    end
end

-- Every 0.25 s: you moved more than 15 m since the last look = arrival somewhere new.
local last, lastT
function L.tick(now)
    local p = U.player()
    local loc = U.location(p)
    if not loc then last = nil; return end
    if last and now - lastT < 1.0 and U.dist(last, loc) > 1500 and not U.get(p, "Flying?", false) then
        arrival("you moved " .. math.floor(U.dist(last, loc) / 100) .. " m", false, "squad")
    end
    last, lastT = loc, now
end

function L.reset() L.allies, classOf, L.lift, L.liftAddr = {}, {}, nil, nil; last = nil end

return L
