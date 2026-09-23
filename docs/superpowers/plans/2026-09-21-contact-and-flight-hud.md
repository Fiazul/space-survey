# Contact recovery and flight HUD implementation plan

**Goal:** Prevent post-impact uphill launches and replace the flight HUD with the approved expedition instrument direction.
**Architecture:** TerrainSampler owns collision response. HUD retains external control references while restructuring its presentation; a small FlightVector control projects nose and velocity independently. No flight data is invented.
**Tech stack:** Godot 4.6 GDScript, existing programmatic UI.
**Spec:** docs/design/astryx-flight-interface-direction.md
**Execution:** Inline, as requested by the user; checkpoint already pushed before fixes.

- [x] Push checkpoint with the known contact bug recorded.
- [x] Reproduce high-speed slope impact and verify recovery under inward thrust.
- [x] Dissipate impact tangent, retain limited slide/bounce; rerun contact and scene tests.
- [x] Replace default HUD arrangement and label styling; version layout storage so old coordinates cannot overlap new instruments.
- [x] Separate nose and velocity cues; keep render diagnostics behind F3.
- [x] Fix unnamed docking prompt and retain all existing menu/input connections.
- [x] Inspect real in-engine desktop orbit and forced-touch captures for readability and overlap.
- [ ] Follow-up: bright surface and supercruise visual review on hardware.
- [ ] Run contact, HUD and existing integration checks, record limitations, commit and push the verified changes.

Review focus: bright snow contrast, long body names, backward velocity, offscreen vector,
legacy saved HUD coordinates, docked/transit screen conflicts, surface impacts under thrust.
