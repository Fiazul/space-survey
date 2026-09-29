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

## Landing-cycle pass (2026-09-29)

`tools/test_landing_cycle.tscn` runs the full cycle for all seven hulls at 60 and
20 fps in main's frame order over rotating Earth. Sustained groundward thrust no
longer gains AGL (verified). Fixed classes, each through one shared path:

- Contact corrections drop the sub-ULP motion remainder while Earth co-rotates
  ~1.4 km/frame: a resting hull walked metres per second. All writes now go through
  `Ship.apply_surface_contact` -> `_advance_anchor`.
- Two resolvers per frame (ship substeps, then main) in two float-offset frames,
  and main erased the ship's `surface_impact`. `Ship.surface_contact_owned` makes
  the ship the only resolver for its anchor body; main covers other bodies.
- Ship physics rotated its surface frame by float32 basis products while main
  rebound the ephemeris basis each frame (up to ~1 m mismatch). `terrain_angle`
  carries the ephemeris spin angle as a double; both build the same basis.
- Broad-phase used radial altitude against the hull radius: on steep slopes hull
  probes were skipped and a 10 km/s impact embedded 6-28 m. `BROAD_SLOPE_COS`.
- Terrain-avoidance hold was push-only: gear-down hover over open ground bobbed
  between ~50 and 100 m. `ShipAssistant.correction` holds both ways without
  vertical pilot intent.
- Stationary support confirmation required `v_radial <= 0` exactly; ~1e-10 of
  rounding blocked a pad lock indefinitely. `REST_KMS`; the lock pose is seated
  on the deck by `SurfaceFacility.seat`.
- Relocations that skipped the revision bump could leave `landed`/pad state live;
  every discontinuous move goes through `Ship.relocate`.
- Sub-metre results computed from Earth-radius float32 vectors (ADR-0002):
  the pad hold rebuilt `terrain_basis*pad` every frame, `seat`/`pad_at`/facility
  and settlement collision used `affine_inverse()*point`, and contact returned an
  absolute snapped position. Now the pad hold rotates the double-precision offset
  (`_rotate_anchor`), site-local math subtracts the origin first
  (`SurfaceFacility.to_site`), body-frame conversion runs in double with the spin
  angle (`Ship.terrain_local`), and contact returns a double-precision `delta`
  (`TerrainSampler._snap_delta`); a settling hull projects from its end point.

Measured after this pass: pad hold drift <= 9 mm over 5 s of rotation; a hull
resting on bare ground shows 0 m/s, <= 0.5 m AGL spread and <= 0.2 m creep (was
~2 m, 4.7 m/s, 3 m). The test pins the rotation clock (`LANDING_CLOCK=<unix_s>`
or `wall` to randomise the phase).
