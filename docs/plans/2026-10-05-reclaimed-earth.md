# Reclaimed Earth

Approved direction: import the local mmo-rpg oak/pine kit, enlarge Earth's trees,
make Astryx more vibrant, and let forests reclaim powerless abandoned cities.
Also simplify Sovereign to one swept wing pair and remove its central stern keel.

Implementation: prove distance partitioning and bounded populations, copy six
tree GLBs and their shared textures with provenance, normalize meshes to km,
use seven instanced batches (two species × three detail levels plus legacy
ground props), then allow street vegetation outside building footprints.
Keep terrain/collision height, facility clearances and atmospheric gates intact.
Add recipe-controlled moss/ivy and cracked, overgrown streets; apply a restrained
shared color grade. Verify the required terrain checks and affected forest,
settlement and ship checks. Capture real rendered forest/city/ship views.

Budget: 64 full trees, 512 medium trees, remaining forest instances as four-triangle
crossed cards, within the existing 8,192 forest + 400 ground-prop population cap.
Full assets <=3,000 triangles; textures <=1,024px. Tree batches may submit up to
11 material surfaces, replacing the old three primitive-only draws intentionally.
GPU frame rate requires the user's hardware; software rendering verifies appearance.

User refinement: uneven groves, ordinary trees 80–140 m and rare ship-sized giants
250–440 m. Keep a stable grid only as the underlying seat IDs; grove coverage and
jitter break its appearance. This deliberately exceeds real Earth tree heights.

Progress: baseline checks passed; new LOD test failed then passed; large-tree test
failed then passed. Imported kit is 2.8 MB including shared textures. Ship rebuilt
at 18,168 triangles and all 34 sockets retained.

Forests now build independently from terrain. Measured worker latency and tangential
flight speed select a wider sparse sampling stride on canonical tree seats; stopping
restores the dense population even without moving. Ruins prefetch a corridor up to
10 km ahead. Both retain their submitted population while replacement jobs run.
Tree detail buffers update at most about seven times per second. Worker shutdown
also collects jobs when detached test/tool nodes are freed.

Verified: terrain recipe, Earth collision, surface band, skin kill and lighting;
forest seating/giants, tree LOD caps, submitted prop geometry/determinism, settlement
clearance, independent 4 km/s scenery streaming and 78.6 km/s Earth/Moon terrain
streaming. Earth captures use the actual imported textures, a simpler foliage lighting
shader, mixed temperate oak/pine coverage and capped tree exposure. Seven tree batches
remain within 500k submitted triangles and the fixed instance caps. Software GL
captures verify appearance and shader execution, not device frame rate.

Next request completed alongside validation: stellar recipes use visible blackbody
colors, bounded surface texture and white-biased optical corona. A reproduced shared
planet-loader bug reset the pending-map list on every callback: fast-loaded maps
were disabled while slower maps loaded. A mutable state dictionary now retains only
unfinished loads and releases the polling closure on completion. The staggered-load
regression failed six assertions before the fix and passes after it. No universal
GPU frame-rate claim is implied by these checks.
