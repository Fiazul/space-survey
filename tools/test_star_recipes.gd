extends Node3D
var failures := 0
class StarScene extends PlanetSystem:
	func _ready() -> void:
		_dot_tex = _make_dot_texture()
func _ready() -> void:
	for row in Ephemeris.STARS:
		check("sky star has spectral metadata "+row.name, not SystemDB.spectral(SystemDB.id_for_name(row.name)).is_empty())
	for row in SystemDB.STARS+SystemDB.AUTHORED:
		var spec := PlanetGenerator.catalog_star(row)
		var a := PlanetGenerator.recipe_for(spec)
		var b := PlanetGenerator.recipe_for(spec)
		check("deterministic "+row.name, a == b)
		check("valid physical metadata "+row.name, a.stellar.radius_km > 0 and a.stellar.temperature_k > 0 and a.stellar.luminosity_solar > 0)
		check("stars aren't landable/minable", not preload("res://scripts/world/surface_recipe.gd").resolve(a).solid and a.materials.crust.is_empty())
	for pair in [["F5IV","subgiant"],["M1.5VI","subdwarf"],["K3III","giant"],["A2II","bright_giant"],["M2Iab","supergiant"],["DQ6","white_dwarf"],["DZ7","white_dwarf"],["L8","brown_dwarf"],["T9","brown_dwarf"],["Y1","brown_dwarf"],["WC8","wolf_rayet"],["C5","carbon_star"]]:
		check("classify "+pair[0], StarRecipe.resolve({"spectral":pair[0]}).stellar.type == pair[1])
	for family in ["neutron_star","pulsar","magnetar"]:
		var compact := StarRecipe.resolve({"stellar_type":family})
		check("compact radius", is_equal_approx(compact.stellar.radius_km,12.0))
		check("compact hazards", StarRecipe.exposure(compact,20,1).radiation_index > 1)
	var sun := StarRecipe.resolve({"name":"Sun"})
	var earth := StarRecipe.exposure(sun,149597870.7,695700)
	check("solar flux at Earth about 1361 W/m²", absf(earth.flux_w_m2-1361) < 5)
	check("Earth isn't a heat hazard", earth.level == 0)
	var close := StarRecipe.exposure(sun,695700*10,695700)
	var far := StarRecipe.exposure(sun,695700*20,695700)
	check("inverse square radiation", is_equal_approx(close.flux_w_m2/far.flux_w_m2,4))
	check("approach warning", close.level >= 2)
	check("photosphere warning", StarRecipe.exposure(sun,695700,695700).level == 3)
	check("compressed arena keeps dimensionless flux", is_equal_approx(close.flux_w_m2,StarRecipe.exposure(sun,50,5).flux_w_m2))
	var hot := StarRecipe.resolve({"spectral":"O5V"})
	var cool := StarRecipe.resolve({"spectral":"M8V"})
	var brown := StarRecipe.resolve({"spectral":"T8"})
	check("hot stars are bluer", hot.color_a.b > hot.color_a.r and cool.color_a.r > cool.color_a.b)
	check("dwarf size ordering", hot.stellar.radius_km > sun.stellar.radius_km and sun.stellar.radius_km > cool.stellar.radius_km)
	check("brown dwarfs dimmer", brown.stellar.brightness < cool.stellar.brightness)
	var authored := StarRecipe.resolve({"spectral":"M5V", "stellar":{"temperature_k":3100,"radius_solar":.15,"mass_solar":.12}})
	check("explicit measurements override estimates", authored.stellar.temperature_k == 3100 and authored.stellar.radius_solar == .15)
	var bad := StarRecipe.resolve({"stellar":{"temperature_k":NAN,"radius_solar":-1,"mass_solar":0}})
	check("invalid overrides cannot poison physics", is_finite(bad.stellar.temperature_k) and bad.stellar.radius_km > 0 and bad.stellar.mass_solar > 0)
	var look := PlanetGenerator.paint({"star":true,"spectral":"DQ6"},1)
	check("actual shader uses dwarf surface", int(look.mat.get_shader_parameter("stellar_mode")) == 2)
	check("corona is a single mesh", look.sphere.get_child_count() == 1)
	look.sphere.free()
	var scene := StarScene.new()
	add_child(scene)
	scene.load_system([PlanetGenerator.catalog_star({"name":"Test sun","spectral":"G2V"})])
	var radius: float = scene._bodies[0].radius
	scene.refresh(Vector3(0,0,radius*2),.016)
	check("runtime approach warns", scene.stellar_hazard.level >= 2 and scene._bodies[0].sphere.visible)
	scene.refresh(Vector3(0,0,radius*1000),.016)
	check("runtime withdrawal clears warning", scene.stellar_hazard.level == 0)
	var info := PlanetInfo.new()
	add_child(info)
	info.planets = scene
	info.codex = null # bypass discovery only in the fixture; don't mutate saved discovery
	info.open_for("Test sun")
	check("scan details include stellar model", "Main Sequence" in info._title.text and info._body.get_child_count() >= 7)
	info._close()
	info.queue_free()
	scene.load_system([])
	check("system change clears stellar readout", scene.stellar_hazard.is_empty())
	scene.queue_free()
	await get_tree().process_frame
	print("star_recipes: ", "OK" if failures == 0 else "FAIL %d" % failures)
	get_tree().quit(1 if failures else 0)
func check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
		push_error(label)
