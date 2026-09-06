class_name Ship
extends Node3D

const WEDGE_DESIGN := preload("res://scripts/flight/wedge_fighter.gd")
const _FM := preload("res://scripts/flight/flight_mode.gd")
# Player ship: loads a swappable GLB/OBJ (see SHIP_MODELS — the Class II cruiser
# is the default), with speed-reactive authored propulsion meshes and arcade 6DOF
# flight. If a .glb can't be loaded it falls back to a primitive fighter so the
# game never breaks. swap_ship() rebuilds the hull at runtime (used when docked).
#
# N.O.V.A.-style feel: simple to fly, momentum that eases to a stop, the hull
# banks into turns. Floating origin means we never move this node — it stays at
# (0,0,0) and only rotates; forward motion accumulates into `true_pos` and the
# world is rendered around it.
#
# fly(delta) is called by main.gd (explicit order); mouse look is read in _input.

# ============================ TWEAK ME ============================
# Ships you can fly — swap at the station. First entry is the default cruiser.
# Each model owns its booster geometry. Styling maps those named surfaces to the
# shared extremely bright, edge-faded propulsion shader; no procedural booster is built.
const SHIP_MODELS := [
	# Class II Galactic Cruiser — the default player ship. Herminio Nieves' authored
	# surfaces receive a dedicated pass: preserved textured hull/cockpit, animated
	# rainbow a1 window strip, blue engine covers, and edge-faded rear propulsion.
	# The six authored propulsion patches remain the nozzle faces and anchor matching
	# two-layer torch plumes; their positions are never randomized.
	{ "name": "Class II Galactic Cruiser", "path": "res://assets/class_ii_galactic_cruiser/Class II Gallactic Cruiser.obj", "length": 0.92, "yaw": 180.0, "pitch": 0.0, "engine_pitch": 0.88, "hp": 220, "bolt_scale": 1.35, "bolt_speed": 1250.0, "fire_cd": 0.10, "dmg": 3, "energy_max": 150.0, "energy_use": 0.72, "warp": 119.8, "light_accent": Color(0.38, 0.72, 1.0), "light_energy": 0.42, "class_ii_cruiser": true, "color_pick": true, "default_color": "silver" },
	# Snarkrans Starship — its OBJ split preserves .000 plus .010_...018 as the
	# upper booster, and .005_...035 plus .001_...034 as the lower twin boosters.
	{ "name": "Snarkrans Starship", "path": "res://assets/snarkrans_starship/spaceship.obj", "length": 0.82, "yaw": 180.0, "pitch": 0.0, "engine_pitch": 0.80, "hp": 190, "bolt_scale": 1.2, "bolt_speed": 1400.0, "fire_cd": 0.08, "dmg": 3, "energy_max": 145.0, "energy_use": 0.76, "warp": 125.0, "light_accent": Color(0.30, 0.62, 1.0), "light_energy": 0.38, "snarkrans_starship": true, "color_pick": true, "default_color": "graphite" },
	# Base Basic PBR — root.1 and root.3 are the authored twin boosters.
	{ "name": "Base Basic PBR", "path": "res://assets/base_basic_pbr.glb", "length": 0.96, "yaw": 180.0, "pitch": 0.0, "engine_pitch": 0.76, "hp": 250, "bolt_scale": 1.4, "bolt_speed": 1325.0, "fire_cd": 0.11, "dmg": 4, "energy_max": 165.0, "energy_use": 0.82, "warp": 112.0, "light_accent": Color(0.35, 0.68, 1.0), "light_energy": 0.34, "base_basic_pbr": true, "color_pick": false, "default_color": "silver" },
	# SpaceShip — JazOone / Sketchfab CC-BY. Layer_1 is five Layer_1_Material_0
	# chunks; the first two are the actual boosters and all five take the existing
	# HDR propulsion shader.
	{ "name": "SpaceShip", "path": "res://assets/jazoone_spaceship/spaceship.glb", "length": 0.90, "yaw": 0.0, "pitch": 0.0, "engine_pitch": 0.84, "hp": 210, "bolt_scale": 1.3, "bolt_speed": 1280.0, "fire_cd": 0.10, "dmg": 3, "energy_max": 155.0, "energy_use": 0.74, "warp": 118.0, "light_accent": Color(0.32, 0.70, 1.0), "light_energy": 0.36, "jazoone_spaceship": true, "color_pick": false, "default_color": "silver" },
	# Selene: ceramic interceptor with authored twin engines and exhaust.
	{ "name": "Selene", "path": "res://assets/wedge_fighter/wedge_fighter.glb", "length": 0.72, "yaw": 180.0, "pitch": 0.0, "engine_pitch": 1.08, "hp": 155, "bolt_scale": 0.9, "bolt_speed": 1500.0, "fire_cd": 0.075, "dmg": 2, "energy_max": 135.0, "energy_use": 0.62, "warp": 130.0, "light_accent": Color(0.16, 0.70, 1.0), "light_energy": 0.35, "wedge_fighter": true, "color_pick": false, "default_color": "gold" },
]

# Saved per-ship hull colours. Booster surfaces never enter the paint pass.
const SHIP_PALETTES := [
	{ "key": "rosegold", "name": "Rose Gold", "swatch": Color(0.86, 0.58, 0.52), "accent": Color(1.00, 0.88, 0.82) },
	{ "key": "blush", "name": "Blush", "swatch": Color(0.96, 0.74, 0.76), "accent": Color(1.00, 0.86, 0.88) },
	{ "key": "navy", "name": "Navy", "swatch": Color(0.16, 0.26, 0.62), "accent": Color(0.72, 0.84, 1.00) },
	{ "key": "teal", "name": "Teal", "swatch": Color(0.10, 0.66, 0.66), "accent": Color(0.72, 1.00, 0.98) },
	{ "key": "charcoal", "name": "Charcoal", "swatch": Color(0.16, 0.16, 0.18), "accent": Color(0.85, 0.90, 1.00) },
	{ "key": "emerald", "name": "Emerald", "swatch": Color(0.06, 0.52, 0.26), "accent": Color(0.80, 1.00, 0.86) },
	{ "key": "burgundy", "name": "Burgundy", "swatch": Color(0.52, 0.09, 0.19), "accent": Color(1.00, 0.84, 0.84) },
	{ "key": "silver", "name": "Steel Blue", "swatch": Color(0.42, 0.60, 0.95), "accent": Color(0.72, 0.85, 1.00) },
	{ "key": "gold", "name": "Silver", "swatch": Color(0.82, 0.84, 0.88), "accent": Color(0.90, 0.93, 1.00) },
	{ "key": "champagne", "name": "Champagne Gold", "swatch": Color(0.83, 0.69, 0.42), "accent": Color(1.00, 0.94, 0.78) },
	{ "key": "ash", "name": "Silver Ash", "swatch": Color(0.74, 0.76, 0.80), "accent": Color(0.92, 0.95, 1.00) },
	{ "key": "graphite", "name": "Graphite", "swatch": Color(0.30, 0.31, 0.34), "accent": Color(0.85, 0.90, 1.00) },
	{ "key": "onyx", "name": "Onyx Black", "swatch": Color(0.10, 0.10, 0.12), "accent": Color(0.80, 0.86, 1.00) },
]
# Camera zoom (mouse wheel)
const ZOOM_MIN := 0.45              # closest, in hull-length multiples
const ZOOM_MAX := 8.0               # farthest
const ZOOM_STEP := 0.12             # per wheel notch
# Authored `length` was ~0.6 when 1 unit was a game metre. Now 1 unit = 1 km,
# so that hull would be 600 m. Fit to this many km instead; ratios between ships stay.
const HULL_REF_LENGTH := 0.6
const HULL_KM := 0.08               # ~80 m reference craft — visible, small against Earth
# =================================================================

# --- Flight tuning ---
# Heavier hull: lower THRUST + lower DAMPING means the ship carries its momentum and
# banks into wide, curving turns instead of snapping direction (no more jig-jag).
# Cruise speed stays ~THRUST/DAMPING (≈220), but acceleration and turn-out are gentler.
const THRUST := 1650.0        # forward/back accel (units/s^2) — ×10 for the spread-out system
const STRAFE_THRUST := 1050.0 # lateral / vertical accel
const BOOST_MULT := 3.0       # Shift multiplier
const BOOST_DRAIN := 5.0      # boost energy/sec burned while boosting — very efficient, so a full
							  # tank lasts a long time and tops back up fast (combat owns the pool)
const MAX_SPEED := 10000.0
# Calm in-system cruise: sublight (non-warp) flight is capped here so you're not
# blitzing past the planets near Sol. Boost (Shift) multiplies it for fast travel.
# This is SEPARATE from warp — the per-ship ly tops are unaffected.
const SUBLIGHT_MAX := 550.0
const GRAVITY_IDLE_SPEED := 50.0   # below this, an un-thrusting ship is released from gravity (no idle drift)
# Weapons speed-lock: you can only fire at regular (sublight) speed. Holding fire force-caps
# the ship to this, so opening fire while warping/boosting drops you to combat speed.
const WEAPON_FIRE_SPEED := SUBLIGHT_MAX
# Auto-settle: close to a body, gently bleed speed toward a hover so releasing thrust
# holds you on station to capture (thrust still lets you nudge/orbit). Closer = stronger.
const SETTLE_RANGE := 900.0
const SETTLE_RATE := 1.5
# Damping vs thrust sets the real cruise speed (~THRUST/DAMPING here) — MAX_SPEED is
# just a ceiling. Lower DAMPING = more glide/momentum (the "heavy" feel).
const DAMPING := 0.75         # higher = eases to a stop faster when idle (WARP cruise tuning)
# Sublight drift: a much lighter damping used at non-warp speeds so the ship GLIDES — it
# carries momentum through turns and coasts when you ease off, instead of braking itself.
# Sublight top speed is capped (SUBLIGHT_MAX) regardless, so this only adds drift, not
# speed. At warp we blend back to DAMPING so FTL travel times stay tuned.
const DRIFT_DAMPING := 0.32
const BRAKE_RATE := 3.0       # Vela's air-brake (R): eases velocity to ~0 over ~1.5s
const STEER_SMOOTH := 9.0     # mouse-steer inertia: lower = heavier, more turn coast
const STRAFE_SMOOTH := 5.0    # A/D & up/down (strafe/lift) input inertia: lower = heavier
const MOUSE_SENS := 0.0022    # default; runtime value lives in `mouse_sens` (Settings menu)
# --- Continuous "follow-up" steering: mouse motion winds a PERSISTENT turn rate that keeps the
# ship rotating after you stop moving your hand (no rotating-forever fatigue). Move the same way
# = faster; move opposite = smoothly winds down THROUGH centre and reverses (no sticky middle —
# we deliberately do NOT snap to zero). Idle jitter under the dead zone is ignored.
const MOUSE_DEADZONE := 0.6   # px/frame below this = idle jitter, ignored (so a still hand holds the turn)
const RATE_ACCEL := 3.4       # how fast mouse motion winds the turn-rate up (× mouse_sens). Higher =
							  # the auto-rotate engages in a quick move instead of a long hold
const MAX_YAW_RATE := 3.2     # top yaw turn speed (rad/s) — higher = big turns need much less mouse
							  # sweep (fine aim is unaffected: small moves never reach the cap)
const MAX_PITCH_RATE := 2.6   # top pitch turn speed (rad/s)
const PITCH_LEVEL := 3.0      # pitch self-levels to 0 when idle (so the nose settles, never backflips)
const REVERSE_BOOST := 2.6    # (A/D keyboard) opposing the current spin winds it down this much faster
const REVERSE_BRAKE := 6.0    # mouse opposing the spin brakes it toward 0 this fast (rad/s²) — makes
							  # reversing IMMEDIATE even with a gentle move (kills full spin in ~0.27s)
