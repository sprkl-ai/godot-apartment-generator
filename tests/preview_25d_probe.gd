extends SceneTree
var failures: Array[String] = []
var checks: int = 0
func _initialize() -> void:
	call_deferred("_run")
func expect(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); push_error(message)
func _run() -> void:
	var main: Control = load("res://demo/main.tscn").instantiate()
	root.add_child(main); current_scene = main
	for i: int in 10: await process_frame
	main.seed_input.text = "42"; main.floor_input.value = 2; main._generate()
	var fingerprint: String = JSON.stringify(main.model.layout_document(),"",true,true).sha256_text()
	main._open_preview()
	for i: int in 12: await process_frame
	var preview: Node3D = current_scene as Node3D
	expect(preview != null,"2.5D button changes scene")
	if preview != null:
		expect(preview.model.seed_value == 42 and preview.model.floor_number == 2,"preview retains seed/floor")
		expect(JSON.stringify(preview.model.layout_document(),"",true,true).sha256_text() == fingerprint,"2D and 3D use same layout")
		var geometry: Node3D = preview.get_child(0)
		expect(geometry._geometry.get_child_count() > 50,"3D mesh geometry exists")
		var factory: Script = load("res://examples/level_geometry_3d.gd")
		expect(factory.world_point(Vector2(2,-4),3) == Vector3(2,3,-4),"2D to 3D coordinate convention")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/preview-25d.png")
		var old_size: float = preview.camera.size
		var wheel: InputEventMouseButton = InputEventMouseButton.new(); wheel.button_index = MOUSE_BUTTON_WHEEL_UP; wheel.pressed = true
		preview._unhandled_input(wheel); expect(preview.camera.size < old_size,"3D zoom")
		var press: InputEventMouseButton = InputEventMouseButton.new(); press.button_index = MOUSE_BUTTON_LEFT; press.pressed = true
		preview._unhandled_input(press)
		var motion: InputEventMouseMotion = InputEventMouseMotion.new(); motion.relative = Vector2(30,0)
		var yaw: float = preview.yaw; preview._unhandled_input(motion); expect(preview.yaw != yaw,"3D orbit")
		# Rebuild with opt-in physics; old geometry must leave the active tree.
		var old: Node3D = geometry._geometry
		geometry.create_collisions = true; geometry.build(preview.model.data)
		expect(old.get_parent() == null,"rebuild detaches old geometry")
		expect(geometry._geometry.find_children("*","StaticBody3D",true,false).size() > 0,"optional mesh collisions")
		var boxes: int = 0; var box_dimensions_match: bool = true; var box_poses_match: bool = true
		for mesh: Node in geometry._geometry.get_children():
			if not mesh is MeshInstance3D or not mesh.mesh is BoxMesh: continue
			var collider: CollisionShape3D = mesh.get_child(0).get_child(0)
			boxes += 1
			box_dimensions_match = box_dimensions_match and collider.shape is BoxShape3D and collider.shape.size == mesh.mesh.size
			box_poses_match = box_poses_match and collider.global_transform.is_equal_approx(mesh.global_transform)
		expect(boxes > 0 and box_dimensions_match,"box collisions use matching primitive dimensions")
		expect(box_poses_match,"box collisions preserve world rotation and position")
		var floor_shapes: int = 0
		for collider: Node in geometry._geometry.find_children("*","CollisionShape3D",true,false):
			if collider.shape is ConcavePolygonShape3D: floor_shapes += 1
		expect(floor_shapes > 0,"nonrectangular floors retain mesh collisions")
		await physics_frame
		await physics_frame
		var spawn: Vector3 = factory.world_point(preview.model.spawn_point())
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(spawn+Vector3.UP*8,spawn-Vector3.UP)
		var hit: Dictionary = preview.get_world_3d().direct_space_state.intersect_ray(query)
		expect(not hit.is_empty(),"floor collides from above")
		expect(not hit.is_empty() and hit.normal.y > .9,"floor collision normal faces upwards")
		change_scene_to_file("res://demo/main.tscn")
		for i: int in 10: await process_frame
		expect(current_scene.model.seed_value == 42 and current_scene.model.floor_number == 2,"return preserves seed/floor")
	var file: FileAccess = FileAccess.open("res://docs/preview-25d-checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  ")+"\n"); file.close()
	print("LAB_25D_CHECKS ",failures)
	quit(0 if failures.is_empty() else 1)
