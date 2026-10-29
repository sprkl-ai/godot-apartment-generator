extends Control
## Standalone portfolio workbench. Model owns generation; this view owns UI.
const Model = preload("res://demo/lab_model.gd")
const Board = preload("res://demo/board.gd")
var model: RefCounted
var board: Control
var seed_input: LineEdit
var floor_input: SpinBox
var generate_button: Button
var status: Label
var inspector: Label
var validation: Label
var export_dialog: FileDialog
var _seed: int = 104829
var _floor: int = 1


func _ready() -> void:
	_seed = int(get_tree().get_meta("preview_seed",_seed))
	_floor = int(get_tree().get_meta("preview_floor",_floor))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = _make_theme()
	_build_ui()
	model = Model.new()
	_generate.call_deferred()
	generate_button.grab_focus()


func _make_theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = 14
	result.set_color("font_color","Label",Color("d9e4e8"))
	for type: String in ["Button","LineEdit","SpinBox","CheckButton"]:
		result.set_color("font_color",type,Color("d9e4e8"))
		result.set_color("font_hover_color",type,Color("ffffff"))
	for state: String in ["normal","hover","pressed","disabled","focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color("21333f") if state != "hover" else Color("304a57")
		box.border_color = Color("71e5bd") if state == "focus" else Color("3b5360")
		box.set_border_width_all(1)
		box.set_corner_radius_all(5)
		box.content_margin_left = 13; box.content_margin_right = 13
		box.content_margin_top = 9; box.content_margin_bottom = 9
		result.set_stylebox(state,"Button",box)
		if state in ["normal","focus"]: result.set_stylebox(state,"LineEdit",box)
	result.set_constant("separation","VBoxContainer",12)
	result.set_constant("separation","HBoxContainer",10)
	return result


func _label(text: String, font_size: int = 14, color: Color = Color("d9e4e8")) -> Label:
	var label := Label.new(); label.text = text
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	return label


func _button(text: String, action: Callable) -> Button:
	var button := Button.new(); button.text = text; button.pressed.connect(action)
	return button


func _build_ui() -> void:
	var background := ColorRect.new(); background.color = Color("0b141b")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge: String in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+edge,22)
	add_child(margin)
	var layout := VBoxContainer.new(); margin.add_child(layout)
	var heading := HBoxContainer.new(); layout.add_child(heading)
	var titles := VBoxContainer.new(); titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation",3); heading.add_child(titles)
	titles.add_child(_label("APARTMENT GENERATOR LAB",25))
	titles.add_child(_label("Seeded architecture / shared walls / furniture clearances",13,Color("8fa6b2")))
	var badge := _label("sprkl-ai  /  GODOT",12,Color("71e5bd")); heading.add_child(badge)
	heading.add_child(_button("2.5D preview",_open_preview))
	var toolbar := HBoxContainer.new(); layout.add_child(toolbar)
	toolbar.add_child(_label("SEED",11,Color("8fa6b2")))
	seed_input = LineEdit.new(); seed_input.text = str(_seed); seed_input.custom_minimum_size.x = 145
	seed_input.select_all_on_focus = true; seed_input.text_submitted.connect(func(_text: String) -> void: _generate())
	toolbar.add_child(seed_input)
	toolbar.add_child(_label("FLOOR",11,Color("8fa6b2")))
	floor_input = SpinBox.new(); floor_input.min_value = 1; floor_input.max_value = 100
	floor_input.value = _floor; floor_input.custom_minimum_size.x = 80; toolbar.add_child(floor_input)
	generate_button = _button("Generate",_generate); toolbar.add_child(generate_button)
	toolbar.add_child(_button("Random seed",_randomize_seed))
	var spacer := Control.new(); spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL; toolbar.add_child(spacer)
	toolbar.add_child(_button("Export JSON",func() -> void:
		export_dialog.current_file = "apartments-%d-floor-%d.json" % [_seed,_floor]
		export_dialog.popup_centered_ratio(.75)))
	var layers := HBoxContainer.new(); layout.add_child(layers)
	for entry: Array in [["Furniture","show_furniture",true],["Clearances","show_clearances",false],["Room graph","show_graph",false],["Background","show_background",false]]:
		var toggle := CheckButton.new(); toggle.text = entry[0]; toggle.button_pressed = entry[2]
		toggle.toggled.connect(func(enabled: bool) -> void:
			board.set(entry[1],enabled)
			if entry[1] == "show_background": board.fit_map()
			board.queue_redraw())
		layers.add_child(toggle)
	layers.add_spacer(false)
	var walk := CheckButton.new(); walk.text = "Walk test"
	walk.toggled.connect(func(enabled: bool) -> void: board.set_walking(enabled))
	layers.add_child(walk)
	layers.add_child(_button("Fit map",func() -> void: board.fit_map()))
	var workspace := HBoxContainer.new(); workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(workspace)
	var frame := PanelContainer.new(); frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL; workspace.add_child(frame)
	var panel := StyleBoxFlat.new(); panel.bg_color = Color("101b23"); panel.border_color = Color("2a404b"); panel.set_border_width_all(1)
	frame.add_theme_stylebox_override("panel",panel)
	board = Board.new(); board.custom_minimum_size = Vector2(440,330)
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL; board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.room_selected.connect(_on_room_selected); frame.add_child(board)
	var sidebar_scroll := ScrollContainer.new(); sidebar_scroll.custom_minimum_size.x = 225
	sidebar_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sidebar_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; workspace.add_child(sidebar_scroll)
	var sidebar := VBoxContainer.new(); sidebar.custom_minimum_size.x = 211
	sidebar.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sidebar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar_scroll.add_child(sidebar)
	sidebar.add_child(_label("FLOOR REPORT",12,Color("71e5bd")))
	status = _label("Preparing geometry…",14)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; sidebar.add_child(status)
	validation = _label("",13); validation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sidebar.add_child(validation)
	sidebar.add_child(HSeparator.new())
	sidebar.add_child(_label("ROOM INSPECTOR",12,Color("71e5bd")))
	inspector = _label("Click any playable room\nto inspect its geometry.",13)
	inspector.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; sidebar.add_child(inspector)
	var vertical_spacer := Control.new(); vertical_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL; sidebar.add_child(vertical_spacer)
	sidebar.add_child(_label("LEGEND",11,Color("8fa6b2")))
	sidebar.add_child(_label("●  Lift / entry\n●  Living / storage\n●  Bath / corridor\n━  Door opening",13,Color("a9babe")))
	var footer := HBoxContainer.new(); layout.add_child(footer)
	footer.add_child(_label("Scroll: zoom   ·   Middle/right drag: pan   ·   Click: inspect   ·   Walk test: WASD / arrows",12,Color("8fa6b2")))
	export_dialog = FileDialog.new(); export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	export_dialog.access = FileDialog.ACCESS_FILESYSTEM; export_dialog.filters = PackedStringArray(["*.json ; Floor geometry"])
	export_dialog.file_selected.connect(_export); add_child(export_dialog)


