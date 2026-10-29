class_name EndlessScheme
extends Resource

@export var base_loot_count: int = 1
@export var maximum_loot_count: int = 3
@export var first_extra_loot_chance: float = 0.40
@export var additional_loot_chance: float = 0.40
@export var weapon_chance: float = 0.05

@export var boss_health_multiplier: float = 1.0
@export var boss_damage_multiplier: float = 1.0

@export_group("Procedural architecture")
@export var building_columns: int = 30
@export var building_rows: int = 30
@export var building_cell_min: float = 4.0
@export var building_cell_max: float = 7.0
@export var building_narrow_axis_chance: float = 0.20
@export var dense_partition_max_size: Vector2 = Vector2(16.0, 14.0)
@export var dense_partition_attempts: int = 16
@export var dense_room_area_multiplier: float = 1.0
@export var room_player_width: float = 1.65
@export var room_player_area_limits: Vector2 = Vector2(25.0, 100.0)
@export var background_max_player_span: Vector2 = Vector2(10.0, 10.0)
@export var bath_max_player_span: Vector2 = Vector2(7.0,7.0)
@export var doorway_jamb_width: float = 0.7
@export var dense_doorway_width: float = 2.6
@export var building_perimeter_cells: int = 2
@export var active_sector_radius_cells: int = 12
@export var active_route_arm_steps: int = 4
@export var active_route_max_degree: int = 3
@export var active_route_loop_count: int = 2
@export var active_route_loop_detour_rooms: int = 3
@export var active_route_spread_weight: float = 2.5
@export_group("Apartment entrance")
@export var entry_lift_span_min: Vector2 = Vector2(1.9, 1.98)
@export var entry_lift_span_max: Vector2 = Vector2(2.0, 2.0)
@export var entry_front_notch_count: Vector2i = Vector2i(1, 2)
@export var entry_door_limits: Vector2i = Vector2i(3, 6)
@export var entry_working_door_limits: Vector2i = Vector2i(2, 4)
@export var entry_wing_steps: int = 2
@export var entry_stair_size: Vector2 = Vector2(3.13, 6.87)
@export var entry_stair_rear_depth: float = 3.0
@export_group("Procedural architecture")
@export var dense_room_weights: PackedFloat32Array = PackedFloat32Array([6, 3, 3, 3, 2])
@export var dense_corridor_chance: float = 0.16
@export var service_shower_short_side: Vector2 = Vector2(5.5, 6.2)
@export var service_shower_long_side: Vector2 = Vector2(7.0, 8.0)
@export var service_shower_chance: float = 0.015
@export var active_service_shower_min_count: int = 1
@export var active_loop_bias: float = 5.0
@export var zone_weights: PackedFloat32Array = PackedFloat32Array([1, 1, 0, 1])
@export var packing_attempts: int = 1800
@export var architecture_height_limit: float = 126.0
@export var room_size_min: float = 9.6
@export var room_size_max: float = 21.0
@export var entry_loop_size_min: float = 11.0
@export var entry_loop_size_max: float = 17.0
@export var bend_size_min: float = 12.0
@export var bend_size_max: float = 19.0
@export var cross_room_size_min: float = 15.0
@export var cross_room_size_max: float = 22.0
@export var boss_room_min_side: float = 5.5
@export var shape_weights: PackedFloat32Array = PackedFloat32Array([3, 4, 3, 2, 1])
@export var laboratory_shape_weights: PackedFloat32Array = PackedFloat32Array([3, 3, 2, 4, 1])
@export var attic_shape_weights: PackedFloat32Array = PackedFloat32Array([2, 5, 3, 2, 1])
@export var active_corridor_target_fraction: float = 0.25
@export var corridor_width_min: float = 3.4
@export var corridor_width_max: float = 4.0
@export var corridor_length_min: float = 8.0
@export var corridor_length_max: float = 24.0
@export var potential_rooms_min: int = 34
@export var potential_rooms_max: int = 44
@export var active_rooms_min: int = 16
@export var active_rooms_max: int = 20
@export_group("Area-based encounters")
@export var room_fog_min_lift_ratio: float = 1.0
@export var room_fog_single_lift_ratio: float = 1.1
@export var room_fog_large_lift_ratio: float = 2.0
@export var room_fog_small_count: int = 0
@export var room_fog_single_count: int = 1
@export var room_fog_medium_counts: Vector2i = Vector2i(1, 2)
@export var room_fog_large_counts: Vector2i = Vector2i(2, 3)
@export var room_fog_large_extra_chance: float = 0.5
@export var endless_chests_enabled: bool = false
@export var compact_room_area_per_fog: float = 8.0
@export var compact_room_chest_reserved_area: float = 8.0
@export var fog_spawn_attempts: int = 32
@export var fog_spawn_clearance: float = 1.0
@export var fog_spawn_separation: float = 2.0
@export var fog_spawn_door_clearance: float = 1.8

@export var reward_base_experience: int = 20
@export var reward_experience_per_fog: int = 8
@export var reward_boss_experience: int = 60
@export var reward_base_currency: int = 8
@export var reward_currency_per_fog: int = 2
@export var reward_boss_currency: int = 20

func calculate_reward(personal_fog_kills: int, boss_defeated: bool) -> Dictionary:
	var kills: int = maxi(0, personal_fog_kills)
	return {
		"experience": reward_base_experience + kills * reward_experience_per_fog
			+ (reward_boss_experience if boss_defeated else 0),
		"currency": reward_base_currency + kills * reward_currency_per_fog
			+ (reward_boss_currency if boss_defeated else 0),
	}
