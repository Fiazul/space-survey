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

## Slice 1 done (2026-09-29, branch `one-physics`)

What changed:
- `Ephemeris` (autoload, no class_name) now delegates to a current `SystemEphemeris`
  (`scripts/world/system_ephemeris.gd`). `SolEphemeris` (`sol_ephemeris.gd`) holds every
  Sol table verbatim (PLANETS, PHYSICAL_MOONS, STARS, GM/radius/spin `match` blocks,
  ATMO_TOP_KM, JPL url/parse/date cache); `Ephemeris` re-exports the constants so
  `E.PLANETS`, `E.GM_EARTH` etc. still resolve. The HTTP fetch stays on the autoload node
  and always writes Sol. `Ephemeris.MOONS` deleted.
- New API: `switch_system(id)`, `system_for(id)`, `current()`, `is_physical_system(id="")`,
  `system_id`, `primary_star`, `spawn_body()`, `spawn_pos()` (`geo_start_pos()` is now an
  alias), `is_star(name)`, `has_drag_air(name)`. Authored arcade systems keep Sol current.
- `GeneratedEphemeris` (`generated_ephemeris.gd`): star from `StarRecipe.resolve(row)`
  (mass/radius/luminosity from spectral type), 2-6 worlds on circular Kepler orbits at
  real km (first orbit from sqrt(L), ratio 1.5-2.3), Chen & Kipping mass-radius, seeded
  kind/air/atmo/spin (close-in worlds tidally locked). Star at the origin. Positions freeze
  at `place_at(rotation_clock.unix_s)` on switch, like Sol's per-session JPL positions.
  Proxima (`SystemDB` row `physical: true`, `star_name`, `planet_prefix`) generates
  Proxima Centauri + Proxima b..g; spawn = the solid world nearest the HZ (Proxima c).
- `SystemDB.is_physical/star_row`; `bodies(id)` for a physical id = `sol_from(ephemeris
  worlds)` (now also passes `kind`, `air_amount`, `spectral`). Portals of a physical
  system hang around its spawn world at Sol's gate radius.
- Hardcoded "Sun"/"Earth" routed through `primary_star`/`spawn_body()`: planet_system
  to_sun/to_star/sun sky disc (disc repainted for the primary via `_match_sun_sky`),
  main boot anchor/sun light/solar light/skin respawn, ship debug geo park,
  `sweet_spot(_off)`, `solar_state`. `FlightMode.has_drag_model` asks the ephemeris:
  Sol = Earth only (unchanged), generated = recipe `air_amount > 0`. `_newton_atmo_drag`
  measures altitude from the anchor's own radius/atmo_top (identical numbers at Earth).
  `has_drag_model` finds the autoload at run time (`Engine.get_main_loop()`), because a
  compile-time `Ephemeris` reference there breaks every `--script` test that preloads
  `flight_mode.gd` (test_flight_mode / test_air_terminal hung on it).
- `main._arrive`: `ship.newton = Ephemeris.is_physical_system()`; physical systems
  anchor at `spawn_body()` and park at `spawn_pos()`; arcade branch untouched. Arcade
  guardians gated off in physical systems; props hide in physical non-Sol systems;
  non-Sol physical saves without a valid anchor respawn at the spawn park. HUD names the
  star (`hud.physical_system_name`).
- Tests: `tools/test_system_ephemeris.tscn` (Sol bit-identical to b62b8a5 via an
  embedded snapshot, Proxima real-scale/anchoring/skin/spin/Newton, switch back),
  `tools/test_proxima_boot.tscn` (real main boot, `_arrive("proxima")`, 30 s fall).
  Both are scene tests: CLAUDE.md's `--script` loop skip list needs both names added.
  `test_surface_integration` now skips physical systems when picking its arcade system.

