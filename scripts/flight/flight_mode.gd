class_name FlightMode
extends RefCounted
# Zone is where. Mode is how. Exclusion is the no-cruise bubble (Elite EZ, real size).

const CRUISE := "CRUISE"
const LOCAL := "LOCAL"
const AIR := "AIR"


const STAR_CHROMOSPHERE_KM := 2500.0   # real chromosphere; corona is visual, not a cruise wall
const AIRLESS_EZ_KM := 10.0            # dump before the skin; vacuum has no 25% fake air

# Boosted terminal velocity ship.gd's drag targets at Earth sea level (player
# directive 2026-09-12: air must allow >=10 km/s, was ~0.14 km/s under the old
# hand-picked ballistic coefficient). air_ballistic derives the coefficient
# from this instead of it being hand-tuned.
const AIR_TERMINAL_KMS := 12.0

const SPEED_OF_SOUND_KMS := 0.34
# Fraction of the [0,1] air_load curve FlightMode targets AT boosted sea-level
# equilibrium (AIR_TERMINAL_KMS). Not fully saturated: a genuinely harder dive
# above equilibrium (a designed high-thrust entry, DEV tools, etc.) should still
# read as MORE load, so the curve needs headroom above the speed ordinary
# controlled flight actually reaches. air_load_q_ref derives the curve's knee
# (q_ref) from this instead of q_ref being a separately hand-picked magic number.
# 2026-09-12: the old q_ref=5.0 was picked when boosted equilibrium topped out at
# q~=0.02 at sea level (the pre-rescale ballistic, docs/ROADMAP.md L.3); under the
# rescaled drag, equilibrium q is 176.4 (rho0 * AIR_TERMINAL_KMS^2), and the old
# knee saturated air_load to 1.0 at every altitude reachable in ordinary flight —
# see the HUD's Load readout, which pinned at 100% permanently.
const AIR_LOAD_TARGET_FRAC := 0.9
# Onset floor on dynamic pressure (kg/m^3 * km^2/s^2). Below this q, air_load is
# HARD zero — not just numerically tiny. Without it, alt=90-100 km (where rho is
# ~1e-5..1e-6 of sea level) still returns a nonzero-but-imperceptible air_load for
# any real entry speed, which is wrong: nothing should be felt that high. Picked so
# 2 km/s at ~70 km (rho ~= 3.25e-4 kg/m^3, q = rho*4 ~= 1.3e-3) is the FIRST felt
# buffet — the number the player actually asked for. Untouched by the 2026-09-12
# rescale: q_ref moved from 5.0 to ~76.6, but this floor operates on raw q (not on
# the normalized output), so it's now a smaller fraction of q_ref but still gates
# the same real physical q values — still the right number for the same job.
const AIR_LOAD_Q_FLOOR := 0.0013


# Dynamic-pressure-derived entry intensity, 0..1. Reuses Ephemeris.RHO0 /
# EARTH_ATMO_H_KM — the SAME curve _newton_atmo_drag uses for drag — so heat FX
# and the drag that actually slows you always agree. PlanetGenerator.air_density_at
# is a second, independent curve (sky-opacity scale height, not drag's); mixing it
# in here would let the glow and the deceleration disagree.
# Solves air_load's own curve (1 - exp(-q/q_ref) == AIR_LOAD_TARGET_FRAC) for q_ref at
# q = rho0 * AIR_TERMINAL_KMS^2 (dynamic pressure at boosted sea-level equilibrium), so
# the curve's knee tracks AIR_TERMINAL_KMS instead of being a second hand-picked number.
# Takes rho0 as an arg (not Ephemeris.RHO0 directly), same autoload-free reason as
# air_ballistic.
static func air_load_q_ref(rho0: float) -> float:
	var q := rho0 * AIR_TERMINAL_KMS * AIR_TERMINAL_KMS
	return q / -log(1.0 - AIR_LOAD_TARGET_FRAC)


