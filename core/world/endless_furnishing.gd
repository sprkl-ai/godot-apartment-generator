extends RefCounted

## Places furniture against real wall faces using shared collision footprints.
const DEFAULT_STATS: Resource = preload("res://data/balance/endless_furnishing_stats.tres")
const DEFAULT_SCHEME: Resource = preload("res://data/balance/endless_scheme.tres")
const SANITY_STATS: Resource = preload("res://data/balance/endless_sanity_stats.tres")
# Measured empty tabletop of the nightstand model.
const TABLET_SURFACES: Dictionary = {"nightstand":[{"offset":Vector2.ZERO,"height":.7105,"size":Vector2(.50,.32)}]}
const RACK: String = "res://assets/environment/attic_rack.png"
const CABINET: String = "res://assets/environment/attic_cabinet.png"
const LAMP: String = "res://assets/sprites/endless_lamp.png"
const PREFIX: String = "endless_furnishing:"
const WALL_FOOT_PREFIX: String = "endless_wall_foot:"

static func apply(data: EndlessFloorData, stats: Resource = DEFAULT_STATS) -> void:
	if data == null or data.level == null:
		return
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = data.seed ^ 0x46F17
	var furnished_rooms: Array[RoomDef] = []
	var hall_ordinal: int = 0
	for room_index: int in data.level.rooms.size():
		var room: RoomDef = data.level.rooms[room_index]
		var node: EndlessNode = data.nodes[room_index] if room_index < data.nodes.size() else null
		var purpose: String = purpose_for(room,node,data.seed,stats)
		room.set_meta("endless_room_purpose",purpose)
		if purpose == "bath": room.set_meta("endless_bath_variant",bath_variant_for(room,data.seed,stats))
		if room_index > 0 and purpose == "hall" and not stats.hall_decor_roster.is_empty():
			room.set_meta("endless_hall_decor",String(stats.hall_decor_roster[posmod(data.seed+hall_ordinal,stats.hall_decor_roster.size())]))
			hall_ordinal += 1
	for room_index: int in data.level.rooms.size():
		var room: RoomDef = data.level.rooms[room_index]
		room.set_meta("endless_inactive_shell", false)
		_set_door_sweeps(room,data.level.doors,data.level.rooms)
		_set_sealed_ports(room, data.sealed_ports, stats)
		_clear_generated(room)
		if room_index == 0:
			continue
		_add_wall_feet(room, stats)
		if bool(room.get_meta("apartment_entry",false)):
			_furnish_entry(room,stats)
			continue
		_relocate_encounters(room, stats)
		var dense_room: bool = room_index < data.nodes.size() and not data.nodes[room_index].floor_outline_unity.is_empty()
		if dense_room and (data.nodes[room_index].role == EndlessNode.Role.START or (data.nodes[room_index].role == EndlessNode.Role.HALL and not stats.semantic_room_dressing)):
			continue
		if not dense_room and (room_index >= data.furniture_zones.size() or data.furniture_zones[room_index].is_empty()):
			continue
		furnished_rooms.append(room)
	# Reserve plant footprints before ordinary furniture.
	if stats.semantic_room_dressing:
		_add_distributed_plants(furnished_rooms, data.seed, stats)
		reserve_support_slots(furnished_rooms,"nightstand",int(SANITY_STATS.pill_min_per_floor),stats,TABLET_SURFACES)
	for room: RoomDef in furnished_rooms:
		_furnish_room(room, rng, stats)
	if stats.semantic_room_dressing:
		_ensure_weapon_support(data,furnished_rooms,stats)
	# Keep pots solid until all floor reservations are complete.
	if stats.semantic_room_dressing:
		_mark_plant_pickups(furnished_rooms, stats)
		_move_plant_to_entry(data,stats)
	# Background dressing uses a separate stream so it cannot change playable rooms.
	for master_index: int in data.master_rooms.size():
		var room: RoomDef = data.master_rooms[master_index]
		room.set_meta("endless_door_sweeps",[])
		_set_sealed_ports(room, data.sealed_ports, stats)
		_clear_generated(room)
		var active_index: int = data.active_master_indices.find(master_index)
		if active_index >= 0 and active_index < data.level.rooms.size():
			room.set_meta("endless_room_purpose",data.level.rooms[active_index].get_meta("endless_room_purpose","storage"))
			room.set_meta("endless_bath_variant",data.level.rooms[active_index].get_meta("endless_bath_variant","bath"))
			room.set_meta("endless_door_sweeps",data.level.rooms[active_index].get_meta("endless_door_sweeps",[]))
			for prop: LevelColliderDef in data.level.rooms[active_index].colliders:
				if String(prop.editor_id).begins_with(PREFIX) or String(prop.editor_id).begins_with(WALL_FOOT_PREFIX):
					room.colliders.append(prop.duplicate(true))
			continue
		if master_index == 0 or master_index >= data.master_nodes.size():
			continue
		# Sealed background rooms need no traversal grid.
		room.set_meta("endless_inactive_shell", true)
		_add_wall_feet(room, stats)
		var node: EndlessNode = data.master_nodes[master_index]
		room.set_meta("endless_room_purpose",purpose_for(room,node,data.seed,stats))
		if room.get_meta("endless_room_purpose") == "bath": room.set_meta("endless_bath_variant",bath_variant_for(room,data.seed,stats))
		if node.role == EndlessNode.Role.START or (node.role == EndlessNode.Role.HALL and not stats.semantic_room_dressing) or (node.floor_outline_unity.is_empty() and node.role in [EndlessNode.Role.CONNECTOR, EndlessNode.Role.OPTIONAL_CONNECTOR]):
			continue
		var master_rng: RandomNumberGenerator = RandomNumberGenerator.new()
		master_rng.seed = data.seed ^ 0x46F17 ^ (master_index * 7919)
		_furnish_room(room, master_rng, stats)
		_furnish_background_center(room, master_rng, stats)


static func _furnish_background_center(room: RoomDef, rng: RandomNumberGenerator, stats: Resource) -> void:
	if not stats.semantic_room_dressing: return
	room.set_meta("endless_inactive_shell", true)
	var purpose: String = dressing_purpose_for(room)
	var kinds: Array = stats.background_center_groups.get(purpose,[])
	var area: float = 0.0
	for part: Rect2 in room.areas: area += part.get_area()
	if kinds.is_empty() or area < stats.background_center_min_area: return
	var wanted: int=mini(stats.background_center_max_groups,roundi(area/stats.background_center_min_area))
	var centres: Array[Vector2]=[]
	var candidates: Array[Vector2] = [room.bounds.get_center()]
	for part: Rect2 in room.areas:
		if not candidates.has(part.get_center()): candidates.append(part.get_center())
	var inward: Vector2 = [Vector2.DOWN,Vector2.LEFT,Vector2.UP,Vector2.RIGHT][rng.randi_range(0,3)]
	var tangent: Vector2 = inward.orthogonal()
	var anchors: Array[Vector2] = []
	var first_size: Vector2 = footprint_for(String(kinds[0]),stats)
	while not candidates.is_empty() and centres.size()<wanted:
		if not centres.is_empty():
			candidates.sort_custom(func(a: Vector2,b: Vector2)->bool:return a.distance_squared_to(centres[-1])>b.distance_squared_to(centres[-1]))
		var centre: Vector2=candidates.pop_front()
		if centres.any(func(previous: Vector2)->bool:return previous.distance_to(centre)<first_size.length()*2.0+stats.semantic_group_gap):continue
		if not _try_place(room,room.colliders.size(),String(kinds[0]),first_size,first_size,centre,inward,anchors,stats,true): continue
		centres.append(centre)
		room.colliders[-1].set_meta("background_center_group",true)
		for index: int in range(1,kinds.size()):
			var kind: String = String(kinds[index])
			var size: Vector2 = footprint_for(kind,stats)
			var point: Vector2 = centre + (inward*((first_size.y+size.y)*.5+stats.semantic_group_gap) if index==1 else tangent*((first_size.x+size.x)*.5+stats.semantic_group_gap))
			if _try_place(room,room.colliders.size(),kind,size,size,point,inward,anchors,stats,true):
				room.colliders[-1].set_meta("background_center_group",true)


# Adjacency requires a shared wall interval; bounds overlap or corner contact is insufficient.
static func rooms_share_boundary(first: RoomDef, second: RoomDef) -> bool:
	if first == second: return false
	for a: Rect2 in first.areas:
		for b: Rect2 in second.areas:
			var vertical: bool = is_equal_approx(a.end.x,b.position.x) or is_equal_approx(b.end.x,a.position.x)
			var horizontal: bool = is_equal_approx(a.end.y,b.position.y) or is_equal_approx(b.end.y,a.position.y)
			if vertical and minf(a.end.y,b.end.y)-maxf(a.position.y,b.position.y) > .001: return true
			if horizontal and minf(a.end.x,b.end.x)-maxf(a.position.x,b.position.x) > .001: return true
	return false


static func _mark_plant_pickups(rooms: Array[RoomDef], stats: Resource) -> void:
	if int(stats.plant_pickup_count) <= 0: return
	var marked: int = 0
	for room: RoomDef in rooms:
		if room.get_meta("endless_room_purpose","") == "hall": continue
		for prop: LevelColliderDef in room.colliders:
			if not String(prop.editor_id).begins_with(PREFIX) or String(prop.editor_id).get_slice(":",3) != "plant": continue
			var type: int = int(Loot.Type.get(String(prop.get_meta("plant_variant","")).to_upper(),-1))
			if not Loot.is_plant(type): continue
			prop.set_meta("plant_pickup_type",type)
			prop.disabled = true; prop.collision_layer = 0
			marked += 1
			if marked >= int(stats.plant_pickup_count): return
			break


