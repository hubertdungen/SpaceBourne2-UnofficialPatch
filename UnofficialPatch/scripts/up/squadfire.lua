--[[
  Allies who turn and fire in the same instant (fixes SquadReaction, FriendlyFireGuard, and the
  hold of ArrivalHoldFire).

  What the game does (Master_Soldier, build 2026-10-26): every 1.5 s UpdateBattle looks for a target
  and, in the same call, switches to aiming, snaps its focus to it and fires (BattleShoot /
  PistolShot): no time to turn, no reaction time. Idle soldiers keep their focus on you, so a target
  behind you means rounds coming your way.

  What the patch does, with UE4SS 3.0.1 post-hooks only (nothing can be stopped before it runs):
  - the rounds a squad soldier fires at a target it has just picked are removed until its reaction
    time is over (by tier: rookies slower, veterans faster); then the soldier fires its first burst
    with the game's own function. A soldier just put on a spot (lift, catch-up) holds fire a moment.
  - any round of a squad soldier or companion whose line passes through you before it reaches its
    target is removed (it would hit you).
  The round is ended with the projectile plugin's own Destroy(), the same call HTR uses.
]]

local U = require("up.util")
local G = require("up.gamedefs")
local P = G.P

local S = { st = {}, removed = 0, guarded = 0, refired = 0 }
local GT
function S.init(gt) GT = gt end
local function cfg() return UNOFFICIAL_PATCH.cfg.SquadFire end
local function fixOn(name) return UNOFFICIAL_PATCH.fixes[name] == true end

local function state(a)
    local s = S.st[a]
    if not s then
        local n = 0
        for _ in pairs(S.st) do n = n + 1 end
        if n > 100 then S.st = {} end
        s = {}
        S.st[a] = s
    end
    return s
end

function S.hold(a, secs)
    if not a then return end
    local s = state(a)
    s.holdUntil = math.max(s.holdUntil or 0, os.clock() + (secs or 1.5))
end

-- Never inside the "created" event itself: the projectile plugin is still setting the round up
-- there, and ending it then crashed the game (access violation, test launch 1). The round is ended
-- at the next game-thread pump instead (a frame later, about 1-2 m into its flight).
local pending, flushing = {}, false
local function flush()
    flushing = false
    local list = pending
    pending = {}
    for _, proj in ipairs(list) do
        if U.valid(proj) then pcall(function() proj:Destroy() end) end
    end
