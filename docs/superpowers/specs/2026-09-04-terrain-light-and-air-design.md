# Terrain light and air

Slice **A6** of the Earth flyover. The ground stops being a flat sheet and starts
being sunlit land under an atmosphere.

Target is the reference the user set: a ship low over a planet, relief running to
the horizon, mountain faces catching a low sun with their far sides in shadow, and
distant terrain dissolving into a warm haze band under a graduated sky.

| Slice | State |
|---|---|
| A1-A5 | Sampler, rings, ceiling, cap, contact kill — **done** |
| **A6** | **Light and air — this document** |
| A7 | Surface colour palette (was Task 7 of the terrain plan) |
| B / C / D | Named peaks / water / kit objects |

## Problem

Three named gaps, all measured rather than guessed.

**The terrain is unlit.** `surface_patch._mat()` sets
`SHADING_MODE_UNSHADED` on both the land and water materials. There is no sun
angle, no darker side to a hill, no ridge definition — the mesh renders at its
albedo value regardless of where the sun is. Almost everything the reference image
communicates is *shading*, so this is the single largest gap and the cheapest to
close. The flag is a holdover: it dates from when the tile was a small stamp in a
dark scene and shaded boxes read as the "black boxes" bug in
`PLANET_GENERATOR.md`.

**Nothing fades with distance.** Searching for fog across the world scripts and
the cook shader finds it only as `fog_disabled` on the starfield, galaxy and
corona materials. Ring 3 reaches 204.8 km and its outer edge is a hard boundary
against black. In the reference, distance is what sells the scale.

**There is no sky inside the air.** The cook shader paints an atmospheric limb for
a globe seen from *outside*. From 15 km up inside the air there is nothing: black
space and stars. Haze needs something to fade into, so it cannot land alone.

## Goal

At 15 km over Earth: sunlit relief to the horizon, a shadowed side to every ridge,
distant ground dissolving into a coloured horizon band, and stars still faintly
visible overhead. No shadow maps, no volumetrics, no landing.

## Design

### A6.1 One lighting rule, two consumers

The same argument that governs height governs light. `planet_cook.gdshader`
computes the terminator three times as `smoothstep(-0.04, 0.28, ndotl)`. If the
tile lights itself with Godot's `DirectionalLight3D` while the globe uses that
curve, the two will disagree exactly where they meet — the tile's edge — and no
amount of parameter twiddling fixes a structural mismatch.

So the terminator becomes shared data:

```gdscript
PlanetGenerator.TERMINATOR_LO := -0.04
PlanetGenerator.TERMINATOR_HI := 0.28
```

Bound as uniforms to **both** the cook material and the new tile material, with a
test asserting both receive the same pair. `planet_cook.gdshader`'s three
hardcoded call sites become that uniform.

The tile gets its own shader rather than a `StandardMaterial3D`, for the same
reason: it must run the project's terminator, not Godot's lambert.

`shaders/terrain_tile.gdshader`, `render_mode` shaded is not used — it computes
light itself from `sun_dir`, exactly as the cook shader does, so the two paths are
one rule:

| Uniform | From |
|---|---|
| `sun_dir` | `PlanetGenerator.apply_view()`, same vector the globe gets |
| `term_lo`, `term_hi` | the shared constants above |
| `air_amount`, `color_air` | the recipe |
| `haze_km` | derived — see A6.3 |
| `camera_up` | for the horizon-band gradient |

### A6.2 Smooth normals, which the grid rebuild just made free

`_tri()` currently sets one face normal per triangle, so the mesh is flat-shaded:
every 50 m quad is a visible facet. That is tolerable unlit and unacceptable once
light lands.

The performance pass replaced per-quad sampling with a `(RING_SEGS+1)²` grid, so
each vertex's four neighbours are already in hand. Vertex normals come from the
grid's own cross-products at no sampling cost:

```
n[i,j] = normalize(cross(p[i+1,j] - p[i-1,j], p[i,j+1] - p[i,j-1]))
```

Edge vertices fall back to the outward radial. **Positions do not change** — this
is shading data only, so `mesh_matches_the_height_function` must stay green
through this change, and it is the check that proves normals were not smuggled
into geometry.

### A6.3 Aerial perspective

Terrain colour blends toward a haze colour by distance from the camera:

```
haze = 1 - exp(-dist_km / haze_km)          # exponential, not linear
haze *= air_amount                          # airless worlds get none
haze *= low_altitude_density                # thicker near the ground
```

`haze_km` is chosen for a stated purpose rather than by eye: **ring 3's outer
edge must be substantially dissolved.** Ring 3 reaches 204.8 km, so
`haze_km = 70` puts its rim at `1 - exp(-204.8/70)` = **95% haze**. That hides the
LOD boundary as a side effect, which is the other reason the ring edges were a
listed risk after Task 3.

Measured across the plausible range, so the choice is visible as a choice:

| `haze_km` | ring 3 rim (204.8 km) | 20 km out | 5 km out |
|---|---|---|---|
| 40 | 99% | 39% | 12% |
| **70** | **95%** | **25%** | **7%** |
| 120 | 82% | 15% | 4% |

