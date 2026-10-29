class_name EndlessGenerator
extends RefCounted

const Furnishing = preload("res://core/world/endless_furnishing.gd")

## Generates room geometry, active routes and deterministic furnishing data.
## Internal geometry uses +Y up. Flip Y only when writing final Godot data;
## moving the flip earlier changes the handedness of rotations.

const MAIN_ROOM_COUNT: int = 7
const OPTIONAL_ROOM_COUNT: int = 5
const REGULAR_FOG_COUNT: int = 33
const CHEST_COUNT: int = 11
const DOOR_WIDTH: float = 2.9
const DOOR_CUT_WIDTH: float = DOOR_WIDTH * 1.3
const WALL_VISUAL_INSET: float = 0.12
const FLOOR_PADDING: float = 26.0
const FLOOR_SEED_STEP: int = 104729
const LINK_SEAM_TOLERANCE: float = 0.08
enum PackedShape { ROOM, STRAIGHT, ELBOW, TEE, CROSS }

const BACKDROP_ASSET: String = "murino_city_foggy_backdrop"
const BACKDROP_TINT: Color = Color(0.36, 0.40, 0.41, 0.33)
const BACKDROP_Z: int = -32760

# Cardinal directions use the internal +Y-up frame.
const GRID_EAST: Vector2i = Vector2i(1, 0)
const GRID_NORTH: Vector2i = Vector2i(0, 1)
const GRID_WEST: Vector2i = Vector2i(-1, 0)
const GRID_SOUTH: Vector2i = Vector2i(0, -1)

# Calibrated canvas dimensions determine the legacy contour scale.
const CANVAS_PIXELS: Dictionary = {
	"room_boss_new_01": Vector2i(1161, 1162),
	"room_corner_ne_01": Vector2i(1205, 1216),
	"room_cross_nesw_01": Vector2i(1217, 1199),
	"room_dead_end_s_01": Vector2i(1106, 1060),
	"room_funnel_ew_01": Vector2i(1167, 849),
	"room_hall_ew_01": Vector2i(1201, 656),
	"room_junction_nesw_01": Vector2i(1145, 1176),
	"room_ring_nesw_01": Vector2i(1167, 1142),
	"room_square_ew_01": Vector2i(1035, 1054),
	"room_square_nesw_01": Vector2i(1169, 1143),
	"room_square_new_01": Vector2i(1096, 1095),
	"room_square_ns_01": Vector2i(1158, 1160),
}

var _scheme: EndlessScheme = null
var _endless_seed: int = 0
var _endless_random: DotNetRandom = null
var _run_seed: int = 0
var _potential_nodes: Array[EndlessNode] = []
var _active_master_indices: PackedInt32Array = PackedInt32Array()
var _sealed_ports: Array[Dictionary] = []
var _active_theme: int = 1
var _dense_route_links: Dictionary = {}
var _entry_exits: Array[int] = []


func generate(run_seed: int, floor_index: int, scheme: EndlessScheme) -> EndlessFloorData:
	_scheme = scheme
	_run_seed = run_seed
	_endless_seed = _wrap_int32(run_seed + floor_index * FLOOR_SEED_STEP)
	_endless_random = DotNetRandom.new(_endless_seed)

	_active_theme = theme_for_floor(run_seed, floor_index, scheme.zone_weights)
	var nodes: Array[EndlessNode] = _generate_expedition_architecture()
	return _build_floor_data(nodes, floor_index)


## Theme selection uses a separate RNG stream from layout generation.
static func theme_for_floor(run_seed: int, floor_index: int,
	weights: PackedFloat32Array = PackedFloat32Array([1, 1, 0, 1])) -> int:
	var random: DotNetRandom = DotNetRandom.new(_wrap_int32(run_seed + maxi(1, floor_index) * FLOOR_SEED_STEP + 7919))
	var total: float = 0.0
	for i: int in mini(4, weights.size()):
		total += maxf(0.0, weights[i])
	if total <= 0.0:
		return [1, 2, 4][random.next_int(0, 3)]
	var choice: float = random.next_double() * total
	for i: int in mini(4, weights.size()):
		choice -= maxf(0.0, weights[i])
		if choice < 0.0:
			return i + 1
	return 4


# Partition the entire building; concave cut-outs belong to neighbouring rooms.
func _generate_expedition_architecture() -> Array[EndlessNode]:
	# Retry isolated partitions without relaxing room limits.
	for _attempt: int in maxi(1,_scheme.dense_partition_attempts):
		var nodes: Array[EndlessNode] = _try_generate_expedition_architecture()
		if not nodes.is_empty(): return nodes
	assert(false,"Room partition cannot satisfy minimum area, maximum area and side limits.")
	return []


func _try_generate_expedition_architecture() -> Array[EndlessNode]:
	_potential_nodes = []
	var columns: int = maxi(12, _scheme.building_columns)
	var rows: int = maxi(12, _scheme.building_rows)
	var shaft_cell: Vector2i = Vector2i(columns / 2, rows * 2 / 3)
	# Reserve service-cell dimensions before partitioning to keep shared seams aligned.
	var service_cell: Vector2i = shaft_cell + Vector2i(-3, -3)
	var reserve_service: bool = _scheme.active_service_shower_min_count > 0
	var reserved_service_size: Vector2=_dense_service_cell_size() if reserve_service else Vector2.ZERO
	reserved_service_size = Vector2(minf(reserved_service_size.x,reserved_service_size.y),maxf(reserved_service_size.x,reserved_service_size.y))
	var entry_size: Vector2 = Vector2(_dimension(8.0*_scheme.entry_lift_span_min.x,8.0*_scheme.entry_lift_span_max.x),
		_dimension(7.0*_scheme.entry_lift_span_min.y,7.0*_scheme.entry_lift_span_max.y))
	var near_row: float = (entry_size.y-7.0)*.5
	var ordinary_span_limit: Vector2 = _scheme.dense_partition_max_size.min(_scheme.background_max_player_span * _scheme.room_player_width)
	var xs: Array[float] = [0.0]
	var ys: Array[float] = [0.0]
	for x: int in columns:
		xs.append(xs[-1] + (8.0 if x == shaft_cell.x else (entry_size.x-8.0)*.5 if absi(x-shaft_cell.x)==1 else reserved_service_size.x if reserve_service and x == service_cell.x else _dense_cell_size()))
	for y: int in rows:
		var depth: float = 7.0 if y == shaft_cell.y else near_row if y in [shaft_cell.y-1,shaft_cell.y-2] else reserved_service_size.y if reserve_service and y==service_cell.y else _dense_cell_size()
		if y==shaft_cell.y+1: depth=_scheme.entry_stair_rear_depth
		ys.append(ys[-1] + depth)
	var origin: Vector2 = Vector2((xs[shaft_cell.x] + xs[shaft_cell.x + 1]) * 0.5,
		(ys[shaft_cell.y] + ys[shaft_cell.y + 1]) * 0.5)
	var owners: Dictionary = {}
	_add_dense_room([shaft_cell], xs, ys, origin, owners, false)
	_potential_nodes[0].role = EndlessNode.Role.START
	# Cut landing corners on the shared grid before assigning adjacent apartments.
	var entry_cells: Array[Vector2i] = []
	var apartment_corners: Array[int]=[]
	var notch_side: int=-1 if _endless_random.next_double()<.5 else 1
	var notches: int=_endless_random.next_int(_scheme.entry_front_notch_count.x,_scheme.entry_front_notch_count.y+1)
	for row: int in 3:
		for column: int in range(-1,2):
			if row==0 and column==0: continue
			if row==2 and column!=0 and (column==notch_side or notches==2):
				apartment_corners.append(column);continue
			entry_cells.append(shaft_cell+GRID_SOUTH*row+GRID_EAST*column)
	# Reserve both rear stair arms before neighbouring apartments.
	for side: int in [-1,1]:entry_cells.append(shaft_cell+GRID_NORTH+GRID_EAST*side)
	_add_dense_room(entry_cells, xs, ys, origin, owners, false)
	# Join each landing cut-out to an apartment so it cannot become a trapped closet.
	for side: int in apartment_corners:
		var apartment: Array[Vector2i]=[]
		for row: int in [2,3]:
			for column: int in [side,side*2]:apartment.append(shaft_cell+GRID_SOUTH*row+GRID_EAST*column)
		_add_dense_room(apartment,xs,ys,origin,owners,false)
	if reserve_service:
		_add_dense_room([service_cell],xs,ys,origin,owners,false)
		_potential_nodes[-1].service_shower=true
	for y: int in rows:
		for x: int in columns:
			var cell: Vector2i = Vector2i(x, y)
			if owners.has(cell):
				continue
			var cells: Array[Vector2i] = [cell]
			var service_size: Vector2=Vector2(xs[x+1]-xs[x],ys[y+1]-ys[y])
			var service: bool=minf(service_size.x,service_size.y)>=_scheme.service_shower_short_side.x-.001 \
				and minf(service_size.x,service_size.y)<=_scheme.service_shower_short_side.y+.001 \
				and maxf(service_size.x,service_size.y)>=_scheme.service_shower_long_side.x-.001 \
				and maxf(service_size.x,service_size.y)<=_scheme.service_shower_long_side.y+.001 \
				and _endless_random.next_double()<_scheme.service_shower_chance
			var corridor: bool = _endless_random.next_double() < _scheme.dense_corridor_chance
			var offsets: Array[Vector2i] = []
			var corridor_directions: Array[Vector2i] = []
			if ys[y + 1] - ys[y] <= _scheme.corridor_width_max + 0.001:
				corridor_directions.append(GRID_EAST)
			if xs[x + 1] - xs[x] <= _scheme.corridor_width_max + 0.001:
				corridor_directions.append(GRID_NORTH)
			corridor = corridor and not corridor_directions.is_empty() and not service
			if corridor:
				var direction: Vector2i = corridor_directions[_endless_random.next_int(0, corridor_directions.size())]
				offsets = [direction, direction * 2]
			elif not service:
				match _dense_shape():
					1: offsets = [GRID_EAST]
					2: offsets = [GRID_NORTH]
					3: offsets = [GRID_EAST, GRID_NORTH]
					4: offsets = [GRID_EAST, GRID_NORTH, GRID_EAST + GRID_NORTH]
			var fits: bool = true
			for offset: Vector2i in offsets:
				var other: Vector2i = cell + offset
				if other.x >= columns or other.y >= rows or owners.has(other):
					fits = false
					break
			if fits:
				for offset: Vector2i in offsets:
					cells.append(cell + offset)
			var end_cell: Vector2i = cell
			for part: Vector2i in cells:
				end_cell = end_cell.max(part)
			var span: Vector2 = Vector2(xs[end_cell.x + 1] - xs[x], ys[end_cell.y + 1] - ys[y])
			if corridor and (maxf(span.x, span.y) > _scheme.corridor_length_max \
					or maxf(span.x, span.y) < _scheme.corridor_length_min):
				cells = [cell]
			if not corridor and not service and (span.x > ordinary_span_limit.x + .001 or span.y > ordinary_span_limit.y + .001):
				cells = [cell]
			_add_dense_room(cells, xs, ys, origin, owners, corridor and cells.size() == 3)
			_potential_nodes[-1].service_shower=service
	if not _dense_enlarge_rooms(owners, xs, ys, origin, shaft_cell): return []
	# Derive one port per shared wall interval, not from room centres.
	for y: int in rows:
		for x: int in columns:
			var cell: Vector2i = Vector2i(x, y)
			for step: Vector2i in [GRID_EAST, GRID_NORTH]:
				var other: Vector2i = cell + step
				if not owners.has(other):
					continue
				var first: EndlessNode = _potential_nodes[owners[cell]]
				var second: EndlessNode = _potential_nodes[owners[other]]
				if first == second or first.links.has(second.index):
					continue
				if (first.index == 0 or second.index == 0) and not (first.index in [0, 1] and second.index in [0, 1]):
					continue
				var port: Vector2 = Vector2(xs[x + 1], (ys[y] + ys[y + 1]) * 0.5) if step == GRID_EAST \
					else Vector2((xs[x] + xs[x + 1]) * 0.5, ys[y + 1])
				var direction: int = EndlessNode.EXIT_EAST if step == GRID_EAST else EndlessNode.EXIT_NORTH
				first.links.append(second.index)
				second.links.append(first.index)
				first.link_directions[second.index] = direction
				second.link_directions[first.index] = _opposite_exit(direction)
				first.link_positions[second.index] = port - origin
				second.link_positions[first.index] = port - origin
				var shared_length: float = ys[y + 1] - ys[y] if step == GRID_EAST else xs[x + 1] - xs[x]
				var width: float = minf(_scheme.dense_doorway_width, shared_length - _scheme.doorway_jamb_width * 2.0)
				first.link_widths[second.index] = width
				second.link_widths[first.index] = width
	for node: EndlessNode in _potential_nodes:
		node.exits = _exit_mask(node, _potential_nodes)
	if not _configure_dense_entry(): return []
	var selected: Array[int] = _dense_select_routes(shaft_cell)
	# Route constraints may exhaust growth; retry rather than return too few rooms.
	if selected.size() < _scheme.active_rooms_min: return []
	# The required shower must remain reachable within the route budget.
	var services: int=0
	for index: int in selected: services+=int(_potential_nodes[index].service_shower)
	if services<_scheme.active_service_shower_min_count:return []
	return _dense_active_nodes(selected)


