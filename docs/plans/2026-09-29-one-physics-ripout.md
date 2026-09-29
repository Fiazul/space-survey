# One physics: removing the arcade flight model (2026-09-29)

Roadmap row S.3. Decision (player, 2026-09-28): 1 scene unit = 1 km, Newton gravity,
anchored positions in EVERY star system. No wormholes. Star-to-star is the crafted drive
first, teleport-after-first-visit later (`docs/ROADMAP.md` "September 29 direction").

Inventory below is from a read-only scout on 2026-09-29; line numbers drift. Runs on a
branch after the landing contact pass and the playable minute are committed, because it
touches the same files.

## Delete outright

- `scripts/travel/wormhole.gd` (523 lines), `WORMHOLE_NETWORK.md`, `WORMHOLE_NETWORK.png`,
  `tools/export_wh_graph.gd`, `tools/draw_wh_network.py`.
- `SystemDB` hub/graph/portal sections (`system_db.gd` ~160-447: `wormhole_pos`,
  `all_wormholes`, `_compute_stations`, `WH_HUBS`, `_ensure_graph`, `neighbors`,
  `wh_edges`, `next_hop`, `INTERSTELLAR`, `arrival_pos`, `PORTAL_LOCAL_R`, `portals`).
- `Ephemeris.MOONS` (arcade-only), `ship.gd` arcade constants: `THRUST` 1650,
  `STRAFE_THRUST` 1050, `SUBLIGHT_MAX` 550, `GRAVITY_IDLE_SPEED`, `SETTLE_*`, `DAMPING`,
  `DRIFT_DAMPING`, `WARP_ARRIVE_*` (unused), `HYPERSONIC_SPEED`, `WARP_FLOOR`,
  `SOL_FIELD_RADIUS` (unused), `WARP_CHARGE/DECAY_TIME`, per-hull `warp` and `bolt_speed`
  (dead), galactic drive (`galactic_cruising`, `galactic_loom_rate`).
- `planet_system.gd`: `STAR/PLANET_ZONE_*`, `ZONE_EDGE/FLOOR`, `_slow_min`,
  `VISUAL_SCALE`, `GRAVITY_ENABLED`, `GRAV_G`, `STAR_GRAVITY_*`, arcade moon orbits and
  static `b.pos` placement, hub star shell, `_fmt_star_dist`, `surface_angle` NAN branch.
- `GameState.wormholes_found` (already dead), `nav_unlocked` (lane-specific).

## Replace

| Area | Today | After |
|---|---|---|
| `ship.newton` flag | branches at ~14 sites | gone; one integration path |
| Autopilot | flies at warp | cruise autopilot under time compression (roadmap S.4) |
| `_arrive` | resets anchor to "Earth", arcade `arrival_pos` | per-system spawn from the system's ephemeris |
| Ephemeris | Sol singleton, name-keyed tables, geocentric frame | `SystemEphemeris` per star: Sol from JPL/NASA data, others generated at real scale from HYG mass/luminosity + seed. Same public API (below) |
| Bodies in other systems | authored arcade bodies (K2-18, Proxima, TRAPPIST, Alien) | recipe worlds at real radii/orbits, same `PlanetGenerator` cook |
| Combat constants | arcade units (`KEEP_DIST` 30, `SPAWN_RADIUS` 60, `GUARD_RANGE` 2500, bolt speeds) | re-tuned in km as ratios (roadmap S.8); until then combat stays disabled outside Sol |
| `WEAPON_FIRE_SPEED` / `SUBLIGHT_MAX` reads in combat | speed gates | combat-envelope gate (S.8) |
| HUD | "W warp", spool text, `LOCAL FLIGHT`, `SUPERCRUISE READY`, hypersonic crosshair hide | compression readout naming the frame; `AU_PER_UNIT` already assumes km |
| StarMap / MapChart / MiniMap | wormhole lanes, `DIST_SCALE` 0.072, `AU_TO_UNITS` | visited-system teleport list; km units |
| Onboarding / tutor | "wormhole" step, warp text | drop the step (ids are safe, the index shifts) |
| Saves | `off` in arcade units for non-Sol, `system="interstellar"` | migrate: non-Sol saves respawn at the system's spawn; interstellar → Sol |

## Ephemeris API the rest of the code calls (must survive unchanged)

`gravity_bodies, pos64, scene_pos, has_pos, is_anchorable, rel_km, gm, body_radius_km,
atmo_top_km, spin_rad_s, scene_spin_rad_s, surface_basis, surface_angle, solar_state,
flight_zone, surface_kill_km, sweet_spot(_off), geo_start_pos → spawn, live_worlds,
PLANETS, STARS, rotation_clock`, constants `RHO0, EARTH_*, SKY_*, CAM_RENDER_FAR_KM,
AU_TO_UNITS, UNITS_PER_LY`, plus a primary-star name replacing hardcoded "Sun"
(`planet_system.gd` ~618/804, `main.gd` ~451, `solar_state`). `FlightMode.has_drag_model`
is "Earth"-only today; becomes recipe-driven (S.5).

## Three riskiest couplings

1. **Ephemeris is a global Sol singleton.** Flipping Newton on elsewhere sums Sol's
   bodies against a fake "Earth" anchor. Anchor frame (ADR-0002), skin kill and
   co-rotation all assume Ephemeris names. Do this first, as its own slice.
2. **`_arrive` and save/restore.** Every arrival resets the anchor to "Earth". Saved `off`
   values outside Sol are arcade units. Needs a migration and a per-system spawn.
3. **Hidden gates.** `combat.gd` duck-types `has_method("is_hypersonic")`; props'
   `struct_limit` is active in Sol too; the `physical` flag gates surface tiles and
   clouds (`surface_patch.gd` ~429, `cloud_layer.gd` ~261).

## Slices (each its own brief, in order)

1. **SystemEphemeris.** Extract the Sol tables behind an instance with the API above;
   Sol behaves identically (all tests green, `test_anchor_frame` known failures aside).
   Add a generated system from an HYG star. Acceptance: fly Newton in Proxima at 1 km
   units with anchoring, no arcade code reached.
2. **Rip flight.** Delete the arcade constants and every `newton` branch; one
   integration path. `speed_zones`, spool, damping, 550 cap gone. Tests that assert
   arcade behaviour (`test_plasma` newton=false, `test_ship_roster` warp escalation,
   `test_surface_band` arcade-tile, `test_surface_integration` arcade NAN) are rewritten
   or deleted with a stated reason each.
3. **Rip travel.** Wormholes, hubs, portals, lanes, onboarding step. `platform_teleport`
   stays: `is_teleport_platform` becomes a plain list on `visited`. Saves migrate.
4. **UI + docs.** HUD/StarMap/MiniMap/tutor text; CLAUDE.md, CONTEXT.md, README,
   `scripts/travel/README.md`, `tools/README.md`, ADR for the decision.

Tests/tools that exercise arcade paths today: `test_plasma.gd:40`, `test_ship_roster.gd:95`,
`test_surface_integration.gd:111-120`, `test_surface_band.gd:14,90-92`,
`test_anchor_frame.gd:108`, `test_earth_terrain.gd:603`, `render_thruster.gd:26`.

Units contradiction to resolve while here: `planet_system.gd:44` says 1u = 0.01 AU,
`system_db.gd:4` and `props.gd:18` say 0.1 AU.
