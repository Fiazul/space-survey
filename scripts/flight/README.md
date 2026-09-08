# scripts/flight/

The player ship: physics, visuals, controls, and hull-specific design data.

| File | Type | Role |
|---|---|---|
| `ship.gd` | feature area | Flight physics, visuals (boosters/streaks), warp, autopilot, customization |
| `ship_mesh.gd` | feature area | Stateless mesh/material/FX build helpers for the hulls, split out of `ship.gd` |
| `flight_mode.gd` | feature area | Zone (CENTER/INSIDE/SKIN/AIR/SPACE) vs mode (LOCAL/CRUISE/AIR) + exclusion-zone math |
| `turn_carry.gd` | feature area | Sol flight assist: a turn carries velocity with the hull |
| `touch_controls.gd` | feature area | Mobile multi-touch control overlay (`--touch` to test on desktop) |
| `wedge_fighter.gd` | data | `WedgeFighterDesign` — one hull's shader/geometry design constants |
