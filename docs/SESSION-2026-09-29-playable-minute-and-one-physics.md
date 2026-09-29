# Session 2026-09-29: playable minute, one physics (pickup note)

Written at the end of a hard day. The player has not flown any of this. Every "works"
below means "a headless scripted test passes", nothing more. Read `docs/ROADMAP.md`
"September 29 direction" for the decisions; this note is the state.

## Where things are

- **main @ b62b8a5** (committed, not pushed): landing contact pass, playable minute,
  fix pass, arcade UI removal. Tree clean apart from this note.
- **branch `one-physics`** in worktree `../space-survey-one-physics`, 6 commits on top of
  main, not pushed, not merged: slices 1 and 2 of
  `docs/plans/2026-09-29-one-physics-ripout.md`. Slices 3 (delete wormholes/hubs) and 4
  (UI + docs leftovers) not started. Handoff notes for each are at the end of that plan.
- The player's live profile was overwritten twice by test runs earlier today (saved
  location lost, coins kept). `ASTRYX_PROFILE_DIR` + `ProfileDir.isolate()` now stop
  that; every tool that boots the real game uses it.

## What a player can check in ten minutes (fresh launch from b62b8a5 or the branch)

```
ASTRYX_START=pad godot --path .
```
Start locked on Kennedy LC-39A. Lift off, climb through the skin (sky black, no stars
through the noon blue), reach a few hundred km, turn back, dive (HUD reads MACH and AIR
LOAD, rumble plays), land on the same pad. README "How to play the loop" has the keys.
That loop is the only thing today was meant to make real. Judge the day on it.

## What is still unknown

- Whether landing FEELS landed. The scripted test asserts lock, hold, no drift, depart
  for seven hulls at 60 and 20 fps. The player reported "nothing about landing was fixed"
  from an editor instance that predated the commit; not yet re-flown. If it still feels
  wrong after a fresh launch, the contact pass measured the wrong thing and the landing
  session (roadmap S.1: mark pad → approach → position → touch down) is the real work.
- Whether the four moments of the loop feel like anything. No camera/sound/HUD design
  exists for lift-off, skin exit, look-back, re-entry (roadmap S.6).
- Anything visual: all captures are llvmpipe software GL.

## If picking up

1. Fly the loop. Write one sentence per moment.
2. If continuing the rip-out: slice 3 brief is the plan doc's "Slice 2 done" handoff.
   Then merge `one-physics` into main and remove the worktree.
3. Known open bugs: `docs/bugs/2026-09-29-thrust-dead-zone.md` (throttle under ~0.34
   does nothing, hurts touch), `test_anchor_frame` two Moon wall-clock assertions fail
   at HEAD, Alien Zone swarm still in arcade units (roadmap S.8), props hidden outside Sol
   until slice 3.

## Lesson recorded

The orchestrator reported test results as in-game facts all day. Any claim about feel
ends with a build in the player's hands and a question, not a green test.
