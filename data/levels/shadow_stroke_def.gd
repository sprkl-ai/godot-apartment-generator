extends Resource

@export var points: PackedVector2Array = PackedVector2Array()
@export_range(0.05, 24.0, 0.05) var radius: float = 1.25
@export_range(0.0, 1.0, 0.01) var opacity: float = 0.45
@export var erase: bool = false
@export_range(-4096, 4094, 1) var draw_z: int = -4077
@export_range(0, 3, 1) var editor_layer: int = 2
@export var owner_keys: PackedStringArray = PackedStringArray()

func is_valid() -> bool:
	if points.is_empty() or not is_finite(radius) or radius < 0.05 or radius > 24.0 \
			or not is_finite(opacity) or opacity <= 0.0 or opacity > 1.0:
		return false
	for point: Vector2 in points:
		if not point.is_finite():
			return false
	return draw_z >= -4096 and draw_z <= 4094 and editor_layer >= 0 and editor_layer <= 3

func paint_key() -> String:
	var owners: PackedStringArray = owner_keys.duplicate()
	owners.sort()
	return "%d|%d|%s" % [draw_z, editor_layer, ",".join(owners)]

func translate(delta: Vector2) -> void:
	for index: int in points.size():
		points[index] += delta

func rotate_around(center: Vector2, angle: float) -> void:
	for index: int in points.size():
		points[index] = center + (points[index] - center).rotated(angle)
