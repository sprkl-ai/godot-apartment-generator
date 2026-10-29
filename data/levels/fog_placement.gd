## Encounter reservations affect furnishing; this demo spawns no enemies.
class_name FogPlacementDef
extends Resource

@export var position: Vector2 = Vector2.ZERO

@export var strength_tier: int = 0

@export var group_id: int = 0

@export var patrol_radius: float = 1.0
@export var aggro_radius: float = 2.35

@export var is_ranged: bool = false

@export_enum("Fog", "Broodfog") var enemy_kind: int = 0

@export_group("Level editor")
@export var editor_id: StringName = &""
@export var editor_layer: int = 3
