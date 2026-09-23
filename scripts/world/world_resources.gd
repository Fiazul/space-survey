class_name WorldResources
extends RefCounted
## Gameplay source pools, not measured deposits or extraction yields.
## Explicit recipe materials override these conservative composition presets.

static func resolve(recipe: Dictionary) -> Dictionary:
	if recipe.has("materials"):
		return recipe.materials.duplicate(true)
	var kind := str(recipe.get("kind", "rocky"))
	if kind == "star":
		return {"crust": [], "ocean": [], "atmosphere": [], "salvage": []}
	if kind == "gas":
		return {"crust": [], "ocean": [], "atmosphere": ["hydrogen", "helium", "methane"], "salvage": []}
	var ice := float(recipe.get("ice_amount", 0.0)) > 0.25 or kind == "ice"
	return {
		"crust": ["water_ice", "silicon", "iron"] if ice else ["iron", "silicon", "aluminium", "titanium", "copper", "quartz", "nickel", "niobium"],
		"ocean": [], # Liquid identity must be declared; shine is not chemistry.
		"atmosphere": [], # Atmospheric identity must be declared too.
		"salvage": [],
	}
