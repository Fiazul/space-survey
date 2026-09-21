extends SceneTree
var failures := 0
func _initialize() -> void:
	if not FileAccess.file_exists("res://scripts/crafting/crafting_catalog.gd"):
		check("crafting catalog exists", false)
	else:
		var catalog = load("res://scripts/crafting/crafting_catalog.gd")
		var elements: Dictionary = catalog.elements()
		var recipes: Dictionary = catalog.recipes()
		var G = load("res://scripts/world/planet_generator.gd")
		var earth: Dictionary = G.recipe_for({"name": "Earth"})
		for group in ["crust", "ocean", "atmosphere", "salvage"]:
			for id in earth.materials[group]:
				check("Earth material resolves: " + id, elements.has(id))
		for id in earth.crafting_recipes:
			check("Earth recipe resolves: " + id, recipes.has(id))
		var slot = recipes.hull_patch.inputs[0]
		check("iron fills structural class", slot.accepts(elements.iron, 1.0))
		check("aluminium substitutes for iron", slot.accepts(elements.aluminium, 1.0))
		check("nitrogen cannot replace structural metal", not slot.accepts(elements.nitrogen, 1.0))
		check("poor material fails minimum grade", not slot.accepts(elements.iron, 0.01))
		check("better environment improves grade", elements.iron.grade(slot.class_id, 1.2) > elements.iron.grade(slot.class_id, 0.8))
		for recipe in recipes.values():
			check("recipe has output and slots", not recipe.output.is_empty() and recipe.inputs.size() > 0)
			for input in recipe.inputs:
				check("slot has positive amount and valid grade", input.amount > 0 and input.min_grade >= 0.0 and input.min_grade <= 1.0)
	print("crafting_catalog: ", "OK" if failures == 0 else "FAIL %d" % failures)
	quit(0 if failures == 0 else 1)
func check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
		push_error(label)
