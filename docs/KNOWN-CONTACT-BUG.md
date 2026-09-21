# Known issue at the 2026-09-21 checkpoint

Reported by the player: point the ship toward the ground and continue thrusting
following surface contact. The ship can continue moving away and AGL increases.
Braking to zero with S permits approaching the surface again.

This checkpoint intentionally preserves the bug before the contact-response fix
and the approved expedition-instrument HUD redesign. Prior contact tests passed
but did not reproduce this sustained-thrust interaction. See the gameplay-readiness
spec for other limitations and the four outstanding anchor/drag test assertions.
