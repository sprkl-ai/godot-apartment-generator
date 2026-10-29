## Collider points are local to position and rotate with the collider.
class_name LevelColliderDef
extends Resource

const WALL_BOUNDARY_LAYER: int = 1 << 9
const FURNITURE_LAYER: int = 1 << 10

enum ShapeKind {
	RECTANGLE,
	CIRCLE,
	CAPSULE,
	POLYGON,
	SEGMENT,
}

@export_group("Editor")
@export var editor_id: StringName = &""
@export var display_name: String = "КОЛЛАЙДЕР"
@export var editor_layer: int = 1

@export_group("Transform")
@export_enum("Rectangle", "Circle", "Capsule", "Polygon", "Segment") \
var shape_kind: int = ShapeKind.RECTANGLE
@export var position: Vector2 = Vector2.ZERO
@export_range(-6.283185, 6.283185, 0.001, "radians") var rotation: float = 0.0

@export var size: Vector2 = Vector2.ONE
@export_range(0.01, 1000.0, 0.01, "or_greater") var radius: float = 0.5
@export_range(0.02, 1000.0, 0.01, "or_greater") var height: float = 1.0

@export var points: PackedVector2Array = PackedVector2Array()
@export_range(0.01, 1000.0, 0.01, "or_greater") var thickness: float = 0.54
@export var filled: bool = true
@export var closed: bool = true

@export_group("Physics")
@export_flags_2d_physics var collision_layer: int = 1
@export_flags_2d_physics var collision_mask: int = 0
@export var disabled: bool = false
@export var collision_scale: Vector2 = Vector2.ONE

@export_group("Optional prop artwork")
@export_file("*.png") var visual_asset: String = ""
@export_range(-1, 7, 1) var visual_view: int = -1
@export_enum("4 views:4", "8 views:8") var visual_view_count: int = 4
@export var visual_scale: Vector2 = Vector2.ONE
@export var visual_offset: Vector2 = Vector2.ZERO
@export var floor_decoration: bool = false
@export_range(0, 50, 1) var visual_sub_layer: int = 0

func normalized_size() -> Vector2:
	return Vector2(maxf(0.01, absf(size.x)), maxf(0.01, absf(size.y)))

## Physical size; visual dimensions may differ.
func effective_collision_size() -> Vector2:
	return normalized_size() * Vector2(
		maxf(0.01, absf(collision_scale.x)), maxf(0.01, absf(collision_scale.y))
	)

func is_geometry_valid() -> bool:
	match shape_kind:
		ShapeKind.RECTANGLE:
			return normalized_size().x > 0.0 and normalized_size().y > 0.0
		ShapeKind.CIRCLE:
			return radius > 0.0
		ShapeKind.CAPSULE:
			return normalized_size().x > 0.0 and normalized_size().y > 0.0
		ShapeKind.POLYGON:
			return points.size() >= 3
		ShapeKind.SEGMENT:
			return points.size() >= 2 and points[0].distance_to(points[1]) > 0.001 \
				and thickness > 0.0
	return false