static func _add_distributed_plants(rooms: Array[RoomDef], seed: int, stats: Resource) -> void:
	if stats.plant_variants.is_empty() or int(stats.plant_floor_min_count) <= 0: return
	var candidates: Array[Dictionary] = []
	for room: RoomDef in rooms:
		if not stats.plant_room_purposes.has(String(room.get_meta("endless_room_purpose",""))): continue
		var candidate: Dictionary = _plant_wall_candidate(room,seed,stats)
		if not candidate.is_empty(): candidates.append(candidate)
	var selected: Array[int] = []
	var wanted: int = mini(int(stats.plant_floor_min_count),candidates.size())
	while wanted > 0 and selected.is_empty():
		for pair_limit: int in int(stats.plant_max_adjacent_pairs)+1:
			var best: Dictionary = {"indices":[],"spacing":-INF,"spread":-INF}
			_find_plant_selection(candidates,wanted,pair_limit,0,[],best,float(stats.plant_min_separation),mini(wanted,int(stats.plant_pickup_count)))
			selected.assign(best.indices)
			if not selected.is_empty(): break
		wanted -= 1
	var variant_offset: int = posmod(seed,stats.plant_variants.size())
	var placed: Array[Dictionary] = []
	for ordinal: int in selected.size():
		var entry: Dictionary = candidates[selected[ordinal]]
		_place_planned_plant(entry,placed.size(),String(stats.plant_variants[posmod(variant_offset+ordinal,stats.plant_variants.size())]),stats)
		placed.append(entry)
	_fill_other_plant_walls(placed,seed,stats,["living","storage"],variant_offset)
	if placed.size() >= int(stats.plant_floor_min_count): return
	var overflow: Array[Dictionary] = placed.duplicate()
	var initial: Array[int] = []
	for index: int in placed.size(): initial.append(index)
	for room: RoomDef in rooms:
		if room.get_meta("endless_room_purpose","") != "bath": continue
		var entry: Dictionary = _plant_wall_candidate(room,seed,stats,placed)
		if not entry.is_empty(): overflow.append(entry)
	var missing: int = mini(int(stats.plant_floor_min_count)-placed.size(),overflow.size()-placed.size())
	while missing > 0:
		var best: Dictionary = {"indices":[],"spacing":-INF,"spread":-INF}
		_find_plant_selection(overflow,missing,int(stats.plant_max_adjacent_pairs)-_plant_pair_count(placed),placed.size(),initial,best,float(stats.plant_min_separation),mini(placed.size()+missing,int(stats.plant_pickup_count)))
		if not best.indices.is_empty():
			for index: int in best.indices:
				if index < placed.size(): continue
				var entry: Dictionary = overflow[index]
				_place_planned_plant(entry,placed.size(),String(stats.plant_variants[posmod(variant_offset+placed.size(),stats.plant_variants.size())]),stats)
				placed.append(entry)
			break
		missing -= 1
	_fill_other_plant_walls(placed,seed,stats,["bath"],variant_offset)


static func _place_planned_plant(entry: Dictionary, ordinal: int, variant: String, stats: Resource) -> void:
	var room: RoomDef = entry.room
	var size: Vector2 = footprint_for("plant",stats)
	var inward: Vector2 = entry.inward
	var footprint: Vector2 = size if absf(inward.y)>.5 else Vector2(size.y,size.x)
	var prop: LevelColliderDef = _prop(room.index,2000+ordinal,"plant",_wall_side(inward),entry.point,footprint,size,inward)
	prop.set_meta("plant_variant",variant)
	room.colliders.append(prop)


static func _plant_pair_count(placed: Array[Dictionary]) -> int:
	var pairs: int = 0
	for i: int in placed.size():
		for j: int in range(i+1,placed.size()):
			if rooms_share_boundary(placed[i].room,placed[j].room): pairs += 1
	return pairs


static func _fill_other_plant_walls(placed: Array[Dictionary], seed: int, stats: Resource, purposes: Array[String], variant_offset: int) -> void:
	var rooms: Array[RoomDef] = []
	for entry: Dictionary in placed:
		var room: RoomDef = entry.room
		if rooms.has(room) or not purposes.has(String(room.get_meta("endless_room_purpose",""))): continue
		var has_neighbour: bool = false
		for other: Dictionary in placed:
			if rooms_share_boundary(room,other.room): has_neighbour = true; break
		if not has_neighbour: rooms.append(room)
	rooms.sort_custom(func(a: RoomDef,b: RoomDef)->bool:
		var first_area: float = 0.0; var second_area: float = 0.0
		for area: Rect2 in a.areas: first_area += area.get_area()
		for area: Rect2 in b.areas: second_area += area.get_area()
		return first_area > second_area)
	for room: RoomDef in rooms:
		while placed.size() < int(stats.plant_floor_min_count):
			var entry: Dictionary = _plant_wall_candidate(room,seed,stats,placed,true)
			if entry.is_empty(): break
			var variant: String = String(stats.plant_variants[posmod(variant_offset+placed.size(),stats.plant_variants.size())])
			_place_planned_plant(entry,placed.size(),variant,stats); placed.append(entry)


static func _plant_wall_candidate(room: RoomDef, seed: int, stats: Resource, placed: Array[Dictionary] = [], other_wall: bool = false) -> Dictionary:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = seed ^ str(room.bounds.position,room.bounds.size).hash()
	var size: Vector2 = footprint_for("plant",stats)
	var candidates: Array[Dictionary] = []
	for edge: WallSegmentDef in room_wall_segments(room):
		var inward: Vector2 = wall_inward(room,edge)
		if inward == Vector2.ZERO: continue
		var wall_taken: bool = false
		if other_wall:
			for previous: Dictionary in placed:
				if previous.room == room and Vector2(previous.inward).is_equal_approx(inward): wall_taken = true; break
		if wall_taken: continue
		var margin: float = size.x*.5+float(stats.door_clearance)
		var length: float = edge.from.distance_to(edge.to)
		if length <= margin*2.0: continue
		var tangent: Vector2 = (edge.to-edge.from).normalized()
		for attempt: int in int(stats.placement_attempts):
			var fraction: float = random.randf()
			var point: Vector2 = edge.from+tangent*lerpf(margin,length-margin,fraction)+inward*(wall_placement_offset(stats,inward)+size.y*.5)
			var nearby: bool = false
			for previous: Dictionary in placed:
				if point.distance_to(previous.point) < float(stats.plant_min_separation): nearby = true; break
			if nearby: continue
			var footprint: Vector2 = size if absf(inward.y)>.5 else Vector2(size.y,size.x)
			if _fits(room,point,footprint,[],stats): candidates.append({"room":room,"point":point,"inward":inward})
	if candidates.is_empty(): return {}
	return candidates[random.randi_range(0,candidates.size()-1)]


static func _find_plant_selection(candidates: Array[Dictionary], remaining: int, pairs_left: int, start: int, chosen: Array[int], best: Dictionary, minimum_separation: float, minimum_pickups: int) -> void:
	if remaining == 0:
		var pickup_candidates: int = 0
		for index: int in chosen:
			if candidates[index].room.get_meta("endless_room_purpose","") != "hall": pickup_candidates += 1
		if pickup_candidates < minimum_pickups: return
		var spacing: float = INF
		var spread: float = 0.0
		for i: int in chosen.size():
			for j: int in range(i+1,chosen.size()):
				var distance: float = Vector2(candidates[chosen[i]].point).distance_squared_to(candidates[chosen[j]].point)
				spacing = minf(spacing,distance); spread += distance
		if spacing > float(best.spacing) or (is_equal_approx(spacing,float(best.spacing)) and spread > float(best.spread)):
			best.indices = chosen.duplicate(); best.spacing = spacing; best.spread = spread
		return
	for index: int in range(start,candidates.size()-remaining+1):
		var added_pairs: int = 0
		var nearby: bool = false
		for previous: int in chosen:
			if Vector2(candidates[index].point).distance_to(candidates[previous].point) < minimum_separation: nearby = true; break
			if rooms_share_boundary(candidates[index].room,candidates[previous].room): added_pairs += 1
		if nearby or added_pairs > pairs_left: continue
		chosen.append(index)
		_find_plant_selection(candidates,remaining-1,pairs_left-added_pairs,index+1,chosen,best,minimum_separation,minimum_pickups)
		chosen.pop_back()

static func _clear_generated(room: RoomDef) -> void:
	if room.has_meta("endless_traversal_grid"): room.remove_meta("endless_traversal_grid")
	for index: int in range(room.colliders.size() - 1, -1, -1):
		var id: String = String(room.colliders[index].editor_id)
		if id.begins_with(PREFIX) or id.begins_with(WALL_FOOT_PREFIX):
			room.colliders.remove_at(index)

static func _set_sealed_ports(room: RoomDef, ports: Array[Dictionary], stats: Resource) -> void:
	var adjacent: Array[Dictionary] = []
	for port: Dictionary in ports:
		var at: Vector2 = port.position
		var across: Vector2 = port.get("normal",Vector2.RIGHT if bool(port.horizontal_travel) else Vector2.DOWN)
		var probe: Vector2 = across * float(stats.wall_probe_distance)
		if room.contains(at + probe) or room.contains(at - probe):
			var local: Dictionary = port.duplicate()
			local["reservation_half_depth"] = maxf(float(stats.wall_foot_depth),float(stats.sealed_port_reservation_half_depth))
			adjacent.append(local)
	room.set_meta("endless_sealed_ports", adjacent)


static func _set_door_sweeps(room: RoomDef, doors: Array[DoorDef], rooms: Array[RoomDef] = []) -> void:
	var sweeps: Array[Dictionary] = []
	for door: DoorDef in doors:
		if door.locking_rooms.has(room.index):
			var corridor_neighbor: bool = false
			for other: int in door.locking_rooms:
				if other != room.index and other >= 0 and other < rooms.size() and rooms[other].get_meta("endless_room_purpose","") == "hall": corridor_neighbor = true
			sweeps.append({"position":door.position,"width":door.passage_width,"horizontal_travel":door.horizontal_travel,"corridor_neighbor":corridor_neighbor})
	room.set_meta("endless_door_sweeps",sweeps)


