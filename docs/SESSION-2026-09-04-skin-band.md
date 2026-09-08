# Astryx — skin band: the bird-eye ground tile (2026-09-04)

The planet generator's bird-view terrain. `surface_patch.gd` rewritten to be
recipe-driven and body-agnostic, `planet_generator.gd` given the band + kit + crust
contract, `tools/test_surface_band.gd` new. Airless worlds fly the band first.

## The tile was unreachable code

Not "looked wrong" — it could not run. Two gates, each reasonable alone:

```gdscript
should_show():     if body != "Earth": return false
ground_stamp_ok(): return alt_km > kill_km and alt_km < 3.0    # Earth kill = 29
```

`alt > 29 and alt < 3` is empty at every altitude. So `_rebuild`, the prop
MultiMesh and the height sampling had **never rendered once** in the project's
history. The previous commit (`8933730 hide 36 km ground stamp at Earth EZ`) fixed
a genuine bug — a 36 km plate showing at 100 km — by clamping the window shut on
the only body allowed through it.

Every existing assertion was about numbers *inside* the window
(`no_stamp_at_earth_ez`, `no_stamp_in_air`) and none about whether the window
contained anything, so the suite stayed green over dead code. **The new test's
first assertion is that a band is non-empty**, and Earth's emptiness is asserted
explicitly so it reads as a decision instead of an accident.

## The ceiling is derived, not chosen

A local plate reads as ground only while its width dwarfs your altitude. 36 km
seen from 100 km up is the sticker-on-a-globe bug; the same plate from 1 km up is
ground to the horizon. So:

```
ceiling   = TILE_KM_MAX * BAND_ALT_FRACTION = 36 * 0.09 = 3.24 km
plate(alt) = clamp(alt * 10, 2, 36) km
```

The plate scaling is what keeps the quads honest on the way down — 48x48 quads is
208 m each at 1 km altitude, 42 m at 200 m. The old fixed 36 km plate was 750 m
quads at any height.

## Airless first, and Earth is still shut

| World | Kill | Band |
|---|---|---|
| Airless (Moon, Mercury, most moons) | 0.1 km | **0.11 - 3.23 km** (measured) |
| Mars | 0.1 km | same |
| Earth | 29 km | **empty** — kill is above the ceiling |

Earth needs its 29 km kill line moved before it sees hills as objects. That is the
"Honest limits" call in `PLANET_GENERATOR.md`, and it is now a named assertion
(`earth_band_still_empty_until_the_kill_line_moves`) so whoever moves that line is
told what else changed.

## `physical` is load-bearing, not a tidy-up

Deleting the `body != "Earth"` filter without adding the truth flag would pop a
ground plate in deep space. An arcade system runs 1u = 0.01 AU with radii boosted
by `VISUAL_SCALE`, so `nearest_dist - nearest_radius` = 0.1 there is really a
million kilometres. `main._update_skin_kill` already guards the kill line this way
(`planets.is_physical(...)`); `SurfacePatch.should_show` now takes the same flag.

## The tile's hills must agree with the globe's crust

`PlanetGenerator.crust_height()` / `fbm3` / `_noise3` / `_hash3` are a
line-for-line mirror of `planet_cook.gdshader`'s `hash`/`noise`/`fbm`, and the
tile runs them at the **same seed the material got**. Touch one, touch both —
otherwise the ground you fly over stops matching the crust painted overhead.
`_water_at` mirrors the shader's `sample_water()` fallback chain the same way
(spec mask -> blue-over-red on the albedo -> the `land_amount` cut on fbm).

The tile also never reaches for a map by name any more. It used to `load()`
`earth_height.jpg` and `earth_spec_2k.png` unconditionally, which would have
painted Earth's continents onto lunar regolith the moment another body was let
through — the same class of bug as the 36 km sticker.

## The kit is picked by physics

`PlanetGenerator.surface_kit(recipe)`:

| Kit | Gate | Gets |
|---|---|---|
| `tree` | `air_amount > 0.5` AND `water_shine > 0.3` | Earth |
| `ice` | `ice_amount > 0.25` | Europa, icy moons |
| `rock` | anything else with a surface | Moon, Mars, invented rocky |
| `none` | gas giant, star | no plate at all |

Three separate meshes, not one recoloured. A blue tree is not an ice spire, and
`docs/specs/2026-08-22-universal-planet-asset-kit-design.md` is explicit that
colour alone must never turn a hot phenomenon into a cold one. They are still
project-owned primitives (unshaded — the black-boxes bug): the CC0 pack in that
spec is **not acquired**, and acquiring it needs downloads plus a license ledger.

## Props cover the plate, and the first assertion for that was too weak

The candidate walk is row-major, so `if prop_xforms.size() < PROP_MAX` filled the
first rows and left the rest of the ground bare — 220/220 props in one corner.
Fixed by collecting uncapped and thinning at an even fractional stride, so the cap
costs density and never coverage.

**The coverage assertion had to be rewritten to catch it.** The first version took
the largest axis of the props' world-space AABB, and the mutation (truncate
instead of thin) *passed*: truncation keeps the **east** span at full width and
only collapses **north**, so the largest axis still looks fine. The assertion now
measures coverage along the plate's own east/north basis and checks **both**:

```
thinned:   cover 9.8 x 9.8 of a 10.0 km plate   OK
truncated: cover 9.8 x 7.1                      FAIL props_cover_the_whole_plate
```

Props also grow with `sqrt(plate_width)` — 12-40 m at the bottom of the band,
50-170 m at the top. That is a readability cheat and the only one in the file; a
real 20 m boulder is one pixel from 3 km up.

## Verified

`tools/test_surface_band.gd`, 5 sections, run as `--script` (the patch holds no
autoload reference on purpose, so it does not need a `.tscn` wrapper like
`test_chase_rig`).

Measured on the Moon at 1 km altitude: 13,824 ground verts (a full 48x48 plate),
0 water verts (airless -> every quad routes to land), 220 of 312 candidate props,
plate 10 km, geometry sitting on the 1732-1745 km shell.

Five mutations, all caught: truncate-instead-of-thin, allow non-physical systems,
drop the biosphere gate, bind Earth's height everywhere, reopen the band at EZ.

Suite: `planet_generator`, `sol_cook`, `sol_truth`, `sol_occlude`, `sol_sun_lod`,
`skin_kill`, `flight_mode`, `newton`, `surface_band` all OK. Boot clean. The two
standing FAILs are last session's knob guards (`booster_brightness = 20.0`), and
`test_wh_network` times out at 200 s — pre-existing, it has no preloads and zero
planet references.

## Still open here

- **The ship mesh looks yaw-rotated, roughly 30 degrees to the right.** Reported
  from play on 2026-09-04, NOT yet diagnosed or reproduced headlessly. The hull
  appears turned relative to its direction of travel, so the nose is not pointing
  where the ship is going. Candidates, in the order worth checking: the authored
  model's own forward axis (the four hulls are OBJ/GLB from different sources, so
  one may be +X-forward while the rig assumes -Z), `ShipMesh`'s orientation fix-up
  when it fits a model into the holder, or the chase rig's aim basis. Do NOT
  "correct" it by adding a counter-rotation until which layer is wrong is known -
  a fix at the wrong layer will look right in the chase view and be wrong for
  targeting, plume sockets and the fill light. Deferred by the user; the Earth
  flyover work comes first.

- **The plane-band safety speed cap** is the other half of the slice and was NOT
  built. Cruise already dies at EZ; nothing yet forces m/s inside the band, so you
  can still cross a 10 km plate in a blink. `FlightMode` has the words (`LOCAL` /
  `AIR` / `DROP`); the cap does not exist.
