## Final floor geometry and optional dressing data.
class_name RoomDef
extends Resource

@export var index: int = 0

@export var display_name: String = ""

## Bounding box only: use areas/contains for the real room shape.
@export var bounds: Rect2 = Rect2()

## Walkable union; concave rooms must not be filled to their bounding box.
@export var areas: Array[Rect2] = []
## Optional exact contour overrides the rectangular union.
@export var walkable_polygon: PackedVector2Array = PackedVector2Array()

## Generated segments already have doorway cuts.
@export var wall_segments: Array[WallSegmentDef] = []
@export var door_openings: Array[DoorOpeningDef] = []

@export var colliders: Array[LevelColliderDef] = []

@export var shell_asset: String = ""
@export var junk_composition_wet: String = ""
@export var junk_composition_dark: String = ""
@export var junk_composition_dry: String = ""
@export var junk_composition_size: Vector2 = Vector2.ZERO
@export var shell_floor_rect: Rect2 = Rect2(0, 0, 1, 1)
@export var modular_walls: bool = false
@export var exterior_windows: PackedVector2Array = PackedVector2Array()
@export var lights_authored: bool = false
@export var lights: Array[LightPlacementDef] = []

@export var visual_variant: int = 0

@export_group("Level editor")
@export var editor_id: StringName = &""
@export var canvas_offset: Vector2 = Vector2.ZERO
@export var canvas_scale: Vector2 = Vector2.ONE
@export_range(-6.283185, 6.283185, 0.001, "radians") var canvas_rotation: float = 0.0
@export var canvas_layer: int = 0
@export var editor_locked: bool = false

@export_group("")

@export var has_chest: bool = false
@export var chest_position: Vector2 = Vector2.ZERO
@export var chest_kind: int = 0
@export var chest_linked_enemy_ids: PackedStringArray = PackedStringArray()
@export var is_boss_room: bool = false

@export var fogs: Array[FogPlacementDef] = []

@export var trash_count: int = 0
@export_range(0.0, 10.0, 0.05, "or_greater") var trash_wall_band: float = 0.0

func centre() -> Vector2:
	return bounds.get_center()

func industrial_lights() -> Array[LightPlacementDef]:
	if lights_authored:
		return lights
	var defaults: Array[LightPlacementDef] = []
	for area: Rect2 in areas:
		defaults.append(LightPlacementDef.for_area(area))
	return defaults

func size() -> Vector2:
	return bounds.size

func contains(point: Vector2) -> bool:
	if walkable_polygon.size() >= 3:
		return Geometry2D.is_point_in_polygon(point, walkable_polygon)
	for area: Rect2 in areas:
		if area.has_point(point):
			return true
	return false
