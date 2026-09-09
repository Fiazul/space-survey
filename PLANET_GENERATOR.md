# Planet cook

One system paints every world. Catalog row → true position → **recipe** → ball.
You do not land. A billion stars stay sky points until you are there.

## Current close-flight behaviour (2026-09-07)

- Solid planets use local terrain below a per-body ceiling, floored at 35 km above ground
  (see "Skin band" below for the derivation). Measured terrain max: Earth 7.60 km, Moon
  11.64 km, Mars 24.31 km (real DEMs as of 2026-09-09's 4k/8k re-wiring — Earth's max
  dropped from the earlier 9.49 km measured against the old unsigned/land-only
  `earth_height.jpg`; `tools/test_dem_calibration.gd`), all well under the 35 km floor.
- Patch coordinates, terrain queries and impact checks use the body's own rotating frame. The Moon is not anchored at Earth's centre.
- Ring half-width covers the horizon with a projection margin. All rings recenter together to keep their stitched boundaries aligned. The coarse globe is hidden only while the complete local terrain replaces it.
- The altitude tape reads **AGL**, with metres below 1 km; height above the reference sphere is not clearance above a mountain.
- Contact starts hull-loss/respawn, not landing. Earth's substep clamp latches impacts before floating-point projection can hide them; other bodies use a body-local swept contact test.
- Terrain retains mapped geography, adds slope lighting and procedural substrate, and seats smaller kit props on the ground. Airless worlds do not inherit grass or ocean water.

Limits: Earth/Mars/Moon maps are still kilometre-resolution (4 pixels/degree for
Mars/Moon), with procedural finer relief below the map's own texel, not
satellite-detail scenery. Synchronous ring rebuilds keep seams coherent but may
hitch; asynchronous terrain streaming remains future work. This is not general
ship-to-object rigid-body collision.

Checks: `tools/test_surface_integration.tscn` exercises live Moon placement and Earth/Moon death entry; `test_earth_terrain.gd`, `test_surface_band.gd`, `test_terrain_light.gd`, and `test_skin_kill.gd` cover geometry, coverage, materials and contact. `test_dem_calibration.tscn` covers Mars/Moon's real DEM calibration, the RG16 import path, and the CPU/GPU decode mirror. `tools/render_terrain.tscn` captures Earth/Moon bird's-eye and low-altitude views.

## Contract

### Recipe-driven geology and materials

`scripts/world/surface_recipe.gd` resolves the surface profile. Its world defaults
are starting points; a recipe's `surface` dictionary overrides individual values.
Both named `recipe_for(...)` and invented worlds accept those overrides.

| Profile | Generated geometry / material |
| --- | --- |
| Earth | Existing mapped mountains, rock strata/grain, level ocean with animated ripple normals and glints; seeded dormant cones only on dry terrain |
| Moon / Mercury | Crater bowls, raised rims, ejecta, lunar small-crater field and irregular lit boulders; no liquid |
| Mars / Venus | Dry relief and volcanic cones with calderas; no default glowing lava |
| Io | Cones/calderas with local basalt and animated molten fissures; no water |
| Europa / icy moons | Frozen terrain with fractured ice material, ice props and subdued relief; no default liquid ocean |
| Titan | Recipe-selected liquid over a level datum; the visual liquid model is generic, not water chemistry |
| Sun / stars | Recipe-controlled photospheric granulation/plasma, no ground patches |
| Jupiter / Saturn / Uranus / Neptune | Animated cloud eddies over the existing planet maps, no solid terrain |

Example for a custom volcanic world:

```gdscript
var recipe = PlanetGenerator.recipe_for({
    "name": "Ashfall", "kind": "rocky",
    "surface": {
        "mountain_m": 600.0, "crater_count": 6,
        "volcano_count": 12, "volcano_m": 1800.0,
        "lava_amount": 1.0, "liquid_amount": 0.0,
        "rock_amount": 1.0, "ice_surface": 0.0,
    },
})
```

Additional controls: `crater_m`, `crater_field_m`, `wave_scale`, `granulation`
and `storm_strength`. Counts/amplitudes are bounded; star/gas recipes forcibly
disable solid features even if an override requests them. The planet seed fixes
landmark placement. Same-family landmarks do not overlap, and the combined
height bound includes each feature family.

