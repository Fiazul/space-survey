# scripts/combat/

Dogfighting: aliens, bolts, bosses, and their transient visuals.

| File | Type | Role |
|---|---|---|
| `combat.gd` | feature area | Shared battery aim, atmospheric plasma firing, alien AI, named bosses, finite guardian waves |
| `weapon_aim.gd` | math | Constant-velocity interception including shooter and target motion |
| `plasma_projectiles.gd` | feature area | Finite-range plasma pulses with swept collision and muzzle/impact effects |
| `combat_fx.gd` | feature area | `CombatFX` — transient combat visuals (booms/sparks/flashes) + bolt/flash materials |
| `enemy_factory.gd` | feature area | `EnemyFactory` — loads/normalizes/paints the monster GLBs, packs each into a unit dict |

The sight uses the neutral midpoint of the gun battery, independent of the next firing slot. Every gun converges on its shared surface/free-aim point; moving targets receive a per-muzzle intercept. Three pose iterations account for the muzzle moving as its mount rotates. Actual pulses still start at their visible muzzle and inherit ship velocity. `tools/test_weapon_aim.tscn` checks alternating-fire stability and convergence on all five hulls.