# Door sweeps use passage width but retain authored leaf depth.
# Expand only for handle clearance, not the whole doorway box.
static func door_sweep_clear(room: RoomDef, point: Vector2, size: Vector2, stats: Resource = DEFAULT_STATS) -> bool:
	for sweep: Dictionary in room.get_meta("endless_door_sweeps",[]):
		var tangent: Vector2 = Vector2.DOWN if bool(sweep.horizontal_travel) else Vector2.RIGHT
		var normal: Vector2 = tangent.orthogonal()
		var offset: Vector2 = point-Vector2(sweep.position)
		var centre: Vector2 = Vector2(offset.dot(tangent),offset.dot(normal))
		var half: Vector2 = Vector2(size.dot(tangent.abs()),size.dot(normal.abs()))*.5+Vector2.ONE*float(stats.door_sweep_clearance)
		var along_radius: float = maxf(.001,float(sweep.width)*.5)
		var depth_radius: float = maxf(.001,float(stats.door_sweep_leaf_depth))
		for side: float in [-1.0,1.0]:
			var along: float = (centre.x-side*along_radius)*-side
			if along+half.x < 0.0: continue
			var closest: Vector2 = Vector2(maxf(0.0,along-half.x)/along_radius,maxf(0.0,absf(centre.y)-half.y)/depth_radius)
			if closest.length_squared() <= 1.0: return false
	return true

static func _furnish_room(room: RoomDef, rng: RandomNumberGenerator, stats: Resource) -> void:
	if stats.semantic_room_dressing and dressing_purpose_for(room)=="shower":
		if _furnish_public_shower(room,stats):
			_relocate_encounters(room,stats)
			return
		# A shower needs an opposing sink wall; use a bath only if its own size limit fits.
		room.set_meta("endless_bath_variant","bath")
		if not ordinary_bath_room_eligible(room): room.set_meta("endless_room_purpose","storage")
	var edges: Array[WallSegmentDef] = room_wall_segments(room)
	var wanted: int = clampi(roundi(room.bounds.get_area() / float(stats.floor_area_per_cluster)), int(stats.clusters_min), int(stats.clusters_max))
	var anchors: Array[Vector2] = []
	var used_kinds: Dictionary = {}
	for prop: LevelColliderDef in room.colliders:
		if String(prop.editor_id).begins_with(PREFIX) and (String(prop.editor_id).get_slice(":",3) == "plant" or prop.has_meta("support_access_reservation")):
			var reserved_kind: String = String(prop.editor_id).get_slice(":",3)
			anchors.append(prop.position); used_kinds[reserved_kind] = int(used_kinds.get(reserved_kind,0))+1
	var reserved_count: int = anchors.size()
	var purpose: String = dressing_purpose_for(room)
	var required: Array = stats.purpose_required.get(purpose,[]) if stats.semantic_room_dressing else []
	if stats.semantic_room_dressing and purpose == "hall" and not stats.hall_decor_roster.is_empty():
		var hall_fallback: String = String(stats.hall_decor_roster[posmod(str(room.bounds).hash(),stats.hall_decor_roster.size())])
		required = [String(room.get_meta("endless_hall_decor",hall_fallback))]
	if stats.semantic_room_dressing:
		if stats.semantic_area_per_prop.has(purpose):
			var area: float = 0.0
			for part: Rect2 in room.areas: area += part.get_area()
			var limits: Vector2i = stats.semantic_count_limits[purpose]
			wanted = clampi(ceili(area/float(stats.semantic_area_per_prop[purpose])),limits.x,limits.y)
		wanted = maxi(wanted,required.size()+reserved_count)
		if purpose == "hall": wanted = mini(wanted,int(stats.hall_decor_limit))
	for cluster: int in maxi(0,wanted-reserved_count):
		var kind: String = String(required[cluster]) if cluster < required.size() else _choose_kind(rng, stats, purpose)
		if stats.semantic_room_dressing and int(used_kinds.get(kind,0)) >= _kind_limit(kind,purpose,stats):
			var available: Array = stats.purpose_decor.get(purpose,[]).filter(func(candidate: String)->bool:return candidate != "plant" and not stats.semantic_floor_decor.get(purpose,[]).has(candidate) and int(used_kinds.get(candidate,0)) < _kind_limit(candidate,purpose,stats))
			if available.is_empty(): break
			kind = String(available[rng.randi_range(0,available.size()-1)])
		var variation: float = rng.randf_range(1.0 - float(stats.size_variation), 1.0 + float(stats.size_variation))
		var choices: Array[String] = [kind]
		if anchors.is_empty() and kind != "broom" and not stats.semantic_room_dressing:
			# Try smaller pieces without relaxing doorway or encounter reservations.
			if kind != "lamp": choices.append("lamp")
			choices.append("broom")
		elif stats.semantic_room_dressing:
			for fallback: String in stats.semantic_fallbacks.get(purpose,[]):
				if fallback == "plant": continue
				if not choices.has(fallback) and int(used_kinds.get(fallback,0)) < _kind_limit(fallback,purpose,stats): choices.append(fallback)
		var targets: Array[Dictionary] = []
		var placed: bool = false
		for choice: String in choices:
			# Shelf depth must still support its carried loot.
			var choice_scale: float = maxf(variation,float(stats.support_carrier_min_scale)) if stats.support_surfaces.has(choice) else variation
			if choice == "laundry_rack": choice_scale = 1.0
			var base_size: Vector2 = footprint_for(choice,stats) * choice_scale
			var picture: Vector2 = base_size if stats.semantic_footprints.has(choice) else stats.get(choice + "_picture_size") * choice_scale
			if stats.semantic_room_dressing and choice == kind:
				for candidate: Dictionary in _group_targets(room,choice,base_size,stats):
					if _try_place(room,cluster,choice,base_size,picture,candidate.point,candidate.inward,anchors,stats,true):
						placed = true; break
			if placed:
				used_kinds[choice] = int(used_kinds.get(choice,0))+1
				break
			for attempt: int in int(stats.placement_attempts):
				if edges.is_empty(): break
				if choice == kind:
					var fraction: float = rng.randf()
					if rng.randf() < float(stats.corner_preference) or choice=="lamp":
						fraction = float(rng.randi_range(0, 1))
					targets.append({"edge":edges[rng.randi_range(0, edges.size()-1)],"fraction":fraction})
				var target: Dictionary = targets[attempt]
				var edge: WallSegmentDef = target.edge
				var inward: Vector2 = wall_inward(room, edge)
				if inward == Vector2.ZERO: continue
				var tangent: Vector2 = (edge.to - edge.from).normalized()
				var margin: float = base_size.x * 0.5 + float(stats.door_clearance)
				var length: float = edge.from.distance_to(edge.to)
				if length <= margin * 2.0: continue
				var point: Vector2 = edge.from + tangent * lerpf(margin, length-margin, float(target.fraction)) + inward * (wall_placement_offset(stats,inward,choice) + base_size.y * 0.5)
				if not _try_place(room,cluster,choice,base_size,picture,point,inward,anchors,stats): continue
				used_kinds[choice] = int(used_kinds.get(choice,0))+1
				placed = true
				break
			if placed: break
	if stats.semantic_room_dressing: _add_floor_decor(room,rng,purpose,stats)


# Rugs are non-solid dressing but must remain clear of masonry.
static func _add_floor_decor(room: RoomDef, rng: RandomNumberGenerator, purpose: String, stats: Resource) -> void:
	var kinds: Array = stats.semantic_floor_decor.get(purpose,[])
	if kinds.is_empty(): return
	var area: float = 0.0
	for part: Rect2 in room.areas: area += part.get_area()
	var wanted: int = clampi(ceili(area/float(stats.floor_decor_area_per_prop)),stats.floor_decor_count_limits.x,stats.floor_decor_count_limits.y)
	var placed: Array[Rect2] = []
	var kind_offset: int = rng.randi_range(0,kinds.size()-1)
	for ordinal: int in wanted:
		var kind: String = String(kinds[posmod(ordinal+kind_offset,kinds.size())])
		var base_size: Vector2 = footprint_for(kind,stats)
		var anchor: LevelColliderDef = null
		var anchor_kinds: Array[String] = ["sofa"]
		if purpose == "bath": anchor_kinds.assign(["sink","bathtub"])
		for anchor_kind: String in anchor_kinds:
			for prop: LevelColliderDef in room.colliders:
				if String(prop.editor_id).get_slice(":",3) == anchor_kind:
					anchor = prop; break
			if anchor != null: break
		var inward: Vector2 = Vector2.DOWN
		if anchor != null: inward = anchor.get_meta("wall_inward",Vector2.DOWN)
		elif purpose == "hall" and room.bounds.size.y>room.bounds.size.x: inward = Vector2.RIGHT
		var size: Vector2 = base_size if absf(inward.y)>.5 else Vector2(base_size.y,base_size.x)
		var candidates: Array[Dictionary] = []
		if purpose != "hall" and rng.randf() < float(stats.floor_decor_entry_preference): candidates.append_array(_entry_rug_candidates(room,base_size,stats))
		if anchor != null:
			var gap: float = float(stats.floor_decor_edge_padding) if purpose == "bath" else float(stats.semantic_group_gap)
			candidates.append({"point":anchor.position+inward*(anchor.size.dot(inward.abs())*.5+size.dot(inward.abs())*.5+gap),"inward":inward})
		for attempt: int in int(stats.placement_attempts):
			var part: Rect2 = room.areas[rng.randi_range(0,room.areas.size()-1)]
			candidates.append({"point":part.position+part.size*Vector2(rng.randf(),rng.randf()),"inward":inward})
		for candidate: Dictionary in candidates:
			var point: Vector2 = candidate.point
			inward = candidate.inward
			size = base_size if absf(inward.y)>.5 else Vector2(base_size.y,base_size.x)
			var padded: Vector2 = size+Vector2.ONE*float(stats.floor_decor_edge_padding)*2.0
			if not _picture_inside(room,point,padded): continue
			if not door_sweep_clear(room,point,size,stats): continue
			var footprint: Rect2 = Rect2(point-padded*.5,padded)
			var valid: bool = true
			for previous: Rect2 in placed:
				if footprint.intersects(previous): valid = false; break
			if not valid: continue
			for edge: WallSegmentDef in room_wall_segments(room):
				if footprint.intersects(Rect2(edge.from,edge.to-edge.from).abs().grow(float(stats.wall_collision_thickness)*.5)):
					valid = false; break
			if not valid: continue
			var prop: LevelColliderDef = _prop(room.index,1000+ordinal,kind,_wall_side(inward),point,size,size,inward)
			prop.disabled = true; prop.collision_layer = 0; prop.floor_decoration = true
			room.colliders.append(prop); placed.append(footprint)
			break


