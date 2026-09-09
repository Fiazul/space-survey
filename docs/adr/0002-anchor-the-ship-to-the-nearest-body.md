# Anchor the ship's physical state to the nearest body

**Status:** accepted · 2026-09-09

The ship's position was one Earth-centred `Vector3`. This is a stock single-precision Godot
build (`real_t` is a 32-bit float), so a coordinate carries an ULP of about `|value| * 1.19e-7`.
Near Venus — a real ~1.2e8 km from Earth — that is roughly 14 km. `true_pos += velocity * dt`
at 3 km/s over a 0.05 s substep moves 150 m, which rounds to nothing: the ship froze the instant
supercruise dropped to real time. Reproduced and reported at 249.11 km AGL near Venus. The same
failure applies to every body except Earth and the Moon, and it gets worse outward — Saturn's
~1.4e9 km is a ~170 km ULP.

Nothing about that is fixable inside the flight code. `FlightMode.break_at_exclusion` had already
been given a magnitude-scaled boundary tolerance to survive it, and at Venus's magnitude the
tolerance that needs (~450 km) is wider than Venus's entire 250 km atmosphere — there is no eps
that avoids both freezing and never firing. The storage frame had to change.

## Decision

The ship's physical state is **(`anchor_name: String`, `anchor_off: Vector3`)** — the body it is
flying near, and its offset from that body's centre in km. The anchor is re-selected whenever the
nearest body changes.

1. **`Ephemeris` stores every body's position in 64-bit km** (`_pos64`, scene axes) alongside
   nothing else — `scene_pos()` now derives from it. `rel_km(body, anchor)` subtracts per axis in
   GDScript floats (64-bit even in a single-precision build) and packs the small result into a
   `Vector3`. That is the ONE sanctioned way to ask where one Sol body is relative to another.
2. **All cross-body arithmetic happens in doubles before packing.** `AnchorFrame`
   (`scripts/flight/anchor_frame.gd`) holds that arithmetic: decompose, absolute, reanchor,
   rel_to. It is static and autoload-free so a plain `--script` test can exercise it.
3. **`Ship.true_pos` survives as a property**, not a field. The getter packs
   `anchor + anchor_off`; the setter decomposes an absolute position onto the current anchor.
   Boot, arrival, respawn, dock landing, the save file and the debug tools write through it.
   Physics never touches it — the Newton loop integrates `anchor_off`. Reading `true_pos`
   across a reanchor costs about one ULP of the anchor body's own absolute magnitude, once
   packed into a `Vector3` (measured: ~8 m at Earth↔Moon at GEO altitude, up to a few km at
   Saturn↔Titan — bigger anchor magnitude, bigger ULP). A sub-metre bound is impossible here
   by construction, which is exactly why physics and `to_body`/`rel_to` never round-trip
   through it.
4. **Everything else asks the ship.** `Ship.to_body(name)` for a Sol body, `Ship.rel_to(abs_pos)`
   for a static absolute fixture (wormhole portals, props, docks). `PlanetSystem.refresh` takes
   `(ship_off, delta, anchor)` and computes each physical body's offset through `rel_km`.
5. **State that shares the ship's frame moves with it.** Combat's bolts, aliens, pickups and
   guardian centre live in the anchor frame; `main` calls `combat.shift_frame()` on every switch.
   Velocity is untouched: body positions are static for a session (Horizons is fetched once), so
   an anchor hand-off carries no velocity term and needs no hysteresis — the switch is exact.
6. **Outside Sol the anchor stays Earth**, whose position is the origin, so `anchor_off` IS the
   absolute position and every authored system behaves exactly as before. `Ship.anchor_name`
   itself stays `"Earth"` even outside Sol — nothing needs to change it, since Earth's `pos64`
   IS `ZERO64` either way. What must change per system is what `main` hands to
   `PlanetSystem.refresh`: outside Sol that call passes `anchor = ""` (never `ship.anchor_name`
   unconditionally), so `refresh` keeps the plain subtraction against the CURRENT system's own
   bodies instead of `rel_km`-ing against Sol's Earth/Sun (a real bug: an arcade system's sun
   vector came out of Sol's `rel_km("Sun","Earth")`, not the local star).

This is the rendering invariant pushed one level down. Rendering already said "the ship stays at
the render origin; bodies draw at true position minus the ship's true"; physics now says the ship
stays at a small offset from a nearby body, and everything else is measured from there.

## Considered options

- **Compile a double-precision Godot build** (`precision=double`). Correct and invasive: it is a
  non-stock engine binary every contributor and every CI/export path would have to match, for a
  problem that is local to one coordinate. Rejected.
- **Keep one absolute frame, store it as three 64-bit scalars on the ship.** Fixes integration but
  not the fan-out — `PlanetSystem.refresh` subtracts every body against the ship every frame, and
  each of those subtractions is still catastrophic cancellation. Rejected: it fixes the symptom
  we reproduced, not the category.
- **Re-origin the whole world on a threshold** (shift every coordinate when the ship gets far).
  Classic floating origin, but Sol's bodies are at fixed real positions — moving them all means
  rewriting `Ephemeris`, the sky shells and the save format anyway, and it introduces a visible
  discontinuity at every shift. The anchor achieves the same thing continuously. Rejected.

## Consequences

- **Newton now sums the moons too.** `_newton_g` iterated `PLANETS` only while
  `PlanetSystem.refresh` summed mu for every body; that disagreement is gone —
  `Ephemeris.gravity_bodies()` is the one list, resolved once, planets and 1:1 moons together.
- **The ground clamp, co-rotation and altitude are anchor-relative**, so they work at any world
  rather than silently applying Earth's numbers. Co-rotation rotates about `Vector3.UP`, which is
  the celestial pole: exact for Earth, an approximation elsewhere until `Ephemeris` carries a spin
  axis rather than a rate.
- **Atmospheric drag stays Earth-only** and is now gated on the anchor explicitly. There is no
  per-body density table; the geometry around it is anchor-correct, so nothing Earth-shaped fires
  near Venus. Adding that table is backlog.
- **The save carries `anchor` + `off`.** A pre-anchor save has only `pos`, which was Earth-centred
  by definition, so it loads through the setter onto Earth unchanged.
- **Interstellar coordinates keep the plain subtraction.** Named stars sit at ~1e13 km, where the
  ship's own magnitude is a rounding error and the sky point's precision is bounded by the star's
  own 32-bit position either way. Anchoring buys nothing there.
- A body's position is still only as good as the 32-bit AU constants and the Horizons reply behind
  it (a few hundred km at the outer planets). That is a catalogue-accuracy question, not a flight
  one — what the anchor guarantees is that the ship's offset from whatever body it is flying near
  is exact.
