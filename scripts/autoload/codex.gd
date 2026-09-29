# Autoload singleton (registered as `Codex` in project.godot). class_name dropped per ADR-0001.
extends Node
# Tracks which bodies the player has personally scanned/discovered. Persists to
# user://codex.json so progress survives restarts. The Details panel reveals full
# NASA data only once a body is discovered, giving exploration a payoff.

const FILE := "codex.json"

var _found := {}      # body name -> true


func _ready() -> void:
	_load()


# Returns true only if this is a NEW discovery (for the toast).
func discover(name: String) -> bool:
	if name == "" or _found.has(name):
		return false
	_found[name] = true
	_save()
	return true

func is_discovered(name: String) -> bool:
	return _found.has(name)

func count() -> int:
	return _found.size()

# Total named bodies across every system (the discovery denominator).
func total() -> int:
	var names := {}
	for id in SystemDB.all():
		for b in SystemDB.bodies(id):
			names[b.name] = true
	for s in Ephemeris.STARS:
		names[s.name] = true
	return names.size()

# All body names, in system order, with discovered state (for the codex panel).
func entries() -> Array:
	var out := []
	var seen := {}
	for id in SystemDB.all():
		for b in SystemDB.bodies(id):
			if not seen.has(b.name):
				seen[b.name] = true
				out.append({ "name": b.name, "system": SystemDB.display_name(id),
					"found": _found.has(b.name) })
	for s in Ephemeris.STARS:
		if not seen.has(s.name):
			seen[s.name] = true
			out.append({ "name": s.name, "system": "Nearby Stars", "found": _found.has(s.name) })
	return out


func _load() -> void:
	if not FileAccess.file_exists(ProfileDir.path(FILE)):
		return
	var f := FileAccess.open(ProfileDir.path(FILE), FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		_found = data

func _save() -> void:
	var f := FileAccess.open(ProfileDir.path(FILE), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_found))
