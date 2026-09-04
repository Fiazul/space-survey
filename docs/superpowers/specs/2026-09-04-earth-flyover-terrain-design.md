# Earth flyover: terrain and contact kill

Slice **A** of four. Earth gets flyable relief from above Everest down to the
ground, and you die by hitting terrain rather than by crossing an altitude.

This is the foundation the other three sit on, and only this one is designed
here:

| | Slice | Blocked on |
|---|---|---|
| **A** | **Terrain geometry + contact kill** — this document | — |
| B | Named features: Everest, top peaks, volcanoes at real lat/lon | A |
| C | Water: real ocean surface, shoreline, waves | A |
| D | Surface objects: kit dressing readable at 200 m | A |

## Problem

Three separate things block flying over Earth.

**The band is shut.** `PlanetGenerator.ground_stamp_ok()` opens the ground tile
between the kill line and a 3.24 km ceiling. Earth's kill line is 29 km. The
window is empty at every altitude, so Earth has no ground tile at all.

**The kill is a bubble, not a surface.** `Ephemeris.surface_kill_km("Earth")`
returns a constant 29 km derived from `EARTH_MIN_R_KM = 6400`. You die at a
fixed radius from the centre regardless of what is under you — the Pacific and
the summit of Everest kill at the same altitude.

**Nothing bounds speed near the ground.** `speed_zones` is `false` in the Sol
slice and `MAX_SPEED` is 10,000 (1u = 1 km, so 10,000 km/s). At 60 fps that is
166 km per frame. Any contact test would be sampling a hull that teleports past
whole mountain ranges between frames.

And one hard limit on what the data can give us: `earth_height.jpg` is
5400x2700, which is **7.42 km per pixel** at the equator, 8-bit. Everest's
summit pyramid is about 3 km across — less than half a pixel. The DEM can give
a smoothed Himalayan swell and nothing that reads as a mountain. Named peaks are
slice B's job; slice A only has to make the swell flyable and give B somewhere to
put a peak.

## Goal

From 15 km down to contact, over Earth: relief you can fly through, terrain that
reaches the horizon, and a crash when you hit it. Still no landing — contact is
a crash, and the skin kill keeps its existing cutscene and respawn.

## Design

### A1. One height function, two consumers

The correctness core. Mesh geometry and the kill test must never disagree, or you
die in clear air or fly through rock. So there is exactly one implementation,
behind one object:

```gdscript
PlanetGenerator.terrain_sampler(recipe) -> TerrainSampler
```

`TerrainSampler` is a `RefCounted` that owns the recipe's bound height image and
scalar parameters, and exposes:

```gdscript
height_m(dir: Vector3) -> float             # metres above sea level
ground_radius_km(dir, body_radius_km) -> float
alt_above_ground_km(pos, body_radius_km) -> float
is_water(dir) -> bool
max_height_km() -> float                    # for the band ceiling
```

One instance per body, created on arrival, owned by `PlanetSystem` (which
already knows the nearest body and its recipe). The ring mesh builder and
`main._update_skin_kill` both hold that same reference. A test asserts committed
mesh vertices equal `ground_radius_km()` at the same directions.

Height composes as:

- **Bilinear** DEM sample. Nearest-neighbour is what makes 7.42 km pixels read as
  blocks, and bilinear also smooths most of the 8-bit terracing (~35 m steps at
  Everest scale).
- **Procedural detail added on top**, amplitude scaled by the DEM's local slope.
  This is what makes 50 m triangles worth building: flat sea floor stays flat,
  the Himalaya gets rugged. Uses the existing `PlanetGenerator.fbm3`, which is
  already the shader's own noise, so the tile and the globe agree.
- Airless worlds fall through to the existing `crust_height()` fbm and inherit
  everything above for free.

