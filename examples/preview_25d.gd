extends Node3D
const Model = preload("res://demo/lab_model.gd")
const Geometry = preload("res://examples/level_geometry_3d.gd")
var model: RefCounted
var camera: Camera3D
var target: Vector3
var distance: float = 100
var yaw: float = .55
var _dragging: bool = false

func _ready() -> void:
	model = Model.new()
	model.generate(int(get_tree().get_meta("preview_seed",104829)),int(get_tree().get_meta("preview_floor",1)))
	var renderer: Node3D = Geometry.new(); add_child(renderer); renderer.build(model.data)
	var bounds: Rect2 = model.all_bounds()
	target = Geometry.world_point(bounds.get_center())
	var environment: WorldEnvironment = WorldEnvironment.new(); environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("101c27")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b2c6d8")
	environment.environment.ambient_light_energy = .65; add_child(environment)
	var light: DirectionalLight3D = DirectionalLight3D.new(); add_child(light)
	light.rotation_degrees = Vector3(-65,-25,0); light.light_energy = 1.25; light.shadow_enabled = true
	camera = Camera3D.new(); camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = maxf(bounds.size.x,bounds.size.y)*.95; add_child(camera); camera.make_current(); _camera_pose()
	var layer: CanvasLayer = CanvasLayer.new(); add_child(layer)
	var row: HBoxContainer = HBoxContainer.new(); row.position = Vector2(20,18); row.add_theme_constant_override("separation",20); layer.add_child(row)
	var back: Button = Button.new(); back.text = "Back to floor plan"; row.add_child(back)
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://demo/main.tscn"))
	var label: Label = Label.new(); label.text = "2.5D GEOMETRY EXAMPLE   /   Wheel: zoom   /   Drag: orbit   /   No game assets"; row.add_child(label)

func _camera_pose() -> void:
	camera.position = target+Vector3(sin(yaw)*distance,distance*.95,cos(yaw)*distance)
	camera.look_at(target)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]: _dragging = event.pressed
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			camera.size = clampf(camera.size*(.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1),10,600)
	elif event is InputEventMouseMotion and _dragging:
		yaw -= event.relative.x*.007; _camera_pose()
