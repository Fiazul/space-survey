# Needs your eyes

## STANDING PHYSICS NOTE from the user (2026-09-04) — keep this

Verbatim, on a frame at 52 km altitude where the air shell was painting the whole
sky light blue:

> No, the view in this image does not align with reality.
>
> **Sky Brightness in Space:** The background sky is rendered in a bright
> light-blue color instead of deep pitch-black space. In real low Earth orbit or
> deep space, space appears pitch black, even on the sunlit side of a planet.
>
> **Lack of Atmospheric Scattering in Space:** Light-blue sky illumination
> requires Rayleigh scattering through a dense planetary atmosphere around the
> observer. Looking past the edge of a planet from space does not illuminate the
> vacuum of space itself.
>
> **Surface Shadow Contrast:** The dark side (night side) of the planet visible on
> the bottom-left drops into a total black void, but the sky right next to it
> remains light blue, which violates basic light propagation and exposure physics
> in space.
>
> **Dynamic Range & Exposure:** If cameras or human eyes expose for a brightly lit
> sunlit planet curvature, faint background stars remain invisible; conversely, the
> background vacuum stays black rather than glowing blue.

This is a standing constraint, not a one-off bug report. Any future sky, haze,
glow or atmosphere work has to satisfy it: **scattering needs air AROUND THE
OBSERVER along the view ray, and it needs sunlight on that air.** Vacuum is black
regardless of what is nearby and how brightly it is lit.


## STANDING DESIGN BUG from the user (2026-09-05) — keep this

> When we move away from a star — going *towards* space from Earth or the Moon,
> not going in — we should get acceleration. It's a must-fix; currently this is a
> very bad design bug.

**Band speed cap removed 2026-09-08.** Player decision: no hard speed cap in
air at all — Sol speed is Newton + drag only, everywhere, both directions.
Superseded two same-day partial fixes (gating the cap on radial-inward
velocity at both sites it was folded in): rather than make the cap
direction-aware, it is gone. `PlanetSystem.refresh` no longer folds
`FlightMode.band_speed_cap_units`/`_ms` into `speed_limit` (the
`sampler.alt_above_ground_km` call that feeds `_surface.update_for` and the
prop/terrain band itself are unaffected — only the speed-limiting fold was
removed); `refresh()`'s signature is back to `(ship_pos, delta)`, no velocity
parameter, since nothing else in it needed one. `FlightMode.break_at_exclusion`
keeps its inward-only gate (that one guards a real anti-tunnelling snap, not a
speed limiter, and stayed). `FlightMode.band_speed_cap_ms`/`_units` and
`BAND_CAP_ANCHORS` are deleted outright, not merely unused: the flight-side
speed cap they served is gone, and the ONE other caller
(`tools/test_earth_terrain.gd`'s ring-quad anti-tunnelling-design check) moved
to `SurfacePatch.design_speed_ms`/`_units` / `DESIGN_SPEED_ANCHORS` /
`WORST_FRAME_S` the same day — that curve was never a flight rule to begin
with, only a ring-geometry sizing bound that happened to reuse the same
numbers, so it lives with the ring code now. `grep -rn band_speed_cap
scripts tools` finds no caller, only historical comments. Arcade (non-Sol)
systems were never on this path — their force-slow zones (`STAR_ZONE_*`, the
star/edge speed floor in
`refresh`) are a different, untouched mechanism.

Player checklist:
- Burn straight out from 5 km over Earth or dive straight down — speed is
  governed by gravity and drag only, no artificial floor or ceiling either
  direction.
- Fly level in-band at a constant altitude and speed near a power-of-two
  quad boundary (e.g. cruise through ~10-11 km on Earth) — rings should hold
  their current tile size rather than visibly popping every frame
  (`HYSTERESIS_UP`/`_DOWN`).
- Recenter or descend through the band and watch the ring boundaries
  (Earth or Moon, any altitude) — no visible stutter/freeze on this machine
  any more (ring rebuilds no longer block a frame); the old ground keeps
  showing, seamless, until the new ring set is fully ready.
- Look at hazy, low-contrast, far ground near a ring 0/1 boundary (the
  `himalaya_9km`/`ring_boundary_r0r1` viewpoints) — the faint concentric
  crease reported earlier should be gone; shading across a ring seam should
  now be continuous.

Things I cannot verify and you can. Everything here renders on **llvmpipe
software Vulkan** in my environment, so I can prove geometry, ranges, shared
rules and bounds — never appearance. Delete a line once you've judged it.

Fly to Earth, drop through **16.16 km**, and look. Band runs 0.03 → 16.16 km.
(Historical — the ceiling since measured higher: `tools/test_surface_band.gd` now
reports 0.03 → 34.99 km on Earth.)

---

## 1. Three parameter judgments from slice A6 (light and air)

These are tuned to numbers I derived, not to a look. Each has a named lever.

| What to judge | If it's wrong | Lever |
|---|---|---|
| **Haze distance.** Does the far ground dissolve like kilometres of air, or like a grey fog a few hundred metres out? | too much / too little depth | `PlanetGenerator.HAZE_KM` (70.0). Higher = clearer. Measured: 95% at ring 3's 205 km rim, 25% at 20 km, 3% at 2 km (historical — rings are horizon-following now; `tools/test_terrain_light.gd` currently reports 100% at ring 3's 1311 km rim, 25% at 20 km, 3% at 2 km) |
| **Terminator curve.** Do ridges read, or does the lit/dark transition crush them into flat black and flat white? | ridges vanish near the terminator | `TERMINATOR_LO` / `TERMINATOR_HI` (−0.04, 0.28). Widen the gap for a softer roll-off. **Changing these changes the globe too — that sharing is deliberate** |
| **Air shell.** Is it a sky, or a blue wash over everything? | reads as a filter, not air | `air_shell_opacity()`'s `pow(depth, 1.5)`. Measured 0.78 at 15 km, 0.09 at 80 km |

