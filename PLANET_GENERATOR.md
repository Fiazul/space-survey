# Planet cook

One system paints every world. Catalog row → true position → **recipe** → ball.
You do not land. A billion stars stay sky points until you are there.

## Current close-flight behaviour (2026-09-07)

- Solid planets use local terrain below a per-body ceiling, floored at 35 km above ground
  (see "Skin band" below for the derivation). Measured terrain max: Earth 9.49 km, Moon
  1.97 km (`tools/test_earth_terrain.gd`), both well under the 35 km floor.
- Patch coordinates, terrain queries and impact checks use the body's own rotating frame. The Moon is not anchored at Earth's centre.
- Ring half-width covers the horizon with a projection margin. All rings recenter together to keep their stitched boundaries aligned. The coarse globe is hidden only while the complete local terrain replaces it.
- The altitude tape reads **AGL**, with metres below 1 km; height above the reference sphere is not clearance above a mountain.
- Contact starts hull-loss/respawn, not landing. Earth's substep clamp latches impacts before floating-point projection can hide them; other bodies use a body-local swept contact test.
- Terrain retains mapped geography, adds slope lighting and procedural substrate, and seats smaller kit props on the ground. Airless worlds do not inherit grass or ocean water.

Limits: Earth maps are still kilometre-resolution, with procedural finer relief, not satellite-detail scenery. Moon heights are procedural, not a lunar DEM. Synchronous ring rebuilds keep seams coherent but may hitch; asynchronous terrain streaming remains future work. This is not general ship-to-object rigid-body collision.

Checks: `tools/test_surface_integration.tscn` exercises live Moon placement and Earth/Moon death entry; `test_earth_terrain.gd`, `test_surface_band.gd`, `test_terrain_light.gd`, and `test_skin_kill.gd` cover geometry, coverage, materials and contact. `tools/render_terrain.tscn` captures Earth/Moon bird's-eye and low-altitude views.

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

**The kit is chosen by physics, not colour.** `PlanetGenerator.surface_kit()`: `tree` needs real air AND standing liquid (a biosphere), `ice` needs `ice_amount > 0.25`, everything else is bare `rock`, and a gas giant or star gets `none` — no surface to stand a plate on. Earth=tree, Moon=rock, Mars=rock, Europa=ice. Separate meshes, because recolouring a tree blue does not make it an ice spire.

The kit meshes are still **project-owned primitives**, not the CC0 pack in `docs/specs/2026-08-22-universal-planet-asset-kit-design.md` — that library is not acquired. Unshaded, per the black-boxes bug.

**Props cover the plate, not a corner of it.** Candidates are collected row-major and thinned at an even fractional stride; bailing out at `PROP_MAX` mid-walk dresses the first rows and leaves the rest bare. The test measures coverage along the plate's **own** east/north axes and asserts both, because a world-axis AABB cannot see this failure: a truncate keeps east at full width and only collapses north (9.8 × 7.1 of a 10 km plate, versus 9.8 × 9.8 when thinned).

Measured on the Moon (`tools/test_surface_band.gd`, `tools/test_earth_terrain.gd`): 33,466
tris across 4 rings, verts per ring [26112, 24762, 24762, 24762], quad size 0.040 /
0.160 / 0.640 / 2.560 km per ring, 220 of 563 candidate props placed, props covering
2.52 × 2.52 km of a 2.56 km plate.

## Not this slice

Landing. 50 unique planet models. Volumetric air. Gridless mosaic downloads. Rich tree kits. Google Earth tiles.
