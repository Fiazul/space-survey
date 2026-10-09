class_name TestBlackHoleViews
extends Node3D

var failures := 0
var camera: Camera3D
var hole: MeshInstance3D
var output := "/tmp/astryx-black-hole-views"

class CoreWorld extends PlanetSystem:
	func _ready() -> void:
		_dot_tex = _make_dot_texture()
		load_system(Ephemeris.live_worlds())

func _ready() -> void:
	ProfileDir.isolate("test_black_hole_views")
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute(output)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(.005,.005,.008)
	add_child(world)
	camera = Camera3D.new()
	camera.near = .05
	camera.far = 1020000.0
	camera.fov = 70.0
	add_child(camera)
	camera.make_current()
	var recipe := BlackHoleRecipe.resolve(SystemDB.star_row(SystemDB.SAGITTARIUS_A))
	hole = BlackHoleRenderer.paint(recipe).sphere
	var horizon: float = recipe.stellar.horizon_km
	add_child(hole)
	var observer := Vector3(1.0,.12,0).normalized()*.572*149597870.7
	BlackHoleRenderer.update(hole,-observer,horizon,0.0)
	camera.look_at(Vector3(1,-.22,0),Vector3.UP)
	var outward := await capture("outward_inside_flow")
	var plasma := plasma_pixels(outward)
	print("black_hole_views: outward plasma pixels ",plasma)
	check("outward view inside the flow is not cut off",plasma > 2000)
	camera.rotate_object_local(Vector3.FORWARD,deg_to_rad(33.0))
	var rolled := await capture("rolled_inside_flow")
	check("rolled outward flow remains visible",plasma_pixels(rolled) > 2000)
	observer = Vector3(1.0,.12,0).normalized()*2.0*149597870.7
	BlackHoleRenderer.update(hole,-observer,horizon,0.0)
	camera.look_at(-observer,Vector3.UP)
	var foreground := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(.45,.45)
	foreground.mesh = quad
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(.01,1.0,1.0,.8)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	foreground.material_override = material
	add_child(foreground)
	foreground.position = camera.project_position(Vector2(640,240),2.0)
	foreground.basis = camera.basis
	var plume := await capture("transparent_foreground")
	var pixel := plume.get_pixel(640,240)
	print("black_hole_views: foreground plume ",pixel)
	check("black hole does not erase transparent foreground exhaust",pixel.g > .5 and pixel.b > .5 and pixel.b > pixel.r*1.3)
	foreground.free()
	var clean := await capture("before_heat_shimmer")
	var approaching := 0.0
	var receding := 0.0
	var blue := [0.0, 0.0]
	var red := [0.0, 0.0]
	for y in range(250,470):
		for x in range(390,890):
			var lit := clean.get_pixel(x,y)
			var side := 1 if x >= 640 else 0
			if side == 1: approaching += lit.r+lit.g+lit.b
			else: receding += lit.r+lit.g+lit.b
			if lit.r > .1:
				blue[side] += lit.b
				red[side] += lit.r
	var whiteness: Array = [blue[0]/maxf(red[0],.001), blue[1]/maxf(red[1],.001)]
	print("black_hole_views: approaching/receding light ",approaching/maxf(receding,.001)," blue/red receding ",whiteness[0]," approaching ",whiteness[1])
	check("Kerr beaming brightens the approaching side (-z, screen right)",approaching > receding*1.3)
	check("colour temperature T*g makes the approaching side whiter",whiteness[1] > whiteness[0]*1.15)
	var haze := MeshInstance3D.new()
	haze.mesh = quad
	var heat := ShaderMaterial.new()
	heat.shader = ShipMesh.EXHAUST_HAZE_SHADER
	heat.render_priority = -1
	heat.set_shader_parameter("power",1.0)
	heat.set_shader_parameter("strength",0.0)
	heat.set_shader_parameter("screen_refraction_enabled",false)
	haze.material_override = heat
	add_child(haze)
	haze.position = camera.project_position(Vector2(640,260),2.0)
	haze.basis = camera.basis
	var shimmer := await capture("heat_shimmer_over_lens")
	var a := clean.get_pixel(640,260)
	var b := shimmer.get_pixel(640,260)
	check("heat shimmer does not punch a stale-background hole through the lens",absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b) < .025)
	haze.free()
	var backdrop := MeshInstance3D.new()
	var large := QuadMesh.new()
	large.size = Vector2(1800000.0,1800000.0)
	backdrop.mesh = large
	var backdrop_mat := StandardMaterial3D.new()
	backdrop_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	backdrop_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	backdrop_mat.albedo_color = Color(.05,.3,.5,1.0)
	backdrop_mat.render_priority = -110
	backdrop.material_override = backdrop_mat
	add_child(backdrop)
	camera.look_at((-observer).normalized().rotated(Vector3.UP,deg_to_rad(75.0)),Vector3.UP)
	backdrop.basis = camera.basis
	backdrop.position = -camera.basis.z*700000.0
	var dark := Image.create(2,2,false,Image.FORMAT_RGB8)
	dark.fill(Color.BLACK)
	(hole.material_override as ShaderMaterial).set_shader_parameter("background_texture",ImageTexture.create_from_image(dark))
	(hole.material_override as ShaderMaterial).set_shader_parameter("use_core_background",true)
	var edge := await capture("lens_background_transition")
	var edge_jump := 0.0
	for x in range(600,1100):
		var left := edge.get_pixel(x,360)
		var right := edge.get_pixel(x+1,360)
		# Fine orange plasma filaments can vary sharply; measure the blue
		# background transition, rather than the physical emitting surface.
		if left.r > left.b*1.5+.02 or right.r > right.b*1.5+.02: continue
		edge_jump = maxf(edge_jump,absf(left.b-right.b))
	print("black_hole_views: background edge jump ",edge_jump)
	check("weak lens boundary has no hard screen-cut seam",edge_jump < .03)
	# Sky drawn before the lens must reach the eye through the disk only bent,
	# via the lensed background, never straight through the plasma.
	camera.look_at(-observer,Vector3.UP)
	backdrop.basis = camera.basis
	backdrop.position = -camera.basis.z*700000.0
	var through := await capture("disk_over_backdrop")
	backdrop.visible = false
	var plain := await capture("disk_without_backdrop")
	backdrop.visible = true
	var disk := 0
	var leaked := 0
	for y in range(200,520,2):
		for x in range(100,1180,2):
			var bare := plain.get_pixel(x,y)
			if bare.r < .1: continue
			disk += 1
			if through.get_pixel(x,y).b - bare.b > .02: leaked += 1
	print("black_hole_views: straight-through sky over the disk ",leaked,"/",disk)
	check("no straight-through sky over the plasma",disk > 5000 and leaked < disk*.005)
	observer = Vector3(1.0,.12,0).normalized()*7.9*149597870.7
	var inward := -observer.normalized()
	camera.look_at(inward.rotated(Vector3.UP,deg_to_rad(35.0)),Vector3.UP)
	BlackHoleRenderer.update(hole,-observer,horizon,0.0)
	backdrop.basis = camera.basis
	backdrop.position = -camera.basis.z*700000.0
	var target := camera.unproject_position(inward.rotated(Vector3.UP,deg_to_rad(-12.7))*700000.0)
	var off_axis := await capture("far_off_axis_aperture")
	pixel = off_axis.get_pixelv(Vector2i(target))
	print("black_hole_views: off-axis aperture sample ",pixel," at ",target)
	check("far off-axis aperture covers the physical ray cone",pixel.b > .01 and pixel.b < .43)
	backdrop.free()
	await check_kerr_shadow(recipe)
	hole.free()
	Ephemeris.switch_system(SystemDB.SAGITTARIUS_A)
	var cluster: Dictionary = Ephemeris.live_worlds().filter(func(b): return b.name != "Sagittarius A*")[0]
	observer = -Ephemeris.scene_pos(cluster.name).normalized()*2.0*149597870.7
	camera.look_at(-observer,Vector3.UP)
	var core_world := CoreWorld.new()
	add_child(core_world)
	core_world.refresh(observer,0.0,"Sagittarius A*")
	for body in core_world._bodies: body.label.visible = false
	var shadow := await capture("physical_star_behind_shadow")
	pixel = shadow.get_pixel(640,360)
	print("black_hole_views: shadow over background cluster star ",pixel)
	check("physical background star cannot shine through the black-hole shadow",pixel.r+pixel.g+pixel.b < .08)
	core_world.free()
	print("black_hole_views: ","OK" if failures == 0 else "FAIL %d" % failures)
	get_tree().quit(1 if failures else 0)