static func air_load(alt_km: float, spd_kms: float, atmo_top_km: float) -> float:
	if atmo_top_km <= 0.0 or alt_km >= atmo_top_km or alt_km < 0.0 or spd_kms <= 0.0:
		return 0.0
	var rho: float = Ephemeris.RHO0 * exp(-alt_km / Ephemeris.EARTH_ATMO_H_KM)
	var q := rho * spd_kms * spd_kms
	var q_eff := maxf(q - AIR_LOAD_Q_FLOOR, 0.0)
	if q_eff <= 0.0:
		return 0.0
	return 1.0 - exp(-q_eff / air_load_q_ref(Ephemeris.RHO0))


static func mach(spd_kms: float) -> float:
	return spd_kms / SPEED_OF_SOUND_KMS


# Solves ship.gd's own equilibrium (thrust_acc == 500 * ballistic * rho0 * v^2) for the
# ballistic coefficient at v = AIR_TERMINAL_KMS, so the drag number is derived from the
# design target instead of hand-picked. Takes its inputs as args (not read off ship.gd's
# consts directly) so this stays autoload-free and callable from a plain SceneTree test.
static func air_ballistic(thrust_kms2: float, boost_mult: float, rho0: float) -> float:
	return (thrust_kms2 * boost_mult) / (500.0 * rho0 * AIR_TERMINAL_KMS * AIR_TERMINAL_KMS)


# --- Skin-band speed cap: removed 2026-09-08 as a flight limiter (player
# decision, see NEEDS-YOUR-EYES.md and docs/ROADMAP.md "Feel - atmospheric
# flight model"). Contact kill compares the hull against terrain every frame;
# unbounded, MAX_SPEED is 10,000 units/s and 1 unit = 1 km, so 10,000 km/s -
# at 60 fps that is 166 km per frame, and the hull can step over whole
# mountain ranges between samples. That anti-tunnelling gap is now an
# accepted, tracked known limitation rather than a hard-capped speed - a real
# game doesn't clamp you. The design-speed anchor table this cap used lived
# on here only because tools/test_earth_terrain.gd still read it for
# ring-quad sizing, not for anything flight-side; it moved to
# `SurfacePatch.design_speed_ms`/`DESIGN_SPEED_ANCHORS`/`WORST_FRAME_S` the
# same day, and nothing under scripts/ or tools/ calls a band_speed_cap_*
# function any more.


# DEV-only tour aid (F9 dev-speed engines' atmosphere counterpart): there is no
# hard speed cap in air (2026-09-08, see docs/ROADMAP.md "Feel - atmospheric
# flight model"), so the only lever left for a fast Earth tour is weaker drag.
# _newton_atmo_drag reads this; nothing else should. 2026-09-12: drag itself was
# rescaled to a ~12 km/s boosted sea-level terminal (AIR_TERMINAL_KMS above), so
# this is mostly redundant now for ordinary touring — kept as an extra lever for
# even faster dev tours, not removed.
static var dev_fast_air := false
const DEV_AIR_DRAG_MULT := 0.01


# DEV-only tour aid (Ctrl+D): touring low over terrain at dev speed shouldn't end
# every pass in a contact kill. main.gd's death paths (_update_skin_kill,
# _update_core_hazard) read kill_allowed() at the top of their per-frame check;
# nothing else should read this flag directly.
static var dev_no_death := false


static func kill_allowed() -> bool:
	return not dev_no_death


# The only body with a modelled density profile so far (Earth's RHO0 + scale
# height). Gates air_load/mach/drag/co-rotation together so the HUD, the wind
# audio and the deceleration that actually happens always agree (ship.gd:242-
# 244) — a per-body table is backlog, not a silent Earth default elsewhere.
static func has_drag_model(body_name: String) -> bool:
	return body_name == "Earth"


static func exclusion_from_center(radius: float, air_top: float, is_star: bool) -> float:
	if is_star:
		return radius + STAR_CHROMOSPHERE_KM
	if air_top > 0.0:
		return radius + air_top
	return radius + AIRLESS_EZ_KM