static func _entry_rug_candidates(room: RoomDef, size: Vector2, stats: Resource) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for door: Dictionary in room.get_meta("endless_door_sweeps",[]):
		if not bool(door.get("corridor_neighbor",false)): continue
		var inward: Vector2 = Vector2.RIGHT if bool(door.horizontal_travel) else Vector2.DOWN
		if not room.contains(Vector2(door.position)+inward*float(stats.wall_probe_distance)): inward = -inward
		var depth: float = float(stats.door_sweep_leaf_depth)+float(stats.door_sweep_clearance)+float(stats.floor_decor_entry_gap)+size.y*.5
		result.append({"point":Vector2(door.position)+inward*depth,"inward":inward})
	return result


# Only empty authored shelf tiers are supports; there is no floor fallback.
static func support_slots(room: RoomDef, stats: Resource = DEFAULT_STATS, surface_overrides: Dictionary = {}) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var surfaces: Dictionary = stats.support_surfaces if surface_overrides.is_empty() else surface_overrides
	for prop: LevelColliderDef in room.colliders:
		var parts: PackedStringArray = String(prop.editor_id).split(":")
		if parts.size() < 5 or not String(prop.editor_id).begins_with(PREFIX) or prop.disabled: continue
		var kind: String = parts[3]
		if not surfaces.has(kind): continue
		var inward: Vector2 = prop.get_meta("wall_inward",Vector2.DOWN)
		var wanted: Vector2 = prop.size if absf(inward.y)>.5 else Vector2(prop.size.y,prop.size.x)
		var native: Vector2 = footprint_for(kind,stats)
		var factor: float = minf(wanted.x/native.x,wanted.y/native.y)
		var tangent: Vector2 = Vector2(inward.y,-inward.x)
		var yaw: float = {"north":0.0,"south":PI,"west":PI*.5,"east":-PI*.5}.get(parts[4],0.0)
		var tiers: Array = surfaces[kind]
		for ordinal: int in tiers.size():
			var tier: Dictionary = tiers[ordinal]
			var offset: Vector2 = tier.offset
			var approach: Vector2 = prop.position+inward*(prop.size.dot(inward.abs())*.5+float(stats.support_approach_clearance)+float(stats.wall_gap))
			result.append({"point":prop.position+(tangent*offset.x+inward*offset.y)*factor,"height":float(tier.height)*factor,"yaw":yaw,"size":Vector2(tier.size)*factor,"prop_id":String(prop.editor_id),"slot_id":"%s:%d" % [prop.editor_id,ordinal],"approach":approach})
	return result


# Reserve enough approach space for the full player body.
static func reachable_support_slots(room: RoomDef, stats: Resource = DEFAULT_STATS, surfaces: Dictionary = TABLET_SURFACES) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if room.index == 0 or bool(room.get_meta("apartment_entry",false)): return result
	if dressing_purpose_for(room) not in ["living","storage"]: return result
	for slot: Dictionary in support_slots(room,stats,surfaces):
		var inward: Vector2 = (Vector2(slot.approach)-Vector2(slot.point)).normalized()
		slot.approach += inward*maxf(0,float(stats.player_body_radius)-float(stats.support_approach_clearance)+float(stats.wall_gap))
		if not _picture_inside(room,slot.approach,Vector2.ONE*float(stats.player_body_radius)*2.0): continue
		if point_clear(room,slot.approach,float(stats.player_body_radius)): result.append(slot)
	return result


# Reserve carriers before random dressing so collision and visuals use one plan.
static func reserve_support_slots(rooms: Array[RoomDef], kind: String, minimum: int, stats: Resource = DEFAULT_STATS, surfaces: Dictionary = TABLET_SURFACES) -> void:
	var count: int = 0
	for room: RoomDef in rooms:
		count += reachable_support_slots(room,stats,surfaces).size()
	if count >= minimum: return
	var size: Vector2 = footprint_for(kind,stats)
	for pass_index: int in minimum:
		for room: RoomDef in rooms:
			if count >= minimum: return
			if room.index == 0 or bool(room.get_meta("apartment_entry",false)): continue
			if dressing_purpose_for(room) not in ["living","storage"]: continue
			if not stats.purpose_decor.get(dressing_purpose_for(room),[]).has(kind): continue
			if reachable_support_slots(room,stats,surfaces).size() > pass_index: continue
			var placed: bool = false
			for wall: WallSegmentDef in room_wall_segments(room):
				var inward: Vector2 = wall_inward(room,wall)
				var margin: float = size.x*.5+float(stats.door_clearance)
				var length: float = wall.from.distance_to(wall.to)
				if inward == Vector2.ZERO or length <= margin*2.0: continue
				for attempt: int in int(stats.placement_attempts):
					var fraction: float = float(attempt)/maxi(1,int(stats.placement_attempts)-1)
					var point: Vector2 = wall.from+(wall.to-wall.from).normalized()*lerpf(margin,length-margin,fraction)+inward*(wall_placement_offset(stats,inward,kind)+size.y*.5)
					var approach: Vector2 = point+inward*(size.y*.5+float(stats.player_body_radius)+2.0*float(stats.wall_gap))
					if not _picture_inside(room,approach,Vector2.ONE*float(stats.player_body_radius)*2.0) or not point_clear(room,approach,float(stats.player_body_radius)): continue
					var anchors: Array[Vector2] = []
					if not _try_place(room,room.colliders.size(),kind,size,size,point,inward,anchors,stats): continue
					room.colliders[-1].set_meta("support_access_reservation",approach)
					count += 1; placed = true; break
				if placed: break


static func curtain_shower_slots(room: RoomDef, cabin_center: Vector2, stats: Resource = DEFAULT_STATS) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if dressing_purpose_for(room) != "shower": return result
	var nearest: Vector2 = cabin_center.clamp(room.bounds.position,room.bounds.end)
	if nearest.distance_to(cabin_center) < float(stats.curtain_shower_min_lift_distance): return result
	for prop: LevelColliderDef in room.colliders:
		if String(prop.editor_id).get_slice(":",3) != "shower_stall": continue
		var inward: Vector2 = prop.get_meta("wall_inward",Vector2.DOWN)
		var size: Vector2 = stats.curtain_shower_footprint
		var local_size: Vector2 = prop.size if absf(inward.y)>.5 else Vector2(prop.size.y,prop.size.x)
		if local_size.x < size.x or local_size.y < size.y: continue
		var yaw: float = {"north":0.0,"south":PI,"west":PI*.5,"east":-PI*.5}.get(String(prop.editor_id).get_slice(":",4),0.0)
		var point: Vector2 = prop.position
		var approach: Vector2 = point+inward*(local_size.y*.5+float(stats.support_approach_clearance)+float(stats.wall_gap))
		result.append({"point":point,"height":0.0,"yaw":yaw,"size":size,"prop_id":String(prop.editor_id),"slot_id":"curtain:%s"%prop.editor_id,"approach":approach,"placement":"shower","model_kind":"curtain_shower"})
	return result


static func _ensure_weapon_support(data: EndlessFloorData, rooms: Array[RoomDef], stats: Resource) -> void:
	var curtain: bool = posmod(data.floor_index-1,3)==0 and stats.supported_curtain_spawns
	var pipe: bool = posmod(data.floor_index-1,3)==1 and stats.shelf_only_pipe_spawns
	if not curtain and not pipe: return
	var surfaces: Dictionary = stats.curtain_support_surfaces if curtain else stats.support_surfaces
	var wanted: Vector2 = stats.curtain_shelf_footprint if curtain else stats.support_loot_footprint
	var clearance: float = stats.support_approach_clearance
	for room: RoomDef in rooms:
		if curtain and room.index<data.nodes.size() and bool(data.nodes[room.index].get_meta("endless_corridor",false)): continue
		var slots: Array[Dictionary] = support_slots(room,stats,surfaces)
		if curtain: slots.append_array(curtain_shower_slots(room,data.cabin_center,stats))
		for slot: Dictionary in slots:
			if Vector2(slot.size).x >= wanted.x and Vector2(slot.size).y >= wanted.y and _picture_inside(room,slot.approach,Vector2.ONE*clearance*2.0) and point_clear(room,slot.approach,clearance): return
	var candidates: Array[RoomDef] = rooms.duplicate()
	candidates.sort_custom(func(a: RoomDef,b: RoomDef)->bool:return a.bounds.get_center().distance_squared_to(data.cabin_center)>b.bounds.get_center().distance_squared_to(data.cabin_center))
	for room: RoomDef in candidates:
		var purpose: String = dressing_purpose_for(room)
		if purpose not in ["living","storage"]: continue
		for kind: String in surfaces:
			if not stats.purpose_decor.get(purpose,[]).has(kind): continue
			var size: Vector2 = footprint_for(kind,stats)*float(stats.support_carrier_min_scale)
			for wall: WallSegmentDef in room_wall_segments(room):
				var inward: Vector2 = wall_inward(room,wall)
				var length: float = wall.from.distance_to(wall.to)
				var margin: float = size.x*.5+float(stats.door_clearance)
				if inward==Vector2.ZERO or length<=margin*2.0: continue
				for attempt: int in int(stats.placement_attempts):
					var fraction: float = float(attempt)/maxi(1,int(stats.placement_attempts)-1)
					var point: Vector2 = wall.from+(wall.to-wall.from).normalized()*lerpf(margin,length-margin,fraction)+inward*(wall_placement_offset(stats,inward,kind)+size.y*.5)
					var approach: Vector2 = point+inward*(size.y*.5+clearance+float(stats.wall_gap))
					if not _picture_inside(room,approach,Vector2.ONE*clearance*2.0) or not point_clear(room,approach,clearance): continue
					# Late carriers must respect rugs already placed on the floor.
					var footprint: Vector2 = size if absf(inward.y)>.5 else Vector2(size.y,size.x)
					var picture: Rect2 = Rect2(point-footprint*.5,footprint)
					if room.colliders.any(func(prop: LevelColliderDef)->bool:return prop.floor_decoration and picture.intersects(Rect2(prop.position-prop.size*.5,prop.size))): continue
					var anchors: Array[Vector2] = []
					if _try_place(room,room.colliders.size(),kind,size,size,point,inward,anchors,stats): return


static func _kind_limit(kind: String, purpose: String, stats: Resource) -> int:
	return int(stats.semantic_repeat_limits.get(purpose,1)) if stats.semantic_repeatable.get(purpose,[]).has(kind) else 1


