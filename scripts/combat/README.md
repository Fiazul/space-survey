# scripts/combat/

Dogfighting: aliens, bolts, bosses, and their transient visuals.

| File | Type | Role |
|---|---|---|
| `combat.gd` | feature area | Hitscan bolts, alien AI, named bosses, finite guardian waves |
| `combat_fx.gd` | feature area | `CombatFX` — transient combat visuals (booms/sparks/flashes) + bolt/flash materials |
| `enemy_factory.gd` | feature area | `EnemyFactory` — loads/normalizes/paints the monster GLBs, packs each into a unit dict |