- **Earth's 29 km kill line.** Until it moves, the band is airless-only.
- **Combat inside the band: there is no note anywhere.** Searched `docs/` — the
  flight-modes spec/plan, the layers spec, the asset-kit spec and research, and
  `PLANET_GENERATOR.md` say nothing about fighting at low altitude. Enemy spawning
  (`enemy_factory.gd`) has no altitude or terrain awareness. That design does not
  exist yet; do not assume it was decided.
- The kit is primitives. The CC0 library is specced and unacquired.
- All of this was verified headless. Nothing here has been seen on a GPU.

---

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

### One knob for the whole fleet: `ShipMesh.booster_brightness`

The exhaust came out of that pass very subtle, and the note here said "raising the two
energy constants is the lever". It is not any more - `static var booster_brightness` at
the top of `scripts/flight/ship_mesh.gd` is. Change the number, press F5.

It multiplies every booster layer on all four ships through `ShipMesh.booster_gain()`:
the authored propulsion surfaces, both torch cone layers, snarkrans' nozzle plugs and
JazOone's engine discs. The per-ship `*_BOOSTER_GAIN` constants stay put - those are
area compensation (below), not taste, so turning the knob keeps the fleet's relative
balance. `1.0` is the shipped look. Read at BUILD time, so the loop is F5, not live
flight.

Guards, in the contract tests, and they come in pairs: a `*_calibration_*` check that
uses the knob-free base constant (the shipped look must be off the slab, and this stays
testable whatever the knob is parked at) and a `*_knob_within_safe_window` check on the
live value. **If only the `knob_within_safe_window` checks fail, the code is fine and the
number in ship_mesh.gd is too high** - that is the whole point of the split. The windows:
class_ii's broad propulsion value at 1.5 and its core at 3.0, JazOone's disc centre at
2.5 (the binding one, ~x1.29).

Every other brightness assertion compares against `booster_gain()`, so the suite follows
the knob instead of pinning literals the way the old `== 4.0` assertions did. Two of them
were quietly broken by that: `torch_peak_stays_off_the_slab` multiplied by a literal 3.4
described as "the hottest brightness any ship hands the core layer" (snarkrans passes
3.50) and could never fire however far the knob went, and `test_ship_customization`'s
range ceiling scaled with the knob, so a paint bug writing any value under it would pass.
Both now read the built material and assert the ship's own base gain.

`tools/test_booster_brightness.gd` (new) is the one that actually pins the knob. At the
shipped 1.0, `booster_gain(x) == x`, so no other test can tell a wrapped call site from a
hardcoded number - and `cruiser_propulsion.gdshader` defaults `brightness` to 4.0, so on
class_ii even a MISSING set passes. It builds all four ships at 0.5 and 2.5 and requires
every booster material to move by exactly the ratio, plus sockets and positive radii on
every shaped surface. Verified by mutation: unwrapping one call site fails 3 checks,
dropping one `_wire_nozzle_shape` call fails 2, zeroing the radii fails 3.

`tools/render_thruster.gd`'s `TORCH_GAIN`/`PROP_GAIN` are still the split sweep (torch
against propulsion, for picking a value); they apply on top of the knob.

### The emissive was the WHOLE mesh, and that was the real bug

Raising the knob past ~1.16 did not make the engines hotter, it made the white *wider*.
Cause, found by reading `cruiser_propulsion.gdshader` rather than tuning it: **the shader
had no spatial term at all**. Across an entire booster patch the only variation was
`visibility` (view angle, 0.58..1.0) and `shimmer` (a scrolling sine, 0.86..1.12).
Every pixel sat at the same value, so `brightness` scaled a uniformly-lit plate and the
whole plate clipped at once. This is the "headlights, not exhaust" reading, and it is why
three rounds of tuning the energy constants changed nothing - the constants were fine,
the falloff was missing. The plumes were never the problem: `cruiser_torch.gdshader` has
real shaping (`radial_n`, `tip_fade`, `growth`, the shock train), so cones get brighter
*and* keep structure. The surfaces they sit on did not.