# Repair small rooms by merging cells; measure union area, not bounding-box area.
func _dense_enlarge_rooms(owners: Dictionary, xs: Array[float], ys: Array[float],
	origin: Vector2, shaft: Vector2i) -> bool:
	var area_limits: Vector2 = room_area_limits(_scheme)
	var span_limit: Vector2 = _scheme.background_max_player_span * _scheme.room_player_width
	var groups: Dictionary = {}
	var source_area: Dictionary = {}
	var order: Array[int] = []
	for node: EndlessNode in _potential_nodes:
		var area: float = 0.0
		for part: Rect2 in node.floor_areas_unity:
			area += part.get_area()
		source_area[node.index] = area
		groups[node.index] = {"cells": node.building_cells.duplicate(), "area": area,
			"largest": area, "source_areas": PackedFloat32Array([area]),
			"corridor": node.role == EndlessNode.Role.HALL,"service_shower":node.service_shower}
		if node.index > 1 and node.role != EndlessNode.Role.HALL and not node.service_shower:
			order.append(node.index)
	order.sort_custom(func(a: int, b: int) -> bool: return float(source_area[a]) > float(source_area[b]))
	for original: int in order:
		if not groups.has(original):
			continue
		var current: int = original
		while float(groups[current].area) + .001 < maxf(area_limits.x,float(groups[current].largest) * _scheme.dense_room_area_multiplier):
			var group: Dictionary = groups[current]
			var candidates: Dictionary = {}
			for cell: Vector2i in group.cells:
				for step: Vector2i in [GRID_EAST, GRID_NORTH, GRID_WEST, GRID_SOUTH]:
					var adjacent: int = int(owners.get(cell + step, -1))
					if adjacent > 1 and adjacent != current:
						candidates[adjacent] = true
			var best: int = -1
			var score: float = INF
			var best_is_corridor: bool = true
			for candidate: int in candidates:
				if bool(groups[candidate].service_shower): continue
				var cells: Array[Vector2i] = []
				cells.assign(group.cells)
				cells.append_array(groups[candidate].cells)
				if current == 1 or candidate == 1:
					var below_shaft: bool = true
					for cell: Vector2i in cells:
						below_shaft = below_shaft and cell.y < shaft.y
					if not below_shaft:
						continue
				if not _dense_cells_have_one_boundary(cells):
					continue
				var combined: float = float(group.area) + float(groups[candidate].area)
				if combined > area_limits.y + .001: continue
				var required: float = maxf(area_limits.x,maxf(float(group.largest), float(groups[candidate].largest)) * _scheme.dense_room_area_multiplier)
				var low: Vector2i = cells[0]
				var high: Vector2i = cells[0]
				for cell: Vector2i in cells:
					low = low.min(cell)
					high = high.max(cell)
				var span: Vector2 = Vector2(xs[high.x + 1] - xs[low.x],ys[high.y + 1] - ys[low.y])
				# Repair before selecting active rooms so contours, IDs and ports stay aligned.
				if span.x > span_limit.x + .001 or span.y > span_limit.y + .001: continue
				var bounding_area: float = span.x * span.y
				var candidate_score: float = absf(combined - required) / required + bounding_area / combined
				var is_corridor: bool = bool(groups[candidate].corridor)
				if (best_is_corridor and not is_corridor) or (is_corridor == best_is_corridor and candidate_score < score):
					score = candidate_score
					best = candidate
					best_is_corridor = is_corridor
			# Repartition locally when a whole-room merge would exceed the span limit.
			if best < 0 and _dense_repartition_neighbours(current, groups, owners, xs, ys, shaft, area_limits, span_limit):
				continue
			if best < 0: return false
			var keep: int = 1 if best == 1 else current
			var remove: int = current if best == 1 else best
			var merged: Dictionary = groups[keep]
			merged.cells.append_array(groups[remove].cells)
			merged.area = float(merged.area) + float(groups[remove].area)
			merged.largest = maxf(float(merged.largest), float(groups[remove].largest))
			var sources: PackedFloat32Array = merged.source_areas
			sources.append_array(groups[remove].source_areas)
			merged.source_areas = sources
			for cell: Vector2i in merged.cells:
				owners[cell] = keep
			groups.erase(remove)
			current = keep
	var keys: Array = groups.keys()
	keys.sort()
	_potential_nodes = []
	owners.clear()
	for key: int in keys:
		var group: Dictionary = groups[key]
		var cells: Array[Vector2i] = []
		cells.assign(group.cells)
		_add_dense_room(cells, xs, ys, origin, owners, bool(group.corridor))
		_potential_nodes[-1].service_shower=bool(group.service_shower)
		_potential_nodes[-1].set_meta("endless_unmerged_room_areas", group.source_areas)
	_potential_nodes[0].role = EndlessNode.Role.START
	_potential_nodes[1].role = EndlessNode.Role.HUB
	_potential_nodes[1].set_meta("apartment_entry",true)
	return true


func _dense_repartition_neighbours(current: int, groups: Dictionary, owners: Dictionary,
	xs: Array[float], ys: Array[float], shaft: Vector2i, area_limits: Vector2, span_limit: Vector2) -> bool:
	var neighbours: Dictionary = {}
	for cell: Vector2i in groups[current].cells:
		for step: Vector2i in [GRID_EAST, GRID_NORTH, GRID_WEST, GRID_SOUTH]:
			var owner: int = int(owners.get(cell+step,-1))
			if owner > 1 and owner != current and not bool(groups[owner].service_shower): neighbours[owner] = true
	var ids: Array = neighbours.keys()
	for donor_id: int in ids:
		if _dense_try_local_partition(current,donor_id,-1,groups,owners,xs,ys,shaft,area_limits,span_limit): return true
	for a: int in ids.size():
		for b: int in range(a+1,ids.size()):
			if _dense_try_local_partition(current,int(ids[a]),int(ids[b]),groups,owners,xs,ys,shaft,area_limits,span_limit): return true
	return false


func _dense_try_local_partition(current: int, donor_id: int, consumed_id: int, groups: Dictionary,
	owners: Dictionary, xs: Array[float], ys: Array[float], shaft: Vector2i, area_limits: Vector2, span_limit: Vector2) -> bool:
	var target: Dictionary = groups[current]
	var donor: Dictionary = groups[donor_id]
	var cells: Array[Vector2i] = []; cells.assign(target.cells); cells.append_array(donor.cells)
	if consumed_id >= 0: cells.append_array(groups[consumed_id].cells)
	# Bound repair to two immediate neighbours.
	if cells.size() > 14: return false
	var areas: PackedFloat64Array = []
	var total_area: float = 0.0
	for cell: Vector2i in cells:
		var area: float = (xs[cell.x+1]-xs[cell.x])*(ys[cell.y+1]-ys[cell.y])
		areas.append(area); total_area+=area
	for mask: int in range(1,1 << cells.size(),2):
		var first_area: float = 0.0
		for index: int in cells.size():
			if mask & (1 << index): first_area += areas[index]
		var second_area: float = total_area-first_area
		if first_area < area_limits.x-.001 or first_area > area_limits.y+.001 or second_area <= .001: continue
		if second_area > area_limits.y+.001: continue
		var first: Array[Vector2i] = []; var second: Array[Vector2i] = []
		for index: int in cells.size():
			if mask & (1 << index): first.append(cells[index])
			else: second.append(cells[index])
		if current == 1:
			var preserves_landing: bool = true
			for cell: Vector2i in target.cells: preserves_landing = preserves_landing and first.has(cell)
			for cell: Vector2i in first: preserves_landing = preserves_landing and cell.y < shaft.y
			if not preserves_landing: continue
		var first_span: Vector2 = _dense_cells_span(first,xs,ys)
		if first_span.x > span_limit.x+.001 or first_span.y > span_limit.y+.001: continue
		var second_span: Vector2 = _dense_cells_span(second,xs,ys)
		var hall_owner: int = int(owners[second[0]])
		var second_hall: bool = bool(groups[hall_owner].corridor)
		for cell: Vector2i in second: second_hall = second_hall and int(owners[cell]) == hall_owner
		second_hall = second_hall and minf(second_span.x,second_span.y) <= _scheme.corridor_width_max+.001 \
			and maxf(second_span.x,second_span.y) >= _scheme.corridor_length_min-.001 and maxf(second_span.x,second_span.y) <= _scheme.corridor_length_max+.001 \
			and absf(second_span.x*second_span.y-second_area) < .02
		if not second_hall and (second_area < area_limits.x-.001 or second_span.x > span_limit.x+.001 or second_span.y > span_limit.y+.001): continue
		if not _dense_cells_have_one_boundary(first) or not _dense_cells_have_one_boundary(second): continue
		target.cells=first; target.area=first_area
		donor.cells=second; donor.area=second_area; donor.corridor=second_hall
		if consumed_id >= 0: groups.erase(consumed_id)
		for entry: Dictionary in [{"id":current,"group":target},{"id":donor_id,"group":donor}]:
			var repaired: Dictionary = entry.group
			var sources: PackedFloat32Array = []
			repaired.largest=0.0
			for cell: Vector2i in repaired.cells:
				var area: float = (xs[cell.x+1]-xs[cell.x])*(ys[cell.y+1]-ys[cell.y])
				sources.append(area); repaired.largest=maxf(float(repaired.largest),area); owners[cell]=entry.id
			repaired.source_areas=sources
		return true
	return false


static func _dense_cells_span(cells: Array[Vector2i], xs: Array[float], ys: Array[float]) -> Vector2:
	var low: Vector2i = cells[0]
	var high: Vector2i = cells[0]
	for cell: Vector2i in cells:
		low = low.min(cell); high = high.max(cell)
	return Vector2(xs[high.x+1]-xs[low.x],ys[high.y+1]-ys[low.y])


static func room_area_limits(scheme: EndlessScheme) -> Vector2:
	return scheme.room_player_area_limits * scheme.room_player_width * scheme.room_player_width


# Reject holes and point contacts: both break the single connected floor contour.
static func _dense_cells_have_one_boundary(cells: Array[Vector2i]) -> bool:
	var edges: Dictionary = {}
	for cell: Vector2i in cells:
		var candidates: Array[Array] = [
			[cell + GRID_SOUTH, cell, cell + GRID_EAST],
			[cell + GRID_EAST, cell + GRID_EAST, cell + GRID_EAST + GRID_NORTH],
			[cell + GRID_NORTH, cell + GRID_EAST + GRID_NORTH, cell + GRID_NORTH],
			[cell + GRID_WEST, cell + GRID_NORTH, cell]]
		for edge: Array in candidates:
			if cells.has(edge[0]):
				continue
			if edges.has(edge[1]):
				return false
			edges[edge[1]] = edge[2]
	var first: Vector2i = edges.keys()[0]
	var cursor: Vector2i = first
	for count: int in edges.size():
		if not edges.has(cursor):
			return false
		cursor = edges[cursor]
		if cursor == first:
			return count + 1 == edges.size()
	return false


# Record opened connections during route growth; adjacency alone does not open a wall.
func _configure_dense_entry() -> bool:
	var entry: EndlessNode = _potential_nodes[1]
	var stairs: Array[Rect2] = entry_stair_pockets(entry,_scheme)
	var choices: Array[int]=[]
	var working: Array[int]=[]
	for index: int in entry.links:
		if index==0 or _potential_nodes[index].service_shower or is_corridor(_potential_nodes[index],_scheme): continue
		var point: Vector2 = _to_godot_point(entry.link_positions[index])
		var behind_stairs: bool=false
		for pocket: Rect2 in stairs:
			if pocket.grow(_scheme.dense_doorway_width*.5+_scheme.doorway_jamb_width).has_point(point): behind_stairs=true;break
		if behind_stairs: continue
		choices.append(index)
		if _dense_active_allowed(_potential_nodes[index],_potential_nodes[0].building_cells[0]): working.append(index)
	if choices.size()<_scheme.entry_door_limits.x or working.size()<_scheme.entry_working_door_limits.x: return false
	working.sort_custom(func(a: int,b: int)->bool:return _potential_nodes[a].center.x<_potential_nodes[b].center.x)
	var left: int=working[0]
	var right: int=working[-1]
	if _potential_nodes[left].center.x>=entry.center.x or _potential_nodes[right].center.x<=entry.center.x: return false
	_entry_exits=[left,right]
	var count: int=_endless_random.next_int(_scheme.entry_door_limits.x,mini(_scheme.entry_door_limits.y,choices.size())+1)
	var desired: int=_endless_random.next_int(_scheme.entry_working_door_limits.x,mini(_scheme.entry_working_door_limits.y,mini(count,working.size()))+1)
	for index: int in working:
		if _entry_exits.size()>=desired: break
		if not _entry_exits.has(index): _entry_exits.append(index)
	var retained: Array[int]=_entry_exits.duplicate()
	for attempt: int in _scheme.packing_attempts:
		if retained.size()>=count: break
		var index: int=choices[_endless_random.next_int(0,choices.size())]
		if not retained.has(index): retained.append(index)
	# Bounded draws need a deterministic fallback when samples repeat.
	if retained.size()<count:
		entry.set_meta("entry_draw_fallback",true)
		for index: int in choices:
			if retained.size()>=count:break
			if not retained.has(index):retained.append(index)
	for index: int in entry.links.duplicate():
		if index==0 or retained.has(index): continue
		entry.links.erase(index)
		_potential_nodes[index].links.erase(1)
	for index: int in retained: _potential_nodes[index].set_meta("entry_neighbour",true)
	return true


static func entry_stair_bounds(node: EndlessNode, scheme: EndlessScheme, side: int=1) -> Rect2:
	var bounds: Rect2 = _godot_room_bounds(node.center,node.size)
	# Stair pockets meet the shaft masonry and the inner perimeter wall.
	var width: float=bounds.size.x*.5-4.60-.27
	var x: float=bounds.get_center().x+4.60 if side>0 else bounds.get_center().x-4.60-width
	return Rect2(Vector2(x,bounds.position.y+.27),Vector2(width,scheme.entry_stair_size.y+scheme.entry_stair_rear_depth))


static func entry_stair_pockets(node: EndlessNode, scheme: EndlessScheme) -> Array[Rect2]:
	return [entry_stair_bounds(node,scheme,-1),entry_stair_bounds(node,scheme,1)]


func _route_capacity(index: int) -> int:
	return _entry_exits.size()+1 if index==1 else _scheme.active_route_max_degree


func _dense_select_routes(shaft: Vector2i) -> Array[int]:
	var selected: Array[int] = [0, 1]
	_dense_route_links = {0: [1], 1: [0]}
	var target: int = _endless_random.next_int(_scheme.active_rooms_min, _scheme.active_rooms_max + 1)
	for neighbour: int in _entry_exits:
		selected.append(neighbour)
		_dense_connect_route(1,neighbour)
	# Start both wings explicitly; local growth scores can otherwise favour one side.
	for root_index: int in mini(2,_entry_exits.size()):
		var wing_tip: int = _entry_exits[root_index]
		var sign_x: float = signf(_potential_nodes[wing_tip].center.x-_potential_nodes[1].center.x)
		for step: int in _scheme.entry_wing_steps:
			if _potential_nodes[wing_tip].service_shower: break
			var next: int = -1
			var score: float = -INF
			for candidate: int in _potential_nodes[wing_tip].links:
				if selected.has(candidate) or selected.size()>=target or not _dense_route_candidate(candidate,selected,shaft,target): continue
				var pull: float = (_potential_nodes[candidate].center.x-_potential_nodes[wing_tip].center.x)*sign_x
				if pull>score: score=pull;next=candidate
			if next<0: break
			selected.append(next);_dense_connect_route(wing_tip,next);wing_tip=next
	# Sanitary rooms are single-entrance destinations, not route shortcuts.
	var services: int=0
	for anchor: int in selected.duplicate():
		if anchor<=1 or _potential_nodes[anchor].service_shower: continue
		for neighbour: int in _potential_nodes[anchor].links:
			if services>=_scheme.active_service_shower_min_count or selected.size()>=target or _dense_route_links[anchor].size()>=_route_capacity(anchor): break
			if not selected.has(neighbour) and _potential_nodes[neighbour].service_shower and _dense_active_allowed(_potential_nodes[neighbour],shaft):
				selected.append(neighbour); _dense_connect_route(anchor,neighbour); services+=1
	var tip: int = 1
	var steps: int = 0
	var arm: int = 0
	var loops: int = 0
	var handedness: float = -1.0 if _endless_random.next_double() < 0.5 else 1.0
	var direction: Vector2 = Vector2(handedness, -_endless_random.next_double()).normalized()
	while selected.size() < target:
		if loops < _scheme.active_route_loop_count and selected.size() >= \
				(loops + 1) * _scheme.active_route_arm_steps:
			if _dense_add_route_loop(selected, shaft, target):
				loops += 1
				if selected.size() >= target:
					break
		var best: float = -INF
		var chosen: int = -1
		var parent: int = -1
		var change_arm: bool = steps >= _scheme.active_route_arm_steps
		if change_arm:
			arm += 1
			steps = 0
			direction = Vector2(handedness * (-1.0 if arm % 2 else 1.0),
				-_endless_random.next_double()).normalized()
		for anchor: int in selected:
			if anchor == 0 or _potential_nodes[anchor].service_shower or _dense_route_links[anchor].size() >= _route_capacity(anchor):
				continue
			for candidate: int in _potential_nodes[anchor].links:
				if selected.has(candidate) or not _dense_route_candidate(candidate, selected, shaft, target):
					continue
				var node: EndlessNode = _potential_nodes[candidate]
				var step_direction: Vector2 = (node.center - _potential_nodes[anchor].center).normalized()
				var neighbours: int = 0
				for neighbour: int in node.links:
					neighbours += int(selected.has(neighbour))
				var score: float = step_direction.dot(direction) * _scheme.active_route_spread_weight \
					- (neighbours - 1) * _scheme.active_route_spread_weight + _endless_random.next_double()
				if not change_arm and anchor == tip:
					score += _scheme.active_route_spread_weight * 2.0
				if change_arm:
					score += float(_dense_route_links[anchor].size() - 1)
				if score > best:
					best = score
					chosen = candidate
					parent = anchor
		if chosen < 0:
			break
		selected.append(chosen)
		_dense_connect_route(parent, chosen)
		tip = chosen
		steps += 1
	while loops < _scheme.active_route_loop_count and _dense_add_route_loop(selected, shaft, target):
		loops += 1
	return selected