40 fogs the near ground you are meant to be flying over; 120 leaves ring 3's rim
visible. 70 dissolves the boundary while keeping the first 20 km clear.

Haze colour is not a flat tint. In the reference the horizon is warm cream toward
the sun and cool blue away from it, which is forward scattering:

```
warmth  = max(dot(view_dir, sun_dir), 0) ^ 2
haze_col = mix(color_air, sun_warm, warmth)
```

`sun_warm` derives from the star's own colour (`PlanetGenerator.color_from_spectral`
already exists), so a red dwarf's haze is red without a table entry.

Airless worlds get `air_amount = 0` and therefore no haze at all — the Moon must
keep its hard horizon against black, which is correct and is worth asserting so a
future tweak cannot fog the vacuum.

### A6.4 The air shell

One inward-facing sphere at the atmosphere top, additive over the starfield,
opacity following how deep in the air you are:

```
depth = clamp(1 - alt_km / atmo_top_km, 0, 1)
opacity = depth^1.5 * air_amount
```

At 15 km of Earth's 100 km column that is `0.85^1.5` = 0.78 — a strong sky that
still lets stars through, which matches the reference (stars are visible at the
top of its frame). At 80 km it is 0.09, so orbit keeps its black sky and the
existing look is untouched above the band.

Vertical gradient from `color_air` at the zenith to the same forward-scattered
warm colour at the horizon, so the shell and the terrain haze meet in the same
colour instead of showing a seam between them.

This is one mesh and one shader, drawn only when `opacity > 0`. Airless worlds
never draw it.

### A6.5 What this does NOT do

No shadow maps — a mountain does not cast onto the valley behind it. Self-shadowing
needs a depth pass at these extents and is not worth it for a survey flyover. No
volumetric scattering. No clouds from below. No specular sun-glint on water (that
is slice C, with the water surface). No change to the globe's own appearance from
outside, beyond the terminator becoming a uniform with identical values.

## Files

| File | Change |
|---|---|
| `shaders/terrain_tile.gdshader` | **new** — lit, hazed terrain |
| `shaders/air_shell.gdshader` | **new** — inside-the-atmosphere sky |
| `shaders/planet_cook.gdshader` | three hardcoded terminators become one uniform |
| `scripts/world/planet_generator.gd` | `TERMINATOR_*`, `terrain_material()`, `air_shell_material()`, `sun_warm_for()` |
| `scripts/world/surface_patch.gd` | grid vertex normals; tile material from the generator instead of `_mat()`; air shell node |
| `scripts/world/planet_system.gd` | feed `sun_dir` and altitude to the tile and the shell each frame |
| `tools/test_terrain_light.gd` | **new** — this slice's contract |
| `tools/test_earth_terrain.gd` | normals must not move positions |

## Verification

**This is the slice where headless verification is weakest, and that has to be
said plainly rather than papered over.** Everything here is about appearance, and
this environment renders on llvmpipe software Vulkan. What can be proven:

- `terminator_is_one_shared_rule` — the cook material and the tile material
  receive identical `term_lo` / `term_hi`, and `planet_cook.gdshader` no longer
  contains a hardcoded `smoothstep(-0.04, 0.28`.
- `tile_is_not_unshaded` — the tile material is the terrain shader, and no
  `SHADING_MODE_UNSHADED` remains on the land or water material.
- `normals_are_smooth` — adjacent vertices within a quad carry different normals
  (a flat-shaded mesh gives identical ones per triangle).
- `normals_did_not_move_the_geometry` — `vertex_error_km` stays float32-tight, so
  shading data cannot have leaked into positions.
- `normals_point_outward` — every vertex normal has a positive dot with its own
  radial direction; an inverted normal lights the terrain from underneath.
- `haze_dissolves_ring_3` — `1 - exp(-ring_reach_km(3)/haze_km) > 0.9`.
- `haze_is_off_in_vacuum` — an airless recipe yields zero haze at any distance.
- `haze_warms_toward_the_sun` — the haze colour looking sunward differs from the
  colour looking away, and is warmer (higher r-b).
- `air_shell_thins_with_altitude` — opacity at 15 km > 0.5, at 80 km < 0.15, at
  the ceiling monotonic between.
- `air_shell_absent_in_vacuum`.
- Both new shaders compile, which a headless material instantiation does prove.

Every assertion gets mutation-tested.

**What cannot be proven here, and needs a screenshot from the user at 15 km over
Earth:** whether it looks right. Specifically whether the haze distance reads as
kilometres rather than metres, whether the terminator curve makes ridges legible
or crushes them, and whether the air shell's colour is a sky or a blue wash. Those
are three parameter judgments, and they are the user's.

## Judgment calls

**Own shader rather than Godot lighting.** More code, but the alternative
guarantees a visible discontinuity at the tile's edge where the globe's terminator
and Godot's lambert meet. The whole slice is built on shared rules; light is one.

**Haze distance derived from ring 3's reach.** `haze_km = 70` is not a taste
value, it is "dissolve the LOD boundary". If the look wants more or less haze, the
honest lever is `air_amount` per recipe, not this.

**No shadow maps.** Named explicitly because their absence is the biggest
remaining difference from the reference after this slice: the reference's valleys
are dark partly from cast shadow, and ours will be dark only from facing away.