end
local function destroy(proj)
    if #pending >= 200 then return false end
    pending[#pending + 1] = proj
    if not flushing then flushing = true; GT.after(0, flush) end
    return true
end

local function vec(p)
    local v = U.param(p)
    if not v then return nil end
    local ok, t = pcall(function() return { X = v.X, Y = v.Y, Z = v.Z } end)
    return ok and t or nil
end

-- Does the line from o along dir pass through you before it reaches the target?
local function throughYou(o, dir, target)
    local player = U.player()
    local pl = U.location(player)
    if not (o and dir and pl) then return false end
    local len = math.sqrt(dir.X ^ 2 + dir.Y ^ 2 + dir.Z ^ 2)
    if len < 1e-6 then return false end
    local dx, dy, dz = dir.X / len, dir.Y / len, dir.Z / len
    local t = (pl.X - o.X) * dx + (pl.Y - o.Y) * dy + (pl.Z - o.Z) * dz
    if t <= 0 or t > 8000 then return false end
    local tl = U.location(target)
    if tl then
        local tt = (tl.X - o.X) * dx + (tl.Y - o.Y) * dy + (tl.Z - o.Z) * dz
        if t > tt - 40 then return false end -- you are behind the target
    end
    local px, py, pz = o.X + dx * t - pl.X, o.Y + dy * t - pl.Y, o.Z + dz * t - pl.Z
    return math.sqrt(px * px + py * py) < cfg().GuardRadius and math.abs(pz) < U.halfHeight(player) + 20
end

-- Enemies that are not active yet: blind (eyes off: the lift-spawn state), not ready, or spawned
-- less than SpawnGrace seconds ago. Allies "see" them the moment they appear and open fire; with
-- DormantTargets the rounds fired at them are removed. Only shooters (AIType = enemy) count.
S.born, S.bornCount = {}, 0
function S.noteBorn(npc)
    local a = U.addr(npc)
    if not a or S.born[a] then return end
    if S.bornCount > 600 then S.born, S.bornCount = {}, 0 end
    S.born[a] = os.clock()
    S.bornCount = S.bornCount + 1
end
local function dormant(tgt)
    if not (fixOn("DormantTargets") and U.valid(tgt)) then return false end
    if U.get(tgt, P.AIType, nil) ~= G.AIType.Enemy then return false end
    if U.get(tgt, P.Ready, true) == false then return true, "not ready" end
    local eye = U.get(tgt, P.EyeSight, nil)
    if U.valid(eye) then
        local ok, act = pcall(function() return eye:IsActive() end)
        if ok and act == false then return true, "eyes off" end
    end
    local b = S.born[U.addr(tgt) or 0]
    if S.bornCount > 0 and b and os.clock() - b < cfg().SpawnGrace then return true, "just spawned" end
    return false
end

local function reactionOf(sol)
    local list = cfg().ReactionByTier
    local tier = math.floor(tonumber(U.get(sol, P.Tier, 0)) or 0)
    return list[math.max(1, math.min(#list, tier + 1))]
end

local function refire(sol, a, ta)
    if not U.alive(sol, a) or U.get(sol, P.Dead, false) or U.get(sol, P.Injured, false) then return end
    local tgt = U.get(sol, P.Target, nil)
    if not (U.valid(tgt) and U.addr(tgt) == ta) then return end
    if U.get(tgt, P.Dead, false) then return end
    local s = state(a)
    S.refired = S.refired + 1
    if s.pistol then pcall(function() sol:PistolShot() end) else pcall(function() sol:BattleShoot() end) end
end

-- Master_Soldier:OnProjectileCreated_* (post): (OutProjectileObject, OutAttachComponents, OutProjectileLocation, OutProjectileDirection)
function S.onSoldierShot(self, projP, attachP, locP, dirP)
    local sol = U.param(self)
    if not U.valid(sol) or U.get(sol, P.Side, 1) ~= G.AIType.Ally then return end
    local proj = U.param(projP)
    if not U.valid(proj) then return end
    local a = U.addr(sol)
    local s = state(a)
    local now = os.clock()
    local tgt = U.get(sol, P.Target, nil)
    local ta = U.valid(tgt) and U.addr(tgt) or nil
    if now < (s.holdUntil or 0) then
        if destroy(proj) then S.removed = S.removed + 1 end
        return
    end
    local dm, dwhy = dormant(tgt)
    if dm then
        if destroy(proj) then S.removed = S.removed + 1; S.dormant = (S.dormant or 0) + 1 end
        if s.dormantLog ~= ta then s.dormantLog = ta; U.log("squad soldier: target not active (" .. dwhy .. "), no fire") end
        return
    end
    if fixOn("SquadReaction") and ta then
        if ta ~= s.target then s.target, s.acq, s.refire = ta, now, false end
        local react = reactionOf(sol)
        if now - s.acq < react then
            if destroy(proj) then S.removed = S.removed + 1 end
            if not s.refire then
                s.refire = true
                U.log(string.format("squad soldier %s: new target %s, holds fire %.2f s", tostring(a), tostring(U.className(tgt)), react))
                GT.after(react - (now - s.acq) + 0.05, function() refire(sol, a, ta) end)
            end
            return
        end
    end
    if fixOn("FriendlyFireGuard") and throughYou(vec(locP), vec(dirP), tgt) then
        if destroy(proj) then S.guarded = S.guarded + 1 end
    end
end

-- Master_Soldier:PistolShot (post): which of its two fire functions the soldier uses.
function S.onPistol(self) local sol = U.param(self); local a = U.addr(sol); if a then state(a).pistol = true end end
function S.onRifle(self) local sol = U.param(self); local a = U.addr(sol); if a then state(a).pistol = false end end

-- Q1_Shooter_AI:OnProjectileCreated_* (post): companions only.
function S.onShooterShot(self, projP, attachP, locP, dirP)
    local npc = U.param(self)
    if not U.valid(npc) or U.get(npc, P.IsCompanion, false) ~= true then return end
    local proj = U.param(projP)
    if not U.valid(proj) then return end
    local s = S.st[U.addr(npc) or 0]
    if s and os.clock() < (s.holdUntil or 0) then
        if destroy(proj) then S.removed = S.removed + 1 end
        return
    end
    local tgt
    pcall(function() tgt = npc[P.ShootTarget].DetectedActor end)
    if not U.valid(tgt) then tgt = U.get(npc, P.LastDetected, nil) end
    if dormant(tgt) then
        if destroy(proj) then S.removed = S.removed + 1; S.dormant = (S.dormant or 0) + 1 end
        return
    end
    if not fixOn("FriendlyFireGuard") then return end
    if throughYou(vec(locP), vec(dirP), tgt) and destroy(proj) then S.guarded = S.guarded + 1 end
end

return S
