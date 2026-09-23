# Day/night rotation reset

Visiting Amazon after each launch reproduced the same night side. Physical globe
meshes started at identity, then accumulated `rotate_y(spin * delta)`; rebuilding
Sol also reset that angle. A pre-fix probe measured Amazon sunlight dot −0.504273
at boot, Greenwich right ascension 0° at boot/reload and −15.041067° after an hour.
The rotation direction was reversed by the ICRS-to-scene axis mapping.

`CelestialRotation` now owns a UTC-seeded simulation clock. The profile preserves
its epoch, adds elapsed offline time on load, and prevents a backwards wall-clock
jump from rewinding the saved world. Ship time warp advances the same clock;
in-game pause stops it. Earth uses the [USNO GMST approximation](https://aa.usno.navy.mil/faq/GAST),
with UTC approximating UT1. Eastward rotation is negative about scene Y because
ICRS `(x,y,z)` maps to scene `(x,z,y)`.

The configurable `world/day_night/cycle_minutes` defaults to **8 minutes** for one
complete Earth day/night cycle at 1×. It scales only the rotation clock and its
surface-frame transport, not gravity/thrust integration, weapon timing or engine
time scale. The reference duration uses a full sidereal rotation against the
current ephemeris Sun. Other bodies keep their relative rotation periods. The
saved rate applies to offline intervals; upgrading older saves retains their
previous real-time rate for that interval before switching to the new duration.

Globe meshes, sky impostors, local terrain, cloud maps and ship co-rotation now
share that orientation. Terrain horizon shadows sample the Sun in body-local
coordinates and refresh after a one-degree lighting change, at most once every
eight wall-clock seconds; direct shader lighting still updates each frame. This
prevents a short cycle from continuously rebuilding stationary terrain. Tree/building direct
and sky lighting are gated by the local horizon, so surfaces cannot receive
sunlight through the planet at night. Ruin haze also dims at night.

Surface saves retain local position and attitude instead of restoring the old
inertial position after the planet has turned. Earth teleport rows display solar
time and DAY/TWILIGHT/NIGHT. Visiting at the same real hour can still legitimately
mean night; teleporting does not force daylight.

Rotated contact checks also exposed a precision regression at the Sun: rotating
an unchanged large-radius position out and back lost small accumulated motion.
Collision misses now leave inertial position/velocity untouched.

## Verification

- `tools/test_day_night.tscn`: known epoch, eastward sunrise, both day/night halves,
  saved/reloaded/offline phase, body rebuild, globe/terrain agreement, solar labels,
  ship time warp, Earth/Moon co-rotation, surface save restoration and shadow frame.
  Also checks the 240-second half-cycle, 480-second full cycle, configurable/invalid
  durations, legacy save migration, saved-rate offline time and unchanged gravity
  integration when the day duration changes.
- `tools/test_cloud_layer.gd`: cloud orientation plus existing coverage checks.
- Horizon-shadow, ship-systems, Sun-flight, flight-HUD and fast surface-streaming
  regressions; each is run with a timeout to catch scene startup failures.
- `tools/render_day_night.tscn`: GPU captures at identical Amazon coordinates,
  altitude and heading, starting at 16:00 UTC on 2026-09-23 then advancing half
  the configured cycle (240 real seconds at the default); compares ground brightness.

The world-rendering test harnesses still report resource/RID cleanup warnings on
exit; these are not treated as evidence that the scene's assertions failed.

## Limits

This corrects spin and persistence; planetary orbits still use the existing
daily Horizons/cache positions. Other bodies retain their existing spin rates
and Y-axis pole approximation with a stable J2000 phase, not full IAU attitudes
or tidal-locking models. Nutation and precession are not modeled. Desktop tests
and APK packaging do not establish phone performance or touch playability.