static func dressing_purpose_for(room: RoomDef) -> String:
	var purpose: String=String(room.get_meta("endless_room_purpose","storage"))
	return String(room.get_meta("endless_bath_variant","bath")) if purpose=="bath" else purpose


static func ordinary_bath_room_eligible(room: RoomDef) -> bool:
	var limit: Vector2 = room.get_meta("endless_bath_max_span",DEFAULT_SCHEME.bath_max_player_span * DEFAULT_SCHEME.room_player_width)
	return room.bounds.size.x <= limit.x + .001 and room.bounds.size.y <= limit.y + .001


static func bath_variant_for(room: RoomDef, seed: int, stats: Resource = DEFAULT_STATS) -> String:
	if not shower_room_eligible(room,stats): return "bath"
	if bool(room.get_meta("endless_service_shower",false)): return "shower"
	var random: RandomNumberGenerator=RandomNumberGenerator.new()
	random.seed=("bath:%s:%s:%d"%[room.bounds.position,room.bounds.size,seed]).hash()
	return "shower" if random.randf()<float(stats.public_shower_chance) else "bath"


static func shower_room_eligible(room: RoomDef, stats: Resource = DEFAULT_STATS) -> bool:
	var size: Vector2=room.bounds.size
	if size.x>stats.shower_room_max_size.x+.001 or size.y>stats.shower_room_max_size.y+.001: return false
	if size.x<stats.shower_room_min_size.x-.001 or size.y<stats.shower_room_min_size.y-.001: return false
	# A shower bank needs a real rectangular floor, not a concave bounding box.
	return _picture_inside(room,room.bounds.get_center(),size-Vector2.ONE*.002)


static func _furnish_public_shower(room: RoomDef, stats: Resource) -> bool:
	if not shower_room_eligible(room,stats): return false
	var scratch: RoomDef=room.duplicate(true)
	scratch.fogs.clear(); scratch.has_chest=false
	var original_count: int=scratch.colliders.size()
	var edges: Array[WallSegmentDef]=room_wall_segments(room).duplicate()
	edges.sort_custom(func(a: WallSegmentDef,b: WallSegmentDef)->bool:return a.from.distance_squared_to(a.to)>b.from.distance_squared_to(b.to))
	var horizontal: bool=room.bounds.size.x>=room.bounds.size.y
	for edge: WallSegmentDef in edges:
		var tangent: Vector2=(edge.to-edge.from).normalized()
		if (absf(tangent.x)>.5)!=horizontal: continue
		var inward: Vector2=wall_inward(room,edge)
		if inward==Vector2.ZERO: continue
		var size: Vector2=footprint_for("shower_stall",stats)
		var length: float=edge.from.distance_to(edge.to)
		var maximum: int=mini(int(stats.shower_stall_limit),floori((length-2.0*float(stats.shower_fixture_end_clearance)+float(stats.shower_stall_gap))/(size.x+float(stats.shower_stall_gap))))
		for count: int in range(maximum,1,-1):
			scratch.colliders.resize(original_count)
			if not _try_shower_wall_layout(scratch,edge,inward,count,stats): continue
			for index: int in range(original_count,scratch.colliders.size()): room.colliders.append(scratch.colliders[index])
			_add_shower_mats(room,stats)
			return true
	return false


static func _try_shower_wall_layout(room: RoomDef, edge: WallSegmentDef, inward: Vector2, count: int, stats: Resource) -> bool:
	var size: Vector2=footprint_for("shower_stall",stats)
	var margin: float=float(stats.shower_fixture_end_clearance)+size.x*.5
	var length: float=edge.from.distance_to(edge.to)
	if length<margin*2.0: return false
	var tangent: Vector2=(edge.to-edge.from).normalized()
	var original_count: int=room.colliders.size()
	var complete: bool=false
	# Slide the whole bank to preserve the door sweep at a side entry.
	for fraction: float in [.5,0.0,1.0]:
		room.colliders.resize(original_count)
		var start: float=lerpf(margin,length-margin-(count-1)*(size.x+float(stats.shower_stall_gap)),fraction)
		complete=true
		for index: int in count:
			# Avoid floating-point overlap at the flush back edge.
			var point: Vector2=edge.from+tangent*(start+index*(size.x+float(stats.shower_stall_gap)))+inward*(wall_placement_offset(stats,inward,"shower_stall")+size.y*.5+.001)
			if not _try_place(room,index,"shower_stall",size,size,point,inward,[],stats,true): complete=false; break
		if complete: break
	if not complete: return false
	var sink_count: int=0
	for candidate: Dictionary in _shower_wall_candidates(room,"metal_sink",-inward,stats):
		var sink_size: Vector2=footprint_for("metal_sink",stats)
		if _try_place(room,20+sink_count,"metal_sink",sink_size,sink_size,candidate.point,candidate.inward,[],stats,true): sink_count+=1
		if sink_count>=2: break
	if sink_count==0: return false
	for kind: String in ["towel_warmer","coat_hooks"]:
		var placed: bool=false
		for candidate: Dictionary in _shower_wall_candidates(room,kind,Vector2.ZERO,stats):
			if absf(Vector2(candidate.inward).dot(inward))>.5: continue
			var fixture_size: Vector2=footprint_for(kind,stats)
			if _try_place(room,30+room.colliders.size(),kind,fixture_size,fixture_size,candidate.point,candidate.inward,[],stats,true): placed=true; break
		if not placed: return false
	return true


static func _shower_wall_candidates(room: RoomDef, kind: String, required_inward: Vector2, stats: Resource) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	var size: Vector2=footprint_for(kind,stats)
	for edge: WallSegmentDef in room_wall_segments(room):
		var inward: Vector2=wall_inward(room,edge)
		if inward==Vector2.ZERO or (required_inward!=Vector2.ZERO and not inward.is_equal_approx(required_inward)): continue
		var tangent: Vector2=(edge.to-edge.from).normalized()
		var margin: float=size.x*.5+float(stats.wall_gap)
		var length: float=edge.from.distance_to(edge.to)
		if length<margin*2.0: continue
		for step: int in int(stats.placement_attempts):
			var fraction: float=float(step)/maxf(1.0,float(stats.placement_attempts)-1.0)
			result.append({"point":edge.from+tangent*lerpf(margin,length-margin,fraction)+inward*(wall_placement_offset(stats,inward,kind)+size.y*.5),"inward":inward})
	return result


static func _add_shower_mats(room: RoomDef, stats: Resource) -> void:
	var base: Vector2=footprint_for("rubber_mat",stats)
	var candidates: Array[Dictionary]=[]
	for prop: LevelColliderDef in room.colliders:
		if String(prop.editor_id).get_slice(":",3)!="shower_stall": continue
		var inward: Vector2=prop.get_meta("wall_inward",Vector2.DOWN)
		candidates.append({"point":prop.position,"inward":inward,"stall_id":String(prop.editor_id)})
	var placed: Array[Rect2]=[]
	for candidate: Dictionary in candidates:
		var inward: Vector2=candidate.inward
		var size: Vector2=base if absf(inward.y)>.5 else Vector2(base.y,base.x)
		var point: Vector2=candidate.point
		if not _picture_inside(room,point,size): continue
		var bounds: Rect2=Rect2(point-size*.5,size)
		var overlaps: bool=false
		for previous: Rect2 in placed:
			if bounds.intersects(previous): overlaps=true; break
		if overlaps: continue
		var mat: LevelColliderDef=_prop(room.index,1000+placed.size(),"rubber_mat",_wall_side(inward),point,size,size,inward)
		mat.disabled=true; mat.collision_layer=0; mat.floor_decoration=true
		mat.set_meta("shower_stall_id",candidate.stall_id)
		room.colliders.append(mat); placed.append(bounds)


static func _try_place(room: RoomDef, cluster: int, kind: String, base_size: Vector2, picture: Vector2, point: Vector2, inward: Vector2, anchors: Array[Vector2], stats: Resource, grouped: bool = false) -> bool:
	if kind == "laundry_rack" and inward.y < -.5: return false
	if kind == "lamp" and not near_wall_corner(room,point,stats): return false
	var footprint: Vector2 = base_size if absf(inward.y)>.5 else Vector2(base_size.y,base_size.x)
	var spacing: Array[Vector2] = []
	if not grouped: spacing = anchors
	if not _fits(room,point,footprint,spacing,stats,kind): return false
	anchors.append(point)
	room.colliders.append(_prop(room.index,cluster,kind,_wall_side(inward),point,footprint,picture,inward))
	return true


# Door jambs are segment endpoints too; a corner needs two perpendicular edges.
static func near_wall_corner(room: RoomDef, point: Vector2, stats: Resource=DEFAULT_STATS) -> bool:
	var edges: Array[WallSegmentDef]=room_wall_segments(room)
	for first: WallSegmentDef in edges:
		for corner: Vector2 in [first.from,first.to]:
			if point.distance_squared_to(corner)>float(stats.lamp_corner_reach)*float(stats.lamp_corner_reach): continue
			for second: WallSegmentDef in edges:
				if second==first: continue
				if absf((first.to-first.from).normalized().dot((second.to-second.from).normalized()))>.1: continue
				if corner.distance_squared_to(second.from)<.0001 or corner.distance_squared_to(second.to)<.0001:return true
	return false


