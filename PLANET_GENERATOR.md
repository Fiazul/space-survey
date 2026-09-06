# Planet cook

One system paints every world. Catalog row → true position → **recipe** → ball.
You do not land. A billion stars stay sky points until you are there.

## Contract

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
| Skin (last few km; Earth dies at 29 km) | Local ground patch + kit props on airless worlds. Still no landing. |

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

## Plane band (later — possible, not this slice)

**Yes.** A Google-Earth-*feel* from a plane is possible on every planet, moon, and (with a different kit) a star’s skin — without Google, without a mesh per world, without killing the frame rate.

Google Earth 3D tiles are **not** allowed. We do not stream their photogrammetry. The cook already has the legal path: NASA / USGS height where we have it, invented height from the recipe seed where we do not.

### What it is

You drop at EZ. Speed is forced down (safety). Inside the air / the last tens of km you fly at **m/s**, like a plane. The cook globe stays the horizon. Under the hull, one **local tile** rebuilds: hills from height, water from the mask, low-poly kit (rock, ice, tree, lava). Leave the band, the tile dies. You still do not land.

Same system for every body. Recipe picks the kit. Earth: real DEM + water. Mars: rock + ice caps. Europa: ice. Titan: haze + methane lakes as a paint. Invented exoplanet: fbm from seed. Stars: no air, no trees — only if we ever want a chromosphere kit.

### Why it does not hurt performance

- Only the **nearest** body, only while you are in its EZ / air.
- One tile (tens of km, not a planet). Rebuild when you move a few km, not every frame.
- Low-poly kit instances (hundreds, not millions). No unique GLB per world.
- Far systems stay HYG points. A billion worlds never all exist as mesh.
- “Prerender” here means **bake the tile on entry** (height mesh + prop list), then draw it cheap. Not a video, not a planet-sized cache.

### Speed

Cruise dies at EZ (already). Then a **safety cap** so you cannot F9 through the tile: EZ dump to local, air / last-km band in m/s. Sol already has unused approach speed-zones; they stay off until this band is real. Fat engines stay a debug key, not the plane pass.

### Honest limits

- Earth kill is **29 km**. A true plane pass wants ~0.5–8 km. That kill line has to move, or Earth never sees hills as objects. Airless worlds already allow 100 m, so they get the band first.
- This is a **survey flyover**, not a landing game. Skin still kills if you go below the floor.
- It will look like a low-poly aerial, not photogrammetry. That is the point: readable water and relief at m/s, 60 fps on a potato.

### Do not build yet

Keep EZ as the cook globe (the 36 km black stamp at 100 km was the wrong layer). The plane-band **safety speed cap** is still the next slice after the globe reads at EZ. The **tile + kit** half of it is now in — see below.

## Skin band (in, airless worlds first)

The bird-eye ground tile is real and reachable. `scripts/world/surface_patch.gd`, pinned by `tools/test_surface_band.gd`.

**It had never rendered.** `should_show()` let only Earth through, and `ground_stamp_ok()` asked for `alt > kill and alt < 3.0` with Earth's kill at 29 km — a window that is empty at every altitude. So `_rebuild`, the prop MultiMesh and the height sampling were dead code, and no test noticed, because every assertion was about the numbers in the window rather than about whether the window contained anything. The first thing the new test asserts is that a band is **non-empty**.

| | Then | Now |
|---|---|---|
| Bodies | Earth only (and Earth could never qualify) | any physical rocky/ice world |
| Ceiling | hardcoded 3 km | `TILE_KM_MAX * BAND_ALT_FRACTION` = 3.24 km |
| Plate | fixed 36 km | `tile_km_for(alt)` = alt × 10, clamped 2–36 km |
| Height | `earth_height.jpg`, always | recipe height map, else the shader's own crust fbm |
| Water | `earth_spec_2k.png`, always | recipe mask, else the albedo trick, else the `land_amount` cut |
| Props | trees, always | recipe kit: tree / rock / ice |

**The ceiling is not a magic number.** A local plate only reads while its width dwarfs your altitude — 36 km of ground from 100 km up is the sticker-on-a-globe bug; the same plate from 1 km up is ground to the horizon. So the ceiling is derived from the plate's own size, and the plate is derived from altitude, which keeps quad size proportional on the way down (48 × 48 quads: 208 m at 1 km alt, 42 m at 200 m alt).

**Earth's band is still empty, on purpose.** Kill 29 km sits well above the 3.24 km ceiling. That is the honest limit above, now asserted (`earth_band_still_empty_until_the_kill_line_moves`) so whoever moves that kill line is told exactly what they changed. Airless worlds kill at 100 m, so their band is **0.1 → 3.24 km** and they fly it first. Measured: 0.11–3.23 km.

**`physical` is load-bearing.** An arcade system's units are 1u = 0.01 AU with radii boosted by `VISUAL_SCALE`, so its "altitude" of 0.1 is really a million kilometres. Removing Earth's name filter without adding the truth flag would pop a ground plate in deep space. `main._update_skin_kill` guards the kill line the same way.

**The tile's hills agree with the globe's crust.** `PlanetGenerator.crust_height()` is a line-for-line mirror of `planet_cook.gdshader`'s `sample_height()` fallback, `fbm(n * 6.0 + seed)`, run at the same seed. Touch one, touch both — otherwise the ground you fly over stops matching the crust painted overhead.

**The kit is chosen by physics, not colour.** `PlanetGenerator.surface_kit()`: `tree` needs real air AND standing liquid (a biosphere), `ice` needs `ice_amount > 0.25`, everything else is bare `rock`, and a gas giant or star gets `none` — no surface to stand a plate on. Earth=tree, Moon=rock, Mars=rock, Europa=ice. Separate meshes, because recolouring a tree blue does not make it an ice spire.

The kit meshes are still **project-owned primitives**, not the CC0 pack in `docs/specs/2026-08-22-universal-planet-asset-kit-design.md` — that library is not acquired. Unshaded, per the black-boxes bug.

**Props cover the plate, not a corner of it.** Candidates are collected row-major and thinned at an even fractional stride; bailing out at `PROP_MAX` mid-walk dresses the first rows and leaves the rest bare. The test measures coverage along the plate's **own** east/north axes and asserts both, because a world-axis AABB cannot see this failure: a truncate keeps east at full width and only collapses north (9.8 × 7.1 of a 10 km plate, versus 9.8 × 9.8 when thinned).

Measured on the Moon at 1 km: 13,824 ground verts (a full 48×48 plate), 0 water, 220 of 312 candidate props, plate 10 km, geometry on the 1732–1745 km shell.

## Not this slice

Landing. 50 unique planet models. Volumetric air. Gridless mosaic downloads. Rich tree kits. Google Earth tiles. Plane-band tile (see above).
