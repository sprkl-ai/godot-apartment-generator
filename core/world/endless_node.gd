## Internal architecture uses +Y up; RoomDef output is converted once.
class_name EndlessNode
extends RefCounted

enum Role {
	START,
	HALL,
	HUB,
	CONNECTOR,
	RING_HUB,
	FUNNEL,
	BOSS,
	OPTIONAL_ARENA,
	OPTIONAL_CONNECTOR,
}

const EXIT_NONE: int = 0
const EXIT_NORTH: int = 1
const EXIT_EAST: int = 2
const EXIT_SOUTH: int = 4
const EXIT_WEST: int = 8
const EXIT_ALL: int = EXIT_NORTH | EXIT_EAST | EXIT_SOUTH | EXIT_WEST

var index: int = 0
var grid: Vector2i = Vector2i.ZERO
var main_path_order: int = -1
var optional: bool = false
var boss: bool = false
var role: Role = Role.START
var asset_name: String = ""
var world_height: float = 0.0

# Local door anchors use [-0.5, 0.5] before room rotation.
var north_anchor: Vector2 = Vector2(0.0, 0.5)
var east_anchor: Vector2 = Vector2(0.5, 0.0)
var south_anchor: Vector2 = Vector2(0.0, -0.5)
var west_anchor: Vector2 = Vector2(-0.5, 0.0)

var base_mask: int = EXIT_NONE
var quarter_turns: int = 0

var exits: int = EXIT_NONE

var center: Vector2 = Vector2.ZERO
var size: Vector2 = Vector2.ZERO

# Active nodes use active indices; master nodes use master indices.
var links: Array[int] = []

var link_directions: Dictionary = {}
var lighting_seed: int = 0

var floor_areas_unity: Array[Rect2] = []
var floor_outline_unity: PackedVector2Array = PackedVector2Array()
var link_positions: Dictionary = {}
var link_widths: Dictionary = {}
var building_cells: Array[Vector2i] = []
var perimeter_room: bool = false
var service_shower: bool = false

func anchor_for(direction: int) -> Vector2:
	if direction == EXIT_NORTH:
		return north_anchor
	if direction == EXIT_EAST:
		return east_anchor
	if direction == EXIT_SOUTH:
		return south_anchor
	return west_anchor