const YAW_LEVEL := 2.0        # when the mouse goes idle the yaw rate COASTS to 0 this fast — the turn
							  # carries a moment (heavy-ship follow-through) then settles, so it never
							  # spins forever. Higher = stops sooner/snappier; lower = longer coast.
const YAW_KEY_RATE := 0.6     # A/D also steer the yaw from the keyboard: they INTERRUPT the mouse
							  # auto-rotate and drive the turn this fast (rad/s²) so you can break a
							  # spin and change direction with a key (they still strafe too).
const ROLL_RATE := 1.8        # manual Q/E roll (rad/s)
const FLIP_TIME := 3.4        # cinematic drift-flip duration — long & SLOW, a heavy lazy roll (W+C)
const FLIP_CRUISE := 340.0    # steady glide speed DURING the flip so it travels across space
const FLIP_SWERVE := 4.2      # peak yaw-rate of the wavey curve the glide carves (rad/s)
const FLIP_EASE := 2.2        # how gently the glide blends in/out (lower = more seamless)
const FLIP_LEAP_BOOST := 0.9  # extra speed at the START of the flip → a quick LEAP that punches
							  # out of slow-zones (the flip also BYPASSES the body speed cap)

# Warp arrival: a warp ship eases out of warp as it falls toward the nearest mark, so
# it arrives instead of blasting past (and the star has time to bloom into a sphere).
const WARP_ARRIVE_TIME := 2.0      # seconds-to-arrival at which warp starts easing out
const WARP_ARRIVE_SPEED := 400.0   # gentle speed warp bleeds down to (slow enough to scan)
const BANK_ANGLE := 0.8       # max cosmetic bank into turns (rad ≈ 46°) — a clear, visible roll
const BANK_GAIN := 0.7        # bank per unit yaw-RATE (rad/s); full bank ≈ at MAX_YAW_RATE
const BANK_SMOOTH := 5.0
# Cosmetic nose-lean into vertical mouse: a big ship doesn't snap up/down, it tips its nose
# and the whole hull leans into the climb/dive. Pure mesh tilt (heading/aim untouched), eased
# in slowly so it reads as mass, not a flick.
const LEAN_PITCH := 0.5       # max nose-lean into a climb/dive (rad ≈ 29°)
const LEAN_PITCH_GAIN := 0.6  # lean per unit pitch-RATE (rad/s)
const LEAN_SMOOTH := 4.0      # lower = heavier/slower lean (the big-ship weight)
# Cinematic cruise sway: after holding a straight line for SWAY_DELAY seconds the hull
# starts a slow, gentle roll left↔right (cosmetic, on the mesh only — the actual heading
# never changes, so you stay on the same line). Steering resets it instantly.
const SWAY_DELAY := 3.0       # seconds of straight cruise before the sway eases in
const SWAY_RAMP := 2.0        # seconds to ramp the sway from 0 → full once it begins
const SWAY_ANGLE := 0.11      # peak roll of the sway (rad ≈ 6.3°) — subtle, not a wobble
# How much the gun muzzle follows the COSMETIC bank. 0 = the bullet start point is LOCKED to
# the nose centreline and never swings left/right when you strafe/bank with A/D. (Real
# rotation — mouse aim, Q/E roll — still moves it, since that lives in transform.basis.)
const MUZZLE_BANK_FOLLOW := 0.0
# Chase offset in HULL LENGTHS, not kilometres. (0.5 up, 2.6 back) keeps an
# 80 m ship readable. Old (0.33, 1.0) was 1 km back — a speck against Earth.
const CAM_OFFSET := Vector3(0.0, 0.5, 2.6)
# Orbit the whole camera rig this many degrees so you view the ship from slightly BELOW (a low,
# heroic angle that shows a bit of the belly). + = bottom view (look up), - = top view (look down).
# Rig position + aim rotate together, so the ship stays framed where it is — only the angle shifts.
# NEGATIVE = look DOWN at the ship. At 0 the rig aims dead level, so all you see is the
# tail plate and the nozzles; the hull's whole top surface is edge-on and invisible. The
# CAM_OFFSET rise alone (0.5 up over 2.6 back) is only ~11 deg of elevation and the aim
# does not follow it. -14 puts the eye ~1.16 hull-lengths up, 2.38 back, looking down the
# spine, so you read the dorsal hull AND still see both plumes. Dial toward 0 for a flatter
# tail-chase, toward -25 for a map-like overhead.
const CAM_VIEW_PITCH_DEG := -14.0
const CAM_LAG := 6.0
# There is deliberately NO positional lag on the chase rig. One was added (the camera
# easing toward its ideal spot on its own clock, so the hull swings in frame during a
# hard turn) and removed: it reads as input lag, not as mass. The rig stays welded to
# the hull and only its BASIS lags, via CAM_LAG above.
# Free-look (hold RMB or T): mouse orbits the camera instead of steering; the ship
# holds its heading and flies on. Released, the view eases back behind the ship.
const LOOK_YAW_LIMIT := 2.7     # how far around the ship the view can swing (rad)
const LOOK_PITCH_LIMIT := 1.2   # how far up/down (rad)
const LOOK_RETURN := 8.0        # how fast the view snaps to target / eases back home
const FOV_BASE := 70.0
const FOV_KICK := 14.0        # extra FOV at full speed (sense of speed) — gentle

# --- Chase fill light ---
# The scene sun (main.gd, energy 1.05) comes from wherever the real Sun is, so on any
# heading that flies away from it the whole visible side of the hull falls to the 0.35
# counter-fill and 0.2 ambient — a black silhouette with two bright nozzles. This is ONE
# DirectionalLight3D parented to the chase camera, cull-masked to ShipMesh.SHIP_FILL_LAYER,
# so it lifts the hull and touches nothing else in the scene.
# It is DIRECTIONAL on purpose. The three OmniLight3Ds that used to sit a few metres off
# the hull (see _build_ship_model) clipped their own specular on polished metal and blew
# the engine bay to white; a directional light has no distance falloff to blow out, and
# HULL_FILL_SPECULAR keeps the highlight contribution near zero so only diffuse lifts.
const HULL_FILL_ENERGY := 0.85           # >0 lifts the shadow side; 0.0 disables the light
const HULL_FILL_COLOR := Color(0.72, 0.80, 0.95)   # cool starlight, not a warm second sun
const HULL_FILL_SPECULAR := 0.12         # near-zero: diffuse lift without a hotspot
# Where it sits relative to the CAMERA (not the ship): swung off-axis so the hull gets a
# lit side and a darker side. Dead-on (0, 0) is flat and kills the panel detail.
const HULL_FILL_YAW_DEG := -32.0         # - = from the camera's left
const HULL_FILL_PITCH_DEG := -24.0       # - = from above, shining down onto the top surface

# --- State ---
var velocity := Vector3.ZERO
var true_pos := Vector3.ZERO   # absolute position in game units (floating origin)
var speed_limit := INF         # set by main from PlanetSystem; eases us down near a body
# The nearest body's shared height function, assigned by main each frame. The SAME
# instance the ground rings and the contact kill use - three readers, one function.
var terrain: TerrainSampler
var nearest_dir := Vector3.ZERO  # toward nearest body; we only ease down when approaching it
var nearest_name := ""           # body F10 / tape use (Sun when you're at the Sun)
var nearest_dist := INF        # distance to nearest body; set by main (warp arrival ease-out)
var nearest_radius := 1.0      # visual/physical radius of that body (km)
var flight_mode := "LOCAL"     # LOCAL | CRUISE | AIR (or SKIN/INSIDE/CENTER)
var drop_flash := 0.0          # seconds of DROP cue after hitting an EZ
const DROP_FLASH_SECS := 0.4
var star_field_dist := 0.0     # distance to this system's star; set by main (FTL gate; 0 = locked until known)
var struct_limit := INF        # strict sublight cap near stations/probes; set by main from props
var gravity := Vector3.ZERO    # set by main from PlanetSystem; pull toward bodies
var newton := false            # Sol 1:1: real GM/r², no arcade cancel, no vacuum damp
var time_rate := 1.0           # Sol coast warp (1 / 5 / 10 / 50 / 100 / 1000)
var debug_toast := ""          # one-shot note for the HUD (F6/F7/F9 snaps)
var dev_speed := false         # Sol debug: fat engines + burn-warp so GEO is reachable
var _fp := []                  # last ~15s of Sol samples; F4 dumps
var _fp_t := 0.0
const _FP_PATH := "user://sol_footprint.jsonl"
const _FP_PATH2 := "/tmp/astryx_sol_footprint.jsonl"
const _FP_KEEP := 15.0
var _time_idx := 0
const TIME_RATES := [1.0, 5.0, 10.0, 50.0, 100.0, 1000.0, 10000.0, 100000.0]
var dock_approach := 0.0       # 0 outside the station's landing zone, 1 at the pad; set by main
var frozen := false            # docked at a station — motion held, mouse freed
var transiting := false        # in a wormhole tunnel — motion held, view locked forward
var camera: Camera3D           # assigned by main; driven from fly()
@onready var audio := GameAudio   # autoload; the engine voice is driven from fly()
var mouse_sens := MOUSE_SENS   # live mouse sensitivity (Settings menu adjusts this)
var warp := 1.0                # per-ship MAX speed multiplier; >1 = breaks physics (Vela)
var has_galactic_drive := false  # this hull can run the galactic drive (Vela Iron Pulse)
# Live core-distance scanner (only meaningful on the Iron Pulse). main feeds these from the
# GalaxyModel each frame so the HUD can read total + remaining distance to the core in real time.
var core_total_ly := 0.0       # full distance of the voyage (≈ 26,000 ly)
var core_dist_ly := 0.0        # distance still to go right now (shrinks as you fly the drive)
var _warp_charge := 0.0        # 0..1 spool-up; ramps while thrusting forward
var fire_cooldown := 0.22      # seconds between shots (combat reads this)
var max_hp := 100              # this hull's defence / hull integrity (combat reads this)
var bolt_speed := 950.0        # this hull's bullet velocity (combat reads this)
var bolt_scale := 1.0          # this hull's bullet size multiplier (combat reads this)
var bolt_damage := 1           # damage per bolt (combat reads this) — Lyra's hit hard
var bolt_laser := false        # bolts render as red laser beams (Lyra) — combat reads this
var bolt_strong := false       # extra-bright/strong bolt material (HaniStar) — combat reads this
var energy_max := 100.0        # per-ship energy cap (both bars); combat reads this
var energy_use := 1.0          # per-ship consume multiplier; combat + boost read this
var can_fire := true           # false for utility hulls (no weapons) — combat reads this
var locked := false            # skin-kill cutscene: no thrust, no steer, camera stays
var has_laser := false         # right-click nose laser beam (Raptor 2 Neo) — combat reads this
var laser_offset := Vector3.ZERO   # local muzzle offset for the beam (x=right, y=up)
var auto_capture := false       # captures bodies in range automatically (no V) — Raptor 2 Neo
var combat_lock := false        # set by main while in combat — no interstellar/FTL speed
var firing := false             # set by main while holding fire — force-caps to combat speed
var touch_fire := false         # mobile: the on-screen FIRE button (NOT the emulated mouse, which
								# every touch would otherwise trigger) — main reads this on touch builds