What slice 2 can delete safely:
- The `else` (arcade) branch in `main._arrive`, `SystemDB.arrival_pos` non-Sol table,
  `SystemDB._proxima()` (unreachable now), `planet_system.gd` arcade-only branches that
  still read `eph.scene_pos("Sun")` (non-physical orbit spin in refresh/gravity_at).
- Once every system is physical: `is_physical_system` gates, `SystemDB.is_physical`,
  the `refresh_anchor` "" path, and the props/guardian physical gates.

Surprising / needs a decision:
- **Anchor frame is not free-falling.** `Ship._newton_g` sums every body's pull on the
  ship but not the anchor's own acceleration toward the star, so the star's direct
  pull is felt in full. In Sol it is small (2.6 % of Earth's g at GEO, and it already
  dominates Earth's pull past ~259,000 km, i.e. at the Moon). At Proxima c (0.035 AU
  from a 0.12 Msun star) the star's direct pull (5.8e-4 km/s²) beats the planet's
  past 3.6 radii: from a GEO-ratio park the ship falls toward the star. Slice 1 did not
  change the flight model (Sol regression gate); instead generated spawn parks inside
  the planet-dominated zone (`GeneratedEphemeris.spawn_park_km`, 1.8 R at Proxima c).
  Slice 2's single integration path should subtract the anchor's acceleration (tidal
  form), which changes Sol numbers slightly and needs the player's sign-off.
- The Sol HYG star shell (`Ephemeris.STARS`, planet_system `_stars`) stays geocentric:
  in Proxima the "Proxima Centauri" sky point still sits 4.24 ly away and the sky is
  Sol's. Slice 3/4.
- `_is_guarded`, props, the fly-arrive offset and `_land_beside_dock` all assume arcade
  units; they are gated or bypassed in physical non-Sol systems, not converted.

## Slice 2 done (2026-09-29, branch `one-physics`)

What changed:
- One integration path. `ship.newton` and every branch on it are gone; so are the arcade
  constants (`THRUST`/`STRAFE_THRUST`, `SUBLIGHT_MAX`, `GRAVITY_IDLE_SPEED`, `SETTLE_*`,
  `DAMPING`, `DRIFT_DAMPING`, `WARP_*`, `HYPERSONIC_SPEED`, `SOL_FIELD_RADIUS`,
  `WEAPON_FIRE_SPEED`, flip leap), per-hull `warp`/`bolt_speed`, the warp spool, the galactic
  drive and `speed_limit`/`struct_limit`/`star_field_dist`/`gravity` inputs. The velocity
  ceiling left is `MAX_SPEED * boost` (10,000 km/s, was already there in Sol) and the dock
  approach cap. `VISUAL_CRUISE_KMS` (550) is a look-only reference for engine heat/streaks.
  Autopilot is a stub: point, burn at Newton accel, cut 3 radii out (S.4 replaces it).
- **Anchor frame free-falls.** `Ship._newton_g` = Σ g_i(ship) − Σ g_i(anchor centre), in
  64-bit scalars. Sol numbers moved only by the Sun's direct term (GM_sun/AU² = 5.93e-6
  km/s² = 6e-4 g at the ground, 2.6 % of g at GEO). No Sol test expectation needed to change:
  every gate test passes as before; the only printed Sol differences are closed-loop pilot
  paths (`test_playable_minute` apogee 321.2 → 321.4 km, i.e. 6e-4 relative = the removed
  term; flight 146.3 → 149.2 s because the pilot's warp/correction taps shift;
  `test_surface_streaming` lag 19.7 → 19.6 km). Proxima boot at 4e4143d fell 0.7886 km in
  30 s against the world's own 1.0518 (star pull 25 % off); now 0.8520 vs 0.8526.
- `GeneratedEphemeris.spawn_park_km` = 2 radii (no star-dominance clamp).
- Every system is physical: `SystemDB.is_physical`, `Ephemeris.is_physical_system`, the
  authored arcade bodies (`_k2_18/_proxima/_trappist/_alien/_single_star`) and the non-Sol
  `arrival_pos` table are gone. `bodies(id)` = the system's ephemeris worlds for every id;
  an id with no star row (the `interstellar` hub) answers with Sol. Alien Zone's star is
  "Hostile Star" (`star_name`).