Crater/cone/ridge heights feed `TerrainSampler.height_m`, so the ground mesh and
terrain contact test agree. Lava is a material mask carried in terrain UV2; waves
are animated shading over a level collision surface, not fluid simulation.
Kit rocks/ice/trees remain decorative and do not have individual colliders.

The new boulders and landmarks are procedural project geometry, **not scanned
assets or geographically surveyed volcano/crater locations**. Existing maps are
preserved; fine scenery remains synthetic. Terrain streaming and optimization
are deliberately unchanged in this pass.

`tools/test_surface_recipes.gd` covers recipe routing, caldera/crater geometry,
height bounds, contact, seeded repeatability and level procedural oceans.
For visual review, run under `xvfb-run` (plain `--headless` captures nothing — see
CLAUDE.md) with `TERRAIN_SHOTS` set to a comma-separated selection of all 19 values
(`tools/render_terrain.gd:32-53`): `moon_rocks, moon_crater, io_volcano, mars_volcano,
europa_ice, earth_mountains, earth_water, sun_plasma, jupiter_storms, earth_20km,
earth_7km, moon_20km, moon_7km, moon_200m, coast_12km, coast_6km, coast_2km,
himalaya_12km, himalaya_9km`.

### Original generator contract

- **Planet generator** is the cook. Same shader for Sun, planet, moon, invented exoplanet.
- **Recipe** is per-body data. Real map path when we have evidence. Kind, colors, heat when we do not.
- Sky is HYG points. Cook a ball only when the player is in that system.
- No unique mesh per world. A small **kit** (rock / ice / tree / lava) is for bird-eye props, not a GLB per planet.
- Sol maps stay in the albedo slot. Swap later for gridless USGS / NASA / ESA.

## Draw path (LOD)

