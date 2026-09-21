extends Resource
const Element = preload("res://scripts/crafting/element_def.gd")
@export var class_id: int
@export var amount: int = 1
@export_range(0.0, 1.0) var min_grade: float = 0.0

func accepts(element: Element, environment_modifier: float = 1.0) -> bool:
	return element != null and element.qualifies.has(class_id) and element.grade(class_id, environment_modifier) >= min_grade