func _dense_route_candidate(index: int, selected: Array[int], shaft: Vector2i, target: int) -> bool:
	if not _dense_active_allowed(_potential_nodes[index], shaft):
		return false
	if _potential_nodes[index].role != EndlessNode.Role.HALL:
		return true
	var corridors: int = 0
	for existing: int in selected:
		corridors += int(_potential_nodes[existing].role == EndlessNode.Role.HALL)
	return corridors < floori((target - 1) * _scheme.active_corridor_target_fraction)


func _dense_connect_route(first: int, second: int) -> void:
	if not _dense_route_links.has(first):
		_dense_route_links[first] = []
	if not _dense_route_links.has(second):
		_dense_route_links[second] = []
	_dense_route_links[first].append(second)
	_dense_route_links[second].append(first)


func _dense_add_route_loop(selected: Array[int], shaft: Vector2i, target: int) -> bool:
	var best_path: Array[int] = []
	var best_score: float = -INF
	for anchor: int in selected:
		if anchor == 0 or _potential_nodes[anchor].service_shower or _dense_route_links[anchor].size() >= _route_capacity(anchor):
			continue
		var queue: Array[Array] = [[anchor]]
		var visited: Dictionary = {anchor: true}
		for raw_path: Array in queue:
			var path: Array[int] = []
			path.assign(raw_path)
			var last: int = path[-1]
			for neighbour: int in _potential_nodes[last].links:
				if visited.has(neighbour) or neighbour == 0 or _potential_nodes[neighbour].service_shower:
					continue
				if selected.has(neighbour):
					if _dense_route_links[neighbour].size() >= _route_capacity(neighbour) \
							or (path.size() == 1 and _dense_route_links[anchor].has(neighbour)):
						continue
					var score: float = -float(path.size()) + _endless_random.next_double()
					if score > best_score:
						best_score = score
						best_path = path.duplicate()
						best_path.append(neighbour)
					continue
				if path.size() > _scheme.active_route_loop_detour_rooms \
						or selected.size() + path.size() > target:
					continue
				var provisional: Array[int] = selected.duplicate()
				for part: int in path:
					if not provisional.has(part):
						provisional.append(part)
				if not _dense_route_candidate(neighbour, provisional, shaft, target):
					continue
				visited[neighbour] = true
				var next_path: Array[int] = path.duplicate()
				next_path.append(neighbour)
				queue.append(next_path)
	if best_path.is_empty():
		return false
	for index: int in range(1, best_path.size()):
		if not selected.has(best_path[index]):
			selected.append(best_path[index])
		_dense_connect_route(best_path[index - 1], best_path[index])
	return true


func _dense_shape() -> int:
	var total: float = 0.0
	for weight: float in _scheme.dense_room_weights:
		total += maxf(0.0, weight)
	var draw: float = _endless_random.next_double() * total
	for index: int in _scheme.dense_room_weights.size():
		draw -= maxf(0.0, _scheme.dense_room_weights[index])
		if draw < 0.0:
			return index
	return 0


func _dense_cell_size() -> float:
	if _endless_random.next_double() < _scheme.building_narrow_axis_chance:
		return _dimension(_scheme.corridor_width_min, _scheme.corridor_width_max)
	return _dimension(_scheme.building_cell_min, _scheme.building_cell_max)


func _dense_service_cell_size() -> Vector2:
	var short_limits: Vector2=_scheme.service_shower_short_side
	var long_limits: Vector2=_scheme.service_shower_long_side
	var short_side: float=clampf(_dimension(short_limits.x,short_limits.y),short_limits.x,short_limits.y)
	var long_side: float=clampf(_dimension(long_limits.x,long_limits.y),long_limits.x,long_limits.y)
	return Vector2(short_side,long_side) if _endless_random.next_double()<.5 else Vector2(long_side,short_side)


func _add_dense_room(cells: Array[Vector2i], xs: Array[float], ys: Array[float], origin: Vector2,
	owners: Dictionary, corridor: bool) -> void:
	var node: EndlessNode = _packed_node("room_hall_ew_01" if corridor else "room_square_new_01", Vector2.ONE, 0)
	node.building_cells = cells
	var bounds: Rect2 = Rect2()
	for cell: Vector2i in cells:
		owners[cell] = node.index
		var area: Rect2 = Rect2(Vector2(xs[cell.x], ys[cell.y]) - origin,
			Vector2(xs[cell.x + 1] - xs[cell.x], ys[cell.y + 1] - ys[cell.y]))
		node.floor_areas_unity.append(area)
		bounds = area if node.floor_areas_unity.size() == 1 else bounds.merge(area)
		var margin: int = _scheme.building_perimeter_cells
		node.perimeter_room = node.perimeter_room or cell.x < margin or cell.y < margin \
			or cell.x >= _scheme.building_columns - margin or cell.y >= _scheme.building_rows - margin
	node.center = bounds.get_center()
	node.floor_outline_unity = _dense_outline(cells, xs, ys, origin)
	node.size = bounds.size
	node.world_height = bounds.size.y
	node.grid = cells[0]
	_potential_nodes.append(node)


# Trace integer cell edges before conversion; floating unions can split a shared
# seam into separate polygons and discard part of the room.
static func _dense_outline(cells: Array[Vector2i], xs: Array[float], ys: Array[float], origin: Vector2) -> PackedVector2Array:
	var edges: Dictionary = {}
	for cell: Vector2i in cells:
		if not cells.has(cell + GRID_SOUTH):
			edges[cell] = cell + GRID_EAST
		if not cells.has(cell + GRID_EAST):
			edges[cell + GRID_EAST] = cell + GRID_EAST + GRID_NORTH
		if not cells.has(cell + GRID_NORTH):
			edges[cell + GRID_EAST + GRID_NORTH] = cell + GRID_NORTH
		if not cells.has(cell + GRID_WEST):
			edges[cell + GRID_NORTH] = cell
	var first: Vector2i = edges.keys()[0]
	var cursor: Vector2i = first
	var vertices: Array[Vector2i] = []
	for step: int in edges.size():
		vertices.append(cursor)
		cursor = edges[cursor]
		if cursor == first:
			break
	var result: PackedVector2Array = PackedVector2Array()
	for index: int in vertices.size():
		var previous: Vector2i = vertices[posmod(index - 1, vertices.size())]
		var point: Vector2i = vertices[index]
		var following: Vector2i = vertices[(index + 1) % vertices.size()]
		if (point - previous).x * (following - point).y == (point - previous).y * (following - point).x:
			continue
		result.append(Vector2(xs[point.x], ys[point.y]) - origin)
	return result


func _dense_active_allowed(node: EndlessNode, shaft: Vector2i) -> bool:
	if node.perimeter_room:
		return false
	for cell: Vector2i in node.building_cells:
		if cell.y >= shaft.y or cell.y < shaft.y - _scheme.active_sector_radius_cells \
				or absi(cell.x - shaft.x) > _scheme.active_sector_radius_cells:
			return false
	return true


func _dense_active_nodes(selected: Array[int]) -> Array[EndlessNode]:
	var parents: Dictionary = {0: -1}
	var queue: Array[int] = [0]
	var final: int = 1
	for index: int in queue:
		for neighbour: int in _dense_route_links[index]:
			if selected.has(neighbour) and not parents.has(neighbour):
				parents[neighbour] = index
				queue.append(neighbour)
				var candidate: EndlessNode = _potential_nodes[neighbour]
				if not candidate.service_shower and candidate.role == EndlessNode.Role.OPTIONAL_ARENA and candidate.floor_outline_unity.size() == 4 \
						and minf(candidate.size.x, candidate.size.y) >= _scheme.boss_room_min_side:
					final = neighbour
	var path: Array[int] = []
	var ancestor: int = final
	while ancestor >= 0:
		path.push_front(ancestor)
		ancestor = parents[ancestor]
	selected.erase(final)
	selected.append(final)
	_active_master_indices = PackedInt32Array(selected)
	_sealed_ports = []
	var active: Array[EndlessNode] = []
	for i: int in selected.size():
		var source: EndlessNode = _potential_nodes[selected[i]]
		var node: EndlessNode = _packed_node(source.asset_name, source.size, 0)
		node.index = i
		node.set_meta("endless_master_index", source.index)
		node.center = source.center
		node.grid = source.grid
		node.lighting_seed = source.lighting_seed
		node.floor_areas_unity = source.floor_areas_unity.duplicate()
		node.floor_outline_unity = source.floor_outline_unity.duplicate()
		node.building_cells = source.building_cells.duplicate()
		node.service_shower = source.service_shower
		if source.has_meta("apartment_entry"): node.set_meta("apartment_entry",true)
		if source.has_meta("entry_neighbour"): node.set_meta("entry_neighbour",true)
		node.set_meta("endless_unmerged_room_areas", source.get_meta("endless_unmerged_room_areas", PackedFloat32Array()))
		node.main_path_order = path.find(selected[i])
		node.optional = node.main_path_order < 0
		node.boss = selected[i] == final
		node.role = EndlessNode.Role.START if i == 0 else (EndlessNode.Role.BOSS if node.boss else source.role)
		for neighbour: int in source.links:
			var active_index: int = selected.find(neighbour)
			var direction: int = source.link_directions[neighbour]
			if active_index >= 0 and _dense_route_links[selected[i]].has(neighbour):
				node.links.append(active_index)
				node.link_directions[active_index] = direction
				node.link_positions[active_index] = source.link_positions[neighbour]
				node.link_widths[active_index] = source.link_widths[neighbour]
			elif (active_index < 0 or source.has_meta("apartment_entry")) and not source.service_shower and not _potential_nodes[neighbour].service_shower:
				_append_sealed_port(source, _potential_nodes[neighbour], i)
		active.append(node)
	for node: EndlessNode in active:
		node.exits = _exit_mask(node, active)
	return active


# Preserve opening identity and its shared interval through room reindexing.
static func portal_id(first_master: int, second_master: int) -> String:
	return "%d:%d" % [mini(first_master, second_master), maxi(first_master, second_master)]


func _append_sealed_port(source: EndlessNode, peer: EndlessNode, active_room: int) -> void:
	var identity: String = portal_id(source.index, peer.index)
	for existing: Dictionary in _sealed_ports:
		if existing.portal_id == identity:
			return
	var direction: int = int(source.link_directions[peer.index])
	var first: Vector2 = connection_anchor_position(source, peer.index)
	var second: Vector2 = connection_anchor_position(peer, source.index)
	assert(first.distance_to(second) <= LINK_SEAM_TOLERANCE, "Sealed portal source anchors disagree")
	var at: Vector2 = _to_godot_point((first + second) * .5)
	var normal: Vector2 = {EndlessNode.EXIT_EAST: Vector2.RIGHT, EndlessNode.EXIT_WEST: Vector2.LEFT,
		EndlessNode.EXIT_NORTH: Vector2.UP, EndlessNode.EXIT_SOUTH: Vector2.DOWN}[direction]
	var vertical: bool = absf(normal.x) > .5
	var axis: Vector2 = Vector2.DOWN if vertical else Vector2.RIGHT
	var width: float = minf(float(source.link_widths.get(peer.index, DOOR_CUT_WIDTH * 1.12)),
		float(peer.link_widths.get(source.index, DOOR_CUT_WIDTH * 1.12)))
	_sealed_ports.append({"portal_id": identity, "position": at, "axis": axis, "normal": normal,
		"from": at-axis*width*.5, "to": at+axis*width*.5, "horizontal_travel": vertical,
		"kind": ["grille", "furniture", "chain"][posmod(_endless_seed + _sealed_ports.size() * 7919, 3)],
		"width": width, "active_room": active_room, "active_master_room": source.index,
		"inactive_master_room": peer.index})
	if source.has_meta("apartment_entry"): _sealed_ports[-1]["apartment_entry"]=true