| Where | What you see |
|---|---|
| Far (past the far plane) | Sky disc, real angular size, same recipe |
| **EZ** (exclusion) | Cook **mesh**. High bird-eye: curve, continents, weather, craters. Not a 36 km stamp. |
| Skin (below the body's own ceiling, ~35 km on solid worlds) | Local ground patch + kit props, Earth and Moon included. Still no landing. |

The mesh cut is the **near face**, not the centre. A star bigger than the far plane still becomes a ball when you close in.

EZ is the no-cruise bubble (Earth 100 km air, airless +10 km, star chromosphere). That is where bird-eye must read as a real world, not a sticker.

## The three visual bugs

Named so we do not “fix the wrong thing”:

1. **Pacman balls** — Voyager / incomplete mosaics paint unmapped limbs as **black void**. Wrapped on a sphere that is a bite taken out of the world. The cook fills near-black texels with invented crust of the recipe colors. Stars skip this (dark sunspots stay).
2. **Sheet text** — some albedo files still carry USGS grid / labels (Ganymede named). Same slot; swap the file, do not special-case the mesh.
3. **Black boxes** — 101 m tree placeholders were shaded boxes in a dark scene. Unshaded kit primitives until real props land. Missing GLB textures are the other source; craft keep models, worlds do not.

## Render log

Tape, Sol only:

```
Cook    31  · mesh 2  · sky 29
Look    Earth  mesh  ready-map  rocky
```

`Look` is the nearest body: draw path, recipe source, kind. Every cooked world has a recipe with name, kind, source, evidence.

## Scale

Far: one point. Arrive: one cook from the recipe. EZ: the same ball, close maps bind. Unique planet GLBs cannot reach a billion.

## Plane band — superseded

The plane-band design (drop to m/s near a solid world, rebuild one local height-tile
under the hull, kill it when you leave) was written as a future slice; it is now
built and described under "Current close-flight behaviour" above. Still true from
the original design: Google Earth 3D tiles are **not** used — height comes from
NASA/USGS maps where we have them, invented recipe-seed height otherwise. Only the
nearest body's tile exists at a time (tens of km, not a planet); far systems stay
HYG points.

## Skin band

The bird-eye ground tile (`scripts/world/surface_patch.gd`) is live on any physical
rocky/ice world, Earth and Moon included, pinned by `tools/test_surface_band.gd`.

**The ceiling is derived, not a magic number.** It used to be a plate-width ratio
(a fixed-size plate only reads as ground while its width dwarfs your altitude).
The rings' reach is horizon-following now (measured 163.8 km at ~1 km altitude,
`tools/test_earth_terrain.gd`), so that constraint no longer applies; the
ceiling's job is instead to open the band **above the tallest terrain** so you
don't enter it already inside a mountain: `band_ceiling_km = max(sampler.max_height_km
* 1.7, 35.0)` (`BAND_CEILING_MULT`, `BAND_CEILING_MIN_KM` in `planet_generator.gd`).
The only comment on `BAND_CEILING_MIN_KM` (`planet_generator.gd:596`): "bird's-eye
terrain remains active at 7–20 km". Rationale for 35 specifically: not recorded.

**`physical` is load-bearing.** An arcade system's units are 1u = 0.01 AU with radii boosted by `VISUAL_SCALE`, so its "altitude" of 0.1 is really a million kilometres. A ground plate must never pop up in deep space; `main._update_skin_kill` guards the kill line the same way.

**The tile's hills agree with the globe's crust.** `PlanetGenerator.crust_height()` is a line-for-line mirror of `planet_cook.gdshader`'s `sample_height()` fallback, `fbm(n * 6.0 + seed)`, run at the same seed. Touch one, touch both — otherwise the ground you fly over stops matching the crust painted overhead.

**Real DEMs (Mars, Moon, Earth) carry per-body calibration, not per-body branching.** Each mapped recipe (`planet_generator.gd`'s `RECIPES` table) states its own `height_encoding` (`"r8"` or `"rg16"`), `height_datum` (decoded 0..1 sample value at 0 m), `height_m_per_unit` (metres across the file's whole 0..1 span), `height_max` (highest sample the file can produce, an upper bound for `max_height_km()`), `height_signed` (true when a sample below datum is a real depth), and `height_texel_km` (map circumference / pixel width). `TerrainSampler` reads these off the recipe in `_init` and never branches on a body's name. As of 2026-09-09's 4k/8k re-wiring, all three mapped bodies carry real, signed, bathymetry-capable DEMs: Mars `mars_height_4k.png` (MOLA MEGDR 16 ppd, ~5.21 km/texel), Moon `moon_height_4k.png` (LOLA GDR 16 ppd, ~2.67 km/texel), Earth `earth_height_8k.png` (ETOPO 2022 60 arc-sec "surface" grid, ~4.89 km/texel, `height_signed: true` — the old unsigned/land-only `earth_height.jpg` is no longer referenced by any recipe). `docs/research/2026-09-09-dem-ingest.md` and `assets/planets/SOURCES.txt` have the sourcing and the raw min/max_m the fields above are derived from.

**Bathymetry is carried on the CPU, clamped only where the water mask says ocean — never a blanket sea-level floor.** Earth's `earth_height_8k.png` is signed (real seafloor depth down to the Kermadec-Tonga trench's -10708 m), but the visible ocean is still a level water plate at 0 m. `TerrainSampler.height_m()` (`scripts/world/terrain_sampler.gd`) applies `ground = maxf(ground, 0.0)` only when three things are ALL true: the recipe has a map (`_has_map`), the map is signed (`_dem_signed`, i.e. `height_signed: true`), and the existing water mask says this exact point is ocean (`is_water(dir)`, backed by `earth_spec_2k.png` + an elevation veto, not a new mask). Land below sea level that the mask does NOT classify as water (the Dead Sea, -427 m) is left alone and reports its real negative depth — the rule is "liquid_amount > 0 AND masked-as-water", never `if body_name == "Earth"`, and it falls out of fields the recipe already carries (`liquid_amount`, the existing `specular` mask) rather than a new one. `base_height_m()`/`raw_sample01()` (and therefore the CPU/GPU mirror check) still see the real unclamped depth — only the final `height_m()` used by the mesh/kill test/props clamps. **Mirror note, GPU side**: `planet_cook.gdshader`'s distant-globe vertex displacement (`disp = max(h - 0.08, 0.0) * land_v * detail * 2.6`) already multiplies by `land_v` (1 - the same water mask sampled per-vertex), so it zero-gates displacement at every masked-water texel regardless of `h`'s sign — no bathymetry already leaks into the far globe's geometry, and no shader edit was needed for THIS specific rule. **Closed as of 2026-09-09's cook2 pass**: `planet_cook.gdshader`'s close-detail colour block and its water-depth tint, plus the vertex-displacement floor, now read `height_datum`/`height_signed` (bound in `_cook_material` from the recipe, defaulting to 0.0/false) and test elevation as `h - height_datum` (or `height_datum - h` for depth) instead of a bare `h` against a fixed constant, while the water mask stays the sole authority for which pixels are ocean at all; `sample_height()`/`decode_height()` and `PlanetGenerator.crust_height()` (the mapless fbm mirror) needed no change.

**VRAM: the CPU sampler and the distant-globe material read different resolutions of the same Earth data on purpose.** `earth_height_8k.png` is 8192x4096 and, if bound as `height_tex` (`_cook_material`'s far-view `ShaderMaterial`), would import lossless and cost ~8192×4096×4 bytes = **128 MB** as an uncompressed RGBA8 GPU texture — too heavy for the low-end target for a texture the globe only samples at vertex/fragment resolution, never at native detail. `TerrainSampler` reads `"height"` (the 8k file) as raw CPU bytes only — no VRAM cost, full precision for the near-field ring mesh. The recipe carries a second, optional key, `height_globe` (`"res://assets/planets/earth_height_4k.png"`, defaulting to `"height"` if absent), a 4096x2048 BOX-downsample of the identical resampled array (not re-derived from the raw netCDF) for whichever code binds the far globe's `height_tex` to consume instead — **96 MB VRAM saving (128 MB → 32 MB)** once wired. **Consumed as of 2026-09-09's cook2 pass**: every GPU bind of `height` (`_cook_material`'s `_bind_tex`, and both the request/poll halves of `ensure_close_maps`'s threaded loader) now resolves through one helper, `PlanetGenerator.globe_height_path(recipe)` (`recipe.get("height_globe", recipe.get("height", ""))`), so Earth's far globe binds `earth_height_4k.png` (32 MB) instead of the 8k file (128 MB); `TerrainSampler`'s own `"height"` CPU read is untouched.

**RG16 is a byte-pack, not a 16-bit PNG format.** Godot 4.6.3 flattens a real single-channel 16-bit grayscale PNG to 8-bit on load (measured, `tools/probe_dem16.gd`), so the `_height_4k.png`/`_height_8k.png` files are ordinary RGB8 with `value = R*256 + G` (R=high byte, G=low byte, B unused), `compress/mode=0` ("Lossless") so the import path never VRAM-compresses them. Decoded to 0..1 as `(R*256+G)/65535` — GDScript's `TerrainSampler._texel()` and the shader's `planet_cook.gdshader` `decode_height()` (mirrored, touch one touch both) both do this on the DECODED value before the bilinear lerp runs, not on raw bytes, which matters only for the two-byte case (bilerp of R and G separately would not reconstruct `R*256+G`). `tools/test_dem_calibration.gd` is the acceptance gate: it reads known R/G byte pairs straight off the PNG (independent of Godot, via Python/PIL) and asserts they survive the real `res://` import path unchanged, then cross-checks the CPU decode against an independently-written GPU-formula replica for all three bodies.

