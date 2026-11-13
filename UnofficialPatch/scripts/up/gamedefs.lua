--[[
  Every SpaceBourne 2 internal name the Unofficial Patch uses: after a game update, this is the
  file to check. Names come from the game's Blueprints (UE 4.27, build of 2026-10-26).
]]

local G = {}

-- Classes -----------------------------------------------------------------------------------
G.Shooter     = "/Game/1Data/11_AI/Q1_Shooter_AI.Q1_Shooter_AI_C"            -- every on-foot NPC with a gun
G.Soldier     = "/Game/1Data/11_AI/BattleAI/Master_Soldier.Master_Soldier_C" -- squad and battle soldiers
G.HandWeapon  = "/Game/1Data/Weapons/Hand_Weapons/Weapons/Master_Hand_Weapon.Master_Hand_Weapon_C"
G.Elevator    = "/Game/1Data/Interactives/BP_Elevator.BP_Elevator_C"          -- station lifts (cabin + floors)
G.DungeonMgr  = "/Game/1Galaxy/1_CPP_Dungeons/Q1_DungeonManager.Q1_DungeonManager_C" -- dungeon floors
G.GameBuilder = "/Game/1Data/Game_Builder.Game_Builder_C"
G.ShootCoverBT = "/Game/1Data/11_AI/1_VAL_ShootCover.1_VAL_ShootCover"      -- the shooters' combat tree
G.KismetSystem = "/Script/Engine.Default__KismetSystemLibrary"
G.Statics      = "/Script/Engine.Default__GameplayStatics"

G.SquadClass     = "Q1_GroundSquad_C"     -- your ground squad (a Master_Soldier)
G.CompanianClass = "Master_Companian_C"   -- quest companions the station lifts teleport (tag "Ally")
G.PlayerClass    = "Q1_Character_C"

-- Hooked Blueprint functions (UE4SS 3.0.1: every callback runs after the Blueprint body) ------
G.Fn = {
    -- lifts
    TeleportAlly    = G.Elevator .. ":TeleportAlly",       -- puts each "Ally" companion on Exit1 / Exit2
    NPCPoints       = G.Elevator .. ":UpdateNPCPoints",    -- (Moveing) ride starts (true) / ends (false)
    MovedToFloor    = G.DungeonMgr .. ":MovedToFloor",     -- dungeon: arrived on a new floor
    -- squad soldiers
    SoldierUpdate   = G.Soldier .. ":UpdateBattle",        -- 1.5 s timer: target, aim and fire
    SoldierWalk     = G.Soldier .. ":SetWalkSpeed",        -- following you; teleports beyond 30 m
    SoldierWalkOrd  = G.Soldier .. ":SetWalkSpeed_Guarded",
    SoldierShot     = G.Soldier .. ":OnProjectileCreated_7BDC272F4B923FF09908358E50762F8D",
    -- shooters
    Think           = G.Shooter .. ":CheckMeleeDistance",  -- 1 s timer on every shooter
    ShooterShots    = {
        G.Shooter .. ":OnProjectileCreated_03F94406443931C1DCEDC2920A189A84",
        G.Shooter .. ":OnProjectileCreated_EA71D2CB4AF2DDD1487199994F37FD32",
    },
    -- imported fixes
    AddAmmo         = G.GameBuilder .. ":Add Ammo",         -- (RowName, Amount, ByName, Name)
}

-- Projectile-hit events (OutProjectileObject, OutHitResult, ...): imported "end bullets after hit"
G.NpcProjectileHits = {
    G.Shooter .. ":OnProjectileHit_03F94406443931C1DCEDC2920A189A84",
    G.Shooter .. ":OnProjectileHit_EA71D2CB4AF2DDD1487199994F37FD32",
    G.Soldier .. ":OnProjectileHit_7BDC272F4B923FF09908358E50762F8D",
    "/Game/1Data/11_AI/TeamBattle/Q1_Battle_AI.Q1_Battle_AI_C:OnProjectileHit_9835CF3447B6AF136D21F992D0240016",
    "/Game/1Data/11_AI/TeamBattle/BattleObjects/RTS_Turret.RTS_Turret_C:OnProjectileHit_C3F8D03949DD49D1E6C65EA11C41015D",
    "/Game/1Data/11_AI/TeamBattle/Battle_Drone.Battle_Drone_C:OnProjectileHit_D0A49B3840F72CF10A2487AC824BB302",
}
G.PlayerProjectileHits = {}
for _, guid in ipairs({ "C6643AF84D4AB4342E72C7AF57715CE6", "9DAC8CC648A8DCFEE1BE598B9C94CA79", "52750BFC4CD152D861F06D9309C7FA39",
    "EFC583864537553C5A543D852264593A", "AEEB3FF9468D66E105DB4892C03A6C07", "C17D4B8141472A906D873E9C2C08887D",
    "808BFD2441DD8B73192818A6FB4C2BD5" }) do
    G.PlayerProjectileHits[#G.PlayerProjectileHits + 1] = G.HandWeapon .. ":OnProjectileHit_" .. guid
end

-- Properties (exactly as in the Blueprints) ---------------------------------------------------
G.P = {
    -- shooters (Q1_Shooter_AI)
    AIType = "AIType", Dead = "NPCDead", Ready = "Ready?", Injured = "InInjuredMode", HP = "CurrentHP", MaxHP = "MaxHP",
    Deaf = "AttackPlayerWhenSpawn",     -- true: CheckForFirstFocus (every alert, every hit) does nothing
    MoveActor = "TacticleMoveActor",    -- the spot a TacticleMove walks to with the eyes off
    Boss = "IsBoss", EyeSight = "XVisionEye", EyeRifle = "RifleEye", IsCompanion = "IsCompanian", CivilCompanion = "CivilCompanian?",
    ShootTarget = "ShooTarget", LastDetected = "LastDetectedActor", ProjLife = "In Projectile Life Time",
    -- squad soldiers (Master_Soldier)
    Side = "AI_Type", Target = "C_Target", Tier = "Tier", MainTimer = "MainTimer",
    -- lift
    LiftBox = "OverlapBox", LiftMoving = "Elevator_Moving?",
    -- on-foot HUD (Ammo Discipline's finding): Q1Controller.ShipMainWidget -> Curved_Widget_Test,
    -- whose CustomEvent_13 re-reads your spare rounds 2 s later
    HudMain = "ShipMainWidget", HudCurved = "Curved_Widget_Test", HudRefresh = "CustomEvent_13",
}

G.AIType = { Enemy = 0, Ally = 1, Civil = 2, Natural = 3, Guard = 4 }
G.Gait   = { Walk = 0, Run = 1, Sprint = 2 }

return G
