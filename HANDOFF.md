# Astryx — exposure + glow-radius pass (2026-09-03)

Three complaints across two rounds: the booster was too bright and fought the rest of
the image, the ship read as tiny while flying, and then the glow SKIRT was too wide.
All measured in the CHASE view, not the 3/4 beauty view — that distinction is the whole
story of this pass. The scale work on the camera was reverted (see below); the exposure
and glow work stands.

## Measure it in the view you actually play in

`tools/render_thruster.tscn` gained `VIEW=chase`, which puts the camera exactly where
`Ship._update_camera` puts it (CAM_OFFSET hull lengths back, FOV_BASE) instead of the
flattering 3/4 side angle. Also `CAM_FOV` / `CAM_BACK` / `CAM_UP` / `CAM_PITCH` to
photograph a candidate rig without editing ship.gd, and `TORCH_GAIN` / `PROP_GAIN` to
scale the emissive shaders' `brightness` for a sweep.

The 3/4 sheet from the previous pass looked fine. The same build in the chase view was
a white blob with the hull invisible. Anything tuned only on the 3/4 sheet is untested.

## What was actually too bright (measured, not guessed)

Isolation renders at 960x540, p99 luminance and % of frame above 0.08:

| ship | as shipped | torch+prop shaders zeroed | nozzle rig hidden |
|---|---|---|---|
| class_ii | 0.081 / 1.03% | 0.081 / 1.03% | **0.017 / 0.34%** |
| dingo57 | 0.289 / 4.13% | 0.289 / 4.13% | **0.033 / 0.59%** |
| snarkrans | 0.270 / 3.65% | 0.272 / 3.67% | **0.087 / 1.07%** |
| jazoone | 0.653 / 25.3% | **0.268 / 3.70%** | 0.623 / 22.7% |

So on three of four ships the entire blowout was the **OmniLight3D nozzle lights**, and
the torch cones contributed nothing — setting their `brightness` to 0.0 changed the
frame by less than one part in a thousand. On JazOone it was its **hull-booster shader**
and the lights were nearly irrelevant. The plume shader everyone reaches for first was
innocent both times.

Fixes, all of them measured:

- **Nozzle lights** (`ship_mesh._add_nozzle_light`, `ship._update_authored_propulsion`):
  range `socket_radius * 7.0 -> 4.0`, attenuation `1.6 -> 2.2`, energy ramp
  `0.10..1.45 -> 0.04..0.42`, and per-light energy now divided by
  `sqrt(2 / nozzle_count)`. These lights ADD: a flat energy made dingo57's eight
  nozzles four times brighter than JazOone's two. sqrt not 1/n, or an eight-engine ship
  ends up looking weaker than a two-engine one.
- **`cruiser_propulsion.gdshader`**: energy `mix(64,128,power) -> mix(1.6,7.0,power)`
  (x brightness 4.0 = 6.4..28, was 256..512). Gained the same `cool_color`/`hot_color`/
  `temperature` ramp the torch and JazOone disc already had, and `ALBEDO` is now the
  tinted colour rather than `vec3(1.0)` — under `blend_add` a white ALBEDO puts a floor
  of white under the patch and defeats the ramp entirely. Before this, every engine bell
  was the same flat white plate at idle as at full burn.
- **`jazoone_hull_booster.gdshader`**: whole-hull `EMISSION = emis * 4.0 -> * 0.9`, disc
  energy `mix(64,128) -> mix(0.9,4.0)`, and its material `brightness 4.0 -> 0.40` in
  `style_jazoone_spaceship`. JazOone's discs are ~10% of hull length in radius each, far
  bigger relative to the ship than the other hulls' patches, so it needs its own number.

## THE BIG ONE: `render_mode unshaded` discards EMISSION

Every "HDR energy" constant in `cruiser_torch.gdshader` and
`cruiser_propulsion.gdshader` was dead code. Godot 4 takes ALBEDO as the final colour
for an `unshaded` material and never adds the emission term. Both shaders are
`render_mode unshaded, blend_add, ...`, so what reached the screen was `ALBEDO * ALPHA`
and nothing else.

Proven twice, in the 3/4 side view at full burn, 960x540:

| change | clipped px | total light |
|---|---|---|
| as shipped | 2874 | 9278 |
| torch `brightness` = 0 (energy 0) | 2846 | 9329 |
| both shaders' EMISSION x100 | 2846 | 9329 |
| plumes HIDDEN | 2288 | 5513 |

Zeroing the energy and multiplying it by 100 give the same frame; hiding the geometry
removes 40% of all the light. The energy term is not a control at all.

That is why several rounds of "the booster is too bright" got nowhere: the torch core's
`mix(480.0, 1920.0, power) * 3.4` = 6528 was never reaching a pixel, and
`tools/test_class_ii_cruiser.gd` asserted the literal `"1920.0"` was present, so the
number looked load-bearing.

What was actually too bright: `ALBEDO = torch_color` (near white) with `ALPHA` up to
0.88 laid down most of a white plate PER LAYER, and six sockets x two overlapping cones
summed into a slab across the whole tail. `cruiser_propulsion` was worse -
`ALBEDO = vec3(1.0)` with an `ALPHA` floor of **0.45**, so grazing faces never faded.