**Procedural geology stays on below the DEM's texel, band-limited rather than zeroed.** A mapped body's real topography owns any wavelength at or above its own texel (a random procedural crater could otherwise land on top of Olympus Mons); `SurfaceRecipe.resolve()` only hard-zeroes mountains/hills/crater-octaves when a mapped recipe has no `height_texel_km` (Earth, unchanged). When one is present, mountain (~68 km ridge wavelength) and hills (10 km) amplitude is scaled by `_below_texel_weight` — a smoothstep from full strength well below the texel to zero at/above it, the same shape `_band_weight` already uses for mesh-resolution band-limiting, just measured against the DEM's texel instead of the local sample spacing — and each crater-field octave's own band weight is multiplied by the same function against its own `cell_km`. Named/seeded large craters (`crater_count`) are always suppressed on a mapped body regardless of texel, since those represent large discrete features the real DEM already draws.

**The kit is chosen by physics, not colour.** `PlanetGenerator.surface_kit()`: `tree` needs real air AND standing liquid (a biosphere), `ice` needs `ice_amount > 0.25`, everything else is bare `rock`, and a gas giant or star gets `none` — no surface to stand a plate on. Earth=tree, Moon=rock, Mars=rock, Europa=ice. Separate meshes, because recolouring a tree blue does not make it an ice spire.

