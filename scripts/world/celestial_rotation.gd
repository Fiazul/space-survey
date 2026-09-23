class_name CelestialRotation
extends RefCounted
## UTC-seeded rotation clock, independent of mesh lifetime and ship physics.
## GMST approximation: https://aa.usno.navy.mil/faq/GAST (UTC used as UT1).
const J2000_UNIX := 946728000.0 # 2000-01-01 12:00 UTC
const DAY := 86400.0
const EARTH_ROTATION_DAY := DAY / 1.0027379
const DEFAULT_CYCLE_MINUTES := 8.0
var cycle_minutes := DEFAULT_CYCLE_MINUTES:
	set(value):
		cycle_minutes = value if is_finite(value) and value > 0.0 else DEFAULT_CYCLE_MINUTES
var rate: float:
	get:
		# One complete turn against the current ephemeris Sun.
		return EARTH_ROTATION_DAY / (cycle_minutes * 60.0)
var unix_s := 0.0

func _init() -> void:
	cycle_minutes = float(ProjectSettings.get_setting("world/day_night/cycle_minutes", DEFAULT_CYCLE_MINUTES))

func advance(seconds: float) -> void:
	if is_finite(seconds) and seconds > 0.0:
		unix_s += seconds * rate

func load_from(cfg: ConfigFile, now: float) -> void:
	var saved := float(cfg.get_value("world_clock", "unix_s", now))
	var wall := float(cfg.get_value("world_clock", "saved_at", now))
	# Older profiles used real time. Finish their offline interval at their old
	# rate, then use the newly configured cycle without resetting the phase.
	var saved_rate := float(cfg.get_value("world_clock", "rate", 1.0))
	if not is_finite(saved_rate) or saved_rate <= 0.0:
		saved_rate = rate
	unix_s = saved + maxf(0.0, now-wall)*saved_rate if is_finite(saved) and is_finite(wall) else now

func save_into(cfg: ConfigFile, now: float) -> void:
	cfg.set_value("world_clock", "unix_s", unix_s)
	cfg.set_value("world_clock", "saved_at", now)
	cfg.set_value("world_clock", "rate", rate)

static func earth_angle(unix_time: float) -> float:
	var midnight := floorf(unix_time/DAY)*DAY
	var days := (midnight-J2000_UNIX)/DAY
	var hours := (unix_time-midnight)/3600.0
	var centuries := (unix_time-J2000_UNIX)/(DAY*36525.0)
	var gmst := 6.697375 + .065709824279*days + 1.0027379*hours + .0000258*centuries*centuries
	return fposmod(gmst, 24.0)*TAU/24.0

static func basis_at(body: String, spin: float, unix_time: float) -> Basis:
	var angle := earth_angle(unix_time) if body == "Earth" else fposmod(spin*(unix_time-J2000_UNIX), TAU)
	# ICRS (x,y,z) -> scene (x,z,y) reverses handedness. East is +longitude
	# (+Z at Greenwich), therefore prograde rotation is NEGATIVE about scene Y.
	# Other bodies retain the existing Y-pole approximation, with a stable epoch.
	return Basis(Vector3.UP, -angle)
