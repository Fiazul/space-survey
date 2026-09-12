# Session 2026-09-09 — evidence-driven recipes, anchored physics, feel fixes

Pickup note. Committed and pushed 2026-09-09 morning on the player's instruction with
**every slice UNTESTED by the player** — treat the whole "Player check" column below as open.
The Opus review of the full diff was still running at push time; its findings go into the
next session's fix round. Next session: Friday 2026-09-11.

## How to resume

1. Run the CLAUDE.md test loop + all scene tests (list in CLAUDE.md "Commands"). All were
   OK at push time.
2. Start with the player-reported bugs in "Open items" (Venus vanishing near the surface is
   the first).
3. Work through the Opus review findings (section below; blocker 1 first — it is a silent
   Earth-approach regression in the pushed commit).
4. Then the player walks the "Player check" column; nothing there has been seen in the real
   game yet.

## Landed this session (tests green when the slice reported)

| Slice | Files (main) | Verified by | Player check |
|---|---|---|---|
| Ring LOD bands: every procedural octave band-limited by sample spacing (`detail_km`) | surface_recipe.gd `_band_weight`, surface_patch.gd, terrain_sampler.gd `DETAIL_GEOLOGY_DAMPEN` | test_surface_band height/normal/colour boundary agreement; moon_7km capture | Moon 7 km grazing: no straight seam |
| Ring/globe hand-off by committed ground, stale batch committed when cold | surface_patch.gd `has_ground()`, planet_system.gd sphere hide | tools/test_ring_handoff.gd | Dive at Moon at dev speed: globe stays until ring pops in |
| Ring-LOD seam in shader: detail footprint capped by view distance | terrain_tile.gdshader `FOOTPRINT_CEIL_PER_KM` | moon_1km_nadir_lowsun row-scan | Moon 1 km nadir: no straight line |
| Clouds: direction-derived UV, thresholds, adaptive tessellation, drift, sub-texel detail octaves band-limited to pixel footprint | cloud_layer.gd/.gdshader | test_cloud_layer.gd (CPU mirror parity, area fractions) | 20 km above deck: no speckle; under deck 2 km: cell structure |
| Clouds setting Off/Light/Full (default Light). Light = fewer clouds (threshold shift) AND thinner; globe follows the setting | game_state.gd `cloud_quality`, settings_menu.gd, planet_system.gd `cloud_recipe_for_quality`, planet_generator.gd `set_cloud_amount`, planet_cook.gdshader cloud law | test_cloud_layer.gd area fractions Off 0 / Light ~20% / Full ~41% | Cycle setting from orbit: globe + deck change together |
| Fly-through fog only inside the deck's true band; air+fog opacity budget 1.0 | planet_system.gd `_update_air` | tools/test_low_alt_haze.gd | 2 km under deck: no fog until inside cloud |
| 60 km limb "glowing wall": limb term falls off with altitude (`ship_alt_km`/`atmo_top_km` uniforms via `apply_view`) | planet_cook.gdshader, planet_generator.gd `apply_view` | limb/earth_alt_60km capture | 60 km over Earth: thin blue limb line |
| Globe vs ring colour law unified (shared include) + globe UV fix | shaders/planet_color.gdshaderinc, planet_cook.gdshader, terrain_tile.gdshader | tools/test_globe_ring_color_parity.gd, test_globe_ring_uv.gd | Enter Earth over Atlantic/Sahara: no colour jump |
| Hypersonic visual layer ripped (unreachable regime); flying fixes: free-look rate limit, entry cap at shell, drag clamp | ship.gd, flight_mode.gd, hud.gd "Load" | tools/test_flight_envelope.gd, test_flight_mode.gd | No white hull / rainbow plume / camera sag |
| Wind/rumble loudness: log law of dynamic pressure, gate keyed on level (was never audible in real flight, too loud at dev speed) | game_audio.gd `_log_db_for` | tools/test_air_audio.gd | Cruise 80 m/s: faint wind; dev speed: under engine |
| Exclusion-shell freeze at Venus (re-entrant crossing) | flight_mode.gd `break_at_exclusion`, ship.gd `_newton_advance` | test_flight_mode.gd offcenter/earth-scale | — (superseded by anchored frame) |
| **Anchored physics (ADR 0002)**: ship = anchor body + offset; Ephemeris `_pos64`, `rel_km`, `gravity_bodies`; combat `shift_frame`; wormhole/props via `ship.rel_to`; save anchor+off | ship.gd, anchor_frame.gd, ephemeris.gd, planet_system.gd `refresh(ship_off, delta, anchor)`, combat.gd, wormhole.gd, props.gd, main.gd, hud.gd | tools/test_anchor.gd, test_anchor_frame.tscn (real `_newton_advance` at Venus/Saturn, warp handshake, edge sweep, craft rejection, drag gate, combat shift, legacy save) | Warp into Venus → drop flash → AGL counts down at real time; Saturn, Titan; save at Venus, relaunch |
| Review fixes on the above: shell centre once per frame; entry as state edge; `Ephemeris.is_anchorable`; arcade anchor ""; `FlightMode.has_drag_model` gates air_load/mach/drag/corotate together (Earth only); `MAX_SUBSTEPS` 64 + `NEWTON_G_SKIP_THRESHOLD`; `dt − t` after snap; `pending_frame_shift` | same | same + substep timing 3.9 ms @ warp 1000 | Warped approach to Earth: one drop, no impact |
| Free-look camera flip past ±180° (lerp → `lerp_angle`) | ship.gd `_update_camera` | test_chase_rig.gd `_free_look_no_flip` | Hold T, orbit full circle: no spin |
| DEM ingest (16-bit rg16 PNG, `value = R*256+G`, lossless import): Mars MOLA 4 ppd+16 ppd, Moon LOLA 4+16 ppd, Earth ETOPO 2022 60″ 8k + 4k | tools/ingest_dem.py, assets/planets/*_height_{2k,4k,8k}.png, SOURCES.txt, docs/research/2026-09-09-dem-ingest.md | tools/probe_dem16.gd; test_dem_calibration.tscn import-lossless byte checks | — |
| DEM wiring: per-recipe calibration (`height_encoding/datum/m_per_unit/max/signed/texel_km`), rg16 decode mirrored CPU+cook, procedural terms only below texel, signed relief, ocean clamp under water mask | planet_generator.gd RECIPES, terrain_sampler.gd, surface_recipe.gd `_below_texel_weight`, planet_cook.gdshader `decode_height` | tools/test_dem_calibration.tscn (Olympus ≈19.96 km, Hellas ≈−6.07, Moon summit ≈10.62, Everest 7198 = map argmax, Dead Sea −427 land, Mariana clamped 0) | Mars Tharsis: Olympus a broad shield; Hellas descends on the tape |
| Perf: `ensure_close_maps` threaded; PERF_PROFILE-gated timers in main.gd | planet_generator.gd, main.gd | before/after: planets_refresh 7.5 → 2.3 ms/frame; first ring build 1112 → 257 ms | 10,000 km → 30 km approach: one brief stutter at 35 km |
| Globe binds `height_globe` (Earth 4k, −96 MB VRAM) via one helper `globe_height_path` at all three GPU bind sites; cook uniforms `height_datum`/`height_signed` replace raw-h "sea level" tests (vertex floor, land colour, water depth tint) | planet_generator.gd, planet_cook.gdshader, test_planet_generator.gd, PLANET_GENERATOR.md | test_planet_generator.gd (12 new bind/datum cases), globe_ring_color_parity, sol_cook, dem_calibration, pre-terrain set all OK; earth_20km/coast_12km/himalaya_12km captures unchanged | Enter Earth over a coast from orbit: no colour jump at ring pop-in, no blue tint on lowland |
| Exposure per body (`exposure` uniform in planet_color include, recipe default from measured land luminance vs 0.35 target, override `recipe.exposure`) + per-vertex horizon shadow (8-step march along TerrainSampler toward sun, rings 0–2, stored in UV2.y, gates only the direct term) | surface_patch.gd `_horizon_shadow`/`_resolve_exposure`, surface_recipe.gd, terrain_tile.gdshader, planet_color.gdshaderinc, surface_prop.gdshader, render_terrain.gd row `moon_crater_300m_lowsun` | tools/test_horizon_shadow.gd (6 checks incl. ring-boundary continuity); full loop + 6 scene tests green; Moon 300 m rebuild 1.30 → 2.46 s (1.89×); crater capture shows dark near wall + lit far rim | Moon, 300 m over a small crater at low sun: bowl has a shadowed side. Measured Moon albedo is ~0.32 so exposure gain is only ~1.08×; broad flat mare frames still read dark, that is the map, not a bug |
| Ctrl+P dev sites panel: 31 Sol body parks (`Ephemeris.sweet_spot_off`) + 28 landmark sites (Himalaya, Everest, Sahara, Atlantic, Amazon, cloud deck under/above, Mariana, Dead Sea, GEO, Moon 7 km/1 km/200 m/Tycho/Imbrium/summit/SPA, Mars Olympus/Tharsis/Hellas/Valles, Venus 260 km, Titan, Io, Europa, Jupiter, Saturn). Teleport = `_anchor_ship` + lat/lon/alt via shared `TerrainSampler` → `anchor_off`, velocity 0, heading, mesh pose reset. Sol only (arcade shows a notice). render_terrain.gd now reuses `DevSites.dir_for`/`surface_frame` | scripts/world/dev_sites.gd, scripts/ui/dev_sites_panel.gd, main.gd `_input` Ctrl+P, tools/test_dev_sites.gd, test_dev_sites_scene.tscn, tools/render_dev_sites.* | dev_sites: OK; scene test Everest DEM 6905.9 m at (27.99, 86.93); full loop 30/30; capture shows panel + Everest landing (HUD Earth, AGL 3.32 km) | Ctrl+P, click "Everest summit +3 km": mountains, facing south. Known: `.`/`,` time index not reset on teleport (ship.gd private) |
| Globe/ring shader parity: globe binds `exposure` in `_cook_material`; cook ocean goes through shared `ocean_base_color()` (drops the globe's own detail-varying ratio); render_terrain landmark resolver falls back to row lat/lon when a recipe list is empty (DEM bodies); `test_dem_calibration.gd` in CLAUDE.md skip list | planet_generator.gd, planet_cook.gdshader, planet_color.gdshaderinc, render_terrain.gd, CLAUDE.md | parity/planet_generator/sol_cook + pre-terrain set OK; `moon_crater,earth_water` render without error; earth_water ocean same brightness class | Orbit → Earth ring pop-in over open ocean: no brightness step |
| Android touch HUD: buttons were laid out in fixed 1280×720 pixels, so at phone aspect (2400×1080, logical canvas 1600×720) the right cluster sat mid-screen over TELEPORT and THRUST overlapped KILLS/NAV. Now viewport-relative, re-laid on `size_changed`; joystick ring drawn at the steer finger. `project.godot` orientation 4 (Sensor) → 5 (Sensor Landscape) | touch_controls.gd, tools/render_touch_hud.*, BUILD-ANDROID.md, tools/README.md, project.godot | before/after captures 2400×1080, 1920×1080, 1280×720, portrait; debug APK built `builds/android/Astryx.apk` (341 MB); chase_rig + surface_integration OK | Install the new APK: joystick ring appears under the steering finger, buttons flush to the edges, nothing under TELEPORT. Phone stays landscape |

Honest negatives recorded: Himalaya at 9 km looks the same after the 8k DEM (4.9 km texels
cannot resolve 1–5 km ridges; the visible relief is still the procedural overlay). Small
lunar craters at 1 km/200 m low sun still do not read as bowls — measured not a normal/
shading-step defect; needs exposure + cast shadow (in flight below).

## In flight

Nothing. All four slices that were running when this note was first written have landed
(rows above).

## Opus review of the pushed diff (arrived after push, nothing fixed yet)

Verdict: REQUEST CHANGES. Anchored physics checked clean (no absolute-Vector3 subtraction
left on a Sol path; save/legacy/arcade paths correct). Full test loop 31 OK + 8 scene OK.
Nothing visual was re-rendered by the reviewer.

**Blocker**
1. `planet_generator.gd:663-708` threaded `ensure_close_maps`: the poll lambda captures
   `pending` by value, so `pending = still` never persists. On any approach where the four
   close maps finish on different frames, the next poll re-processes already-collected keys,
   `load_threaded_get_status` returns INVALID for them, and the `else` branch sets
   `has_clouds/night/normal/height` back to 0. `close_maps = true` is set the same frame, so
   there is no retry: Earth loses its close maps for the session. Proven with two live probes.
   Fix: box `pending` like `poll_box`, or re-derive it each poll from the bound flags.

**Should-fix**
2. Procedural cloud fallback law differs: `cloud_layer.gd:225` clamps centre to
   `PROC_CENTER_MIN/MAX` (0.14/0.86), `planet_cook.gdshader:364` clamps 0..1. Coverage step
   at the 35 km hand-off on Mars/Venus/Titan. Add the constants to the shader.
3. `touch_controls.gd:126-147`: no release on `NOTIFICATION_APPLICATION_PAUSED` /
   `WM_WINDOW_FOCUS_OUT`; `_touch_at(index, pos, true)` overwrites a held finger without
   releasing it. Lost release = stuck Shift/V, `touch_fire` true, ring frozen. Add
   `_release_all()` + release-before-overwrite.
4. `terrain_tile.gdshader:126-128`: `mix(alb, tex, 1.0)` behind `map_weight > 0.001` is a
   binary switch, not a blend. Decide: drop `map_weight` or restore the blend.
5. `dev_sites_panel.gd:120-137` `go()` never checks `ship.anchor_name == body` after
   `_anchor_ship`; a non-anchorable body would apply a foreign offset to the old anchor.
6. CLAUDE.md loop hangs on `tools/test_dev_sites_scene.gd` (scene-based, not in skip list);
   count text says 6, list has 7, `.tscn` prose omits it. Should be 8.
7. CLAUDE.md "Last verified 2026-09-08 (21 OK)" stale: 31 OK + 8 scene.
8. PLANET_GENERATOR.md:240-251 "Known gap" paragraph stale: both fixes landed.
9. tools/README.md: scene-based list wrong (8 now) and 13 new tools undocumented
   (test_dev_sites, test_dev_sites_scene, test_horizon_shadow, test_low_alt_haze,
   test_air_audio, test_flight_envelope, test_globe_ring_color_parity, test_globe_ring_uv,
   test_ring_handoff, test_dem_calibration, probe_dem16, ingest_dem.py, render_dev_sites).

**Nits**
10. `surface_patch.gd:836` `_skirt_drop` samples at full detail while rim verts used
    `_detail_km_at`; inflates skirt by up to ~1.6× DETAIL_MAX_M (hidden, clamped).
11. Exposure gate differs: cook = rocky && has_albedo; terrain_tile = rocky; surface_prop =
    always. Ice/gas ground unexposed while its props are.
12. `planet_system.gd:840-850` `cloud_recipe_for_quality` duplicates a dict per body per
    frame at Light quality; cache next to `_pushed_cloud_amount`.
13. `hud.gd:1387` Mach/Load shown at Venus/Titan as 0; gate on `has_drag_model`.
14. earth_spec_2k.png.import mipmap flip: reverted before push (editor noise).
15. DEM `.import` files keep `detect_3d/compress_to=1`; an editor 3D-detect reimport would
    VRAM-compress and destroy R*256+G. Set 0 on the six DEM imports.
16. Dev sites panel says "Ctrl+P / Esc to close" but pauses the tree and main is PAUSABLE,
    so only Esc closes. Fix label or make main PROCESS_MODE_ALWAYS.
17. `ship.gd:340` DEV_THRUST_MULT 1e11→1e6, comment "~20 s GEO→skin" stale.
18. CLAUDE.md architecture tree omits CloudLayer and DevSites.
19. Teleport that keeps the anchor (GEO→Everest) leaves `_shell_edge_known` true → spurious
    drop_flash. Reset after `go()`.
20. `main.gd:391-398` `_reanchor_to_nearest` has no hysteresis; at an equidistant point the
    anchor can flip per frame, random-walking ~ULP(2d) (~23 m Earth/Moon midpoint).

## Open items / next briefs (not started)

- **Regional close-map relief** (30–90 m, SRTM/ETOPO tiles) streamed through the close-maps
  path for the nearest few degrees — the actual fix for "Himalaya is a lie". Global 8k stays
  for globe + far ring.
- **Ring first-build stutter** 257 ms: commit one ring per frame instead of four at once
  (surface_patch.gd `_finish_rebuild`).
- **Per-body atmosphere density table** (RHO0, scale height) so `has_drag_model` can open
  beyond Earth; then recipe-driven per-body gravity/air for invented worlds.
- **Co-rotation axis**: `spin_rad_s` is a scalar; rotation is about `Vector3.UP` for every
  body (exact for Earth only).
- **Cloud shell cost**: ~42k prims (92% of band-entry growth); halve segments if the player
  judges it worth it.
- **Moon crater density by albedo map** (highlands dense, maria sparse) — player not yet asked.
- **Bridge/halo ring around the globe** (player report, Earth + Moon): only confirmed cause
  was the 60 km limb wall (fixed). Static captures show no other artifact with the real
  hide rule; a fast-descent transient (ring one size bucket short of the horizon for a few
  frames) remains a hypothesis. Needs a live screenshot.
- **Venus vanishes near the surface (player report 2026-09-09, NOT fixed)**: same symptom as
  the Moon had before the `has_ground()` hand-off fix — the globe hides while the ring is not
  yet showing, so the body disappears from sight on approach. Moon fix was verified on Moon
  only; Venus differs in that it has an `air_amount` shell, a 2k map with no DEM, and the
  anchored frame now switches to it. Start by reproducing with Ctrl+P → "Venus 260 km" and
  descending; check `_surface.has_ground()` vs the sphere-hide rule and whether the ring
  ever builds for a `height_source` "procedural" body at Venus radius. Fix the category:
  every body that shows a ring must keep the globe until the ring has committed geometry.
- Godot shadow maps deferred (whole ground pipeline is unshaded by design).
- **Per-vertex shadow is quad-resolution**: in `moon_crater_300m_lowsun` the lit far rim has a
  squared-off edge (linear interpolation across ring-0 quads on a 240 m bowl). Options: finer
  ring-0 spacing near the camera, or move the horizon test into the fragment shader with a
  small height-texture lookup.
- **Oblique ring-LOD band** (pre-existing, visible in himalaya_9km before and after this
  session): a horizontal brightness/detail step low in the frame where ring 0 meets ring 1
  when the camera is pitched. The nadir seam fix (`FOOTPRINT_CEIL_PER_KM`) did not cover
  this framing.

## Tools added this session

`tools/render_approach.gd/.tscn` (globe/ring/cloud/air shells at approach distances,
`SHELLS=all|nosky|nosurface|noclouds`, `CLOUD_QUALITY`), `tools/render_touch_hud.*`,
`tools/probe_dem16.gd`, `tools/ingest_dem.py`, tests: `test_ring_handoff.gd`,
`test_low_alt_haze.gd`, `test_air_audio.gd`, `test_anchor.gd`, `test_anchor_frame.tscn`,
`test_dem_calibration.tscn`, `test_flight_envelope.gd`, `test_globe_ring_color_parity.gd`,
`test_globe_ring_uv.gd`, `test_horizon_shadow.gd`, `test_cloud_layer.gd`, `test_dev_sites.gd`,
`test_dev_sites_scene.tscn`, `tools/render_dev_sites.*`.
Capture evidence lives only in the session scratchpad (not the repo); re-render with the
`TERRAIN_SHOTS` rows named in render_terrain.gd.

## Gotchas learned

- Godot official build: `Vector3` is float32. Cross-body maths in doubles, always (ADR 0002).
- Godot flattens 16-bit grayscale PNG to 8-bit on load; pack hi/lo in R/G.
- `Camera3D.far` above ~1,048,000 renders black under llvmpipe (render tools use 900000).
- Workers idle on their own "quiet machine" polls; each xvfb-run has its own display, so
  concurrent renders only slow each other. Tests that load DEM/texture assets can flake
  under heavy concurrent godot load — re-run alone before believing a failure.
- Perf numbers from llvmpipe: only per-category CPU ms and hitch attribution transfer.

## Added 2026-09-12

`FlightMode.dev_no_death` (Ctrl+D, DEV-gated like FASTAIR): guards both player-death
paths, `_update_skin_kill` and `_update_core_hazard` in `scripts/core/main.gd`, via
`FlightMode.kill_allowed()`. Cleared whenever DEV mode itself is turned off. New test
`tools/test_dev_no_death.gd`.

## Added 2026-09-12: touch controls reworked (player-untested on device)

Landscape lock (`project.godot` orientation 5→4, `SCREEN_SENSOR_LANDSCAPE`). Left thumb
is now a proper movement joystick (forward + turn, analog `Ship.touch_thrust/touch_yaw`,
brake past the 150° back cone) instead of the old free-drag mouse-look; mapping is the
pure `TouchControls.stick_to_cmd()`, unit-tested in `tools/test_touch_controls.gd`. Right
thumb gets FIRE + stacked UP/DOWN nose-pitch buttons plus BOOST/CAP/THRUST/INTERACT/MAP/
HOME; a top-right DEV button reveals NODEATH/FASTAIR. `Ship._in_fwd/_in_brake/_in_yaw`
now fold touch into every W/S/A/D-reading site (warp spool, cruise sway, throttle,
autopilot cancel). Taller-than-16:9 tablet aspects (16:10/4:3 landscape) are handled by
clamping the overlay's true-bottom-anchored margin so it never drifts past hud.gd's
fixed-720-canvas hazard line — verified by hand at 1280×800/1280×960, untested on an
actual tablet.
