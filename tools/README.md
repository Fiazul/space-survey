`test_black_hole_capture.tscn` checks forced capture from 0.585 AU with arbitrary speed/thrust and NODEATH, swept entry, exterior flybys and the 2 AU return.

# tools/

`test_galactic_core.tscn` checks Ctrl+P, physical scale, orbital inspection, nearby recipe stars, horizon capture/recovery, core density, saves and return travel. `test_black_hole_views.tscn` renders close outward/rolled flow and foreground-exhaust regressions. `test_black_hole_motion.tscn` verifies visible plasma turbulence over four normal-speed half-second intervals with a fixed observer; captures use optional `MOTION_SHOT_DIR`. `render_galactic_core.tscn` captures the real close/polar/wide/overview arrivals and checks for visible, rotating plasma; use a windowed renderer, with optional `CORE_SHOT_DIR`. `test_black_hole_plunge.tscn` checks the pseudo-Newtonian ship gravity (circular orbits under warp at 60/20 fps, capture below the ISCO, force-law ISCO vs recipe, Sol untouched) and the HUD/audio/camera plunge cues. See `docs/GALACTIC_CORE.md`.

Dev-only scripts: none of this ships in a build. See CLAUDE.md for exact invocation forms.

`test_black_hole_portal.tscn` checks horizon entry without hull loss, cinematic
coasting, safe 2 AU saves/return, real Escape input, the return button, mouse
steering restoration, persistent audio cleanup and the Humano picker entry.
`test_humano_runner.tscn` checks jump, landing, collisions, restart and scoring.
`render_black_hole_portal.tscn` captures entry, cubic mist, loading, the dinosaur
arcade at desktop/portrait sizes, keyboard jumping and return; writes `/tmp/astryx-humano`.

## test_* — headless tests (pass/fail contracts)

Most `extends SceneTree`, run via `godot --headless --script tools/test_X.gd`. Some are
scene-based (`extends Node3D`/`Node`, need a `.tscn`, run via
`godot --headless tools/test_X.tscn`): `test_anchor_frame`,
`test_chase_rig`, `test_ship_roster`, `test_ship_modules`, `test_surface_integration`, `test_surface_streaming`.

| File | Covers |
|---|---|
| `test_anchor.gd` | Anchored ship frame (docs/adr/0002): the absolute frame still swallows a Venus-scale substep, the anchored one does not; reanchor continuity, save round-trip |
| `test_anchor_frame.gd` (+ `.tscn`) | The Ephemeris-backed half of the anchor: `rel_km` antisymmetry, a real Newton run at Venus/Saturn, anchor hand-off, anchored-vs-legacy parity |
| `test_booster_brightness.gd` | `ShipMesh.booster_brightness` scales every modular hull booster layer + nozzle shaping sockets |
| `test_chase_rig.gd` (+ `.tscn`) | Third-person chase camera rig + ship-only fill light |
| `test_cloud_layer.gd` | `CloudLayer` shell radius, visible-gate mirrors the ring's `should_show`, airless bodies get no layer |
| `test_earth_terrain.gd` | Earth flyover: height function, nested rings, band ceiling, speed cap, contact kill |
| `test_flight_mode.gd` | `FlightMode` zone/exclusion math |
| `test_galaxy_backdrop.gd` | Camera never ends up inside the opaque galaxy backdrop mesh |
| `test_look_at_pole.gd` | Look-at math doesn't flip the nose when overhead is world-up |
| `test_newton.gd` | Sol Newton gravity numbers + a parked GEO fall |
| `test_planet_generator.gd` | The cook: named Sol recipes + invented look for strangers |
| `test_ship_customization.gd` | `ModularHull.style`: Hull_Paint takes tint/finish, Nozzle_Emit keeps its propulsion pass; module-set persistence |
| `test_ship_roster.gd` (+ `.tscn`) | Seven modular hulls: socket counts drive cones/pads/guns/jets/RCS, fleet scale, stat escalation, tier unlock gate + hangar lock rows |
| `test_ship_modules.gd` (+ `.tscn`) | Weapon/pad set swaps rebuild modules in place, MUZZLE/FOOT move, gear state carries, sets persist |
| `test_skin_kill.gd` | Contact margin + post-death park |
| `test_sol_cook.gd` | Sol cook live: Moon a real ball from GEO, worlds have maps |
| `test_sol_facing.gd` | Roll/yaw nose-facing regressions |
| `test_sol_occlude.gd` | Celestial-body opacity (no see-through) |
| `test_sol_sun_lod.gd` | Sun stays drawn across the sky-disc/mesh LOD switch |
| `test_star_teleport.gd` (+ `.tscn`) | Every Ctrl+P catalogue star: primary-star arrival, recipe visibility, motion reset, repeated visits and saved park |
| `test_stellar_structures.gd` (+ `.tscn`) | Optional-family validation, physical/display separation, deterministic geometry budgets, cache eviction and near/sky ownership |
| `test_stellar_corona_clipping.gd` (+ `.tscn`) | Windowed pixel checks of halo, disk, aurora and wind clipping and foreground occlusion |
| `test_sol_truth.gd` | Radii, fallback distances, visual scale, EZ vs real air |
| `test_streak_scale.gd` | Motion-streak field scale vs ship speed |
| `test_surface_band.gd` | The bird-eye ground tile (skin band) contract |
| `test_surface_integration.gd` (+ `.tscn`) | Live Moon placement + Earth/Moon death entry |
| `test_surface_streaming.gd` (+ `.tscn`) | Fast Earth/Moon flight keeps ground coverage while terrain rebuilds |
| `test_day_night.gd` (+ `.tscn`) | UTC rotation, restart/offline phase, solar clock, co-rotation, body-fixed saves and terrain shadow frame |
| `test_plasma_frame.gd` (+ `.tscn`) | Atmospheric projectile co-rotation, steering independence, fast-drift convergence and floating-origin handoffs |
| `test_surface_recipes.gd` | Recipe routing, crater/caldera geometry, height bounds, contact, repeatability |
| `test_terrain_light.gd` | Ground lighting/haze matches the globe's rule |
| `test_turn_carry.gd` | A turn carries Sol velocity with the hull |