# Edge-on, no disk, white sky: the shadow's equatorial edges sit at the impact
# parameters of the prograde and retrograde photon orbits (Bardeen 1973).
func check_kerr_shadow(recipe: Dictionary) -> void:
	var stellar: Dictionary = recipe.stellar
	var rg: float = stellar.gravitational_radius_km
	var a: float = stellar.spin
	var material := hole.material_override as ShaderMaterial
	material.set_shader_parameter("disk_outer",float(stellar.disk_inner_radii))
	var white := Image.create(2,2,false,Image.FORMAT_RGB8)
	white.fill(Color.WHITE)
	material.set_shader_parameter("background_texture",ImageTexture.create_from_image(white))
	material.set_shader_parameter("use_core_background",true)
	var distance_rg := 200.0
	var observer := Vector3.RIGHT*distance_rg*rg
	camera.fov = 6.0
	camera.look_at(Vector3.LEFT,Vector3.UP)
	BlackHoleRenderer.update(hole,-observer,float(stellar.horizon_km),0.0)
	var shot := await capture("kerr_shadow_edge_on")
	var focal := 360.0/tan(deg_to_rad(camera.fov*.5))
	var right := 640
	while right < 1279 and shot.get_pixel(right+1,360).r < .5: right += 1
	var left := 639
	while left > 0 and shot.get_pixel(left-1,360).r < .5: left -= 1
	var right_b := distance_rg*sin(atan((float(right)+1.0-640.0)/focal))
	var left_b := distance_rg*sin(atan((640.0-float(left))/focal))
	var pro := impact_of_photon_orbit(stellar.photon_sphere_km/rg,a)
	var retro := impact_of_photon_orbit(stellar.photon_orbit_retro_km/rg,a)
	print("black_hole_views: Kerr shadow edges %.3f / %.3f r_g, closed form %.3f / %.3f" % [right_b,left_b,absf(pro),absf(retro)])
	check("prograde (approaching) shadow edge is flattened to the Kerr photon orbit",absf(right_b/absf(pro)-1.0) < .03)
	check("retrograde shadow edge matches the Kerr photon orbit",absf(left_b/absf(retro)-1.0) < .03)
	camera.fov = 70.0

static func impact_of_photon_orbit(r: float, a: float) -> float:
	return -(r*r*r - 3.0*r*r + a*a*r + a*a)/(a*(r - 1.0))

func capture(label: String) -> Image:
	for i in 5: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var shot := get_viewport().get_texture().get_image()
	shot.save_png(output.path_join(label+".png"))
	return shot

func plasma_pixels(shot: Image) -> int:
	var count := 0
	for y in range(80,640):
		for x in range(160,1120):
			var pixel := shot.get_pixel(x,y)
			if pixel.r > .1 and pixel.r > pixel.b*2.0 and pixel.g > .02: count += 1
	return count

func check(label: String, ok: bool) -> void:
	if ok: return
	failures += 1
	push_error(label)