- `_arrive` always anchors at `spawn_body()`/`spawn_pos()`; `_arrive(INTERSTELLAR)` and
  saves in the hub land in Sol. Non-Sol saves whose anchor is not a body of the generated
  system keep the arrival spawn (arcade `off` is never restored outside Sol).
- PlanetSystem: `VISUAL_SCALE`, speed zones, arcade gravity/`GRAV_G`/`STAR_GRAVITY_*`, arcade
  moon orbits, `ORBIT_*`, static `b.pos`, hub fly-arrive, `star_dist` and every `physical`
  gate are gone; `is_physical(name)` became `has_body(name)`; `_fmt_star_dist` became the
  km-native `_fmt_dist_km`. `SurfacePatch`/`CloudLayer` `should_show`/`update_for` lost the
  `physical` argument (all tool callers updated).
- Props: only Sol's GEO-parked station + Finn remain; non-Sol stations/probes, the generic
  platform and the structure slow zone are deleted. **Non-Sol props are hidden** until slice
  3 places stations per body. `OrbitalStations` (ISS/Tiangong) show in Sol only.
- Combat: one gate, `Combat.fire_allowed(ship)` = not docked and not in transit.
  `has_method("is_hypersonic")` duck-typing became `ship is Ship`. Guardian spawning (it
  was already off in physical systems) is deleted with `_is_guarded`.
- Tests: new `tools/test_one_physics.tscn` (no `newton` symbol, GEO radius within 0.014 %
  over a day with the Sun on, Moon-distance sunward drift 0.13 km vs 38.3 km uncorrected,
  Tau Ceti boots/anchors/falls within 0.2 % of GM/r², fire gate). Rewritten or deleted, each
  with a one-line reason in the file: test_plasma "interstellar frame", test_ship_roster
  warp escalation, test_surface_band `arcade_system_gets_no_tile`, test_cloud_layer
  non-physical gate, test_surface_integration arcade NAN (now a generated-world check),
  test_sol_truth VISUAL_SCALE source checks, test_system_ephemeris/test_proxima_boot
  `is_physical_system`/`newton` checks.

Deviation from the brief: `ship.nearest_dist` stays. It is not arcade — the Newton path
reads it for the exclusion shell, the air/weapons test and time-warp zones.

What slice 3 can delete:
- `Wormhole.slow_limit` (unread), `SystemDB.HUB_ENTRY`, `_interstellar()`, the
  `INTERSTELLAR` redirects in `_arrive`/`_restore_location`/`system_for`,
  `main._update_core_hazard`/`_core_kill`/GalaxyModel loom (nothing drives it now),
  `hud.origin_name`, the Props `probe` machinery (no probes left), `_land_beside_dock`
  (no non-Sol docks), `StarRecipe.scene_radius` use in the sky shell.
- Combat still runs the Alien Zone swarm with arcade-unit constants (SPAWN_RADIUS 60, etc.)
  in a km world, and bolts feel full body pulls (`PlanetSystem.gravity_at`, not the tidal
  frame) — both S.8.

Surprises:
- The sun-jump bug (`docs/bugs/2026-09-23-sun-jump-flight.md`) is **not** this defect and is
  not changed by it: that was the Sun's own pull (0.274 km/s²) beating 3 g engines at a
  120 km park, fixed then by the 4 R park. Anchored at the Sun, the frame term only removes
  the planets' pull on the Sun's centre (~1e-9 of it).