`tools/probe_booster_shape.gd` (new) measured what the geometry actually is, in units of
each socket's own radius:

| ship | sockets | radial extent | depth extent | shape |
|---|---|---|---|---|
| class_ii | 6 (one surface) | 0.33-1.82 r | 0.80 r | 4 bells + 2 flat rings |
| snarkrans | 3 | 0.00-1.49 r | 1.96 r | deep housings |
| dingo57 | 8 (own surfaces) | 0.70-1.78 r | 0.77 r | short bell walls |

Careful with those spreads: they are measured in a 2x-radius WINDOW around each socket,
which on class_ii also catches the neighbouring patches (sockets ~14-20 units apart,
radii 8.6). The number that means something is triangle area against distance from a
triangle's OWN nearest socket axis:

| ship | within 1.0 r | in the 1.0-1.15 r fade | beyond the border |
|---|---|---|---|
| class_ii | 100% | 0% | 0% |
| snarkrans | 33% | 10% | 57% |
| dingo57 | 11% | 2% | 87% |

**On dingo57, 87% of the glow was the HOUSING around the engine**, at full intensity, and
on snarkrans 57%. That is the white that kept spreading past the nozzle rim, and no
energy constant could have fixed it. class_ii is the exception - its authored patches are
the nozzle faces themselves, so the border cuts nothing there and only the core gradient
changes its look, which is why its effective area comes out at 108% rather than down.

**The fix: the sockets that place the plumes are now handed to the shader too.** Each
fragment finds its nearest socket and grades against it - `rim` fades the emissive out
between 0.85 and 1.15 r so the glow ends *inside* the housing, `core` boosts the inner
edge 1.5x so the knob buys contrast instead of width, and `depth_dim` drops the deep
interior of a housing that its own bell hides. Both coordinates are needed: every socket
measures MIXED, so a plain radial gradient would have switched snarkrans' 2-radii-deep
walls off wholesale. `socket_count = 0` restores the old flat plate, which is what any
unwired material still gets.

Wiring is `ShipMesh._wire_nozzle_shape` + `_model_to_surface_space`. `shape_axis` exists
because `_add_dense_booster_plug` puts this shader on its own rotated cylinder whose axis
is +Y, not model Z.

**The socket constants are in MODEL space, and one asset's surfaces are not.** JazOone's
five Layer_1 chunks sit under a parent chain that scales them 36.968x (uniform, all three
axes) and rotates them: model +Z comes out as (0.076, -0.046, 0.996) in a chunk's vertex
space. Centres, radii AND the axis all have to be converted - an unconverted axis was the
one bug this work shipped and then caught, and an unconverted centre would have put every
socket ~37x too close to the origin and switched the discs off entirely. The three OBJ
ships load as a single MeshInstance3D, so for them the conversion is identity and none of
this is visible; do not "simplify" it away.