var combat_ref: Node                   # set by main — owns the shared energy pools
var _boost_starved := false            # true while boosting on an empty tank -> plume sputters
var is_boosting := false               # true while boost is actually engaged (combat pauses boost regen)
var boost_blocked := false             # true when Shift pressed in a slow-zone (boost unavailable)
var auto_cruise := false        # Num Lock: hold W+Shift hands-free (forward thrust + boost)
var autopilot := false          # hands-off cinematic flight to autopilot_target (M-map)
var autopilot_target := Vector3.ZERO   # world position to fly to
var autopilot_name := ""        # body the autopilot is bound to (main refreshes the target)
const AP_ARRIVE := 600.0        # stop autopilot within this distance of the target
const AP_TURN := 2.5            # autopilot turn rate toward the target
var muzzle := 2.5              # forward distance bolts spawn at — this hull's nose tip
var muzzle_drop := 0.0         # how far BELOW the nose bolts emerge (set per hull from its height)
# Warp multiplies cruise speed. The REAL top speed is the terminal velocity THRUST·warp/DAMPING
# (the cap = MAX_SPEED·warp is just a ceiling and isn't reached) — so, with 1 ly = 6.32M units,
# time per ly ≈ UNITS_PER_LY·DAMPING / (THRUST·warp) = 2874.6 / warp seconds (W-cruise, no boost;
# Shift/auto-cruise boost ×3 is ~3× faster). Each authored hull supplies its own `warp` value.
const HYPERSONIC_SPEED := 15000.0   # above this a warp ship is "hypersonic" (no combat)
const WARP_FLOOR := 1.0        # zero-charge = calm sublight; holding W spools up to warp
# FTL gate: warp can only spool up once you're beyond the system star's gravity field.
# Inside this radius you fly normal sublight cruise no matter the hull.
const SOL_FIELD_RADIUS := 2200.0
const WARP_CHARGE_TIME := 9.0  # seconds of thrust to reach full warp
const WARP_DECAY_TIME := 3.5   # seconds to spool back down when you ease off

# --- Galactic drive (Vela Iron Pulse only) ---
# The pilgrimage to the Milky Way's core (~26,000 ly). It is NOT a translation speed tier — flying
# the real distance at that speed shatters float precision and piles up across saves. Instead the
# galaxy backdrop LOOMS in toward the core at a fixed pace (galactic_loom_rate → main → galaxy),
# decoupled from how fast the ship actually moves. She still flies normal space at her own warp;
# this just advances the bounded voyage. Only while in deep space (warp_ready) and spooled up.
const GALACTIC_SEC_PER_LY := 0.08      # LOCKED voyage pace — the tuned 0.08 s/ly (do not drift)
const GALACTIC_LOOM_LY_PER_S := 1.0 / GALACTIC_SEC_PER_LY   # = 12.5 ly/s → ~26,000 ly in ~34.7 min
const GALACTIC_TEST_MULT := 1.0  # ⚠ TEST ONLY — set back to 1.0 before shipping. 10× the loom
								  # → core run in ~3.5 min instead of ~35, so the voyage is testable.

# Station landing zone: speed is force-reduced as you near the pad so you can
# actually land — applies to ALL ships, warp included. Fed by main via dock_approach.
const DOCK_EDGE_SPEED := 1000.0    # speed cap at the outer edge of the zone (gentle entry)
const DOCK_PLATFORM_SPEED := 60.0  # speed cap right at the pad (smooth final approach)
const DOCK_SPIN := 0.5             # showroom turntable spin (rad/s) while docked
# Cd*A/m for a dense craft (m²/kg). Converts to km/s² via 500 * B * ρ * v².
const NEWTON_BALLISTIC := 0.005
# Sol engines: a few g. 2 g main beats Earth at the ground; drag sets air cruise ~80 m/s.
const NEWTON_G := 0.00981          # 1 g in km/s²
const NEWTON_THRUST := 0.01962     # 2 g
const NEWTON_STRAFE := 0.00981     # 1 g
const DEV_THRUST_MULT := 10000000.0   # F9: ~20 s GEO→skin if you burn. Dies in air.

# True when a warp ship is blazing fast — combat + crosshair are disabled.
func is_hypersonic() -> bool:
	return warp > 1.0 and velocity.length() > HYPERSONIC_SPEED

# This hull can build full FTL right now: it has a warp drive AND it's clear of every
# force-slow safe-zone (deep space). Near a star/planet the zone caps your speed.
func warp_ready() -> bool:
	return (not newton) and warp > 1.0 and is_inf(speed_limit)

# In open/FTL deep space: every speed cap (body gravity zone, station/probe/wormhole
# slow-zone) is lifted. This is the "interstellar" signal the music state machine reads.
func in_open_space() -> bool:
	return is_inf(speed_limit) and is_inf(struct_limit)


func _debug_circularize() -> void:
	var r := true_pos.length()
	var min_r := Ephemeris.EARTH_RADIUS_KM + HULL_KM + 50.0
	if r < min_r:
		debug_toast = "F6  too low to circle"
		return
	var radial := true_pos / r
	var tang: Vector3 = velocity - radial * velocity.dot(radial)
	if tang.length_squared() < 0.0001:
		tang = radial.cross(Vector3.UP)
	if tang.length_squared() < 0.0001:
		tang = radial.cross(Vector3.RIGHT)
	var v_c := sqrt(Ephemeris.GM_EARTH / r)
	velocity = tang.normalized() * v_c
	_time_idx = 0
	time_rate = 1.0
	debug_toast = "F6  circle  %s" % _debug_speed_txt(v_c)


func _debug_geo_park() -> void:
	true_pos = Ephemeris.geo_start_pos()
	velocity = Vector3.ZERO
	face_toward(-true_pos)
	_kill_turn_rates()
	_time_idx = 0
	time_rate = 1.0
	debug_toast = "F7  parked GEO"


func _debug_toggle_dev_speed() -> void:
	dev_speed = not dev_speed
	if dev_speed:
		debug_toast = "F9  DEV on  ×%.0f engines" % DEV_THRUST_MULT
	else:
		debug_toast = "F9  DEV off"


func _debug_face_earth() -> void:
	var look := nearest_dir
	var who := nearest_name
	if look.length_squared() < 0.0001:
		if true_pos.length_squared() < 0.001:
			debug_toast = "F10  no body"
			return
		look = -true_pos
		who = "Earth"
	face_toward(look)
	_kill_turn_rates()
	velocity = Vector3.ZERO
	debug_toast = "F10  nose at %s  ·  speed 0" % who


func _footprint_tick(delta: float, w_on: bool, s_on: bool) -> void:
	_fp_t += delta
	var r := true_pos.length()
	var earth := (-true_pos / r) if r > 0.001 else Vector3.FORWARD
	var rdot := velocity.dot(true_pos / r) if r > 0.001 else 0.0
	var nose := (-transform.basis.z).dot(earth)
	var cam_dot := 0.0
	if camera != null:
		cam_dot = (-camera.global_transform.basis.z).dot(earth)
	_fp.append({
		"t": snappedf(_fp_t, 0.01),
		"alt": snappedf(r - Ephemeris.EARTH_RADIUS_KM, 0.1),
		"rdot": snappedf(rdot, 0.001),
		"nose": snappedf(nose, 0.001),
		"cam": snappedf(cam_dot, 0.001),
		"prate": snappedf(_pitch_rate, 0.001),
		"yrate": snappedf(_yaw_rate, 0.001),
		"w": w_on,
		"s": s_on,
		"spd": snappedf(velocity.length(), 0.001),
		"dev": dev_speed,
	})
	var cut := _fp_t - _FP_KEEP
	while _fp.size() > 0 and float(_fp[0].t) < cut:
		_fp.remove_at(0)


func _dump_footprint() -> void:
	var f := FileAccess.open(_FP_PATH, FileAccess.WRITE)
	var f2 := FileAccess.open(_FP_PATH2, FileAccess.WRITE)
	if f == null and f2 == null:
		debug_toast = "F4  footprint write failed"
		return
	for row in _fp:
		var line := JSON.stringify(row)
		if f != null:
			f.store_line(line)
		if f2 != null:
			f2.store_line(line)
	if f != null:
		f.close()
	if f2 != null:
		f2.close()
	var last: Dictionary = _fp.back() if _fp.size() > 0 else {}
	var tag := "out" if float(last.get("rdot", 0.0)) > 0.0 else "in"
	debug_toast = "F4  dumped %d samples  %s  nose %.2f" % [_fp.size(), tag, float(last.get("nose", 0.0))]


func _debug_speed_txt(km_s: float) -> String:
	if km_s < 1.0:
		return "%.0f m/s" % (km_s * 1000.0)
	return "%.2f km/s" % km_s


func _clamp_time_warp(thrusting: bool, is_braking: bool) -> void:
	if not newton:
		_time_idx = 0
		time_rate = 1.0
		flight_mode = _FM.LOCAL
		return
	var who := nearest_name if nearest_name != "" else "Earth"
	var dist := nearest_dist if nearest_name != "" and nearest_dist < INF else true_pos.length()
	var zone := Ephemeris.flight_zone(who, dist)
	var rad: float = nearest_radius if nearest_radius > 1.0 else Ephemeris.body_radius_km(who)
	var ez: float = _FM.exclusion_from_center(rad, Ephemeris.atmo_top_km(who), _nearest_is_star())
	var cruise_ok: bool = _FM.can_cruise(zone, dist, ez)
	var was_cruise := time_rate > 1.001
	# DEV speed is for closing 42,000 km. Honest warp still dies on burn; this does not.
	# EZ: cruise never punches a world (Earth air, moon bubble, 1.2 R star).
	if (thrusting and not dev_speed) or is_braking or not cruise_ok:
		if was_cruise and not cruise_ok:
			drop_flash = DROP_FLASH_SECS
		_time_idx = 0
		time_rate = 1.0
	else:
		time_rate = TIME_RATES[_time_idx]
	flight_mode = _FM.of(zone, time_rate, cruise_ok)


func _nearest_is_star() -> bool:
	if nearest_name == "":
		return false
	for p in Ephemeris.PLANETS:
		if str(p.name) == nearest_name:
			return bool(p.get("star", false))
	return false


func _exclusion_who() -> String:
	return nearest_name if nearest_name != "" else "Earth"


func _exclusion_km() -> float:
	var who := _exclusion_who()
	var rad: float = nearest_radius if nearest_radius > 1.0 else Ephemeris.body_radius_km(who)
	return _FM.exclusion_from_center(rad, Ephemeris.atmo_top_km(who), _nearest_is_star())


func _exclusion_center() -> Vector3:
	if nearest_dir.length_squared() < 0.0001 or nearest_dist >= INF:
		return Vector3.ZERO
	return true_pos + nearest_dir.normalized() * nearest_dist


func _cruise_ok_now() -> bool:
	var who := _exclusion_who()
	var dist := nearest_dist if nearest_name != "" and nearest_dist < INF else true_pos.length()
	return _FM.can_cruise(Ephemeris.flight_zone(who, dist), dist, _exclusion_km())


func _newton_g() -> Vector3:
	var g := Vector3.ZERO
	for p in Ephemeris.PLANETS:
		if p.get("craft", false):
			continue
		var mu: float = Ephemeris.gm(str(p.name))
		if mu <= 0.0:
			continue
		var bpos: Vector3 = Vector3.ZERO if p.get("fixed", false) else Ephemeris.scene_pos(str(p.name))
		var rel: Vector3 = bpos - true_pos
		var d := rel.length()
		if d > 0.001:
			g += (rel / d) * (mu / (d * d))
	return g


func _newton_advance(sim: float) -> void:
	var left := sim
	while left > 0.00001:
		var alt := true_pos.length() - Ephemeris.EARTH_RADIUS_KM
		var in_air := alt < Ephemeris.EARTH_ATMO_TOP_KM
		if in_air:
			_time_idx = 0
			time_rate = 1.0
		var dt := minf(left, 0.05 if in_air else 0.25)
		# Dump to the band cap for the shell's own altitude rather than to a dead
		# stop, so crossing an exclusion shell reads as entering atmosphere instead
		# of hitting a wall. See FlightMode.break_at_exclusion.
		var ez_km: float = _exclusion_km()
		var ez_who := _exclusion_who()
		var ez_rad: float = nearest_radius if nearest_radius > 1.0 \
			else Ephemeris.body_radius_km(ez_who)
		var shell_alt: float = maxf(ez_km - ez_rad, 0.2)
		var hit: Dictionary = _FM.break_at_exclusion(
			true_pos, velocity, dt, _exclusion_center(), ez_km,
			_FM.band_speed_cap_units(shell_alt))
		if bool(hit.dropped):
			true_pos = hit.pos
			velocity = hit.vel
			_time_idx = 0
			time_rate = 1.0
			drop_flash = DROP_FLASH_SECS
			break
		velocity += _newton_g() * dt
		_newton_atmo_drag(dt)
		true_pos += velocity * dt
		_newton_ground()
		_newton_corotate(dt)
		left -= dt


