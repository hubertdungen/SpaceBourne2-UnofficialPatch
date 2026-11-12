--[[
  Game bugs that other mods of the set already fix. The patch applies each one only when the mod
  that has it is off (compat.lua), so nothing is fixed twice.

  - EndBulletsAfterHit (from HTR 0.4.6 / 0.4.11): a bullet often stays alive, frozen, for over a
    minute after its hit. Loading while many are around (dying in a long firefight, the death screen
    loads your last save) can crash the game ("Fatal error", access violation reading 0x268). The
    bullet is ended with the projectile plugin's own Destroy() right after the game handled its hit.
  - CompanionBullets (from HTR): companions shoot projectiles that live 0 s and do nothing.
  - SquadKeepUp (from HTR 0.4.2): the game only ever gives following squad soldiers the walk gait,
    so they fall behind and then appear next to you through the 30 m catch-up teleport. They run
    beyond RunBeyond and sprint beyond SprintBeyond instead.
  - AmmoHudRefresh (from Ammo Discipline 0.1.1): the on-foot HUD re-reads your spare rounds only
    after a reload or a weapon draw, never after a pickup. After a pickup the patch runs the HUD's
    own reload handler, which re-reads the count with the game's own code.
]]

local U = require("up.util")
local G = require("up.gamedefs")
local P = G.P

local I = { ended = 0, companions = 0, hud = 0 }
local GT
function I.init(gt) GT = gt end
local function cfg() return UNOFFICIAL_PATCH.cfg end

-- EndBulletsAfterHit: post-hook of every OnProjectileHit_* (OutProjectileObject first).
function I.endAfterHit(self, projP)
    local p = U.param(projP)
    if U.valid(p) and pcall(function() p:Destroy() end) then I.ended = I.ended + 1 end
end

-- CompanionBullets: from the shooter think hook, once per companion.
local fixedLife = {}
function I.companionBullets(npc)
    if U.get(npc, P.IsCompanion, false) ~= true then return end
    local a = U.addr(npc)
    if not a or fixedLife[a] then return end
    fixedLife[a] = true
    if U.get(npc, P.ProjLife, 3.0) < 1.0 then
        U.set(npc, P.ProjLife, 3.0)
        I.companions = I.companions + 1
    end
end

-- SquadKeepUp: Master_Soldier:SetWalkSpeed(_Guarded) post-hook, your squad only.
function I.keepUp(sol)
    if U.get(sol, P.Side, 1) ~= G.AIType.Ally then return end
    if U.get(sol, P.Dead, false) or U.get(sol, P.Injured, false) then return end
    local d = U.dist(U.location(sol), U.location(U.player()))
    if d >= 1e9 then return end
    local k = cfg().Imported
    local gait = (d > k.SprintBeyond) and G.Gait.Sprint or ((d > k.RunBeyond) and G.Gait.Run or G.Gait.Walk)
    pcall(function() sol:SetDesiredGait(gait) end)
    pcall(function() sol:SetGait(gait) end)
end

-- AmmoHudRefresh: Game_Builder:"Add Ammo" post-hook (RowName, Amount, ByName, Name).
local gb, scheduled = nil, false
local function refresh()
    scheduled = false
    if not U.valid(gb) then return end
    local pc
    pcall(function() pc = StaticFindObject(G.Statics):GetPlayerController(gb, 0) end)
    local main = U.valid(pc) and U.get(pc, P.HudMain, nil) or nil
    local w = U.valid(main) and U.get(main, P.HudCurved, nil) or nil
    if not U.valid(w) then return end
    -- (Publisher, Payload, Metadata): the handler only stores them; any object will do
    if pcall(function() w[P.HudRefresh](w, w, w, {}) end) then I.hud = I.hud + 1 end
end
function I.onAddAmmo(self, rowP, amountP)
    local amount = U.param(amountP)
    if type(amount) ~= "number" or amount <= 0 then return end
    gb = U.param(self)
    if scheduled then return end
    scheduled = true
    GT.after(0.08, refresh)
end

return I
