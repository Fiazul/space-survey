class_name SystemEphemeris
extends RefCounted
## One star system's bodies in 64-bit scene km (1 unit = 1 km): positions, GM,
## radius, spin and air column. The Ephemeris autoload delegates to the current
## instance, so anchoring, Newton, skin kill and co-rotation (docs/adr/0002) run
## the same way in every physical system. Subclasses: SolEphemeris (JPL/NASA
## tables), GeneratedEphemeris (HYG star + seed).
const _AF := preload("res://scripts/flight/anchor_frame.gd")
const KM_PER_AU := 149597870.7

var id := ""
var primary_star := ""
var spawn_body := ""
var _pos64 := {}
var _gravity_bodies := []   # [{ name, mu }] for every world with real mass (craft excluded)
var _catalog: Array = []


func live_worlds() -> Array:
	return _catalog


func pos64(name: String) -> PackedFloat64Array:
	return _pos64.get(name, _AF.ZERO64)


func scene_pos(name: String) -> Vector3:
	var a: PackedFloat64Array = pos64(name)
	return Vector3(a[0], a[1], a[2])


func has_pos(name: String) -> bool:
	return _pos64.has(name)


func is_anchorable(name: String) -> bool:
	if not has_pos(name):
		return false
	for p in _catalog:
		if str(p.name) == name:
			return not p.get("craft", false)
	return true


func rel_km(body_name: String, anchor: String) -> Vector3:
	return _AF.sub64(pos64(body_name), pos64(anchor))


func gravity_bodies() -> Array:
	return _gravity_bodies


func _build_gravity_bodies() -> void:
	_gravity_bodies.clear()
	for p in _catalog:
		if p.get("craft", false):
			continue
		var mu := gm(str(p.name))
		if mu > 0.0:
			_gravity_bodies.append({ "name": str(p.name), "mu": mu })


func _entry(name: String) -> Dictionary:
	for p in _catalog:
		if str(p.name) == name:
			return p
	return {}


func gm(body_name: String) -> float:
	return float(_entry(body_name).get("mu", 0.0))


func body_radius_km(body_name: String) -> float:
	return float(_entry(body_name).get("radius", 0.0))


func spin_rad_s(body_name: String) -> float:
	return float(_entry(body_name).get("spin", 0.0))


# Rate the rendered surface frame turns at; differs from spin_rad_s only where
# a body's visual clock is not its sidereal rate (Earth's GMST, see SolEphemeris).
func visual_spin_rad_s(body_name: String) -> float:
	return spin_rad_s(body_name)


func atmo_top_km(body_name: String) -> float:
	return float(_entry(body_name).get("atmo_top_km", 0.0))


func is_star(body_name: String) -> bool:
	return bool(_entry(body_name).get("star", false))


# True where the ship's drag/Mach/co-rotation model applies (FlightMode.has_drag_model).
func has_drag_air(body_name: String) -> bool:
	return bool(_entry(body_name).get("drag", false))


# Spawn park radius from the spawn body's centre, km.
func spawn_park_km() -> float:
	return body_radius_km(spawn_body) * 3.0
