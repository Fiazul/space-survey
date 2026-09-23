# Known issue at the 2026-09-21 checkpoint

Reported by the player: point the ship toward the ground and continue thrusting
following surface contact. The ship can continue moving away and AGL increases.
Braking to zero with S permits approaching the surface again.

This checkpoint intentionally preserves the bug before the contact-response fix
and the approved expedition-instrument HUD redesign. Prior contact tests passed
but did not reproduce this sustained-thrust interaction. See the gameplay-readiness
spec for other limitations and the four outstanding anchor/drag test assertions.

## Resolved after checkpoint

Steep high-speed impacts preserved almost all tangential velocity. On a slope,
that tangent can point upward even with the nose still pointing into the ground.
The contact response now dissipates impact slip and caps residual sliding at
20 m/s, alongside the existing 5 m/s maximum rebound. Free flight is unchanged.
The regression covers a 10 km/s impact on a 45-degree slope and verifies that
groundward thrust can overcome the remaining motion without braking first.
