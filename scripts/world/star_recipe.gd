class_name StarRecipe
extends RefCounted
## Physical estimates and display parameters are deliberately separate.
## Calibration and approximation limits: docs/STAR_RECIPES.md.
const SOLAR_RADIUS_KM := 695700.0
const SIGMA := 5.670374419e-8
# Representative dwarf anchors: Teff K, radius / Sun, mass / Sun.
const DWARFS := {
	"O": [44000.0, 13.0, 58.0], "B": [31000.0, 7.2, 17.7],
	"A": [9700.0, 2.19, 2.18], "F": [7220.0, 1.73, 1.61],
	"G": [5930.0, 1.10, 1.06], "K": [5270.0, .81, .88],
	"M": [3850.0, .59, .57], "L": [2300.0, .10, .07],
	"T": [1300.0, .10, .04], "Y": [450.0, .10, .02],
}
const SEQUENCE := "OBAFGKMLTY"
# Late M dwarfs shrink steeply; one linear M→L span greatly oversizes Proxima.
const M_ANCHORS := [[0.0,3850.0,.59,.57], [5.0,3060.0,.196,.162],
	[5.5,2930.0,.156,.123], [8.0,2570.0,.114,.085], [10.0,2300.0,.10,.07]]

static func resolve(spec: Dictionary) -> Dictionary:
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
	var mode := 0 # photosphere, brown bands, white dwarf, neutron remnant
	var activity := .3
	var cells := 36.0
	var spots := .15
	match family:
		"subdwarf": radius *= .75
		"subgiant": radius *= 2.0
		"giant", "bright_giant", "supergiant", "carbon_star":
			radius = 25.0 if family == "giant" else (70.0 if family == "bright_giant" else 500.0)
			mass = 2.0 if family in ["giant", "carbon_star"] else 15.0
			if family == "carbon_star": temperature = 2800.0; radius = 200.0
			cells = 7.0
			activity = .55
		"brown_dwarf":
			mode = 1; activity = .08; spots = 0.0
		"white_dwarf":
			temperature = 50400.0/maxf(subtype, 1.0)
			radius = .012; mass = .6; mode = 2; activity = .02; spots = 0.0
		"wolf_rayet":
			temperature = 65000.0; radius = 5.0; mass = 20.0; activity = 1.0; cells = 12.0
		"neutron_star", "pulsar", "magnetar":
			temperature = 600000.0; radius = 12.0/SOLAR_RADIUS_KM; mass = 1.4
			mode = 3; activity = 1.0; spots = 0.0
			if not spec.has("spectral"): sp = "REMNANT"
	if letter == "M" and family in ["main_sequence", "subdwarf"]:
		activity = .75; spots = .35
	if letter in ["O", "B", "A"]: spots = .02; cells = 60.0
	var solar := name in ["Sun", "Sol"]
	if solar:
		temperature = 5772.0; radius = 1.0; mass = 1.0
	temperature = _positive(overrides.get("temperature_k", temperature), temperature)
	radius = _positive(overrides.get("radius_solar", radius), radius)
	mass = _positive(overrides.get("mass_solar", mass), mass)
	activity = clampf(float(overrides.get("activity", activity)), 0, 1)
	var color := color_at(temperature)
	var stellar := {
		"type": family, "spectral": sp, "temperature_k": temperature,
		"radius_solar": radius, "radius_km": radius*SOLAR_RADIUS_KM, "mass_solar": mass,
		"luminosity_solar": radius*radius*pow(temperature/5772.0, 4),
		"activity": activity, "mode": mode, "cells": cells, "spots": spots,
		"brightness": clampf(pow(temperature/5772.0, 1.2), .015, 1.4),
		"estimated": not solar, "composition": ["hydrogen", "helium"],
	}
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
	# Display palette; not a photometric colour/false claim of blackbody integration.
	var knots := [800.0, 2300.0, 3800.0, 5772.0, 9700.0, 30000.0]
	var colors := [Color(.32,.055,.015), Color(1,.38,.14), Color(1,.66,.40),
		Color(1,.95,.86), Color(.82,.88,1), Color(.56,.71,1)]
	for i in range(1,knots.size()):
		if temperature < knots[i]:
			return colors[i-1].lerp(colors[i], clampf((temperature-knots[i-1])/(knots[i]-knots[i-1]),0,1))
	return colors[-1]

static func scene_radius(recipe: Dictionary) -> float:
	# Legacy non-Sol arenas use compressed distances. Never insert km into those layouts.
	return clampf(5.0*pow(float(recipe.stellar.radius_solar), .45), .12, 16.0)

static func exposure(recipe: Dictionary, distance: float, rendered_radius: float) -> Dictionary:
	var s: Dictionary = recipe.stellar
	var ratio := maxf(distance/maxf(rendered_radius, .000001), 1.0)
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
