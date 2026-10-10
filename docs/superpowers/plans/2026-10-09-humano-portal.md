# Humano Portal Implementation Plan

> Execute inline in the current checkout, preserving the uncommitted galactic-core work.

**Goal:** Horizon crossing leads through cubic mist to a dinosaur playing Humano;
exit restores the ship at 2 AU.

**Spec:** `docs/superpowers/specs/2026-10-09-humano-portal-design.md`

**Architecture:** A CanvasLayer portal with its own 3D viewport and a Control
runner rendered onto a physical monitor. Main owns entry and anchored return.
Godot 4.6.3; existing direct-reference wiring; no extra dependencies or asset files.

## Constraints and review focus

- Preserve ship hull, customization and progress; never reset or commit existing work.
- Save a 2 AU circular orbit during the portal, including window-close saves.
- Pause/hide every space canvas and input handler; restore previous states on exit.
- Pause existing space audio without changing the player's volume settings.
- Keep fast swept crossings, repeated entry, Escape during loading and small screens valid.
- Use finite coasting inside the portal, never integrate the gravity singularity.
- Run only one Godot process at a time; captures use software rendering and timeouts.

## Tasks

- [x] Add `tools/test_humano_runner.gd` and its scene; see missing runner fail.
- [x] Implement `scripts/ui/humano_runner.gd`: `reset_run()`, `jump()`,
  `advance(delta)`, `human_rect()`, `hit_obstacle()` and pixel artwork.
- [x] Run runner checks and verify red→green.
- [x] Add `tools/test_black_hole_portal.gd` and its scene; see missing entry fail.
- [x] Implement `scripts/core/black_hole_portal.gd`: `begin(main)`,
  `advance(delta)`, `return_to_ship()`, isolated room, suspension and restoration.
- [x] Update Main's horizon handler, process guard, safe profile serialization,
  and `return_from_black_hole_portal()`; preserve ordinary surface behavior.
- [x] Run portal, runner, galactic-core and plunge checks sequentially.
- [x] Capture and inspect cubic entry, loading and arcade at desktop/mobile sizes.
- [x] Review the scoped diff, update module/docs maps, and record verified results.

## Verified result

Runner and portal were tested red→green. Final headless checks: humano_runner, black_hole_portal, galactic_core, black_hole_plunge and one_physics all OK. Software OpenGL captures verified real Space input, cubic descent, loading, dinosaur arcade, portrait layout and 2 AU return. Review findings on mouse capture and persistent audio teardown were reproduced and fixed. Added a Ctrl+P Humano preview row without changing the five physical core views.

The screenshot follow-up exposed a direct Astronaut.glb instance in the concurrently edited Main.tscn, separate from managed Props. Main keeps that decoration in Sol; Props also actively hides inactive system items. Both cases have regressions. The scene and unrelated editor/import changes were preserved. Work stays uncommitted.

The 0.585 AU screenshot follow-up replaces the restored developer bypass with
an explicit 0.6 AU gameplay capture rule. A failing test reproduced outward
escape; forced radial infall now passes with inward, outward and tangential
20-million-km/s velocities, repeated extreme outward thrust, both NODEATH states,
a swept entry, an exterior miss and safe 2 AU exit. Exterior orbit tests use
20 r_g, outside the capture boundary. The physical force-law analysis is retained.

Release snapshot validation: 16 headless checks passed. The catalogue travel
smoke test needed a longer timeout and passed on rerun. OpenGL motion/close-view
checks passed; software Mobile verified input and the full portal sequence.
Its close capture frame exposed foreground occlusion (BH-002), recorded in the
known-bug list and release notes; no Android hardware test was possible.