The fix, in both shaders: **ALBEDO carries the HDR value** (it goes straight to the
rgba16f buffer, so values above 1.0 still bloom), `EMISSION = vec3(0.0)`, and the energy
ramp is scaled to peak just below 1.0 per layer so a dozen overlapping layers sum to a
hot core instead of a slab. Torch peak 0.45, propulsion peak 0.9. `cruiser_led.gdshader`
was always fine, because its ALBEDO is black and it puts everything in... EMISSION -
which means the LED strip is drawn entirely by its ALPHA. Worth a look some day.

### Per-ship gain, because the emissive AREA differs tenfold

`tools/probe_propulsion_area.gd` measures how much of each hull the additive booster
shader covers: **class_ii 0.64%, dingo57 4.30%, snarkrans 6.69%** (JazOone's discs are
their own case). These layers add, so one flat brightness washes the wide-area ships out
while leaving class_ii correct - which is why snarkrans kept a white patch across its
mid-hull after the ALBEDO fix landed. `DINGO57_BOOSTER_GAIN` and
`SNARKRANS_BOOSTER_GAIN` in ship_mesh.gd scale by `sqrt(class_ii_area / own_area)`, the
same reasoning as the per-nozzle light share in ship.gd.

Side view at full burn, before vs after, on snarkrans (the worst case):
clipped px **2874 -> 1374**, inner-ring luminance **0.963 -> 0.399**, total light
**9278 -> 4742**. The hull silhouette survives, and the plume cones are still there.

**Rule: in an `unshaded` shader, never write to EMISSION.** Put the value on ALBEDO.
The contract tests now assert this in both shaders so the trap cannot be re-set.

**Second rule: measure in more than one camera angle.** The chase view (dead astern,
looking down the cone axis) said the torch contributed nothing, which was true in that
view and badly wrong in general - every cone wall is edge-on from directly behind. The
side view is where the plumes actually have area. `tools/render_thruster.tscn` renders
the 3/4 side by default and the chase view with `VIEW=chase`; check both.

`tools/probe_propulsion_area.gd` prints which surfaces carry the additive booster
shaders and how big they are as a share of the hull, which is how "the whole booster
shell is painted white-hot" got ruled out (the shells are 0.4-0.8% of the ship).

## `power` reaches the shaders as 0..POWER_CEIL, not 0.42..1.0

`Ship._update_authored_propulsion` used to hand the shaders
`lerpf(0.42, 1.0, _propulsion_power)`. Work out where the flight states actually land
on that: ordinary cruise with no Shift is `550 / (SUBLIGHT_MAX * BOOST_MULT)` = 0.33 of
`_propulsion_power`, which mapped to **0.61**; full boost clamps `_propulsion_power` to
0.82, mapping to **0.90**. So un-boosted flight already sat near the top of every
brightness ramp and Shift added almost nothing visible.

`POWER_CEIL = 0.75` and a straight `_propulsion_power * POWER_CEIL` pulls the curve
down, and each shader's idle constant came down with it so the ramp keeps its range.
What lands where now (core-layer torch value, x brightness 3.4):

| state | now | before |
|---|---|---|
| at rest | 0.068 | 0.264 |
| cruise, no Shift | 0.134 | 0.331 |
| full boost | 0.349 | 0.477 |

Full boost now lands roughly where un-boosted cruise used to sit, and cruise is 2.6x
below boost instead of 1.4x. Same treatment on the engine bells
(`cruiser_propulsion`), the JazOone disc, and the nozzle lights
(`0.04..0.42 -> 0.015..0.20`).

**Colour is not affected by any of this.** The orange -> white -> blue ramp is driven by
`temperature`, which comes off `_propulsion_power` directly and never went through the
`power` mapping.

`tools/render_thruster.tscn`'s three shots are now `rest` / `cruise` / `boost` at the
`_propulsion_power` values those states really produce (0.0 / 0.33 / 0.82), rather than
the old arbitrary 0.0 / 0.45 / 1.0.

## Halo radius is the glow chain, not the shader

Second round of the same complaint, phrased as "the radius of the brightness should be
lower — is the core too hot?". The core was not the problem.

`Environment.set_glow_level(n, w)`: level 1 is a half-resolution blur, level 5 is 1/32.
Whatever weight level 5 carries gets smeared over an enormous area. main.gd had
`1:0.2 / 3:0.4 / 5:0.7` — the MOST weight on the WIDEST blur — so every hot pixel grew a
soft ball. Now `1:0.8 / 2:0.4 / 3:0.15 / 5:0.0`, and `glow_bloom 0.15 -> 0.05`.

Radius at which the ring-mean luminance is still visible, chase view, full burn:

| ship | before | after |
|---|---|---|
| dingo57 | 111 px | 77 px |
| snarkrans | 142 px | 77 px |
| jazoone | 199 px | 87 px |

**Halving the plume shaders' energy on top of this changed the frame by less than 0.1%**
(r_glow 65 vs 65, clipped-core pixels 1251 vs 1251 on dingo57). So do not reach for the
emissive constants when the complaint is "the glow is too wide" — they are already below
the point where they matter, and the skirt is entirely the level weights.

A tighter variant was measured and NOT shipped: `glow_hdr_threshold 1.0 -> 1.8` with
`glow_bloom 0.0` takes dingo57/snarkrans to 65 px. It is left alone because raising the
threshold globally silences bloom on everything emitting between 1.0 and 1.8 — lasers,
LED strips, distant stars — and none of those render in this harness, so it could not be
verified. Try it if the skirt is still too wide, but look at combat and the starfield.

