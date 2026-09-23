# Recipe-driven world building

World building remains ahead of gameplay implementation. Earth stays recognizable;
abandoned districts are now part of its recipe. These changes are local, not a release.

## Ship landing and hardpoints

All five hulls now have procedural retracting legs, footpads, bay covers and
weapon mounts. Socket positions are fitted against each loaded hull; no new
external model assets are used. B toggles landing gear, R toggles hardpoints,
and firing requests deployment. Gear and weapons are interlocked. Mobile has
GEAR/ARMS controls and UP/DOWN becomes vertical thrust while gear is down.

Terrain support uses oriented hull probes and deployed footpad corners. The old
enclosing sphere only selects contact work; it no longer holds a level ship
roughly 90 m off the ground. Structures use projected hull extents as well as
foot contacts. Resting support survives the post-flight contact check, while
outward thrust can lift off. On flat ground the current fleet's center heights
are approximately 22–37 m with gear down, so center AGL does not read zero at
touchdown. Angular suspension, automatic leveling, walking and persistent
surface parking are not implemented.

Dev-site jumps now transform surface coordinates and heading through the live
planet rotation. This fixes Dhaka jumps landing outside its ruin district.
The Dhaka scatter test produces 413 structures and excludes district trees;
a Vulkan capture confirms buildings and streets at that location. Layouts
remain seeded fictional districts rather than reconstructions of real streets.

Validation: `tools/test_ship_systems.tscn` covers the five rigs, stable contact,
stationary rechecks, takeoff, pitched hulls and off-axis landing;
`tools/test_docking.tscn` covers B/R input and the rotated Dhaka jump;
`tools/render_ship_systems.tscn` captures stowed, gear-down and armed views.

## Atmospheric plasma weapons

Weapon deployment and firing now require a known physical atmosphere. The gate
uses each body's atmospheric top (Earth 100 km, Mars 80 km, etc.), rejects airless
and interstellar frames, and automatically stows mounts on exit. Gear deployment
still interlocks firing. Held fire requests deployment and waits until it finishes.

Player shots use a white-hot 1.2 m by 3.5 m core with a soft blue corona, an
35 m tapered wake, and a 65 ms muzzle flash attached to the actual firing mount.
`Main.plasma_speed_multiplier` defaults to 8.0 (9.6 km/s). It is editable in the
Inspector, including the Remote Inspector while running. 1x is 1.2 km/s;
lifetime is always 3 km divided by the selected speed (0.3125 s at 8x).
A capped visual scale targets a
three-pixel core in the chase camera so distant shots stay readable. Collision
diameter remains 0.30 m; visual scaling does not enlarge the hitbox. They inherit ship
velocity and alternate between the actual deployed muzzles. The old 120 m wide,
hundreds-of-kilometres-long player tracer beam is removed. Swept collisions pick
the nearest target or solid terrain/building obstruction. At most 48 pulses are
alive, and shot meshes/materials are shared. Existing enemy combat remains legacy
content; a full atmospheric combat encounter loop is still roadmap work.
Muzzle flashes briefly light the nearby hull, and solid impacts produce a
bounded 120 ms flare. Damage values are unchanged by this visual pass.

`tools/test_plasma.tscn` covers atmospheric boundaries, deployment lockout,
five-hull muzzle alignment, velocity inheritance, finite lifetime, frame shifts,
population budget and swept target/terrain/building collisions. The ship render
fixture also captures compact pulses at the muzzle and in flight.
`tools/render_plasma.tscn` records a 60 fps sustained-fire sequence using the
real chase-camera placement and game glow settings for visual review.

Fire control replaces the old 800 km crosshair with a pipper on the actual
3 km shot path, clipped to terrain/buildings. Target brackets and a lead diamond
account for target velocity, ship velocity and the selected plasma speed. Close
alignment permits at most 2.5° of physical mount correction; this is not homing.
The status differentiates alignment, valid firing solution, obstruction, range
and deployment/environment locks. The velocity circle is unchanged.
Unchanged obstruction previews reuse their terrain trace for at most 50 ms;
movement of either ray endpoint by 10 m invalidates it immediately. Target leading,
mount aiming and actual projectile collision checks still run each frame.
`tools/test_weapon_aim.tscn` verifies intercepts, mount direction, range, terrain
projection and live speed tuning. Existing shots retain their launch speed.

## Stellar recipes

The shared star model now supplies catalogue bodies, authored stars and hub-star
meshes with type-specific surfaces, radii and nonlethal approach telemetry.
See [STAR_RECIPES.md](../STAR_RECIPES.md) for supported families, overrides,
physical versus display units, hazard assumptions and remaining simulation work.

## Shared controls

SurfaceRecipe supports temperate_forest, arid_mountains, frozen_crust and volcanic
presets through surface.preset. Explicit surface values override preset values.
Controls include vegetation_density, vegetation_from_albedo, tree_spacing_m,
tree_height_m, tree_line_m, snow_line_m, snow_polar_drop_m, sea_ice_latitude,
wave_scale and wave_strength. No vegetation renderer branches on the body name.
Life is explicit: air and liquid alone do not imply trees on Titan or exoplanets.

TerrainSampler remains the ground/contact source. Forest seats use stable
cube-face cells rather than terrain vertices. The forest cache avoids resampling
unchanged cells. Near trees and distant canopy clusters use instanced meshes;
high-altitude terrain uses canopy shading instead of subpixel individual trees.
Snow follows elevation, latitude and slope. Water has animated normal waves,
foam and sky/sun response. Climate gates stop bright desert coastlines being
mistaken for sea ice.

