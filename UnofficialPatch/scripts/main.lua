--[[
  Unofficial Patch for SpaceBourne 2 (UE4SS Lua mod). Part of the SpaceBourne 2 realism set.
  Fixes bugs of the game itself; see README.md for what each fix does and why.

  Layout:
    config.lua          your settings (every fix can be switched off)
    up/gamedefs.lua     every game-internal name (the only file to check after a game patch)
    up/compat.lua       no double fixing: fixes other mods of the set already have
    up/lift.lua         allies and lifts: line-up, safe catch-up teleport
    up/wake.lua         enemies out of a lift that stay blind and deaf
    up/squadfire.lua    squad reaction time, friendly-fire guard, hold fire after a teleport
    up/imports.lua      fixes taken from other mods of the set (only while those are off)
    up/hooks.lua        lazy, fault-isolated hook registration (shared with the set)
    up/gametick.lua     timed work on the game thread (shared with the set; no LoopAsync)
]]

local VERSION = "0.1.1"

local U = require("up.util")

-- Settings --------------------------------------------------------------------------------------
local defaults = {
    Enabled = true,
    Fixes = { LiftLineUp = true, SafeCatchUp = true, ArrivalHoldFire = true, WakeLiftEnemies = true, SquadReaction = true,
        FriendlyFireGuard = true, DormantTargets = true, EndBulletsAfterHit = true, CompanionBullets = true, SquadKeepUp = true, AmmoHudRefresh = true },
    Allies = { CheckAfter = { 0.4, 1.5, 3.5 }, LeftBehind = 1500, HoldFireSeconds = 1.5 },
    LiftEnemies = { StuckSeconds = 3, MaxSeconds = 12 },
    SquadFire = { ReactionByTier = { 0.7, 0.6, 0.5, 0.4, 0.35 }, GuardRadius = 60, SpawnGrace = 1.5, BossGrace = 5 },
    Imported = { RunBeyond = 600, SprintBeyond = 1500 },
    Debug = { Log = false },
}
local function fill(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then dst[k] = v
        elseif type(v) == "table" and type(dst[k]) == "table" and #v == 0 then fill(dst[k], v) end
    end
end
local okCfg, cfg = pcall(require, "config")
if not okCfg or type(cfg) ~= "table" then
    U.warn("config.lua could not be read (" .. tostring(cfg) .. "); using defaults")
    cfg = {}
end
fill(cfg, defaults)
U.Verbose = cfg.Debug.Log == true

UNOFFICIAL_PATCH = { version = VERSION, cfg = cfg, fixes = {} }
if cfg.Enabled == false then
    U.warn("Unofficial Patch " .. VERSION .. " loaded, switched off in config.lua (Enabled = false)")
    return
end

local G = require("up.gamedefs")
local H = require("up.hooks")
local GT = require("up.gametick")
local C = require("up.compat")
local L = require("up.lift")
local W = require("up.wake")
local S = require("up.squadfire")
local I = require("up.imports")
GT.log = function(msg) U.warn(msg) end

-- Which fixes run: all switched on, except the ones another mod of the set already does.
local IMPORTED = { EndBulletsAfterHit = true, CompanionBullets = true, SquadKeepUp = true, AmmoHudRefresh = true }
pcall(C.scan)
local fixes = UNOFFICIAL_PATCH.fixes
for name, on in pairs(cfg.Fixes) do
    if on == true and (not IMPORTED[name] or C.mine(name)) then fixes[name] = true end
end
C.applied = fixes
L.init(GT, S)
S.init(GT)
I.init(GT)

-- Hooks (all post-hooks) ---------------------------------------------------------------------------
local allies = fixes.LiftLineUp or fixes.SafeCatchUp
if fixes.LiftLineUp then
    H.add(G.Fn.TeleportAlly, L.onTeleportAlly, "lift: allies teleported")
    H.add(G.Fn.NPCPoints, L.onLiftPoints, "lift: ride")
    H.add(G.Fn.MovedToFloor, L.onFloor, "dungeon: new floor")
end
if allies then
    H.add(G.Fn.SoldierUpdate, function(self)
        local s = U.param(self)
        if U.valid(s) then L.noteSoldier(s) end
    end, "squad: who follows you")
end
if allies or fixes.SquadKeepUp then
    local function walk(self)
        local s = U.param(self)
        if not U.valid(s) then return end
        if fixes.SquadKeepUp then I.keepUp(s) end
        if allies then L.onSoldierWalk(s) end
    end
    H.add(G.Fn.SoldierWalk, walk, "squad: follow")
    H.add(G.Fn.SoldierWalkOrd, walk, "squad: follow (orders)")
end
if fixes.SquadReaction or fixes.FriendlyFireGuard or fixes.ArrivalHoldFire or fixes.DormantTargets then
    H.add(G.Fn.SoldierShot, S.onSoldierShot, "squad: rounds")
    H.add(G.Soldier .. ":PistolShot", S.onPistol, "squad: pistol")
    H.add(G.Soldier .. ":BattleShoot", S.onRifle, "squad: rifle")
end
if fixes.FriendlyFireGuard or fixes.ArrivalHoldFire or fixes.DormantTargets then
    for i, path in ipairs(G.Fn.ShooterShots) do H.add(path, S.onShooterShot, "companion rounds " .. i) end
end
if fixes.WakeLiftEnemies or fixes.CompanionBullets or allies or fixes.DormantTargets then
    H.add(G.Fn.Think, function(self)
        local npc = U.param(self)
        if not U.valid(npc) then return end
        if fixes.WakeLiftEnemies then W.onThink(npc, os.clock()) end
        if fixes.CompanionBullets then I.companionBullets(npc) end
        if allies then L.noteShooter(npc) end
        if fixes.DormantTargets then S.noteBorn(npc) end
    end, "shooter think")
end
if fixes.EndBulletsAfterHit then
    for i, path in ipairs(G.NpcProjectileHits) do H.add(path, I.endAfterHit, "bullet end (NPC) " .. i) end
    for i, path in ipairs(G.PlayerProjectileHits) do H.add(path, I.endAfterHit, "bullet end (you) " .. i) end
end
if fixes.AmmoHudRefresh then H.add(G.Fn.AddAmmo, I.onAddAmmo, "ammo pickup: HUD count") end

-- Timed work on the game thread: the HUD draw on foot and in a ship, the ALS tick as a fallback.
GT.drive(GT.HUD_TICK, "hud")
GT.drive(GT.FOOT_TICK, "foot")
-- Every load or possession: the squad is checked once it has been registered (the game's own
-- placing at a load can leave soldiers in or under the floor: seen with a loaded test save).
GT.boot(function()
    L.reset()
    if fixes.LiftLineUp or fixes.SafeCatchUp then
        for _, t in ipairs({ 4, 9, 16 }) do GT.after(t, function() L.check("level load", "squad", false) end) end
    end
end)
GT.every(1.0, function(now) pcall(H.poll, now) end)
if fixes.LiftLineUp then
    GT.every(0.25, function(now)
        local ok, err = pcall(L.tick, now)
        if not ok then U.warn("lift tick: " .. tostring(err)) end
    end)
end

local function report()
    local on, off = H.status()
    return string.format("hooks %d on / %d off; allies: %d checks, %d placed, %d no spot, %d traces; lift enemies woken %d; "
        .. "squad rounds held %d (dormant targets %d: %s), refired %d, guarded %d; bullets ended %d; companion bullets %d; HUD refresh %d; %s",
        on, off, L.stats.checks, L.stats.placed, L.stats.failed, L.stats.traces, W.woken, S.removed, S.dormant or 0, S.dormantText(), S.refired, S.guarded,
        I.ended, I.companions, I.hud, GT.report())
end
UNOFFICIAL_PATCH.report = report
if U.Verbose then GT.every(60, function() U.log(report()); U.log("slowest hooks: " .. H.profile()) end, 60) end

-- Tests only (Debug.Commands = true): one word in UnofficialPatch\debug_cmd.txt, read once a second.
--   report | check | off <Fix> | on <Fix> | legacy | modern  (legacy = the 0.1.0 "eyes off" rule, to compare)
if cfg.Debug.Commands then
    GT.every(1.0, function()
        local f = io.open(U.Dir .. "debug_cmd.txt", "r")
        if not f then return end
        local cmd = f:read("*a") or ""
        f:close()
        os.remove(U.Dir .. "debug_cmd.txt")
        local word, arg = cmd:match("^%s*(%a+)%s*(%w*)")
        if word == "report" then U.warn(report())
        elseif word == "check" then L.check("debug", "all", false)
        elseif word == "legacy" or word == "modern" then
            S.legacyEyes = (word == "legacy") or nil
            U.warn("debug: dormant rule " .. word .. " (rounds removed so far: " .. S.removed .. ", dormant " .. S.dormantText() .. ")")
        elseif (word == "off" or word == "on") and cfg.Fixes[arg] ~= nil then
            fixes[arg] = (word == "on") or nil
            U.warn("debug: " .. arg .. " " .. word)
        end
    end)
end

local names = {}
for name in pairs(fixes) do names[#names + 1] = name end
table.sort(names)
U.warn(string.format("=== Unofficial Patch %s loaded: %s | left to other mods: %s ===", VERSION,
    table.concat(names, ", "), C.report()))
local shared = C.publish(VERSION)
U.log("SB2R_GameFixes = " .. shared)
