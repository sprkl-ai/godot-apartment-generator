extends Control
## A geometry-only view: no sprites, imported models, or gameplay scene nodes.
signal room_selected(room: Resource)

var model: RefCounted
var show_furniture: bool = true
var show_clearances: bool = false
var show_graph: bool = false
var show_background: bool = false
var walking: bool = false
var player_point: Vector2 = Vector2.ZERO
var selected_room: Resource
var zoom: float = 8.0
var pan: Vector2 = Vector2.ZERO
var _dragging: bool = false
var _fitted: bool = false

const INK := Color("c6d8df")
const MINT := Color("71e5bd")
const AMBER := Color("f3be78")


func _ready() -> void:
	clip_contents = true
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	resized.connect(func() -> void:
		if not _fitted: fit_map()
		queue_redraw())


func set_model(value: RefCounted) -> void:
	model = value
	selected_room = null
	player_point = model.spawn_point()
	fit_map()


func fit_map() -> void:
	if model == null or model.data == null or size.x < 1.0: return
	var bounds: Rect2 = model.all_bounds(show_background)
	if bounds.size.x <= 0 or bounds.size.y <= 0: return
	zoom = minf((size.x-80.0)/bounds.size.x,(size.y-80.0)/bounds.size.y)
	zoom = clampf(zoom,.3,70.0)
	pan = size*.5-bounds.get_center()*zoom
	_fitted = true
	queue_redraw()


func set_walking(value: bool) -> void:
	walking = value
	if model != null:
		player_point = model.spawn_point()
		if walking:
			zoom = maxf(zoom,13.0)
			pan = size*.5-player_point*zoom
	queue_redraw()


func _process(delta: float) -> void:
	if not walking or model == null: return
	if get_viewport().gui_get_focus_owner() is LineEdit: return
	var direction := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))-float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))-float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	if direction == Vector2.ZERO: return
	player_point = model.move_circle(player_point,player_point+direction.normalized()*5.0*minf(delta,.05))
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if model == null: return
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_MIDDLE,MOUSE_BUTTON_RIGHT]:
			_dragging = event.pressed; accept_event()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			var anchor: Vector2 = (event.position-pan)/zoom
			zoom = clampf(zoom*(1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0/1.15),.25,70.0)
			pan = event.position-anchor*zoom
			queue_redraw(); accept_event()
		elif event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			selected_room = model.room_at((event.position-pan)/zoom)
			room_selected.emit(selected_room); queue_redraw(); accept_event()
	elif event is InputEventMouseMotion and _dragging:
		pan += event.relative; queue_redraw(); accept_event()


func _screen(point: Vector2) -> Vector2:
	return point*zoom+pan


func _rect(rect: Rect2) -> Rect2:
	return Rect2(_screen(rect.position),rect.size*zoom)


func _room_color(room: Resource) -> Color:
	if room.index == 0: return Color("26554e")
	if room.get_meta("apartment_entry",false): return Color("665437")
	return {"hall":Color("294754"),"bath":Color("48415c"),"storage":Color("3d5144"),"living":Color("514940")}.get(String(room.get_meta("endless_room_purpose","living")),Color("3d4851"))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("101b23"))
	_draw_grid()
	if model == null or model.data == null: return
	var data: RefCounted = model.data
	if show_background:
		for room: Resource in data.master_rooms:
			for area: Rect2 in room.areas:
				draw_rect(_rect(area),Color("1a2932"))
				draw_rect(_rect(area),Color("2a3c46"),false,.7)
	for room: Resource in data.level.rooms:
		var color: Color = _room_color(room)
		if room == selected_room: color = color.lightened(.18)
		for area: Rect2 in room.areas: draw_rect(_rect(area),color)
		if show_furniture:
			for prop: Resource in room.colliders:
				_draw_prop(prop)
		if room.has_meta("entry_stair_pockets"):
			var stairs: Variant = room.get_meta("entry_stair_pockets")
			if stairs is Array:
				for stair: Variant in stairs:
					if stair is Rect2: _draw_stair(stair)
	if show_clearances:
		for point: Vector2 in model.free_samples:
			draw_circle(_screen(point),clampf(zoom*.065,.5,1.8),Color(.44,.90,.74,.48),false,.7)
	for room: Resource in data.level.rooms:
		for wall: Resource in room.wall_segments:
			draw_line(_screen(wall.from),_screen(wall.to),Color("b7c8c9"),maxf(1.2,zoom*.15),true)
	for door: Resource in data.level.doors:
		var tangent := Vector2.DOWN if door.horizontal_travel else Vector2.RIGHT
		var half: Vector2 = tangent*door.passage_width*.5
		draw_line(_screen(door.position-half),_screen(door.position+half),AMBER,maxf(2.0,zoom*.12),true)
		if show_clearances:
			var normal: Vector2 = tangent.orthogonal()
			draw_line(_screen(door.position-normal),_screen(door.position+normal),MINT,1.3,true)
	if show_graph:
		for edge: PackedVector2Array in model.graph_edges:
			if edge.size() < 2: continue
			var points := PackedVector2Array()
			for point: Vector2 in edge: points.append(_screen(point))
			draw_polyline(points,Color(.44,.9,.74,.65),1.4,true)
	for room: Resource in data.level.rooms:
		if zoom < 3.4: continue
		var label: String = "LIFT" if room.index == 0 else "ENTRY" if room.get_meta("apartment_entry",false) else "%02d" % room.index
		var at: Vector2 = _screen(_room_anchor(room))
		var font: Font = ThemeDB.fallback_font
		draw_string(font,at-Vector2(font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,11).x*.5,0),label,HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color(.85,.91,.92,.78))
	if walking:
		var player: Vector2 = _screen(player_point)
		draw_circle(player,maxf(4.0,.55*zoom),Color("101b23"))
		draw_arc(player,maxf(4.0,.55*zoom),0,TAU,28,MINT,2.0,true)
		draw_circle(player,2.0,Color.WHITE)
	_draw_scale()


