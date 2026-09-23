extends RefCounted
## Fabrication definitions. Amounts and tiers are initial gameplay tuning. Inventory, unlock persistence and fabrication are consumers.
const C = preload("res://scripts/crafting/material_class.gd").Kind
const Element = preload("res://scripts/crafting/element_def.gd")
const Slot = preload("res://scripts/crafting/recipe_slot.gd")
const Recipe = preload("res://scripts/crafting/recipe_def.gd")

static func elements() -> Dictionary:
	return {
		"titanium": _element("titanium", "Titanium", Element.Phase.SOLID, {C.STRUCTURAL_ALLOY: 0.85, C.RADIATION_SHIELDING: 0.3}),
		"copper": _element("copper", "Copper", Element.Phase.SOLID, {C.STRUCTURAL_ALLOY: 0.3}),
		"nickel": _element("nickel", "Nickel", Element.Phase.SOLID, {C.CATALYST: 0.5, C.STRUCTURAL_ALLOY: 0.55}),
		"niobium": _element("niobium", "Niobium", Element.Phase.SOLID, {C.SUPERCONDUCTOR: 0.85}),
		"quartz": _element("quartz", "Quartz", Element.Phase.SOLID, {C.OPTICS: 0.65, C.SEMICONDUCTOR: 0.35}),
		"water_ice": _element("water_ice", "Water ice", Element.Phase.SOLID, {C.COOLANT: 0.5, C.RADIATION_SHIELDING: 0.4}),
		"hydrogen": _element("hydrogen", "Hydrogen", Element.Phase.GAS, {C.VOLATILE_FUEL: 0.65, C.PROPELLANT: 0.65}),
		"helium": _element("helium", "Helium", Element.Phase.GAS, {C.COOLANT: 0.8, C.PROPELLANT: 0.3}),
		"methane": _element("methane", "Methane", Element.Phase.GAS, {C.VOLATILE_FUEL: 0.5, C.POLYMER: 0.35}),
		"iron": _element("iron", "Iron", Element.Phase.SOLID, {C.STRUCTURAL_ALLOY: 0.45, C.RADIATION_SHIELDING: 0.35}),
		"aluminium": _element("aluminium", "Aluminium", Element.Phase.SOLID, {C.STRUCTURAL_ALLOY: 0.5, C.RADIATION_SHIELDING: 0.3}),
		"silicon": _element("silicon", "Silicon", Element.Phase.SOLID, {C.SEMICONDUCTOR: 0.5}),
		"water": _element("water", "Water", Element.Phase.LIQUID, {C.COOLANT: 0.5, C.RADIATION_SHIELDING: 0.35}),
		"sodium_chloride": _element("sodium_chloride", "Sodium chloride", Element.Phase.SOLID, {}),
		"nitrogen": _element("nitrogen", "Nitrogen", Element.Phase.GAS, {C.PROPELLANT: 0.35, C.COOLANT: 0.4}),
		"oxygen": _element("oxygen", "Oxygen", Element.Phase.GAS, {C.PROPELLANT: 0.4}),
		"argon": _element("argon", "Argon", Element.Phase.GAS, {C.PROPELLANT: 0.5}),
		"reclaimed_polymer": _element("reclaimed_polymer", "Reclaimed polymer", Element.Phase.SOLID, {C.POLYMER: 0.3}),
	}

static func recipes() -> Dictionary:
	return {
		"station_core": _recipe("station_core", 1, [[C.STRUCTURAL_ALLOY, 24, 0.35], [C.RADIATION_SHIELDING, 12, 0.3], [C.SEMICONDUCTOR, 6, 0.35]]),
		"fabricator": _recipe("fabricator", 1, [[C.STRUCTURAL_ALLOY, 10, 0.3], [C.SEMICONDUCTOR, 4, 0.35], [C.CATALYST, 2, 0.3]]),
		"cargo_storage": _recipe("cargo_storage", 1, [[C.STRUCTURAL_ALLOY, 12, 0.25], [C.POLYMER, 4, 0.2]]),
		"archive_module": _recipe("archive_module", 1, [[C.SEMICONDUCTOR, 8, 0.4], [C.OPTICS, 2, 0.4], [C.RADIATION_SHIELDING, 4, 0.3]]),
		"gas_scoop": _recipe("gas_scoop", 2, [[C.STRUCTURAL_ALLOY, 8, 0.45], [C.COOLANT, 4, 0.4], [C.CATALYST, 2, 0.35]]),
		"jump_drive": _recipe("jump_drive", 3, [[C.STRUCTURAL_ALLOY, 16, 0.6], [C.SUPERCONDUCTOR, 8, 0.65], [C.COOLANT, 6, 0.6], [C.OPTICS, 4, 0.5]]),
		"hull_patch": _recipe("hull_patch", 0, [[C.STRUCTURAL_ALLOY, 2, 0.2]]),
		"survival_module": _recipe("survival_module", 0, [[C.STRUCTURAL_ALLOY, 8, 0.2], [C.RADIATION_SHIELDING, 4, 0.2], [C.POLYMER, 2, 0.15]]),
		"survey_scanner": _recipe("survey_scanner", 1, [[C.STRUCTURAL_ALLOY, 3, 0.25], [C.SEMICONDUCTOR, 2, 0.35], [C.POLYMER, 1, 0.2]]),
	}

static func _element(id: String, label: String, phase: int, classes: Dictionary) -> Element:
	var e := Element.new()
	e.id = StringName(id)
	e.display_name = label
	e.phase = phase
	e.qualifies = classes
	return e

static func _recipe(id: String, tier: int, slots: Array) -> Recipe:
	var r := Recipe.new()
	r.id = StringName(id)
	r.output = StringName(id)
	r.unlock_tier = tier
	for row in slots:
		var s := Slot.new()
		s.class_id = int(row[0])
		s.amount = int(row[1])
		s.min_grade = float(row[2])
		r.inputs.append(s)
	return r
