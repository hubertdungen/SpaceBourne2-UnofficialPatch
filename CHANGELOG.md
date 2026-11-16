# Changelog

## 0.1.1 — 2026-11-16

- **Fixed: allies firing at enemies with no effect (DormantTargets).** 0.1.0 treated "eyes off" as "not active yet"
  and removed every squad round fired at such an enemy. Silent Ops switches the eyes of every enemy that has not
  noticed anyone yet off, so with Silent Ops installed the squad's rounds were removed for good: the enemy was never
  hit, never noticed anyone, and its eyes never came back. Enemies walked around and the squad shot them with no effect.
  A target now counts as not active only while it is not ready or inside its spawn grace (1.5 s after it first shows up;
  5 s for a boss intro). Eyes off alone never counts. Enemies that really stayed blind after a lift are still woken by
  WakeLiftEnemies.
- The debug report counts the rounds removed for "not active yet" by reason, and test builds have a `legacy` / `modern`
  debug command to compare the old and the new rule in one run.
- If you are on 0.1.0 and see this, `DormantTargets = false` in `config.lua` is the workaround.

## 0.1.0 — 2026-11-12

First release.

- Allies line up inside the lift after a ride or a new dungeon floor; a checked spot next to you.
- The game's catch-up teleport no longer leaves squad soldiers in the floor, behind a wall or outside the lift.
- Allies that just arrived hold fire for 1.5 s.
- Enemies that came out of a lift blind and deaf and never got their senses back start fighting.
- Squad soldiers take a reaction time (by tier) before the first shot at a new target; rounds that
  would pass through you are removed.
- Allies (squad and companions) no longer fire at enemies that are not active yet: blind, not ready or just spawned; bosses get a 5 s intro (BossGrace).
- The squad is checked a few seconds after every load (soldiers in or under the floor).
- Imported, only while the owner is off: frozen bullets after a hit, companions' 0 s bullets, squad keep-up (HTR),
  HUD spare-ammo count after a pickup (Ammo Discipline).