func _room_anchor(room: Resource) -> Vector2:
	var centre: Vector2 = room.bounds.get_center()
	if not room.get_meta("apartment_entry",false) and model.room_at(centre) == room:
		return centre
	# Bounds of a concave landing can contain the shaft or a neighbouring room.
	# Label a real floor rectangle, never its empty bounding-box corner.
	var largest: float = -1.0
	for area: Rect2 in room.areas:
		if area.get_area() > largest and model.room_at(area.get_center()) == room:
			centre = area.get_center(); largest = area.get_area()
	return centre


func _draw_grid() -> void:
	var step: float = 10.0*zoom
	if step < 20.0 or step > 600.0: return
	var start: Vector2 = pan.posmod(step)
	for x: int in ceili(size.x/step)+1:
		draw_line(Vector2(start.x+x*step,0),Vector2(start.x+x*step,size.y),Color(.35,.49,.58,.08))
	for y: int in ceili(size.y/step)+1:
		draw_line(Vector2(0,start.y+y*step),Vector2(size.x,start.y+y*step),Color(.35,.49,.58,.08))


func _draw_prop(prop: Resource) -> void:
	if String(prop.editor_id).begins_with("endless_wall_foot:"): return
	if prop.disabled and not prop.floor_decoration: return
	var color := Color("8b8b78")
	if prop.floor_decoration: color = Color(.71,.63,.43,.24)
	elif prop.collision_layer == 0: color = Color(.55,.60,.53,.3)
	if prop.shape_kind == 3 and prop.points.size() >= 2:
		var polygon := PackedVector2Array()
		for p: Vector2 in prop.points: polygon.append(_screen(prop.position+p.rotated(prop.rotation)))
		if prop.filled and polygon.size() >= 3: draw_colored_polygon(polygon,color)
		else:
			if prop.closed: polygon.append(polygon[0])
			draw_polyline(polygon,color,maxf(1.2,prop.thickness*zoom),true)
		return
	var half: Vector2 = prop.effective_collision_size()*.5
	var polygon := PackedVector2Array()
	for corner: Vector2 in [Vector2(-half.x,-half.y),Vector2(half.x,-half.y),half,Vector2(-half.x,half.y)]:
		polygon.append(_screen(prop.position+corner.rotated(prop.rotation)))
	draw_colored_polygon(polygon,color)
	polygon.append(polygon[0]); draw_polyline(polygon,Color(.12,.18,.19,.65),.7,true)


func _draw_stair(stair: Rect2) -> void:
	draw_rect(_rect(stair),Color("313e42"))
	for step: int in 10:
		var y: float = stair.position.y+stair.size.y*float(step)/10.0
		draw_line(_screen(Vector2(stair.position.x,y)),_screen(Vector2(stair.end.x,y)),Color("8f9c97"),1.0)


func _draw_scale() -> void:
	var units: float = 10.0 if zoom < 12 else 5.0
	var a := Vector2(24,size.y-28)
	var b := a+Vector2(units*zoom,0)
	draw_line(a,b,INK,2.0)
	draw_line(a-Vector2(0,4),a+Vector2(0,4),INK,1.0)
	draw_line(b-Vector2(0,4),b+Vector2(0,4),INK,1.0)
	draw_string(ThemeDB.fallback_font,a-Vector2(0,9),"%d world units" % int(units),HORIZONTAL_ALIGNMENT_LEFT,-1,11,INK)
