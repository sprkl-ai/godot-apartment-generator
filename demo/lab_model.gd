extends RefCounted
## Presentation-free adapter around the extracted production generator.
const Generator = preload("res://core/world/endless_generator.gd")
const Furnishing = preload("res://core/world/endless_furnishing.gd")
const SCHEME: Resource = preload("res://data/balance/endless_scheme.tres")
var data: RefCounted
var elapsed_ms: float = 0.0
var validation_ms: float = 0.0
var seed_value: int = 0
var floor_number: int = 1
var report: Dictionary = {}
var free_samples: PackedVector2Array = PackedVector2Array()
var graph_edges: Array[PackedVector2Array] = []
var _segments: Array[PackedVector2Array] = []
var _obstacles: Array[Resource] = []

func generate(value: int, floor_index: int) -> void:
	seed_value = value; floor_number = maxi(1,floor_index)
	var started: int = Time.get_ticks_usec() # Wall-clock profiling, not gameplay time.
	data = Generator.new().generate(seed_value,floor_number,SCHEME)
	elapsed_ms = (Time.get_ticks_usec()-started)/1000.0
	started = Time.get_ticks_usec()
	_segments.clear(); _obstacles.clear(); free_samples.clear(); graph_edges.clear()
	for room: RoomDef in data.level.rooms:
		for edge: WallSegmentDef in room.wall_segments:
			_segments.append(PackedVector2Array([edge.from,edge.to]))
		for prop: LevelColliderDef in room.colliders:
			if not prop.disabled and prop.collision_layer != 0: _obstacles.append(prop)
	_validate()
	validation_ms = (Time.get_ticks_usec()-started)/1000.0

func all_bounds(include_background: bool = false) -> Rect2:
	if data == null: return Rect2(-10,-10,20,20)
	if include_background: return data.building_bounds
	var result: Rect2 = data.level.rooms[0].bounds
	for room: RoomDef in data.level.rooms: result = result.merge(room.bounds)
	return result.grow(3)

func room_at(point: Vector2) -> RoomDef:
	if data != null:
		for room: RoomDef in data.level.rooms:
			if room.contains(point): return room
	return null

func spawn_point() -> Vector2:
	return data.cabin_center if data != null else Vector2.ZERO

func can_stand(point: Vector2, radius: float = .55) -> bool:
	if room_at(point) == null: return false
	# A whole circle must fit in the union, including across open door seams.
	for index: int in 12:
		if room_at(point+Vector2.RIGHT.rotated(TAU*index/12.0)*radius) == null: return false
	for edge: PackedVector2Array in _segments:
		if point.distance_to(Geometry2D.get_closest_point_to_segment(point,edge[0],edge[1])) < radius+.06: return false
	for prop: LevelColliderDef in _obstacles:
		var local: Vector2 = (point-prop.position).rotated(-prop.rotation)
		if prop.shape_kind == LevelColliderDef.ShapeKind.POLYGON or prop.shape_kind == LevelColliderDef.ShapeKind.SEGMENT:
			if prop.filled and Geometry2D.is_point_in_polygon(local,prop.points): return false
			var count: int = prop.points.size() if prop.closed else prop.points.size()-1
			for index: int in count:
				if local.distance_to(Geometry2D.get_closest_point_to_segment(local,prop.points[index],prop.points[(index+1)%prop.points.size()])) < radius+prop.thickness*.5: return false
		elif prop.shape_kind == LevelColliderDef.ShapeKind.CIRCLE:
			if local.length() < prop.radius+radius: return false
		else:
			var half: Vector2 = prop.effective_collision_size()*.5
			var closest: Vector2 = local.clamp(-half,half)
			if local.distance_to(closest) < radius: return false
	return true

func move_circle(from: Vector2, to: Vector2, radius: float = .55) -> Vector2:
	var steps: int = maxi(1,ceili(from.distance_to(to)/maxf(.05,radius*.4)))
	var delta: Vector2 = (to-from)/steps
	var current: Vector2 = from
	for step: int in steps:
		if can_stand(current+delta,radius): current += delta
		else:
			if can_stand(current+Vector2(delta.x,0),radius): current.x += delta.x
			if can_stand(current+Vector2(0,delta.y),radius): current.y += delta.y
	return current

func _validate() -> void:
	var issues: Array[String] = []
	var reached: Dictionary = {0:true}
	var queue: Array[int] = [0]
	var cursor: int = 0
	while cursor < queue.size():
		var i: int = queue[cursor]; cursor += 1
		# Active nodes already store active indices, not master-building IDs.
		for other: int in data.nodes[i].links:
			if other < 0 or other >= data.nodes.size(): continue
			if other > i: graph_edges.append(PackedVector2Array([data.level.rooms[i].centre(),data.level.rooms[other].centre()]))
			if not reached.has(other): reached[other] = true; queue.append(other)
	if reached.size() != data.level.rooms.size(): issues.append("Disconnected room graph")
	var checked: int = 0
	for room: RoomDef in data.level.rooms:
		if room.index == 0: continue
		var grid: Dictionary = Furnishing._traversal_grid(room,Furnishing.DEFAULT_STATS)
		var door_labels: Dictionary = {}
		for cell: int in grid.doors: door_labels[int(grid.labels[cell])] = true
		if door_labels.size() > 1: issues.append("Room %d: conservative door lanes disconnected" % room.index)
		for cell: int in grid.open.size():
			if grid.open[cell] == 0: continue
			free_samples.append(Vector2(grid.origin)+Vector2(cell%int(grid.width)+.5,floori(float(cell)/int(grid.width))+.5)*float(grid.step))
		checked += 1
	report = {"issues":issues,"graph_connected":reached.size()==data.level.rooms.size(),"checked_rooms":checked,
		"rooms":data.level.rooms.size(),"doors":data.level.doors.size(),"free_cells":free_samples.size()}

func _point(value: Vector2) -> Array:
	return [value.x,value.y]

func layout_document() -> Dictionary:
	var rooms: Array = []
	for room: RoomDef in data.level.rooms:
		var areas: Array = []; var walls: Array = []; var props: Array = []
		for area: Rect2 in room.areas: areas.append([area.position.x,area.position.y,area.size.x,area.size.y])
		for edge: WallSegmentDef in room.wall_segments: walls.append([_point(edge.from),_point(edge.to)])
		for prop: LevelColliderDef in room.colliders:
			var points: Array = []
			for point: Vector2 in prop.points: points.append(_point(point))
			props.append({"id":String(prop.editor_id),"point":_point(prop.position),"size":_point(prop.effective_collision_size()),
				"rotation":prop.rotation,"shape":prop.shape_kind,"points":points,"disabled":prop.disabled,"solid":prop.collision_layer!=0,
				"radius":prop.radius,"thickness":prop.thickness,"closed":prop.closed,"filled":prop.filled,"collision_layer":prop.collision_layer})
		rooms.append({"id":room.index,"purpose":String(room.get_meta("endless_room_purpose","shaft")),
			"entry":bool(room.get_meta("apartment_entry",false)),"areas":areas,"walls":walls,"furniture":props})
	var doors: Array = []
	for door: DoorDef in data.level.doors:
		doors.append({"point":_point(door.position),"horizontal_travel":door.horizontal_travel,"width":door.passage_width,"rooms":Array(door.locking_rooms)})
	return {"format_version":1,"run_seed":seed_value,"floor":floor_number,"floor_seed":data.seed,"rooms":rooms,"doors":doors}

func export_json(path: String) -> Error:
	var file: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(layout_document(),"  ",true,true)+"\n")
	file.flush()
	return file.get_error()
