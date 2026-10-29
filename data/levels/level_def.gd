## Shared level schema; campaign-only fields are unused by this demo.
class_name LevelDef
extends Resource

const ShadowStroke = preload("res://data/levels/shadow_stroke_def.gd")

@export var level_id: int = 1
@export_enum("none", "basement", "laboratory") var lighting_style: String = "none"
@export var display_name: String = ""
@export var trash_catalog: TrashCatalog
@export var background_music_clip: String = "music_level"
@export_range(0.01, 100.0, 0.01, "or_greater") var runtime_layout_scale: float = 1.0

@export var rooms: Array[RoomDef] = []
@export var doors: Array[DoorDef] = []

@export var player_spawn: Vector2 = Vector2(-21.5, 1.5)
@export var goal_position: Vector2 = Vector2(15.8, -12.3)

@export var boss_position: Vector2 = Vector2(22.0, -12.0)
@export var boss_room_index: int = 5

@export_group("Campaign variants")
@export var portal_position: Vector2 = Vector2(25.5, -12.0)
@export var boss_scene: String = "res://entities/fog/fog.tscn"
@export var boss_stats: String = "res://data/balance/boss_stats.tres"
@export var boss_required_for_goal: bool = false
@export var guaranteed_first_chest_type: int = -1
@export var guaranteed_first_casino_buff: bool = false
@export var key_fragment_room_indices: PackedInt32Array = PackedInt32Array()
@export var puzzle_room_index: int = -1
@export var puzzle_column_positions: PackedVector2Array = PackedVector2Array()
@export var puzzle_sequence: PackedInt32Array = PackedInt32Array()
@export var bonus_chest_positions: PackedVector2Array = PackedVector2Array()
func bonus_chest_kind(index: int) -> int:
	return 1 if index == 0 else 0

@export var bonus_chest_linked_enemy_ids: Array = []

@export_group("Level 3 specials")
@export var teacher_position: Vector2 = Vector2.ZERO
@export var safe_position: Vector2 = Vector2.ZERO
@export var crowbar_position: Vector2 = Vector2.ZERO
@export var construction_hazard_position: Vector2 = Vector2.ZERO
@export var safe_lamp_position: Vector2 = Vector2.ZERO
@export var secret_column_position: Vector2 = Vector2.ZERO
@export var secret_code_position: Vector2 = Vector2.ZERO
@export var boss_gate_door_index: int = -1
@export var teacher_gate_door_index: int = -1
@export var safe_room_index: int = -1
@export var crowbar_room_index: int = -1
@export var teacher_room_index: int = -1
@export var brood_web_patches: Array[Rect2] = []

@export_group("Level 4 attic")
@export var attic_anchors: Array[AtticAnchorDef] = []

@export_group("Backdrop")
@export var backdrop_asset: String = "murino_city_foggy_backdrop"
@export var backdrop_bounds: Rect2 = Rect2(-42.0, -27.0, 84.0, 55.0)
@export var backdrop_tint: Color = Color(0.57, 0.62, 0.64, 0.42)
@export var backdrop_z: int = -32760

@export var room_shell_tint: Color = Color.WHITE
@export var room_shell_z_base: int = -20000

@export_group("Level editor")
@export var editor_format_version: int = 1
@export_range(0.01, 10.0, 0.01, "or_greater") var editor_grid_size: float = 0.25
@export var editor_layers: PackedStringArray = PackedStringArray([
	"КАНВАСЫ", "КОЛЛАЙДЕРЫ", "ОБЪЕКТЫ", "ПРОТИВНИКИ",
])
@export var editor_object_layers: Dictionary = {}
@export var editor_object_sublayers: Dictionary = {}
@export var editor_next_id: int = 1

@export var shadow_strokes: Array[ShadowStroke] = []

@export_group("")
var _layout_scale: float = 1.0

func scale_layout(multiplier: float) -> void:
	var target_scale: float = maxf(0.01, multiplier)
	var factor: float = target_scale / _layout_scale
	if is_equal_approx(factor, 1.0):
		return
	_layout_scale = target_scale
	multiply_layout(factor)