**JazOone needed the same treatment, and the obvious fix did not work.** Its disc comes
from a binary `step(0.25, mask)`, so softening the mask into a gradient looked like the
answer - but `probe_propulsion_area.gd` measures the mask as saturated: the gradient keeps
**96.1%** of lit texels and the rim stays hard. It got the socket falloff as well, off the
sockets `probe_jazoone_sockets.gd` recovered from that same mask. Its gain stays 0.40:
unlike the other three it never had a housing ring (2.52% of hull raw, 2.63% effective -
it keeps 104% of its area against dingo57's 12%), so the shaping redistributes the same
total energy into a hot centre and a 50%-value rim. Peak at full boost: 1.29 broad, 1.94
at the centre. It is still the ship with the least headroom - about x1.29 of knob.

`tools/render_thruster.gd` gained `KNOB=<f>` (photograph a candidate knob without editing
ship_mesh.gd), `SHAPE=0` (strip the sockets back off after the build - the A/B against
the old flat plate) and `SHIP=<label>` (one hull instead of the four-ship sheet, which is
minutes of wall clock on software Vulkan). Nothing else assigns `booster_brightness`
except `test_booster_brightness.gd`, which restores it.

**Measured A/B**, dingo57, chase view, knob 1.0, `SHAPE=0` against shaped, comparing only
the pixels that differ (the whole-frame stats are useless here - the ship is ~40 px wide
in the chase view and the starfield swamps every metric):

| | total light in the engine band | peak | look |
|---|---|---|---|
| flat plate (old) | 100% | 1.000 | eight pale octagonal plates nearly merging into one band |
| shaped (border) | **72%** at boost, 86% at cruise | 1.000 | eight small bright cores, dark metal between them |

The peak does not move - the core still clips - while 28% of the light in that band goes
away. That is the housing, and it is the whole point.

**And run it as a SCENE, with a display.** `render_thruster.gd`'s own header says so
(`xvfb-run -a godot --path . res://tools/render_thruster.tscn`); driving it with
`--script` hangs forever without ever creating its output directory, because a SceneTree
script never pumps render frames. Two runs were wasted on this.

### Per-ship gain, because the emissive AREA differs tenfold

`tools/probe_propulsion_area.gd` measures how much of each hull the additive booster
shader covers: **class_ii 0.64%, dingo57 4.30%, snarkrans 6.69%** (JazOone's discs are
their own case). These layers add, so one flat brightness washes the wide-area ships out
while leaving class_ii correct - which is why snarkrans kept a white patch across its
mid-hull after the ALBEDO fix landed. `DINGO57_BOOSTER_GAIN` and
`SNARKRANS_BOOSTER_GAIN` in ship_mesh.gd scale by `sqrt(class_ii_area / own_area)`, the
same reasoning as the per-nozzle light share in ship.gd.

**Re-derived from EFFECTIVE area once the border landed.** Raw area is the wrong input
now: most of each housing contributes nothing, so `probe_propulsion_area.gd` integrates
the shader's own falloff over the triangles and prints the table it derives the gains
from:

| ship | raw % | effective % | kept | gain |
|---|---|---|---|---|
| class_ii | 0.64 | 0.68 | 108% | 4.00 (anchor) |
| dingo57 | 4.30 | 0.50 | 12% | **4.68** (was 1.6) |
| snarkrans | 6.69 | 1.20 | 18% | **3.02** (was 1.3) |
| jazoone | 2.52 | 2.63 | 104% | 0.40 (unchanged, different ramp) |

Snarkrans' upper/lower shells now integrate to 0.00% - the old 1.6 and 1.3 were mostly
compensating for area that is no longer lit at all. Deriving from raw area after the
border would have over-compensated again in the opposite direction. The cost: dingo57 and
snarkrans emit ~34% and ~42% of the total light they used to, which is exactly the excess
that came from lighting their housings; class_ii, the anchor, is unchanged at 106%. The
probe also stopped reporting JazOone's whole hull as emissive (it read 100%; the discs are
2.52%) - it integrates per triangle against the mask now.

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

## One glow variant, and it is on

Settings had a `Glow` dropdown with **High** and **Low**. That was never two qualities:
High meant `glow_enabled = true` at the tuned values, Low meant `glow_enabled = false`.
A toggle wearing the wrong labels. It is now one `CheckButton`, and main.gd ships a
single glow level that sits between the two old ends:

| | intensity | bloom | levels |
|---|---|---|---|
| old High | 0.9 | 0.05 | 1:0.8 2:0.4 3:0.15 5:0.0 |
| old Low | *off* | — | — |
| **now** | **0.45** | **0.0** | unchanged |

`glow_intensity` is the amplitude dial on the whole blur chain, so halving it halves the
halo's brightness *and* the radius at which it is still visible — that is why the level
weights (the radius tuning above) are left exactly as measured. `glow_bloom` goes to 0
because bloom bleeds every pixel regardless of `glow_hdr_threshold`: harmless while glow
was off, a flat lift across the whole frame now that it ships on.

