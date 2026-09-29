# Thrust dead zone under 0.01 km/s² (found 2026-09-29 in review)

`ship.gd` (~:1585-1588, `fly()` integration) drops any commanded thrust whose
acceleration is below 0.01 km/s². With 3 g main engines that means throttle below
about 0.34 does nothing; strafe and lift (1.5 g) below about 0.68 do nothing.

Keyboard throttle is binary so nobody noticed. Analog touch throttle (0..1) and any
scripted pilot hit it: `tools/minute_pilot.gd` uses a 0.4 minimum throttle purely to
get around it. Present since at least HEAD 2e7fef9 (`ship.gd:1465` there).

Fix: remove the floor or make it a true epsilon (1e-9), then drop the 0.4 floor in
`MinutePilot`. Add a test that a 0.1 throttle over 10 s changes velocity by the
expected 0.1 × accel × 10. Not in the playable-minute pass on purpose; it is a
flight-model change and needs its own tiny brief + review.
