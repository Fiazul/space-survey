class_name SurfaceFacility
extends RefCounted
## Earth geography is sourced; the abandoned compound and ship pad are game adaptations.
const EARTH_SITES := [{"id": "kennedy_lc39a", "name": "KENNEDY / LC-39A", "operator": "NASA / SpaceX",
	"lat_deg": 28.608402, "lon_deg": -80.604201, "radius_km": 6371.0,
	"source": "https://netspublic.grc.nasa.gov/main/20190807_Final_DRAFT_EA_SpaceX_Starship.pdf"},
	{"id":"wenchang","name":"WENCHANG","operator":"China / Wenchang Space Launch Site",
	"lat_deg":19.6144917,"lon_deg":110.9511333,"radius_km":6371.0,
	"source":"https://www.wikidata.org/wiki/Q1246624",
	"coordinate_note":"Published site reference coordinate; game apron is fictional, not a surveyed pad replica."}]
const PAD := AABB(Vector3(-.13, -.012, -.13), Vector3(.26, .012, .26))
const FOOTPRINT_KM := 1.05 # compound plus hull approach and vegetation clearance

static func resolve(recipe: Dictionary, sampler) -> Array:
	var config: Dictionary = recipe.get("surface", {})
	var sites: Array = config.get("facilities", EARTH_SITES if config.get("facility_preset", "") == "earth_spaceports" else [])
	var result := []
	for source in sites:
		var site: Dictionary = source.duplicate(true)
		var up := DevSites.dir_for(float(site.lat_deg), float(site.lon_deg))
		var frame := DevSites.surface_frame(up)
		var axes := Basis(frame.east, up, frame.north)
		var radius := float(site.get("radius_km", 6371.0))
		var height := 0.0
		# The common elevated apron clears all nearby terrain samples, including
		# coarse coastal DEM errors. Rendering and collision share this exact seat.
		for x in [-.72, -.36, 0.0, .36, .72]:
			for z in [-.66, -.33, 0.0, .33, .66]:
				var dir := (up*radius + axes*Vector3(x,0,z)).normalized()
				height = maxf(height, sampler.height_m(dir)/1000.0)
		site["dir"] = up
		site["transform"] = Transform3D(axes, up*(radius+height+.025))
		site["parts"] = parts()
		result.append(site)
	return result

# Every collidable piece is a shared box recipe; no invisible oversized sphere.
static func parts() -> Array:
	var out := [{"box": AABB(Vector3(-.73,-.060,-.66),Vector3(1.46,.047,1.32)), "material":0},
		{"box":PAD,"material":1},
		{"box":AABB(Vector3(.22,.087,-.23),Vector3(.075,.012,.025)),"material":2},
		{"box":AABB(Vector3(-.38,-.013,-.27),Vector3(.19,.045,.09)),"material":0},
		{"box":AABB(Vector3(-.38,.032,-.27),Vector3(.19,.006,.025)),"material":2},
		{"box":AABB(Vector3(-.34,-.013,.19),Vector3(.14,.026,.10)),"material":0},
		{"box":AABB(Vector3(.23,-.013,.17),Vector3(.065,.037,.065)),"material":0}]
	for z in [-.31,-.275]:
		out.append({"box":AABB(Vector3(.06,-.013,z),Vector3(.032,.04,.024)),"material":3})
	# Open service tower, hangar facade and repeated framing stay procedural.
	for x in [.22,.243]:
		for z in [-.23,-.207]:
			out.append({"box":AABB(Vector3(x,-.013,z),Vector3(.004,.115,.004)),"material":2})
	for y in [.005,.03,.055,.08,.10]:
		out.append({"box":AABB(Vector3(.22,y,-.23),Vector3(.027,.003,.027)),"material":3})
	out.append({"box":AABB(Vector3(-.355,-.012,-.179),Vector3(.14,.036,.002)),"material":2})
	for x in [-.35,-.315,-.28,-.245,-.21]:
		out.append({"box":AABB(Vector3(x,-.012,-.177),Vector3(.002,.036,.002)),"material":3})
	# Keep a 700 m approach square clear. Move visible geometry and its exact
	# collision together; the pad never needs an invisible collision exemption.
	for i in range(2,out.size()):
		var box: AABB = out[i].box
		var center := box.get_center()
		box.position += Vector3(signf(center.x)*.30,0,signf(center.z)*.30)
		out[i].box = box
	return out