# Port-bearing contours are packed without snapping centres to a grid.
func _generate_sparse_expedition_architecture() -> Array[EndlessNode]:
	_potential_nodes = []
	var shaft: EndlessNode = _packed_node("room_square_new_01", Vector2(8, 7), 0)
	shaft.base_mask = EndlessNode.EXIT_SOUTH
	shaft.role = EndlessNode.Role.START
	_potential_nodes.append(shaft)
	var left_width: float = _dimension(_scheme.entry_loop_size_min, _scheme.entry_loop_size_max)
	var right_width: float = _dimension(_scheme.entry_loop_size_min, _scheme.entry_loop_size_max)
	var upper_height: float = _dimension(_scheme.entry_loop_size_min, _scheme.entry_loop_size_max)
	var lower_height: float = _dimension(_scheme.entry_loop_size_min, _scheme.entry_loop_size_max)
	var upper_left: EndlessNode = _packed_node("room_square_new_01", Vector2(left_width, upper_height), 0)
	_attach_packed(shaft, upper_left, EndlessNode.EXIT_SOUTH)
	var upper_right: EndlessNode = _packed_node("room_square_new_01", Vector2(right_width, upper_height), 0)
	_attach_packed(upper_left, upper_right, EndlessNode.EXIT_EAST)
	var lower_left: EndlessNode = _packed_node("room_square_new_01", Vector2(left_width, lower_height), 0)
	_attach_packed(upper_left, lower_left, EndlessNode.EXIT_SOUTH)
	var lower_right: EndlessNode = _packed_node("room_square_new_01", Vector2(right_width, lower_height), 0)
	_attach_packed(upper_right, lower_right, EndlessNode.EXIT_SOUTH)
	_connect_ports(lower_left, lower_right, EndlessNode.EXIT_EAST)
	var elbow: EndlessNode = _random_packed_node(PackedShape.ELBOW, EndlessNode.EXIT_NORTH)
	_attach_packed(lower_left, elbow, EndlessNode.EXIT_SOUTH)
	var tee: EndlessNode = _packed_node("room_junction_nesw_01",
		Vector2(_dimension(_scheme.bend_size_min, _scheme.bend_size_max),
		_dimension(_scheme.bend_size_min, _scheme.bend_size_max)), 0)
	_attach_packed(lower_right, tee, EndlessNode.EXIT_EAST)
	var bend_exit: int = _free_ports(elbow)[0]
	var first_passage: EndlessNode = _random_packed_node(PackedShape.STRAIGHT, _opposite_exit(bend_exit))
	_attach_packed(elbow, first_passage, bend_exit)
	var second_passage: EndlessNode = _random_packed_node(PackedShape.STRAIGHT, EndlessNode.EXIT_WEST)
	_attach_packed(tee, second_passage, EndlessNode.EXIT_EAST)
	var second_bend: EndlessNode = _random_packed_node(PackedShape.ELBOW, _opposite_exit(bend_exit))
	second_bend.center = door_anchor_position(first_passage, bend_exit) - _door_anchor_offset(second_bend, _opposite_exit(bend_exit))
	if not _packed_position_is_free(second_bend):
		# This orientation leaves the independently sized bend outside the initial loop.
		second_bend = _packed_node("room_corner_ne_01", unrotated_size(second_bend),
			2 if bend_exit == EndlessNode.EXIT_EAST else 3)
	_attach_packed(first_passage, second_bend, bend_exit)
	var reserved_count: int = _potential_nodes.size()
	var target: int = _endless_random.next_int(_scheme.potential_rooms_min, _scheme.potential_rooms_max + 1)
	for attempt: int in _scheme.packing_attempts:
		if _potential_nodes.size() >= target:
			break
		var parent: EndlessNode = _potential_nodes[_endless_random.next_int(1, _potential_nodes.size())]
		var free: Array[int] = _free_ports(parent)
		if free.is_empty():
			continue
		var direction: int = free[_endless_random.next_int(0, free.size())]
		var shape: int = _pick_packed_shape()
		var child: EndlessNode = _random_packed_node(shape, _opposite_exit(direction))
		child.center = door_anchor_position(parent, direction) - _door_anchor_offset(child, _opposite_exit(direction))
		if not _packed_position_is_free(child):
			continue
		_attach_packed(parent, child, direction)
	_complete_service_wing(target)
	var low: float = INF
	var high: float = -INF
	for node: EndlessNode in _potential_nodes:
		low = minf(low, node.center.y - node.size.y * 0.5)
		high = maxf(high, node.center.y + node.size.y * 0.5)
	for node: EndlessNode in _potential_nodes:
		node.center.y -= (low + high) * 0.5
		node.exits = _exit_mask(node, _potential_nodes)
	var selected: Array[int] = []
	for i: int in reserved_count:
		selected.append(i)
	var active_target: int = _endless_random.next_int(_scheme.active_rooms_min, _scheme.active_rooms_max + 1)
	while selected.size() < mini(active_target, _potential_nodes.size()):
		var candidates: Array[int] = []
		for index: int in selected:
			for neighbor: int in _potential_nodes[index].links:
				if not selected.has(neighbor) and not candidates.has(neighbor):
					candidates.append(neighbor)
		if candidates.is_empty():
			break
		var corridor_count: int = 0
		for index: int in selected:
			corridor_count += int(_is_passage(_potential_nodes[index]))
		if float(corridor_count) / float(selected.size() - 1) < _scheme.active_corridor_target_fraction:
			var passages: Array[int] = []
			for candidate: int in candidates:
				if _is_passage(_potential_nodes[candidate]):
					passages.append(candidate)
			if not passages.is_empty():
				candidates = passages
		selected.append(candidates[_endless_random.next_int(0, candidates.size())])
	var parents: Dictionary = {0: -1}
	var queue: Array[int] = [0]
	var final_master: int = 1
	for index: int in queue:
		for neighbor: int in _potential_nodes[index].links:
			if selected.has(neighbor) and not parents.has(neighbor):
				parents[neighbor] = index
				queue.append(neighbor)
				if _potential_nodes[neighbor].role == EndlessNode.Role.OPTIONAL_ARENA \
						and minf(_potential_nodes[neighbor].size.x, _potential_nodes[neighbor].size.y) >= _scheme.boss_room_min_side:
					final_master = neighbor
	var path: Array[int] = []
	var ancestor: int = final_master
	while ancestor >= 0:
		path.push_front(ancestor)
		ancestor = int(parents[ancestor])
	selected.erase(final_master)
	selected.append(final_master)
	_active_master_indices = PackedInt32Array(selected)
	var active: Array[EndlessNode] = []
	_sealed_ports = []
	for i: int in selected.size():
		var source: EndlessNode = _potential_nodes[selected[i]]
		var node: EndlessNode = _packed_node(source.asset_name, unrotated_size(source), source.quarter_turns)
		node.index = i
		node.set_meta("endless_master_index", source.index)
		node.grid = source.grid
		node.center = source.center
		node.base_mask = source.base_mask
		node.north_anchor = source.north_anchor
		node.east_anchor = source.east_anchor
		node.south_anchor = source.south_anchor
		node.west_anchor = source.west_anchor
		node.lighting_seed = source.lighting_seed
		node.main_path_order = path.find(selected[i])
		node.optional = node.main_path_order < 0
		node.boss = selected[i] == final_master
		node.role = EndlessNode.Role.START if i == 0 else (EndlessNode.Role.BOSS if node.boss else source.role)
		for neighbor: int in source.links:
			var direction: int = int(source.link_directions[neighbor])
			var active_index: int = selected.find(neighbor)
			if active_index >= 0:
				node.links.append(active_index)
				node.link_directions[active_index] = direction
			else:
				_append_sealed_port(source, _potential_nodes[neighbor], i)
		active.append(node)
	for node: EndlessNode in active:
		node.exits = _exit_mask(node, active)
	return active


func _dimension(minimum: float, maximum: float) -> float:
	return snappedf(lerpf(minimum, maximum, _endless_random.next_double()), 0.2)


func _complete_service_wing(target: int) -> void:
	# The outermost east half-plane is unoccupied and can host a fallback wing.
	while _potential_nodes.size() < target:
		var edge: EndlessNode = _potential_nodes[1]
		for candidate: EndlessNode in _potential_nodes:
			if candidate.center.x + candidate.size.x * 0.5 > edge.center.x + edge.size.x * 0.5:
				edge = candidate
		var anchors: Dictionary = {}
		for direction: int in edge.link_directions.values():
			anchors[direction] = _door_anchor_offset(edge, direction) / edge.size
		# Packing reserved the whole bounding box, so filling its concave notch is safe.
		_set_visual(edge, "room_square_new_01", edge.size.y, EndlessNode.EXIT_ALL)
		edge.quarter_turns = 0
		edge.north_anchor = anchors.get(EndlessNode.EXIT_NORTH, Vector2(0, 0.5))
		edge.south_anchor = anchors.get(EndlessNode.EXIT_SOUTH, Vector2(0, -0.5))
		edge.west_anchor = anchors.get(EndlessNode.EXIT_WEST, Vector2(-0.5, 0))
		edge.east_anchor = Vector2(0.5, 0)
		var passage: EndlessNode = _packed_node("room_hall_ew_01",
			Vector2(_scheme.corridor_length_min, _scheme.corridor_width_min), 0)
		_attach_packed(edge, passage, EndlessNode.EXIT_EAST)


func _packed_node(asset: String, dimensions: Vector2, turns: int) -> EndlessNode:
	var node: EndlessNode = EndlessNode.new()
	_set_visual(node, asset, dimensions.y, EndlessNode.EXIT_ALL)
	node.size = dimensions if turns % 2 == 0 else Vector2(dimensions.y, dimensions.x)
	node.quarter_turns = turns
	node.index = _potential_nodes.size()
	node.grid = Vector2i(node.index, 0) # identity only, never a placement lattice
	node.lighting_seed = trash_seed_for(_endless_seed, node.index)
	node.role = EndlessNode.Role.OPTIONAL_ARENA
	match asset:
		"room_corner_ne_01":
			node.base_mask = EndlessNode.EXIT_NORTH | EndlessNode.EXIT_EAST
			node.role = EndlessNode.Role.OPTIONAL_CONNECTOR
		"room_junction_nesw_01":
			node.base_mask = EndlessNode.EXIT_NORTH | EndlessNode.EXIT_EAST | EndlessNode.EXIT_WEST
			node.role = EndlessNode.Role.CONNECTOR
		"room_hall_ew_01":
			node.base_mask = EndlessNode.EXIT_EAST | EndlessNode.EXIT_WEST
			node.role = EndlessNode.Role.HALL
		"room_cross_nesw_01":
			node.role = EndlessNode.Role.HUB
	return node


func _random_packed_node(shape: int, required_port: int) -> EndlessNode:
	var dimensions: Vector2 = Vector2(_dimension(_scheme.room_size_min, _scheme.room_size_max),
		_dimension(_scheme.room_size_min, _scheme.room_size_max))
	var asset: String = "room_square_new_01"
	if shape == PackedShape.STRAIGHT:
		asset = "room_hall_ew_01"
		dimensions = Vector2(_dimension(_scheme.corridor_length_min, _scheme.corridor_length_max),
			_dimension(_scheme.corridor_width_min, _scheme.corridor_width_max))
	elif shape == PackedShape.ELBOW:
		asset = "room_corner_ne_01"
	elif shape == PackedShape.TEE:
		asset = "room_junction_nesw_01"
	elif shape == PackedShape.CROSS:
		asset = "room_cross_nesw_01"
		dimensions = Vector2(_dimension(_scheme.cross_room_size_min, _scheme.cross_room_size_max),
			_dimension(_scheme.cross_room_size_min, _scheme.cross_room_size_max))
	if shape in [PackedShape.ELBOW, PackedShape.TEE]:
		dimensions = Vector2(_dimension(_scheme.bend_size_min, _scheme.bend_size_max),
			_dimension(_scheme.bend_size_min, _scheme.bend_size_max))
	var rotations: Array[int] = []
	var node: EndlessNode = _packed_node(asset, dimensions, 0)
	for turn: int in 4:
		if (_rotate_mask(node.base_mask, turn) & required_port) != 0:
			rotations.append(turn)
	return _packed_node(asset, dimensions, rotations[_endless_random.next_int(0, rotations.size())])


func _pick_packed_shape() -> int:
	var weights: PackedFloat32Array = _scheme.shape_weights
	if _active_theme == 2:
		weights = _scheme.laboratory_shape_weights
	elif _active_theme == 4:
		weights = _scheme.attic_shape_weights
	var total: float = 0.0
	for weight: float in weights:
		total += maxf(0.0, weight)
	var value: float = _endless_random.next_double() * total
	for i: int in weights.size():
		value -= maxf(0.0, weights[i])
		if value < 0.0:
			return i
	return PackedShape.ROOM


static func _is_passage(node: EndlessNode) -> bool:
	return node.role in [EndlessNode.Role.HALL, EndlessNode.Role.OPTIONAL_CONNECTOR, EndlessNode.Role.CONNECTOR]


static func _free_ports(node: EndlessNode) -> Array[int]:
	var free: Array[int] = []
	var mask: int = _rotate_mask(node.base_mask, node.quarter_turns)
	for direction: int in [EndlessNode.EXIT_NORTH, EndlessNode.EXIT_EAST, EndlessNode.EXIT_SOUTH, EndlessNode.EXIT_WEST]:
		if (mask & direction) != 0 and not node.link_directions.values().has(direction):
			free.append(direction)
	return free


func _attach_packed(parent: EndlessNode, child: EndlessNode, direction: int) -> void:
	child.center = door_anchor_position(parent, direction) - _door_anchor_offset(child, _opposite_exit(direction))
	child.index = _potential_nodes.size()
	child.grid = Vector2i(child.index, 0)
	_potential_nodes.append(child)
	_connect_ports(parent, child, direction)


static func _connect_ports(first: EndlessNode, second: EndlessNode, direction: int) -> void:
	first.links.append(second.index)
	second.links.append(first.index)
	first.link_directions[second.index] = direction
	second.link_directions[first.index] = _opposite_exit(direction)


func _packed_position_is_free(node: EndlessNode) -> bool:
	var bounds: Rect2 = Rect2(node.center - node.size * 0.5, node.size)
	# The north side is reserved for the shaft, never a traversable branch.
	if bounds.end.y > -3.5 + 0.001 or bounds.position.y < -_scheme.architecture_height_limit:
		return false
	for other: EndlessNode in _potential_nodes:
		var occupied: Rect2 = Rect2(other.center - other.size * 0.5, other.size).grow(-0.02)
		if bounds.grow(-0.02).intersects(occupied):
			return false
	return true


static func _connection_direction(node: EndlessNode, other: EndlessNode) -> int:
	return int(node.link_directions.get(other.index, _exit_mask_from_grid_delta(other.grid - node.grid)))


static func _axis_cell_center(sizes: Array[float], index: int) -> float:
	var result: float = -sizes[0] * 0.5
	for i: int in index:
		result += sizes[i]
	return result + sizes[index] * 0.5


func _architectural_wall_segments(node: EndlessNode) -> Array[WallSegmentDef]:
	var result: Array[WallSegmentDef] = []
	if not node.floor_outline_unity.is_empty():
		for i: int in node.floor_outline_unity.size():
			_append_cut_segments(result, node.floor_outline_unity[i],
				node.floor_outline_unity[(i + 1) % node.floor_outline_unity.size()], node, node.exits)
		return result
	var outline: PackedVector2Array = _contour_for_asset(node.asset_name, unrotated_size(node))
	for i: int in outline.size():
		_append_cut_segments(result, node.center + _rotate_local(outline[i], node.quarter_turns),
			node.center + _rotate_local(outline[(i + 1) % outline.size()], node.quarter_turns), node, node.exits)
	return result


