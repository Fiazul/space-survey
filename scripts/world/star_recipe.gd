class_name StarRecipe
extends RefCounted
## Physical estimates and display parameters are deliberately separate.
## Calibration and approximation limits: docs/STAR_RECIPES.md.
const SOLAR_RADIUS_KM := 695700.0
const SIGMA := 5.670374419e-8
# Sun HDR brightness control; the shader compresses photosphere exposure.
const SUN_BRIGHTNESS_MULTIPLIER := 1
# Representative dwarf anchors: Teff K, radius / Sun, mass / Sun.
const DWARFS := {
	"O": [44000.0, 13.0, 58.0], "B": [31000.0, 7.2, 17.7],
	"A": [9700.0, 2.19, 2.18], "F": [7220.0, 1.73, 1.61],
	"G": [5930.0, 1.10, 1.06], "K": [5270.0, .81, .88],
	"M": [3850.0, .59, .57], "L": [2300.0, .10, .07],
	"T": [1300.0, .10, .04], "Y": [450.0, .10, .02],
}
const SEQUENCE := "OBAFGKMLTY"
static var _color_cache: Dictionary = {}
# Late M dwarfs shrink steeply; one linear M→L span greatly oversizes Proxima.
const M_ANCHORS := [[0.0,3850.0,.59,.57], [5.0,3060.0,.196,.162],
	[5.5,2930.0,.156,.123], [8.0,2570.0,.114,.085], [10.0,2300.0,.10,.07]]

