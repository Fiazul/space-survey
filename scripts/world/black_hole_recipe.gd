class_name BlackHoleRecipe
extends RefCounted
# GRAVITY 2021: https://www.eso.org/public/news/eso2119/
# Kerr metric: Bardeen, Press & Teukolsky 1972 (ApJ 178, 347). Lengths are
# km; disk_*_radii are in gravitational radii r_g = GM/c^2.
const C_KM_S := 299792.458
const GM_SUN := 132712440018.0

static func resolve(spec: Dictionary) -> Dictionary:
	var mass := maxf(float(spec.get("stellar", {}).get("mass_solar", 4.30e6)), 1.0)
	var spin := clampf(float(spec.get("stellar", {}).get("spin", 0.9)), 0.0, 0.998)
	var gm := GM_SUN * mass
	var r_g := gm / (C_KM_S * C_KM_S)
	var horizon := r_g * (1.0 + sqrt(1.0 - spin * spin))
	var z1 := 1.0 + pow(1.0 - spin * spin, 1.0 / 3.0) * (pow(1.0 + spin, 1.0 / 3.0) + pow(1.0 - spin, 1.0 / 3.0))
	var z2 := sqrt(3.0 * spin * spin + z1 * z1)
	var isco := r_g * (3.0 + z2 - sqrt((3.0 - z1) * (3.0 + z1 + 2.0 * z2)))
	var photon_pro := r_g * 2.0 * (1.0 + cos(2.0 / 3.0 * acos(-spin)))
	var photon_retro := r_g * 2.0 * (1.0 + cos(2.0 / 3.0 * acos(spin)))
	var marginally_bound := r_g * (2.0 - spin + 2.0 * sqrt(1.0 - spin))
	var horizon_rate := spin * C_KM_S / (2.0 * horizon)
	var name := str(spec.get("name", "Black Hole"))
	return {"name": name, "kind": "star", "source": "black-hole-recipe",
		"seed": float(posmod(name.hash(), 10000)) * .017,
		"color_a": Color.BLACK, "color_b": Color.BLACK, "features": [],
		"land_amount": 0.0, "cloud_amount": 0.0, "ice_amount": 0.0, "air_amount": 0.0,
		"city_amount": 0.0, "water_shine": 0.0, "surface": {"solid": false},
		"materials": {"crust": [], "ocean": [], "atmosphere": [], "salvage": []},
		"evidence": "GRAVITY mass; Kerr a=%.2f null geodesics; enhanced accretion emission" % spin,
		"stellar": {"type": "black_hole", "spectral": "SMBH", "mass_solar": mass,
			"radius_km": horizon, "radius_solar": horizon / 695700.0,
			"temperature_k": 0.0, "luminosity_solar": 0.0, "activity": 0.0, "mode": 5,
			"estimated": false, "composition": [],
			"brightness": 0.0, "display_color": Color.BLACK, "display_hot_color": Color.BLACK,
			"visual": {"sensor_mode": "enhanced_visible", "wind_nebula": false, "debris_disk": false},
			"spin": spin, "gravitational_radius_km": r_g,
			"horizon_km": horizon, "isco_km": isco,
			"photon_sphere_km": photon_pro, "photon_orbit_retro_km": photon_retro,
			"marginally_bound_km": marginally_bound, "horizon_angular_velocity_rad_s": horizon_rate,
			"disk_inner_radii": isco / r_g, "disk_outer_radii": 36.0,
			"view_park_km": 7.9 * 149597870.7}}
