# tools/

Dev-only scripts: none of this ships in a build. See CLAUDE.md for exact invocation forms.

## test_* — headless tests (pass/fail contracts)

Most `extends SceneTree`, run via `godot --headless --script tools/test_X.gd`. Five are
scene-based (`extends Node3D`/`Node`, need a `.tscn`, run via
`godot --headless tools/test_X.tscn`): `test_base_basic_pbr`, `test_chase_rig`,
`test_ship_roster`, `test_surface_integration`, `test_wedge_fighter`.

| File | Covers |
|---|---|
| `test_base_basic_pbr.gd` (+ `.tscn`) | Base PBR material/shading contract for a ship hull |
| `test_booster_brightness.gd` | `ShipMesh.booster_brightness` + nozzle shaping |
| `test_chase_rig.gd` (+ `.tscn`) | Third-person chase camera rig + ship-only fill light |
| `test_class_ii_cruiser.gd` | Class II cruiser default asset + dedicated surfaces |
| `test_dingo57_starship.gd` | Dingo57 hull: 8 authored boosters + 1 opaque double-sided hull |
| `test_earth_terrain.gd` | Earth flyover: height function, nested rings, band ceiling, speed cap, contact kill |
| `test_flight_mode.gd` | `FlightMode` zone/exclusion math |
| `test_galaxy_backdrop.gd` | Camera never ends up inside the opaque galaxy backdrop mesh |
| `test_jazoone_spaceship.gd` | JazOone hull material split + emissive engine discs |
| `test_look_at_pole.gd` | Look-at math doesn't flip the nose when overhead is world-up |
| `test_newton.gd` | Sol Newton gravity numbers + a parked GEO fall |
| `test_planet_generator.gd` | The cook: named Sol recipes + invented look for strangers |
| `test_ship_customization.gd` | Saved ship coloring survives while propulsion materials stay intact |
| `test_ship_roster.gd` (+ `.tscn`) | Every playable hull builds cleanly |
| `test_skin_kill.gd` | Contact margin + post-death park |
| `test_snarkrans_starship.gd` | Snarkrans hull: 4 authored booster roles |
| `test_sol_cook.gd` | Sol cook live: Moon a real ball from GEO, worlds have maps |
| `test_sol_facing.gd` | Roll/yaw nose-facing regressions |
| `test_sol_occlude.gd` | Celestial-body opacity (no see-through) |
| `test_sol_sun_lod.gd` | Sun stays drawn across the sky-disc/mesh LOD switch |
| `test_sol_truth.gd` | Radii, fallback distances, visual scale, EZ vs real air |
| `test_streak_scale.gd` | Motion-streak field scale vs ship speed |
| `test_surface_band.gd` | The bird-eye ground tile (skin band) contract |
| `test_surface_integration.gd` (+ `.tscn`) | Live Moon placement + Earth/Moon death entry |
| `test_surface_recipes.gd` | Recipe routing, crater/caldera geometry, height bounds, contact, repeatability |
| `test_terrain_light.gd` | Ground lighting/haze matches the globe's rule |
| `test_turn_carry.gd` | A turn carries Sol velocity with the hull |
| `test_wedge_fighter.gd` (+ `.tscn`) | Wedge-fighter hull build |
| `test_wh_network.gd` | Wormhole graph connectivity + hop distances from Earth |

## render_* — visual review captures (offscreen screenshots, human/agent judged)

| File | Captures |
|---|---|
| `render_terrain.gd` (+ `.tscn`) | Ground-tile terrain (`TERRAIN_SHOTS` env selects which bodies/scenes) |
| `render_thruster.gd` (+ `.tscn`) | Contact sheet of every ship's boosters, matching the live WorldEnvironment |
| `render_wedge_fighter.gd` (+ `.tscn`) | Wedge-fighter hull render |

## gen_*/build_*/draw_*/fetch_*/ingest_*/export_*/parse_* — asset & data generators

| File | Produces |
|---|---|
| `build_starfield.gd` | `assets/starfield_{naked,low,high,tycho}.res` baked star meshes |
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
| `gen_reward_audio.py` | `assets/reward.wav` capture fanfare |
| `gen_star_catalog.py` | Prints GDScript star-catalogue rows (for `system_db.gd`) from real nearest-star data |
| `gen_teleport_audio.py` | `assets/teleport.wav` teleport whoosh |
| `gen_ui_click.py` | `assets/ui_click.wav` UI click |
| `draw_tab_target.py` | `TAB_TARGETING.png` diagram |
| `draw_wh_network.py` | `WORMHOLE_NETWORK.png` from `/tmp/wh_graph.json` |
| `export_wh_graph.gd` | Dumps the live wormhole graph to `/tmp/wh_graph.json` for `draw_wh_network.py` |
| `parse_tycho.py` | Parses the raw Tycho-2 catalogue into `tools/data/tycho_slim.bin` |
| `real_positions.py` | Reference computation of real Sun/planet/star positions (dev verification, not consumed by the game) |

## misc — one-off probes & repros

| File | Type | Purpose |
|---|---|---|
| `_bigtri.gd` | probe | Finds the source of a stray giant triangle artifact |
| `inspect_galaxy.gd` | probe | Inspects `assets/galaxy.glb` structure |
| `probe_booster_shape.gd` | probe | Booster-socket falloff shape investigation |
| `probe_earth_dem.gd` | probe | One-shot measurement of `earth_height.jpg`'s encoding (feeds constants into `test_earth_terrain.gd`) |
| `probe_jazoone_sockets.gd` | probe | Derives JazOone's booster sockets in model space |
| `probe_live_scene.gd` (+ `.tscn`) | probe | Live-scene screenshot capture harness |
| `probe_propulsion_area.gd` | probe | Which surfaces get the additive propulsion shader |
| `probe_ring_cost.gd` | probe | Ring-rebuild timing/sampler-call cost measurement |
| `probe_vanguard.gd` | probe | Reports actual per-surface material state of the Vanguard hull build |
| `repro_overhead_w.gd` | repro | Headless repro: pitch Earth overhead, F10, then W — writes a flight footprint JSONL |