func _newton_atmo_drag(delta: float) -> void:
	var r := true_pos.length()
	var alt := r - Ephemeris.EARTH_RADIUS_KM
	if alt >= Ephemeris.EARTH_ATMO_TOP_KM or alt < 0.0:
		return
	var rho := Ephemeris.RHO0 * exp(-alt / Ephemeris.EARTH_ATMO_H_KM)
	var spd := velocity.length()
	if spd < 1e-8:
		return
	var acc := 500.0 * NEWTON_BALLISTIC * rho * spd * spd
	velocity = velocity.move_toward(Vector3.ZERO, acc * delta)


func reset_mesh_pose() -> void:
	if _mesh_root != null:
		_mesh_root.rotation = Vector3.ZERO


func _newton_corotate(dt: float) -> void:
	# Inside the air the ship rides with Earth. You should not see the ground race.
	var alt := true_pos.length() - Ephemeris.EARTH_RADIUS_KM
	if alt >= Ephemeris.EARTH_ATMO_TOP_KM:
		return
	var ang := Ephemeris.spin_rad_s("Earth") * dt
	if absf(ang) < 1.0e-12:
		return
	true_pos = true_pos.rotated(Vector3.UP, ang)
	velocity = velocity.rotated(Vector3.UP, ang)
	rotate(Vector3.UP, ang)
	_cam_basis = _cam_basis.rotated(Vector3.UP, ang)


func _newton_ground() -> void:
	# Backstop so a physics substep can never put the hull INSIDE the rock. This
	# used to pin at a flat 6400 km from Earth's centre, which is 29 km altitude -
	# an independent blocker on the Earth flyover: removing the kill bubble alone
	# would still have stopped every descent 29 km up and looked like the band was
	# broken. Now it pins at the terrain beneath you plus the contact margin, so the
	# swept kill in main._update_skin_kill sees contact and fires.
	#
	# true_pos is Earth-centred (Earth is the origin anchor), so this clamp is
	# Earth's. Other bodies are handled by the kill itself, which works in each
	# body's own frame.
	var r := true_pos.length()
	if r < 0.001:
		return
	var n := true_pos / r
	var contact: float = Ephemeris.surface_kill_km("Earth")
	var min_r: float = Ephemeris.EARTH_RADIUS_KM + contact
	if terrain != null:
		min_r = terrain.ground_radius_km(n, Ephemeris.EARTH_RADIUS_KM) + contact
	if r >= min_r:
		return
	true_pos = n * min_r
	var inward := velocity.dot(n)
	if inward < 0.0:
		velocity -= n * inward

# True while the galactic drive is carrying us — the drive hull, spooled up, in clear deep space.
# main uses it to loom the core; the HUD uses it for the drive readout; streaks use it for the blur.
func galactic_cruising() -> bool:
	return has_galactic_drive and warp_ready() and _warp_charge > 0.02

# Signed ly/s the galactic core looms this frame: the LOCKED voyage pace (0.08 s/ly × test mult),
# its sign set by whether she's heading toward the core (+ = approach) or away (− = recede). It is
# NOT scaled by spool/throttle — once she's cruising the drive, the pace is the locked 0.08 s/ly,
# full stop. DECOUPLED from her real translation speed, so the ~26,000 ly haul is a bounded illusion
# that never moves true_pos. main feeds this to galaxy.advance_ly each frame.
func galactic_loom_rate() -> float:
	if not galactic_cruising() or velocity.length() < 1.0:
		return 0.0
	var heading := signf(velocity.normalized().dot(GalaxyModel.DIR.normalized()))
	return GALACTIC_LOOM_LY_PER_S * GALACTIC_TEST_MULT * heading

var _current_model := 0        # index into SHIP_MODELS
var _color_choice := {}        # ship name -> palette key
var _finish_choice := {}       # ship name -> "metallic" | "glassy"
var _engine_pitch := 1.0       # per-ship engine voice character (set on build)
var _mesh_root: Node3D
var _engine_mat: StandardMaterial3D   # only used by the primitive fallback
# Cold end of the exhaust temperature ramp, matched to cruiser_torch's cool_color.
const ENGINE_COOL := Color(1.0, 0.33, 0.06)
# Ceiling on the `power` value handed to the booster shaders. `power` used to map onto
# 0.42..1.0, which put ORDINARY CRUISE (no Shift) at 0.61 and full boost at 0.90 - so
# un-boosted flight already sat near the top of the brightness ramp and Shift added
# almost nothing. 0.75 pulls the whole curve down so full boost now lands roughly where
# un-boosted cruise used to be, and cruise sits well below that. Colour is unaffected:
# the orange -> white -> blue ramp is driven by `temperature`, not by this.
const POWER_CEIL := 0.75

var _propulsion_power := 0.0           # smoothed authored-mesh power (speed driven)
var _propulsion_surge := 0.0           # decaying kick applied when throttle is punched
var _authored_propulsion: Array[ShaderMaterial] = [] # Authored rear meshes; speed-reactive
var _torch_materials: Array[ShaderMaterial] = []     # Torch cones only; these reshape
var _nozzle_lights: Array[OmniLight3D] = []          # Real light the plume cannot emit
var _hull_fill: DirectionalLight3D                   # Chase fill; parented to the camera
var _engine_accent := Color(0.35, 0.70, 1.0)         # Hot-end exhaust colour for lights
var _streaks: GPUParticles3D          # motion streaks at high speed
var _streak_mat: StandardMaterial3D
var _cam_zoom := 1.0          # target zoom (mouse wheel)
var _cam_zoom_smooth := 1.0   # eased toward _cam_zoom
var _hull_km := HULL_KM       # live fitted hull length (km); camera sits in hull-lengths
var _cam_basis := Basis()
var _bank := 0.0
var _lean := 0.0              # eased cosmetic nose-lean into a climb/dive (mesh-only)
var _flip_t := 0.0            # remaining cinematic flip time (0 = not flipping)
var _flip_dir := 1.0          # +1 roll/drift right · -1 left
var _flip_yaw := 0.0          # accumulated swerve of the drift heading during the flip
var _cruise_t := 0.0           # seconds held on a straight cruise (drives the cinematic sway)
var _mouse_delta := Vector2.ZERO
var _steer := Vector2.ZERO     # eased mouse-steer (rotational inertia for curving turns)
var _yaw_rate := 0.0           # yaw turn-rate (rad/s) — eases to 0 when the mouse is idle (heading-hold)
var _pitch_rate := 0.0         # pitch turn-rate (rad/s) — self-levels to 0 when the mouse is idle
var _strafe := 0.0             # eased A/D lateral input (heavy, drifting thrust)
var _lift := 0.0              # eased Space/Ctrl vertical input
var _mouse_captured := false
var _free_look := false       # true while RMB or T is held
var _look_yaw := 0.0          # target orbit angles (set in fly)
var _look_pitch := 0.0
var _look_yaw_s := 0.0        # smoothed orbit angles actually applied to the camera
var _look_pitch_s := 0.0


