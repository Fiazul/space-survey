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
| L.3 | Band speed cap removed; Newton + drag only, both directions; DEV FASTAIR (`\`) = drag ×0.1 touring stopgap | player: acceleration must exist leaving a body; artificial caps break the "fly it, don't be capped" feel | burn straight out from 5 km over Earth: no ceiling, no floor, either direction | S |
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
| G.8 | Entry-heat regime: the ship's 2 g thrust vs drag never reaches heating speeds in air; any visible entry FX needs a designed flight regime first (high-thrust air mode or a deliberate hot-entry descent profile), then leading-edge-only blackbody glow capped at deep orange, never a plume, never white | 2026-09-09 audit: controlled flight tops out at air_load ≈0.005 (80 m/s sea level, 250 m/s at 10 km), below every FX threshold — a visual layer here was unreachable and got ripped out rather than shipped dark | a designed dive reaches air_load ≥0.5 without a terrain kill | M |

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
