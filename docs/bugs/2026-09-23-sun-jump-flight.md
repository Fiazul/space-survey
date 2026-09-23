# Sun jump: reversed-looking motion and lost travel

Reproduced through Ctrl+P's actual `DevSitesPanel.go` path, with normal engines.
The old Sun park was only 120 km above the photosphere. Local gravitational
acceleration measured 0.274106 km/s²; forward engine acceleration is 0.02943 km/s².
After ten seconds burning outward, radial velocity was **−2.4468 km/s**. The
steering assist rotated that backwards fall with the hull: turning toward the Sun
changed it to **+2.4468 km/s**, before gravity reversed the motion again. These
signs reproduce the user's report; this was not an inverted altitude formula.

The float32 position vector also discarded small per-frame displacements. At the
old park, ten seconds of outward burn moved the rendered position only 8.8125 km
inward, undercounting the expected travel. At a more distant park, whole seconds
of ordinary thrust could disappear into coordinate rounding.

Changes:

- The default Sun park is four solar radii from the centre. Normal forward thrust
  exceeds local gravity. Gravity itself is unchanged; closer approaches can still
  overpower the engines.
- TurnCarry only redirects velocity within 30 degrees of forward flight. It does
  not flip a backward fall or sideways drift just because the hull turns.
- Newton position integration carries rounding residuals between steps. Explicit
  relocation, anchor changes and externally corrected positions invalidate them.
  Stellar altitude includes this residual and uses double-precision scalar length.
- Dev jumps cancel carried autopilot/rotation/time-warp state and publish the new
  terrain, gravity and nearest-body data before the next flight step.
- The stellar HUD reads `PHOTO ALT` with explicit radial `IN`/`OUT`. An outward
  burn that remains underpowered during a fall displays `THRUST BELOW GRAVITY`.

`tools/test_sun_flight.tscn` exercises the real panel jump, outward/inward burns,
monotonic altitude, metre-sized translations at large radii, relocation reset and
the HUD warning. `tools/test_turn_carry.gd` includes both a single 180-degree turn
and a turn in 180 increments, alongside the existing forward steering checks.

Validation: Sun flight, turn carry, dev-site table and five-hull landing/system
checks pass. The older `test_anchor_frame` suite has two existing failures
(`earth_drag_still_fires`, the Saturn/Titan nonzero-error expectation), and
`test_surface_integration` has four existing failures (legacy hull-clearance
expectations and rest-speed). An isolated copy using the old position integration
produced the identical failures. Test teardown also reports existing resource leaks.
