extends Resource
const Slot = preload("res://scripts/crafting/recipe_slot.gd")
@export var id: StringName
@export var output: StringName
@export var inputs: Array[Slot] = []
@export var unlock_tier: int = 0