static func _own_shared_walls_once(rooms: Array[RoomDef]) -> void:
	var lines: Dictionary = {}
	var coordinates: Dictionary = {}
	for room: RoomDef in rooms:
		# One room owns shared-line physics; both retain inward wall faces for placement.
		if not room.has_meta("endless_visual_walls"):
			room.set_meta("endless_visual_walls", room.wall_segments.duplicate())
		var owned: Array[WallSegmentDef] = []
		for segment: WallSegmentDef in room.wall_segments:
			var horizontal: bool = absf(segment.from.y - segment.to.y) < 0.001
			var fixed: float = segment.from.y if horizontal else segment.from.x
			var prefix: String = "h" if horizontal else "v"
			var bucket: int = roundi(fixed * 1000.0)
			var key: String = prefix + str(bucket)
			# Fractional seams can straddle quantisation buckets; compare neighbouring buckets.
			for adjacent: int in [bucket, bucket - 1, bucket + 1]:
				var candidate_key: String = prefix + str(adjacent)
				if coordinates.has(candidate_key) and absf(float(coordinates[candidate_key]) - fixed) < 0.001:
					key = candidate_key
					fixed = float(coordinates[key])
					break
			var begin: float = minf(segment.from.x, segment.to.x) if horizontal else minf(segment.from.y, segment.to.y)
			var end: float = maxf(segment.from.x, segment.to.x) if horizontal else maxf(segment.from.y, segment.to.y)
			var pieces: Array[Vector2] = [Vector2(begin, end)]
			for occupied: Vector2 in lines.get(key, []):
				var remaining: Array[Vector2] = []
				for piece: Vector2 in pieces:
					if occupied.y <= piece.x + 0.001 or occupied.x >= piece.y - 0.001:
						remaining.append(piece)
						continue
					if occupied.x > piece.x + 0.001:
						remaining.append(Vector2(piece.x, occupied.x))
					if occupied.y < piece.y - 0.001:
						remaining.append(Vector2(occupied.y, piece.y))
				pieces = remaining
			if not lines.has(key):
				lines[key] = []
				coordinates[key] = fixed
			for piece: Vector2 in pieces:
				var wall: WallSegmentDef = WallSegmentDef.new()
				wall.from = Vector2(piece.x, fixed) if horizontal else Vector2(fixed, piece.x)
				wall.to = Vector2(piece.y, fixed) if horizontal else Vector2(fixed, piece.y)
				owned.append(wall)
				lines[key].append(piece)
		room.wall_segments = owned


static func theme_name_for(theme: int) -> String:
	match theme:
		2: return "ЛАБОРАТОРИЯ"
		3: return "ЖИЛОЙ КОРПУС"
		4: return "СЫРОЙ ТЕХЭТАЖ"
		_: return "ПОДВАЛ"



func _generate_placed_nodes() -> Array[EndlessNode]:
	for _attempt: int in 64:
		var nodes: Array[EndlessNode] = _generate_endless_nodes()
		_configure_room_visuals(nodes)
		_place_rooms(nodes)
		if not _has_overlapping_unlinked_rooms(nodes) and not _has_broken_linked_room_seams(nodes):
			return nodes

	var fallback: Array[EndlessNode] = _finalize_layout(_create_fallback_nodes())
	_configure_room_visuals(fallback)
	_place_rooms(fallback)
	assert(
		not _has_overlapping_unlinked_rooms(fallback),
		"Fallback endless layout contains overlapping unlinked rooms."
	)
	assert(
		not _has_broken_linked_room_seams(fallback),
		"Fallback endless layout contains disconnected room seams."
	)
	return fallback


# Match seeds identify floor one; generation adds one FLOOR_SEED_STEP.
static func run_seed_for_first_floor_seed(first_floor_seed: int) -> int:
	return _wrap_int32(first_floor_seed - FLOOR_SEED_STEP)


func _generate_endless_nodes() -> Array[EndlessNode]:
	for _attempt: int in 512:
		var nodes: Array[EndlessNode] = _try_generate_nodes()
		if nodes.is_empty() or not _has_expected_composition(nodes):
			continue
		return _finalize_layout(nodes)

	return _finalize_layout(_create_fallback_nodes())


func _try_generate_nodes() -> Array[EndlessNode]:
	var nodes: Array[EndlessNode] = []
	var occupied: Dictionary = {}

	var start: EndlessNode = EndlessNode.new()
	start.index = 0
	start.grid = Vector2i.ZERO
	start.main_path_order = 0
	start.role = EndlessNode.Role.START
	nodes.append(start)
	occupied[start.grid] = true

	var previous_direction: Vector2i = Vector2i.ZERO
	var straight_run: int = 0
	var turn_count: int = 0

	for order: int in range(1, MAIN_ROOM_COUNT):
		var previous: EndlessNode = nodes[nodes.size() - 1]
		var directions: Array[Vector2i] = _shuffled_grid_directions()
		var chosen_direction: Vector2i = Vector2i.ZERO
		var chosen_grid: Vector2i = Vector2i.ZERO
		var found: bool = false

		for direction: Vector2i in directions:
			if previous_direction != Vector2i.ZERO and direction == -previous_direction:
				continue
			var next_straight_run: int = straight_run + 1 if direction == previous_direction else 1
			if next_straight_run > 2:
				continue

			var candidate: Vector2i = previous.grid + direction
			if not _can_occupy_grid(candidate, previous.grid, occupied):
				continue
			if order == MAIN_ROOM_COUNT - 1 and absi(candidate.x) + absi(candidate.y) < 3:
				continue

			chosen_direction = direction
			chosen_grid = candidate
			found = true
			break

		if not found:
			return []

		if previous_direction != Vector2i.ZERO and chosen_direction != previous_direction:
			turn_count += 1
		straight_run = straight_run + 1 if chosen_direction == previous_direction else 1
		previous_direction = chosen_direction

		var node: EndlessNode = EndlessNode.new()
		node.index = order
		node.grid = chosen_grid
		node.main_path_order = order
		node.boss = order == MAIN_ROOM_COUNT - 1
		node.role = _main_role_for_order(order)
		nodes.append(node)
		occupied[chosen_grid] = true
		_link(previous, node)

	if turn_count < 2:
		return []

	var first_hub: EndlessNode = _find_main_path_node(nodes, 2)
	var second_hub: EndlessNode = _find_main_path_node(nodes, 4)

	if _try_add_optional_node(nodes, first_hub, occupied, EndlessNode.Role.OPTIONAL_ARENA) == null:
		return []
	if _try_add_optional_node(nodes, first_hub, occupied, EndlessNode.Role.OPTIONAL_ARENA) == null:
		return []

	if not _try_add_optional_chain(nodes, second_hub, occupied):
		return []
	if _try_add_optional_node(nodes, second_hub, occupied, EndlessNode.Role.OPTIONAL_ARENA) == null:
		return []

	return nodes


static func _main_role_for_order(order: int) -> EndlessNode.Role:
	match order:
		1: return EndlessNode.Role.HALL
		2: return EndlessNode.Role.HUB
		3: return EndlessNode.Role.CONNECTOR
		4: return EndlessNode.Role.RING_HUB
		5: return EndlessNode.Role.FUNNEL
		_: return EndlessNode.Role.BOSS


func _try_add_optional_chain(
	nodes: Array[EndlessNode], parent: EndlessNode, occupied: Dictionary
) -> bool:
	var directions: Array[Vector2i] = _shuffled_grid_directions()
	for direction: Vector2i in directions:
		var first_grid: Vector2i = parent.grid + direction
		var second_grid: Vector2i = first_grid + direction
		if not _can_occupy_grid(first_grid, parent.grid, occupied):
			continue
		occupied[first_grid] = true
		var second_fits: bool = _can_occupy_grid(second_grid, first_grid, occupied)
		occupied.erase(first_grid)
		if not second_fits:
			continue

		var connector: EndlessNode = _create_optional_node(
			nodes, parent, first_grid, EndlessNode.Role.OPTIONAL_CONNECTOR
		)
		occupied[first_grid] = true
		var arena: EndlessNode = _create_optional_node(
			nodes, connector, second_grid, EndlessNode.Role.OPTIONAL_ARENA
		)
		occupied[second_grid] = true
		return arena != null
	return false


func _try_add_optional_node(
	nodes: Array[EndlessNode], parent: EndlessNode, occupied: Dictionary, role: EndlessNode.Role
) -> EndlessNode:
	var directions: Array[Vector2i] = _shuffled_grid_directions()
	for direction: Vector2i in directions:
		var grid: Vector2i = parent.grid + direction
		if not _can_occupy_grid(grid, parent.grid, occupied):
			continue
		var node: EndlessNode = _create_optional_node(nodes, parent, grid, role)
		occupied[grid] = true
		return node
	return null


static func _create_optional_node(
	nodes: Array[EndlessNode], parent: EndlessNode, grid: Vector2i, role: EndlessNode.Role
) -> EndlessNode:
	var node: EndlessNode = EndlessNode.new()
	node.index = nodes.size()
	node.grid = grid
	node.optional = true
	node.role = role
	nodes.append(node)
	_link(parent, node)
	return node


func _shuffled_grid_directions() -> Array[Vector2i]:
	var directions: Array[Vector2i] = [GRID_EAST, GRID_NORTH, GRID_WEST, GRID_SOUTH]
	for i: int in range(directions.size() - 1, 0, -1):
		var swap_index: int = _endless_random.next_int(0, i + 1)
		var temporary: Vector2i = directions[i]
		directions[i] = directions[swap_index]
		directions[swap_index] = temporary
	return directions


static func _can_occupy_grid(candidate: Vector2i, parent: Vector2i, occupied: Dictionary) -> bool:
	if occupied.has(candidate):
		return false
	for other: Vector2i in occupied.keys():
		if other == parent:
			continue
		var distance: int = absi(candidate.x - other.x) + absi(candidate.y - other.y)
		if distance <= 1:
			return false
	return true


static func _link(a: EndlessNode, b: EndlessNode) -> void:
	if a == null or b == null:
		return
	a.links.append(b.index)
	b.links.append(a.index)


static func _has_expected_composition(nodes: Array[EndlessNode]) -> bool:
	if nodes.size() != MAIN_ROOM_COUNT + OPTIONAL_ROOM_COUNT:
		return false

	var main_count: int = 0
	var optional_count: int = 0
	var boss_count: int = 0
	for node: EndlessNode in nodes:
		if node.main_path_order >= 0:
			main_count += 1
		if node.optional:
			optional_count += 1
		if node.boss:
			boss_count += 1
		if (node.role == EndlessNode.Role.HUB or node.role == EndlessNode.Role.RING_HUB) \
				and _count_exits(_exit_mask(node, nodes)) != 4:
			return false
	return main_count == MAIN_ROOM_COUNT and optional_count == OPTIONAL_ROOM_COUNT and boss_count == 1


func _finalize_layout(nodes: Array[EndlessNode]) -> Array[EndlessNode]:
	var rotation: int = _endless_random.next_int(0, 4)
	var mirror: bool = _endless_random.next_int(0, 2) == 1
	for node: EndlessNode in nodes:
		var transformed: Vector2i = node.grid
		if mirror:
			transformed.y = -transformed.y
		for _turn: int in rotation:
			transformed = Vector2i(-transformed.y, transformed.x)
		node.grid = transformed

	var final_index: int = -1
	for i: int in nodes.size():
		if nodes[i].boss:
			final_index = i
			break
	if final_index >= 0:
		var final_node: EndlessNode = nodes[final_index]
		nodes.remove_at(final_index)
		nodes.append(final_node)
	return nodes


func _create_fallback_nodes() -> Array[EndlessNode]:
	var main_grid: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, -1),
		Vector2i(2, -2), Vector2i(3, -2), Vector2i(4, -2),
	]
	var nodes: Array[EndlessNode] = []
	for order: int in main_grid.size():
		var node: EndlessNode = EndlessNode.new()
		node.index = order
		node.grid = main_grid[order]
		node.main_path_order = order
		node.boss = order == MAIN_ROOM_COUNT - 1
		node.role = EndlessNode.Role.START if order == 0 else _main_role_for_order(order)
		nodes.append(node)
		if order > 0:
			_link(nodes[order - 1], node)

	var first_hub: EndlessNode = nodes[2]
	var second_hub: EndlessNode = nodes[4]
	_create_optional_node(nodes, first_hub, Vector2i(2, 1), EndlessNode.Role.OPTIONAL_ARENA)
	_create_optional_node(nodes, first_hub, Vector2i(3, 0), EndlessNode.Role.OPTIONAL_ARENA)
	var connector: EndlessNode = _create_optional_node(
		nodes, second_hub, Vector2i(1, -2), EndlessNode.Role.OPTIONAL_CONNECTOR
	)
	_create_optional_node(nodes, connector, Vector2i(0, -2), EndlessNode.Role.OPTIONAL_ARENA)
	_create_optional_node(nodes, second_hub, Vector2i(2, -3), EndlessNode.Role.OPTIONAL_ARENA)
	return nodes


static func _find_main_path_node(nodes: Array[EndlessNode], order: int) -> EndlessNode:
	for node: EndlessNode in nodes:
		if node.main_path_order == order:
			return node
	assert(false, "Endless main path is incomplete.")
	return null


static func _find_node_by_index(nodes: Array[EndlessNode], index: int) -> EndlessNode:
	for node: EndlessNode in nodes:
		if node.index == index:
			return node
	return null



static func _exit_mask(node: EndlessNode, nodes: Array[EndlessNode]) -> int:
	var mask: int = EndlessNode.EXIT_NONE
	for linked_index: int in node.links:
		var linked: EndlessNode = _find_node_by_index(nodes, linked_index)
		if linked == null:
			continue
		mask |= _connection_direction(node, linked)
	return mask


static func _count_exits(mask: int) -> int:
	var value: int = mask
	var count: int = 0
	while value != 0:
		count += value & 1
		value >>= 1
	return count


static func _are_opposite_exits(exits: int) -> bool:
	return exits == (EndlessNode.EXIT_EAST | EndlessNode.EXIT_WEST) \
		or exits == (EndlessNode.EXIT_NORTH | EndlessNode.EXIT_SOUTH)


static func _canonical_base_mask(exits: int) -> int:
	var degree: int = _count_exits(exits)
	if degree <= 1:
		return EndlessNode.EXIT_SOUTH
	if degree >= 4:
		return EndlessNode.EXIT_ALL
	if degree == 3:
		return EndlessNode.EXIT_NORTH | EndlessNode.EXIT_EAST | EndlessNode.EXIT_WEST
	return (EndlessNode.EXIT_EAST | EndlessNode.EXIT_WEST) if _are_opposite_exits(exits) \
		else (EndlessNode.EXIT_NORTH | EndlessNode.EXIT_EAST)


static func _rotate_mask_once(mask: int) -> int:
	var result: int = EndlessNode.EXIT_NONE
	if mask & EndlessNode.EXIT_NORTH: result |= EndlessNode.EXIT_WEST
	if mask & EndlessNode.EXIT_WEST: result |= EndlessNode.EXIT_SOUTH
	if mask & EndlessNode.EXIT_SOUTH: result |= EndlessNode.EXIT_EAST
	if mask & EndlessNode.EXIT_EAST: result |= EndlessNode.EXIT_NORTH
	return result


static func _rotate_mask(mask: int, quarter_turns: int) -> int:
	var rotated: int = mask
	for _turn: int in quarter_turns:
		rotated = _rotate_mask_once(rotated)
	return rotated


static func _find_mask_rotation(source: int, target: int) -> int:
	var rotated: int = source
	for turn: int in 4:
		if rotated == target:
			return turn
		rotated = _rotate_mask_once(rotated)
	return 0


static func _exit_mask_from_grid_delta(delta: Vector2i) -> int:
	if delta.x > 0: return EndlessNode.EXIT_EAST
	if delta.x < 0: return EndlessNode.EXIT_WEST
	if delta.y > 0: return EndlessNode.EXIT_NORTH
	return EndlessNode.EXIT_SOUTH


static func _opposite_exit(direction: int) -> int:
	if direction == EndlessNode.EXIT_NORTH: return EndlessNode.EXIT_SOUTH
	if direction == EndlessNode.EXIT_EAST: return EndlessNode.EXIT_WEST
	if direction == EndlessNode.EXIT_SOUTH: return EndlessNode.EXIT_NORTH
	return EndlessNode.EXIT_EAST


