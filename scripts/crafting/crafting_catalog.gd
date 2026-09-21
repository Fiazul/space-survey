extends RefCounted
## Starter definitions only. Inventory, unlock persistence and fabrication are consumers.
const C = preload("res://scripts/crafting/material_class.gd").Kind
const Element = preload("res://scripts/crafting/element_def.gd")
const Slot = preload("res://scripts/crafting/recipe_slot.gd")
const Recipe = preload("res://scripts/crafting/recipe_def.gd")

static func elements() -> Dictionary:
	return {
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