static func occupied(sites: Array, dir: Vector3, radius: float) -> bool:
	for site in sites:
		if dir.distance_squared_to(site.dir)*radius*radius < FOOTPRINT_KM*FOOTPRINT_KM:
			return true
	return false

# Site-local coordinates of a body-frame point. Subtract the site origin first:
# both are ~6371 km float32 vectors, so the difference is exact, while
# affine_inverse()*point adds two rounded Earth-radius terms (a 0.5 m error).
static func to_site(site: Dictionary, point: Vector3) -> Vector3:
	var xf: Transform3D = site.transform
	return xf.basis.inverse()*(point-xf.origin)

static func pad_at(sites: Array, center: Vector3, pose: Basis, feet: PackedVector3Array) -> Dictionary:
	var site := approach_at(sites,center,pose,feet)
	if site.is_empty(): return {}
	for foot in feet:
		var point := to_site(site, center+pose*foot)
		if point.y < -.002 or point.y > .0025: return {}
	return site

# Contact may be confirmed across a small support gap; the berth holds the feet
# on the deck instead. Returns the body-frame move: it is sub-metre, so callers
# apply it as a displacement, never by rebuilding an Earth-radius position.
static func seat_offset(site: Dictionary, center: Vector3, pose: Basis, feet: PackedVector3Array, skin: float) -> Vector3:
	var xf: Transform3D = site.transform
	var lowest := INF
	for foot in feet:
		lowest = minf(lowest, to_site(site, center+pose*foot).y)
	return Vector3.ZERO if lowest == INF else xf.basis.y.normalized()*(skin-lowest)

# This checks lateral fit and level attitude only. Assistance can allow a
# controlled descent here, but this is never evidence of actual touchdown.
static func approach_at(sites: Array, center: Vector3, pose: Basis, feet: PackedVector3Array) -> Dictionary:
	if feet.is_empty(): return {}
	for site in sites:
		var p := to_site(site, center)
		if absf(p.x) > .2 or absf(p.z) > .2 or p.y < 0 or p.y > .5: continue
		if (site.transform.basis.inverse()*pose).y.dot(Vector3.UP) < .97: continue
		var fits := true
		for foot in feet:
			var point := to_site(site, center+pose*foot)
			if absf(point.x) > .125 or absf(point.z) > .125:
				fits = false
		if fits: return site
	return {}

static func collide(sites: Array, from: Vector3, to: Vector3, velocity: Vector3,
		skin: float, hull_basis := Basis.IDENTITY, half := Vector3.ZERO) -> Dictionary:
	var result := {"hit":false,"position":to,"velocity":velocity,"normal":Vector3.ZERO,"budget_limited":false}
	var first := 2.0
	for site in sites:
		var xf: Transform3D = site.transform
		var a := to_site(site, from)
		var b := to_site(site, to)
		var basis := xf.basis.inverse()*hull_basis
		var padding := Vector3.ONE*skin + basis.x.abs()*half.x + basis.y.abs()*half.y + basis.z.abs()*half.z
		var broad := AABB(Vector3(-.8,-.1,-.8)-padding,Vector3(1.6,.3,1.6)+padding*2)
		if SurfaceSettlement.box_contact(a,b,broad).is_empty(): continue
		for part in site.parts:
			var box: AABB = part.box
			var hit := SurfaceSettlement.box_contact(a,b,AABB(box.position-padding,box.size+padding*2))
			if hit.is_empty() or float(hit.t) >= first: continue
			first = hit.t
			var normal: Vector3 = xf.basis*hit.normal
			result.hit = true
			result.normal = normal
			result.position = xf*(a.lerp(b,first)+hit.normal*float(hit.push))
			var inward := minf(velocity.dot(normal),0.0)
			result.velocity = velocity-normal*inward
	return result
