extends Resource
## A raw or recovered material. Quality values are gameplay tuning, not chemistry.
enum Phase { SOLID, LIQUID, GAS }
@export var id: StringName
@export var display_name: String
@export var phase: Phase = Phase.SOLID
@export var qualifies: Dictionary = {}

func grade(class_id: int, environment_modifier: float = 1.0) -> float:
	return clampf(float(qualifies.get(class_id, 0.0)) * maxf(environment_modifier, 0.0), 0.0, 1.0)