`tools/render_thruster.tscn` takes `GLOW_L1..L5`, `GLOW_THRESHOLD`, `GLOW_INTENSITY`,
`GLOW_STRENGTH`, `GLOW_BLOOM` for exactly this sweep. Shell note: pass them with
`env VAR=x ... cmd`, not `"$@"` — expanded words are not treated as assignment prefixes,
so a sweep written the obvious way silently runs every profile at the defaults.

**Rule of thumb for this project's environment** (FILMIC, `tonemap_exposure 0.7`,
`glow_hdr_threshold 1.0`): emissive linear values clip somewhere around 4. Anything
above ~40 is a flat white plate whose only remaining variable is halo size, and between
480 and 6528 the rendered frame is bit-identical. If a value is in the hundreds, it is
not "HDR headroom", it is broken.

## Making the ship feel big

- **Chase rig: TRIED AND REVERTED. Do not redo it.** `FOV_BASE 70 -> 48`,
  `CAM_OFFSET (0, 0.5, 2.6) -> (0, 0.16, 1.75)`, `CAM_VIEW_PITCH_DEG 0 -> 5`, plus a
  positional lag on the rig (`CAM_POS_LAG` / `CAM_POS_SLACK`) so the hull swung in
  frame during a turn. On paper it worked — a hull-length object spanned 0.642 of frame
  height instead of 0.275, and the eye sat +0.2 degrees off the hull axis instead of
  +10.9 above it. In the hand it felt LAGGY rather than heavy: easing the camera
  position reads as input lag, not as mass. Everything above is back to its original
  value. If you want to try scale again, the camera is the wrong lever; the rig stays
  welded to the hull with only its BASIS lagging, via `CAM_LAG`.
- **Streak field rescaled to hull lengths** (`Ship._fit_streaks`, `STREAK_BOX_Z`,
  `STREAK_FIELD_HULLS`) — KEPT. The field was authored in raw units and against an 80 m
  hull worked out to ~560 hull lengths deep, made of streaks 30 hull lengths long, all
  of it far away. Debris that big sliding past tells the eye the ship is a speck. It is
  now 14 x 5 hull lengths with 0.75-hull streaks flowing at 75 hull lengths/sec. One
  node scale does the whole rescale — box, velocities and mesh — because the particles
  run in `local_coords`. `_fit_streaks` is called again on every ship swap.
  `tools/test_streak_scale.gd` locks the conversion down.

## Still open

- **The torch plume cones are close to invisible in the chase view.** Proven, not
  suspected: `brightness = 0` on all of them moves p99 by <0.001 and hiding the whole
  plume root moves the lit fraction from 0.24% to 0.34% on class_ii and not at all on
  dingo57. Seen end-on down its own axis the cone's walls are all edge-on, and
  `soft_edge = mix(0.06, 1.0, pow(facing, 1.15))` in `cruiser_torch.gdshader` drops them
  to 6%. The plume geometry is also small: class_ii's core cone is ~4.5% of hull length
  across. Now that the lights no longer dominate there is headroom to make the plume the
  thing you actually see — that is the next piece of work, and it was NOT done here.
- Shock diamonds remain compiled-but-never-visually-confirmed (carried over).
- All rendering here was llvmpipe software Vulkan. Performance is untested.

---

# Astryx — AAA booster/thruster pass (2026-09-02)

## What the thruster is now

Four layers, all driven from ONE value (`Ship._propulsion_power` + `_propulsion_surge`)
so no layer can disagree with another about how hard the engine is working:

1. **Torch cones** — `shaders/cruiser_torch.gdshader`, two per socket (fog sheath +
   inner core), built by `ShipMesh._add_torch_layer`.
2. **Nozzle lights** — `OmniLight3D` per socket. The torch is emissive geometry and
   cannot light anything; this is what puts engine glow on the hull.
3. **Heat haze** — `shaders/exhaust_haze.gdshader`, a screen-space refraction shell.
4. **Glow** — unchanged; the existing `WorldEnvironment` picks up the HDR emission.

