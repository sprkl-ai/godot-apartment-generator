class_name LightPlacementDef
extends Resource

@export var position: Vector2 = Vector2.ZERO
@export var radius: float = 8.0
@export var rotation: float = 0.0

static func for_area(area: Rect2) -> LightPlacementDef:
	var light: LightPlacementDef = LightPlacementDef.new()
	var vertical: bool = area.size.y > area.size.x * 1.4
	light.position = area.position + area.size * (Vector2(0.18, 0.40) if vertical else Vector2(0.40, 0.18))
	light.rotation = -PI * 0.5 if vertical else 0.0
	light.radius = clampf(area.size.length() * 0.58, 4.0, 11.5)
	return light