static func _group_targets(room: RoomDef, kind: String, size: Vector2, stats: Resource) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var gap: float=float(stats.wall_gap) if kind=="shower_stall" else float(stats.semantic_group_gap)
	var anchor_kind: String = String(stats.semantic_group_anchors.get(kind,""))
	if anchor_kind.is_empty(): return result
	for index: int in range(room.colliders.size()-1,-1,-1):
		var anchor: LevelColliderDef = room.colliders[index]
		if not String(anchor.editor_id).begins_with(PREFIX) or String(anchor.editor_id).get_slice(":",3) != anchor_kind: continue
		var inward: Vector2 = anchor.get_meta("wall_inward",Vector2.ZERO)
		var previous: Vector2 = anchor.size if absf(inward.y)>.5 else Vector2(anchor.size.y,anchor.size.x)
		if stats.semantic_group_front.has(kind):
			result.append({"point":anchor.position+inward*((previous.y+size.y)*.5+gap),"inward":inward})
			return result
		var tangent: Vector2 = Vector2(-inward.y,inward.x)
		for direction: float in [-1.0,1.0]:
			var point: Vector2 = anchor.position+tangent*direction*((previous.x+size.x)*.5+gap)+inward*(size.y-previous.y)*.5
			var contact: Vector2 = point-inward*(wall_placement_offset(stats,inward,kind)+size.y*.5)
			for edge: WallSegmentDef in room_wall_segments(room):
				if not wall_inward(room,edge).is_equal_approx(inward): continue
				if Geometry2D.get_closest_point_to_segment(contact,edge.from,edge.to).distance_to(contact)>.02: continue
				var margin: float = size.x*.5+float(stats.door_clearance)
				if contact.distance_to(edge.from)<margin or contact.distance_to(edge.to)<margin: continue
				result.append({"point":point,"inward":inward}); break
		return result
	return result

static func _choose_kind(rng: RandomNumberGenerator, stats: Resource, purpose: String = "") -> String:
	if stats.semantic_room_dressing and not purpose.is_empty():
		var catalog: Array = stats.purpose_decor.get(purpose,[]).filter(func(kind:String)->bool:return kind != "plant" and not stats.semantic_floor_decor.get(purpose,[]).has(kind))
		if not catalog.is_empty(): return String(catalog[rng.randi_range(0,catalog.size()-1)])
	var kinds: Array = stats.decor_weights.keys()
	kinds.sort()
	var total: float = 0.0
	for kind: String in kinds: total += maxf(0.0, float(stats.decor_weights[kind]))
	var roll: float = rng.randf() * total
	for kind: String in kinds:
		roll -= maxf(0.0, float(stats.decor_weights[kind]))
		if roll < 0.0: return kind
	return "broom"


static func footprint_for(kind: String, stats: Resource = DEFAULT_STATS) -> Vector2:
	return stats.semantic_footprints[kind] if stats.semantic_footprints.has(kind) else stats.get(kind+"_footprint")


# Purpose is stable across active-route reindexing.
static func purpose_for(room: RoomDef, node: EndlessNode, seed: int, stats: Resource = DEFAULT_STATS) -> String:
	if bool(room.get_meta("apartment_entry",false)): return ["entry_green","entry_ochre","entry_blue"][posmod(seed,3)]
	if bool(room.get_meta("entry_neighbour",false)): return "living"
	if bool(room.get_meta("endless_service_shower",false)): return "bath"
	if node != null and (node.role in [EndlessNode.Role.START,EndlessNode.Role.HALL] or bool(node.get_meta("endless_corridor",false))): return "hall"
	var identity: String = "%s:%s:%d" % [room.bounds.position,room.bounds.size,seed]
	var purposes: Array = stats.room_purpose_weights.keys(); purposes.sort()
	# Excluding oversized baths must not change eligible rooms' random draws.
	if not ordinary_bath_room_eligible(room) and bath_variant_for(room,seed,stats) != "shower": purposes.erase("bath")
	var total: float = 0.0
	for key: String in purposes: total += maxf(0.0,float(stats.room_purpose_weights[key]))
	var random: RandomNumberGenerator = RandomNumberGenerator.new(); random.seed = identity.hash()
	var roll: float = random.randf()*total
	for key: String in purposes:
		roll -= maxf(0.0,float(stats.room_purpose_weights[key]))
		if roll < 0.0: return key
	return "storage"


static func _furnish_entry(room: RoomDef, stats: Resource) -> void:
	var pockets: Array=room.get_meta("entry_stair_pockets")
	for index: int in pockets.size():
		var stairs: Rect2=pockets[index]
		var guard: LevelColliderDef=_prop(room.index,index,"entry_stairs","north",stairs.get_center(),stairs.size,stairs.size,Vector2.DOWN)
		room.colliders.append(guard)
	var anchors: Array[Vector2]=[]
	for kind: String in ["garbage_chute","entry_mailboxes","chair","telephone_table"]:
		var size: Vector2=Vector2(2.1,.24) if kind=="entry_mailboxes" else footprint_for(kind,stats)
		var placed: bool=false
		for wall: WallSegmentDef in room_wall_segments(room):
			if wall.from.distance_to(wall.to)<size.x+float(stats.door_clearance)*2.0: continue
			var inward: Vector2=wall_inward(room,wall)
			var footprint: Vector2=size if absf(inward.y)>.5 else Vector2(size.y,size.x)
			for fraction: float in [.25,.75,.5]:
				var point: Vector2=wall.from.lerp(wall.to,fraction)+inward*(footprint.dot(inward.abs())*.5+wall_contact_depth(stats,inward)+float(stats.wall_gap))
				if _try_place(room,room.colliders.size(),kind,footprint,footprint,point,inward,anchors,stats,true):
					if kind=="telephone_table":room.colliders[-1].set_meta("entry_ashtray",true)
					placed=true;break
			if placed:break


static func _move_plant_to_entry(data: EndlessFloorData, stats: Resource) -> void:
	if posmod(data.seed,2)==0:return
	var rooms: Array[RoomDef]=data.level.rooms
	var entry: RoomDef=null
	var pots: Array[Dictionary]=[]
	for room: RoomDef in rooms:
		if bool(room.get_meta("apartment_entry",false)): entry=room
		for prop: LevelColliderDef in room.colliders:
			if String(prop.editor_id).get_slice(":",3)=="plant": pots.append({"room":room,"point":prop.position,"prop":prop})
	if entry==null:return
	for pot: Dictionary in pots:
		if pot.prop.has_meta("plant_pickup_type"):continue
		var remaining: Array[Dictionary]=pots.duplicate();remaining.erase(pot)
		var candidate: Dictionary=_plant_wall_candidate(entry,data.seed,stats,remaining)
		if candidate.is_empty():continue
		remaining.append(candidate)
		if _plant_pair_count(remaining)>int(stats.plant_max_adjacent_pairs):continue
		(pot.room as RoomDef).colliders.erase(pot.prop)
		_place_planned_plant(candidate,0,String(pot.prop.get_meta("plant_variant","plant_fern")),stats)
		return

static func wall_contact_depth(stats: Resource = DEFAULT_STATS, inward: Vector2 = Vector2.ZERO) -> float:
	# Height projection applies only to legacy painted walls, not 3D wall faces.
	var visible_inset: float = float(stats.wall_depth)*maxf(0.0,maxf(inward.x,-inward.y)) \
		if bool(stats.projected_wall_footprint) else 0.0
	return maxf(visible_inset,maxf(float(stats.wall_foot_depth),float(stats.wall_collision_thickness)*.5))

static func wall_placement_offset(stats: Resource = DEFAULT_STATS, inward: Vector2 = Vector2.ZERO, kind: String = "") -> float:
	if kind == "laundry_rack": return wall_contact_depth(stats,inward)+float(stats.laundry_rack_wall_gap)
	return wall_contact_depth(stats,inward)+float(stats.shower_wall_gap if kind=="shower_stall" else stats.wall_gap)

static func room_wall_segments(room: RoomDef) -> Array[WallSegmentDef]:
	# Shared-line physics has one owner, but both rooms retain inward wall faces.
	var edges: Array[WallSegmentDef] = room.get_meta("endless_visual_walls", room.wall_segments)
	return edges

static func wall_inward(room: RoomDef, edge: WallSegmentDef) -> Vector2:
	var tangent: Vector2 = (edge.to - edge.from).normalized()
	if tangent == Vector2.ZERO:
		return Vector2.ZERO
	var normal: Vector2 = Vector2(-tangent.y, tangent.x)
	for fraction: float in [0.5, 0.25, 0.75]:
		var point: Vector2 = edge.from.lerp(edge.to, fraction)
		var positive: bool = room.contains(point + normal * float(DEFAULT_STATS.wall_probe_distance))
		var negative: bool = room.contains(point - normal * float(DEFAULT_STATS.wall_probe_distance))
		if positive != negative:
			return normal if positive else -normal
	return Vector2.ZERO

static func _wall_side(inward: Vector2) -> String:
	if inward.y > 0.5: return "north"
	if inward.y < -0.5: return "south"
	return "west" if inward.x > 0.5 else "east"

static func _add_wall_feet(room: RoomDef, stats: Resource) -> void:
	var edges: Array[WallSegmentDef] = room_wall_segments(room)
	for edge_index: int in edges.size():
		var edge: WallSegmentDef = edges[edge_index]
		var inward: Vector2 = wall_inward(room, edge)
		if inward == Vector2.ZERO:
			continue
		var tangent: Vector2 = (edge.to - edge.from).normalized()
		var prop: LevelColliderDef = LevelColliderDef.new()
		prop.editor_id = StringName("%s%d:%d" % [WALL_FOOT_PREFIX, room.index, edge_index])
		var contact_depth: float = wall_contact_depth(stats,inward)
		prop.position = (edge.from + edge.to) * 0.5 + inward * contact_depth * 0.5
		prop.size = tangent.abs() * edge.from.distance_to(edge.to) + inward.abs() * contact_depth
		prop.collision_layer = 1
		prop.set_meta("wall_inward", inward)
		room.colliders.append(prop)

static func _relocate_encounters(room: RoomDef, stats: Resource) -> void:
	# Physical skirting thickness is independent of the wall's visual height.
	var reserved: Array[Vector2] = []
	if room.has_chest:
		room.chest_position = _safe_encounter_position(room, room.chest_position,
			float(stats.wall_foot_chest_clearance), reserved, stats)
		reserved.append(room.chest_position)
	for fog: FogPlacementDef in room.fogs:
		fog.position = _safe_encounter_position(room, fog.position,
			float(stats.wall_foot_actor_clearance), reserved, stats)
		reserved.append(fog.position)