Layers 2-3 live under a separate `BoosterNozzleRig` node, NOT under the per-ship plume
root. The plume roots have a checked contract ("N sockets -> exactly 2N CylinderMesh
children") and the contract tests assert exact child counts.

**There is deliberately no ember/spark particle layer.** One was built (a single
`GPUParticles3D` per ship on `EMISSION_SHAPE_POINTS`) and removed: with the emitter in
the scene the hull region washed out warm — a 960x540 frame went from 0.2% to 12.7%
bright pixels — and shrinking the sparks ~8000x (converting their scale from model to
world units) barely moved it, 12.0% -> 10.3%. So the cause is the emitter's presence,
not the quad size, and it was not worth shipping unexplained. If you try again, gate it
on `tools/render_thruster.tscn ISOLATE=no_embers` before keeping it.

## Torch shader specifics

- **Turbulence** comes from `assets/fx/exhaust_noise.png` (baked by
  `tools/gen_exhaust_noise.py`), sampled in `(angle, axial - flow)` space so it advects
  downstream, with a domain warp so filaments curl. It replaced the old `sin()` pair.
- **Seam:** `atan()` wraps a full turn at the back of the plume; automatic mip
  selection reads that as a huge UV step and drops to the blurriest mip, drawing a grey
  line down the exhaust. `flow_sample()` fixes it with `textureGrad` + wrapped
  derivatives. Do not replace it with a plain `texture()` call.
- **Shock diamonds** (Mach disks) are the strongest "real rocket" cue. Core layers only
  (`SHOCK_TRAIN`); on the fog sheath they read as banding.
- **Temperature ramp:** cold engine = orange, hot = blue-white. Shared with the JazOone
  hull disc so the disc and its plume never disagree.
- **Throttle shaping** happens in the vertex stage (`length_scale`, `flare_scale`),
  stretched about the NOZZLE end, not the centre, so a longer flame keeps its root on
  the socket. This needs `extra_cull_margin` or the plume pops off at high throttle.
- **Depth fade** is in WORLD units (view-space depth) while the mesh is in model space,
  so `_add_torch_layer` converts through the `fit_model` scale.

## JazOone — two things were actually broken

- Its engine discs were gated on `booster_uv_a`/`booster_uv_b` UV discs AND the emissive
  mask. `tools/probe_jazoone_sockets.gd` proves **no vertex UV lands inside either
  disc**, so that branch never ran. The UV gate is gone; the emissive mask alone is
  precise (3464 of 310277 vertices, in exactly two tight clusters).
- It had no plume geometry at all. `add_jazoone_booster_plumes` now builds it on the two
  probed sockets.
- **Mind the sign:** JazOone imports with `yaw: 0`, so its rear is **+Z**. The other
  three are `yaw: 180` and vent along **-Z**. `_add_torch_layer(..., facing)` carries
  this; a sign slip buries the flame inside the hull.

## Tooling

- `tools/gen_exhaust_noise.py` — bakes the tiling noise (seeded/deterministic). Periodic
  Perlin, not value noise (value noise leaves a visible rectilinear grid), with
  histogram equalisation (plain min/max rescale leaves FBM as grey mush).
- `tools/probe_jazoone_sockets.gd` — recovers sockets from the emissive mask.
- `tools/render_thruster.tscn` + `.gd` — offscreen contact sheet, all 4 ships x 3
  throttle settings, mirroring main.gd's environment. Run as a **scene**, not
  `--script`:
  `SHOT_DIR=/tmp/shots xvfb-run -a <godot> --path <copy> res://tools/render_thruster.tscn`

## Gotchas hit

- `TAU` is a **built-in** Godot shader constant; redefining it is a compile error.
- Headless (`--headless --script`) DOES compile shaders through the dummy renderer, so
  shader errors surface in the contract tests. Use that as the fast gate.
- `assets/fx/exhaust_noise.png.import` must stay `compress/mode=0`,
  `detect_3d/compress_to=0`, `fix_alpha_border=false`. The four channels are
  independent data; block compression correlates them and alpha-border bleeding
  corrupts RGB.

---

# Astryx — Authored ship roster and propulsion handoff (2026-08-27)

## Current state

- The player roster is now four authored ships: **Class II Galactic Cruiser**
  (default), **Snarkrans Starship**, **Dingo57 Starship**, and **SpaceShip**
  (JazOone / Sketchfab CC-BY).
- SpaceShip's `Layer_1` is five `Layer_1_Material_0` chunks of the **whole hull**
  (vertex-split, not five boosters). Painting them with the additive propulsion
  shader made the ship solid white. Hull now keeps its albedo; the HDR torch
  is masked to the two emissive engine discs.
- SpaceShip yaw is `0`. The Sketchfab GLB already faces correctly; the OBJ
  ships' `yaw: 180` flipped this one so the nose sat where the engines belong.
- The previous player ships, their dedicated engine loops/music, and the random
  procedural booster-layout system were removed.
- Hull customization is restored for every non-booster surface. Propulsion
  surfaces are excluded by shader identity and always remain white-hot.
- Class II uses its six authored `propulsion` patches as exact sockets. Each has
  a nested HDR white core and longer cyan fog sheath behind the nozzle face.
- Snarkrans uses the user-identified `.000` and `.010_...018` upper-booster
  objects plus the `.005_...035` and `.001_...034` lower-pair objects. Their
  three empty centers are filled with dense emissive plugs, then extended with
  the same nested torch treatment.
- Dingo57's eight user-identified booster groups retain their authored geometry,
  get the HDR propulsion material, and now also get fog+core trails from their
  rear faces (070/109 = center pair halves).
- The shared torch shader now flows: axial wisps, radial edge fade, white core
  going cyan toward the tip. JazOone SpaceShip is left as-is.
- Dingo57 ingest now keeps the eight booster groups as dedicated surfaces
  and merges every remaining face into one opaque `hull_body` surface.
  Runtime styling forces that hull opaque and double-sided, including under
  glassy hangar finish, so thin chassis panels (including bottom groups
  `053`, `065`, `092`, `104` and the earlier outer groups) cannot vanish.
  Do not split the hull back into SketchUp glass/opaque material buckets.
- Booster materials react to throttle, boost, warp charge, and starvation
  sputter. No booster position is randomized.

## Verification and constraints

- Headless contract tests cover all three imported ships and customization.
- Codex did not launch or visually render the game; the user reviewed the visual
  result and accepted the current pass as good enough to push.
- Keep future booster work mesh-specific. Tune the authored surface/socket and
  its emissive plume; do not restore the old random booster generator.
- Do not record this personal Astryx/space-game work in monthly worklogs.

## Best next action

Continue with user-directed visual tuning. For propulsion, adjust only the named
ship's socket radius, plume width/length, or shader brightness; preserve the
other ships and keep booster meshes outside hull recoloring.

---

# Astryx — Session Handoff (Sol cook · 2026-08-20)

Private repo: `git@github.com:Fiazul/space-survey.git` (`main`).
Godot 4.6.2. Game is code-spawned. First pass. Do not treat Sol as finished.

## Start here next time

**Bug: Sun vanishes on close approach.** Player flew DEV toward the Sun
(~0.109 AU, tape `Alt 15,653,855 km Sun`). Then lost the Sun getting closer
(they described a meter-scale region — recreate, do not guess the exact
number). Likely code: sky disc hides below `max(CAM_FAR*0.5, R_sun*1.2)`
≈ 835,000 km from centre (~140,000 km above photosphere), and the cook
mesh stays off because physical stars force `too_far = true`. Both off =
no Sun. Recreate with F9 at the Sun until Zone hits SKIN/INSIDE / skin
alt drops under ~140,000 km. Fix that first. The Sun is a `kind` 3 star,
not a unique object.

## What landed this slice

- One cook. Sol maps. Other stars cook from spectral type (no `sol.obj`).
  Exoplanets invent from radius/temp. Sky = HYG points; a ball cooks on arrival.
- 2k mosaics: Phobos, Ganymede (USGS sheet crop, grid still on), Callisto,
  Cassini majors, Uranian majors, Triton, Pluto, Charon. Deimos still pending.
- Moon from GEO is a real ball (far plane 520,000 km). Spawn still faces Earth.
- Sky Sun: 0.53° photosphere + circular corona (square glare was a quad with
  leftover edge glow; discarded + angular cap).
- Kind-3 burn: granules, limb, chromosphere rim.
- Tape: `Zone CENTER|INSIDE|SKIN|AIR|SPACE` + skin alt. Earth air 100 km.
  Spec: `docs/specs/2026-08-20-sol-flight-layers-design.md`.

## Next plan (after the close-Sun vanish)

1. Recreate + fix Sun/star LOD so one path handles far disc and close ball
   (Sun = just a star). No special `_sun_sky` forever.
2. Same LOD for any star: catalog row → position → recipe → render.
3. Earth look pass. Ganymede gridless map swap. Deimos mosaic.
4. Richer 101 km-band bird view. Titan/Venus air as real shells later.

## Not done

Earth polish. 8k USGS. Landing. Vacuum RCS. Flight feel. Billion visitable
meshes (sky points only until you arrive).

# Astryx — Session Handoff (v0.11.5 · current)

> Pick-up doc for the next session. Project: `/home/fiazul/Desktop/Astryx`
> Godot 4.6.2 / GDScript · repo `git@github.com:Fiazul/Astryx.git` (main).
> The game is **all code-spawned** — `Main.tscn` is a one-node stub; `main.gd` builds the
> world, ship, camera, lights, and UI at runtime.
> ✅ **Everything through v0.11.5 is committed + pushed** to `main`.
> ~12k lines of GDScript · ~35 modules · 7 ships · ~50 real star systems · Android APK + CI.

## What changed in v0.11.5 (latest)

- **Codebase modularization** — split the god-files into domain folders
  (`core/flight/world/travel/combat/ui` + `autoload/`) behind autoload singletons
  (`GameState`/`Ephemeris`/`Codex`/`PlanetData`/`GameAudio`); `main.gd` 2093→1780,
  `combat.gd` 1352→1031 (CombatFX + EnemyFactory split out). Map in
  [`ARCHITECTURE.md`](ARCHITECTURE.md), rationale in `docs/adr/0001-*`.
- **Galactic core cleanup** — removed the experimental Sgr A\* black-hole visual; the
  Milky Way galaxy backdrop + looming approach remain (`scripts/world/galaxy_model.gd`).
- **Ship music** — **Vela Iron Pulse** & **Lyra** now fly to the dedicated interstellar
  theme (`bgm_hani.ogg`), alongside HaniNebula & Raptor 2 Neo.

## What changed in v0.11.4

- **Realistic star field** — background sky is now a **baked real-catalogue points-mesh**
  (`scripts/starfield.gd` + `tools/build_starfield.gd`): default **HYG naked-eye, ~15,598 real
  stars** (mag ≤ 7), real sky positions, real B-V→RGB colour, magnitude-driven size/glow.
  Tiers `naked` / `tycho` / `high` / `low`. Full report: [`STARFIELD.md`](STARFIELD.md).
- **The galactic core** — the Milky Way is now visible as a textured **galaxy backdrop**
  (`scripts/galaxy_model.gd`, `assets/galaxy.glb`, CC-BY): placed toward the **real Sgr A\***
  direction, laid edge-on in the real galactic plane, additive glow + a radial-fade disc
  shader (no hard polygon edge), no occlusion of the starfield. Backdrop only — not a
  destination (~26k ly is past float32's reach). See [`STARFIELD.md`](STARFIELD.md).
- **Mars's moons** — added **Phobos & Deimos** (`ephemeris.gd`) with codex fact-sheets
  (`planet_data.gd`) and missions (`missions.gd`); fixed a **moon-detachment bug** where
  moons orbited their parent's raw Horizons position instead of its revolved scene position
  (`planet_system.gd` `frame_pos` cache, in both `refresh()` and `gravity_at()`).

## What changed in v0.11.1 → v0.11.3

- **v0.11.1** — dark, dramatic **wormhole transit visual** (the *style* pass promised in the
  v0.11.0 next-plan: ship holds facing the portal, slight shake, dark + cinematic).
- **v0.11.2** — **boss fights** + a **combat HUD target** readout; **drift-flip** (W+C) flight
  move; teleport / UX fixes.
- **v0.11.3** — **beginner quest** onboarding; **finite guardian waves** (swarms now end);
  **escape leap**; **capture ring** VFX; star-**gravity fixes**.
- **Docs/assets** — added [`CREDITS.md`](CREDITS.md) (models = Poly Pizza / Free3D, SFX =
  scripts, music = AI-generated) + README **Assets** section.

## What changed in v0.11.0

### Camera / controls
- **Free-look is HOLD again** (`ship.gd`): hold **T** (or RMB) to orbit the camera; full **360°**
  (yaw clamp removed); wider zoom (`ZOOM_MIN 0.2 … ZOOM_MAX 6.0`).
- **Crosshair pinned to the nose** (`hud.gd _draw`/`set_lock_progress`): the reticle is projected
  from the ship's forward ray each frame, so it sits exactly on the shot line through camera sway.
- **Muzzle moved to the nose tip** (`ship.gd muzzle = box.size.z * 0.42`).

### Weapons → hitscan "ray bullets"
- Player fire is now an **instant hitscan ray** (`combat.gd _fire_ray` / `_show_shot_beam`), not a
  projectile: no float-precision blob, no drift, no bloom-bar. A bright tracer **pulse** flashes per
  shot (`SHOT_*` consts). Aliens still fire dodgeable projectiles.
- New laser-zap **fire SFX** (`tools/gen_fire_audio.py` → `sfx_fire.wav`); bolt bloom tamed
  (`_bolt_material` emission 20→4, HaniStar 36→8). The `Smg Bullet.glb` projectile path is retired.

### Tab targeting — ray raycast (see `TAB_TARGETING.md` / `.png`)
- `main._aim_ranked()` returns the **up-to-4 objects the aim ray passes nearest to** (smallest
  ANGLE off the line); `_cycle_nav_target()` steps 1st→2nd→3rd→4th→loop; moving the cursor
  re-ranks. **Narrow ~7° beam** for bodies, **wide 28° for wormholes** (key nav targets); per-kind
  long reach (`_tab_pick_range`: star 30 ly, planet 0.3–2, moon 0.6, probe 0.3). NOT nearest-to-ship.
- Wormholes check **every** active portal (`portals_rel`), track which (`_nav_wormhole` / `_locked_wh`).
- **Undiscovered targets read "Unknown Planet/Star/…"** until scanned (`_tab_display_name`).
- **Hold X ≥1s** → locks the Tab target as an **orange** waypoint (`lock_nav_target`); a radial
  **lock ring** fills around the crosshair (`hud._draw_lock_ring`). Orange persists through aim/Tab
  changes — only the **✖ CANCEL NAV** button clears it. **Raptor form swap moved off X → hold RMB ≥1s**
  (`main._update_holds`).

### Gravity & slow-zones (`planet_system.gd`)
- **Star gravity ON** (`STAR_GRAVITY_ENABLED`) — stars pull the ship (planets/bolts stay off). It
  **fades as you thrust away** so it never traps you (`ship.gd` gravity block). Sol unaffected.
- **Stars slow you slightly more on entry**: `STAR_ZONE_MULT 90→120`, new `STAR_EDGE_SPEED 64`.

### Teleport (`main.gd`) + audio
- Teleport is a **small light-ball that shrinks to 0 → you jump** (`TELEPORT_TIME 8s`, `TP_ORB_BASE`);
  camera pulled back so it frames from outside. The **"voooouuu" whoosh fades in → holds → fades out**
  across the ritual (`tools/gen_teleport_audio.py` → 11s `teleport.wav`, volume bell in `_update_teleport`).
- Crisp **click** SFX (`gen_ui_click.py`). ⚠️ audio assets must be re-imported into the real tree
  (`godot --headless --import`) — running the game does NOT re-import changed WAVs.

### Wormhole network (multi-hub) — see `WORMHOLE_NETWORK.md` / `.png`
- `SystemDB._ensure_graph()` rebuilt: **5 spread hubs**, each linked to Earth + to each other; every
  other system spokes off its nearest hub (capped/balanced). **Earth→anywhere ≤2 hops, any→any ≤3.**
  Verified by `tools/test_wh_network.gd`. Diagram via `export_wh_graph.gd` + `draw_wh_network.py`.

### Platforms, teleport console, UI
- **Platforms everywhere promised**: `props.gd` spawns a single reusable **generic dockable platform**
  in every `has_station` system without a hand-placed station (fixes "teleported, no station"). Lazy
  (one node, re-homed per system).
- **Isolated platform-teleport console** (`platform_teleport.gd`): own screen (NOT the star map);
  unlocked platforms bright, locked dark grey; click → confirm → teleport ritual.
- **Quest log (J)** closes on outside-click.
- **New-game tutorial notifications** (`tutor.gd`): small left-of-middle tip boxes, ting-tong chime
  (`gen_notify_audio.py` → `notify.wav`), click-for-detail, drag-off to dismiss; **pops faster while
  Sol isn't fully scanned** (`main._sol_fully_unlocked`).
- **Capture celebration** (`reward_card.gd`): semi-transparent top-centre card, **auto-grants** the
  reward (no more "press G"), happy fanfare (`gen_reward_audio.py` → `reward.wav`), fades out in ~5s.
- **Reset Progress** button in Settings (two-tap confirm) → `main.reset_progress()` wipes the save +
  reloads. (Save lives in `user://`, not the repo.)

## ⭐ NEXT PLAN

Sol 1:1 first pass lives in this repo (`Fiazul/space-survey`). Full dump: [`docs/SESSION-2026-08-18-sol-first-pass.md`](docs/SESSION-2026-08-18-sol-first-pass.md). Rule: every Sol feature is a first cut and needs a perfection pass.

**First:** recreate Sun vanish on close approach (see top of this file). Then fold Sol Sun into the generic star LOD.

After that: Earth look, Deimos mosaic, Ganymede gridless swap, 101 km bird view. Layers spec: `docs/specs/2026-08-20-sol-flight-layers-design.md`.

Older carried list (still valid, not this Sol slice):
1. **Rudder finder**
2. **"New item found" → notification**
3. **A Notification TAB**
4. **Wormhole STYLE** transit visual

## Tooling notes (this session)
- All SFX are **pure-Python `wave` generators** in `tools/gen_*.py` (no deps). Regenerate then
  **re-import the real tree** so the running game picks them up.
- Parse-check on a COPY: `cp -r . /tmp/c && rm -rf /tmp/c/.godot && godot --headless --path /tmp/c --import`.
- Run: `DISPLAY=:1 <godot-bin> --path /home/fiazul/Desktop/Astryx`. Godot binary lives at
  `/home/fiazul/Desktop/Godot_v4.6.2-stable_linux.x86_64`.

---

# Astryx — Session Handoff (v0.10.0)

> Project: `/home/fiazul/Desktop/Astryx`
> Godot 4.6.2 / GDScript · repo `git@github.com:Fiazul/Astryx.git` (main). Everything
> below is committed + pushed. The game is **all code-spawned** — `Main.tscn` is a
> one-node stub; `main.gd` builds the world, ship, camera, lights, and UI at runtime.

## State of the game (v0.10.0)
A real-solar-system third-person explorer with light combat, navigation, a
discovery loop, a coin economy, an **in-hangar ship customizer**, a **mission log**,
and a **zoomable star map**. ~10.5k lines of GDScript across 25 modules; 51 real
star systems; Android APK + touch controls; CI release builds.

## What changed since v0.8

### v0.9.0 — wormhole graph + quests + full resume
- **Wormhole graph travel**: Prim's MST + extra edges; BFS `next_hop()` routing over
  *known* edges (`is_edge_known`); the Interstellar hub only lists **unlocked** wormholes.
- **Full state resume**: position, system, hull, coins, discoveries, onboarding step,
  and active quest all persist to `user://profile.cfg` (saved from stable states only).

### v0.10.0 (this session)
- **Mission Log (J)** — `missions.gd` (`MissionDB`): every star/planet/moon is a mission
  with a crude/savage (mostly-true) story + coin bounty (`STORIES` keyed by body name).
  `quest_log.gd` (`QuestLog`, CanvasLayer) is the board: list grouped by system, detail
  pane, **★ Track** → `main.track_quest()` drives the nav arrow; survey to complete/claim.
- **Zoomable / pannable map** — `map_chart.gd` (`MapChart`, custom `_draw`): wheel-zoom,
  drag-pan out to ~150 ly, star/wormhole/planet icons on **toggleable filter layers**, a
  live animated **player cursor**, hover read-outs, wormhole lanes. `map.gd` hosts it +
  filter chips + a right-side system body list. Wormholes are live on the corner radar
  (`wormhole.portals_rel`, `minimap.gd` swirl blips); the nav arrow prioritises wormholes.
- **Warp-speed rebalance** — top hulls ≈ 23–24 s/ly, mid ≈ 28–30 s, others ≈ 40 s. Tuned
  via per-hull `warp` (terminal velocity = `THRUST × warp / DAMPING`, NOT the `MAX_SPEED`
  cap). `UNITS_PER_LY = 6,324,107.7`; `warp ≈ 2874.6 / target_seconds`.
- **HaniStar customizer** — now `color_pick` like HaniNebula: body + wing swatches, bell
  toggle, metallic/glassy finish. Wings = **GLB surface 4** (verified by rendering each
  surface). Added `wing_surfs` (list) + `wing_role` options for multi-surface wings
  (HaniNebula's single `wing_surf` couldn't express it). `current_has_wing_pick()` now
  recognises all three (`wing_surf`/`wing_surfs`/`wing_role`).
- **Champagne Gold** palette — new `champagne` swatch + `recolor` role (polished gold:
  metallic 0.85, roughness 0.16). Palette is now **10** colours.
- **Editable Cancel Nav** (and HUD declutter) — `cancel_nav` is a registered movable HUD
  widget (drag-place + wheel-scale, persists to `user://hud_layout.cfg`); default baked
  into `DEFAULT_LAYOUT`/`DEFAULT_SCALE`. Centre-screen clutter (objective/quest/tip lines,
  bottom help strip) moved off to the free right side (`rx = SCREEN.x - 300`).
- **Guardian "phantom boss" bugfix** — a guardian boss parked at a body kept summoning/
  firing with no distance gate → `in_combat()` stayed true → warp bled to sublight →
  player stranded with a stuck "100%" bar. Fixes: a **leash** in `_update_scan` abandons
  the fight (`combat.abandon_combat()`, zeroes `_combat_t`) once you're > `GUARD_RANGE×2.5`
  from the guarded body; `reset()` clears stale `guard_body`/`zone_kills`/`_combat_t`.
- **Named bosses** — `combat.BOSS_NAMES` (crude/savage), deterministic per body via hash;
  `boss_state()` returns `name`; HUD bar + probe scan show it (Alien-zone boss = "Vortex").

### Ships (`ship.gd`, `SHIP_MODELS`)
Seven hulls. Each entry tunes hp / fire / warp / booster / surface roles.
- **Lyra** tanky red laser-bolts (`raw` look) · **Stella** glass-cannon machine-gun ·
  **Raptor** dual-booster bruiser (X = warp/combat form fork) · **Vela** FTL, spools over
  ~9s, **R** air-brake · **HaniStar** pink support that fights (`bolt_strong`), now
  colour-pickable · **Raptor 2 Neo** mother-ship with nose **laser** (2 GLB surfaces:
  `silver` hull + `glass` strips) · **HaniNebula** evolved pro form, fully colour-pickable,
  boosters snapped to her model's real engine holes (`BOOSTER_NO_RING`), own music track.

### In-hangar customizer (`hud.gd set_hangar` → `main.gd` → `ship.gd`)
- **BODY / WING COLOUR** swatches from `Ship.SHIP_PALETTES` (10: rosegold, blush, navy,
  teal, charcoal, emerald, burgundy, silver=SteelBlue, gold=Silver, **champagne**=gold).
- **ENGINE BELL** add/remove · **FINISH** metallic/glassy (`ShipMesh.set_glassy`).
- Opt in with `"color_pick": true`. Surface mapping styles in `_build_ship_model`:
  **whole-hull** (HaniNebula: body everywhere except `wing_surf`) vs **template**
  (Raptor 2 / HaniStar: replace `body_role` surfaces, paint `wing_surf`/`wing_surfs`/
  `wing_role` with wing colour, keep glass).
- Persisted per-ship: `ship.customization_state()`/`load_customization()` ↔
  `user://profile.cfg` `[player] customization`.
- ⚠️ **Metallic gotcha:** in this probe-less scene `metallic = 1.0` has no diffuse and
  only mirrors the empty starfield → reads as *clear glass*. Palette roles use
  `metallic ≈ 0.55` + `emission = albedo` so colours stay solid (see `ship_mesh.gd recolor`).

### Flight feel, VFX, audio
- **Sublight drift** (`DRIFT_DAMPING` 0.32) glides through turns; blends to `DAMPING`
  (0.75) as warp spools so FTL times stay tuned. Heavy A/D + up/down low-passed.
- Living booster flame (layered sines on a smoothed base) + motion streaks.
- Per-ship engine voice ducks under music after ~8s; **HaniNebula** has her own track.

## Controls
WASD thrust · **Shift** boost · **Q/E** roll · **Space/Ctrl** up·down ·
**L-click** fire · **R-click** laser (Raptor 2) · **Tab** waypoint · **V** scan/capture ·
**L** codex · **W+C** drift-flip · **J** mission log · **G** details · **M** map · **F** dock/wormhole ·
**R** Vela brake · **Num Lock** auto-cruise · **H** teleport Earth · **Esc** cursor/back ·
wheel zoom · **1–7** swap ship (docked).

## ⭐ NEXT — planned TODO (carried over)
1. **Bullet "bloat" fix** (combat.gd) — the fat cyan bar in fast dogfights. Root cause
   diagnosed: a 51-unit additive trail + hard bloom (emission 10) near the ~1u chase cam.
   Levers: cap `reach` to ~20 + drop emission to ~4. **Reverted twice** — must NOT change
   shooting speed/gating; only the trail/bloom. Get a screenshot to confirm.
2. **Platform F-interaction** — at a platform, **F** lets you choose ship AND quick-teleport
   to another unlocked platform. (Platforms = wormhole-attached now + player-placed later.)
3. **Show platforms on the map** (each platform's position).
4. **Confirm warp boost fork** — is the 23 s/ly the W-cruise terminal or boosted? If boosted,
   divide `warp` by ~3.
5. **Unify interaction on F** — drop **V** capture (hold-F to capture; F context chain:
   dock/platform/wormhole/capture); repurpose **V** → auto-navigate to the tracked quest.
   (Do NOT change shooting.)
6. **Right-side quest box** — boxed/table tracker on the right; click or key → navigate.
   Replaces the old top-centre tracker.
7. **Guide/prompts as side notifications** — boxed, clickable for detail (currently plain
   right-side labels).
- Background long-shot: **double-precision build** (`precision=double`) to kill float32
  jitter at ly-scale → real planet sizes + landable surfaces; combat stakes (Hull 0 is a
  no-op today → death/respawn).

## Headless / verification workflow (assistant can't see a live GPU)
- **Parse check** — never `--import` the real tree (the importer re-tabs `ship.gd`
  comments). Validate on a **copy**: `cp -r . /tmp/acheck && rm -rf /tmp/acheck/.godot &&
  godot --headless --path /tmp/acheck --import` then grep stderr for errors.
- **Render a model surface-by-surface** (to identify wings etc.) — the real Godot binary
  (`/home/fiazul/Desktop/space_craft/Godot_v4.6.2-stable_linux.x86_64`) under
  `xvfb-run` renders with hardware GL: load the GLB into a `Node3D` scene, tint each
  surface a distinct colour, position a `Camera3D`, `await` a few `process_frame`s, then
  `get_viewport().get_texture().get_image().save_png(...)`. Run as a real scene
  (`godot --path COPY res://render.tscn`), NOT `--script` (a SceneTree `--script` won't
  pump render frames and hangs).
- Visual changes need the user's eyes — get a screenshot before declaring done.

## Profile / saves
`user://profile.cfg` (progress + per-ship customization), `user://codex.json`
(captures), `user://hud_layout.cfg` (HUD layout). Flatpak userdata:
`~/.var/app/org.godotengine.Godot/data/godot/app_userdata/Cold Light/`.
