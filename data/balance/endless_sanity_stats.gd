extends Resource

@export var sanity_max: float
@export var sanity_loss: float
@export var sanity_interval: float
@export var nearby_fog_radius: float
@export var nearby_fog_decay_multiplier: float
@export var pill_recovery: float
@export var pill_duration: float
@export var plant_recovery_per_second: float
@export var rare_threshold: float
@export var patch_threshold: float
@export var phantom_threshold: float
@export var ally_threshold: float
@export var brightness_interval_min: float
@export var brightness_interval_max: float
@export var brightness_duration_min: float
@export var brightness_duration_max: float
@export var brightness_multiplier: float
@export var patch_interval: float
@export var patch_intense_threshold: float
@export var patch_intense_interval: float
@export var patch_intense_count: int
@export var patch_reroll_interval: float
@export var patch_hold_min: float
@export var patch_hold_max: float
@export var patch_switch_duration: float
@export var patch_switch_interval: float
@export var patch_size: float
@export var patch_count: int
@export var patch_upload_grid_size: int
@export var patch_height: float
@export var patch_variant_count: int
@export var dither_threshold: float
@export var dither_strength: float
@export var permanent_darkness_threshold: float
@export var permanent_darkness_multiplier: float
@export var heartbeat_threshold: float
@export var heartbeat_volume_db: float
@export var phantom_interval_min: float
@export var phantom_interval_max: float
@export var phantom_lifetime: float
@export var phantom_speed: float
@export var phantom_spawn_distance_min: float
@export var phantom_spawn_distance_max: float
@export var phantom_max_count: int
@export var phantom_burst_interval: float
@export var phantom_burst_duration: float
@export var phantom_burst_count: int
@export var ally_hit_damage: int
@export var ally_hit_cooldown: float
@export var ally_substitution_duration: float
@export var pill_spawn_chance: float
@export var pill_min_per_floor: int
@export var pill_max_per_floor: int
@export var debug_sanity_fraction: float

func to_settings() -> Dictionary:
	var result: Dictionary = {}
	for property: Dictionary in get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			result[String(property.name)] = get(String(property.name))
	return result
