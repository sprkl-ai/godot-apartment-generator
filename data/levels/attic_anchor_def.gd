class_name AtticAnchorDef
extends Resource

@export var editor_id: StringName = &""
@export var kind: StringName = &""
@export var room_index: int = -1
@export var position: Vector2 = Vector2.ZERO
@export var size: Vector2 = Vector2.ONE
@export var rotation: float = 0.0
@export var points: PackedVector2Array = PackedVector2Array()
@export var linked_id: StringName = &""
@export var value: int = 0
@export var visual_asset: String = ""

func world_points() -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in points:
		result.append(position + point.rotated(rotation))
	return result

func contains(point: Vector2) -> bool:
	var local: Vector2 = (point - position).rotated(-rotation)
	if points.size() >= 3:
		return Geometry2D.is_point_in_polygon(local, points)
	return Rect2(-size * 0.5, size).has_point(local)
