--[[
  Enemies that come out of a lift and ignore you (fix WakeLiftEnemies).

  What the game does (Q1_Shooter_AI, build 2026-10-26): an enemy spawned with
  AttackPlayerWhenSpawn = true and a TacticleMoveActor (the spot outside the lift it must reach)
  runs TacticleMove: both eyes are switched off (XVisionEye, RifleEye) and a timer turns them back
  on, with the combat tree, only once the NPC is within 2 m of that spot. 0.1 s after spawning the
  Blueprint also starts the combat tree, which can take the NPC elsewhere. If it never gets within
  2 m (blocked, pushed, sent elsewhere), its eyes stay off for good. And AttackPlayerWhenSpawn = true
  makes CheckForFirstFocus - the handler of every alert and of every hit - return at once.
  Blind and deaf: it walks around and never fights back.

  What the patch does: once a second (the shooter's own 1 s timer, CheckMeleeDistance), an enemy that
  is still blind and deaf on its way to that spot, and has not come closer to it for StuckSeconds, or
  has been at it for MaxSeconds, or was hit meanwhile, gets what the game gives it on arrival: eyes on,
  combat tree started, and it can hear alerts and hits again.
  Silent Ops keeps unaware enemies blind and deaf on purpose; it never does that to NPCs that spawn
  already deaf (lift and drop-ship waves), and an NPC is only touched here while it has a lift spot
  more than 2.5 m away, so Silent Ops' own NPCs are left alone.
]]

local U = require("up.util")
local G = require("up.gamedefs")
local P = G.P

local W = { watch = {}, woken = 0 }
local function cfg() return UNOFFICIAL_PATCH.cfg.LiftEnemies end

local BT
local function tree()
    if not U.valid(BT) then BT = StaticFindObject(G.ShootCoverBT) end
    return U.valid(BT) and BT or nil
end

local function active(comp)
    local ok, v = pcall(function() return comp:IsActive() end)
    return ok and v == true
end

local function wake(npc, a, why)
    for _, name in ipairs({ P.EyeSight, P.EyeRifle }) do
        local eye = U.get(npc, name, nil)
        if U.valid(eye) then pcall(function() eye:SetActive(true, false) end) end
    end
    U.set(npc, P.Deaf, false)
    local bt = tree()
    if bt then pcall(function() npc.Controller:RunBehaviorTree(bt) end) end
    W.watch[a] = nil
    W.woken = W.woken + 1
    U.log("woke a lift enemy (" .. why .. "): " .. tostring(U.className(npc)))
end

-- Q1_Shooter_AI:CheckMeleeDistance (post), every second on every shooter.
function W.onThink(npc, now)
    if U.get(npc, P.AIType, -1) ~= G.AIType.Enemy then return end
    local a = U.addr(npc)
    if not a then return end
    if U.get(npc, P.Dead, false) or not U.get(npc, P.Deaf, false) then W.watch[a] = nil; return end
    local spot = U.get(npc, P.MoveActor, nil)
    local eye = U.get(npc, P.EyeSight, nil)
    if not (U.valid(spot) and U.valid(eye)) or active(eye) then W.watch[a] = nil; return end
    local d = U.dist(U.location(npc), U.location(spot))
    if d <= 250 then W.watch[a] = nil; return end -- arriving: the game's own timer wakes it
    local hp = U.get(npc, P.HP, 0)
    local w = W.watch[a]
    if not w then
        local n = 0
        for _ in pairs(W.watch) do n = n + 1 end
        if n > 200 then W.watch = {} end
        W.watch[a] = { since = now, best = d, bestAt = now, hp = hp }
        return
    end
    if d < w.best - 50 then w.best, w.bestAt = d, now end
    local c = cfg()
    if hp < w.hp - 0.5 then wake(npc, a, "hit")
    elseif now - w.bestAt >= c.StuckSeconds then wake(npc, a, string.format("stuck %.0f m from its spot", d / 100))
    elseif now - w.since >= c.MaxSeconds then wake(npc, a, "too long") end
end

return W