Also worth a glance: **the night side.** `NIGHT_FILL` is 0.06, so the dark
hemisphere is 6% lit rather than pure black — pure black loses the horizon and
reads as a hole. If it looks milky, that number is why.

## 2. The pale diagonal band from the 22:57 screenshot

**Not reproduced 2026-09-08**, across 12 rendered captures spanning the
altitudes and geometry named in the original report: `earth_7km, earth_20km,
earth_34km` (near the 35 km ceiling), `coast_2km`, `himalaya_9km`, `moon_7km,
moon_20km, moon_200m`, plus new poles (`arctic_2km, antarctic_5km,
north_pole_exact_2km`) and two shots centred on the ring 0/1 and ring 1/2
stitch lines (`ring_boundary_r0r1`, `seam_horizon_r1r2`). None show a pale
band with no ground; the globe/ring handoff (`planet_system.gd`, "The coarse
globe has a different displacement...") stayed a hard cut in the SAME frame
`_surface.visible` flips (`if _surface.visible: b.sphere.visible = false`,
right after `_surface.update_for` returns) — there is structurally no frame
where both are visible together, so the "globe pokes through a valley"
mechanism this cut guards against cannot occur either. What the captures DO
show, once already, is a related but distinct failure: `should_show()`'s
altitude gate had no margin, so a ship holding level flight exactly at the
ceiling or kill line could flip the ring **and** the globe it hides on and
off every frame — a strobe, not a "no ground" pale band, but plausibly what
got misread as one from a single frame. Fixed: `SurfacePatch._in_band_hyst()`
(instance-side, `should_show()` itself stays a pure boundary test —
`CloudLayer.should_show` and `tools/test_cloud_layer.gd` both assert it at
exact edge values) requires clearing either edge by `BAND_HYSTERESIS` (2%)
before actually leaving the band once already shown. Covered by
`tools/test_surface_band.gd`'s `_band_edge_hysteresis()`. If the pale band
recurs, it needs a fresh screenshot with an altitude/position readout — one
frame with no numbers attached could not be narrowed further this session.

## 3. Ring seams

**One real seam found, everything else clean.** All 12 captures above show
sealed rims — no gaps, no visible-through-to-the-globe slivers — confirming
the skirt/stitch maths does what it claims. `ring_boundary_r0r1` (camera
centred on the ring 0/1 stitch, 1 km alt) and `seam_horizon_r1r2` (ring 1/2
stitch near the horizon, 5 km alt) are both clean water/coast, no crease.

One WAS visible, faint, and is now **fixed 2026-09-09**: `himalaya_9km` (9 km
alt, looking 18 km ahead over dry terrain) showed a barely-perceptible
straight-edged crease in haze-distant ground at the ring 0/1 boundary —
confirmed root cause was per-mesh normals: each ring computed its vertex
normals from its OWN face/neighbour data, so two adjacent rings built at
different quad sizes could (and did) disagree at their shared rim, even
though both rings sample the exact same `TerrainSampler` height. Fixed by
deriving every vertex normal analytically instead of from mesh geometry:
`SurfacePatch._analytic_normal()` samples `sampler.ground_radius_km()` at
a FIXED world step (`NORMAL_STEP_FRAC` × ring 0's quad size, the SAME step
for every ring in the batch, not each ring's own quad size) via central
finite differences along the east/north tangents, then cross/normalize/
flip-toward-outward. Two rings built from the same sampler at the same
world position now compute the identical normal by construction — there is
no averaging step left to disagree. Covered by
`tools/test_surface_band.gd`'s `_ring_boundary_normal_agreement()`, which
builds a Moon patch, finds the closest committed vertex in ring 0 and ring 1
near their shared rim, and asserts both match the analytically-expected
normal and each other within 1e-3. Re-captured `himalaya_9km` after the fix
shows the same edge-detect + level-stretch pass with the crease gone
(`crop_himalaya_edge.png`/`crop_bl.png` were the before evidence).

## 4. Does it still hitch?

**No — fixed 2026-09-09, moved off the main thread entirely.** The previous
fix (staging one ring per `update_for` call across several frames) still cost
~130 ms of MAIN-THREAD time per frame while it landed, spread rather than
gone. That's now replaced: `SurfacePatch._start_rebuild()` dispatches all 4
rings as one `WorkerThreadPool.add_group_task()` (one element per ring,
`_compute_ring()` runs on a background thread and returns plain
arrays/dictionaries only — no `Mesh`/`ArrayMesh`/`RenderingServer` call is
ever made off the main thread), and `_poll_rebuild()` checks
`is_group_task_completed()` once per `update_for` call, committing the whole
batch atomically (`_finish_rebuild()`, main-thread only, builds the actual
`ArrayMesh`es via `add_surface_from_arrays`) the instant it's ready. The old,
fully self-consistent ring set keeps showing — no seam, no empty gap — for
however many real frames the background batch takes.

Measured this session (`tools/_probe_timing2.gd`, deleted after use), Earth,
ring 0 at 6 km alt, warm materials (shaders already compiled), a 5 km
recenter (large enough to cross `REBUILD_FRAC` and actually trigger a
rebuild):

| Event | Main-thread cost | Before (staged, previous pass) | After (WorkerThreadPool) |
|---|---|---|---|
| Recenter dispatch (the `update_for` call that starts the batch) | one-time | part of ~131 ms/frame | **0.09 ms** |
| Per-frame poll while a batch is in flight (`is_group_task_completed` check) | every frame until commit | ~131 ms/frame x up to 4 frames | **~0.09 ms/frame** (measured avg 0.085 ms over 360 polls) |
| Total wall time for the batch to actually finish (off main thread, does not block a frame) | — | ~527 ms spread over 4 frames | ~31-360 ms depending on `WorkerThreadPool` scheduling load, entirely off the render thread |
| Cold arrival / any rescale | main-thread cost | ~590-870 ms **blocking**, one frame | same dispatch/poll cost as recenter — cold and rescale go through the identical async path now (`update_for`'s `cold or rescaled or recentered` check), not a special-cased synchronous rebuild. Nothing was showing before a cold arrival anyway, so there is no old set to protect; the tile is simply invisible for the same off-thread duration instead of freezing the frame. |

`tools/render_terrain.gd`/`tools/test_earth_terrain.gd`/
`tools/test_surface_band.gd`/`tools/test_terrain_light.gd` all use a
test-only `SurfacePatch.force_ready()` (blocks until the in-flight batch
lands) wherever they need geometry deterministically ready in a single
synchronous call — the live game (`PlanetSystem`) never calls it and never
blocks a frame on ring geometry.

Also fixed (carried over from the previous pass): `base_quad_km()`'s
quantisation had no hysteresis, so an altitude landing a float epsilon
either side of a power-of-two boundary could flip the bucket — a rebuild
dispatch — every single frame the ship held that altitude.
`base_quad_km(alt, radius, current)` now takes the ring's current bucket and
holds it within a ±6%/-53% band around itself (`HYSTERESIS_UP`/
`HYSTERESIS_DOWN`) before allowing a step. Covered by
`tools/test_surface_band.gd`'s `_quantisation_hysteresis()` (finds the real
crossing altitude by bisection rather than hard-coding the horizon formula).

Per-ring COMPUTE cost is unchanged (still real CPU work, just off the main
thread now) — that's the noise-inlining / `RING_SEGS` lever, untouched this
pass, and the next thing to pull only if background-thread contention with
other systems ever becomes the bottleneck instead of frame time.

## 5. The ship mesh looks yaw-rotated ~30°

Reported 2026-09-04, not diagnosed. Full note in `docs/SESSION-2026-09-04-skin-band.md` under "Still open",
including the three candidate layers and why a counter-rotation is the wrong first
move.

---

## 6. Hypersonic-entry visual layer — removed 2026-09-09

Plasma sheath, hull heat glow, and camera g-sag/buffet were built on
`FlightMode.air_load`, then found unreachable in controlled flight: 2 g thrust
vs 2.5·rho·v² drag caps sustained airspeed at ~80 m/s at sea level and ~250 m/s
at 10 km, so `air_load` never exceeds ~0.005 — below every FX threshold. The
whole visual layer was removed rather than shipped invisible; `air_load`/`mach`,
the HUD readout, and engine-air audio stay. See `docs/ROADMAP.md` "G.8" for what
a reachable regime would need before any visual FX is re-added.

---

## Known-not-fixed, so don't report these

- **Ground is still one flat colour.** The albedo spans under two texels across a
  whole ring — 0.51 on Earth. Slice A7 (the palette) is what fixes it.
- **No mountain ridges at 50 m scale.** `DETAIL_FREQ` gives a **44.5 km**
  wavelength, which is coarser than ring 0's entire 3.2 km width, so it adds broad
  undulation rather than ridges. Ridge-scale features need roughly 150× that
  frequency. I described this as "what makes 50 m triangles worth having" in an
  earlier commit; that was wrong in effect, and it is the #4 item on the
  reference-image gap list.
- **No cast shadows.** A mountain does not shade the valley behind it; dark sides
  are dark only from facing away from the sun. Named in the spec as the biggest
  remaining gap from your reference image.
- **Water is a dark plate**, not a surface. Slice C.
- **Trees only between 570 m and 5.2 km elevation** on dry ground, so most of
  Earth has no props at all. Slice D.
