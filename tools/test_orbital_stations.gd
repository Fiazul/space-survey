extends SceneTree
var failures := 0
func _initialize() -> void:
	var orbit_script = load("res://scripts/world/station_orbits.gd")
	check("orbital catalogue exists",orbit_script != null)
	if orbit_script == null:
		quit(1)
		return
	var catalog = orbit_script.new()
	var css: Dictionary = catalog.state_at("tiangong",1790208000.0)
	check("official CSS epoch position maps EME2000 to scene",css.position.distance_to(Vector3(-1550.902250285,2159.908107309,6216.928702898))<.002)
	check("official CSS epoch velocity maps EME2000 to scene",css.velocity.distance_to(Vector3(-5.513762569,4.472785285,-2.934444221))<.00001)
	var midpoint: Dictionary = catalog.state_at("tiangong",1790208120.0)
	check("interpolated station stays in low Earth orbit",midpoint.position.length()>6700 and midpoint.position.length()<6900)
	check("station moves along its orbit",midpoint.position.distance_to(css.position)>800)
	var later: Dictionary = catalog.state_at("tiangong",1790208121.0)
	check("reported velocity matches trajectory",(later.position-midpoint.position).distance_to(midpoint.velocity)<.02)
	var iss: Dictionary = catalog.state_at("iss",1789992000.0)
	check("NASA epoch preserved",iss.position.distance_to(Vector3(-6472.64520865952,1453.71970533104,-1488.44544316792))<.002)
	var fallback: Dictionary = catalog.state_at("iss",1900000000.0)
	check("outdated data explicitly marked approximate",fallback.approximate)
	check("fallback remains a bounded orbit",fallback.position.is_finite() and fallback.position.length()>6600 and fallback.position.length()<7000)
	check("unknown station is rejected",catalog.state_at("missing",1790208000.0).is_empty())
	print("orbital_stations: ","OK" if failures==0 else "FAIL %d" % failures)
	quit(0 if failures==0 else 1)
func check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
		push_error(label)