func _ready() -> void:
	_build_visual()
	_set_capture(true)
	_cam_basis = transform.basis  # seed so the first frame isn't a lurch


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _mouse_captured:
		_mouse_delta += event.relative
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_zoom = clampf(_cam_zoom - ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_zoom = clampf(_cam_zoom + ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
		elif not _mouse_captured and not frozen:
			_set_capture(true)
	elif event is InputEventKey and event.pressed and not event.echo and newton:
		if event.keycode == KEY_PERIOD or event.keycode == KEY_BRACKETRIGHT:
			_time_idx = mini(_time_idx + 1, TIME_RATES.size() - 1)
			time_rate = TIME_RATES[_time_idx]
		elif event.keycode == KEY_COMMA or event.keycode == KEY_BRACKETLEFT:
			_time_idx = maxi(_time_idx - 1, 0)
			time_rate = TIME_RATES[_time_idx]
		elif event.keycode == KEY_F6:
			_debug_circularize()
		elif event.keycode == KEY_F7:
			_debug_geo_park()
		elif event.keycode == KEY_F9:
			_debug_toggle_dev_speed()
		elif event.keycode == KEY_F10:
			_debug_face_earth()
		elif event.keycode == KEY_F4:
			_dump_footprint()
	# (Esc is owned by the Settings menu — opens/closes it and frees the cursor.)

# Touch look: the on-screen drag region feeds steering here (same pipeline as mouse-look,
# but with no mouse capture, which phones don't have). Called by TouchControls.
func add_touch_look(v: Vector2) -> void:
	_mouse_delta += v


# Called every frame by main.gd, before the world is rebuilt around the ship.
func fly(delta: float) -> void:
	# Wormhole transit: motion held, view locked forward, streaks at full tilt.
	if transiting:
		velocity = Vector3.ZERO
		_mouse_delta = Vector2.ZERO
		_steer = Vector2.ZERO
		_strafe = 0.0
		_lift = 0.0
		_look_yaw = 0.0
		_look_pitch = 0.0
		_yaw_rate = 0.0
		_pitch_rate = 0.0
		_bank = 0.0
		_lean = 0.0
		# Face the nose INTO the tunnel (the tunnel renders ahead at local -Z). Flip 180°
		# so the ship dives forward instead of riding through tail-first. The hull holds
		# STABLE facing the portal — only a faint breathing roll/pitch so it isn't dead
		# (yaw stays exactly PI so the nose points dead-on). (Reset to 0 on normal path.)
		var wob := Time.get_ticks_msec() * 0.001
		_mesh_root.rotation = Vector3(
			sin(wob * 0.7) * 0.012, PI, sin(wob * 0.5) * 0.018)
		_update_authored_propulsion(0.4, delta) # engines low — calm, not hypersonic
		_update_streaks(SUBLIGHT_MAX * 0.7)     # restrained streaks — dark, not warp-busy
		_update_camera(delta)
		if audio:
			audio.engine_off()   # silent in the wormhole
		return

	# Skin-kill cutscene: hull is already lost. Tumble, no thrust.
	if locked:
		velocity = Vector3.ZERO
		_mouse_delta = Vector2.ZERO
		_steer = Vector2.ZERO
		_strafe = 0.0
		_lift = 0.0
		_look_yaw = 0.0
		_look_pitch = 0.0
		_yaw_rate = 0.0
		_pitch_rate = 0.0
		if _mesh_root != null:
			_mesh_root.rotate_y(2.6 * delta)
			_mesh_root.rotate_x(1.5 * delta)
			_mesh_root.rotate_z(0.9 * delta)
		_update_authored_propulsion(0.15, delta)
		_update_streaks(0.0)
		_update_camera(delta)
		if audio:
			audio.engine_off()
		return

	# Docked: hold position, idle the propulsion, keep the camera steady, and slowly
	# turntable the hull so the ship is clearly on show while you pick one.
	if frozen:
		velocity = Vector3.ZERO
		_mouse_delta = Vector2.ZERO
		_steer = Vector2.ZERO
		_strafe = 0.0
		_lift = 0.0
		_look_yaw = 0.0
		_look_pitch = 0.0
		_yaw_rate = 0.0
		_pitch_rate = 0.0
		_bank = 0.0
		_lean = 0.0
		_mesh_root.rotate_y(DOCK_SPIN * delta)
		_update_authored_propulsion(0.0, delta)
		_update_streaks(0.0)   # docked — no motion streaks
		_update_camera(delta)
		if audio:
			audio.engine_off()   # engine cut while docked
		return

	# --- Look vs. steer ---
	# HOLD RMB or T for free-look: the mouse orbits the camera (full 360°) around the ship
	# while it keeps flying. Release to steer normally again.
	# (On laser ships RMB fires the nose beam instead, so free-look there is T-only.)
	_free_look = (Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not has_laser) \
		or Input.is_physical_key_pressed(KEY_T)
	var md := _mouse_delta
	_mouse_delta = Vector2.ZERO
	var turn := 0.0   # this frame's mouse yaw (drives cosmetic banking below)
	var lean := 0.0   # this frame's mouse pitch (drives the cosmetic nose-lean below)
	var attitude_before := transform.basis

	if autopilot:
		_autopilot_steer(delta)
		_steer = Vector2.ZERO
		_yaw_rate = 0.0
		_pitch_rate = 0.0
		_look_yaw = 0.0
		_look_pitch = 0.0
	elif _free_look:
		_steer = Vector2.ZERO
		_yaw_rate = 0.0
		_pitch_rate = 0.0
		_look_yaw -= md.x * mouse_sens
		_look_pitch = clampf(_look_pitch - md.y * mouse_sens, -LOOK_PITCH_LIMIT, LOOK_PITCH_LIMIT)
	else:
		# Heading steering with inertia: mouse motion winds a turn rate (so it has weight and curves),
		# but when you STOP moving, the rate eases back to 0 — the ship SETTLES on its heading instead
		# of spinning forever. So you can fix a direction; a stray nudge just nudges, it can't lock a
		# runaway spin. Reversing brakes hard so flipping direction is immediate. Idle jitter ignored.
		if absf(md.x) > MOUSE_DEADZONE:
			if _yaw_rate * md.x < 0.0:
				_yaw_rate = move_toward(_yaw_rate, 0.0, REVERSE_BRAKE * delta)
			_yaw_rate = clampf(_yaw_rate + md.x * mouse_sens * RATE_ACCEL, -MAX_YAW_RATE, MAX_YAW_RATE)
		else:
			# Mouse idle → settle: ease the turn rate to 0 so the ship holds its heading.
			_yaw_rate = lerpf(_yaw_rate, 0.0, clampf(YAW_LEVEL * delta, 0.0, 1.0))
		# A/D INTERRUPT the auto-rotate and steer the yaw directly — break a spin and change
		# direction from the keyboard. Opposing the current spin winds it down/reverses faster.
		var kyaw := 0.0
		if Input.is_physical_key_pressed(KEY_A):
			kyaw -= 1.0
		if Input.is_physical_key_pressed(KEY_D):
			kyaw += 1.0
		if kyaw != 0.0:
			var kax := YAW_KEY_RATE * (REVERSE_BOOST if _yaw_rate * kyaw < 0.0 else 1.0)
			_yaw_rate = clampf(_yaw_rate + kyaw * kax * delta, -MAX_YAW_RATE, MAX_YAW_RATE)
		if absf(md.y) > MOUSE_DEADZONE:
			_pitch_rate = clampf(_pitch_rate + md.y * mouse_sens * RATE_ACCEL, -MAX_PITCH_RATE, MAX_PITCH_RATE)
		else:
			_pitch_rate = lerpf(_pitch_rate, 0.0, clampf(PITCH_LEVEL * delta, 0.0, 1.0))
		turn = _yaw_rate     # banking reads the turn RATE (rad/s) so the bank holds with the turn
		lean = _pitch_rate
		rotate_object_local(Vector3.UP, -_yaw_rate * delta)
		rotate_object_local(Vector3.RIGHT, -_pitch_rate * delta)
		var roll := 0.0
		if Input.is_physical_key_pressed(KEY_Q):
			roll += 1.0
		if Input.is_physical_key_pressed(KEY_E):
			roll -= 1.0
		rotate_object_local(Vector3.BACK, roll * ROLL_RATE * delta)
		orthonormalize()  # scrub float drift out of the basis over time
		_look_yaw = 0.0
		_look_pitch = 0.0
		# Sol: a turn is a turn. Carry speed with the hull so the nose and the path match.
		if newton:
			velocity = TurnCarry.apply(velocity, attitude_before, transform.basis)

	# --- Thrust (local axes -> world via current basis) ---
	# Shift = boost, draining the shared boost pool (owned by combat). It only ENGAGES
	# (and only burns energy) when the boost can actually push you faster — i.e. you're
	# NOT pinned by a star/station slow-zone. Pressing Shift in a slow-zone does nothing
	# and costs nothing.
	var boost := 1.0
	var be: float = combat_ref.boost_energy if combat_ref != null else 1.0
	var boost_effective := minf(speed_limit, struct_limit) >= SUBLIGHT_MAX
	var want_boost := Input.is_physical_key_pressed(KEY_SHIFT) or auto_cruise
	is_boosting = false
	# Pressed Shift where boost can't help (a slow-zone) -> tell the player, cost nothing.
	boost_blocked = want_boost and not boost_effective
	if want_boost and be > 0.0 and boost_effective:
		boost = BOOST_MULT
		is_boosting = true
		if combat_ref != null:
			combat_ref.boost_energy = maxf(combat_ref.boost_energy - BOOST_DRAIN * energy_use * delta, 0.0)
	# Plume only chokes if you're trying to boost effectively but the tank is empty.
	_boost_starved = want_boost and boost_effective and be <= 0.0
	var fwd := 0.0
	var strafe := 0.0
	var lift := 0.0
	# S is reverse thrust on every hull — with the heavier flight model
	# you need to be able to back off and reposition. In Sol, S is a brake instead:
	# reverse-along-nose while facing Earth is an outbound burn and feels like "S
	# takes me away".
	if Input.is_physical_key_pressed(KEY_W) or auto_cruise:
		fwd -= 1.0
	if Input.is_physical_key_pressed(KEY_S) and not newton:
		fwd += 1.0
	# Honest Sol uses S as a brake (see dump: turn-away leftover).
	var braking := newton and Input.is_physical_key_pressed(KEY_S)
	if Input.is_physical_key_pressed(KEY_A):
		strafe -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		strafe += 1.0
	if Input.is_physical_key_pressed(KEY_SPACE):
		lift += 1.0
	if Input.is_physical_key_pressed(KEY_CTRL):
		lift -= 1.0

	# FTL: every hull can spool warp by holding W. There's no gate — instead the
	# force-slow safe-zones around stars/planets cap your speed when you're near them,
	# so you naturally drop out of warp near a body and fly free in the deep.
	# Auto-pilot drives forward at warp toward the target (overrides manual thrust).
	if autopilot:
		fwd = -1.0
		strafe = 0.0
		lift = 0.0
		braking = false
	var eff_warp := 1.0
	# Every hull (the Iron Pulse included) translates at its OWN warp here — fast, but a sane,
	# bounded coordinate rate. Her dramatic galactic SPEED is not a translation tier; it's the
	# core-voyage looming (see galactic_loom_rate + main), which is decoupled from true_pos so the
	# ~26,000 ly haul can never balloon the floating-origin coordinate the way it used to.
	if newton:
		# Honest Sol: engines only. Warp is not a local speed tier.
		_warp_charge = 0.0
		eff_warp = 1.0
	elif warp > 1.0 and not combat_lock:
		if Input.is_physical_key_pressed(KEY_W) or auto_cruise or autopilot:   # auto-cruise/autopilot spool warp too
			_warp_charge = minf(_warp_charge + delta / WARP_CHARGE_TIME, 1.0)
		else:
			_warp_charge = maxf(_warp_charge - delta / WARP_DECAY_TIME, 0.0)
		var c := _warp_charge * _warp_charge * (3.0 - 2.0 * _warp_charge)   # smoothstep
		eff_warp = lerpf(WARP_FLOOR, warp, c)
	elif combat_lock:
		# No interstellar speed during combat — bleed any spool back to sublight.
		_warp_charge = maxf(_warp_charge - delta / WARP_DECAY_TIME, 0.0)

	# Heavy lateral/vertical control: ease the A/D and Space/Ctrl inputs so they ramp into
	# thrust and coast out of it (a weighty, drifting feel) instead of snapping on/off.
	# Forward/back (W/S) stays responsive — only the sideways/vertical axes are weighted.
	var sk := clampf(STRAFE_SMOOTH * delta, 0.0, 1.0)
	_strafe = lerpf(_strafe, strafe, sk)
	_lift = lerpf(_lift, lift, sk)
	var t_fwd := NEWTON_THRUST if newton else THRUST
	var t_side := NEWTON_STRAFE if newton else STRAFE_THRUST
	if newton and dev_speed and _cruise_ok_now():
		t_fwd *= DEV_THRUST_MULT
		t_side *= DEV_THRUST_MULT
	var local_accel := Vector3(_strafe * t_side, _lift * t_side, fwd * t_fwd) * eff_warp
	var g_thrusting := local_accel.length_squared() > 0.0001
	if local_accel.length_squared() > 0.0001:
		velocity += (transform.basis * local_accel) * boost * delta

	# Gravitational tug toward nearby bodies. It draws you in and helps you settle to land,
	# but must NEVER trap you. Two safeguards:
	#  • IDLE RELEASE — a parked, slow ship (no thrust) is let go entirely, so gravity can't
	#    balance damping into a permanent ~30 u/s drift toward the star while you sit still.
	#  • OUTWARD FADE — thrusting away from the pull fades it out (gone when straight out).
	# Sol newton skips both — a parked ship must fall, and vacuum has no damping.
	var g := gravity
	if newton:
		_clamp_time_warp(g_thrusting, braking)
		if drop_flash > 0.0:
			drop_flash = maxf(drop_flash - delta, 0.0)
		var sim: float = delta * time_rate
		_newton_advance(sim)
		_footprint_tick(delta, fwd < 0.0, fwd > 0.0)
	else:
		if not g_thrusting and velocity.length() < GRAVITY_IDLE_SPEED:
			g = Vector3.ZERO                        # idle + slow → released; you settle to a stop
		elif g.length() > 0.01 and g_thrusting:
			var thrust_dir := (transform.basis * local_accel).normalized()
			var outward := -g.normalized()
			var align := thrust_dir.dot(outward)   # 1 = thrusting straight out, -1 = straight in
			if align > 0.0:
				g *= (1.0 - align)                  # fade the pull as you head outward
		velocity += g * delta

	# Damping: velocity eases toward zero when you're not thrusting. Sublight uses the
	# light DRIFT_DAMPING so the ship glides and carries momentum through turns; as warp
	# spools up we blend back to the heavier DAMPING that the FTL travel speeds are tuned
	# around, so deep-space cruise times are unchanged.
	if not newton:
		var damp := DRIFT_DAMPING
		if eff_warp > 1.0:
			damp = lerpf(DRIFT_DAMPING, DAMPING, smoothstep(1.0, 2.0, eff_warp))
		velocity = velocity.lerp(Vector3.ZERO, clampf(damp * delta, 0.0, 1.0))
		# Auto-settle near a body: a soft brake that strengthens as you close in, so EASING OFF the
		# throttle lets you hover and capture instead of drifting past. Only while coasting, though —
		# holding thrust pushes you right in (and through), so a body never freezes you in place.
		if nearest_dist < SETTLE_RANGE and not braking and not g_thrusting:
			var settle := SETTLE_RATE * (1.0 - nearest_dist / SETTLE_RANGE)
			velocity = velocity.lerp(Vector3.ZERO, clampf(settle * delta, 0.0, 1.0))
	# Sol brake: a smooth hard stop plus a warp dump.
	if braking:
		velocity = velocity.lerp(Vector3.ZERO, clampf(BRAKE_RATE * delta, 0.0, 1.0))
		_warp_charge = 0.0
	var cap := MAX_SPEED * eff_warp * boost
	if not newton and eff_warp <= 1.0:
		cap = minf(cap, SUBLIGHT_MAX * boost)   # arcade systems only; Sol is uncapped
	# Force-slow safe-zones around stars/planets/moons (NO pull) — applied in ANY mode
	# and ANY direction, so you ease right down to orbit, analyse, and capture a body,
	# and a star drops you out of warp as you arrive. Scaled by the body's mass.
	cap = minf(cap, speed_limit)
	# Harbour cap near stations — any mode, so you never blast through a structure.
	cap = minf(cap, struct_limit)
	# Weapons lock: while you hold fire you're pulled down to regular combat speed — you
	# can't shoot above it, so opening fire itself slows the ship out of warp/boost.
	if firing:
		cap = minf(cap, WEAPON_FIRE_SPEED)
	# Bleed warp charge when something is force-slowing us, so the drive visibly drops
	# out of warp as you settle near a body/station (or open fire) instead of pinning at full spool.
	if (speed_limit < INF or struct_limit < INF or firing) and cap < MAX_SPEED:
		_warp_charge = minf(_warp_charge, cap / maxf(MAX_SPEED, 1.0))
	# The drift-flip LEAP bypasses slow-zone/gravity caps so it can break you out of a well.
	if _flip_t > 0.0:
		cap = maxf(cap, FLIP_CRUISE * (1.0 + FLIP_LEAP_BOOST))
	velocity = velocity.limit_length(cap)

	# Platform approach: inside the station's landing zone the speed is force-reduced
	# so you can actually land — no matter how fast you arrived (warp included). The
	# cap shrinks smoothly with proximity, easing you down rather than snapping. You
	# keep steering, you just can't blast through. (dock_approach is fed by main.)
	if dock_approach > 0.0:
		var land_cap := lerpf(DOCK_EDGE_SPEED, DOCK_PLATFORM_SPEED, dock_approach)
		velocity = velocity.limit_length(land_cap)

	# --- Floating origin: never move the node; accumulate the true position ---
	# Safe now: every hull translates at its own warp (bounded coordinate rate), and the core
	# voyage looms separately instead of flying real distance — so this never balloons.
	if not newton:
		true_pos += velocity * delta

	# --- Cosmetic banking (on the mesh only, so the camera stays steady) ---
	var target_bank := clampf(-turn * BANK_GAIN - _strafe * 0.35, -BANK_ANGLE, BANK_ANGLE)
	# Cinematic cruise sway: hold a straight line (forward thrust, no steer/strafe input)
	# and after a beat the hull breathes a slow roll left↔right. Any steer/strafe input
	# unwinds it fast so it never fights real control.
	var steering := absf(turn) > 0.0008 or absf(_strafe) > 0.04 or _free_look or autopilot or braking
	var cruising := (Input.is_physical_key_pressed(KEY_W) or auto_cruise) and not steering
	_cruise_t = (_cruise_t + delta) if cruising else maxf(_cruise_t - delta * 3.0, 0.0)
	var sway_ramp := clampf((_cruise_t - SWAY_DELAY) / SWAY_RAMP, 0.0, 1.0)
	if sway_ramp > 0.0:
		# Two non-harmonic sines → an organic drift rather than a metronome wobble. At
		# interstellar speed the wave stretches LONGER and a touch wider (a grand, slow
		# banking roll) vs. the quicker breathe of normal sublight cruise.
		var warpf := smoothstep(1.0, 2.0, eff_warp)        # 0 sublight → 1 full warp
		var rate := lerpf(1.0, 0.5, warpf)                 # slower = longer wave at warp
		var amp := SWAY_ANGLE * lerpf(1.0, 1.45, warpf)    # slightly wider roll at warp
		var st := Time.get_ticks_msec() * 0.001
		var sway := (sin(st * 0.9 * rate) + 0.4 * sin(st * 0.37 * rate + 1.1)) / 1.4
		target_bank = clampf(target_bank + sway * amp * sway_ramp, -BANK_ANGLE, BANK_ANGLE)
	_bank = lerpf(_bank, target_bank, clampf(BANK_SMOOTH * delta, 0.0, 1.0))
	# Nose-lean into a climb/dive: vertical mouse leans the whole hull (mesh only; the real
	# pitch already happened on the transform above). Eased slowly so the big ship tips its
	# nose with weight instead of snapping. +lean (mouse down → nose-down dive) reads natural.
	var target_lean := clampf(lean * LEAN_PITCH_GAIN, -LEAN_PITCH, LEAN_PITCH)
	_lean = lerpf(_lean, target_lean, clampf(LEAN_SMOOTH * delta, 0.0, 1.0))
	_mesh_root.rotation = Vector3(_lean, 0.0, _bank)   # clear any transit flip/wobble
	# Cinematic drift-flip: a full 360° barrel roll layered on the bank (cosmetic — heading
	# is untouched). The sideways drift kick was added to velocity in do_flip().
	if _flip_t > 0.0:
		_flip_t = maxf(_flip_t - delta, 0.0)
		var fp := 1.0 - _flip_t / FLIP_TIME            # 0 → 1 across the move
		# NOSE STAYS STRAIGHT: a pure barrel roll around the forward axis — only the wings
		# sweep (x-y), the nose never pitches/yaws off the aim line. Heavy eased slow-fast-slow.
		var fe := fp * fp * (3.0 - 2.0 * fp)
		_mesh_root.rotation.z = _bank + _flip_dir * TAU * fe
		# DRIVE the ship through a wide wavey arc so it visibly TRAVELS while rolling. A compound
		# sine gives a rich S-on-S-on-S weave (more curve); facing/aim (transform) is untouched.
		# The glide is LERPED in (and out), so entering/leaving the flip is seamless — no snap.
		var weave := sin(fp * TAU) + 0.45 * sin(fp * 2.0 * TAU) + 0.22 * sin(fp * 3.0 * TAU)
		_flip_yaw += _flip_dir * FLIP_SWERVE * weave * delta
		# Quick LEAP: a speed burst that decays into the cruise glide over the first third.
		if not newton:
			var leap := 1.0 + FLIP_LEAP_BOOST * (1.0 - smoothstep(0.0, 0.32, fp))
			var glide := (-transform.basis.z).rotated(Vector3.UP, _flip_yaw) * (FLIP_CRUISE * leap)
			velocity = velocity.lerp(glide, clampf(FLIP_EASE * delta, 0.0, 1.0))

	# --- Engine / booster intensity ---
	var flipping := _flip_t > 0.0
	var throttle := 1.0 if (Input.is_physical_key_pressed(KEY_W) or auto_cruise) else 0.18
	if Input.is_physical_key_pressed(KEY_S):
		throttle = maxf(throttle, 0.55)
	if boost > 1.0:
		throttle *= 1.4
	if flipping:
		throttle = 1.7                      # boosters BLAZE — the leap-push is a hard burn
	_update_authored_propulsion(throttle, delta)

	# --- Engine voice: loop while we're on the gas, with start/stop whooshes ---
	if audio:
		var thrusting := local_accel != Vector3.ZERO or flipping
		var ship_name: String = SHIP_MODELS[_current_model].name
		# During the leap, force the boost voice so you HEAR the push.
		audio.update_engine(ship_name, thrusting, clampf(throttle, 0.0, 1.0), boost > 1.0 or flipping, _engine_pitch, delta)
	if _engine_mat:  # fallback ship only
		var e := 2.0 + throttle * 4.0
		_engine_mat.emission_energy_multiplier = lerpf(
			_engine_mat.emission_energy_multiplier, e, clampf(8.0 * delta, 0.0, 1.0))

	# Fat motion streaks during the leap-push (warp-like), normal speed-based otherwise.
	_update_streaks(maxf(velocity.length(), MAX_SPEED * 0.7) if flipping else velocity.length())
	_update_camera(delta)


func _update_authored_propulsion(throttle: float, delta: float) -> void:
	var k := clampf(7.0 * delta, 0.0, 1.0)
	var t := Time.get_ticks_msec() * 0.001
	# Each ship's named booster surface keeps its authored shape. Speed only changes
	# its heat/flow: sublight is bright, while boost/warp drives it white-hot.
	var speed_power := clampf(velocity.length() / (SUBLIGHT_MAX * BOOST_MULT), 0.0, 1.0)
	var warp_power := clampf(_warp_charge, 0.0, 1.0) if warp > 1.0 else 0.0
	var target_power := maxf(speed_power, warp_power)
	# A small throttle lead prevents a dead-looking delay before the ship accelerates.
	target_power = maxf(target_power, clampf(throttle / 1.7, 0.0, 1.0) * 0.28)
	if is_boosting:
		target_power = maxf(target_power, 0.82)
	var sputter := 1.0
	if _boost_starved:
		sputter = 0.18 if fmod(t * 11.0, 1.0) < 0.45 else 0.72
		k = 1.0
	var previous := _propulsion_power
	_propulsion_power = lerpf(_propulsion_power, target_power * sputter, k)
	# Punching the throttle should visibly kick the flame before it settles: chamber
	# pressure overshoots, the plume over-expands, then relaxes. Measured as rate of
	# change (frame-rate independent) and decayed on its own clock, so the kick reads
	# as a transient rather than just a longer burn. The -1.5 floor ignores the slow
	# drift of ordinary acceleration and only fires on a real stab at the throttle.
	var rise := maxf(_propulsion_power - previous, 0.0) / maxf(delta, 0.0001)
	_propulsion_surge = maxf(
		_propulsion_surge * (1.0 - clampf(3.6 * delta, 0.0, 1.0)),
		clampf((rise - 1.5) * 0.10, 0.0, 0.70))

	# All four imported ships use their own named rear propulsion meshes. Keep a
	# visible idle burn, then increase turbulence and flow with speed.
	var heat := clampf(_propulsion_power * 1.12 + _propulsion_surge * 0.25, 0.0, 1.0)
	for propulsion in _authored_propulsion:
		propulsion.set_shader_parameter("power", _propulsion_power * POWER_CEIL)
		propulsion.set_shader_parameter("flow_speed", lerpf(0.8, 3.1, _propulsion_power))
		# Exhaust runs orange when cold and blue-white when hot. Torch cones, the
		# JazOone engine discs and the haze all read the same value, so no layer can
		# disagree with another about how hard the engine is working.
		propulsion.set_shader_parameter("temperature", heat)

	# Only the torch cones reshape. Length moves a lot with throttle; flare moves very
	# little, or the plume balloons outward instead of stretching backward.
	var length_scale := lerpf(0.52, 1.30, _propulsion_power) + _propulsion_surge * 0.42
	var flare_scale := lerpf(0.80, 1.06, _propulsion_power) + _propulsion_surge * 0.10
	var churn := lerpf(0.55, 1.35, _propulsion_power)
	for torch in _torch_materials:
		torch.set_shader_parameter("length_scale", length_scale)
		torch.set_shader_parameter("flare_scale", flare_scale)
		torch.set_shader_parameter("turbulence", churn)

	# Emissive geometry cannot put a photon on the hull, so these are what actually
	# make the tail glow when the engines light up.
	if not _nozzle_lights.is_empty():
		var lit := ENGINE_COOL.lerp(_engine_accent, smoothstep(0.12, 0.78, heat))
		# Per-light energy is divided down as the nozzle count rises. These lights add,
		# so a flat energy made dingo57's eight nozzles four times as bright as
		# JazOone's two and bleached the hull white around the tail. sqrt, not 1/n: the
		# eye reads light roughly logarithmically, and 1/n makes an eight-engine ship
		# look weaker than a two-engine one.
		var share := sqrt(2.0 / maxf(float(_nozzle_lights.size()), 1.0))
		# Same story as POWER_CEIL: 0.04..0.42 had cruise at 0.165 and boost at 0.352.
		# Now boost lands where cruise used to be.
		var lenergy := (lerpf(0.015, 0.20, _propulsion_power)
			+ _propulsion_surge * 0.09) * share
		# Slight flicker so it reads as combustion rather than a fixed lamp.
		lenergy *= 1.0 + sin(t * 27.0) * 0.05 * _propulsion_power
		for light in _nozzle_lights:
			light.light_color = lit
			light.light_energy = lenergy


# Parent the chase fill light under the camera once it exists, so it inherits the
# camera's orientation for free — no per-frame aiming, and it survives every path
# that rewrites camera.global_transform (transit buffet, teleport, aim snap).
func _ensure_hull_fill() -> void:
	if HULL_FILL_ENERGY <= 0.0:
		return
	if _hull_fill != null and _hull_fill.get_parent() == camera:
		return
	if _hull_fill == null:
		_hull_fill = DirectionalLight3D.new()
		_hull_fill.name = "HullFill"
		_hull_fill.light_color = HULL_FILL_COLOR
		_hull_fill.light_energy = HULL_FILL_ENERGY
		_hull_fill.light_specular = HULL_FILL_SPECULAR
		_hull_fill.shadow_enabled = false
		# Only the hull. Everything else in the game is on layer 1 alone, so this
		# light cannot reach the planets, the station, the props or the starfield.
		_hull_fill.light_cull_mask = ShipMesh.SHIP_FILL_LAYER
		# Rotation is relative to the camera: yaw first, then pitch down onto the hull.
		_hull_fill.rotation = Vector3(
			deg_to_rad(HULL_FILL_PITCH_DEG), deg_to_rad(HULL_FILL_YAW_DEG), 0.0)
	elif _hull_fill.get_parent() != null:
		_hull_fill.get_parent().remove_child(_hull_fill)
	camera.add_child(_hull_fill)


func _update_camera(delta: float) -> void:
	if camera == null:
		return
	_ensure_hull_fill()
	# Camera basis lags the ship's a touch -> gentle sway / sense of speed.
	_cam_basis = _cam_basis.slerp(transform.basis, clampf(CAM_LAG * delta, 0.0, 1.0))
	_cam_zoom_smooth = lerpf(_cam_zoom_smooth, _cam_zoom, clampf(10.0 * delta, 0.0, 1.0))
	# Free-look orbit: ease the applied angles toward target (0 = straight behind).
	# Rotating the whole chase rig keeps the ship framed, so at 0 it's the usual cam.
	var lk := clampf(LOOK_RETURN * delta, 0.0, 1.0)
	_look_yaw_s = lerpf(_look_yaw_s, _look_yaw, lk)
	_look_pitch_s = lerpf(_look_pitch_s, _look_pitch, lk)
	# CAM_VIEW_PITCH orbits the rig (position + aim together) so the ship is seen from slightly below.
	var basis := _cam_basis * Basis(Vector3.RIGHT, deg_to_rad(CAM_VIEW_PITCH_DEG)) \
		* (Basis(Vector3.UP, _look_yaw_s) * Basis(Vector3.RIGHT, _look_pitch_s))
	var cam_pos := basis * (CAM_OFFSET * _hull_km * _cam_zoom_smooth)
	# Wormhole transit: only a SLIGHT, slow buffet (gentle position drift + a touch of
	# roll/pitch) and a restrained FOV lean → the dive feels tense and dark, not stormy.
	if transiting:
		var t := Time.get_ticks_msec() * 0.001
		var pj := 0.05
		cam_pos += basis * Vector3(sin(t * 7.0) * pj, cos(t * 9.0) * pj, sin(t * 11.0) * pj * 0.5)
		var jr := 0.004
		basis = basis * Basis.from_euler(Vector3(
			sin(t * 5.0) * jr, cos(t * 6.0) * jr, sin(t * 8.0) * jr * 2.0))
		camera.global_transform = Transform3D(basis, cam_pos)
		camera.fov = lerpf(camera.fov, FOV_BASE + FOV_KICK * 0.8, clampf(3.0 * delta, 0.0, 1.0))
		return
	camera.global_transform = Transform3D(basis, cam_pos)
	# Clamp the fraction so warp speeds don't blow the FOV out into a fisheye.
	var speed_frac := clampf(velocity.length() / MAX_SPEED, 0.0, 1.0)
	camera.fov = lerpf(camera.fov, FOV_BASE + speed_frac * FOV_KICK, clampf(4.0 * delta, 0.0, 1.0))


func _set_capture(c: bool) -> void:
	_mouse_captured = c
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if c else Input.MOUSE_MODE_VISIBLE)


# World position of the gun muzzle, tracking the hull's COSMETIC bank so bolts always
# leave the visible nose (slightly below centre) instead of drifting sideways when you
# bank into a turn or strafe with A/D. The forward offset sits on the roll axis (so it's
# unaffected); the small downward drop is rolled with the hull to stay glued to the gun.
func muzzle_world() -> Vector3:
	var local_off := Basis.from_euler(Vector3(0.0, 0.0, _bank * MUZZLE_BANK_FOLLOW)) * Vector3(0.0, -muzzle_drop, -muzzle)
	return true_pos + transform.basis * local_off


# ----------------------------------------------------------------------------
# Visual setup
# ----------------------------------------------------------------------------
func _build_visual() -> void:
	_mesh_root = Node3D.new()
	add_child(_mesh_root)
	_build_ship_model(_current_model)
	_build_streaks()


# A field of thin additive streaks that stream past the ship — only at speed, so
# you feel "fast" without any HUD number. Lives on the ship (origin), in local
# coords, flowing +Z (toward/behind the chase camera).
# Scale cue, not a speed cue. The field below is authored in raw units: a box 45 deep
# with 2.4-long streaks. Against an 80 m hull (_hull_km = 0.08) that is a field ~560
# hull lengths deep made of debris 30 hull lengths long, all of it far away — and
# debris that big sliding past tells the eye the ship is a speck. _fit_streaks rescales
# the whole emitter (box, velocities and streak mesh together, which node scale does in
# one go because the particles run in local_coords) so the field is measured in HULL
# LENGTHS. Streaks then pass close to the hull at hull-relevant size, and the parallax
# reads as "something big is moving" instead of "a dot is drifting".
const STREAK_BOX_Z := 45.0        # the authored emission_box_extents.z below
const STREAK_FIELD_HULLS := 14.0  # how deep the field should actually be, in hull lengths


func _fit_streaks() -> void:
	if _streaks == null:
		return
	_streaks.scale = Vector3.ONE * (_hull_km * STREAK_FIELD_HULLS / STREAK_BOX_Z)


func _build_streaks() -> void:
	_streaks = GPUParticles3D.new()
	add_child(_streaks)
	_streaks.amount = 90
	_streaks.lifetime = 0.45
	_streaks.local_coords = true
	_streaks.emitting = false
	_streaks.visibility_aabb = AABB(Vector3(-60, -60, -90), Vector3(120, 120, 180))

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(16, 11, 45)
	pm.direction = Vector3(0, 0, 1)        # stream toward/past the camera
	pm.spread = 0.0
	pm.initial_velocity_min = 180.0
	pm.initial_velocity_max = 240.0
	pm.gravity = Vector3.ZERO
	_streaks.process_material = pm

	var streak := BoxMesh.new()
	streak.size = Vector3(0.03, 0.03, 2.4)  # long + thin = a motion streak
	_streak_mat = StandardMaterial3D.new()
	_streak_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_streak_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_streak_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_streak_mat.albedo_color = Color(0.7, 0.9, 1.0, 0.0)
	streak.material = _streak_mat
	_streaks.draw_pass_1 = streak
	_fit_streaks()


# Density + brightness + flow speed all ramp with the ship's RAW speed. Two ramps so
# you feel motion across the whole envelope: a gentle cue over the calm sublight range
# (so normal cruise no longer feels static), then the dramatic warp stretch up top.
func _update_streaks(speed: float) -> void:
	if _streaks == null:
		return
	# Sublight cue: 0 at rest -> ~full by SUBLIGHT_MAX (the calm-cruise cap). Kept subtle
	# so it reads as "moving" without the busy warp look — but visible enough to notice.
	var sub := clampf(speed / SUBLIGHT_MAX, 0.0, 1.0)
	# High-speed/warp stretch: off until ~1/3 of MAX_SPEED, full near the top.
	var hi := clampf((speed / MAX_SPEED - 0.3) / 0.5, 0.0, 1.0)
	var t := maxf(sub * 0.72, hi)
	_streaks.emitting = t > 0.01
	_streaks.amount_ratio = clampf(0.15 + t, 0.0, 1.0)
	_streaks.speed_scale = 1.0 + t * 1.6
	var a: Color = _streak_mat.albedo_color
	a.a = t * 0.8
	# Galactic drive only: at her absolute top speed the normal ramp is already maxed out, so
	# push the streaks PAST it — a much faster, denser hyperspace blur. Eased by the spool charge
	# so it swells in with the drive; ONLY this hull while actually cruising, so regular flight
	# (and every other ship) keeps the exact streak feel above.
	if galactic_cruising():
		var g := _warp_charge   # 0..1 drive spool
		_streaks.emitting = true
		_streaks.amount_ratio = 1.0
		_streaks.speed_scale = lerpf(2.6, 9.0, g)   # far faster flow than the warp max (2.6)
		a.a = lerpf(0.8, 0.95, g)
	_streak_mat.albedo_color = a


# (Re)build the hull and its authored propulsion for SHIP_MODELS[idx]. Safe to call at runtime to
# swap ships: it clears the old model first.
func _build_ship_model(idx: int) -> void:
	# Detach old children immediately (queue_free is deferred, which would let the
	# old meshes pollute the AABB fit below) then free them.
	for c in _mesh_root.get_children():
		_mesh_root.remove_child(c)
		c.queue_free()
	_authored_propulsion.clear()
	_torch_materials.clear()
	_nozzle_lights.clear()
	_propulsion_surge = 0.0
	_engine_mat = null

	var info = SHIP_MODELS[idx]
	warp = float(info.get("warp", 1.0))
	fire_cooldown = float(info.get("fire_cd", 0.22))
	max_hp = int(info.get("hp", 100))
	bolt_speed = float(info.get("bolt_speed", 950.0))
	bolt_scale = float(info.get("bolt_scale", 1.0))
	bolt_damage = int(info.get("dmg", 1))
	bolt_laser = bool(info.get("bolt_laser", false))
	bolt_strong = bool(info.get("bolt_strong", false))
	energy_max = float(info.get("energy_max", 100.0))
	energy_use = float(info.get("energy_use", 1.0))
	can_fire = bool(info.get("can_fire", true))
	has_laser = bool(info.get("laser", false))
	laser_offset = info.get("laser_offset", Vector3.ZERO)
	auto_capture = bool(info.get("auto_capture", false))
	_engine_pitch = float(info.get("engine_pitch", 1.0))
	has_galactic_drive = bool(info.get("galactic_drive", false))
	_warp_charge = 0.0
	# Loads a PackedScene (.glb/.gltf/.fbx/.dae) OR a bare Mesh (.obj) — wrap a Mesh
	# in a MeshInstance3D so both paths produce a model Node3D.
	var res := load(info.path)
	var model: Node3D
	if res is PackedScene:
		model = (res as PackedScene).instantiate() as Node3D
	elif res is Mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = res
		model = mi
	if model == null:
		push_warning("Ship: could not load %s — using primitive fallback." % info.path)
		_build_primitive_ship()
		return
	# Install legacy OBJ surface overrides before the MeshInstance3D enters the live
	# renderer. Growing the override array after scene attachment makes Godot 4.6
	# briefly query its not-yet-filled material slots.
	if info.get("class_ii_cruiser", false):
		_authored_propulsion = ShipMesh.style_class_ii_cruiser(model)
	elif info.get("snarkrans_starship", false):
		_authored_propulsion = ShipMesh.style_snarkrans_starship(model)
	elif info.get("base_basic_pbr", false):
		_authored_propulsion = ShipMesh.style_base_basic_pbr(model)
	elif info.get("jazoone_spaceship", false):
		_authored_propulsion = ShipMesh.style_jazoone_spaceship(model)
	elif info.get("wedge_fighter", false):
		_authored_propulsion = WEDGE_DESIGN.style(model)
	var picked_palette := _palette_for(_color_for(info.name, info))
	if not info.get("wedge_fighter", false) and not info.get("base_basic_pbr", false):
		ShipMesh.color_authored_ship(model, picked_palette.swatch, _finish_for(info.name))
	_mesh_root.add_child(model)
	model.rotation = Vector3(deg_to_rad(float(info.pitch)), deg_to_rad(float(info.yaw)), 0.0)
	_hull_km = float(info.length) / HULL_REF_LENGTH * HULL_KM
	_fit_streaks()   # the debris field is measured in hull lengths; this hull just changed
	var box := ShipMesh.fit_model(_mesh_root, model, _hull_km)
	# The Class II source only supplies six flat propulsion patches. Fit the hull
	# first, then extend those exact sockets into visible two-layer torch plumes so
	# exhaust volume cannot alter the intended ship scale.
	var plumes: Array[ShaderMaterial] = []
	if info.get("class_ii_cruiser", false):
		plumes = ShipMesh.add_class_ii_booster_plumes(model)
	elif info.get("snarkrans_starship", false):
		plumes = ShipMesh.add_snarkrans_booster_plumes(model)
	elif info.get("base_basic_pbr", false):
		plumes = ShipMesh.add_base_basic_booster_plumes(model)
	elif info.get("jazoone_spaceship", false):
		plumes = ShipMesh.add_jazoone_booster_plumes(model)
	# Torch cones are the only layer whose GEOMETRY reacts to throttle, so they are
	# tracked separately from the flat authored propulsion surfaces and the haze.
	for material in plumes:
		if material.shader == ShipMesh.CRUISER_TORCH_SHADER:
			_torch_materials.append(material)
	_authored_propulsion.append_array(plumes)
	# Haze shells and nozzle lights live in their own rig node so the plume roots keep
	# their "N sockets -> exactly 2N cones" shape; collect them back by name.
	_authored_propulsion.append_array(ShipMesh.collect_haze_materials(model))
	_nozzle_lights = ShipMesh.collect_nozzle_lights(model)
	_engine_accent = info.get("light_accent", Color(0.35, 0.70, 1.0))
	print("%s: %d torch cones, %d nozzle lights, %d driven materials"
		% [info.name, _torch_materials.size(), _nozzle_lights.size(),
		_authored_propulsion.size()])
	# Bolts spawn close to the nose — just shy of the hull's front tip — so the bright tracer
	# clearly emerges from the ship rather than floating ahead of it.
	muzzle = box.size.z * 0.42
	muzzle_drop = box.size.y * 0.18   # emerge a little below centre (lowered to match the
									  # hull's new lower framing), where the guns sit
	# Tag every mesh under the hull with the ship-only fill layer, so the chase fill
	# light (HULL_FILL_*, parented to the camera) can light us and nothing else. Done
	# LAST, after the plume/nozzle rigs are attached, so the walk catches all of it.
	ShipMesh.tag_fill_layer(_mesh_root)
	# NO ship-attached lights. The three key/fill/core omnis that used to go here are
	# gone along with the per-nozzle lights: point lights sitting a few metres off a
	# polished metallic hull clip their own specular and diffuse long before the
	# diffuse term looks bright, and the result was an engine bay that blew out to
	# white in the running game while an offscreen render of the same ship looked fine.
	# The hull is now lit by main.gd's scene sun (1.05) + counter-fill (0.35) and the
	# 0.2 ambient, which is what actually defines its form. `accent` / `light_energy`
	# stay in SHIP_MODELS and SHIP_PALETTES - they still drive the exhaust colour - and
	# ShipMesh.add_hull_lights still exists if this is ever reinstated.


# --- Ship-swap API (called by main when docked) ---
func swap_ship(idx: int) -> void:
	if idx < 0 or idx >= SHIP_MODELS.size() or idx == _current_model:
		return
	_current_model = idx
	_bank = 0.0
	_mesh_root.rotation = Vector3.ZERO  # drop any banking carryover
	_build_ship_model(idx)

func ship_count() -> int:
	return SHIP_MODELS.size()

func current_index() -> int:
	return _current_model

func ship_name_at(i: int) -> String:
	return SHIP_MODELS[i].name


# --- Saved hangar colour / finish -----------------------------------------

func _color_for(ship_name: String, info: Dictionary) -> String:
	if not _color_choice.has(ship_name):
		_color_choice[ship_name] = String(info.get("default_color", "silver"))
	var saved = _color_choice[ship_name]
	# Migrate profiles written by the previous body/wing picker.
	if saved is Dictionary:
		saved = String(saved.get("body", info.get("default_color", "silver")))
		_color_choice[ship_name] = saved
	return String(saved)


func _palette_for(key: String) -> Dictionary:
	for palette in SHIP_PALETTES:
		if String(palette.key) == key:
			return palette
	return SHIP_PALETTES[0]


func _has_palette(key: String) -> bool:
	for palette in SHIP_PALETTES:
		if String(palette.key) == key:
			return true
	return false


func _finish_for(ship_name: String) -> String:
	return String(_finish_choice.get(ship_name, "metallic"))


func current_has_color_pick() -> bool:
	return bool(SHIP_MODELS[_current_model].get("color_pick", false))


func current_body_color() -> String:
	var info: Dictionary = SHIP_MODELS[_current_model]
	return _color_for(info.name, info)


func current_finish() -> String:
	return _finish_for(SHIP_MODELS[_current_model].name)


func set_ship_color(_part: String, key: String) -> void:
	var info: Dictionary = SHIP_MODELS[_current_model]
	if not info.get("color_pick", false) or not _has_palette(key):
		return
	_color_choice[info.name] = key
	_rebuild_customized_ship()


func set_ship_finish(key: String) -> void:
	if key != "metallic" and key != "glassy":
		return
	_finish_choice[SHIP_MODELS[_current_model].name] = key
	_rebuild_customized_ship()


func _rebuild_customized_ship() -> void:
	_bank = 0.0
	_mesh_root.rotation = Vector3.ZERO
	_build_ship_model(_current_model)


func customization_state() -> Dictionary:
	return {"color": _color_choice.duplicate(true), "finish": _finish_choice.duplicate(true)}


func load_customization(saved: Dictionary) -> void:
	if saved == null:
		return
	if saved.has("color") and saved.color is Dictionary:
		_color_choice = saved.color.duplicate(true)
	if saved.has("finish") and saved.finish is Dictionary:
		_finish_choice = saved.finish.duplicate(true)
	_rebuild_customized_ship()

func set_frozen(f: bool) -> void:
	frozen = f
	# Clear any showroom-spin / banking carryover so the hull is aligned with the
	# nose again the instant you undock (otherwise it'd fly pointing sideways).
	_mesh_root.rotation = Vector3.ZERO
	_set_capture(not f)


# Point the nose (-Z) at a world point and snap the chase camera to match, so
# the very first frame opens already framed (no swing). Used at spawn.
func face_toward(world_point: Vector3) -> void:
	var dir := world_point - global_position
	if dir.length_squared() < 0.0001:
		return
	dir = dir.normalized()
	var up := Vector3.UP
	if absf(dir.dot(up)) > 0.98:
		up = Vector3.RIGHT
	transform.basis = Basis.looking_at(dir, up)
	_cam_basis = transform.basis


func _kill_turn_rates() -> void:
	_yaw_rate = 0.0
	_pitch_rate = 0.0
	_steer = Vector2.ZERO
	_look_yaw = 0.0
	_look_pitch = 0.0
	_look_yaw_s = 0.0
	_look_pitch_s = 0.0


# Cinematic drift-flip (W + C): a full barrel roll plus a sideways drift slew. The roll is
# cosmetic (mesh only, so heading/aim are unaffected); the drift is a one-off velocity kick
# that decays through the normal damping. dir < 0 = left, ≥ 0 = right. Works in free-look too.
func do_flip(dir := 1.0) -> void:
	if _flip_t > 0.0 or frozen or transiting:
		return
	_flip_dir = -1.0 if dir < 0.0 else 1.0
	_flip_t = FLIP_TIME
	_flip_yaw = 0.0
	# Motion is DRIVEN each frame during the flip (see fly()'s flip block) so the ship glides
	# through a wide arc instead of spinning on the spot — no one-shot impulse to be damped away.


# Begin hands-off cinematic flight to a body (main keeps autopilot_target current).
func start_autopilot(body_name: String) -> void:
	autopilot = true
	autopilot_name = body_name


# Steer the ship toward autopilot_target; cancel the moment the player takes control.
func _autopilot_steer(delta: float) -> void:
	# Cancel only when the player actually flies (thrust keys) — not the mouse, so it
	# doesn't abort the instant the map closes and the cursor re-captures.
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_S) \
			or Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_D) \
			or Input.is_physical_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_CTRL):
		autopilot = false
		return
	var to := autopilot_target - true_pos
	if to.length() < AP_ARRIVE:
		autopilot = false
		return
	var dir := to.normalized()
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var tb := Transform3D(Basis(), Vector3.ZERO).looking_at(dir, up).basis
	transform.basis = transform.basis.slerp(tb, clampf(AP_TURN * delta, 0.0, 1.0)).orthonormalized()