static func _safe_encounter_position(room: RoomDef, original: Vector2, clearance: float, reserved: Array[Vector2], stats: Resource) -> Vector2:
	if _encounter_position_clear(room, original, clearance, reserved, float(stats.actor_clearance) * 2.0):
		return original
	var candidate: Vector2 = original
	for _pass: int in int(stats.placement_attempts):
		var moved: bool = false
		for collider: LevelColliderDef in room.colliders:
			if not String(collider.editor_id).begins_with(WALL_FOOT_PREFIX):
				continue
			var offset: Vector2 = candidate - collider.position
			var half: Vector2 = collider.effective_collision_size() * 0.5 + Vector2.ONE * clearance
			if absf(offset.x) > half.x or absf(offset.y) > half.y:
				continue
			var normal: Vector2 = collider.get_meta("wall_inward")
			candidate += normal * (half.dot(normal.abs()) - offset.dot(normal) + 0.001)
			moved = true
		if not moved:
			break
	if _encounter_position_clear(room, candidate, clearance, reserved):
		return candidate
	# Search actual floor rectangles when concave corners have competing normals.
	var best: Vector2 = original
	var best_distance: float = INF
	var packed: Vector2 = original
	var packed_separation: float = -INF
	var packed_distance: float = INF
	var step: float = float(stats.encounter_search_step)
	var search_areas: Array[Rect2] = room.areas.duplicate()
	if not search_areas.has(room.bounds):
		search_areas.append(room.bounds)
	for area: Rect2 in search_areas:
		var inner: Rect2 = area.grow(-clearance)
		if inner.size.x < 0.0 or inner.size.y < 0.0:
			continue
		var xs: Array[float] = []
		var ys: Array[float] = []
		for xi: int in ceili(inner.size.x / step) + 1:
			xs.append(inner.position.x + minf(xi * step, inner.size.x))
		for yi: int in ceili(inner.size.y / step) + 1:
			ys.append(inner.position.y + minf(yi * step, inner.size.y))
		# Include exact obstacle boundaries so a narrow safe strip cannot miss the grid.
		for collider: LevelColliderDef in room.colliders:
			if collider.disabled or collider.collision_layer == 0:
				continue
			var obstacle: Rect2 = Rect2(collider.position - collider.effective_collision_size() * 0.5,
				collider.effective_collision_size()).grow(clearance + 0.001)
			for x: float in [obstacle.position.x, obstacle.end.x]:
				if x >= inner.position.x and x <= inner.end.x:
					xs.append(x)
			for y: float in [obstacle.position.y, obstacle.end.y]:
				if y >= inner.position.y and y <= inner.end.y:
					ys.append(y)
		for y: float in ys:
			for x: float in xs:
				var point: Vector2 = Vector2(x, y)
				var distance: float = original.distance_squared_to(point)
				if _encounter_position_clear(room, point, clearance, reserved):
					if distance < best_distance:
						best_distance = distance
						best = point
				elif _encounter_position_clear(room, point, clearance, reserved, float(stats.actor_clearance) * 2.0):
					# Spacing may shrink to two actor radii, but wall clearance is never relaxed.
					var separation: float = INF
					for occupied: Vector2 in reserved:
						separation = minf(separation, point.distance_to(occupied))
					if separation > packed_separation or (is_equal_approx(separation, packed_separation) and distance < packed_distance):
						packed = point
						packed_separation = separation
						packed_distance = distance
	return best if best_distance < INF else packed

static func _encounter_position_clear(room: RoomDef, point: Vector2, clearance: float, reserved: Array[Vector2], minimum_separation: float = -1.0) -> bool:
	if not _picture_inside(room, point, Vector2.ONE * clearance * 2.0) or not point_clear(room, point, clearance):
		return false
	if not door_sweep_clear(room,point,Vector2.ONE*clearance*2.0): return false
	var separation: float = clearance * 2.0 if minimum_separation < 0.0 else minimum_separation
	for occupied: Vector2 in reserved:
		if point.distance_to(occupied) < separation:
			return false
	return true

static func _fits(room: RoomDef, point: Vector2, size: Vector2, anchors: Array[Vector2], stats: Resource, kind: String = "") -> bool:
	if not _picture_inside(room, point, size):
		return false
	if not door_sweep_clear(room,point,size,stats): return false
	for port: Dictionary in room.get_meta("endless_sealed_ports", []):
		var along: Vector2 = port.get("axis",Vector2.DOWN if bool(port.horizontal_travel) else Vector2.RIGHT)
		var across: Vector2 = along.orthogonal()
		var offset: Vector2 = point - Vector2(port.position)
		var width: float = float(port.width) if port.has("width") else DoorDef.new().passage_width
		var side_limit: float = (width + float(stats.sealed_port_clearance) + size.dot(along.abs())) * 0.5
		var depth_limit: float = float(port.get("reservation_half_depth",stats.wall_foot_depth)) \
			+ float(stats.sealed_port_clearance) + size.dot(across.abs())*.5
		if absf(offset.dot(along)) < side_limit and absf(offset.dot(across)) < depth_limit:
			return false
	if room.has_chest and point.distance_to(room.chest_position) < float(stats.chest_clearance) + size.length() * 0.5:
		return false
	for fog: FogPlacementDef in room.fogs:
		if point.distance_to(fog.position) < float(stats.encounter_clearance) + size.length() * 0.5:
			return false
	for anchor: Vector2 in anchors:
		if anchor.distance_to(point) < float(stats.cluster_clearance):
			return false
	var footprint: Rect2 = Rect2(point - size * 0.5, size)
	for edge: WallSegmentDef in room_wall_segments(room):
		var physical_wall: Rect2 = Rect2(edge.from,edge.to-edge.from).abs().grow(float(stats.wall_collision_thickness)*.5)
		if footprint.intersects(physical_wall):
			return false
	for collider: LevelColliderDef in room.colliders:
		if collider.disabled or collider.collision_layer == 0:
			continue
		if collider.has_meta("support_access_reservation"):
			var access: Vector2 = collider.get_meta("support_access_reservation")
			if footprint.intersects(Rect2(access-Vector2.ONE*float(stats.player_body_radius),Vector2.ONE*float(stats.player_body_radius)*2.0)): return false
		var padding: float = 0.0 if String(collider.editor_id).begins_with(WALL_FOOT_PREFIX) else float(stats.actor_clearance)
		# Adjacent cubicles share a partition gap; the front walking lane remains reserved.
		if kind=="shower_stall" and String(collider.editor_id).get_slice(":",3)=="shower_stall":padding=0.0
		# Wall-mounted fixtures share a lane and need no extra actor-radius gap.
		if kind in ["towel_warmer","coat_hooks"] and String(collider.editor_id).get_slice(":",3) in ["towel_warmer","coat_hooks"]:
			padding=float(stats.wall_gap)
		var obstacle: Rect2 = Rect2(collider.position - collider.effective_collision_size() * 0.5, collider.effective_collision_size()).grow(padding)
		if footprint.intersects(obstacle):
			return false
	return _preserves_traversal(room, footprint, stats)


# Preserve existing free regions, not an assumed initially connected room.
# Grid padding reserves the requested walking width plus half a grid cell.
static func _preserves_traversal(room: RoomDef, footprint: Rect2, stats: Resource) -> bool:
	if bool(room.get_meta("endless_inactive_shell", false)): return true
	# Simple obstacle arrangements cannot split the floor; avoid rasterizing those cases.
	var reach: float = float(stats.player_body_radius) * float(stats.traversal_width_multiplier) * 2.0 + float(stats.traversal_grid_step)
	var vicinity: Rect2 = footprint.grow(reach)
	var nearby_props: int = 0
	var simple_props: bool = true
	for prop: LevelColliderDef in room.colliders:
		if prop.disabled or prop.collision_layer == 0 or String(prop.editor_id).begins_with(WALL_FOOT_PREFIX): continue
		if prop.shape_kind != LevelColliderDef.ShapeKind.RECTANGLE or not is_zero_approx(prop.rotation):
			nearby_props += 2; simple_props = false; continue
		if vicinity.intersects(Rect2(prop.position-prop.effective_collision_size()*.5,prop.effective_collision_size())):
			nearby_props += 1
	var nearby_walls: Array[WallSegmentDef] = []
	for edge: WallSegmentDef in room_wall_segments(room):
		if vicinity.intersects(Rect2(edge.from,edge.to-edge.from).abs().grow(float(stats.wall_collision_thickness)*.5)):
			nearby_walls.append(edge)
	if nearby_props == 0 and nearby_walls.size() < 2: return true
	if nearby_props == 1 and nearby_walls.is_empty() and simple_props: return true
	if nearby_props == 0 and nearby_walls.size() == 2:
		var first: WallSegmentDef = nearby_walls[0]; var second: WallSegmentDef = nearby_walls[1]
		if first.from.is_equal_approx(second.from) or first.from.is_equal_approx(second.to) or first.to.is_equal_approx(second.from) or first.to.is_equal_approx(second.to): return true
	var grid: Dictionary = _traversal_grid(room, stats)
	var before: PackedByteArray = grid.open
	var after: PackedByteArray = before.duplicate()
	var removed: PackedInt32Array = _block_traversal_rect(after, footprint.grow(grid.padding), grid)
	if removed.is_empty(): return true
	# Each narrow arm must retain at least one usable cell.
	for group: PackedInt32Array in grid.areas:
		var survives: bool = group.is_empty()
		for cell: int in group:
			if after[cell] != 0: survives = true; break
		if not survives: return false
	for cell: int in grid.doors:
		if after[cell] == 0: return false
	# Newly separated fragments touch removed cells; flood only their boundary targets.
	var borders: Dictionary = {}
	var labels: PackedInt32Array = grid.labels
	for cell: int in removed:
		for neighbour: int in _traversal_neighbours(cell, grid.width, after.size()):
			if after[neighbour] == 0: continue
			var label: int = labels[neighbour]
			if not borders.has(label): borders[label] = {}
			borders[label][neighbour] = true
	for targets: Dictionary in borders.values():
		if targets.size() < 2: continue
		var queue: PackedInt32Array = PackedInt32Array([int(targets.keys()[0])])
		var seen: PackedByteArray = PackedByteArray(); seen.resize(after.size())
		seen[queue[0]] = 1
		var cursor: int = 0
		while cursor < queue.size() and not targets.is_empty():
			var cell: int = queue[cursor]; cursor += 1
			targets.erase(cell)
			for neighbour: int in _traversal_neighbours(cell, grid.width, after.size()):
				if after[neighbour] == 0 or seen[neighbour] != 0: continue
				seen[neighbour] = 1; queue.append(neighbour)
		if not targets.is_empty(): return false
	return true