**The DEM's encoding is unknown and must be measured first.** We do not know
what `r = 0.0` and `r = 1.0` mean in this file, whether sea level sits at 0.0 or
at some midpoint, or whether ocean bathymetry is encoded below it. Every number
downstream depends on that mapping, so establishing it is task 1 and it is a
probe, not an assumption.

### A2. Four nested rings

Replaces the single plate. Concentric, each ring's quad 4x the one inside it:

| Ring | Quad | Reach | Rebuild trigger |
|---|---|---|---|
| 0 | 50 m | 3.2 km | hull moves 50 m |
| 1 | 200 m | 12.8 km | hull moves 200 m |
| 2 | 800 m | 51 km | hull moves 800 m |
| 3 | 3.2 km | 205 km | hull moves 3.2 km |

64x64 quads each; rings 1-3 are built as **donuts** with the inner ring's
footprint removed, so nothing overdraws. 32,768 triangles total, constant at
every altitude — ring 0 rebuilds constantly and is cheap, ring 3 almost never.

Ring seams get **vertical skirts**: each ring's outer edge drops straight down
by one quad of its own size. Adjacent rings sample the same height function at
different rates, so their edges do not meet exactly; a skirt hides the gap and
is invisible from above.

Rings inherit the existing floating-origin handling (`_surface.position =
-ship_pos`).

**Props stay on ring 0 only** in this slice, keeping the existing even-thinning
placement. Slice D revisits density and per-ring dressing.

### A3. The band opens, and the 29 km contract dies

**The ceiling rule changes, and the old reason for it is gone.** The 3.24 km
ceiling existed because a single local plate only reads as ground while its width
dwarfs your altitude — a 36 km plate seen from 100 km up is a sticker on a globe.
Rings reach 205 km, so that constraint no longer applies. The ceiling's job is
now the opposite one: **the band must open above the tallest terrain**, or you
enter it already inside a mountain.

```
ceiling_km = max(sampler.max_height_km() * 1.7, MIN_CEILING_KM)   # MIN = 3.0
```

Earth: 8.85 x 1.7 = **15.0 km**.

A world with no DEM needs an elevation scale before `max_height_km()` means
anything. It keeps the existing `3.2` lift constant already in
`surface_patch._vert`, and `fbm3` is bounded at 0.97, so a noise world's max is
~3.0 km and its ceiling ~5.2 km. That is a change from the 3.24 km the airless
band shipped with last slice — larger, and correct for the same reason Earth's
is: the band must open above the terrain, not above a plate-width ratio.
`MIN_CEILING_KM = 3.0` is only a floor for a world flat enough that 1.7x its
relief would open the band underground.

This supersedes the plate-derived ceiling from the previous slice.

Kill becomes position-dependent:

```
alt = |pos| - (body_radius_km + height_m(dir) / 1000)
dead if alt <= CONTACT_KM
```

`CONTACT_KM` comes from the ship model's actual bounding radius, measured from
the AABB rather than guessed, with a 0.02 km floor so a small hull still gets a
contact margin bigger than one ring-0 quad's worth of height error.

**This deletes a pinned contract**, deliberately and on the record:

- `Ephemeris.EARTH_MIN_R_KM` and the scalar `surface_kill_km("Earth") == 29.0`
- four assertions in `tools/test_skin_kill.gd`: `earth_kill_29km`,
  `earth_uses_29km`, `29km_dies_earth`, `30km_lives_earth`
- `Ephemeris.sweet_spot()`, which parks a respawn at `kill * 4`
- `earth_band_still_empty_until_the_kill_line_moves` in
  `tools/test_surface_band.gd` — written one slice ago precisely so that moving
  this line would announce itself

The airless 100 m floor stays as a floor: contact kill applies everywhere, and
`SURFACE_KILL_FLOOR_KM` becomes the minimum contact distance rather than an
altitude bubble.

**The kill test sweeps the movement segment**, not the frame's endpoint. It
samples along last-frame-position to this-frame-position at a count derived from
the distance and ring 0's quad size, capped. A point test plus one frame-rate dip
equals flying through a mountainside.