The three quality presets no longer mention glow at all (there is nothing for them to
pick). Only **Performance** still forces it off.

**This re-arms the glow chain, so `booster_brightness` matters again.** Anything the
plume pushes above 1.0 now blooms. At the time of writing the knob is 20.0, which puts
class_ii's propulsion peak at 20.8 and its torch core at 11.15 — the "hot pixel grows a
ball" config, and `test_class_ii_cruiser` / `test_jazoone_spaceship` say so via their
`*_knob_within_safe_window` guards. Both clear at a knob of **1.9 or below**
(propulsion: `0.26 x 4.0 x knob x 1.5 <= 3.0`; torch: `0.20 x 3.40 x knob x 0.82 <= 1.5`).

## The hull was black except for the nozzles

Complaint: "we cant have rest of our ship completely dark". The scene sun in main.gd
comes from wherever the real Sun is, so on any heading that flies away from it the whole
camera-facing side of the hull drops to the 0.35 counter-fill plus 0.2 ambient — a
silhouette with two bright engines.

Fix is one `DirectionalLight3D` named `HullFill`, parented to the chase camera (so it
inherits the camera's orientation for free and survives every path that rewrites
`camera.global_transform`), swung off-axis and cull-masked to the ship alone:

- `Ship.HULL_FILL_ENERGY` 0.85, `HULL_FILL_COLOR` cool, `HULL_FILL_SPECULAR` **0.12**
- `HULL_FILL_YAW_DEG` -32, `HULL_FILL_PITCH_DEG` -24 — dead-on is flat and erases the
  panel detail the light exists to reveal
- `light_cull_mask = ShipMesh.SHIP_FILL_LAYER` (bit 2). `ShipMesh.tag_fill_layer()` ORs
  that bit onto every `VisualInstance3D` under the hull at build time. Everything else
  in the game sits on layer 1 alone, so this light cannot reach the planets, the
  station, the props or the starfield. Layer 1 stays set on the hull so the scene sun
  and counter-fill still light it.

**Directional, not point, on purpose.** The three key/fill/core `OmniLight3D`s that used
to sit a few metres off the hull clipped their own specular on low-roughness metal and
blew the engine bay to white in-game while an offscreen render of the same ship looked
fine (see the note in `Ship._build_ship_model`). A directional light has no distance
falloff to blow out, and `light_specular 0.12` keeps the highlight contribution near
zero, so only diffuse lifts.

## The chase camera aimed dead level

`Ship.CAM_VIEW_PITCH_DEG` was 0.0, so all you saw was the tail plate and the nozzles —
the hull's whole top surface was edge-on. `CAM_OFFSET` (0.5 up over 2.6 back) does raise
the eye ~11 deg, but the *aim* did not follow it.

Now **-14.0** (negative = look down). The rig rotates position and aim together, so the
eye ends up 1.11 hull-lengths up and 2.40 back — 24.9 deg of elevation — looking down
the spine. You read the dorsal hull and still see both plumes. Toward 0 for a flatter
tail-chase, toward -25 for a map-like overhead.

`tools/test_chase_rig.tscn` pins the signs on both of these, because each is one flip
away from being useless and nothing else covers them: the eye must be above *and* the
aim must tip down; the fill's cull mask must exclude layer 1; the fill must come from
above; and every mesh on all four hulls must be tagged while keeping layer 1.

It is a **scene**, not a `--script` test, unlike the rest of `tools/`. It preloads
ship.gd for the rig constants and ship.gd touches the `Ephemeris` autoload at parse
time, which a `--script` run does not register — the whole file then fails to compile.

## `booster_brightness` must keep its decimal point

The knob was found as `static var booster_brightness := 20`. `:=` infers **int** from
that, so every fractional value assigned to it truncates — `= 0.8` becomes `0` and the
boosters go out entirely. `test_booster_brightness.gd` sweeps 0.8 and caught it as four
`scales_by_exactly_the_knob_ratio` failures. It is `20.0` now. Keep the point.

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
