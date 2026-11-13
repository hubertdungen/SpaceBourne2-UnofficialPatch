--[[
  Unofficial Patch settings. Open with Notepad, save, restart the game.
  Every fix is on by default; set one to false to get the game's own behaviour back.
]]
return {
    Enabled = true,

    Fixes = {
        -- Allies and lifts
        LiftLineUp      = true,  -- after a lift ride or a new floor, allies stand inside the lift next to you
        SafeCatchUp     = true,  -- the game's catch-up teleport never leaves an ally in a wall, in the floor or outside
        ArrivalHoldFire = true,  -- an ally just put on a spot holds fire a moment (HoldFireSeconds)
        -- Enemies
        WakeLiftEnemies = true,  -- enemies out of a lift that stayed blind and deaf start fighting
        -- Squad fire
        SquadReaction     = true, -- squad soldiers take a reaction time before the first shot at a new target
        FriendlyFireGuard = true, -- squad and companion rounds that would go through you are removed
        DormantTargets    = true, -- allies don't fire at enemies that are not active yet (blind, not ready, just spawned)

        -- Fixes other mods of the set already have. Applied only while that mod is off.
        EndBulletsAfterHit = true, -- frozen bullets after a hit (load crash after a long firefight); HTR has it
        CompanionBullets   = true, -- companions' bullets that did nothing; HTR has it
        SquadKeepUp        = true, -- squad runs / sprints to keep up instead of walking; HTR has it
        AmmoHudRefresh     = true, -- HUD spare-ammo count updates after a pickup; Ammo Discipline has it
    },

    Allies = {
        CheckAfter      = { 0.4, 1.5, 3.5 }, -- seconds after a ride / floor change when allies are checked
        LeftBehind      = 1500,  -- cm: after a ride, an ally farther than this is brought to you
        HoldFireSeconds = 1.5,
    },

    LiftEnemies = {
        StuckSeconds = 3,   -- not closer to its lift spot for this long: woken
        MaxSeconds   = 12,  -- still blind after this long: woken
    },

    SquadFire = {
        ReactionByTier = { 0.7, 0.6, 0.5, 0.4, 0.35 }, -- seconds, soldier tier 0 .. 4
        GuardRadius    = 60,  -- cm: a round passing closer than this to you is removed
        SpawnGrace     = 1.5, -- seconds after an enemy first shows up before allies may fire at it
    },

    Imported = { RunBeyond = 600, SprintBeyond = 1500 }, -- SquadKeepUp, cm (same as HTR)

    Debug = { Log = false }, -- true: UnofficialPatch\unofficialpatch.log tells what each fix did
}