### A4. Speed cap, with an anti-tunnelling proof

```gdscript
FlightMode.band_speed_cap(alt_above_ground_km) -> float   # m/s
```

Interpolated over anchors: 100 km -> 2000, 15 km -> 600, 5 km -> 300,
1 km -> 150, 0.2 km -> 60, and 60 below that. Dressed in the HUD as an
atmospheric flight limit so it reads in-world rather than as an invisible wall.

Applied through the existing `PlanetSystem.speed_limit` channel that the ship
already reads, but **independent of the `speed_zones` flag** — the cap is a
correctness requirement of contact kill, not part of the deferred approach-zone
pass.

The test is not "the numbers are these". It is the guarantee:

```
for every altitude in the band:
    band_speed_cap(alt) * WORST_FRAME_TIME < ring_0_quad_size
```

At 60 fps the anchors above hold with margin everywhere (the tightest point is
2000 m/s -> 33 m against a 50 m quad). At 20 fps they do not, which is the second
reason the kill test sweeps rather than samples a point.

### A5. Surface colour, because the map runs out before the geometry does

Measured on the shipped tile: at 1 km altitude a 10 km plate covers **1.9
texels** of the Moon's 2048px albedo, 0.96 on Mars, and **0.51 on Earth**. Half
a pixel. The ground is one flat colour and no triangle count changes that. This
is the "blurry surface" seen in the first GPU look, and it is a data limit, not
a mesh limit.

`planet_cook.gdshader` already handles it for the globe: past `detail > 0.02` it
blends a procedural grass / rock / dirt / ice palette driven by height and
slope. **The tile bypasses that entirely** — `surface_patch._color_at()` samples
the albedo image and stops. So today the tile is blurrier than the globe at the
same altitude, which is backwards, and at the tile's outer edge the two disagree
visibly.

Same rule as A1, applied to colour: one palette, two consumers.

```gdscript
TerrainSampler.surface_color(dir, height_m, slope) -> Color
```

It reproduces the shader's close-up palette and blends over the map colour by
**how far the map has run out**, which is a measurable quantity rather than a
taste knob:

```
texels_across = plate_km / km_per_texel
map_weight    = clamp(texels_across / MAP_FADE_TEXELS, 0, 1)    # MAP_FADE = 4
```

Above four texels the map still carries real information and leads; below it the
map degrades to a broad tint and the procedural palette carries the detail. The
map is never fully discarded — it keeps Mare Imbrium dark and the Sahara pale,
which is the evidence the recipe exists to preserve.

Verification: `tile_colour_matches_the_globe_palette` — the tile's colour at a
direction equals the shader's palette inputs at that same direction within
tolerance, so the seam does not show a step. And
`map_leads_when_it_has_detail` / `noise_leads_when_it_does_not`, pinned at the
measured texel counts above.

## Files

| File | Change |
|---|---|
| `scripts/world/terrain_sampler.gd` | new — `TerrainSampler` |
| `scripts/world/planet_generator.gd` | `terrain_sampler()`, ceiling from max height, retire the plate-derived ceiling |
| `scripts/world/surface_patch.gd` | single plate -> four rings, skirts, sampler-driven vertices and colour |
| `scripts/world/planet_system.gd` | own the sampler, expose it, feed the band cap into `speed_limit` |
| `scripts/flight/flight_mode.gd` | `band_speed_cap()` |
| `scripts/core/main.gd` | `_update_skin_kill` -> swept contact test against the sampler |
| `scripts/autoload/ephemeris.gd` | retire `EARTH_MIN_R_KM`; `sweet_spot()` off contact distance |
| `tools/probe_earth_dem.gd` | new — establish the DEM's encoding (task 1) |
| `tools/test_earth_terrain.gd` | new — this spec's contract |
| `tools/test_skin_kill.gd` | four assertions rewritten for contact kill |
| `tools/test_surface_band.gd` | see below — rings retire the plate, and much of this file with it |

