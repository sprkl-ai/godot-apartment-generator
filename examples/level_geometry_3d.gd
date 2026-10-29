extends Node3D
## Example renderer: replace materials/meshes without changing generation.
## Final Godot 2D (x,y) maps to 3D (x,height,z=y); never flip Y a second time.
@export var wall_height: float = 2.6
@export var wall_thickness: float = .14
@export var furniture_height: float = .75
@export var create_collisions: bool = false
var _geometry: Node3D
var _materials: Dictionary = {}

static func world_point(point: Vector2, height: float = 0) -> Vector3:
	return Vector3(point.x,height,point.y)

func build(floor_data: RefCounted) -> void:
	if is_instance_valid(_geometry):
		remove_child(_geometry); _geometry.queue_free()
	_geometry = Node3D.new(); _geometry.name = "GeneratedGeometry"; add_child(_geometry)
	for room: RoomDef in floor_data.level.rooms:
		var colour: Color = Color("475666")
		if room.index == 0: colour = Color("a77b42")
		elif room.get_meta("apartment_entry",false): colour = Color("497c73")
		elif room.get_meta("endless_room_purpose","") == "bath": colour = Color("426e87")
		var outlines: Array[PackedVector2Array] = []
		for area: Rect2 in room.areas:
			var polygon: PackedVector2Array = PackedVector2Array([area.position,area.position+Vector2(area.size.x,0),area.end,area.position+Vector2(0,area.size.y)])
			var merged: bool = false
			for i: int in outlines.size():
				var result: Array[PackedVector2Array] = Geometry2D.merge_polygons(outlines[i],polygon)
				if result.size() == 1: outlines[i] = result[0]; merged = true; break
			if not merged: outlines.append(polygon)
		for polygon: PackedVector2Array in outlines: _floor(polygon,colour)
		for wall: WallSegmentDef in room.wall_segments: _wall(wall.from,wall.to,wall_height,Color("9ba6b0"))
		for prop: LevelColliderDef in room.colliders:
			if prop.disabled or prop.collision_layer == 0 or prop.floor_decoration: continue
			if String(prop.editor_id).begins_with("endless_wall_foot:"): continue
			if prop.shape_kind == LevelColliderDef.ShapeKind.POLYGON and not prop.filled:
				var count: int = prop.points.size() if prop.closed else prop.points.size()-1
				for i: int in count:
					_wall(prop.position+prop.points[i].rotated(prop.rotation),prop.position+prop.points[(i+1)%prop.points.size()].rotated(prop.rotation),furniture_height,Color("718a94"))
			else:
				var size: Vector2 = prop.effective_collision_size()
				_box(Vector3(size.x,furniture_height,size.y),world_point(prop.position,furniture_height*.5),-prop.rotation,Color("b79165"))

func _material(colour: Color) -> StandardMaterial3D:
	if not _materials.has(colour):
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = colour; material.roughness = .92
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[colour] = material
	return _materials[colour]

func _box(size: Vector3, point: Vector3, yaw: float, colour: Color) -> void:
	var node: MeshInstance3D = MeshInstance3D.new(); var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size; node.mesh = mesh; node.material_override = _material(colour)
	_geometry.add_child(node); node.position = point; node.rotation.y = yaw
	if create_collisions:
		var body: StaticBody3D = StaticBody3D.new()
		var collider: CollisionShape3D = CollisionShape3D.new()
		var shape: BoxShape3D = BoxShape3D.new(); shape.size = size
		node.add_child(body); body.add_child(collider); collider.shape = shape

func _wall(a: Vector2, b: Vector2, height: float, colour: Color) -> void:
	var delta: Vector2 = b-a
	_box(Vector3(delta.length(),height,wall_thickness),world_point((a+b)*.5,height*.5),-delta.angle(),colour)

func _floor(polygon: PackedVector2Array, colour: Color) -> void:
	var indices: PackedInt32Array = Geometry2D.triangulate_polygon(polygon)
	var surface: SurfaceTool = SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in indices.size():
		# Godot uses clockwise front faces; x/y->x/z already changes handedness.
		surface.set_normal(Vector3.UP); surface.add_vertex(world_point(polygon[indices[i]],-.015))
	var node: MeshInstance3D = MeshInstance3D.new(); node.mesh = surface.commit()
	node.material_override = _material(colour); _geometry.add_child(node)
	if create_collisions: node.create_trimesh_collision()
