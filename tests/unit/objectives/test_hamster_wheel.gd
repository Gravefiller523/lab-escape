extends GutTest
## The hamster wheel and the floor task pieces (NEW 2026-11-13, roadmap WP15). Solo: this PC is the host and owns the
## player, so the belt pushes it. Placement on a real floor is covered by the full-run test.

const PLAYER_SCENE: PackedScene = preload("res://systems/player/player.tscn")
const WAIT: float = 8.0
const WHEEL_ID: StringName = &"task_hamster_wheel"

var _world: Node3D
var _body: PlayerCharacter
var _saved_work: float = 0.0


func before_each() -> void:
	Perception.players_invisible = true
	_world = Node3D.new()
	add_child_autofree(_world)
	_add_box(Vector3(0, -0.5, 0), Vector3(40, 1, 40))
	var props := PropSpawner.new()
	props.name = "Props"
	_world.add_child(props)
	_body = PLAYER_SCENE.instantiate() as PlayerCharacter
	_body.player_id = Net.local_player_id()
	_body.name = str(_body.player_id)
	_body.position = Vector3(0, 0.1, 8)
	_world.add_child(_body)
	_body.set_input_override(PlayerInputState.new())
	DamageService.give_components(_body, 100.0)
	_saved_work = _wheel_data().work_seconds
	await wait_physics_frames(3)


func after_each() -> void:
	_wheel_data().work_seconds = _saved_work
	Perception.players_invisible = false
	EventBus.run_ended.emit(&"abandoned")
	await wait_process_frames(2)


func _wheel_data() -> FloorTaskData:
	return ContentRegistry.get_content(WHEEL_ID) as FloorTaskData


func _add_box(center: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	_world.add_child(body)
	return body


## The wheel at the origin, facing -Z: you run towards -Z, the belt carries you towards +Z.
func _wheel() -> HamsterWheelTask:
	var task := Objectives.place_task(WHEEL_ID, Transform3D.IDENTITY) as HamsterWheelTask
	assert_not_null(task, "the wheel is placed")
	return task


func _run(forward: bool) -> void:
	var input := PlayerInputState.new()
	input.move = Vector2(0, 1) if forward else Vector2.ZERO
	_body.set_input_override(input)


func test_the_wheel_is_content() -> void:
	var data: FloorTaskData = _wheel_data()
	assert_not_null(data)
	assert_eq(data.reward, &"loot")
	assert_true(ContentRegistry.get_content(data.reward_loot_id) is LootTableData, "its reward table exists")
	assert_gt(data.work_seconds, 0.0)


func test_standing_on_the_belt_carries_you_off() -> void:
	var wheel: HamsterWheelTask = _wheel()
	_body.teleport(Transform3D(Basis.IDENTITY, Vector3(0, 0.3, -1.0)))
	await wait_physics_frames(5)
	assert_true(wheel.get_node("Belt").call("contains", _body.global_position), "you start on the belt")
	await wait_seconds(2.0)
	assert_false(wheel.get_node("Belt").call("contains", _body.global_position), "doing nothing, it carries you off")
	assert_gt(_body.global_position.z, 1.6, "out of the back")
	assert_lt(wheel.get_progress(), 0.15, "and you didn't fill it")


func test_running_keeps_you_on_and_fills_it() -> void:
	var wheel: HamsterWheelTask = _wheel()
	_body.teleport(Transform3D(Basis.IDENTITY, Vector3(0, 0.3, 0.5)))
	await wait_physics_frames(3)
	_run(true)
	await wait_seconds(2.0)
	assert_true(wheel.get_node("Belt").call("contains", _body.global_position), "running against the front, you stay on the belt")
	var expected: float = 2.0 / _wheel_data().work_seconds
	assert_almost_eq(wheel.get_progress(), expected, expected * 0.4, "about 2 seconds of work done")
	assert_has(wheel.get_participants(), _body.player_id)


func test_a_full_wheel_pays_out_once() -> void:
	_wheel_data().work_seconds = 0.5
	var wheel: HamsterWheelTask = _wheel()
	watch_signals(EventBus)
	var gems_before: int = Props.get_props(&"prop_gem").size() + Props.get_props(&"prop_gem_large").size()
	_body.teleport(Transform3D(Basis.IDENTITY, Vector3(0, 0.3, 0.5)))
	_run(true)
	await wait_until(func() -> bool: return wheel.is_done(), WAIT)
	assert_true(wheel.is_done(), "full")
	assert_signal_emitted_with_parameters(EventBus, "floor_task_completed", [WHEEL_ID])
	await wait_physics_frames(3)
	var gems_after: int = Props.get_props(&"prop_gem").size() + Props.get_props(&"prop_gem_large").size()
	assert_gt(gems_after, gems_before, "it paid out gems")
	var count: int = Props.get_props().size()
	await wait_seconds(0.5)
	assert_eq(Props.get_props().size(), count, "only once")
	assert_eq(wheel.get_node("Sign").get("text"), "WHEEL FULL")


func test_two_runners_fill_it_twice_as_fast() -> void:
	var wheel: HamsterWheelTask = _wheel()
	wheel.add_work([1, 2] as Array[int], 1.0)
	var two: float = wheel.get_progress()
	var other := Objectives.place_task(WHEEL_ID, Transform3D(Basis.IDENTITY, Vector3(20, 0, 0))) as HamsterWheelTask
	other.add_work([1] as Array[int], 1.0)
	assert_almost_eq(two, other.get_progress() * 2.0, 0.0001)
	assert_eq(wheel.get_participants().size(), 2)


func test_a_ghost_doesnt_count() -> void:
	var wheel: HamsterWheelTask = _wheel()
	_body.teleport(Transform3D(Basis.IDENTITY, Vector3(0, 0.3, 0.5)))
	await wait_physics_frames(3)
	_body.set_ghost(true)
	await wait_physics_frames(3)
	assert_eq(wheel.get_runners().size(), 0, "ghosts can't run the wheel")
	_body.set_ghost(false)


func test_more_players_more_tasks_and_room_is_checked() -> void:
	assert_eq(RunDifficulty.floor_task_count(1), Config.game.floor_tasks_base)
	assert_gte(RunDifficulty.floor_task_count(8), RunDifficulty.floor_task_count(4))
	var spot := Node3D.new()
	_world.add_child(spot)
	assert_true(Objectives.has_space(spot, Transform3D(Basis.IDENTITY, Vector3(10, 0, 0))), "open floor: room for it")
	_add_box(Vector3(10, 1.5, 1.0), Vector3(4, 3, 0.3))
	assert_false(Objectives.has_space(spot, Transform3D(Basis.IDENTITY, Vector3(10, 0, 0))), "a wall in the way: no room")


func test_tasks_go_when_the_floor_changes() -> void:
	_wheel()
	assert_eq(Objectives.get_tasks().size(), 1)
	EventBus.floor_loading.emit(99, &"department_zoology")
	await wait_process_frames(2)
	assert_eq(Objectives.get_tasks().size(), 0, "a new floor starts without the old floor's tasks")
