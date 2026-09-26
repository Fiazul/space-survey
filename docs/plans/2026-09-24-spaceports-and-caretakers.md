# Spaceports, orbital stations and caretaker missions

Status: Kennedy and Wenchang surface ports, automatic ship assistance and dated ISS/Tiangong orbital references implemented. Collidable orbital berths, caretaker missions and station services remain pending. See [the assistant update](2026-09-24-ship-assistant.md).

## Decisions

- Earth gets both surface spaceports at real launch-site locations and real-world orbital station references. Ground locations use sourced latitude/longitude; orbital locations use a dated orbital state and advance with the game clock. An orbiting station cannot be pinned to a permanent longitude. Record source, epoch and approximation with every catalogue entry; do not claim live tracking without a current feed.
- Real facilities provide geography and identity. Their in-game landing pads and docking berths must accommodate Astryx hulls; these are fictional adaptations, not claims that today's facilities can berth these ships.
- Successful landing/locking and station services require a designated pad or berth. Terrain remains solid everywhere. Ground contact away from a facility cannot open docking services, grant a landing checkpoint or replace the port loop. Keep contact/support separate from permission to dock; no invisible walls or lethal ground.
- Ship flight keeps the existing banking, steering, boost, drift and camera response. The user subsequently requested underside support jets for takeoff and gravity/drift correction. The latest user directive replaces gear-only support with automatic hazard and approach assistance, including gear-up terrain protection, plus planetary leveling that yields to manual Q/E and pitch input. Cosmetic flutter never adds random physical forces. Space flight retains free attitude.
- Caretaker bots provide ship-to-station communication and missions at planets and safe stellar hubs. No on-foot controls are needed. Gas giants and unsafe surfaces use orbital facilities.
- Earth stays an abandoned graveyard and yields scrap, not an improving colony. Autonomous caretakers can survive there. The new request for existing bot hubs supersedes the original downloaded roadmap's prohibition on all pre-existing infrastructure; player-built relays and station upgrades still matter.

## What exists now

`ShipSystems` supplies procedural feet, weapons and eight canted underside support outlets per hull. `ShipSurfaceContact` resolves hull/foot contact against terrain, ruins and facility geometry. Co-rotation preserves fractional position changes, fixing low-speed takeoff that previously showed velocity without gaining altitude.