# ----------------------------------------------------------------------------
# Fallback: a small fighter from primitives (used only if the .glb won't load)
# ----------------------------------------------------------------------------
func _build_primitive_ship() -> void:
	var hull_mat := StandardMaterial3D.new()
	hull_mat.albedo_color = Color(0.22, 0.26, 0.34)
	hull_mat.metallic = 0.6
	hull_mat.roughness = 0.4
	hull_mat.emission_enabled = true
	hull_mat.emission = Color(0.14, 0.17, 0.24)
	hull_mat.emission_energy_multiplier = 0.5

	var fuselage := MeshInstance3D.new()
	var fmesh := BoxMesh.new()
	fmesh.size = Vector3(0.7, 0.4, 2.2)
	fuselage.mesh = fmesh
	fuselage.material_override = hull_mat
	_mesh_root.add_child(fuselage)

	var nose := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.45
	cone.height = 1.2
	cone.radial_segments = 8
	cone.rings = 0
	nose.mesh = cone
	nose.material_override = hull_mat
	nose.rotation = Vector3(deg_to_rad(-90.0), 0.0, 0.0)
	nose.position = Vector3(0.0, 0.0, -1.6)
	_mesh_root.add_child(nose)

	for s in [-1.0, 1.0]:
		var wing := MeshInstance3D.new()
		var wmesh := BoxMesh.new()
		wmesh.size = Vector3(1.5, 0.08, 0.9)
		wing.mesh = wmesh
		wing.material_override = hull_mat
		wing.position = Vector3(s * 0.95, -0.04, 0.35)
		wing.rotation = Vector3(0.0, 0.0, s * deg_to_rad(14.0))
		_mesh_root.add_child(wing)

	var glass_mat := StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.4, 0.8, 1.0)
	glass_mat.emission_enabled = true
	glass_mat.emission = Color(0.35, 0.75, 1.0)
	glass_mat.emission_energy_multiplier = 1.6
	var cockpit := MeshInstance3D.new()
	var cmesh := BoxMesh.new()
	cmesh.size = Vector3(0.42, 0.26, 0.7)
	cockpit.mesh = cmesh
	cockpit.material_override = glass_mat
	cockpit.position = Vector3(0.0, 0.2, -0.35)
	_mesh_root.add_child(cockpit)

	_engine_mat = StandardMaterial3D.new()
	_engine_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_engine_mat.albedo_color = Color(0.2, 0.9, 1.0)
	_engine_mat.emission_enabled = true
	_engine_mat.emission = Color(0.2, 0.9, 1.0)
	_engine_mat.emission_energy_multiplier = 3.0
	var engine := MeshInstance3D.new()
	var emesh := BoxMesh.new()
	emesh.size = Vector3(0.5, 0.3, 0.3)
	engine.mesh = emesh
	engine.material_override = _engine_mat
	engine.position = Vector3(0.0, 0.0, 1.2)
	_mesh_root.add_child(engine)
	_hull_km = HULL_KM
	_fit_streaks()
	_mesh_root.scale = Vector3.ONE * (HULL_KM / 3.4)