The kit meshes are still **project-owned primitives**, not the CC0 pack in `docs/specs/2026-08-22-universal-planet-asset-kit-design.md` — that library is not acquired. Unshaded, per the black-boxes bug.

**Props cover the plate, not a corner of it.** Candidates are collected row-major and thinned at an even fractional stride; bailing out at `PROP_MAX` mid-walk dresses the first rows and leaves the rest bare. The test measures coverage along the plate's **own** east/north axes and asserts both, because a world-axis AABB cannot see this failure: a truncate keeps east at full width and only collapses north (9.8 × 7.1 of a 10 km plate, versus 9.8 × 9.8 when thinned).

Measured on the Moon (`tools/test_surface_band.gd`, `tools/test_earth_terrain.gd`): 33,466
tris across 4 rings, verts per ring [26112, 24762, 24762, 24762], quad size 0.040 /
0.160 / 0.640 / 2.560 km per ring, 220 of 563 candidate props placed, props covering
2.52 × 2.52 km of a 2.56 km plate.

**Height noise is band-limited by local sample spacing, not just calibrated for grade.**
`SurfacePatch._compute_ring` derives `detail_km` — a continuous function of a
vertex's distance from the hull (`dist_km / 16`), never of which ring is asking —
and threads it through `TerrainSampler.height_m`/`ground_radius_km` into
`TerrainSampler._detail_m`'s ridged octaves and `SurfaceRecipe.height_offset_m`'s
crater octaves and hills. Each octave's own wavelength (`cell_km`) is weighted by
`SurfaceRecipe._band_weight`: full strength once its cell spans 4+ samples at
`detail_km`, zero below 1.5. Ring quads jump 4x at every ring boundary, so an
unweighted fine octave (below Nyquist for the coarser ring, resolved fine for the
finer one) rendered as a genuinely different-looking texture on either side of the
boundary — reported as a straight full-width band at moon_7km. `detail_km == 0.0`
(the default for every caller except the ring builder — contact kill, props,
tests) means full detail everywhere, so nothing outside mesh-building changed.
Measured before/after at moon_7km (`tools/render_terrain.gd`): disabling
`TerrainSampler._detail_m` entirely removed the band outright, proving it (not
`SurfaceRecipe`'s crater octaves, which measured a clean, uniformly-distributed
`hash01` and a sub-1%-of-pixels visual delta when disabled) was the dominant
source. `tools/test_surface_band.gd`'s `_ring_boundary_height_agreement` pins
height equality at 21 shared rim points across all three ring boundaries.