static func resolve(spec: Dictionary) -> Dictionary:
	if spec.get("stellar_type", "") == "black_hole" or spec.get("stellar", {}).get("type", "") == "black_hole":
		return BlackHoleRecipe.resolve(spec)
	var name := str(spec.get("name", "Star"))
	var sp := str(spec.get("spectral", "G2V")).strip_edges().to_upper()
	var overrides: Dictionary = spec.get("stellar", {})
	var letter := sp.left(1)
	var subtype := _subtype(sp)
	var family := str(overrides.get("type", spec.get("stellar_type", "")))
	if family.is_empty():
		if letter == "D": family = "white_dwarf"
		elif letter in ["L", "T", "Y"]: family = "brown_dwarf"
		elif letter == "W": family = "wolf_rayet"
		elif letter == "C": family = "carbon_star"
		elif "VI" in sp: family = "subdwarf"
		elif "IV" in sp: family = "subgiant"
		elif "III" in sp: family = "giant"
		elif "II" in sp: family = "bright_giant"
		elif "I" in sp: family = "supergiant"
		else: family = "main_sequence"
	var anchor: Array = DWARFS.get(letter, DWARFS.G)
	var next_index := SEQUENCE.find(letter)+1
	var next: Array = DWARFS.get(SEQUENCE.substr(next_index, 1), anchor)
	var t := clampf(subtype/10.0, 0, 1)
	var temperature := lerpf(anchor[0], next[0], t)
	var radius := lerpf(anchor[1], next[1], t)
	var mass := lerpf(anchor[2], next[2], t)
	if letter == "M":
		for i in range(1, M_ANCHORS.size()):
			if subtype <= M_ANCHORS[i][0]:
				var low: Array = M_ANCHORS[i-1]
				var high: Array = M_ANCHORS[i]
				var mix_t := clampf((subtype-low[0])/(high[0]-low[0]),0,1)
				temperature = lerpf(low[1],high[1],mix_t)
				radius = lerpf(low[2],high[2],mix_t)
				mass = lerpf(low[3],high[3],mix_t)
				break
	var mode := 0 # photosphere, brown clouds, white dwarf, neutron remnant, stellar wind
	var activity := .3
	var cells := 350.0
	var spots := .15
	match family:
		"subdwarf": radius *= .75
		"subgiant": radius *= 2.0
		"giant", "bright_giant", "supergiant", "carbon_star":
			radius = 25.0 if family == "giant" else (70.0 if family == "bright_giant" else 500.0)
			mass = 2.0 if family in ["giant", "carbon_star"] else 15.0
			if family == "carbon_star": temperature = 2800.0; radius = 200.0
			cells = 5.0
			activity = .55
		"brown_dwarf":
			mode = 1; activity = .08; spots = 0.0
		"white_dwarf":
			temperature = 50400.0/maxf(subtype, 1.0)
			radius = .012; mass = .6; mode = 2; activity = .02; spots = 0.0
		"wolf_rayet":
			temperature = 65000.0; radius = 5.0; mass = 20.0; activity = 1.0; cells = 18.0; mode = 4
		"neutron_star", "pulsar", "magnetar":
			temperature = 600000.0; radius = 12.0/SOLAR_RADIUS_KM; mass = 1.4
			mode = 3; activity = 1.0; spots = 0.0
			if not spec.has("spectral"): sp = "REMNANT"
	if letter == "M" and family in ["main_sequence", "subdwarf"]:
		activity = .75; spots = .35
	if letter in ["O", "B", "A"]: spots = .02
	var solar := name in ["Sun", "Sol"]
	if solar:
		temperature = 5772.0; radius = 1.0; mass = 1.0
	temperature = _positive(overrides.get("temperature_k", temperature), temperature)
	radius = _positive(overrides.get("radius_solar", radius), radius)
	mass = _positive(overrides.get("mass_solar", mass), mass)
	activity = clampf(float(overrides.get("activity", activity)), 0, 1)
	var radiative := smoothstep(7000.0, 10000.0, temperature)
	if mode == 0 and family not in ["giant", "bright_giant", "supergiant", "carbon_star"]:
		cells = clampf(350.0 * pow(radius, .35), 175.0, 1200.0)
		spots *= 1.0 - radiative * .9
		activity *= 1.0 - radiative * .75
	var color := color_at(temperature)
	# Authored HDR display response, independent of the physical flux/hazard model.
	# The extended glow represents camera glare as well as the much fainter corona.
	var brightness := clampf(7.0*pow(temperature/5772.0, .65), 2.5, 14.0)
	if mode == 0:
		brightness = clampf(2.2*pow(temperature/5772.0, .20), 1.8, 3.2)
	if mode == 1:
		brightness = clampf(pow(temperature/5772.0, 1.2), .015, 1.4)
	if solar:
		brightness *= maxf(SUN_BRIGHTNESS_MULTIPLIER, 0.0)
	var stellar := {
		"type": family, "spectral": sp, "temperature_k": temperature,
		"radius_solar": radius, "radius_km": radius*SOLAR_RADIUS_KM, "mass_solar": mass,
		"luminosity_solar": radius*radius*pow(temperature/5772.0, 4),
		"activity": activity, "mode": mode, "cells": cells, "spots": spots,
		"brightness": brightness,
		"limb_floor": .35 if mode == 1 else (.48 if mode == 0 else .72),
		"detail_contrast": lerpf(.32, .025, radiative) if mode == 0 else .20,
		"cool_color": color_at(temperature * .94), "hot_color": color_at(temperature * 1.06),
		"corona_strength": brightness*(.11+activity*.32) if mode == 0 else
			(brightness*.025 if mode == 1 else (.075 if mode == 2 else (.22 if mode == 3 else .6))),
		"corona_extent": 2.8,
		"corona_falloff": 9.0 if mode in [1, 2] else (2.6 if mode == 4 else 3.8),
		"estimated": not solar, "composition": ["hydrogen", "helium"],
	}
	stellar["visual"] = _visual(overrides.get("visual", {}), family)
	stellar["display_color"] = color
	stellar["display_hot_color"] = stellar.hot_color
	if family == "brown_dwarf" and stellar.visual.sensor_mode == "enhanced_visible":
		# Reference-inspired atmospheric display; physical continuum stays in color_a.
		stellar.display_color = Color("b12712")
		stellar.display_hot_color = Color("f1763d")
	elif stellar.visual.sensor_mode == "uv":
		stellar.display_color = Color("ba890f")
		stellar.display_hot_color = Color("ffdc70")
	elif stellar.visual.sensor_mode == "xray":
		stellar.display_color = Color("59b5ff")
		stellar.display_hot_color = Color("b6e5ff")
	if family == "white_dwarf": stellar.composition = ["degenerate_carbon_oxygen", "hydrogen_or_helium_envelope"]
	if mode == 3: stellar.composition = ["neutron_rich_matter"]
	if family == "carbon_star": stellar.composition = ["hydrogen", "helium", "carbon"]
	return {"name": name, "kind": "star", "source": "stellar-recipe", "spectral": sp,
		"evidence": "Solar reference" if solar else "catalog spectral %s; estimate / authored overrides" % sp,
		"stellar": stellar, "color_a": color, "color_b": color.darkened(.65),
		"seed": float(posmod(name.hash(),10000))*.017, "features": [],
		"land_amount": 0.0, "cloud_amount": 0.0, "ice_amount": 0.0, "air_amount": 0.0,
		"city_amount": 0.0, "water_shine": 0.0, "surface": {"solid": false},
		"materials": {"crust": [], "ocean": [], "atmosphere": [], "salvage": []}}