static func _traversal_grid(room: RoomDef, stats: Resource) -> Dictionary:
	var step: float = float(stats.traversal_grid_step)
	var padding: float = float(stats.player_body_radius) * float(stats.traversal_width_multiplier) + step * .5
	# Cache geometry values, not identities: moved or disabled props change the grid.
	var signature: Array = [room.bounds, room.areas, room.walkable_polygon, room.get_meta("endless_door_sweeps", []), step, padding]
	for prop: LevelColliderDef in room.colliders:
		signature.append([prop.position, prop.rotation, prop.effective_collision_size(), prop.disabled, prop.collision_layer, prop.shape_kind, prop.points, prop.filled, prop.closed, prop.thickness])
	for edge: WallSegmentDef in room_wall_segments(room): signature.append([edge.from, edge.to])
	var key: int = hash(signature)
	var cached: Dictionary = room.get_meta("endless_traversal_grid", {})
	if cached.get("key", -1) == key: return cached
	var width: int = maxi(1, ceili(room.bounds.size.x / step))
	var height: int = maxi(1, ceili(room.bounds.size.y / step))
	var grid: Dictionary = {"key":key, "width":width, "step":step, "origin":room.bounds.position, "padding":padding}
	var open: PackedByteArray = PackedByteArray(); open.resize(width * height)
	var points: PackedVector2Array = PackedVector2Array(); points.resize(open.size())
	for cell: int in open.size():
		var point: Vector2 = room.bounds.position + Vector2(cell % width + .5, floori(float(cell) / width) + .5) * step
		points[cell] = point
		if room.contains(point): open[cell] = 1
	for edge: WallSegmentDef in room_wall_segments(room):
		_block_traversal_rect(open, Rect2(edge.from, edge.to-edge.from).abs().grow(float(stats.wall_collision_thickness) * .5 + padding), grid)
	for prop: LevelColliderDef in room.colliders:
		if prop.disabled or prop.collision_layer == 0: continue
		# Open partitions block their edges, not the entire cubicle rectangle.
		if prop.shape_kind == LevelColliderDef.ShapeKind.POLYGON and not prop.filled:
			var count: int = prop.points.size() if prop.closed else prop.points.size()-1
			for index: int in count:
				var a: Vector2 = prop.position + prop.points[index].rotated(prop.rotation)
				var b: Vector2 = prop.position + prop.points[(index+1)%prop.points.size()].rotated(prop.rotation)
				_block_traversal_rect(open, Rect2(a,b-a).abs().grow(prop.thickness*.5 + padding), grid)
			continue
		var size: Vector2 = prop.effective_collision_size()
		var rotated_size: Vector2 = Vector2(absf(cos(prop.rotation))*size.x+absf(sin(prop.rotation))*size.y, absf(sin(prop.rotation))*size.x+absf(cos(prop.rotation))*size.y)
		_block_traversal_rect(open, Rect2(prop.position-rotated_size*.5,rotated_size).grow(padding), grid)
	var labels: PackedInt32Array = PackedInt32Array(); labels.resize(open.size()); labels.fill(-1)
	var label: int = 0
	for start: int in open.size():
		if open[start] == 0 or labels[start] >= 0: continue
		var queue: PackedInt32Array = PackedInt32Array([start]); labels[start] = label
		var cursor: int = 0
		while cursor < queue.size():
			var cell: int = queue[cursor]; cursor += 1
			for neighbour: int in _traversal_neighbours(cell, width, open.size()):
				if open[neighbour] == 0 or labels[neighbour] >= 0: continue
				labels[neighbour] = label; queue.append(neighbour)
		label += 1
	var area_groups: Array[PackedInt32Array] = []
	for area: Rect2 in room.areas:
		var group: PackedInt32Array = PackedInt32Array()
		for cell: int in open.size():
			if open[cell] != 0 and area.has_point(points[cell]): group.append(cell)
		area_groups.append(group)
	var doors: PackedInt32Array = PackedInt32Array()
	for door: Dictionary in room.get_meta("endless_door_sweeps", []):
		var nearest: int = -1; var distance: float = INF
		for cell: int in open.size():
			if open[cell] == 0: continue
			var candidate: float = points[cell].distance_squared_to(Vector2(door.position))
			if candidate < distance: nearest = cell; distance = candidate
		if nearest >= 0: doors.append(nearest)
	grid.merge({"open":open, "labels":labels, "areas":area_groups, "doors":doors})
	room.set_meta("endless_traversal_grid", grid)
	return grid


static func _block_traversal_rect(open: PackedByteArray, obstacle: Rect2, grid: Dictionary) -> PackedInt32Array:
	var removed: PackedInt32Array = PackedInt32Array()
	var step: float = grid.step; var origin: Vector2 = grid.origin; var width: int = grid.width
	var first: Vector2i = Vector2i(ceili((obstacle.position.x-origin.x)/step-.5), ceili((obstacle.position.y-origin.y)/step-.5))
	var last: Vector2i = Vector2i(floori((obstacle.end.x-origin.x)/step-.5), floori((obstacle.end.y-origin.y)/step-.5))
	for y: int in range(maxi(0,first.y), mini(floori(float(open.size())/width)-1,last.y)+1):
		for x: int in range(maxi(0,first.x), mini(width-1,last.x)+1):
			var cell: int = y * width + x
			if open[cell] != 0: open[cell] = 0; removed.append(cell)
	return removed


static func _traversal_neighbours(cell: int, width: int, count: int) -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	if cell % width > 0: result.append(cell-1)
	if cell % width < width-1: result.append(cell+1)
	if cell >= width: result.append(cell-width)
	if cell+width < count: result.append(cell+width)
	return result

static func _picture_inside(room: RoomDef, point: Vector2, size: Vector2) -> bool:
	for offset: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2.ZERO]:
		if not room.contains(point + offset * size * 0.5):
			return false
	return true

static func _prop(room: int, cluster: int, kind: String, side: String, point: Vector2, footprint: Vector2, picture: Vector2, inward: Vector2) -> LevelColliderDef:
	var prop: LevelColliderDef = LevelColliderDef.new()
	prop.editor_id = StringName("%s%d:%d:%s:%s" % [PREFIX, room, cluster, kind, side])
	prop.display_name = {"rack":"Стеллаж", "cabinet":"Шкаф", "broom":"Метла", "lamp":"Торшер",
		"table":"Стол", "bench":"Скамья", "dark_crate":"Деревянный ящик", "metal_locker":"Металлический шкаф",
		"radiator":"Батарея", "chair":"Стул", "rolled_rug":"Свёрнутый ковёр", "plant":"Комнатное растение",
		"bathtub":"Ванна", "sink":"Умывальник", "metal_sink":"Металлическая раковина", "coat_hooks":"Вешалка для одежды", "rubber_mat":"Резиновый коврик", "water_heater":"Бойлер", "laundry_basket":"Корзина для белья",
		"sofa":"Диван", "tv":"Телевизор", "wall_unit":"Советская стенка", "coffee_table":"Журнальный столик",
		"armchair":"Кресло", "stool":"Табурет", "wall_mirror":"Зеркало", "utility_cart":"Тележка",
		"mop":"Швабра", "gramophone":"Граммофон", "telephone_table":"Тумба с телефоном",
		"sewing_table":"Швейная машинка", "radio_console":"Радиола", "coat_stand":"Вешалка",
		"washboard_bucket":"Ведро со стиральной доской", "basin_stack":"Стопка тазов",
		"runner_blue":"Ковровая дорожка", "woven_mat":"Тканый коврик", "laundry_rack":"Раскладная сушилка для белья",
		"metal_shelf":"Складской стеллаж", "garbage_chute":"Мусоропровод"}.get(kind, kind)
	prop.position = point
	prop.size = footprint
	if kind=="shower_stall":
		prop.shape_kind=LevelColliderDef.ShapeKind.POLYGON
		prop.filled=false; prop.closed=false
		prop.thickness=float(DEFAULT_STATS.shower_partition_thickness)
		var half: Vector2=Vector2(picture.x,picture.y)*.5
		var points: PackedVector2Array=PackedVector2Array([Vector2(-half.x+prop.thickness*.5,half.y),Vector2(-half.x+prop.thickness*.5,-half.y),Vector2(half.x-prop.thickness*.5,-half.y),Vector2(half.x-prop.thickness*.5,half.y)])
		for index: int in points.size(): points[index]=points[index].rotated(Vector2.DOWN.angle_to(inward))
		prop.points=points
	prop.visual_asset = {"rack":RACK, "cabinet":CABINET, "lamp":LAMP}.get(kind, "")
	prop.visual_view_count = 1
	prop.visual_scale = picture / footprint
	prop.visual_offset = Vector2(0, -(picture.y - footprint.y) * 0.5 / footprint.y)
	prop.collision_layer = 1
	prop.set_meta("wall_inward", inward)
	return prop
static func point_clear(room: RoomDef, point: Vector2, padding: float = 0.0) -> bool:
	for collider: LevelColliderDef in room.colliders:
		if collider.disabled or collider.collision_layer == 0:
			continue
		var local: Vector2 = (point - collider.position).rotated(-collider.rotation)
		var half: Vector2 = collider.effective_collision_size() * 0.5 + Vector2.ONE * padding
		if absf(local.x) <= half.x and absf(local.y) <= half.y:
			return false
	return true

static func blocking_segments(room: RoomDef) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for collider: LevelColliderDef in room.colliders:
		if collider.disabled or collider.collision_layer == 0:
			continue
		if collider.shape_kind==LevelColliderDef.ShapeKind.POLYGON and not collider.filled:
			var count: int=collider.points.size() if collider.closed else collider.points.size()-1
			for index: int in count:
				result.append(PackedVector2Array([collider.position+collider.points[index].rotated(collider.rotation),collider.position+collider.points[(index+1)%collider.points.size()].rotated(collider.rotation)]))
			continue
		if collider.shape_kind!=LevelColliderDef.ShapeKind.RECTANGLE: continue
		var half: Vector2 = collider.effective_collision_size() * 0.5
		var corners: PackedVector2Array = PackedVector2Array()
		for direction: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			corners.append(collider.position + (direction * half).rotated(collider.rotation))
		for index: int in 4:
			result.append(PackedVector2Array([corners[index], corners[(index + 1) % 4]]))
	return result
