# Plasma direction and high-speed readability

Two independent direction failures were reproduced:

- With an eight-minute Earth cycle, an equatorial ship is transported about
  83 km/s by its surface frame. Projectiles only inherited `ship.velocity`, which
  excludes that frame transport. They therefore appeared to run sideways or
  backwards as the ship moved around the planet. A regression across four headings
  and several muzzle speeds failed 20 assertions before the correction.
- When ship drift exceeds muzzle speed, the intercept quadratic can have two
  positive roots. Converging the guns on the free-aim endpoint always selected the
  earliest root, even if it required turning the guns away from the nose. At
  200 km/s backwards drift and 32× muzzle speed, both guns failed the heading check.

Atmospheric shots, impact flashes and resolved traces now follow the same planetary
frame as the ship before their relative motion is integrated. This transport uses
the terrain basis, never ship steering. It is gated by the existing atmospheric
co-rotation model (currently Earth). Anchor changes also shift the cached body
centre, preventing a second translation on the next update.

Per-gun convergence selects the valid intercept closest to the requested firing
direction. Target acquisition retains its earliest-intercept default. A fired shot
keeps its course when the ship turns; the next shot follows the new barrel pose.

The firing effect now has a dense launch pulse, camera-relative motion exposure,
a brief collision-clipped final trace, a white muzzle discharge, local hull light,
an emitter glow pulse and a stronger impact flash. Traces are visual-only and
bounded; they cannot hit again. Shared meshes and per-instance fading avoid extra
assets and per-shot material copies. Main's default speed/damage settings reference
the projectile tuning constants instead of overriding them with duplicate numbers.

## Verification

- `tools/test_plasma_frame.tscn`: headings at 0.5×, 32×, 132× and 256×; independent
  shot flight after steering; new shots follow the turned nose; fast-drift
  convergence; rotating traces and anchor handoff.
- `tools/test_plasma.tscn`: all five hulls' muzzle origins, inherited momentum,
  deployment/atmosphere gates, ground/building occlusion, clipped visual endpoints,
  no duplicate damage, bounded effects and high-speed sub-frame visibility.
- `tools/test_weapon_aim.tscn`: assistance, all-hull convergence and stable sight.
- GPU chase captures with static flight, 80 km/s lateral motion, and firing while
  turning in the accelerated rotating frame. User tuning is exercised separately
  from the stock constants; local experimental values remain editable.