func multiply_layout(factor: float) -> void:
	if factor <= 0.0 or is_equal_approx(factor, 1.0):
		return
	player_spawn *= factor
	goal_position *= factor
	boss_position *= factor
	portal_position *= factor
	teacher_position *= factor
	safe_position *= factor
	crowbar_position *= factor
	construction_hazard_position *= factor
	safe_lamp_position *= factor
	secret_column_position *= factor
	secret_code_position *= factor
	for index: int in range(brood_web_patches.size()):
		var patch: Rect2 = brood_web_patches[index]
		brood_web_patches[index] = Rect2(patch.position * factor, patch.size * factor)
	for stroke: ShadowStroke in shadow_strokes:
		if stroke == null:
			continue
		stroke.radius *= factor
		for index: int in stroke.points.size():
			stroke.points[index] *= factor
	for anchor: AtticAnchorDef in attic_anchors:
		if anchor == null:
			continue
		anchor.position *= factor
		anchor.size *= factor
		var scaled_anchor_points: PackedVector2Array = PackedVector2Array()
		for point: Vector2 in anchor.points:
			scaled_anchor_points.append(point * factor)
		anchor.points = scaled_anchor_points
	backdrop_bounds = Rect2(backdrop_bounds.position * factor, backdrop_bounds.size * factor)
	var scaled_columns: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in puzzle_column_positions:
		scaled_columns.append(point * factor)
	puzzle_column_positions = scaled_columns
	var scaled_bonus: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in bonus_chest_positions:
		scaled_bonus.append(point * factor)
	bonus_chest_positions = scaled_bonus
	for room_def: RoomDef in rooms:
		if room_def == null:
			continue
		room_def.bounds = Rect2(room_def.bounds.position * factor, room_def.bounds.size * factor)
		room_def.canvas_offset *= factor
		room_def.junk_composition_size *= factor
		var scaled_room_polygon: PackedVector2Array = PackedVector2Array()
		for point: Vector2 in room_def.walkable_polygon:
			scaled_room_polygon.append(point * factor)
		room_def.walkable_polygon = scaled_room_polygon
		for light: LightPlacementDef in room_def.lights:
			light.position *= factor
			light.radius *= factor
		room_def.trash_wall_band *= factor
		var scaled_windows: PackedVector2Array = PackedVector2Array()
		for point: Vector2 in room_def.exterior_windows:
			scaled_windows.append(point * factor)
		room_def.exterior_windows = scaled_windows
		for index: int in room_def.areas.size():
			var area: Rect2 = room_def.areas[index]
			room_def.areas[index] = Rect2(area.position * factor, area.size * factor)
		for wall: WallSegmentDef in room_def.wall_segments:
			if wall != null:
				wall.from *= factor
				wall.to *= factor
		for opening: DoorOpeningDef in room_def.door_openings:
			if opening != null:
				opening.centre *= factor
		for collider: LevelColliderDef in room_def.colliders:
			if collider == null:
				continue
			collider.position *= factor
			collider.size *= factor
			collider.radius *= factor
			collider.height *= factor
			collider.thickness *= factor
			var scaled_points: PackedVector2Array = PackedVector2Array()
			for point: Vector2 in collider.points:
				scaled_points.append(point * factor)
			collider.points = scaled_points
		if room_def.has_chest:
			room_def.chest_position *= factor
		for fog: FogPlacementDef in room_def.fogs:
			if fog != null:
				fog.position *= factor
				fog.patrol_radius *= factor
	for door: DoorDef in doors:
		if door != null:
			door.position *= factor

func room(index: int) -> RoomDef:
	for def: RoomDef in rooms:
		if def != null and def.index == index:
			return def
	return null

func attic_anchor(id: StringName) -> AtticAnchorDef:
	for anchor: AtticAnchorDef in attic_anchors:
		if anchor != null and anchor.editor_id == id:
			return anchor
	return null

## Overlapping seams resolve to the first matching room.
func room_at(point: Vector2) -> RoomDef:
	for def: RoomDef in rooms:
		if def != null and def.contains(point):
			return def
	return null

func total_regular_fogs() -> int:
	var total: int = 0
	for def: RoomDef in rooms:
		if def != null:
			total += def.fogs.size()
	return total