## render_* — visual review captures (offscreen screenshots, human/agent judged)

| File | Captures |
|---|---|
| `render_day_night.gd` (+ `.tscn`) | Same Amazon location and heading at local noon/midnight; writes `/tmp/day-night/amazon-{day,night}.png` using the production terrain/cloud path without touching saves |
| `render_star_teleport.gd` (+ `.tscn`) | Real Ctrl+P picker arrivals for six representative stars; `/tmp/star-teleport/*.png` or `STAR_TELEPORT_SHOTS`, isolated player profile |
| `render_stellar_integration.gd` (+ `.tscn`) | Ten high-resolution production captures with automatic detail selection; `docs/reference/stellar-integration` |
| `render_stellar_production.gd` (+ `.tscn`) | Production family gallery including astronomical wind scale; `STELLAR_PRODUCTION_SHOTS` selects output |
| `render_plasma.gd` (+ `.tscn`) | 90 chase-camera firing frames; `PLASMA_CRUISE_KMS`, `PLASMA_ROTATING=1` and `PLASMA_SHOTS` select fast drift, turning with planetary rotation and output directory |
| `render_terrain.gd` (+ `.tscn`) | Ground-tile terrain (`TERRAIN_SHOTS` env selects which bodies/scenes) |
| `render_approach.gd` (+ `.tscn`) | Earth/Moon at distance (30/8/3/1.5 R) + altitude (60/25/10 km) with a `SHELLS=all\|nosky\|nosurface\|noclouds` toggle, for diagnosing the reported "ring/bridge around the globe" (which shell it belongs to) |
| `render_thruster.gd` (+ `.tscn`) | Modular hulls with plumes, gear and weapons deployed, matching the live WorldEnvironment (`SHIP=<slug>`, `WEAPON`/`PAD`=mk1\|mk2, `FRAME_SCALE`, `VIEW=rear\|chase`; glow on as in main.gd, `GLOW_ON=0` disables) |
| `render_touch_hud.gd` (+ `.tscn`) | Boots the real `Main` scene offscreen at a given resolution (xvfb `-screen 0 WxHx24` sets the resolution — the project is fullscreen; `-- --touch`) so the touch-controls overlay + HUD can be looked at without a device. `SHOT_HANGAR`/`SHOT_DEV`/`SHOT_TOAST`/`SHOT_SYSTEMS`/`SHOT_TELEPORT`=1 open states; `TOUCH_SCALE`/`SAFE_INSET` preview a phone's scale/cutout |

## gen_*/build_*/draw_*/fetch_*/ingest_*/export_*/parse_* — asset & data generators

| File | Produces |
|---|---|
| `build_starfield.gd` | `assets/starfield_{naked,low,high,tycho}.res` baked star meshes |
| `build_stellar_integration_sheet.py` | Labeled comparison of production captures; requires Pillow |
| `build_dingo57_obj.py` | Godot-safe re-grouped Dingo57 OBJ (source has too many material switches) |
| `build_godot_double.sh` | Compiles a double-precision (64-bit coords) Godot editor build |
| `fetch_planet_maps.py` | Downloads 2k evidence planet maps to `/tmp/planet-maps` |
| `ingest_planet_maps.py` | Crops/resizes fetched maps into `assets/planets/` |
| `gen_booster.py` | Booster/engine sound design prototyper |
| `gen_engine_audio.py` | Per-hull engine start/loop/stop OGGs |
| `gen_exhaust_noise.py` | `assets/fx/exhaust_noise.png` tileable turbulence texture |
| `gen_fire_audio.py` | `assets/sfx_fire.wav` laser fire zap |
| `gen_laser_audio.py` | `assets/laser_loop.wav` beam hum |
| `gen_notify_audio.py` | `assets/notify.wav` tutorial chime |
| `gen_star_catalog.py` | Prints GDScript star-catalogue rows (for `system_db.gd`) from real nearest-star data |
| `gen_teleport_audio.py` | `assets/teleport.wav` teleport whoosh |
| `gen_ui_click.py` | `assets/ui_click.wav` UI click |
| `draw_tab_target.py` | `TAB_TARGETING.png` diagram |
| `parse_tycho.py` | Parses the raw Tycho-2 catalogue into `tools/data/tycho_slim.bin` |
| `real_positions.py` | Reference computation of real Sun/planet/star positions (dev verification, not consumed by the game) |

## misc — one-off probes & repros

| File | Type | Purpose |
|---|---|---|
| `_bigtri.gd` | probe | Finds the source of a stray giant triangle artifact |
| `inspect_galaxy.gd` | probe | Inspects `assets/galaxy.glb` structure |
| `probe_earth_dem.gd` | probe | One-shot measurement of `earth_height.jpg`'s encoding (feeds constants into `test_earth_terrain.gd`) |
| `probe_live_scene.gd` (+ `.tscn`) | probe | Live-scene screenshot capture harness |
| `probe_ring_cost.gd` | probe | Ring-rebuild timing/sampler-call cost measurement |
| `repro_overhead_w.gd` | repro | Headless repro: pitch Earth overhead, F10, then W — writes a flight footprint JSONL |
