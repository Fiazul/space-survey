# Known bugs

## BH-001 — Sagittarius A* fly-through in developer no-death mode

**Status:** Fixed for `test-2026-10-09` (`0.15.0-dev.20261009.1`).

Tracking: [GitHub issue #3](https://github.com/Fiazul/space-survey/issues/3).

The player reported flying inside Sagittarius A* and emerging on the other side
with developer mode enabled. The reproduced bypass occurs with NODEATH enabled:
the flight integrator keeps advancing after a swept horizon crossing, and the
root horizon handler skips Humano entry.

To reproduce in the previous development build, open TELEPORT (Ctrl+P), choose Sagittarius A*, enable DEV with F9
and NODEATH with Ctrl+D, then fly through the physical horizon. The ship can
continue through instead of starting the cubic-mist descent and dinosaur game.
Expected behavior is capture into the nonlethal portal while preserving the hull.

The first horizon-only capture change was reverted at the player's request.
The follow-up screenshot showed 0.585 AU and about 20 million km/s. This release
adds a deliberate gameplay capture boundary at 0.6 AU: crossing it forces radial
infall, independent of incoming velocity, steering, thrust and developer NODEATH.
Swept crossings cannot skip the region. Infall reaches the horizon within four
simulation seconds from the boundary, then opens Humano without destroying the
hull. The HUD reads **CORE CAPTURE — NO ESCAPE**. Ordinary physics remains in use
outside the capture region.

The direct TELEPORT → search `Humano` → **through the horizon → Humano** preview
now works with NODEATH enabled too. Exit returns to a circular orbit at 2 AU.
The capture boundary is a fictional gameplay rule, not a physical event horizon.

This report concerns the physical horizon trigger; the rendered dark shadow is
larger than that trigger.

## BH-002 — Close accretion layer can obscure the ship in Mobile preview

**Status:** Open in `test-2026-10-09`.
Tracking: [GitHub issue #4](https://github.com/Fiazul/space-survey/issues/4).

The software Vulkan Mobile preview at 0.585 AU shows a close accretion layer
covering much of the foreground hull, with a horizontal screen boundary.
Forced capture, the no-escape HUD and the Humano transition still work.
See the [captured frame](reference/humano-portal/mobile_capture.png).

Reproduce with `tools/render_black_hole_portal.tscn --rendering-method mobile`
and software Vulkan (lavapipe); inspect `00_forced_capture.png`. OpenGL
close-view/foreground checks passed. On-device Android impact is unverified.
