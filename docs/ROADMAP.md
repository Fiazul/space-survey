# Roadmap — visual view + gameplay feel

Reframed 2026-09-09 (player rejected "Sol realism → public build" framing: "we are
currently working on a visual view and gameplay feel"). Goal image: an Elite Dangerous
frame, ship 100–200 m over a Mars-like surface — hard-shadowed, sharp-rimmed craters,
layered distance haze, low sun. No landing, ever — solo-dev scope stays hypersonic
atmospheric flight skimming the skin (`Ephemeris.surface_kill_km`), not a landing game.

Every row: why it matters against the goal image, acceptance judged by looking at the
real game (not a test passing), size (S ≤ 1 worker-day, M 2–3, L a week+), status.

## Landed today, awaiting player verification (2026-09-08/09)

| # | Item | Why it matters | Acceptance (in-game) | Size |
|---|---|---|---|---|
| L.1 | Ice ≠ water classification + water look (ripple, foam line, shallow tint, mipmapped masks) | sea ice/shelves were reading as water, wrong for a Mars-first frame but also wrong on Earth | coastlines and polar ice read distinct from open ocean in a real flight | M |
| L.2 | Recipe geology: multi-octave crater fields 30 km → 45 m, real depth/diameter law, rim crests, hills band, landmark pre-cull; Moon max height 2.87 km (test bound 3.6 km) | craters need sharp rims and real depth to read like the reference at low altitude | craters at 100–200 m alt show a rim crest and a bowl, not a smear | M |
| L.3 | Band speed cap removed; Newton + drag only, both directions; DEV FASTAIR (`\`) = drag ×0.1 touring stopgap. 2026-09-12: drag rescaled (`FlightMode.air_ballistic`/`AIR_TERMINAL_KMS`) so boosted sea-level terminal ≈ `AIR_TERMINAL_KMS` (currently 50 km/s; was ≈12 km/s under an earlier revision of this same directive, ≈0.14 km/s under the original hand-picked ballistic coefficient) — DEV FASTAIR is now mostly redundant at that speed; contact-kill tunnelling at hypersonic in-air speed is the accepted known limitation already described in `flight_mode.gd` | player: acceleration must exist leaving a body; artificial caps break the "fly it, don't be capped" feel | burn straight out from 5 km over Earth: no ceiling, no floor, either direction | S |
| L.4 | `FlightMode.air_load`/`mach` source + HUD/audio only; visual entry layer removed 2026-09-09 (unreachable regime) | this IS the gameplay feel axis — hypersonic atmospheric flight has to feel physical, but the FX must actually be reachable first | HUD G/Vspd/Mach/Load and engine-air audio read correctly through a dive; no visual claims made until G.8 lands | M |

## In flight (2026-09-09)

| # | Item | Why it matters | Acceptance (in-game) | Size |
|---|---|---|---|---|
| F.1 | Surface ring rebuild moved to WorkerThreadPool, atomic swap, quantisation + band-edge hysteresis, analytic normals for seam continuity | a rebuild hitch or a torn seam breaks the frame at exactly the altitude the goal image lives at | steady flight over Earth ring recenter shows no hitch, no seam tear; pale band / polar holes stay unreproduced | M |
| F.2 | Near-surface CloudLayer at recipe `cloud_alt_km`, gated like the ring; fixing coverage-floor bug (clear sky was 45% opaque), adding drift/morph synced with globe clouds, translucent thin cloud | layered atmosphere is part of the reference frame's depth read | flying under/through the cloud shell at low alt reads as air, not a grey wall; clear sky reads clear | M |
| F.4 | Perf: threaded close-map loading in `ensure_close_maps`; profiler scene prepared, measurement pending on a quiet machine | player: "going towards Earth is super laggy" — a stutter kills the flight feel outright | approach to Earth from deep space shows no stutter on a quiet run, fps logged before/after | M |

## Open gaps vs the goal frame (not yet briefed)

| # | Item | Why it matters | Acceptance (in-game) | Size |
|---|---|---|---|---|
| G.1 | **Cast shadows on terrain from the sun** — landed (per-vertex horizon shadow), shadow maps deferred. `SurfacePatch._compute_ring` marches each vertex toward the sun with the shared `TerrainSampler` height function and stores a soft-edged shadow factor in vertex `UV2.y`, multiplying `terrain_tile.gdshader`'s direct-light term only (ambient floor/night side untouched); paired with a per-body `exposure` albedo gain in `shaders/planet_color.gdshaderinc` so a dim body doesn't compress to black before the shadow can add contrast. Rendered captures pending player judgment (`PLANET_GENERATOR.md` "Exposure and horizon shadow") | the single biggest visible gap from the reference — the reference's hard-shadowed rims ARE this | a crater at low sun angle shows a real cast shadow from its rim, not just facing-away darkening | L |
| G.2 | Layered distance / aerial perspective tuned to the reference frame; low-sun long shadows; night side (spec: `docs/superpowers/specs/2026-08-22-recipe-driven-planet-nights-design.md`) | the reference's depth comes from haze layering + long low-sun shadows, not flat lighting | far terrain dissolves in layered haze at the reference's altitude band; low sun casts long shadows | M |
| G.3 | Near-ground detail at 100–200 m: rock/boulder scale, scree, small-scale normal detail, prop density on the potato budget | at the reference altitude the ground must show texture at metre scale, not a flat-shaded plate | flying at 100–200 m over dry terrain shows rock-scale detail, not a smooth ring | M |
| G.4 | Chase-cam framing like the reference (ship low in frame, horizon high), FOV | the reference's composition is part of "the view" the player wants | chase cam at cruise shows ship low, horizon high, matching the reference crop | S |
| G.5 | Sun glint at horizon over ocean (pre-existing term, needs judging in real flight) | low-sun water glint sells both light direction and water material | flying toward a low sun over ocean shows a glint streak on the water | S |
| G.6 | Water still a shader plate — no real wave geometry (fine for now) | flagged so it isn't silently expected to look like real waves yet | n/a — explicitly deferred | — |
| G.7 | Surface kit (CC0 props): KayKit Forest, Quaternius clouds/accents, Kenney Nature; recipe → kit mapping; prop density/dressing pass | props still primitives; demoted below the shadow/haze/detail work since those read at a glance and props don't at this altitude | Earth trees, Moon ejecta rocks, Europa ice, Io basalt read as real props in captures; 60 fps floor at 1 km on the potato target | M |
| G.8 | Entry-heat regime: the ship's 2 g thrust vs drag never reaches heating speeds in air; any visible entry FX needs a designed flight regime first (high-thrust air mode or a deliberate hot-entry descent profile), then leading-edge-only blackbody glow capped at deep orange, never a plume, never white | 2026-09-09 audit: controlled flight topped out at air_load ≈0.005 (80 m/s sea level, 250 m/s at 10 km), below every FX threshold — a visual layer here was unreachable and got ripped out rather than shipped dark. **2026-09-12 update: the premise changed** — drag was rescaled (see L.3) so boosted equilibrium now reaches air_load ≈0.9 at every altitude (`FlightMode.AIR_LOAD_TARGET_FRAC`, `tools/test_flight_envelope.gd`), well past this row's ≥0.5 acceptance bar; the regime is now reachable in ordinary controlled flight, not just a designed dive. This item is still open (no visual FX exists) but no longer blocked on reachability — it needs an actual FX design pass, not a new audit | a designed dive reaches air_load ≥0.5 without a terrain kill | M |

## Later / not the current axis

Compressed from the old release-phase plan; revisit once the visual/feel axis above is
judged against the reference frame.

- Release hygiene: name Cold Light vs Astryx undecided (`project.godot` vs docs).
- Wormhole hop test reinstatement (scene-based, hop guarantee unchecked since 2026-09-08).
- `./build.sh` verified end to end, screenshot from the real build.
- Settings (resolution/vsync/volume/invert-Y/reset profile), controller support.
- Release: Windows + Linux build.sh, itch.io/GitHub Release, CREDITS complete.
- Sun as one physical body (retire `_sun_sky` impostor).
- Map swaps in the albedo slot (Deimos, gridless Ganymede, 8k USGS/NASA/ESA majors).
- Named peaks / real-spot volcanoes from a small table.
- CC0 kit acquisition/provenance ledger (see G.7 above for the mapping work itself).

## Explicitly not on this roadmap

Landing. Unique mesh per world. Google Earth tiles. Volumetric air. Store-page scope
(Steam, achievements, localization).

## Gameplay layer — foundation started 2026-09-21

Spec: `docs/specs/2026-09-12-astryx-gameplay-layer-spec.md` (progression spine, material
classes + grades, probes/relays/stations, data archive, procedural quests, map UI).
Starter material classes, qualification resources, Earth recipes, and non-lethal
surface contact are implemented. Inventory/fabrication are next. See
`docs/specs/2026-09-21-surface-contact-and-gameplay-readiness.md`. Thesis: no loss ever, difficulty from
scale and distance. Earth = permanent graveyard port.

Implementation order (from spec §7, systems before spine): (1) MaterialClass / ElementDef /
RecipeDef + qualification table → (2) grade from planet-gen params → (3) inventory +
fabricator → (4) probe deploy, async build, relay persistence → (5) station tier + fast
travel (fuel, mass cap) → (6) scan data value + archive unlock tree → (7) quest composer,
3 shapes first → (8) map filtering / relay collapse → (9) spine beats 1–8 last.

Landing direction updated by the user on 2026-09-21: ships need solid terrain contact
and future landing support; player landing controls are not part of the current pass.
The old “no landing, ever” constraint is superseded. Choose the probe deployment trigger
when implementing the relay loop; free, unlimited probes remain required.

Gas skimming (§2) maps onto atmospheric flight and is a candidate gathering loop.

## September 24 direction: facilities and caretaker jobs

Ships retain the existing seamless flight and banking. Small underside support jets
now counter gravity and drift only with gear deployed, upright, below 500 m AGL and
60 m/s. They provide departure lift without replacing normal controls. Safe landing
locks are restricted to designated pads while terrain stays solid. The first physical
Earth port is Kennedy LC-39A, with a procedural apron, collision, persisted pad lock
and departure support for all five hulls. The remaining Earth sites, orbital berths,
station services and NPC jobs are still pending. Earth needs both surface spaceports at verified
real launch sites and orbital station references. Planets and safe stellar locations
get interactive caretaker bots and jobs. This replaces the original prohibition on all
pre-existing infrastructure; Earth remains an abandoned, scrap-only destination.

Implementation sequence and current gaps: [spaceports and caretakers](plans/2026-09-24-spaceports-and-caretakers.md).

## September 29 direction: one physics, speed, transitions (must-have)

Decided by the player 2026-09-28/29 after a combat review. These sit ABOVE the visual
rows: none of the gameplay beats can be judged until they land. Source for the time
budget and early rewards: the storyboard "Astryx #1: The Last Launch" (2026-09-24,
GAMEPLAY footers per page); repo spine is `docs/specs/2026-09-12-astryx-gameplay-layer-spec.md` §1.

Decisions (record as ADR when the first slice starts):
- **One physics, one unit.** 1 scene unit = 1 km and Newton gravity everywhere. The
  arcade flight model (0.01 AU scale, `VISUAL_SCALE`, 550 cap, warp spool, drift damping,
  `GRAVITY_ENABLED=false`) is removed, not kept "until we say otherwise". Supersedes
  `docs/specs/2026-08-17-sol-speed-end-goal.md` "other systems stay arcade".
- **Speed is time compression, never a fake engine.** In-system travel = Newton at real
  speed with a faster clock. Compression must stay engaged during burns (the clock is not
  the ship) so Earth→Sun is ~1 min and a departure is not a 17-minute burn. No caps, no
  fake gravity, no fake air. Allowed compromises: infinite fuel, hull never breaks, heat is
  visual only.
- **Air terminal speed is derived, not chosen.** `AIR_TERMINAL_KMS` 50 km/s was a test
  value during the build (player, 2026-09-28), not a design call. Derive the ballistic
  coefficient from a plausible drag coefficient and hull area; expect ~0.3–1 km/s at sea
  level rising with altitude. Hypersonic only where the air is thin.
- **Star-to-star: drive first, teleport after.** No wormholes. The first visit to a system
  is by the crafted interstellar drive (storyboard p.6, beat 8 payoff); after a first
  visit the system unlocks for teleport (Genshin-style). Teleport never handles the first hop.
- **Combat has a role or it is cut.** Storyboard p.4: optional, pulled by distress calls,
  in atmosphere, pays in rare parts, never mandatory. Alien boss waves / capture-for-coins
  leave the README. No bullet work until the combat envelope exists (co-moving enemies,
  reduced thrust authority while engaged, bullets tuned in ratios: bolt speed / ship
  delta-v, engagement radius / speed, seconds of flight).
- **Vertical slice before breadth.** Beats 1–3 (minutes 0–15: Earth falls, launch, orbit,
  return) get finished to a level a stranger can play, before any new system starts.

| # | Item | Why it matters | Acceptance (in-game) | Size |
|---|---|---|---|---|
| S.1 | Landing is its OWN session (player, 2026-09-29: "not a toy"): a designed sequence — mark the pad, approach, position, touch down — with its own spec before any build. The 2026-09-29 contact pass (`tools/test_landing_cycle.tscn`, 8 defect classes, review found 2 float32 sub-ULP blockers in `SurfaceFacility.seat` and the pad hold) only makes the current mechanics correct; it is not the landing feature | beats 1–3 cannot be played if the first landing breaks | a stranger can mark LC-39A, fly the approach, position, and land, all seven hulls, without reading anything | L — spec first; contact pass in fix round |
| S.2 | Earth sites as world content: more real launch pads (Baikonur, Wenchang, Jiuquan, Starbase, Tanegashima, Kourou), ruin districts (NASA HQ, SpaceX Hawthorne, CNSA), one orbital station on the LC-39A facility contract | it is what the player sees in minutes 0–15 | each site loads at its real coordinates, pad lock works, ruins read as ruins from 200 m | M |
| S.3 | One physics: rip the arcade model, Newton + km everywhere; per-system ephemeris at real scale from HYG mass/luminosity + seed; re-tune every non-Sol constant (spawn radii, guard ranges, arrival positions) in km | foundation for travel, combat, and the kids/education version; the two-physics split is the root of the "soggy" feel | a non-Sol system flies exactly like Sol; no `VISUAL_SCALE`, no 550, no spool; `speed_zones`/arcade paths deleted | L — on a branch, after S.1/S.2 |
| S.4 | Cruise autopilot under compression: "go to X" plans burn, coast, flip, brake; compression stays on during burns; HUD names the frame ("×840 compression", never "velocity") | the only thing that keeps Sol to 2 hours; Navigator today only draws markers | Earth→Moon in ~2 min real, Earth→Sun ~1 min, no dev engines; drop to 1× only at the exclusion zone | M |
| S.5 | Derived drag constant; atmospheres on Mars and the giants through the recipe, not per-body branches | air combat and gas skimming happen at a few hundred m/s only if drag is honest | sea-level terminal ~0.3–1 km/s on Earth; hypersonic reachable above ~30 km; Mars/Jupiter air load reads on the HUD | S |
| S.6 | Transition architecture: every regime change is one event with a 2-second feel spec (camera, sound, HUD) driven by `FlightMode.air_load` and body proximity — cloud entry/exit, skin entry, hypersonic onset, gas-giant descent, exclusion-zone DROP, compression engage/disengage. One system, one table, no per-case hacks | today each transition is a first pass with no design, which is why they all feel "soggy"; G.8 entry-heat is one row of this table | each transition has a written spec row and a render/audio capture; a dive from 100 km to sea level reads as a continuous change, not a set of switches | M |
| S.7 | Planet doctor: `tools/planet_doctor` runs contract checks (every recipe cooks, `crust_height` == shader `sample_height` at sampled points, ring seams continuous, no NaN), perf probes (ring rebuild ms per body, close-map load ms, frame time along a fixed flight path at 20 km / 7 km / 200 m) and look checks (the 19 `TERRAIN_SHOTS` under xvfb diffed against golden PNGs with a perceptual threshold → "human should look") into one green/red table | "so we always know something broke, lags, or doesn't render well" (player); llvmpipe can't judge beauty, so reds hand PNG paths to a human | one command, one table; a deliberate height change turns a row red | M |
| S.8 | Combat envelope (after S.3/S.4): co-moving enemy spawn, thrust authority cap while engaged, ratio-tuned bullets (~1.5 km/s, 3–4 km, ~2 s flight, exact crosshair = actual bolt kinematics incl. ship velocity), visible tracers with a min pixel size, hit feedback | only meaningful once one physics exists; the 2026-09-28 bullet brief is parked until then | a fight at 30 km/s orbital speed feels identical to one at rest; the lead marker is where the bolt lands | M |

Order: S.1 → S.2 → S.3 (branch) → S.4 → S.5 → S.6 → S.7 alongside → S.8 last. Probes,
inventory, mining, drive (beats 4–8) resume after S.4.

Open decisions for the player, not yet written down anywhere: (a) support jets gear-down
only (roadmap) vs terrain avoidance also gear-up (code + tests) — recommend updating this
roadmap to the code; (b) whether a bare-ground touchdown is ever allowed or the 35 m
gear-down hover stays the rule (current rule: locks only on pads).

## Fleet update (2026-10-05)

Sovereign added as tier 8: 240 m, eight modular weapon mounts, four fusion drives,
440 HP and 250 energy; unlocks after 16 systems beyond Sol. Hull budget increases
from 25k to 30k only for this ship. Angular continuous armor, swept black ray inlays, a panoramic bridge and upper/lower
stepped engine hoods and lower cradles follow the concept and player feedback;
dense square tiles and raised bumps removed. No armor
extends behind the nozzle mouths; socket checks enforce exhaust clearance.
Final polish adds narrow exposed-metal bevels, weighted normals, restrained brushed
surface maps and lower bridge aprons. Outer housings shortened to approximately 120 m
with recessed, chamfered ventilators and swept louvers on their front ends.
The final export uses 18,168 triangles, six material surfaces and approximately 1.05 MiB.
Extra canards/tail blades and the central underside stern keel are removed; one
continuous swept wing pair remains.
Authored metallic/roughness maps now retain their factors through hull recoloring.
Editable source and concept live in `tools/blender/`; final studio and Godot previews
are in `docs/reference/sovereign/`. Player judgment of the revised look is still pending.

## Reclaimed Earth and stellar rendering (2026-10-06)

Imported the local mmo-rpg oak/pine kit with full, medium and card detail levels.
Earth has uneven groves, 80–140 m trees and rare 250–440 m giants, plus vegetation
between powerless ruins, moss and overgrown streets. TerrainSampler still controls
all seating and collision. A shared restrained color grade adds vibrance.

Forest jobs run separately from terrain; velocity/worker latency widen coverage at
speed and stopped flight restores density. Ruins prefetch ahead and both retain
previous instances until replacement data arrives. Population and geometry caps
are tested, including 4 km/s scenery and 78.6 km/s terrain streaming.

Stars now use cached visible blackbody/CIE colors and temperature-based surface
variation instead of the orange plasma override. Surface detail filters away below
pixel size, hot stars have subdued convection, and optical halos tend toward white.
The Sun's sixfold exposure boost is removed. A reproduced shared asynchronous-map
bug that disabled completed textures during staggered loading is fixed and covered
by a regression. Star destinations and mesh/sky handoffs pass their existing checks.
Rendered previews are in `docs/reference/reclaimed-earth/` and `stellar-colors/`;
device GPU frame rate and final player judgment remain unverified.

Actual in-game review also found far-side triangles corrupting distant opaque
stellar spheres. The common cook shader now culls those faces; its pixel regression
fails with the old mode and passes for the Sun/Sirius cores with the fix. Space
background is black. Current nearby destinations remain predominantly warm/white
because their catalogue includes no O/B stars; hot-star recipes support blue-white.