- The HYG sky shell still sits geocentric (sky in Tau Ceti is Sol's), as slice 1 noted.
- Docs still describing the arcade model, for slice 4: `PLANET_GENERATOR.md:155`,
  `docs/SESSION-2026-09-04-skin-band.md:59,442,882`,
  `docs/specs/2026-08-17-sol-physical-scale-design.md:17`,
  `docs/superpowers/specs/2026-09-04-earth-flyover-terrain-design.md:29,186`,
  `docs/superpowers/plans/2026-09-04-earth-flyover-terrain.md:1340,1387`,
  `docs/ROADMAP.md:108-109,135` (decision text, keep).

## Slice 3 done (2026-09-29, branch `one-physics`)

- Deleted `wormhole.gd`(+uid), `WORMHOLE_NETWORK.md/.png(.import)`, `export_wh_graph.gd`(+uid),
  `draw_wh_network.py`; SystemDB hub/graph/portal sections, `INTERSTELLAR`, `HUB_ENTRY`.
  `is_teleport_platform(id)` = Sol or `GameState.visited`; `has_station` = same.
- GameState: `coins`, `claimed`, `nav_unlocked`, `wormholes_found`, reward/nav consts and claim
  API gone; old save keys ignored. main: wormhole wiring, radar, routes/"via" text, nav lanes,
  paid navigator, `_nav_goal`, core hazard/`_core_kill`, probe readout, `_land_beside_dock`,
  `hud.origin_name`, GalaxyModel loom, dead `ship.transiting` flag (every reader) removed.
- `main.travel_to(id)` / `can_travel_to(id)`: visited, or `ASTRYX_DEV_TRAVEL=1`; refusal toast
  "Not yet reached — needs the interstellar drive" (also star map, quest log, teleport console).
  Teleports route through it; emergency home always allowed.
- Save in a system with no star row (`interstellar`) → Sol pad start. Boot resets the Ephemeris
  autoload to Sol (it survived `reload_current_scene`). `surface_off/basis` reads no longer
  print "no default" errors.
- Props anchored (body + off, `dock_rel(ship)`); the station parks 20 km off every system's
  spawn park (2 radii out in generated systems). Finn Sol-only.
- Tests: new `test_travel.tscn`; `test_docking` (relocate to spawn instead of `_land_beside_dock`),
  `test_dev_no_death` (core-hazard checks deleted: hazard gone), `test_one_physics` (transit fire
  gate deleted: flag gone), `test_landing_cycle`, `test_onboarding_migration`/`test_profile_dir`/
  `test_anchor_frame` (renamed strings only).
- Verified (coordinator-cut acceptance): test_one_physics OK, test_playable_minute OK,
  test_landing_cycle (LANDING_HULLS=1) OK, test_travel OK, headless Sol pad boot clean (no
  SCRIPT ERROR, saved at kennedy_lc39a). Full sweep NOT run.

## Slice 4 remaining

- Grep sweep `warp|spool|sublight|hypersonic|leap|lane|capture|claim|bounty|VISUAL_SCALE|0.01 AU|0.1 AU|newton` in scripts/ tools/ with verdict list (not done).
- `MissionDB.reward` / bounty text now unused by any economy — delete or keep as flavour.
- `TAB_TARGETING.md` still describes wormhole Tab targets.
- CONTEXT.md glossary: remove wormhole/arcade/lane/coins terms; keep "time warp = Sol clock rate".
- README.md, lore.md wormhole/FTL mentions; `PLANET_GENERATOR.md:155`; `scripts/*/README.md` rows.
- CLAUDE.md directives/forbidden-patterns still mentioning arcade (`VISUAL_SCALE`, 0.01 AU).
- docs/ROADMAP.md: delete "Wormhole hop test reinstatement"; add "Later: sky in generated systems is Sol's star field".
- New ADR `docs/adr/0003-one-physics-one-unit.md` (referenced by code comments already).
- Onboarding `teleport_net` text checked: no wormhole mention (done).
- Full `tools/test_*.gd` sweep with per-test profile dirs, docking PASS list, test_system_ephemeris.
- Ready-to-merge checklist for the player (fly: pad start, dock, teleport to a visited system, dev travel).
