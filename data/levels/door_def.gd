class_name DoorDef
extends Resource

@export var position: Vector2 = Vector2.ZERO

## Travel axis, perpendicular to the door panel.
@export var horizontal_travel: bool = false

@export var label: String = ""
@export_enum("hermetic", "soviet_wood") var visual_theme: String = "hermetic"
@export var passage_width: float = 2.8
@export var wood_starts_open: bool = false
@export var wood_open_side: float = 1.0

## Adjacent active room indices.
@export var locking_rooms: PackedInt32Array = PackedInt32Array()

@export var required_item_type: int = -1