static func _exit_mask_to_vector(direction: int) -> Vector2:
	if direction == EndlessNode.EXIT_NORTH: return Vector2(0.0, 1.0)
	if direction == EndlessNode.EXIT_EAST: return Vector2(1.0, 0.0)
	if direction == EndlessNode.EXIT_SOUTH: return Vector2(0.0, -1.0)
	return Vector2(-1.0, 0.0)



func _configure_room_visuals(nodes: Array[EndlessNode]) -> void:
	for node: EndlessNode in nodes:
		var exits: int = _exit_mask(node, nodes)
		node.exits = exits
		var canonical_mask: int = _canonical_base_mask(exits)

		match node.role:
			EndlessNode.Role.START:
				_set_visual(node, "room_dead_end_s_01", 12.0, canonical_mask)
			EndlessNode.Role.HALL:
				_set_visual(node, "room_hall_ew_01", 7.0, canonical_mask)
			EndlessNode.Role.HUB:
				var hub_asset: String = "room_cross_nesw_01" \
					if _seed_variant(node, 2) == 0 else "room_junction_nesw_01"
				_set_visual(node, hub_asset, 16.5, EndlessNode.EXIT_ALL)
			EndlessNode.Role.CONNECTOR:
				var opposite: bool = _are_opposite_exits(exits)
				_set_visual(
					node, "room_square_new_01" if opposite else "room_corner_ne_01",
					12.0 if opposite else 15.0, canonical_mask
				)
			EndlessNode.Role.RING_HUB:
				_set_visual(node, "room_ring_nesw_01", 15.5, EndlessNode.EXIT_ALL)
			EndlessNode.Role.FUNNEL:
				_set_visual(node, "room_funnel_ew_01", 8.0, canonical_mask)
			EndlessNode.Role.BOSS:
				_set_visual(node, "room_boss_new_01", 21.0, canonical_mask)
			EndlessNode.Role.OPTIONAL_CONNECTOR:
				_set_visual(node, "room_corner_ne_01", 15.0, canonical_mask)
			_:
				const ARENAS: Array[String] = [
					"room_square_ew_01", "room_square_new_01",
					"room_square_nesw_01", "room_square_ns_01",
				]
				_set_visual(
					node, ARENAS[_seed_variant(node, ARENAS.size())], 12.0, canonical_mask
				)

		node.quarter_turns = _find_mask_rotation(node.base_mask, exits)
		var pixels: Vector2i = CANVAS_PIXELS.get(node.asset_name, Vector2i(1, 1)) as Vector2i
		var scale: float = node.world_height / maxf(0.01, float(pixels.y))
		var unrotated_size: Vector2 = Vector2(float(pixels.x) * scale, float(pixels.y) * scale)
		node.size = unrotated_size if node.quarter_turns % 2 == 0 \
			else Vector2(unrotated_size.y, unrotated_size.x)


# Preserve uint32 overflow for reproducible variants.
func _seed_variant(node: EndlessNode, count: int) -> int:
	var hash_value: int = _wrap_uint32(_endless_seed)
	hash_value = hash_value ^ _wrap_uint32(node.index * 2654435761)
	hash_value = hash_value ^ (hash_value >> 16)
	return hash_value % maxi(1, count)


static func _set_visual(node: EndlessNode, asset_name: String, world_height: float, base_mask: int) -> void:
	node.asset_name = asset_name
	node.world_height = world_height
	node.base_mask = base_mask
	node.north_anchor = Vector2(0.0, 0.5)
	node.east_anchor = Vector2(0.5, 0.0)
	node.south_anchor = Vector2(0.0, -0.5)
	node.west_anchor = Vector2(-0.5, 0.0)

	# The L contour has off-centre door anchors.
	if asset_name == "room_corner_ne_01":
		node.north_anchor = Vector2(-0.285, 0.5)
		node.east_anchor = Vector2(0.5, -0.30)
	elif asset_name == "room_junction_nesw_01":
		node.east_anchor = Vector2(0.5, -0.27)
		node.west_anchor = Vector2(-0.5, -0.27)



func _place_rooms(nodes: Array[EndlessNode]) -> void:
	var start: EndlessNode = _find_main_path_node(nodes, 0)
	start.center = Vector2.ZERO

	var main_path_count: int = 0
	for node: EndlessNode in nodes:
		if node.main_path_order >= 0:
			main_path_count += 1

	for order: int in range(1, main_path_count):
		var previous: EndlessNode = _find_main_path_node(nodes, order - 1)
		var current: EndlessNode = _find_main_path_node(nodes, order)
		_place_adjacent(previous, current)

	for node: EndlessNode in nodes:
		if not node.optional or node.links.is_empty():
			continue
		var parent: EndlessNode = _find_node_by_index(nodes, node.links[0])
		_place_adjacent(parent, node)


static func _place_adjacent(placed: EndlessNode, target: EndlessNode) -> void:
	var grid_delta: Vector2i = target.grid - placed.grid
	var direction: int = _exit_mask_from_grid_delta(grid_delta)
	var opposite: int = _opposite_exit(direction)
	var placed_offset: Vector2 = _door_anchor_offset(placed, direction)
	var target_offset: Vector2 = _door_anchor_offset(target, opposite)
	var overlap: Vector2 = _exit_mask_to_vector(direction) * 0.02
	target.center = placed.center + placed_offset - target_offset - overlap


static func _has_overlapping_unlinked_rooms(nodes: Array[EndlessNode]) -> bool:
	const TOLERANCE: float = 0.35
	if not nodes.is_empty() and not nodes[0].building_cells.is_empty():
		var occupied: Dictionary = {}
		for node: EndlessNode in nodes:
			for cell: Vector2i in node.building_cells:
				if occupied.has(cell):
					return true
				occupied[cell] = true
		return false
	for i: int in nodes.size():
		var first_size: Vector2 = _max_vector(
			nodes[i].size - Vector2.ONE * TOLERANCE * 2.0, Vector2.ONE
		)
		var first: Rect2 = Rect2(nodes[i].center - first_size * 0.5, first_size)
		for j: int in range(i + 1, nodes.size()):
			if nodes[i].links.has(nodes[j].index):
				continue
			var second_size: Vector2 = _max_vector(
				nodes[j].size - Vector2.ONE * TOLERANCE * 2.0, Vector2.ONE
			)
			var second: Rect2 = Rect2(nodes[j].center - second_size * 0.5, second_size)
			if first.intersects(second):
				return true
	return false


# Linked anchors overlap by .02 units; larger separation means a broken seam.
static func _has_broken_linked_room_seams(nodes: Array[EndlessNode]) -> bool:
	for node: EndlessNode in nodes:
		for linked_index: int in node.links:
			if linked_index <= node.index:
				continue
			var linked: EndlessNode = _find_node_by_index(nodes, linked_index)
			if linked == null:
				return true
			var direction: int = _connection_direction(node, linked)
			var first_anchor: Vector2 = node.link_positions.get(linked_index, door_anchor_position(node, direction))
			var second_anchor: Vector2 = linked.link_positions.get(node.index, door_anchor_position(linked, _opposite_exit(direction)))
			if first_anchor.distance_to(second_anchor) > LINK_SEAM_TOLERANCE:
				return true
	return false


static func _max_vector(a: Vector2, b: Vector2) -> Vector2:
	return Vector2(maxf(a.x, b.x), maxf(a.y, b.y))



static func _door_anchor_offset(node: EndlessNode, world_direction: int) -> Vector2:
	var base_direction: int = _rotate_mask(world_direction, (4 - node.quarter_turns) % 4)
	var normalized_anchor: Vector2 = node.anchor_for(base_direction)
	var unrotated_size: Vector2 = node.size if node.quarter_turns % 2 == 0 \
		else Vector2(node.size.y, node.size.x)
	var local: Vector2 = Vector2(
		normalized_anchor.x * unrotated_size.x, normalized_anchor.y * unrotated_size.y
	)
	return _rotate_local(local, node.quarter_turns)


static func door_anchor_position(node: EndlessNode, direction: int) -> Vector2:
	for peer: int in node.link_positions:
		if int(node.link_directions.get(peer, 0)) == direction:
			return node.link_positions[peer]
	return node.center + _door_anchor_offset(node, direction)


static func connection_anchor_position(node: EndlessNode, neighbour_index: int) -> Vector2:
	if node.link_positions.has(neighbour_index):
		return node.link_positions[neighbour_index]
	return door_anchor_position(node, int(node.link_directions.get(neighbour_index, EndlessNode.EXIT_NORTH)))


static func _rotate_local(point: Vector2, quarter_turns: int) -> Vector2:
	var result: Vector2 = point
	for _turn: int in quarter_turns:
		result = Vector2(-result.y, result.x)
	return result



# Fixed-width overflow keeps prop-scatter seeds consistent between callers.
static func trash_seed_for(floor_seed: int, node_index: int) -> int:
	return _wrap_int32(floor_seed * 486187739 + node_index * 977)


static func _wrap_int32(value: int) -> int:
	var wrapped: int = value & 0xFFFFFFFF
	if wrapped >= 0x80000000:
		wrapped -= 0x100000000
	return wrapped


static func _wrap_uint32(value: int) -> int:
	return value & 0xFFFFFFFF



static func _to_godot_point(point: Vector2) -> Vector2:
	return Vector2(point.x, -point.y)


# Convert a bottom-left-origin rectangle, including its height in the Y flip.
static func _godot_rect_from_unity_minmax(minimum: Vector2, maximum: Vector2) -> Rect2:
	return Rect2(minimum.x, -maximum.y, maximum.x - minimum.x, maximum.y - minimum.y)


static func _godot_room_bounds(center: Vector2, size: Vector2) -> Rect2:
	# Preserve dimensions directly to avoid cancellation changing shaft width.
	return Rect2(_to_godot_point(center) - size * 0.5, size)


# Structural contours define physics; decorative texture alpha does not.
static func _contour_for_asset(asset_name: String, unrotated_size: Vector2) -> PackedVector2Array:
	match asset_name:
		"room_corner_ne_01":
			return PackedVector2Array([
				_local(unrotated_size, -1.0, -1.0), _local(unrotated_size, 1.0, -1.0),
				_local(unrotated_size, 1.0, -0.207), _local(unrotated_size, -0.155, -0.207),
				_local(unrotated_size, -0.155, 1.0), _local(unrotated_size, -1.0, 1.0),
			])
		"room_cross_nesw_01":
			return PackedVector2Array([
				_local(unrotated_size, -0.376, 1.0), _local(unrotated_size, 0.376, 1.0),
				_local(unrotated_size, 0.376, 0.43), _local(unrotated_size, 1.0, 0.43),
				_local(unrotated_size, 1.0, -0.43), _local(unrotated_size, 0.376, -0.43),
				_local(unrotated_size, 0.376, -1.0), _local(unrotated_size, -0.376, -1.0),
				_local(unrotated_size, -0.376, -0.43), _local(unrotated_size, -1.0, -0.43),
				_local(unrotated_size, -1.0, 0.43), _local(unrotated_size, -0.376, 0.43),
			])
		"room_junction_nesw_01":
			return PackedVector2Array([
				_local(unrotated_size, -1.0, 0.031), _local(unrotated_size, -0.59, 0.031),
				_local(unrotated_size, -0.59, 1.0), _local(unrotated_size, 0.59, 1.0),
				_local(unrotated_size, 0.59, 0.031), _local(unrotated_size, 1.0, 0.031),
				_local(unrotated_size, 1.0, -1.0), _local(unrotated_size, -1.0, -1.0),
			])
		"room_funnel_ew_01":
			return PackedVector2Array([
				_local(unrotated_size, -1.0, -0.984),
				_local(unrotated_size, 1.0, -0.279),
				_local(unrotated_size, 1.0, 0.291),
				_local(unrotated_size, -1.0, 0.969),
			])
		_:
			return PackedVector2Array([
				_local(unrotated_size, -1.0, -1.0), _local(unrotated_size, 1.0, -1.0),
				_local(unrotated_size, 1.0, 1.0), _local(unrotated_size, -1.0, 1.0),
			])


static func _local(size: Vector2, normalized_x: float, normalized_y: float) -> Vector2:
	return Vector2(normalized_x * size.x * 0.5, normalized_y * size.y * 0.5)


static func unrotated_size(node: EndlessNode) -> Vector2:
	return node.size if node.quarter_turns % 2 == 0 else Vector2(node.size.y, node.size.x)


static func is_trash_floor_point(asset_name: String, point: Vector2) -> bool:
	match asset_name:
		"room_corner_ne_01":
			return point.x <= -0.155 or point.y <= -0.207
		"room_cross_nesw_01":
			return absf(point.x) <= 0.376 or absf(point.y) <= 0.43
		"room_junction_nesw_01":
			return point.y <= 0.031 or absf(point.x) <= 0.59
		"room_ring_nesw_01":
			# Inset for wall thickness so the southern ring lane keeps its intended width.
			return not (
				absf(point.x) <= 0.41 and point.y >= -0.29 and point.y <= 0.33
			)
		"room_funnel_ew_01":
			# The walkable trapezoid has two vertical door-bearing ends despite its artwork.
			return point.y >= -0.633 + 0.359 * point.x \
				and point.y <= 0.630 - 0.344 * point.x
		_:
			return true


static func normalized_world_point(node: EndlessNode, normalized: Vector2) -> Vector2:
	var unrotated_size: Vector2 = node.size if node.quarter_turns % 2 == 0 \
		else Vector2(node.size.y, node.size.x)
	return node.center + _rotate_local(_local(unrotated_size, normalized.x, normalized.y), node.quarter_turns)


# Test the floor union so open seams between adjacent rooms remain traversable.
static func is_walkable_godot_point(nodes: Array[EndlessNode], point: Vector2) -> bool:
	var unity_point: Vector2 = Vector2(point.x, -point.y)
	for node: EndlessNode in nodes:
		if not node.floor_areas_unity.is_empty():
			for area: Rect2 in node.floor_areas_unity:
				if area.grow(0.0001).has_point(unity_point):
					return true
			continue
		var local: Vector2 = unity_point - node.center
		local = _rotate_local(local, (4 - node.quarter_turns) % 4)
		var size: Vector2 = unrotated_size(node)
		var normalized: Vector2 = Vector2(
			local.x / maxf(0.001, size.x * 0.5),
			local.y / maxf(0.001, size.y * 0.5)
		)
		# Adjacent fractional contours can disagree by a few ULPs at a shared seam.
		if absf(normalized.x) <= 1.00001 and absf(normalized.y) <= 1.00001 \
				and is_trash_floor_point(node.asset_name, normalized):
			return true
	return false


static func is_walkable_godot_circle(
	nodes: Array[EndlessNode], centre: Vector2, radius: float
) -> bool:
	if not is_walkable_godot_point(nodes, centre):
		return false
	var bounded_radius: float = maxf(0.0, radius)
	for index: int in 12:
		var angle: float = TAU * float(index) / 12.0
		if not is_walkable_godot_point(
			nodes, centre + Vector2.from_angle(angle) * bounded_radius
		):
			return false
	return true