func _generate() -> void:
	var value: String = seed_input.text.strip_edges()
	if not value.is_valid_int():
		validation.text = "Seed must be a whole number."; validation.modulate = Color("f3be78"); return
	_seed = clampi(int(value),-2147483648,2147483647)
	_floor = int(floor_input.value)
	seed_input.text = str(_seed)
	model.generate(_seed,_floor)
	board.set_model(model)
	status.text = "%d playable rooms\n%d door openings\n%.1f ms generation\nSeed %d · floor %d" % [model.data.level.rooms.size(),model.data.level.doors.size(),model.elapsed_ms,_seed,_floor]
	var issues: Array = model.report.get("issues",[])
	validation.text = "PASS · room graph connected\n%d rooms checked" % int(model.report.get("checked_rooms",0)) if issues.is_empty() else "CHECK · %d findings\n%s" % [issues.size(),"\n".join(issues.slice(0,4))]
	validation.modulate = Color("71e5bd") if issues.is_empty() else Color("f3be78")
	_on_room_selected(null)


func _randomize_seed() -> void:
	var random := RandomNumberGenerator.new(); random.randomize()
	seed_input.text = str(random.randi_range(1,2147483646)); _generate()


func _on_room_selected(room: Resource) -> void:
	if room == null:
		inspector.text = "Click any playable room\nto inspect its geometry."; return
	var area: float = 0.0
	for part: Rect2 in room.areas: area += part.get_area()
	var doors: int = 0
	for door: Resource in model.data.level.doors:
		if door.locking_rooms.has(room.index): doors += 1
	var purpose: String = "Lift cabin" if room.index == 0 else "Apartment entry" if room.get_meta("apartment_entry",false) else String(room.get_meta("endless_room_purpose","room")).capitalize()
	inspector.text = "%s · #%02d\n\nArea: %.1f units²\nBounds: %.1f × %.1f\nFloor rectangles: %d\nDoors: %d\nFurniture / colliders: %d" % [purpose,room.index,area,room.bounds.size.x,room.bounds.size.y,room.areas.size(),doors,room.colliders.size()]


func _export(path: String) -> void:
	var error: Error = model.export_json(path)
	validation.text = "JSON saved:\n"+path.get_file() if error == OK else "Export failed: "+error_string(error)
	validation.modulate = Color("71e5bd") if error == OK else Color("f3be78")


func _open_preview() -> void:
	if model == null or model.data == null: return
	get_tree().set_meta("preview_seed",model.seed_value)
	get_tree().set_meta("preview_floor",model.floor_number)
	var error: Error = get_tree().change_scene_to_file("res://examples/preview_25d.tscn")
	if error != OK:
		validation.text = "Preview failed: "+error_string(error)
		validation.modulate = Color("f3be78")
