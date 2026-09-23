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

Player rays use one additive mesh with no opaque core, halo shell or tapered wake. Default speed is 32× (38.4 km/s); damage is independently 32× the hull base damage. Both are editable on Main. Swept collision still uses a 30 cm diameter and a 3 km range.

Each shot starts as an 80 m launch pulse. In flight, a capped 1/60-second exposure
stretches the visible pulse up to 640 m, using motion relative to the firing ship
so inherited cruise velocity cannot skew the streak. Impact/range termination
keeps the final clipped segment for a 45 ms fade, as a bounded, visual-only trace.
It cannot damage anything or extend past its resolved endpoint. This retains the
shot's last visible path even when its entire flight completes between frames.

A short white muzzle lance lights the local hull, the firing cannon's emitter
flares and cools over 120 ms, and impacts flash then collapse. These effects use
shared procedural meshes and per-instance fading, with no new imported assets.
Gun transforms and the shared aiming point remain independent of the discharge.

Atmospheric shots and their hit traces inherit the same planetary frame rotation
as the ship, separately from ordinary inherited velocity. Without that transport,
an eight-minute Earth cycle carries the equatorial ship about 83 km/s sideways
while its bullets remain behind. Gun convergence also selects the intercept branch
nearest the requested firing direction; when ship drift exceeds muzzle speed, the
earliest intercept can otherwise point backwards. Already-fired shots never turn
with later ship steering. `tools/test_plasma_frame.tscn` covers rotation, headings,
0.5×/32×/256× speeds, fast drift, independent flight and anchor handoffs.