## Exact floor decomposition; bounding boxes include non-walkable concave corners.
static func node_floor_areas(node: EndlessNode) -> Array[Rect2]:
	if not node.floor_areas_unity.is_empty():
		var dense_areas: Array[Rect2] = []
		for area: Rect2 in node.floor_areas_unity:
			dense_areas.append(_godot_rect_from_unity_minmax(area.position, area.end))
		return dense_areas
	var local_areas: Array[Rect2] = [Rect2(-1, -1, 2, 2)]
	match node.asset_name:
		"room_corner_ne_01":
			local_areas = [Rect2(-1, -1, 2, 0.793), Rect2(-1, -0.207, 0.845, 1.207)]
		"room_junction_nesw_01":
			local_areas = [Rect2(-1, -1, 2, 1.031), Rect2(-0.59, 0.031, 1.18, 0.969)]
		"room_cross_nesw_01":
			local_areas = [Rect2(-1, -0.43, 2, 0.86), Rect2(-0.376, -1, 0.752, 0.57), Rect2(-0.376, 0.43, 0.752, 0.57)]
	var result: Array[Rect2] = []
	for local_area: Rect2 in local_areas:
		var first: Vector2 = _to_godot_point(normalized_world_point(node, local_area.position))
		var opposite: Vector2 = _to_godot_point(normalized_world_point(node, local_area.end))
		var minimum: Vector2 = _min_vector(first, opposite)
		result.append(Rect2(minimum, _max_vector(first, opposite) - minimum))
	return result


static func furniture_areas(node: EndlessNode) -> Array:
	var result: Array = []
	if node.role not in [EndlessNode.Role.OPTIONAL_ARENA, EndlessNode.Role.BOSS]:
		return result
	if not node.floor_areas_unity.is_empty():
		for area: Rect2 in node_floor_areas(node):
			var inner: Rect2 = area.grow(-2.4)
			if inner.has_area():
				result.append(inner)
		return result
	# Corner bays leave the cross between doorways clear.
	var bounds: Rect2 = _godot_room_bounds(node.center, node.size).grow(-1.0)
	var half: Vector2 = bounds.size * 0.5 - Vector2(2.2, 2.2)
	if half.x < 1.0 or half.y < 1.0:
		return result
	for origin: Vector2 in [bounds.position, Vector2(bounds.end.x - half.x, bounds.position.y),
		Vector2(bounds.position.x, bounds.end.y - half.y), bounds.end - half]:
		result.append(Rect2(origin, half))
	return result


static func safe_interior_godot_point(node: EndlessNode) -> Vector2:
	if not node.floor_areas_unity.is_empty():
		return _to_godot_point(node.floor_areas_unity[0].get_center())
	var normalized: Vector2 = Vector2.ZERO
	if node.asset_name == "room_ring_nesw_01":
		normalized = Vector2(0.0, -0.66)
	elif node.asset_name == "room_corner_ne_01":
		normalized = Vector2(-0.42, -0.42)
	return _to_godot_point(normalized_world_point(node, normalized))


# Segments are already door-cut; consumers must not cut them again.
func _room_wall_segments(node: EndlessNode, door_mask: int) -> Array[WallSegmentDef]:
	var segments: Array[WallSegmentDef] = []
	var unrotated_size: Vector2 = node.size if node.quarter_turns % 2 == 0 \
		else Vector2(node.size.y, node.size.x)
	var contour: PackedVector2Array = _contour_for_asset(node.asset_name, unrotated_size)

	var signed_area: float = 0.0
	for i: int in contour.size():
		var current: Vector2 = contour[i]
		var next_point: Vector2 = contour[(i + 1) % contour.size()]
		signed_area += current.x * next_point.y - next_point.x * current.y
	var inward_sign: float = 1.0 if signed_area >= 0.0 else -1.0

	for i: int in contour.size():
		var from_local: Vector2 = contour[i]
		var to_local: Vector2 = contour[(i + 1) % contour.size()]
		var edge: Vector2 = to_local - from_local
		if edge.length_squared() > 0.0001:
			var inward_normal: Vector2 = Vector2(-edge.y, edge.x).normalized() * inward_sign
			from_local += inward_normal * WALL_VISUAL_INSET
			to_local += inward_normal * WALL_VISUAL_INSET
		var from_world: Vector2 = node.center + _rotate_local(from_local, node.quarter_turns)
		var to_world: Vector2 = node.center + _rotate_local(to_local, node.quarter_turns)
		_append_cut_segments(segments, from_world, to_world, node, door_mask)

	if node.asset_name == "room_ring_nesw_01":
		_append_ring_interior_walls(segments, node)

	return segments


static func _append_ring_interior_walls(segments: Array[WallSegmentDef], node: EndlessNode) -> void:
	# The southern edge is inset for the wall collider thickness.
	var half_width: float = node.size.x * 0.205
	var top_extent: float = node.size.y * 0.165
	var bottom_extent: float = node.size.y * 0.145
	var bottom_left: Vector2 = node.center + _rotate_local(
		Vector2(-half_width, -bottom_extent), node.quarter_turns
	)
	var bottom_right: Vector2 = node.center + _rotate_local(
		Vector2(half_width, -bottom_extent), node.quarter_turns
	)
	var top_right: Vector2 = node.center + _rotate_local(
		Vector2(half_width, top_extent), node.quarter_turns
	)
	var top_left: Vector2 = node.center + _rotate_local(
		Vector2(-half_width, top_extent), node.quarter_turns
	)
	_add_segment(segments, bottom_left, bottom_right)
	_add_segment(segments, bottom_right, top_right)
	_add_segment(segments, top_right, top_left)
	_add_segment(segments, top_left, bottom_left)


func _append_cut_segments(
	segments: Array[WallSegmentDef], from: Vector2, to: Vector2, node: EndlessNode, door_mask: int
) -> void:
	var delta: Vector2 = to - from
	var length: float = delta.length()
	if length < 0.08:
		return

	var cuts: Array[Vector2] = []
	var anchors: Array[Vector2] = []
	var widths: Dictionary = {}
	if not node.floor_outline_unity.is_empty():
		for peer: int in node.link_positions:
			var anchor: Vector2 = node.link_positions[peer]
			anchors.append(anchor)
			widths[anchor] = node.link_widths.get(peer, DOOR_CUT_WIDTH * 1.12)
	else:
		for direction: int in [
		EndlessNode.EXIT_NORTH, EndlessNode.EXIT_EAST, EndlessNode.EXIT_SOUTH, EndlessNode.EXIT_WEST
		]:
			if (door_mask & direction) != 0:
				anchors.append(door_anchor_position(node, direction))
	for anchor: Vector2 in anchors:
		var parameter: float = clampf(
			delta.dot(anchor - from) / maxf(0.0001, length * length), 0.0, 1.0
		)
		var closest: Vector2 = from + delta * parameter
		if anchor.distance_to(closest) > (0.01 if not node.floor_outline_unity.is_empty() else DOOR_CUT_WIDTH * 0.72):
			continue
		var half_cut: float = float(widths.get(anchor, DOOR_CUT_WIDTH * 1.12)) * 0.5 / length
		cuts.append(Vector2(parameter - half_cut, parameter + half_cut))

	cuts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)

	var cursor: float = 0.0
	for cut: Vector2 in cuts:
		var cut_start: float = clampf(cut.x, 0.0, 1.0)
		var cut_end: float = clampf(cut.y, 0.0, 1.0)
		if cut_start > cursor + 0.005:
			_add_segment(segments, from + delta * cursor, from + delta * cut_start)
		cursor = maxf(cursor, cut_end)
	if cursor < 0.995:
		_add_segment(segments, from + delta * cursor, to)


static func _add_segment(segments: Array[WallSegmentDef], from: Vector2, to: Vector2) -> void:
	var segment: WallSegmentDef = WallSegmentDef.new()
	segment.from = _to_godot_point(from)
	segment.to = _to_godot_point(to)
	segments.append(segment)



func _chest_position(node: EndlessNode, exits: int) -> Vector2:
	if not node.floor_areas_unity.is_empty():
		return node.floor_areas_unity[0].get_center()
	# A concave room can place the generic exit midpoint inside a wall.
	if node.asset_name == "room_corner_ne_01":
		return normalized_world_point(node, Vector2(0.0, -0.66))

	if _are_opposite_exits(exits):
		var first_direction: int = EndlessNode.EXIT_EAST \
			if (exits & EndlessNode.EXIT_EAST) != 0 else EndlessNode.EXIT_NORTH
		var second_direction: int = _opposite_exit(first_direction)
		return (door_anchor_position(node, first_direction) \
			+ door_anchor_position(node, second_direction)) * 0.5

	var normalized_position: Vector2 = Vector2.ZERO
	if node.asset_name == "room_ring_nesw_01":
		normalized_position = Vector2(-0.56, -0.56)
	return normalized_world_point(node, normalized_position)



static func _fog_count_for_role(role: EndlessNode.Role) -> int:
	match role:
		EndlessNode.Role.HALL, EndlessNode.Role.FUNNEL:
			return 2
		EndlessNode.Role.HUB, EndlessNode.Role.CONNECTOR, EndlessNode.Role.OPTIONAL_ARENA:
			return 3
		EndlessNode.Role.RING_HUB, EndlessNode.Role.BOSS:
			return 4
		EndlessNode.Role.OPTIONAL_CONNECTOR:
			return 3
		_:
			return 0


static func _trash_count_for_role(role: EndlessNode.Role) -> int:
	match role:
		EndlessNode.Role.HALL: return 7
		EndlessNode.Role.FUNNEL: return 8
		EndlessNode.Role.CONNECTOR, EndlessNode.Role.OPTIONAL_CONNECTOR: return 15
		EndlessNode.Role.HUB, EndlessNode.Role.RING_HUB: return 18
		EndlessNode.Role.BOSS: return 24
		_: return 12


static func _fog_markers(node: EndlessNode) -> Array[Vector2]:
	if not node.floor_areas_unity.is_empty():
		var markers: Array[Vector2] = []
		for area: Rect2 in node.floor_areas_unity:
			for fraction: Vector2 in [Vector2(.3, .3), Vector2(.7, .3), Vector2(.3, .7), Vector2(.7, .7)]:
				markers.append(area.position + area.size * fraction)
		return markers
	var normalized: Array[Vector2] = []
	match node.asset_name:
		"room_ring_nesw_01":
			normalized = [
				Vector2(0.0, 0.62), Vector2(0.62, 0.0), Vector2(0.0, -0.62), Vector2(-0.62, 0.0),
			]
		"room_funnel_ew_01":
			normalized = [
				Vector2(-0.46, -0.03), Vector2(0.38, -0.03),
				Vector2(-0.30, 0.28), Vector2(0.18, 0.20),
			]
		"room_corner_ne_01":
			normalized = [Vector2(-0.48, 0.48), Vector2(-0.38, -0.38), Vector2(0.38, -0.38)]
		"room_junction_nesw_01":
			normalized = [Vector2(-0.55, -0.48), Vector2(0.55, -0.48), Vector2(0, 0.55), Vector2(0, -0.2)]
		"room_cross_nesw_01":
			normalized = [
				Vector2(0.0, 0.55), Vector2(0.55, 0.0), Vector2(0.0, -0.55), Vector2(-0.55, 0.0),
				Vector2(0.0, 0.0),
			]
		"room_hall_ew_01":
			normalized = [
				Vector2(-0.52, 0.18), Vector2(0.52, -0.18),
				Vector2(-0.20, -0.22), Vector2(0.20, 0.22),
			]
		_:
			normalized = [
				Vector2(-0.50, 0.50), Vector2(0.50, 0.50), Vector2(-0.50, -0.50), Vector2(0.50, -0.50),
				Vector2(0.0, 0.58), Vector2(0.58, 0.0), Vector2(0.0, -0.58), Vector2(-0.58, 0.0),
			]

	var world: Array[Vector2] = []
	for point: Vector2 in normalized:
		world.append(normalized_world_point(node, point))
	return world


# Encounter groups use final sequential room indices, not creation-order IDs.
func _spawn_fogs(
	node: EndlessNode, room_index: int, count: int, chest_position: Vector2, has_chest: bool
) -> Array[FogPlacementDef]:
	var markers: Array[Vector2] = _fog_markers(node)
	var occupied: Array[bool] = []
	occupied.resize(markers.size())
	occupied.fill(false)
	var marker_offset: int = _seed_variant(node, maxi(1, markers.size()))
	var scattered: Array[Vector2] = _scatter_fog_points(node,count,chest_position,has_chest) if not node.floor_areas_unity.is_empty() else []

	var placements: Array[FogPlacementDef] = []
	for i: int in count:
		if i < scattered.size():
			var placement: FogPlacementDef = _fog_placement(scattered[i],room_index,i)
			placements.append(placement)
			continue
		var position: Vector2 = markers[(marker_offset + i) % markers.size()]
		var found: bool = false
		for attempt: int in markers.size():
			var marker_index: int = (marker_offset + i + attempt) % markers.size()
			var candidate: Vector2 = markers[marker_index]
			if not occupied[marker_index] \
					and (not has_chest or candidate.distance_to(chest_position) >= 1.8):
				position = candidate
				occupied[marker_index] = true
				found = true
				break
		if not found:
			# Reuse a known floor marker rather than a potentially non-walkable bounds centre.
			position = markers[(marker_offset + i) % markers.size()]

		placements.append(_fog_placement(position,room_index,i))
	return placements


func _fog_placement(point: Vector2, room_index: int, ordinal: int) -> FogPlacementDef:
	var placement: FogPlacementDef = FogPlacementDef.new()
	placement.position = _to_godot_point(point)
	placement.strength_tier = 1
	placement.group_id = 1000 + room_index * 10 + ordinal / 2
	placement.patrol_radius = 0.45
	placement.aggro_radius = 2.35
	placement.is_ranged = fog_is_ranged(_endless_seed,room_index,ordinal)
	return placement


# Sample by actual floor area to spread markers across merged room arms.
func _scatter_fog_points(node: EndlessNode, count: int, chest: Vector2, has_chest: bool) -> Array[Vector2]:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = _endless_seed ^ str(node.center,node.size,node.floor_outline_unity).hash()
	var total_area: float = 0.0
	for area: Rect2 in node.floor_areas_unity: total_area += area.get_area()
	var result: Array[Vector2] = []
	var clearance: float = _scheme.fog_spawn_clearance
	for ordinal: int in count:
		var best: Vector2 = Vector2.INF
		var score: float = -INF
		for attempt: int in _scheme.fog_spawn_attempts:
			var draw: float = random.randf()*total_area
			var area: Rect2 = node.floor_areas_unity[-1]
			for candidate_area: Rect2 in node.floor_areas_unity:
				draw -= candidate_area.get_area()
				if draw <= 0.0:
					area = candidate_area; break
			var point: Vector2 = area.position+area.size*Vector2(random.randf(),random.randf())
			if not is_walkable_godot_circle([node],_to_godot_point(point),clearance): continue
			if has_chest and point.distance_to(chest) < _scheme.fog_spawn_door_clearance: continue
			var blocked: bool = false
			for port: Vector2 in node.link_positions.values():
				if point.distance_to(port) < _scheme.fog_spawn_door_clearance: blocked = true; break
			if blocked: continue
			var separation: float = INF
			for previous: Vector2 in result: separation = minf(separation,point.distance_to(previous))
			if separation < _scheme.fog_spawn_separation: continue
			if result.is_empty(): best = point; break
			if separation > score: best = point; score = separation
		if best == Vector2.INF: break
		result.append(best)
	return result


