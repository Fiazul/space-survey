# The playable minute (2026-09-29)

One loop a stranger can fly tonight, no menus, no story. It goes in front of every
roadmap row (`docs/ROADMAP.md` "September 29 direction") because it is the honest test
of whether the fantasy works, and because the player needs one thing that plays.

## The loop

1. Start locked on the LC-39A pad, gear down, engines idle, clean HUD.
2. Lift off. Support jets, engine ramp, climb through the air. Sky goes black at the skin.
3. Reach a few hundred km. Earth under you: real terrain, clouds, day/night line.
4. Turn back. Dive. Air load climbs, rumble builds. Land on the same pad.

Target: about one minute of real flight for a decent pilot, under five for a first-timer.

## Scope (build)

- **Boot on the pad.** A new profile starts locked on LC-39A, gear down. Existing saves
  are untouched. `ASTRYX_START=pad` forces it for any profile (dev + tests). Goes through
  `Ship.relocate()` and the facility attach path, never a raw `anchor_off` write.
- **Home marker.** The pad is a permanent HUD target: name, distance, and an edge arrow
  when off-screen (Navigator already draws markers and edge arrows; reuse, don't add a
  second marker system). Below 5 km it also shows height above pad.
- **Four moments, tuning only, no new systems:**
  - lift-off: engine audio ramps with thrust; support-jet lift reads on the HUD;
  - skin exit: sky must be black above the skin, stars visible, no haze in vacuum
    (standing rule, `NEEDS-YOUR-EYES.md`); verify, fix only if broken;
  - look back: Earth at 300 km renders terrain + clouds without a visible stutter;
    measure frame time on the approach, log it, quick wins only (F.4 is its own row);
  - re-entry: `FlightMode.air_load` drives HUD and engine-air audio (L.4 already);
    confirm it reads through a real dive.
- **Land.** Pad lock from the 2026-09-29 contact pass. If lock is flaky, report, don't
  patch around it (landing is its own session, roadmap S.1).
- **How to play.** One short section in `README.md` (keys, the loop, what "good" looks
  like). Remove the alien-boss-wave / capture-for-coins sales text while there (player
  decision 2026-09-29).

## Out of scope

Combat, probes, inventory, new ships, flight-model or drag changes, any refactor of
`main.gd`, terrain/shader changes, Android build. If it isn't one of the four moments
or the boot/marker, it waits.

## Acceptance

- `tools/test_playable_minute.tscn` (scene-based): scripted flight from pad → full thrust
  up → coast → return burn → descend → pad lock, at dt 1/60, asserting: pad lock at
  boot; leaves the skin above 100 km; apogee ≥ 300 km; comes back inside 100 km with
  air load rising; re-locks on LC-39A. Prints `playable_minute: OK`. Under 3 min sim.
- `ASTRYX_START=pad godot --path .` boots on the pad on a fresh profile (state evidence).
- Four captures under `xvfb-run -a` (existing render harness pattern, `SHOT_DIR`):
  on-pad, mid-climb through the skin, look-back at 300 km, re-entry with air load > 0.3.
  PNG paths in the report for the human to look at.
- Frame-time log on the 300 km look-back and the re-entry, before/after any quick win.
- Existing tests unaffected: `test_landing_cycle`, `test_docking`, `test_landing_support`,
  `test_surface_facility`, `test_ship_systems`, `test_anchor_frame` all still pass.
- No commits. `git status` + `git diff --stat` in the report.

## Player check (after build)

Play it ten times. Then one person who has never seen it plays once. Write down what
they say at each of the four moments. That note decides what comes next.