static func _visual(authored: Variant, family: String) -> Dictionary:
	var options: Dictionary = authored if authored is Dictionary else {}
	var sensor := str(options.get("sensor_mode", "visible"))
	var issues: Array[String] = []
	var photosphere := family in ["main_sequence", "subdwarf", "subgiant", "giant", "bright_giant", "supergiant", "carbon_star", "wolf_rayet"]
	var remnant := family in ["neutron_star", "pulsar", "magnetar"]
	if sensor not in ["visible", "enhanced_visible", "uv", "xray"] or (sensor == "uv" and not photosphere) or (sensor == "xray" and not remnant):
		issues.append("unsupported sensor mode for family")
		sensor = "visible"
	var result := {"sensor_mode":sensor, "aurora":false, "debris_disk":false, "wind_nebula":false,
		"disk_inner_radii":4.0, "disk_outer_radii":26.0, "wind_extent_radii":0.0,
		"validation":issues}
	for option in ["aurora", "debris_disk", "wind_nebula"]:
		if options.get(option, false) != true:
			continue
		var allowed: bool = (option == "aurora" and family == "brown_dwarf") or (option == "debris_disk" and family == "white_dwarf") or (option == "wind_nebula" and remnant)
		if not allowed:
			issues.append(option + " requires its stellar family")
			continue
		if option == "wind_nebula":
			var extent := _positive(options.get("wind_extent_radii", 0.0), 0.0)
			if sensor != "xray" or extent <= 1.0 or extent > 1e13:
				issues.append("wind_nebula requires xray mode and authored extent (1..1e13 stellar radii)")
				continue
			result.wind_extent_radii = extent
		if option == "debris_disk":
			var inner := _positive(options.get("disk_inner_radii", 4.0), 0.0)
			var outer := _positive(options.get("disk_outer_radii", 26.0), 0.0)
			if inner <= 1.0 or outer <= inner or outer > 10000.0:
				issues.append("debris_disk requires 1 < inner < outer <= 10000 stellar radii")
				continue
			result.disk_inner_radii = inner
			result.disk_outer_radii = outer
		result[option] = true
	return result

static func _subtype(sp: String) -> float:
	var digits := ""
	for c in sp:
		if c in "0123456789.": digits += c
		elif not digits.is_empty(): break
	return float(digits) if not digits.is_empty() else 0.0

static func _positive(value: Variant, fallback: float) -> float:
	var n := float(value)
	return n if is_finite(n) and n > 0 else fallback