# Classify encounter markers without consuming the layout RNG.
static func fog_is_ranged(floor_seed: int, room_index: int, placement_index: int) -> bool:
	var mixed: int = absi(
		floor_seed * 2246822519 + (room_index + 31) * 3266489917 + placement_index * 668265263
	)
	return mixed % 4 == 0



func _build_floor_data(nodes: Array[EndlessNode], floor_index: int) -> EndlessFloorData:
	var level: LevelDef = LevelDef.new()
	var theme: int = _active_theme
	var boss_stop: bool = maxi(1, floor_index) % 5 == 0
	level.level_id = 1000 + maxi(1, floor_index)
	level.display_name = "ЭТАЖ %d · %s" % [floor_index, theme_name_for(theme)]
	level.backdrop_asset = "level2_subterranean_backdrop" if theme == 2 \
		else ("level3_tower_backdrop_variant_a" if theme == 3 else "level1_subterranean_backdrop")
	level.backdrop_tint = Color(0.35, 0.38, 0.40, 1.0)
	level.lighting_style = "laboratory" if theme == 2 else ("none" if theme == 3 else "basement")
	level.backdrop_z = BACKDROP_Z
	level.room_shell_z_base = -20000

	var minimum: Vector2 = nodes[0].center - nodes[0].size * 0.5
	var maximum: Vector2 = nodes[0].center + nodes[0].size * 0.5
	for node: EndlessNode in _potential_nodes:
		minimum = _min_vector(minimum, node.center - node.size * 0.5)
		maximum = _max_vector(maximum, node.center + node.size * 0.5)
	minimum -= Vector2.ONE * FLOOR_PADDING
	maximum += Vector2.ONE * FLOOR_PADDING
	level.backdrop_bounds = _godot_rect_from_unity_minmax(minimum, maximum)

	var position_by_node_index: Dictionary = {}
	for i: int in nodes.size():
		position_by_node_index[nodes[i].index] = i

	var rooms: Array[RoomDef] = []
	var chest_positions_unity: Array[Vector2] = []
	for i: int in nodes.size():
		var node: EndlessNode = nodes[i]
		var exits: int = node.exits
		var has_chest: bool = node.index != 0 and _scheme.endless_chests_enabled
		var chest_unity: Vector2 = _chest_position(node, exits)
		var name: String = "ТОЧКА ВХОДА" if node.index == 0 \
			else (("ЗАЛ БОССА" if boss_stop else "ДАЛЬНИЙ ЗАЛ") if node.boss \
				else ("НЕОБЯЗАТЕЛЬНАЯ КОМНАТА" if node.optional else "БОЕВАЯ КОМНАТА"))

		var room: RoomDef = RoomDef.new()
		room.index = i
		room.display_name = name
		room.bounds = _godot_room_bounds(node.center, node.size)
		if node.has_meta("apartment_entry"):
			room.set_meta("apartment_entry",true)
			room.set_meta("entry_stair_rear_depth",_scheme.entry_stair_rear_depth)
			room.set_meta("entry_stairs",entry_stair_bounds(node,_scheme))
			room.set_meta("entry_stair_pockets",entry_stair_pockets(node,_scheme))
		if node.has_meta("entry_neighbour"): room.set_meta("entry_neighbour",true)
		if node.service_shower: room.set_meta("endless_service_shower",true)
		room.areas = node_floor_areas(node)
		room.wall_segments = _architectural_wall_segments(node)
		# These boundary segments are already door-cut.
		room.door_openings = []
		room.shell_asset = node.asset_name
		room.visual_variant = i
		room.has_chest = has_chest
		room.chest_position = _to_godot_point(chest_unity)
		room.is_boss_room = node.boss and boss_stop
		room.trash_count = 0 if node.index == 0 else _trash_count_for_role(node.role)
		if node.has_meta("apartment_entry"): room.trash_count=0;room.has_chest=false
		rooms.append(room)
		chest_positions_unity.append(chest_unity)
	_own_shared_walls_once(rooms)
	level.rooms = rooms

	var doors: Array[DoorDef] = []
	for i: int in nodes.size():
		for other_node_index: int in nodes[i].links:
			if other_node_index <= nodes[i].index:
				continue
			# The cabin owns its entrance doors; do not add a second seal.
			if nodes[i].index == 0 or other_node_index == 0:
				continue
			var other_node: EndlessNode = _find_node_by_index(nodes, other_node_index)
			var other_room_index: int = position_by_node_index[other_node_index]
			doors.append(_build_door_def(nodes[i], other_node, i, other_room_index))
	level.doors = doors

	var start_node: EndlessNode = nodes[0]
	var boss_node: EndlessNode = null
	var boss_room_index: int = -1
	for i: int in nodes.size():
		if nodes[i].boss:
			boss_node = nodes[i]
			boss_room_index = i
			break
	assert(boss_node != null, "Endless layout has no final boss room.")

	level.player_spawn = _to_godot_point(start_node.center)
	level.boss_position = _to_godot_point(boss_node.center)
	level.boss_room_index = boss_room_index
	level.boss_required_for_goal = boss_stop

	var linked_node: EndlessNode = _find_node_by_index(nodes, boss_node.links[0])
	var boss_entry_direction: Vector2 = (linked_node.center - boss_node.center).normalized()
	var perpendicular: Vector2 = Vector2(-boss_entry_direction.y, boss_entry_direction.x)
	var boss_interior_scale: float = minf(boss_node.size.x, boss_node.size.y)
	var goal_unity: Vector2 = boss_node.center + perpendicular * boss_interior_scale * 0.16
	var boss_chest_unity: Vector2 = boss_node.center - perpendicular * boss_interior_scale * 0.16

	level.goal_position = _to_godot_point(goal_unity)
	rooms[boss_room_index].chest_position = _to_godot_point(boss_chest_unity)
	chest_positions_unity[boss_room_index] = boss_chest_unity

	var total_fogs: int = 0
	for i: int in nodes.size():
		var node: EndlessNode = nodes[i]
		if node.index == 0 or node.has_meta("apartment_entry") or is_corridor(node, _scheme):
			continue
		var area: float = 0.0
		for part: Rect2 in rooms[i].areas:
			area += part.get_area()
		var count: int = regular_fogs_for_area(area, rooms[0].bounds.get_area(), _scheme, _endless_random.next_double())
		var placements: Array[FogPlacementDef] = _spawn_fogs(
			node, i, count, chest_positions_unity[i], rooms[i].has_chest
		)
		var fogs: Array[FogPlacementDef] = placements
		rooms[i].fogs = fogs
		_fit_room_encounters(rooms[i])
		total_fogs += rooms[i].fogs.size()

	assert(total_fogs > 0, "An expedition must contain souls to charge its elevator.")

	var data: EndlessFloorData = EndlessFloorData.new()
	data.level = level
	data.cabin_center = level.player_spawn
	data.cabin_bounds = Rect2(level.player_spawn - Vector2(4.0, 3.5), Vector2(8.0, 7.0))
	data.cabin_door_position = level.player_spawn + Vector2(0.0, 3.5)
	data.portal_position = data.cabin_center
	level.portal_position = data.portal_position
	data.theme_id = theme
	data.theme_name = theme_name_for(theme)
	data.cycle_index = (maxi(1, floor_index) - 1) / 5
	data.is_boss_floor = boss_stop
	data.boss_health_multiplier = _scheme.boss_health_multiplier
	data.boss_damage_multiplier = _scheme.boss_damage_multiplier
	data.seed = _endless_seed
	data.floor_index = floor_index
	data.nodes = nodes
	for active_node: EndlessNode in nodes:
		data.furniture_zones.append(furniture_areas(active_node))
	data.master_nodes = _potential_nodes
	data.active_master_indices = _active_master_indices
	data.sealed_ports = _sealed_ports
	data.building_bounds = level.backdrop_bounds.grow(-FLOOR_PADDING)
	data.building_grid_size = Vector2i(_scheme.building_columns, _scheme.building_rows)
	for node: EndlessNode in _potential_nodes:
		var room: RoomDef = RoomDef.new()
		room.index = node.index
		room.bounds = _godot_room_bounds(node.center, node.size)
		if node.has_meta("apartment_entry"):
			room.set_meta("apartment_entry",true)
			room.set_meta("entry_stair_rear_depth",_scheme.entry_stair_rear_depth)
			room.set_meta("entry_stairs",entry_stair_bounds(node,_scheme))
			room.set_meta("entry_stair_pockets",entry_stair_pockets(node,_scheme))
		if node.has_meta("entry_neighbour"): room.set_meta("entry_neighbour",true)
		if node.service_shower: room.set_meta("endless_service_shower",true)
		room.areas = node_floor_areas(node)
		room.shell_asset = node.asset_name
		room.wall_segments = _architectural_wall_segments(node)
		room.trash_count = 0
		room.has_chest = false
		room.fogs = []
		data.master_rooms.append(room)
	# Dressing and encounter placement must share the same corridor classification.
	for node: EndlessNode in data.nodes:
		node.set_meta("endless_corridor", is_corridor(node, _scheme))
	for node: EndlessNode in data.master_nodes:
		node.set_meta("endless_corridor", is_corridor(node, _scheme))
	for room: RoomDef in data.level.rooms + data.master_rooms:
		room.set_meta("endless_bath_max_span", _scheme.bath_max_player_span * _scheme.room_player_width)
	Furnishing.apply(data)
	return data


# Test corridor width across the floor union, not the bounding box of a bent room.
static func is_corridor(node: EndlessNode, scheme: EndlessScheme) -> bool:
	if node.role == EndlessNode.Role.START or node.service_shower:
		return false
	if node.role == EndlessNode.Role.HALL or node.asset_name == "room_hall_ew_01":
		return true
	if minf(node.size.x, node.size.y) <= scheme.corridor_width_max + 0.001:
		return true
	if node.role not in [EndlessNode.Role.CONNECTOR, EndlessNode.Role.OPTIONAL_CONNECTOR, EndlessNode.Role.FUNNEL]:
		return false
	var outline: PackedVector2Array = node.floor_outline_unity
	if outline.is_empty():
		outline = _contour_for_asset(node.asset_name, unrotated_size(node))
	# Erosion leaves no interior when every arm is corridor-width.
	return Geometry2D.offset_polygon(outline, -(scheme.corridor_width_max * 0.5 + 0.001), Geometry2D.JOIN_MITER).is_empty()


# Use floor-union area; concave bounding boxes overestimate encounter space.
static func regular_fogs_for_area(area: float, lift_area: float, scheme: EndlessScheme, roll: float) -> int:
	var ratio: float = maxf(0.0, area) / maxf(0.001, lift_area)
	if ratio < scheme.room_fog_min_lift_ratio:
		return scheme.room_fog_small_count
	if ratio <= scheme.room_fog_single_lift_ratio:
		return scheme.room_fog_single_count
	if ratio <= scheme.room_fog_large_lift_ratio:
		var chance: float = inverse_lerp(scheme.room_fog_single_lift_ratio, scheme.room_fog_large_lift_ratio, ratio)
		return scheme.room_fog_medium_counts.y if roll < chance else scheme.room_fog_medium_counts.x
	return scheme.room_fog_large_counts.y if roll < scheme.room_fog_large_extra_chance else scheme.room_fog_large_counts.x


# Failed physical packing may reduce the roster, never place actors in masonry.
func _fit_room_encounters(room: RoomDef) -> void:
	var stats: Resource = Furnishing.DEFAULT_STATS
	Furnishing._add_wall_feet(room, stats)
	var reserved: Array[Vector2] = []
	if room.has_chest:
		room.chest_position = Furnishing._safe_encounter_position(room, room.chest_position,
			float(stats.wall_foot_chest_clearance), reserved, stats)
		var chest_clearance: float = float(stats.wall_foot_chest_clearance)
		room.has_chest = Furnishing._picture_inside(room, room.chest_position, Vector2.ONE * chest_clearance * 2.0) \
			and Furnishing.point_clear(room, room.chest_position, chest_clearance)
		if room.has_chest:
			reserved.append(room.chest_position)
	var accepted: Array[FogPlacementDef] = []
	var clearance: float = float(stats.wall_foot_actor_clearance)
	var separation: float = float(stats.actor_clearance) * 2.0
	for fog: FogPlacementDef in room.fogs:
		var candidate: Vector2 = Furnishing._safe_encounter_position(room, fog.position, clearance, reserved, stats)
		if not Furnishing._encounter_position_clear(room, candidate, clearance, reserved, separation):
			continue
		fog.position = candidate
		accepted.append(fog)
		reserved.append(candidate)
	if accepted.size() < room.fogs.size():
		var floor_area: float = 0.0
		for area: Rect2 in room.areas:
			floor_area += area.get_area()
		var available: float = floor_area - (_scheme.compact_room_chest_reserved_area if room.has_chest else 0.0)
		var budget: int = maxi(0, floori(available / maxf(0.01, _scheme.compact_room_area_per_fog)))
		if accepted.size() > budget:
			accepted.resize(budget)
	room.fogs = accepted
	# Rebuild provisional colliders once after encounter placement.
	Furnishing._clear_generated(room)


# Door ownership uses final room indices rather than graph creation-order IDs.
static func _build_door_def(
	first_node: EndlessNode, second_node: EndlessNode, first_room_index: int, second_room_index: int
) -> DoorDef:
	var first_direction: int = _connection_direction(first_node, second_node)
	var second_direction: int = _opposite_exit(first_direction)
	var horizontal: bool = first_direction == EndlessNode.EXIT_EAST \
		or first_direction == EndlessNode.EXIT_WEST
	var first_edge: Vector2 = first_node.link_positions.get(second_node.index, door_anchor_position(first_node, first_direction))
	var second_edge: Vector2 = second_node.link_positions.get(first_node.index, door_anchor_position(second_node, second_direction))
	var midpoint: Vector2 = (first_edge + second_edge) * 0.5

	var door: DoorDef = DoorDef.new()
	door.set_meta("endless_portal_id",portal_id(int(first_node.get_meta("endless_master_index",first_node.index)),
		int(second_node.get_meta("endless_master_index",second_node.index))))
	door.position = _to_godot_point(midpoint)
	door.passage_width = first_node.link_widths.get(second_node.index, DOOR_CUT_WIDTH * 1.12)
	door.horizontal_travel = horizontal
	door.label = "Процедурный стык комнат"
	door.locking_rooms = PackedInt32Array([first_room_index, second_room_index])
	return door


static func _min_vector(a: Vector2, b: Vector2) -> Vector2:
	return Vector2(minf(a.x, b.x), minf(a.y, b.y))
