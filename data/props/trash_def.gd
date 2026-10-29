class_name TrashDef
extends Resource

enum Weight { LIGHT, MEDIUM, HEAVY }

@export var asset: String = ""
@export_file("*.png") var texture_override: String = ""
@export_range(0, 100, 1) var max_per_room: int = 0

func texture_path() -> String:
	return texture_override if not texture_override.is_empty() else "res://assets/environment/%s.png" % asset

@export var world_height: float = 0.5

@export var weight: Weight = Weight.LIGHT

@export var collider_scale: float = 0.72
