extends GutTest
## level_gen's floor scene with a real generated floor (solo): players start in the lift room, the
## lift part is far away, and the stand-in lift only leaves once the part and everyone are in the lift room.

const FLOOR_SCENE: PackedScene = preload("res://systems/level_gen/level_floor.tscn")


func test_fetch_the_part_then_leave() -> void:
	var floor_node := FLOOR_SCENE.instantiate() as LevelFloor
	add_child_autofree(floor_node)
	await wait_process_frames(2)
	var department: DepartmentData = GameFlow.get_department(GameFlowService.PLACEHOLDER_DEPARTMENT_ID)
	var layout: FloorLayout = LevelGenerator.generate(department, 1, 1, 3, 1)
	Level.build(layout, floor_node)
	EventBus.floor_ready.emit(1, department.id)
	await wait_physics_frames(5)

	var body: PlayerCharacter = PlayerCharacter.find(Net.local_player_id())
	assert_not_null(body, "the player spawned")
	assert_eq(Level.get_room_for_position(body.global_position).room_kind, &"lift", "in the elevator")
	var parts: Array[NetProp] = Props.get_props(department.lift_part_prop_id)
	assert_eq(parts.size(), 1, "one part to fetch")
	assert_ne(Level.get_room_for_position(parts[0].global_position).room_kind, &"lift", "somewhere else")
	assert_string_contains(floor_node.lift_blocker(), "Bring the lift part")

	var lift_at: Vector3 = Level.get_markers(&"lift")[0].global_position
	parts[0].global_position = lift_at + Vector3(0, 1, -2)
	await wait_physics_frames(5)
	assert_eq(floor_node.lift_blocker(), "", "part in, everyone in: the lift can go")

	body.teleport(Transform3D(Basis.IDENTITY, parts[0].global_position + Vector3(0, 0, -20)))
	await wait_physics_frames(5)
	assert_string_contains(floor_node.lift_blocker(), "Waiting for", "not without everyone")
	Level.clear()