**Generic detail roughness is turned down where named craters exist.** Measured
(`tools/probe_amplitude.gd`, not checked in): over a 3x3 km Moon patch,
`_detail_m`'s mean |offset| is 19.3 m — the same order of magnitude as the
geology pass's own craters (mean |offset| 21.2 m) — even though `_detail_m`'s
wavelength (411 m–3.6 km) is several times a small crater's diameter (45–90 m).
Two independent noise fields of comparable amplitude sum into whichever is least
structured winning visually: reported as "rolling hills, zero bowls" at
moon_200m even with real craters present in the height field (1562 counted by
`test_surface_recipes.gd`'s crater-encounter check). `TerrainSampler.DETAIL_GEOLOGY_DAMPEN`
(0.2) scales `_detail_m`'s amplitude down — never to zero, so there is still
roughness between craters — on any world with `crater_density > 0.0` (Earth and
Io, which have none, are unaffected).

## Exposure and horizon shadow (2026-09-09)

Two fixes for "the ring reads as dark mush at low sun" (measured: 15 deg sun
over the Moon, peak local-contrast std 0.035 linear). The ground pipeline is
`unshaded` by design (`shaders/terrain_tile.gdshader`'s own header comment) -
Godot shadow maps are not the plan; both fixes stay inside the existing
per-vertex/per-fragment lighting model.

**Exposure** is a flat per-body albedo gain, `apply_exposure()` in
`shaders/planet_color.gdshaderinc`, folded into `land_tint_color()` (both
`planet_cook.gdshader` and `terrain_tile.gdshader` already call this for every
`KIND_ROCKY` body, so the gain flows to both automatically) and into
`ocean_base_color()` (only `terrain_tile.gdshader` calls this one - see the
gap below). `SurfaceRecipe.resolve()` computes a colour-only default (target
0.35 linear against the recipe's `color_a` luminance, capped at 3.5x,
solid bodies only - star/gas stay at 1.0), honouring `recipe.exposure` or
`recipe.surface.exposure` as an explicit override; `SurfacePatch.bind_recipe`
then REFINES that default once a real `TerrainSampler` exists, by sampling
the actual mean of the same `land_color()` every ring vertex paints with (a
36-point sphere sample), which is what actually gets bound to `_land_mat`/
`_water_mat`/`_prop_mat`'s `exposure` uniform.

Live-measured (not the "12% albedo" guess this slice started from):
`moon_2k.jpg`'s own mean linear luminance is ~0.32, and `land_color()`'s real
sampled mean for Earth/Moon/Mars/Mercury/Venus all land in ~0.22-0.33 -
giving MODEST gains (~1.05-1.6x), not 2.5-3x. `tools/test_horizon_shadow.gd`
asserts the general contract (bounded 1.0-3.5, solid-only, override honoured)
against this measured range rather than an assumed number.

**Known gap**: `planet_cook.gdshader`'s own material build
(`PlanetGenerator._cook_material`, scripts/world/planet_generator.gd:995) never
sets an `exposure` shader parameter, so the globe currently runs the
include's neutral default (1.0) regardless of body - only the ring gets the
real per-body gain. Wiring it up needs one line in `_cook_material`:
`mat.set_shader_parameter("exposure", float(surface.get("exposure", 1.0)))`
(`surface` is already `SurfaceRecipe.resolve(recipe)` at that point). Also:
`planet_cook.gdshader`'s ocean blend (line ~252, `vec3 ocean_col = mix(alb,
color_ocean, ocean_ratio);`) computes the ocean colour inline instead of
calling the include's `ocean_base_color()`, so a ring's ocean gets exposure
gain the globe's ocean does not - same one-line fix, call `ocean_base_color`
there instead.

**Horizon shadow** is a per-vertex cast shadow, computed in
`SurfacePatch._compute_ring` (the worker-thread ring builder) rather than a
Godot shadow map. For each grid vertex (rings 0-2 only - ring 3 is far enough
that marching it would pay for precision nobody is close enough to see) it
marches `HORIZON_STEPS` (8) samples toward the sun along the surface,
geometric growth `HORIZON_STEP_GROWTH` (1.7x) from a FIXED first step (the
same `normal_step` the analytic-normal fix already uses, not the calling
ring's own quad size - using the per-ring quad reopened the exact
ring-boundary discontinuity that fix was for, and had to be caught by a
dedicated boundary-agreement test). Each sample re-uses the SAME
`TerrainSampler.ground_radius_km()` every mesh vertex and the contact kill
already read - never a second height source. The classic self-shadow test:
the tallest rise-over-run angle among the samples vs. the sun's own elevation
above the local horizontal, soft-edged over `HORIZON_MARGIN_DEG` (1.5 deg).
The result is stored in vertex `UV2.y` (`UV2.x` already carried the lava
mask; `UV2.y` was unused) and multiplies ONLY the direct-light term in
`terrain_tile.gdshader`'s `lit` calculation - the ambient floor (0.18) and
the night side (`night_fill`) are untouched, so a fully shadowed crater still
reads as ground, never a hole into space. Measured cost (Moon, 300 m
altitude - the finest ring scale, i.e. the reference frame's own altitude):
a four-ring rebuild went from 1.30 s to 2.46 s (1.89x), under the 2x budget.

## Not this slice

Landing. 50 unique planet models. Volumetric air. Gridless mosaic downloads. Rich tree kits. Google Earth tiles.
