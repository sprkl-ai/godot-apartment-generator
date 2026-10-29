extends SceneTree
var app: Control
var checks: Dictionary = {}
func _initialize() -> void:
	call_deferred("run")
func expect(key: String, result: bool) -> void:
	checks[key] = result
	if not result: push_error("UI probe failed: "+key)
func run() -> void:
	root.size = Vector2i(1440,900)
	app = load("res://demo/main.tscn").instantiate()
	root.add_child(app); current_scene = app
	for index: int in 6: await process_frame
	expect("initial generation",app.model.data != null and app.model.data.level.rooms.size()>=16)
	app.seed_input.text = "12345"; app.floor_input.value = 2; app._generate()
	expect("seed and floor controls",app.model.seed_value == 12345 and app.model.floor_number == 2)
	var previous: RefCounted = app.model.data
	app.seed_input.text = "not a seed"; app._generate()
	expect("invalid input retains map",app.model.data == previous and app.validation.text.contains("whole number"))
	app.seed_input.text = "104829"; app.floor_input.value = 1; app._generate()
	for control: Node in app.find_children("*","CheckButton",true,false):
		if control.text in ["Clearances","Room graph","Background"]:
			control.button_pressed = true
			expect("toggle "+control.text,app.board.get({"Clearances":"show_clearances","Room graph":"show_graph","Background":"show_background"}[control.text]))
			control.button_pressed = false
	app.board.fit_map()
	var room: Resource = app.model.data.level.rooms[1]
	var click := InputEventMouseButton.new(); click.button_index = MOUSE_BUTTON_LEFT; click.pressed = true
	click.position = app.board._screen(room.areas[0].get_center()); app.board._gui_input(click)
	expect("room inspector click",app.board.selected_room != null and app.inspector.text.contains("Area:"))
	var before_zoom: float = app.board.zoom
	var wheel := InputEventMouseButton.new(); wheel.button_index = MOUSE_BUTTON_WHEEL_UP; wheel.pressed = true; wheel.position = app.board.size*.5
	app.board._gui_input(wheel)
	expect("wheel zoom",app.board.zoom > before_zoom)
	var before_pan: Vector2 = app.board.pan
	var drag := InputEventMouseButton.new(); drag.button_index = MOUSE_BUTTON_MIDDLE; drag.pressed = true
	app.board._gui_input(drag)
	var motion := InputEventMouseMotion.new(); motion.relative = Vector2(40,-15); app.board._gui_input(motion)
	drag.pressed = false; app.board._gui_input(drag)
	expect("middle drag pan",app.board.pan == before_pan+Vector2(40,-15))
	app.board.set_walking(true)
	expect("walk spawn",app.model.can_stand(app.board.player_point))
	app.seed_input.grab_focus(); var before: Vector2 = app.board.player_point
	var key := InputEventKey.new(); key.keycode = KEY_D; key.physical_keycode = KEY_D; key.pressed = true
	Input.parse_input_event(key); Input.flush_buffered_events(); await process_frame; app.board._process(.1)
	expect("editing seed does not move walker",app.board.player_point == before)
	app.generate_button.grab_focus(); await process_frame; app.board._process(.1)
	print("KEY_STATE ",Input.is_physical_key_pressed(KEY_D)," canmove ",app.model.can_stand(before+Vector2(.25,0))," before ",before," after ",app.board.player_point)
	expect("walk responds outside text field",app.board.player_point != before)
	var release: InputEventKey = key.duplicate(); release.pressed = false; Input.parse_input_event(release); Input.flush_buffered_events()
	app.board.set_walking(false); app.generate_button.grab_focus(); app.board.fit_map()
	app._export("user://ui-export.json")
	expect("JSON export",FileAccess.file_exists("user://ui-export.json"))
	app.seed_input.text = str(app.model.seed_value)
	app._generate()
	for index: int in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/preview.png")
	root.size = Vector2i(960,640); root.content_scale_size = Vector2i(960,640)
	for index: int in 4: await process_frame
	app.board.fit_map(); await process_frame; await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/preview-small.png")
	expect("small viewport footer remains visible",app.get_children()[1].get_children()[0].get_children()[-1].get_global_rect().end.y <= 640)
	for button: Node in app.find_children("*","Button",true,false):
		if button is Control and button.is_visible_in_tree() and button.get_parent() is not FileDialog:
			if button.get_global_rect().position.x > 960: expect("no control starts outside viewport",false)
	var file := FileAccess.open("res://docs/ui-checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(checks,"  ")+"\n"); file.close()
	print("UI_PROBE_DONE ",checks)
	app.queue_free(); await process_frame
	quit(0 if not checks.values().has(false) else 1)
