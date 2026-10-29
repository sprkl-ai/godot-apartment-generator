## Generated geometry plus internal architecture nodes.
class_name EndlessFloorData
extends RefCounted

var level: LevelDef = null
var portal_position: Vector2 = Vector2.ZERO
var boss_health_multiplier: float = 1.0
var boss_damage_multiplier: float = 1.0
var seed: int = 0
var floor_index: int = 0

var theme_id: int = 1
var theme_name: String = "ПОДВАЛ"
var cycle_index: int = 0
var is_boss_floor: bool = false
# The lift follows the generated landing; it is not necessarily world zero.
var cabin_center: Vector2 = Vector2.ZERO
var cabin_bounds: Rect2 = Rect2(-4.0, -3.5, 8.0, 7.0)
var cabin_door_position: Vector2 = Vector2(0.0, 3.5)
var cabin_door_direction: Vector2 = Vector2.DOWN

# Full building envelope; level.rooms contains only the playable selection.
var master_nodes: Array[EndlessNode] = []
var master_rooms: Array[RoomDef] = []
# Maps each active node index back to its master-building index.
var active_master_indices: PackedInt32Array = PackedInt32Array()
var sealed_ports: Array[Dictionary] = []
var building_bounds: Rect2 = Rect2()
var building_grid_size: Vector2i = Vector2i.ZERO
var furniture_zones: Array[Array] = []

# Nodes and level.rooms share active indices.
var nodes: Array[EndlessNode] = []
