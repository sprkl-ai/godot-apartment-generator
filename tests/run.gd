extends SceneTree
const Model = preload("res://demo/lab_model.gd")
var checks: int = 0
var failures: Array[String] = []
var measurements: Array = []

func _initialize() -> void:
	call_deferred("_run")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); push_error(message)

func _run() -> void:
	var model: RefCounted = Model.new()
	var baseline: Dictionary = {}
	if FileAccess.file_exists("res://tests/source_fingerprints.json"):
		var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/source_fingerprints.json"))
		for entry: Dictionary in reference.cases:
			baseline["%d:%d" % [entry.run_seed,entry.floor]] = entry.sha256
	for seed_value: int in [1,2,3,42,100,104829,386232221,-1234]:
		for floor_number: int in [1,2,5]:
			model.generate(seed_value,floor_number)
			var id: String = "%d:%d" % [seed_value,floor_number]
			expect(model.report.graph_connected,id+" room graph connected")
			expect(model.report.rooms >= 16,id+" keeps original expedition size")
			expect(model.free_samples.size() > 0,id+" conservative clearance layer exists")
			expect(model.can_stand(model.spawn_point()),id+" spawn is free")
			var entries: int = 0
			for room: RoomDef in model.data.level.rooms:
				if room.get_meta("apartment_entry",false): entries += 1
			expect(entries == 1,id+" exactly one entry landing")
			var fingerprint: String = JSON.stringify(model.layout_document(),"",true,true).sha256_text()
			if baseline.has(id): expect(fingerprint == baseline[id],id+" matches production geometry")
			measurements.append({"seed":seed_value,"floor":floor_number,"generation_ms":model.elapsed_ms,
				"validation_ms":model.validation_ms,"issues":model.report.issues,"rooms":model.report.rooms})
			if seed_value in [1,42]:
				model.generate(seed_value,floor_number)
				expect(JSON.stringify(model.layout_document(),"",true,true).sha256_text() == fingerprint,id+" deterministic")
	# Continuous motion must not skip a solid wall even with a long frame.
	model.generate(42,1)
	var start: Vector2 = model.spawn_point()
	var end: Vector2 = model.move_circle(start,start+Vector2(-30,0))
	expect(end.distance_to(start+Vector2(-30,0)) > 1,"long movement cannot tunnel through shaft side")
	expect(model.can_stand(end),"blocked movement leaves a legal endpoint")
	# Circle-to-rectangle corners and open polygon partitions, not only AABB overlap.
	var rectangle: LevelColliderDef = LevelColliderDef.new()
	rectangle.position = start; rectangle.size = Vector2.ONE*2
	model._obstacles.append(rectangle)
	expect(not model.can_stand(start),"solid furniture blocks its interior")
	model._obstacles.clear()
	var wall: LevelColliderDef = LevelColliderDef.new()
	wall.shape_kind = LevelColliderDef.ShapeKind.POLYGON; wall.filled = false; wall.closed = false
	wall.position = start; wall.points = PackedVector2Array([Vector2(-1,-1),Vector2(-1,1),Vector2(1,1)])
	wall.thickness = .1; model._obstacles.append(wall)
	expect(model.can_stand(start,.2),"open partition leaves interior clear")
	expect(not model.can_stand(start+Vector2(-1,0),.2),"open partition blocks real segment")
	model.generate(42,1)
	var path: String = "user://test-layout.json"
	expect(model.export_json("user://missing-export-parent-for-test/layout.json") != OK,"export reports unavailable destination")
	expect(model.export_json(path) == OK,"JSON export succeeds")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	expect(parsed is Dictionary and parsed.rooms.size() == model.report.rooms,"export is valid and complete")
	var extra: LevelColliderDef = LevelColliderDef.new(); extra.shape_kind = LevelColliderDef.ShapeKind.CIRCLE
	extra.radius = 2.25; extra.thickness = .17; extra.closed = false; extra.filled = false; extra.collision_layer = 1024
	model.data.level.rooms[2].colliders.append(extra)
	var exported: Dictionary = model.layout_document().rooms[2].furniture[-1]
	expect(exported.radius == extra.radius and exported.thickness == extra.thickness,"export preserves circle/segment dimensions")
	expect(exported.closed == extra.closed and exported.filled == extra.filled and exported.collision_layer == extra.collision_layer,"export preserves collider topology/layer")
	var result: Dictionary = {"checks":checks,"failures":failures,"maps":measurements,"source_parity_cases":baseline.size()}
	var output: FileAccess = FileAccess.open("res://docs/test_results.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(result,"  ")+"\n"); output.close()
	print("LAB_TESTS: %d checks, %d failures, %d production reference cases" % [checks,failures.size(),baseline.size()])
	quit(0 if failures.is_empty() else 1)