Kennedy LC-39A is the first facility recipe: 28.608402° N, 80.604201° W, from [NASA's hosted SpaceX environmental assessment](https://netspublic.grc.nasa.gov/main/20190807_Final_DRAFT_EA_SpaceX_Starship.pdf). The ship apron and buildings are fictional game adaptations at the sourced location, not a replica. The coarse coast mask reads water here, so the compound uses a raised solid foundation; fine coastal geography remains future work. The same box recipes drive visible geometry and collision. Trees, props and generated ruins exclude the footprint. Nearby rendering uses five batched material meshes plus a label, unloaded beyond 15 km.

The 260 m pad fits all five hulls. Gear contact within the pad and upright alignment can lock the ship. The attachment follows the rotating body and persists by facility ID with body-local position/attitude. Space releases the lock and supplies two seconds of clearance lift; Ctrl/brake can override that lift. A compact pad clearance/offset cue accompanies the existing vertical-speed display. Bare ground remains physical contact without a facility lock. Support jets hold a slow upright ship against gravity and damp uncommanded drift; Space/Ctrl still control ascent/descent. Main thrust, steering and banking keep their existing paths.

Try TELEPORT / Ctrl+P → Kennedy / NASA SpaceX LC-39A landing pad, B to lower gear, Ctrl to descend, Space to depart. Mobile uses the existing gear and UP/DOWN controls. Verified via `test_surface_facility.tscn`, `test_landing_support.tscn`, existing hull/contact tests, and rendered inspection of the real terrain patch and all five support rigs. Broader station services and orbital docking are not supplied by this first pad.

`Props` stations are decorative meshes. `Main._update_dock_ui` grants docking by proximity; `_set_docked` freezes the ship. This is not physical station docking.

The crafting catalogue supplies material classes, elements and nine component/facility recipes. It does not supply a persistent inventory, harvesting transactions, fabrication or recipe unlocks. The existing mission log lists survey objectives; it is not yet a caretaker quest system.

## Build order

### 1. One Earth port that supports the whole landing cycle

Create a reusable facility recipe: stable ID, parent body, surface/orbital placement, source metadata, visual recipe, pad/berth dimensions, approach vector, services, caretaker role and ownership. Start with one verified Earth launch site; use the same recipe for subsequent sites.

Fit its ground foundation into the shared terrain sampler. Clear vegetation/ruins within the pad footprint. Generate the pad, collision surface, markings, approach lights and nearby caretaker terminal with procedural geometry. All five ships must fit, including deployed feet and wings.

Split terrain contact from facility attachment. Flight states: approach, supported contact, pad/berth locked, releasing, free flight. Require gear/berth readiness, correct alignment, low relative speed and the full landing footprint within an available pad. Space releases the attachment and triggers support lift while steering and main thrust remain available once airborne. Collision outside a pad gives physical contact, not a successful landing.

HUD: one contextual approach cue with pad ID, clearance, descent speed and alignment. A compact status explains why locking is unavailable. Keep the view clear of large new panels.

Done when every hull can approach, touch down, stay attached through day/night rotation, reload at the same facility and take off; bare terrain never grants facility services or a landing checkpoint.

### 2. One Earth orbital station using the same facility contract

Replace a decorative proximity dock with a physical station and a ship-sized berth. Place it in an Earth-relative orbit using sourced orbital parameters/epoch. Docking uses station-relative position, attitude and velocity. Attach to the moving station frame while docked; release with the station's inherited velocity. Orbital departures use berth clearance, not planetary upward lift.

A real station's visual model may need an added fictional external berth rather than pretending a large ship fits inside an existing small docking port. Test collision, approach, berth lock, frame changes and reload while the station moves. Expand Earth ports/stations only after this shared loop works.

### 3. First caretaker and persistent mission

Use ship comms with one contextual interaction control. Caretaker data: stable identity, role, small dialogue set, available jobs and unlocked services. Persist accepted/completed jobs and rewards independently of streamed meshes. Begin with a survey mission, an Earth scrap recovery job and a relay-expansion job. Generate objectives from actual reachable bodies, available materials and player progression; explain why each job exists.

Implement persistent inventory and exactly-once reward transactions before allowing material rewards. Then wire class/grade recipe slots to an atomic fabrication transaction. Show qualifying substitutions and missing inputs. Keep the roadmap's free, unlimited probes and persistent timed relay builds; reserve advanced fabrication/storage for built or upgraded stations.

First playable loop: launch from Earth port → contact caretaker → survey or recover scrap → return and dock → receive reward → fabricate a starter component → obtain the Moon relay objective. Earth resources remain low-grade scrap.

### 4. Recipe-driven planetary and stellar hubs

Deterministically assign caretakers and approach locations to each planet and star. Use surface pads only on suitable terrain; use orbital berths for gas giants or hostile surfaces. Stellar placement must use the current star recipe's size, radiation/heat hazards, gravity and activity, with a safety margin and a reachable approach corridor. Validate binary companions and the facility's entire orbital path, not just its spawn point. Never use one fixed distance for every stellar class.

Small caretaker pods provide comms/missions; they do not automatically give away all player-built station facilities. Ownership and service tiers distinguish legacy Earth sites, autonomous hubs and player-built stations.

Only load nearby facility geometry and bot visuals. Keep distant sites as lightweight catalogue entries/map markers; sleeping bots need no continuous AI update. Share procedural meshes/materials and batch repeated pad fixtures. Persist station/quest state by IDs, not node paths.

### 5. Expand the network and progression

Populate the verified Earth catalogue, then the rest of Sol, then procedural systems. Add material-grade sampling, gas skimming, archive unlocks, station upgrades and fuel/cargo-gated travel. Map filters distinguish ports, orbital berths, caretaker jobs and player relays. Script the roadmap's story beats over these working systems.

## Verification and boundaries

Test pad containment and collision at low frame rates, all five hull sizes, moving orbital frames, saved attachments, teleport/frame resets, simultaneous input during takeoff, exactly-once quest rewards and craft rollback when inputs are missing. Measure near-surface frame time with a port present before replicating facilities across Earth.

Current validation limitation: `test_surface_integration.tscn` still fails its three Earth/Moon hull-clearance assertions. These also fail on unchanged `a02b4d7`, verified in an isolated baseline. Baseline additionally fails `newton_rest_stays_slow`; the co-rotation precision change passes that check. Do not describe the entire terrain integration suite as passing. New facility/support tests, existing ship systems, terrain contact, surface structures, Sun flight and HUD tests pass; rendered review covers the raised foundation, gear contact and all five underside rigs.

The current projectile model already adds ship velocity to muzzle velocity. With the user's local 132x tuning, muzzle speed is 158.4 km/s; a forward shot from a ship moving forward at 10 km/s travels at 168.4 km/s in that frame. Its 3 km muzzle-relative range gives about 0.019 seconds of live flight. Visible afterimages are separate from damaging projectiles. Range, muzzle speed, damage and visual exposure should remain independent tuning controls; the present pass preserves the user's experimental values.