Rings replace the single plate, so `tile_km_for()`, `TILE_KM_MAX`,
`TILE_KM_MIN`, `BAND_ALT_FRACTION` and `TILE_ALT_MULT` all retire. That takes
nine assertions in `tools/test_surface_band.gd` with them —
`plate_grows_with_altitude`, `plate_never_below_min`, `plate_never_above_max`,
`plate_always_dwarfs_the_altitude`, `tile_plate_scales_to_the_altitude`,
`plate_sits_on_the_moons_shell`, `plate_is_local_not_global`,
`standing_still_keeps_the_same_plate`, and
`earth_band_still_empty_until_the_kill_line_moves`. Each is either restated
against a ring (`ring_0_sits_on_the_moons_shell`) or deleted as describing a
mechanism that no longer exists. The parts of that file worth keeping outright
are the recipe-source assertions (`moon_does_not_borrow_earths_height` and
friends), the kit gates, and the crust-mirror checks — none of those depend on
the plate.

`props_cover_the_whole_plate` becomes `props_cover_ring_0`; the even-thinning
behaviour it guards is unchanged.

## Verification

Headless, and this is a stated limitation rather than a preference: everything
here renders on llvmpipe software Vulkan in this environment. Geometry,
agreement, seams and bounds are provable. Whether it looks good is not.

`tools/test_earth_terrain.gd`:

- `mesh_matches_the_height_function` — committed vertex radii equal
  `ground_radius_km()` at the same directions. The one that stops you dying in
  clear air.
- `dem_encoding_matches_the_probe` — the calibration task 1 measured, pinned, so
  a re-fetched map with different encoding fails loudly instead of flattening
  the planet.
- `everest_is_the_high_point_of_the_himalaya` — the height at 27.99N 86.93E is
  the maximum over that region. Catches a flipped V or a 180-degree longitude
  offset, which would otherwise put the world's mountains in the ocean and go
  unnoticed.
- `sea_level_is_flat_over_open_ocean`
- `rings_have_no_gaps` — each ring's inner edge plus skirt covers the next ring's
  outer edge.
- `ring_budget_is_constant` — triangle count does not grow with altitude.
- `cap_prevents_tunnelling` — the A4 guarantee, swept over the whole band.
- `contact_kill_fires_on_terrain_not_in_air` — at Everest's lat/lon, 9 km is dead
  and 12 km is alive; over open Pacific, 1 km is alive and 0 km is dead.
- `earth_band_is_no_longer_empty` — the inverse of the assertion this slice
  retires, so the change is asserted rather than silent.
- `swept_kill_catches_a_frame_long_jump` — a single-frame displacement across a
  mountain is caught, where a point test at both ends would miss it.

Each assertion gets mutation-tested: it must be shown to fail when the thing it
describes is broken.

## Judgment calls

**No vertical exaggeration.** Real 8.848 km on a real 6371 km sphere. From the
15 km ceiling Everest is a bump; it reads as a mountain only from a few km out.
Games routinely exaggerate 2-3x. Kept real because this project is physical-scale
everywhere else — the flag is that the first look from the ceiling may
disappoint, and an exaggeration multiplier would be a one-line change in the
sampler if wanted.

**Ceiling derived, not authored.** `max_height * 1.7` rather than a per-body
constant, so a world with no map and a world with a DEM both get a correct
ceiling without a table entry.

## Out of scope

Named peaks and volcanoes (B). Water look, shorelines, waves (C) — this slice
only flattens sub-sea-level quads to sea level. Kit dressing and prop density
(D). Landing, or any contact that is survivable. Atmospheric drag. Collision
shapes / physics bodies — the contact test is analytic against the height
function, not a Godot collider. Higher-resolution DEMs. Airless-world retuning
beyond inheriting the new ceiling rule.
