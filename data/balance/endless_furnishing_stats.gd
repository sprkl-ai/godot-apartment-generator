extends Resource

@export var clusters_min: int = 2
@export var clusters_max: int = 5
@export var floor_area_per_cluster: float = 65.0
@export var placement_attempts: int = 24
@export var cluster_clearance: float = 2.2
@export var encounter_clearance: float = 1.5
@export var chest_clearance: float = 2.0
@export var actor_clearance: float = 0.65
@export var player_body_radius: float
## Required traversal width relative to the player body diameter.
@export var traversal_width_multiplier: float = 1.5
## Smaller cells cost more; clearance padding includes half a cell.
@export var traversal_grid_step: float = 0.35
@export var rack_footprint: Vector2 = Vector2(1.5, 0.7)
@export var rack_picture_size: Vector2 = Vector2(2.05, 2.7)
@export var cabinet_footprint: Vector2 = Vector2(1.2, 0.7)
@export var cabinet_picture_size: Vector2 = Vector2(1.75, 2.5)
@export var size_variation: float = 0.12
@export var wall_depth: float = 0.85
@export var projected_wall_footprint: bool = true
@export var wall_foot_depth: float = 0.12
@export var wall_collision_thickness: float = 0.54
@export var wall_gap: float = 0.08
@export var shower_wall_gap: float
@export var shower_partition_thickness: float
@export var wall_probe_distance: float = 0.05
@export var wall_foot_actor_clearance: float = 0.8
@export var wall_foot_chest_clearance: float = 1.0
@export var door_clearance: float = 0.85
@export var door_sweep_leaf_depth: float = 1.3
@export var door_sweep_clearance: float = 0.18
@export var broom_footprint: Vector2 = Vector2(0.24, 0.22)
@export var broom_picture_size: Vector2 = Vector2(0.55, 1.65)
@export var lamp_footprint: Vector2 = Vector2(0.45, 0.45)
@export var lamp_corner_reach: float = 1.5
@export var lamp_picture_size: Vector2 = Vector2(0.9, 2.05)
@export var encounter_search_step: float = 0.5

@export var side_height_rise_ratio: float = 0.65
@export var trash_density_multiplier: float = 0.1167
@export var trash_room_max: int = 3
@export var trash_room_min: int = 0
@export var trash_area_per_prop: float = 54.0
@export var sealed_port_clearance: float = 0.4
@export var sealed_port_reservation_half_depth: float = 0.0

@export var decor_weights: Dictionary = {"rack": 12.0, "cabinet": 10.0, "broom": 5.0, "lamp": 7.0, "table": 10.0, "bench": 8.0, "dark_crate": 9.0, "metal_locker": 7.0, "radiator": 8.0, "chair": 8.0, "rolled_rug": 7.0, "plant": 9.0}
@export var corner_preference: float = 0.65
@export var table_footprint: Vector2 = Vector2(1.45, 0.9)
@export var table_picture_size: Vector2 = Vector2(1.65, 1.65)
@export var bench_footprint: Vector2 = Vector2(1.7, 0.55)
@export var bench_picture_size: Vector2 = Vector2(1.9, 1.0)
@export var dark_crate_footprint: Vector2 = Vector2(0.85, 0.75)
@export var crate_debris_skin: float = 0.35
@export var dark_crate_picture_size: Vector2 = Vector2(1.05, 1.25)
@export var metal_locker_footprint: Vector2 = Vector2(0.8, 0.65)
@export var metal_locker_picture_size: Vector2 = Vector2(1.1, 2.4)
@export var radiator_footprint: Vector2 = Vector2(1.1, 0.35)
@export var radiator_picture_size: Vector2 = Vector2(1.3, 1.2)
@export var chair_footprint: Vector2 = Vector2(0.65, 0.65)
@export var chair_picture_size: Vector2 = Vector2(0.85, 1.55)
@export var rolled_rug_footprint: Vector2 = Vector2(1.1, 0.42)
@export var rolled_rug_picture_size: Vector2 = Vector2(1.3, 0.8)
@export var plant_footprint: Vector2 = Vector2(0.45, 0.45)
@export var plant_picture_size: Vector2 = Vector2(0.9, 1.6)
@export var carpet_footprint: Vector2 = Vector2(2.3, 1.82)
@export var carpet_picture_size: Vector2 = Vector2(2.3, 1.82)

@export var semantic_room_dressing: bool = false
@export var room_purpose_weights: Dictionary = {"bath": 25.0, "living": 45.0, "storage": 30.0}
@export_range(0.0,1.0) var public_shower_chance: float = 0.5
@export var shower_room_max_size: Vector2
@export var shower_room_min_size: Vector2
@export var shower_stall_gap: float
@export var shower_stall_limit: int
@export var shower_fixture_end_clearance: float
@export var shower_mat_gap: float
@export var shower_wet_steps_db: float
@export var shower_wet_step_slice: float
@export var shower_wet_step_pitch: Vector2
@export var purpose_decor: Dictionary = {}
@export var purpose_required: Dictionary = {}
@export var semantic_footprints: Dictionary = {}
@export var semantic_fallbacks: Dictionary = {}
@export var hall_decor_limit: int = 1
@export var hall_decor_roster: PackedStringArray = PackedStringArray()
@export var support_surfaces: Dictionary = {}
@export var support_loot_footprint: Vector2 = Vector2(0.62,0.44)
@export var support_carrier_min_scale: float = 1.0
@export var support_approach_clearance: float = 0.35
@export var shelf_only_pipe_spawns: bool = true
@export var supported_curtain_spawns: bool = true
@export var curtain_support_surfaces: Dictionary = {}
@export var curtain_shelf_footprint: Vector2
@export var curtain_shower_footprint: Vector2
@export var curtain_shower_min_lift_distance: float
@export var laundry_rack_wall_gap: float
@export var semantic_area_per_prop: Dictionary = {}
@export var semantic_count_limits: Dictionary = {}
@export var semantic_repeatable: Dictionary = {}
@export var semantic_repeat_limits: Dictionary = {}
@export var semantic_group_anchors: Dictionary = {}
@export var semantic_group_front: Array[String] = []
@export var semantic_group_gap: float = 0.75
@export var background_center_min_area: float
@export var background_center_max_groups: int
@export var background_center_groups: Dictionary = {}
@export var semantic_floor_decor: Dictionary = {}
@export var floor_decor_area_per_prop: float = 100.0
@export var floor_decor_count_limits: Vector2i = Vector2i(1,2)
@export var floor_decor_edge_padding: float = 0.18
@export var floor_decor_entry_preference: float = 0.8
@export var floor_decor_entry_gap: float = 0.12
@export var plant_floor_min_count: int = 4
@export var plant_pickup_count: int = 2
@export var plant_max_adjacent_pairs: int = 1
@export var plant_min_separation: float = 3.3
@export var plant_room_purposes: Array[String] = ["living","storage","hall"]
@export var plant_variants: PackedStringArray = PackedStringArray(["plant_fern","plant_ficus","plant_cactus","plant_aloe","plant_ivy"])