static func can_cruise(zone: String, dist: float, exclusion: float) -> bool:
	if zone != "SPACE":
		return false
	return dist > exclusion


static func of(zone: String, time_rate: float, cruise_ok: bool) -> String:
	if zone == "AIR":
		return AIR
	if zone == "SPACE":
		if time_rate > 1.001 and cruise_ok:
			return CRUISE
		return LOCAL
	return zone


static func must_drop(zone: String, time_rate: float, dist: float, exclusion: float) -> bool:
	return time_rate > 1.001 and not can_cruise(zone, dist, exclusion)


# If a step starts outside EZ and would enter or punch through, sit exactly on
# the shell rather than wherever a coarse dt happens to land. Position only —
# velocity is returned unchanged (2026-09-08: no hard cap). Purely geometric:
# without this snap, an interplanetary-speed straight-line step could land
# arbitrarily deep past the shell before the caller ever notices the crossing.
# Ship no longer relies on `dropped` to fire the entry handshake (that's an
# exact outside->inside edge tracked on the ship itself, docs/adr/0002 finding
# 2) — this return value is now purely "did the snap have to move you".

# Real_t is 32-bit (real_t = float), ULP ~ |value| * 1.19e-7. ENTRY uses a tight
# multiple so a genuine crossing is never misread as "already inside" (that
# swallowed ~40% of entries at Earth's shell before ship-side edge tracking
# existed). SNAP stays generous so the post-snap position reads reliably
# inside next call (anti-re-fire) even after a substep of float noise.
const SHELL_ENTRY_EPS_ULP_MULT := 2.0
const SHELL_EPS_ULP_MULT := 32.0

static func break_at_exclusion(pos: Vector3, vel: Vector3, dt: float, center: Vector3,
		ez: float) -> Dictionary:
	var miss := { "pos": pos, "vel": vel, "dropped": false, "t": 0.0 }
	if dt <= 0.0 or ez <= 0.0:
		return miss
	var w: Vector3 = pos - center
	var r0 := w.length()
	var mag := maxf(maxf(pos.length(), center.length()), ez)
	var eps := maxf(mag * 1.19e-7 * SHELL_ENTRY_EPS_ULP_MULT, 0.001)
	if r0 <= ez + eps:
		return miss
	var a := vel.length_squared()
	if a < 1.0e-16:
		return miss
	# Direction-blind was the bug: this used to cap on distance-to-shell alone,
	# so climbing away got dumped the same as diving in. d(t)^2 = |w + vel*t|^2
	# is a convex parabola in t; if the radial component (vel.dot(w)) is already
	# outward at t=0, it is provably increasing for every t>0, so an outbound
	# ship can never re-cross the shell within this straight-line step. Gate on
	# it explicitly rather than relying on that proof holding forever.
	if vel.dot(w) >= 0.0:
		return miss
	var b := 2.0 * vel.dot(w)
	var c := r0 * r0 - ez * ez
	var disc := b * b - 4.0 * a * c
	var t := -1.0
	if disc >= 0.0:
		t = (-b - sqrt(disc)) / (2.0 * a)
	var end: Vector3 = pos + vel * dt
	var ends_inside := (end - center).length() <= ez
	if t <= 0.0 or t > dt:
		if not ends_inside:
			return miss
		t = clampf((-b) / (2.0 * a), 0.00001, dt)
	var hit: Vector3 = pos + vel * t
	var n: Vector3 = hit - center
	if n.length_squared() < 1.0e-12:
		n = w
	n = n.normalized()
	# Snap a hair INSIDE the shell (generous SNAP eps, not ENTRY's tight one) so
	# the next call reads it as inside with margin to spare — anti-re-fire.
	var snap_eps := maxf(maxf(center.length(), ez) * 1.19e-7 * SHELL_EPS_ULP_MULT, 0.001)
	return { "pos": center + n * (ez - snap_eps), "vel": vel, "dropped": true, "t": t }