These are visual climate approximations, not surveyed global biomes. Tree meshes
remain procedural low-poly assets. Canopy clusters are not interactive trees.
Water is not a fluid/buoyancy or underwater simulation; contact uses mean sea level.
Mountain LOD transitions and the finite-resolution DEM still require improvement.
The physical close-surface pipeline is live in Sol; extrasolar arcade systems
still need physical-unit migration before it can be enabled there.

## Materials and fabrication

WorldResources supplies overridable gameplay material pools, not measured deposits
or extraction yields. Solid-world liquid and atmosphere identities must be declared.
Earth retains scrap-only port salvage.

Catalog outputs: hull patch, survival module, survey scanner, station core,
fabricator, cargo storage, archive module, gas scoop and jump drive. The last six
are proposed initial names/costs for the roadmap's capabilities. Recipes require
material classes, amounts and minimum grades. Probes/basic relays remain free.

Definitions do not implement inventory, refining, fabrication transactions,
deployment, component effects, unlock persistence or craftable world meshes.

## Validation and next work

Tests cover deterministic placement, budgets, warm-coast ice exclusion, explicit
biospheres, material references and existing terrain/contact behavior. Amazon
placement produced 2,958 near trees; a 10 m shift retained 2,917. Cold placement
was about 641 ms versus 8 ms cached on this machine. These are CPU scatter timings,
not frame rate measurements or Android performance claims.

Next: improve canopy/mountain LOD transitions, validate Android budgets, improve
vegetation and ruin assets, add distant settlement LOD and interactive resource
sites, then return to acquisition/fabrication. The whole world-building pass is
not complete.

Performance follow-up: forest instance buffers now pack off-thread and publish
through bulk MultiMesh uploads. A 360-frame CPU-only forest flight profile measured
prop publication falling from 13.5 ms to 0.19 ms maximum, and the maximum measured
main update falling from 22.2 ms to 13.7 ms. The test excludes rendering; these
figures do not establish Android/GPU frame rate. Ocean fragments now skip land-only
procedural detail. Runtime profile harness: tools/profile_world_flight.tscn with
PERF_PROFILE=1 and PROFILE_CASE=forest or exit. Scene tests still report existing
resource/RID leaks at shutdown; those are not claimed fixed.


## Abandoned settlements

`surface.settlement_preset: "earth_graveyard"` configures 16 abandoned regions on
Earth. This is a fictional seeded district layout at approximate city locations,
not a street-map reconstruction. Earth's powered night lights are disabled.
Other recipes can supply `surface.settlements` entries with name, lat_deg, lon_deg,
radius_km, density, seed and optional material IDs. An explicit empty list disables
the preset. No runtime renderer branches on Earth's name.

`SurfaceSettlement` owns deterministic plots and the box parts defining broken
office stacks, roofless industrial halls and collapsed housing. Terrain and water
checks reject unsuitable plots. Forests and loose prop seats avoid districts.
`SurfaceStructures` builds instance buffers on a worker and submits three mesh
groups, capped at 1,800 buildings within 2.8 km. Streets and weathered plots are
terrain shading, following the same 120 m plot grid. Mesh parts are also the
collision shapes: high-speed hull sweeps stop at walls/roofs; missing walls are
open. Collision runs independently of render streaming, with a bounded cache and
conservative stop for pathological oversized sweeps. Ship hulls still use a
conservative bounding sphere, not landing gear or detailed hull geometry.

Buildings carry stable IDs and the region's recipe salvage material pool. This
is source metadata, not implemented salvage/inventory interactions or guaranteed
yields. Ctrl+P has London ruins and Dhaka ruins review sites. Runtime tests and
actual Vulkan captures verify both districts. There are no on-foot interiors,
NPCs, live cities, missions or functioning fabrication stations in this pass.
Ruin silhouettes and assets remain procedural; distant mesh coverage and broader
variety are unfinished. The entire Earth/gameplay roadmap is not complete.

`tools/test_surface_structures.gd` checks high-speed walls, roofs, open gaps,
embedded recovery, outward escape, settled roof contact, stable layouts, rendering
budgets, empty overrides and shared material IDs. Existing biome, cloud, dev-site,
crafting and terrain-contact regression checks pass.


## PC rendering measurements

The real desktop renderer is Vulkan Forward+ on Radeon Vega 11, 1920x1080.
An earlier forest run measured 17.0 ms median / 17.3 ms p95 wall frame time,
16.3 ms median GPU time and 0.56 ms maximum prop upload. Mapped-cloud normals now
use derivatives of the existing detail sample, replacing four additional
three-octave noise evaluations. A comparable preceding run measured 18.0 ms median
wall / 16.8 ms median GPU time; this is a modest improvement, not a guaranteed FPS.

The initial London ruins run measured 15.2 ms median / 15.7 ms p95 wall time and
14.5 ms median GPU time. A later run with revised road/facade shaders measured
17.0 ms median with a 197 ms outlier. Another game process was running during the
final sequence; the following forest run hit 35 ms wall despite 17.6 ms GPU time.
That sequence is unsuitable for an isolated before/after claim. Benchmarking was
stopped to avoid competing with the user's game. Cold rendering stalls, sustained
frame pacing and atmospheric exit still need an isolated GPU follow-up. Do not
claim that every source of lag is fixed or use these numbers as Android results.
