class_name CelestialRotation
extends RefCounted
## One UTC-seeded simulation clock, independent of mesh lifetime and visibility.
## GMST approximation: https://aa.usno.navy.mil/faq/GAST (UTC used as UT1).
const J2000_UNIX := 946728000.0 # 2000-01-01 12:00 UTC
const DAY := 86400.0
var unix_s := 0.0

func advance(seconds: float) -> void:
	if is_finite(seconds) and seconds > 0.0:
		unix_s += seconds

func load_from(cfg: ConfigFile, now: float) -> void:
	var saved := float(cfg.get_value("world_clock", "unix_s", now))
	var wall := float(cfg.get_value("world_clock", "saved_at", now))
	unix_s = saved + maxf(0.0, now-wall) if is_finite(saved) and is_finite(wall) else now

func save_into(cfg: ConfigFile, now: float) -> void:
	cfg.set_value("world_clock", "unix_s", unix_s)
	cfg.set_value("world_clock", "saved_at", now)

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