static func color_at(temperature: float) -> Color:
	var kelvin := int(round(clampf(temperature if is_finite(temperature) else 5772.0, 500.0, 1000000.0)))
	if _color_cache.has(kelvin):
		return _color_cache[kelvin]
	var xyz := Vector3.ZERO
	var reference := exp(14387769.0 / (550.0 * kelvin)) - 1.0
	for wavelength in range(380, 781, 5):
		var power := pow(550.0 / wavelength, 5.0) * reference / (exp(14387769.0 / (wavelength * kelvin)) - 1.0)
		xyz += _cie_xyz(wavelength) * power
	var rgb := Vector3(
		3.2404542 * xyz.x - 1.5371385 * xyz.y - .4985314 * xyz.z,
		-.9692660 * xyz.x + 1.8760108 * xyz.y + .0415560 * xyz.z,
		.0556434 * xyz.x - .2040259 * xyz.y + 1.0572252 * xyz.z).max(Vector3.ZERO)
	rgb /= maxf(rgb.x, maxf(rgb.y, rgb.z))
	var color := Color(rgb.x, rgb.y, rgb.z).linear_to_srgb()
	if _color_cache.size() >= 256:
		_color_cache.erase(_color_cache.keys()[0])
	_color_cache[kelvin] = color
	return color

# Wyman et al. (2013), CIE 1931 multi-lobe fit: https://cwyman.org/papers/jcgt13_xyzApprox.pdf
static func _cie_xyz(wavelength: float) -> Vector3:
	return Vector3(
		.362 * _cie_lobe(wavelength, 442.0, .0624, .0374) + 1.056 * _cie_lobe(wavelength, 599.8, .0264, .0323) - .065 * _cie_lobe(wavelength, 501.1, .0490, .0382),
		.821 * _cie_lobe(wavelength, 568.8, .0213, .0247) + .286 * _cie_lobe(wavelength, 530.9, .0613, .0322),
		1.217 * _cie_lobe(wavelength, 437.0, .0845, .0278) + .681 * _cie_lobe(wavelength, 459.0, .0385, .0725))

static func _cie_lobe(wavelength: float, center: float, left: float, right: float) -> float:
	var t := (wavelength - center) * (left if wavelength < center else right)
	return exp(-.5 * t * t)

static func scene_radius(recipe: Dictionary) -> float:
	# Legacy non-Sol arenas use compressed distances. Never insert km into those layouts.
	return clampf(5.0*pow(float(recipe.stellar.radius_solar), .45), .12, 16.0)

static func exposure(recipe: Dictionary, distance: float, rendered_radius: float) -> Dictionary:
	var s: Dictionary = recipe.stellar
	var ratio := maxf(distance/maxf(rendered_radius, .000001), 1.0)
	if s.type == "black_hole":
		return {"name": recipe.name, "type": "black_hole", "level": 3 if ratio < 1.1 else (1 if ratio < 3.0 else 0),
			"state": "EVENT HORIZON" if ratio < 1.1 else ("STRONG GRAVITY" if ratio < 3.0 else "NOMINAL"),
			"flux_w_m2": 0.0, "equilibrium_k": 0.0, "radiation_index": 0.0, "radii": ratio}
	var flux := SIGMA*pow(float(s.temperature_k),4)/(ratio*ratio)
	var equilibrium := float(s.temperature_k)/sqrt(2.0*ratio)
	# UV/wind/remnant indices are gameplay proxies, NOT dose in sieverts.
	var uv := clampf((float(s.temperature_k)-4500.0)/25000.0, .005, 1.0)
	var radiation := flux/100000.0*uv*(1.0+float(s.activity)*2.0)
	if int(s.mode) == 3: radiation *= 10.0 if s.type == "magnetar" else 3.0
	var level := 0
	if equilibrium > 500 or radiation > .1: level = 1
	if equilibrium > 900 or radiation > 1: level = 2
	if ratio <= 1.1 or equilibrium > 1800 or radiation > 10: level = 3
	var state := "NOMINAL"
	if level == 1: state = "STELLAR HEAT"
	if level == 2: state = "EXTREME HEAT"
	if radiation > 1: state = "RADIATION HAZARD"
	if ratio <= 1.1: state = "PHOTOSPHERE — PULL AWAY"
	return {"name": recipe.name, "level": level, "state": state, "flux_w_m2": flux,
		"equilibrium_k": equilibrium, "radiation_index": radiation, "radii": ratio}
